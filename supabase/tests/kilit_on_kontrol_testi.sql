-- =====================================================================
-- Ay kilidi ön kontrolü ve düzeltmesiz kabul edilmiş itiraz testleri (20261231200000_kilit_on_kontrol.sql, T-96, T-52)
-- Testin kendi sahte verisi (Eylül 2026); örnek veri yüklü olsun olmasın çalışır.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/kilit_on_kontrol_testi.sql
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

create function test.gk(p_sicil text, p_gun date) returns pdks.gun_kaydi language sql security definer as $$
    select * from pdks.gun_kaydi where calisan_id = test.c(p_sicil) and is_gunu = p_gun $$;
create function test.engel(p jsonb, p_kod text) returns jsonb language sql immutable as $$
    select e from jsonb_array_elements(p -> 'engeller') e where e ->> 'kod' = p_kod $$;
create temp table ko_sonuc (ad text primary key, sonuc jsonb);
grant all on ko_sonuc to authenticated;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
-- Eylül 2026, bugün 15 Ekim kabul edilir.
--   KO01: 14 Eylül planlı, gece işinden geçmedi (zorla da geçilemez)
--   KO02: 15 Eylül planlı, okutma yok → açık soru (zorla geçilebilir) ve kodsuz gün
--   KO03: 16 Eylül günü var; itirazı kabul edildi ama düzeltme yapılmadı (T-52, bilgi)
--   KO04: 17 Eylül için karar bekleyen fazla mesai talebi (kilit kapatır, bilgi); günü işlendi
insert into pdks.departman (ad) values ('KO Üretim'), ('KO İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = case when s like 'KOI%' then 'KO İdari' else 'KO Üretim' end), '2025-01-01'
from unnest(array['KO01','KO02','KO03','KO04','KOI1','KOI2','KOA1']) s;
update pdks.calisan set departman_id = (select id from pdks.departman where ad = 'KO Üretim') where sicil_no = 'KOA1';
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('x', 'ko_ik1@ornek.test', 'ik',   test.c('KOI1'), '00000000-0000-0000-0000-000000000f11'),
    ('x', 'ko_ik2@ornek.test', 'ik',   test.c('KOI2'), '00000000-0000-0000-0000-000000000f12'),
    ('x', 'ko_amir@ornek.test', 'amir', test.c('KOA1'), '00000000-0000-0000-0000-000000000f13');
update pdks.departman set amir_id = test.k('ko_amir@ornek.test') where ad = 'KO Üretim';
insert into pdks.kart (kart_no, calisan_id) select 'KO-' || s, test.c(s) from unnest(array['KO01','KO02','KO03','KO04']) s;
insert into pdks.okuyucu (kod, ad, sistem) values ('KO-PDKS', 'KO PDKS', 'pdks');
insert into pdks.fazla_mesai_onayi (calisan_id, yil, imza_tarihi, belge_no, giren_id)
values (test.c('KO04'), 2026, '2026-01-02', 'KO-FMO-4', test.k('ko_ik1@ornek.test'));
insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id, giren_id)
select test.c(s), g::date, (select id from pdks.vardiya_tanim where kod = 'GUNDUZ'), test.k('ko_ik1@ornek.test')
from (values ('KO01', '2026-09-14'), ('KO02', '2026-09-15'), ('KO04', '2026-09-17')) v(s, g);
insert into pdks.gun_kaydi (calisan_id, is_gunu, durum, giris_zamani, cikis_zamani, hesap_tamam, calisma_dk)
values (test.c('KO03'), '2026-09-16', 'tamam', test.ts('2026-09-16 08:30'), test.ts('2026-09-16 17:00'), true, 450);
set local pdks.test_bugun = '2026-09-10';
set local role authenticated;
select test.oturum('ko_amir@ornek.test');
select pdks.fazla_mesai_talep_et(test.c('KO04'), '2026-09-17', 60, 'Sevkiyat yetişmeli');
reset role;
insert into pdks.aktarim (kaynak, dosya_adi, dosya_ozeti, veri_tarihi)
select 'pdks', 'ko_' || g || '.csv', 'ko-' || g, g::date from unnest(array['2026-09-15', '2026-09-16', '2026-09-17', '2026-09-18']) g;
insert into pdks.ham_okutma (aktarim_id, okuyucu_id, kart_no, okutma_zamani, yon)
select (select id from pdks.aktarim where dosya_ozeti = 'ko-2026-09-17'), (select id from pdks.okuyucu where kod = 'KO-PDKS'), 'KO-KO04', test.ts('2026-09-17 ' || x.s), x.y
from (values ('08:00', 'giris'), ('17:00', 'cikis')) x(s, y);
set local pdks.test_bugun = '2026-10-15';
select pdks.gece_isi_calistir('2026-09-15');
select pdks.gece_isi_calistir('2026-09-17');
set local role authenticated;
select test.oturum('ko_ik1@ornek.test');
select pdks.itiraz_gir((test.gk('KO03', '2026-09-16')).id, 'Servis geç geldi; 08:00''de fabrikadaydı');
select test.oturum('ko_ik2@ornek.test');
select pdks.itiraz_karar((select id from pdks.itiraz where calisan_id = test.c('KO03')), true, 'Servis kaydı doğruluyor');

-- 1) Ön kontrol bütün engelleri tek seferde verir, hiçbir şeyi değiştirmez ----------------------
insert into ko_sonuc select 'once', pdks.ay_kilit_on_kontrol(2026::smallint, 9::smallint);
reset role;
select test.dogrula('ön kontrol: zorla da kilitlenemez (işlenmemiş planlı gün var), zorlamadan da',
    (select (sonuc ->> 'kilitlenebilir')::boolean = false and (sonuc ->> 'zorlamadan_kilitlenebilir')::boolean = false
     from ko_sonuc where ad = 'once'));
select test.dogrula('ön kontrol: işlenmemiş planlı gün (KO01, 14.09) zorla geçilemez olarak listelendi',
    (select test.engel(sonuc, 'islenmemis_plan_gunu') ->> 'tur' = 'zorla_gecilemez'
            and (test.engel(sonuc, 'islenmemis_plan_gunu') ->> 'sayi')::int = 1
            and test.engel(sonuc, 'islenmemis_plan_gunu') -> 'liste' @> '[{"sicil": "KO01", "gun": "2026-09-14"}]'
     from ko_sonuc where ad = 'once'));
select test.dogrula('ön kontrol: açık soru ve kodsuz kalacak gün (KO02, 15.09) zorla geçilebilir olarak listelendi',
    (select test.engel(sonuc, 'acik_soru') ->> 'tur' = 'zorla_gecilebilir'
            and test.engel(sonuc, 'acik_soru') -> 'liste' @> '[{"sicil": "KO02", "gun": "2026-09-15"}]'
            and test.engel(sonuc, 'kodsuz_gun') -> 'liste' @> '[{"sicil": "KO02", "gun": "2026-09-15"}]'
     from ko_sonuc where ad = 'once'));
select test.dogrula('ön kontrol: bilgi olarak bekleyen FM talebi (KO04) ve düzeltmesiz kabul edilmiş itiraz (KO03, T-52)',
    (select test.engel(sonuc, 'kapanacak_fm_talebi') ->> 'tur' = 'bilgi'
            and test.engel(sonuc, 'kapanacak_fm_talebi') -> 'liste' @> '[{"sicil": "KO04", "gun": "2026-09-17"}]'
            and test.engel(sonuc, 'duzeltmesiz_kabul_itiraz') ->> 'tur' = 'bilgi'
            and test.engel(sonuc, 'duzeltmesiz_kabul_itiraz') -> 'liste' @> '[{"sicil": "KO03", "gun": "2026-09-16"}]'
     from ko_sonuc where ad = 'once'));
select test.dogrula('ön kontrol hiçbir şeyi değiştirmedi: ay açık, talep bekliyor, KO01 günü yok',
    not pdks.donem_kilitli_mi('2026-09-14')
    and (select durum = 'talep' from pdks.fazla_mesai_plani where calisan_id = test.c('KO04'))
    and (test.gk('KO01', '2026-09-14')).id is null);

-- 2) Engel çözülünce kilitlenebilir olur ---------------------------------------------------------
insert into pdks.aktarim (kaynak, dosya_adi, dosya_ozeti, veri_tarihi) values ('pdks', 'ko_2026-09-14.csv', 'ko-2026-09-14', '2026-09-14');
select pdks.gece_isi_calistir('2026-09-14');
set local role authenticated;
select test.oturum('ko_ik1@ornek.test');
insert into ko_sonuc select 'sonra', pdks.ay_kilit_on_kontrol(2026::smallint, 9::smallint);
reset role;
select test.dogrula('14.09 işlenince: zorla kilitlenebilir, zorlamadan hâlâ değil (açık sorular)',
    (select (sonuc ->> 'kilitlenebilir')::boolean and not (sonuc ->> 'zorlamadan_kilitlenebilir')::boolean
            and test.engel(sonuc, 'islenmemis_plan_gunu') is null
     from ko_sonuc where ad = 'sonra'));

-- 3) T-52: kilit özeti düzeltmesiz kabul edilmiş itirazı söyler ----------------------------------
set local role authenticated;
select test.oturum('ko_ik1@ornek.test');
insert into ko_sonuc select 'kilit', pdks.ay_kilitle(2026::smallint, 9::smallint, true, 'Test: zorla kilit gerekçesi');
reset role;
select test.dogrula('kilit özeti: 1 düzeltmesiz kabul edilmiş itiraz, mesajda ve izde',
    (select (sonuc ->> 'duzeltmesiz_kabul_itiraz')::int = 1
            and sonuc ->> 'mesaj' like '%Düzeltmesi yapılmamış 1 kabul edilmiş itiraz%'
     from ko_sonuc where ad = 'kilit')
    and exists (select 1 from pdks.donem_kilit_izi z join pdks.donem d on d.id = z.donem_id
                where d.yil = 2026 and d.ay = 9
                  and z.ozet -> 'duzeltmesiz_kabul_itiraz_listesi' @> '[{"sicil": "KO03", "tarih": "2026-09-16"}]'));
select test.hata('ön kontrolü yalnızca İK çağırır', 'yetkiniz yok',
    $$select test.oturum('ko_amir@ornek.test'); set local role authenticated; select pdks.ay_kilit_on_kontrol(2026::smallint, 10::smallint)$$);
reset role;
select test.dogrula('ay bitmemişse ön kontrol bunu zorla geçilemez engel olarak söyler (Kasım)',
    (select test.engel(pdks.ay_kilit_on_kontrol_ic(2026::smallint, 11::smallint), 'ay_bitmedi') ->> 'tur' = 'zorla_gecilemez'));

do $$ begin raise notice 'TÜM TESTLER GEÇTİ'; end $$;
rollback;
