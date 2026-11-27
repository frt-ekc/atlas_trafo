-- =====================================================================
-- Yıllık fazla mesai sınırı testleri (20261221010000_yillik_fazla_mesai.sql, T-57)
-- Testin kendi sahte verisi (Ekim ve Aralık 2026); sınır geçici olarak 600 dk yapılır.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/yillik_fazla_mesai_testi.sql
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
create function test.gk(p_sicil text, p_gun date) returns pdks.gun_kaydi language sql security definer as $$
    select * from pdks.gun_kaydi where calisan_id = test.c(p_sicil) and is_gunu = p_gun $$;
create function test.hv(p_sicil text, p_gun date) returns pdks.fazla_mesai_inceleme language sql security definer as $$
    select * from pdks.fazla_mesai_inceleme where calisan_id = test.c(p_sicil) and is_gunu = p_gun $$;
create function test.toplam(p_sicil text) returns integer language sql security definer as $$
    select pdks.fm_yillik_toplam(test.c(p_sicil), 2026) $$;
create function test.asim(p_sicil text) returns bigint language sql security definer as $$
    select count(*) from pdks.uyari where tur = 'fm_yillik_sinir_asildi' and calisan_id = test.c(p_sicil) $$;
create function test.talep(p_sicil text, p_gun date, p_dk int) returns void language sql as $$
    insert into pdks.fazla_mesai_plani (calisan_id, is_gunu, planli_dk, gerekce, talep_eden_id)
    values (test.c(p_sicil), p_gun, p_dk, 'Sipariş yetişmeli', test.k('yf_ik1@ornek.test')) $$;
create function test.onayla(p_sicil text, p_gun date) returns void language sql as $$
    update pdks.fazla_mesai_plani set durum = 'onaylandi', karar_veren_id = test.k('yf_ik2@ornek.test')
    where calisan_id = test.c(p_sicil) and is_gunu = p_gun and durum = 'talep' $$;
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
--   YF01: hafta içi havuz (14 Ekim, 120 dk), sonra planlar     YF02: Pazar 18 Ekim çalışması (İK havuzdan onaylar, FM100 480; T-78), sonra plan
--   YF03: Pazar 18 Ekim planlı 60 dk + çalışma (iki kez sayılmamalı)
--   YF04: yazılı onay yok, Pazar; havuz kilitten sonra onaylanır     YF05: sınır doluyken havuz
--   YF06: tatil çalışması (İK havuzdan onaylar) tek başına sınırı aşar (sınır 400)     YF07: reddedilen / bekleyen kayıt sayılmaz
insert into pdks.departman (ad) values ('YF Üretim'), ('YF İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = case when s like 'YFI%' then 'YF İdari' else 'YF Üretim' end), '2025-01-01'
from unnest(array['YF01','YF02','YF03','YF04','YF05','YF06','YF07','YFI1','YFI2','YFA1','YFA2']) s;
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('YF İK 1', 'yf_ik1@ornek.test', 'ik', test.c('YFI1'), '00000000-0000-0000-0000-0000000000b1'),
    ('YF İK 2', 'yf_ik2@ornek.test', 'ik', test.c('YFI2'), '00000000-0000-0000-0000-0000000000b2'),
    ('YF Amir', 'yf_amir@ornek.test', 'amir', test.c('YFA1'), '00000000-0000-0000-0000-0000000000b3'),
    ('YF Amir 2', 'yf_amir2@ornek.test', 'amir', test.c('YFA2'), '00000000-0000-0000-0000-0000000000b4');
update pdks.departman set amir_id = test.k('yf_amir@ornek.test') where ad = 'YF Üretim';
update pdks.departman set amir_id = test.k('yf_amir2@ornek.test') where ad = 'YF İdari';
insert into pdks.kart (kart_no, calisan_id) select 'YF-' || s, test.c(s)
from unnest(array['YF01','YF02','YF03','YF04','YF05','YF06','YF07']) s;
insert into pdks.okuyucu (kod, ad, sistem) values ('YF-PDKS', 'YF PDKS', 'pdks');
insert into pdks.fazla_mesai_onayi (calisan_id, yil, imza_tarihi, belge_no, giren_id)
select test.c(s), 2026, '2026-01-02', 'YF-' || s, test.k('yf_ik1@ornek.test')
from unnest(array['YF01','YF02','YF03','YF05','YF06','YF07']) s;

create temp table yf_gun on commit drop as
select * from (values ('YF01', date '2026-10-14', '19:00'), ('YF02', date '2026-10-18', '17:00'),
                      ('YF03', date '2026-10-18', '18:00'), ('YF04', date '2026-10-18', '17:00'),
                      ('YF05', date '2026-10-14', '19:00'), ('YF06', date '2026-10-18', '17:00'),
                      ('YF07', date '2026-10-14', '19:00')) v(s, g, bit);
insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id, giren_id)
select test.c(s), g, (select id from pdks.vardiya_tanim where kod = 'GUNDUZ'), test.k('yf_ik1@ornek.test') from yf_gun
union all
select test.c(s), g::date, (select id from pdks.vardiya_tanim where kod = 'GUNDUZ'), test.k('yf_ik1@ornek.test')
from unnest(array['YF01','YF02','YF05','YF07']) s, generate_series(date '2026-12-01', date '2026-12-05', '1 day') g;
insert into pdks.aktarim (kaynak, dosya_adi, dosya_ozeti, veri_tarihi)
select distinct 'pdks', 'yf_' || g || '.csv', 'yf-pdks-' || g, g from yf_gun;
insert into pdks.ham_okutma (aktarim_id, okuyucu_id, kart_no, okutma_zamani, yon)
select (select id from pdks.aktarim where dosya_ozeti = 'yf-pdks-' || g),
       (select id from pdks.okuyucu where kod = 'YF-PDKS'), 'YF-' || s, test.ts(g || ' ' || x.saat), x.yon
from yf_gun cross join lateral (values ('08:00', 'giris'), (bit, 'cikis')) x(saat, yon);

update pdks.ayar set deger = 400 where anahtar = 'fm_yillik_sinir_dk';
select test.talep('YF03', '2026-10-18', 60);
select test.onayla('YF03', '2026-10-18');
select pdks.gece_isi_calistir('2026-10-14');
select pdks.gece_isi_calistir('2026-10-18');
-- T-78: yazılı onaylı Pazar çalışması da İK onayıyla (havuz) FM100 olur; YF03'ün onaylı planı günü önceden onaylar
select test.dogrula('T-78: planı olmayan yazılı onaylı Pazar çalışması havuzda (YF02, YF06: 540 dk); planlı Pazar havuza düşmez (YF03)',
    (select tur = 'tatil_calismasi' and dakika = 540 from test.hv('YF02', '2026-10-18'))
    and (select tur = 'tatil_calismasi' and dakika = 540 from test.hv('YF06', '2026-10-18'))
    and (test.hv('YF03', '2026-10-18')).id is null
    and (select fm100_dk = 0 from test.gk('YF06', '2026-10-18')) and test.toplam('YF06') = 0);
set local role authenticated;
select test.oturum('yf_ik1@ornek.test');
select pdks.fazla_mesai_inceleme_karar((test.hv('YF02', '2026-10-18')).id, true);
select pdks.fazla_mesai_inceleme_karar((test.hv('YF06', '2026-10-18')).id, true);
reset role;
select test.dogrula('yazılı onaylı tatil çalışması sınırı (400) aşınca İK''ya uyarı (YF06: 480)', test.asim('YF06') = 1);
select test.dogrula('sınırı aşmayana uyarı yok (YF01)', test.asim('YF01') = 0);
update pdks.ayar set deger = 600 where anahtar = 'fm_yillik_sinir_dk';

-- 1) Plan talebi ve onayı: havuz ve tatil sayılır -------------------------------
set local role authenticated;
select test.oturum('yf_ik1@ornek.test');
select pdks.fazla_mesai_inceleme_karar((test.hv('YF01', '2026-10-14')).id, true);
reset role;
select test.dogrula('sınır altındaki havuz onayı: işaret ve uyarı yok (YF01)',
    not (test.hv('YF01', '2026-10-14')).yillik_sinir_asildi and test.asim('YF01') = 0);
select test.talep('YF01', g::date, 120) from generate_series(date '2026-12-01', date '2026-12-05', '1 day') g;
select test.onayla('YF01', g::date) from generate_series(date '2026-12-01', date '2026-12-04', '1 day') g;
select test.hata('havuz 120 + plan 480 doluyken yeni plan onayı reddedilir', 'Yıllık fazla mesai sınırı aşılıyor. Kalan süre: 0',
    $$select test.onayla('YF01', '2026-12-05')$$);
select test.hata('tatil çalışması 480 iken 150 dk plan talebi reddedilir', 'Kalan süre: 2 sa',
    $$update pdks.ayar set deger = 720 where anahtar = 'gunluk_azami_calisma_dk';
      select test.talep('YF02', '2026-12-01', 150)$$);
select test.talep('YF02', '2026-12-01', 120);
select test.onayla('YF02', '2026-12-01');
select test.dogrula('sınıra tam oturan plan onaylanır: 480 tatil + 120 plan = 600 (YF02)', test.toplam('YF02') = 600);

-- 2) Toplam: aynı süre iki kez sayılmaz --------------------------------------------
select test.dogrula('normal gün: havuz 120 + plan 480 = 600 (YF01)', test.toplam('YF01') = 600);
select test.dogrula('planlı Pazar: FM100 planı zaten içerir (540), 60 dk bir daha eklenmez (YF03)',
    (select fm100_dk = 540 from test.gk('YF03', '2026-10-18')) and test.toplam('YF03') = 540);
select test.dogrula('karar bekleyen havuz sayılmaz (YF04, YF07)', test.toplam('YF04') = 0 and test.toplam('YF07') = 0);
set local role authenticated;
select pdks.fazla_mesai_inceleme_karar((test.hv('YF07', '2026-10-14')).id, false, 'Çalışma yapılmamış');
reset role;
select test.talep('YF07', '2026-12-01', 60);
select test.dogrula('reddedilen havuz ve bekleyen talep sayılmaz (YF07)', test.toplam('YF07') = 0);
select test.dogrula('başka yıl sayılmaz', pdks.fm_yillik_toplam(test.c('YF01'), 2025) = 0);

-- 3) Havuz: sınır aşılsa da onaylanır, işaretlenir --------------------------------
select test.talep('YF05', g::date, 120) from generate_series(date '2026-12-01', date '2026-12-05', '1 day') g;
select test.onayla('YF05', g::date) from generate_series(date '2026-12-01', date '2026-12-05', '1 day') g;
set local role authenticated;
select pdks.fazla_mesai_inceleme_karar((test.hv('YF05', '2026-10-14')).id, true);
reset role;
select test.dogrula('sınır doluyken havuz onayı reddedilmez, puantaja girer (FM50 120)',
    (select durum = 'onaylandi' from test.hv('YF05', '2026-10-14'))
    and (select fm50_dk = 120 and calisma_dk = 600 from test.gk('YF05', '2026-10-14')) and test.toplam('YF05') = 720);
select test.dogrula('kayıt "yıllık sınır aşıldı" işaretlendi, bir uyarı yazıldı',
    (test.hv('YF05', '2026-10-14')).yillik_sinir_asildi and test.asim('YF05') = 1);
select test.hata('reddedilmiş kayda işaret konamaz', 'yillik_sinir_check',
    format('update pdks.fazla_mesai_inceleme set yillik_sinir_asildi = true where id = %s', (test.hv('YF07', '2026-10-14')).id));

-- 4) Kilitli aya gelen tatil onayı da sayılır ---------------------------------------
delete from pdks.vardiya_plani where tarih between '2026-10-01' and '2026-10-31'
    and not exists (select 1 from pdks.gun_kaydi g where g.calisan_id = vardiya_plani.calisan_id and g.is_gunu = tarih);
set local role authenticated;
select pdks.ay_kilitle(2026::smallint, 10::smallint, true, 'Test: zorla kilit gerekçesi');
select pdks.fazla_mesai_inceleme_karar((test.hv('YF04', '2026-10-18')).id, true);
reset role;
select test.dogrula('kilitli ayda onaylanan tatil çalışması toplamda (FM100 farkı 480)',
    (select fark_satiri and fm100_etki_dk = 480 and yazili_onaysiz and not yillik_sinir_asildi from test.hv('YF04', '2026-10-18'))
    and test.toplam('YF04') = 480);
-- 5) Yıllık görünüm (ekran) aynı hesabı verir (T-62) -------------------------------
set local role authenticated;
select test.oturum('yf_ik1@ornek.test');
create temp table yf_gorunum on commit drop as
select sicil_no, toplam_dk, kalan_dk, onayli_plan_dk, onayli_havuz_dk, gerceklesen_dk, sinir_dk
from pdks.v_fazla_mesai_yillik where sicil_no like 'YF%' and yil = 2026;
reset role;
select test.dogrula('görünümdeki toplam ve kalan, sınır denetimindekiyle aynı (6 çalışan)',
    (select count(*) = 6 and bool_and(toplam_dk = test.toplam(sicil_no) and kalan_dk = 600 - toplam_dk and sinir_dk = 600)
     from yf_gorunum));
select test.dogrula('yalnızca tatil çalışması olan da görünür (YF06: planı yok, toplam 480)',
    (select onayli_plan_dk = 0 and toplam_dk = 480 and gerceklesen_dk = 480 from yf_gorunum where sicil_no = 'YF06'));
select test.dogrula('havuz ayrı sütunda, gerçekleşen puantajdaki dakika (YF05: plan 600, havuz 120, gerçekleşen 120)',
    (select onayli_plan_dk = 600 and onayli_havuz_dk = 120 and gerceklesen_dk = 120 and kalan_dk = -120
     from yf_gorunum where sicil_no = 'YF05'));
select test.dogrula('kilitli aya gelen onayın farkı da gerçekleşende (YF04: 480)',
    (select gerceklesen_dk = 480 from yf_gorunum where sicil_no = 'YF04'));
set local role authenticated;
select test.oturum('yf_amir@ornek.test');
select test.dogrula('amir görünümde yalnızca kendi çalışanlarını görür ve aynı toplamı okur',
    (select count(*) = 6 and bool_and(sicil_no like 'YF%') from pdks.v_fazla_mesai_yillik where yil = 2026)
    and (select toplam_dk = 720 from pdks.v_fazla_mesai_yillik where sicil_no = 'YF05'));
select test.oturum('yf_amir2@ornek.test');
select test.dogrula('başka departmanın amiri göremez',
    (select count(*) = 0 from pdks.v_fazla_mesai_yillik where sicil_no like 'YF%'));
reset role;
select test.dogrula('fm_yillik_toplam ekrandan çağrılamaz',
    not has_function_privilege('authenticated', 'pdks.fm_yillik_toplam(bigint, integer)', 'execute')
    and not has_function_privilege('anon', 'pdks.fm_yillik_toplam(bigint, integer)', 'execute'));

do $$ begin raise notice 'TÜM TESTLER GEÇTİ'; end $$;
rollback;
