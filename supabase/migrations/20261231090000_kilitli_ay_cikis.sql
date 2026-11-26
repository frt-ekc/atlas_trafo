-- =====================================================================
-- K7 · T-67: Çıkış kilitli aya düşerse kilitli ayın vardiya planları siliniyordu
--
-- Sorun: Ahmet 14–18 Eylül planlı; 14, 15 Eylül çalıştı, 16'sından itibaren gelmedi. 21–22 Eylül
-- izni vardı. Eylül kilitlendikten sonra İK çıkışı 15.09 olarak girdi. Gün kayıtları doğru şekilde
-- değişmedi (düzeltmeler Ekim'e fark satırı oldu), ama isten_cikis_gir kilitli Eylül'ün 16–18
-- planlarını sildi ve 21–22 iznini iptal etti. Kilitli ay kendi içinde tutarsız kaldı (planı olmayan
-- "soru bekliyor" gün); canlı puantajda Eylül izinli günü 2'den 0'a indi.
--
-- Karar (Yusuf, A seçeneği): çıkış kilitli ayın planına ve iznine dokunmaz. Yalnızca kilitli olmayan
-- ayların planları silinir, izinleri ve bekleyen fazla mesai talepleri iptal edilir. Gün kayıtları
-- eskisi gibi sonraki aya fark satırı olur. Çıkış kilitli aya düştüyse sonuçta (kilitli_ayda_kalan_plan,
-- kilitli_ayda_kalan_izin, kilitli_ay_uyarisi) ve kalıcı İK uyarısında (cikis_kilitli_ay) söylenir.
-- Bilinçli bedel: kilitli puantajda çıkıştan sonraki izin ve çalışma günleri kalır; İK gerekirse
-- bordroda elle düzeltir (uyarı bunu söyler).
-- Ayrıca kilitli ayın vardiya planı hiçbir yoldan silinemez (vardiya_plani_kilitli_silme).
-- Güncelleme engellenmez: kilitli ayda bekleyen planın reddi önceki planı geri yükler (T-49, T-93).
-- Kalıcı test: supabase/tests/kilitli_ay_cikis_testi.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Yeni uyarı türü
-- ---------------------------------------------------------------------
alter table pdks.uyari drop constraint uyari_tur_check;
alter table pdks.uyari add constraint uyari_tur_check check (tur in (
    'ariza_suphesi', 'cikis_kilitli_ay', 'dosya_gelmedi', 'fm_gunluk_sinir_asildi', 'fm_onay_geri_alindi',
    'fm_onay_yok', 'fm_plansiz_calisma', 'fm_yillik_sinir_asildi', 'fm_yillik_sinir_yaklasti',
    'gece_calisma_siniri_asildi', 'gece_isi_calismadi', 'gecici_kart_cakisma', 'gecici_kart_iade_edilmedi',
    'gecici_kart_zimmetsiz', 'geriye_donuk_vardiya', 'iptal_kart_okutma', 'isg_belgesi_suresi_dolmus',
    'isg_belgesi_suresi_doluyor', 'isg_belgesi_yok', 'izin_gununde_okutma', 'kart_paylasim_suphesi',
    'kendi_okutmasi_yuklendi', 'plansiz_gun_calismasi', 'puantaj_ayari_degisti', 'sik_kart_unutma',
    'soru_eskale', 'yazili_onay_eksik', 'yetkisiz_bolge_okutmasi'));

-- ---------------------------------------------------------------------
-- 2. Kilitli ayın vardiya planı silinemez
-- ---------------------------------------------------------------------
create function pdks.vardiya_plani_kilitli_silme_engelle()
returns trigger
language plpgsql
set search_path = pdks
as $$
begin
    if pdks.donem_kilitli_mi(old.tarih) then
        raise exception 'Kilitli ayın vardiya planı silinemez (%).', to_char(old.tarih, 'DD.MM.YYYY');
    end if;
    return old;
end;
$$;
revoke execute on function pdks.vardiya_plani_kilitli_silme_engelle() from public, anon, authenticated;

create trigger vardiya_plani_kilitli_silme
before delete on pdks.vardiya_plani
for each row execute function pdks.vardiya_plani_kilitli_silme_engelle();

-- ---------------------------------------------------------------------
-- 3. İşten çıkış (son hâli T-32; kilitli ay kayıtları değişmez, uyarı)
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
    -- T-67: çıkıştan sonra kilitli aya düşen kayıtlar değişmez; sayılır ve İK'ya bildirilir
    v_kilitli_gun  integer := 0;
    v_kilitli_plan integer;
    v_kilitli_izin integer;
    v_kilitli_ay   text;
    v_uyari        text;
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
        select g.id, g.is_gunu from pdks.gun_kaydi g
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
        -- Kilitli günün kendisi değişmez; düzeltme sonraki aya fark satırı olur
        if pdks.donem_kilitli_mi(v_gun.is_gunu) then
            v_kilitli_gun := v_kilitli_gun + 1;
        end if;
    end loop;
    v_ozet := v_ozet || jsonb_build_object('vardiya_yok_yapilan_gun', v_n);

    -- Çıkıştan sonraki vardiya planları (T-67: kilitli ayınki kalır; kilitli ay kaydı değişmez)
    select count(*) into v_kilitli_plan
    from pdks.vardiya_plani
    where calisan_id = p_calisan_id and tarih > p_cikis_tarihi and pdks.donem_kilitli_mi(tarih);
    delete from pdks.vardiya_plani
    where calisan_id = p_calisan_id and tarih > p_cikis_tarihi and not pdks.donem_kilitli_mi(tarih);
    get diagnostics v_n = row_count;
    v_ozet := v_ozet || jsonb_build_object('silinen_plan', v_n);

    -- Tamamı çıkıştan sonraya düşen izinler (çıkış gününü kapsayan izin olduğu gibi kalır).
    -- T-67: kilitli ayda başlayan izin kalır (kilitli puantaja girmiştir)
    select count(*) into v_kilitli_izin
    from pdks.izin
    where calisan_id = p_calisan_id and baslangic > p_cikis_tarihi and iptal_zamani is null
      and pdks.donem_kilitli_mi(baslangic);
    update pdks.izin set iptal_zamani = now(), iptal_eden_id = v_ben, iptal_nedeni = v_gerekce
    where calisan_id = p_calisan_id and baslangic > p_cikis_tarihi and iptal_zamani is null
      and not pdks.donem_kilitli_mi(baslangic);
    get diagnostics v_n = row_count;
    v_ozet := v_ozet || jsonb_build_object('iptal_edilen_izin', v_n);

    -- Onay bekleyen fazla mesai talepleri (çıkıştan sonraki günler; kilitli ayda bekleyen talep
    -- kalmaz, kilit kapatır: T-63)
    update pdks.fazla_mesai_plani
    set durum = 'iptal', karar_veren_id = v_ben, karar_aciklama = v_gerekce
    where calisan_id = p_calisan_id and is_gunu > p_cikis_tarihi and durum = 'talep'
      and not pdks.donem_kilitli_mi(is_gunu);
    get diagnostics v_n = row_count;
    v_ozet := v_ozet || jsonb_build_object('iptal_edilen_fm_talebi', v_n);

    -- Bağlı kullanıcı hesabı
    update pdks.kullanici set aktif = false where calisan_id = p_calisan_id and aktif;
    get diagnostics v_n = row_count;
    v_ozet := v_ozet || jsonb_build_object('pasif_yapilan_hesap', v_n);

    -- T-67: çıkış kilitli aya düştüyse İK'ya bildirilir (sonuçta ve kalıcı uyarı olarak)
    v_ozet := v_ozet || jsonb_build_object('kilitli_ayda_kalan_plan', v_kilitli_plan,
                                           'kilitli_ayda_kalan_izin', v_kilitli_izin);
    if v_kilitli_gun + v_kilitli_plan + v_kilitli_izin > 0 then
        select string_agg(to_char(make_date(d.yil, d.ay, 1), 'MM/YYYY'), ', ' order by d.yil, d.ay)
          into v_kilitli_ay
        from pdks.donem d
        where d.durum = 'kilitli' and (make_date(d.yil, d.ay, 1) + interval '1 month')::date > p_cikis_tarihi + 1;
        v_uyari := format('%s %s için işten çıkış (%s) kilitli aya (%s) düşüyor. Kilitli ayın kaydı değişmedi: '
                          || 'çıkıştan sonraki %s vardiya planı ve %s izin kaydı yerinde kaldı; kilitli puantajdaki '
                          || 'izin ve çalışma günleri gerekirse bordroda elle düzeltilmelidir. Çıkıştan sonraki %s gün '
                          || 'kaydının düzeltmesi sonraki aya fark satırı olarak yazıldı.',
                          v_c.ad, v_c.soyad, to_char(p_cikis_tarihi, 'DD.MM.YYYY'), v_kilitli_ay,
                          v_kilitli_plan, v_kilitli_izin, v_kilitli_gun);
        v_ozet := v_ozet || jsonb_build_object('kilitli_ay_uyarisi', v_uyari);
        perform pdks.uyari_yaz('cikis_kilitli_ay', 'cikis:' || p_calisan_id, v_uyari, p_calisan_id);
    end if;

    return v_ozet;
end;
$$;
