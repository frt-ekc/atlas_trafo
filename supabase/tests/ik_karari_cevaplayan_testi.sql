-- =====================================================================
-- İK kararı amirin cevabını silmez (20261231020000_ik_karari_cevaplayan.sql, T-32)
--   * Amir "gelmedi" / "bilmiyorum" der, İK karar verir: cevaplayan amir kalır, kararı veren ve
--     zamanı ayrı sütunlarda (ik_karar_veren_id, ik_karar_zamani).
--   * "Yalnızca İK kapatır" ve görevler ayrılığı yeni sütunla da korunur.
--   * İşten çıkış soruyu kapatırken amirin cevabına dokunmaz (kapatan / kapanış nedeni).
-- Testin kendi sahte verisi kullanılır; örnek veri yüklü olsun olmasın çalışır.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/ik_karari_cevaplayan_testi.sql
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
create function test.k(p text) returns bigint language sql security definer as $$
    select id from pdks.kullanici where eposta = p $$;
create function test.g(p text) returns bigint language sql security definer as $$
    select id from pdks.gun_kaydi where calisan_id = test.c(p) and is_gunu = '2026-08-05' $$;
create function test.s(p text) returns bigint language sql security definer as $$
    select id from pdks.amir_sorusu where gun_kaydi_id = test.g(p) $$;
create function test.oturum(p_eposta text) returns void language sql security definer as $$
    select set_config('request.jwt.claims',
        json_build_object('sub', (select auth_kullanici_id from pdks.kullanici where eposta = p_eposta),
                          'role', 'authenticated')::text, true) $$;
-- Sorgu hata verirse mesajını döner, vermezse null
create function test.hata(p_sorgu text) returns text language plpgsql as $$
begin
    execute p_sorgu;
    return null;
exception when others then
    return sqlerrm;
end $$;
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
--   IC Üretim: amiri ICA1. IC01 amir "gelmedi" → İK devamsız; IC02 amir "bilmiyorum" → İK geldi;
--   IC03 amir cevap vermedi → İK geldi; IC04 amir "gelmedi" → İK işten çıkış girer;
--   ICI1 İK uzmanının kendi kaydı (görevler ayrılığı), ICI2 ikinci İK
insert into pdks.departman (ad) values ('IC Üretim'), ('IC İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = d), '2025-01-01'
from (values ('ICA1', 'IC Üretim'), ('IC01', 'IC Üretim'), ('IC02', 'IC Üretim'), ('IC03', 'IC Üretim'), ('IC04', 'IC Üretim'),
             ('ICI1', 'IC Üretim'), ('ICI2', 'IC İdari')) v(s, d);
insert into pdks.kullanici (eposta, rol, calisan_id, auth_kullanici_id)
select e, r, test.c(s), u::uuid
from (values ('ic_amir@ornek.test', 'amir', 'ICA1', '00000000-0000-0000-0000-0000000032a1'),
             ('ic_ik1@ornek.test',  'ik',   'ICI1', '00000000-0000-0000-0000-0000000032a2'),
             ('ic_ik2@ornek.test',  'ik',   'ICI2', '00000000-0000-0000-0000-0000000032a3')) v(e, r, s, u);
update pdks.departman set amir_id = test.k('ic_amir@ornek.test') where ad = 'IC Üretim';
insert into pdks.gun_kaydi (calisan_id, is_gunu, vardiya_id, planli_baslangic, planli_bitis, durum)
select test.c(s), '2026-08-05', (select id from pdks.vardiya_tanim where kod = 'GUNDUZ_8'),
       '2026-08-05 08:00+03', '2026-08-05 16:00+03', 'soru_bekliyor'
from unnest(array['IC01', 'IC02', 'IC03', 'IC04', 'ICI1']) s;
insert into pdks.amir_sorusu (gun_kaydi_id, soru_turu, aciklama, atanan_id, son_cevap_tarihi)
select test.g(s), 'hic_kayit_yok', 'Hiç okutma yok', test.k('ic_amir@ornek.test'), '2026-08-08'
from unnest(array['IC01', 'IC02', 'IC03', 'IC04', 'ICI1']) s;

set local role authenticated;
select test.oturum('ic_amir@ornek.test');
select pdks.soru_cevapla(test.s('IC01'), 'gelmedi', p_aciklama => 'Sabah görmedim') \g /dev/null
select pdks.soru_cevapla(test.s('IC02'), 'bilmiyorum') \g /dev/null
select pdks.soru_cevapla(test.s('IC04'), 'gelmedi') \g /dev/null
select pdks.soru_cevapla(test.s('ICI1'), 'gelmedi') \g /dev/null
reset role;
create temp table ic_once as select id, cevap_zamani from pdks.amir_sorusu where id in (test.s('IC01'), test.s('IC02'));

set local role authenticated;
select test.oturum('ic_ik1@ornek.test');
select pdks.soru_ik_karari(test.s('IC01'), true, 'Kapı ve servis kaydı yok') \g /dev/null
select pdks.soru_ik_karari(test.s('IC02'), false, 'Kapı kaydı 08:02, servis 16:10', '2026-08-05 08:02+03', '2026-08-05 16:10+03') \g /dev/null
select pdks.soru_ik_karari(test.s('IC03'), false, 'Kapı kaydı 08:05, servis 16:10', '2026-08-05 08:05+03', '2026-08-05 16:10+03') \g /dev/null
reset role;

-- 1) Bulgudaki durum: İK kararından sonra amirin cevabı ve adı kalır -----------------------------
select test.dogrula('amir "gelmedi" dedi, İK devamsız kararı verdi: cevaplayan hâlâ amir',
    (select cevap = 'gelmedi' and cevaplayan_id = test.k('ic_amir@ornek.test') and cevap_aciklama = 'Sabah görmedim'
     from pdks.amir_sorusu where id = test.s('IC01')));
select test.dogrula('İK kararı ayrı sütunlarda: kararı veren İK, karar zamanı dolu, sonuç devamsız, soru kapandı',
    (select ik_karar_veren_id = test.k('ic_ik1@ornek.test') and ik_karar_zamani is not null
            and ik_karari = 'devamsiz' and durum = 'kapandi'
     from pdks.amir_sorusu where id = test.s('IC01')));
select test.dogrula('amirin cevap zamanı İK kararıyla değişmedi',
    (select s.cevap_zamani = o.cevap_zamani from pdks.amir_sorusu s join ic_once o using (id) where s.id = test.s('IC01')));
select test.dogrula('amir "bilmiyorum" dedi, İK "geldi" dedi: cevaplayan amir, kararı veren İK',
    (select cevap = 'bilmiyorum' and cevaplayan_id = test.k('ic_amir@ornek.test')
            and ik_karar_veren_id = test.k('ic_ik1@ornek.test') and ik_karari = 'geldi'
     from pdks.amir_sorusu where id = test.s('IC02')));
select test.dogrula('amir cevap vermeden İK karar verdi: cevap ve cevaplayan boş, kararı veren İK',
    (select cevap is null and cevaplayan_id is null and ik_karar_veren_id = test.k('ic_ik1@ornek.test') and ik_karari = 'geldi'
     from pdks.amir_sorusu where id = test.s('IC03')));
select test.dogrula('devamsız düzeltmesinin yapanı İK, soruya bağlı (karar dayanağı izlenebilir)',
    exists (select 1 from pdks.duzeltme where soru_id = test.s('IC01') and alan = 'durum' and yeni_deger = 'devamsiz'
            and yapan_id = test.k('ic_ik1@ornek.test')));

-- 2) Kurallar yeni sütunla da korunur --------------------------------------------------------
set local role authenticated;
select test.oturum('ic_ik1@ornek.test');
select test.dogrula('İK kendi kaydındaki soruya karar veremez (görevler ayrılığı)',
    test.hata($q$select pdks.soru_ik_karari(test.s('ICI1'), true, 'Deneme')$q$) like 'Görevler ayrılığı%');
reset role;
select test.dogrula('kendi kaydının sorusuna kararı veren olarak doğrudan da yazılamaz (trigger, amir_sorusu.ik_karar_veren_id)',
    test.hata($q$update pdks.amir_sorusu set ik_karar_veren_id = test.k('ic_ik1@ornek.test') where id = test.s('ICI1')$q$)
        like 'Görevler ayrılığı%amir_sorusu.ik_karar_veren_id%');
select test.dogrula('İK kararı bekleyen soruyu İK olmayan biri kapatamaz (kararı veren amir yazılsa da)',
    test.hata($q$update pdks.amir_sorusu set durum = 'kapandi', ik_karari = 'geldi', ik_karar_veren_id = test.k('ic_amir@ornek.test'),
                 ik_karar_zamani = now() where id = test.s('ICI1')$q$) = 'Bu soruyu yalnızca İK kapatabilir.');
select test.dogrula('kapatırken kararı veren yazılmazsa (eski yol: cevaplayana İK) soru kapanmaz',
    test.hata($q$update pdks.amir_sorusu set durum = 'kapandi', cevaplayan_id = test.k('ic_ik2@ornek.test') where id = test.s('ICI1')$q$)
        = 'Bu soruyu yalnızca İK kapatabilir.');
select test.dogrula('İK kararı sonucu, kararı veren ve zamanı birlikte dolu ya da boş olmalı',
    test.hata($q$update pdks.amir_sorusu set ik_karari = 'geldi' where id = test.s('IC04')$q$) like '%amir_sorusu_ik_karari_tam%');
set local role authenticated;
select test.oturum('ic_ik2@ornek.test');
select test.dogrula('başka İK, ICI1''in sorusuna karar verebilir',
    test.hata($q$select pdks.soru_ik_karari(test.s('ICI1'), true, 'Kayıt yok')$q$) is null);
reset role;
select test.dogrula('ICI1: cevaplayan amir, kararı veren ikinci İK',
    (select cevaplayan_id = test.k('ic_amir@ornek.test') and ik_karar_veren_id = test.k('ic_ik2@ornek.test')
     from pdks.amir_sorusu where id = test.s('ICI1')));

-- 3) İşten çıkış açık soruyu kapatır, amirin cevabına dokunmaz --------------------------------
set local role authenticated;
select test.oturum('ic_ik1@ornek.test');
select pdks.isten_cikis_gir(test.c('IC04'), '2026-08-04', 'İstifa') \g /dev/null
reset role;
select test.dogrula('işten çıkış: soru kapandı, cevaplayan amir ve cevabı "gelmedi" kaldı',
    (select durum = 'kapandi' and cevap = 'gelmedi' and cevaplayan_id = test.k('ic_amir@ornek.test') and cevap_aciklama is null
     from pdks.amir_sorusu where id = test.s('IC04')));
select test.dogrula('işten çıkış: kapatan İK, kapanış nedeni "İşten çıkış (04.08.2026)", önceki durum İK kararı bekliyor',
    (select kapatan_id = test.k('ic_ik1@ornek.test') and kapanis_nedeni = 'İşten çıkış (04.08.2026)'
            and kapanis_zamani is not null and onceki_durum = 'ik_karari_bekliyor' and ik_karari is null
     from pdks.amir_sorusu where id = test.s('IC04')));
select test.dogrula('işten çıkış nedeni ("İstifa") amirin okuyabildiği soruya yazılmadı, düzeltme gerekçesinde',
    (select position('İstifa' in concat(cevap_aciklama, kapanis_nedeni)) = 0 from pdks.amir_sorusu where id = test.s('IC04'))
    and exists (select 1 from pdks.duzeltme where gun_kaydi_id = test.g('IC04') and gerekce = 'İşten çıkış (04.08.2026): İstifa'));

-- 4) Hiçbir kayıtta İK kararı kararı verensiz kalmadı (eski kayıtlar da taşındı) --------------
select test.dogrula('İK kararı olan her soruda kararı veren ve zamanı dolu',
    not exists (select 1 from pdks.amir_sorusu where ik_karari is not null and (ik_karar_veren_id is null or ik_karar_zamani is null)));

\echo 'TÜM TESTLER GEÇTİ'
rollback;
