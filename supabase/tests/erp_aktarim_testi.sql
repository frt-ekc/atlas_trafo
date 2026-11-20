-- =====================================================================
-- ERP aktarım testleri (20261127020000_erp_aktarim.sql)
--   v_puantaj_aktarim: yalnızca kilitli ay · puantaj satırıyla tutarlılık ·
--   fark satırı ve kaynak dönem · yetkiler
-- Testin kendi sahte verisi (Ekim 2026) kullanılır; örnek veri yüklü olsun
-- olmasın çalışır. Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/erp_aktarim_testi.sql
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
create function test.oturum(p_eposta text) returns void language sql security definer as $$
    select set_config('request.jwt.claims',
        json_build_object('sub', (select auth_kullanici_id from pdks.kullanici where eposta = p_eposta),
                          'role', 'authenticated')::text, true);
$$;
create function test.c(p text) returns bigint language sql security definer as $$
    select id from pdks.calisan where sicil_no = p $$;
create function test.k(p text) returns bigint language sql security definer as $$
    select id from pdks.kullanici where eposta = p $$;
create function test.gk(p_sicil text, p_gun date) returns pdks.gun_kaydi language sql security definer as $$
    select * from pdks.gun_kaydi where calisan_id = test.c(p_sicil) and is_gunu = p_gun $$;
create function test.ts(p text) returns timestamptz language sql immutable as $$
    select (p::timestamp) at time zone 'Europe/Istanbul' $$;
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
insert into pdks.departman (ad) values ('EA Üretim'), ('EA İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = d), '2025-01-01'
from (values ('EA01', 'EA Üretim'), ('EA02', 'EA Üretim'), ('EAA1', 'EA Üretim'), ('EAI1', 'EA İdari')) v(s, d);
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('EA Amir', 'ea_amir@ornek.test', 'amir', test.c('EAA1'), '00000000-0000-0000-0000-0000000000c1'),
    ('EA İK',   'ea_ik@ornek.test',   'ik',   test.c('EAI1'), '00000000-0000-0000-0000-0000000000c2');
update pdks.departman set amir_id = test.k('ea_amir@ornek.test') where ad = 'EA Üretim';
insert into pdks.kart (kart_no, calisan_id) values ('EA-01', test.c('EA01')), ('EA-02', test.c('EA02'));
insert into pdks.okuyucu (kod, ad, sistem) values ('EA-PDKS', 'EA PDKS', 'pdks');
insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id, giren_id)
select test.c(s), g, (select id from pdks.vardiya_tanim where kod = 'GUNDUZ_8'), test.k('ea_ik@ornek.test')
from unnest(array['EA01', 'EA02']) s, unnest(array['2026-10-05', '2026-10-06']::date[]) g;
insert into pdks.aktarim (kaynak, dosya_adi, dosya_ozeti, veri_tarihi)
select 'pdks', 'ea_' || g || '.csv', 'ea-pdks-' || g, g from unnest(array['2026-10-05', '2026-10-06']::date[]) g;
-- EA01 iki gün normal; EA02 6 Ekim 20 dk geç
insert into pdks.ham_okutma (aktarim_id, okuyucu_id, kart_no, okutma_zamani, yon)
select (select id from pdks.aktarim where dosya_ozeti = 'ea-pdks-' || (z::timestamp)::date),
       (select id from pdks.okuyucu where kod = 'EA-PDKS'), k, test.ts(z), y
from (values ('EA-01', '2026-10-05 07:55', 'giris'), ('EA-01', '2026-10-05 16:02', 'cikis'),
             ('EA-01', '2026-10-06 07:56', 'giris'), ('EA-01', '2026-10-06 16:01', 'cikis'),
             ('EA-02', '2026-10-05 07:57', 'giris'), ('EA-02', '2026-10-05 16:03', 'cikis'),
             ('EA-02', '2026-10-06 08:20', 'giris'), ('EA-02', '2026-10-06 16:00', 'cikis')) v(k, z, y);
select pdks.gece_isi_calistir('2026-10-05');
select pdks.gece_isi_calistir('2026-10-06');

-- 1) Açık ay aktarıma çıkmaz ---------------------------------------------------------
select test.dogrula('açık ay ERP aktarımında yok',
    not exists (select 1 from pdks.v_puantaj_aktarim where donem = '2026-10'));

set local role authenticated;
select test.oturum('ea_ik@ornek.test');
select pdks.ay_kilitle(2026::smallint, 10::smallint, true);
reset role;

-- 2) Kilitli ay -----------------------------------------------------------------------
select test.dogrula('kilitli ay: EA01 için NÇ 2 gün / 840 dk ve HT satırı (sicil ve dönemle)',
    (select gun = 2 and dakika = 840 from pdks.v_puantaj_aktarim
     where donem = '2026-10' and sicil = 'EA01' and kod = 'NÇ' and satir_turu = 'normal' and kaynak_donem is null)
    and exists (select 1 from pdks.v_puantaj_aktarim where donem = '2026-10' and sicil = 'EA01' and kod = 'HT'));
select test.dogrula('aktarım satırları puantaj kalemleriyle birebir (eksik / fazla satır yok)',
    (select count(*) from pdks.v_puantaj_aktarim a
     join pdks.puantaj_satiri s on s.id = a.puantaj_satiri_id
     where s.calisan_id in (test.c('EA01'), test.c('EA02')))
    = (select count(*) from pdks.puantaj_kalemi k join pdks.puantaj_satiri s on s.id = k.puantaj_satiri_id
       where s.calisan_id in (test.c('EA01'), test.c('EA02'))));
select test.dogrula('her çalışanın NÇ + FM50 + FM100 dakikası puantajdaki çalışma dakikasına eşit',
    not exists (select 1 from pdks.puantaj_satiri s
                join pdks.donem d on d.id = s.donem_id and d.yil = 2026 and d.ay = 10
                where s.calisan_id in (test.c('EA01'), test.c('EA02'))
                  and s.calisma_dk <> (select coalesce(sum(dakika), 0) from pdks.v_puantaj_aktarim a
                                       where a.puantaj_satiri_id = s.id and a.kod in ('NÇ', 'FM50', 'FM100'))));
select test.dogrula('ayın her günü için tam bir gün kodu (31 gün)',
    (select sum(gun) = 31 from pdks.v_puantaj_aktarim where donem = '2026-10' and sicil = 'EA02' and kod <> 'FM50'));

-- 3) Fark satırı: kaynak dönem dolu ---------------------------------------------------
-- Örnek veri yüklüyse onun Kasım planları bu testte gece işinden geçmez; ay kilidi (20261201010000)
-- işlenmemiş planlı günü zorla bile kabul etmez. Test yalnızca kendi verisine bakar (ROLLBACK geri alır).
delete from pdks.vardiya_plani where tarih between '2026-11-01' and '2026-11-30';
set local role authenticated;
select test.oturum('ea_ik@ornek.test');
select pdks.kayit_duzelt((test.gk('EA02', '2026-10-06')).id, 'giris_zamani', '2026-10-06 08:00+03',
                         'Kilit sonrası belge geldi: 08:00 girişi');
select pdks.ay_kilitle(2026::smallint, 11::smallint, true);
reset role;
select test.dogrula('fark satırı: dönem 2026-11, kaynak dönem 2026-10, NÇ +20 dk',
    (select gun = 0 and dakika = 20 from pdks.v_puantaj_aktarim
     where donem = '2026-11' and sicil = 'EA02' and satir_turu = 'fark' and kaynak_donem = '2026-10' and kod = 'NÇ'));

-- 4) Yetkiler -------------------------------------------------------------------------
set local role authenticated;
select test.oturum('ea_amir@ornek.test');
select test.dogrula('amir ERP aktarımını göremez', (select count(*) from pdks.v_puantaj_aktarim) = 0);
select test.oturum('ea_ik@ornek.test');
select test.dogrula('İK ERP aktarımını görür',
    (select count(*) > 0 from pdks.v_puantaj_aktarim where sicil in ('EA01', 'EA02')));
reset role;
select test.dogrula('aktarım görünümü çağıranın yetkisiyle çalışır ve yalnızca okunur',
    (select 'security_invoker=true' = any (reloptions) from pg_class where oid = 'pdks.v_puantaj_aktarim'::regclass)
    and not has_table_privilege('authenticated', 'pdks.v_puantaj_aktarim', 'insert'));

do $$ begin raise notice 'ERP AKTARIM TESTLERİ GEÇTİ'; end $$;
rollback;
