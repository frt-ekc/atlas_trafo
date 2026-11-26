-- =====================================================================
-- K2 · T-32: İK kararı, soruyu cevaplayan amirin adını siliyordu
--
-- Sorun: Amir "gelmedi" der (cevaplayan = amir). İK devamsız kararı verince soru_ik_karari
-- cevaplayan_id'ye İK'yı yazıyordu: kayıtta "gelmedi"yi İK söylemiş görünüyor, amirin adı başka
-- hiçbir yerde yok ("gelmedi" günü değiştirmediği için düzeltme satırı da yok). Devamsızlık
-- (çalışan aleyhine) kararının dayanağı gösterilemiyordu. İşten çıkış (isten_cikis_gir) açık
-- soruları kapatırken aynı şeyi yapıyor, İK'nın gerekçesini amirin açıklamasına ekliyordu.
-- Sebep: "yalnızca İK kapatır" (amir_sorusu_kontrol) ve görevler ayrılığı trigger'ı kapatanı
-- cevaplayan_id'den okuyordu.
--
-- Düzeltme:
--   * amir_sorusu'na İK kararı için ik_karar_veren_id ve ik_karar_zamani. soru_ik_karari bunları
--     yazar, cevaplayan_id / cevap / cevap_zamani'na dokunmaz. Sonuç (ik_karari), kararı veren ve
--     zamanı birlikte dolu ya da boş (check).
--   * isten_cikis_gir soruyu T-46'nın kapanış sütunlarıyla kapatır (kapatan_id, kapanis_nedeni
--     "İşten çıkış (GG.AA.YYYY)", kapanis_zamani, onceki_durum); amirin açıklamasına bir şey eklemez.
--   * amir_sorusu_kontrol: İK kararı bekleyen soruyu kapatan ik_karar_veren_id ya da kapatan_id'den
--     okunur, cevaplayan_id'den değil. Görevler ayrılığı ik_karar_veren_id'yi de denetler.
--   * Eski kayıtlar (karar: amirin silinmiş adı geri getirilemez, cevaplayan boş kalır):
--     İK kararı olan soruda İK cevaplayan_id'den ik_karar_veren_id'ye taşınır, cevaplayan_id
--     boşaltılır ("bilinmiyor"). Karar zamanı o sorunun İK düzeltmesinden alınır. İşten çıkışla
--     kapanmış sorular kapanış sütunlarına taşınır; önceki durum cevaptan çıkarılır.
-- Kalıcı test: supabase/tests/ik_karari_cevaplayan_testi.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. İK kararının sütunları
-- ---------------------------------------------------------------------
alter table pdks.amir_sorusu
    add column ik_karar_veren_id bigint references pdks.kullanici (id),
    add column ik_karar_zamani   timestamptz;
comment on column pdks.amir_sorusu.ik_karar_veren_id is
    'İK kararını veren kullanıcı (soru_ik_karari). cevaplayan_id amirin cevabıdır, İK kararıyla değişmez (T-32).';
comment on column pdks.amir_sorusu.ik_karar_zamani is 'İK kararının zamanı (T-32).';
comment on column pdks.amir_sorusu.cevaplayan_id is
    'Soruyu cevaplayan (soru_cevapla). İK kararı ve işten çıkış bunu değiştirmez; T-32 öncesi İK kararlarında boştur (silinmiş, bilinmiyor).';

-- ---------------------------------------------------------------------
-- 2. Eski kayıtlar
-- ---------------------------------------------------------------------
-- 2a. İK kararı verilmiş sorular: cevaplayan_id'deki İK kararı verendir. Amirin adı zaten
--     silinmişti, geri getirilemez; cevaplayan boş kalır (yanlış isim yerine "bilinmiyor").
update pdks.amir_sorusu s
set ik_karar_veren_id = s.cevaplayan_id,
    ik_karar_zamani = coalesce(
        (select min(d.yapilma_zamani) from pdks.duzeltme d where d.soru_id = s.id and d.kaynak = 'ik'),
        s.cevap_zamani, s.olusturma_zamani),
    cevaplayan_id = null
where s.ik_karari is not null and s.ik_karar_veren_id is null;

-- 2b. İşten çıkışla kapanmış sorular: İK cevaplayan_id'de, gerekçe cevap_aciklama'nın sonunda.
--     Kapanış sütunlarına taşınır. Önceki durum kayıtlı değildi: cevaptan çıkarılır.
--     cevap_aciklama'ya eklenmiş gerekçe olduğu gibi kalır (geçmiş metin değiştirilmez).
with cikis as (
    select s.id, d.gerekce, d.yapilma_zamani
    from pdks.amir_sorusu s
    cross join lateral (
        select d.gerekce, d.yapilma_zamani from pdks.duzeltme d
        where d.gun_kaydi_id = s.gun_kaydi_id and d.alan = 'durum' and d.yeni_deger = 'vardiya_yok'
          and d.kaynak = 'ik' and d.yapan_id = s.cevaplayan_id and d.gerekce like 'İşten çıkış (%'
        order by d.id desc limit 1) d
    where s.durum = 'kapandi' and s.ik_karari is null and s.kapanis_nedeni is null
      and s.cevap_aciklama like '%İşten çıkış (%'
      and pdks.kullanici_rolu(s.cevaplayan_id) = 'ik'
)
update pdks.amir_sorusu s
set kapatan_id = s.cevaplayan_id,
    kapanis_nedeni = coalesce(substring(c.gerekce from '^İşten çıkış \(\d\d\.\d\d\.\d{4}\)'), 'İşten çıkış'),
    kapanis_zamani = c.yapilma_zamani,
    onceki_durum = case when s.cevap in ('gelmedi', 'bilmiyorum') then 'ik_karari_bekliyor'
                        when s.eskale_zamani is not null then 'eskale'
                        else 'acik' end,
    cevaplayan_id = null
from cikis c
where c.id = s.id;

alter table pdks.amir_sorusu
    add constraint amir_sorusu_ik_karari_tam check (
        (ik_karari is null) = (ik_karar_veren_id is null)
        and (ik_karari is null) = (ik_karar_zamani is null));

-- ---------------------------------------------------------------------
-- 3. Görevler ayrılığı: İK kendi kaydındaki soruya karar veremez (önce cevaplayan_id korurdu)
-- ---------------------------------------------------------------------
drop trigger amir_sorusu_gorev_ayriligi on pdks.amir_sorusu;
create trigger amir_sorusu_gorev_ayriligi before insert or update on pdks.amir_sorusu
    for each row execute function pdks.kendi_kaydi_engelle('gun_kaydi', 'atanan_id', 'eskale_edilen_id', 'cevaplayan_id', 'kapatan_id', 'ik_karar_veren_id');

-- ---------------------------------------------------------------------
-- 4. "Yalnızca İK kapatır": kapatan, kararı veren ya da kapatan sütunundan okunur
-- ---------------------------------------------------------------------
create or replace function pdks.amir_sorusu_kontrol()
returns trigger
language plpgsql
set search_path = pdks
as $$
begin
    if new.cevap is not null and old.cevap is null then
        new.cevap_zamani := now();
        if new.cevap = 'gelmedi' and pdks.kullanici_rolu(new.cevaplayan_id) is distinct from 'ik' then
            new.durum := 'ik_karari_bekliyor';
        end if;
    end if;
    -- T-32: cevaplayan amirdir; kapatan İK kararında ik_karar_veren_id, başka işlemde kapatan_id
    if new.durum = 'kapandi' and old.durum = 'ik_karari_bekliyor'
       and pdks.kullanici_rolu(coalesce(new.ik_karar_veren_id, new.kapatan_id)) is distinct from 'ik' then
        raise exception 'Bu soruyu yalnızca İK kapatabilir.';
    end if;
    return new;
end;
$$;

-- ---------------------------------------------------------------------
-- 5. İK kararı amirin cevabına dokunmaz
-- ---------------------------------------------------------------------
create or replace function pdks.soru_ik_karari(p_soru_id bigint, p_devamsiz boolean, p_gerekce text, p_giris timestamptz default null, p_cikis timestamptz default null)
returns void
language plpgsql
security definer
set search_path = pdks
as $$
declare
    v_ben   bigint := pdks.yetki_gerekli('ik');
    v_soru  pdks.amir_sorusu;
begin
    select * into v_soru from pdks.amir_sorusu where id = p_soru_id for update;
    -- Son karar İK'dadır (T-39): soru amirde, üst amirde ya da İK'da beklerken İK karar verebilir
    if not found or v_soru.durum not in ('acik', 'eskale', 'ik_karari_bekliyor') then
        raise exception 'İK kararı bekleyen soru bulunamadı.';
    end if;
    if not p_devamsiz and p_giris is null and p_cikis is null then
        raise exception 'Devamsız değilse giriş ya da çıkış saatini girin.';
    end if;

    if p_devamsiz then
        perform pdks.devamsiz_izin_denetle(v_soru.gun_kaydi_id);
    end if;

    -- T-32: amirin cevabı (cevaplayan, cevap, zamanı) olduğu gibi kalır; İK'nın kararı ayrı sütunlarda
    update pdks.amir_sorusu
    set durum = 'kapandi', ik_karar_veren_id = v_ben, ik_karar_zamani = now(),
        -- Yalnızca sonuç: gerekçe, amirin okuyamadığı duzeltme satırındadır (T-106)
        ik_karari = case when p_devamsiz then 'devamsiz' else 'geldi' end
    where id = p_soru_id;

    if p_devamsiz then
        perform pdks.duzeltme_uygula(v_soru.gun_kaydi_id, 'durum', 'devamsiz', p_gerekce, 'ik', v_ben,
                                     p_soru_id => p_soru_id, p_aleyhine => true);
    else
        perform pdks.saat_yaz(v_soru.gun_kaydi_id, p_giris, p_cikis, p_gerekce, 'ik', v_ben, p_soru_id => p_soru_id);
    end if;

    -- Değişen gün hemen hesaplanır (kilitli ayda yapılmaz; düzeltme orada fark satırı olur)
    perform pdks.gun_hesapla(v_soru.gun_kaydi_id);
end;
$$;

-- ---------------------------------------------------------------------
-- 6. İşten çıkış soruyu kapanış sütunlarıyla kapatır
-- ---------------------------------------------------------------------
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
        -- T-32: amirin cevabına (cevaplayan, cevap, açıklama) dokunulmaz; kapatan ve nedeni ayrı yazılır.
        -- Nedende yalnızca tarih var: İK'nın açıklaması (ör. istifa) amirin okuyamadığı düzeltme gerekçesinde.
        update pdks.amir_sorusu
        set durum = 'kapandi', kapatan_id = v_ben, kapanis_zamani = now(), onceki_durum = durum,
            kapanis_nedeni = 'İşten çıkış (' || to_char(p_cikis_tarihi, 'DD.MM.YYYY') || ')'
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
