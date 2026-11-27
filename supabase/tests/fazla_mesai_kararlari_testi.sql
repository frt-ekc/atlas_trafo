-- =====================================================================
-- Fazla mesai kararları testleri (20261231170000_fazla_mesai_kararlari.sql)
--   T-64: günlük 11 saat sınırı net çalışmaya (mola hariç) uygulanır.
--   T-77: havuz eşiğinin altındaki onaysız süre kaybolmaz; gün kaydında ve ay toplamında durur.
--   T-78: hafta tatili / resmî tatil çalışması, yazılı onay olsa da İK onayına bağlıdır.
-- Testin kendi sahte verisi (Ekim / Kasım 2026) kullanılır; örnek veri yüklü olsun
-- olmasın çalışır. Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/fazla_mesai_kararlari_testi.sql
-- =====================================================================
\pset tuples_only on
\pset format unaligned
begin;
set local pdks.test_bugun = '2027-01-15';
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
create function test.gunluk_uyari(p_sicil text) returns bigint language sql security definer as $$
    select count(*) from pdks.uyari where tur = 'fm_gunluk_sinir_asildi' and calisan_id = test.c(p_sicil)
      and tekillik_anahtari like 'gunluk:%' $$;
create function test.ts(p text) returns timestamptz language sql immutable as $$
    select (p::timestamp) at time zone 'Europe/Istanbul' $$;
create function test.gunduz() returns smallint language sql as $$
    select id from pdks.vardiya_tanim where kod = 'GUNDUZ' $$;
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
--   GUNDUZ 08:00–17:00 = 540 dk brüt, 60 dk mola, 480 net. Hepsinin yazılı fazla mesai onayı var.
--   FK01: Çarşamba 14 Ekim 08:00–17:10 → 10 dk eşik altı (T-77, raporun H5 örneği)
--   FK02: Çarşamba 14 Ekim 08:00–20:45 → brüt 765, net 705: günlük sınır uyarısı (705 > 660 + 15)
--   FK03: Çarşamba 14 Ekim 08:00–20:10 → brüt 730, net 670: uyarı yok (eskiden brüt 730 > 675 uyarıydı)
--   FK04: Pazar 18 Ekim 08:00–17:00, planı yok → havuzda, İK onaylar (T-78)
--   FK05: Pazar 18 Ekim 08:00–18:00, İK'nın onayladığı 60 dk plan → günü önceden onaylanmış (T-78)
--   FK06: Pazar 18 Ekim 08:00–17:00, planı yok → havuzda, İK reddeder
insert into pdks.departman (ad) values ('FK Üretim'), ('FK İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = d), '2025-01-01'
from (values ('FK01', 'FK Üretim'), ('FK02', 'FK Üretim'), ('FK03', 'FK Üretim'), ('FK04', 'FK Üretim'),
             ('FK05', 'FK Üretim'), ('FK06', 'FK Üretim'), ('FKA1', 'FK Üretim'),
             ('FKI1', 'FK İdari'), ('FKI2', 'FK İdari')) v(s, d);
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('FK Amir', 'fk_amir@ornek.test', 'amir', test.c('FKA1'), '00000000-0000-0000-0000-0000000007a1'),
    ('FK İK 1', 'fk_ik1@ornek.test',  'ik',   test.c('FKI1'), '00000000-0000-0000-0000-0000000007a2'),
    ('FK İK 2', 'fk_ik2@ornek.test',  'ik',   test.c('FKI2'), '00000000-0000-0000-0000-0000000007a3');
update pdks.departman set amir_id = test.k('fk_amir@ornek.test') where ad = 'FK Üretim';
insert into pdks.kart (kart_no, calisan_id)
select 'FK-' || s, test.c(s) from unnest(array['FK01', 'FK02', 'FK03', 'FK04', 'FK05', 'FK06']) s;
insert into pdks.okuyucu (kod, ad, sistem) values ('FK-PDKS', 'FK PDKS', 'pdks');

insert into pdks.fazla_mesai_onayi (calisan_id, yil, imza_tarihi, belge_no, giren_id)
select test.c(s), 2026, '2026-01-02', 'FK-FMO-' || s, test.k('fk_ik1@ornek.test')
from unnest(array['FK01', 'FK02', 'FK03', 'FK04', 'FK05', 'FK06']) s;

insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id, giren_id)
select test.c(s), t::date, test.gunduz(), test.k('fk_ik1@ornek.test')
from (values ('FK01', '2026-10-14'), ('FK02', '2026-10-14'), ('FK03', '2026-10-14'),
             ('FK04', '2026-10-18'), ('FK05', '2026-10-18'), ('FK06', '2026-10-18')) x(s, t);

-- FK05'in Pazar günü için İK'nın onayladığı 60 dk fazla mesai planı (talep eden ve onaylayan ayrı kişi)
insert into pdks.fazla_mesai_plani (calisan_id, is_gunu, planli_dk, gerekce, talep_eden_id)
values (test.c('FK05'), '2026-10-18', 60, 'Pazar sevkiyatı', test.k('fk_ik1@ornek.test'));
update pdks.fazla_mesai_plani set durum = 'onaylandi', karar_veren_id = test.k('fk_ik2@ornek.test')
where calisan_id = test.c('FK05') and is_gunu = '2026-10-18';

insert into pdks.aktarim (kaynak, dosya_adi, dosya_ozeti, veri_tarihi)
select 'pdks', 'fk_' || d || '.csv', 'fk-pdks-' || d, d::date
from unnest(array['2026-10-14', '2026-10-18']) d;

insert into pdks.ham_okutma (aktarim_id, okuyucu_id, kart_no, okutma_zamani, yon)
select (select id from pdks.aktarim where dosya_ozeti = 'fk-pdks-' || (z::timestamp)::date),
       (select id from pdks.okuyucu where kod = 'FK-PDKS'), 'FK-' || s, test.ts(z), y
from (values
    ('FK01', '2026-10-14 08:00', 'giris'), ('FK01', '2026-10-14 17:10', 'cikis'),
    ('FK02', '2026-10-14 08:00', 'giris'), ('FK02', '2026-10-14 20:45', 'cikis'),
    ('FK03', '2026-10-14 08:00', 'giris'), ('FK03', '2026-10-14 20:10', 'cikis'),
    ('FK04', '2026-10-18 08:00', 'giris'), ('FK04', '2026-10-18 17:00', 'cikis'),
    ('FK05', '2026-10-18 08:00', 'giris'), ('FK05', '2026-10-18 18:00', 'cikis'),
    ('FK06', '2026-10-18 08:00', 'giris'), ('FK06', '2026-10-18 17:00', 'cikis')) v(s, z, y);

select pdks.gece_isi_calistir('2026-10-14');
select pdks.gece_isi_calistir('2026-10-18');

-- 1) T-64: 11 saat net çalışmadır ---------------------------------------------------
select test.dogrula('T-64 plan yolu: GÜNDÜZ''e 180 dk plan kabul (540 + 180 − 60 mola = 660 net)',
    (select true from (select pdks.fm_plan_denetle(test.c('FK01'), '2026-11-18', test.gunduz(), 180, null)) x));
select test.hata('T-64 plan yolu: 181 dk plan reddedilir (net 661) ve mesaj net süreyi söyler', 'net çalışma süresi (mola hariç) 11 sa 1 dk',
    format('select pdks.fm_plan_denetle(%s, %L, %s::smallint, 181, null)', test.c('FK01'), '2026-11-18', test.gunduz()));
select test.dogrula('T-64 gece uyarısı: net 705 dk sınırı (660 + 15 dk eşik) aşar, mesaj net süreyi yazar',
    test.gunluk_uyari('FK02') = 1
    and exists (select 1 from pdks.uyari where tur = 'fm_gunluk_sinir_asildi' and calisan_id = test.c('FK02')
                and mesaj like '%11 sa 45 dk net%' and mesaj like '%mola hariç%'));
select test.dogrula('T-64 gece uyarısı: brüt 730 / net 670 dk uyarı değil (eskiden brüt ölçüyle uyarıydı)',
    test.gunluk_uyari('FK03') = 0);

set local role authenticated;
select test.oturum('fk_ik1@ornek.test');
select pdks.fazla_mesai_inceleme_karar((test.hv('FK03', '2026-10-14')).id, true);
reset role;
select test.dogrula('T-64 havuz onayı: net 670 dk onaylanınca "günlük sınır aşıldı" işaretlenir (670 > 660)',
    (select calisma_dk = 670 from test.gk('FK03', '2026-10-14'))
    and (test.hv('FK03', '2026-10-14')).gunluk_sinir_asildi
    and exists (select 1 from pdks.uyari where tur = 'fm_gunluk_sinir_asildi'
                and tekillik_anahtari = 'havuz:' || (test.hv('FK03', '2026-10-14')).id
                and mesaj like '%net çalışma (mola hariç)%'));

-- 2) T-77: eşik altı süre ----------------------------------------------------------
select test.dogrula('T-77: 10 dk eşik altı kalış havuza düşmez, fazla mesai olmaz, gün kaydında durur',
    (test.hv('FK01', '2026-10-14')).id is null
    and (select fazla_mesai_dk = 0 and calisma_dk = 480 and esik_alti_dk = 10 from test.gk('FK01', '2026-10-14')));
select test.dogrula('T-77: eşiği aşan süre eşik altı sayılmaz, havuza düşer (FK02 225 dk)',
    (select esik_alti_dk = 0 from test.gk('FK02', '2026-10-14')) and (test.hv('FK02', '2026-10-14')).dakika = 225);
select test.dogrula('T-77: eşik altı süre canlı puantajda ay toplamı olarak görünür',
    (select esik_alti_dk = 10 from pdks.v_puantaj_canli where calisan_id = test.c('FK01') and yil = 2026 and ay = 10));
update pdks.gun_kaydi set esik_alti_dk = 99 where id = (test.gk('FK01', '2026-10-14')).id;
select test.dogrula('T-77: eşik altı süre elle değiştirilemez (tetikleyici eski değeri korur)',
    (test.gk('FK01', '2026-10-14')).esik_alti_dk = 10);
select test.hata('T-77: eksi değer girilemez', 'gun_kaydi_esik_alti_dk_check',
    $$alter table pdks.gun_kaydi disable trigger gun_kaydi_esik_alti;
      update pdks.gun_kaydi set esik_alti_dk = -1 where id = (test.gk('FK01', '2026-10-14')).id$$);
alter table pdks.gun_kaydi enable trigger gun_kaydi_esik_alti;

-- 3) T-78: tatil çalışması İK onayına bağlı -------------------------------------------
select test.dogrula('T-78: yazılı onaylı Pazar çalışması (planı yok) puantaja girmedi, havuzda İK kararı bekliyor',
    (select fm100_dk = 0 and calisma_dk = 0 from test.gk('FK04', '2026-10-18'))
    and (select tur = 'tatil_calismasi' and dakika = 540 and durum = 'inceleme_bekliyor' from test.hv('FK04', '2026-10-18')));
select test.dogrula('T-78: İK''nın onayladığı plan günü önceden onaylar: vardiya + 60 dk plan FM100 (540 net), havuz yok',
    (select fm100_dk = 540 and calisma_dk = 540 and mola_dk = 60 from test.gk('FK05', '2026-10-18'))
    and (test.hv('FK05', '2026-10-18')).id is null);

set local role authenticated;
select test.oturum('fk_amir@ornek.test');
select test.hata('T-78: amir tatil çalışmasına karar veremez', 'yetkiniz yok',
    format('select pdks.fazla_mesai_inceleme_karar(%s, true)', (test.hv('FK04', '2026-10-18')).id));
select test.oturum('fk_ik1@ornek.test');
select pdks.fazla_mesai_inceleme_karar((test.hv('FK04', '2026-10-18')).id, true);
select pdks.fazla_mesai_inceleme_karar((test.hv('FK06', '2026-10-18')).id, false, 'Pazar çalışması istenmemişti');
reset role;
select test.dogrula('T-78: İK onayıyla Pazar çalışması FM100 oldu (480 net) ve yıllık toplama girdi',
    (select fm100_dk = 480 and calisma_dk = 480 from test.gk('FK04', '2026-10-18'))
    and (select fm100_etki_dk = 480 and not yazili_onaysiz from test.hv('FK04', '2026-10-18'))
    and pdks.fm_yillik_toplam(test.c('FK04'), 2026) = 480);
select test.dogrula('T-78: İK reddedince yazılı onay olsa da Pazar çalışması puantaja girmez',
    (select fm100_dk = 0 and calisma_dk = 0 from test.gk('FK06', '2026-10-18'))
    and pdks.fm_yillik_toplam(test.c('FK06'), 2026) = 0);

-- 4) T-77: kilitli puantaj satırı -------------------------------------------------
set local role authenticated;
select test.oturum('fk_ik1@ornek.test');
select pdks.ay_kilitle(2026::smallint, 10::smallint, true, 'Test: zorla kilit gerekçesi');
reset role;
select test.dogrula('T-77: kilitli puantajın normal satırında eşik altı ay toplamı (FK01 10 dk), fazla mesaiye eklenmedi',
    (select esik_alti_dk = 10 and fazla_mesai_dk = 0 from pdks.puantaj_satiri s join pdks.donem d on d.id = s.donem_id
     where s.calisan_id = test.c('FK01') and d.yil = 2026 and d.ay = 10 and s.satir_turu = 'normal'));

select test.dogrula('yeni tetikleyici fonksiyonu uygulamaya kapalı',
    not has_function_privilege('authenticated', 'pdks.gun_kaydi_esik_alti()', 'execute')
    and not has_function_privilege('anon', 'pdks.gun_kaydi_esik_alti()', 'execute'));

do $$ begin raise notice 'FAZLA MESAİ KARARLARI TESTLERİ GEÇTİ'; end $$;
rollback;
