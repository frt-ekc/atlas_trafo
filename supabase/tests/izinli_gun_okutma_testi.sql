-- =====================================================================
-- İzinli günde okutma uyarısı testleri (20261231200000_kilit_on_kontrol.sql, T-54)
-- Testin kendi sahte verisi (Ekim 2026); örnek veri yüklü olsun olmasın çalışır.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/izinli_gun_okutma_testi.sql
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

create function test.gk(p_sicil text, p_gun date) returns pdks.gun_kaydi language sql security definer as $$
    select * from pdks.gun_kaydi where calisan_id = test.c(p_sicil) and is_gunu = p_gun $$;
create function test.uy(p_sicil text) returns text language sql security definer as $$
    select string_agg(mesaj, ' | ' order by id) from pdks.uyari where tur = 'izin_gununde_okutma' and calisan_id = test.c(p_sicil) $$;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
--   IO01: 15 Ekim mazeret izni önceden girildi; aynı gün 08:00–17:00 okuttu → uyarı
--   IO02: 15 Ekim rapor önceden girildi; 08:05'te okuttu → uyarı
--   IO03: 15 Ekim yıllık izin; okutma yok → uyarı yok
insert into pdks.departman (ad) values ('IO Üretim'), ('IO İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = case when s like 'IOI%' then 'IO İdari' else 'IO Üretim' end), '2025-01-01'
from unnest(array['IO01','IO02','IO03','IOI1']) s;
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('x', 'io_ik@ornek.test', 'ik', test.c('IOI1'), '00000000-0000-0000-0000-000000000f21');
insert into pdks.kart (kart_no, calisan_id) select 'IO-' || s, test.c(s) from unnest(array['IO01','IO02','IO03']) s;
insert into pdks.okuyucu (kod, ad, sistem) values ('IO-PDKS', 'IO PDKS', 'pdks');
insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id, giren_id)
select test.c(s), '2026-10-15', (select id from pdks.vardiya_tanim where kod = 'GUNDUZ'), test.k('io_ik@ornek.test')
from unnest(array['IO01','IO02','IO03']) s;
set local pdks.test_bugun = '2026-10-10';
set local role authenticated;
select test.oturum('io_ik@ornek.test');
select pdks.izin_gir(test.c('IO01'), 'mazeret', '2026-10-15', '2026-10-15');
select pdks.izin_gir(test.c('IO02'), 'rapor',   '2026-10-15', '2026-10-15');
select pdks.izin_gir(test.c('IO03'), 'yillik',  '2026-10-15', '2026-10-15');
reset role;
insert into pdks.aktarim (kaynak, dosya_adi, dosya_ozeti, veri_tarihi) values ('pdks', 'io.csv', 'io-ozet', '2026-10-15');
insert into pdks.ham_okutma (aktarim_id, okuyucu_id, kart_no, okutma_zamani, yon)
select (select id from pdks.aktarim where dosya_ozeti = 'io-ozet'), (select id from pdks.okuyucu where kod = 'IO-PDKS'), 'IO-' || s, test.ts('2026-10-15 ' || z), y
from (values ('IO01', '08:00', 'giris'), ('IO01', '17:00', 'cikis'), ('IO02', '08:05', 'giris')) v(s, z, y);
set local pdks.test_bugun = '2026-10-20';
select pdks.gece_isi_calistir('2026-10-15');

select test.dogrula('hazırlık: üç gün de izinli / raporlu işlendi',
    (test.gk('IO01', '2026-10-15')).durum = 'izinli' and (test.gk('IO02', '2026-10-15')).durum = 'raporlu'
    and (test.gk('IO03', '2026-10-15')).durum = 'izinli');
select test.dogrula('izinli günde okutan IO01 için İK''ya uyarı (gün, saatler)',
    test.uy('IO01') like '%15.10.2026%' and test.uy('IO01') like '%08:00%17:00%');
select test.dogrula('raporlu günde okutan IO02 için uyarı (yalnızca giriş)',
    test.uy('IO02') like '%15.10.2026%08:05%');
select test.dogrula('okutması olmayan izinli gün için uyarı yok (IO03)', test.uy('IO03') is null);
select test.dogrula('uyarı amire görünmez (izin türü İK bilgisi): amir politikası bu türü kapsamaz',
    not exists (select 1 from pg_policy where polrelid = 'pdks.uyari'::regclass and polname = 'amir_okur'
                and pg_get_expr(polqual, polrelid) like '%izin_gununde_okutma%'));

do $$ begin raise notice 'TÜM TESTLER GEÇTİ'; end $$;
rollback;
