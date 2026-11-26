-- =====================================================================
-- Dosyanın günü ve satır tarihleri testleri (20261231120000_dosya_tarihi.sql, T-17, T-18, T-21)
-- Testin kendi sahte verisi (Eylül–Aralık 2026); örnek veri yüklü olsun olmasın çalışır.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/dosya_tarihi_testi.sql
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

create function test.ozet(p text) returns text language sql as $$ select repeat(p, 64) $$;
create function test.aktarim_var(p_gun date) returns boolean language sql security definer as $$
    select exists (select 1 from pdks.aktarim where kaynak = 'pdks' and veri_tarihi = p_gun and dosya_adi like 'dt_%') $$;
create function test.hata_mesaji(p_sql text) returns text language plpgsql as $$
begin
    execute p_sql;
    return null;
exception when others then
    return sqlerrm;
end $$;
create temp table dt_sonuc (ad text primary key, aktarim_id bigint);
grant all on dt_sonuc to authenticated;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
-- Bugün 10 Aralık 2026 kabul edilir. DT01: gece vardiyası çalışanı.
insert into pdks.departman (ad) values ('DT Üretim'), ('DT İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = case when s like 'DTI%' then 'DT İdari' else 'DT Üretim' end), '2025-01-01'
from unnest(array['DT01','DTI1']) s;
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('x', 'dt_ik@ornek.test', 'ik', test.c('DTI1'), '00000000-0000-0000-0000-000000000da1');
insert into pdks.kart (kart_no, calisan_id) values ('DT-K1', test.c('DT01'));
insert into pdks.okuyucu (kod, ad, sistem) values ('DT-PDKS', 'DT PDKS', 'pdks');
set local pdks.test_bugun = '2026-12-10';
set local role authenticated;
select test.oturum('dt_ik@ornek.test');

-- 1) T-17: yanlış günün dosyası reddedilir ------------------------------------------------------
select test.hata('10 Aralık''ın satırları "7 Aralık" dosyası olarak yüklenemez',
    '1. satırın tarihi (10.12.2026) dosyanın günü (07.12.2026) ya da ertesi gün değil',
    $$select pdks.dosya_yukle('pdks', 'dt_20261207.csv', '2026-12-07',
        '[{"okuyucu": "DT-PDKS", "kart_no": "DT-K1", "zaman": "2026-12-10T07:55:00+03:00", "yon": "giris"},
          {"okuyucu": "DT-PDKS", "kart_no": "DT-K1", "zaman": "2026-12-10T17:02:00+03:00", "yon": "cikis"}]', test.ozet('a'))$$);
select test.dogrula('reddedilen dosya 7 Aralık için aktarım bırakmadı (gün "veri yok" kalır)',
    not test.aktarim_var('2026-12-07'));
select test.hata('karışık dosyada ilk aykırı satır numarasıyla söylenir (2. satır, 05.12)',
    '2. satırın tarihi (05.12.2026)',
    $$select pdks.dosya_yukle('pdks', 'dt_20261207b.csv', '2026-12-07',
        '[{"okuyucu": "DT-PDKS", "kart_no": "DT-K1", "zaman": "2026-12-07T07:55:00+03:00"},
          {"okuyucu": "DT-PDKS", "kart_no": "DT-K1", "zaman": "2026-12-05T17:02:00+03:00"}]', test.ozet('b'))$$);

-- 2) Dosyanın günü ve ertesi sabah (gece vardiyası çıkışı) kabul edilir; saat dilimi İstanbul ----
insert into dt_sonuc values ('gece', pdks.dosya_yukle('pdks', 'dt_20261208.csv', '2026-12-08',
    '[{"okuyucu": "DT-PDKS", "kart_no": "DT-K1", "zaman": "2026-12-08T23:58:00+03:00", "yon": "giris"},
      {"okuyucu": "DT-PDKS", "kart_no": "DT-K1", "zaman": "2026-12-09T08:03:00+03:00", "yon": "cikis"},
      {"okuyucu": "DT-PDKS", "kart_no": "DT-K1", "zaman": "2026-12-08T21:30:00Z"}]', test.ozet('c')));
select test.dogrula('8 Aralık dosyası: 8 Aralık gecesi, 9 Aralık sabahı ve UTC yazılmış (İstanbul''da 9 Aralık 00:30) satır kabul edildi',
    (select aktarim_id is not null from dt_sonuc where ad = 'gece'));

select test.dogrula('çakışan dışa aktarım: 9 Aralık dosyasında 8 Aralık gecesinin (önceden gelmiş) okutması kabul edilir, yeniden yazılmaz',
    pdks.dosya_yukle('pdks', 'dt_20261209.csv', '2026-12-09',
        '[{"okuyucu": "DT-PDKS", "kart_no": "DT-K1", "zaman": "2026-12-08T23:58:00+03:00", "yon": "giris"},
          {"okuyucu": "DT-PDKS", "kart_no": "DT-K1", "zaman": "2026-12-09T23:50:00+03:00", "yon": "giris"}]', test.ozet('1'))
    is not null);
select test.hata('önceki günün YENİ okutması ise reddedilir', '1. satırın tarihi (08.12.2026)',
    $$select pdks.dosya_yukle('pdks', 'dt_20261209b.csv', '2026-12-09',
        '[{"okuyucu": "DT-PDKS", "kart_no": "DT-K1", "zaman": "2026-12-08T12:00:00+03:00"}]', test.ozet('2'))$$);

-- 3) T-18: ileri tarih ----------------------------------------------------------------------------
select test.hata('dosyanın günü bugünden ileri olamaz (11 Aralık)', 'Dosyanın günü (11.12.2026) bugünden ileri olamaz',
    $$select pdks.dosya_yukle('pdks', 'dt_20261211.csv', '2026-12-11',
        '[{"okuyucu": "DT-PDKS", "kart_no": "DT-K1", "zaman": "2026-12-11T07:55:00+03:00"}]', test.ozet('d'))$$);
select test.hata('bugünün dosyasında yarına ait satır olamaz', '1. satırın tarihi (11.12.2026) bugünden ileri',
    $$select pdks.dosya_yukle('pdks', 'dt_20261210.csv', '2026-12-10',
        '[{"okuyucu": "DT-PDKS", "kart_no": "DT-K1", "zaman": "2026-12-11T00:10:00+03:00"}]', test.ozet('e'))$$);
reset role;
-- Eskiden yüklenmiş ileri tarihli bir aktarım (2030) olsa bile gece işi ileri bir günü işlemez
insert into pdks.aktarim (kaynak, dosya_adi, dosya_ozeti, veri_tarihi) values ('pdks', 'dt_2030.csv', 'dt-2030', '2030-01-01');
select test.hata('gece işi bugünden ileri bir gün için çalışmaz (2029-12-31)', 'Bu gün için henüz veri yok',
    $$select pdks.gece_isi_calistir('2029-12-31')$$);
select test.hata('gece işi yarın için de çalışmaz', 'Bu gün için henüz veri yok',
    $$select pdks.gece_isi_calistir('2026-12-11')$$);
select test.dogrula('ileri tarihli gece işi satırı yazılmadı',
    not exists (select 1 from pdks.gece_isi where islenen_gun > '2026-12-10'));

-- 4) T-17: kilitli aya dosya yüklenemez ---------------------------------------------------------
set local role authenticated;
select test.oturum('dt_ik@ornek.test');
select pdks.ay_kilitle(2026::smallint, 9::smallint, true, 'Test: zorla kilit gerekçesi');
select test.hata('kilitli Eylül''e dosya yüklenemez', '15.09.2026 kilitli bir aya ait; bu güne dosya yüklenemez',
    $$select pdks.dosya_yukle('pdks', 'dt_20260915.csv', '2026-09-15',
        '[{"okuyucu": "DT-PDKS", "kart_no": "DT-K1", "zaman": "2026-09-15T07:55:00+03:00"}]', test.ozet('f'))$$);

-- 5) T-21: hata mesajı girdiyi kısaltır ---------------------------------------------------------
select test.dogrula('1000 karakterlik okuyucu kodu mesajda 40 karakter + "…"',
    (select length(m) < 120 and m like '%' || repeat('X', 40) || '…%'
     from (select test.hata_mesaji($q$select pdks.dosya_yukle('pdks', 'dt_20261209.csv', '2026-12-09',
               jsonb_build_array(jsonb_build_object('okuyucu', repeat('X', 1000), 'kart_no', 'DT-K1',
                                                    'zaman', '2026-12-09T07:55:00+03:00')), test.ozet('9'))$q$) as m) x));
reset role;

do $$ begin raise notice 'TÜM TESTLER GEÇTİ'; end $$;
rollback;
