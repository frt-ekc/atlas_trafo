-- =====================================================================
-- Mükerrer çıkış okutması testleri (20261231190000_puantaj_kalanlari.sql, T-29)
-- Testin kendi sahte verisi (Ekim 2026); örnek veri yüklü olsun olmasın çalışır.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/mukerrer_cikis_testi.sql
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
create function test.saat(p timestamptz) returns text language sql immutable as $$
    select to_char(p at time zone 'Europe/Istanbul', 'HH24:MI:SS') $$;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
-- Hepsi 14 Ekim GÜNDÜZ (08:00–17:00); mükerrer eşiği 3 dk, erken çıkış toleransı 5 dk.
--   MK01: iki okuyucuda giriş 07:50 / 07:52, çıkış 16:59 / 17:01  → giriş 07:50, çıkış 17:01
--   MK02: çıkış 16:53 ve 16:56                                    → çıkış 16:56 (erken 0; ilk tutulsaydı 7 dk)
--   MK03: zincir çıkış 17:00, 17:02, 17:04                        → çıkış 17:04
--   MK04: eski kuralla 17:01 önceden "mükerrer" işaretli          → 16:59'a dokunulmaz (iki çıkış birden düşmez)
insert into pdks.departman (ad) values ('MK Üretim'), ('MK İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = case when s like 'MKI%' then 'MK İdari' else 'MK Üretim' end), '2025-01-01'
from unnest(array['MK01','MK02','MK03','MK04','MKI1']) s;
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('x', 'mk_ik@ornek.test', 'ik', test.c('MKI1'), '00000000-0000-0000-0000-000000000fe1');
insert into pdks.kart (kart_no, calisan_id) select 'MK-' || s, test.c(s) from unnest(array['MK01','MK02','MK03','MK04']) s;
insert into pdks.okuyucu (kod, ad, sistem) values ('MK-P1', 'MK PDKS 1', 'pdks'), ('MK-P2', 'MK PDKS 2', 'pdks');
insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id, giren_id)
select test.c(s), '2026-10-14', (select id from pdks.vardiya_tanim where kod = 'GUNDUZ'), test.k('mk_ik@ornek.test')
from unnest(array['MK01','MK02','MK03','MK04']) s;
insert into pdks.aktarim (kaynak, dosya_adi, dosya_ozeti, veri_tarihi) values ('pdks', 'mk.csv', 'mk-ozet', '2026-10-14');
insert into pdks.ham_okutma (aktarim_id, okuyucu_id, kart_no, okutma_zamani, yon)
select (select id from pdks.aktarim where dosya_ozeti = 'mk-ozet'), (select id from pdks.okuyucu where kod = o),
       'MK-' || s, test.ts('2026-10-14 ' || z), y
from (values ('MK01', 'MK-P1', '07:50:00', 'giris'), ('MK01', 'MK-P2', '07:52:00', 'giris'),
             ('MK01', 'MK-P2', '16:59:00', 'cikis'), ('MK01', 'MK-P1', '17:01:00', 'cikis'),
             ('MK02', 'MK-P1', '07:55:00', 'giris'),
             ('MK02', 'MK-P1', '16:53:00', 'cikis'), ('MK02', 'MK-P1', '16:56:00', 'cikis'),
             ('MK03', 'MK-P1', '07:55:00', 'giris'),
             ('MK03', 'MK-P1', '17:00:00', 'cikis'), ('MK03', 'MK-P1', '17:02:00', 'cikis'), ('MK03', 'MK-P1', '17:04:00', 'cikis'),
             ('MK04', 'MK-P1', '07:55:00', 'giris'),
             ('MK04', 'MK-P1', '16:59:00', 'cikis'), ('MK04', 'MK-P1', '17:01:00', 'cikis')) v(s, o, z, y);
-- MK04: dağıtımdan önceki gece eski kuralla işaretlenmiş gibi
insert into pdks.okutma_isareti (ham_okutma_id, isaret, aciklama)
select h.id, 'mukerrer', 'eski kural (test)' from pdks.ham_okutma h where h.kart_no = 'MK-MK04' and h.okutma_zamani = test.ts('2026-10-14 17:01');
set local pdks.test_bugun = '2026-10-20';
select pdks.gece_isi_calistir('2026-10-14');

select test.dogrula('iki okuyucu: giriş ilk okutma (07:50), çıkış son okutma (17:01)',
    test.saat((test.gk('MK01', '2026-10-14')).giris_zamani) = '07:50:00'
    and test.saat((test.gk('MK01', '2026-10-14')).cikis_zamani) = '17:01:00');
select test.dogrula('çıkış 16:53 ve 16:56: çıkış 16:56, erken çıkış tolerans içinde (0)',
    test.saat((test.gk('MK02', '2026-10-14')).cikis_zamani) = '16:56:00'
    and (test.gk('MK02', '2026-10-14')).erken_cikis_dk = 0);
select test.dogrula('zincir 17:00 / 17:02 / 17:04: çıkış zincirin sonu (17:04)',
    test.saat((test.gk('MK03', '2026-10-14')).cikis_zamani) = '17:04:00');
select test.dogrula('eski kuralla işaretlenmiş çifte dokunulmaz: çıkış 16:59 kalır, iki çıkış birden düşmez',
    test.saat((test.gk('MK04', '2026-10-14')).cikis_zamani) = '16:59:00'
    and (select count(*) = 1 from pdks.okutma_isareti i join pdks.ham_okutma h on h.id = i.ham_okutma_id
         where h.kart_no = 'MK-MK04' and i.isaret = 'mukerrer'));
select pdks.gece_isi_calistir('2026-10-15');
select test.dogrula('ertesi gece pencere tekrar tarayınca yeni işaret eklenmez (MK01: tek giriş, tek çıkış işareti)',
    (select count(*) = 2 from pdks.okutma_isareti i join pdks.ham_okutma h on h.id = i.ham_okutma_id
     where h.kart_no = 'MK-MK01' and i.isaret = 'mukerrer'));

do $$ begin raise notice 'TÜM TESTLER GEÇTİ'; end $$;
rollback;
