-- =====================================================================
-- Zorla kilidin izi (20261231050000_zorla_kilit_izi.sql, T-92)
--   * Zorla kilitte gerekçe zorunlu (en az 10 karakter); yoksa kilit reddedilir.
--   * Her kilit pdks.donem_kilit_izi'ne yazılır: zorla mı, gerekçe, kilit anındaki özet (atlanan
--     açık sorulu günler, açık itirazlar, onaysız fazla mesai, bekleyen plan, kodsuz günler).
--   * İz değiştirilemez, silinemez; yalnızca İK ve yönetici okur (amir okuyamaz).
--   * Normal kilit ve ekranın bugünkü 3 parametreli çağrısı değişmedi.
-- Testin kendi sahte verisi kullanılır; örnek veri yüklü olsun olmasın çalışır.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/zorla_kilit_izi_testi.sql
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
-- Dönemin izi (RLS'siz)
create function test.iz(p_yil int, p_ay int) returns pdks.donem_kilit_izi language sql security definer as $$
    select z.* from pdks.donem_kilit_izi z join pdks.donem d on d.id = z.donem_id where d.yil = p_yil and d.ay = p_ay $$;
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
--   ZK Üretim, Eylül 2026: ZK01 10 Eylül açık sorulu (amir cevaplamadı), ZK02 12 Eylül 08:25 girişli (geç kalma) ve açık itirazlı.
--   Mayıs 2026: hiç gün yok (normal kilit). ZKI1 İK, ZKA1 amir.
insert into pdks.departman (ad) values ('ZK Üretim'), ('ZK İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, a, 'Örnek', (select id from pdks.departman where ad = d), '2025-01-01'
from (values ('ZK01', 'Veli', 'ZK Üretim'), ('ZK02', 'Ali', 'ZK Üretim'), ('ZKA1', 'Hasan', 'ZK Üretim'), ('ZKI1', 'Elif', 'ZK İdari')) v(s, a, d);
insert into pdks.kullanici (eposta, rol, calisan_id, auth_kullanici_id) values
    ('zk_ik@ornek.test',   'ik',   test.c('ZKI1'), '00000000-0000-0000-0000-0000000092a1'),
    ('zk_amir@ornek.test', 'amir', test.c('ZKA1'), '00000000-0000-0000-0000-0000000092a2');
update pdks.departman set amir_id = test.k('zk_amir@ornek.test') where ad = 'ZK Üretim';
insert into pdks.gun_kaydi (calisan_id, is_gunu, vardiya_id, planli_baslangic, planli_bitis, durum, giris_zamani, cikis_zamani)
values (test.c('ZK01'), '2026-09-10', (select id from pdks.vardiya_tanim where kod = 'GUNDUZ_8'), '2026-09-10 08:00+03', '2026-09-10 16:00+03', 'soru_bekliyor', null, null),
       (test.c('ZK02'), '2026-09-12', (select id from pdks.vardiya_tanim where kod = 'GUNDUZ_8'), '2026-09-12 08:00+03', '2026-09-12 16:00+03', 'tamam',
        '2026-09-12 08:25+03', '2026-09-12 16:00+03');
insert into pdks.amir_sorusu (gun_kaydi_id, soru_turu, aciklama, atanan_id, son_cevap_tarihi)
values ((select id from pdks.gun_kaydi where calisan_id = test.c('ZK01')), 'hic_kayit_yok', 'Hiç okutma yok', test.k('zk_amir@ornek.test'), '2026-09-13');
insert into pdks.itiraz (calisan_id, gun_kaydi_id, metin)
values (test.c('ZK02'), (select id from pdks.gun_kaydi where calisan_id = test.c('ZK02')), 'Servis geç geldi, kartımı 08:00''de okuttum');

-- 1) Zorla kilitte gerekçe zorunlu -----------------------------------------------------------
set local role authenticated;
select test.oturum('zk_ik@ornek.test');
select test.dogrula('zorla kilit gerekçesiz reddedilir',
    test.hata($q$select pdks.ay_kilitle(2026::smallint, 9::smallint, true)$q$)
        = 'Zorla kilitte gerekçe yazılmalıdır (en az 10 karakter).');
select test.dogrula('zorla kilit kısa gerekçeyle (boşluklar sayılmaz) reddedilir',
    test.hata($q$select pdks.ay_kilitle(2026::smallint, 9::smallint, true, '   Bordro   ')$q$)
        = 'Zorla kilitte gerekçe yazılmalıdır (en az 10 karakter).');
select test.dogrula('reddedilen zorla kilitten sonra Eylül kilitli değil, iz yok',
    not exists (select 1 from pdks.donem where yil = 2026 and ay = 9 and durum = 'kilitli')
    and test.iz(2026, 9) is null);
select test.dogrula('normal (zorlamasız) kilit açık soru ve itiraz varken yine reddedilir',
    test.hata($q$select pdks.ay_kilitle(2026::smallint, 9::smallint)$q$) is not null);

-- 2) Gerekçeli zorla kilit: iz yazılır --------------------------------------------------------
create temp table sonuc as
select pdks.ay_kilitle(2026::smallint, 9::smallint, true, '  Bordro 1 Ekim''de kesilecek; itiraz ve soru Ekim''de fark satırıyla düzeltilecek.  ') as r;
reset role;
select test.dogrula('Eylül kilitlendi; ekrana dönen özette gerekçe de var',
    exists (select 1 from pdks.donem where yil = 2026 and ay = 9 and durum = 'kilitli')
    and (select r ->> 'zorla_gerekce' like 'Bordro 1 Ekim%' from sonuc));
select test.dogrula('iz: zorla, gerekçe (baştaki ve sondaki boşluklar atılmış), kilitleyen İK, zamanı dolu',
    (select zorla and gerekce = 'Bordro 1 Ekim''de kesilecek; itiraz ve soru Ekim''de fark satırıyla düzeltilecek.'
            and kilitleyen_id = test.k('zk_ik@ornek.test') and kilit_zamani is not null
     from test.iz(2026, 9)));
select test.dogrula('iz özeti: 1 açık sorulu gün ve 1 açık itiraz sayıldı',
    (select (ozet -> 'zorla_gecilen' ->> 'acik_soru_gun')::int = 1 and (ozet -> 'zorla_gecilen' ->> 'acik_itiraz')::int = 1
     from test.iz(2026, 9)));
select test.dogrula('iz özeti: açık sorulu gün listesinde Veli (ZK01) 10.09.2026',
    (select ozet -> 'acik_soru_listesi' @> '[{"sicil": "ZK01", "tarih": "2026-09-10"}]'::jsonb from test.iz(2026, 9)));
select test.dogrula('iz özeti: açık itiraz listesinde Ali (ZK02) 12.09.2026, itiraz metni yok',
    (select ozet -> 'acik_itiraz_listesi' @> jsonb_build_array(jsonb_build_object('sicil', 'ZK02', 'tarih', '2026-09-12',
                'itiraz_id', (select id from pdks.itiraz where calisan_id = test.c('ZK02'))))
            and position('Servis geç geldi' in ozet::text) = 0
     from test.iz(2026, 9)));
select test.dogrula('iz özeti ekrana dönen özetle aynı sayıları taşıyor',
    (select z.ozet -> 'zorla_gecilen' = s.r -> 'zorla_gecilen' and z.ozet -> 'kodsuz_gun' = s.r -> 'kodsuz_gun'
     from test.iz(2026, 9) z, sonuc s));

-- 3) İz değiştirilemez, silinemez -------------------------------------------------------------
select test.dogrula('iz değiştirilemez',
    test.hata($q$update pdks.donem_kilit_izi set gerekce = 'Sonradan değiştirilmiş gerekçe' where zorla$q$) like '%değiştirilemez%');
select test.dogrula('iz silinemez',
    test.hata($q$delete from pdks.donem_kilit_izi$q$) like '%değiştirilemez%');
select test.dogrula('zorla iz gerekçesiz eklenemez (kural tablonun üstünde de)',
    test.hata($q$insert into pdks.donem_kilit_izi (donem_id, zorla, gerekce, ozet, kilitleyen_id)
                 values (pdks.donem_bul('2026-04-01'), true, null, '{}', test.k('zk_ik@ornek.test'))$q$) like '%donem_kilit_izi%');

-- 4) Kim görür --------------------------------------------------------------------------------
set local role authenticated;
select test.oturum('zk_amir@ornek.test');
select test.dogrula('amir ayın kilitli olduğunu görür ama izi (gerekçe, özet) göremez',
    (select count(*) = 1 from pdks.donem where yil = 2026 and ay = 9 and durum = 'kilitli')
    and (select count(*) = 0 from pdks.donem_kilit_izi));
select test.oturum('zk_ik@ornek.test');
select test.dogrula('İK izi görür',
    (select count(*) = 1 from pdks.donem_kilit_izi z join pdks.donem d on d.id = z.donem_id where d.yil = 2026 and d.ay = 9));

-- 5) Normal kilit ve ekranın bugünkü 3 parametreli çağrısı ------------------------------------
select test.dogrula('normal kilit 3 parametreyle (ekranın bugünkü çağrısı) çalışır',
    test.hata($q$select pdks.ay_kilitle(2026::smallint, 5::smallint, false)$q$) is null);
select test.dogrula('normal kilit 4 parametreyle, gerekçe verilse de saklanmaz (gerekçe yalnızca zorla için)',
    test.hata($q$select pdks.ay_kilitle(2026::smallint, 4::smallint, false, 'Gereksiz bir gerekçe metni')$q$) is null);
reset role;
select test.dogrula('normal kilitlerin de izi var: zorla değil, gerekçe boş',
    (select not zorla and gerekce is null from test.iz(2026, 5))
    and (select not zorla and gerekce is null from test.iz(2026, 4)));

\echo 'TÜM TESTLER GEÇTİ'
rollback;
