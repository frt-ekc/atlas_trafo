-- =====================================================================
-- Organizasyon ve roller testleri (20261125010000_organizasyon_ve_roller.sql)
--   yaka · isg ve admin rolleri · admin'in kullanıcı ve ayar fonksiyonları ·
--   admin karar veremez · rol bazında görünürlük
-- Testin kendi sahte verisi kullanılır; örnek veri yüklü olsun olmasın çalışır.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/organizasyon_roller_testi.sql
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
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
insert into pdks.departman (ad, yaka) values ('OR Üretim', 'mavi'), ('OR Bilgi İşlem', 'beyaz');
insert into pdks.departman (ad) values ('OR Varsayılan');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = d), '2025-01-01'
from (values ('OR01', 'OR Üretim'), ('OR02', 'OR Üretim'), ('ORM1', 'OR Üretim'), ('ORI1', 'OR Bilgi İşlem'),
             ('ORA1', 'OR Bilgi İşlem'), ('ORS1', 'OR Bilgi İşlem'), ('ORN1', 'OR Bilgi İşlem')) v(s, d);
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('OR Amir',  'or_amir@ornek.test',  'amir',  test.c('ORM1'), '00000000-0000-0000-0000-0000000000a1'),
    ('OR İK',    'or_ik@ornek.test',    'ik',    test.c('ORI1'), '00000000-0000-0000-0000-0000000000a2'),
    ('OR Admin', 'or_admin@ornek.test', 'admin', test.c('ORA1'), '00000000-0000-0000-0000-0000000000a3'),
    ('OR İSG',   'or_isg@ornek.test',   'isg',   test.c('ORS1'), '00000000-0000-0000-0000-0000000000a4');
update pdks.departman set amir_id = test.k('or_amir@ornek.test') where ad = 'OR Üretim';
insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id, giren_id)
values (test.c('OR01'), '2026-10-05', (select id from pdks.vardiya_tanim where kod = 'GUNDUZ_8'), test.k('or_ik@ornek.test'));
insert into pdks.izin (calisan_id, tur, baslangic, bitis, giren_id)
values (test.c('OR02'), 'rapor', '2026-10-05', '2026-10-06', test.k('or_ik@ornek.test'));
insert into pdks.gun_kaydi (calisan_id, is_gunu, vardiya_id, durum)
values (test.c('OR01'), '2026-10-05', (select id from pdks.vardiya_tanim where kod = 'GUNDUZ_8'), 'eksik');

-- 1) Yaka ve roller ---------------------------------------------------------------
select test.dogrula('departman yaka alanı: mavi / beyaz; varsayılan mavi',
    (select yaka = 'beyaz' from pdks.departman where ad = 'OR Bilgi İşlem')
    and (select yaka = 'mavi' from pdks.departman where ad = 'OR Varsayılan'));
select test.hata('yaka yalnızca mavi ya da beyaz', 'check',
    $$insert into pdks.departman (ad, yaka) values ('OR Hatalı', 'gri')$$);
select test.dogrula('isg ve admin rolleri tanımlı',
    exists (select 1 from pdks.kullanici where eposta = 'or_isg@ornek.test' and rol = 'isg')
    and exists (select 1 from pdks.kullanici where eposta = 'or_admin@ornek.test' and rol = 'admin'));
select test.hata('tanımsız rol girilemez', 'check',
    format($$insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id) values ('X', 'x@ornek.test', 'mudur', %s)$$,
           test.c('ORN1')));

-- 2) Görünürlük (RLS) ------------------------------------------------------------------
set local role authenticated;
select test.oturum('or_admin@ornek.test');
select test.dogrula('admin kullanıcıları, çalışanları, ayarları, okuyucuları ve gece işini görür',
    (select count(*) >= 4 from pdks.kullanici) and (select count(*) >= 7 from pdks.calisan)
    and (select count(*) > 0 from pdks.ayar) and (select count(*) > 0 from pdks.ayar_gecmisi)
    and has_table_privilege('pdks.okuyucu', 'select') and has_table_privilege('pdks.gece_isi', 'select'));
select test.dogrula('admin çalışan kayıtlarını göremez (gün kaydı, izin, düzeltme, uyarı, puantaj)',
    (select count(*) from pdks.gun_kaydi) = 0 and (select count(*) from pdks.izin) = 0
    and (select count(*) from pdks.duzeltme) = 0 and (select count(*) from pdks.uyari) = 0
    and (select count(*) from pdks.puantaj_satiri) = 0 and (select count(*) from pdks.v_izin_amir) = 0);
select test.oturum('or_isg@ornek.test');
select test.dogrula('İSG uzmanı çalışan listesini ve departmanları görür',
    (select count(*) >= 7 from pdks.calisan) and (select count(*) >= 3 from pdks.departman));
select test.dogrula('İSG uzmanı gün kaydı, izin, ayar ve diğer kullanıcıları göremez',
    (select count(*) from pdks.gun_kaydi) = 0 and (select count(*) from pdks.izin) = 0
    and (select count(*) from pdks.ayar) = 0 and (select count(*) from pdks.kullanici) = 1);

-- 3) Admin karar veremez -------------------------------------------------------------------
select test.oturum('or_admin@ornek.test');
select test.hata('admin gün kaydı düzeltemez', 'yetkiniz yok',
    format($$select pdks.kayit_duzelt(%s, 'durum', 'devamsiz', 'Admin denemesi')$$, (select id from pdks.calisan limit 1)));
select test.hata('admin devamsızlık kararı veremez', 'yetkiniz yok', $$select pdks.soru_ik_karari(1, true, 'Admin denemesi')$$);
select test.hata('admin itiraza karar veremez', 'yetkiniz yok', $$select pdks.itiraz_karar(1, false, 'Admin denemesi')$$);
select test.hata('admin izin giremez', 'yetkiniz yok',
    $$select pdks.izin_gir(1, 'yillik', '2026-10-01', '2026-10-01')$$);
select test.hata('admin fazla mesaiye karar veremez', 'yetkiniz yok', $$select pdks.fazla_mesai_karar(1, true)$$);
select test.hata('admin onaysız fazla mesaiye karar veremez', 'yetkiniz yok',
    $$select pdks.fazla_mesai_inceleme_karar(1, true)$$);
select test.hata('admin ayı kilitleyemez', 'yetkiniz yok', $$select pdks.ay_kilitle(2026::smallint, 10::smallint)$$);
select test.hata('admin amir sorusunu cevaplayamaz', 'yetkiniz yok', $$select pdks.soru_cevapla(1, 'gelmedi')$$);
select test.hata('admin gece işini tetikleyemez', 'yetkiniz yok', $$select pdks.gece_isi_tetikle('2026-10-05')$$);

-- 4) Admin: kullanıcı ve ayar yönetimi ------------------------------------------------------
select test.dogrula('admin yeni kullanıcı tanımlar',
    pdks.kullanici_ekle('OR_Yeni@Ornek.test', 'amir', test.c('ORN1'), test.k('or_amir@ornek.test')) > 0);
reset role;
select test.dogrula('yeni kullanıcı: e-posta küçük harfe çevrildi, rol ve üst amir yazıldı',
    (select rol = 'amir' and ust_amir_id = test.k('or_amir@ornek.test') and aktif and auth_kullanici_id is null
     from pdks.kullanici where eposta = 'or_yeni@ornek.test'));
set local role authenticated;
select test.oturum('or_admin@ornek.test');
select test.hata('aynı e-posta ikinci kez kullanılamaz', 'başka bir kullanıcıda',
    format($$select pdks.kullanici_ekle('or_yeni@ornek.test', 'amir', %s)$$, test.c('OR01')));
select test.hata('hesabı olan çalışana ikinci hesap açılamaz', 'zaten bir kullanıcı hesabı',
    format($$select pdks.kullanici_ekle('or_ikinci@ornek.test', 'amir', %s)$$, test.c('ORN1')));
select test.hata('admin kendine hesap açamaz', 'Görevler ayrılığı',
    format($$select pdks.kullanici_ekle('or_kendim@ornek.test', 'ik', %s)$$, test.c('ORA1')));
select test.hata('geçersiz e-posta reddedilir', 'Geçerli bir e-posta',
    format($$select pdks.kullanici_ekle('hatali-eposta', 'amir', %s)$$, test.c('OR01')));
select test.hata('geçersiz rol reddedilir', 'Geçersiz rol',
    format($$select pdks.kullanici_ekle('or_hatali@ornek.test', 'mudur', %s)$$, test.c('OR01')));

select pdks.kullanici_guncelle(test.k('or_yeni@ornek.test'), p_rol => 'isg', p_aktif => false);
reset role;
select test.dogrula('admin başka kullanıcının rolünü ve aktifliğini değiştirir',
    (select rol = 'isg' and not aktif and ust_amir_id = test.k('or_amir@ornek.test')
     from pdks.kullanici where eposta = 'or_yeni@ornek.test'));
-- Auth hesabı sonradan açılırsa güncellemede bağlanır
insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000a9', 'or_yeni@ornek.test');
set local role authenticated;
select test.oturum('or_admin@ornek.test');
select pdks.kullanici_guncelle(test.k('or_yeni@ornek.test'), p_aktif => true);
reset role;
select test.dogrula('aynı e-postalı Auth hesabı kullanıcıya bağlandı',
    (select auth_kullanici_id = '00000000-0000-0000-0000-0000000000a9' and aktif
     from pdks.kullanici where eposta = 'or_yeni@ornek.test'));
set local role authenticated;
select test.oturum('or_admin@ornek.test');
select test.hata('admin kendi hesabını değiştiremez', 'Görevler ayrılığı',
    format($$select pdks.kullanici_guncelle(%s, p_rol => 'ik')$$, test.k('or_admin@ornek.test')));
select test.hata('kullanıcı kendi üst amiri olamaz', 'kendisinin üst amiri',
    format($$select pdks.kullanici_guncelle(%s, p_ust_amir_id => %s)$$,
           test.k('or_amir@ornek.test'), test.k('or_amir@ornek.test')));

select pdks.ayar_guncelle('gec_kalma_tolerans_dk', '7');
reset role;
select test.dogrula('admin ayarı değiştirir; geçmişe eski / yeni değer ve değiştiren yazılır',
    pdks.ayar_al('gec_kalma_tolerans_dk') = 7
    and exists (select 1 from pdks.ayar_gecmisi where anahtar = 'gec_kalma_tolerans_dk' and eski_deger = 10
                and yeni_deger = 7 and guncelleyen_id = test.k('or_admin@ornek.test')));
set local role authenticated;
select test.oturum('or_admin@ornek.test');
select test.hata('bilinmeyen ayar değiştirilemez', 'Ayar bulunamadı', $$select pdks.ayar_guncelle('yok_boyle_ayar', '1')$$);
select test.hata('eksi ayar değeri girilemez', 'değer 0 ile 60 arasında olmalı', $$select pdks.ayar_guncelle('gec_kalma_tolerans_dk', '-1')$$);

-- 5) Kullanıcı ve ayar yönetimi yalnızca admin'de ----------------------------------------------
select test.oturum('or_ik@ornek.test');
select test.hata('İK kullanıcı tanımlayamaz', 'yetkiniz yok',
    format($$select pdks.kullanici_ekle('or_x@ornek.test', 'amir', %s)$$, test.c('OR01')));
select test.hata('İK ayar değiştiremez', 'yetkiniz yok', $$select pdks.ayar_guncelle('gec_kalma_tolerans_dk', '20')$$);
select test.oturum('or_isg@ornek.test');
select test.hata('İSG uzmanı kullanıcı güncelleyemez', 'yetkiniz yok',
    format($$select pdks.kullanici_guncelle(%s, p_aktif => false)$$, test.k('or_amir@ornek.test')));
reset role;
select test.dogrula('iç yardımcı uygulamaya kapalı, ekran fonksiyonları açık',
    not has_function_privilege('authenticated', 'pdks.auth_hesabi_bagla(bigint)', 'execute')
    and has_function_privilege('authenticated', 'pdks.ayar_guncelle(text, text)', 'execute')
    and not has_function_privilege('anon', 'pdks.kullanici_ekle(text, text, bigint, bigint)', 'execute'));

do $$ begin raise notice 'ORGANİZASYON VE ROL TESTLERİ GEÇTİ'; end $$;
rollback;
