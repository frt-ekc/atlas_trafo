-- =====================================================================
-- İtiraz ve fazla mesai kararı kuralları testleri (20261231160000_itiraz_kurallari.sql, T-15, T-16, T-51, T-69)
-- Testin kendi sahte verisi (Kasım 2026); örnek veri yüklü olsun olmasın çalışır.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/itiraz_kurallari_testi.sql
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
create function test.hv(p_sicil text, p_gun date) returns pdks.fazla_mesai_inceleme language sql security definer as $$
    select * from pdks.fazla_mesai_inceleme where calisan_id = test.c(p_sicil) and is_gunu = p_gun $$;
create function test.kilit(p_yil int, p_ay int) returns jsonb language sql security definer as $$
    select z.ozet from pdks.donem_kilit_izi z join pdks.donem d on d.id = z.donem_id
    where d.yil = p_yil and d.ay = p_ay order by z.kilit_zamani desc limit 1 $$;
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

create function test.gk(p_sicil text, p_gun date) returns pdks.gun_kaydi language sql security definer as $$
    select * from pdks.gun_kaydi where calisan_id = test.c(p_sicil) and is_gunu = p_gun $$;
create function test.itiraz(p_sicil text, p_gun date) returns pdks.itiraz language sql security definer as $$
    select i.* from pdks.itiraz i join pdks.gun_kaydi g on g.id = i.gun_kaydi_id
    where g.calisan_id = test.c(p_sicil) and g.is_gunu = p_gun order by i.id limit 1 $$;
create temp table it_sonuc (ad text primary key, sonuc jsonb);
grant all on it_sonuc to authenticated;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
-- Bugün 20 Kasım 2026.
--   IT01: 10 Kasım (çalıştı) ve 18 Kasım (soru bekliyor) günleri var; 15 Kasım'da işten çıkar.
--   IT02: 12 Kasım günü (itiraz için) · ITI2'nin (İK müdürü) de 12 Kasım günü var.
--   ITI1: İK uzmanı · ITI2: İK müdürü · ITA1: amir
insert into pdks.departman (ad) values ('IT Üretim'), ('IT İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = case when s like 'IT0%' then 'IT Üretim' else 'IT İdari' end), '2025-01-01'
from unnest(array['IT01','IT02','ITI1','ITI2','ITA1']) s;
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('x', 'it_ik1@ornek.test',  'ik',   test.c('ITI1'), '00000000-0000-0000-0000-000000000fc1'),
    ('x', 'it_ik2@ornek.test',  'ik',   test.c('ITI2'), '00000000-0000-0000-0000-000000000fc2'),
    ('x', 'it_amir@ornek.test', 'amir', test.c('ITA1'), '00000000-0000-0000-0000-000000000fc3');
update pdks.departman set amir_id = test.k('it_amir@ornek.test') where ad = 'IT Üretim';
insert into pdks.gun_kaydi (calisan_id, is_gunu, durum, giris_zamani, cikis_zamani, hesap_tamam, calisma_dk)
values (test.c('IT01'), '2026-11-10', 'tamam', test.ts('2026-11-10 08:00'), test.ts('2026-11-10 17:00'), true, 480),
       (test.c('IT01'), '2026-11-18', 'soru_bekliyor', null, null, false, null),
       (test.c('IT02'), '2026-11-12', 'tamam', test.ts('2026-11-12 08:00'), test.ts('2026-11-12 17:00'), true, 480),
       (test.c('ITI2'), '2026-11-12', 'tamam', test.ts('2026-11-12 08:00'), test.ts('2026-11-12 17:00'), true, 480);
insert into pdks.fazla_mesai_onayi (calisan_id, yil, imza_tarihi, belge_no, giren_id)
values (test.c('IT02'), 2026, '2026-01-02', 'IT-FMO-2', test.k('it_ik2@ornek.test'));
insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id, giren_id)
values (test.c('IT02'), '2026-11-25', (select id from pdks.vardiya_tanim where kod = 'GUNDUZ'), test.k('it_ik2@ornek.test'));
set local pdks.test_bugun = '2026-11-20';

-- 1) T-51: aynı güne ikinci açık itiraz girilmez -----------------------------------------------
set local role authenticated;
select test.oturum('it_amir@ornek.test');
select pdks.itiraz_gir((test.gk('IT02', '2026-11-12')).id, 'Servis geç geldi, 07:50''de fabrikadaydı');
select test.oturum('it_ik1@ornek.test');
select test.hata('aynı güne ikinci açık itiraz girilmez (Türkçe, ilk itirazın numarasıyla)', 'Bu güne ait açık bir itiraz var',
    $$select pdks.itiraz_gir((test.gk('IT02', '2026-11-12')).id, 'Aynı konu, ikinci kez')$$);
select pdks.itiraz_karar((test.itiraz('IT02', '2026-11-12')).id, false, 'Servis kaydı geç gelişi doğrulamıyor');
select test.dogrula('karara bağlanan itirazdan sonra aynı güne yeni itiraz girilebilir',
    pdks.itiraz_gir((test.gk('IT02', '2026-11-12')).id, 'Yeni kanıt: kapı kaydı') is not null);

-- 2) T-15: İK kendi gününe ait itirazı incelemeye alamaz ------------------------------------------
select pdks.itiraz_gir((test.gk('ITI2', '2026-11-12')).id, 'İK müdürünün günü için itiraz');
select test.oturum('it_ik2@ornek.test');
select test.hata('İK müdürü kendi gününün itirazını incelemeye alamaz', 'Görevler ayrılığı',
    $$select pdks.itiraz_incelemeye_al((test.itiraz('ITI2', '2026-11-12')).id)$$);
select test.oturum('it_ik1@ornek.test');
select pdks.itiraz_incelemeye_al((test.itiraz('ITI2', '2026-11-12')).id);
select test.dogrula('başka İK incelemeye alabilir', (test.itiraz('ITI2', '2026-11-12')).durum = 'inceleniyor');

-- 3) T-69: işten çıkış çıkış sonrası günlerin açık itirazlarını kapatır; o günlere itiraz girilmez ---
select pdks.itiraz_gir((test.gk('IT01', '2026-11-10')).id, 'Çıkıştan önceki gün için itiraz');
select pdks.itiraz_gir((test.gk('IT01', '2026-11-18')).id, 'Çıkıştan sonraki gün için itiraz');
insert into it_sonuc select 'cikis', pdks.isten_cikis_gir(test.c('IT01'), '2026-11-15', 'İstifa');
select test.dogrula('çıkıştan sonraki günün itirazı kapandı (red, nedeni işten çıkış), sonuç sayıyor',
    (select durum = 'red' and karar_aciklama like 'İşten çıkış (15.11.2026)%' from test.itiraz('IT01', '2026-11-18'))
    and (select (sonuc ->> 'kapatilan_itiraz')::int = 1 from it_sonuc where ad = 'cikis'));
select test.dogrula('çıkıştan önceki günün itirazı açık kaldı (normal karara bağlanır)',
    (test.itiraz('IT01', '2026-11-10')).durum = 'acik');
select test.hata('çıkıştan sonraki güne yeni itiraz girilmez', 'çalışma tarihleri dışında: 18.11.2026',
    $$select pdks.itiraz_gir((test.gk('IT01', '2026-11-18')).id, 'Tekrar deneme')$$);

-- 4) T-16: talebi giren kendi talebini onaylayamaz, Türkçe mesaj ---------------------------------
select pdks.fazla_mesai_talep_et(test.c('IT02'), '2026-11-25', 60, 'Sevkiyat yetişmeli');
select test.hata('talebi giren İK kendi talebini onaylayamaz (Türkçe)', 'Görevler ayrılığı: kendi girdiğiniz fazla mesai talebine karar veremezsiniz',
    $$select pdks.fazla_mesai_karar((select id from pdks.fazla_mesai_plani where calisan_id = test.c('IT02') and is_gunu = '2026-11-25'), true)$$);
select test.oturum('it_ik2@ornek.test');
select pdks.fazla_mesai_karar((select id from pdks.fazla_mesai_plani where calisan_id = test.c('IT02') and is_gunu = '2026-11-25'), true);
reset role;
select test.dogrula('başka İK onaylayabilir',
    (select durum = 'onaylandi' from pdks.fazla_mesai_plani where calisan_id = test.c('IT02') and is_gunu = '2026-11-25'));

do $$ begin raise notice 'TÜM TESTLER GEÇTİ'; end $$;
rollback;
