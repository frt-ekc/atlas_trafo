-- =====================================================================
-- Geriye dönük vardiya planı onayı ve reddi testleri (20261203010000_plan_onayi.sql)
--   onay → gün hemen oluşur / düzelir · ret → gün değişmez · ret + işlenmemiş gün → kilit reddeder ·
--   onay bekleyen + işlenmemiş gün → kilit reddeder (zorla da) · görevler ayrılığı ·
--   kilitli ayda onay → fark satırı (dakika farkı doğru)
-- Testin kendi sahte verisi (Ekim 2026) kullanılır; örnek veri yüklü olsun olmasın çalışır.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/plan_onayi_testi.sql
-- =====================================================================
\pset tuples_only on
\pset format unaligned
begin;
-- Bu test Kasım / Aralık 2026'yı kilitler; ay bitmeden kilit olmadığı için (T-89) bugün 15.01.2027 kabul edilir
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
create function test.v(p text) returns smallint language sql security definer as $$
    select id from pdks.vardiya_tanim where kod = p $$;
create function test.gk(p_sicil text) returns pdks.gun_kaydi language sql security definer as $$
    select * from pdks.gun_kaydi where calisan_id = test.c(p_sicil) and is_gunu = '2026-10-05' $$;
create function test.plan(p_sicil text) returns pdks.vardiya_plani language sql security definer as $$
    select * from pdks.vardiya_plani where calisan_id = test.c(p_sicil) and tarih = '2026-10-05' $$;
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
--   Herkes 5 Ekim'de 07:55–16:05 çalıştı (PO04: 07:55–17:05).
--   PO01, PO02: plan yanlışlıkla 08-17 (GUNDUZ), işlendi · PO04: 08-17 doğru, işlendi
--   PO03, PO05: geriye dönük 08-16 planı gece işinden ÖNCE girildi, İK onayı bekliyor
insert into pdks.departman (ad) values ('PO Üretim'), ('PO İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = d), '2025-01-01'
from (values ('POA1', 'PO Üretim'), ('PO01', 'PO Üretim'), ('PO02', 'PO Üretim'), ('PO03', 'PO Üretim'),
             ('PO04', 'PO Üretim'), ('PO05', 'PO Üretim'), ('POI1', 'PO İdari'), ('POI2', 'PO İdari')) v(s, d);
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('PO İK 1', 'po_ik1@ornek.test', 'ik',   test.c('POI1'), '00000000-0000-0000-0000-0000000000e1'),
    ('PO İK 2', 'po_ik2@ornek.test', 'ik',   test.c('POI2'), '00000000-0000-0000-0000-0000000000e2'),
    ('PO Amir', 'po_amir@ornek.test', 'amir', test.c('POA1'), '00000000-0000-0000-0000-0000000000e3');
update pdks.departman set amir_id = test.k('po_amir@ornek.test') where ad = 'PO Üretim';
insert into pdks.kart (kart_no, calisan_id)
select 'PO-' || s, test.c(s) from unnest(array['PO01', 'PO02', 'PO03', 'PO04', 'PO05']) s;
insert into pdks.okuyucu (kod, ad, sistem) values ('PO-PDKS', 'PO PDKS', 'pdks');
insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id, giren_id, geriye_donuk, ik_onay_durumu)
values (test.c('PO01'), '2026-10-05', test.v('GUNDUZ'),   test.k('po_ik1@ornek.test'), false, 'gerekmez'),
       (test.c('PO02'), '2026-10-05', test.v('GUNDUZ'),   test.k('po_ik1@ornek.test'), false, 'gerekmez'),
       (test.c('PO04'), '2026-10-05', test.v('GUNDUZ'),   test.k('po_ik1@ornek.test'), false, 'gerekmez'),
       (test.c('PO03'), '2026-10-05', test.v('GUNDUZ_8'), test.k('po_ik1@ornek.test'), true,  'bekliyor'),
       (test.c('PO05'), '2026-10-05', test.v('GUNDUZ_8'), test.k('po_ik1@ornek.test'), true,  'bekliyor');
insert into pdks.aktarim (kaynak, dosya_adi, dosya_ozeti, veri_tarihi) values ('pdks', 'po.csv', 'po-pdks-1', '2026-10-05');
insert into pdks.ham_okutma (aktarim_id, okuyucu_id, kart_no, okutma_zamani, yon)
select (select id from pdks.aktarim where dosya_ozeti = 'po-pdks-1'), (select id from pdks.okuyucu where kod = 'PO-PDKS'),
       'PO-' || s, z::timestamptz, y
from unnest(array['PO01', 'PO02', 'PO03', 'PO04', 'PO05']) s,
     lateral (values ('2026-10-05 07:55+03', 'giris'),
                     (case when s = 'PO04' then '2026-10-05 17:05+03' else '2026-10-05 16:05+03' end, 'cikis')) v(z, y);
select pdks.gece_isi_calistir('2026-10-05');

select test.dogrula('onay bekleyen plan gece işinde kullanılmadı: PO03 ve PO05 işlenmedi, diğerleri işlendi',
    (test.gk('PO03')).id is null and (test.gk('PO05')).id is null
    and (select count(*) from pdks.gun_kaydi g join pdks.calisan c on c.id = g.calisan_id
         where c.sicil_no in ('PO01', 'PO02', 'PO04') and g.durum = 'tamam') = 3);

-- ---------------------------------------------------------------------
-- Onay bekleyen planın işlenmemiş günü → kilit reddeder (zorla da)
-- ---------------------------------------------------------------------
set local role authenticated;
select test.oturum('po_ik1@ornek.test');
select test.hata('onay bekleyen planın işlenmemiş günü zorla geçilemez; mesaj "İK onayı bekleyen plan" der',
    '10/2026 döneminde işlenmemiş 2 planlı gün bulunuyor (2 çalışan, ilk gün 05.10.2026); 2 günün geriye dönük planı İK onayı bekliyor. Kilitlemeden önce bu günler işlenmelidir; İK onayı bekleyen plan onaylanmalı veya reddedilmelidir.',
    $$select pdks.ay_kilitle(2026::smallint, 10::smallint, true)$$);

-- ---------------------------------------------------------------------
-- Görevler ayrılığı: İK kendi çalışan kaydının planını onaylayamaz / reddedemez (Eylül: kilitler etkilenmez)
-- ---------------------------------------------------------------------
select test.oturum('po_ik2@ornek.test');
select pdks.vardiya_plani_gir(test.c('POI1'), '2026-09-15', test.v('BEYAZ'), 'İK 1 için geriye dönük plan');
select test.oturum('po_ik1@ornek.test');
select test.hata('İK kendi gününün planını onaylayamaz', 'kimse kendi kaydında işlem yapamaz (vardiya_plani.onay)',
    $$select pdks.vardiya_plani_onayla((select id from pdks.vardiya_plani where calisan_id = test.c('POI1') and tarih = '2026-09-15'), true)$$);
select test.hata('İK kendi gününün planını reddedemez', 'kimse kendi kaydında işlem yapamaz (vardiya_plani.onay)',
    $$select pdks.vardiya_plani_onayla((select id from pdks.vardiya_plani where calisan_id = test.c('POI1') and tarih = '2026-09-15'), false)$$);
reset role;
select test.dogrula('reddedilen onay denemeleri planı değiştirmedi (hâlâ onay bekliyor)',
    (select ik_onay_durumu = 'bekliyor' from pdks.vardiya_plani where calisan_id = test.c('POI1') and tarih = '2026-09-15'));

-- ---------------------------------------------------------------------
-- Onay → gün hemen düzelir (işlenmiş gün)
-- ---------------------------------------------------------------------
set local role authenticated;
select test.oturum('po_amir@ornek.test');
select pdks.vardiya_plani_gir(test.c('PO02'), '2026-10-05', test.v('GUNDUZ_8'), 'Aslında 08-16 çalıştı');
select test.dogrula('geriye dönük plan girilince gün değişmez (PO02 08-17 kalır, erken çıkış 55)',
    (test.plan('PO02')).ik_onay_durumu = 'bekliyor'
    and (select vardiya_id = test.v('GUNDUZ') and erken_cikis_dk = 55 from test.gk('PO02')));
select test.oturum('po_ik1@ornek.test');
select pdks.vardiya_plani_onayla((test.plan('PO02')).id, true);
select test.dogrula('onay: işlenmiş gün hemen yeni plana göre düzeldi ve hesaplandı (PO02 08-16, erken 0, 420 dk)',
    (select vardiya_id = test.v('GUNDUZ_8') and erken_cikis_dk = 0 and calisma_dk = 420 and hesap_tamam
     from test.gk('PO02')));
select test.dogrula('onayın düzeltme izi: vardiya, İK kaynaklı, gerekçede plan onayı',
    exists (select 1 from pdks.duzeltme where gun_kaydi_id = (test.gk('PO02')).id and alan = 'vardiya_id'
            and kaynak = 'ik' and yapan_id = test.k('po_ik1@ornek.test') and gerekce like 'Geriye dönük vardiya planı onaylandı%'));

-- ---------------------------------------------------------------------
-- Onay → gün hemen oluşur (onay beklediği için işlenmemiş gün)
-- ---------------------------------------------------------------------
select test.hata('planı giren İK kendi girdiği planı onaylayamaz', 'kendi girdiğiniz planı',
    $$select pdks.vardiya_plani_onayla((test.plan('PO03')).id, true)$$);
select test.oturum('po_ik2@ornek.test');
select pdks.vardiya_plani_onayla((test.plan('PO03')).id, true);
select test.dogrula('onay: işlenmemiş gün hemen gece işinden geçti (PO03 08-16, tamam, 420 dk)',
    (select vardiya_id = test.v('GUNDUZ_8') and durum = 'tamam' and calisma_dk = 420 and hesap_tamam from test.gk('PO03')));

-- ---------------------------------------------------------------------
-- Ret → gün değişmez
-- ---------------------------------------------------------------------
select test.oturum('po_ik1@ornek.test');
select pdks.vardiya_plani_gir(test.c('PO04'), '2026-10-05', test.v('GUNDUZ_8'), 'Yanlış giriş denemesi');
select test.oturum('po_ik2@ornek.test');
select pdks.vardiya_plani_onayla((test.plan('PO04')).id, false);
-- T-49: ret önceki geçerli plana döner (reddedilen değişiklik vardiya_plani_gecmisi'nde kalır)
select test.dogrula('ret: işlenmiş gün değişmedi, düzeltme yazılmadı, plan GÜNDÜZ''e döndü (PO04 08-17 kalır)',
    (test.plan('PO04')).ik_onay_durumu = 'gerekmez' and (test.plan('PO04')).vardiya_id = test.v('GUNDUZ')
    and (select vardiya_id = test.v('GUNDUZ') and durum = 'tamam' and calisma_dk = 480 from test.gk('PO04'))
    and not exists (select 1 from pdks.duzeltme where gun_kaydi_id = (test.gk('PO04')).id));

-- ---------------------------------------------------------------------
-- Ret + işlenmemiş gün → kilit reddeder (zorla da); doğru plan girilip onaylanınca geçer
-- ---------------------------------------------------------------------
select pdks.vardiya_plani_onayla((test.plan('PO05')).id, false);
select test.dogrula('ret: işlenmemiş gün işlenmemiş kaldı (PO05)', (test.gk('PO05')).id is null);
select test.oturum('po_ik1@ornek.test');
select test.hata('reddedilmiş planın işlenmemiş günü varken kilit reddedilir; mesaj reddedilmiş planı söyler (zorla da)',
    '10/2026 döneminde işlenmemiş 1 planlı gün bulunuyor (1 çalışan, ilk gün 05.10.2026); 1 günün geriye dönük planı reddedilmiş',
    $$select pdks.ay_kilitle(2026::smallint, 10::smallint, true)$$);
select pdks.vardiya_plani_gir(test.c('PO05'), '2026-10-05', test.v('GUNDUZ_8'), 'Doğru plan');
select test.dogrula('doğru plan girilince yeniden İK onayı bekler (geriye dönük)',
    (test.plan('PO05')).ik_onay_durumu = 'bekliyor' and (test.plan('PO05')).giren_id = test.k('po_ik1@ornek.test'));
select test.oturum('po_ik2@ornek.test');
select pdks.vardiya_plani_onayla((test.plan('PO05')).id, true);
select test.dogrula('doğru planın onayıyla gün oluştu (PO05 tamam)', (test.gk('PO05')).durum = 'tamam');

-- ---------------------------------------------------------------------
-- Onay bekleyen plan zorla geçilebilir; kilitli ayda onay → fark satırı
-- ---------------------------------------------------------------------
select test.oturum('po_amir@ornek.test');
select pdks.vardiya_plani_gir(test.c('PO01'), '2026-10-05', test.v('GUNDUZ_8'), 'Aslında 08-16 çalıştı');
select test.oturum('po_ik1@ornek.test');
select test.hata('onay bekleyen plan varken zorlamadan kilit reddedilir', 'İK onayı bekleyen 1 geriye dönük vardiya planı',
    $$select pdks.ay_kilitle(2026::smallint, 10::smallint)$$);
select test.dogrula('onay bekleyen plan zorla geçildi; kilit özeti bunu sayar',
    (select r -> 'zorla_gecilen' ->> 'bekleyen_plan_onayi' = '1' and r ->> 'kodsuz_gun' = '0'
     from (select pdks.ay_kilitle(2026::smallint, 10::smallint, true) as r) x));
reset role;
create temp table once as
select g.calisma_dk, g.erken_cikis_dk, h.calisma_dk as yeni_calisma, h.erken_cikis_dk as yeni_erken
from pdks.gun_kaydi g
cross join lateral pdks.vardiya_araligi(test.v('GUNDUZ_8'), g.is_gunu) a
cross join lateral pdks.gun_hesabi(g.calisan_id, g.is_gunu, a.p_bas, a.p_bit, g.giris_zamani, g.cikis_zamani, test.v('GUNDUZ_8')) h
where g.id = (test.gk('PO01')).id;
set local role authenticated;
select test.oturum('po_ik2@ornek.test');
select pdks.vardiya_plani_onayla((test.plan('PO01')).id, true);
reset role;
select test.dogrula('kilitli ayda onay: gün değişmedi, vardiya düzeltmesi Kasım''a fark satırı',
    (select vardiya_id = test.v('GUNDUZ') and calisma_dk = 425 and erken_cikis_dk = 55 from test.gk('PO01'))
    and exists (select 1 from pdks.duzeltme d join pdks.donem p on p.id = d.hedef_donem_id
                where d.gun_kaydi_id = (test.gk('PO01')).id and d.alan = 'vardiya_id' and d.fark_satiri and p.ay = 11));
-- Kasım kilitlenince fark satırı yazılır. Örnek veri yüklüyse onun Kasım planları bu testte işlenmez:
-- kilit (20261201010000) bunları işlenmemiş gün sayar; test yalnızca kendi verisine bakar.
delete from pdks.vardiya_plani where tarih between '2026-11-01' and '2026-11-30';
set local role authenticated;
select test.oturum('po_ik1@ornek.test');
select pdks.ay_kilitle(2026::smallint, 11::smallint, true);
reset role;
select test.dogrula('fark satırının dakika farkı doğru: NÇ ve erken çıkış, gün iki planla ayrı ayrı hesaplanınca çıkan fark kadar',
    (select o.yeni_calisma - o.calisma_dk = -5 and o.yeni_erken - o.erken_cikis_dk = -55 from once o)
    and (select p.calisma_dk = (select yeni_calisma - calisma_dk from once)
                and p.erken_cikis_dk = (select yeni_erken - erken_cikis_dk from once)
         from pdks.puantaj_satiri p join pdks.donem d on d.id = p.donem_id
         where d.yil = 2026 and d.ay = 11 and p.calisan_id = test.c('PO01') and p.satir_turu = 'fark')
    and exists (select 1 from pdks.v_puantaj_aktarim where donem = '2026-11' and sicil = 'PO01'
                and satir_turu = 'fark' and kaynak_donem = '2026-10' and kod = 'NÇ' and dakika = -5));
select test.dogrula('kilitli Ekim''in puantajı değişmedi (PO01 NÇ 425 dk)',
    exists (select 1 from pdks.v_puantaj_aktarim where donem = '2026-10' and sicil = 'PO01'
            and satir_turu = 'normal' and kod = 'NÇ' and dakika = 425));

do $$ begin raise notice 'PLAN ONAYI TESTLERİ GEÇTİ'; end $$;
rollback;
