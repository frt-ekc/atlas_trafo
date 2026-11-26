-- =====================================================================
-- Kartı kimin tanımladığı ve kendine kart tanımlama testleri (20261231110000_kart_tanimlayan.sql, T-82)
-- Testin kendi sahte verisi (kart kayıtları); örnek veri yüklü olsun olmasın çalışır.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/kart_tanimlayan_testi.sql
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

create function test.kart(p_no text) returns pdks.kart language sql security definer as $$
    select * from pdks.kart where kart_no = p_no $$;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
--   KR01: üretim çalışanı · KRI1 (İK uzmanı), KRI2 (İK müdürü): ikisinin de asıl kartı var
insert into pdks.departman (ad) values ('KR Üretim'), ('KR İK');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = case when s like 'KRI%' then 'KR İK' else 'KR Üretim' end), '2025-01-01'
from unnest(array['KR01','KRI1','KRI2']) s;
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('x', 'kr_ik1@ornek.test', 'ik', test.c('KRI1'), '00000000-0000-0000-0000-000000000ca1'),
    ('x', 'kr_ik2@ornek.test', 'ik', test.c('KRI2'), '00000000-0000-0000-0000-000000000ca2');
insert into pdks.kart (kart_no, calisan_id) values ('KR-I1', test.c('KRI1')), ('KR-I2', test.c('KRI2'));

-- 1) Tanımlayan yazılır ------------------------------------------------------------------------
set local role authenticated;
select test.oturum('kr_ik1@ornek.test');
select pdks.kart_tanimla(test.c('KR01'), 'KR-01');
reset role;
select test.dogrula('İK uzmanının tanımladığı kartta tanımlayan yazılı',
    (test.kart('KR-01')).tanimlayan_id = test.k('kr_ik1@ornek.test'));

-- 2) Kimse kendine kart tanımlayamaz (rapordaki senaryo: kartı başkası iptal etti) ---------------
set local role authenticated;
select test.oturum('kr_ik2@ornek.test');
select pdks.kart_iptal_et((test.kart('KR-I1')).id, 'kayip');
select test.oturum('kr_ik1@ornek.test');
select test.hata('İK uzmanı kendine yeni kart tanımlayamaz', 'Görevler ayrılığı',
    $$select pdks.kart_tanimla(test.c('KRI1'), 'KR-I1B')$$);
select test.dogrula('İK uzmanının aktif kartı yok (tanımlama geri alındı)',
    not exists (select 1 from pdks.kart where calisan_id = test.c('KRI1') and durum = 'aktif'));

-- 3) Başka bir İK tanımlayabilir ---------------------------------------------------------------
select test.oturum('kr_ik2@ornek.test');
select pdks.kart_tanimla(test.c('KRI1'), 'KR-I1B');
reset role;
select test.dogrula('İK müdürü İK uzmanına kart tanımladı; tanımlayan İK müdürü',
    (test.kart('KR-I1B')).tanimlayan_id = test.k('kr_ik2@ornek.test') and (test.kart('KR-I1B')).durum = 'aktif');

-- 4) Tanımlayan sonradan değiştirilemez ---------------------------------------------------------
select test.hata('tanımlayan değiştirilemez', 'tanımlayan değiştirilemez',
    $$update pdks.kart set tanimlayan_id = null where kart_no = 'KR-I1B'$$);
select test.hata('kendi kartına doğrudan yazılan tanımlayan da reddedilir', 'Görevler ayrılığı',
    $$insert into pdks.kart (kart_no, calisan_id, tanimlayan_id) values ('KR-I2B', test.c('KRI2'), test.k('kr_ik2@ornek.test'))$$);
select test.dogrula('iptal ve iptal edeni yazmak tanımlayanı değiştirmez (iptal yolu çalışıyor)',
    (test.kart('KR-I1')).durum = 'iptal' and (test.kart('KR-I1')).iptal_eden_id = test.k('kr_ik2@ornek.test'));

do $$ begin raise notice 'TÜM TESTLER GEÇTİ'; end $$;
rollback;
