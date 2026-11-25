-- =====================================================================
-- İşten çıkışta okutma denetimi testleri (20261219010000_cikis_okutma.sql, T-65)
-- Testin kendi sahte verisi (Ekim 2026); gece işi hiç çalışmaz (günler işlenmemiştir).
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/cikis_okutma_testi.sql
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
create function test.izin(p_sicil text) returns bigint language sql security definer as $$
    select id from pdks.izin where calisan_id = test.c(p_sicil) order by id desc limit 1 $$;
create function test.ts(p text) returns timestamptz language sql immutable as $$
    select (p::timestamp) at time zone 'Europe/Istanbul' $$;
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
--   CO01: 15 Ekim planlı, işlenmemiş okutma     CO02: 17 Ekim Cumartesi plansız okutma
--   CO03: 14 Ekim gece vardiyası, 15'inde 06:05 çıkış     CO04: aynı, ama 15'inde akşam yeniden giriş
--   CO05: plansız gün, gece yarısından hemen önce / sonra     CO06: iade edilmiş geçici kart
--   CO07: kartı 13'ünde iptal, 15'inde başkası okutmuş     CO08: 15 Ekim 00-08 vardiyası, 14'ünde 23:50 giriş
--   CO09: onay bekleyen gece planı     CO10: reddedilmiş gece planı     CO11: gündüz vardiyası, 00:30 okutma
insert into pdks.departman (ad) values ('CO Üretim'), ('CO İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = case when s in ('COI1', 'COG1') then 'CO İdari' else 'CO Üretim' end), '2025-01-01'
from unnest(array['CO01','CO02','CO03','CO04','CO05','CO06','CO07','CO08','CO09','CO10','CO11','COI1','COG1']) s;
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('CO İK', 'co_ik@ornek.test', 'ik', test.c('COI1'), '00000000-0000-0000-0000-0000000000e1'),
    ('CO Güvenlik', 'co_guv@ornek.test', 'guvenlik', test.c('COG1'), null);
insert into pdks.kart (kart_no, calisan_id)
select 'CO-' || substr(s, 3), test.c(s)
from unnest(array['CO01','CO02','CO03','CO04','CO05','CO06','CO08','CO09','CO10','CO11']) s;
insert into pdks.kart (kart_no, calisan_id, durum, iptal_nedeni, iptal_zamani)
values ('CO-07', test.c('CO07'), 'iptal', 'kayip', test.ts('2026-10-13 09:00'));
insert into pdks.gecici_kart (kart_no) values ('CO-GK1');
insert into pdks.gecici_kart_zimmet (gecici_kart_id, calisan_id, verilis_zamani, veren_id)
values ((select id from pdks.gecici_kart where kart_no = 'CO-GK1'), test.c('CO06'),
        test.ts('2026-10-15 07:30'), test.k('co_guv@ornek.test'));
update pdks.gecici_kart_zimmet set iade_zamani = test.ts('2026-10-15 17:30'), iade_alan_id = test.k('co_guv@ornek.test')
where calisan_id = test.c('CO06');
insert into pdks.okuyucu (kod, ad, sistem) values ('CO-PDKS', 'CO PDKS', 'pdks');

insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id, giren_id)
select test.c(s), g::date, (select id from pdks.vardiya_tanim where kod = v), test.k('co_ik@ornek.test')
from (values ('CO01', '2026-10-14', 'GUNDUZ'), ('CO01', '2026-10-15', 'GUNDUZ'), ('CO02', '2026-10-16', 'GUNDUZ'),
             ('CO03', '2026-10-14', 'V3'), ('CO04', '2026-10-14', 'V3'),
             ('CO08', '2026-10-15', 'GECE_8'), ('CO09', '2026-10-14', 'V3'), ('CO10', '2026-10-14', 'V3'),
             ('CO11', '2026-10-14', 'GUNDUZ')) t(s, g, v);
update pdks.vardiya_plani set ik_onay_durumu = 'bekliyor'   where calisan_id = test.c('CO09');
update pdks.vardiya_plani set ik_onay_durumu = 'reddedildi' where calisan_id = test.c('CO10');

insert into pdks.aktarim (kaynak, dosya_adi, dosya_ozeti, veri_tarihi)
values ('pdks', 'co.csv', 'co-pdks', '2026-10-17');
insert into pdks.ham_okutma (aktarim_id, okuyucu_id, kart_no, okutma_zamani, yon)
select (select id from pdks.aktarim where dosya_ozeti = 'co-pdks'),
       (select id from pdks.okuyucu where kod = 'CO-PDKS'), k, test.ts(z), y
from (values ('CO-01', '2026-10-14 07:55', 'giris'), ('CO-01', '2026-10-14 17:02', 'cikis'),
             ('CO-01', '2026-10-15 07:56', 'giris'), ('CO-01', '2026-10-15 17:01', 'cikis'),
             ('CO-02', '2026-10-17 08:00', 'giris'), ('CO-02', '2026-10-17 13:00', 'cikis'),
             ('CO-03', '2026-10-14 21:50', 'giris'), ('CO-03', '2026-10-15 06:05', 'cikis'),
             ('CO-04', '2026-10-14 21:50', 'giris'), ('CO-04', '2026-10-15 06:05', 'cikis'),
             ('CO-04', '2026-10-15 21:52', 'giris'),
             ('CO-05', '2026-10-14 23:59:59', 'cikis'), ('CO-05', '2026-10-16 00:00:00', 'giris'),
             ('CO-GK1', '2026-10-15 07:50', 'giris'), ('CO-GK1', '2026-10-15 17:05', 'cikis'),
             ('CO-GK1', '2026-10-16 08:00', 'giris'),   -- iadeden sonra: CO06'ya ait değil
             ('CO-07', '2026-10-15 08:00', 'giris'),
             ('CO-08', '2026-10-14 23:50', 'giris'),
             ('CO-09', '2026-10-15 06:05', 'cikis'), ('CO-10', '2026-10-15 06:05', 'cikis'),
             ('CO-11', '2026-10-15 00:30', 'cikis')) v(k, z, y);

select test.dogrula('hazırlık: hiçbir gün işlenmemiş',
    not exists (select 1 from pdks.gun_kaydi g join pdks.calisan c on c.id = g.calisan_id where c.sicil_no like 'CO%'));

-- Oturum saat dilimi UTC: sınırlar yine İstanbul saatiyle hesaplanmalı
set local timezone = 'UTC';
set local role authenticated;
select test.oturum('co_ik@ornek.test');

-- 1) Reddedilenler ------------------------------------------------------------
select test.hata('işlenmemiş günde okutma varken çıkış reddedilir; mesaj okutmayı İstanbul saatiyle verir',
    'kart okutması var (15.10.2026 07:56)', $$select pdks.isten_cikis_gir(test.c('CO01'), '2026-10-14')$$);
select test.hata('plansız Cumartesi okutması varken çıkış reddedilir', 'kart okutması var (17.10.2026 08:00)',
    $$select pdks.isten_cikis_gir(test.c('CO02'), '2026-10-16')$$);
select test.hata('gece vardiyasından sonraki akşam yeniden gelen: reddedilir', '15.10.2026 21:52',
    $$select pdks.isten_cikis_gir(test.c('CO04'), '2026-10-14')$$);
select test.hata('gece vardiyası gününden bir gün önce yazılan çıkış reddedilir', '14.10.2026 21:50',
    $$select pdks.isten_cikis_gir(test.c('CO03'), '2026-10-13')$$);
select test.hata('İstanbul gece yarısındaki okutma sonraki güne aittir', '16.10.2026 00:00',
    $$select pdks.isten_cikis_gir(test.c('CO05'), '2026-10-15')$$);
select test.hata('geçici kartla okutma da sayılır', '15.10.2026 07:50',
    $$select pdks.isten_cikis_gir(test.c('CO06'), '2026-10-14')$$);
select test.hata('ertesi günün 00-08 vardiyasına 23:50 girişi ertesi güne aittir', '14.10.2026 23:50',
    $$select pdks.isten_cikis_gir(test.c('CO08'), '2026-10-14')$$);
select test.hata('reddedilmiş gece planı pencere açmaz', '15.10.2026 06:05',
    $$select pdks.isten_cikis_gir(test.c('CO10'), '2026-10-14')$$);
select test.hata('gündüz vardiyasının penceresi gece yarısını aşmaz', '15.10.2026 00:30',
    $$select pdks.isten_cikis_gir(test.c('CO11'), '2026-10-14')$$);
reset role;
select test.dogrula('reddedilen çıkış hiçbir şeyi değiştirmedi (CO01)',
    (select aktif and isten_cikis_tarihi is null from pdks.calisan where id = test.c('CO01'))
    and (select durum = 'aktif' from pdks.kart where kart_no = 'CO-01')
    and (select count(*) = 2 from pdks.vardiya_plani where calisan_id = test.c('CO01')));

-- 2) Kabul edilenler ----------------------------------------------------------
set local role authenticated;
select test.dogrula('son gün doğru girilince çıkış kabul edilir (CO01)',
    pdks.isten_cikis_gir(test.c('CO01'), '2026-10-15') is not null);
select test.dogrula('son gece vardiyasının sabah çıkışı o güne aittir (CO03)',
    pdks.isten_cikis_gir(test.c('CO03'), '2026-10-14') is not null);
select test.dogrula('onay bekleyen gece planının penceresi de sayılır (CO09)',
    pdks.isten_cikis_gir(test.c('CO09'), '2026-10-14') is not null);
select test.dogrula('geçici kartın iadesinden sonraki okutma çalışana yazılmaz (CO06)',
    pdks.isten_cikis_gir(test.c('CO06'), '2026-10-15') is not null);
select test.dogrula('kartın iptalinden sonraki okutma engel değildir (CO07)',
    pdks.isten_cikis_gir(test.c('CO07'), '2026-10-13') is not null);
select test.dogrula('gece yarısındaki okutmanın günü çıkış günü olunca kabul edilir (CO05)',
    pdks.isten_cikis_gir(test.c('CO05'), '2026-10-16') is not null);
select test.dogrula('00-08 vardiyasının günü çıkış günü olunca kabul edilir (CO08)',
    pdks.isten_cikis_gir(test.c('CO08'), '2026-10-15') is not null);
reset role;
select test.dogrula('cikistan_sonraki_okutma ekrandan çağrılamaz',
    not has_function_privilege('authenticated', 'pdks.cikistan_sonraki_okutma(bigint, date)', 'execute')
    and not has_function_privilege('anon', 'pdks.cikistan_sonraki_okutma(bigint, date)', 'execute'));

do $$ begin raise notice 'TÜM TESTLER GEÇTİ'; end $$;
rollback;
