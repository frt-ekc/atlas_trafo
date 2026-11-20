-- =====================================================================
-- Geçici kart (sorun 4) ve kart paylaşımı (sorun 6) testleri
-- Migration: 20261117020000_gecici_kart.sql, 20261117030000_kart_paylasimi.sql
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK), iz bırakmaz.
-- Çalıştırma: psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/gecici_kart_ve_paylasim_testi.sql
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
-- Kısa yollar: e-posta / sicil / kart no → id
create function test.k(p text) returns bigint language sql as $$ select id from pdks.kullanici where eposta = p $$;
create function test.c(p text) returns bigint language sql as $$ select id from pdks.calisan where sicil_no = p $$;
create function test.g(p text) returns bigint language sql as $$ select id from pdks.gecici_kart where kart_no = p $$;
-- Yalnızca bu testin verisine ait uyarıları sayar (T Montaj çalışanları ya da T- okuyucuları).
-- Örnek veride (seed) Eylül okutmaları da olduğu için tüm uyarıları saymak testi şansa bağlardı.
create function test.uyari_sayisi(p_tur text) returns bigint language sql as $$
    select count(*) from pdks.uyari u
    where u.tur = p_tur
      and (u.calisan_id in (select c.id from pdks.calisan c join pdks.departman d on d.id = c.departman_id
                            where d.ad = 'T Montaj')
           or u.okuyucu_id in (select o.id from pdks.okuyucu o where o.kod in ('T-PDKS', 'T-KAPI')))
$$;
-- Komutun verdiği hata mesajı (hata vermezse null)
create function test.hata_mesaji(p_sql text) returns text language plpgsql as $$
begin
    execute p_sql;
    return null;
exception when others then
    return sqlerrm;
end $$;

set timezone = 'Europe/Istanbul';

-- Örnek veri (yalnızca sahte) -------------------------------------------
insert into pdks.kullanici (ad_soyad, eposta, rol) values
    ('İK Bir', 'ik@ornek.test', 'ik'),
    ('Amir Bir', 'amir@ornek.test', 'amir');
insert into pdks.kullanici (ad_soyad, eposta, rol) values ('Güvenlik Bir', 'guvenlik@ornek.test', 'guvenlik');
select test.dogrula('güvenlik rolü eklenebiliyor', test.k('guvenlik@ornek.test') is not null);
insert into pdks.departman (ad, amir_id) values ('T Montaj', test.k('amir@ornek.test'));
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Soyad' || s, (select id from pdks.departman where ad = 'T Montaj'), '2025-01-01'
from unnest(array['T1001','T1002','T1003','T1004','T1005','T1006','T1007','T1008']) s;
insert into pdks.kart (kart_no, calisan_id)
select 'TK' || substr(s, 2), test.c(s) from unnest(array['T1001','T1002','T1003','T1004','T1005','T1006','T1007','T1008']) s;
insert into pdks.gecici_kart (kart_no) values ('TGK-01'), ('TGK-02'), ('TGK-03'), ('TGK-04');
insert into pdks.okuyucu (kod, ad, sistem) values ('T-PDKS', 'A kapısı PDKS', 'pdks'),
                                                ('T-KAPI', 'Tesis kapısı', 'kapi');
insert into pdks.aktarim (kaynak, dosya_adi, dosya_ozeti, veri_tarihi)
values ('pdks', 'pdks_eylul.csv', 'ozet-pdks', '2026-09-30'),
       ('kapi', 'kapi_eylul.csv', 'ozet-kapi', '2026-09-30');

-- =====================================================================
-- A) GEÇİCİ KART VE ZİMMET
-- =====================================================================
select test.hata_bekle('geçici kart numarası asıl kartla aynı olamaz',
    $$insert into pdks.gecici_kart (kart_no) values ('TK1001')$$);
select test.hata_bekle('asıl kart numarası geçici kartla aynı olamaz',
    $$insert into pdks.kart (kart_no, calisan_id) values ('TGK-01', test.c('T1008'))$$);

select test.hata_bekle('amir geçici kart veremez',
    $$insert into pdks.gecici_kart_zimmet (gecici_kart_id, calisan_id, verilis_zamani, veren_id)
      values (test.g('TGK-01'), test.c('T1001'), '2026-09-10 07:50+03', test.k('amir@ornek.test'))$$);

insert into pdks.gecici_kart_zimmet (gecici_kart_id, calisan_id, verilis_zamani, veren_id)
values (test.g('TGK-01'), test.c('T1001'), '2026-09-10 07:50+03', test.k('guvenlik@ornek.test'));
select test.dogrula('güvenlik geçici kartı verdi', exists (select 1 from pdks.gecici_kart_zimmet));

select test.hata_bekle('iade edilmemiş kart başkasına verilemez',
    $$insert into pdks.gecici_kart_zimmet (gecici_kart_id, calisan_id, verilis_zamani, veren_id)
      values (test.g('TGK-01'), test.c('T1002'), '2026-09-10 09:00+03', test.k('guvenlik@ornek.test'))$$);
select test.dogrula('çakışma mesajı açık zimmeti söyler: kart, kişi, tarih, saat, iade durumu (20261129020000)',
    test.hata_mesaji($$insert into pdks.gecici_kart_zimmet (gecici_kart_id, calisan_id, verilis_zamani, veren_id)
      values (test.g('TGK-01'), test.c('T1002'), '2026-09-10 09:00+03', test.k('guvenlik@ornek.test'))$$)
    = 'TGK-01 kartı AdT1001 SoyadT1001''a 10.09.2026 07:50''de verilmiş zimmetle çakışıyor (henüz iade edilmedi).');
select test.hata_bekle('bir çalışanda aynı anda iki geçici kart olamaz',
    $$insert into pdks.gecici_kart_zimmet (gecici_kart_id, calisan_id, verilis_zamani, veren_id)
      values (test.g('TGK-02'), test.c('T1001'), '2026-09-10 09:00+03', test.k('guvenlik@ornek.test'))$$);
select test.hata_bekle('zimmetin çalışanı değiştirilemez',
    $$update pdks.gecici_kart_zimmet set calisan_id = test.c('T1002')$$);
select test.hata_bekle('zimmet silinemez (yetki yok)',
    $$delete from pdks.gecici_kart_zimmet$$);
select test.hata_bekle('amir iade alamaz',
    $$update pdks.gecici_kart_zimmet set iade_zamani = '2026-09-10 17:10+03', iade_alan_id = test.k('amir@ornek.test')$$);

update pdks.gecici_kart_zimmet
set iade_zamani = '2026-09-10 17:10+03', iade_alan_id = test.k('guvenlik@ornek.test')
where gecici_kart_id = test.g('TGK-01');
select test.dogrula('güvenlik iadeyi aldı',
    (select iade_zamani is not null from pdks.gecici_kart_zimmet where gecici_kart_id = test.g('TGK-01')));
select test.hata_bekle('iade edilmiş zimmet değiştirilemez',
    $$update pdks.gecici_kart_zimmet set iade_zamani = '2026-09-10 18:00+03'$$);
select test.hata_bekle('geriye dönük çakışan zimmet girilemez',
    $$insert into pdks.gecici_kart_zimmet (gecici_kart_id, calisan_id, verilis_zamani, veren_id)
      values (test.g('TGK-01'), test.c('T1002'), '2026-09-10 12:00+03', test.k('guvenlik@ornek.test'))$$);
select test.dogrula('iade edilmiş zimmetle çakışmada mesaj iade saatini de söyler',
    test.hata_mesaji($$insert into pdks.gecici_kart_zimmet (gecici_kart_id, calisan_id, verilis_zamani, veren_id)
      values (test.g('TGK-01'), test.c('T1002'), '2026-09-10 12:00+03', test.k('guvenlik@ornek.test'))$$)
    like '%TGK-01 kartı AdT1001 SoyadT1001''a 10.09.2026 07:50''de verilmiş zimmetle çakışıyor (iade: 10.09.2026 17:10).');
select test.dogrula('isim eki: son ünlüye göre a / e, ünlüyle bitince y',
    pdks.yonelme_eki('Osman Doğan') = 'Osman Doğan''a' and pdks.yonelme_eki('Elif Şen') = 'Elif Şen''e'
    and pdks.yonelme_eki('Mehmet Kaya') = 'Mehmet Kaya''ya' and pdks.yonelme_eki('Levent Sarı') = 'Levent Sarı''ya'
    and pdks.yonelme_eki('Serkan Öztürk') = 'Serkan Öztürk''e' and pdks.yonelme_eki('Ezgi Polater') = 'Ezgi Polater''e'
    and pdks.yonelme_eki('Ahmet Er') = 'Ahmet Er''e' and pdks.yonelme_eki('Hülya Gündoğdu') = 'Hülya Gündoğdu''ya');
select test.dogrula('saat eki: okunuşun son sayısına göre (yirmi beş''te, yedi''de, otuz''da, kırk''ta, elli''de, altı''da)',
    pdks.saat_eki('2026-11-24 07:25+03') = '07:25''te' and pdks.saat_eki('2026-11-24 07:00+03') = '07:00''de'
    and pdks.saat_eki('2026-11-24 17:30+03') = '17:30''da' and pdks.saat_eki('2026-11-24 08:40+03') = '08:40''ta'
    and pdks.saat_eki('2026-11-24 13:50+03') = '13:50''de' and pdks.saat_eki('2026-11-24 09:06+03') = '09:06''da'
    and pdks.saat_eki('2026-11-24 00:00+03') = '00:00''da' and pdks.saat_eki('2026-11-24 10:00+03') = '10:00''da'
    and pdks.saat_eki('2026-11-24 11:03+03') = '11:03''te');

select test.hata_bekle('zimmet tablo sahibi için bile silinemez',
    $$delete from pdks.gecici_kart_zimmet$$);
select test.hata_bekle('zimmet tablosu boşaltılamaz (TRUNCATE)',
    $$truncate pdks.gecici_kart_zimmet$$);

update pdks.gecici_kart set durum = 'kayip' where kart_no = 'TGK-04';
select test.hata_bekle('kayıp geçici kart verilemez',
    $$insert into pdks.gecici_kart_zimmet (gecici_kart_id, calisan_id, verilis_zamani, veren_id)
      values (test.g('TGK-04'), test.c('T1003'), '2026-09-11 07:00+03', test.k('guvenlik@ornek.test'))$$);

select test.dogrula('okutma sahibi: zimmet içindeki geçici kart → çalışan',
    pdks.okutma_sahibi('TGK-01', '2026-09-10 10:00+03') = test.c('T1001'));
select test.dogrula('okutma sahibi: zimmet dışındaki geçici kart → kimse',
    pdks.okutma_sahibi('TGK-01', '2026-09-10 18:30+03') is null);
select test.dogrula('okutma sahibi: asıl kart → sahibi',
    pdks.okutma_sahibi('TK1002', '2026-09-10 10:00+03') = test.c('T1002'));
select test.dogrula('okutma sahibi: bilinmeyen kart → kimse',
    pdks.okutma_sahibi('X-999', '2026-09-10 10:00+03') is null);

-- Gece işi kontrolleri için okutmalar (10 Eylül)
insert into pdks.ham_okutma (aktarim_id, okuyucu_id, kart_no, okutma_zamani, yon)
select (select id from pdks.aktarim where dosya_ozeti = 'ozet-pdks'), (select id from pdks.okuyucu where kod = 'T-PDKS'), k, t::timestamptz, y
from (values ('TGK-01', '2026-09-10 08:00+03', 'giris'),   -- zimmet içinde: normal
             ('TGK-01', '2026-09-10 18:30+03', 'giris'))   -- zimmet dışında: uyarı
     v(k, t, y);
insert into pdks.kanit_kaydi (aktarim_id, okuyucu_id, kaynak, kart_no, okutma_zamani, yon)
values ((select id from pdks.aktarim where dosya_ozeti = 'ozet-kapi'), (select id from pdks.okuyucu where kod = 'T-KAPI'),
        'kapi', 'TK1001', '2026-09-10 12:00+03', 'giris');   -- A'nın asıl kartı, geçici kart zimmetliyken

-- C'ye 11 Eylül'de verilip iade edilmeyen kart; D'ye ayda 3 kez kart
insert into pdks.gecici_kart_zimmet (gecici_kart_id, calisan_id, verilis_zamani, veren_id)
values (test.g('TGK-03'), test.c('T1003'), '2026-09-11 07:00+03', test.k('guvenlik@ornek.test'));
insert into pdks.gecici_kart_zimmet (gecici_kart_id, calisan_id, verilis_zamani, veren_id, iade_zamani, iade_alan_id)
select test.g('TGK-02'), test.c('T1004'), (d || ' 07:00+03')::timestamptz, test.k('guvenlik@ornek.test'), null, null
from unnest(array['2026-09-02']) d;
update pdks.gecici_kart_zimmet set iade_zamani = '2026-09-02 17:00+03', iade_alan_id = test.k('guvenlik@ornek.test')
where calisan_id = test.c('T1004') and iade_zamani is null;
insert into pdks.gecici_kart_zimmet (gecici_kart_id, calisan_id, verilis_zamani, veren_id)
values (test.g('TGK-02'), test.c('T1004'), '2026-09-03 07:00+03', test.k('guvenlik@ornek.test'));
update pdks.gecici_kart_zimmet set iade_zamani = '2026-09-03 17:00+03', iade_alan_id = test.k('guvenlik@ornek.test')
where calisan_id = test.c('T1004') and iade_zamani is null;
insert into pdks.gecici_kart_zimmet (gecici_kart_id, calisan_id, verilis_zamani, veren_id)
values (test.g('TGK-02'), test.c('T1004'), '2026-09-04 07:00+03', test.k('guvenlik@ornek.test'));
update pdks.gecici_kart_zimmet set iade_zamani = '2026-09-04 17:00+03', iade_alan_id = test.k('guvenlik@ornek.test')
where calisan_id = test.c('T1004') and iade_zamani is null;

select pdks.gecici_kart_kontrol('2026-09-10');
select test.dogrula('geçici kart zimmetliyken asıl kart okutuldu → İK''ya uyarı',
    test.uyari_sayisi('gecici_kart_cakisma') = 1);
select test.dogrula('geçici kart zimmet dışında okutuldu → İK''ya uyarı',
    test.uyari_sayisi('gecici_kart_zimmetsiz') = 1);
select test.dogrula('aynı gün tekrar işlenince uyarı çoğalmıyor',
    pdks.gecici_kart_kontrol('2026-09-10') = 0
    and test.uyari_sayisi('gecici_kart_cakisma') = 1 and test.uyari_sayisi('gecici_kart_zimmetsiz') = 1);
select pdks.gecici_kart_kontrol('2026-09-12');
select test.dogrula('iade edilmeyen geçici kart → İK''ya uyarı',
    exists (select 1 from pdks.uyari where tur = 'gecici_kart_iade_edilmedi' and calisan_id = test.c('T1003')));
select pdks.gecici_kart_kontrol('2026-09-04');
select test.dogrula('ayda 3 geçici kart alan çalışan → bilgi uyarısı',
    exists (select 1 from pdks.uyari where tur = 'sik_kart_unutma' and calisan_id = test.c('T1004')));
select test.dogrula('uygulama (authenticated) zimmete doğrudan yazamaz',
    not has_table_privilege('authenticated', 'pdks.gecici_kart_zimmet', 'insert'));

-- =====================================================================
-- B) KART PAYLAŞIMI ŞÜPHESİ
-- =====================================================================
-- T1005 ve T1006: 5 farklı günde 3 saniye arayla arka arkaya → şüphe
-- T1007 ve T1008: 4 farklı günde arka arkaya → eşik altı, şüphe yok
-- T1001 ve T1002: 5 günde ama 20 saniye arayla → ardışık sayılmaz
-- T1003 ve T1004: tek seferlik ardışık okutma → şüphe yok
insert into pdks.ham_okutma (aktarim_id, okuyucu_id, kart_no, okutma_zamani, yon)
select (select id from pdks.aktarim where dosya_ozeti = 'ozet-pdks'), (select id from pdks.okuyucu where kod = 'T-PDKS'),
       k, (g || ' ' || s)::timestamptz, 'giris'
from (
    select g::date::text as g, k, s
    from generate_series('2026-09-16'::date, '2026-09-20'::date, '1 day') g,
         (values ('TK1005', '07:40:00+03'), ('TK1006', '07:40:03+03'),
                 ('TK1001', '07:45:00+03'), ('TK1002', '07:45:20+03')) v(k, s)
    union all
    select g::date::text, k, s
    from generate_series('2026-09-16'::date, '2026-09-19'::date, '1 day') g,
         (values ('TK1007', '07:50:00+03'), ('TK1008', '07:50:02+03')) v(k, s)
    union all
    select '2026-09-16', k, s from (values ('TK1003', '07:55:00+03'), ('TK1004', '07:55:01+03')) v(k, s)
) x;

select pdks.kart_paylasim_kontrol('2026-09-30');
select test.dogrula('kart paylaşımı şüphesi: tek çift için tek uyarı',
    test.uyari_sayisi('kart_paylasim_suphesi') = 1);
select test.dogrula('şüpheli çift T1005–T1006',
    exists (select 1 from pdks.uyari where tur = 'kart_paylasim_suphesi'
            and calisan_id = test.c('T1005') and mesaj like '%T1006%'));
select test.dogrula('eşik altı (4 gün) çift uyarı almadı',
    not exists (select 1 from pdks.uyari where tur = 'kart_paylasim_suphesi' and mesaj like '%T1007%'));
select test.dogrula('20 saniye arayla okutanlar ardışık sayılmadı',
    not exists (select 1 from pdks.uyari where tur = 'kart_paylasim_suphesi' and calisan_id = test.c('T1001')));
select test.dogrula('tek seferlik ardışık okutma uyarı almadı',
    not exists (select 1 from pdks.uyari where tur = 'kart_paylasim_suphesi' and mesaj like '%T1003%'));
select test.dogrula('tekrar çalıştırınca uyarı çoğalmıyor',
    pdks.kart_paylasim_kontrol('2026-09-30') = 0 and test.uyari_sayisi('kart_paylasim_suphesi') = 1);
select test.dogrula('kart paylaşımı günlük kaydı değiştirmedi (ceza yok)',
    not exists (select 1 from pdks.gun_kaydi) and not exists (select 1 from pdks.duzeltme));

update pdks.ayar set deger = 4 where anahtar = 'kart_paylasim_gun';
select pdks.kart_paylasim_kontrol('2026-09-30');
select test.dogrula('eşik ayardan değişince (4 gün) T1007–T1008 da uyarı aldı',
    exists (select 1 from pdks.uyari where tur = 'kart_paylasim_suphesi' and calisan_id = test.c('T1007')));

select test.dogrula('pdks fonksiyonlarının hiçbiri herkese (PUBLIC) açık değil',
    not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                where n.nspname = 'pdks' and has_function_privilege('public', p.oid, 'execute')));

do $$ begin raise notice 'GEÇİCİ KART VE KART PAYLAŞIMI TESTLERİ GEÇTİ'; end $$;
rollback;
