-- =====================================================================
-- Sonradan onaylanan fazla mesai planı testleri (20261227010000_plan_onayi_hesap.sql, T-61)
--   Amir planı zamanında ister, İK gece işinden SONRA onaylar. Onay günü hemen yeniden
--   hesaplar; havuzda karşılığı kalmayan bekleyen kayıt kapanır, kalan varsa kalanı bekler.
--   Kilitli aya ve havuzdan zaten onaylanmış güne plan onayı verilmez.
-- Testin kendi sahte verisi (Ekim 2026) kullanılır; örnek veri yüklü olsun olmasın çalışır.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/plan_onayi_hesap_testi.sql
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
create function test.gk(p_sicil text, p_gun date) returns pdks.gun_kaydi language sql security definer as $$
    select * from pdks.gun_kaydi where calisan_id = test.c(p_sicil) and is_gunu = p_gun $$;
create function test.hv(p_sicil text, p_gun date) returns pdks.fazla_mesai_inceleme language sql security definer as $$
    select * from pdks.fazla_mesai_inceleme where calisan_id = test.c(p_sicil) and is_gunu = p_gun $$;
create function test.plan(p_sicil text, p_gun date) returns pdks.fazla_mesai_plani language sql security definer as $$
    select * from pdks.fazla_mesai_plani where calisan_id = test.c(p_sicil) and is_gunu = p_gun $$;
create function test.ts(p text) returns timestamptz language sql immutable as $$
    select (p::timestamp) at time zone 'Europe/Istanbul' $$;
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
--   Hepsi 14 Ekim Çarşamba GUNDUZ (08:00–17:00), yazılı onaylı, 08:00–19:00 çalıştı (120 dk fazla).
--   SP01: 120 dk plan, gece işinden sonra onaylanır       → FM50 120, havuz kapanır
--   SP02: 60 dk plan, gece işinden sonra onaylanır        → FM50 60, havuzda kalan 60 dk bekler
--   SP03: 120 dk plan; havuz önce onaylanır               → plan onayı reddedilir (iki kez sayılmaz)
--   SP04: 120 dk plan, İK reddeder                        → gün ve havuz değişmez
--   SP05: 120 dk plan, gece işinden ÖNCE onaylanır        → eskisi gibi: FM50 120, havuz yok
--   SP06: 120 dk plan; Ekim kilitlendikten sonra onay      → reddedilir
insert into pdks.departman (ad) values ('SP Üretim'), ('SP İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = d), '2025-01-01'
from (values ('SP01', 'SP Üretim'), ('SP02', 'SP Üretim'), ('SP03', 'SP Üretim'), ('SP04', 'SP Üretim'),
             ('SP05', 'SP Üretim'), ('SP06', 'SP Üretim'), ('SPA1', 'SP Üretim'), ('SPI1', 'SP İdari')) v(s, d);
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('SP Amir', 'sp_amir@ornek.test', 'amir', test.c('SPA1'), '00000000-0000-0000-0000-0000000007a1'),
    ('SP İK',   'sp_ik@ornek.test',   'ik',   test.c('SPI1'), '00000000-0000-0000-0000-0000000007a2');
update pdks.departman set amir_id = test.k('sp_amir@ornek.test') where ad = 'SP Üretim';
insert into pdks.kart (kart_no, calisan_id)
select 'SP-' || s, test.c(s) from unnest(array['SP01', 'SP02', 'SP03', 'SP04', 'SP05', 'SP06']) s;
insert into pdks.okuyucu (kod, ad, sistem) values ('SP-PDKS', 'SP PDKS', 'pdks');

insert into pdks.fazla_mesai_onayi (calisan_id, yil, imza_tarihi, belge_no, giren_id)
select test.c(s), 2026, '2026-01-02', 'SP-FMO-' || s, test.k('sp_ik@ornek.test')
from unnest(array['SP01', 'SP02', 'SP03', 'SP04', 'SP05', 'SP06']) s;

insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id, giren_id)
select test.c(s), '2026-10-14', (select id from pdks.vardiya_tanim where kod = 'GUNDUZ'), test.k('sp_ik@ornek.test')
from unnest(array['SP01', 'SP02', 'SP03', 'SP04', 'SP05', 'SP06']) s;

-- 13 Ekim: amir talepleri zamanında girer; SP05'inki hemen onaylanır
set local pdks.test_bugun = '2026-10-13';
set local role authenticated;
select test.oturum('sp_amir@ornek.test');
select pdks.fazla_mesai_talep_et(test.c(s), '2026-10-14', d, 'Sevkiyat yetişmeli')
from (values ('SP01', 120), ('SP02', 60), ('SP03', 120), ('SP04', 120), ('SP05', 120), ('SP06', 120)) v(s, d);
select test.oturum('sp_ik@ornek.test');
select pdks.fazla_mesai_karar((test.plan('SP05', '2026-10-14')).id, true);
reset role;

-- 14 Ekim çalışıldı; gece işi çalıştı. Diğer talepler henüz onaylanmadı.
set local pdks.test_bugun = '2026-11-15';
insert into pdks.aktarim (kaynak, dosya_adi, dosya_ozeti, veri_tarihi) values ('pdks', 'sp.csv', 'sp-pdks', '2026-10-14');
insert into pdks.ham_okutma (aktarim_id, okuyucu_id, kart_no, okutma_zamani, yon)
select (select id from pdks.aktarim where dosya_ozeti = 'sp-pdks'), (select id from pdks.okuyucu where kod = 'SP-PDKS'),
       'SP-' || s, test.ts(z), y
from unnest(array['SP01', 'SP02', 'SP03', 'SP04', 'SP05', 'SP06']) s,
     (values ('2026-10-14 08:00', 'giris'), ('2026-10-14 19:00', 'cikis')) v(z, y);
select pdks.gece_isi_calistir('2026-10-14');

select test.dogrula('hazırlık: onaylanmamış planlı günlerde 120 dk havuzda bekliyor, FM yok',
    (select bool_and((test.hv(s, '2026-10-14')).dakika = 120 and (test.hv(s, '2026-10-14')).durum = 'inceleme_bekliyor'
                     and (test.gk(s, '2026-10-14')).fm50_dk = 0)
     from unnest(array['SP01', 'SP02', 'SP03', 'SP04', 'SP06']) s));
select test.dogrula('hazırlık: önceden onaylanan SP05 eskisi gibi FM50 120, havuz yok',
    (test.gk('SP05', '2026-10-14')).fm50_dk = 120 and (test.hv('SP05', '2026-10-14')).id is null);

-- 1) Gece işinden sonra gelen onay günü hemen yeniden hesaplar (T-61) -------------
set local role authenticated;
select test.oturum('sp_ik@ornek.test');
select pdks.fazla_mesai_karar((test.plan('SP01', '2026-10-14')).id, true);
reset role;
select test.dogrula('T-61: plan onayı puantaja hemen yansıdı (çalışma 600, FM50 120)',
    (select calisma_dk = 600 and fm50_dk = 120 and fazla_mesai_dk = 120 from test.gk('SP01', '2026-10-14')));
select test.dogrula('T-61: havuzdaki kayıt plana göre karşılandı ve kapandı (karar gerekmez, ay kilidini durdurmaz)',
    (select durum = 'reddedildi' and karar_veren_id = test.k('sp_ik@ornek.test')
            and karar_aciklama like 'Fazla mesai planı onaylandı%'
     from test.hv('SP01', '2026-10-14')));
select pdks.gun_hesabini_yenile((test.gk('SP01', '2026-10-14')).id);
select test.dogrula('T-61: günün ilgisiz bir sebeple yeniden hesaplanması sonucu değiştirmez',
    (select fm50_dk = 120 from test.gk('SP01', '2026-10-14')));
select test.dogrula('yıllık toplamda süre bir kez sayılır (plan 120, havuz 0)',
    pdks.fm_yillik_toplam(test.c('SP01'), 2026) = 120);

-- 2) Plan sürenin bir kısmını karşılıyorsa kalan havuzda bekler ------------------
set local role authenticated;
select test.oturum('sp_ik@ornek.test');
select pdks.fazla_mesai_karar((test.plan('SP02', '2026-10-14')).id, true);
reset role;
select test.dogrula('60 dk plan: FM50 60 oldu; havuzda kalan 60 dk İK kararı bekliyor',
    (select fm50_dk = 60 from test.gk('SP02', '2026-10-14'))
    and (select durum = 'inceleme_bekliyor' and dakika = 60 from test.hv('SP02', '2026-10-14')));
set local role authenticated;
select test.oturum('sp_ik@ornek.test');
select pdks.fazla_mesai_inceleme_karar((test.hv('SP02', '2026-10-14')).id, true);
reset role;
select test.dogrula('kalan 60 dk havuzdan onaylanınca FM50 120 oldu; yıllık toplam 120',
    (select fm50_dk = 120 from test.gk('SP02', '2026-10-14')) and pdks.fm_yillik_toplam(test.c('SP02'), 2026) = 120);

-- 3) Havuzdan zaten onaylanmış güne plan onayı verilmez -------------------------
set local role authenticated;
select test.oturum('sp_ik@ornek.test');
select pdks.fazla_mesai_inceleme_karar((test.hv('SP03', '2026-10-14')).id, true);
select test.hata('havuzdan onaylanmış güne plan onaylanmaz (süre iki kez sayılırdı)', 'plan ayrıca onaylanamaz',
    format('select pdks.fazla_mesai_karar(%s, true)', (test.plan('SP03', '2026-10-14')).id));
reset role;
select test.dogrula('plan talep olarak kaldı; yıllık toplam 120 (iki kez sayılmadı)',
    (test.plan('SP03', '2026-10-14')).durum = 'talep' and pdks.fm_yillik_toplam(test.c('SP03'), 2026) = 120);
set local role authenticated;
select test.oturum('sp_ik@ornek.test');
select pdks.fazla_mesai_karar((test.plan('SP03', '2026-10-14')).id, false, 'Süre havuzdan onaylandı');
reset role;

-- 4) Ret: hiçbir şey değişmez -------------------------------------------------------
set local role authenticated;
select test.oturum('sp_ik@ornek.test');
select pdks.fazla_mesai_karar((test.plan('SP04', '2026-10-14')).id, false, 'Plan gerekçesi yetersiz');
reset role;
select test.dogrula('reddedilen plan: gün FM 0, havuz kaydı İK kararı bekliyor',
    (select fm50_dk = 0 from test.gk('SP04', '2026-10-14'))
    and (select durum = 'inceleme_bekliyor' and dakika = 120 from test.hv('SP04', '2026-10-14')));

-- 5) Kilitli ay: plan onayı verilmez, havuz yolu kullanılır ----------------------------
set local role authenticated;
select test.oturum('sp_ik@ornek.test');
select pdks.ay_kilitle(2026::smallint, 10::smallint, true);
select test.hata('kilitli aya düşen güne plan onayı verilmez', 'kilitli',
    format('select pdks.fazla_mesai_karar(%s, true)', (test.plan('SP06', '2026-10-14')).id));
select pdks.fazla_mesai_inceleme_karar((test.hv('SP06', '2026-10-14')).id, true);
reset role;
select test.dogrula('kilitli ayda süre havuzdan onaylanır: gün değişmez, FM50 120 sonraki aya fark olur',
    (select fark_satiri and fm50_etki_dk = 120 from test.hv('SP06', '2026-10-14'))
    and (select fm50_dk = 0 from test.gk('SP06', '2026-10-14')));

rollback;
