-- =====================================================================
-- K7 · T-65: Çıkış tarihinden sonraki okutma, gün işlenmemişse ya da plansızsa
-- fark edilmiyordu; çalışanın son günü sessizce kayboluyordu
--
-- isten_cikis_gir yalnızca gun_kaydi'na bakıyordu. Gece işi henüz çalışmadıysa ya da
-- o gün plan yoksa gun_kaydi yoktur, ama okutma ham_okutma'da durur.
--
-- Değişiklik:
--   * cikistan_sonraki_okutma(calisan, tarih): çalışanın kartıyla (ya da o anda zimmetli
--     geçici kartla) çıkış gününden sonra yapılmış ilk okutmanın zamanı; yoksa null.
--   * isten_cikis_gir: böyle bir okutma varsa reddeder. Diğer adımlar aynı.
-- Kalıcı test: supabase/tests/cikis_okutma_testi.sql
-- =====================================================================

-- Çıkış gününe ait sayılan okutmalar:
--   * çıkış gününün gece yarısına (İstanbul) kadar olanlar,
--   * o günün vardiyası gece yarısını aşıyorsa vardiya penceresinin sonuna kadar olanlar.
-- Sonraki bir günün vardiya penceresine düşen okutma gece yarısından önce de olsa
-- sonraki güne aittir (ör. 00-08 vardiyasına 23:50'de giriş); çıkış gününün kendi
-- penceresindeyse çıkış gününe sayılır.
-- İptal edilmiş kartın iptalinden sonraki okutması sayılmaz (kartı başkası okutmuş olabilir;
-- o okutma için gece işi iptal_kart_okutma uyarısı verir).
create function pdks.cikistan_sonraki_okutma(p_calisan_id bigint, p_cikis_tarihi date)
returns timestamptz
language sql
stable
set search_path = pdks
as $$
    with gunler as (
        -- İşlenmiş günde gun_kaydi'nın vardiyası (düzeltilmiş olabilir), yoksa plan
        select coalesce(g.is_gunu, vp.tarih) as tarih, coalesce(g.vardiya_id, vp.vardiya_id) as vardiya_id
        from (select * from pdks.vardiya_plani
              where calisan_id = p_calisan_id and ik_onay_durumu <> 'reddedildi'
                and tarih between p_cikis_tarihi and p_cikis_tarihi + 1) vp
        full join (select * from pdks.gun_kaydi
                   where calisan_id = p_calisan_id
                     and is_gunu between p_cikis_tarihi and p_cikis_tarihi + 1) g on g.is_gunu = vp.tarih
    ), pencere as (
        select g.tarih,
               a.p_bas - make_interval(mins => vt.pencere_once_dk) as bas,
               a.p_bit + make_interval(mins => vt.pencere_sonra_dk) as bit
        from gunler g
        join pdks.vardiya_tanim vt on vt.id = g.vardiya_id
        cross join lateral pdks.vardiya_araligi(g.vardiya_id, g.tarih) a
    ), sinir as (
        select ((p_cikis_tarihi + 1)::timestamp at time zone 'Europe/Istanbul') as gun_sonu,
               (select bas from pencere where tarih = p_cikis_tarihi) as son_bas,
               (select bit from pencere where tarih = p_cikis_tarihi) as son_bit,
               (select bas from pencere where tarih = p_cikis_tarihi + 1) as ertesi_bas
    ), kartlar as (
        select kart_no, iptal_zamani from pdks.kart where calisan_id = p_calisan_id
        union all
        select distinct gk.kart_no, null::timestamptz
        from pdks.gecici_kart_zimmet z
        join pdks.gecici_kart gk on gk.id = z.gecici_kart_id
        where z.calisan_id = p_calisan_id
    )
    select min(h.okutma_zamani)
    from sinir s
    cross join kartlar k
    join pdks.ham_okutma h on h.kart_no = k.kart_no
                          and h.okutma_zamani >= least(s.gun_sonu, s.ertesi_bas)
    where (k.iptal_zamani is null or h.okutma_zamani < k.iptal_zamani)
      and not coalesce(h.okutma_zamani between s.son_bas and s.son_bit, false)
      and pdks.okutma_sahibi(h.kart_no, h.okutma_zamani) = p_calisan_id;
$$;

comment on function pdks.cikistan_sonraki_okutma(bigint, date) is
    'Çalışanın çıkış gününden (o günün vardiya penceresi dahil) sonraki ilk okutması; yoksa null.';

revoke execute on function pdks.cikistan_sonraki_okutma(bigint, date) from public, anon, authenticated;

create or replace function pdks.isten_cikis_gir(p_calisan_id bigint, p_cikis_tarihi date, p_aciklama text default null)
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
    v_okutma   timestamptz;
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

    -- İşlenmemiş ya da plansız günün okutması (ham kayıt)
    v_okutma := pdks.cikistan_sonraki_okutma(p_calisan_id, p_cikis_tarihi);
    if v_okutma is not null then
        raise exception 'Çıkış tarihinden sonra kart okutması var (%); çıkış tarihi kontrol edilmelidir.',
            to_char(v_okutma at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI');
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
