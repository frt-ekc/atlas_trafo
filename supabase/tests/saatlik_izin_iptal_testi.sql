-- =====================================================================
-- Saatlik izin iptali (20261230010000_saatlik_izin_iptal.sql, T-50)
-- 13–15 Ekim 2026 hafta içi, GÜNDÜZ 08:00–17:00. Testin kendi sahte verisi.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/saatlik_izin_iptal_testi.sql
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
create function test.gk(p_sicil text, p_gun date) returns pdks.gun_kaydi language sql security definer as $$
    select * from pdks.gun_kaydi where calisan_id = test.c(p_sicil) and is_gunu = p_gun $$;
-- Çalışanın o günkü son saatlik izni
create function test.si(p_sicil text, p_gun date) returns pdks.saatlik_izin language sql security definer as $$
    select * from pdks.saatlik_izin where calisan_id = test.c(p_sicil) and tarih = p_gun order by id desc limit 1 $$;
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
--   Hepsi GÜNDÜZ planlı, 08:00 giriş, 15:00 çıkış (2 saat erken)
--   SI01: 13 Ekim, yanlış saatlik izin, iptal, doğrusu girilir
--   SI02: 14 Ekim, saatlik izin, ay kilitlenir
--   SI03: 15 Ekim, izin gece işinden önce girilip iptal edilir
--   SII1 / SII2: İK uzmanları · SIA1: amir
insert into pdks.departman (ad) values ('SI Üretim'), ('SI İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = case when s ~ 'SI[IA]' then 'SI İdari' else 'SI Üretim' end), '2025-01-01'
from unnest(array['SI01', 'SI02', 'SI03', 'SII1', 'SII2', 'SIA1']) s;
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('x', 'si_ik1@ornek.test',  'ik',   test.c('SII1'), '00000000-0000-0000-0000-0000000000e1'),
    ('x', 'si_ik2@ornek.test',  'ik',   test.c('SII2'), '00000000-0000-0000-0000-0000000000e2'),
    ('x', 'si_amir@ornek.test', 'amir', test.c('SIA1'), '00000000-0000-0000-0000-0000000000e3');
update pdks.departman set amir_id = test.k('si_amir@ornek.test') where ad like 'SI %';
insert into pdks.kart (kart_no, calisan_id) select 'K-' || sicil_no, id from pdks.calisan where sicil_no ~ '^SI0';
insert into pdks.okuyucu (kod, ad, sistem) values ('SI-PDKS', 'SI PDKS', 'pdks');
insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id, giren_id)
select c.id, g::date, (select id from pdks.vardiya_tanim where kod = 'GUNDUZ'), test.k('si_ik1@ornek.test')
from pdks.calisan c cross join generate_series(date '2026-10-13', date '2026-10-15', '1 day') g
where c.sicil_no ~ '^SI0';
insert into pdks.aktarim (kaynak, dosya_adi, dosya_ozeti, veri_tarihi)
select 'pdks', 'si_' || g || '.csv', 'si-pdks-' || g, g::date
from unnest(array['2026-10-13', '2026-10-14', '2026-10-15']) g;
insert into pdks.ham_okutma (aktarim_id, okuyucu_id, kart_no, okutma_zamani, yon)
select (select id from pdks.aktarim where dosya_ozeti = 'si-pdks-' || v.g),
       (select id from pdks.okuyucu where kod = 'SI-PDKS'), 'K-' || v.s, test.ts(v.g || ' ' || x.z), x.y
from (values ('SI01', '2026-10-13'), ('SI02', '2026-10-14'), ('SI03', '2026-10-15')) v(s, g)
cross join (values ('08:00', 'giris'), ('15:00', 'cikis')) x(z, y);
select pdks.gece_isi_calistir('2026-10-13');
select pdks.gece_isi_calistir('2026-10-14');
select test.dogrula('hazırlık: SI01 13 Ekim 2 saat erken çıkmış, saatlik izin yok',
    (select durum = 'tamam' and erken_cikis_dk = 120 and saatlik_izin_dk = 0 from test.gk('SI01', '2026-10-13')));

-- 1) Yanlış saatlik izin girilir (bulgudaki durum) -----------------------------------------
set local role authenticated;
select test.oturum('si_ik1@ornek.test');
select pdks.saatlik_izin_gir(test.c('SI01'), '2026-10-13', test.ts('2026-10-13 15:00'), test.ts('2026-10-13 17:00'), 'mazeret');
reset role;
select test.dogrula('yanlış izin: erken çıkış 0, saatlik izin 120',
    (select erken_cikis_dk = 0 and saatlik_izin_dk = 120 from test.gk('SI01', '2026-10-13')));

-- 2) Kim iptal edebilir ---------------------------------------------------------------------
set local role authenticated;
select test.oturum('si_amir@ornek.test');
select test.hata('amir iptal edemez', 'yetkiniz yok',
    $$select pdks.saatlik_izin_iptal((test.si('SI01', '2026-10-13')).id, 'Yanlış saat girildi')$$);
select test.oturum('si_ik1@ornek.test');
select test.hata('neden boş olamaz', 'İptal nedeni',
    $$select pdks.saatlik_izin_iptal((test.si('SI01', '2026-10-13')).id, '  ')$$);
select test.hata('neden çok kısa olamaz', 'İptal nedeni',
    $$select pdks.saatlik_izin_iptal((test.si('SI01', '2026-10-13')).id, 'abc')$$);
select test.hata('olmayan izin', 'bulunamadı',
    $$select pdks.saatlik_izin_iptal(-1, 'Yanlış saat girildi')$$);
reset role;
select test.dogrula('reddedilen denemeler izni değiştirmedi',
    (select iptal_zamani is null from test.si('SI01', '2026-10-13'))
    and (select saatlik_izin_dk = 120 from test.gk('SI01', '2026-10-13')));

-- 3) İK iptal eder: kayıt kalır, gün yeniden hesaplanır ------------------------------------
set local role authenticated;
select test.oturum('si_ik1@ornek.test');
select pdks.saatlik_izin_iptal((test.si('SI01', '2026-10-13')).id, '  Yanlış saat girildi ');
reset role;
select test.dogrula('iptal: gün hemen yeniden hesaplandı, erken çıkış 120 geri geldi',
    (select erken_cikis_dk = 120 and saatlik_izin_dk = 0 and hesap_tamam from test.gk('SI01', '2026-10-13')));
select test.dogrula('iptal: kayıt silinmedi; kim, ne zaman, neden yazıldı',
    (select count(*) = 1 from pdks.saatlik_izin where calisan_id = test.c('SI01'))
    and (select iptal_zamani is not null and iptal_eden_id = test.k('si_ik1@ornek.test')
                and iptal_nedeni = 'Yanlış saat girildi'
                and tur = 'mazeret' and baslangic = test.ts('2026-10-13 15:00')
         from test.si('SI01', '2026-10-13')));
set local role authenticated;
select test.oturum('si_ik1@ornek.test');
select test.hata('iki kez iptal edilemez', 'zaten iptal',
    $$select pdks.saatlik_izin_iptal((test.si('SI01', '2026-10-13')).id, 'Yanlış saat girildi')$$);

-- 4) Doğrusu aynı saatlere yeniden girilebilir --------------------------------------------
select pdks.saatlik_izin_gir(test.c('SI01'), '2026-10-13', test.ts('2026-10-13 16:00'), test.ts('2026-10-13 17:00'), 'mazeret');
reset role;
select test.dogrula('iptal edilen izin çakışma sayılmaz; doğru izin 60 dk',
    (select erken_cikis_dk = 60 and saatlik_izin_dk = 60 from test.gk('SI01', '2026-10-13')));
select test.dogrula('puantajda yalnızca geçerli izin: 60 dk',
    (select saatlik_izin_dk = 60 and erken_cikis_dk = 60 from pdks.v_puantaj_canli
     where calisan_id = test.c('SI01') and yil = 2026 and ay = 10));
set local role authenticated;
select test.oturum('si_amir@ornek.test');
select test.dogrula('amir iptal edilen izni görmez, geçerli olanı görür',
    (select count(*) = 1 and min(baslangic) = test.ts('2026-10-13 16:00')
     from pdks.v_saatlik_izin_amir where calisan_id = test.c('SI01')));
reset role;

-- 5) Görevler ayrılığı: İK kendi saatlik iznini iptal edemez -------------------------------
set local role authenticated;
select test.oturum('si_ik2@ornek.test');
select pdks.saatlik_izin_gir(test.c('SII1'), '2026-10-13', test.ts('2026-10-13 10:00'), test.ts('2026-10-13 12:00'), 'vizite');
select test.oturum('si_ik1@ornek.test');
select test.hata('İK kendi iznini iptal edemez', 'Görevler ayrılığı',
    $$select pdks.saatlik_izin_iptal((test.si('SII1', '2026-10-13')).id, 'Kendi iznim yanlış')$$);
select test.oturum('si_ik2@ornek.test');
select pdks.saatlik_izin_iptal((test.si('SII1', '2026-10-13')).id, 'Başka İK iptal eder');
reset role;
select test.dogrula('başka İK iptal edebilir',
    (select iptal_eden_id = test.k('si_ik2@ornek.test') from test.si('SII1', '2026-10-13')));

-- 6) Tablo yine de silinmez, iptal geri alınmaz --------------------------------------------
set local role authenticated;
select test.oturum('si_ik1@ornek.test');
select test.hata('İK tabloyu doğrudan değiştiremez', 'permission denied',
    $$update pdks.saatlik_izin set iptal_zamani = now() where calisan_id = test.c('SI01')$$);
select test.hata('İK doğrudan silemez', 'permission denied',
    $$delete from pdks.saatlik_izin where calisan_id = test.c('SI01')$$);
reset role;
select test.hata('sistem de silemez', 'değiştirilemez',
    $$delete from pdks.saatlik_izin where calisan_id = test.c('SI01')$$);
select test.hata('iptal dışında alan değişmez (saat)', 'değiştirilemez',
    $$update pdks.saatlik_izin set bitis = bitis + interval '1 hour' where id = (test.si('SI01', '2026-10-13')).id$$);
select test.hata('iptal geri alınamaz', 'değiştirilemez',
    format('update pdks.saatlik_izin set iptal_zamani = null, iptal_eden_id = null, iptal_nedeni = null where id = %s',
           (select id from pdks.saatlik_izin where calisan_id = test.c('SI01') and iptal_zamani is not null)));
select test.hata('iptal bilgisi eksik yazılamaz', 'saatlik_izin_iptal_tam',
    $$update pdks.saatlik_izin set iptal_zamani = now() where id = (test.si('SI01', '2026-10-13')).id$$);

-- 7) Gece işinden önce iptal: gece işi iptal edilen izni saymaz -----------------------------
set local role authenticated;
select test.oturum('si_ik1@ornek.test');
select pdks.saatlik_izin_gir(test.c('SI03'), '2026-10-15', test.ts('2026-10-15 15:00'), test.ts('2026-10-15 17:00'), 'diger');
select pdks.saatlik_izin_iptal((test.si('SI03', '2026-10-15')).id, 'Yanlış kişiye girildi');
reset role;
select pdks.gece_isi_calistir('2026-10-15');
select test.dogrula('gece işi: iptal edilen izin sayılmadı, erken çıkış 120',
    (select durum = 'tamam' and erken_cikis_dk = 120 and saatlik_izin_dk = 0 from test.gk('SI03', '2026-10-15')));

-- 8) Kilitli ay: iptal edilemez ---------------------------------------------------------------
set local role authenticated;
select test.oturum('si_ik1@ornek.test');
select pdks.saatlik_izin_gir(test.c('SI02'), '2026-10-14', test.ts('2026-10-14 15:00'), test.ts('2026-10-14 17:00'), 'mazeret');
select pdks.ay_kilitle(2026::smallint, 10::smallint, true);
select test.hata('kilitli aydaki izin iptal edilemez', 'kilitli',
    $$select pdks.saatlik_izin_iptal((test.si('SI02', '2026-10-14')).id, 'Yanlış saat girildi')$$);
reset role;
select test.dogrula('kilitli ay: izin ve gün değişmedi',
    (select iptal_zamani is null from test.si('SI02', '2026-10-14'))
    and (select erken_cikis_dk = 0 and saatlik_izin_dk = 120 from test.gk('SI02', '2026-10-14')));

-- 9) Yetkiler ---------------------------------------------------------------------------------
select test.dogrula('iptal fonksiyonunu oturum açan çağırır, anonim çağıramaz; iç trigger fonksiyonu kapalı',
    has_function_privilege('authenticated', 'pdks.saatlik_izin_iptal(bigint, text)', 'execute')
    and not has_function_privilege('anon', 'pdks.saatlik_izin_iptal(bigint, text)', 'execute')
    and not has_function_privilege('authenticated', 'pdks.saatlik_izin_yalniz_iptal()', 'execute'));

do $$ begin raise notice 'TÜM TESTLER GEÇTİ'; end $$;
rollback;
