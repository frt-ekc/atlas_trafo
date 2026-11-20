-- =====================================================================
-- Ay kilidi ve günün hemen hesaplanması testleri (20261201010000_ay_kilidi_ve_aninda_hesap.sql)
--   A) Testin kendi sahte verisi (Eylül ve Ekim 2026): her kural tek tek
--      (20261201020000_kilit_ozeti.sql: onay bekleyen geriye dönük plan ve kilit özeti dahil)
--   B) Örnek veri yüklüyse uçtan uca: Kasım gece işi → sorular → İK kararları → kilit →
--      puantaj ve ERP satırları → kilitten sonra itiraz kabulü → Aralık'ta fark satırı
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/ay_kilidi_testi.sql
-- =====================================================================
\pset tuples_only on
\pset format unaligned
begin;
set local timezone = 'Europe/Istanbul';

create schema test;
create function test.dogrula(p_ad text, p_kosul boolean) returns void language plpgsql as $$
begin
    if p_kosul is not true then raise exception 'KALDI  %', p_ad; end if;
    raise notice 'GEÇTİ  %', p_ad;
end $$;
-- Hata bekler; mesaj verilen kalıbı içermeli
create function test.hata(p_ad text, p_kalip text, p_sql text) returns void language plpgsql as $$
begin
    begin
        execute p_sql;
    exception when others then
        if sqlerrm not like '%' || p_kalip || '%' then
            raise exception 'KALDI  %: beklenmeyen hata: %', p_ad, sqlerrm;
        end if;
        raise notice 'GEÇTİ  %  (%)', p_ad, sqlerrm;
        return;
    end;
    raise exception 'KALDI  %: hata bekleniyordu ama komut çalıştı', p_ad;
end $$;
create function test.oturum(p_eposta text) returns void language sql security definer as $$
    select set_config('request.jwt.claims',
        json_build_object('sub', (select auth_kullanici_id from pdks.kullanici where eposta = p_eposta),
                          'role', 'authenticated')::text, true);
$$;
create function test.c(p text) returns bigint language sql security definer as $$
    select id from pdks.calisan where sicil_no = p $$;
create function test.k(p text) returns bigint language sql security definer as $$
    select id from pdks.kullanici where eposta = p $$;
create function test.gk(p_sicil text, p_gun date) returns pdks.gun_kaydi language sql security definer as $$
    select * from pdks.gun_kaydi where calisan_id = test.c(p_sicil) and is_gunu = p_gun $$;
create function test.soru(p_sicil text, p_gun date) returns pdks.amir_sorusu language sql security definer as $$
    select * from pdks.amir_sorusu where gun_kaydi_id = (test.gk(p_sicil, p_gun)).id $$;
create function test.ts(p text) returns timestamptz language sql immutable as $$
    select (p::timestamp) at time zone 'Europe/Istanbul' $$;
-- Kilitli ayın ERP satırlarından bir çalışanın bir koddaki gün sayısı (normal satır)
create function test.kod_gun(p_donem text, p_sicil text, p_kod text) returns numeric language sql security definer as $$
    select coalesce(sum(gun), 0) from pdks.v_puantaj_aktarim
    where donem = p_donem and sicil = p_sicil and kod = p_kod and satir_turu = 'normal' $$;
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

-- =====================================================================
-- A) Testin kendi verisi (Ekim 2026)
-- =====================================================================
--   AKA1: AK Üretim'in amiri (üst amiri yok) · AK01–AK03, AK05: AK Üretim · AK06: 20 Ekim'de işe girdi
--   AKI1 / AKI2: İK (AK İdari, amiri yok)
insert into pdks.departman (ad) values ('AK Üretim'), ('AK İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = d), t::date
from (values ('AKA1', 'AK Üretim', '2025-01-01'), ('AK01', 'AK Üretim', '2025-01-01'), ('AK02', 'AK Üretim', '2025-01-01'),
             ('AK03', 'AK Üretim', '2025-01-01'), ('AK05', 'AK Üretim', '2025-01-01'), ('AK06', 'AK Üretim', '2026-10-20'),
             ('AKI1', 'AK İdari', '2025-01-01'), ('AKI2', 'AK İdari', '2025-01-01')) v(s, d, t);
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('AK İK 1', 'ak_ik1@ornek.test', 'ik',   test.c('AKI1'), '00000000-0000-0000-0000-0000000000a1'),
    ('AK İK 2', 'ak_ik2@ornek.test', 'ik',   test.c('AKI2'), '00000000-0000-0000-0000-0000000000a2'),
    ('AK Amir', 'ak_amir@ornek.test', 'amir', test.c('AKA1'), '00000000-0000-0000-0000-0000000000a3');
update pdks.departman set amir_id = test.k('ak_amir@ornek.test') where ad = 'AK Üretim';
insert into pdks.kart (kart_no, calisan_id)
select 'AK-' || s, test.c(s) from unnest(array['AKA1', 'AK01', 'AK02', 'AK03', 'AK05', 'AK06', 'AKI1', 'AKI2']) s;
insert into pdks.okuyucu (kod, ad, sistem) values ('AK-PDKS', 'AK PDKS', 'pdks');
insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id, giren_id)
select test.c(s), g::date, (select id from pdks.vardiya_tanim where kod = 'GUNDUZ_8'), test.k('ak_ik2@ornek.test')
from (values ('AK01', '2026-10-05'), ('AK01', '2026-10-06'), ('AK02', '2026-10-06'), ('AK03', '2026-10-06'),
             ('AK05', '2026-10-06'), ('AKA1', '2026-10-06'), ('AKI1', '2026-10-06')) v(s, g);
insert into pdks.aktarim (kaynak, dosya_adi, dosya_ozeti, veri_tarihi)
select 'pdks', 'ak_' || g || '.csv', 'ak-pdks-' || g, g::date from unnest(array['2026-10-05', '2026-10-06']) g;
-- AK01 iki gün normal · AK02 girişi yok · AK03 çıkışı yok · AK05, AKA1, AKI1 hiç okutmadı
insert into pdks.ham_okutma (aktarim_id, okuyucu_id, kart_no, okutma_zamani, yon)
select (select id from pdks.aktarim where dosya_ozeti = 'ak-pdks-' || (z::timestamp)::date),
       (select id from pdks.okuyucu where kod = 'AK-PDKS'), k, test.ts(z), y
from (values ('AK-AK01', '2026-10-05 07:55', 'giris'), ('AK-AK01', '2026-10-05 16:04', 'cikis'),
             ('AK-AK01', '2026-10-06 07:54', 'giris'), ('AK-AK01', '2026-10-06 16:03', 'cikis'),
             ('AK-AK02', '2026-10-06 16:02', 'cikis'),
             ('AK-AK03', '2026-10-06 07:52', 'giris')) v(k, z, y);
select pdks.gece_isi_calistir('2026-10-05');
select pdks.gece_isi_calistir('2026-10-06');

select test.dogrula('hazırlık: 6 Ekim''de beş soru açıldı (giriş yok, çıkış yok, üç hiç kayıt yok)',
    (select count(*) from pdks.amir_sorusu q join pdks.gun_kaydi g on g.id = q.gun_kaydi_id
     where g.is_gunu = '2026-10-06' and q.durum = 'acik') = 5);
select test.dogrula('hazırlık: amirin kendi günü (üst amiri yok) doğrudan İK''ya atandı',
    pdks.kullanici_rolu((test.soru('AKA1', '2026-10-06')).atanan_id) = 'ik');

-- ---------------------------------------------------------------------
-- 4) Cevap ve düzeltme günü hemen hesaplar (gece işini beklemez)
-- ---------------------------------------------------------------------
set local role authenticated;
select test.oturum('ak_amir@ornek.test');
select pdks.soru_cevapla((test.soru('AK02', '2026-10-06')).id, 'geldi_saat_farkli', p_giris => '2026-10-06 08:00+03');
select test.dogrula('amir cevabından hemen sonra gün hesaplandı (AK02: tamam, 420 dk)',
    (select hesap_tamam and durum = 'tamam' and calisma_dk = 420 and gec_kalma_dk = 0 from test.gk('AK02', '2026-10-06')));
select pdks.soru_cevapla((test.soru('AK03', '2026-10-06')).id, 'bilmiyorum');
select test.dogrula('"bilmiyorum" cevabında gün hesaplanmaz, İK kararına gider (AK03)',
    (select not hesap_tamam from test.gk('AK03', '2026-10-06'))
    and (test.soru('AK03', '2026-10-06')).durum = 'ik_karari_bekliyor');
select test.oturum('ak_ik1@ornek.test');
select pdks.soru_ik_karari((test.soru('AK03', '2026-10-06')).id, false, 'Vardiya sonuna kadar çalıştı', null, '2026-10-06 16:00+03');
select test.dogrula('İK kararından hemen sonra gün hesaplandı (AK03: tamam, 420 dk)',
    (select hesap_tamam and durum = 'tamam' and calisma_dk = 420 from test.gk('AK03', '2026-10-06')));
select pdks.kayit_duzelt((test.gk('AK01', '2026-10-06')).id, 'giris_zamani', '2026-10-06 08:30+03', 'Belge: 08:30 girişi');
select test.dogrula('İK kayıt düzeltmesinden hemen sonra gün yeniden hesaplandı (AK01: 30 dk geç, mola 30, 420 dk)',
    (select hesap_tamam and gec_kalma_dk = 30 and mola_dk = 30 and calisma_dk = 420 from test.gk('AK01', '2026-10-06')));

-- ---------------------------------------------------------------------
-- 3) İK, İK'ya atanmış ya da eskale edilmiş soruyu kapatabilir; görevler ayrılığı korunur
-- ---------------------------------------------------------------------
select test.oturum('ak_ik2@ornek.test');
select test.hata('soru_cevapla İK''ya açık değil (amir rolü ister)', 'yetkiniz yok',
    $$select pdks.soru_cevapla((test.soru('AKA1', '2026-10-06')).id, 'geldi_saat_dogru')$$);
select pdks.soru_ik_karari((test.soru('AKA1', '2026-10-06')).id, false, 'Toplantıdaydı, giriş 08:00',
                           '2026-10-06 08:00+03', '2026-10-06 16:00+03');
select test.dogrula('İK''ya doğrudan atanmış soru (amirin kendi günü) İK kararıyla kapandı ve gün hesaplandı',
    (test.soru('AKA1', '2026-10-06')).durum = 'kapandi'
    and (select hesap_tamam and durum = 'tamam' from test.gk('AKA1', '2026-10-06')));
reset role;
-- AK05'in sorusu süresinde cevaplanmadı: amirin üst amiri yok → İK'ya eskale
select pdks.gece_isi_eskale(current_date + 10);
select test.dogrula('üst amiri olmayan amirin sorusu İK''ya eskale edildi',
    (select durum = 'eskale' and pdks.kullanici_rolu(eskale_edilen_id) = 'ik' from test.soru('AK05', '2026-10-06')));
set local role authenticated;
select test.oturum('ak_ik1@ornek.test');
select test.hata('İK kendi günündeki soruya karar veremez (görevler ayrılığı)', 'Görevler ayrılığı',
    $$select pdks.soru_ik_karari((test.soru('AKI1', '2026-10-06')).id, false, 'Geldi', '2026-10-06 08:00+03', '2026-10-06 16:00+03')$$);
select pdks.soru_ik_karari((test.soru('AK05', '2026-10-06')).id, true, 'Haber vermeden gelmedi');
select test.dogrula('İK''ya eskale edilmiş soru İK kararıyla kapandı (AK05 devamsız)',
    (test.soru('AK05', '2026-10-06')).durum = 'kapandi' and (test.gk('AK05', '2026-10-06')).durum = 'devamsiz');
select test.oturum('ak_ik2@ornek.test');
select pdks.soru_ik_karari((test.soru('AKI1', '2026-10-06')).id, false, 'Eğitimdeydi', '2026-10-06 08:00+03', '2026-10-06 16:00+03');
select test.dogrula('başka İK, İK''nın kendi günündeki soruyu kapattı',
    (test.soru('AKI1', '2026-10-06')).durum = 'kapandi');
select test.hata('kapanmış soruya ikinci kez karar verilemez', 'İK kararı bekleyen soru bulunamadı',
    $$select pdks.soru_ik_karari((test.soru('AKI1', '2026-10-06')).id, true, 'Deneme')$$);
reset role;

-- ---------------------------------------------------------------------
-- Saatlik izin: izinli günde mola. saatlik_izin_gir günü gun_hesabini_yenile ile yeniden hesaplar;
-- sonuç gun_hesapla'nın kullandığı gun_hesabi ile aynı olmalı (iki yol aynı hesabı verir)
-- ---------------------------------------------------------------------
set local role authenticated;
select test.oturum('ak_ik1@ornek.test');
select pdks.saatlik_izin_gir(test.c('AKA1'), '2026-10-06', '2026-10-06 12:00+03', '2026-10-06 15:00+03', 'mazeret');
reset role;
select test.dogrula('saatlik izinli günde mola 60''tan 30''a indi (AKA1: 3 saat izin, 270 dk çalışma)',
    (select mola_dk = 30 and saatlik_izin_dk = 180 and calisma_dk = 270 and hesap_tamam from test.gk('AKA1', '2026-10-06')));
select test.dogrula('saatlik izin sonrası yeniden hesap gun_hesabi ile aynı (gun_hesapla da bunu yazar)',
    (select (g.calisma_dk, g.mola_dk, g.saatlik_izin_dk, g.gec_kalma_dk, g.erken_cikis_dk)
            = (h.calisma_dk, h.mola_dk, h.saatlik_izin_dk, h.gec_kalma_dk, h.erken_cikis_dk)
     from pdks.gun_kaydi g
     cross join lateral pdks.gun_hesabi(g.calisan_id, g.is_gunu, g.planli_baslangic, g.planli_bitis,
                                        g.giris_zamani, g.cikis_zamani, g.vardiya_id) h
     where g.id = (test.gk('AKA1', '2026-10-06')).id));

-- ---------------------------------------------------------------------
-- 5) Eylül: onay bekleyen geriye dönük plan kilidi durdurur; zorla kilit özeti
--    AK02 7 Eylül: hiç kayıt yok (açık soru) · AK03 8 Eylül: gün normal işlendi, sonra amir aynı güne
--    geriye dönük plan girdi (İK onayı bekliyor); aynı güne açık itiraz
-- ---------------------------------------------------------------------
insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id, giren_id, geriye_donuk, ik_onay_durumu)
values (test.c('AK02'), '2026-09-07', (select id from pdks.vardiya_tanim where kod = 'GUNDUZ_8'), test.k('ak_ik2@ornek.test'), false, 'gerekmez'),
       (test.c('AK03'), '2026-09-08', (select id from pdks.vardiya_tanim where kod = 'GUNDUZ_8'), test.k('ak_ik2@ornek.test'), false, 'gerekmez');
insert into pdks.aktarim (kaynak, dosya_adi, dosya_ozeti, veri_tarihi)
select 'pdks', 'ak_' || g || '.csv', 'ak-pdks-' || g, g::date from unnest(array['2026-09-07', '2026-09-08']) g;
insert into pdks.ham_okutma (aktarim_id, okuyucu_id, kart_no, okutma_zamani, yon)
select (select id from pdks.aktarim where dosya_ozeti = 'ak-pdks-2026-09-08'), (select id from pdks.okuyucu where kod = 'AK-PDKS'),
       'AK-AK03', test.ts(z), y
from (values ('2026-09-08 07:55', 'giris'), ('2026-09-08 16:04', 'cikis')) v(z, y);
select pdks.gece_isi_calistir('2026-09-07');
select pdks.gece_isi_calistir('2026-09-08');
insert into pdks.itiraz (calisan_id, gun_kaydi_id, metin)
values (test.c('AK03'), (test.gk('AK03', '2026-09-08')).id, 'Vardiya değişikliği bana sorulmadı');
set local role authenticated;
select test.oturum('ak_amir@ornek.test');
select pdks.vardiya_plani_gir(test.c('AK03'), '2026-09-08', (select id from pdks.vardiya_tanim where kod = 'GUNDUZ_8'), 'Geriye dönük düzeltme');
reset role;
set local role authenticated;
select test.oturum('ak_ik1@ornek.test');
select test.hata('onay bekleyen geriye dönük plan varken zorlamadan kilit reddedilir',
    '9/2026 döneminde İK onayı bekleyen 1 geriye dönük vardiya planı var',
    $$select pdks.ay_kilitle(2026::smallint, 9::smallint)$$);
select test.dogrula('zorla kilit özeti: geçilen kalemler ve puantaja kodsuz giren gün sayısı',
    pdks.ay_kilitle(2026::smallint, 9::smallint, true)
    = '{"donem": "2026-09", "zorla": true, "kodsuz_gun": 1,
        "zorla_gecilen": {"acik_soru_gun": 1, "acik_itiraz": 1, "bekleyen_fazla_mesai": 0, "bekleyen_plan_onayi": 1},
        "mesaj": "9/2026 kilitlendi. Zorla geçilenler: 1 açık sorulu gün, 1 açık itiraz, 1 onay bekleyen geriye dönük plan. Puantaja kodsuz giren gün: 1."}'::jsonb);
reset role;
select test.dogrula('kodsuz gün sayısı puantajla uyuşuyor: AK02 7 Eylül hiçbir kod almadı, AK03 8 Eylül NÇ',
    not exists (select 1 from pdks.gun_kodlari_hesapla(2026, 9) k where k.calisan_id = test.c('AK02') and k.tarih = '2026-09-07')
    and exists (select 1 from pdks.gun_kodlari_hesapla(2026, 9) k
                where k.calisan_id = test.c('AK03') and k.tarih = '2026-09-08' and k.kod = 'NÇ'));

-- ---------------------------------------------------------------------
-- 1) Kilit, hesabı bekleyen günleri kilitten önce hesaplar
-- ---------------------------------------------------------------------
-- Eski davranışı canlandır: AK01 5 Ekim düzeltildi ama hesaplanmadı (doğrudan duzeltme_uygula)
select pdks.duzeltme_uygula((test.gk('AK01', '2026-10-05')).id, 'cikis_zamani', '2026-10-05 16:10+03',
                            'Hesaplanmamış gün denemesi', 'ik', test.k('ak_ik1@ornek.test'));
select test.dogrula('hazırlık: AK01 5 Ekim hesabı bekliyor',
    not (test.gk('AK01', '2026-10-05')).hesap_tamam);

-- ---------------------------------------------------------------------
-- 2) Gece işinden geçmemiş planlı gün varken kilit reddedilir (zorla da geçmez)
-- ---------------------------------------------------------------------
insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id, giren_id)
select test.c(s), '2026-10-07', (select id from pdks.vardiya_tanim where kod = 'GUNDUZ_8'), test.k('ak_ik2@ornek.test')
from unnest(array['AK01', 'AK06']) s;   -- AK06 o gün henüz işe girmemişti: sayılmaz
set local role authenticated;
select test.oturum('ak_ik1@ornek.test');
select test.hata('işlenmemiş planlı gün varken kilit reddedilir; mesaj gün, kişi ve ilk günü söyler',
    '10/2026 döneminde gece işinden geçmemiş 1 planlı gün var (1 çalışan; ilk gün 07.10.2026)',
    $$select pdks.ay_kilitle(2026::smallint, 10::smallint)$$);
select test.hata('zorla seçeneği işlenmemiş günü geçemez', 'zorla geçilemez',
    $$select pdks.ay_kilitle(2026::smallint, 10::smallint, true)$$);
reset role;
select test.dogrula('reddedilen kilit ayı açık bıraktı ve hesabı geri aldı (tek işlem)',
    not pdks.donem_kilitli_mi('2026-10-05') and not (test.gk('AK01', '2026-10-05')).hesap_tamam);
delete from pdks.vardiya_plani where tarih = '2026-10-07';
set local role authenticated;
select test.oturum('ak_ik1@ornek.test');
select test.dogrula('zorlamadan kilit özeti: geçilen kalem yok, kodsuz gün yok',
    pdks.ay_kilitle(2026::smallint, 10::smallint)
    = '{"donem": "2026-10", "zorla": false, "kodsuz_gun": 0, "mesaj": "10/2026 kilitlendi.",
        "zorla_gecilen": {"acik_soru_gun": 0, "acik_itiraz": 0, "bekleyen_fazla_mesai": 0, "bekleyen_plan_onayi": 0}}'::jsonb);
reset role;
select test.dogrula('kilit zorlamadan geçti (açık soru, itiraz, havuz yok)', pdks.donem_kilitli_mi('2026-10-05'));
select test.dogrula('kilitten önce hesaplanan gün puantajda: AK01 NÇ 2 gün (5 Ekim kaybolmadı)',
    (test.gk('AK01', '2026-10-05')).hesap_tamam and test.kod_gun('2026-10', 'AK01', 'NÇ') = 2);
select test.dogrula('devamsız gün DVMSZ; ayın kalan 30 günü HT ya da RT (resmi tatiller örnek veriyle gelir)',
    test.kod_gun('2026-10', 'AK05', 'DVMSZ') = 1
    and test.kod_gun('2026-10', 'AK05', 'HT') + test.kod_gun('2026-10', 'AK05', 'RT') = 30);

-- ---------------------------------------------------------------------
-- 4b) Kilitli ayda düzeltme günü değiştirmez ve hesaplamaz; fark satırı olur
-- ---------------------------------------------------------------------
set local role authenticated;
select test.oturum('ak_ik1@ornek.test');
select pdks.kayit_duzelt((test.gk('AK02', '2026-10-06')).id, 'giris_zamani', '2026-10-06 08:20+03', 'Kilit sonrası belge');
reset role;
select test.dogrula('kilitli ayda düzeltme: gün aynı kaldı, düzeltme fark satırı olarak Kasım''a yazıldı',
    (select giris_zamani = '2026-10-06 08:00+03' and gec_kalma_dk = 0 from test.gk('AK02', '2026-10-06'))
    and exists (select 1 from pdks.duzeltme d join pdks.donem p on p.id = d.hedef_donem_id
                where d.gun_kaydi_id = (test.gk('AK02', '2026-10-06')).id and d.fark_satiri
                  and p.yil = 2026 and p.ay = 11));

-- =====================================================================
-- B) Örnek veriyle uçtan uca (seed yüklü değilse atlanır)
-- =====================================================================
select exists (select 1 from pdks.calisan where sicil_no = '1001') as ornek_var \gset
\if :ornek_var
-- Test yalnızca örnek veriye bakar: A bölümünün Kasım'a yazdığı fark düzeltmesi Aralık kilidini etkilemez
update pdks.kullanici set auth_kullanici_id = v.u::uuid
from (values ('uretim.muduru@example.com', '00000000-0000-0000-0000-0000000000b1'),
             ('ik.uzmani@example.com',     '00000000-0000-0000-0000-0000000000b2'),
             ('ik.muduru@example.com',     '00000000-0000-0000-0000-0000000000b3')) v(e, u)
where eposta = v.e;
do $$ declare d date; begin
    for d in select g::date from generate_series(date '2026-11-01', date '2026-11-30', interval '1 day') g loop
        perform pdks.gece_isi_calistir(d);
    end loop;
end $$;
select test.dogrula('uçtan uca hazırlık: Kasım işlendi, 4 soru üst amirde / İK''da bekliyor',
    (select count(*) from pdks.amir_sorusu q join pdks.gun_kaydi g on g.id = q.gun_kaydi_id
     where q.durum = 'eskale' and g.is_gunu between '2026-11-01' and '2026-11-30') = 4
    and pdks.kullanici_rolu((test.soru('1001', '2026-11-26')).eskale_edilen_id) = 'ik');

set local role authenticated;
select test.oturum('uretim.muduru@example.com');
select pdks.soru_cevapla((test.soru('1003', '2026-11-04')).id, 'geldi_saat_dogru');   -- S2
select pdks.soru_cevapla((test.soru('1005', '2026-11-05')).id, 'bilmiyorum');         -- S4
select pdks.soru_cevapla((test.soru('2009', '2026-11-25')).id, 'gelmedi');            -- S19
select test.oturum('ik.uzmani@example.com');
select pdks.soru_ik_karari((test.soru('1005', '2026-11-05')).id, false, 'Vardiya sonuna kadar çalıştı', null, '2026-11-05 17:00+03');
select pdks.soru_ik_karari((test.soru('2009', '2026-11-25')).id, true, 'Haber vermeden gelmedi');
select pdks.soru_ik_karari((test.soru('1001', '2026-11-26')).id, false, 'Üretim müdürü teyit etti', '2026-11-26 08:00+03'); -- S22 (İK'ya eskale)
select pdks.fazla_mesai_inceleme_karar(f.id, f.calisan_id = test.c('3004'), 'Yazılı onay ya da plan yok')
from pdks.fazla_mesai_inceleme f where f.durum = 'inceleme_bekliyor' order by f.id;
select test.hata('uçtan uca: Okan''ın (S13) onay bekleyen planının günü işlenmedi; kilit zorla da reddeder',
    '11/2026 döneminde gece işinden geçmemiş 1 planlı gün var (1 çalışan; ilk gün 13.11.2026); 1 günün geriye dönük planı İK onayı bekliyor',
    $$select pdks.ay_kilitle(2026::smallint, 11::smallint, true)$$);
-- Planı İK uzmanı girdi; görevler ayrılığı gereği İK müdürü onaylar
select test.oturum('ik.muduru@example.com');
select pdks.vardiya_plani_onayla((select id from pdks.vardiya_plani where calisan_id = test.c('2005') and tarih = '2026-11-13'), true);
-- Hemen kilit (arada gece işi yok)
select test.oturum('ik.uzmani@example.com');
select test.dogrula('uçtan uca: Kasım kilit özeti — zorla yok, geçilen kalem yok, kodsuz gün yok',
    (select r ->> 'kodsuz_gun' = '0' and r -> 'zorla_gecilen' = '{"acik_soru_gun": 0, "acik_itiraz": 0, "bekleyen_fazla_mesai": 0, "bekleyen_plan_onayi": 0}'::jsonb
     from (select pdks.ay_kilitle(2026::smallint, 11::smallint) as r) x));
reset role;

select test.dogrula('uçtan uca: Kasım zorlamadan kilitlendi', pdks.donem_kilitli_mi('2026-11-15'));
select test.dogrula('uçtan uca: cevaplanan günler kayıp değil (1001, 1003, 1005: NÇ 21 gün)',
    test.kod_gun('2026-11', '1001', 'NÇ') = 21 and test.kod_gun('2026-11', '1003', 'NÇ') = 21
    and test.kod_gun('2026-11', '1005', 'NÇ') = 21);
select test.dogrula('uçtan uca: Kaan 20 gün NÇ + 1 gün DVMSZ',
    test.kod_gun('2026-11', '2009', 'NÇ') = 20 and test.kod_gun('2026-11', '2009', 'DVMSZ') = 1);
select test.dogrula('uçtan uca: 76 çalışanın her birinde ayın 30 günü tam bir kez kodlandı (ERP normal satırları)',
    (select count(*) from (select sicil from pdks.v_puantaj_aktarim where donem = '2026-11' and satir_turu = 'normal'
                           group by sicil having sum(gun) = 30) x) = 76);
select test.dogrula('uçtan uca: hafta tatili 9 gün; Pazar çalışanlarda 8 (Mehmet 1002 ve Erkan 5102)',
    (select count(*) from (select sicil from pdks.v_puantaj_aktarim where donem = '2026-11' and satir_turu = 'normal'
                                 and kod = 'HT' group by sicil having sum(gun) = 9) x) = 74
    and test.kod_gun('2026-11', '1002', 'HT') = 8 and test.kod_gun('2026-11', '5102', 'HT') = 8);
select test.dogrula('uçtan uca: ERP''de izin kodları (Can RPR 3, Deniz Yİ 2, Derya MZR 1) ve FM100 (Mehmet)',
    test.kod_gun('2026-11', '2007', 'RPR') = 3 and test.kod_gun('2026-11', '2008', 'Yİ') = 2
    and test.kod_gun('2026-11', '4005', 'MZR') = 1 and test.kod_gun('2026-11', '1002', 'FM100') = 1);

-- Kilitten sonra itiraz: Selin 9 Kasım 08:35 girişine itiraz, İK kabul edip 08:00 yazar
set local role authenticated;
select test.oturum('ik.uzmani@example.com');
select pdks.itiraz_gir((test.gk('3002', '2026-11-09')).id, 'Servis geç geldi, 08:00''de fabrikadaydım');
select pdks.itiraz_karar((select id from pdks.itiraz where gun_kaydi_id = (test.gk('3002', '2026-11-09')).id), true, 'Servis kaydı doğruluyor');
select pdks.kayit_duzelt((test.gk('3002', '2026-11-09')).id, 'giris_zamani', '2026-11-09 08:00+03', 'İtiraz kabulü',
                         p_itiraz_id => (select id from pdks.itiraz where gun_kaydi_id = (test.gk('3002', '2026-11-09')).id));
reset role;
select test.dogrula('uçtan uca: kilitli Kasım günü değişmedi, düzeltme Aralık''a fark satırı',
    (select giris_zamani = '2026-11-09 08:35+03' from test.gk('3002', '2026-11-09'))
    and exists (select 1 from pdks.duzeltme d join pdks.donem p on p.id = d.hedef_donem_id
                where d.gun_kaydi_id = (test.gk('3002', '2026-11-09')).id and d.fark_satiri and p.ay = 12));

-- Aralık: 7 Aralık demo planı işlenmediği için kilit reddedilir; plan kaldırılınca fark satırı yazılır
set local role authenticated;
select test.oturum('ik.uzmani@example.com');
select test.hata('uçtan uca: Aralık kilidi 7 Aralık''ın işlenmemiş 10 planlı günü yüzünden reddedilir (zorla da)',
    '12/2026 döneminde gece işinden geçmemiş 10 planlı gün var (10 çalışan; ilk gün 07.12.2026)',
    $$select pdks.ay_kilitle(2026::smallint, 12::smallint, true)$$);
reset role;
delete from pdks.vardiya_plani where tarih = '2026-12-07';
set local role authenticated;
select test.oturum('ik.uzmani@example.com');
select pdks.ay_kilitle(2026::smallint, 12::smallint, true);
reset role;
select test.dogrula('uçtan uca: Aralık ERP''sinde Selin için Kasım kaynaklı fark satırı (NÇ dakika arttı)',
    exists (select 1 from pdks.v_puantaj_aktarim where donem = '2026-12' and sicil = '3002'
            and satir_turu = 'fark' and kaynak_donem = '2026-11' and kod = 'NÇ' and dakika > 0));
\else
do $$ begin raise notice 'Örnek veri yüklü değil; uçtan uca bölüm atlandı'; end $$;
\endif

do $$ begin raise notice 'AY KİLİDİ TESTLERİ GEÇTİ'; end $$;
rollback;
