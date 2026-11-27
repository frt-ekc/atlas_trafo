-- =====================================================================
-- Çalışan, plan, izin ve kart kuralları testleri (20261231140000_calisan_kart_kurallari.sql, T-68, T-75, T-86)
-- Testin kendi sahte verisi (Aralık 2026); örnek veri yüklü olsun olmasın çalışır.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/calisan_kart_kurallari_testi.sql
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

create function test.sor(p_sql text) returns text language plpgsql security definer as $$
declare v text; begin execute p_sql into v; return v; end $$;
create function test.hata_mesaji(p_sql text) returns text language plpgsql as $$
begin
    execute p_sql;
    return null;
exception when others then
    return sqlerrm;
end $$;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
-- Bugün 20 Kasım 2026 kabul edilir.
--   CA01: çalışıyor (giriş 01.01.2025) · CA02: 15.11.2026'da ayrıldı · CA03: 15.12.2026'da işe girecek
--   CAI1, CAI2: İK · CAG1: güvenlik
insert into pdks.departman (ad) values ('CA Üretim'), ('CA İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = case when s like 'CA0%' then 'CA Üretim' else 'CA İdari' end),
       case when s = 'CA03' then date '2026-12-15' else date '2025-01-01' end
from unnest(array['CA01','CA02','CA03','CAI1','CAI2','CAG1']) s;
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('x', 'ca_ik@ornek.test',  'ik',       test.c('CAI1'), '00000000-0000-0000-0000-000000000fa1'),
    ('x', 'ca_ik2@ornek.test', 'ik',       test.c('CAI2'), '00000000-0000-0000-0000-000000000fa2'),
    ('x', 'ca_gv@ornek.test',  'guvenlik', test.c('CAG1'), '00000000-0000-0000-0000-000000000fa3');
insert into pdks.kart (kart_no, calisan_id) values ('CA-K1', test.c('CA01')), ('CA-K2', test.c('CA02'));
insert into pdks.gecici_kart (kart_no) values ('CA-GK1'), ('CA-GK2');
set local pdks.test_bugun = '2026-11-20';
set local role authenticated;
select test.oturum('ca_ik2@ornek.test');
select pdks.isten_cikis_gir(test.c('CA02'), '2026-11-15', 'İstifa');
select test.oturum('ca_ik@ornek.test');

-- 1) T-68: plan ve izin yalnızca çalışma tarihleri içinde ----------------------------------------
select test.hata('ayrılmış çalışana çıkıştan sonraki güne plan girilmez',
    'çalışma tarihleri dışında: 21.11.2026 (işe giriş 01.01.2025, son çalışma günü 15.11.2026)',
    $$select pdks.vardiya_plani_gir(test.c('CA02'), '2026-11-21', (select id from pdks.vardiya_tanim where kod = 'GUNDUZ'))$$);
select test.hata('işe girmemiş çalışana girişten önceki güne plan girilmez',
    'çalışma tarihleri dışında: 14.12.2026 (işe giriş 15.12.2026)',
    $$select pdks.vardiya_plani_gir(test.c('CA03'), '2026-12-14', (select id from pdks.vardiya_tanim where kod = 'GUNDUZ'))$$);
select test.dogrula('işe giriş günü ve sonrasına plan girilir',
    pdks.vardiya_plani_gir(test.c('CA03'), '2026-12-15', (select id from pdks.vardiya_tanim where kod = 'GUNDUZ')) is not null);
select test.hata('ayrılmış çalışana çıkıştan sonra izin girilmez', 'çalışma tarihleri dışında: 20.11.2026',
    $$select pdks.izin_gir(test.c('CA02'), 'yillik', '2026-11-20', '2026-11-25')$$);
select test.hata('işe girmemiş çalışana girişten önce izin girilmez', 'çalışma tarihleri dışında: 01.12.2026',
    $$select pdks.izin_gir(test.c('CA03'), 'yillik', '2026-12-01', '2026-12-05')$$);
select test.hata('girişi kapsayan izin de girilmez (13–16 Aralık)', 'çalışma tarihleri dışında: 13.12.2026',
    $$select pdks.izin_gir(test.c('CA03'), 'yillik', '2026-12-13', '2026-12-16')$$);
select test.hata('ayrılmış çalışana çıkıştan sonra saatlik izin girilmez', 'çalışma tarihleri dışında: 18.11.2026',
    $$select pdks.saatlik_izin_gir(test.c('CA02'), '2026-11-18', test.ts('2026-11-18 10:00'), test.ts('2026-11-18 12:00'), 'mazeret')$$);
select test.dogrula('çalışana çalışma tarihleri içinde izin girilir',
    pdks.izin_gir(test.c('CA01'), 'yillik', '2026-12-21', '2026-12-22') is not null);

-- 2) T-68 / T-75: kart --------------------------------------------------------------------------
select test.hata('ayrılmış çalışana kart tanımlanmaz', 'işten ayrılmış (son çalışma günü 15.11.2026)',
    $$select pdks.kart_tanimla(test.c('CA02'), 'CA-K2B')$$);
select test.hata('olmayan çalışana kart tanımlanmaz (Türkçe)', 'Çalışan bulunamadı',
    $$select pdks.kart_tanimla(-1, 'CA-K9')$$);
select test.hata('başkasındaki kart numarası: kimde olduğu söylenir', 'CA-K1 numaralı kart AdCA01 Örnek (CA01) adına kayıtlı',
    $$select pdks.kart_tanimla(test.c('CA03'), 'ca-k1')$$);
select test.hata('iptal edilmiş kartın numarası: kimde olduğu ve iptal olduğu söylenir', 'CA-K2 numaralı kart AdCA02 Örnek (CA02) adına kayıtlıydı ve iptal edildi',
    $$select pdks.kart_tanimla(test.c('CA03'), 'CA-K2')$$);
select test.hata('geçersiz kart numarası (boşluk / Türkçe harf)', 'Kart numarası',
    $$select pdks.kart_tanimla(test.c('CA03'), 'CA K3')$$);
select pdks.kart_tanimla(test.c('CA03'), '  ca-k3 ');
select test.dogrula('kart numarası büyük harfe çevrilip boşlukları alınarak yazılır (dosyadaki okutmayla eşleşsin)',
    test.sor($q$select string_agg(kart_no, ',') from pdks.kart where calisan_id = $q$ || test.c('CA03')) = 'CA-K3');

-- 3) T-68 / T-86: geçici kart --------------------------------------------------------------------
select test.oturum('ca_gv@ornek.test');
select test.hata('ayrılmış çalışana geçici kart verilmez', 'işten ayrılmış (son çalışma günü 15.11.2026)',
    $$select pdks.gecici_kart_ver((select id from pdks.gecici_kart where kart_no = 'CA-GK1'), test.c('CA02'))$$);
select test.hata('işe başlamamış çalışana geçici kart verilmez', 'henüz işe başlamadı (işe giriş 15.12.2026)',
    $$select pdks.gecici_kart_ver((select id from pdks.gecici_kart where kart_no = 'CA-GK1'), test.c('CA03'))$$);
select test.hata('olmayan geçici kart (Türkçe)', 'Geçici kart bulunamadı',
    $$select pdks.gecici_kart_ver(-1, test.c('CA01'))$$);
select test.hata('olmayan çalışan (Türkçe)', 'Çalışan bulunamadı',
    $$select pdks.gecici_kart_ver((select id from pdks.gecici_kart where kart_no = 'CA-GK1'), -1)$$);
select pdks.gecici_kart_ver((select id from pdks.gecici_kart where kart_no = 'CA-GK1'), test.c('CA01'));
select test.hata('çalışanda açık geçici kart varken ikincisi: hangi kart olduğu söylenir',
    'Bu çalışanda zaten açık bir geçici kart var (CA-GK1',
    $$select pdks.gecici_kart_ver((select id from pdks.gecici_kart where kart_no = 'CA-GK2'), test.c('CA01'))$$);

-- 4) T-86: kart iptal nedeni zorunlu ve listeden ---------------------------------------------------
select test.oturum('ca_ik@ornek.test');
select test.hata('iptal nedeni boş geçilemez', 'İptal nedeni seçilmeli: kayıp, yenilendi, işten çıkış ya da diğer',
    $$select pdks.kart_iptal_et((select id from pdks.kart where kart_no = 'CA-K1'), null)$$);
select test.hata('geçersiz iptal nedeni (Türkçe)', 'İptal nedeni seçilmeli',
    $$select pdks.kart_iptal_et((select id from pdks.kart where kart_no = 'CA-K1'), 'unuttu')$$);
select pdks.kart_iptal_et((select id from pdks.kart where kart_no = 'CA-K1'), 'kayip');
select test.dogrula('geçerli nedenle iptal edilir', (select durum = 'iptal' and iptal_nedeni = 'kayip' from pdks.kart where kart_no = 'CA-K1'));

-- 5) T-75: çalışan ekleme ---------------------------------------------------------------------------
select test.hata('işe giriş 1900 olamaz', 'İşe giriş tarihi',
    $$select pdks.calisan_ekle('CA90', 'Ad', 'Soyad', (select id from pdks.departman where ad = 'CA Üretim')::smallint, '1900-01-01')$$);
select test.hata('işe giriş 2099 olamaz', 'İşe giriş tarihi',
    $$select pdks.calisan_ekle('CA91', 'Ad', 'Soyad', (select id from pdks.departman where ad = 'CA Üretim')::smallint, '2099-01-01')$$);
select test.hata('küçük harfli aynı sicil ikinci çalışan olamaz', 'Bu sicil numarası başka bir çalışanda kayıtlı',
    $$select pdks.calisan_ekle('ca01', 'Ad', 'Soyad', (select id from pdks.departman where ad = 'CA Üretim')::smallint, '2026-12-01')$$);
select test.dogrula('makul tarihle yeni çalışan eklenir',
    pdks.calisan_ekle('CA92', 'Ad', 'Soyad', (select id from pdks.departman where ad = 'CA Üretim')::smallint, '2026-12-14') is not null);
reset role;
select test.hata('veritabanında da büyük/küçük harf farkıyla ikinci sicil olmaz', 'calisan_sicil_buyuk_harf_tekil',
    $$insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
      values ('ca92', 'A', 'B', (select id from pdks.departman where ad = 'CA Üretim'), '2026-12-14')$$);

do $$ begin raise notice 'TÜM TESTLER GEÇTİ'; end $$;
rollback;
