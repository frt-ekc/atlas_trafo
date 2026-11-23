# Örnek veri (Kasım 2026)

`supabase/seed.sql` demo için **sahte** bir ay üretir. Kişiler, kartlar ve okutmalar uydurmadır; gerçek Atlas Trafo verisi içermez.

Seed yalnızca gece işinin işleyeceği **girdileri** yazar: organizasyon, kullanıcılar, kartlar, vardiya planı, izinler, fazla mesai onay ve planları, geçici kart zimmetleri, PDKS / kapı / yemekhane / servis okutmaları. Gün kayıtlarını, düzeltmeleri, amir sorularını ve uyarıları **gece işi** üretir.

Veri her çalıştırmada aynı çıkar: saatler rastgele değil, sicil ve tarihten türetilir.

## Yükleme

```bash
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/seed.sql
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/ornek_veri_testi.sql   # 59 kontrol (Kasım'ı gece işinden de geçirir, sonda geri alır)
```

Seed ikinci kez çalıştırılırsa hiçbir şey yazmadan durur. Yerelde `supabase db reset` seed'i kendisi yükler.

## Organizasyon

| Departman | Yaka | Çalışanlar | Vardiya |
|---|---|---|---|
| Aktif Kısım ve Montaj | mavi | 1001–1010 | Gündüz 08:00–17:00 |
| Bobinaj | mavi | 2001 (amir, gündüz); A: 2002–2004, B: 2005–2007, C: 2008–2010 | Gruplar haftalık döner: V1 06–14, V2 14–22, V3 22–06 |
| Kalite Kontrol ve YG Test Laboratuvarı | mavi | 3001–3005 | Gündüz 08:00–17:00 |
| İdari İşler | mavi | 4001–4006 | Gündüz 08:00–17:00 |
| Nüve Dizme | mavi | 5001 (amir); 5002, 5003 | Amir 08–16; işçiler 08–16 / 16–24 / 00–08 haftalık dönüşümlü |
| Kazan İmalat ve Kaynak | mavi | 5101 (amir); 5102, 5103 | Amir 08–16; işçiler 08–16 / 16–24 / 00–08 haftalık dönüşümlü |
| Boyahane ve Yüzey İşlem | mavi | 5201–5203 | 08–16 |
| Bakım ve Onarım | mavi | 5301–5303 | 08–16 |
| Depo ve Sevkiyat | mavi | 5401–5403 | 08–16 |
| Ar-Ge ve Tasarım | beyaz | 6001 (amir); 6002, 6003 | Amir 08:30–18:00; çalışanlar esnek mesai |
| Üretim Planlama | beyaz | 6101–6103 | 08:30–18:00 |
| Satış ve Pazarlama | beyaz | 6201 (amir); 6202, 6203 | Amir 08:30–18:00; çalışanlar esnek mesai |
| Dış Ticaret ve Lojistik | beyaz | 6301–6303 | 08:30–18:00 |
| Satın Alma | beyaz | 6401–6403 | 08:30–18:00 |
| İnsan Kaynakları | beyaz | 6501–6503 | 08:30–18:00 |
| İSG | beyaz | 6601–6603 | 08:30–18:00 |
| Finans ve Muhasebe | beyaz | 6701–6703 | 08:30–18:00 |
| Bilgi İşlem | beyaz | 6801–6803 | 08:30–18:00 |
| Üst Yönetim | beyaz | 6901–6903 | 08:30–18:00 |

76 çalışan, 77 kart, 19 departman (9 mavi, 10 beyaz yaka). Hafta içi her gün herkesin vardiya planı var (2–30 Kasım); ayrıca iki Pazar planı (S29, S30) ve demo günü 7 Aralık için yalnızca Montaj'ın 10 kişisinin planı (okutmaları `demo/` klasöründeki CSV'lerle demoda yüklenir, bkz. `docs/demo_akisi.md`). Her kaynaktan Kasım'ın her günü için bir dosya, ayrıca 1 Aralık için PDKS ve kapı dosyası var: 30 Kasım'ın gece vardiyaları (V2, V3, 16–24) 1 Aralık sabahı biter ve bu dosyalar olmadan işlenemez. Her departmanın amiri grubun ilk siciliyle başlar (İdari İşler'in amiri üretim müdürü Levent Sarı). Mavi yaka amirlerinin üst amiri üretim müdürü, beyaz yaka amirlerinin üst amiri genel müdür Rıza Kalkan (6901). Esnek mesaili çalışanlar 08:00–09:30 arasında gelir, günde ortalama 9 saat kalır. Bobinaj atölye PDKS'sini (PDKS-2), diğer herkes ana giriş PDKS'sini (PDKS-1) kullanır. Herkes kapı turnikesinden geçer ve yemekhanede okutur; bazı çalışanlar servisle gelir (SRV-1, SRV-2).

## Demo hesapları

Hesaplar Supabase Auth'ta (Authentication → Add user) aşağıdaki e-postalarla açılır; şifreyi açan kişi belirler. Seed bu hesapları e-posta üzerinden `kullanici` tablosuna bağlar. Hesaplar seed'den sonra açılırsa `seed.sql`'in son komutu (10. bölüm) tek başına yeniden çalıştırılır.

| E-posta | Kişi (sicil) | Rol | Ne görür |
|---|---|---|---|
| `elif.sen@atlastrafo.example.com` | Elif Şen (4001) | ik | Her şey |
| `ahmet.er@atlastrafo.example.com` | Ahmet Er (4002) | ik | Her şey; Elif'in kendi kayıtlarını o işler |
| `hasan.yilmaz@atlastrafo.example.com` | Hasan Yılmaz (1001) | amir | Montaj; ayrıca Bobinaj'ın vekil amiri |
| `serkan.ozturk@atlastrafo.example.com` | Serkan Öztürk (2001) | amir | Bobinaj |
| `zeynep.acar@atlastrafo.example.com` | Zeynep Acar (3001) | amir | Kalite |
| `levent.sari@atlastrafo.example.com` | Levent Sarı (4006) | amir | İdari; üç amirin üst amiri |
| `recep.bayram@atlastrafo.example.com` | Recep Bayram (4003) | guvenlik | Çalışan listesi, geçici kartlar |
| `nur.tekin@atlastrafo.example.com` | Nur Tekin (4004) | yonetici | Her şey (yalnızca okur) |
| `tuba.erkoc@atlastrafo.example.com` | Tuba Erkoç (6602) | isg | Çalışan listesi, departmanlar, İSG belgeleri, bölge yetkileri, İSG / bölge uyarıları |
| `alper.cinar@atlastrafo.example.com` | Alper Çınar (6802) | admin | Kullanıcılar, çalışan listesi, ayarlar, okuyucular, gece işi durumu; çalışan kayıtlarını (gün kaydı, izin, puantaj) görmez |

Yeni departmanların amirleri (`baris.yalcin@atlastrafo.example.com`, `aylin.kaplan@atlastrafo.example.com` … `riza.kalkan@atlastrafo.example.com`) de `kullanici` tablosunda tanımlıdır; sorular onlara gider. Demo için Auth hesabı açmak zorunlu değildir.

## İSG

Bölgeler: Yüksek Gerilim Test Laboratuvarı (kapı okuyucusu `YG-KAPI`) ve Boyahane (`BOYA-KAPI`). YG Test Lab'a Kalite Kontrol ve YG Test Laboratuvarı ile Bakım ve Onarım, Boyahane'ye Boyahane ve Yüzey İşlem ile Bakım ve Onarım girebilir. Mavi yakadaki 46 çalışanın hepsinin İSG eğitimi ve sağlık muayenesi kaydı var. Bitişler 2027'de; iki bilerek konmuş istisna var: Uğur Keskin'in (5303) İSG eğitimi 10 Kasım'da doldu (S25), Taner Yazıcı'nın (5302) sağlık muayenesi 15 Aralık'ta doluyor (S26).

## Bilerek konmuş durumlar

| # | Kim, ne zaman | Ne oldu | Sorun | Beklenen sonuç |
|---|---|---|---|---|
| S1 | Mehmet Kaya (1002), 3 Kas | PDKS girişi yok, kapı girişi 08:00'den önce | 1 | Gece işi kanıtla düzeltir |
| S2 | Ali Demir (1003), 4 Kas | PDKS girişi yok, kapı girişi 08:25 | 1 | Kanıt vardiya başından sonra: amire soru (`kanit_vardiya_sonrasi`) |
| S3 | Veli Çelik (1004), 5 Kas | PDKS çıkışı yok, kapı çıkışı 17:12 | 2 | Çıkış 17:12 olarak yazılır |
| S4 | Mustafa Şahin (1005), 5 Kas | Çıkışa dair hiçbir okutma yok | 2 | Amire soru (`cikis_yok`) |
| S5 | Hüseyin Aydın (1006), 6 Kas | PDKS girişi 40 sn arayla iki kez | 3 | İkincisi `mukerrer` işaretlenir |
| S6 | İbrahim Arslan (1007), 10 Kas | Kartını unuttu, gün boyu geçici kart GK-01; 13:05'te asıl kartı kapıda okutuldu | 4 | Okutmalar İbrahim'e yazılır; `gecici_kart_cakisma` uyarısı |
| S7 | Osman Doğan (1008), 11, 17, 19 Kas | Ayda 3 kez geçici kart (hepsi akşam iade edildi) | 4 | `sik_kart_unutma` bilgisi |
| S8 | Emre Koç (1009), 12 Kas | Kartını kaybetti; o gün geçici kart, sonra yeni kart (K1009B). 16 Kas'ta iptal edilmiş eski kartı okutuldu | 4 | Eski kart okutması iptal kart olarak işaretlenir |
| S9 | Burak Kurt (1010), 18 Kas | Geçici kart GK-02'yi iade etmedi; ertesi gün asıl kartını kullandı | 4 | `gecici_kart_iade_edilmedi` ve `gecici_kart_cakisma` uyarıları |
| S10 | Atölye PDKS (PDKS-2), 19 Kas 05:30–09:30 | Okuyucu çalışmadı; kapı kayıtları var | 5 | Arıza şüphesi; girişler kapı kaydıyla düzeltilir |
| S11 | Kemal Aslan (2002) ve Murat Polat (2003), 2–6 Kas | İki kart aynı okuyucuda 3 sn arayla; Murat kapıdan 35 dk geç girdi | 6 | `kart_paylasim_suphesi` (karar İK'da) |
| S12 | Cem Erdoğan (2004), 16 Kas | V3: giriş 16 Kas 21:50 civarı, çıkış 17 Kas 06:00 sonrası | 7 | Tek iş günü (16 Kas) olarak hesaplanır |
| S13 | Okan Yıldız (2005), 13 Kas | V3 yerine V2'de çalıştı; plan ertesi gün geriye dönük düzeltildi | 8 | Plan İK onayı bekliyor; gün onaya kadar işlenmez (Kasım gece işinden sonra 1597 gün kaydı). Onaylanınca gün hemen V2'ye göre oluşur |
| S14 | Selin Uçar (3002), 9 ve 13 Kas | 9 Kas 08:35'te girdi; 13 Kas 16:20'de çıktı | 9 | Geç kalma 35 dk, erken çıkış 40 dk |
| S15 | Gizem Korkmaz (3003), 20 Kas | Onaylı 120 dk fazla mesai, 19:05'te çıktı | 10 | Planlı fazla mesai |
| S16 | Ece Ateş (3004), 23 Kas | Plansız, 19:30'a kadar kaldı | 10 | `fm_plansiz_calisma` uyarısı, karar İK'da |
| S17 | Merve Yücel (3005), 24 Kas | Yazılı fazla mesai onayı yokken 18:40'a kadar kaldı | 10 | `fm_onay_yok` uyarısı |
| S18 | Can Kılıç (2007) 23–25 Kas; Deniz Aksoy (2008) 26–27 Kas | Rapor / yıllık izin, okutma yok | 14 | Can'ın rapor günleri `raporlu`, Deniz'in yıllık izin günleri `izinli`. Amirin izin türünü görmemesi hedeflenir; bugün amir türü kısmen görebiliyor (T-12) |
| S19 | Kaan Bulut (2009), 25 Kas | Planı var, izni ve hiçbir okutması yok | 13 | Amire soru (`hic_kayit_yok`); devamsızlık kararı İK'da |
| S20 | 26 Kas 08:01, PDKS-1 | Sistemde olmayan kart (K9999) | 3 | Bilinmeyen kart olarak işaretlenir |
| S21 | 27 Kas | Servis dosyası gelmedi | 16 | `dosya_gelmedi` uyarısı |
| S22 | Hasan Yılmaz (1001, Montaj amiri), 26 Kas | Girişine dair hiçbir okutma yok | 13 | Soru kendisine değil üst amiri Levent Sarı'ya gider (görevler ayrılığı) |
| S23 | 27 Kas 08:10, PDKS-1 | Kimseye zimmetli olmayan geçici kart GK-05 | 4 | `gecici_kart_zimmetsiz` uyarısı |
| S24 | Ferhat Kara (5002), 17 Kas (00–08); Gökhan Tuna (5003), 2–6 Kas (16–24) | Ferhat 16 Kas 23:39'da girdi, 17 Kas 08:09'da çıktı; Gökhan her gün gece yarısından sonra çıktı | 7 | Ferhat: tek iş günü (17 Kas), mola 60 dk, gece çalışması 315 dk. Gökhan: gün girişin olduğu güne yazılır |
| S25 | Uğur Keskin (5303, Bakım), 12 Kas 10:15 | İSG eğitimi 10 Kas'ta doldu; YG Test Lab kapısından geçti (Bakım'ın yetkisi var) | İSG | Bir kez `isg_belgesi_suresi_dolmus` (dolmadan önce `_doluyor` da); kapı açık, bölge uyarısı yok |
| S26 | Taner Yazıcı (5302, Bakım) | Sağlık muayenesi 15 Ara'da doluyor | İSG | 15 Kas'tan itibaren `isg_belgesi_suresi_doluyor` |
| S27 | Selim Ünal (5402, Depo) 19 Kas 14:10; Hakan Ekinci (5202, Boyahane) 09:00 | İkisi de Boyahane kapısından geçti | İSG | Selim'e `yetkisiz_bolge_okutmasi`, Hakan'a yok |
| S28 | Ece Ateş (S16), Merve Yücel (S17), Erkan Duman (S30) | Onaysız fazla mesai | 10 | İK Fazla mesai ekranında 3 bekleyen havuz kaydı: 150, 100 ve 485 dk (tatil çalışması) |
| S29 | Mehmet Kaya (1002), 22 Kas Pazar | Yazılı onayı var; Gündüz planıyla çalıştı | 10 | FM100 480 dk, puantaj kodu FM100 |
| S30 | Erkan Duman (5102), 29 Kas Pazar | Yazılı onayı yok; 08–16 planıyla çalıştı | 10 | FM100 0; süre havuzda `tatil_calismasi`, karar İK'da |
| S31 | Onur Baysal (6002), İrem Toprak (6202) | Esnek mesai | — | Ay sonu fark: Onur −152 dk, İrem +29 dk |
| S32 | İrem Toprak (6202), 18 Kas | Esnek; PDKS girişi yok, kapı girişi 09:12 | 1 | Giriş 09:17 (kanıt + yürüme payı), amire soru yok |

Ayrıca Derya Özkan (4005) 16 Kasım'da mazeret izinlidir.

"Beklenen sonuç" sütunu, Kasım gece işinden geçtikten sonra ekranda görülecek sonuçtur; S24–S32 ve açık soruların yalnızca S2, S4, S19, S22 olduğu `ornek_veri_testi.sql`'de denetlenir. Seed'de ileri tarihli geçici kart zimmeti yoktur (en geç 19 Kasım): ileri tarihli bir zimmet canlıda o kartın ya da kişinin bugün kart almasını engeller.
