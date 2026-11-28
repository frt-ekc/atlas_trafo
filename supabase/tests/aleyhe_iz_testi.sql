-- =====================================================================
-- Amirin aleyhe saati ve karar izleri (20261231210000_aleyhe_iz.sql; T-44, T-35)
--   T-44: Amirin girdiği saat geç kalma ya da erken çıkış doğuruyorsa düzeltme "çalışan aleyhine"
--         işaretlenir. Ölçü günün kendi hesabıdır (gun_hesabi): tolerans, esnek mesai ve saatlik izin
--         sayılır. Amirin yetkisi değişmez; yalnızca iz ve İK'nın süzebilmesi içindir.
--   T-35: İtirazı incelemeye alan ve zamanı; arızaya karar veren ve zamanı ayrı sütunlarda tutulur.
--         Arızayı giren (giren_id) artık karar verenle ezilmez.
-- Testin kendi sahte verisi kullanılır; örnek veri yüklü olsun olmasın çalışır.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/aleyhe_iz_testi.sql
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
-- Günün o alandaki son düzeltmesi aleyhe mi? (RLS'siz okunur)
create function test.aleyhe(p text, p_alan text) returns boolean language sql security definer as $$
    select calisan_aleyhine from pdks.duzeltme
    where gun_kaydi_id = test.g(p) and alan = p_alan order by id desc limit 1 $$;
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
--   AY Üretim, amiri AYA1; AYI1 İK. 5 Ağustos 2026 (açık ay). Geç kalma toleransı 10, erken çıkış 5 dk.
--   AY01 GUNDUZ_8 08:00–16:00, amir giriş 08:20             → giriş aleyhe (geç kalma 20 dk)
--   AY02 GUNDUZ_8, amir giriş 08:05                         → tolerans içinde, aleyhe değil
--   AY03 GUNDUZ_8, amir 07:55–15:00                         → giriş değil, çıkış aleyhe (erken çıkış 60 dk)
--   AY04 GUNDUZ_8, amir 08:00–16:30                         → ikisi de aleyhe değil
--   AY05 V3 22:00–06:00 (gece yarısını geçer), amir 22:00–05:00 → çıkış aleyhe
--   AY06 GUNDUZ_8, 08:00–10:00 saatlik izin, amir giriş 10:00 → izinli saat geç kalma değil, aleyhe değil
--   AY07 ESNEK, amir 09:30–17:30                            → esnek mesaide geç kalma yok, aleyhe değil
--   AY08 GUNDUZ_8, İK giriş 08:30 (duzeltme_uygula, kaynak ik) → kural amirin saatine; İK'nın kendi kararı işaretlenmez
insert into pdks.departman (ad) values ('AY Üretim'), ('AY İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = d), '2025-01-01'
from (values ('AYA1', 'AY Üretim'), ('AY01', 'AY Üretim'), ('AY02', 'AY Üretim'), ('AY03', 'AY Üretim'), ('AY04', 'AY Üretim'),
             ('AY05', 'AY Üretim'), ('AY06', 'AY Üretim'), ('AY07', 'AY Üretim'), ('AY08', 'AY Üretim'), ('AYI1', 'AY İdari')) v(s, d);
insert into pdks.kullanici (eposta, rol, calisan_id, auth_kullanici_id)
select e, r, test.c(s), u::uuid
from (values ('ay_amir@ornek.test', 'amir', 'AYA1', '00000000-0000-0000-0000-0000000044a1'),
             ('ay_ik@ornek.test',   'ik',   'AYI1', '00000000-0000-0000-0000-0000000044a2')) v(e, r, s, u);
update pdks.departman set amir_id = test.k('ay_amir@ornek.test') where ad = 'AY Üretim';
insert into pdks.gun_kaydi (calisan_id, is_gunu, vardiya_id, planli_baslangic, planli_bitis, durum)
select test.c(s), '2026-08-05', (select id from pdks.vardiya_tanim where kod = v),
       ('2026-08-05 ' || b || '+03')::timestamptz, (bi || '+03')::timestamptz, 'soru_bekliyor'
from (values ('AY01', 'GUNDUZ_8', '08:00', '2026-08-05 16:00'), ('AY02', 'GUNDUZ_8', '08:00', '2026-08-05 16:00'),
             ('AY03', 'GUNDUZ_8', '08:00', '2026-08-05 16:00'), ('AY04', 'GUNDUZ_8', '08:00', '2026-08-05 16:00'),
             ('AY05', 'V3',       '22:00', '2026-08-06 06:00'), ('AY06', 'GUNDUZ_8', '08:00', '2026-08-05 16:00'),
             ('AY07', 'ESNEK',    '07:00', '2026-08-05 19:00'), ('AY08', 'GUNDUZ_8', '08:00', '2026-08-05 16:00')) x(s, v, b, bi);
insert into pdks.saatlik_izin (calisan_id, tarih, baslangic, bitis, tur, giren_id)
values (test.c('AY06'), '2026-08-05', '2026-08-05 08:00+03', '2026-08-05 10:00+03', 'mazeret', test.k('ay_ik@ornek.test'));
insert into pdks.amir_sorusu (gun_kaydi_id, soru_turu, aciklama, atanan_id, son_cevap_tarihi)
select test.g(s), 'hic_kayit_yok', 'Deneme sorusu', test.k('ay_amir@ornek.test'), '2026-08-08'
from (values ('AY01'), ('AY02'), ('AY03'), ('AY04'), ('AY05'), ('AY06'), ('AY07')) v(s);

-- 1) T-44: amirin cevabındaki saat ----------------------------------------------------------
set local role authenticated;
select test.oturum('ay_amir@ornek.test');
select pdks.soru_cevapla(test.s('AY01'), 'geldi_saat_farkli', '2026-08-05 08:20+03', '2026-08-05 16:00+03') \g /dev/null
select pdks.soru_cevapla(test.s('AY02'), 'geldi_saat_farkli', '2026-08-05 08:05+03', '2026-08-05 16:00+03') \g /dev/null
select pdks.soru_cevapla(test.s('AY03'), 'geldi_saat_farkli', '2026-08-05 07:55+03', '2026-08-05 15:00+03') \g /dev/null
select pdks.soru_cevapla(test.s('AY04'), 'geldi_saat_farkli', '2026-08-05 08:00+03', '2026-08-05 16:30+03') \g /dev/null
select pdks.soru_cevapla(test.s('AY05'), 'geldi_saat_farkli', '2026-08-05 22:00+03', '2026-08-06 05:00+03') \g /dev/null
select pdks.soru_cevapla(test.s('AY06'), 'geldi_saat_farkli', '2026-08-05 10:00+03', '2026-08-05 16:00+03') \g /dev/null
select pdks.soru_cevapla(test.s('AY07'), 'geldi_saat_farkli', '2026-08-05 09:30+03', '2026-08-05 17:30+03') \g /dev/null
reset role;

select test.dogrula('T-44 amir girişi 08:20 (geç kalma 20 dk): giriş düzeltmesi çalışan aleyhine',
    test.aleyhe('AY01', 'giris_zamani') and not test.aleyhe('AY01', 'cikis_zamani'));
select test.dogrula('T-44 amir girişi 08:05 (10 dk tolerans içinde): aleyhe değil',
    not test.aleyhe('AY02', 'giris_zamani'));
select test.dogrula('T-44 amir 07:55–15:00: giriş aleyhe değil, çıkış aleyhe (erken çıkış 60 dk)',
    not test.aleyhe('AY03', 'giris_zamani') and test.aleyhe('AY03', 'cikis_zamani'));
select test.dogrula('T-44 amir 08:00–16:30: ikisi de aleyhe değil',
    not test.aleyhe('AY04', 'giris_zamani') and not test.aleyhe('AY04', 'cikis_zamani'));
select test.dogrula('T-44 gece vardiyası 22:00–06:00, amir çıkışı 05:00: çıkış aleyhe',
    not test.aleyhe('AY05', 'giris_zamani') and test.aleyhe('AY05', 'cikis_zamani'));
select test.dogrula('T-44 08:00–10:00 saatlik izinli çalışanın girişi 10:00: geç kalma değil, aleyhe değil',
    not test.aleyhe('AY06', 'giris_zamani'));
select test.dogrula('T-44 esnek mesaide 09:30 giriş: geç kalma sayılmaz, aleyhe değil',
    not test.aleyhe('AY07', 'giris_zamani') and not test.aleyhe('AY07', 'cikis_zamani'));
select test.dogrula('T-44 işaret günün hesabıyla aynı: AY01 geç kalma 20 dk, AY03 erken çıkış 60 dk',
    (select gec_kalma_dk = 20 from pdks.gun_kaydi where id = test.g('AY01'))
    and (select erken_cikis_dk = 60 from pdks.gun_kaydi where id = test.g('AY03')));
select test.dogrula('T-44 amirin yetkisi değişmedi: aleyhe saatli sorular da cevaplandı',
    (select count(*) = 7 from pdks.amir_sorusu where gun_kaydi_id in (select id from pdks.gun_kaydi where calisan_id in
        (select id from pdks.calisan where sicil_no like 'AY0%')) and durum = 'cevaplandi'));
select pdks.duzeltme_uygula(test.g('AY08'), 'giris_zamani', '2026-08-05 08:30+03', 'Kapı kaydı 08:30', 'ik', test.k('ay_ik@ornek.test')) \g /dev/null
select test.dogrula('T-44 İK''nın kendi saat düzeltmesi bu kurala girmez (aleyhe kararı zaten İK''nındır)',
    not test.aleyhe('AY08', 'giris_zamani'));
select test.dogrula('T-44 amir kaynaklı aleyhe işaret yalnızca giriş / çıkış saatinde olur (durum alanında reddedilir)',
    test.hata($q$select pdks.duzeltme_uygula(test.g('AY04'), 'durum', 'izinli', 'Deneme gerekçesi', 'amir',
                                             test.k('ay_amir@ornek.test'), p_aleyhine => true)$q$)
        like '%duzeltme_aleyhe_kaynagi%');

-- 2) T-35: itirazı incelemeye alma -----------------------------------------------------------
set local role authenticated;
select test.oturum('ay_amir@ornek.test');
select pdks.itiraz_gir(test.g('AY01'), 'Çalışan 08:00''de geldiğini söylüyor') \g /dev/null
select test.oturum('ay_ik@ornek.test');
select pdks.itiraz_incelemeye_al((select id from pdks.itiraz where gun_kaydi_id = test.g('AY01'))) \g /dev/null
reset role;
select test.dogrula('T-35 incelemeye alan İK ve zaman itirazda',
    (select durum = 'inceleniyor' and inceleyen_id = test.k('ay_ik@ornek.test') and inceleme_zamani is not null
     from pdks.itiraz where gun_kaydi_id = test.g('AY01')));
set local role authenticated;
select test.oturum('ay_ik@ornek.test');
select pdks.itiraz_karar((select id from pdks.itiraz where gun_kaydi_id = test.g('AY01')), false, 'Kapı kaydı 08:20''yi gösteriyor') \g /dev/null
reset role;
select test.dogrula('T-35 karardan sonra inceleme izi korunur',
    (select durum = 'red' and inceleyen_id = test.k('ay_ik@ornek.test') and inceleme_zamani is not null
     from pdks.itiraz where gun_kaydi_id = test.g('AY01')));

-- 3) T-35: arıza kararı ----------------------------------------------------------------------
insert into pdks.okuyucu (kod, ad, sistem) values ('AY-K1', 'AY test kapısı', 'kapi');
insert into pdks.ariza (okuyucu_id, baslangic, bitis, kaynak, durum, aciklama)
values ((select id from pdks.okuyucu where kod = 'AY-K1'), '2026-08-05 07:00+03', '2026-08-05 09:00+03', 'otomatik_suphe', 'suphe', 'AY şüphe 1'),
       ((select id from pdks.okuyucu where kod = 'AY-K1'), '2026-08-05 12:00+03', '2026-08-05 13:00+03', 'otomatik_suphe', 'suphe', 'AY şüphe 2');
set local role authenticated;
select test.oturum('ay_ik@ornek.test');
select pdks.ariza_karar((select id from pdks.ariza where aciklama = 'AY şüphe 1'), true) \g /dev/null
select pdks.ariza_karar((select id from pdks.ariza where aciklama = 'AY şüphe 2'), false) \g /dev/null
reset role;
select test.dogrula('T-35 arıza onayı: karar veren ve zaman ayrı sütunda, giren_id ezilmedi',
    (select durum = 'onaylandi' and karar_veren_id = test.k('ay_ik@ornek.test') and karar_zamani is not null and giren_id is null
     from pdks.ariza where aciklama = 'AY şüphe 1'));
select test.dogrula('T-35 arıza reddi: karar veren ve zaman ayrı sütunda',
    (select durum = 'reddedildi' and karar_veren_id = test.k('ay_ik@ornek.test') and karar_zamani is not null and giren_id is null
     from pdks.ariza where aciklama = 'AY şüphe 2'));

\echo 'TÜM TESTLER GEÇTİ'
rollback;
