-- =====================================================================
-- Soru cevaplayamayan amir testleri (20261231100000_gecersiz_amir.sql, T-70)
-- Testin kendi sahte verisi (Ekim 2026); örnek veri yüklü olsun olmasın çalışır.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/gecersiz_amir_testi.sql
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
create function test.ts(p text) returns timestamptz language sql immutable as $$
    select (p::timestamp) at time zone 'Europe/Istanbul' $$;
create function test.plan(p_sicil text, p_gun date) returns pdks.fazla_mesai_plani language sql security definer as $$
    select * from pdks.fazla_mesai_plani where calisan_id = test.c(p_sicil) and is_gunu = p_gun $$;
create function test.hv(p_sicil text, p_gun date) returns pdks.fazla_mesai_inceleme language sql security definer as $$
    select * from pdks.fazla_mesai_inceleme where calisan_id = test.c(p_sicil) and is_gunu = p_gun $$;
create function test.kilit(p_yil int, p_ay int) returns jsonb language sql security definer as $$
    select z.ozet from pdks.donem_kilit_izi z join pdks.donem d on d.id = z.donem_id
    where d.yil = p_yil and d.ay = p_ay order by z.kilit_zamani desc limit 1 $$;
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

create function test.soru(p_sicil text, p_gun date) returns pdks.amir_sorusu language sql security definer as $$
    select q.* from pdks.amir_sorusu q join pdks.gun_kaydi g on g.id = q.gun_kaydi_id
    where g.calisan_id = test.c(p_sicil) and g.is_gunu = p_gun order by q.id limit 1 $$;
create function test.uyari(p_dep text) returns text language sql security definer as $$
    select string_agg(mesaj, ' | ' order by id) from pdks.uyari
    where tur = 'amirsiz_departman' and mesaj like p_dep || ' departmanının%' $$;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
-- Departmanlar ve amirleri (hepsi "amir" rolüyle başlar):
--   GA Pasif : amir GAA1 (üst GAU1)               → GAA1'in hesabı pasif yapılır (kullanici_guncelle)
--   GA Rol   : amir GAB1 (üst GAU1)               → GAB1'in rolü "guvenlik" olur
--   GA Vekil : amir GAC1, vekil GAV1 (üst GAU1)   → GAC1'in hesabı pasif yapılır
--   GA Ust   : amir GAE1 (üst GAU2)               → GAU2 pasif yapılır (eskale İK'ya gitmeli)
--   GA Bos   : amir GAF1 (üst GAU2)               → ikisi de pasif (soru İK'ya)
-- Çalışanlar: GA01 GA Pasif · GA02 GA Rol · GA03 GA Vekil · GA04 GA Pasif (sorusu önceden açık)
--             GA05 GA Ust · GA06 GA Bos. Hiçbiri okutma yapmaz; planlı günde "hiç kayıt yok" sorusu açılır.
insert into pdks.departman (ad) values ('GA Pasif'), ('GA Rol'), ('GA Vekil'), ('GA Ust'), ('GA Bos'), ('GA Yönetim');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = d), '2025-01-01'
from (values ('GA01', 'GA Pasif'), ('GA04', 'GA Pasif'), ('GA02', 'GA Rol'), ('GA03', 'GA Vekil'),
             ('GA05', 'GA Ust'), ('GA06', 'GA Bos'),
             ('GAA1', 'GA Yönetim'), ('GAB1', 'GA Yönetim'), ('GAC1', 'GA Yönetim'), ('GAV1', 'GA Yönetim'),
             ('GAE1', 'GA Yönetim'), ('GAF1', 'GA Yönetim'), ('GAU1', 'GA Yönetim'), ('GAU2', 'GA Yönetim'),
             ('GAI1', 'GA Yönetim'), ('GAD1', 'GA Yönetim')) v(s, d);
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('x', 'ga_u1@ornek.test', 'amir',  test.c('GAU1'), '00000000-0000-0000-0000-000000000ba1'),
    ('x', 'ga_u2@ornek.test', 'amir',  test.c('GAU2'), '00000000-0000-0000-0000-000000000ba2'),
    ('x', 'ga_ik@ornek.test', 'ik',    test.c('GAI1'), '00000000-0000-0000-0000-000000000ba3'),
    ('x', 'ga_ad@ornek.test', 'admin', test.c('GAD1'), '00000000-0000-0000-0000-000000000ba4');
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id, ust_amir_id)
select 'x', lower(s) || '@ornek.test', 'amir', test.c(s), ('00000000-0000-0000-0000-000000000b' || lpad(n::text, 2, '0'))::uuid,
       test.k(case when s in ('GAE1', 'GAF1') then 'ga_u2@ornek.test' else 'ga_u1@ornek.test' end)
from (values ('GAA1', 11), ('GAB1', 12), ('GAC1', 13), ('GAV1', 14), ('GAE1', 15), ('GAF1', 16)) v(s, n);
update pdks.departman d set amir_id = test.k(lower(v.a) || '@ornek.test'),
                            vekil_amir_id = case when v.v is not null then test.k(lower(v.v) || '@ornek.test') end
from (values ('GA Pasif', 'GAA1', null), ('GA Rol', 'GAB1', null), ('GA Vekil', 'GAC1', 'GAV1'),
             ('GA Ust', 'GAE1', null), ('GA Bos', 'GAF1', null)) v(d, a, v)
where d.ad = v.d;
insert into pdks.okuyucu (kod, ad, sistem) values ('GA-PDKS', 'GA PDKS', 'pdks');
insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id, giren_id)
select test.c(s), g::date, (select id from pdks.vardiya_tanim where kod = 'GUNDUZ'), test.k('ga_ik@ornek.test')
from (values ('GA04', '2026-10-13'), ('GA05', '2026-10-13'),
             ('GA01', '2026-10-14'), ('GA02', '2026-10-14'), ('GA03', '2026-10-14'), ('GA06', '2026-10-14')) v(s, g);
insert into pdks.aktarim (kaynak, dosya_adi, dosya_ozeti, veri_tarihi)
select 'pdks', 'ga_' || g || '.csv', 'ga-' || g, g::date from unnest(array['2026-10-13', '2026-10-14', '2026-10-15']) g;
set local pdks.test_bugun = '2026-10-16';

-- Hazırlık: 13 Ekim soruları geçerli amirlere açılır
select pdks.gece_isi_calistir('2026-10-13');
select test.dogrula('hazırlık: GA04''ün sorusu amir GAA1''e, GA05''inki amir GAE1''e açıldı',
    (test.soru('GA04', '2026-10-13')).atanan_id = test.k('gaa1@ornek.test') and (test.soru('GA04', '2026-10-13')).durum = 'acik'
    and (test.soru('GA05', '2026-10-13')).atanan_id = test.k('gae1@ornek.test'));

-- 1) Amirler soru cevaplayamaz hâle gelir -------------------------------------------------------
set local role authenticated;
select test.oturum('ga_ad@ornek.test');
select pdks.kullanici_guncelle(test.k('gaa1@ornek.test'), p_aktif => false);           -- GA Pasif amiri
reset role;
update pdks.kullanici set rol = 'guvenlik' where eposta = 'gab1@ornek.test';           -- GA Rol amiri
update pdks.kullanici set aktif = false where eposta in ('gac1@ornek.test',            -- GA Vekil amiri
                                                         'ga_u2@ornek.test',           -- GA Ust / GA Bos üst amiri
                                                         'gaf1@ornek.test');           -- GA Bos amiri

select test.dogrula('açık soru devredildi: GA04''ün sorusu pasif GAA1''den üst amir GAU1''e geçti',
    (test.soru('GA04', '2026-10-13')).atanan_id = test.k('ga_u1@ornek.test') and (test.soru('GA04', '2026-10-13')).durum = 'acik');
select test.dogrula('İK''ya uyarı: GA Pasif amiri pasif, yeni amir atanmalı, soru şimdilik kime gidiyor, 1 soru devredildi',
    test.uyari('GA Pasif') like '%hesabı pasif%' and test.uyari('GA Pasif') like '%yeni amir%'
    and test.uyari('GA Pasif') like '%1 açık soru devredildi%');
select test.dogrula('İK''ya uyarı: GA Rol amirinin rolü değişti (güvenlik)',
    test.uyari('GA Rol') like '%rolü güvenlik%');
select test.dogrula('İK''ya uyarı: GA Vekil, GA Bos amiri pasif; GA Ust''te amir geçerli olduğu için uyarı yok',
    test.uyari('GA Vekil') is not null and test.uyari('GA Bos') is not null and test.uyari('GA Ust') is null);

-- 2) Yeni sorular geçerli kişiye açılır ---------------------------------------------------------
select pdks.gece_isi_calistir('2026-10-14');
select test.dogrula('pasif amirin departmanı: soru üst amir GAU1''e',
    (test.soru('GA01', '2026-10-14')).atanan_id = test.k('ga_u1@ornek.test'));
select test.dogrula('rolü değişen amirin departmanı: soru üst amir GAU1''e',
    (test.soru('GA02', '2026-10-14')).atanan_id = test.k('ga_u1@ornek.test'));
select test.dogrula('vekili olan departman: soru vekil GAV1''e',
    (test.soru('GA03', '2026-10-14')).atanan_id = test.k('gav1@ornek.test'));
select test.dogrula('amiri de üst amiri de pasif: soru İK''ya',
    pdks.kullanici_rolu((test.soru('GA06', '2026-10-14')).atanan_id) = 'ik');
set local role authenticated;
select test.oturum('ga_u1@ornek.test');
select pdks.soru_cevapla((test.soru('GA01', '2026-10-14')).id, 'gelmedi');
reset role;
select test.dogrula('devralan üst amir soruyu cevaplayabiliyor',
    (test.soru('GA01', '2026-10-14')).cevaplayan_id = test.k('ga_u1@ornek.test'));

-- 3) Eskale: üst amir pasifse İK'ya ------------------------------------------------------------
select pdks.gece_isi_eskale((test.soru('GA05', '2026-10-13')).son_cevap_tarihi);
select test.dogrula('GA05''in sorusu süresinde cevaplanmadı; pasif üst amir GAU2''ye değil İK''ya gitti',
    (test.soru('GA05', '2026-10-13')).durum = 'eskale'
    and pdks.kullanici_rolu((test.soru('GA05', '2026-10-13')).eskale_edilen_id) = 'ik');

-- 4) Hesabı yeniden açılan amir sorusunu yeniden alır; tekrar uyarı yazılmaz --------------------
update pdks.kullanici set aktif = true where eposta = 'gac1@ornek.test';
select test.dogrula('GA Vekil amiri geri döndü: uyarı sayısı değişmedi',
    (select count(*) = 1 from pdks.uyari where tur = 'amirsiz_departman' and mesaj like 'GA Vekil departmanının%'));

-- 5) Vekil soru alamaz olunca uyarı "yeni vekil amir" der; amir geçerli, soru amire gider ------
update pdks.kullanici set aktif = false where eposta = 'gav1@ornek.test';
select test.dogrula('vekil pasif: uyarı yeni vekil amir ister, departmanın sorusu geri dönen amir GAC1''e',
    test.uyari('GA Vekil') like '%vekil amiri AdGAV1 Örnek%yeni vekil amir atanmalıdır%'
    and pdks.departman_soru_hedefi((select id from pdks.departman where ad = 'GA Vekil')) = test.k('gac1@ornek.test'));

do $$ begin raise notice 'TÜM TESTLER GEÇTİ'; end $$;
rollback;
