-- =====================================================================
-- Rapor gerekçesi amire gizli (20261214010000_rapor_gizliligi.sql, T-12 seçenek a)
--   * Amir duzeltme tablosunu doğrudan okuyamaz; v_duzeltme_amir'i okur.
--   * Durum düzeltmesinde ve izne dayanan düzeltmede gerekçe gizli, "raporlu" → "izinli".
--   * Saat düzeltmesinin gerekçesi görünür; başka departmanınki görünmez.
--   * İK ve yönetici tablodan her şeyi görür.
--
-- 1. bölüm migration'dan önceki kodda KALIR (amir tabloyu okuyabiliyordu).
-- Testin kendi sahte verisi kullanılır; örnek veri yüklü olsun olmasın çalışır.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/rapor_gizliligi_testi.sql
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
create function test.c(p text) returns bigint language sql security definer as $$
    select id from pdks.calisan where sicil_no = p $$;
create function test.k(p text) returns bigint language sql security definer as $$
    select id from pdks.kullanici where eposta = p $$;
create function test.g(p text) returns bigint language sql security definer as $$
    select id from pdks.gun_kaydi where calisan_id = test.c(p) and is_gunu = '2026-08-04' $$;
create function test.oturum(p_eposta text) returns void language sql security definer as $$
    select set_config('request.jwt.claims',
        json_build_object('sub', (select auth_kullanici_id from pdks.kullanici where eposta = p_eposta),
                          'role', 'authenticated')::text, true) $$;
grant usage on schema test to authenticated, anon;
grant execute on all functions in schema test to authenticated, anon;

-- Test verisi (yalnızca sahte) ---------------------------------------------
--   RG Üretim (amiri RGA1): RG01 raporlu yapılır, RG02 izne dayanan saat düzeltmesi,
--   RG03 saat düzeltmesi, RG04 raporlu iken izinliye çevrilir
--   RG Depo (amiri RGB1): RG11 raporlu · RG İdari: RGI1 İK, RGY1 yönetici, RGG1 güvenlik
insert into pdks.departman (ad) values ('RG Üretim'), ('RG Depo'), ('RG İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = d), '2025-01-01'
from (values ('RGA1', 'RG Üretim'), ('RG01', 'RG Üretim'), ('RG02', 'RG Üretim'), ('RG03', 'RG Üretim'), ('RG04', 'RG Üretim'),
             ('RGB1', 'RG Depo'), ('RG11', 'RG Depo'),
             ('RGI1', 'RG İdari'), ('RGY1', 'RG İdari'), ('RGG1', 'RG İdari')) v(s, d);
insert into pdks.kullanici (eposta, rol, calisan_id, auth_kullanici_id)
select e, r, test.c(s), u::uuid
from (values ('rg_amir@ornek.test',  'amir',     'RGA1', '00000000-0000-0000-0000-0000000012b1'),
             ('rg_depo@ornek.test',  'amir',     'RGB1', '00000000-0000-0000-0000-0000000012b2'),
             ('rg_ik@ornek.test',    'ik',       'RGI1', '00000000-0000-0000-0000-0000000012b3'),
             ('rg_yon@ornek.test',   'yonetici', 'RGY1', '00000000-0000-0000-0000-0000000012b4'),
             ('rg_guv@ornek.test',   'guvenlik', 'RGG1', '00000000-0000-0000-0000-0000000012b5')) v(e, r, s, u);
update pdks.departman set amir_id = test.k('rg_amir@ornek.test') where ad = 'RG Üretim';
update pdks.departman set amir_id = test.k('rg_depo@ornek.test') where ad = 'RG Depo';
insert into pdks.gun_kaydi (calisan_id, is_gunu, vardiya_id, planli_baslangic, planli_bitis, giris_zamani, cikis_zamani, durum)
select test.c(s), '2026-08-04', (select id from pdks.vardiya_tanim where kod = 'GUNDUZ_8'),
       '2026-08-04 08:00+03', '2026-08-04 16:00+03', '2026-08-04 07:55+03', '2026-08-04 16:04+03', 'tamam'
from unnest(array['RG01', 'RG02', 'RG03', 'RG04', 'RG11']) s;
insert into pdks.izin (calisan_id, tur, baslangic, bitis, giren_id)
values (test.c('RG02'), 'rapor', '2026-08-04', '2026-08-04', test.k('rg_ik@ornek.test'));

set local role authenticated;
select test.oturum('rg_ik@ornek.test');
select pdks.kayit_duzelt(test.g('RG01'), 'durum', 'raporlu', 'Rapor: GIZLI-TANI üst solunum yolu') \g /dev/null
select pdks.kayit_duzelt(test.g('RG02'), 'cikis_zamani', '2026-08-04 12:00+03', 'GIZLI-IZIN hastaneye sevk',
                         p_izin_id => (select id from pdks.izin where calisan_id = test.c('RG02'))) \g /dev/null
select pdks.kayit_duzelt(test.g('RG03'), 'giris_zamani', '2026-08-04 08:20+03', 'Kapı kamerasına göre') \g /dev/null
select pdks.kayit_duzelt(test.g('RG04'), 'durum', 'raporlu', 'GIZLI-ILK rapor') \g /dev/null
select pdks.kayit_duzelt(test.g('RG04'), 'durum', 'izinli', 'GIZLI-SON yıllık izne çevrildi') \g /dev/null
select pdks.kayit_duzelt(test.g('RG11'), 'durum', 'raporlu', 'Rapor: GIZLI-DEPO') \g /dev/null

-- 1) Tablo amire kapalı (eski kodda KALIR) -----------------------------------
select test.oturum('rg_amir@ornek.test');
select test.dogrula('amir duzeltme tablosunu doğrudan okuyamaz', (select count(*) from pdks.duzeltme) = 0);

-- 2) Görünüm: gizli ve açık alanlar -------------------------------------------
select test.dogrula('amir kendi ekibinin 5 düzeltmesini görünümde görür',
    (select count(*) from pdks.v_duzeltme_amir
     where calisan_id in (test.c('RG01'), test.c('RG02'), test.c('RG03'), test.c('RG04'))) = 5);
select test.dogrula('durum düzeltmesi: gerekçe gizli, yeni değer "izinli"',
    (select count(*) = 1 and bool_and(gerekce = 'İK tarafından düzeltildi' and eski_deger = 'tamam' and yeni_deger = 'izinli')
     from pdks.v_duzeltme_amir where calisan_id = test.c('RG01')));
select test.dogrula('izne dayanan saat düzeltmesi: gerekçe gizli, saat görünür',
    (select count(*) = 1 and bool_and(gerekce = 'İK tarafından düzeltildi' and yeni_deger::timestamptz = '2026-08-04 12:00+03')
     from pdks.v_duzeltme_amir where calisan_id = test.c('RG02')));
select test.dogrula('saat düzeltmesi: gerekçe ve değerler görünür',
    (select count(*) = 1 and bool_and(gerekce = 'Kapı kamerasına göre' and eski_deger::timestamptz = '2026-08-04 07:55+03'
            and yeni_deger::timestamptz = '2026-08-04 08:20+03' and yapan_id = test.k('rg_ik@ornek.test'))
     from pdks.v_duzeltme_amir where calisan_id = test.c('RG03')));
select test.dogrula('eski değerdeki "raporlu" da "izinli" görünür',
    (select array_agg(eski_deger || '>' || yeni_deger order by id) from pdks.v_duzeltme_amir where calisan_id = test.c('RG04'))
        = array['tamam>izinli', 'izinli>izinli']);
select test.dogrula('görünümün hiçbir satırında "raporlu" ya da gizli gerekçe yok',
    (select count(*) from pdks.v_duzeltme_amir v where to_jsonb(v)::text ilike '%raporlu%' or to_jsonb(v)::text like '%GIZLI%') = 0);
select test.dogrula('görünümde izin, itiraz ve soru bağı sütunu yok',
    (select count(*) from information_schema.columns where table_schema = 'pdks' and table_name = 'v_duzeltme_amir'
     and column_name in ('izin_id', 'itiraz_id', 'soru_id')) = 0);
select test.dogrula('başka departmanın düzeltmesi görünmez',
    (select count(*) from pdks.v_duzeltme_amir where calisan_id = test.c('RG11')) = 0);
-- Süzgeç sırası: kullanıcının kendi koşulu başka departmanın satırını göremez (security_barrier)
create function pg_temp.sizdir(p_id bigint) returns boolean language plpgsql cost 0.0001 as $$
begin
    if p_id = test.c('RG11') then raise exception 'SIZDI'; end if;
    return true;
end $$;
select test.dogrula('kullanıcı koşulu görünümün süzmesinden önce çalışmaz',
    (select count(*) from pdks.v_duzeltme_amir where pg_temp.sizdir(calisan_id)) >= 5);

-- 3) Diğer roller --------------------------------------------------------------
select test.oturum('rg_depo@ornek.test');
select test.dogrula('diğer amir yalnızca kendi departmanını görür (gerekçe gizli)',
    (select count(*) = 1 and bool_and(calisan_id = test.c('RG11') and gerekce = 'İK tarafından düzeltildi')
     from pdks.v_duzeltme_amir where calisan_id in (test.c('RG01'), test.c('RG02'), test.c('RG03'), test.c('RG04'), test.c('RG11')))
    and (select count(*) from pdks.duzeltme) = 0);
select test.oturum('rg_ik@ornek.test');
select test.dogrula('İK tablodan her şeyi görür: raporlu, gerekçe, izin bağı',
    (select yeni_deger = 'raporlu' and gerekce = 'Rapor: GIZLI-TANI üst solunum yolu' from pdks.duzeltme where calisan_id = test.c('RG01'))
    and (select izin_id is not null and gerekce like 'GIZLI-IZIN%' from pdks.duzeltme where calisan_id = test.c('RG02'))
    and (select count(*) from pdks.duzeltme where calisan_id in (test.c('RG01'), test.c('RG02'), test.c('RG03'), test.c('RG04'), test.c('RG11'))) = 6);
select test.oturum('rg_yon@ornek.test');
select test.dogrula('yönetici tablodan okumaya devam eder',
    (select count(*) from pdks.duzeltme where calisan_id in (test.c('RG01'), test.c('RG11'))) = 2);
select test.oturum('rg_guv@ornek.test');
select test.dogrula('güvenlik ne tabloyu ne görünümü görür',
    (select count(*) from pdks.duzeltme) = 0 and (select count(*) from pdks.v_duzeltme_amir) = 0);
select set_config('request.jwt.claims', '{"role":"authenticated"}', true) \g /dev/null
select test.dogrula('PDKS kullanıcısı olmayan oturum görünümde satır görmez', (select count(*) from pdks.v_duzeltme_amir) = 0);

-- 4) Yetkiler ------------------------------------------------------------------
select test.oturum('rg_amir@ornek.test');
select test.hata('görünümden silinemez', 'permission denied', $$delete from pdks.v_duzeltme_amir$$);
select test.hata('görünümden değiştirilemez', 'permission denied', $$update pdks.v_duzeltme_amir set kaynak = 'ik'$$);
reset role;
select test.dogrula('görünüm yalnızca authenticated''a ve yalnızca okumaya açık; anon kapalı',
    has_table_privilege('authenticated', 'pdks.v_duzeltme_amir', 'select')
    and not has_table_privilege('authenticated', 'pdks.v_duzeltme_amir', 'insert, update, delete')
    and not has_table_privilege('anon', 'pdks.v_duzeltme_amir', 'select'));
select test.dogrula('duzeltme tablosunda amir politikası yok; görünüm security_barrier',
    not exists (select 1 from pg_policy where polrelid = 'pdks.duzeltme'::regclass and polname = 'amir_okur')
    and (select 'security_barrier=true' = any (reloptions) from pg_class where oid = 'pdks.v_duzeltme_amir'::regclass));

do $$ begin raise notice 'RAPOR GİZLİLİĞİ TESTLERİ GEÇTİ'; end $$;
rollback;
