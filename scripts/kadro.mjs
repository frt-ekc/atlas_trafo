// Seed'siz canlı kurulumun kadrosu: sisteme giren 25 kişi (scripts/sentetik_veri.mjs --kurulum).
// Ad, soyad, departman, rol, e-posta ve görev supabase/seed.sql ile aynıdır (yalnızca Elif Şen ve Ahmet Er
// seed'de İdari İşler'de, burada İnsan Kaynakları'ndadır); kişiler uydurmadır.
// Sicil burada yazılmaz: işe giriş tarihinden ve sabit tohumdan üretilir (hep aynı çıkar).
// Doğum yılı yalnızca işe girişteki yaşın gerçekçi olduğunu gösterir; dosyaya ve veritabanına yazılmaz (KVKK).
// amiri: amiri olduğu departman.
const E = "@atlastrafo.example.com";
const kisi = (ad, soyad, departman, rol, eposta, gorev, ise_giris, dogum, amiri = null) =>
  ({ ad, soyad, departman, rol, eposta: eposta + E, gorev, ise_giris, dogum, amiri });
const amir = (ad, soyad, departman, eposta, gorev, ise_giris, dogum) =>
  kisi(ad, soyad, departman, "amir", eposta, gorev, ise_giris, dogum, departman);

export const KADRO = [
  // Yönetim
  amir("Rıza", "Kalkan", "Üst Yönetim", "riza.kalkan", "Genel müdür", "1998-03-09", 1964),
  amir("Levent", "Sarı", "İdari İşler", "levent.sari", "Üretim müdürü", "2001-09-03", 1971),
  kisi("Nur", "Tekin", "İdari İşler", "yonetici", "nur.tekin", "Fabrika müdürü", "2003-05-12", 1973),
  // İK, güvenlik, İSG, sistem
  kisi("Ahmet", "Er", "İnsan Kaynakları", "ik", "ahmet.er", "İK müdürü", "2005-04-04", 1977),
  kisi("Elif", "Şen", "İnsan Kaynakları", "ik", "elif.sen", "İK uzmanı", "2015-02-09", 1989),
  kisi("Recep", "Bayram", "İdari İşler", "guvenlik", "recep.bayram", "Güvenlik görevlisi", "2012-10-15", 1980),
  amir("Mert", "Alkan", "İSG", "mert.alkan", "İSG amiri", "2014-06-16", 1986),
  kisi("Tuba", "Erkoç", "İSG", "isg", "tuba.erkoc", "İSG uzmanı", "2018-09-10", 1992),
  amir("Tamer", "Oğuz", "Bilgi İşlem", "tamer.oguz", "Bilgi işlem amiri", "2011-02-14", 1983),
  kisi("Alper", "Çınar", "Bilgi İşlem", "admin", "alper.cinar", "Sistem yöneticisi", "2017-05-08", 1991),
  // Mavi yaka departman amirleri
  amir("Hasan", "Yılmaz", "Aktif Kısım ve Montaj", "hasan.yilmaz", "Montaj amiri (Bobinaj vekili)", "2004-06-07", 1978),
  amir("Serkan", "Öztürk", "Bobinaj", "serkan.ozturk", "Bobinaj amiri", "2006-03-06", 1979),
  amir("Zeynep", "Acar", "Kalite Kontrol ve YG Test Laboratuvarı", "zeynep.acar", "Kalite amiri", "2009-09-14", 1983),
  amir("Barış", "Yalçın", "Nüve Dizme", "baris.yalcin", "Nüve amiri", "2010-05-03", 1984),
  amir("Sinan", "Güler", "Kazan İmalat ve Kaynak", "sinan.guler", "Kazan amiri", "2007-11-05", 1981),
  amir("Cengiz", "Sezer", "Boyahane ve Yüzey İşlem", "cengiz.sezer", "Boyahane amiri", "2005-08-15", 1976),
  amir("Volkan", "Şimşek", "Bakım ve Onarım", "volkan.simsek", "Bakım amiri", "2008-02-11", 1982),
  amir("Ramazan", "Çetin", "Depo ve Sevkiyat", "ramazan.cetin", "Depo amiri", "2003-10-06", 1975),
  // Beyaz yaka departman amirleri
  amir("Aylin", "Kaplan", "Ar-Ge ve Tasarım", "aylin.kaplan", "Ar-Ge amiri", "2011-07-04", 1984),
  amir("Cansu", "Akın", "Üretim Planlama", "cansu.akin", "Planlama amiri", "2013-03-11", 1987),
  amir("Serdar", "Coşkun", "Satış ve Pazarlama", "serdar.coskun", "Satış amiri", "2010-10-11", 1982),
  amir("Gamze", "Yüksel", "Dış Ticaret ve Lojistik", "gamze.yuksel", "Dış ticaret amiri", "2012-04-16", 1985),
  amir("Nihat", "Uysal", "Satın Alma", "nihat.uysal", "Satın alma amiri", "2006-09-18", 1978),
  amir("Filiz", "Oral", "İnsan Kaynakları", "filiz.oral", "İnsan kaynakları amiri", "2009-01-12", 1981),
  amir("Hülya", "Gündoğdu", "Finans ve Muhasebe", "hulya.gundogdu", "Finans amiri", "2008-06-02", 1980),
];

// Üst amirler (seed ile aynı): mavi yaka amirleri üretim müdürüne, beyaz yaka amirleri genel müdüre bağlı
export const MAVI_UST_AMIR = `levent.sari${E}`;
export const BEYAZ_UST_AMIR = `riza.kalkan${E}`;
export const BOBINAJ_VEKILI = `hasan.yilmaz${E}`;
