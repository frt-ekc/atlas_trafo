-- =====================================================================
-- Havuz onayında günlük 11 saat sınırı testleri (20261226010000_gunluk_sinir.sql, T-58)
--   İş Kanunu m.63: günlük çalışma 11 saati aşamaz. Plan talebi bunu reddeder.
--   Havuzdaki fiilen yapılmış çalışma reddedilmez (T-56, T-57 ile aynı karar):
--   puantaja girer, gunluk_sinir_asildi işaretlenir, İK'ya uyarı yazılır.
--   Ölçü plan yoluyla aynıdır: net çalışma (mola hariç, T-64; 20261231170000_fazla_mesai_kararlari.sql).
-- Testin kendi sahte verisi (Ekim / Kasım 2026) kullanılır; örnek veri yüklü olsun
-- olmasın çalışır. Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/gunluk_sinir_testi.sql
-- =====================================================================
\pset tuples_only on
\pset format unaligned
begin;
set local pdks.test_bugun = '2026-11-15';
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
-- Karar anında yazılan günlük sınır uyarısı (gece işinin "gunluk:" anahtarlı uyarısı ayrıdır)
create function test.asim(p_sicil text) returns bigint language sql security definer as $$
    select count(*) from pdks.uyari where tur = 'fm_gunluk_sinir_asildi' and calisan_id = test.c(p_sicil)
      and tekillik_anahtari like 'havuz:%' $$;
create function test.ts(p text) returns timestamptz language sql immutable as $$
    select (p::timestamp) at time zone 'Europe/Istanbul' $$;
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
--   GUNDUZ vardiyası 08:00–17:00 = 540 dk brüt (60 dk mola dahil); sınır net 660 dk (11 saat, mola hariç)
--   GS01: 08:00–20:59 → havuz 239, brüt 779 (raporun D2 örneği)
--   GS02: 08:00–20:00 → havuz 180, brüt 720, net 660 (tam sınırda; T-64)
--   GS03: 08:00–20:01 → havuz 181, brüt 721, net 661 (sınırı 1 dk aşar; plan yolunda da 661 reddedilir)
--   GS04: 08:00–20:59 → havuz 239; İK reddeder
--   GS05: Pazar 18 Ekim 08:00–20:30, yazılı onayı yok → tatil çalışması 750 dk
insert into pdks.departman (ad) values ('GS Üretim'), ('GS İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = d), '2025-01-01'
from (values ('GS01', 'GS Üretim'), ('GS02', 'GS Üretim'), ('GS03', 'GS Üretim'), ('GS04', 'GS Üretim'),
             ('GS05', 'GS Üretim'), ('GSA1', 'GS Üretim'), ('GSI1', 'GS İdari')) v(s, d);
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('GS Amir', 'gs_amir@ornek.test', 'amir', test.c('GSA1'), '00000000-0000-0000-0000-0000000006a1'),
    ('GS İK',   'gs_ik@ornek.test',   'ik',   test.c('GSI1'), '00000000-0000-0000-0000-0000000006a2');
update pdks.departman set amir_id = test.k('gs_amir@ornek.test') where ad = 'GS Üretim';
insert into pdks.kart (kart_no, calisan_id)
select 'GS-' || s, test.c(s) from unnest(array['GS01', 'GS02', 'GS03', 'GS04', 'GS05']) s;
insert into pdks.okuyucu (kod, ad, sistem) values ('GS-PDKS', 'GS PDKS', 'pdks');

insert into pdks.fazla_mesai_onayi (calisan_id, yil, imza_tarihi, belge_no, giren_id)
select test.c(s), 2026, '2026-01-02', 'GS-FMO-' || s, test.k('gs_ik@ornek.test')
from unnest(array['GS01', 'GS02', 'GS03', 'GS04']) s;

insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id, giren_id)
select test.c(s), t::date, (select id from pdks.vardiya_tanim where kod = 'GUNDUZ'), test.k('gs_ik@ornek.test')
from (values ('GS01', '2026-10-14'), ('GS02', '2026-10-14'), ('GS03', '2026-10-14'), ('GS04', '2026-10-14'),
             ('GS05', '2026-10-18'), ('GS02', '2026-11-18'), ('GS03', '2026-11-18')) x(s, t);

insert into pdks.aktarim (kaynak, dosya_adi, dosya_ozeti, veri_tarihi)
select 'pdks', 'gs_' || d || '.csv', 'gs-pdks-' || d, d::date
from unnest(array['2026-10-14', '2026-10-18']) d;

insert into pdks.ham_okutma (aktarim_id, okuyucu_id, kart_no, okutma_zamani, yon)
select (select id from pdks.aktarim where dosya_ozeti = 'gs-pdks-' || (z::timestamp)::date),
       (select id from pdks.okuyucu where kod = 'GS-PDKS'), 'GS-' || s, test.ts(z), y
from (values
    ('GS01', '2026-10-14 08:00', 'giris'), ('GS01', '2026-10-14 20:59', 'cikis'),
    ('GS02', '2026-10-14 08:00', 'giris'), ('GS02', '2026-10-14 20:00', 'cikis'),
    ('GS03', '2026-10-14 08:00', 'giris'), ('GS03', '2026-10-14 20:01', 'cikis'),
    ('GS04', '2026-10-14 08:00', 'giris'), ('GS04', '2026-10-14 20:59', 'cikis'),
    ('GS05', '2026-10-18 08:00', 'giris'), ('GS05', '2026-10-18 20:30', 'cikis')) v(s, z, y);

select pdks.gece_isi_calistir('2026-10-14');
select pdks.gece_isi_calistir('2026-10-18');

select test.dogrula('hazırlık: beş kayıt havuzda bekliyor (239 / 180 / 181 / 239 / 750 dk)',
    (test.hv('GS01', '2026-10-14')).dakika = 239 and (test.hv('GS02', '2026-10-14')).dakika = 180
    and (test.hv('GS03', '2026-10-14')).dakika = 181 and (test.hv('GS04', '2026-10-14')).dakika = 239
    and (test.hv('GS05', '2026-10-18')).dakika = 750 and (test.hv('GS05', '2026-10-18')).tur = 'tatil_calismasi'
    and (select count(*) = 5 from pdks.fazla_mesai_inceleme where durum = 'inceleme_bekliyor'
         and calisan_id in (select id from pdks.calisan where sicil_no like 'GS0%')));
select test.dogrula('hazırlık: karar verilmeden işaret "hayır"',
    not (test.hv('GS01', '2026-10-14')).gunluk_sinir_asildi);

-- 1) Sınırı aşan gün onaylanır, ama iz bırakır (T-58) ---------------------------
set local role authenticated;
select test.oturum('gs_ik@ornek.test');
select pdks.fazla_mesai_inceleme_karar((test.hv('GS01', '2026-10-14')).id, true);
reset role;
select test.dogrula('çalışılan süre reddedilmez: GS01 puantaja girdi (çalışma 719, FM50 239)',
    (select durum = 'onaylandi' from test.hv('GS01', '2026-10-14'))
    and (select calisma_dk = 719 and fm50_dk = 239 from test.gk('GS01', '2026-10-14')));
select test.dogrula('T-58: 11 saati aşan gün "günlük sınır aşıldı" olarak işaretlendi',
    (test.hv('GS01', '2026-10-14')).gunluk_sinir_asildi);
select test.dogrula('T-58: onay anında İK''ya bir uyarı yazıldı (net 11 sa 59 dk, sınır 11 sa)',
    test.asim('GS01') = 1
    and exists (select 1 from pdks.uyari where tur = 'fm_gunluk_sinir_asildi'
                and tekillik_anahtari = 'havuz:' || (test.hv('GS01', '2026-10-14')).id
                and mesaj like '%11 sa 59 dk%' and mesaj like '%mola hariç%' and mesaj like '%11 sa%'));

-- 2) Sınır: 660 dk kabul, 661 dk işaretli (plan yoluyla aynı ölçü) --------------------
set local role authenticated;
select test.oturum('gs_ik@ornek.test');
select pdks.fazla_mesai_inceleme_karar((test.hv('GS02', '2026-10-14')).id, true);
select pdks.fazla_mesai_inceleme_karar((test.hv('GS03', '2026-10-14')).id, true);
reset role;
select test.dogrula('tam 11 saat (net 660 dk, brüt 720) sınırı aşmaz: işaret yok, uyarı yok',
    not (test.hv('GS02', '2026-10-14')).gunluk_sinir_asildi and test.asim('GS02') = 0
    and (select calisma_dk = 660 and mola_dk = 60 from test.gk('GS02', '2026-10-14')));
select test.dogrula('11 saat 1 dk (net 661 dk) aşar: işaret ve uyarı var',
    (test.hv('GS03', '2026-10-14')).gunluk_sinir_asildi and test.asim('GS03') = 1);
select test.dogrula('aynı ölçü plan yolunda: 180 dk plan kabul (540 + 180 − 60 mola = 660)',
    (select true from (select pdks.fm_plan_denetle(test.c('GS02'), '2026-11-18',
        (select id from pdks.vardiya_tanim where kod = 'GUNDUZ')::smallint, 180, null)) x));
select test.hata('aynı ölçü plan yolunda: 181 dk plan reddedilir (540 + 181 − 60 = 661)', 'sınır 11 sa',
    format('select pdks.fm_plan_denetle(%s, %L, %s::smallint, 181, null)',
           test.c('GS03'), '2026-11-18', (select id from pdks.vardiya_tanim where kod = 'GUNDUZ')));

-- 3) Ret: işaret ve uyarı yok ------------------------------------------------------
set local role authenticated;
select test.oturum('gs_ik@ornek.test');
select pdks.fazla_mesai_inceleme_karar((test.hv('GS04', '2026-10-14')).id, false, 'Plansız kalış onaylanmadı');
reset role;
select test.dogrula('reddedilen kayıtta işaret yok, onay uyarısı yok; süre puantaja girmedi',
    not (test.hv('GS04', '2026-10-14')).gunluk_sinir_asildi and test.asim('GS04') = 0
    and (select fm50_dk = 0 from test.gk('GS04', '2026-10-14')));
select test.hata('reddedilmiş kayda işaret elle konamaz', 'gunluk_sinir_check',
    format('update pdks.fazla_mesai_inceleme set gunluk_sinir_asildi = true where id = %s',
           (test.hv('GS04', '2026-10-14')).id));

-- 4) Pazar (tatil çalışması) da aynı kurala tabi ----------------------------------------
set local role authenticated;
select test.oturum('gs_ik@ornek.test');
select pdks.fazla_mesai_inceleme_karar((test.hv('GS05', '2026-10-18')).id, true, 'Pazar arıza onarımı');
reset role;
select test.dogrula('Pazar 12 sa 30 dk: FM100 olarak girdi, işaret ve uyarı var (yazılı onaysız işareti de)',
    (select fm100_dk > 0 and calisma_dk + mola_dk = 750 from test.gk('GS05', '2026-10-18'))
    and (test.hv('GS05', '2026-10-18')).gunluk_sinir_asildi
    and (test.hv('GS05', '2026-10-18')).yazili_onaysiz
    and test.asim('GS05') = 1);

-- Karardan sonra işaret değiştirilemez: fazla_mesai_inceleme_kontrol karara bağlanmış kaydı
-- yalnızca karar işleminin içinde güncellemeye izin verir. Bu test tek işlem olduğu için o
-- durum burada sınanamaz; ekranın rolü (authenticated) tabloya yalnızca SELECT yetkisiyle erişir.

-- 5) Kim görür -----------------------------------------------------------------------
set local role authenticated;
select test.oturum('gs_amir@ornek.test');
select test.dogrula('amir kendi bölümünün kayıtlarında işareti görür (ekran etiketi için)',
    (select count(*) filter (where gunluk_sinir_asildi) = 3 from pdks.fazla_mesai_inceleme
     where calisan_id in (select id from pdks.calisan where sicil_no like 'GS0%')));
reset role;

rollback;
