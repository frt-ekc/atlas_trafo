-- =====================================================================
-- Hesabı tamamlanmamış gün her yerde "bekliyor" sayılır (20261231040000_hesapsiz_gun.sql, T-91)
--   Durumu "tamam" ama hesabı yapılmamış (hesap_tamam = false) gün puantaj satırında ve yönetici
--   panelinde "çalışılan" sayılıyordu; kod listesi (kalem, ERP) onu saymıyordu. Artık üçü aynı:
--   çalışılan değil, bekleyen. Zorla kilitte satır ile kalemler aynı sayıyı yazar.
-- Testin kendi sahte verisi kullanılır; örnek veri yüklü olsun olmasın çalışır.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/hesapsiz_gun_testi.sql
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
create function test.c(p text) returns bigint language sql security definer as $$
    select id from pdks.calisan where sicil_no = p $$;
create function test.oturum(p_eposta text) returns void language sql security definer as $$
    select set_config('request.jwt.claims',
        json_build_object('sub', (select auth_kullanici_id from pdks.kullanici where eposta = p_eposta),
                          'role', 'authenticated')::text, true) $$;
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
--   HS Üretim, Eylül 2026, gündüz vardiyası 08:00–16:00.
--   HS01: 8 ve 9 Eylül hesaplanmış tamam gün; 10 Eylül İK saatleri yazmış, durum tamam, ama günün
--         açık sorusu var: gün hesaplanamıyor, kilit de onu hesaplayamaz (rapordaki Q4 vakası)
--   HS02: 8 ve 9 Eylül hesaplanmış tamam gün (karşılaştırma)
--   HS03: 10 Eylül durum tamam, hesap yapılmamış; testte gun_hesapla ile hesaplanır
--   HSI1: İK uzmanı (zorla kilit); HSA1: departman amiri
insert into pdks.departman (ad) values ('HS Üretim'), ('HS İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = d), '2025-01-01'
from (values ('HS01', 'HS Üretim'), ('HS02', 'HS Üretim'), ('HS03', 'HS Üretim'), ('HSA1', 'HS Üretim'), ('HSI1', 'HS İdari')) v(s, d);
insert into pdks.kullanici (eposta, rol, calisan_id, auth_kullanici_id)
values ('hs_ik@ornek.test', 'ik', test.c('HSI1'), '00000000-0000-0000-0000-0000000091a1'),
       ('hs_amir@ornek.test', 'amir', test.c('HSA1'), '00000000-0000-0000-0000-0000000091a2');
insert into pdks.gun_kaydi (calisan_id, is_gunu, vardiya_id, planli_baslangic, planli_bitis, durum, giris_zamani, cikis_zamani,
                            calisma_dk, gec_kalma_dk, erken_cikis_dk, fazla_mesai_dk, fm50_dk, fm100_dk, gece_calisma_dk,
                            saatlik_izin_dk, mola_dk, hesap_tamam)
select test.c(s), d, (select id from pdks.vardiya_tanim where kod = 'GUNDUZ_8'), d + time '08:00', d + time '16:00', 'tamam',
       d + time '08:00', d + time '16:00',
       h.dk, h.sifir, h.sifir, h.sifir, h.sifir, h.sifir, h.sifir, h.sifir, h.mola, (h.dk is not null)
from (values ('HS01', date '2026-09-08', true), ('HS01', date '2026-09-09', true), ('HS01', date '2026-09-10', false),
             ('HS02', date '2026-09-08', true), ('HS02', date '2026-09-09', true), ('HS03', date '2026-09-10', false)) v(s, d, hesaplandi)
cross join lateral (select case when hesaplandi then 450 end as dk, case when hesaplandi then 0 end as sifir,
                           case when hesaplandi then 30 end as mola) h;

insert into pdks.amir_sorusu (gun_kaydi_id, soru_turu, aciklama, atanan_id, son_cevap_tarihi)
values ((select id from pdks.gun_kaydi where calisan_id = test.c('HS01') and is_gunu = '2026-09-10'), 'giris_yok', 'Deneme sorusu',
        (select id from pdks.kullanici where eposta = 'hs_amir@ornek.test'), '2026-09-13');

create temp table canli as
select c.sicil_no, v.* from pdks.v_puantaj_canli v join pdks.calisan c on c.id = v.calisan_id
where v.yil = 2026 and v.ay = 9 and c.sicil_no like 'HS0%';

-- 1) Canlı puantaj ve yönetici paneli ------------------------------------------------------
select test.dogrula('HS01 canlı puantaj: hesaplanmamış 10 Eylül çalışılan sayılmaz (2), bekleyen sayılır (1)',
    (select calisilan_gun = 2 and bekleyen_gun = 1 and calisma_dk = 900 from canli where sicil_no = 'HS01'));
select test.dogrula('HS01 canlı puantaj kod listesiyle aynı: çalışılan gün = NÇ günü',
    (select calisilan_gun from canli where sicil_no = 'HS01')
    = (select coalesce(sum(gun), 0) from pdks.gun_kodlari_hesapla(2026, 9) where calisan_id = test.c('HS01') and kod in ('NÇ', 'FM100')));
select test.dogrula('HS02 (hepsi hesaplanmış) değişmedi: çalışılan 2, bekleyen 0',
    (select calisilan_gun = 2 and bekleyen_gun = 0 from canli where sicil_no = 'HS02'));
select test.dogrula('yönetici paneli: HS Üretim çalışılan 4 (2 + 2 + 0), bekleyen 2; aynı gün iki kez sayılmaz',
    (select calisilan_gun = 4 and bekleyen_gun = 2 from pdks.v_departman_ozet where departman = 'HS Üretim' and yil = 2026 and ay = 9));

-- 2) Hesap tamamlanınca gün çalışılan olur ---------------------------------------------------
select test.dogrula('HS03 hesaplanmadan önce: çalışılan 0, bekleyen 1',
    (select calisilan_gun = 0 and bekleyen_gun = 1 from canli where sicil_no = 'HS03'));
select pdks.gun_hesapla((select id from pdks.gun_kaydi where calisan_id = test.c('HS03') and is_gunu = '2026-09-10')) \g /dev/null
select test.dogrula('HS03 10 Eylül hesaplanınca (gun_hesapla): çalışılan 1, bekleyen 0',
    (select calisilan_gun = 1 and bekleyen_gun = 0 from pdks.v_puantaj_canli where yil = 2026 and ay = 9 and calisan_id = test.c('HS03')));

-- 3) Zorla kilit: satır ile kalemler aynı sayıyı yazar --------------------------------------
--    Kilit hesaplanmamış günleri önce hesaplar; HS01'in 10 Eylül'ü açık sorusu yüzünden hesaplanamaz,
--    zorla kilit soruyu geçer.
set local role authenticated;
select test.oturum('hs_ik@ornek.test');
select pdks.ay_kilitle(2026::smallint, 9::smallint, true) \g /dev/null
reset role;
select test.dogrula('zorla kilit: HS01 satırı çalışılan 2, NÇ kalemi 2 gün (önce satır 3, kalem 2)',
    (select s.calisilan_gun = 2 and k.gun = 2
     from pdks.puantaj_satiri s
     join pdks.donem d on d.id = s.donem_id and d.yil = 2026 and d.ay = 9
     join pdks.puantaj_kalemi k on k.puantaj_satiri_id = s.id and k.kod = 'NÇ'
     where s.calisan_id = test.c('HS01') and s.satir_turu = 'normal'));
select test.dogrula('zorla kilit: HS Üretim''in bütün satırlarında çalışılan gün = NÇ + FM100 kalem günü',
    not exists (
        select 1 from pdks.puantaj_satiri s
        join pdks.donem d on d.id = s.donem_id and d.yil = 2026 and d.ay = 9
        join pdks.calisan c on c.id = s.calisan_id and c.sicil_no like 'HS0%'
        where s.satir_turu = 'normal'
          and s.calisilan_gun <> coalesce((select sum(k.gun) from pdks.puantaj_kalemi k
                                           where k.puantaj_satiri_id = s.id and k.kod in ('NÇ', 'FM100')), 0)));

\echo 'TÜM TESTLER GEÇTİ'
rollback;
