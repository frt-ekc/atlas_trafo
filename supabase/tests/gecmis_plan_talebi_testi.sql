-- =====================================================================
-- Geçmiş güne fazla mesai planı talebi testleri (20261228010000_gecmis_plan_talebi.sql, T-76)
--   "Planlı fazla mesai" çalışmadan önce verilen karardır. Talep, girildiği gün (İstanbul)
--   bugün ya da sonrası için olmalıdır. Geçmiş günün çalışması havuzdan (İK incelemesi) gelir.
--   Zamanında girilmiş talep, gün geçtikten sonra da onaylanabilir (T-61).
-- Testin kendi sahte verisi (Ekim 2026) kullanılır; örnek veri yüklü olsun olmasın çalışır.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/gecmis_plan_talebi_testi.sql
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
create function test.plan_sayisi(p_sicil text, p_gun date) returns bigint language sql security definer as $$
    select count(*) from pdks.fazla_mesai_plani where calisan_id = test.c(p_sicil) and is_gunu = p_gun $$;
create function test.plan(p_sicil text, p_gun date) returns pdks.fazla_mesai_plani language sql security definer as $$
    select * from pdks.fazla_mesai_plani where calisan_id = test.c(p_sicil) and is_gunu = p_gun $$;
create function test.gk(p_sicil text, p_gun date) returns pdks.gun_kaydi language sql security definer as $$
    select * from pdks.gun_kaydi where calisan_id = test.c(p_sicil) and is_gunu = p_gun $$;
create function test.ts(p text) returns timestamptz language sql immutable as $$
    select (p::timestamp) at time zone 'Europe/Istanbul' $$;
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
--   Bugün 14 Ekim 2026 Çarşamba kabul edilir. GP01 ve GP02 yazılı onaylı, 13–15 Ekim GUNDUZ.
insert into pdks.departman (ad) values ('GP Üretim'), ('GP İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = d), '2025-01-01'
from (values ('GP01', 'GP Üretim'), ('GP02', 'GP Üretim'), ('GPA1', 'GP Üretim'), ('GPI1', 'GP İdari')) v(s, d);
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('GP Amir', 'gp_amir@ornek.test', 'amir', test.c('GPA1'), '00000000-0000-0000-0000-0000000008a1'),
    ('GP İK',   'gp_ik@ornek.test',   'ik',   test.c('GPI1'), '00000000-0000-0000-0000-0000000008a2');
update pdks.departman set amir_id = test.k('gp_amir@ornek.test') where ad = 'GP Üretim';
insert into pdks.kart (kart_no, calisan_id) values ('GP-GP01', test.c('GP01')), ('GP-GP02', test.c('GP02'));
insert into pdks.okuyucu (kod, ad, sistem) values ('GP-PDKS', 'GP PDKS', 'pdks');
insert into pdks.fazla_mesai_onayi (calisan_id, yil, imza_tarihi, belge_no, giren_id)
select test.c(s), 2026, '2026-01-02', 'GP-FMO-' || s, test.k('gp_ik@ornek.test') from unnest(array['GP01', 'GP02']) s;
insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id, giren_id)
select test.c(s), t::date, (select id from pdks.vardiya_tanim where kod = 'GUNDUZ'), test.k('gp_ik@ornek.test')
from unnest(array['GP01', 'GP02']) s, unnest(array['2026-10-13', '2026-10-14', '2026-10-15']) t;

set local pdks.test_bugun = '2026-10-14';

-- 1) Geçmiş güne talep reddedilir (T-76) ---------------------------------------------
set local role authenticated;
select test.oturum('gp_amir@ornek.test');
select test.hata('T-76: amir dünkü güne fazla mesai planı talep edemez', 'Geçmiş bir güne fazla mesai planı girilemez',
    format('select pdks.fazla_mesai_talep_et(%s, %L, 120, %L)', test.c('GP01'), '2026-10-13', 'Dün kaldı'));
select test.oturum('gp_ik@ornek.test');
select test.hata('T-76: İK de dünkü güne talep giremez (havuz yolu kullanılır)', 'onaysız fazla mesai listesinden',
    format('select pdks.fazla_mesai_talep_et(%s, %L, 120, %L)', test.c('GP02'), '2026-10-13', 'Dün kaldı'));
reset role;
select test.dogrula('reddedilen talepler kayıt bırakmadı',
    test.plan_sayisi('GP01', '2026-10-13') = 0 and test.plan_sayisi('GP02', '2026-10-13') = 0);

-- 2) Bugün ve sonrası serbest ------------------------------------------------------------
set local role authenticated;
select test.oturum('gp_amir@ornek.test');
select test.dogrula('bugüne talep girilebilir ("bugün 2 saat daha kal")',
    pdks.fazla_mesai_talep_et(test.c('GP01'), '2026-10-14', 120, 'Sevkiyat yetişmeli') is not null);
select test.dogrula('yarına talep girilebilir',
    pdks.fazla_mesai_talep_et(test.c('GP02'), '2026-10-15', 60, 'Sayım') is not null);
reset role;

-- 3) Zamanında girilen talep, gün geçtikten sonra da onaylanır (T-61 bozulmaz) -------------
insert into pdks.aktarim (kaynak, dosya_adi, dosya_ozeti, veri_tarihi) values ('pdks', 'gp.csv', 'gp-pdks', '2026-10-14');
insert into pdks.ham_okutma (aktarim_id, okuyucu_id, kart_no, okutma_zamani, yon)
select (select id from pdks.aktarim where dosya_ozeti = 'gp-pdks'), (select id from pdks.okuyucu where kod = 'GP-PDKS'),
       'GP-GP01', test.ts(z), y
from (values ('2026-10-14 08:00', 'giris'), ('2026-10-14 19:00', 'cikis')) v(z, y);
set local pdks.test_bugun = '2026-10-16';
select pdks.gece_isi_calistir('2026-10-14');
set local role authenticated;
select test.oturum('gp_ik@ornek.test');
select pdks.fazla_mesai_karar((test.plan('GP01', '2026-10-14')).id, true);
reset role;
select test.dogrula('14 Ekim''de girilen talep 16 Ekim''de onaylandı; gün FM50 120 oldu',
    (test.plan('GP01', '2026-10-14')).durum = 'onaylandi' and (test.gk('GP01', '2026-10-14')).fm50_dk = 120);

-- 4) Gün geçince aynı güne yeni talep artık girilemez ---------------------------------------
set local role authenticated;
select test.oturum('gp_amir@ornek.test');
select test.hata('16 Ekim''de, 15 Ekim için yeni talep girilemez', 'Geçmiş bir güne fazla mesai planı girilemez',
    format('select pdks.fazla_mesai_talep_et(%s, %L, 60, %L)', test.c('GP01'), '2026-10-15', 'Unutuldu'));
reset role;

rollback;
