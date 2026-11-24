-- =====================================================================
-- Ekran ve uyarı metinleri (20261216010000_ekran_metinleri.sql)
--   * Her ayarın adı, kategorisi ve açıklaması var; iç numara ve teknik not yok.
--   * Süre ve cevap adı metinleri; metin yardımcıları anon'a kapalı.
--   * Veritabanı fonksiyonlarının ürettiği metinlerde eski ifadeler kalmadı.
-- Örnek veri yüklü olsun olmasın çalışır. Sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/ekran_metinleri_testi.sql
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

select test.dogrula('26 ayarın adı, kategorisi ve tekil sırası var',
    (select count(*) >= 26 and bool_and(ad <> '' and kategori <> '' and aciklama <> '')
            and count(distinct sira) = count(*) and count(distinct ad) = count(*) from pdks.ayar));
select test.dogrula('ayar metninde iç numara, kategori öneki, formül ya da 1 / 0 ifadesi yok',
    not exists (select 1 from pdks.ayar where ad || ' ' || aciklama ~ '(Sorun \d|^[^.]*: |1 ise|0 ise|bu değer\)|×|=|_dk|m\.\d)'));
select test.dogrula('ayar açıklamaları nokta ile biter, en çok iki cümle',
    (select bool_and(aciklama ~ '\.$' and array_length(regexp_split_to_array(aciklama, '\.\s'), 1) <= 3) from pdks.ayar));
select test.dogrula('süre metni: 690, 600, 45, 0',
    array[pdks.sure_metni(690), pdks.sure_metni(600), pdks.sure_metni(45), pdks.sure_metni(0)] = array['11 sa 30 dk', '10 sa', '45 dk', '0 dk']);
select test.dogrula('ayar değeri metni: Açık / Kapalı, dakika, yüzde, gün',
    array[pdks.ayar_degeri_metni(1, 'evet/hayır'), pdks.ayar_degeri_metni(0, 'evet/hayır'), pdks.ayar_degeri_metni(10, 'dakika'),
          pdks.ayar_degeri_metni(80, 'yüzde'), pdks.ayar_degeri_metni(3, 'gün')] = array['Açık', 'Kapalı', '10 dk', '%80', '3 gün']);
select test.dogrula('her soru cevabının Türkçe adı var; amir gerekçesine kod yazılmaz',
    (select bool_and(pdks.soru_cevabi_adi(k) <> k) from unnest(array['geldi_saat_dogru', 'geldi_saat_farkli', 'kart_unuttu', 'gelmedi', 'bilmiyorum']) k)
    and (select prosrc not like '%''Amir cevabı: '' || p_cevap%' from pg_proc where oid = 'pdks.soru_cevapla(bigint, text, timestamptz, timestamptz, text)'::regprocedure));
select test.dogrula('üretilen metinlerde eski ifadeler kalmadı',
    not exists (select 1 from pg_proc where pronamespace = 'pdks'::regnamespace
                and prosrc ~ '(Ceza değildir|Kapı kilitlenmedi|İK incelemeli|üst amire / İK|Bilgi amaçlıdır|dk kaldı|arka arkaya okutuldu)'));
select test.dogrula('metin yardımcıları anon''a kapalı',
    not has_function_privilege('anon', 'pdks.sure_metni(integer)', 'execute')
    and not has_function_privilege('anon', 'pdks.ayar_degeri_metni(integer, text)', 'execute')
    and not has_function_privilege('anon', 'pdks.soru_cevabi_adi(text)', 'execute'));

do $$ begin raise notice 'EKRAN METİNLERİ TESTLERİ GEÇTİ'; end $$;
rollback;
