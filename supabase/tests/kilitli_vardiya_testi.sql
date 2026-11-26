-- =====================================================================
-- Kilitli ayın vardiyası değişmez (20261231060000_kilitli_vardiya.sql, T-93)
--   Kilitli günde vardiya değişince fark satırı yalnızca kaybı yazıyordu (geç kalma, eksik çalışma);
--   yeni vardiyanın dışında kalan çalışma havuza düşmüyordu. Karar: kilitli günde vardiya düzeltmesi
--   reddedilir (plan onayı, kayıt düzeltmesi, amir cevabı). Bekleyen plan yalnızca reddedilebilir.
--   Saat ve durum düzeltmeleri eskisi gibi sonraki aya fark olur.
-- Testin kendi sahte verisi kullanılır; örnek veri yüklü olsun olmasın çalışır.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/kilitli_vardiya_testi.sql
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
create function test.plan(p text) returns pdks.vardiya_plani language sql security definer as $$
    select * from pdks.vardiya_plani where calisan_id = test.c(p) and vardiya_id = 2 $$;
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
--   KV Üretim, amiri KVA; İK KVI. Plan Gündüz (08–17), okutma 08:00–17:05.
--   KV01 Ali: 21 Eylül (Eylül sonra zorla kilitlenir). KV02 Veli: 22 Eylül (ret için).
--   KV03 Can: 5 Ekim (açık ay, karşılaştırma). Amir üçü için de "aslında Sabah (06–14)" planı girer.
insert into pdks.departman (ad) values ('KV Üretim'), ('KV İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, a, 'Örnek', (select id from pdks.departman where ad = d), '2025-01-01'
from (values ('KV01', 'Ali', 'KV Üretim'), ('KV02', 'Veli', 'KV Üretim'), ('KV03', 'Can', 'KV Üretim'),
             ('KVA', 'Hasan', 'KV Üretim'), ('KVI', 'Elif', 'KV İdari')) v(s, a, d);
insert into pdks.kullanici (eposta, rol, calisan_id, auth_kullanici_id) values
    ('kv_ik@ornek.test',   'ik',   test.c('KVI'), '00000000-0000-0000-0000-0000000093b1'),
    ('kv_amir@ornek.test', 'amir', test.c('KVA'), '00000000-0000-0000-0000-0000000093b2');
update pdks.departman set amir_id = test.k('kv_amir@ornek.test') where ad = 'KV Üretim';
insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id, giren_id)
select test.c(s), d, 1, test.k('kv_amir@ornek.test')
from (values ('KV01', date '2026-09-21'), ('KV02', date '2026-09-22'), ('KV03', date '2026-10-05')) v(s, d);
insert into pdks.gun_kaydi (calisan_id, is_gunu, vardiya_id, planli_baslangic, planli_bitis, durum, giris_zamani, cikis_zamani)
select test.c(s), d, 1, d + time '08:00', d + time '17:00', 'tamam', d + time '08:00', d + time '17:05'
from (values ('KV01', date '2026-09-21'), ('KV02', date '2026-09-22'), ('KV03', date '2026-10-05')) v(s, d);
select pdks.gun_hesapla(test.g(s)) from unnest(array['KV01', 'KV02', 'KV03']) s \g /dev/null

set local role authenticated;
select test.oturum('kv_amir@ornek.test');
select pdks.vardiya_plani_gir(test.c(s), d, 2::smallint, 'Aslında sabah vardiyasındaydı')
from (values ('KV01', date '2026-09-21'), ('KV02', date '2026-09-22'), ('KV03', date '2026-10-05')) v(s, d) \g /dev/null
-- Planlar İK onayı beklerken Eylül zorla kilitlenir
select test.oturum('kv_ik@ornek.test');
select pdks.ay_kilitle(2026::smallint, 9::smallint, true, 'Bordro kesilecek; bekleyen planlar sonra değerlendirilecek') \g /dev/null
reset role;
create temp table once as select calisan_id, vardiya_id, calisma_dk, gec_kalma_dk from pdks.gun_kaydi where id = test.g('KV01');

-- 1) Bulgudaki durum: kilitli ayda plan onayı reddedilir ----------------------------------------
set local role authenticated;
select test.oturum('kv_ik@ornek.test');
select test.dogrula('kilitli ayda (21 Eylül) vardiya planı onaylanamaz; mesaj ne yapılacağını söyler',
    test.hata(format('select pdks.vardiya_plani_onayla(%s, true)', (test.plan('KV01')).id))
        = 'Kilitli ayda vardiya değiştirilemez (09.2026). Bekleyen plan yalnızca reddedilebilir; giriş ya da çıkış saati yanlışsa kayıt düzeltmesiyle düzeltin.');
reset role;
select test.dogrula('reddedilen onaydan sonra plan hâlâ onay bekliyor, vardiya fark satırı yok',
    (test.plan('KV01')).ik_onay_durumu = 'bekliyor'
    and not exists (select 1 from pdks.duzeltme where gun_kaydi_id = test.g('KV01') and alan = 'vardiya_id'));
select test.dogrula('Ali''nin Eylül günü değişmedi: Gündüz, 480 dk, geç kalma yok (kesinti yazılmadı)',
    (select g.vardiya_id = 1 and g.calisma_dk = o.calisma_dk and g.gec_kalma_dk = 0
     from pdks.gun_kaydi g join once o using (calisan_id) where g.id = test.g('KV01')));

-- 2) Bekleyen plan kilitli ayda reddedilebilir --------------------------------------------------
set local role authenticated;
select test.oturum('kv_ik@ornek.test');
select test.dogrula('kilitli ayda bekleyen plan reddedilebilir',
    test.hata(format('select pdks.vardiya_plani_onayla(%s, false)', (test.plan('KV02')).id)) is null);
reset role;
select test.dogrula('ret önceki planı (Gündüz) geri getirdi (T-49), gün değişmedi, düzeltme yok',
    (select vardiya_id = 1 from pdks.vardiya_plani where calisan_id = test.c('KV02') and tarih = '2026-09-22')
    and test.plan('KV02') is null
    and (select vardiya_id = 1 from pdks.gun_kaydi where id = test.g('KV02'))
    and not exists (select 1 from pdks.duzeltme where gun_kaydi_id = test.g('KV02')));

-- 3) Kayıt düzeltmesi: vardiya reddedilir, saat eskisi gibi fark olur -----------------------------
set local role authenticated;
select test.oturum('kv_ik@ornek.test');
select test.dogrula('kilitli günde kayıt düzeltmesiyle vardiya değiştirilemez',
    test.hata(format($q$select pdks.kayit_duzelt(%s, 'vardiya_id', '2', 'Sabah vardiyasıydı')$q$, test.g('KV01')))
        like 'Kilitli ayda vardiya değiştirilemez (09.2026).%');
select test.dogrula('kilitli günde saat düzeltmesi eskisi gibi yapılır (itiraz, kart unutma vb.)',
    test.hata(format($q$select pdks.kayit_duzelt(%s, 'cikis_zamani', '2026-09-21 17:30+03', 'Servis kaydı 17:30')$q$, test.g('KV01'))) is null);
reset role;
select test.dogrula('saat düzeltmesi sonraki aya fark satırı oldu, gün kaydı değişmedi',
    exists (select 1 from pdks.duzeltme where gun_kaydi_id = test.g('KV01') and alan = 'cikis_zamani' and fark_satiri)
    and (select cikis_zamani = '2026-09-21 17:05+03' from pdks.gun_kaydi where id = test.g('KV01')));
select test.dogrula('kural tablonun üstünde: kilitli güne doğrudan vardiya düzeltmesi de yazılamaz',
    test.hata(format($q$select pdks.duzeltme_uygula(%s, 'vardiya_id', '2', 'Doğrudan deneme', 'ik', %s)$q$,
                     test.g('KV01'), test.k('kv_ik@ornek.test'))) like 'Kilitli ayda vardiya değiştirilemez (09.2026).%');

-- 4) Açık ay eskisi gibi: plan onayı günü değiştirir, vardiya dışı süre havuza düşer ---------------
set local role authenticated;
select test.oturum('kv_ik@ornek.test');
select test.dogrula('açık ayda (5 Ekim) plan onaylanır',
    test.hata(format('select pdks.vardiya_plani_onayla(%s, true)', (test.plan('KV03')).id)) is null);
reset role;
select test.dogrula('açık ay: gün Sabah vardiyasıyla hesaplandı, 14:00 sonrası 185 dk havuza düştü',
    (select vardiya_id = 2 and gec_kalma_dk = 120 from pdks.gun_kaydi where id = test.g('KV03'))
    and exists (select 1 from pdks.fazla_mesai_inceleme where gun_kaydi_id = test.g('KV03')
                and tur = 'vardiya_sonrasi' and dakika = 185 and durum = 'inceleme_bekliyor'));

\echo 'TÜM TESTLER GEÇTİ'
rollback;
