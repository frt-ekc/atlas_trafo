-- =====================================================================
-- Puantaj kuralları testleri (20261123010000_puantaj_kurallari.sql)
--   tolerans ve yuvarlama · onaysız fazla mesai havuzu · FM50 / FM100 ·
--   gece çalışması · saatlik izin · puantaj kodları ve kalemleri · fark
-- Testin kendi sahte verisi (Ekim 2026) kullanılır; örnek veri yüklü olsun
-- olmasın çalışır. Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/puantaj_kurallari_testi.sql
-- =====================================================================
\pset tuples_only on
\pset format unaligned
begin;
-- Bu test Kasım / Aralık 2026'yı kilitler; ay bitmeden kilit olmadığı için (T-89) bugün 15.01.2027 kabul edilir
set local pdks.test_bugun = '2027-01-15';
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
create function test.gk(p_sicil text, p_gun date) returns pdks.gun_kaydi language sql security definer as $$
    select * from pdks.gun_kaydi where calisan_id = test.c(p_sicil) and is_gunu = p_gun $$;
create function test.hv(p_sicil text, p_gun date) returns pdks.fazla_mesai_inceleme language sql security definer as $$
    select * from pdks.fazla_mesai_inceleme where calisan_id = test.c(p_sicil) and is_gunu = p_gun $$;
create function test.ps(p_sicil text, p_yil int, p_ay int, p_tur text) returns pdks.puantaj_satiri
language sql security definer as $$
    select s.* from pdks.puantaj_satiri s join pdks.donem d on d.id = s.donem_id
    where s.calisan_id = test.c(p_sicil) and d.yil = p_yil and d.ay = p_ay and s.satir_turu = p_tur $$;
create function test.kalem(p_sicil text, p_yil int, p_ay int, p_tur text, p_kod text) returns pdks.puantaj_kalemi
language sql security definer as $$
    select k.* from pdks.puantaj_kalemi k where k.puantaj_satiri_id = (test.ps(p_sicil, p_yil, p_ay, p_tur)).id
      and k.kod = p_kod $$;
create function test.ts(p text) returns timestamptz language sql immutable as $$
    select (p::timestamp) at time zone 'Europe/Istanbul' $$;
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
insert into pdks.resmi_tatil (tarih, ad, yarim_gun) values
    ('2026-10-28', 'Cumhuriyet Bayramı arifesi', true),
    ('2026-10-29', 'Cumhuriyet Bayramı', false)
on conflict (tarih) do nothing;

insert into pdks.departman (ad) values ('PK Üretim'), ('PK İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = d), '2025-01-01'
from (values ('PK01', 'PK Üretim'), ('PK02', 'PK Üretim'), ('PK03', 'PK Üretim'), ('PK04', 'PK Üretim'),
             ('PK05', 'PK Üretim'), ('PK06', 'PK Üretim'), ('PK07', 'PK Üretim'), ('PK08', 'PK Üretim'),
             ('PKA1', 'PK Üretim'), ('PKI1', 'PK İdari'), ('PKI2', 'PK İdari')) v(s, d);
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('PK Amir', 'pk_amir@ornek.test', 'amir', test.c('PKA1'), '00000000-0000-0000-0000-0000000000e1'),
    ('PK İK 1', 'pk_ik1@ornek.test',  'ik',   test.c('PKI1'), '00000000-0000-0000-0000-0000000000e2'),
    ('PK İK 2', 'pk_ik2@ornek.test',  'ik',   test.c('PKI2'), '00000000-0000-0000-0000-0000000000e3');
update pdks.departman set amir_id = test.k('pk_amir@ornek.test') where ad = 'PK Üretim';
insert into pdks.kart (kart_no, calisan_id)
select 'PK-' || s, test.c(s) from unnest(array['PK01', 'PK02', 'PK03', 'PK04', 'PK05', 'PK06', 'PK07', 'PK08', 'PKI2']) s;
insert into pdks.okuyucu (kod, ad, sistem) values ('PK-PDKS', 'PK PDKS', 'pdks');

-- 20:00–06:00 süren test vardiyası (gece çalışması sınırı için)
insert into pdks.vardiya_tanim (kod, ad, baslangic, bitis) values ('PK_GECE', 'PK gece (20-06)', '20:00', '06:00');

-- Yazılı fazla mesai onayı: PK05 dışında herkesin var
insert into pdks.fazla_mesai_onayi (calisan_id, yil, imza_tarihi, belge_no, giren_id)
select test.c(s), 2026, '2026-01-02', 'PK-FMO-' || s, test.k('pk_ik1@ornek.test')
from unnest(array['PK01', 'PK02', 'PK03', 'PK04', 'PK06', 'PK08']) s;
insert into pdks.fazla_mesai_onayi (calisan_id, yil, imza_tarihi, belge_no, giren_id)
values (test.c('PKI2'), 2026, '2026-01-02', 'PK-FMO-PKI2', test.k('pk_ik1@ornek.test'));

-- Vardiya planları
insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id, giren_id)
select test.c(s), t::date, (select id from pdks.vardiya_tanim where kod = v), test.k('pk_ik1@ornek.test')
from (values ('PK01', '2026-10-05', 'GUNDUZ'), ('PK01', '2026-10-06', 'GUNDUZ'), ('PK01', '2026-10-07', 'GUNDUZ'),
             ('PK01', '2026-10-08', 'GUNDUZ'), ('PK01', '2026-10-09', 'GUNDUZ'),
             ('PK02', '2026-10-05', 'GUNDUZ'), ('PK02', '2026-10-07', 'GUNDUZ'),
             ('PK03', '2026-10-06', 'GUNDUZ'), ('PK03', '2026-10-08', 'GUNDUZ'),
             ('PK04', '2026-10-03', 'GUNDUZ'), ('PK04', '2026-10-04', 'GUNDUZ'),
             ('PK05', '2026-10-04', 'GUNDUZ'),
             ('PK06', '2026-10-28', 'GUNDUZ'), ('PK06', '2026-10-29', 'GUNDUZ'),
             ('PK07', '2026-10-12', 'GUNDUZ'), ('PK07', '2026-10-13', 'GUNDUZ'), ('PK07', '2026-10-14', 'GUNDUZ'),
             ('PK07', '2026-10-15', 'GUNDUZ'), ('PK07', '2026-10-16', 'GUNDUZ'), ('PK07', '2026-10-29', 'GUNDUZ'),
             ('PK08', '2026-10-05', 'PK_GECE'),
             ('PKI2', '2026-10-05', 'GUNDUZ')) x(s, t, v);

-- PK07 izinleri: yıllık, mazeret, ücretsiz, diğer, rapor
insert into pdks.izin (calisan_id, tur, baslangic, bitis, giren_id)
select test.c('PK07'), t, d::date, d::date, test.k('pk_ik1@ornek.test')
from (values ('yillik', '2026-10-12'), ('mazeret', '2026-10-13'), ('ucretsiz', '2026-10-14'),
             ('diger', '2026-10-15'), ('rapor', '2026-10-16')) x(t, d);

-- PK03, 6 Ekim: onaylı 60 dk fazla mesai planı
insert into pdks.fazla_mesai_plani (calisan_id, is_gunu, planli_dk, gerekce, talep_eden_id)
values (test.c('PK03'), '2026-10-06', 60, 'Sipariş yetişmeli', test.k('pk_amir@ornek.test'));
update pdks.fazla_mesai_plani set durum = 'onaylandi', karar_veren_id = test.k('pk_ik1@ornek.test')
where calisan_id = test.c('PK03') and is_gunu = '2026-10-06';

-- Gece işinden önce girilen saatlik izinler (İK)
set local role authenticated;
select test.oturum('pk_ik1@ornek.test');
select pdks.saatlik_izin_gir(test.c('PK02'), '2026-10-07', test.ts('2026-10-07 15:00'), test.ts('2026-10-07 17:00'), 'mazeret');
select pdks.saatlik_izin_gir(test.c('PK03'), '2026-10-08', test.ts('2026-10-08 08:00'), test.ts('2026-10-08 10:00'), 'vizite');
reset role;

-- PDKS dosyaları ve okutmalar
insert into pdks.aktarim (kaynak, dosya_adi, dosya_ozeti, veri_tarihi)
select 'pdks', 'pk_' || g::date || '.csv', 'pk-pdks-' || g::date, g::date
from generate_series(date '2026-10-01', date '2026-10-31', interval '1 day') g;

insert into pdks.ham_okutma (aktarim_id, okuyucu_id, kart_no, okutma_zamani, yon)
select (select id from pdks.aktarim where dosya_ozeti = 'pk-pdks-' || (z::timestamp)::date),
       (select id from pdks.okuyucu where kod = 'PK-PDKS'), 'PK-' || s, test.ts(z), y
from (values
    ('PK01', '2026-10-05 07:58', 'giris'), ('PK01', '2026-10-05 17:01', 'cikis'),
    ('PK01', '2026-10-06 08:12', 'giris'), ('PK01', '2026-10-06 17:00', 'cikis'),
    ('PK01', '2026-10-07 07:55', 'giris'), ('PK01', '2026-10-07 16:56', 'cikis'),
    ('PK01', '2026-10-08 07:57', 'giris'), ('PK01', '2026-10-08 16:54', 'cikis'),
    ('PK01', '2026-10-09 07:59', 'giris'), ('PK01', '2026-10-09 17:00', 'cikis'),
    ('PK02', '2026-10-05 07:55', 'giris'), ('PK02', '2026-10-05 18:30', 'cikis'),
    ('PK02', '2026-10-07 07:56', 'giris'), ('PK02', '2026-10-07 15:00', 'cikis'),
    ('PK03', '2026-10-06 07:55', 'giris'), ('PK03', '2026-10-06 18:30', 'cikis'),
    ('PK03', '2026-10-08 10:20', 'giris'), ('PK03', '2026-10-08 17:00', 'cikis'),
    ('PK04', '2026-10-03 07:55', 'giris'), ('PK04', '2026-10-03 17:02', 'cikis'),
    ('PK04', '2026-10-04 07:55', 'giris'), ('PK04', '2026-10-04 17:02', 'cikis'),
    ('PK05', '2026-10-04 07:55', 'giris'), ('PK05', '2026-10-04 17:02', 'cikis'),
    ('PK06', '2026-10-28 07:55', 'giris'), ('PK06', '2026-10-28 17:02', 'cikis'),
    ('PK06', '2026-10-29 07:55', 'giris'), ('PK06', '2026-10-29 17:02', 'cikis'),
    ('PK08', '2026-10-05 19:55', 'giris'), ('PK08', '2026-10-06 06:03', 'cikis'),
    ('PKI2', '2026-10-05 07:55', 'giris'), ('PKI2', '2026-10-05 18:00', 'cikis')) v(s, z, y);

do $$
declare d date;
begin
    for d in select g::date from generate_series(date '2026-10-03', date '2026-10-30', interval '1 day') g loop
        perform pdks.gece_isi_calistir(d);
    end loop;
end $$;

select test.dogrula('hazırlık: gece işi Ekim günlerini hatasız işledi',
    not exists (select 1 from pdks.gece_isi where islenen_gun between '2026-10-03' and '2026-10-30' and durum <> 'basarili'));

-- 1) Ayarlar ---------------------------------------------------------------
select test.dogrula('geç kalma toleransı 10, erken çıkış 5 dk; yuvarlama kapalı; Cumartesi normal gün; gece sınırı 450',
    pdks.ayar_al('gec_kalma_tolerans_dk') = 10 and pdks.ayar_al('erken_cikis_tolerans_dk') = 5
    and pdks.ayar_al('tolerans_yuvarlama_dk') = 0 and pdks.ayar_al('cumartesi_hafta_sonu') = 0
    and pdks.ayar_al('gece_calisma_sinir_dk') = 450);
select test.dogrula('tolerans değişikliği ayar geçmişine yazıldı (5 → 10)',
    exists (select 1 from pdks.ayar_gecmisi where anahtar = 'gec_kalma_tolerans_dk' and eski_deger = 5 and yeni_deger = 10));

-- 2) Tolerans ve yuvarlama ---------------------------------------------------
select test.dogrula('vardiyadan önce giriş: geç kalma yok, çalışma 480 dk (540 − 60 dk mola)',
    (select gec_kalma_dk = 0 and calisma_dk = 480 from test.gk('PK01', '2026-10-05')));
select test.dogrula('9 dk geç kalma tolerans (10 dk) içinde: geç sayılmaz',
    (select gec_kalma_dk = 0 and calisma_dk = 471 from pdks.gun_hesabi(test.c('PK01'), '2026-10-06',
        test.ts('2026-10-06 08:00'), test.ts('2026-10-06 17:00'), test.ts('2026-10-06 08:09'), test.ts('2026-10-06 17:00'))));
select test.dogrula('12 dk geç kalma tam dakikasıyla sayılır (tolerans 10)',
    (select gec_kalma_dk = 12 and calisma_dk = 468 from test.gk('PK01', '2026-10-06')));
select test.dogrula('4 dk erken çıkış sayılmaz, 6 dk sayılır (tolerans 5)',
    (select erken_cikis_dk = 0 from test.gk('PK01', '2026-10-07'))
    and (select erken_cikis_dk = 6 and calisma_dk = 474 from test.gk('PK01', '2026-10-08')));
update pdks.ayar set deger = 15 where anahtar = 'tolerans_yuvarlama_dk';
select test.dogrula('yuvarlama 15 dk: 12 dk geç → 15, 9 dk geç → 0, 6 dk erken → 15',
    (select gec_kalma_dk = 15 from pdks.gun_hesabi(test.c('PK01'), '2026-10-06', test.ts('2026-10-06 08:00'),
        test.ts('2026-10-06 17:00'), test.ts('2026-10-06 08:12'), test.ts('2026-10-06 17:00')))
    and (select gec_kalma_dk = 0 from pdks.gun_hesabi(test.c('PK01'), '2026-10-06', test.ts('2026-10-06 08:00'),
        test.ts('2026-10-06 17:00'), test.ts('2026-10-06 08:09'), test.ts('2026-10-06 17:00')))
    and (select erken_cikis_dk = 15 from pdks.gun_hesabi(test.c('PK01'), '2026-10-08', test.ts('2026-10-08 08:00'),
        test.ts('2026-10-08 17:00'), test.ts('2026-10-08 07:57'), test.ts('2026-10-08 16:54'))));
update pdks.ayar set deger = 0 where anahtar = 'tolerans_yuvarlama_dk';

-- 3) Onaysız fazla mesai havuzu ---------------------------------------------
select test.dogrula('plansız 90 dk puantaja girmedi, havuzda İK kararı bekliyor',
    (select fazla_mesai_dk = 0 and fm50_dk = 0 and calisma_dk = 480 from test.gk('PK02', '2026-10-05'))
    and (select durum = 'inceleme_bekliyor' and tur = 'vardiya_sonrasi' and dakika = 90
         from test.hv('PK02', '2026-10-05')));
select test.dogrula('plansız çalışma uyarısı da yazıldı',
    exists (select 1 from pdks.uyari where tur = 'fm_plansiz_calisma' and calisan_id = test.c('PK02')));
select test.dogrula('onaylı plan 60 dk FM50 oldu, planı aşan 30 dk havuza düştü',
    (select fm50_dk = 60 and fazla_mesai_dk = 60 and calisma_dk = 540 from test.gk('PK03', '2026-10-06'))
    and (select dakika = 30 from test.hv('PK03', '2026-10-06')));
select test.dogrula('eşik altındaki (1–2 dk) geç çıkış havuza düşmez',
    (select (test.hv('PK01', '2026-10-05')).id is null) and (select (test.hv('PK04', '2026-10-04')).id is null));

set local role authenticated;
select test.oturum('pk_amir@ornek.test');
select test.dogrula('amir kendi departmanının havuz kayıtlarını görür (İK''nınkini görmez)',
    (select count(*) from pdks.fazla_mesai_inceleme) = 3);
select test.hata('amir havuza karar veremez', 'yetkiniz yok',
    format('select pdks.fazla_mesai_inceleme_karar(%s, true)', (test.hv('PK02', '2026-10-05')).id));
select test.oturum('pk_ik2@ornek.test');
select test.hata('İK kendi fazla mesaisine karar veremez', 'Görevler ayrılığı',
    format('select pdks.fazla_mesai_inceleme_karar(%s, true)', (test.hv('PKI2', '2026-10-05')).id));
select test.oturum('pk_ik1@ornek.test');
select test.hata('ret gerekçesiz olmaz', 'Ret gerekçesi',
    format('select pdks.fazla_mesai_inceleme_karar(%s, false)', (test.hv('PK03', '2026-10-06')).id));
select pdks.fazla_mesai_inceleme_karar((test.hv('PK03', '2026-10-06')).id, false, 'Planı aşan kalış onaylanmadı');
reset role;
update pdks.ayar set deger = 50 where anahtar = 'fm_yillik_sinir_dk';
set local role authenticated;
select test.oturum('pk_ik1@ornek.test');
select pdks.fazla_mesai_inceleme_karar((test.hv('PK02', '2026-10-05')).id, true);
reset role;
update pdks.ayar set deger = 16200 where anahtar = 'fm_yillik_sinir_dk';

select test.dogrula('İK onayı puantaja girdi: FM50 90 dk, çalışma 570 dk (630 − 60 dk mola)',
    (select fm50_dk = 90 and fazla_mesai_dk = 90 and calisma_dk = 570 from test.gk('PK02', '2026-10-05'))
    and (select durum = 'onaylandi' and fm50_etki_dk = 90 and calisma_etki_dk = 90 and not fark_satiri
         from test.hv('PK02', '2026-10-05')));
select test.dogrula('onay sınırı aşsa da engellenmedi; yıllık sınır uyarısı yazıldı',
    exists (select 1 from pdks.uyari where tur = 'fm_yillik_sinir_asildi' and calisan_id = test.c('PK02')));
select test.dogrula('ret kaydı gerekçesiyle tutuldu; plan dışı süre puantaja girmedi',
    (select durum = 'reddedildi' and karar_aciklama is not null from test.hv('PK03', '2026-10-06'))
    and (select fm50_dk = 60 from test.gk('PK03', '2026-10-06')));
select test.hata('karara bağlanmış havuz kaydı değiştirilemez', 'değiştirilemez',
    format('update pdks.fazla_mesai_inceleme set dakika = 10 where id = %s', (test.hv('PK02', '2026-10-05')).id));
select test.hata('havuz kaydı silinemez', 'silinemez',
    format('delete from pdks.fazla_mesai_inceleme where id = %s', (test.hv('PK02', '2026-10-05')).id));
select test.hata('havuz onayı olmadan fazla mesai yazılamaz', 'izin verilen',
    format('update pdks.gun_kaydi set fazla_mesai_dk = 120, fm50_dk = 120 where id = %s', (test.gk('PK02', '2026-10-05')).id));

-- 4) FM50 / FM100 --------------------------------------------------------------
select test.dogrula('Cumartesi normal iş günü: NÇ, fazla mesai yok',
    (select fm100_dk = 0 and fm50_dk = 0 and calisma_dk = 480 from test.gk('PK04', '2026-10-03')));
select test.dogrula('Pazar çalışması (yazılı onay var): tüm net çalışma FM100',
    (select fm100_dk = 480 and fm50_dk = 0 and fazla_mesai_dk = 480 and calisma_dk = 480 from test.gk('PK04', '2026-10-04')));
select test.dogrula('Pazar çalışması (yazılı onay yok): puantaja girmedi, havuzda',
    (select fm100_dk = 0 and calisma_dk = 0 from test.gk('PK05', '2026-10-04'))
    and (select tur = 'tatil_calismasi' and dakika = 542 and durum = 'inceleme_bekliyor' from test.hv('PK05', '2026-10-04')));
select test.dogrula('resmi tatilde çalışılan gün "tatil" değil, FM100',
    (select durum = 'tamam' and fm100_dk = 480 from test.gk('PK06', '2026-10-29')));
select test.dogrula('arife (yarım gün tatil) normal iş günü sayılır',
    (select fm100_dk = 0 and calisma_dk = 480 from test.gk('PK06', '2026-10-28')));
select test.dogrula('resmi tatilde okutması olmayan gün "tatil"',
    (select durum = 'tatil' and hesap_tamam from test.gk('PK07', '2026-10-29')));
update pdks.ayar set deger = 1 where anahtar = 'cumartesi_hafta_sonu';
select test.dogrula('cumartesi_hafta_sonu = 1 ise Cumartesi çalışması FM100',
    (select fm100_dk = 480 from pdks.gun_hesabi(test.c('PK04'), '2026-10-03', test.ts('2026-10-03 08:00'),
        test.ts('2026-10-03 17:00'), test.ts('2026-10-03 07:55'), test.ts('2026-10-03 17:02'))));
update pdks.ayar set deger = 0 where anahtar = 'cumartesi_hafta_sonu';

set local role authenticated;
select test.oturum('pk_ik1@ornek.test');
select pdks.fazla_mesai_inceleme_karar((test.hv('PK05', '2026-10-04')).id, true, 'Bakım işi için çağrıldı');
reset role;
select test.dogrula('İK onayıyla yazılı onayı olmayanın Pazar çalışması FM100 oldu (542 − 60 dk mola)',
    (select fm100_dk = 482 and calisma_dk = 482 from test.gk('PK05', '2026-10-04')));

-- 5) Gece çalışması --------------------------------------------------------------
select test.dogrula('20:00–06:00 vardiyası: gece çalışması 540 dk (600 − 60 dk mola)',
    (select gece_calisma_dk = 540 and calisma_dk = 540 from test.gk('PK08', '2026-10-05')));
select test.dogrula('gündüz vardiyasında gece çalışması yok',
    (select gece_calisma_dk = 0 from test.gk('PK01', '2026-10-05')));
select test.dogrula('7,5 saati aşan gece çalışması İK''ya uyarı',
    exists (select 1 from pdks.uyari where tur = 'gece_calisma_siniri_asildi' and calisan_id = test.c('PK08')));

-- 6) Saatlik izin ----------------------------------------------------------------
select test.dogrula('izinle erken çıkış (15:00) erken çıkış sayılmaz; izin süresi ayrı tutulur',
    (select erken_cikis_dk = 0 and calisma_dk = 390 and saatlik_izin_dk = 120 from test.gk('PK02', '2026-10-07')));
select test.dogrula('sabah izni: izin bitişinden (10:00) sonraki 20 dk geç kalma',
    (select gec_kalma_dk = 20 and calisma_dk = 370 and saatlik_izin_dk = 120 from test.gk('PK03', '2026-10-08')));

select test.dogrula('hazırlık: PK01 9 Ekim izinsiz hesaplandı (480 dk)',
    (select calisma_dk = 480 and saatlik_izin_dk = 0 from test.gk('PK01', '2026-10-09')));
set local role authenticated;
select test.oturum('pk_ik1@ornek.test');
select pdks.saatlik_izin_gir(test.c('PK01'), '2026-10-09', test.ts('2026-10-09 10:00'), test.ts('2026-10-09 12:00'),
                             'vizite', 'Hastane vizitesi');
select test.dogrula('hesaplanmış güne girilen vizite günü yeniden hesaplattı (gün içi 2 saat düşüldü)',
    (select calisma_dk = 390 and saatlik_izin_dk = 120 and gec_kalma_dk = 0 and erken_cikis_dk = 0
     from test.gk('PK01', '2026-10-09')));
select test.hata('çakışan saatlik izin girilemez', 'başka bir saatlik izin',
    format('select pdks.saatlik_izin_gir(%s, ''2026-10-09'', %L, %L, ''mazeret'')',
           test.c('PK01'), test.ts('2026-10-09 11:00'), test.ts('2026-10-09 13:00')));
select test.hata('İK kendi saatlik iznini giremez', 'Görevler ayrılığı',
    format('select pdks.saatlik_izin_gir(%s, ''2026-10-20'', %L, %L, ''mazeret'')',
           test.c('PKI1'), test.ts('2026-10-20 10:00'), test.ts('2026-10-20 11:00')));
select test.hata('iş günüyle uyuşmayan saat reddedilir', 'uyuşmuyor',
    format('select pdks.saatlik_izin_gir(%s, ''2026-10-20'', %L, %L, ''mazeret'')',
           test.c('PK01'), test.ts('2026-10-25 10:00'), test.ts('2026-10-25 11:00')));
select test.oturum('pk_amir@ornek.test');
select test.hata('amir saatlik izin giremez', 'yetkiniz yok',
    format('select pdks.saatlik_izin_gir(%s, ''2026-10-20'', %L, %L, ''mazeret'')',
           test.c('PK01'), test.ts('2026-10-20 10:00'), test.ts('2026-10-20 11:00')));
select test.dogrula('amir saatlik izin tablosunu (türü) göremez',
    (select count(*) from pdks.saatlik_izin) = 0);
select test.dogrula('amir saatlik izinleri türü gizli olarak görür',
    (select count(*) = 3 and bool_and(tur = 'saatlik_izin') from pdks.v_saatlik_izin_amir));
reset role;
select test.hata('saatlik izin silinemez', 'değiştirilemez',
    format('delete from pdks.saatlik_izin where calisan_id = %s', test.c('PK01')));

-- 7) Gün gün puantaj kodları -------------------------------------------------------
create temp table kodlar as select * from pdks.gun_kodlari_hesapla(2026, 10);
create function test.kod(p_sicil text, p_gun date) returns text language sql as $$
    select string_agg(kod || ':' || gun || ':' || dakika, ' ' order by kod)
    from kodlar where calisan_id = test.c(p_sicil) and tarih = p_gun $$;
select test.dogrula('normal gün NÇ; onaylı plan dışı çalışma FM50',
    test.kod('PK01', '2026-10-05') = 'NÇ:1:480' and test.kod('PK02', '2026-10-05') = 'FM50:0:90 NÇ:1:480');
select test.dogrula('Pazar ve resmi tatil çalışması FM100; çalışılmayan resmi tatil RT',
    test.kod('PK04', '2026-10-04') = 'FM100:1:480' and test.kod('PK06', '2026-10-29') = 'FM100:1:480'
    and test.kod('PK07', '2026-10-29') = 'RT:1:0');
select test.dogrula('izin kodları: Yİ, MZR, ÜCSZ, Dİ, RPR',
    test.kod('PK07', '2026-10-12') = 'Yİ:1:0' and test.kod('PK07', '2026-10-13') = 'MZR:1:0'
    and test.kod('PK07', '2026-10-14') = 'ÜCSZ:1:0' and test.kod('PK07', '2026-10-15') = 'Dİ:1:0'
    and test.kod('PK07', '2026-10-16') = 'RPR:1:0');
select test.dogrula('planı olmayan gün HT',
    test.kod('PK01', '2026-10-10') = 'HT:1:0' and test.kod('PK07', '2026-10-20') = 'HT:1:0');
select test.dogrula('devamsız gün DVMSZ; karar bekleyen gün kod almaz',
    (select string_agg(kod, ',') = 'DVMSZ' from pdks.gun_kod_satirlari(test.c('PK01'), '2026-10-20', 'devamsiz', 0, 0, 0))
    and not exists (select 1 from pdks.gun_kod_satirlari(test.c('PK01'), '2026-10-20', 'soru_bekliyor', 0, 0, 0)));
select test.dogrula('her çalışanın her günü tam bir gün kodu alır (FM50 hariç)',
    not exists (select calisan_id, tarih from kodlar where kod <> 'FM50'
                group by 1, 2 having sum(gun) <> 1)
    and (select count(distinct tarih) = 31 from kodlar where calisan_id = test.c('PK01')));

set local role authenticated;
select test.oturum('pk_amir@ornek.test');
select test.hata('amir gün kodlarını (izin türü içerir) göremez', 'yetkiniz yok',
    $$select * from pdks.gun_kodlari(2026, 10)$$);
select test.oturum('pk_ik1@ornek.test');
select test.dogrula('İK gün kodlarını görür', (select count(*) > 0 from pdks.gun_kodlari(2026, 10)));

-- 8) Ay kilidi ve puantaj kalemleri -------------------------------------------------
select test.hata('İK kararı bekleyen havuz kaydı varken ay kilitlenmez', 'onaysız fazla mesai',
    $$select pdks.ay_kilitle(2026::smallint, 10::smallint)$$);
select pdks.ay_kilitle(2026::smallint, 10::smallint, true);
reset role;

select test.dogrula('PK01 Ekim kalemleri: NÇ 5 gün / 2288 dk, HT 25 gün, RT 1 gün',
    (select gun = 5 and dakika = 2288 from test.kalem('PK01', 2026, 10, 'normal', 'NÇ'))
    and (select gun = 25 from test.kalem('PK01', 2026, 10, 'normal', 'HT'))
    and (select gun = 1 from test.kalem('PK01', 2026, 10, 'normal', 'RT')));
select test.dogrula('puantaj satırında FM50 / FM100 / gece / saatlik izin sütunları',
    (select fm50_dk = 90 and fm100_dk = 0 and fazla_mesai_dk = 90 from test.ps('PK02', 2026, 10, 'normal'))
    and (select fm100_dk = 480 and fm50_dk = 0 from test.ps('PK04', 2026, 10, 'normal'))
    and (select gece_calisma_dk = 540 from test.ps('PK08', 2026, 10, 'normal'))
    and (select saatlik_izin_dk = 120 from test.ps('PK01', 2026, 10, 'normal')));
select test.dogrula('her normal satırda NÇ + FM50 + FM100 kalemleri çalışma dakikasına eşit',
    not exists (
        select 1 from pdks.puantaj_satiri s join pdks.donem d on d.id = s.donem_id
        where d.yil = 2026 and d.ay = 10 and s.satir_turu = 'normal'
          and s.calisma_dk <> coalesce((select sum(k.dakika) from pdks.puantaj_kalemi k
                                         where k.puantaj_satiri_id = s.id and k.kod in ('NÇ', 'FM50', 'FM100')), 0)));
select test.dogrula('kalemlerde FM50 / FM100 satırdaki sütunlarla aynı',
    not exists (
        select 1 from pdks.puantaj_satiri s join pdks.donem d on d.id = s.donem_id
        where d.yil = 2026 and d.ay = 10 and s.satir_turu = 'normal'
          and (s.fm50_dk <> coalesce((select dakika from pdks.puantaj_kalemi where puantaj_satiri_id = s.id and kod = 'FM50'), 0)
            or s.fm100_dk <> coalesce((select dakika from pdks.puantaj_kalemi where puantaj_satiri_id = s.id and kod = 'FM100'), 0))));
select test.dogrula('PK07 izin ve tatil kalemleri',
    (select gun = 1 from test.kalem('PK07', 2026, 10, 'normal', 'Yİ'))
    and (select gun = 1 from test.kalem('PK07', 2026, 10, 'normal', 'RPR'))
    and (select gun = 1 from test.kalem('PK07', 2026, 10, 'normal', 'Dİ'))
    and (select gun = 1 from test.kalem('PK07', 2026, 10, 'normal', 'RT')));
select test.hata('puantaj kalemi silinemez', 'değiştirilemez',
    $$delete from pdks.puantaj_kalemi$$);

-- 9) Kilitten sonra: saatlik izin girilemez, düzeltme ve havuz onayı sonraki aya fark ----
set local role authenticated;
select test.oturum('pk_ik1@ornek.test');
select test.hata('kilitli aya saatlik izin girilemez', 'kilitli',
    format('select pdks.saatlik_izin_gir(%s, ''2026-10-20'', %L, %L, ''mazeret'')',
           test.c('PK01'), test.ts('2026-10-20 10:00'), test.ts('2026-10-20 11:00')));
select pdks.kayit_duzelt((test.gk('PK01', '2026-10-06')).id, 'giris_zamani', '2026-10-06 08:00+03',
                         'Kilit sonrası belge geldi: 08:00 girişi');
select pdks.fazla_mesai_inceleme_karar((test.hv('PKI2', '2026-10-05')).id, true, 'Ay sonu sayımı');
reset role;

select test.dogrula('kilitli günün kaydı değişmedi (giriş ve fazla mesai)',
    (select gec_kalma_dk = 12 from test.gk('PK01', '2026-10-06'))
    and (select fazla_mesai_dk = 0 from test.gk('PKI2', '2026-10-05')));
select test.dogrula('kilitli aya ait havuz onayı Kasım''a fark olarak yönlendirildi',
    (select h.fark_satiri and h.fm50_etki_dk = 60 and d.yil = 2026 and d.ay = 11
     from test.hv('PKI2', '2026-10-05') h join pdks.donem d on d.id = h.hedef_donem_id));

-- Örnek veri yüklüyse onun Kasım planları bu testte gece işinden geçmez; ay kilidi (20261201010000)
-- işlenmemiş planlı günü zorla bile kabul etmez. Test yalnızca kendi verisine bakar (ROLLBACK geri alır).
delete from pdks.vardiya_plani where tarih between '2026-11-01' and '2026-11-30';
set local role authenticated;
select test.oturum('pk_ik1@ornek.test');
select pdks.ay_kilitle(2026::smallint, 11::smallint, true);
reset role;

select test.dogrula('Kasım fark satırı (düzeltme): geç kalma −12, çalışma +12, NÇ kalemi +12 dk',
    (select gec_kalma_dk = -12 and calisma_dk = 12 and calisilan_gun = 0 from test.ps('PK01', 2026, 11, 'fark'))
    and (select gun = 0 and dakika = 12 from test.kalem('PK01', 2026, 11, 'fark', 'NÇ')));
select test.dogrula('Kasım fark satırı (havuz onayı): FM50 +60, çalışma +60, FM50 kalemi 60 dk',
    (select fm50_dk = 60 and fazla_mesai_dk = 60 and calisma_dk = 60 from test.ps('PKI2', 2026, 11, 'fark'))
    and (select dakika = 60 from test.kalem('PKI2', 2026, 11, 'fark', 'FM50')));
select test.dogrula('Ekim''in normal satırları değişmedi',
    (select gec_kalma_dk = 12 from test.ps('PK01', 2026, 10, 'normal'))
    and (select fm50_dk = 0 from test.ps('PKI2', 2026, 10, 'normal')));

-- 10) Yetkiler ------------------------------------------------------------------------
select test.dogrula('yeni tablolarda RLS açık; uygulama doğrudan yazamaz',
    (select bool_and(rowsecurity) from pg_tables where schemaname = 'pdks'
      and tablename in ('saatlik_izin', 'fazla_mesai_inceleme', 'puantaj_kalemi'))
    and not has_table_privilege('authenticated', 'pdks.fazla_mesai_inceleme', 'insert')
    and not has_table_privilege('authenticated', 'pdks.puantaj_kalemi', 'insert'));
select test.dogrula('iç hesap fonksiyonları uygulamaya kapalı',
    not has_function_privilege('authenticated', 'pdks.gun_kodlari_hesapla(integer, integer)', 'execute')
    and not has_function_privilege('authenticated', 'pdks.gun_sonrasi_kontroller(bigint)', 'execute')
    and has_function_privilege('authenticated', 'pdks.gun_kodlari(integer, integer)', 'execute'));
set local role authenticated;
select test.oturum('pk_amir@ornek.test');
select test.dogrula('amir puantaj kalemlerini göremez', (select count(*) from pdks.puantaj_kalemi) = 0);
reset role;

do $$ begin raise notice 'PUANTAJ KURALLARI TESTLERİ GEÇTİ'; end $$;
rollback;
