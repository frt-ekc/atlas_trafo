-- =====================================================================
-- Planı olmayan izin günü (20261231010000_plansiz_izin_gunu.sql, T-94)
-- Ekim 2026: 15 Perşembe, 16 Cuma, 17 Cumartesi, 18 Pazar, 19 Pazartesi;
-- 28 Ekim arife (yarım gün), 29 Ekim Cumhuriyet Bayramı. Testin kendi sahte verisi.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/plansiz_izin_gunu_testi.sql
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
create function test.oturum(p_eposta text) returns void language sql security definer as $$
    select set_config('request.jwt.claims',
        json_build_object('sub', (select auth_kullanici_id from pdks.kullanici where eposta = p_eposta),
                          'role', 'authenticated')::text, true);
$$;
create function test.c(p text) returns bigint language sql security definer as $$
    select id from pdks.calisan where sicil_no = p $$;
create function test.k(p text) returns bigint language sql security definer as $$
    select id from pdks.kullanici where eposta = p $$;
-- Çalışanın Ekim'deki bir gününün puantaj kodu (birden çok kod varsa virgülle)
create function test.kod(p_sicil text, p_gun date) returns text language sql security definer as $$
    select string_agg(kod, ',' order by kod) from pdks.gun_kodlari_hesapla(2026, 10)
    where calisan_id = test.c(p_sicil) and tarih = p_gun $$;
-- Çalışanın Ekim'de bir koddan kaç günü var
create function test.kod_gun(p_sicil text, p_kod text) returns numeric language sql security definer as $$
    select coalesce(sum(gun), 0) from pdks.gun_kodlari_hesapla(2026, 10)
    where calisan_id = test.c(p_sicil) and kod = p_kod $$;
create function test.canli(p_sicil text) returns pdks.v_puantaj_canli language sql security definer as $$
    select * from pdks.v_puantaj_canli where yil = 2026 and ay = 10 and calisan_id = test.c(p_sicil) $$;
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
--   PI01: yalnızca 15 Ekim planlı; 15–19 Ekim yıllık izin (Perşembe–Pazartesi)
--   PI02: Ekim'de hiç planı yok; 27–30 Ekim rapor (arife ve bayram içinde)
--   PI03: yalnızca 13 Ekim planlı; 14 Ekim mazeret izni yanlış girilir, iptal edilir
--   PI04: 21 Ekim'de işe girdi, 21 Ekim planlı; 19–22 Ekim yıllık izin (işe girişten önceki günler sayılmaz)
--   PII1: İK uzmanı
insert into pdks.departman (ad) values ('PI Üretim'), ('PI İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = case when s = 'PII1' then 'PI İdari' else 'PI Üretim' end),
       case when s = 'PI04' then date '2026-10-21' else date '2025-01-01' end
from unnest(array['PI01', 'PI02', 'PI03', 'PI04', 'PII1']) s;
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('x', 'pi_ik1@ornek.test', 'ik', test.c('PII1'), '00000000-0000-0000-0000-0000000000f1');
insert into pdks.kart (kart_no, calisan_id) select 'K-' || sicil_no, id from pdks.calisan where sicil_no ~ '^PI0';
insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id, giren_id)
select test.c(v.s), v.g::date, (select id from pdks.vardiya_tanim where kod = 'GUNDUZ'), test.k('pi_ik1@ornek.test')
from (values ('PI01', '2026-10-15'), ('PI03', '2026-10-13'), ('PI04', '2026-10-21')) v(s, g);

set local role authenticated;
select test.oturum('pi_ik1@ornek.test');
select pdks.izin_gir(test.c('PI01'), 'yillik',  '2026-10-15', '2026-10-19', null);
select pdks.izin_gir(test.c('PI02'), 'rapor',   '2026-10-27', '2026-10-30', null);
select pdks.izin_gir(test.c('PI03'), 'mazeret', '2026-10-14', '2026-10-14', null);
reset role;
-- PI04: işe girişten (21 Ekim) önce başlayan izin. T-68'den beri izin_gir bunu reddediyor; burada eski
-- bir kayıt gibi doğrudan yazılır ki puantajın giriş öncesi günleri saymadığı yine sınansın.
insert into pdks.izin (calisan_id, tur, baslangic, bitis, giren_id)
values (test.c('PI04'), 'yillik', '2026-10-19', '2026-10-22', test.k('pi_ik1@ornek.test'));

insert into pdks.aktarim (kaynak, dosya_adi, dosya_ozeti, veri_tarihi)
select 'pdks', 'pi_' || g::date || '.csv', 'pi-pdks-' || g::date, g::date
from generate_series(date '2026-10-13', date '2026-10-22', '1 day') g;
select pdks.gece_isi_calistir(g::date) from generate_series(date '2026-10-13', date '2026-10-22', '1 day') g;

-- 1) Bulgudaki durum: planı olmayan iş günü izin kodunu alır, HT değil ------------------------
select test.dogrula('planlı izin günü (15 Ekim Perşembe) Yİ', test.kod('PI01', '2026-10-15') = 'Yİ');
select test.dogrula('planı olmayan izin günü (16 Ekim Cuma) Yİ, HT değil', test.kod('PI01', '2026-10-16') = 'Yİ');
select test.dogrula('planı olmayan izin günü (19 Ekim Pazartesi) Yİ', test.kod('PI01', '2026-10-19') = 'Yİ');
select test.dogrula('planı olmayan gün kaydı açılmadı (yalnızca kod hesabı)',
    (select count(*) = 1 from pdks.gun_kaydi where calisan_id = test.c('PI01')));

-- 2) Hafta tatili ve Cumartesi ayarı ----------------------------------------------------------
select test.dogrula('izin içindeki Pazar (18 Ekim) HT kalır', test.kod('PI01', '2026-10-18') = 'HT');
select test.dogrula('Cumartesi iş günüyse (ayar 0) izin içindeki Cumartesi Yİ', test.kod('PI01', '2026-10-17') = 'Yİ');
select test.dogrula('izin dışındaki planı olmayan gün yine HT', test.kod('PI01', '2026-10-20') = 'HT');

-- 3) Puantaj satırı kodlarla aynı sayıyı verir ----------------------------------------------
select test.dogrula('Ekim: Yİ 4 gün (15, 16, 17, 19); planlı gün iki kez sayılmaz', test.kod_gun('PI01', 'Yİ') = 4);
select test.dogrula('canlı puantaj: izinli gün 4 (önce 1 idi)', (test.canli('PI01')).izinli_gun = 4);

-- 4) Cumartesi hafta tatiliyse izin sayılmaz ------------------------------------------------
update pdks.ayar set deger = 1 where anahtar = 'cumartesi_hafta_sonu';
select test.dogrula('Cumartesi hafta tatiliyse (ayar 1) 17 Ekim HT', test.kod('PI01', '2026-10-17') = 'HT');
select test.dogrula('ayar 1: Yİ 3 gün, canlı izinli gün 3',
    test.kod_gun('PI01', 'Yİ') = 3 and (test.canli('PI01')).izinli_gun = 3);
update pdks.ayar set deger = 0 where anahtar = 'cumartesi_hafta_sonu';

-- 5) Rapor: raporlu gün sayılır; bayram RT kalır, arife (yarım gün) rapor günüdür; hiç planı olmayan çalışan --
select test.dogrula('hiç planı olmayan çalışan puantajda görünür (canlı satır var)',
    (select count(*) = 1 from pdks.v_puantaj_canli where yil = 2026 and ay = 10 and calisan_id = test.c('PI02')));
select test.dogrula('27 ve 30 Ekim RPR', test.kod('PI02', '2026-10-27') = 'RPR' and test.kod('PI02', '2026-10-30') = 'RPR');
select test.dogrula('arife (28 Ekim, yarım gün) RPR', test.kod('PI02', '2026-10-28') = 'RPR');
select test.dogrula('bayram (29 Ekim) RT kalır', test.kod('PI02', '2026-10-29') = 'RT');
select test.dogrula('rapor raporlu güne sayılır (3), izinli güne değil (0)',
    (select raporlu_gun = 3 and izinli_gun = 0 and calisilan_gun = 0 and calisma_dk = 0 from test.canli('PI02')));
select test.dogrula('PI02 diğer günleri HT', test.kod('PI02', '2026-10-05') = 'HT');

-- 6) İptal edilen izin sayılmaz ------------------------------------------------------------
select test.dogrula('iptalden önce 14 Ekim MZR', test.kod('PI03', '2026-10-14') = 'MZR' and (test.canli('PI03')).izinli_gun = 1);
set local role authenticated;
select test.oturum('pi_ik1@ornek.test');
select pdks.izin_iptal((select id from pdks.izin where calisan_id = test.c('PI03')), 'Yanlış güne girildi');
reset role;
select test.dogrula('iptalden sonra 14 Ekim HT, izinli gün 0',
    test.kod('PI03', '2026-10-14') = 'HT' and (test.canli('PI03')).izinli_gun = 0);

-- 7) İşe girişten önceki izin günleri sayılmaz ----------------------------------------------
select test.dogrula('işe girişten önce (19, 20 Ekim) kod yok',
    test.kod('PI04', '2026-10-19') is null and test.kod('PI04', '2026-10-20') is null);
select test.dogrula('işe girişten sonra 21 (planlı) ve 22 (plansız) Yİ, izinli gün 2',
    test.kod('PI04', '2026-10-21') = 'Yİ' and test.kod('PI04', '2026-10-22') = 'Yİ'
    and (test.canli('PI04')).izinli_gun = 2);

-- 8) Ay kilidi: bordroya giden satır ve kalemler aynı sayıyı yazar --------------------------
set local role authenticated;
select test.oturum('pi_ik1@ornek.test');
select pdks.ay_kilitle(2026::smallint, 10::smallint, true, 'Test: zorla kilit gerekçesi');
reset role;
select test.dogrula('kilit: PI01 satırı izinli gün 4, Yİ kalemi 4',
    (select s.izinli_gun = 4 and k.gun = 4
     from pdks.puantaj_satiri s
     join pdks.donem d on d.id = s.donem_id and d.yil = 2026 and d.ay = 10
     join pdks.puantaj_kalemi k on k.puantaj_satiri_id = s.id and k.kod = 'Yİ'
     where s.calisan_id = test.c('PI01') and s.satir_turu = 'normal'));
select test.dogrula('kilit: hiç planı olmayan PI02 için satır var (raporlu 3, RPR 3, RT 1)',
    (select s.raporlu_gun = 3
            and (select gun from pdks.puantaj_kalemi where puantaj_satiri_id = s.id and kod = 'RPR') = 3
            and (select gun from pdks.puantaj_kalemi where puantaj_satiri_id = s.id and kod = 'RT') = 1
     from pdks.puantaj_satiri s
     join pdks.donem d on d.id = s.donem_id and d.yil = 2026 and d.ay = 10
     where s.calisan_id = test.c('PI02') and s.satir_turu = 'normal'));

-- 9) Hız kararları korunur (2000 kişi / 500 bin gün kaydı ölçümünün dayandığı üç yapı) -------
--    İK ekranı görünümü RLS altında okur; yukarıdaki test.canli ise RLS'siz (security definer).
set local role authenticated;
select test.oturum('pi_ik1@ornek.test');
select test.dogrula('İK oturumunda (RLS) canlı puantaj aynı: PI01 izinli 4, PI02 raporlu 3',
    (select izinli_gun = 4 from pdks.v_puantaj_canli where yil = 2026 and ay = 10 and calisan_id = test.c('PI01'))
    and (select raporlu_gun = 3 from pdks.v_puantaj_canli where yil = 2026 and ay = 10 and calisan_id = test.c('PI02')));
reset role;
-- Fonksiyon inline edilebilir kalmalı: SET ya da security definer eklenirse görünüm her sorguda
-- bütün yılların izin günlerini hesaplar.
select test.dogrula('plansiz_izin_gunleri inline edilebilir (SET yok, security definer değil)',
    (select proconfig is null and not prosecdef and not proisstrict and prolang = (select oid from pg_language where lanname = 'sql')
     from pg_proc where oid = 'pdks.plansiz_izin_gunleri(date, date)'::regprocedure));
create function test.plan(p_sorgu text) returns text language plpgsql as $$
declare v_satir text; v_plan text := '';
begin
    for v_satir in execute 'explain (costs off) ' || p_sorgu loop v_plan := v_plan || v_satir || E'\n'; end loop;
    return v_plan;
end $$;
select test.dogrula('canlı puantajın planında fonksiyon açılmış (ayrı "Function Scan" yok), ay filtresi izin günlerine iniyor',
    position('plansiz_izin_gunleri' in test.plan('select * from pdks.v_puantaj_canli where yil = 2026 and ay = 10')) = 0
    and test.plan('select * from pdks.v_puantaj_canli where yil = 2026 and ay = 10') ~ 'EXTRACT\(month FROM d\.gun\)');
select test.dogrula('izin okuma politikası oturumu sorgu başına bir kez denetler ((select ...) kalıbı)',
    (select qual ~* '^\(\s*select pdks\.tum_veriyi_gorur\(\)' from pg_policies
     where schemaname = 'pdks' and tablename = 'izin' and policyname = 'ik_yonetici_okur'));

-- 10) Kilitli ay (Ekim, 8. bölümde kilitlendi): planı olmayan izin gününe dokunan giriş / iptal reddedilir --
--     Fark satırı yalnızca gün kaydı olan günden üretilir; bu günde bordro sessizce yanlış kalırdı.
create function test.hata(p_sorgu text) returns text language plpgsql as $$
begin
    execute p_sorgu;
    return null;
exception when others then
    return sqlerrm;
end $$;
grant execute on function test.hata(text) to authenticated;
create temp table hz_once as select count(*) as izin_sayisi from pdks.izin;
set local role authenticated;
select test.oturum('pi_ik1@ornek.test');
select test.dogrula('kilitli ayda planı olmayan iş gününe (PI03, 14 Ekim) izin girilemez',
    test.hata($q$select pdks.izin_gir(test.c('PI03'), 'mazeret', '2026-10-14', '2026-10-14', null)$q$)
        like 'İzin girilemez: 14.10.2026 tarihinin ayı (10.2026) kilitli%');
select test.dogrula('kilitli ayda gün kaydı olan güne (PI03, 13 Ekim) izin girilir (fark satırı yolu, T-48)',
    test.hata($q$select pdks.izin_gir(test.c('PI03'), 'mazeret', '2026-10-13', '2026-10-13', null)$q$) is null);
select test.dogrula('kilitli ayda yalnızca Pazar (PI03, 25 Ekim) kapsayan izin girilir (zaten HT)',
    test.hata($q$select pdks.izin_gir(test.c('PI03'), 'yillik', '2026-10-25', '2026-10-25', null)$q$) is null);
select test.dogrula('kilitli ayın planı olmayan günlerini kapsayan iznin (PI02 rapor) iptali reddedilir',
    test.hata($q$select pdks.izin_iptal((select id from pdks.izin where calisan_id = test.c('PI02')), 'Yanlış girildi')$q$)
        like 'İzin iptal edilemez: 27.10.2026 tarihinin ayı (10.2026) kilitli%');
select test.dogrula('açık aya (Kasım) planı olmayan güne izin girilir',
    test.hata($q$select pdks.izin_gir(test.c('PI03'), 'yillik', '2026-11-02', '2026-11-03', null)$q$) is null);
reset role;
select test.dogrula('reddedilenler iz bırakmadı: yalnızca 3 izin eklendi, PI02 raporu geçerli',
    (select count(*) from pdks.izin) = (select izin_sayisi + 3 from hz_once)
    and (select iptal_zamani is null from pdks.izin where calisan_id = test.c('PI02')));
set local role authenticated;
select test.oturum('pi_ik1@ornek.test');
select test.dogrula('kilitli ayın yalnızca gün kaydı olan / tatil günlerini kapsayan izin iptal edilir',
    test.hata($q$select pdks.izin_iptal((select id from pdks.izin where calisan_id = test.c('PI03') and baslangic = '2026-10-25'), 'Yanlış girildi')$q$) is null);
reset role;

\echo 'TÜM TESTLER GEÇTİ'
rollback;
