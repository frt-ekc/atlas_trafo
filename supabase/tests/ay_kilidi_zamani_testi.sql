-- =====================================================================
-- Ay bitmeden kilit yok (20261207010000_ay_kilidi_zamani.sql, T-89)
--   * Gerçek tarihle: içinde bulunulan ay ve ileri ay kilitlenemez (zorla da);
--     bitmiş bir ay kilitlenir.
--   * Ayın son günü sınırı: test tarihi ayarıyla (pdks.test_bugun) ayın son günü
--     kilit reddedilir, ertesi gün kabul edilir.
--   * Test tarihi ayarı yalnızca doğrudan veritabanı bağlantısında (session_user
--     = postgres) geçerlidir; ekrandan gelen istek (session_user = authenticator)
--     ayarı göremez ve her zaman gerçek tarihi kullanır.
--
-- Testin kendi sahte verisi kullanılır; örnek veri yüklü olsun olmasın çalışır.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/ay_kilidi_zamani_testi.sql
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
create function test.calisir(p_ad text, p_sql text) returns void language plpgsql as $$
begin
    execute p_sql;
    raise notice 'GEÇTİ  %', p_ad;
exception when others then
    raise exception 'KALDI  %: %', p_ad, sqlerrm;
end $$;
-- Gerçek (ayarsız) İstanbul tarihi; kodun hesabından bağımsız
create function test.gercek_bugun() returns date language sql as $$
    select (now() at time zone 'Europe/Istanbul')::date $$;
-- Gerçek bugüne göre p_kaydir ay sonrasının (eksi: öncesinin) kilit çağrısı
create function test.kilit_sql(p_kaydir integer, p_zorla boolean default false) returns text language sql as $$
    select format('select pdks.ay_kilitle(%s::smallint, %s::smallint, %L::boolean)',
                  extract(year from d)::int, extract(month from d)::int, p_zorla)
    from (select (date_trunc('month', test.gercek_bugun()) + make_interval(months => p_kaydir))::date as d) x $$;
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte): bir İK kullanıcısı
insert into pdks.departman (ad) values ('AZ İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
values ('AZI1', 'AdAZI1', 'Örnek', (select id from pdks.departman where ad = 'AZ İdari'), '2020-01-01');
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id)
values ('AZ İK', 'az_ik@ornek.test', 'ik', (select id from pdks.calisan where sicil_no = 'AZI1'),
        '00000000-0000-0000-0000-0000000089b1');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000089b1","role":"authenticated"}', true) \g /dev/null

-- 1) Gerçek tarihle ---------------------------------------------------------
set local role authenticated;
select test.hata('içinde bulunulan ay kilitlenemez', 'henüz bitmedi', test.kilit_sql(0));
select test.hata('içinde bulunulan ay zorla da kilitlenemez', 'henüz bitmedi', test.kilit_sql(0, true));
select test.hata('gelecek ay kilitlenemez', 'henüz bitmedi', test.kilit_sql(1));
select test.hata('iki ay sonrası (T-89''daki Ocak 2027 gibi) kilitlenemez', 'henüz bitmedi', test.kilit_sql(2));
-- 12 ay önce: örnek veride o aya ait plan ya da gün yok
select test.calisir('bitmiş bir ay (12 ay önce) kilitlenir', test.kilit_sql(-12));
reset role;

-- 2) Ayın son günü sınırı (test tarihi ayarıyla) -----------------------------
set local pdks.test_bugun = '2030-06-30';
select test.dogrula('test tarihi ayarı doğrudan bağlantıda geçerli (bugün = 30.06.2030)',
    pdks.bugun() = '2030-06-30');
set local role authenticated;
select test.hata('ayın son günü (30.06.2030) Haziran 2030 kilitlenemez', 'henüz bitmedi',
    'select pdks.ay_kilitle(2030::smallint, 6::smallint)');
reset role;
set local pdks.test_bugun = '2030-07-01';
set local role authenticated;
select test.calisir('ertesi gün (01.07.2030) Haziran 2030 kilitlenir',
    'select pdks.ay_kilitle(2030::smallint, 6::smallint)');
reset role;

-- 3) Test tarihi ayarı yalnızca doğrudan bağlantıda -------------------------
set local pdks.test_bugun = '';
select test.dogrula('ayar boşsa gerçek tarih kullanılır', pdks.bugun() = test.gercek_bugun());
-- session_user bu psql oturumunda postgres'tir; ekrandan gelen istekte authenticator olur.
-- Bu oturumda session_user değiştirilemediği için koşul fonksiyonun kendisinden okunur.
select test.dogrula('pdks.bugun() ayarı yalnızca session_user = postgres iken kullanır',
    (select prosrc ~ 'session_user\s*=\s*''postgres''' and prosrc like '%pdks.test_bugun%'
     from pg_proc where oid = 'pdks.bugun'::regproc));

select 'Ay kilidi zamanı testi: hepsi GEÇTİ';
rollback;
