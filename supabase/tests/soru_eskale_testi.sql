-- =====================================================================
-- Soru: amir → üst amir → İK (20261210010000_ikinci_eskale.sql, T-39)
--   * Amir süresinde cevaplamazsa soru üst amire gider (eskiden de böyleydi).
--   * Üst amir de süresinde cevaplamazsa (son cevap tarihi + soru_eskalasyon_gun)
--     soru İK'ya geçer: durum ik_karari_bekliyor, ik_eskale_zamani dolar, üst amirin
--     adı silinmez, İK'ya uyarı yazılır. Bir gecede en çok bir kademe.
--   * Üst amiri olmayan amirin sorusu ilk kademede İK'ya gider, bir daha taşınmaz.
--   * İK her açık soruya (amirde, üst amirde ya da İK'da) karar verebilir; gün hesaplanır.
--
-- Testin kendi sahte verisi kullanılır (Ekim 2026). Gece işinin eskalasyon adımı
-- işlenen günü parametre olarak alır; testte bu günler sırayla verilir.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/soru_eskale_testi.sql
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
create function test.calisir(p_ad text, p_sql text) returns void language plpgsql as $$
begin
    execute p_sql;
    raise notice 'GEÇTİ  %', p_ad;
exception when others then
    raise exception 'KALDI  %: %', p_ad, sqlerrm;
end $$;
create function test.c(p text) returns bigint language sql security definer as $$
    select id from pdks.calisan where sicil_no = p $$;
create function test.k(p text) returns bigint language sql security definer as $$
    select id from pdks.kullanici where eposta = p $$;
-- Çalışanın 14 Ekim sorusu
create function test.soru(p_sicil text) returns pdks.amir_sorusu language sql security definer as $$
    select q.* from pdks.amir_sorusu q join pdks.gun_kaydi g on g.id = q.gun_kaydi_id
    where g.calisan_id = test.c(p_sicil) and g.is_gunu = '2026-10-14' $$;
create function test.gun(p_sicil text) returns pdks.gun_kaydi language sql security definer as $$
    select * from pdks.gun_kaydi where calisan_id = test.c(p_sicil) and is_gunu = '2026-10-14' $$;
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
--   ES Üretim: amiri ES Amir, onun üst amiri ES Müdür (rolü amir)
--   ES Bakım: amiri ES Bakım Amiri, üst amiri yok
--   ES01, ES02 (Üretim) ve ES03 (Bakım): 14 Ekim soruları, son cevap 17 Ekim
--   ES04 (Üretim): 14 Ekim sorusu, son cevap 30 Ekim (hâlâ amirde)
insert into pdks.departman (ad) values ('ES Üretim'), ('ES Bakım'), ('ES İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = d), '2025-01-01'
from (values ('ES01', 'ES Üretim'), ('ES02', 'ES Üretim'), ('ES04', 'ES Üretim'), ('ES03', 'ES Bakım'),
             ('ESA1', 'ES İdari'), ('ESB1', 'ES İdari'), ('ESU1', 'ES İdari'), ('ESI1', 'ES İdari')) v(s, d);
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('ES Müdür', 'es_mudur@ornek.test', 'amir', test.c('ESU1'), '00000000-0000-0000-0000-0000000039b1'),
    ('ES İK',    'es_ik@ornek.test',    'ik',   test.c('ESI1'), '00000000-0000-0000-0000-0000000039b2'),
    ('ES Bakım Amiri', 'es_bakim@ornek.test', 'amir', test.c('ESB1'), '00000000-0000-0000-0000-0000000039b3');
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id, ust_amir_id) values
    ('ES Amir', 'es_amir@ornek.test', 'amir', test.c('ESA1'), '00000000-0000-0000-0000-0000000039b4',
     test.k('es_mudur@ornek.test'));
update pdks.departman set amir_id = test.k('es_amir@ornek.test')  where ad = 'ES Üretim';
update pdks.departman set amir_id = test.k('es_bakim@ornek.test') where ad = 'ES Bakım';

insert into pdks.gun_kaydi (calisan_id, is_gunu, vardiya_id, durum, planli_baslangic, planli_bitis)
select test.c(s), '2026-10-14', 1, 'soru_bekliyor', '2026-10-14 08:00+03', '2026-10-14 17:00+03'
from unnest(array['ES01', 'ES02', 'ES03', 'ES04']) s;
insert into pdks.amir_sorusu (gun_kaydi_id, soru_turu, aciklama, atanan_id, son_cevap_tarihi)
select (test.gun(s)).id, 'hic_kayit_yok', 'Hiç okutma yok', test.k(a), t::date
from (values ('ES01', 'es_amir@ornek.test', '2026-10-17'), ('ES02', 'es_amir@ornek.test', '2026-10-17'),
             ('ES03', 'es_bakim@ornek.test', '2026-10-17'), ('ES04', 'es_amir@ornek.test', '2026-10-30')) v(s, a, t);

-- 1) Birinci kademe: amir → üst amir (ya da üst amiri yoksa İK) ---------------
select test.dogrula('16.10: süre dolmadı, hiçbir soru taşınmadı', pdks.gece_isi_eskale('2026-10-16') = 0);
select test.dogrula('17.10: amirin süresi doldu, 3 soru taşındı', pdks.gece_isi_eskale('2026-10-17') = 3);
select test.dogrula('ES01 üst amire (ES Müdür) gitti',
    (select durum = 'eskale' and eskale_edilen_id = test.k('es_mudur@ornek.test') from test.soru('ES01')));
select test.dogrula('ES03 (üst amiri olmayan amir) İK''ya gitti',
    (select durum = 'eskale' and pdks.kullanici_rolu(eskale_edilen_id) = 'ik' from test.soru('ES03')));

-- 2) İkinci kademe: üst amir de cevaplamazsa İK -------------------------------
select test.dogrula('19.10: üst amirin süresi dolmadı, ES01 hâlâ üst amirde',
    pdks.gece_isi_eskale('2026-10-19') = 0
    and (select durum = 'eskale' and ik_eskale_zamani is null from test.soru('ES01')));
select test.dogrula('20.10: üst amirin süresi de doldu, 2 soru İK''ya geçti',
    pdks.gece_isi_eskale('2026-10-20') = 2);
select test.dogrula('ES01: İK kararı bekliyor; üst amirin adı duruyor, İK''ya geçiş zamanı yazıldı',
    (select durum = 'ik_karari_bekliyor' and eskale_edilen_id = test.k('es_mudur@ornek.test')
            and ik_eskale_zamani is not null from test.soru('ES01')));
select test.dogrula('ES01 için İK''ya uyarı yazıldı',
    exists (select 1 from pdks.uyari where tur = 'soru_eskale' and tekillik_anahtari = 'soru_ik:' || (test.soru('ES01')).id
                                     and mesaj like '%üst amir de süresinde cevaplamadı%'));
select test.dogrula('ES03 (zaten İK''da) bir daha taşınmadı',
    (select durum = 'eskale' and ik_eskale_zamani is null from test.soru('ES03')));
select test.dogrula('ES04 (süresi 30.10) hâlâ amirde', (select durum = 'acik' from test.soru('ES04')));
select test.dogrula('21.10: tekrar çalışınca hiçbir şey değişmedi', pdks.gece_isi_eskale('2026-10-21') = 0);

-- 3) İK her açık soruya karar verir ----------------------------------------
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000039b2","role":"authenticated"}', true) \g /dev/null
set local role authenticated;
select test.calisir('İK, üst amirden gelen ES01 sorusuna karar verdi (geldi, 08:00–17:00)',
    $$select pdks.soru_ik_karari((test.soru('ES01')).id, false, 'Vardiya amiri teyit etti',
                                 '2026-10-14 08:00+03', '2026-10-14 17:00+03')$$);
select test.calisir('İK, İK''ya eskale edilmiş ES03 sorusuna karar verdi (eskisi gibi)',
    $$select pdks.soru_ik_karari((test.soru('ES03')).id, true, 'Haber vermeden gelmedi')$$);
select test.calisir('İK, hâlâ amirde duran ES04 sorusuna karar verdi (son karar İK''da)',
    $$select pdks.soru_ik_karari((test.soru('ES04')).id, false, 'Belge geldi',
                                 '2026-10-14 08:00+03', '2026-10-14 17:00+03')$$);
select test.calisir('İK, üst amirde duran ES02 sorusuna karar verdi',
    $$select pdks.soru_ik_karari((test.soru('ES02')).id, false, 'Belge geldi',
                                 '2026-10-14 08:00+03', '2026-10-14 17:00+03')$$);
reset role;
select test.dogrula('ES01: soru kapandı, gün tamam ve hesaplandı',
    (select durum = 'kapandi' from test.soru('ES01'))
    and (select durum = 'tamam' and hesap_tamam from test.gun('ES01')));
select test.dogrula('ES03: gün devamsız',
    (select durum = 'kapandi' from test.soru('ES03')) and (select durum = 'devamsiz' from test.gun('ES03')));

select 'Soru eskalasyonu testi: hepsi GEÇTİ';
rollback;
