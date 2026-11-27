-- =====================================================================
-- Kaybolan geçici kart testleri (20261231200000_kilit_on_kontrol.sql, T-85)
-- Testin kendi sahte verisi (geçici kart kayıtları); örnek veri yüklü olsun olmasın çalışır.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/gecici_kart_kayip_testi.sql
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
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

create function test.gkart(p text) returns pdks.gecici_kart language sql security definer as $$
    select * from pdks.gecici_kart where kart_no = p $$;
create function test.zimmet(p text) returns pdks.gecici_kart_zimmet language sql security definer as $$
    select z.* from pdks.gecici_kart_zimmet z join pdks.gecici_kart g on g.id = z.gecici_kart_id
    where g.kart_no = p order by z.id desc limit 1 $$;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
--   GKK1: güvenlik; GK-K5 kartını GZ01'e verir, kart kaybolur. GK-K6 boşta. GZI1: İK. GZA1: amir.
insert into pdks.departman (ad) values ('GZ Üretim'), ('GZ İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = case when s like 'GZ0%' then 'GZ Üretim' else 'GZ İdari' end), '2025-01-01'
from unnest(array['GZ01','GZI1','GZG1','GZA1']) s;
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('x', 'gz_ik@ornek.test',   'ik',       test.c('GZI1'), '00000000-0000-0000-0000-000000000f31'),
    ('x', 'gz_gv@ornek.test',   'guvenlik', test.c('GZG1'), '00000000-0000-0000-0000-000000000f32'),
    ('x', 'gz_amir@ornek.test', 'amir',     test.c('GZA1'), '00000000-0000-0000-0000-000000000f33');
insert into pdks.gecici_kart (kart_no) values ('GK-K5'), ('GK-K6');
insert into pdks.okuyucu (kod, ad, sistem) values ('GZ-PDKS', 'GZ PDKS', 'pdks');
set local role authenticated;
select test.oturum('gz_gv@ornek.test');
select pdks.gecici_kart_ver((select id from pdks.gecici_kart where kart_no = 'GK-K5'), test.c('GZ01'));

-- 1) Yetki ve gerekçe ---------------------------------------------------------------------------
select test.oturum('gz_amir@ornek.test');
select test.hata('amir geçici kartın durumunu değiştiremez', 'yetkiniz yok',
    $$select pdks.gecici_kart_durum((test.gkart('GK-K5')).id, 'kayip', 'Çalışan kaybettiğini bildirdi')$$);
select test.oturum('gz_gv@ornek.test');
select test.hata('gerekçesiz olmaz', 'gerekçe',
    $$select pdks.gecici_kart_durum((test.gkart('GK-K5')).id, 'kayip', 'yok')$$);
select test.hata('geçersiz durum', 'Durum',
    $$select pdks.gecici_kart_durum((test.gkart('GK-K5')).id, 'calindi', 'Çalışan kaybettiğini bildirdi')$$);

-- 2) Kayıp: kim, ne zaman, neden yazılır; açık zimmet kapanır -----------------------------------
select pdks.gecici_kart_durum((test.gkart('GK-K5')).id, 'kayip', 'Çalışan kaybettiğini bildirdi');
reset role;
select test.dogrula('GK-K5 kayıp; değiştiren güvenlik, neden ve zaman yazılı',
    (select durum = 'kayip' and durum_degistiren_id = test.k('gz_gv@ornek.test') and durum_nedeni like 'Çalışan kaybettiğini%'
            and durum_zamani is not null from test.gkart('GK-K5')));
select test.dogrula('açık zimmet kapandı (iade = kayıp bildirimi, alan güvenlik)',
    (select iade_zamani is not null and iade_alan_id = test.k('gz_gv@ornek.test') and aciklama like '%kayıp%'
     from test.zimmet('GK-K5')));
set local role authenticated;
select test.oturum('gz_gv@ornek.test');
select test.hata('kayıp kart kimseye verilemez', 'kayıp',
    $$select pdks.gecici_kart_ver((test.gkart('GK-K5')).id, test.c('GZ01'))$$);
select test.dogrula('çalışana başka geçici kart verilebilir (zimmet kapandığı için)',
    pdks.gecici_kart_ver((test.gkart('GK-K6')).id, test.c('GZ01')) is not null);

-- 3) Kayıp kart okutulursa İK'ya uyarı --------------------------------------------------------
reset role;
insert into pdks.aktarim (kaynak, dosya_adi, dosya_ozeti, veri_tarihi) values ('pdks', 'gz.csv', 'gz-ozet', current_date);
insert into pdks.ham_okutma (aktarim_id, okuyucu_id, kart_no, okutma_zamani, yon)
values ((select id from pdks.aktarim where dosya_ozeti = 'gz-ozet'), (select id from pdks.okuyucu where kod = 'GZ-PDKS'),
        'GK-K5', now() - interval '1 minute', 'giris');
select pdks.gece_isi_isaretle(current_date, null);
select test.dogrula('kayıp bildirilen geçici kart okutulunca uyarı yazıldı',
    exists (select 1 from pdks.uyari where tur = 'gecici_kart_zimmetsiz' and mesaj like 'Kayıp bildirilen geçici kart GK-K5 okutuldu%'));

-- 4) Bulunan kart yeniden aktif olur; iptal kesindir ------------------------------------------
set local role authenticated;
select test.oturum('gz_gv@ornek.test');
select pdks.gecici_kart_durum((test.gkart('GK-K5')).id, 'aktif', 'Kart bulundu, güvenliğe teslim edildi');
select pdks.gecici_kart_durum((test.gkart('GK-K5')).id, 'iptal', 'Kart kırıldı, kullanımdan kaldırıldı');
select test.hata('iptal edilen kart yeniden aktif olmaz', 'iptal',
    $$select pdks.gecici_kart_durum((test.gkart('GK-K5')).id, 'aktif', 'Yeniden kullanmak istiyoruz')$$);
reset role;

do $$ begin raise notice 'TÜM TESTLER GEÇTİ'; end $$;
rollback;
