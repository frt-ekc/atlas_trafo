-- =====================================================================
-- Fazla mesai testleri (20261115000500_fazla_mesai.sql)
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK), iz bırakmaz.
-- Çalıştırma: psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/fazla_mesai_testi.sql
-- Hepsi geçerse sonda "FAZLA MESAİ TESTLERİ GEÇTİ" yazar.
--
-- Not: id'leri elle yazmıyoruz (1, 2 ...). ROLLBACK sayaçları geri almaz;
-- test ikinci kez çalışınca id'ler kayar. Bunun yerine sicil/e-posta ile buluruz.
-- =====================================================================
\pset tuples_only on
\pset format unaligned
begin;

create schema test;
create function test.hata_bekle(p_ad text, p_sql text) returns void language plpgsql as $$
begin
    begin
        execute p_sql;
    exception when others then
        raise notice 'GEÇTİ  %  (%)', p_ad, sqlerrm;
        return;
    end;
    raise exception 'KALDI  %: hata bekleniyordu ama komut çalıştı', p_ad;
end $$;
create function test.dogrula(p_ad text, p_kosul boolean) returns void language plpgsql as $$
begin
    if p_kosul is not true then raise exception 'KALDI  %', p_ad; end if;
    raise notice 'GEÇTİ  %', p_ad;
end $$;
-- Kısa yollar: kullanıcı (e-posta), çalışan (sicil), plan (sicil + gün)
create function test.k(p_eposta text) returns bigint language sql as $$
    select id from pdks.kullanici where eposta = p_eposta $$;
create function test.c(p_sicil text) returns bigint language sql as $$
    select id from pdks.calisan where sicil_no = p_sicil $$;
create function test.p(p_sicil text, p_gun date) returns bigint language sql as $$
    select id from pdks.fazla_mesai_plani
    where calisan_id = test.c(p_sicil) and is_gunu = p_gun
    order by id desc limit 1 $$;

set timezone = 'Europe/Istanbul';

-- Örnek veri (sentetik) --------------------------------------------------
insert into pdks.kullanici (ad_soyad, eposta, rol) values
    ('FM Amir', 'fm_amir@ornek.test', 'amir'),
    ('FM İK',   'fm_ik@ornek.test',   'ik');
insert into pdks.departman (ad, amir_id) values ('FM Bobinaj', test.k('fm_amir@ornek.test'));
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Test', 'Çalışan ' || s, (select id from pdks.departman where ad = 'FM Bobinaj'), '2025-01-01'
from unnest(array['FM01', 'FM02']) s;          -- FM01 onaylı, FM02 onaysız

-- Vardiya planı: Aralık günleri gündüz (08-17 = 540 dk), 4 Aralık gece (V3)
insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id)
select test.c(s), g::date, (select id from pdks.vardiya_tanim where kod = 'GUNDUZ')
from unnest(array['FM01', 'FM02']) s,
     unnest(array['2026-12-01', '2026-12-02', '2026-12-03', '2026-12-15', '2026-12-16']::date[]) g;
insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id)
values (test.c('FM01'), '2026-12-04', (select id from pdks.vardiya_tanim where kod = 'V3'));


-- 1) Yıllık yazılı onay ---------------------------------------------------
select test.hata_bekle('amir yazılı onay giremez',
    $$insert into pdks.fazla_mesai_onayi (calisan_id, yil, imza_tarihi, belge_no, giren_id)
      values (test.c('FM01'), 2026, '2026-01-02', 'FMO-2026-001', test.k('fm_amir@ornek.test'))$$);
insert into pdks.fazla_mesai_onayi (calisan_id, yil, imza_tarihi, belge_no, giren_id)
values (test.c('FM01'), 2026, '2026-01-02', 'FMO-2026-001', test.k('fm_ik@ornek.test'));
select test.dogrula('İK yazılı onayı girdi', pdks.fm_onay_gecerli_mi(test.c('FM01'), '2026-12-01'));
select test.hata_bekle('aynı yıl için ikinci onay girilemez',
    $$insert into pdks.fazla_mesai_onayi (calisan_id, yil, imza_tarihi, belge_no, giren_id)
      values (test.c('FM01'), 2026, '2026-02-01', 'FMO-2026-099', test.k('fm_ik@ornek.test'))$$);
select test.hata_bekle('yazılı onay silinemez',
    $$delete from pdks.fazla_mesai_onayi where calisan_id = test.c('FM01')$$);
select test.hata_bekle('onayın belge numarası değiştirilemez',
    $$update pdks.fazla_mesai_onayi set belge_no = 'BAŞKA' where calisan_id = test.c('FM01')$$);

-- 2) Talep aşamasında yasal kontroller ------------------------------------
select test.hata_bekle('yazılı onayı olmayan çalışana fazla mesai istenemez',
    $$insert into pdks.fazla_mesai_plani (calisan_id, is_gunu, planli_dk, gerekce, talep_eden_id)
      values (test.c('FM02'), '2026-12-01', 60, 'Sipariş yetişmeli', test.k('fm_amir@ornek.test'))$$);
select test.hata_bekle('gece vardiyasına fazla mesai planlanamaz (m.69)',
    $$insert into pdks.fazla_mesai_plani (calisan_id, is_gunu, planli_dk, gerekce, talep_eden_id)
      values (test.c('FM01'), '2026-12-04', 60, 'Sipariş yetişmeli', test.k('fm_amir@ornek.test'))$$);
select test.hata_bekle('günlük 11 saat net çalışma aşılamaz (540 + 181 − 60 mola > 660, T-64)',
    $$insert into pdks.fazla_mesai_plani (calisan_id, is_gunu, planli_dk, gerekce, talep_eden_id)
      values (test.c('FM01'), '2026-12-01', 181, 'Sipariş yetişmeli', test.k('fm_amir@ornek.test'))$$);
select test.hata_bekle('vardiya planı olmayan güne fazla mesai istenemez',
    $$insert into pdks.fazla_mesai_plani (calisan_id, is_gunu, planli_dk, gerekce, talep_eden_id)
      values (test.c('FM01'), '2026-12-20', 60, 'Sipariş yetişmeli', test.k('fm_amir@ornek.test'))$$);

-- Yıllık sınırı test etmek için 270 saat yerine geçici olarak 300 dk yapıyoruz
update pdks.ayar set deger = 300, guncelleyen_id = test.k('fm_ik@ornek.test') where anahtar = 'fm_yillik_sinir_dk';

insert into pdks.fazla_mesai_plani (calisan_id, is_gunu, planli_dk, gerekce, talep_eden_id)
select test.c('FM01'), g::date, 120, 'Trafo siparişi yetişmeli', test.k('fm_amir@ornek.test')
from unnest(array['2026-12-01', '2026-12-02', '2026-12-03', '2026-12-15']::date[]) g;
select test.dogrula('4 talep girildi, vardiya planından doldu',
    (select count(*) = 4 and bool_and(durum = 'talep' and vardiya_id is not null)
     from pdks.fazla_mesai_plani where calisan_id = test.c('FM01')));
select test.hata_bekle('aynı güne ikinci etkin plan girilemez',
    $$insert into pdks.fazla_mesai_plani (calisan_id, is_gunu, planli_dk, gerekce, talep_eden_id)
      values (test.c('FM01'), '2026-12-01', 30, 'İkinci talep denemesi', test.k('fm_amir@ornek.test'))$$);

-- 3) Onay İK'da, sınır onay anında korunur --------------------------------
select test.hata_bekle('amir fazla mesaiyi onaylayamaz',
    $$update pdks.fazla_mesai_plani set durum = 'onaylandi', karar_veren_id = test.k('fm_amir@ornek.test')
      where id = test.p('FM01', '2026-12-01')$$);
update pdks.fazla_mesai_plani set durum = 'onaylandi', karar_veren_id = test.k('fm_ik@ornek.test')
where id = test.p('FM01', '2026-12-01');
select test.dogrula('İK onayladı, karar zamanı yazıldı',
    (select durum = 'onaylandi' and karar_zamani is not null from pdks.fazla_mesai_plani
     where id = test.p('FM01', '2026-12-01')));
select test.dogrula('henüz yaklaşma uyarısı yok (120 < 240)',
    not exists (select 1 from pdks.uyari where tur = 'fm_yillik_sinir_yaklasti' and calisan_id = test.c('FM01')));

update pdks.fazla_mesai_plani set durum = 'onaylandi', karar_veren_id = test.k('fm_ik@ornek.test')
where id = test.p('FM01', '2026-12-02');
select test.dogrula('%80 eşiği geçilince İK''ya uyarı düştü (240 / 300)',
    (select count(*) = 1 from pdks.uyari where tur = 'fm_yillik_sinir_yaklasti' and calisan_id = test.c('FM01')));
select test.hata_bekle('yıllık sınır aşılamaz (240 + 120 > 300)',
    $$update pdks.fazla_mesai_plani set durum = 'onaylandi', karar_veren_id = test.k('fm_ik@ornek.test')
      where id = test.p('FM01', '2026-12-03')$$);
select test.hata_bekle('onaylı planın dakikası değiştirilemez',
    $$update pdks.fazla_mesai_plani set planli_dk = 60 where id = test.p('FM01', '2026-12-01')$$);
select test.hata_bekle('onaylı plan tekrar talebe döndürülemez',
    $$update pdks.fazla_mesai_plani set durum = 'talep', karar_zamani = null
      where id = test.p('FM01', '2026-12-01')$$);

-- Reddetmek de onaylamak gibi İK'nın işi. 3 Aralık planı hâlâ 'talep' durumunda.
select test.hata_bekle('amir fazla mesai planını reddedemez',
    $$update pdks.fazla_mesai_plani set durum = 'reddedildi', karar_veren_id = test.k('fm_amir@ornek.test')
      where id = test.p('FM01', '2026-12-03')$$);

-- Uygulamanın silme yetkisi yok (yetki hatası). postgres denese bile trigger engeller.
select test.hata_bekle('fazla mesai planı silinemez',
    $$delete from pdks.fazla_mesai_plani where id = test.p('FM01', '2026-12-01')$$);

-- 4) Gerçekleşen fazla mesai (gece işi yazar) -----------------------------
insert into pdks.gun_kaydi (calisan_id, is_gunu, vardiya_id, durum, fazla_mesai_dk)
values (test.c('FM01'), '2026-12-01', (select id from pdks.vardiya_tanim where kod = 'GUNDUZ'), 'eksik', 90);
select test.dogrula('onaylı plan içindeki 90 dk yazıldı',
    (select fazla_mesai_dk = 90 from pdks.gun_kaydi where calisan_id = test.c('FM01') and is_gunu = '2026-12-01'));
select test.hata_bekle('onaylı plandan fazlası yazılamaz (150 > 120)',
    $$update pdks.gun_kaydi set fazla_mesai_dk = 150
      where calisan_id = test.c('FM01') and is_gunu = '2026-12-01'$$);
select test.hata_bekle('plansız güne fazla mesai yazılamaz',
    $$insert into pdks.gun_kaydi (calisan_id, is_gunu, vardiya_id, durum, fazla_mesai_dk)
      values (test.c('FM02'), '2026-12-01', (select id from pdks.vardiya_tanim where kod = 'GUNDUZ'), 'eksik', 30)$$);
select test.dogrula('canlı puantajda fazla mesai görünüyor',
    (select fazla_mesai_dk = 90 from pdks.v_puantaj_canli
     where calisan_id = test.c('FM01') and yil = 2026 and ay = 12));

-- FM01, 2026: onaylı 120 + 120 = 240 dk, gerçekleşen 90 dk, kalan 300 - 240 = 60 dk
select test.dogrula('yıllık görünüm: onaylı 240, gerçekleşen 90, kalan 60',
    (select onayli_plan_dk = 240 and gerceklesen_dk = 90 and kalan_dk = 60
     from pdks.v_fazla_mesai_yillik where calisan_id = test.c('FM01') and yil = 2026));

-- 5) Onayın geri alınması -------------------------------------------------
-- Çalışan 10 Kasım'da bildirdi: 30 gün sonra (10 Aralık) onay geçersiz
update pdks.fazla_mesai_onayi
set geri_alma_bildirim_tarihi = '2026-11-10', geri_alma_giren_id = test.k('fm_ik@ornek.test')
where calisan_id = test.c('FM01') and yil = 2026;
select test.dogrula('geçerlilik bildirimden 30 gün sonra bitiyor',
    (select gecerlilik_bitisi = '2026-12-10' from pdks.fazla_mesai_onayi where calisan_id = test.c('FM01')));
select test.dogrula('10 Aralık öncesi onay hâlâ geçerli', pdks.fm_onay_gecerli_mi(test.c('FM01'), '2026-12-09'));
select test.dogrula('10 Aralık ve sonrası geçersiz', not pdks.fm_onay_gecerli_mi(test.c('FM01'), '2026-12-10'));
select test.dogrula('15 Aralık planı sistemce iptal edildi',
    (select durum = 'iptal' and karar_veren_id is null from pdks.fazla_mesai_plani
     where id = test.p('FM01', '2026-12-15')));
select test.dogrula('3 Aralık talebi (geçerlilik içinde) olduğu gibi kaldı',
    (select durum = 'talep' from pdks.fazla_mesai_plani where id = test.p('FM01', '2026-12-03')));
select test.dogrula('geri alma İK''ya uyarı olarak düştü',
    exists (select 1 from pdks.uyari where tur = 'fm_onay_geri_alindi' and calisan_id = test.c('FM01')));
select test.hata_bekle('geri alınan onaydan sonraki güne talep girilemez',
    $$insert into pdks.fazla_mesai_plani (calisan_id, is_gunu, planli_dk, gerekce, talep_eden_id)
      values (test.c('FM01'), '2026-12-16', 60, 'Sipariş yetişmeli', test.k('fm_amir@ornek.test'))$$);
select test.hata_bekle('geri alınmış onay tekrar değiştirilemez',
    $$update pdks.fazla_mesai_onayi set geri_alma_bildirim_tarihi = '2026-11-20'
      where calisan_id = test.c('FM01')$$);
select test.hata_bekle('geçerli onay varken kişisiz iptal yapılamaz',
    $$update pdks.fazla_mesai_plani set durum = 'iptal' where id = test.p('FM01', '2026-12-03')$$);

do $$ begin raise notice 'FAZLA MESAİ TESTLERİ GEÇTİ'; end $$;
rollback;
