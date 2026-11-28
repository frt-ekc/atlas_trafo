-- =====================================================================
-- Şema temizliği testleri: veritabanında kullanılmayan özelliklere ait
-- sütun, fonksiyon, ayar, açıklama ya da rol kalmamalı.
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/sema_temizligi_testi.sql
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

-- Aranan kelimeler
create function test.eski_mi(p text) returns boolean language sql as $$
    select p ~* '\m(kiosk|pin|streamlit|python|psycopg)' $$;

select test.dogrula('sütun adlarında kalıntı yok',
    not exists (select 1 from information_schema.columns
                where table_schema = 'pdks' and test.eski_mi(column_name)));
select test.dogrula('fonksiyon adlarında ve gövdelerinde kalıntı yok',
    not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                where n.nspname = 'pdks' and (test.eski_mi(p.proname) or test.eski_mi(p.prosrc))));
select test.dogrula('tablo, sütun ve fonksiyon açıklamalarında kalıntı yok',
    not exists (select 1 from pg_description d
                join pg_class c on c.oid = d.objoid and d.classoid = 'pg_class'::regclass
                join pg_namespace n on n.oid = c.relnamespace
                where n.nspname = 'pdks' and test.eski_mi(d.description))
    and not exists (select 1 from pg_description d
                join pg_proc p on p.oid = d.objoid and d.classoid = 'pg_proc'::regclass
                join pg_namespace n on n.oid = p.pronamespace
                where n.nspname = 'pdks' and test.eski_mi(d.description)));
select test.dogrula('kısıtlarda (uyarı türleri vb.) kalıntı yok',
    not exists (select 1 from pg_constraint
                where connamespace = 'pdks'::regnamespace and test.eski_mi(pg_get_constraintdef(oid))));
select test.dogrula('ayarlarda ve ayar geçmişinde kalıntı yok',
    not exists (select 1 from pdks.ayar where test.eski_mi(anahtar))
    and not exists (select 1 from pdks.ayar_gecmisi where test.eski_mi(anahtar)));
select test.dogrula('eski doğrudan bağlantı rolleri yok',
    not exists (select 1 from pg_roles where rolname in ('pdks_uygulama', 'pdks_gece_isi')));
select test.dogrula('itiraz açıklaması güncel iş akışını anlatıyor',
    obj_description('pdks.itiraz'::regclass, 'pg_class') = 'Çalışanın itirazı. Amir ya da İK girer; reddi yalnızca İK.');
select test.dogrula('ayar geçmişi yine değiştirilemez (koruma geri açıldı)',
    exists (select 1 from pg_trigger where tgname = 'ayar_gecmisi_degistirilemez'
            and tgrelid = 'pdks.ayar_gecmisi'::regclass and tgenabled = 'O'));

-- T-03: security definer fonksiyonlarda geçici şema (pg_temp) en sonda aranır
select test.dogrula('T-03: pdks''teki her security definer fonksiyonun search_path''inde pg_temp var',
    not exists (select 1 from pg_proc p
                where p.pronamespace = 'pdks'::regnamespace and p.prosecdef
                  and not exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%pg_temp%')));
-- T-08: pdks'te yeni fonksiyon herkese kapalı doğar; hiçbir fonksiyon PUBLIC'e açık değil
create function pdks.t08_deneme_fn() returns int language sql as 'select 1';
select test.dogrula('T-08: yeni oluşturulan fonksiyon anon''a ve PUBLIC''e kapalı doğuyor',
    not has_function_privilege('anon', 'pdks.t08_deneme_fn()', 'execute')
    and not exists (select 1 from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                    where p.oid = 'pdks.t08_deneme_fn()'::regprocedure and a.grantee = 0));
drop function pdks.t08_deneme_fn();
select test.dogrula('T-08: pdks fonksiyonlarının hiçbiri PUBLIC''e açık değil',
    not exists (select 1 from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                where p.pronamespace = 'pdks'::regnamespace and a.grantee = 0 and a.privilege_type = 'EXECUTE'));

do $$ begin raise notice 'ŞEMA TEMİZLİĞİ TESTLERİ GEÇTİ'; end $$;
rollback;
