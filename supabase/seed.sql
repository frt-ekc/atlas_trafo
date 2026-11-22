-- =====================================================================
-- Örnek (sahte) veri — Kasım 2026
--
-- Tüm kişiler, kartlar ve okutmalar uydurmadır. Gerçek Atlas Trafo verisi içermez.
-- Gece işinin işleyeceği GİRDİLER üretilir: organizasyon, kullanıcılar, kartlar,
-- vardiya planı, izinler, fazla mesai onay/planları, geçici kart zimmetleri ve
-- PDKS / kapı / yemekhane / servis okutmaları. Gün kayıtlarını, düzeltmeleri ve
-- amir sorularını gece işi üretir.
--
-- Bilerek konmuş hatalar ve hangi soruna karşılık geldikleri: docs/ornek_veri.md
--
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/seed.sql
-- Veri her çalıştırmada aynı çıkar (rastgele değil, sicil ve tarihten türetilir).
-- İkinci kez çalıştırılırsa hiçbir şey yazmadan durur.
-- =====================================================================
begin;
set local timezone = 'Europe/Istanbul';

do $$
begin
    if exists (select 1 from pdks.calisan where sicil_no = '1001') then
        raise exception 'Örnek veri zaten yüklü (sicil 1001 var); işlem yapılmadı.';
    end if;
end $$;

-- Sicil ve tarihten türetilen sabit "rastgele" sayı: [alt, ust]
create function pg_temp.sayi(p_tohum text, p_alt int, p_ust int) returns int
language sql immutable as $$
    select p_alt + abs(hashtext(p_tohum)) % (p_ust - p_alt + 1)
$$;

-- ---------------------------------------------------------------------
-- 1. Resmi tatiller (2026) ve okuyucular
-- ---------------------------------------------------------------------
insert into pdks.resmi_tatil (tarih, ad, yarim_gun) values
    ('2026-01-01', 'Yılbaşı', false),
    ('2026-03-19', 'Ramazan Bayramı arifesi', true),
    ('2026-03-20', 'Ramazan Bayramı 1. gün', false),
    ('2026-03-21', 'Ramazan Bayramı 2. gün', false),
    ('2026-03-22', 'Ramazan Bayramı 3. gün', false),
    ('2026-04-23', 'Ulusal Egemenlik ve Çocuk Bayramı', false),
    ('2026-05-01', 'Emek ve Dayanışma Günü', false),
    ('2026-05-19', 'Atatürk''ü Anma, Gençlik ve Spor Bayramı', false),
    ('2026-05-26', 'Kurban Bayramı arifesi', true),
    ('2026-05-27', 'Kurban Bayramı 1. gün', false),
    ('2026-05-28', 'Kurban Bayramı 2. gün', false),
    ('2026-05-29', 'Kurban Bayramı 3. gün', false),
    ('2026-05-30', 'Kurban Bayramı 4. gün', false),
    ('2026-07-15', 'Demokrasi ve Millî Birlik Günü', false),
    ('2026-08-30', 'Zafer Bayramı', false),
    ('2026-10-28', 'Cumhuriyet Bayramı arifesi', true),
    ('2026-10-29', 'Cumhuriyet Bayramı', false)
on conflict (tarih) do nothing;

insert into pdks.okuyucu (kod, ad, sistem, konum) values
    ('PDKS-1', 'Ana giriş PDKS',       'pdks',      'İdari bina girişi'),
    ('PDKS-2', 'Atölye PDKS',          'pdks',      'Bobinaj atölyesi girişi'),
    ('KAPI-1', 'Ana kapı turnike',     'kapi',      'Fabrika ana kapısı'),
    ('YMK-1',  'Yemekhane',            'yemekhane', 'Yemekhane girişi'),
    ('SRV-1',  'Servis 1 (Bornova)',   'servis',    'Servis aracı'),
    ('SRV-2',  'Servis 2 (Buca)',      'servis',    'Servis aracı');

-- ---------------------------------------------------------------------
-- 2. Departmanlar, çalışanlar, kartlar
-- ---------------------------------------------------------------------
-- Kısa ad (bu dosyada kullanılır) → departman adı ve yaka
create temp table dp (kisa text primary key, ad text, yaka text) on commit drop;
insert into dp values
    ('Montaj',     'Aktif Kısım ve Montaj',                   'mavi'),
    ('Bobinaj',    'Bobinaj',                                 'mavi'),
    ('Kalite',     'Kalite Kontrol ve YG Test Laboratuvarı',  'mavi'),
    ('İdari',      'İdari İşler',                             'mavi'),
    ('Nüve',       'Nüve Dizme',                              'mavi'),
    ('Kazan',      'Kazan İmalat ve Kaynak',                  'mavi'),
    ('Boya',       'Boyahane ve Yüzey İşlem',                 'mavi'),
    ('Bakım',      'Bakım ve Onarım',                         'mavi'),
    ('Depo',       'Depo ve Sevkiyat',                        'mavi'),
    ('ArGe',       'Ar-Ge ve Tasarım',                        'beyaz'),
    ('Planlama',   'Üretim Planlama',                         'beyaz'),
    ('Satış',      'Satış ve Pazarlama',                      'beyaz'),
    ('DışTicaret', 'Dış Ticaret ve Lojistik',                 'beyaz'),
    ('SatınAlma',  'Satın Alma',                              'beyaz'),
    ('İK',         'İnsan Kaynakları',                        'beyaz'),
    ('İSG',        'İSG',                                     'beyaz'),
    ('Finans',     'Finans ve Muhasebe',                      'beyaz'),
    ('Bİ',         'Bilgi İşlem',                             'beyaz'),
    ('ÜstYönetim', 'Üst Yönetim',                             'beyaz');
insert into pdks.departman (ad, yaka) select ad, yaka from dp order by ad;

-- grup: G = Gündüz 08-17 · A/B/C = Bobinaj V1/V2/V3 dönüşümlü · G8 = Gündüz 08-16 ·
--       R1/R2 = 08-16 / 16-24 / 00-08 haftalık dönüşümlü · BY = beyaz yaka 08:30-18:00 · E = esnek
create temp table c (sicil text, ad text, soyad text, dep text, grup text, servis text) on commit drop;
insert into c values
    -- Montaj (gündüz)
    ('1001', 'Hasan',   'Yılmaz',   'Montaj',  'G', 'SRV-1'),
    ('1002', 'Mehmet',  'Kaya',     'Montaj',  'G', 'SRV-1'),
    ('1003', 'Ali',     'Demir',    'Montaj',  'G', null),
    ('1004', 'Veli',    'Çelik',    'Montaj',  'G', 'SRV-1'),
    ('1005', 'Mustafa', 'Şahin',    'Montaj',  'G', null),
    ('1006', 'Hüseyin', 'Aydın',    'Montaj',  'G', 'SRV-1'),
    ('1007', 'İbrahim', 'Arslan',   'Montaj',  'G', null),
    ('1008', 'Osman',   'Doğan',    'Montaj',  'G', 'SRV-1'),
    ('1009', 'Emre',    'Koç',      'Montaj',  'G', null),
    ('1010', 'Burak',   'Kurt',     'Montaj',  'G', 'SRV-1'),
    -- Bobinaj (amir gündüz; A, B, C grupları haftalık V1 / V2 / V3 dönüşümlü)
    ('2001', 'Serkan',  'Öztürk',   'Bobinaj', 'G', null),
    ('2002', 'Kemal',   'Aslan',    'Bobinaj', 'A', null),
    ('2003', 'Murat',   'Polat',    'Bobinaj', 'A', null),
    ('2004', 'Cem',     'Erdoğan',  'Bobinaj', 'A', null),
    ('2005', 'Okan',    'Yıldız',   'Bobinaj', 'B', null),
    ('2006', 'Tolga',   'Güneş',    'Bobinaj', 'B', null),
    ('2007', 'Can',     'Kılıç',    'Bobinaj', 'B', null),
    ('2008', 'Deniz',   'Aksoy',    'Bobinaj', 'C', null),
    ('2009', 'Kaan',    'Bulut',    'Bobinaj', 'C', null),
    ('2010', 'Eren',    'Taş',      'Bobinaj', 'C', null),
    -- Kalite (gündüz)
    ('3001', 'Zeynep',  'Acar',     'Kalite',  'G', 'SRV-2'),
    ('3002', 'Selin',   'Uçar',     'Kalite',  'G', 'SRV-2'),
    ('3003', 'Gizem',   'Korkmaz',  'Kalite',  'G', null),
    ('3004', 'Ece',     'Ateş',     'Kalite',  'G', 'SRV-2'),
    ('3005', 'Merve',   'Yücel',    'Kalite',  'G', null),
    -- İdari (gündüz)
    ('4001', 'Elif',    'Şen',      'İdari',   'G', null),
    ('4002', 'Ahmet',   'Er',       'İdari',   'G', null),
    ('4003', 'Recep',   'Bayram',   'İdari',   'G', null),
    ('4004', 'Nur',     'Tekin',    'İdari',   'G', null),
    ('4005', 'Derya',   'Özkan',    'İdari',   'G', 'SRV-2'),
    ('4006', 'Levent',  'Sarı',     'İdari',   'G', null),
    -- Nüve Dizme ve Kazan İmalat (amir 08-16; işçiler 08-16 / 16-24 / 00-08 dönüşümlü)
    ('5001', 'Barış',   'Yalçın',   'Nüve',       'G8', null),
    ('5002', 'Ferhat',  'Kara',     'Nüve',       'R1', null),
    ('5003', 'Gökhan',  'Tuna',     'Nüve',       'R2', null),
    ('5101', 'Sinan',   'Güler',    'Kazan',      'G8', null),
    ('5102', 'Erkan',   'Duman',    'Kazan',      'R1', null),
    ('5103', 'Yasin',   'Avcı',     'Kazan',      'R2', null),
    -- Boyahane, Bakım, Depo (08-16)
    ('5201', 'Cengiz',  'Sezer',    'Boya',       'G8', null),
    ('5202', 'Hakan',   'Ekinci',   'Boya',       'G8', null),
    ('5203', 'Orhan',   'Bozkurt',  'Boya',       'G8', null),
    ('5301', 'Volkan',  'Şimşek',   'Bakım',      'G8', null),
    ('5302', 'Taner',   'Yazıcı',   'Bakım',      'G8', null),
    ('5303', 'Uğur',    'Keskin',   'Bakım',      'G8', null),
    ('5401', 'Ramazan', 'Çetin',    'Depo',       'G8', null),
    ('5402', 'Selim',   'Ünal',     'Depo',       'G8', null),
    ('5403', 'Halil',   'Turan',    'Depo',       'G8', null),
    -- Beyaz yaka (08:30-18:00); Ar-Ge ve Satış çalışanları esnek mesai
    ('6001', 'Aylin',   'Kaplan',   'ArGe',       'BY', null),
    ('6002', 'Onur',    'Baysal',   'ArGe',       'E',  null),
    ('6003', 'Pınar',   'Demirtaş', 'ArGe',       'E',  null),
    ('6101', 'Cansu',   'Akın',     'Planlama',   'BY', null),
    ('6102', 'Tuncay',  'Erdem',    'Planlama',   'BY', null),
    ('6103', 'Damla',   'Özer',     'Planlama',   'BY', null),
    ('6201', 'Serdar',  'Coşkun',   'Satış',      'BY', null),
    ('6202', 'İrem',    'Toprak',   'Satış',      'E',  null),
    ('6203', 'Kerem',   'Aydoğan',  'Satış',      'E',  null),
    ('6301', 'Gamze',   'Yüksel',   'DışTicaret', 'BY', null),
    ('6302', 'Batuhan', 'Işık',     'DışTicaret', 'BY', null),
    ('6303', 'Seda',    'Karaca',   'DışTicaret', 'BY', null),
    ('6401', 'Nihat',   'Uysal',    'SatınAlma',  'BY', null),
    ('6402', 'Esra',    'Bilgin',   'SatınAlma',  'BY', null),
    ('6403', 'Arda',    'Sönmez',   'SatınAlma',  'BY', null),
    ('6501', 'Filiz',   'Oral',     'İK',         'BY', null),
    ('6502', 'Ozan',    'Kurtuluş', 'İK',         'BY', null),
    ('6503', 'Burcu',   'Çakır',    'İK',         'BY', null),
    ('6601', 'Mert',    'Alkan',    'İSG',        'BY', null),
    ('6602', 'Tuba',    'Erkoç',    'İSG',        'BY', null),
    ('6603', 'Kadir',   'Eren',     'İSG',        'BY', null),
    ('6701', 'Hülya',   'Gündoğdu', 'Finans',     'BY', null),
    ('6702', 'Emrah',   'Sevim',    'Finans',     'BY', null),
    ('6703', 'Melis',   'Aras',     'Finans',     'BY', null),
    ('6801', 'Tamer',   'Oğuz',     'Bİ',         'BY', null),
    ('6802', 'Alper',   'Çınar',    'Bİ',         'BY', null),
    ('6803', 'Ezgi',    'Polater',  'Bİ',         'BY', null),
    ('6901', 'Rıza',    'Kalkan',   'ÜstYönetim', 'BY', null),
    ('6902', 'Şule',    'Erten',    'ÜstYönetim', 'BY', null),
    ('6903', 'Yavuz',   'Soylu',    'ÜstYönetim', 'BY', null);

insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select c.sicil, c.ad, c.soyad, d.id, date '2024-01-02' + pg_temp.sayi(c.sicil, 0, 600)
from c join dp on dp.kisa = c.dep join pdks.departman d on d.ad = dp.ad
order by c.sicil;

insert into pdks.kart (kart_no, calisan_id, verilis_tarihi)
select 'K' || sicil_no, id, ise_giris_tarihi from pdks.calisan where sicil_no in (select sicil from c);

-- ---------------------------------------------------------------------
-- 3. Kullanıcılar (hepsi aynı zamanda çalışan)
--    E-postalar Supabase Auth'ta açılacak demo hesaplarıyla eşleşir.
-- ---------------------------------------------------------------------
create function pg_temp.cid(p text) returns bigint language sql stable as $$
    select id from pdks.calisan where sicil_no = p $$;

insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id) values
    ('Elif Şen',      'elif.sen@atlastrafo.example.com',     'ik',       pg_temp.cid('4001')),
    ('Ahmet Er',      'ahmet.er@atlastrafo.example.com',     'ik',       pg_temp.cid('4002')),
    ('Recep Bayram',  'recep.bayram@atlastrafo.example.com',      'guvenlik', pg_temp.cid('4003')),
    ('Nur Tekin',     'nur.tekin@atlastrafo.example.com','yonetici', pg_temp.cid('4004')),
    ('Levent Sarı',   'levent.sari@atlastrafo.example.com', 'amir',     pg_temp.cid('4006'));

insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, ust_amir_id)
select a, e, 'amir', pg_temp.cid(s), (select id from pdks.kullanici where eposta = 'levent.sari@atlastrafo.example.com')
from (values ('Hasan Yılmaz',  'hasan.yilmaz@atlastrafo.example.com',  '1001'),
             ('Serkan Öztürk', 'serkan.ozturk@atlastrafo.example.com', '2001'),
             ('Zeynep Acar',   'zeynep.acar@atlastrafo.example.com',  '3001')) v(a, e, s);

create function pg_temp.kid(p text) returns bigint language sql stable as $$
    select id from pdks.kullanici where eposta = p $$;

-- Yeni departmanların amirleri: mavi yakada üst amir üretim müdürü, beyaz yakada genel müdür
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id)
values ('Rıza Kalkan', 'riza.kalkan@atlastrafo.example.com', 'amir', pg_temp.cid('6901'));
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, ust_amir_id)
select c.ad || ' ' || c.soyad, v.e, 'amir', pg_temp.cid(v.s),
       (select id from pdks.kullanici
        where eposta = case when dp.yaka = 'mavi' then 'levent.sari@atlastrafo.example.com' else 'riza.kalkan@atlastrafo.example.com' end)
from (values ('5001', 'baris.yalcin@atlastrafo.example.com'),        ('5101', 'sinan.guler@atlastrafo.example.com'),
             ('5201', 'cengiz.sezer@atlastrafo.example.com'),    ('5301', 'volkan.simsek@atlastrafo.example.com'),
             ('5401', 'ramazan.cetin@atlastrafo.example.com'),        ('6001', 'aylin.kaplan@atlastrafo.example.com'),
             ('6101', 'cansu.akin@atlastrafo.example.com'),    ('6201', 'serdar.coskun@atlastrafo.example.com'),
             ('6301', 'gamze.yuksel@atlastrafo.example.com'), ('6401', 'nihat.uysal@atlastrafo.example.com'),
             ('6501', 'filiz.oral@atlastrafo.example.com'), ('6601', 'mert.alkan@atlastrafo.example.com'),
             ('6701', 'hulya.gundogdu@atlastrafo.example.com'),      ('6801', 'tamer.oguz@atlastrafo.example.com')) v(s, e)
join c on c.sicil = v.s join dp on dp.kisa = c.dep;

-- İSG uzmanı ve sistem yöneticisi
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id) values
    ('Tuba Erkoç',  'tuba.erkoc@atlastrafo.example.com',        'isg',   pg_temp.cid('6602')),
    ('Alper Çınar', 'alper.cinar@atlastrafo.example.com', 'admin', pg_temp.cid('6802'));

-- Her departmanın amiri: grubun ilk sicili (İdari İşler: üretim müdürü)
update pdks.departman d
set amir_id = case when dp.kisa = 'Montaj'  then pg_temp.kid('hasan.yilmaz@atlastrafo.example.com')
                   when dp.kisa = 'Bobinaj' then pg_temp.kid('serkan.ozturk@atlastrafo.example.com')
                   when dp.kisa = 'Kalite'  then pg_temp.kid('zeynep.acar@atlastrafo.example.com')
                   when dp.kisa = 'İdari'   then pg_temp.kid('levent.sari@atlastrafo.example.com')
                   else (select k.id from pdks.kullanici k
                         join pdks.calisan x on x.id = k.calisan_id
                         where x.departman_id = d.id and k.rol = 'amir'
                         order by x.sicil_no limit 1) end
from dp
where d.ad = dp.ad;
update pdks.departman set vekil_amir_id = pg_temp.kid('hasan.yilmaz@atlastrafo.example.com') where ad = 'Bobinaj';

-- İSG: bölgeler, bölge kapıları ve giriş yetkileri (İSG uzmanı verir)
insert into pdks.bolge (kod, ad) values ('YG-LAB', 'Yüksek Gerilim Test Laboratuvarı'), ('BOYAHANE', 'Boyahane');
insert into pdks.okuyucu (kod, ad, sistem, konum, bolge_id) values
    ('YG-KAPI',   'YG Test Lab kapısı', 'kapi', 'Kalite binası', (select id from pdks.bolge where kod = 'YG-LAB')),
    ('BOYA-KAPI', 'Boyahane kapısı',    'kapi', 'Boyahane',      (select id from pdks.bolge where kod = 'BOYAHANE'));
insert into pdks.bolge_yetkisi (bolge_id, departman_id, veren_id)
select (select id from pdks.bolge where kod = v.b), d.id, pg_temp.kid('tuba.erkoc@atlastrafo.example.com')
from (values ('YG-LAB', 'Kalite'), ('YG-LAB', 'Bakım'), ('BOYAHANE', 'Boya'), ('BOYAHANE', 'Bakım')) v(b, kisa)
join dp on dp.kisa = v.kisa join pdks.departman d on d.ad = dp.ad;

-- İSG eğitimi ve sağlık muayenesi: mavi yaka herkesin geçerli kaydı var (yalnızca tarih)
insert into pdks.isg_belge (calisan_id, tur, gecerlilik_bitis, belge_no, giren_id)
select x.id, t.tur,
       case -- S25 Uğur'un İSG eğitimi 10 Kasım'da doldu; S26 Taner'in sağlık muayenesi 15 Aralık'ta doluyor
            when x.sicil_no = '5303' and t.tur = 'isg_egitimi'      then date '2026-11-10'
            when x.sicil_no = '5302' and t.tur = 'saglik_muayenesi' then date '2026-12-15'
            else case t.tur when 'isg_egitimi' then date '2027-01-15' else date '2027-02-01' end
                 + pg_temp.sayi(x.sicil_no || t.tur, 0, 300) end,
       'ISG-' || x.sicil_no || '-' || t.kisa, pg_temp.kid('tuba.erkoc@atlastrafo.example.com')
from pdks.calisan x
join pdks.departman d on d.id = x.departman_id and d.yaka = 'mavi'
cross join (values ('isg_egitimi', 'E'), ('saglik_muayenesi', 'M')) t(tur, kisa)
where x.sicil_no in (select sicil from c)
order by x.sicil_no, t.tur;

-- İK kayıtlarını İK uzmanı girer; kendi kayıtlarını İK müdürü (görevler ayrılığı)
create function pg_temp.giren(p_calisan bigint) returns bigint language sql stable as $$
    select case when p_calisan = pg_temp.cid('4001') then pg_temp.kid('ahmet.er@atlastrafo.example.com')
                else pg_temp.kid('elif.sen@atlastrafo.example.com') end $$;

-- ---------------------------------------------------------------------
-- 4. Vardiya planı: 1-30 Kasım 2026, hafta içi
--    Bobinaj grupları haftalık döner: 1. hafta A=V1 B=V2 C=V3, sonra kayar.
-- ---------------------------------------------------------------------
create temp table p (sicil text, tarih date, vardiya text) on commit drop;
insert into p
select c.sicil, g::date,
       case when c.grup = 'G'  then 'GUNDUZ'
            when c.grup = 'G8' then 'GUNDUZ_8'
            when c.grup = 'BY' then 'BEYAZ'
            when c.grup = 'E'  then 'ESNEK'
            when c.grup in ('R1', 'R2') then
                 (array['GUNDUZ_8', 'AKSAM_8', 'GECE_8'])[1 + ((array_position(array['R1', 'R2'], c.grup) - 1
                                              + (extract(week from g)::int - extract(week from date '2026-11-02')::int)) % 3)]
            else (array['V1', 'V2', 'V3'])[1 + ((array_position(array['A', 'B', 'C'], c.grup) - 1
                                              + (extract(week from g)::int - extract(week from date '2026-11-02')::int)) % 3)]
       end
from c, generate_series(date '2026-11-02', date '2026-11-30', interval '1 day') g
where extract(isodow from g) <= 5;

-- Senaryo S13: Okan 13 Kasım'da V3 yerine V2'de çalıştı; plan ertesi gün geriye dönük düzeltildi
update p set vardiya = 'V2' where sicil = '2005' and tarih = '2026-11-13';
-- S29 Mehmet (yazılı onaylı) 22 Kasım Pazar, S30 Erkan (yazılı onay yok) 29 Kasım Pazar çalıştı
insert into p values ('1002', '2026-11-22', 'GUNDUZ'), ('5102', '2026-11-29', 'GUNDUZ_8');

insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id, giren_id, giris_zamani, geriye_donuk, ik_onay_durumu, aciklama)
select pg_temp.cid(p.sicil), p.tarih, v.id, pg_temp.giren(pg_temp.cid(p.sicil)),
       case when p.sicil = '2005' and p.tarih = '2026-11-13' then timestamptz '2026-11-14 09:10'
            else timestamptz '2026-10-26 10:00' end,
       p.sicil = '2005' and p.tarih = '2026-11-13',
       case when p.sicil = '2005' and p.tarih = '2026-11-13' then 'bekliyor' else 'gerekmez' end,
       case when p.sicil = '2005' and p.tarih = '2026-11-13' then 'V3 yerine V2 (ihtiyaç değişikliği)' end
from p join pdks.vardiya_tanim v on v.kod = p.vardiya;

-- Demo günü 7 Aralık (Pazartesi): yalnızca Montaj'ın 10 kişisi planlı (okutmaları demo/ klasöründeki
-- CSV'lerle demoda yüklenir; bu yüzden p tablosuna eklenmez, seed okutma üretmez)
insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id, giren_id, giris_zamani)
select pg_temp.cid(c.sicil), date '2026-12-07', (select id from pdks.vardiya_tanim where kod = 'GUNDUZ'),
       pg_temp.giren(pg_temp.cid(c.sicil)), timestamptz '2026-11-16 10:00'
from c where c.dep = 'Montaj';

-- ---------------------------------------------------------------------
-- 5. İzinler
-- ---------------------------------------------------------------------
insert into pdks.izin (calisan_id, tur, baslangic, bitis, aciklama, giren_id)
select pg_temp.cid(s), t, b, e, a, pg_temp.giren(pg_temp.cid(s))
from (values ('2007', 'rapor',  date '2026-11-23', date '2026-11-25', 'Doktor raporu'),
             ('2008', 'yillik', date '2026-11-26', date '2026-11-27', 'Yıllık izin'),
             ('4005', 'mazeret', date '2026-11-16', date '2026-11-16', 'Mazeret izni')) v(s, t, b, e, a);

-- ---------------------------------------------------------------------
-- 6. Fazla mesai: yazılı onaylar (Merve hariç) ve bir onaylı plan
-- ---------------------------------------------------------------------
insert into pdks.fazla_mesai_onayi (calisan_id, yil, imza_tarihi, belge_no, giren_id)
select pg_temp.cid(sicil), 2026, date '2026-01-05', 'FMO-2026-' || sicil, pg_temp.giren(pg_temp.cid(sicil))
from c where sicil < '4000' and sicil <> '3005';

insert into pdks.fazla_mesai_plani (calisan_id, is_gunu, vardiya_id, planli_dk, gerekce, talep_eden_id)
values (pg_temp.cid('3003'), '2026-11-20', (select id from pdks.vardiya_tanim where kod = 'GUNDUZ'), 120,
        'Sevkiyat öncesi son kontroller', pg_temp.kid('zeynep.acar@atlastrafo.example.com'));
update pdks.fazla_mesai_plani
set durum = 'onaylandi', karar_veren_id = pg_temp.kid('ahmet.er@atlastrafo.example.com'), karar_zamani = now(),
    karar_aciklama = 'Uygun'
where calisan_id = pg_temp.cid('3003') and is_gunu = '2026-11-20';

-- ---------------------------------------------------------------------
-- 7. Okutmalar (önce geçici tabloda üretilir, senaryolar uygulanır, sonra yazılır)
-- ---------------------------------------------------------------------
create temp table o (sicil text, tarih date, sistem text, okuyucu text, kart text,
                     zaman timestamptz, yon text) on commit drop;

with v as (
    select p.sicil, p.tarih, p.vardiya, c.dep, c.servis,
           (p.tarih + t.baslangic) at time zone 'Europe/Istanbul' as bas,
           ((p.tarih + case when t.bitis <= t.baslangic then 1 else 0 end) + t.bitis) at time zone 'Europe/Istanbul' as bit
    from p join c using (sicil) join pdks.vardiya_tanim t on t.kod = p.vardiya
), z0 as (
    -- Esnek mesai: giriş 08:00–09:30 arası, günde ortalama 9 saat (net 8 saat) kalır
    select v.*,
           case when vardiya = 'ESNEK'
                then (tarih + time '08:00') at time zone 'Europe/Istanbul'
                     + make_interval(mins => pg_temp.sayi(sicil || tarih || 'g', 0, 90), secs => pg_temp.sayi(sicil || tarih || 'gs', 0, 59))
                else bas - make_interval(mins => pg_temp.sayi(sicil || tarih || 'g', 5, 20), secs => pg_temp.sayi(sicil || tarih || 'gs', 0, 59))
           end as pdks_giris
    from v
), z as (
    select z0.*,
           case when dep = 'Bobinaj' then 'PDKS-2' else 'PDKS-1' end as pdks_okuyucu,
           case when vardiya = 'ESNEK'
                then pdks_giris + make_interval(mins => 540 + pg_temp.sayi(sicil || tarih || 'c', -30, 30))
                else bit + make_interval(mins => pg_temp.sayi(sicil || tarih || 'c', 1, 12), secs => pg_temp.sayi(sicil || tarih || 'cs', 0, 59))
           end as pdks_cikis
    from z0
)
insert into o
select sicil, tarih, 'pdks', pdks_okuyucu, null, pdks_giris, 'giris' from z
union all
select sicil, tarih, 'pdks', pdks_okuyucu, null, pdks_cikis, 'cikis' from z
union all
select sicil, tarih, 'kapi', 'KAPI-1', null, pdks_giris - make_interval(mins => pg_temp.sayi(sicil || tarih || 'kg', 2, 6)), 'giris' from z
union all
select sicil, tarih, 'kapi', 'KAPI-1', null, pdks_cikis + make_interval(mins => pg_temp.sayi(sicil || tarih || 'kc', 2, 5)), 'cikis' from z
union all
select sicil, tarih, 'yemekhane', 'YMK-1', null,
       case when vardiya in ('GUNDUZ', 'GUNDUZ_8', 'BEYAZ', 'ESNEK') then (tarih + time '12:00') at time zone 'Europe/Istanbul'
            when vardiya = 'V1'      then (tarih + time '10:30') at time zone 'Europe/Istanbul'
            when vardiya = 'V2'      then (tarih + time '18:30') at time zone 'Europe/Istanbul'
            when vardiya = 'AKSAM_8' then (tarih + time '19:30') at time zone 'Europe/Istanbul'
            when vardiya = 'GECE_8'  then (tarih + time '03:00') at time zone 'Europe/Istanbul'
            else                          (tarih + 1 + time '02:00') at time zone 'Europe/Istanbul' end
       + make_interval(mins => pg_temp.sayi(sicil || tarih || 'y', 0, 40)), null from z
union all
select sicil, tarih, 'servis', servis, null, pdks_giris - make_interval(mins => pg_temp.sayi(sicil || tarih || 'sg', 18, 30)), 'giris'
from z where servis is not null
union all
select sicil, tarih, 'servis', servis, null, pdks_cikis + make_interval(mins => pg_temp.sayi(sicil || tarih || 'sc', 8, 14)), 'cikis'
from z where servis is not null;

-- Kart numaraları: asıl kart; Emre (1009) 12 Kasım'dan sonra yeni kartını kullanır
update o set kart = case when sicil = '1009' and tarih >= '2026-11-12' then 'K1009B' else 'K' || sicil end;

-- İzinli ve devamsız günlerde okutma yok
delete from o using pdks.izin i
where pg_temp.cid(o.sicil) = i.calisan_id and o.tarih between i.baslangic and i.bitis;
delete from o where sicil = '2009' and tarih = '2026-11-25';                         -- S19

-- Saatler bir zaman dilimiyle düzeltilir
create function pg_temp.saat(p_tarih date, p_saat time) returns timestamptz language sql immutable as $$
    select (p_tarih + p_saat) at time zone 'Europe/Istanbul' $$;

-- S1  Mehmet 3 Kasım: PDKS girişi yok, kapı girişi vardiyadan önce (kanıtla düzeltilir)
delete from o where sicil = '1002' and tarih = '2026-11-03' and sistem = 'pdks' and yon = 'giris';
-- S2  Ali 4 Kasım: PDKS girişi yok, kapı girişi vardiya başladıktan sonra (amire sorulur)
delete from o where sicil = '1003' and tarih = '2026-11-04' and sistem = 'pdks' and yon = 'giris';
update o set zaman = pg_temp.saat('2026-11-04', '08:25') where sicil = '1003' and tarih = '2026-11-04' and sistem = 'kapi' and yon = 'giris';
-- S3  Veli 5 Kasım: PDKS çıkışı yok, kapı çıkışı 17:12 (kanıttaki saat yazılır)
delete from o where sicil = '1004' and tarih = '2026-11-05' and sistem = 'pdks' and yon = 'cikis';
update o set zaman = pg_temp.saat('2026-11-05', '17:12') where sicil = '1004' and tarih = '2026-11-05' and sistem = 'kapi' and yon = 'cikis';
-- S4  Mustafa 5 Kasım: PDKS çıkışı yok, kanıt da yok (amire sorulur)
delete from o where sicil = '1005' and tarih = '2026-11-05' and yon = 'cikis';
-- S5  Hüseyin 6 Kasım: PDKS girişi 40 sn arayla iki kez okutuldu (mükerrer)
insert into o select sicil, tarih, sistem, okuyucu, kart, zaman + interval '40 seconds', yon
from o where sicil = '1006' and tarih = '2026-11-06' and sistem = 'pdks' and yon = 'giris';
-- S6  İbrahim 10 Kasım: kartını unuttu, gün boyu geçici kart GK-01 ile okuttu;
--     13:05'te asıl kartı kapıda okutuldu (kartı başkası kullanıyor olabilir)
update o set kart = 'GK-01' where sicil = '1007' and tarih = '2026-11-10';
insert into o values ('1007', '2026-11-10', 'kapi', 'KAPI-1', 'K1007', pg_temp.saat('2026-11-10', '13:05'), 'giris');
-- S7  Osman 11, 17 ve 19 Kasım: kartını unuttu, geçici kartla okuttu (ayda 3 kez)
update o set kart = 'GK-03' where sicil = '1008' and tarih in ('2026-11-11', '2026-11-17');
update o set kart = 'GK-01' where sicil = '1008' and tarih = '2026-11-19';
-- S8  Emre 12 Kasım: kartını kaybetti; o gün geçici kart, ertesi günden yeni kart.
--     16 Kasım'da iptal edilen eski kartı PDKS'de okutuldu
update o set kart = 'GK-04' where sicil = '1009' and tarih = '2026-11-12';
insert into o values ('1009', '2026-11-16', 'pdks', 'PDKS-1', 'K1009', pg_temp.saat('2026-11-16', '08:30'), 'giris');
-- S9  Burak 18 Kasım: geçici kart GK-02 aldı, iade etmedi
update o set kart = 'GK-02' where sicil = '1010' and tarih = '2026-11-18';
-- Geçici kartla gelinen günlerde serviste okutulacak kart yok (kart güvenlikten alınır)
delete from o where sistem = 'servis' and kart like 'GK-%';
-- S10 19 Kasım 05:30-09:30: Atölye PDKS (PDKS-2) arızalı, okutma düşmedi; kapı kayıtları var
delete from o where okuyucu = 'PDKS-2'
  and zaman >= pg_temp.saat('2026-11-19', '05:30') and zaman < pg_temp.saat('2026-11-19', '09:30');
-- S11 Kemal ve Murat 2-6 Kasım: iki kart aynı okuyucuda 3 sn arayla okutuldu (kart paylaşımı);
--     Murat kapıdan 35 dk geç girdi
update o m set zaman = k.zaman + interval '3 seconds'
from o k
where m.sicil = '2003' and k.sicil = '2002' and m.tarih = k.tarih and m.tarih between '2026-11-02' and '2026-11-06'
  and m.sistem = 'pdks' and k.sistem = 'pdks' and m.yon = 'giris' and k.yon = 'giris';
update o set zaman = pg_temp.saat(tarih, '06:35')
where sicil = '2003' and tarih between '2026-11-02' and '2026-11-06' and sistem = 'kapi' and yon = 'giris';
-- S14 Selin 9 Kasım geç geldi (08:35), 13 Kasım erken çıktı (16:20)
update o set zaman = pg_temp.saat('2026-11-09', '08:35') where sicil = '3002' and tarih = '2026-11-09' and sistem = 'pdks' and yon = 'giris';
update o set zaman = pg_temp.saat('2026-11-09', '08:31') where sicil = '3002' and tarih = '2026-11-09' and sistem = 'kapi' and yon = 'giris';
update o set zaman = pg_temp.saat('2026-11-09', '08:05') where sicil = '3002' and tarih = '2026-11-09' and sistem = 'servis' and yon = 'giris';
update o set zaman = pg_temp.saat('2026-11-13', '16:20') where sicil = '3002' and tarih = '2026-11-13' and sistem = 'pdks' and yon = 'cikis';
update o set zaman = pg_temp.saat('2026-11-13', '16:23') where sicil = '3002' and tarih = '2026-11-13' and sistem = 'kapi' and yon = 'cikis';
delete from o where sicil = '3002' and tarih = '2026-11-13' and sistem = 'servis' and yon = 'cikis';
-- S15 Gizem 20 Kasım: onaylı 120 dk fazla mesai, 19:05'te çıktı
update o set zaman = pg_temp.saat('2026-11-20', '19:05') where sicil = '3003' and tarih = '2026-11-20' and sistem = 'pdks' and yon = 'cikis';
update o set zaman = pg_temp.saat('2026-11-20', '19:08') where sicil = '3003' and tarih = '2026-11-20' and sistem = 'kapi' and yon = 'cikis';
-- S16 Ece 23 Kasım: plansız fazla mesai, 19:30'da çıktı
update o set zaman = pg_temp.saat('2026-11-23', '19:30') where sicil = '3004' and tarih = '2026-11-23' and sistem = 'pdks' and yon = 'cikis';
update o set zaman = pg_temp.saat('2026-11-23', '19:33') where sicil = '3004' and tarih = '2026-11-23' and sistem = 'kapi' and yon = 'cikis';
update o set zaman = pg_temp.saat('2026-11-23', '19:42') where sicil = '3004' and tarih = '2026-11-23' and sistem = 'servis' and yon = 'cikis';
-- S17 Merve 24 Kasım: yazılı onayı yokken 18:40'a kadar çalıştı
update o set zaman = pg_temp.saat('2026-11-24', '18:40') where sicil = '3005' and tarih = '2026-11-24' and sistem = 'pdks' and yon = 'cikis';
update o set zaman = pg_temp.saat('2026-11-24', '18:43') where sicil = '3005' and tarih = '2026-11-24' and sistem = 'kapi' and yon = 'cikis';
-- S20 26 Kasım: sistemde olmayan kart (K9999) okutuldu
insert into o values (null, '2026-11-26', 'pdks', 'PDKS-1', 'K9999', pg_temp.saat('2026-11-26', '08:01'), 'giris');
-- S22 Montaj amiri Hasan 26 Kasım: PDKS girişi ve hiçbir kanıt yok (soru üst amirine gider)
delete from o where sicil = '1001' and tarih = '2026-11-26' and yon = 'giris';
-- S23 27 Kasım: kimseye zimmetli olmayan geçici kart GK-05 okutuldu
insert into o values (null, '2026-11-27', 'pdks', 'PDKS-1', 'GK-05', pg_temp.saat('2026-11-27', '08:10'), 'giris');
-- S25 Uğur (Bakım, YG Lab'a yetkili) 12 Kasım 10:15'te YG Test Lab kapısından geçti
insert into o values ('5303', '2026-11-12', 'kapi', 'YG-KAPI', 'K5303', pg_temp.saat('2026-11-12', '10:15'), 'giris');
-- S27 Selim (Depo, yetkisiz) 19 Kasım 14:10'da Boyahane kapısından geçti; Hakan (Boyahane) 09:00'da
insert into o values ('5402', '2026-11-19', 'kapi', 'BOYA-KAPI', 'K5402', pg_temp.saat('2026-11-19', '14:10'), 'giris'),
                     ('5202', '2026-11-19', 'kapi', 'BOYA-KAPI', 'K5202', pg_temp.saat('2026-11-19', '09:00'), 'giris');
-- S32 İrem (esnek) 18 Kasım: PDKS girişi yok, kapı girişi 09:12
delete from o where sicil = '6202' and tarih = '2026-11-18' and sistem = 'pdks' and yon = 'giris';
update o set zaman = pg_temp.saat('2026-11-18', '09:12') where sicil = '6202' and tarih = '2026-11-18' and sistem = 'kapi' and yon = 'giris';

-- ---------------------------------------------------------------------
-- 8. Kart iptali (S8) ve geçici kartlar
-- ---------------------------------------------------------------------
update pdks.kart set durum = 'iptal', iptal_nedeni = 'kayip', iptal_zamani = pg_temp.saat('2026-11-12', '09:00'),
                     iptal_eden_id = pg_temp.kid('elif.sen@atlastrafo.example.com')
where kart_no = 'K1009';
insert into pdks.kart (kart_no, calisan_id, verilis_tarihi) values ('K1009B', pg_temp.cid('1009'), '2026-11-12');

insert into pdks.gecici_kart (kart_no) values ('GK-01'), ('GK-02'), ('GK-03'), ('GK-04'), ('GK-05');

-- Her zimmet verilir, akşam iade alınır (GK-02 iade edilmedi: S9)
do $$
declare
    r record;
    v_id bigint;
begin
    for r in select * from (values
            ('GK-01', '1007', date '2026-11-10', time '07:25', 'Kartını evde unuttu'),
            ('GK-03', '1008', date '2026-11-11', time '07:25', 'Kartını evde unuttu'),
            ('GK-04', '1009', date '2026-11-12', time '07:25', 'Kartını kaybetti'),
            ('GK-03', '1008', date '2026-11-17', time '07:25', 'Kartını evde unuttu'),
            ('GK-02', '1010', date '2026-11-18', time '07:25', 'Kartını evde unuttu'),
            ('GK-01', '1008', date '2026-11-19', time '07:25', 'Kartını evde unuttu')) v(kart, sicil, gun, saat, aciklama)
        order by gun
    loop
        insert into pdks.gecici_kart_zimmet (gecici_kart_id, calisan_id, verilis_zamani, veren_id, aciklama)
        values ((select id from pdks.gecici_kart where kart_no = r.kart), pg_temp.cid(r.sicil),
                pg_temp.saat(r.gun, r.saat), pg_temp.kid('recep.bayram@atlastrafo.example.com'), r.aciklama)
        returning id into v_id;
        if r.kart <> 'GK-02' then
            update pdks.gecici_kart_zimmet
            set iade_zamani = pg_temp.saat(r.gun, '17:25'), iade_alan_id = pg_temp.kid('recep.bayram@atlastrafo.example.com')
            where id = v_id;
        end if;
    end loop;
end $$;

-- ---------------------------------------------------------------------
-- 9. Dosya aktarımları: her kaynak için günde bir dosya
--    S21: 27 Kasım servis dosyası gelmedi
-- ---------------------------------------------------------------------
--    1 Aralık: yalnızca PDKS ve kapı (30 Kasım gece vardiyalarının sabaha kadarki okutmaları;
--    bu dosyalar olmadan 30 Kasım'ın V2 / V3 / 16-24 vardiyaları işlenemez)
insert into pdks.aktarim (kaynak, dosya_adi, dosya_ozeti, veri_tarihi, satir_sayisi, aktarim_zamani)
select k, k || '_' || to_char(g, 'YYYYMMDD') || '.csv', md5(k || g::date), g::date,
       (select count(*) from o where o.sistem = k and (o.zaman at time zone 'Europe/Istanbul')::date = g::date),
       (g::date + 1 + time '00:30') at time zone 'Europe/Istanbul'
from unnest(array['pdks', 'kapi', 'yemekhane', 'servis']) k,
     generate_series(date '2026-11-01', date '2026-12-01', interval '1 day') g
where not (k = 'servis' and g::date = '2026-11-27')
  and not (k in ('yemekhane', 'servis') and g::date = '2026-12-01');

delete from o where sistem = 'servis' and (zaman at time zone 'Europe/Istanbul')::date = '2026-11-27';

insert into pdks.ham_okutma (aktarim_id, okuyucu_id, kart_no, okutma_zamani, yon)
select a.id, r.id, o.kart, o.zaman, o.yon
from o
join pdks.okuyucu r on r.kod = o.okuyucu
join pdks.aktarim a on a.kaynak = 'pdks' and a.veri_tarihi = (o.zaman at time zone 'Europe/Istanbul')::date
where o.sistem = 'pdks'
order by o.zaman;

insert into pdks.kanit_kaydi (aktarim_id, okuyucu_id, kaynak, kart_no, okutma_zamani, yon)
select a.id, r.id, o.sistem, o.kart, o.zaman, o.yon
from o
join pdks.okuyucu r on r.kod = o.okuyucu
join pdks.aktarim a on a.kaynak = o.sistem and a.veri_tarihi = (o.zaman at time zone 'Europe/Istanbul')::date
where o.sistem <> 'pdks'
order by o.zaman;

-- ---------------------------------------------------------------------
-- 10. Supabase Auth'ta açılmış demo hesaplarını kullanıcılara bağla
--     (Hesaplar sonradan açılırsa bu komut tek başına yeniden çalıştırılır.)
-- ---------------------------------------------------------------------
update pdks.kullanici k
set auth_kullanici_id = u.id
from auth.users u
where lower(u.email) = lower(k.eposta) and k.auth_kullanici_id is null;

commit;
