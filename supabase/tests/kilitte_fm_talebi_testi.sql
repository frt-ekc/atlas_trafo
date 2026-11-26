-- =====================================================================
-- Ay kilidinde karar bekleyen fazla mesai talebi testleri (20261231080000_kilitte_fm_talebi.sql, T-63)
-- Testin kendi sahte verisi (Eylül–Ekim 2026); örnek veri yüklü olsun olmasın çalışır.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/kilitte_fm_talebi_testi.sql
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
create function test.ts(p text) returns timestamptz language sql immutable as $$
    select (p::timestamp) at time zone 'Europe/Istanbul' $$;
create function test.plan(p_sicil text, p_gun date) returns pdks.fazla_mesai_plani language sql security definer as $$
    select * from pdks.fazla_mesai_plani where calisan_id = test.c(p_sicil) and is_gunu = p_gun $$;
create function test.hv(p_sicil text, p_gun date) returns pdks.fazla_mesai_inceleme language sql security definer as $$
    select * from pdks.fazla_mesai_inceleme where calisan_id = test.c(p_sicil) and is_gunu = p_gun $$;
create function test.kilit(p_yil int, p_ay int) returns jsonb language sql security definer as $$
    select z.ozet from pdks.donem_kilit_izi z join pdks.donem d on d.id = z.donem_id
    where d.yil = p_yil and d.ay = p_ay order by z.kilit_zamani desc limit 1 $$;
create temp table kt_sonuc (ay int, sonuc jsonb) on commit drop;
grant all on kt_sonuc to authenticated;
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
-- Hepsi yazılı onaylı, GUNDUZ (08:00–17:00). Talepleri amir girer, kararı İK verir.
--   KT06: 15 Eylül 120 dk talep, karar yok; 08–17 çalıştı (fazla mesai yapmadı, havuz yok)
--   KT01: 14 Ekim 120 dk talep, karar yok; 08–17 çalıştı (havuz yok)
--   KT02: 14 Ekim 120 dk talep, karar yok; 08–19 çalıştı (120 dk havuzda)
--   KT03: 14 Ekim talep, gün gelmeden onaylandı        KT04: 14 Ekim talep, reddedildi
--   KT05: 4 Kasım talep, karar yok (Ekim kilidi dokunmamalı)
insert into pdks.departman (ad) values ('KT Üretim'), ('KT İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = case when s like 'KT0%' then 'KT Üretim' else 'KT İdari' end), '2025-01-01'
from unnest(array['KT01','KT02','KT03','KT04','KT05','KT06','KTA1','KTI1']) s;
update pdks.calisan set departman_id = (select id from pdks.departman where ad = 'KT Üretim') where sicil_no = 'KTA1';
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('KT Amir', 'kt_amir@ornek.test', 'amir', test.c('KTA1'), '00000000-0000-0000-0000-0000000008a1'),
    ('KT İK',   'kt_ik@ornek.test',   'ik',   test.c('KTI1'), '00000000-0000-0000-0000-0000000008a2');
update pdks.departman set amir_id = test.k('kt_amir@ornek.test') where ad = 'KT Üretim';
insert into pdks.kart (kart_no, calisan_id)
select 'KT-' || s, test.c(s) from unnest(array['KT01','KT02','KT03','KT04','KT05','KT06']) s;
insert into pdks.okuyucu (kod, ad, sistem) values ('KT-PDKS', 'KT PDKS', 'pdks');
insert into pdks.fazla_mesai_onayi (calisan_id, yil, imza_tarihi, belge_no, giren_id)
select test.c(s), 2026, '2026-01-02', 'KT-FMO-' || s, test.k('kt_ik@ornek.test')
from unnest(array['KT01','KT02','KT03','KT04','KT05','KT06']) s;

create temp table kt_gun on commit drop as
select * from (values ('KT06', date '2026-09-15', '17:00'), ('KT01', date '2026-10-14', '17:00'),
                      ('KT02', date '2026-10-14', '19:00'), ('KT03', date '2026-10-14', '19:00'),
                      ('KT04', date '2026-10-14', '17:00')) v(s, g, bit);
insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id, giren_id)
select test.c(s), g, (select id from pdks.vardiya_tanim where kod = 'GUNDUZ'), test.k('kt_ik@ornek.test')
from (select s, g from kt_gun union all select 'KT05', date '2026-11-04') x;

-- Talepler gün gelmeden girilir
set local pdks.test_bugun = '2026-09-14';
set local role authenticated;
select test.oturum('kt_amir@ornek.test');
select pdks.fazla_mesai_talep_et(test.c('KT06'), '2026-09-15', 120, 'Sevkiyat yetişmeli');
reset role;
set local pdks.test_bugun = '2026-10-13';
set local role authenticated;
select test.oturum('kt_amir@ornek.test');
select pdks.fazla_mesai_talep_et(test.c(s), d::date, 120, 'Sevkiyat yetişmeli')
from (values ('KT01', '2026-10-14'), ('KT02', '2026-10-14'), ('KT03', '2026-10-14'),
             ('KT04', '2026-10-14'), ('KT05', '2026-11-04')) v(s, d);
select test.oturum('kt_ik@ornek.test');
select pdks.fazla_mesai_karar((test.plan('KT03', '2026-10-14')).id, true);
select pdks.fazla_mesai_karar((test.plan('KT04', '2026-10-14')).id, false, 'Gerek yok');
reset role;

-- Günler çalışıldı ve işlendi; aylar bitti
set local pdks.test_bugun = '2026-11-15';
insert into pdks.aktarim (kaynak, dosya_adi, dosya_ozeti, veri_tarihi)
select distinct 'pdks', 'kt_' || g || '.csv', 'kt-pdks-' || g, g from kt_gun;
insert into pdks.ham_okutma (aktarim_id, okuyucu_id, kart_no, okutma_zamani, yon)
select (select id from pdks.aktarim where dosya_ozeti = 'kt-pdks-' || g),
       (select id from pdks.okuyucu where kod = 'KT-PDKS'), 'KT-' || s, test.ts(g || ' ' || x.saat), x.yon
from kt_gun cross join lateral (values ('08:00', 'giris'), (bit, 'cikis')) x(saat, yon);
select pdks.gece_isi_calistir('2026-09-15');
select pdks.gece_isi_calistir('2026-10-14');
select test.dogrula('hazırlık: KT06, KT01, KT02 talepleri karar bekliyor; yalnızca KT02''nin 120 dk''sı havuzda',
    (select bool_and((test.plan(s, g)).durum = 'talep')
     from (values ('KT06', date '2026-09-15'), ('KT01', date '2026-10-14'), ('KT02', date '2026-10-14')) v(s, g))
    and (test.hv('KT06', '2026-09-15')).id is null and (test.hv('KT01', '2026-10-14')).id is null
    and (select dakika = 120 and durum = 'inceleme_bekliyor' from test.hv('KT02', '2026-10-14')));

-- 1) Yalnızca talep bekleyen ay: kilit durmaz, talep kapanır, mesajda ve izde görünür ---------
set local role authenticated;
select test.oturum('kt_ik@ornek.test');
insert into kt_sonuc select 9, pdks.ay_kilitle(2026::smallint, 9::smallint);
reset role;
select test.dogrula('Eylül: bekleyen talep normal kilidi durdurmaz',
    pdks.donem_kilitli_mi('2026-09-15'));
select test.dogrula('Eylül: KT06 talebi kilitle "iptal" oldu (kişisiz, açıklamalı, karar zamanı dolu)',
    (select durum = 'iptal' and karar_veren_id is null and karar_zamani is not null
            and karar_aciklama like 'Dönem kilitlendi%'
     from test.plan('KT06', '2026-09-15')));
select test.dogrula('Eylül: kilit sonucunda kapatılan talep sayısı 1 ve mesajda yazıyor',
    (select (sonuc ->> 'kapatilan_fm_talebi')::int = 1
            and sonuc ->> 'mesaj' like '%Karar bekleyen 1 fazla mesai talebi kapatıldı%'
     from kt_sonuc where ay = 9));
select test.dogrula('Eylül: kilit izinde kapatılan talebin listesi (sicil, tarih, dakika)',
    test.kilit(2026, 9) -> 'kapatilan_fm_talep_listesi'
    = '[{"sicil": "KT06", "tarih": "2026-09-15", "planli_dk": 120}]'::jsonb);

-- 2) Havuz da bekliyorsa normal kilit yine durur; talep değişmez (işlem geri alınır) ------------
set local role authenticated;
select test.oturum('kt_ik@ornek.test');
select test.hata('Ekim: KT02''nin havuz kaydı normal kilidi eskisi gibi durdurur', 'onaysız fazla mesai',
    $$select pdks.ay_kilitle(2026::smallint, 10::smallint)$$);
reset role;
select test.dogrula('Ekim: başarısız kilit talepleri kapatmadı',
    (test.plan('KT01', '2026-10-14')).durum = 'talep' and (test.plan('KT02', '2026-10-14')).durum = 'talep');

-- 3) Zorla kilit: bekleyen talepler kapanır; karara bağlanmış ve başka aydaki talepler değişmez -----
set local role authenticated;
select test.oturum('kt_ik@ornek.test');
insert into kt_sonuc select 10, pdks.ay_kilitle(2026::smallint, 10::smallint, true, 'Test: zorla kilit gerekçesi');
reset role;
select test.dogrula('Ekim: KT01 ve KT02 talepleri "iptal (dönem kilitlendi)"',
    (select bool_and(durum = 'iptal' and karar_veren_id is null and karar_aciklama like 'Dönem kilitlendi%')
     from pdks.fazla_mesai_plani where calisan_id in (test.c('KT01'), test.c('KT02'))));
select test.dogrula('Ekim: onaylı (KT03), reddedilmiş (KT04) ve Kasım''daki (KT05) talepler değişmedi',
    (test.plan('KT03', '2026-10-14')).durum = 'onaylandi' and (test.plan('KT04', '2026-10-14')).durum = 'reddedildi'
    and (test.plan('KT05', '2026-11-04')).durum = 'talep');
select test.dogrula('Ekim: mesaj hem zorla geçilen havuzu hem kapatılan 2 talebi söylüyor',
    (select sonuc ->> 'mesaj' like '%1 onaysız fazla mesai%' and sonuc ->> 'mesaj' like '%Karar bekleyen 2 fazla mesai talebi kapatıldı%'
            and (sonuc ->> 'kapatilan_fm_talebi')::int = 2
     from kt_sonuc where ay = 10));
select test.dogrula('Ekim: kilit izinde iki talep listelendi',
    jsonb_array_length(test.kilit(2026, 10) -> 'kapatilan_fm_talep_listesi') = 2);
select test.dogrula('Ekim kilitlendikten sonra o aya ait karar bekleyen talep kalmadı',
    not exists (select 1 from pdks.fazla_mesai_plani
                where durum = 'talep' and is_gunu between '2026-09-01' and '2026-10-31'
                  and calisan_id in (select test.c(s) from unnest(array['KT01','KT02','KT03','KT04','KT05','KT06']) s)));

-- 4) Çalışılan süre havuzdan eskisi gibi karara bağlanır (fark satırı) --------------------------
set local role authenticated;
select test.oturum('kt_ik@ornek.test');
select pdks.fazla_mesai_inceleme_karar((test.hv('KT02', '2026-10-14')).id, true);
reset role;
select test.dogrula('KT02''nin 120 dk''sı kilitten sonra havuzdan onaylandı ve fark satırına gitti',
    (select durum = 'onaylandi' and fark_satiri and fm50_etki_dk = 120 from test.hv('KT02', '2026-10-14')));

-- 5) Kişisiz (sistem) iptal yalnızca kilit sırasında mümkün -----------------------------------
select test.hata('kilit dışında kişisiz iptal reddedilir (yazılı onay geçerli)', 'İptal eden kullanıcı belirtilmeli',
    $$update pdks.fazla_mesai_plani set durum = 'iptal', karar_veren_id = null, karar_aciklama = 'Dönem kilitlendi (sahte)'
      where id = (test.plan('KT05', '2026-11-04')).id$$);
select test.dogrula('ekran kullanıcısı fazla mesai planını doğrudan değiştiremez (yalnızca okur)',
    not has_table_privilege('authenticated', 'pdks.fazla_mesai_plani', 'update'));

do $$ begin raise notice 'TÜM TESTLER GEÇTİ'; end $$;
rollback;
