-- =====================================================================
-- Durum düzeltmesi testleri (20261202010000_durum_duzeltmesi.sql)
--   Hesaplanmış gün devamsız / raporlu / izinli yapılınca eski dakikalar temizlenir,
--   gün "bekleyen" sayılmaz; tekrar "tamam" yapılınca gün yeniden hesaplanır.
--   Testin kendi sahte verisi (4 Ağustos 2026, Salı). Örnek veri yüklü olsa da olmasa da çalışır.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/durum_duzeltmesi_testi.sql
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
create function test.oturum(p_eposta text) returns void language sql security definer as $$
    select set_config('request.jwt.claims',
        json_build_object('sub', (select auth_kullanici_id from pdks.kullanici where eposta = p_eposta),
                          'role', 'authenticated')::text, true);
$$;
create function test.c(p text) returns bigint language sql security definer as $$
    select id from pdks.calisan where sicil_no = p $$;
create function test.k(p text) returns bigint language sql security definer as $$
    select id from pdks.kullanici where eposta = p $$;
create function test.gk(p_sicil text) returns pdks.gun_kaydi language sql security definer as $$
    select * from pdks.gun_kaydi where calisan_id = test.c(p_sicil) and is_gunu = '2026-08-04' $$;
create function test.canli(p_sicil text) returns pdks.v_puantaj_canli language sql security definer as $$
    select * from pdks.v_puantaj_canli where calisan_id = test.c(p_sicil) and yil = 2026 and ay = 8 $$;
create function test.ps(p_sicil text) returns pdks.puantaj_satiri language sql security definer as $$
    select s.* from pdks.puantaj_satiri s join pdks.donem d on d.id = s.donem_id
    where s.calisan_id = test.c(p_sicil) and d.yil = 2026 and d.ay = 8 and s.satir_turu = 'normal' $$;
create function test.ts(p text) returns timestamptz language sql immutable as $$
    select (p::timestamp) at time zone 'Europe/Istanbul' $$;
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

-- ---------------------------------------------------------------------
-- Hazırlık: DD01–DD04 aynı saatlerde çalıştı (07:55–16:04, vardiya 08–16)
--   DD01 kontrol: hiç düzeltilmez · DD02 devamsız · DD03 raporlu · DD04 izinli yapılır
--   DDI1: İK (DD İdari, planı yok)
-- ---------------------------------------------------------------------
insert into pdks.departman (ad) values ('DD Üretim'), ('DD İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = d), '2025-01-01'
from (values ('DDA1', 'DD Üretim'), ('DD01', 'DD Üretim'), ('DD02', 'DD Üretim'),
             ('DD03', 'DD Üretim'), ('DD04', 'DD Üretim'), ('DDI1', 'DD İdari')) v(s, d);
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('DD İK',   'dd_ik@ornek.test',   'ik',   test.c('DDI1'), '00000000-0000-0000-0000-0000000000d1'),
    ('DD Amir', 'dd_amir@ornek.test', 'amir', test.c('DDA1'), '00000000-0000-0000-0000-0000000000d2');
update pdks.departman set amir_id = test.k('dd_amir@ornek.test') where ad = 'DD Üretim';
insert into pdks.kart (kart_no, calisan_id)
select 'DD-' || s, test.c(s) from unnest(array['DD01', 'DD02', 'DD03', 'DD04']) s;
insert into pdks.okuyucu (kod, ad, sistem) values ('DD-PDKS', 'DD PDKS', 'pdks');
insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id, giren_id)
select test.c(s), '2026-08-04', (select id from pdks.vardiya_tanim where kod = 'GUNDUZ_8'), test.k('dd_ik@ornek.test')
from unnest(array['DD01', 'DD02', 'DD03', 'DD04']) s;
insert into pdks.aktarim (kaynak, dosya_adi, dosya_ozeti, veri_tarihi)
values ('pdks', 'dd_20260804.csv', 'dd-pdks-20260804', '2026-08-04');
insert into pdks.ham_okutma (aktarim_id, okuyucu_id, kart_no, okutma_zamani, yon)
select (select id from pdks.aktarim where dosya_ozeti = 'dd-pdks-20260804'),
       (select id from pdks.okuyucu where kod = 'DD-PDKS'), 'DD-' || s, test.ts(z), y
from unnest(array['DD01', 'DD02', 'DD03', 'DD04']) s,
     (values ('2026-08-04 07:55', 'giris'), ('2026-08-04 16:04', 'cikis')) v(z, y);
select pdks.gece_isi_calistir('2026-08-04');

select test.dogrula('hazırlık: dört gün de hesaplandı, aynı dakikalar (çalışma > 0)',
    (select count(*) = 4 and count(distinct calisma_dk) = 1 and min(calisma_dk) > 0 and bool_and(hesap_tamam)
     from pdks.gun_kaydi where is_gunu = '2026-08-04' and durum = 'tamam'
       and calisan_id in (test.c('DD01'), test.c('DD02'), test.c('DD03'), test.c('DD04'))));

-- ---------------------------------------------------------------------
-- 1) Son duruma geçen günün dakikaları temizlenir
-- ---------------------------------------------------------------------
set local role authenticated;
select test.oturum('dd_ik@ornek.test');
select pdks.kayit_duzelt((test.gk('DD02')).id, 'durum', 'devamsiz', 'Test: kartını başkası okuttu');
select pdks.kayit_duzelt((test.gk('DD03')).id, 'durum', 'raporlu', 'Test: rapor belgesi geldi');
select pdks.kayit_duzelt((test.gk('DD04')).id, 'durum', 'izinli', 'Test: yıllık izin dilekçesi');
reset role;

select test.dogrula('devamsız yapılan günde çalışma, fazla mesai, gece ve mola dakikası kalmadı (DD02)',
    (select durum = 'devamsiz' and calisma_dk is null and fazla_mesai_dk is null and fm50_dk is null
            and fm100_dk is null and gece_calisma_dk is null and mola_dk is null and gec_kalma_dk is null
     from test.gk('DD02')));
select test.dogrula('raporlu ve izinli yapılan günlerde de dakika kalmadı (DD03, DD04)',
    (select calisma_dk is null and fm50_dk is null from test.gk('DD03'))
    and (select calisma_dk is null and fm50_dk is null from test.gk('DD04')));
select test.dogrula('saatler ve düzeltme izi duruyor: giriş / çıkış silinmedi, iz eski "tamam" yeni "devamsiz", aleyhine',
    (select giris_zamani = test.ts('2026-08-04 07:55') and cikis_zamani = test.ts('2026-08-04 16:04') from test.gk('DD02'))
    and exists (select 1 from pdks.duzeltme d where d.gun_kaydi_id = (test.gk('DD02')).id and d.alan = 'durum'
                and d.eski_deger = 'tamam' and d.yeni_deger = 'devamsiz' and d.calisan_aleyhine));
select test.dogrula('düzeltilmeyen kontrol günü olduğu gibi (DD01)',
    (select durum = 'tamam' and hesap_tamam and calisma_dk > 0 from test.gk('DD01')));

-- ---------------------------------------------------------------------
-- 2) Canlı puantaj: devamsız gün dakika getirmez, gün "bekleyen" sayılmaz
-- ---------------------------------------------------------------------
select test.dogrula('son duruma geçen günlerin hesabı kapandı (hesap_tamam)',
    (test.gk('DD02')).hesap_tamam and (test.gk('DD03')).hesap_tamam and (test.gk('DD04')).hesap_tamam);
select test.dogrula('canlı puantaj DD02: 1 devamsız gün, 0 çalışma ve fazla mesai dakikası, bekleyen gün yok',
    (select devamsiz_gun = 1 and calisilan_gun = 0 and calisma_dk = 0 and fm50_dk = 0 and fazla_mesai_dk = 0
            and bekleyen_gun = 0 from test.canli('DD02')));
select test.dogrula('canlı puantaj DD03: 1 raporlu gün, 0 dakika, bekleyen yok · DD04: 1 izinli gün, 0 dakika, bekleyen yok',
    (select raporlu_gun = 1 and calisma_dk = 0 and bekleyen_gun = 0 from test.canli('DD03'))
    and (select izinli_gun = 1 and calisma_dk = 0 and bekleyen_gun = 0 from test.canli('DD04')));

-- ---------------------------------------------------------------------
-- 3) Geri "tamam" yapılan gün yeniden hesaplanır (kontrol günüyle aynı dakikalar)
-- ---------------------------------------------------------------------
set local role authenticated;
select test.oturum('dd_ik@ornek.test');
select pdks.kayit_duzelt((test.gk('DD04')).id, 'durum', 'tamam', 'Test: izin dilekçesi yanlış güne yazılmış');
reset role;
select test.dogrula('tekrar "tamam" yapılan gün hemen hesaplandı, dakikalar kontrol günüyle aynı (DD04 = DD01)',
    (select g4.durum = 'tamam' and g4.hesap_tamam and g4.calisma_dk = g1.calisma_dk and g4.fm50_dk = g1.fm50_dk
            and g4.mola_dk = g1.mola_dk
     from test.gk('DD04') g4, test.gk('DD01') g1));

-- ---------------------------------------------------------------------
-- 4) Kilitli puantaj: devamsız / raporlu günün dakikası puantaj satırına girmez
-- ---------------------------------------------------------------------
set local role authenticated;
select test.oturum('dd_ik@ornek.test');
select pdks.ay_kilitle(2026::smallint, 8::smallint);
reset role;
select test.dogrula('kilitli Ağustos: DD02 satırında 1 devamsız gün, 0 çalışma ve 0 FM50 dakikası',
    (select devamsiz_gun = 1 and calisma_dk = 0 and fm50_dk = 0 from test.ps('DD02')));
select test.dogrula('kilitli Ağustos: DD03 1 raporlu gün, 0 dakika · DD01 dakikaları duruyor',
    (select raporlu_gun = 1 and calisma_dk = 0 from test.ps('DD03'))
    and (select calisma_dk = (test.gk('DD01')).calisma_dk from test.ps('DD01')));

do $$ begin raise notice 'DURUM DÜZELTMESİ TESTLERİ GEÇTİ'; end $$;
rollback;
