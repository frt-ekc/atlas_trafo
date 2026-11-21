-- =====================================================================
-- WHERE'siz UPDATE / DELETE taraması (T-31, 20261204010000_dosya_yukle_where.sql)
--   Supabase, ekrandan gelen (HTTP) isteklerde `safeupdate` eklentisini yükler:
--   WHERE'siz UPDATE / DELETE "UPDATE requires a WHERE clause" hatasıyla reddedilir.
--   psql bu eklentiyi yükleyemediği için diğer testler bu hatayı görmez.
--   Bu test `pdks` şemasındaki bütün fonksiyonların kodunu tarar ve
--   WHERE'siz UPDATE / DELETE bulursa KALIR.
-- Tarayıcı önce kendini sınar: bilerek yazılmış hatalı örnekleri yakalamalı,
-- doğru örnekleri (WHERE'li, ON CONFLICT DO UPDATE, SELECT ... FOR UPDATE) yakalamamalı.
-- Veri kullanmaz; örnek veri yüklü olsun olmasın çalışır.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/where_siz_guncelleme_testi.sql
-- =====================================================================
\pset tuples_only on
\pset format unaligned
begin;

create schema test;
create function test.dogrula(p_ad text, p_kosul boolean) returns void language plpgsql as $$
begin
    if p_kosul is not true then raise exception 'KALDI  %', p_ad; end if;
    raise notice 'GEÇTİ  %', p_ad;
end $$;

-- Bir fonksiyon gövdesindeki WHERE'siz UPDATE / DELETE cümlelerini döndürür.
--   1. Yorumlar (-- ...) ve tek tırnaklı metinler silinir (içlerindeki "update" sayılmasın).
--   2. Gövde ";" ile cümlelere bölünür.
--   3. Cümlede "update <tablo> [takma ad] set" ya da "delete from" aranır;
--      "on conflict ... do update set" bir INSERT'tir, sayılmaz.
--   4. Bulunan yerden cümle sonuna kadar "where" yoksa cümle döndürülür.
create function test.wheresiz(p_govde text) returns setof text language sql immutable as $$
    with temiz as (
        select regexp_replace(
                   regexp_replace(lower(p_govde), '--[^\n]*', ' ', 'g'),
                   '''([^'']|'''')*''', '''''', 'g') as govde
    ), cumle as (
        select btrim(regexp_replace(c, '\s+', ' ', 'g')) as c
        from temiz, regexp_split_to_table(temiz.govde, ';') as c
    ), bulunan as (
        select c,
               coalesce(
                   (regexp_match(c, '(?:^|[^a-z0-9_])((?<!do )update (?:only )?[a-z0-9_."]+(?: (?:as )?[a-z0-9_]+)? set .*)$'))[1],
                   (regexp_match(c, '(?:^|[^a-z0-9_])(delete from .*)$'))[1]
               ) as parca
        from cumle
    )
    select c from bulunan
    where parca is not null and parca !~ '(^|[^a-z0-9_])where([^a-z0-9_]|$)';
$$;

-- 1. Tarayıcının kendi sınaması -------------------------------------------
select test.dogrula('WHERE''siz UPDATE yakalanır (T-31''deki satır)',
    (select count(*) from test.wheresiz($b$
        begin
            update dosya_satiri set okutma_zamani = zaman_metni::timestamptz;
        exception when invalid_datetime_format then null;
        end;
    $b$)) = 1);
select test.dogrula('WHERE''siz DELETE yakalanır',
    (select count(*) from test.wheresiz('delete from pdks.x;')) = 1);
select test.dogrula('Takma adlı WHERE''siz UPDATE yakalanır',
    (select count(*) from test.wheresiz('update pdks.x as t set a = 1 from pdks.y;')) = 1);
select test.dogrula('Önünde WHERE''li bir sorgu olsa da yakalanır',
    (select count(*) from test.wheresiz(
        'if exists (select 1 from pdks.y where b) then update pdks.x set a = 1; end if;')) = 1);
select test.dogrula('WHERE''li UPDATE ve DELETE yakalanmaz',
    (select count(*) from test.wheresiz($b$
        update dosya_satiri set okutma_zamani = zaman_metni::timestamptz
        where zaman_metni is not null;
        update dosya_satiri d set okuyucu_id = r.id from pdks.okuyucu r where upper(r.kod) = d.okuyucu_kod;
        delete from pdks.x where id = 1;
        with s as (select 1) delete from pdks.x using s where true;
    $b$)) = 0);
select test.dogrula('ON CONFLICT DO UPDATE, SELECT FOR UPDATE, yorum ve metin yakalanmaz',
    (select count(*) from test.wheresiz($b$
        insert into pdks.x (a) values (1) on conflict (a) do update set a = excluded.a;
        select * from pdks.x for update;
        -- update pdks.x set a = 1;
        raise exception 'update pdks.x set a = 1 yapılamadı';
    $b$)) = 0);

-- 2. pdks şemasındaki bütün fonksiyonlar ----------------------------------
select test.dogrula('pdks şemasında taranacak fonksiyon var',
    (select count(*) from pg_proc p join pg_language l on l.oid = p.prolang
     where p.pronamespace = 'pdks'::regnamespace and l.lanname in ('plpgsql', 'sql')) > 50);

-- Bulunan her cümle ekrana yazılır, sonra test kalır
do $$
declare r record; v_sayi integer := 0;
begin
    for r in
        select p.oid::regprocedure as fn, w as cumle
        from pg_proc p
        join pg_language l on l.oid = p.prolang
        cross join lateral test.wheresiz(p.prosrc) as w
        where p.pronamespace = 'pdks'::regnamespace and l.lanname in ('plpgsql', 'sql')
        order by 1
    loop
        raise notice 'WHERE''siz: %  →  %', r.fn, left(r.cumle, 120);
        v_sayi := v_sayi + 1;
    end loop;
    perform test.dogrula('pdks fonksiyonlarında WHERE''siz UPDATE / DELETE yok (bulunan: ' || v_sayi || ')', v_sayi = 0);
end $$;

select test.dogrula('dosya_yukle''deki geçici tablo güncellemesi WHERE''li (T-31)',
    pg_get_functiondef('pdks.dosya_yukle'::regproc) ~ 'set okutma_zamani = zaman_metni::timestamptz\s+where ');

rollback;
\echo 'WHERE''siz güncelleme taraması: GEÇTİ'
