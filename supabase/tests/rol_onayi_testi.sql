-- =====================================================================
-- İki adımlı rol verme ve kullanıcı geçmişi testleri (20261223010000_rol_onayi.sql, T-72 + T-33)
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/rol_onayi_testi.sql
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
create function test.izin(p_sicil text) returns bigint language sql security definer as $$
    select id from pdks.izin where calisan_id = test.c(p_sicil) order by id desc limit 1 $$;
create function test.ts(p text) returns timestamptz language sql immutable as $$
    select (p::timestamp) at time zone 'Europe/Istanbul' $$;
create function test.kul(p text) returns pdks.kullanici language sql security definer as $$
    select * from pdks.kullanici where eposta = p $$;
create function test.oneri(p text) returns pdks.rol_onerisi language sql security definer as $$
    select o.* from pdks.rol_onerisi o where o.kullanici_id = test.k(p) order by o.id desc limit 1 $$;
create function test.karar(p text, p_onay boolean, p_aciklama text default null) returns void language sql as $$
    select pdks.rol_onerisi_karar((test.oneri(p)).id, p_onay, p_aciklama) $$;
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
insert into pdks.departman (ad) values ('RO Üretim');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = 'RO Üretim'), '2025-01-01'
from unnest(array['RO01','RO02','RO03','RO04','RO05','ROA1','ROA2','ROI1','ROI2','ROM1','ROY1']) s;
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('x', 'ro_admin@ornek.test', 'admin',    test.c('ROA1'), '00000000-0000-0000-0000-0000000000a2'),
    ('x', 'ro_admin2@ornek.test', 'admin',   test.c('ROA2'), '00000000-0000-0000-0000-0000000000a3'),
    ('x', 'ro_ik1@ornek.test',   'ik',       test.c('ROI1'), '00000000-0000-0000-0000-0000000000a4'),
    ('x', 'ro_ik2@ornek.test',   'ik',       test.c('ROI2'), '00000000-0000-0000-0000-0000000000a5'),
    ('x', 'ro_amir@ornek.test',  'amir',     test.c('ROM1'), '00000000-0000-0000-0000-0000000000a6'),
    ('x', 'ro_yon@ornek.test',   'yonetici', test.c('ROY1'), '00000000-0000-0000-0000-0000000000a7');
insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000b9', 'ro_sahte@ornek.test');

-- 1) Rapordaki yol: admin başka çalışana bağlı İK hesabı açar -------------------
set local role authenticated;
select test.oturum('ro_admin@ornek.test');
select test.dogrula('admin İK hesabı açabilir (öneri olarak)',
    pdks.kullanici_ekle('ro_sahte@ornek.test', 'ik', test.c('RO01')) > 0);
reset role;
select test.dogrula('yeni İK hesabı pasif; Auth hesabı bağlansa da oturum yok',
    (select not aktif and auth_kullanici_id is not null from test.kul('ro_sahte@ornek.test')));
set local role authenticated;
select test.oturum('ro_sahte@ornek.test');
select test.hata('onaysız İK hesabı işlem yapamaz', 'Oturum bulunamadı',
    $$select pdks.izin_gir(test.c('ROA1'), 'yillik', '2026-12-28', '2026-12-31')$$);
reset role;
select test.dogrula('öneri kim, kime, hangi rol, hangi çalışan bilgisini tutar',
    (select durum = 'bekliyor' and oneren_id = test.k('ro_admin@ornek.test') and calisan_id = test.c('RO01')
            and yeni_rol = 'ik' and yeni_hesap and aktif_yap from test.oneri('ro_sahte@ornek.test')));
set local role authenticated;
select test.oturum('ro_admin@ornek.test');
select test.hata('admin pasif İK hesabını kendisi açamaz', 'onay bekleyen bir rol değişikliği',
    $$select pdks.kullanici_guncelle(test.k('ro_sahte@ornek.test'), p_aktif => true)$$);
select test.hata('admin kendi önerisini onaylayamaz', 'yetkiniz yok', $$select test.karar('ro_sahte@ornek.test', true)$$);
select test.oturum('ro_admin2@ornek.test');
select test.hata('başka admin de onaylayamaz', 'yetkiniz yok', $$select test.karar('ro_sahte@ornek.test', true)$$);
select test.oturum('ro_amir@ornek.test');
select test.hata('amir onaylayamaz', 'yetkiniz yok', $$select test.karar('ro_sahte@ornek.test', true)$$);
select test.oturum('ro_ik1@ornek.test');
select test.hata('ret gerekçesiz olmaz', 'Ret gerekçesi', $$select test.karar('ro_sahte@ornek.test', false, ' ')$$);
select test.karar('ro_sahte@ornek.test', false, 'Bu çalışan İK görevlisi değil');
reset role;
select test.dogrula('ret: hesap pasif kalır, karar izi durur',
    (select not aktif from test.kul('ro_sahte@ornek.test'))
    and (select durum = 'reddedildi' and karar_veren_id = test.k('ro_ik1@ornek.test') and karar_zamani is not null
         from test.oneri('ro_sahte@ornek.test')));
set local role authenticated;
select test.oturum('ro_admin@ornek.test');
select pdks.kullanici_guncelle(test.k('ro_sahte@ornek.test'), p_aktif => true);
reset role;
select test.dogrula('reddedilmiş İK hesabını açmak yeniden öneri olur; hesap pasif kalır',
    (select not aktif from test.kul('ro_sahte@ornek.test'))
    and (select durum = 'bekliyor' and aktif_yap and not yeni_hesap from test.oneri('ro_sahte@ornek.test')));
set local role authenticated;
select test.oturum('ro_ik2@ornek.test');
select test.karar('ro_sahte@ornek.test', true);
select test.oturum('ro_sahte@ornek.test');
select test.dogrula('İK onaylayınca hesap açılır', pdks.oturum_rolu() = 'ik');
reset role;

-- 2) Var olan hesabı yükseltme ---------------------------------------------------
set local role authenticated;
select test.oturum('ro_admin@ornek.test');
select pdks.kullanici_guncelle(test.k('ro_amir@ornek.test'), p_rol => 'ik', p_ust_amir_id => test.k('ro_yon@ornek.test'));
reset role;
select test.dogrula('amir → İK: onaya kadar eski rolüyle aktif; üst amir hemen değişir',
    (select rol = 'amir' and aktif and ust_amir_id = test.k('ro_yon@ornek.test') from test.kul('ro_amir@ornek.test'))
    and (select eski_rol = 'amir' and yeni_rol = 'ik' and not aktif_yap from test.oneri('ro_amir@ornek.test')));
set local role authenticated;
select test.oturum('ro_admin@ornek.test');
select test.hata('ikinci öneri açılamaz', 'onay bekleyen bir rol değişikliği',
    $$select pdks.kullanici_guncelle(test.k('ro_amir@ornek.test'), p_rol => 'admin')$$);
select pdks.kullanici_guncelle(test.k('ro_amir@ornek.test'), p_rol => 'amir', p_aktif => true);
select test.dogrula('değişiklik içermeyen kayıt bekleyen öneriyi bozmaz', (test.oneri('ro_amir@ornek.test')).durum = 'bekliyor');
select test.oturum('ro_ik1@ornek.test');
select test.karar('ro_amir@ornek.test', true);
reset role;
select test.dogrula('onaylanınca rol İK olur', (select rol = 'ik' and aktif from test.kul('ro_amir@ornek.test')));
set local role authenticated;
select test.hata('karara bağlanmış öneriye yeniden karar verilemez', 'bulunamadı', $$select test.karar('ro_amir@ornek.test', false, 'Vazgeçildi')$$);
select test.oturum('ro_admin@ornek.test');
select pdks.kullanici_guncelle(test.k('ro_amir@ornek.test'), p_rol => 'amir');
select test.dogrula('rolü düşürmek tek adımdır', (test.kul('ro_amir@ornek.test')).rol = 'amir');
select pdks.kullanici_guncelle(test.k('ro_amir@ornek.test'), p_rol => 'guvenlik');
select pdks.kullanici_guncelle(test.k('ro_amir@ornek.test'), p_rol => 'amir');
select test.dogrula('diğer roller tek adımdır', (test.kul('ro_amir@ornek.test')).rol = 'amir');

-- 3) Görevler ayrılığı -----------------------------------------------------------
select pdks.kullanici_guncelle(test.k('ro_ik1@ornek.test'), p_rol => 'admin');
select test.dogrula('İK → admin de öneridir', (test.kul('ro_ik1@ornek.test')).rol = 'ik');
select test.oturum('ro_ik1@ornek.test');
select test.hata('İK kendi hesabının önerisine karar veremez', 'Görevler ayrılığı', $$select test.karar('ro_ik1@ornek.test', true)$$);
select test.oturum('ro_ik2@ornek.test');
select test.karar('ro_ik1@ornek.test', false, 'Görev değişikliği yok');
-- Öneren admin sonradan İK olursa kendi önerisini onaylayamaz
select test.oturum('ro_admin2@ornek.test');
select pdks.kullanici_guncelle(test.k('ro_yon@ornek.test'), p_rol => 'admin');
select test.oturum('ro_admin@ornek.test');
select pdks.kullanici_guncelle(test.k('ro_admin2@ornek.test'), p_rol => 'ik');
select test.oturum('ro_ik2@ornek.test');
select test.karar('ro_admin2@ornek.test', true);
select test.oturum('ro_admin2@ornek.test');
select test.hata('öneren, İK olsa da kendi önerisini onaylayamaz', 'Görevler ayrılığı', $$select test.karar('ro_yon@ornek.test', true)$$);

-- 4) Pasife alma, iptal, işten ayrılma --------------------------------------------
select test.oturum('ro_admin@ornek.test');
select pdks.kullanici_guncelle(test.k('ro_yon@ornek.test'), p_aktif => false);
select test.dogrula('pasife alınan hesabın bekleyen önerisi iptal olur',
    (test.oneri('ro_yon@ornek.test')).durum = 'iptal' and not (test.kul('ro_yon@ornek.test')).aktif);
select pdks.kullanici_ekle('ro_iki@ornek.test', 'admin', test.c('RO02'));
reset role;
update pdks.calisan set aktif = false, isten_cikis_tarihi = '2026-11-20' where sicil_no = 'RO02';
set local role authenticated;
select test.oturum('ro_ik2@ornek.test');
select test.hata('işten ayrılanın önerisi onaylanamaz', 'işten ayrılmış', $$select test.karar('ro_iki@ornek.test', true)$$);
select test.oturum('ro_admin@ornek.test');
select pdks.kullanici_ekle('ro_uc@ornek.test', 'amir', test.c('RO03'));
select test.dogrula('amir hesabı eskisi gibi hemen açılır',
    (test.kul('ro_uc@ornek.test')).aktif and (test.oneri('ro_uc@ornek.test')).id is null);
select pdks.kullanici_guncelle(test.k('ro_ik2@ornek.test'), p_aktif => false);
select test.dogrula('İK hesabını pasife almak tek adımdır', not (test.kul('ro_ik2@ornek.test')).aktif);
select pdks.kullanici_guncelle(test.k('ro_ik2@ornek.test'), p_aktif => true);
select test.dogrula('pasif İK hesabını yeniden açmak öneridir',
    not (test.kul('ro_ik2@ornek.test')).aktif and (test.oneri('ro_ik2@ornek.test')).durum = 'bekliyor');
reset role;

-- 5) Kullanıcı geçmişi (T-33) -------------------------------------------------------
select test.dogrula('hesap açma izi: yapan, çalışan ve rol',
    (select count(*) = 2 from pdks.kullanici_gecmisi where kullanici_id = test.k('ro_uc@ornek.test')
       and yapan_id = test.k('ro_admin@ornek.test') and calisan_id = test.c('RO03')
       and (alan, yeni_deger) in (('hesap', 'açıldı'), ('rol', 'amir'))));
select test.dogrula('onaylanan rolün izi: eski / yeni rol, onaylayan ve öneri',
    (select count(*) = 1 from pdks.kullanici_gecmisi g join pdks.rol_onerisi o on o.id = g.rol_onerisi_id
     where g.kullanici_id = test.k('ro_amir@ornek.test') and g.alan = 'rol' and g.eski_deger = 'amir' and g.yeni_deger = 'ik'
       and g.yapan_id = test.k('ro_ik1@ornek.test') and o.oneren_id = test.k('ro_admin@ornek.test')));
select test.dogrula('rol düşürme, aktiflik ve üst amir izi; tek adımlı işlemde öneri boş',
    exists (select 1 from pdks.kullanici_gecmisi where kullanici_id = test.k('ro_amir@ornek.test') and alan = 'rol'
              and eski_deger = 'ik' and yeni_deger = 'amir' and rol_onerisi_id is null)
    and exists (select 1 from pdks.kullanici_gecmisi where kullanici_id = test.k('ro_ik2@ornek.test') and alan = 'aktif'
              and eski_deger = 'true' and yeni_deger = 'false' and yapan_id = test.k('ro_admin@ornek.test'))
    and exists (select 1 from pdks.kullanici_gecmisi where kullanici_id = test.k('ro_amir@ornek.test') and alan = 'ust_amir_id'));
select test.hata('geçmiş değiştirilemez', 'değiştirilemez', $$update pdks.kullanici_gecmisi set yeni_deger = 'x'$$);
select test.hata('geçmiş silinemez', 'değiştirilemez', $$delete from pdks.kullanici_gecmisi$$);
select test.hata('öneri silinemez', 'silinemez', $$delete from pdks.rol_onerisi$$);
select test.hata('tablo kuralı: admin kararı yazılamaz', 'yalnızca İK',
    $$update pdks.rol_onerisi set durum = 'onaylandi', karar_veren_id = test.k('ro_admin@ornek.test') where durum = 'bekliyor'$$);

-- 6) Yetkiler -----------------------------------------------------------------------
set local role authenticated;
select test.oturum('ro_amir@ornek.test');
select test.dogrula('amir önerileri ve geçmişi göremez',
    (select count(*) = 0 from pdks.rol_onerisi) and (select count(*) = 0 from pdks.kullanici_gecmisi));
select test.oturum('ro_admin@ornek.test');
select test.dogrula('admin önerileri ve geçmişi görür, yazamaz',
    (select count(*) > 0 from pdks.rol_onerisi) and (select count(*) > 0 from pdks.kullanici_gecmisi)
    and not has_table_privilege('authenticated', 'pdks.rol_onerisi', 'insert, update, delete')
    and not has_table_privilege('authenticated', 'pdks.kullanici_gecmisi', 'insert, update, delete'));
select test.oturum('ro_ik1@ornek.test');
select test.dogrula('İK bekleyen önerileri görür', (select count(*) > 0 from pdks.rol_onerisi where durum = 'bekliyor'));
reset role;
select test.dogrula('anon karar veremez', not has_function_privilege('anon', 'pdks.rol_onerisi_karar(bigint, boolean, text)', 'execute'));

do $$ begin raise notice 'TÜM TESTLER GEÇTİ'; end $$;
rollback;
