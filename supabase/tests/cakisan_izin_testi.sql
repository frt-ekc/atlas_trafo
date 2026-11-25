-- =====================================================================
-- Çakışan izin testleri (20261218010000_cakisan_izin.sql, T-47)
-- Testin kendi sahte verisi (Ekim 2026); örnek veri yüklü olsun olmasın çalışır.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/cakisan_izin_testi.sql
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
create function test.izin(p_sicil text) returns bigint language sql security definer as $$
    select id from pdks.izin where calisan_id = test.c(p_sicil) order by id desc limit 1 $$;
create function test.ts(p text) returns timestamptz language sql immutable as $$
    select (p::timestamp) at time zone 'Europe/Istanbul' $$;
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
insert into pdks.departman (ad) values ('CI Üretim'), ('CI İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = d), '2025-01-01'
from (values ('CI01', 'CI Üretim'), ('CI02', 'CI Üretim'), ('CI03', 'CI Üretim'),
             ('CII1', 'CI İdari'), ('CII2', 'CI İdari')) v(s, d);
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('CI İK 1', 'ci_ik1@ornek.test', 'ik', test.c('CII1'), '00000000-0000-0000-0000-0000000000d1'),
    ('CI İK 2', 'ci_ik2@ornek.test', 'ik', test.c('CII2'), '00000000-0000-0000-0000-0000000000d2');

set local role authenticated;
select test.oturum('ci_ik1@ornek.test');

-- 1) Tam gün izinler --------------------------------------------------------
select pdks.izin_gir(test.c('CI01'), 'yillik', '2026-10-20', '2026-10-22');

select test.hata('kesişen rapor reddedilir, mesaj mevcut iznin tarihlerini verir', '20.10.2026 – 22.10.2026',
    $$select pdks.izin_gir(test.c('CI01'), 'rapor', '2026-10-21', '2026-10-23')$$);
select test.hata('tek günlük izin, uzun iznin içinde reddedilir', 'önce bu izin iptal edilmelidir',
    $$select pdks.izin_gir(test.c('CI01'), 'mazeret', '2026-10-21', '2026-10-21')$$);
select test.hata('mevcut izni kapsayan daha uzun izin reddedilir', 'geçerli bir izni vardır',
    $$select pdks.izin_gir(test.c('CI01'), 'ucretsiz', '2026-10-19', '2026-10-30')$$);
select test.hata('ilk güne değen izin reddedilir', 'geçerli bir izni vardır',
    $$select pdks.izin_gir(test.c('CI01'), 'diger', '2026-10-18', '2026-10-20')$$);
select test.hata('son güne değen izin reddedilir', 'geçerli bir izni vardır',
    $$select pdks.izin_gir(test.c('CI01'), 'diger', '2026-10-22', '2026-10-24')$$);

select test.oturum('ci_ik2@ornek.test');
select test.hata('başka İK aynı izni tekrar giremez', 'geçerli bir izni vardır',
    $$select pdks.izin_gir(test.c('CI01'), 'yillik', '2026-10-20', '2026-10-22')$$);

select test.dogrula('bitişik izin (bir gün sonra başlayan) girilir',
    pdks.izin_gir(test.c('CI01'), 'yillik', '2026-10-23', '2026-10-23') is not null);
select test.dogrula('bitişik izin (bir gün önce biten) girilir',
    pdks.izin_gir(test.c('CI01'), 'mazeret', '2026-10-19', '2026-10-19') is not null);
select test.dogrula('başka çalışanın izni engel değildir',
    pdks.izin_gir(test.c('CI02'), 'yillik', '2026-10-20', '2026-10-22') is not null);

select pdks.izin_iptal((select id from pdks.izin where calisan_id = test.c('CI02')), 'Yanlış tür girildi');
select test.dogrula('iptal edilen iznin yerine rapor girilir',
    pdks.izin_gir(test.c('CI02'), 'rapor', '2026-10-21', '2026-10-21') is not null);
select test.dogrula('geçerli izinler: CI01 3, CI02 1 (rapor)',
    (select count(*) = 3 from pdks.izin where calisan_id = test.c('CI01') and iptal_zamani is null)
    and (select array_agg(tur) = array['rapor'] from pdks.izin
         where calisan_id = test.c('CI02') and iptal_zamani is null));
select test.hata('bitişi başlangıcından önce olan izin reddedilir', 'başlangıcından önce olamaz',
    $$select pdks.izin_gir(test.c('CI03'), 'yillik', '2026-10-22', '2026-10-20')$$);
select test.hata('görevler ayrılığı sürüyor: İK kendi iznini giremez', 'Görevler ayrılığı',
    $$select pdks.izin_gir(test.c('CII2'), 'yillik', '2026-10-20', '2026-10-20')$$);

-- 2) Saatlik izin -----------------------------------------------------------
select test.hata('tam gün izinli güne saatlik izin girilemez', '21.10.2026 günü tam gün izinlidir',
    $$select pdks.saatlik_izin_gir(test.c('CI01'), '2026-10-21', test.ts('2026-10-21 10:00'), test.ts('2026-10-21 12:00'), 'vizite')$$);
select test.dogrula('izni iptal edilmiş güne saatlik izin girilir',
    pdks.saatlik_izin_gir(test.c('CI02'), '2026-10-20', test.ts('2026-10-20 10:00'), test.ts('2026-10-20 12:00'), 'vizite') is not null);
select test.dogrula('izinsiz güne saatlik izin girilir',
    pdks.saatlik_izin_gir(test.c('CI03'), '2026-10-21', test.ts('2026-10-21 08:00'), test.ts('2026-10-21 10:00'), 'vizite') is not null);
select test.hata('çakışan saatlik izin yine reddedilir', 'başka bir saatlik izin var',
    $$select pdks.saatlik_izin_gir(test.c('CI03'), '2026-10-21', test.ts('2026-10-21 09:00'), test.ts('2026-10-21 11:00'), 'mazeret')$$);
select test.dogrula('viziteden sonra aynı güne rapor girilir (ters yön bilerek açık)',
    pdks.izin_gir(test.c('CI03'), 'rapor', '2026-10-21', '2026-10-23') is not null);
reset role;

do $$ begin raise notice 'TÜM TESTLER GEÇTİ'; end $$;
rollback;
