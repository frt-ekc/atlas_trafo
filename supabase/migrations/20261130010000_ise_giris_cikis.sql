-- =====================================================================
-- İşe giriş ve işten çıkış (yalnızca İK)
--
-- Önceden çalışanlar yalnızca örnek veriyle (seed) giriyordu; ekleyen ya da
-- işten çıkaran bir fonksiyon yoktu. Bu dosya:
--   1. Gece işinin gün kaydı adımı çalışanı "aktif" alanına göre değil,
--      işe giriş ve işten çıkış TARİHİNE göre süzer. Böylece çıkış girildikten
--      sonra da son günler (çıkış günü dahil) ertesi sabah işlenir; işe giriş
--      tarihinden önceki planlar işlenmez.
--   2. pdks.calisan_ekle(...)      : yeni çalışan (ileri tarihli giriş olabilir)
--   3. pdks.isten_cikis_gir(...)   : çıkış tarihi, kartlar, planlar, izinler,
--      fazla mesai talepleri, hesap ve çıkıştan sonra işlenmiş günler
-- Departman değiştirme bilerek yok: departmanın geçmişi tutulmadığı için
-- geçmiş günler yeni departmana kayardı (amir görünürlüğü, departman özeti).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Gece işi: çalışan tarihe göre süzülür (yalnızca "join calisan" satırı değişti)
-- ---------------------------------------------------------------------
create or replace function pdks.gece_isi_gun_kayitlari(p_gun date, p_gece_isi_id bigint)
returns integer
language plpgsql
set search_path = pdks
as $$
declare
    v_n integer;
begin
    with plan as (
        select vp.calisan_id, vp.vardiya_id, vt.pencere_once_dk, vt.pencere_sonra_dk,
               (p_gun + vt.baslangic) at time zone 'Europe/Istanbul' as bas,
               (p_gun + case when vt.gece_yarisini_asar then 1 else 0 end + vt.bitis) at time zone 'Europe/Istanbul' as bit
        from pdks.vardiya_plani vp
        join pdks.vardiya_tanim vt on vt.id = vp.vardiya_id
        -- O gün işte miydi? (aktif alanı çıkış girilince hemen false olur; tarih son günü de kapsar)
        join pdks.calisan c on c.id = vp.calisan_id
                           and p_gun >= c.ise_giris_tarihi
                           and (c.isten_cikis_tarihi is null or p_gun <= c.isten_cikis_tarihi)
        where vp.tarih = p_gun
          and not exists (select 1 from pdks.gun_kaydi g where g.calisan_id = vp.calisan_id and g.is_gunu = p_gun)
    ), tam as (
        select p.* from plan p
        where pdks.pdks_verisi_tam_mi(p.bas - make_interval(mins => p.pencere_once_dk),
                                      p.bit + make_interval(mins => p.pencere_sonra_dk))
    ), okut as (
        select p.calisan_id,
               min(h.okutma_zamani) filter (where h.yon is distinct from 'cikis') as giris,
               max(h.okutma_zamani) filter (where h.yon is distinct from 'giris') as cikis
        from tam p
        join pdks.ham_okutma h
          on h.okutma_zamani between p.bas - make_interval(mins => p.pencere_once_dk)
                                 and p.bit + make_interval(mins => p.pencere_sonra_dk)
        where pdks.okutma_sahibi(h.kart_no, h.okutma_zamani) = p.calisan_id
          and not pdks.okutma_gecersiz_mi(h.id)
        group by p.calisan_id
    ), durumlu as (
        select t.calisan_id, t.vardiya_id, t.bas, t.bit, o.giris,
               case when o.giris is null or o.cikis > o.giris then o.cikis end as cikis,
               (select i.tur from pdks.izin i
                where i.calisan_id = t.calisan_id and p_gun between i.baslangic and i.bitis
                  and i.iptal_zamani is null
                order by i.id limit 1) as izin_turu,
               -- Resmi tatil yalnızca hiç okutma yoksa "tatil"dir; okutma varsa çalışılmış gün işlenir
               exists (select 1 from pdks.resmi_tatil r where r.tarih = p_gun and not r.yarim_gun)
                   and o.giris is null and o.cikis is null as tatil
        from tam t
        left join okut o on o.calisan_id = t.calisan_id
    )
    insert into pdks.gun_kaydi (calisan_id, is_gunu, vardiya_id, planli_baslangic, planli_bitis,
                                giris_zamani, cikis_zamani, giris_kaynagi, cikis_kaynagi,
                                durum, hesap_tamam, gece_isi_id)
    select d.calisan_id, p_gun, d.vardiya_id, d.bas, d.bit,
           d.giris, d.cikis,
           case when d.giris is not null then 'pdks' end,
           case when d.cikis is not null then 'pdks' end,
           case when d.izin_turu = 'rapor' then 'raporlu'
                when d.izin_turu is not null then 'izinli'
                when d.tatil then 'tatil'
                when d.giris is not null and d.cikis is not null then 'tamam'
                else 'eksik' end,
           (d.izin_turu is not null or d.tatil),
           p_gece_isi_id
    from durumlu d;
    get diagnostics v_n = row_count;
    return v_n;
end;
$$;

-- ---------------------------------------------------------------------
-- 2. Yeni çalışan (yalnızca İK)
-- ---------------------------------------------------------------------
create function pdks.calisan_ekle(p_sicil_no text, p_ad text, p_soyad text,
                                  p_departman_id smallint, p_ise_giris_tarihi date)
returns bigint
language plpgsql
security definer
set search_path = pdks
as $$
declare
    v_eski  pdks.calisan;
    v_id    bigint;
begin
    perform pdks.yetki_gerekli('ik');

    if coalesce(trim(p_sicil_no), '') = '' or coalesce(trim(p_ad), '') = '' or coalesce(trim(p_soyad), '') = '' then
        raise exception 'Sicil numarası, ad ve soyad boş olamaz.';
    end if;
    if p_ise_giris_tarihi is null then
        raise exception 'İşe giriş tarihi girilmeli.';
    end if;
    if not exists (select 1 from pdks.departman where id = p_departman_id) then
        raise exception 'Departman bulunamadı.';
    end if;

    select * into v_eski from pdks.calisan where sicil_no = trim(p_sicil_no);
    if found then
        if v_eski.isten_cikis_tarihi is not null or not v_eski.aktif then
            raise exception 'Bu sicil işten ayrılmış bir çalışana ait; yeniden işe giriş desteklenmiyor.';
        end if;
        raise exception 'Bu sicil numarası başka bir çalışanda kayıtlı: % %.', v_eski.ad, v_eski.soyad;
    end if;

    insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
    values (trim(p_sicil_no), trim(p_ad), trim(p_soyad), p_departman_id, p_ise_giris_tarihi)
    returning id into v_id;
    return v_id;
end;
$$;

-- ---------------------------------------------------------------------
-- 3. İşten çıkış (yalnızca İK; kimse kendi çıkışını giremez)
--    Çıkış tarihi son çalışma günüdür ve ileri olamaz. Dönen özet ekranda gösterilir.
-- ---------------------------------------------------------------------
create function pdks.isten_cikis_gir(p_calisan_id bigint, p_cikis_tarihi date, p_aciklama text default null)
returns jsonb
language plpgsql
security definer
set search_path = pdks
as $$
declare
    v_ben      bigint := pdks.yetki_gerekli('ik');
    v_bugun    date := (now() at time zone 'Europe/Istanbul')::date;
    v_c        pdks.calisan;
    v_gerekce  text;
    v_gun      record;
    v_zimmet   record;
    v_n        integer;
    v_ozet     jsonb := '{}'::jsonb;
begin
    select * into v_c from pdks.calisan where id = p_calisan_id for update;
    if not found then
        raise exception 'Çalışan bulunamadı.';
    end if;
    if pdks.kullanici_calisani(v_ben) = p_calisan_id then
        raise exception 'Görevler ayrılığı: kimse kendi kaydında işlem yapamaz (calisan.isten_cikis).';
    end if;
    if v_c.isten_cikis_tarihi is not null or not v_c.aktif then
        raise exception 'Bu çalışanın işten çıkışı zaten girilmiş.';
    end if;
    if p_cikis_tarihi is null then
        raise exception 'Çıkış tarihi girilmeli.';
    end if;
    if p_cikis_tarihi < v_c.ise_giris_tarihi then
        raise exception 'Çıkış tarihi işe giriş tarihinden (%) önce olamaz.', to_char(v_c.ise_giris_tarihi, 'DD.MM.YYYY');
    end if;
    if p_cikis_tarihi > v_bugun then
        raise exception 'Çıkış tarihi ileri olamaz; son çalışma günü ya da sonrasında girin.';
    end if;

    -- Açık geçici kart zimmeti: önce kart iade alınmalı
    select gk.kart_no, z.verilis_zamani into v_zimmet
    from pdks.gecici_kart_zimmet z join pdks.gecici_kart gk on gk.id = z.gecici_kart_id
    where z.calisan_id = p_calisan_id and z.iade_zamani is null
    limit 1;
    if found then
        raise exception 'Çalışanda iade edilmemiş geçici kart var (%, % tarihinde verildi); önce iade alın.',
            v_zimmet.kart_no, to_char(v_zimmet.verilis_zamani at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI');
    end if;

    -- Çıkıştan sonra okutması olan gün varsa çıkış tarihi yanlıştır
    select g.is_gunu into v_gun
    from pdks.gun_kaydi g
    where g.calisan_id = p_calisan_id and g.is_gunu > p_cikis_tarihi
      and (g.giris_zamani is not null or g.cikis_zamani is not null)
    order by g.is_gunu
    limit 1;
    if found then
        raise exception 'Çıkış tarihinden sonra çalışılmış gün var (%); çıkış tarihini kontrol edin.',
            to_char(v_gun.is_gunu, 'DD.MM.YYYY');
    end if;

    v_gerekce := 'İşten çıkış (' || to_char(p_cikis_tarihi, 'DD.MM.YYYY') || ')'
                 || coalesce(': ' || nullif(trim(p_aciklama), ''), '');

    -- Çalışan kaydı
    update pdks.calisan set isten_cikis_tarihi = p_cikis_tarihi, aktif = false where id = p_calisan_id;

    -- Kartlar (okutma sahibi kart iptalinden etkilenmez; son günün okutmaları yine çalışana yazılır)
    update pdks.kart set durum = 'iptal', iptal_nedeni = 'isten_cikis', iptal_zamani = now(), iptal_eden_id = v_ben
    where calisan_id = p_calisan_id and durum = 'aktif';
    get diagnostics v_n = row_count;
    v_ozet := v_ozet || jsonb_build_object('iptal_edilen_kart', v_n);

    -- Çıkıştan sonra işlenmiş günler (çıkış geç girildiyse): "vardiya yok" olur, açık soruları kapanır
    v_n := 0;
    for v_gun in
        select g.id from pdks.gun_kaydi g
        where g.calisan_id = p_calisan_id and g.is_gunu > p_cikis_tarihi and g.durum <> 'vardiya_yok'
        order by g.is_gunu
    loop
        update pdks.amir_sorusu
        set durum = 'kapandi', cevaplayan_id = v_ben,
            cevap_aciklama = concat_ws(' | ', cevap_aciklama, v_gerekce)
        where gun_kaydi_id = v_gun.id and durum in ('acik', 'eskale', 'ik_karari_bekliyor');
        perform pdks.duzeltme_uygula(v_gun.id, 'durum', 'vardiya_yok', v_gerekce, 'ik', v_ben);
        v_n := v_n + 1;
    end loop;
    v_ozet := v_ozet || jsonb_build_object('vardiya_yok_yapilan_gun', v_n);

    -- Çıkıştan sonraki vardiya planları
    delete from pdks.vardiya_plani where calisan_id = p_calisan_id and tarih > p_cikis_tarihi;
    get diagnostics v_n = row_count;
    v_ozet := v_ozet || jsonb_build_object('silinen_plan', v_n);

    -- Tamamı çıkıştan sonraya düşen izinler (çıkış gününü kapsayan izin olduğu gibi kalır)
    update pdks.izin set iptal_zamani = now(), iptal_eden_id = v_ben, iptal_nedeni = v_gerekce
    where calisan_id = p_calisan_id and baslangic > p_cikis_tarihi and iptal_zamani is null;
    get diagnostics v_n = row_count;
    v_ozet := v_ozet || jsonb_build_object('iptal_edilen_izin', v_n);

    -- Onay bekleyen fazla mesai talepleri (çıkıştan sonraki günler)
    update pdks.fazla_mesai_plani
    set durum = 'iptal', karar_veren_id = v_ben, karar_aciklama = v_gerekce
    where calisan_id = p_calisan_id and is_gunu > p_cikis_tarihi and durum = 'talep';
    get diagnostics v_n = row_count;
    v_ozet := v_ozet || jsonb_build_object('iptal_edilen_fm_talebi', v_n);

    -- Bağlı kullanıcı hesabı
    update pdks.kullanici set aktif = false where calisan_id = p_calisan_id and aktif;
    get diagnostics v_n = row_count;
    v_ozet := v_ozet || jsonb_build_object('pasif_yapilan_hesap', v_n);

    return v_ozet;
end;
$$;

revoke execute on function pdks.calisan_ekle(text, text, text, smallint, date),
                           pdks.isten_cikis_gir(bigint, date, text)
       from public, anon;
grant execute on function pdks.calisan_ekle(text, text, text, smallint, date),
                          pdks.isten_cikis_gir(bigint, date, text)
      to authenticated;
