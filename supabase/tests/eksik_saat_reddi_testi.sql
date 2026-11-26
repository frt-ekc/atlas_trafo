-- =====================================================================
-- Tek saatli cevap günü askıda bırakmaz (20261231030000_eksik_saat_reddi.sql, T-41)
--   Amirin cevabı ya da İK'nın "geldi" kararı uygulandığında günde hem giriş hem çıkış olmalı;
--   biri eksik kalacaksa cevap reddedilir, soru açık kalır. Kural soru türüne değil sonuca bakar.
--   Kilitli ayda saat fark satırındadır; kural oradaki saati de sayar.
-- Testin kendi sahte verisi kullanılır; örnek veri yüklü olsun olmasın çalışır.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/eksik_saat_reddi_testi.sql
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
    select id from pdks.gun_kaydi where calisan_id = test.c(p) $$;
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
-- Sorunun ve günün durumu (RLS'siz okunur)
create function test.soru_durumu(p text) returns text language sql security definer as $$
    select durum from pdks.amir_sorusu where id = test.s(p) $$;
create function test.gun(p text) returns pdks.gun_kaydi language sql security definer as $$
    select * from pdks.gun_kaydi where id = test.g(p) $$;
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
--   ES Üretim, amiri ESA1; ESI1 İK. Gündüz vardiyası 08:00–16:00, 5 Ağustos 2026 (açık ay).
--   ES01 giriş yok (PDKS çıkışı 16:05)          → A: yalnızca çıkış reddedilir; B: giriş yeter
--   ES02 kanıt vardiya sonrası (hiç saat yok)    → C: yalnızca çıkış reddedilir, ikisiyle kabul
--   ES03 hiç kayıt yok                            → "saat doğru": iki saat plandan, kabul
--   ES04 çıkış yok (PDKS girişi 08:02)            → "kart unuttu": çıkış plandan, kabul
--   ES05 kanıt vardiya sonrası (hiç saat yok)    → "saat doğru": yalnızca giriş yazılırdı, reddedilir
--   ES06 hiç kayıt yok, amir "bilmiyorum"        → İK "geldi" tek saatle reddedilir, ikisiyle kabul
--   ES07 hiç kayıt yok, amir "gelmedi"           → saat istemez; İK "devamsız" saat istemez
--   ES08 giriş yok, 15 Temmuz (kilitli ay)       → İK girişi fark satırında; amirin yalnızca çıkışı kabul
insert into pdks.departman (ad) values ('ES Üretim'), ('ES İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = d), '2025-01-01'
from (values ('ESA1', 'ES Üretim'), ('ES01', 'ES Üretim'), ('ES02', 'ES Üretim'), ('ES03', 'ES Üretim'), ('ES04', 'ES Üretim'),
             ('ES05', 'ES Üretim'), ('ES06', 'ES Üretim'), ('ES07', 'ES Üretim'), ('ES08', 'ES Üretim'), ('ESI1', 'ES İdari')) v(s, d);
insert into pdks.kullanici (eposta, rol, calisan_id, auth_kullanici_id)
select e, r, test.c(s), u::uuid
from (values ('es_amir@ornek.test', 'amir', 'ESA1', '00000000-0000-0000-0000-0000000041b1'),
             ('es_ik@ornek.test',   'ik',   'ESI1', '00000000-0000-0000-0000-0000000041b2')) v(e, r, s, u);
update pdks.departman set amir_id = test.k('es_amir@ornek.test') where ad = 'ES Üretim';
insert into pdks.gun_kaydi (calisan_id, is_gunu, vardiya_id, planli_baslangic, planli_bitis, durum,
                            giris_zamani, giris_kaynagi, cikis_zamani, cikis_kaynagi)
select test.c(s), g::date, (select id from pdks.vardiya_tanim where kod = 'GUNDUZ_8'),
       (g || ' 08:00+03')::timestamptz, (g || ' 16:00+03')::timestamptz, 'soru_bekliyor',
       gi::timestamptz, case when gi is not null then 'pdks' end, ci::timestamptz, case when ci is not null then 'pdks' end
from (values ('ES01', '2026-08-05', null, '2026-08-05 16:05+03'),
             ('ES02', '2026-08-05', null, null),
             ('ES03', '2026-08-05', null, null),
             ('ES04', '2026-08-05', '2026-08-05 08:02+03', null),
             ('ES05', '2026-08-05', null, null),
             ('ES06', '2026-08-05', null, null),
             ('ES07', '2026-08-05', null, null),
             ('ES08', '2026-07-15', null, '2026-07-15 16:03+03')) v(s, g, gi, ci);
insert into pdks.amir_sorusu (gun_kaydi_id, soru_turu, aciklama, atanan_id, son_cevap_tarihi)
select test.g(s), t, 'Deneme sorusu', test.k('es_amir@ornek.test'), '2026-08-08'
from (values ('ES01', 'giris_yok'), ('ES02', 'kanit_vardiya_sonrasi'), ('ES03', 'hic_kayit_yok'), ('ES04', 'cikis_yok'),
             ('ES05', 'kanit_vardiya_sonrasi'), ('ES06', 'hic_kayit_yok'), ('ES07', 'hic_kayit_yok'), ('ES08', 'giris_yok')) v(s, t);

-- 1) Amirin cevabı ---------------------------------------------------------------------------
set local role authenticated;
select test.oturum('es_amir@ornek.test');
select test.dogrula('A) "giriş yok" sorusuna yalnızca çıkış (17:30): reddedilir, mesaj girişi ister',
    test.hata($q$select pdks.soru_cevapla(test.s('ES01'), 'geldi_saat_farkli', null, '2026-08-05 17:30+03')$q$)
        = 'Günde giriş saati yok; giriş saatini de girin.');
select test.dogrula('A) reddedilen cevaptan sonra soru açık, gün değişmedi',
    test.soru_durumu('ES01') = 'acik' and (test.gun('ES01')).cikis_zamani = '2026-08-05 16:05+03');
select test.dogrula('B) aynı soruya yalnızca giriş (08:10): çıkış PDKS''ten var, kabul edilir',
    test.hata($q$select pdks.soru_cevapla(test.s('ES01'), 'geldi_saat_farkli', '2026-08-05 08:10+03', null)$q$) is null);
select test.dogrula('B) soru cevaplandı, gün tamam ve hesaplandı (08:10–16:05)',
    test.soru_durumu('ES01') = 'cevaplandi'
    and (select durum = 'tamam' and hesap_tamam and giris_zamani = '2026-08-05 08:10+03' from test.gun('ES01')));
select test.dogrula('C) "kanıt vardiya sonrası" sorusuna yalnızca çıkış: reddedilir (ekran bu türde tek saati kabul ediyordu)',
    test.hata($q$select pdks.soru_cevapla(test.s('ES02'), 'geldi_saat_farkli', null, '2026-08-05 17:00+03')$q$)
        = 'Günde giriş saati yok; giriş saatini de girin.');
select test.dogrula('C) iki saatle kabul, gün hesaplandı',
    test.hata($q$select pdks.soru_cevapla(test.s('ES02'), 'geldi_saat_farkli', '2026-08-05 10:30+03', '2026-08-05 17:00+03')$q$) is null
    and (select durum = 'tamam' and hesap_tamam from test.gun('ES02')));
select test.dogrula('"hiç kayıt yok" + "saat doğru": iki saat plandan yazılır, kabul',
    test.hata($q$select pdks.soru_cevapla(test.s('ES03'), 'geldi_saat_dogru')$q$) is null
    and (select hesap_tamam and giris_zamani = '2026-08-05 08:00+03' and cikis_zamani = '2026-08-05 16:00+03' from test.gun('ES03')));
select test.dogrula('"çıkış yok" + "kart unuttu": çıkış plandan, giriş PDKS''ten; kabul',
    test.hata($q$select pdks.soru_cevapla(test.s('ES04'), 'kart_unuttu')$q$) is null
    and (select hesap_tamam from test.gun('ES04')));
select test.dogrula('"kanıt vardiya sonrası" + "saat doğru": plan yalnızca girişi doldurur, reddedilir ve "Saat farklı"yı önerir',
    test.hata($q$select pdks.soru_cevapla(test.s('ES05'), 'geldi_saat_dogru')$q$)
        = 'Günde çıkış saati yok; "Saat farklı" seçip çıkış saatini de girin.');
select test.dogrula('"gelmedi" saat istemez, İK kararına gider',
    test.hata($q$select pdks.soru_cevapla(test.s('ES07'), 'gelmedi')$q$) is null and test.soru_durumu('ES07') = 'ik_karari_bekliyor');
select pdks.soru_cevapla(test.s('ES06'), 'bilmiyorum') \g /dev/null

-- 2) İK kararı -------------------------------------------------------------------------------
select test.oturum('es_ik@ornek.test');
select test.dogrula('İK "geldi" yalnızca giriş (08:00): reddedilir, mesaj çıkışı ister, soru İK''da kalır',
    test.hata($q$select pdks.soru_ik_karari(test.s('ES06'), false, 'Kapı 08:00', '2026-08-05 08:00+03', null)$q$)
        = 'Günde çıkış saati yok; çıkış saatini de girin.'
    and test.soru_durumu('ES06') = 'ik_karari_bekliyor');
select test.dogrula('İK "geldi" iki saatle: kabul, gün hesaplandı',
    test.hata($q$select pdks.soru_ik_karari(test.s('ES06'), false, 'Kapı 08:00, servis 16:10', '2026-08-05 08:00+03', '2026-08-05 16:10+03')$q$) is null
    and (select durum = 'tamam' and hesap_tamam from test.gun('ES06')));
select test.dogrula('İK "devamsız" saat istemez',
    test.hata($q$select pdks.soru_ik_karari(test.s('ES07'), true, 'Kayıt yok')$q$) is null
    and (test.gun('ES07')).durum = 'devamsiz');
reset role;

-- 3) Kilitli ay: saat fark satırında, kural onu da sayar --------------------------------------
set local role authenticated;
select test.oturum('es_ik@ornek.test');
select pdks.ay_kilitle(2026::smallint, 7::smallint, true, 'Test: zorla kilit gerekçesi') \g /dev/null
reset role;
-- İK'nın girişi (kilitli ayda gün kaydı değişmez, düzeltme fark satırı olur)
select pdks.duzeltme_uygula(test.g('ES08'), 'giris_zamani', '2026-07-15 08:04+03', 'Kapı kaydı', 'ik', test.k('es_ik@ornek.test')) \g /dev/null
select test.dogrula('kilitli ay: İK girişi fark satırında, gün kaydında giriş yok',
    (test.gun('ES08')).giris_zamani is null
    and exists (select 1 from pdks.duzeltme where gun_kaydi_id = test.g('ES08') and alan = 'giris_zamani' and fark_satiri));
set local role authenticated;
select test.oturum('es_amir@ornek.test');
select test.dogrula('kilitli ay: amirin yalnızca çıkışı kabul (giriş fark satırından sayılır)',
    test.hata($q$select pdks.soru_cevapla(test.s('ES08'), 'geldi_saat_farkli', null, '2026-07-15 16:30+03')$q$) is null
    and test.soru_durumu('ES08') = 'cevaplandi');
reset role;

\echo 'TÜM TESTLER GEÇTİ'
rollback;
