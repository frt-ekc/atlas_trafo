-- =====================================================================
-- Ayar sınırları (20261212010000_ayar_sinirlari.sql, T-74)
--   * Her ayarda aralık dışı değer reddedilir, sınır değerler kabul edilir.
--   * Yasal sınırlar yasa değerini aşamaz; mola sıralaması bozulamaz.
--   * Ondalık / metin / boş / çok büyük değer Türkçe mesajla reddedilir.
--   * Puantajı etkileyen ayar değişince İK'ya uyarı yazılır.
--
-- 1. bölüm T-74'ün raporundaki denemelerdir; migration'dan önceki kodda burada KALIR
-- (değerler tırnaklı yazılır, eski integer sürümünde de çalışır).
-- Testin kendi sahte verisi kullanılır; örnek veri yüklü olsun olmasın çalışır.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/ayar_sinirlari_testi.sql
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
create function test.oturum(p_uuid text) returns void language sql as $$
    select set_config('request.jwt.claims', json_build_object('sub', p_uuid, 'role', 'authenticated')::text, true) $$;
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte): ASD1 admin, ASI1 İK, ASM1 amir ------------------
insert into pdks.departman (ad) values ('AS İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = 'AS İdari'), '2025-01-01'
from unnest(array['ASD1', 'ASI1', 'ASM1']) s;
insert into pdks.kullanici (eposta, rol, calisan_id, auth_kullanici_id)
select e, r, (select id from pdks.calisan where sicil_no = s), u::uuid
from (values ('as_admin@ornek.test', 'admin', 'ASD1', '00000000-0000-0000-0000-0000000074b1'),
             ('as_ik@ornek.test',    'ik',    'ASI1', '00000000-0000-0000-0000-0000000074b2'),
             ('as_amir@ornek.test',  'amir',  'ASM1', '00000000-0000-0000-0000-0000000074b3')) v(e, r, s, u);

-- 1) Raporun denemeleri: eski kodda hepsi kabul ediliyordu -----------------------
select test.oturum('00000000-0000-0000-0000-0000000074b1');
set local role authenticated;
select test.hata('rapor: ' || a || ' = ' || d || ' reddedilir', 'arasında olmalı',
                 format('select pdks.ayar_guncelle(%L, %L)', a, d))
from (values ('gunluk_azami_calisma_dk', '1440'), ('fm_yillik_sinir_dk', '60000'), ('gece_calisma_sinir_dk', '0'),
             ('gec_kalma_tolerans_dk', '100000'), ('gec_kalma_tolerans_dk', '2147483647'), ('mola_uzun_dk', '0'),
             ('mola_kisa_sinir_dk', '600'), ('cumartesi_hafta_sonu', '7'), ('fm_yaklasma_uyari_yuzde', '500'),
             ('soru_eskalasyon_gun', '0'), ('kart_paylasim_sn', '0')) v(a, d);
reset role;

-- 2) Tanım ---------------------------------------------------------------------
select test.dogrula('her ayarın aralığı var ve bugünkü değer aralığın içinde',
    (select bool_and(en_az >= 0 and en_az <= en_cok and deger between en_az and en_cok) from pdks.ayar));
select test.dogrula('yasal üst sınırlar yasa değerinde: 660, 16200, 450; mola en az 15 / 30 / 60',
    (select array_agg(en_cok order by anahtar) from pdks.ayar
     where anahtar in ('fm_yillik_sinir_dk', 'gece_calisma_sinir_dk', 'gunluk_azami_calisma_dk')) = array[16200, 450, 660]
    and (select array_agg(en_az order by en_az) from pdks.ayar
         where anahtar in ('mola_kisa_dk', 'mola_orta_dk', 'mola_uzun_dk')) = array[15, 30, 60]);
select test.dogrula('bayrak 0–1, yüzde 1–100',
    (select en_az = 0 and en_cok = 1 from pdks.ayar where anahtar = 'cumartesi_hafta_sonu')
    and (select en_az = 1 and en_cok = 100 from pdks.ayar where anahtar = 'fm_yaklasma_uyari_yuzde'));

-- 3) Her ayarda sınır dışı ret, sınır değer kabul ---------------------------------
-- Her ayar kendi alt işleminde denenir ve geri alınır; mola sıralaması diğer ayarlara takılmasın.
-- (Mola ayarında sınır değer diğer molalarla sırayı bozuyorsa önce diğerleri uygun yere çekilir.)
create function test.sinir_dene(p_anahtar text, p_deger integer, p_kabul boolean) returns void language plpgsql as $$
declare
    v_hata text;
    v_sonuc integer;
begin
    begin
        if p_anahtar like 'mola\_%' and p_kabul then
            update pdks.ayar set deger = case anahtar
                when 'mola_kisa_dk' then 15
                when 'mola_orta_dk' then case when p_anahtar = 'mola_kisa_dk' and p_deger >= 30 then p_deger + 1 else 30 end
                when 'mola_uzun_dk' then 120
                when 'mola_kisa_sinir_dk' then 60
                when 'mola_orta_sinir_dk' then 450 end
            where anahtar like 'mola\_%' and anahtar <> p_anahtar;
        end if;
        -- değer zaten sınırdaysa "değişiklik yok" olmasın
        update pdks.ayar set deger = case when en_cok = p_deger then en_az else en_cok end
        where anahtar = p_anahtar and deger = p_deger;
        perform set_config('role', 'authenticated', true);
        perform pdks.ayar_guncelle(p_anahtar, p_deger::text);
        perform set_config('role', 'postgres', true);
        select deger into v_sonuc from pdks.ayar where anahtar = p_anahtar;
        raise exception using errcode = 'ZZ001', message = 'geri al';
    exception
        when sqlstate 'ZZ001' then v_hata := null;
        when others then v_hata := sqlerrm;
    end;
    if p_kabul and (v_hata is not null or v_sonuc is distinct from p_deger) then
        raise exception 'KALDI  % = % kabul edilmeliydi: % (yazılan %)', p_anahtar, p_deger, v_hata, v_sonuc;
    elsif not p_kabul and (v_hata is null or v_hata not like '%için değer % ile % arasında olmalı.%') then
        raise exception 'KALDI  % = % reddedilmeliydi: %', p_anahtar, p_deger, v_hata;
    end if;
end $$;

select test.oturum('00000000-0000-0000-0000-0000000074b1');
do $$
declare
    r record;
    n int := 0;
begin
    for r in select * from pdks.ayar order by anahtar loop
        perform test.sinir_dene(r.anahtar, r.en_az - 1, false);
        perform test.sinir_dene(r.anahtar, r.en_cok + 1, false);
        perform test.sinir_dene(r.anahtar, r.en_az, true);
        perform test.sinir_dene(r.anahtar, r.en_cok, true);
        n := n + 1;
        raise notice 'GEÇTİ  %: % ve % reddedilir, % ve % kabul edilir', r.anahtar, r.en_az - 1, r.en_cok + 1, r.en_az, r.en_cok;
    end loop;
    if n < 26 then raise exception 'KALDI  en az 26 ayar denenmeliydi, % denendi', n; end if;
end $$;

-- 4) Sayı olmayan girişler Türkçe mesajla ---------------------------------------
set local role authenticated;
select test.hata('geçersiz giriş reddedilir: ' || coalesce(quote_literal(d), 'null'), 'için tam sayı girin',
                 format('select pdks.ayar_guncelle(%L, %L)', 'gec_kalma_tolerans_dk', d))
from (values ('10.5'), ('10,5'), ('on'), (''), ('  '), ('1e3'), ('10; drop'), (null)) v(d);
select test.hata('integer''a sığmayan sayı da aralık mesajı alır', 'gec_kalma_tolerans_dk için değer 0 ile 60 arasında olmalı.',
    $$select pdks.ayar_guncelle('gec_kalma_tolerans_dk', '99999999999999999999')$$);
select test.hata('bilinmeyen ayar', 'Ayar bulunamadı', $$select pdks.ayar_guncelle('yok', '1')$$);
select test.hata('null anahtar', 'Ayar bulunamadı', $$select pdks.ayar_guncelle(null, '1')$$);

-- 5) Mola sıralaması (hepsi kendi aralığının içinde) ------------------------------
select test.hata('kısa mola orta molaya eşit olamaz', 'Mola süreleri sıralı', $$select pdks.ayar_guncelle('mola_kisa_dk', '30')$$);
select test.hata('orta mola uzun moladan büyük olamaz', 'Mola süreleri sıralı', $$select pdks.ayar_guncelle('mola_orta_dk', '75')$$);
select test.hata('orta mola uzun molaya eşit olamaz', 'Mola süreleri sıralı', $$select pdks.ayar_guncelle('mola_orta_dk', '60')$$);
select test.hata('orta sınır kısa sınırdan küçük olamaz', 'Mola sınırları sıralı', $$select pdks.ayar_guncelle('mola_orta_sinir_dk', '200')$$);
select test.hata('orta sınır kısa sınıra eşit olamaz', 'Mola sınırları sıralı', $$select pdks.ayar_guncelle('mola_orta_sinir_dk', '240')$$);
select pdks.ayar_guncelle('mola_uzun_dk', '90') \g /dev/null
select pdks.ayar_guncelle('mola_orta_dk', '75') \g /dev/null
reset role;
select test.dogrula('uzun mola büyütülünce orta mola 75 olabilir',
    pdks.ayar_al('mola_orta_dk') = 75 and pdks.ayar_al('mola_uzun_dk') = 90);

-- 6) İK'ya uyarı -----------------------------------------------------------------
create function test.uyari(p text) returns bigint language sql security definer as $$
    select count(*) from pdks.uyari where tur = 'puantaj_ayari_degisti' and mesaj like p || ' ayarı %' $$;
grant execute on function test.uyari(text) to authenticated;
update pdks.ayar set deger = 10 where anahtar = 'gec_kalma_tolerans_dk';
set local role authenticated;
select pdks.ayar_guncelle('gec_kalma_tolerans_dk', ' 15 ') \g /dev/null
reset role;
select test.dogrula('puantajı etkileyen ayar: geçmiş ve uyarı yazıldı (eski, yeni, değiştiren)',
    pdks.ayar_al('gec_kalma_tolerans_dk') = 15
    and (select eski_deger = 10 and yeni_deger = 15 from pdks.ayar_gecmisi where anahtar = 'gec_kalma_tolerans_dk' order by id desc limit 1)
    and exists (select 1 from pdks.uyari where tur = 'puantaj_ayari_degisti'
                and mesaj like 'gec_kalma_tolerans_dk ayarı 10 değerinden 15 değerine%AdASD1 Örnek%'));
set local role authenticated;
select pdks.ayar_guncelle('gec_kalma_tolerans_dk', '15') \g /dev/null
reset role;
select test.dogrula('aynı değer yeniden girilince uyarı ve geçmiş yazılmaz', test.uyari('gec_kalma_tolerans_dk') = 1);
set local role authenticated;
select pdks.ayar_guncelle('gec_kalma_tolerans_dk', '10') \g /dev/null
select pdks.ayar_guncelle('gec_kalma_tolerans_dk', '15') \g /dev/null
select pdks.ayar_guncelle('isg_uyari_gun', '45') \g /dev/null
reset role;
select test.dogrula('her değişiklik ayrı uyarıdır (aynı değere yeniden dönmek de)', test.uyari('gec_kalma_tolerans_dk') = 3);
select test.dogrula('puantajı etkilemeyen ayarda uyarı yok', pdks.ayar_al('isg_uyari_gun') = 45 and test.uyari('isg_uyari_gun') = 0);
set local role authenticated;
select test.hata('reddedilen değişiklik', 'arasında olmalı', $$select pdks.ayar_guncelle('gec_kalma_tolerans_dk', '61')$$);
reset role;
select test.dogrula('reddedilen değişiklikte uyarı yok', test.uyari('gec_kalma_tolerans_dk') = 3);
select test.oturum('00000000-0000-0000-0000-0000000074b2');
set local role authenticated;
select test.dogrula('İK uyarıyı görür', (select count(*) = 3 from pdks.uyari where tur = 'puantaj_ayari_degisti' and mesaj like 'gec_kalma_tolerans_dk%'));
select test.hata('İK ayar değiştiremez', 'yetkiniz yok', $$select pdks.ayar_guncelle('gec_kalma_tolerans_dk', '20')$$);
reset role;
select test.oturum('00000000-0000-0000-0000-0000000074b3');
set local role authenticated;
select test.dogrula('amir uyarıyı görmez', (select count(*) = 0 from pdks.uyari where tur = 'puantaj_ayari_degisti'));
reset role;

-- 7) Yetki: tek sürüm, anon kapalı, aralık ekrandan değişmez -------------------------
select test.dogrula('ayar_guncelle tek sürüm; authenticated açık, anon kapalı',
    (select count(*) = 1 from pg_proc where pronamespace = 'pdks'::regnamespace and proname = 'ayar_guncelle')
    and has_function_privilege('authenticated', 'pdks.ayar_guncelle(text, text)', 'execute')
    and not has_function_privilege('anon', 'pdks.ayar_guncelle(text, text)', 'execute'));
select test.oturum('00000000-0000-0000-0000-0000000074b1');
set local role authenticated;
select test.hata('admin aralığı doğrudan değiştiremez', 'permission denied', $$update pdks.ayar set en_cok = 99999$$);
reset role;

do $$ begin raise notice 'AYAR SINIRLARI TESTLERİ GEÇTİ'; end $$;
rollback;
