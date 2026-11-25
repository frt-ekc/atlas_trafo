-- =====================================================================
-- Canlı kurulum: yalnızca YAPI (seed'siz)
--   resmi tatiller (2026), 19 departman, okuyucular, İSG bölgeleri ve bölge kapıları.
-- Çalışan, kullanıcı, kart, plan ve okutma YOK: onlar scripts/sentetik_veri.mjs --kurulum çıktısıyla
-- (yukle.sql) gelir. Bölge yetkileri de oradadır: yetkiyi veren kullanıcı zorunlu bir alandır.
-- Vardiya tanımları, ayarlar ve 2027 arifeleri migration'lardan gelir.
-- Sıra: migration'lar → bu dosya → yukle.sql (docs/canli_kurulum.md).
-- Boş olmayan veritabanında hiçbir şey yazmadan durur. Adlar seed.sql ile birebir aynıdır.
-- =====================================================================
begin;

do $$
begin
    if exists (select 1 from pdks.departman) or exists (select 1 from pdks.calisan) or exists (select 1 from pdks.okuyucu) then
        raise exception 'Veritabanı boş değil (departman, çalışan ya da okuyucu var); işlem yapılmadı.';
    end if;
end $$;

-- 1. Resmi tatiller (2026). Arifeler migration'la gelmiş olabilir.
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

-- 2. Departmanlar
insert into pdks.departman (ad, yaka) values
    ('Aktif Kısım ve Montaj',                  'mavi'),
    ('Bobinaj',                                'mavi'),
    ('Kalite Kontrol ve YG Test Laboratuvarı', 'mavi'),
    ('İdari İşler',                            'mavi'),
    ('Nüve Dizme',                             'mavi'),
    ('Kazan İmalat ve Kaynak',                 'mavi'),
    ('Boyahane ve Yüzey İşlem',                'mavi'),
    ('Bakım ve Onarım',                        'mavi'),
    ('Depo ve Sevkiyat',                       'mavi'),
    ('Ar-Ge ve Tasarım',                       'beyaz'),
    ('Üretim Planlama',                        'beyaz'),
    ('Satış ve Pazarlama',                     'beyaz'),
    ('Dış Ticaret ve Lojistik',                'beyaz'),
    ('Satın Alma',                             'beyaz'),
    ('İnsan Kaynakları',                       'beyaz'),
    ('İSG',                                    'beyaz'),
    ('Finans ve Muhasebe',                     'beyaz'),
    ('Bilgi İşlem',                            'beyaz'),
    ('Üst Yönetim',                            'beyaz');

-- 3. İSG bölgeleri
insert into pdks.bolge (kod, ad) values
    ('YG-LAB',   'Yüksek Gerilim Test Laboratuvarı'),
    ('BOYAHANE', 'Boyahane');

-- 4. Okuyucular (son iki satır bölge kapısıdır)
insert into pdks.okuyucu (kod, ad, sistem, konum, bolge_id) values
    ('PDKS-1',    'Ana giriş PDKS',          'pdks',      'İdari bina girişi',              null),
    ('PDKS-2',    'Atölye PDKS',             'pdks',      'Bobinaj atölyesi girişi',        null),
    ('PDKS-3',    'Kazan-Nüve atölye PDKS',  'pdks',      'Kazan ve nüve atölyesi girişi',  null),
    ('KAPI-1',    'Ana kapı turnike',        'kapi',      'Fabrika ana kapısı',             null),
    ('KAPI-2',    'Personel kapısı turnike', 'kapi',      'Fabrika arka personel kapısı',   null),
    ('YMK-1',     'Yemekhane',               'yemekhane', 'Yemekhane girişi',               null),
    ('SRV-1',     'Servis 1 (Bornova)',      'servis',    'Servis aracı',                   null),
    ('SRV-2',     'Servis 2 (Buca)',         'servis',    'Servis aracı',                   null),
    ('SRV-3',     'Servis 3 (Karşıyaka)',    'servis',    'Servis aracı',                   null),
    ('SRV-4',     'Servis 4 (Çiğli)',        'servis',    'Servis aracı',                   null),
    ('SRV-5',     'Servis 5 (Menemen)',      'servis',    'Servis aracı',                   null),
    ('SRV-6',     'Servis 6 (Kemalpaşa)',    'servis',    'Servis aracı',                   null),
    ('SRV-7',     'Servis 7 (Torbalı)',      'servis',    'Servis aracı',                   null),
    ('YG-KAPI',   'YG Test Lab kapısı',      'kapi',      'Kalite binası', (select id from pdks.bolge where kod = 'YG-LAB')),
    ('BOYA-KAPI', 'Boyahane kapısı',         'kapi',      'Boyahane',      (select id from pdks.bolge where kod = 'BOYAHANE'));

commit;
