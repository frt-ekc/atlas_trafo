-- =====================================================================
-- İşten ayrılan çalışanın hesabı (20261211010000_cikmis_hesap.sql, T-71)
--   * Admin, işten ayrılmış çalışanın hesabını yeniden açamaz (kullanici_guncelle).
--   * Hesap bir şekilde açık kalsa bile oturum yoktur: oturum_kullanici_id bağlı
--     çalışanın aktif olmasını şart koşar; işlem "Oturum bulunamadı" ile reddedilir.
--   * Çalışmaya devam eden birinin kapatılmış hesabı yine açılabilir.
--
-- Testin kendi sahte verisi kullanılır; örnek veri yüklü olsun olmasın çalışır.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/cikmis_hesap_testi.sql
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
create function test.oturum(p_uuid text) returns void language sql as $$
    select set_config('request.jwt.claims', json_build_object('sub', p_uuid, 'role', 'authenticated')::text, true) $$;
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
--   HSX1: İK, işten ayrılacak · HSY1: amir, çalışmaya devam ediyor (hesabı kapatılacak)
--   HSI2: çıkışı giren İK · HSD1: admin · HSW1: izin girilecek çalışan
insert into pdks.departman (ad) values ('HS İdari'), ('HS Üretim');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = d), '2025-01-01'
from (values ('HSX1', 'HS İdari'), ('HSY1', 'HS İdari'), ('HSI2', 'HS İdari'), ('HSD1', 'HS İdari'),
             ('HSW1', 'HS Üretim')) v(s, d);
insert into pdks.kullanici (eposta, rol, calisan_id, auth_kullanici_id)
select e, r, test.c(s), u::uuid
from (values ('hs_x1@ornek.test',    'ik',    'HSX1', '00000000-0000-0000-0000-0000000071b1'),
             ('hs_y1@ornek.test',    'amir',  'HSY1', '00000000-0000-0000-0000-0000000071b2'),
             ('hs_ik2@ornek.test',   'ik',    'HSI2', '00000000-0000-0000-0000-0000000071b3'),
             ('hs_admin@ornek.test', 'admin', 'HSD1', '00000000-0000-0000-0000-0000000071b4')) v(e, r, s, u);

-- 1) Çıkış: hesap kapanır ----------------------------------------------------
select test.oturum('00000000-0000-0000-0000-0000000071b3');
set local role authenticated;
select pdks.isten_cikis_gir(test.c('HSX1'), '2026-10-14', 'İstifa') \g /dev/null
reset role;
select test.dogrula('çıkış girildi: çalışan ve hesabı aktif değil',
    (select not c.aktif and not k.aktif from pdks.calisan c join pdks.kullanici k on k.calisan_id = c.id
     where c.sicil_no = 'HSX1'));

-- 2) Admin çıkmış çalışanın hesabını açamaz ---------------------------------
select test.oturum('00000000-0000-0000-0000-0000000071b4');
set local role authenticated;
select test.hata('admin, işten ayrılmış çalışanın hesabını yeniden açamaz',
    'işten ayrılmış (çıkış: 14.10.2026); hesabı yeniden açılamaz',
    $$select pdks.kullanici_guncelle(test.k('hs_x1@ornek.test'), p_aktif => true)$$);
reset role;
select test.dogrula('hesap kapalı kaldı', not (select aktif from pdks.kullanici where eposta = 'hs_x1@ornek.test'));

-- 3) Hesap elle açılmış olsa bile oturum yok --------------------------------
update pdks.kullanici set aktif = true where eposta = 'hs_x1@ornek.test';   -- ör. veritabanına elle müdahale
select test.oturum('00000000-0000-0000-0000-0000000071b1');
set local role authenticated;
select test.dogrula('çıkmış çalışanın açık hesabıyla oturum yok, rol yok, veri yok',
    pdks.oturum_kullanici_id() is null and pdks.oturum_rolu() is null and not pdks.tum_veriyi_gorur()
    and (select count(*) from pdks.calisan) = 0);
select test.hata('çıkmış çalışanın açık hesabı işlem yapamaz (izin girişi)', 'Oturum bulunamadı',
    $$select pdks.izin_gir(test.c('HSW1'), 'yillik', '2026-12-14', '2026-12-15')$$);
reset role;

-- 4) Çalışmaya devam edenin hesabı açılıp kapanabilir ------------------------
select test.oturum('00000000-0000-0000-0000-0000000071b4');
set local role authenticated;
select test.calisir('admin, çalışmaya devam eden amirin hesabını kapattı',
    $$select pdks.kullanici_guncelle(test.k('hs_y1@ornek.test'), p_aktif => false)$$);
select test.calisir('admin, aynı hesabı yeniden açtı',
    $$select pdks.kullanici_guncelle(test.k('hs_y1@ornek.test'), p_aktif => true)$$);
reset role;
select test.oturum('00000000-0000-0000-0000-0000000071b2');
set local role authenticated;
select test.dogrula('yeniden açılan amir hesabıyla oturum var', pdks.oturum_rolu() = 'amir');
reset role;

select 'Çıkmış hesap testi: hepsi GEÇTİ';
rollback;
