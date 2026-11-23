-- =====================================================================
-- Kullanıcı çift kayıt testleri (20261208010000_kullanici_cift_kayit.sql, T-105)
--   * izinli_mi kolonu yok; amirin izni izin tablosundan okunur
--   * soru, izinli amirin vekiline gider (izin bitince, iptal edilince ya da vekil yoksa amire)
--   * kullanici.ad_soyad her zaman çalışan kaydından gelir
--   * kullanici_ekle ad soyad almaz
-- Testin kendi sahte verisi kullanılır; örnek veri yüklü olsun olmasın çalışır.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/kullanici_cift_kayit_testi.sql
-- =====================================================================
\pset tuples_only on
\pset format unaligned
begin;
set local timezone = 'Europe/Istanbul';
set local pdks.test_bugun = '2030-03-10';

create schema test;
create function test.dogrula(p_ad text, p_kosul boolean) returns void language plpgsql as $$
begin
    if p_kosul is not true then raise exception 'KALDI  %', p_ad; end if;
    raise notice 'GEÇTİ  %', p_ad;
end $$;
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
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
insert into pdks.departman (ad) values ('KC Üretim'), ('KC Vekilsiz');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, a, so, (select id from pdks.departman where ad = d), '2025-01-01'
from (values ('KC01', 'Deniz', 'İşçi',  'KC Üretim'),
             ('KC02', 'Ece',   'Usta',  'KC Vekilsiz'),
             ('KCA1', 'Kemal', 'Amir',  'KC Üretim'),
             ('KCV1', 'Vedat', 'Vekil', 'KC Üretim'),
             ('KCB1', 'Burak', 'Amir',  'KC Vekilsiz'),
             ('KCI1', 'İpek',  'İK',    'KC Üretim'),
             ('KCD1', 'Ayla',  'Admin', 'KC Üretim'),
             ('KCN1', 'Nazlı', 'Yeni',  'KC Üretim')) v(s, a, so, d);
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('Yanlış Ad', 'kc_amir@ornek.test',   'amir',  test.c('KCA1'), '00000000-0000-0000-0000-0000000000c1'),
    ('KC Vekil',  'kc_vekil@ornek.test',  'amir',  test.c('KCV1'), '00000000-0000-0000-0000-0000000000c2'),
    ('KC Amir 2', 'kc_amir2@ornek.test',  'amir',  test.c('KCB1'), '00000000-0000-0000-0000-0000000000c3'),
    ('KC İK',     'kc_ik@ornek.test',     'ik',    test.c('KCI1'), '00000000-0000-0000-0000-0000000000c4'),
    ('KC Admin',  'kc_admin@ornek.test',  'admin', test.c('KCD1'), '00000000-0000-0000-0000-0000000000c5');
update pdks.departman set amir_id = test.k('kc_amir@ornek.test'), vekil_amir_id = test.k('kc_vekil@ornek.test')
where ad = 'KC Üretim';
update pdks.departman set amir_id = test.k('kc_amir2@ornek.test') where ad = 'KC Vekilsiz';

-- 1) izinli_mi kolonu kalktı ------------------------------------------------------
select test.dogrula('kullanici tablosunda izinli_mi kolonu yok',
    not exists (select 1 from information_schema.columns
                where table_schema = 'pdks' and table_name = 'kullanici' and column_name = 'izinli_mi'));

-- 2) Soru yönlendirmesi izin tablosuna bakar ---------------------------------------
select test.dogrula('amir izinli değilken soru amire gider',
    pdks.soru_atanacak(test.c('KC01')) = test.k('kc_amir@ornek.test'));

insert into pdks.izin (calisan_id, tur, baslangic, bitis, giren_id)
values (test.c('KCA1'), 'yillik', '2030-03-09', '2030-03-12', test.k('kc_ik@ornek.test'));
select test.dogrula('amirin bugün yıllık izni varsa soru vekile gider',
    pdks.soru_atanacak(test.c('KC01')) = test.k('kc_vekil@ornek.test'));
select test.dogrula('kullanici_izinli_mi: izin günlerinde true',
    pdks.kullanici_izinli_mi(test.k('kc_amir@ornek.test'))
    and pdks.kullanici_izinli_mi(test.k('kc_amir@ornek.test'), '2030-03-12'));

set local pdks.test_bugun = '2030-03-13';
select test.dogrula('izin bitince soru yine amire gider',
    pdks.soru_atanacak(test.c('KC01')) = test.k('kc_amir@ornek.test'));
select test.dogrula('kullanici_izinli_mi: izinden önce ve sonra false',
    not pdks.kullanici_izinli_mi(test.k('kc_amir@ornek.test'))
    and not pdks.kullanici_izinli_mi(test.k('kc_amir@ornek.test'), '2030-03-08'));

set local pdks.test_bugun = '2030-03-10';
update pdks.izin set iptal_zamani = now(), iptal_eden_id = test.k('kc_ik@ornek.test'), iptal_nedeni = 'Test iptali'
where calisan_id = test.c('KCA1');
select test.dogrula('iptal edilen izin sayılmaz: soru amire gider',
    pdks.soru_atanacak(test.c('KC01')) = test.k('kc_amir@ornek.test'));

insert into pdks.izin (calisan_id, tur, baslangic, bitis, giren_id)
values (test.c('KCA1'), 'rapor', '2030-03-10', '2030-03-10', test.k('kc_ik@ornek.test'));
select test.dogrula('amirin raporu da izin sayılır: soru vekile gider',
    pdks.soru_atanacak(test.c('KC01')) = test.k('kc_vekil@ornek.test'));

insert into pdks.izin (calisan_id, tur, baslangic, bitis, giren_id)
values (test.c('KCB1'), 'yillik', '2030-03-10', '2030-03-10', test.k('kc_ik@ornek.test'));
select test.dogrula('vekili olmayan departmanda izinli amire soru yine amire gider',
    pdks.soru_atanacak(test.c('KC02')) = test.k('kc_amir2@ornek.test'));

select test.dogrula('çalışana bağlı olmayan kullanıcı izinli sayılmaz',
    not pdks.kullanici_izinli_mi(-1));

-- 3) Ad soyad çalışan kaydından -----------------------------------------------------
select test.dogrula('elle yazılan ad yerine çalışanın adı yazılır',
    (select ad_soyad from pdks.kullanici where eposta = 'kc_amir@ornek.test') = 'Kemal Amir');
select test.dogrula('bütün test kullanıcılarının adı çalışan kaydıyla aynı',
    not exists (select 1 from pdks.kullanici k join pdks.calisan c on c.id = k.calisan_id
                where k.eposta like 'kc\_%' and k.ad_soyad <> c.ad || ' ' || c.soyad));

update pdks.kullanici set ad_soyad = 'Başka Bir Ad' where eposta = 'kc_amir@ornek.test';
select test.dogrula('kullanıcının adı elle değiştirilemez (çalışandan geri yazılır)',
    (select ad_soyad from pdks.kullanici where eposta = 'kc_amir@ornek.test') = 'Kemal Amir');

update pdks.calisan set soyad = 'Yılmaz' where sicil_no = 'KCA1';
select test.dogrula('çalışanın soyadı değişince kullanıcı adı da değişir',
    (select ad_soyad from pdks.kullanici where eposta = 'kc_amir@ornek.test') = 'Kemal Yılmaz');

insert into pdks.kullanici (ad_soyad, eposta, rol) values ('Bağsız Kişi', 'kc_bagsiz@ornek.test', 'ik');
select test.dogrula('çalışana bağlı olmayan kullanıcının adı olduğu gibi kalır',
    (select ad_soyad from pdks.kullanici where eposta = 'kc_bagsiz@ornek.test') = 'Bağsız Kişi');

select test.dogrula('veritabanında çalışan adıyla uyuşmayan kullanıcı kalmadı',
    not exists (select 1 from pdks.kullanici k join pdks.calisan c on c.id = k.calisan_id
                where k.ad_soyad <> c.ad || ' ' || c.soyad));

-- 4) kullanici_ekle ad soyad almaz -------------------------------------------------
set local role authenticated;
select test.oturum('kc_admin@ornek.test');
select test.dogrula('admin, ad soyad yazmadan kullanıcı tanımlar',
    pdks.kullanici_ekle('kc_yeni@ornek.test', 'amir', test.c('KCN1')) > 0);
reset role;
select test.dogrula('yeni kullanıcının adı çalışan kaydından geldi',
    (select ad_soyad from pdks.kullanici where eposta = 'kc_yeni@ornek.test') = 'Nazlı Yeni');
select test.dogrula('eski 5 parametreli kullanici_ekle kaldırıldı',
    to_regprocedure('pdks.kullanici_ekle(text, text, text, bigint, bigint)') is null
    and to_regprocedure('pdks.kullanici_ekle(text, text, bigint, bigint)') is not null);

-- 5) Yetkiler -------------------------------------------------------------------------
select test.dogrula('iç fonksiyonlar uygulamaya kapalı, kullanici_ekle açık',
    not has_function_privilege('authenticated', 'pdks.kullanici_izinli_mi(bigint, date)', 'execute')
    and not has_function_privilege('anon', 'pdks.kullanici_izinli_mi(bigint, date)', 'execute')
    and has_function_privilege('authenticated', 'pdks.kullanici_ekle(text, text, bigint, bigint)', 'execute')
    and not has_function_privilege('anon', 'pdks.kullanici_ekle(text, text, bigint, bigint)', 'execute'));

do $$ begin raise notice 'KULLANICI ÇİFT KAYIT TESTLERİ GEÇTİ'; end $$;
rollback;
