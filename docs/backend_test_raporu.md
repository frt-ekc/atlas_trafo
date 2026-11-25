# Backend Test Raporu — Atlas Trafo PDKS

> Not: Bu rapordaki kullanıcı e-postaları testin yapıldığı tarihteki adreslerdir (rol@example.com). 22 Kasım'da adresler ad.soyad@atlastrafo.example.com biçimine çevrildi; eşleme için docs/demo_akisi.md → Demo kullanıcıları.

Plan: `BACKEND_TEST_PLANI.md` · Ortam: yalnızca yerel Supabase (`supabase db reset`), canlıya bağlanılmadı.
Deneme sorguları ve ham çıktılar `scratch/` klasöründe (git'e girmez).

---

## Özet ve düzeltme planı (Adım 14, 22 Kasım 2026)

> Bu bölüm raporun tamamından derlendi. Ayrıntı, kanıt ve "Sade dille" açıklamaları her bulgunun kendi başlığında, adımların içinde.
> Düzeltmeler `docs/duzeltme_rehberi.md`'deki 8 adımla yürütülür (Yusuf; PR'ları Fırat inceler ve birleştirir).

### Rapor için özet paragraf
Veritabanını (backend) 13 adımda, yalnızca yerel Supabase'te ve sahte veriyle test ettik. Kapsam:
- 31 migration, 117 fonksiyon, 59 tetikleyici, 9 görünüm ve RLS politikaları;
- 117 fonksiyon × 8 oturum yetki matrisi, 35 tablo + 9 görünüm × 8 oturum RLS matrisi (352 hücre);
- 32 örnek veri senaryosu ve 7 Aralık demo akışı.

Her fonksiyonu ekranın çağırdığı RPC ile ve ilgili rolün kullanıcısıyla (rol taklidi) çağırdık; son sürüm kodunu veritabanından okuduk. Yalnızca 8–13. adımlarda 940'tan fazla çağrı yapıldı, her biri sonda geri alındı. Yeni bulunan her sorun için Kasım ayı uçtan uca oynandı: gece işi, amir soruları, İK kararları, itirazlar, fazla mesai havuzu, ay kilidi, sonraki aya fark satırı ve ERP aktarımı.

104 bulgu çıktı (103'ü test adımlarında, T-104 ekran PR'larının incelemesinde): 1 Kritik, 17 Yüksek, 33 Orta, 34 Düşük, 19 Görüş. Kritik bulgu (ekrandan dosya yüklenemiyordu, T-31) test sırasında düzeltildi (PR #35). Ekran tarafında T-37 ve T-38 düzeltildi (PR #40, #37); T-34 ve T-89'un ekran tarafı düzeltildi, veritabanı tarafı açık (PR #40, #39). Bulgular 16 kök neden grubunda toplandı; 25 Kasım'a kadar düzeltilip canlı kurulumdan önce `main`'e alınması planlandı. Kalanlar ya düzeltme listesinde ya da "Bilinen sınırlılıklar" bölümünde.

### Güncel özet tablo

| Önem | Toplam | Açık | Düzeltildi | Öneri: düzelt | Öneri: sınırlılık / belge |
|---|---:|---:|---:|---:|---:|
| Kritik | 1 | 0 | 1 | — | — |
| Yüksek | 19 | 2 | 17 (T-12, T-13, T-28, T-39, T-45, T-47, T-56, T-57, T-65, T-71, T-72, T-74, T-89, T-90, T-104, T-106, T-108) | 2 | 0 |
| Orta | 33 | 29 | 4 (T-33, T-38, T-59, T-62) | 21 | 8 |
| Düşük | 34 | 30 | 4 (T-37, T-05, T-22, T-103) | 20 | 13 |
| Görüş | 19 | 17 | 2 (T-04, T-101) | 7 | 10 |
| **Toplam** | **106** | **78** | **28** | **50** | **31** |

"Açık" sütununda T-34 (Düşük) de var: ekran tarafı düzeltildi, veritabanı tarafı açık.

**Tutarlılık denetimi (22 Kasım):**
- Her bulgunun önemi başlığında, adım sonundaki "Bulgular önem sırasıyla" listesinde ve metindeki atıflarda aynı (otomatik karşılaştırma: 0 fark).
- Numaralar T-01'den T-106'ya kadar; atlanan ve tekrar eden yok (T-107 planlanan kart paylaşımı kanıt kuralına ayrıldı). T-104, 22 Kasım'daki ekran PR'larının (#37, #39–#41) incelemesinde bulundu (raporun sonundaki "PR incelemesi" bölümü).
- Adımlar raporda 1 → 13 sırasıyla duruyor; Endpoint testi 6 ile 7 arasında.
- Numaralar adım sırasında değil: Adım 10, 11'den sonra yapıldığı için Adım 9'da T-76–78, Adım 11'de T-79–80, Adım 10'da T-81–88 var. Bu bilinçli; numara değiştirilmedi.

**Yüksek bulgular (19):** T-12, T-13, T-28, T-39, T-45, T-46, T-47, T-56, T-57, T-65, T-71, T-72, T-74, T-79, T-89, T-90, T-104, T-106, T-108.

### Kök neden grupları

Her grup için **tek düzeltme önerisi**. Grup içinde Yüksek olanlar 25 Kasım'a kadar; kalanı 26 Kasım – 3 Aralık arasında, zaman kalırsa. Bir bulgu birden fazla gruba dokunuyorsa **asıl** grubunda sayıldı, diğer grupta "bağlantı" olarak anıldı.

#### K1 · UTC tarihi — T-45, T-59, T-04 · en yüksek: Yüksek · **ilk iş (öğretici)**
- **Kök:** `current_date` / `now()::date` oturumun saat diliminde (UTC) çalışıyor. İstanbul 00:00–03:00 arasında dünün tarihi kullanılıyor. Bağlantı: T-45'in altındaki "Adım 10 notu" (`v_isg_durum`), "T-45 bağlantısı" (`fazla_mesai_plani_kontrol`).
- **Tek düzeltme:** Gün gerektiren her yerde `(now() at time zone 'Europe/Istanbul')::date` (T-45 öneri tablosunun ilk altı satırı). Kalıcı test, oturumu `set timezone = 'UTC'` yapıp sabit bir saatle (ör. `02:30+03`) çalışır (T-04).
- **Neden ilk iş:** Tek bir kalıp, birkaç fonksiyonda aynı değişiklik, kolay yazılan bir test. Yusuf migration → test → `db reset` → rapor işaretleme → PR döngüsünü riski düşük bir işle öğrenir.

#### K2 · Soru ne zaman açılır, kime gider, ne zaman kapanır — T-39, T-40, T-41, T-42, T-32, T-44, T-19, T-23, T-43, T-98 · en yüksek: Yüksek
- **Kök:** Soru yaşam döngüsü üç ayrı yerden yönetiliyor (gece işi, `soru_cevapla` / `soru_ik_karari`, `kayit_duzelt`) ve "son karar İK'dadır" kuralı kodda tek yerde değil. Bağlantı: T-46 (izin, K5), T-70 (pasif amir, K7), T-90 (kodsuz gün, K3).
- **Tek düzeltme:** `pdks.soru_kapat(soru, neden, kapatan)` adında tek bir kapatma yolu ve dört kural:
  1. Üst amir de süresinde cevaplamazsa soru İK'ya gider; İK her açık soruya karar verebilir (T-39).
  2. İK'nın `kayit_duzelt`'i, izin girişi (T-46) ve sonradan gelen kanıt (T-42) o günün açık sorusunu bu yolla kapatır. Kapanmış güne amir cevabı saat yazamaz (T-40).
  3. Cevap soru türünün gerektirdiği saatleri istemeli (T-41; ekranda da Gökalp).
  4. Karar sütunları ayrı tutulur; amirin cevabı silinmez (T-32), aleyhe saat işaretlenir (T-44).
- **Sınırlılık:** T-19 ve T-23 (geç gelen dosya, işlenmiş günü yeniden işlemiyor). İşletme kuralıyla çözülür: "Dört dosya yüklenir, gece işi en son çalışır." T-43 (vekile devir) ve T-98 (panelde soru sayısı).

#### K3 · Ay kilidi ve puantaj — T-89, T-90, T-91, T-92, T-93, T-95, T-96, T-101, T-26, T-97 · en yüksek: Yüksek
- **Kök:** `ay_kilitle` "ne zaman kilitlenebilir" ve "kilitte ne kalıyor" sorularını tam sormuyor ve cevabını saklamıyor. Puantaj satırı ile gün kodları aynı günü farklı kurallarla sayıyor.
- **Tek düzeltme:** `ay_kilit_on_kontrol(yil, ay)` adında yalnızca okuyan bir fonksiyon; `ay_kilitle` bunu kullanır.
  - Ay bitmeden kilit yok (T-89).
  - Kodsuz kalacak gün engel sayılır ve zorlamayla geçilirse listesi tutulur (T-90, T-101).
  - Zorla kilit gerekçe ister; özet `donem` satırına yazılır (T-92).
  - Bütün engeller tek seferde döner (T-96; ekran Gökalp).
- **Aynı PR'da:** `v_puantaj_canli`'de çalışılan gün `durum = 'tamam' and hesap_tamam` (T-91). Kilitli ayda plan onayı reddedilir (T-93). Yalnızca kodu değişen fark da satır olarak yazılır (T-95).
- **Sınırlılık:** T-26 (kilitli ayda işlenmemiş gün gece işinde "hatalı"), T-97 (sistem yolunda kilitli döneme satır ekleme).

#### K4 · Havuz ve fazla mesai kontrolleri — T-56, T-57, T-79, T-58, T-61, T-62, T-63, T-76, T-102, T-60, T-64, T-77, T-78 · en yüksek: Yüksek
- **Kök:** Fazla mesai kuralları (yazılı onay, 11 saat, 270 saat) yalnızca **plan** yolunda denetleniyor; **havuz** yolu, tatil çalışması ve planı olmayan gün bu denetimden geçmiyor.
- **Tek düzeltme:** `fm_denetle(calisan, gun, dakika, yol)` adında tek bir denetim fonksiyonu.
  - Plan talebi, plan onayı ve havuz onayı aynı fonksiyonu çağırır: yazılı onay (T-56), günlük sınır (T-58), yıllık sınıra havuz ve FM100 dahil (T-57).
  - Geçmiş güne plan talebi reddedilir (T-76).
  - Planı olmayan günde okutma "plansız gün çalışması" uyarısı ve havuz kaydı üretir (T-79).
- **Aynı grupta:**
  - Sonradan onaylanan plan günü yeniden hesaplar (T-61).
  - `v_fazla_mesai_yillik` havuzu da sayar (T-62).
  - Bekleyen FM talebi kilitte engel ya da uyarı olur (T-63, K3 ile).
  - Reddedilen tatil çalışmasının kodu netleşir: öneri HT (T-102, İK kararı).
  - Geri alınan yazılı onay aynı yıl yenilenebilir (T-60).
- **Karar / sınırlılık:** T-64 (11 saate mola dahil), T-77 (15 dk eşiği; mevzuat kontrol edilecek), T-78 (Pazar planı İK onayı istemiyor). Üçü İK ile konuşulup belgeye yazılır.

#### K5 · İzin ve plan kuralları — T-46, T-47, T-48, T-49, T-50, T-94, T-54 · en yüksek: Yüksek
- **Kök:** `izin_gir` yalnızca satır ekliyor; günle, başka izinle, kilitli ayla ve plansız günle ilişkisini denetlemiyor.
- **Tek düzeltme:** `izin_gir` içinde (ya da `izin` tetikleyicisinde) dört kontrol ve bir eylem:
  - Çakışan geçerli izin varsa ret (T-47).
  - Kilitli aya ret (T-48).
  - İşlenmiş güne izin girilirse gün izinli olarak yeniden yazılır ve açık soru `soru_kapat` ile kapanır (T-46, K2).
  - Puantajda gün kaydı olmayan izin günü izin koduyla kodlanır, HT değil (T-94).
- **Aynı grupta:** Geriye dönük plan eski planı saklar, ret onu geri getirir (T-49). `saatlik_izin_iptal` (T-50). İzinli günde okutma uyarısı (T-54).

#### K6 · Admin yetkileri, ayarlar ve iz — T-71, T-72, T-74, T-33, T-80, T-82, T-09, T-10, T-73, T-100 · en yüksek: Yüksek
- **Kök:** Kullanıcı, rol ve ayar değişiklikleri tek kişinin elinde ve izsiz. Hesabın kime ait olduğu ve çalışanın aktifliği oturumda denetlenmiyor.
- **Tek düzeltme:**
  - `kullanici_gecmisi` ve `kart` için `tanimlayan_id` ile iz (T-33, T-82).
  - `oturum_kullanici_id` bağlı çalışanın aktif olmasını şart koşar; `kullanici_guncelle` çıkmış çalışanın hesabını açmaz (T-71).
  - `ik` / `admin` rolü verme iki adımlı: admin önerir, farklı bir İK kullanıcısı onaylar (T-72).
  - `ayar` tablosuna `en_az` / `en_cok`; yasal sınırlar yasa değerini aşamaz (T-74).
  - Admin `calisan`'da yalnızca sicil, ad, soyad ve departman görür (T-80; karar verildi). CLAUDE.md'deki cümle buna göre düzeltilir (Fırat).
- **Sınırlılık:** T-09 (canlıda sign-up kapalı), T-10 (ayar yetkisi admin'de; T-74'teki aralıklar, iz ve İK uyarısı yeterli kabul edilir), T-73 (üst amir döngüsü), T-100 (kilitten sonra ayar değişince fark; T-74 ve belgeyle).

#### K7 · İşe giriş ve işten çıkış — T-65, T-66, T-67, T-68, T-69, T-70, T-75 · en yüksek: Yüksek
- **Kök:** `isten_cikis_gir` çıkışın sonuçlarını kendi içinde tek tek elle yapıyor; çalışan tarihlerini ise diğer fonksiyonlar hiç denetlemiyor.
- **Tek düzeltme:** `calisan_calisiyor_mu(calisan, gun)` adında ortak bir yardımcı.
  - `vardiya_plani_gir`, `izin_gir`, `kart_tanimla`, `gecici_kart_ver` ve `itiraz_gir` bunu çağırır (T-68, T-69).
  - `isten_cikis_gir` çıkıştan sonraki okutmayı `ham_okutma` üzerinden arar (T-65).
  - Çıkış kilitli ayın planlarını silmez (T-67).
  - Departman amiri ise önce yeni amir istenir ya da İK'ya uyarı yazılır (T-70).
- **Aynı grupta:** `calisan_ekle`'de tarih aralığı ve büyük/küçük harfe duyarsız sicil (T-75).
- **Sınırlılık:** T-66 (yanlış çıkış geri alınamaz). Prosedür belgelenir: yanlış çıkışı yalnızca veritabanı yöneticisi, kayıtlı bir düzeltmeyle geri alır.

#### K8 · Veri aktarımı ve gece işi — T-13, T-17, T-18, T-21, T-31, T-20, T-24, T-25, T-99 · en yüksek: Yüksek (T-31 Kritik, düzeltildi)
- **Kök:** `dosya_yukle` dosyanın kimden ve hangi güne ait olduğunu yeterince denetlemiyor.
- **Tek düzeltme (karar verildi):**
  - Yükleyen `aktarim`'e yazılır ve yönetici listesinde görünür (T-13).
  - Satır tarihi dosya günü ya da ertesi gün olmalı; kilitli ay reddedilir (T-17).
  - İleri tarihli satır ve ileri tarihli gece işi yok (T-18).
  - Hata mesajı girdiyi kısaltır (T-21).
- **Sınırlılık:**
  - T-13'ün kalan kısmı: gerçek kurulumda aktarım bir sistem hesabıyla yapılır.
  - T-20: özet istemciden geliyor; satırlar zaten tekil.
  - T-24: 2000 kişide ekrandan gece işi 8 sn sınırına takılır. Gerçek kurulumda pg_cron SQL'de çalışır; ekran düğmesi tek gün içindir.
  - T-25: bir çalışanın hatası bütün günü durduruyor.
  - T-99 (varsayım, karar verildi): PDKS kayıtları saniyeli gelir; gerçek kurulumda teyit edilir.

#### K9 · Gizlilik ve görevler ayrılığı (RLS) — T-12, T-106, T-15, T-14 · en yüksek: Yüksek
- **Tek düzeltme (karar verildi):** Amire özel, gerekçeyi ve izin türünü gizleyen bir düzeltme görünümü (T-12). "Raporlu" durumunun amire görünmesi bilinçli kabul edilir ve belgelenir. İK'nın soru kararındaki gerekçe de amire gizlidir; amir yalnızca sonucu görür (T-106). `itiraz_incelemeye_al`'da görevler ayrılığı (T-15).
- **Sınırlılık:** T-14 (vekillik tarihi yok; vekil her zaman yetkili).

#### K10 · Hesap kuralları — T-28, T-27, T-29, T-30 · en yüksek: Yüksek
- **Tek düzeltme:**
  - Arife günü 13:00'ten sonrası tatil (karar verildi). Vardiya bitişi arifede 13:00'e çekilir; 13:00 sonrası onaylı çalışma FM100 olur (T-28).
  - Tolerans saniyesiyle karşılaştırılır (T-27).
  - Mükerrer çıkışta son okutma tutulur (T-29).
- **Sınırlılık:** T-30 (giriş çıkıştan sonra gelirse amire soru gidiyor; amir doğru cevaplar).

#### K11 · Kart, geçici kart ve İSG — T-81, T-84, T-86, T-87, T-85, T-36, T-83, T-88 · en yüksek: Orta
- **Tek düzeltme (zaman kalırsa):**
  - Kart paylaşımı için İK kararı kaydı (`kart_paylasim_inceleme`: var / yok, gerekçe, günler) (T-81).
  - Zimmet tetikleyicisi ileri tarihi ve tutarsız iadeyi reddeder (T-84).
  - Kart mesajları Türkçe; iptal nedeni zorunlu (T-86).
  - İSG'de en geç biten belge geçerli; tarih aralığı (T-87).
  - Geçici kartı "kayıp" yapan fonksiyon (T-85).
- **Sınırlılık:** T-36 (kart biçimi gerçek kurulumda öğrenilir), T-83 (zimmet şimdiki saatle girilir), T-88 (İSG uyarısı bölgeye bakmıyor).

#### K12 · İtiraz ve arıza — T-34, T-51, T-35, T-52, T-53, T-55 · en yüksek: Düşük
- **Tek düzeltme:**
  - Düzeltmeye bağlanan itiraz aynı çalışanın, aynı günün ve kabul edilmiş itirazı olmalı (T-34).
  - Aynı güne ikinci açık itiraz reddedilir (T-51).
  - İncelemeye alma ve arıza kararına "kim, ne zaman" yazılır (T-35, zaman kalırsa).
- **Sınırlılık:** T-52 (düzeltmesiz kabul edilen itiraz izlenmiyor), T-53 (`ariza_kaniti_yok` üretilmiyor), T-55 (arıza süre tutarlılığı).

#### K13 · Hata mesajları — T-37 (✅ PR #40), T-16 · en yüksek: Düşük
- **Tek düzeltme:** Ekran, PostgreSQL'in kendi hata kodlarını (23505, 23503, 23514, 22P02) sade Türkçe cümleye çevirir (T-37, Gökalp). Sık görülen kısıt hataları fonksiyonun içinde Türkçe `raise` ile önden yakalanır (T-16, Yusuf). T-21, T-75 ve T-86'nın mesaj kısımları da bununla kapanır.

#### K14 · Şema ve altyapı — T-01, T-02, T-03, T-06, T-08 · en yüksek: Orta
- **Tek düzeltme (zaman kalırsa):** Tek migration'da `search_path`'e `pg_temp` (T-03), `alter default privileges … revoke execute from public` (T-08) ve 55 yabancı anahtar index'i (T-02).
- **Sınırlılık:** T-01 (tablo sahibi `gun_kaydi`'nın bazı alanlarını izsiz değiştirebilir; CLAUDE.md ile `veritabani.md` kural 3 aynı kapsama indirilir), T-06 (`auth.users` yabancı anahtarı yok).

#### K15 · Belge ve ekran — T-38 (✅ PR #37), T-07, T-11, T-05, T-22, T-103 · en yüksek (açık olanlar): Düşük
- **Tek düzeltme:**
  - İşe giriş ve işten çıkış ekranı (T-38, Gökalp): ✅ PR #37 ile yapıldı.
  - Ekrandaki eskimiş not (T-11, Gökalp).
  - `v_izin_amir` açıklaması (T-07, Yusuf).
  - README test sayısı (T-05), `ornek_veri.md` S18 (T-22) ve `demo_akisi.md`'nin üç eksiği (T-103). Mehmet, Fırat onayıyla.

#### K16 · Görünüm ve RLS hızı — T-104 · en yüksek: Yüksek · **demo öncesi**
- **Kök:** `security_invoker` görünümler (`v_esnek_mesai`, `v_departman_ozet`) amirin oturumunda RLS politikalarıyla çalışıyor; aynı sorgu RLS'siz 6 ms, amirde 1–4,4 saniye. Bağlantı: T-24 (gece işi hızı), T-02 (eksik index).
- **Tek düzeltme:** Ekranın okuduğu özet görünümleri, rolü ve departmanı bir kez çözen `security definer` fonksiyonlara çevir (ör. `pdks.departman_ozeti(yil, ay)`, `pdks.esnek_mesai_ozeti(yil, ay)`); ya da RLS politikalarındaki oturum fonksiyonlarını `(select pdks.oturum_...())` kalıbıyla bir kez değerlendirilir hale getir. Kalıcı test: amir oturumunda `explain analyze` süresi örnek veriyle 500 ms'nin altında.

### Düzeltme listesi

**Kime:** Yusuf = backend / veritabanı (rehberle) · Gökalp = ekran (GitHub issue) · Mehmet = rapor metni ve belge.

**1. Yüksek bulgular — 25 Kasım'a kadar `main`'de** (önerilen sıra; her satır ayrı küçük PR ve kalıcı test)

| Sıra | Grup | Bulgu(lar) | Önem | Kime | Tahmini süre | Not |
|---:|---|---|---|---|---|---|
| 1 | K1 | T-45 (+ T-59, T-04) | Yüksek | Yusuf | 3 saat | **İlk iş, öğretici.** Bir kalıp, birkaç fonksiyon, UTC testi |
| 2 | K16 | T-104 | Yüksek | Yusuf | 4 saat | **Demo öncesi.** Amirin Departmanlar sayfası 8 sn'de düşüyor; özet görünümleri fonksiyona çevir |
| 3 | K3 | T-89 | Yüksek | Yusuf | 1–2 saat | `ay_kilitle` başına tek kontrol. Canlıyı en çok koruyan değişiklik. Ekran tarafı PR #39 ile main'de; veritabanı tarafı açık |
| 4 | K3 | T-90 (+ T-101) | Yüksek | Yusuf | 4 saat | Kodsuz gün engel ve liste. Ekran (Gökalp) sonra |
| 5 | K2 | T-39 | Yüksek | Yusuf | 4 saat | İkinci eskalasyon İK'ya; İK her açık soruya karar verir |
| 6 | K6 | T-71 | Yüksek | Yusuf | 2 saat | `oturum_kullanici_id` + `kullanici_guncelle` |
| 7 | K6 | T-74 | Yüksek | Yusuf | 3 saat | `ayar.en_az` / `en_cok` + test |
| 8 | K4 | T-56 | Yüksek | Yusuf | 2 saat | Havuz onayında yazılı onay şartı |
| 9 | K5 | T-47 | Yüksek | Yusuf | 2 saat | Çakışan izin ret |
| 10 | K7 | T-65 | Yüksek | Yusuf | 2 saat | Çıkış kontrolü `ham_okutma` üzerinden |
| 11 | K5 | T-46 | Yüksek | Yusuf | 4 saat | İşlenmiş güne izin: gün yeniden yazılır, soru kapanır |
| 12 | K10 | T-28 | Yüksek | Yusuf | 4 saat | Arife 13:00 sonrası tatil |
| 13 | K9 | T-12 | Yüksek | Yusuf + Mehmet | 4 saat | Amire özel görünüm; "raporlu" belgelenir |
| 14 | K8 | T-13 (+ T-17, T-18) | Yüksek | Yusuf + Mehmet | 4 saat | Yükleyen `aktarim`'de; tarih kuralları; sınırlılık metni |
| 15 | K6 | T-33 + T-72 | Yüksek | Yusuf | 5 saat | `kullanici_gecmisi` + iki adımlı rol yükseltme |
| 16 | K4 | T-57 | Yüksek | Yusuf | 3 saat | Yıllık sınıra havuz ve FM100 |
| 17 | K4 | T-79 | Yüksek | Yusuf | 3 saat | Plansız gün çalışması: uyarı ve havuz |

- **Toplam:** yaklaşık 54 saat, yani 7 iş günü. 23–25 Kasım'a (3 gün) ancak günde 4–5 PR ile sığar.
- **Önerilen kesme çizgisi:** 1–11. sıra 25 Kasım'a kadar mutlaka (yaklaşık 31 saat; T-104 demo öncesi de olmalı). Bunlar veri bütünlüğünü, ay kilidini ve çalışan aleyhine sonuçları koruyor. 12–17. sıra sığmazsa 26 Kasım'dan sonra ikinci bir canlı güncellemeyle (Fırat) gider. O zamana kadar raporda "açık, düzeltiliyor" olarak kalır.
- Bu, planın "Yüksek'ler 25 Kasım'a kadar" kuralından bir sapmadır; kararı Fırat verir.

**2. Orta ve Düşük — 26 Kasım – 3 Aralık, zaman kalırsa** (grup sırasıyla; Yüksek'ten kalan grup parçaları önce)

| Sıra | Grup | Bulgular (öneri: düzelt) | En yüksek önem | Kime | Tahmini süre |
|---:|---|---|---|---|---|
| 18 | K2 | T-40, T-32, T-41, T-42, T-44 (`soru_kapat`) | Orta | Yusuf (+ Gökalp: T-41 ekranı) | 1 gün |
| 19 | K3 | T-91, T-92, T-93, T-95 | Orta | Yusuf (+ Gökalp: T-92, T-96 ekranı) | 1 gün |
| 20 | K4 | T-58, T-61, T-62, T-63, T-76, T-102, T-60 | Orta | Yusuf | 1,5 gün |
| 21 | K5 | T-48, T-49, T-50, T-94, T-54 | Orta | Yusuf | 1 gün |
| 22 | K7 | T-67, T-68, T-70, T-69, T-75 | Orta | Yusuf | 1 gün |
| 23 | K6 | T-82, T-80 | Orta | Yusuf (+ Fırat: CLAUDE.md) | 3 saat |
| 24 | K9 | T-15 | Düşük | Yusuf | 1 saat |
| 25 | K10 | T-27, T-29 | Düşük | Yusuf | 3 saat |
| 26 | K8 | T-21 | Düşük | Yusuf | 1 saat |
| 27 | K11 | T-84, T-86, T-87, T-85, T-81 | Orta | Yusuf (+ Gökalp: T-81 ekranı) | 1 gün |
| 28 | K12 | T-34 (veritabanı tarafı; ekranı PR #40), T-51, T-35 | Düşük | Yusuf | 3 saat |
| 29 | K13 | T-16 (T-37 ✅ PR #40) | Düşük | Yusuf | 2 saat |
| 30 | K14 | T-03, T-08, T-02 | Görüş | Yusuf | 3 saat |
| 31 | K15 | T-11 / T-07 / T-05, T-22, T-103 (T-38 ✅ PR #37) | Düşük | Gökalp / Yusuf / Mehmet | ekran 1 saat; belge 2 saat |

**3. Karar bekleyenler (İK ile, Fırat):**
- T-64: 11 saate mola dahil mi.
- T-77: 15 dk eşiği; mevzuat kontrol edilecek.
- T-78: Pazar planı İK onayı istesin mi.
- T-102: reddedilen tatil çalışmasının kodu.
- T-01: koruma mı, belge mi.

Karar çıkana kadar hepsi "Bilinen sınırlılıklar"da durur.

### Bulgu dizini (104)

Önem, adım ve kısa başlık bulgunun kendi başlığından alındı. "Grup" yukarıdaki kök neden grubu; "Öneri" düzeltme listesindeki karar.

| Bulgu | Önem | Adım | Kısa başlık | Grup | Kime | Öneri |
|---|---|---|---|---|---|---|
| T-01 | Orta | 1 | `gun_kaydi`'nda durum ve dakika alanları doğrudan, izsiz değiştirilebiliyor | K14 | Mehmet | Sınırlılık (+ belge eşitlenir) |
| T-02 | Görüş | 1 | 55 yabancı anahtar sütununda index yok | K14 | Yusuf | Düzelt (zaman kalırsa) |
| T-03 | Görüş | 1 | 45 `security definer` fonksiyonun `search_path`'inde `pg_temp` yok | K14 | Yusuf | Düzelt (zaman kalırsa) |
| T-04 | Görüş | 1 | Testler UTC davranışını sınamıyor | K1 | Yusuf | ✅ Düzeltildi (PR #46) |
| T-05 | Düşük | 1 | README'de işe giriş / işten çıkış test sayısı yanlış | K15 | Mehmet | Belge |
| T-06 | Görüş | 1 | `kullanici.auth_kullanici_id`'nin `auth.users`'a yabancı anahtarı yok | K14 | Mehmet | Sınırlılık (+ belge eşitlenir) |
| T-07 | Düşük | 1 | `v_izin_amir`'in açıklaması yok | K15 | Yusuf | Düzelt |
| T-08 | Görüş | 2 | `pdks`'te yeni oluşturulan fonksiyon herkese açık doğuyor | K14 | Yusuf | Düzelt (zaman kalırsa) |
| T-09 | Görüş | 2 | `ayar_al`, hesabı bağlı olmayan her oturuma açık | K6 | Mehmet | Sınırlılık |
| T-10 | Görüş | 2 | Puantajı etkileyen ayarları yalnızca admin, tek başına değiştirebiliyor | K6 | Mehmet | Sınırlılık |
| T-11 | Düşük | 2 | Ekrandaki "`v_fazla_mesai_yillik` çalışmıyor" notu eskimiş | K15 | Gökalp | Düzelt |
| T-12 | Yüksek | 3 | Amir izin türünü (rapor = sağlık bilgisi) üç yoldan görebiliyor | K9 | Yusuf + Mehmet | ✅ Düzeltildi (seçenek a, feature/T12-rapor-gizliligi) + belge |
| T-13 | Yüksek | 3 | İK, dosya yükleyerek kendi çalışılmış gününü üretebiliyor ve yükleyen kaydedilmiyor | K8 | Yusuf + Mehmet | ✅ Düzeltildi (feature/T13-yukleyen) + sınırlılık metni |
| T-14 | Orta | 3 | Vekil amir her zaman yetkili | K9 | — | Sınırlılık |
| T-15 | Düşük | 3 | İK kendi itirazını "incelemeye alabiliyor" | K9 | Yusuf | Düzelt |
| T-16 | Düşük | 3 | "Talep eden onaylayamaz" kuralı ham İngilizce hata mesajıyla dönüyor | K13 | Yusuf | Düzelt (zaman kalırsa) |
| T-17 | Orta | 4 | Satır tarihleri dosyanın günüyle karşılaştırılmıyor | K8 | Yusuf | Düzelt (karar verildi) |
| T-18 | Orta | 4 | İleri tarihli bir dosya, gece işinin gelecekteki bir gün için çalışmasına ve açık soruların… | K8 | Yusuf | Düzelt (karar verildi) |
| T-19 | Görüş | 4 | İşlenmiş bir güne sonradan gelen dosya sessizce yok sayılıyor | K2 | — | Sınırlılık |
| T-20 | Düşük | 4 | Dosya özeti istemciden geliyor | K8 | — | Sınırlılık |
| T-21 | Düşük | 4 | Hata mesajı kullanıcı girdisini kısaltmadan geri yansıtıyor | K8 | Yusuf | Düzelt |
| T-22 | Düşük | 5 | `docs/ornek_veri.md` S18'in beklenen sonucu veritabanıyla tutmuyor | K15 | Mehmet | Belge |
| T-23 | Orta | 5 | Kapı / servis dosyası PDKS'den sonra gelirse kanıt kullanılmıyor | K2 | — | Sınırlılık |
| T-24 | Orta | 5 | Gece işi 2000 çalışanda ekrandan çalışmıyor (8 saniye zaman aşımı) | K8 | — | Sınırlılık |
| T-25 | Düşük | 5 | Bir çalışanda çıkan hata o günün bütün çalışanlarını işlenmemiş bırakıyor | K8 | — | Sınırlılık |
| T-26 | Görüş | 5 | Kilitli aydaki işlenmemiş planlı gün için gece işi "hatalı" bitiyor | K3 | — | Sınırlılık |
| T-27 | Düşük | 6 | Tolerans saniyeleri atarak karşılaştırılıyor | K10 | Yusuf | Düzelt |
| T-28 | Yüksek | 6 | Yarım gün arife tam iş günü sayılıyor: öğleden sonra çıkana erken çıkış, çalışana FM100 yok | K10 | Yusuf | ✅ Düzeltildi (feature/T28-arife) |
| T-29 | Düşük | 6 | Mükerrer çıkışta ilk okutma tutuluyor, son okutma atılıyor | K10 | Yusuf | Düzelt (zaman kalırsa) |
| T-30 | Görüş | 6 | Giriş çıkıştan sonra gelirse amire "çıkış yok" soruluyor | K10 | — | Sınırlılık |
| T-31 | Kritik | Endpoint | `dosya_yukle` ekrandan (HTTP) hiç çalışmıyor: "UPDATE requires a WHERE clause" | K8 | Yusuf | Düzeltildi (PR #35) |
| T-32 | Orta | Endpoint | İK kararı, soruyu cevaplayan amirin adını siliyor | K2 | Yusuf | Düzelt |
| T-33 | Orta | Endpoint | Kullanıcı ekleme ve rol / aktiflik değişikliği iz bırakmıyor | K6 | Yusuf | ✅ Düzeltildi (feature/T72-rol-onayi) |
| T-34 | Düşük | Endpoint | Düzeltmeye başka çalışanın, başka günün ya da reddedilmiş bir itirazı bağlanabiliyor | K12 | Yusuf | Ekran ✅ PR #40; veritabanı: Düzelt |
| T-35 | Görüş | Endpoint | İtirazı incelemeye alma ve arıza kararında "kim, ne zaman" eksik | K12 | Yusuf | Düzelt (zaman kalırsa) |
| T-36 | Düşük | Endpoint | `kart_tanimla` kart numarasının biçimini denetlemiyor | K11 | — | Sınırlılık |
| T-37 | Düşük | Endpoint | Veri aktarımı formu veritabanı hatasını ham gösteriyor | K13 | Gökalp | ✅ Düzeltildi (PR #40) |
| T-38 | Orta | Endpoint | İşe giriş ve işten çıkış için ekran yok | K15 | Gökalp | ✅ Düzeltildi (PR #37) |
| T-39 | Yüksek | 7 | Üst amir de cevaplamazsa soru hiçbir zaman İK'ya gitmiyor | K2 | Yusuf | ✅ Düzeltildi (PR #55) |
| T-40 | Orta | 7 | İK'nın kayıt düzeltmesi açık soruyu kapatmıyor | K2 | Yusuf | Düzelt |
| T-41 | Orta | 7 | Tek saatli cevap günü askıda bırakıyor: soru kapanıyor, eksik saat için yeni soru açılmıyor | K2 | Yusuf + Gökalp | Düzelt |
| T-42 | Orta | 7 | Kanıt sonradan gelince açık soru kapanmıyor, üst amire eskale oluyor | K2 | Yusuf | Düzelt (zaman kalırsa) |
| T-43 | Düşük | 7 | Amir izne çıkınca önceden açılmış soruları vekile geçmiyor | K2 | — | Sınırlılık |
| T-44 | Görüş | 7 | Amirin girdiği aleyhe saat "çalışan aleyhine" işaretlenmiyor | K2 | Yusuf | Düzelt (zaman kalırsa) |
| T-45 | Yüksek | 8 | Geriye dönük plan kararı UTC tarihiyle veriliyor | K1 | Yusuf | ✅ Düzeltildi — PR #46 (kod), PR #47 (kilitli ay testi / canlı kontrol listesi) |
| T-46 | Yüksek | 8 | İşlenmiş güne girilen izin günü değiştirmiyor | K5 | Yusuf | Düzelt (25 Kas) |
| T-47 | Yüksek | 8 | Çakışan izinler reddedilmiyor | K5 | Yusuf | ✅ Düzeltildi (feature/T47-cakisan-izin) |
| T-48 | Orta | 8 | Kilitli aya izin girilebiliyor | K5 | Yusuf | Düzelt |
| T-49 | Orta | 8 | Geriye dönük plan geçerli planın üstüne yazılıyor | K5 | Yusuf | Düzelt |
| T-50 | Orta | 8 | Yanlış girilen saatlik izin geri alınamıyor | K5 | Yusuf | Düzelt |
| T-51 | Düşük | 8 | Aynı güne birden çok açık itiraz girilebiliyor | K12 | Yusuf | Düzelt |
| T-52 | Görüş | 8 | Kabul edilip düzeltmesi yapılmayan itiraz hiçbir yerde görünmüyor | K12 | — | Sınırlılık |
| T-53 | Düşük | 8 | `ariza_kaniti_yok` sorusu hiç üretilmiyor | K12 | — | Sınırlılık |
| T-54 | Görüş | 8 | İzinli günde okutma varsa gün sessizce "izinli" oluyor | K5 | Yusuf | Düzelt (zaman kalırsa) |
| T-55 | Düşük | 8 | Arıza kayıtlarında süre ve karar tutarlılığı denetlenmiyor | K12 | — | Sınırlılık |
| T-56 | Yüksek | 9 | İK, yazılı onayı olmayan çalışanın onaysız fazla mesaisini puantaja alabiliyor | K4 | Yusuf | ✅ Düzeltildi (feature/T56-havuz-yazili-onay) |
| T-57 | Yüksek | 9 | Yıllık 270 saat sınırı yalnızca planları sayıyor | K4 | Yusuf | ✅ Düzeltildi (feature/T57-yillik-toplam) |
| T-58 | Orta | 9 | Havuz onayında günlük 11 saat sınırı denetlenmiyor | K4 | Yusuf | Düzelt |
| T-59 | Orta | 9 | Yazılı onayın geri alınması bazı durumlarda hiç kaydedilemiyor | K1 | Yusuf | ✅ Düzeltildi — PR #46 (kod), PR #47 (kilitli ay testi / canlı kontrol listesi) |
| T-60 | Düşük | 9 | Onayını geri alan çalışan aynı yıl yeniden yazılı onay veremiyor | K4 | Yusuf | Düzelt (zaman kalırsa) |
| T-61 | Orta | 9 | İşlenmiş güne sonradan onaylanan fazla mesai planı günü yeniden hesaplamıyor | K4 | Yusuf | Düzelt |
| T-62 | Orta | 9 | `v_fazla_mesai_yillik` yalnızca planlı fazla mesaiyi gösteriyor | K4 | Yusuf | ✅ Düzeltildi (feature/T57-yillik-toplam, T-57 ile) |
| T-63 | Düşük | 9 | Kilitli ayda karar bekleyen fazla mesai talebi askıda kalıyor | K4 | Yusuf | Düzelt |
| T-64 | Görüş | 9 | Günlük 11 saat sınırı molayı da çalışma sayıyor | K4 | Mehmet | Sınırlılık (karar İK / mevzuat) |
| T-65 | Yüksek | 11 | Çıkış tarihinden sonraki okutma, gün henüz işlenmemişse ya da plansızsa fark edilmiyor | K7 | Yusuf | ✅ Düzeltildi (feature/T65-cikis-okutma) |
| T-66 | Orta | 11 | Yanlış girilen işten çıkış geri alınamıyor | K7 | Mehmet | Sınırlılık (+ prosedür) |
| T-67 | Orta | 11 | Çıkış kilitli aya düşerse kilitli ayın vardiya planları siliniyor | K7 | Yusuf | Düzelt |
| T-68 | Düşük | 11 | Çıkıştan sonra ve girişten önce plan, izin, kart ve geçici kart kabul ediliyor | K7 | Yusuf | Düzelt |
| T-69 | Düşük | 11 | Çıkıştan sonraki güne ait itiraz açık kalıyor | K7 | Yusuf | Düzelt (zaman kalırsa) |
| T-70 | Orta | 11 | Departman amirinin hesabı pasif olunca ya da rolü değişince yeni sorular ona açılmaya devam… | K7 | Yusuf | Düzelt |
| T-71 | Yüksek | 11 | Çıkmış çalışanın hesabı admin tarafından yeniden açılabiliyor | K6 | Yusuf | ✅ Düzeltildi (PR #56) |
| T-72 | Yüksek | 11 | Admin, başka bir çalışana bağlı bir İK (ya da admin) hesabı açarak görevler ayrılığını ve "a… | K6 | Yusuf | ✅ Düzeltildi (feature/T72-rol-onayi) |
| T-73 | Düşük | 11 | Üst amir zincirinde döngü ve amir olmayan üst amir kabul ediliyor | K6 | Mehmet | Sınırlılık |
| T-74 | Yüksek | 11 | Ayarlar için yalnızca "0'dan küçük olamaz" kontrolü var | K6 | Yusuf | ✅ Düzeltildi (feature/T74-ayar-sinirlari) |
| T-75 | Düşük | 11 | `calisan_ekle` ve `kart_tanimla`: tarih aralığı ve büyük/küçük harf kontrolü yok, kart hatal… | K7 | Yusuf | Düzelt (zaman kalırsa) |
| T-76 | Orta | 9 | Geçmiş, çalışılmış bir güne "planlı" fazla mesai talebi girilip onaylanabiliyor | K4 | Yusuf | Düzelt |
| T-77 | Orta | 9 | 15 dakikanın altındaki plansız çalışma hiçbir yere yazılmıyor | K4 | Mehmet | Sınırlılık (karar İK / mevzuat) |
| T-78 | Görüş | 9 | Pazar vardiyası amirin tek kararıyla FM100 oluyor | K4 | Mehmet | Sınırlılık (karar İK / mevzuat) |
| T-79 | Yüksek | 11 (Adım 10 betiğinde yeniden doğrulandı) | Planı olmayan günde (ör. Cumartesi) yapılan çalışma hiçbir yere yazılmıyor | K4 | Yusuf | Düzelt (25 Kas) |
| T-80 | Düşük | 11 (Adım 10 betiğinde yeniden doğrulandı) | Admin `calisan` tablosunun bütün satırlarını ve sütunlarını görüyor | K6 | Yusuf + Fırat (CLAUDE.md) | Düzelt (karar verildi) |
| T-81 | Orta | 10 | Kart paylaşımı şüphesinde karar verilemiyor | K11 | Yusuf + Gökalp | Düzelt (zaman kalırsa) |
| T-82 | Orta | 10 | İK kendine asıl kart tanımlayabiliyor | K6 | Yusuf | Düzelt |
| T-83 | Düşük | 10 | Geçici kart zimmeti yalnızca "şu an" girilebiliyor | K11 | — | Sınırlılık |
| T-84 | Düşük | 10 (Adım 8 şüphesi) | Sistem yolunda ileri tarihli zimmet ve ileri tarihli iade kabul ediliyor | K11 | Yusuf | Düzelt |
| T-85 | Düşük | 10 | Kaybolan geçici kart sistemde "kayıp" yapılamıyor | K11 | Yusuf | Düzelt (zaman kalırsa) |
| T-86 | Düşük | 10 | Kart ve geçici kart işlemlerinde ham ya da yanıltıcı mesajlar | K11 | Yusuf | Düzelt |
| T-87 | Düşük | 10 | İSG belgesinde "son girilen kayıt" geçerli sayılıyor | K11 | Yusuf | Düzelt |
| T-88 | Görüş | 10 | İSG uyarısı okutmanın nerede yapıldığına bakmıyor | K11 | — | Sınırlılık |
| T-89 | Yüksek | 12 | İleri bir ay kilitlenebiliyor | K3 | Yusuf | ✅ Düzeltildi — ekran PR #39, veritabanı PR #49 |
| T-90 | Yüksek | 12 | Askıdaki gün puantaja kodsuz giriyor ve hiçbir yerde görünmüyor | K3 | Yusuf | ✅ Düzeltildi (PR #54) |
| T-91 | Orta | 12 | Puantaj satırı ile gün kodları "tamam ama hesaplanmamış" günü farklı sayıyor | K3 | Yusuf | Düzelt |
| T-92 | Orta | 12 | Zorla kilidin izi yok: hangi engellerin geçildiği ve neden geçildiği saklanmıyor | K3 | Yusuf + Gökalp | Düzelt |
| T-93 | Orta | 12 | Kilitli ayda geriye dönük plan onayı fark satırına yalnızca kaybı yazıyor | K3 | Yusuf | Düzelt |
| T-94 | Orta | 12 | Planı olmayan güne düşen izin puantajda "HT" (hafta tatili) kodlanıyor | K5 | Yusuf | Düzelt |
| T-95 | Düşük | 12 | Yalnızca gün kodunu değiştiren fark kayboluyor | K3 | Yusuf | Düzelt (zaman kalırsa) |
| T-96 | Görüş | 12 | Kilit engelleri tek tek bildiriliyor | K3 | Gökalp + Yusuf | Düzelt (zaman kalırsa) |
| T-97 | Düşük | 12 | Sistem yolunda kilitli döneme sonradan puantaj satırı eklenebiliyor | K3 | — | Sınırlılık |
| T-98 | Düşük | 12 (ek) | Yönetici panelinde "açık soru" sayısı bakan kişiye göre değişiyor | K2 | — | Sınırlılık |
| T-99 | Orta | 12 (ek; Adım 12 şüphesinden) | Saniyesiz okutma zamanı kabul ediliyor | K8 | Mehmet | Sınırlılık (varsayım; karar verildi) |
| T-100 | Orta | 12 (ek; Adım 12 şüphesinden) | Fark hesabı kilitli ayın "önce" değerini bugünkü ayarla hesaplıyor | K6 | Mehmet | Sınırlılık |
| T-101 | Görüş | 12 (ek; Adım 12 şüphesinden) | Kilit, kodsuz kalan günlerin listesini vermiyor | K3 | Yusuf + Gökalp | ✅ Düzeltildi (PR #54, T-90 ile) |
| T-102 | Orta | 13 | Reddedilen tatil çalışması puantajda "FM100 1 gün / 0 dk" kodlanıyor | K4 | Yusuf | Düzelt |
| T-103 | Düşük | 13 | `docs/demo_akisi.md`'de üç eksik ya da belirsiz adım | K15 | Mehmet | Belge |
| T-104 | Yüksek | PR incelemesi | Amirin Departmanlar sayfası RLS'li görünümler yüzünden 8 sn'de zaman aşımına düşüyor | K16 | Yusuf | ✅ Düzeltildi (PR #48); kalan 46 politika ayrı iş |
| T-106 | Yüksek | T-12 düzeltmesi | İK'nın soru kararındaki gerekçe (sağlık bilgisi olabilir) amire açık | K9 | Fırat | ✅ Düzeltildi (feature/T106-ik-karar-gerekcesi) |
| T-108 | Yüksek | T-104 devamı | Oturum yardımcıları oturumu kendi içlerinde satır başına soruyor; amirin "çalışanlarım" listesi yarım saniye | K16 | Yusuf | ✅ Düzeltildi (PR #63) |

### Bilinen sınırlılıklar

Düzeltilmeyecek (ya da karar çıkana kadar böyle kalacak) konular. Proje raporuna doğrudan konabilecek sade cümlelerle:

- **Veritabanı sahibi bazı gün alanlarını izsiz değiştirebilir (T-01).** Uygulama ve ekranlar gün kaydına doğrudan yazamaz; yalnızca veritabanının sahibi (canlıda yalnızca proje sorumlusu) bazı alanları düzeltme kaydı bırakmadan değiştirebilir. Gerçek kurulumda bu erişim tek kişiyle sınırlıdır.
- **Giriş hesabı ile kullanıcı kaydı arasında veritabanı bağı yok (T-06).** Bağ e-postayla kuruluyor; silinen bir giriş hesabı kullanıcı kaydını kendiliğinden kapatmaz.
- **Ayarlar okunabilir (T-09).** Giriş yapmış ama sisteme bağlı olmayan bir hesap tolerans gibi ayarları okuyabilir. Canlıda yeni hesap açma kapalıdır; çalışan verisine erişim yoktur.
- **Ayarları sistem yöneticisi değiştirir (T-10, T-100).** Değişiklik `ayar_gecmisi`'nde izlenir. Her ayarın izin verilen aralığı vardır (`en_az` / `en_cok`); yasal sınırlar yasa değerini aşamaz ve puantajı etkileyen ayar değişince İK'ya uyarı gider (T-74). İK'nın ön onayı yoktur. Ay kilitlendikten sonra ayar değişirse, o aya sonradan gelen düzeltmenin farkı yeni ayarla hesaplanır. Bu yüzden ayarlar ay ortasında değil, ay başında değiştirilir.
- **Veri aktarımını yapan kişi (T-13).** Prototipte dosyaları İK elle yükler; yükleyen kaydedilir (`aktarim.yukleyen_id`) ve kendi okutmasını içeren dosyada diğer İK'ya uyarı gider. Okutmanın gerçekliği doğrulanmaz: İK başka bir çalışanın okutmasını uydurabilir, yalnızca izi kalır. Gerçek kurulumda dosyaları bir sistem hesabı otomatik yükler. T-13'ten önce yüklenmiş dosyalarda yükleyen boştur.
- **Vekil amir her zaman yetkilidir (T-14).** Vekillik için tarih aralığı tutulmaz; vekil atandığı sürece amirle aynı yetkiye sahiptir.
- **Geç gelen dosya (T-19, T-23).** Gece işi bir günü bir kez işler. Kapı, yemekhane ve servis dosyaları PDKS'den sonra yüklenirse o günün kanıtları kullanılmaz ve amire gereksiz soru gidebilir. İşletme kuralı: o günün dört dosyası yüklenir, gece işi en son çalışır.
- **Dosya özeti ekrandan gelir (T-20).** Aynı satırlar ikinci kez yazılmaz; ama aynı dosya farklı bir özetle "yeni dosya" gibi kaydedilebilir.
- **Gece işinin hızı (T-24, T-25).** 2000 çalışanda bir günün işlenmesi ekranın 8 saniyelik sınırını aşar. Gerçek kurulumda gece işi veritabanında zamanlanmış görev olarak çalışır; ekrandaki düğme demo ve tek gün içindir. Bir çalışanda çıkan hata o günü bütün çalışanlar için durdurur ve hata kaydı İK'ya görünür.
- **Kilitli aydaki işlenmemiş gün (T-26).** Böyle bir gün için gece işi "hatalı" biter. Ay zaten işlenmemiş planlı gün varken kilitlenemediği için normal akışta oluşmaz.
- **Giriş çıkıştan sonra okutulursa (T-30).** Sistem günü "çıkış yok" diye amire sorar; amirin cevabı günü düzeltir.
- **Kart numarası biçimi (T-36).** Kart numarasının biçimi denetlenmez. Gerçek kurulumda kartların biçimi öğrenilip eklenecek.
- **Vekile devir (T-43).** Amir izne çıkınca önceden açılmış sorular vekile geçmez. Süresi dolunca üst amire gider.
- **İtiraz ve arıza ayrıntıları (T-52, T-53, T-55).** Kabul edilip düzeltmesi yapılmamış itiraz ayrı listelenmez. Arızalı okuyucuda amire özel bir soru türü yerine olağan "giriş yok" sorusu gider. Arıza kayıtlarında süre tutarlılığı denetlenmez.
- **Fazla mesai kuralları için İK kararları (T-64, T-77, T-78).**
  - Günlük 11 saat sınırına mola dahil sayılır (yasadan katı).
  - 15 dakikanın altındaki plansız kalış fazla mesai incelemesine düşmez; Fazla Çalışma Yönetmeliği'ndeki yuvarlama kuralı ile mevzuat kontrol edilecek.
  - Pazar günü için girilen vardiya planı İK onayı istemez.
- **Yanlış girilen işten çıkış (T-66).** Sistemde geri alma yoktur; yalnızca veritabanı yöneticisi, kayıt altına alınan bir düzeltmeyle geri alabilir. Bu düzeltmenin adımları henüz yazılı bir prosedür değildir.
- **Üst amir zinciri (T-73).** Üst amir döngüsü ve amir olmayan üst amir denetlenmez; kullanıcıları sistem yöneticisi doğru tanımlar.
- **Geçici kart saati (T-83).** Geçici kart zimmeti kaydın girildiği andan başlar; geriye dönük zimmet girilemez. Kart önce sisteme kaydedilip sonra verilir.
- **İSG uyarısı (T-88).** Eğitimi ya da muayenesi dolmuş çalışanın okutması bir kez uyarı üretir; riskli bölgeye giriş ayrıca işaretlenmez. Kapı hiçbir durumda kilitlenmez (proje kararı).
- **Kilitli döneme sistem yoluyla satır (T-97).** Ekrandan yapılamaz; yalnızca veritabanı sahibi kilitli aya ek satır yazabilir.
- **Panelde açık soru sayısı (T-98).** Amir yönetici panelinde yalnızca kendisine atanmış açık soruları sayar; departmanın bütün açık soruları İK ve yönetici panelinde görünür.
- **PDKS saat biçimi (T-99, varsayım).** Sistem PDKS kayıtlarının saniyeli geldiğini varsayar. Kart paylaşımı denetimi saniyeye dayanır; gerçek kurulumda PDKS çıktısının biçimi teyit edilir.
- **"Raporlu" durumu amire API'den açık (T-12; karar verildi).** Amir ekibinin raporlu olduğunu bilir, nedenini bilmez (gün planlaması için). Gün kaydının durumu ve canlı puantajdaki raporlu gün sayısı amire API'den açıktır; ekranda "İzinli" görünür. Durum ve izin düzeltmelerinin gerekçesi artık gizlidir (`v_duzeltme_amir`). Saat düzeltmesinin gerekçesi amire açıktır; İK oraya sağlık bilgisi yazmamalıdır.
- **Yalnızca örnek veri (genel).** Bütün test sahte veriyle, yerel veritabanında yapıldı; gerçek Atlas Trafo verisiyle ve ekranlardan (HTTP) yük testi yapılmadı.

---

## Adım 1 — Kurulum, otomatik testler, şema yapısı (21 Kasım 2026)

Taban: `main` @ `15ee334` (PR #34 dahil) · 30 migration · 21 test dosyası.

### Sonuç tablosu

| # | Madde | Ne yaptım | Beklenen | Gerçekleşen | |
|---|---|---|---|---|---|
| 1 | Örnek veriyle kurulum | `supabase db reset` | Hatasız; migration sayısı | Çıkış kodu 0, günlükte hata yok; 30 migration uygulandı ve kayıt tablosunda 30 satır; 76 çalışan | ✅ |
| 2 | 21 test, örnek veriyle | Her dosya `psql -v ON_ERROR_STOP=1` | Hepsi GEÇTİ | 21 / 21 GEÇTİ (toplam 635 kontrol) | ✅ |
| 3 | 21 test, örnek verisiz | `db reset --no-seed`, sonra 21 dosya | `ornek_veri_testi` dışında hepsi | 20 / 21; yalnızca `ornek_veri_testi` kaldı ("Örnek veri yüklü değil") | ✅ |
| 4 | Arka arkaya iki tur, iz | Sıfırlamadan iki tur; önce/sonra her tablonun satır sayısı ve içerik md5 özeti | Sonuç ve veri değişmemeli | İki turda sonuçlar aynı (örnek veriyle ve verisiz). 35 tablonun sayı ve içerik özeti birebir aynı. `test` şeması kalmadı | ✅ |
| 5 | UTC'de testler | `PGTZ=UTC`, örnek veriyle ve verisiz | Hepsi geçmeli | Sonuçlar İstanbul turuyla aynı (21 / 21 ve 20 / 21). **Ama** 21 dosyanın 20'si oturum saat dilimini kendisi İstanbul'a sabitliyor; bu tur UTC davranışını sınamıyor (bkz. T-04) | ✅ (zayıf) |
| K1 | Tablo / view / fonksiyon / tetikleyici | `pg_tables`, `pg_views`, `pg_proc`, `pg_trigger` | 35 / 9 / 117 / 59 | 35 / 9 / 117 / 59 | ✅ |
| K2 | RLS kapalı tablo | `pg_class.relrowsecurity` | 0 | 0 | ✅ |
| K3 | RLS açık, politikası yok | `pg_policy` | 0 | 0 | ✅ |
| K4 | `anon`'un çalıştırabildiği fonksiyon | `has_function_privilege` | 0 | 0; PUBLIC'e açık fonksiyon da 0 | ✅ |
| K5 | `authenticated`'ın SELECT dışı tablo yetkisi | INSERT / UPDATE / DELETE / TRUNCATE / REFERENCES / TRIGGER | 0 | 0; `anon`'un hiçbir tablo yetkisi yok; sequence yetkisi yok | ✅ |
| K6 | `security definer` + sabit olmayan `search_path` | `proconfig` | 0 | 0 (46 definer fonksiyonun hepsinde sabit). 45'inde değer yalnızca `pdks`, `pg_temp` yok (bkz. T-03) | ✅ |
| K7 | `security_invoker` olmayan view | `reloptions` | Yalnızca bilinçli olanlar | Yalnızca `v_izin_amir` ve `v_saatlik_izin_amir` (nedenleri aşağıda) | ✅ |
| K8 | Değiştirilemez tablolar, `postgres` olarak | Her tabloya satır üretip UPDATE / DELETE / TRUNCATE | Hepsi hata | `ham_okutma`, `kanit_kaydi`, `aktarim`, `okutma_isareti`, `duzeltme`, `puantaj_satiri` (76 satırla): 18 denemenin 18'i "değiştirilemez ve silinemez" hatası verdi | ✅ |
| K9 | `gun_kaydi`'na doğrudan UPDATE | Giriş, durum, çalışan, dakika alanları ayrı ayrı | Hata | Giriş, çalışan / gün ve devamsızlığa giden durum engelleniyor; **durumun diğer geçişleri ve dakika alanları engellenmiyor, iz de kalmıyor** (T-01). DELETE ve TRUNCATE engelleniyor | ❌ |
| K10 | `_id` ile bitip yabancı anahtarı olmayan sütun | `information_schema` + `pg_constraint` | Listele | Yalnızca `kullanici.auth_kullanici_id` (bkz. T-06) | ✅ |
| K11 | Yabancı anahtar sütununda index | İlk anahtarı o sütun olan index | Eksikleri listele | 55 yabancı anahtar sütununda index yok (T-02) | ⚠️ |

**İki view neden `security_invoker` değil (bilinçli):** Amir `izin` ve `saatlik_izin` tablolarını RLS yüzünden göremez (politika yalnızca İK / yönetici). `v_izin_amir` ve `v_saatlik_izin_amir` sahibinin yetkisiyle çalışır, satırları içeride `tum_veriyi_gorur() or amirin_calisani_mi(calisan_id)` ile süzer ve izin türünü gizler (`'izinli'` / `'saatlik_izin'` sabit metni döner). Böylece amir kendi çalışanının izinli olduğunu görür, sağlık bilgisi olabilecek türü görmez. `security_invoker` olsalardı amir hiç satır göremezdi.

**Planda adı geçen fonksiyonlar:** `tolerans_uygula`, `mola_suresi`, `fazla_mesai_talep_et`, `ayar_iz` `pg_proc`'ta var.

### Bulgular

### T-01 · `gun_kaydi`'nda durum ve dakika alanları doğrudan, izsiz değiştirilebiliyor
- **Adım:** 1 · **Önem:** Orta
- **Yer:** `pdks.gun_kaydi_koru` tetikleyicisi (son sürüm: `20261114000200_kurallar.sql`)
- **Ne oldu:** Tablo sahibi (`postgres`) olarak doğrudan `UPDATE` ile:
  - Engellenenler (hata veriyor): `giris_zamani`, `cikis_zamani`, `vardiya_id`, `calisan_id`, `is_gunu` ve devamsızlığa giren ya da çıkan `durum`.
  - Engellenmeyenler: `durum`'un diğer geçişleri (`tamam` → `izinli`, `vardiya_yok`, `raporlu` …) ve bütün dakika alanları (`calisma_dk`, `fazla_mesai_dk`, `fm50_dk`, `fm100_dk`, `gec_kalma_dk`, `erken_cikis_dk`, `gece_calisma_dk`, `mola_dk`, `saatlik_izin_dk`). Bunlar hata vermeden değişiyor ve `duzeltme`'ye hiçbir satır yazılmıyor.
- **Ne olmalıydı:** CLAUDE.md §2 ve plan: "`gun_kaydi` doğrudan UPDATE edilmez; yalnızca `pdks.duzeltme_uygula(...)` ile değişir." `docs/veritabani.md` kural 3 ise korumayı yalnızca "giriş, çıkış, vardiya ya da devamsız" diye sınırlıyor; iki belge birbirini tutmuyor.
- **Kanıt:** `scratch/a1_degistirilemez_2.sql`, Veli Çelik (1004), 3 Kasım, işlem sonda geri alındı:
  ```
  önce:  (6945, tamam, 480, düzeltme=0)
  gun_kaydi|giris_zamani|HATA: giris_zamani alanı yalnızca pdks.duzeltme_uygula() ile değiştirilebilir.
  gun_kaydi|durum tamam→devamsiz|HATA: durum alanı yalnızca pdks.duzeltme_uygula() ile değiştirilebilir.
  gun_kaydi|calisan_id|HATA: Günlük kaydın çalışanı veya günü değiştirilemez.
  gun_kaydi|durum tamam→izinli|ÇALIŞTI
  gun_kaydi|calisma_dk=999|ÇALIŞTI
  sonra: (6945, izinli, 999, düzeltme=0)
  gun_kaydi UPDATE yetkisi: authenticated=false, anon=false, service_role=false, postgres=true
  ```
- **Sade dille:** Ekranlar ve uygulama bu tabloya yazamıyor, bu taraf güvenli. Ama veritabanına sahip olarak giren biri, örneğin SQL Editor'dan bir çalışanın gününü "izinli" yapabilir ya da çalışma dakikasını değiştirebilir. Bu değişiklik düzeltme kaydına geçmez, yani kimin ne zaman neden yaptığı bilinmez. Puantaj ve maaş bu alanlardan hesaplandığı için iz bırakmayan bir maaş değişikliği mümkün. Kural belgede "her değişiklik izli" diye anlatılıyor.
- **Öneri:** İki yol var:
  1. Tetikleyici dakika alanlarını ve durumun tüm geçişlerini de korusun. Gece işinin hesap adımı (`gun_hesapla`) ve `duzeltme_uygula` bu alanları meşru olarak yazdığı için, onların işlem içinde koyduğu bir işaretle (`set_config`) izin verilsin.
  2. Bu bilinçli bir sınırlılık olarak kabul edilsin; CLAUDE.md'deki kural, `veritabani.md` kural 3'le aynı kapsama indirilsin.

  Karar Fırat'ın.
- **Durum:** Açık

### T-02 · 55 yabancı anahtar sütununda index yok
- **Adım:** 1 · **Önem:** Görüş
- **Yer:** Şema geneli (tam liste: `scratch/a1_sema_sonuc.txt`, bölüm 11)
- **Ne oldu:** 55 tek sütunlu yabancı anahtarın sütunu hiçbir indexin ilk anahtarı değil. Sık sorgulananlardan bazıları:
  - `calisan.departman_id`: amirin çalışanlarını süzen `amirin_calisani_mi` her RLS kontrolünde bunu kullanıyor.
  - `gun_kaydi.vardiya_id`, `itiraz.gun_kaydi_id`, `duzeltme.calisan_id`.
  - `ham_okutma.aktarim_id`, `kanit_kaydi.aktarim_id`, `puantaj_satiri.calisan_id`, `uyari.calisan_id`.

  Kalanların çoğu "giren / yapan / karar veren" türünden iz sütunları.
- **Ne olmalıydı:** Planın beklentisi "eksikleri listele". Sorgu ve birleştirme yolu olan yabancı anahtarlarda index beklenir.
- **Kanıt:** `pg_constraint` (contype = 'f') ile `pg_index.indkey[0]` karşılaştırması: 55 satır.
- **Sade dille:** 76 çalışanlık örnek veride fark edilmez; Kasım'ın tamamı 4 saniyede işleniyor. 2000 çalışanda gün kaydı, düzeltme ve okutma tabloları büyüyünce bazı ekran ve RLS sorguları yavaşlayabilir. Bu henüz ölçülmedi; süre Adım 5'te ölçülecek.
- **Öneri:** Adım 5'teki süre ölçümünden sonra karar verilsin. Gerekirse yalnızca sık sorgulanan 8–10 sütuna index eklensin.
- **Durum:** Açık

### T-03 · 45 `security definer` fonksiyonun `search_path`'inde `pg_temp` yok
- **Adım:** 1 · **Önem:** Görüş
- **Yer:** 45 fonksiyon (`search_path=pdks`); yalnızca 1 fonksiyonda `search_path=pdks, pg_temp`.
- **Ne oldu:** PostgreSQL, `search_path`'te açıkça yazılmayan `pg_temp`'i (geçici şema) tablo ararken **en başa** koyar. `authenticated` ve `anon` rollerinin veritabanında geçici tablo açma (TEMP) yetkisi var.
- **Ne olmalıydı:** PostgreSQL belgeleri `security definer` fonksiyonlarda `pg_temp`'in sona yazılmasını öneriyor: `set search_path = pdks, pg_temp`.
- **Kanıt:**
  ```
  authenticated TEMP yetkisi: true · anon TEMP yetkisi: true
  search_path=pdks (pg_temp yok) definer: 45
  ```
  Bu 45 fonksiyonun gövdesinde şemasız yazılmış bir tablo ya da view adı aranıp **bulunamadı**: her `from`, `join`, `update`, `into`, `delete from` `pdks.` önekiyle yazılmış. Fonksiyon çağrıları için risk yok, çünkü PostgreSQL fonksiyon ararken geçici şemaya bakmıyor. **Şu an istismar edilebilir bir yol kanıtlanamadı.**
- **Sade dille:** Kapı şu an kilitli, ama kilidin bir mandalı eksik. Gelecekte biri bir fonksiyona şemasız bir tablo adı yazarsa, giriş yapmış bir kullanıcı aynı adla geçici bir tablo açıp fonksiyonu kendi tablosunu okumaya kandırabilir. Fonksiyon sahibin yetkisiyle çalıştığı için bu bir yetki açığı olurdu.
- **Öneri:** Fonksiyonlar başka bir nedenle yeniden yazıldıkça `set search_path = pdks, pg_temp` yapılsın; ya da tek bir migration'da hepsine `alter function … set search_path = pdks, pg_temp` uygulansın. `sema_temizligi_testi`'ne bir kontrol eklensin.
- **Durum:** Açık

### T-04 · Testler UTC davranışını sınamıyor
- **Adım:** 1 · **Önem:** Görüş
- **Yer:** `supabase/tests/*.sql`
- **Ne oldu:** 21 test dosyasının 20'si başta `set local timezone = 'Europe/Istanbul'` yapıyor; yalnızca `sema_temizligi_testi` yapmıyor, onun da saatle ilgisi yok. `PGTZ=UTC` ile çalıştırınca da oturum İstanbul'a çevrildiği için sonuç değişmiyor. Yerel veritabanının varsayılan saat dilimi zaten UTC.
- **Ne olmalıydı:** Canlıdaki gece işi pg_cron ile UTC oturumunda çalışıyor. En az bir test gece işini ve hesabı UTC oturumunda çalıştırıp İstanbul'la aynı sonucu doğrulamalı.
- **Kanıt:**
  ```
  grep -L timezone supabase/tests/*.sql → yalnızca sema_temizligi_testi.sql
  show timezone (varsayılan) → UTC
  ```
- **Sade dille:** Testler hep "İstanbul saatindeyiz" diye başlıyor. Gerçek gece işi ise sunucuda UTC saatiyle çalışıyor. Kodda saat dilimine bağlı bir hata olsaydı testler onu yakalamazdı. Daha önce Kasım'ın UTC'de de aynı işlendiği elle denenmişti, ama bunu sınayan kalıcı bir test yok.
- **Öneri:** `gece_isi_testi`'ne ya da yeni küçük bir teste "aynı günü UTC oturumunda işle; gün kaydı, düzeltme ve dakikalar İstanbul turuyla aynı" kontrolü eklensin. Adım 5'te ayrıca elle de denenecek.
- **Durum:** ✅ Düzeltildi — PR #46 (test: `istanbul_tarihi_testi.sql`; aynı işlemler UTC−12 ve UTC+14 oturumla yapılır, günün her saatinde İstanbul'la farklı tarihli bir oturum sınanır)

### T-05 · README'de işe giriş / işten çıkış test sayısı yanlış
- **Adım:** 1 · **Önem:** Düşük
- **Yer:** `README.md`, ilerleme tablosu ("İşe giriş ve işten çıkış … (35 test)")
- **Ne oldu:** `ise_giris_cikis_testi.sql` 33 kontrol çalıştırıyor. Dosyada geçen 35 `test.dogrula(` / `test.hata(` eşleşmesinin 2'si yardımcı fonksiyonların tanımı. Sayı PR #30'da yanlış verilmişti.
- **Ne olmalıydı:** 33.
- **Kanıt:** Örnek veriyle çalıştırmada `GEÇTİ` satırı sayısı 33; diğer 20 dosyanın README'deki sayıları gerçek sayılarla aynı.
- **Sade dille:** Belgede yazan test sayısı gerçekte olandan 2 fazla. Sistemi etkilemiyor, ama rapordaki rakamlar güvenilir olmalı.
- **Öneri:** README'de 35 → 33.
- **Durum:** ✅ Düzeltildi (belge, `feature/T103-belge-duzeltmeleri`). README ilerleme tablosunda 33 test yazıyor.

### T-06 · `kullanici.auth_kullanici_id`'nin `auth.users`'a yabancı anahtarı yok
- **Adım:** 1 · **Önem:** Görüş
- **Yer:** `pdks.kullanici` (`20261114000100_tablolar.sql`)
- **Ne oldu:** Sütun `uuid unique`, ama `auth.users(id)`'ye bağlı değil. Bu, `_id` ile bitip yabancı anahtarı olmayan tek sütun.
- **Ne olmalıydı:** Bilinçli olabilir: seed, hesapları sonradan e-postayla bağlıyor, testler de var olmayan sahte uuid'ler kullanıyor. Ama nedeni hiçbir yerde yazmıyor.
- **Kanıt:** Şema sorgusu bölüm 10: tek satır `kullanici.auth_kullanici_id`.
- **Sade dille:** Supabase'de bir giriş hesabı silinirse PDKS kullanıcısı silinmiş hesaba bağlı görünmeye devam eder. O hesapla zaten giriş yapılamaz, yani güvenlik riski yok. Yalnızca "bu kullanıcının hesabı var mı" bilgisi yanıltıcı olur.
- **Öneri:** Bilinçli tercihse `docs/veritabani.md` "Bilinçli tercihler"e bir satır yazılsın. Değilse `on delete set null` ile yabancı anahtar eklensin; testlerin sahte uuid'leri buna uyacak şekilde değişmeli.
- **Durum:** Açık

### T-07 · `v_izin_amir`'in açıklaması yok
- **Adım:** 1 · **Önem:** Düşük
- **Yer:** `pdks.v_izin_amir`
- **Ne oldu:** `obj_description` boş. Eşi olan `v_saatlik_izin_amir`'de "Amirin saatlik izin görünümü: izin türü gizlidir." açıklaması var.
- **Ne olmalıydı:** Bilinçli olarak RLS'i aşan bir view'ın neden böyle olduğu veritabanında yazmalı.
- **Kanıt:** `select obj_description('pdks.v_izin_amir'::regclass)` → boş.
- **Sade dille:** Bu view kuralları bilerek esnetiyor (amirin göremediği tabloyu süzerek gösteriyor). Bunu bilmeyen biri ileride "güvenlik hatası" sanıp bozabilir.
- **Öneri:** `comment on view pdks.v_izin_amir is '…'`.
- **Durum:** Açık

### Denediklerim
- Örnek veriyle ve verisiz kurulum; 21 test dosyası, iki tur, ayrıca UTC. Sonuçlar dosya dosya `scratch/a1_*_1.txt`, `_2.txt`, `_utc.txt`.
- İz kontrolü: 35 tablonun satır sayısı ve içerik md5 özeti testlerden önce ve sonra (`scratch/a1_iz.sql`).
- Şema sorgularının tamamı (`scratch/a1_sema.sql`, sonuç `scratch/a1_sema_sonuc.txt`).
- Değiştirilemez tablolar, gerçek satırlarla: gece işi ve Kasım kilidiyle satır üretildi; `puantaj_satiri` 76 satır (`scratch/a1_degistirilemez*.sql`).
- `gun_kaydi`'nda alan alan doğrudan UPDATE.
- **`gun_kaydi` TRUNCATE, `duzeltme` boşken** (76 gün kaydı; düzeltme, soru, itiraz ve havuz tabloları boş; `scratch/a1_truncate.sql`):
  - basamaksız TRUNCATE: "cannot truncate a table referenced in a foreign key constraint";
  - CASCADE: `duzeltme`'nin TRUNCATE tetikleyicisi komut düzeyinde olduğu için tablo boşken de "değiştirilemez ve silinemez" hatası veriyor.

  Koruma dolaylı ama her durumda çalışıyor.
- `security definer` fonksiyonların gövdelerinde şemasız tablo adı araması.

### Denemediklerim
- **Satır içermeyen değiştirilemez tablolarda UPDATE ve DELETE:** satır düzeyindeki tetikleyici satır yokken çalışmadığı için anlamsız. Hepsinde en az 1 satırla denedim; `okutma_isareti` 1, `duzeltme` 2 satırdı.
- **`service_role` (gizli anahtar):** `pdks` şemasında USAGE yetkisi yok, yani gizli anahtarla API'den `pdks`'e erişilemiyor. Ekran kodu gizli anahtarı `pdks` için kullanıyor mu, bakmadım; ekranlar kapsam dışı.
- **T-02'deki eksik indexlerin süreye etkisi:** ölçülmedi, Adım 5'te ölçülecek.
- **`gun_kaydi`'na başka tablolardan yabancı anahtar eklenip kaldırılması durumu:** `gun_kaydi`'nın kendi TRUNCATE tetikleyicisi yok; bugün onu `duzeltme`'nin tetikleyicisi koruyor. İleride bu ilişki değişirse koruma kalkar. Bunu denemek şemayı değiştirmeyi gerektirdiği için denemedim.

### Şüpheler
- **8 yardımcı fonksiyonda `search_path` sabit değil** (`degistirilemez`, `dakika`, `dakika_toplami`, `aralik`, `gece_araligi`, `tolerans_uygula`, `yonelme_eki`, `saat_eki`). Hepsi `security definer` değil ve tablo okumuyor; risk görmüyorum ama Adım 2'de yetki matrisinde bakılacak.

---

## Adım 2 — Yetki matrisi (21 Kasım 2026)

**Yöntem** (`scratch/a2_matris.sql`, tekrar çalıştırılabilir):
- **Hazırlık:** tek bir dış işlemde, `postgres` olarak:
  - her kullanıcıya sahte bir Auth kimliği (e-postanın md5'i);
  - Kasım 1–24 gece işi;
  - İK kararı bekleyen bir soru (S4), açık bir itiraz, onay bekleyen bir fazla mesai talebi;
  - kartı iptal edilmiş bir çalışan (K1010).
- **Çağrılar:** her (rol × fonksiyon) çağrısı ayrı bir alt işlemde yapıldı ve başarılıysa kasıtlı bir hatayla geri alındı; çağrılar birbirini etkilemedi. Dış işlem sonda `ROLLBACK`.
- **Parametreler:** örnek veriden önceden hesaplanmış sabit değerler. Bu değerler RLS altında okunmadığı için her rol aynı kaydı denedi.
- **Oturumlar:**

  | Sütun | Hesap |
  |---|---|
  | ik | `ik.muduru` (seed kayıtlarının çoğunu `ik.uzmani` girdiği için görevler ayrılığına takılmasın diye) |
  | amir | `montaj.amiri` |
  | guvenlik | `guvenlik` |
  | yonetici | `fabrika.muduru` |
  | isg | `isg.uzmani` |
  | admin | `sistem.yoneticisi` |
  | bagsiz | hiçbir kullanıcıya bağlı olmayan Auth kimliği |
  | pasif_ik | `ik.uzmani`, `aktif = false` (rolü ik; 34 yazma fonksiyonunun hepsi denendi) |

- **Hücreler:** ✅ çalıştı · ⛔ yetki hatası · ⚠️ başka hata · ❗ beklenenden farklı.

**Kapsam:**
- `authenticated`'ın EXECUTE yetkisi olan 41 fonksiyon:
  - 34 RPC: ilk satırları `yetki_gerekli(...)`;
  - 7 yardımcı: `yetki_gerekli` çağırmıyor.
- Ek olarak, kapalı olması gereken 14 iç fonksiyon denendi: 7 iç fonksiyon (`duzeltme_uygula`, `gun_hesapla`, `gece_isi_calistir` vb.) ve Adım 1'deki `search_path`'i sabit olmayan yardımcılardan 7'si. Sekizincisi `degistirilemez` bir tetikleyici fonksiyonu, doğrudan çağrılamıyor.
- Toplam 55 fonksiyon × 8 oturum = **440 hücre**.

### Matris

| Fonksiyon | Beklenen (yetki_gerekli) | ik | amir | guvenlik | yonetici | isg | admin | bagsiz | pasif_ik |
|---|---|---|---|---|---|---|---|---|---|
| `ariza_gir` | ik | ✅ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |
| `ariza_karar` | ik | ✅ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |
| `ay_kilitle` | ik | ✅ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |
| `ayar_guncelle` | admin | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ✅ | ⛔ | ⛔ |
| `bolge_yetkisi_kaldir` | isg | ⛔ | ⛔ | ⛔ | ⛔ | ✅ | ⛔ | ⛔ | ⛔ |
| `bolge_yetkisi_ver` | isg | ⛔ | ⛔ | ⛔ | ⛔ | ✅ | ⛔ | ⛔ | ⛔ |
| `calisan_ekle` | ik | ✅ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |
| `dosya_yukle` | ik | ✅ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |
| `fazla_mesai_inceleme_karar` | ik | ✅ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |
| `fazla_mesai_karar` | ik | ✅ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |
| `fazla_mesai_onayi_geri_al` | ik | ✅ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |
| `fazla_mesai_onayi_gir` | ik | ✅ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |
| `fazla_mesai_talep_et` | amir, ik | ✅ | ✅ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |
| `gece_isi_tetikle` | ik | ✅ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |
| `gecici_kart_iade_al` | guvenlik, ik | ✅ | ⛔ | ✅ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |
| `gecici_kart_ver` | guvenlik, ik | ✅ | ⛔ | ✅ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |
| `isg_belge_gir` | isg | ⛔ | ⛔ | ⛔ | ⛔ | ✅ | ⛔ | ⛔ | ⛔ |
| `isten_cikis_gir` | ik | ✅ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |
| `itiraz_gir` | amir, ik | ✅ | ✅ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |
| `itiraz_incelemeye_al` | ik | ✅ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |
| `itiraz_karar` | ik | ✅ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |
| `izin_gir` | ik | ✅ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |
| `izin_iptal` | ik | ✅ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |
| `kart_iptal_et` | ik | ✅ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |
| `kart_tanimla` | ik | ✅ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |
| `kayit_duzelt` | ik | ✅ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |
| `kullanici_ekle` | admin | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ✅ | ⛔ | ⛔ |
| `kullanici_guncelle` | admin | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ✅ | ⛔ | ⛔ |
| `saatlik_izin_gir` | ik | ✅ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |
| `soru_cevapla` | amir | ⛔ | ✅ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |
| `soru_ik_karari` | ik | ✅ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |
| `uyari_goruldu` | ik | ✅ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |
| `vardiya_plani_gir` | amir, ik | ✅ | ✅ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |
| `vardiya_plani_onayla` | ik | ✅ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |
| `amirin_calisani_mi` | herkes (okuma yardımcısı) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `ayar_al` | herkes (okuma yardımcısı) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `gun_kodlari` | ik, yonetici (tum_veriyi_gorur) | ✅ | ⛔ | ⛔ | ✅ | ⛔ | ⛔ | ⛔ | ⛔ |
| `oturum_departmanlari` | herkes (okuma yardımcısı) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `oturum_kullanici_id` | herkes (okuma yardımcısı) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `oturum_rolu` | herkes (okuma yardımcısı) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `tum_veriyi_gorur` | herkes (okuma yardımcısı) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `duzeltme_uygula` | hiç kimse (authenticated’a kapalı) | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |
| `gun_hesapla` | hiç kimse (authenticated’a kapalı) | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |
| `gece_isi_calistir` | hiç kimse (authenticated’a kapalı) | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |
| `saat_yaz` | hiç kimse (authenticated’a kapalı) | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |
| `donem_kilitle` | hiç kimse (authenticated’a kapalı) | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |
| `puantaj_yaz` | hiç kimse (authenticated’a kapalı) | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |
| `uyari_yaz` | hiç kimse (authenticated’a kapalı) | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |
| `dakika` | hiç kimse (authenticated’a kapalı) | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |
| `dakika_toplami` | hiç kimse (authenticated’a kapalı) | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |
| `aralik` | hiç kimse (authenticated’a kapalı) | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |
| `gece_araligi` | hiç kimse (authenticated’a kapalı) | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |
| `tolerans_uygula` | hiç kimse (authenticated’a kapalı) | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |
| `yonelme_eki` | hiç kimse (authenticated’a kapalı) | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |
| `saat_eki` | hiç kimse (authenticated’a kapalı) | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |

**Özet:**
- **Uyuşma:** 440 hücrenin 440'ı beklenenle aynı; ❗ yok, ⚠️ yok. Beklenen rolün her çağrısı gerçekten çalıştı ve geçerli bir sonuç döndürdü (ör. `calisan_ekle` → 77, `isten_cikis_gir` → özet). Yani ⛔'ler parametre hatası değil.
- **⛔ hücrelerin kaynağı:**
  - 165'i "Bu işlem için yetkiniz yok." (yanlış rol);
  - 68'i "Oturum bulunamadı ya da hesap bir çalışana bağlı değil." (34 RPC × bağsız ve pasif);
  - 6'sı `gun_kodlari`'nın kendi kontrolü (`tum_veriyi_gorur`);
  - 112'si "permission denied for function …" (iç fonksiyonlar `authenticated`'a hiç açık değil).
- **Kontrolün yeri:** `yetki_gerekli` her RPC'de `declare` bölümünde, yani ilk iş olarak çalışıyor. Ondan önce patlayabilecek bir şey yok.
- **Yönetici:** hiçbir yazma fonksiyonunu çalıştıramıyor. Çalıştırabildiği tek fonksiyon `gun_kodlari` (okuma).
- **Admin:** yalnızca `ayar_guncelle`, `kullanici_ekle`, `kullanici_guncelle`'yi çalıştırabiliyor. Gün kaydı, izin, kart, plan, puantaj fonksiyonlarının hepsinde ⛔. Ayarların puantajı dolaylı etkilediği için bkz. T-10.
- **Pasif kullanıcı ve bağsız oturum:** 34 RPC'nin hepsinde ⛔. Yardımcılar çalışıyor ama `null` / `false` döndürüyor (`oturum_rolu` = null, `tum_veriyi_gorur` = false); tek istisna `ayar_al` (T-09).
- **Yardımcıyla kural atlama:** `duzeltme_uygula`, `saat_yaz`, `gun_hesapla`, `gece_isi_calistir`, `donem_kilitle`, `puantaj_yaz`, `uyari_yaz` 8 oturumun hepsinde "permission denied". İK onayı olmadan `duzeltme_uygula` ile gün değiştirme denendi, olmuyor. Tablolara doğrudan yazma yetkisi de yok (Adım 1 K5).
- **Adım 1'deki şüphe kapandı:** `search_path`'i sabit olmayan yardımcıların hiçbiri `authenticated`'a açık değil (7'si denendi: hepsi "permission denied"). Yalnızca `search_path`'i sabit olan `security definer` fonksiyonların içinden çağrılıyorlar.

**Yetki kontrolü olmayan 7 fonksiyon:**

| Fonksiyon | Ne | Yorum |
|---|---|---|
| `oturum_rolu`, `oturum_kullanici_id`, `oturum_departmanlari`, `tum_veriyi_gorur`, `amirin_calisani_mi` | RLS politikalarının ve view'ların kullandığı okuma yardımcıları | Yetki kontrolü unutulmamış: oturumun kendisini anlatıyorlar, RLS'in çalışması için `authenticated`'a açık olmaları gerekiyor. `amirin_calisani_mi(id)` yalnızca evet / hayır döndürüyor |
| `gun_kodlari` | Puantaj kodları | Kendi kontrolü var (`tum_veriyi_gorur`): yalnızca ik ve yönetici |
| `ayar_al` | Bir ayarın değeri | Kontrol yok; bkz. T-09 |

### Bulgular

### T-08 · `pdks`'te yeni oluşturulan fonksiyon herkese açık doğuyor
- **Adım:** 2 · **Önem:** Görüş
- **Yer:** `pdks` şemasının varsayılan yetkileri (`pg_default_acl`)
- **Ne oldu:** `pdks` için tanımlı bir varsayılan yetki yok; Supabase'in varsayılanları yalnızca `public` şemasında. PostgreSQL'in kendi kuralıyla yeni bir fonksiyon PUBLIC'e, dolayısıyla `anon` ve `authenticated`'a açık doğuyor. Bugün güvenli olmasının nedeni her migration'ın sonunda `revoke … from public, anon` yazılması. Bunu `gecici_kart_ve_paylasim_testi` içindeki "pdks fonksiyonlarının hiçbiri herkese (PUBLIC) açık değil" kontrolü denetliyor.
- **Ne olmalıydı:** Kural migration yazanın dikkatine kalmamalı. Şema düzeyinde "yeni fonksiyon kapalı doğsun" ayarı olmalı.
- **Kanıt:** `scratch/a2_varsayilan.sql` (sonda ROLLBACK):
  ```
  create function pdks.a2_deneme_fn() returns int language sql as 'select 1';
  yeni fonksiyon: PUBLIC=true authenticated=true anon=true
  pg_default_acl: yalnızca 'public' şeması için satırlar var; 'pdks' için yok
  ```
  Yeni tablo için durum farklı: yetki gelmiyor (`authenticated` SELECT ve INSERT = false). RLS kapalı doğuyor, ama bunu `giris_ve_yetki_testi` yakalıyor.
- **Sade dille:** Yeni yazılan her fonksiyon, biri kapatmayı unutursa internetten çağrılabilir. Şu an her migration kapatıyor ve bir test de bunu kontrol ediyor. Ama bu kontrol konusu geçici kartlar olan bir test dosyasının içinde; bilmeyen biri bulamaz ya da yanlışlıkla silebilir.
- **Öneri:**
  1. Bir migration'da `alter default privileges for role postgres in schema pdks revoke execute on functions from public;` yazılsın.
  2. PUBLIC kontrolü `sema_temizligi_testi`'ne ya da `giris_ve_yetki_testi`'ne taşınsın.
- **Durum:** Açık

### T-09 · `ayar_al`, hesabı bağlı olmayan her oturuma açık
- **Adım:** 2 · **Önem:** Görüş
- **Yer:** `pdks.ayar_al` (son sürüm: `20261118040000_ayar_al_yetkisi.sql`)
- **Ne oldu:** `ayar_al(anahtar)`, `security definer` ve yetki kontrolü yok. Supabase'e giriş yapmış ama `pdks.kullanici`'ya bağlı olmayan bir oturum da, pasif bir kullanıcı da 26 ayarın değerini okuyabiliyor. `ayar` tablosunun kendisi RLS ile korunuyor.
- **Ne olmalıydı:** Ayarlar gizli değil (tolerans, mola eşikleri…), ama bu fonksiyon RLS'i aşan tek okuma yolu. Bağlı olmayan oturum başka hiçbir veriye ulaşamıyor.
- **Kanıt:** Matris, `ayar_al` satırı: bagsiz = 5, pasif_ik = 5 (`yurume_payi_dk`).
- **Sade dille:** Sistemde kaydı olmayan biri, Supabase'te bir hesap açabiliyorsa fabrikanın geç kalma toleransı gibi kurallarını okuyabilir. Çalışan bilgisi değil, zararı küçük. Ama canlıda "Allow new users to sign up" hâlâ açıksa herkes hesap açabilir (bu ayarın kapatılması Fırat'ın bekleyen işlerinde).
- **Öneri:**
  - Canlıda sign-up kapatılsın (asıl önlem).
  - İstenirse `ayar_al`'a "oturum bağlı mı" kontrolü eklensin. Ama fonksiyon RLS'in ve view'ların içinden de çağrılıyor; kontrol bunları bozmamalı.
- **Durum:** Açık

### T-10 · Puantajı etkileyen ayarları yalnızca admin, tek başına değiştirebiliyor
- **Adım:** 2 · **Önem:** Görüş
- **Yer:** `pdks.ayar_guncelle` (`yetki_gerekli('admin')`)
- **Ne oldu:** 26 ayarın bir kısmı puantajı doğrudan değiştiriyor: `gec_kalma_tolerans_dk`, `erken_cikis_tolerans_dk`, `tolerans_yuvarlama_dk`, mola eşikleri (`mola_*`), `yurume_payi_dk`, `fm_plansiz_esik_dk`, `fm_yillik_sinir_dk`, `esnek_gunluk_hedef_dk`, `cumartesi_hafta_sonu`. Bunları yalnızca admin değiştirebiliyor, İK değiştiremiyor (matris: İK ⛔, admin ✅). Değişiklik izi var: `ayar_gecmisi`, değer 0'dan küçük olamaz.
- **Ne olmalıydı:** CLAUDE.md admin'i "çalışan kayıtlarını görmez, karar veremez" diye tanımlıyor. Tolerans ya da mola eşiği ise geç kalma ve çalışma dakikasını, yani maaşa giden rakamı belirleyen bir karar.
- **Kanıt:** Matris, `ayar_guncelle` satırı; `pdks.ayar`'ın 26 satırı.
- **Sade dille:** Bilgi işlemdeki sistem yöneticisi, kimseye sormadan geç kalma toleransını 10 dakikadan 0'a indirebilir. Ertesi gece işlenen günlerde herkesin geç kalma dakikası değişir. İz kalır, ama İK'nın onayı ya da haberi olmaz.
- **Öneri:** Karar konusu. Ya puantajı etkileyen ayarlar İK'ya (ya da admin + İK onayına) verilsin, ya da bu bilinçli kabul edilip `docs/veritabani.md` "Bilinçli tercihler"e yazılsın. Geçersiz değer denemeleri Adım 11'de.
- **Durum:** Sınırlılık. Ayar yetkisi admin'de kalır; aralık kontrolü, yasal üst sınır, `ayar_gecmisi` ve İK'ya uyarı (T-74, `feature/T74-ayar-sinirlari`) yeterli kabul edilir. Aralık içindeki değişiklik İK onayı istemez.

### T-11 · Ekrandaki "`v_fazla_mesai_yillik` çalışmıyor" notu eskimiş
- **Adım:** 2 · **Önem:** Düşük
- **Yer:** `app/(panel)/fazla-mesai/page.tsx` (ekran, Gökalp) ↔ `pdks.v_fazla_mesai_yillik`
- **Ne oldu:** Ekran kodunda şu not var: "v_fazla_mesai_yillik görünümü kullanılmıyor: içindeki pdks.ayar_al() fonksiyonunu giriş yapmış kullanıcı çalıştıramıyor (42501 permission denied)." Bu yüzden yıllık fazla mesai toplamı ekranda ayrıca hesaplanıyor. Oysa `ayar_al`'ın yetkisi `edd8838`'de (18 Kasım) verilmiş, görünüm İK oturumuyla çalışıyor.
- **Ne olmalıydı:** Ekran görünümü kullanmalı ya da not kaldırılmalı. Aynı kuralın (270 saat sınırı, kalan dakika) iki ayrı yerde hesaplanması ileride iki farklı sonuç doğurabilir.
- **Kanıt:** `scratch/a2_fm_yillik.sql`:
  ```
  ik:   1 satır, örnek kalan_dk=16080
  amir: 0 satır   (Montaj'da fazla mesai planı yok)
  ```
- **Sade dille:** Ekran bir hatayı aşmak için hesabı kendisi yapıyor, ama o hata artık yok. Şimdilik sonuç aynı; kural değişirse iki hesap birbirinden ayrılabilir.
- **Öneri:** Gökalp'e not: görünümü kullansın ve kodu sadeleştirsin. Sayıların karşılaştırması Adım 9'da.
- **Durum:** ✅ Düzeltildi (ekran notu, `feature/53-t41-t11-ekran`). Eskimiş not doğru gerekçeyle değiştirildi; hesap ekranda kalıyor, çünkü ekran bekleyen talepleri de gösteriyor. `v_fazla_mesai_yillik` görünümü ekranlarda kullanılmıyor (`fazla_mesai_testi.sql` ve `giris_ve_yetki_testi.sql` kullanıyor); silinmesi migration ister.

### Denediklerim
- 41 açık fonksiyonun hepsi × 8 oturum, ayrıca 14 kapalı iç fonksiyon × 8 oturum: 440 çağrı (`scratch/a2_ham.txt`).
- Her ✅ hücrenin döndürdüğü değer: çağrının gerçekten iş yaptığını gösteriyor.
- Her ⛔ hücrenin hata mesajı: yetki kontrolünden mi geliyor?
- İç fonksiyonlarla kural atlama: `duzeltme_uygula` ile İK onayı olmadan gün değiştirme ve diğerleri.
- Yeni fonksiyon ve yeni tablonun varsayılan yetkileri (`pg_default_acl`).
- `v_fazla_mesai_yillik` İK ve amir oturumuyla.

### Denemediklerim
- **Amirin başka departmandaki kayıtta işlem yapması:** örneğin Montaj amirinin Bobinaj çalışanına plan girmesi. Matriste amir hep kendi çalışanıyla denendi. Bu bir kapsam (departman) kontrolü, Adım 3'te.
- **Admin'in `kullanici_guncelle` ile kendine ya da başkasına İK rolü vermesi:** Adım 11'de.
- **Fonksiyonların ekrandan (PostgREST üzerinden) çağrılması:** veritabanında `authenticated` rolü ve JWT taklidiyle denedim. PostgREST aynı rolü kullandığı için sonuç aynı olmalı, ama HTTP ile denemedim.
- **Vekil amir (Montaj → Bobinaj) ve amirin üst amire eskale olan soruyu cevaplaması:** Adım 3 ve 7.

### Şüpheler
- **`kullanici_guncelle(p_kullanici_id, p_rol, …)` rol değiştirebiliyor.** Admin kendine `ik` rolü verip İK fonksiyonlarını çalıştırabiliyorsa, admin'in "karar veremez" sınırı tek adımda aşılır. Kodu okumadım ve denemedim; Adım 11'de.

---

## Adım 3 — Görevler ayrılığı ve RLS (21 Kasım 2026)

**Betikler:**

| Betik | Ne sınıyor |
|---|---|
| `scratch/a3_rls.sql` | RLS matrisi |
| `scratch/a3_izin_turu.sql` | İzin türü sızıntısı |
| `scratch/a3_kapsam_gorev.sql` | Amir kapsamı, vekillik, görevler ayrılığı, dolaylı yollar |

**Ortak hazırlık:**
- Her betik tek işlem ve sonda `ROLLBACK`.
- Kasım'ın tamamı gece işinden geçirildi: 1597 gün kaydı, 10 düzeltme, 4 soru.
- 3 itiraz ve 3 saatlik izin eklendi; böylece boş tablo görmemek için her türde satır var.
- **Oturumlar:**

  | Sütun | Hesap |
  |---|---|
  | ik | `ik.muduru` |
  | amir | `montaj.amiri`: Montaj'ın amiri, **Bobinaj'ın vekili** |
  | guvenlik | `guvenlik` |
  | yonetici | `fabrika.muduru` |
  | isg | `isg.uzmani` |
  | admin | `sistem.yoneticisi` |
  | bagsiz | hiçbir kullanıcıya bağlı olmayan Auth kimliği |
  | pasif_ik | `ik.uzmani`, `aktif = false` |

### RLS matrisi (`select count(*)`; 35 tablo + 9 view × 8 oturum = 352 hücre)

**Beklenen** her hücre için politikalardan türetildi:
- ik ve yönetici = sahibin gördüğü toplam;
- amir = Montaj + Bobinaj çalışanlarının satırları (sahibin gözüyle ayrıca sayıldı) ve kendisine atanmış / eskale edilmiş sorular;
- guvenlik, isg, admin = planın tablosundaki nesneler;
- oturum açan herkes = `bolge`, `departman`, `donem`, `resmi_tatil`, `vardiya_tanim`;
- `kullanici` = kendi satırı (admin hepsini);
- bağsız ve pasif = 0.

| Nesne | Tür | ik | amir | guvenlik | yonetici | isg | admin | bagsiz | pasif_ik |
|---|---|---|---|---|---|---|---|---|---|
| `aktarim` | tablo | 121 | 0 | 0 | 121 | 0 | 0 | 0 | 0 |
| `amir_sorusu` | tablo | 4 | 2 | 0 | 4 | 0 | 0 | 0 | 0 |
| `ariza` | tablo | 1 | 0 | 0 | 1 | 0 | 0 | 0 | 0 |
| `ayar` | tablo | 26 | 0 | 0 | 26 | 0 | 26 | 0 | 0 |
| `ayar_gecmisi` | tablo | 27 | 0 | 0 | 27 | 0 | 27 | 0 | 0 |
| `bolge` | tablo | 2 | 2 | 2 | 2 | 2 | 2 | 0 | 0 |
| `bolge_yetkisi` | tablo | 4 | 0 | 0 | 4 | 4 | 4 | 0 | 0 |
| `bolge_yetkisi_gecmisi` | tablo | 4 | 0 | 0 | 4 | 4 | 4 | 0 | 0 |
| `calisan` | tablo | 76 | 20 | 76 | 76 | 76 | 76 | 0 | 0 |
| `departman` | tablo | 19 | 19 | 19 | 19 | 19 | 19 | 0 | 0 |
| `donem` | tablo | 1 | 1 | 1 | 1 | 1 | 1 | 0 | 0 |
| `duzeltme` | tablo | 10 | 9 | 0 | 10 | 0 | 0 | 0 | 0 |
| `fazla_mesai_inceleme` | tablo | 3 | 0 | 0 | 3 | 0 | 0 | 0 | 0 |
| `fazla_mesai_onayi` | tablo | 24 | 0 | 0 | 24 | 0 | 0 | 0 | 0 |
| `fazla_mesai_plani` | tablo | 1 | 0 | 0 | 1 | 0 | 0 | 0 | 0 |
| `gece_isi` | tablo | 30 | 0 | 0 | 30 | 0 | 30 | 0 | 0 |
| `gecici_kart` | tablo | 5 | 0 | 5 | 5 | 0 | 0 | 0 | 0 |
| `gecici_kart_zimmet` | tablo | 6 | 0 | 6 | 6 | 0 | 0 | 0 | 0 |
| `gun_kaydi` | tablo | 1597 | 420 | 0 | 1597 | 0 | 0 | 0 | 0 |
| `ham_okutma` | tablo | 3173 | 0 | 0 | 3173 | 0 | 0 | 0 | 0 |
| `isg_belge` | tablo | 92 | 0 | 0 | 92 | 92 | 0 | 0 | 0 |
| `itiraz` | tablo | 3 | 2 | 0 | 3 | 0 | 0 | 0 | 0 |
| `izin` | tablo | 3 | 0 | 0 | 3 | 0 | 0 | 0 | 0 |
| `kanit_kaydi` | tablo | 5162 | 0 | 0 | 5162 | 0 | 0 | 0 | 0 |
| `kart` | tablo | 77 | 0 | 0 | 77 | 0 | 0 | 0 | 0 |
| `kullanici` | tablo | 25 | 1 | 1 | 25 | 1 | 25 | 0 | 0 |
| `okutma_isareti` | tablo | 4 | 0 | 0 | 4 | 0 | 0 | 0 | 0 |
| `okuyucu` | tablo | 8 | 0 | 0 | 8 | 8 | 8 | 0 | 0 |
| `puantaj_kalemi` | tablo | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `puantaj_satiri` | tablo | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `resmi_tatil` | tablo | 17 | 17 | 17 | 17 | 17 | 17 | 0 | 0 |
| `saatlik_izin` | tablo | 3 | 0 | 0 | 3 | 0 | 0 | 0 | 0 |
| `uyari` | tablo | 20 | 0 | 0 | 20 | 4 | 0 | 0 | 0 |
| `vardiya_plani` | tablo | 1608 | 431 | 0 | 1608 | 0 | 0 | 0 | 0 |
| `vardiya_tanim` | tablo | 9 | 9 | 9 | 9 | 9 | 9 | 0 | 0 |
| `v_departman_ozet` | view | 19 | 2 | 0 | 19 | 0 | 0 | 0 | 0 |
| `v_esnek_mesai` | view | 4 | 0 | 0 | 4 | 0 | 0 | 0 | 0 |
| `v_fazla_mesai_yillik` | view | 1 | 0 | 0 | 1 | 0 | 0 | 0 | 0 |
| `v_gece_isi_durumu` | view | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 |
| `v_isg_durum` | view | 152 | 0 | 0 | 152 | 152 | 0 | 0 | 0 |
| `v_izin_amir` | view | 3 | 2 | 0 | 3 | 0 | 0 | 0 | 0 |
| `v_puantaj_aktarim` | view | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `v_puantaj_canli` | view | 76 | 20 | 0 | 76 | 0 | 0 | 0 | 0 |
| `v_saatlik_izin_amir` | view | 3 | 2 | 0 | 3 | 0 | 0 | 0 | 0 |

**Özet:**
- **Uyuşma:** 352 hücrenin hepsi beklenenle aynı; ❗ yok. Amir için kontrol edilen sayılar: `gun_kaydi` 420 / 420, `vardiya_plani` 431 / 431, `duzeltme` 9 / 9, `calisan` 20 / 20, `amir_sorusu` 2 / 2, `itiraz` 2 / 2, `v_puantaj_canli` 20 / 20.
- **Matrisin göstermediği şey:** satır **sayısı** doğru, ama amirin gördüğü satırların **içeriği** izin türünü sızdırıyor (T-12).
- **`v_gece_isi_durumu`, bağsız ve pasif oturumda 1 satır:** bu görünüm her zaman tek satır döndürüyor (dünün tarihi ve "gece işi çalıştı mı"). `gece_isi` tablosu RLS ile korunduğu için bu oturumlar `calisti = false` görüyor. Sızan veri yok.
- **isg:** `uyari` 4 satır. Dördü de İSG türünde (1 süresi dolmuş, 2 süresi doluyor, 1 yetkisiz bölge); İSG'nin 20 uyarının geri kalanını görmediği doğrulandı.
- **Amir `fazla_mesai_onayi`'nı göremiyor:** kendi departmanında 20 satır var, amir 0 görüyor; politika yok. Amir fazla mesai talep ederken yazılı onay olup olmadığını ancak hata mesajından öğreniyor. Tasarım tercihi gibi; bulgu değil.

### Amir kapsamı ve vekillik

| # | Deneme | Beklenen | Gerçekleşen | |
|---|---|---|---|---|
| 1 | Başka departmanın (Kalite, Selin 3002) gün kaydını id ile okumak | 0 satır | 0 | ✅ |
| 2 | Aynı çalışanın kaydını, düzeltmesini, planını id ile okumak | 0 | 0 / 0 | ✅ |
| 3 | Başka departmana vardiya planı, itiraz, fazla mesai talebi | Red | "Bu çalışan sizin departmanınızda değil." (3 / 3) | ✅ |
| 4 | Başka amire atanmış soruyu (S19, Bobinaj amiri) cevaplamak | Red | "Soru bulunamadı ya da size atanmamış." | ✅ |
| 5 | Vekil olduğu Bobinaj'ı görmek; Bobinaj amiri izinli **değil** | ? | Görüyor (Bobinaj'ın 209 gün kaydının 209'u) ve Bobinaj'a plan **girebiliyor** | ⚠️ T-14 |
| 6 | Vekillik kaldırılınca (`vekil_amir_id = null`) | Görmemeli | 0 satır; plan girişi reddedildi | ✅ |
| 7 | Vekillik tarihleri | — | Şemada yok; tek alan `departman.vekil_amir_id` | ⚠️ T-14 |

### İzin türü (sağlık bilgisi) amire sızıyor mu?

Senaryo: Montaj amiri vekili olduğu Bobinaj'da Can Kılıç'ın (2007) 23–25 Kasım raporunu ve Deniz Aksoy'un (2008) 26–27 Kasım yıllık iznini görüyor. Ayrıca İK, Montaj'dan Veli Çelik'in (1004) 6 Kasım gününü `kayit_duzelt` ile "raporlu" yapıyor ve gerekçeye tanı yazıyor.

| Yol | Amir ne görüyor | |
|---|---|---|
| `izin` tablosu | 0 satır | ✅ |
| `v_izin_amir` | 2007 ve 2008: `tur = izinli` (tür gizli) | ✅ |
| `gun_kaydi.durum` | 2007: `raporlu` (3 gün), 2008: `izinli`, 1004: `raporlu` | ❌ T-12 |
| `v_puantaj_canli` | 2007: `raporlu_gun = 3`, 1004: `raporlu_gun = 1`, 2008: `izinli_gun = 2` | ❌ T-12 |
| `duzeltme` | `1004 2026-11-06 durum: tamam → raporlu \| gerekçe: Rapor: üst solunum yolu enfeksiyonu` | ❌ T-12 |
| `uyari` | 0 satır | ✅ |
| `v_departman_ozet` | Yalnızca çalışılan ve devamsız gün; izin türü yok | ✅ |

### Görevler ayrılığı

İK = `ik.muduru` (Ahmet Er, 4002). Kayıtlar, kendisi değil, başkası tarafından girildi: itiraz, izin (İK uzmanı), geriye dönük plan (üretim müdürü), İK kararı bekleyen soru, uyarı, havuz kaydı, yazılı fazla mesai onayı.

| # | Deneme | Gerçekleşen | |
|---|---|---|---|
| 1 | İK kendi gününü düzeltir (`kayit_duzelt`) | Red (`duzeltme.yapan_id`) | ✅ |
| 2 | İK kendi itirazını girer | Red | ✅ |
| 3 | İK kendi itirazını **incelemeye alır** | **Çalıştı** | ❌ T-15 |
| 4 | İK kendi itirazına karar verir | Red (`itiraz.karar_veren_id`) | ✅ |
| 5 | İK kendi iznini girer / iptal eder | Red / red | ✅ |
| 6 | İK kendi saatlik iznini girer | Red | ✅ |
| 7 | İK kendi vardiya planını girer | Red | ✅ |
| 8 | İK kendi planını onaylar (başkası girmiş) | Red (`vardiya_plani.onay`) | ✅ |
| 9 | İK kendi yazılı fazla mesai onayını girer / geri alır | Red / red | ✅ |
| 10 | İK kendi hakkındaki soruya karar verir | Red (`amir_sorusu.cevaplayan_id`) | ✅ |
| 11 | İK kendi havuz kaydına (onaysız fazla mesai) karar verir | Red | ✅ |
| 12 | İK kendi işten çıkışını girer | Red | ✅ |
| 13 | İK kendi kartını iptal eder; kendine geçici kart verir | Red / red | ✅ |
| 14 | İK kendisi hakkındaki uyarıyı "görüldü" yapar | Red (`uyari.goren_id`) | ✅ |
| 15 | Güvenlik kendine geçici kart verir | Red | ✅ |
| 16 | Amir kendi hakkındaki soruyu (S22) cevaplar | Red; soru üst amiri `uretim.muduru`'da | ✅ |
| 17 | Amir kendi fazla mesaisini talep eder; kendi itirazını, kendi planını girer | Red (3 / 3) | ✅ |
| 18 | Talep eden İK kendi fazla mesai talebini onaylar | Red, ama ham İngilizce CHECK mesajıyla | ✅ (T-16) |
| 19 | Başka İK aynı talebi onaylar | Çalıştı | ✅ |
| 20 | **Dolaylı:** İK kendi kartıyla PDKS dosyası yükleyip gece işini çalıştırır | Kendi adına "tamam, 480 dk" gün kaydı oluştu | ❌ T-13 |

### Bulgular

### T-12 · Amir izin türünü (rapor = sağlık bilgisi) üç yoldan görebiliyor
- **Adım:** 3 · **Önem:** Yüksek (KVKK m.6, özel nitelikli kişisel veri; Kritik'e yakın)
- **Yer:**
  - `pdks.gun_kaydi`'nın `amir_okur` politikası (`durum` sütunu);
  - `pdks.v_puantaj_canli` (`raporlu_gun`, `izinli_gun`; `security_invoker`, amirin gün kaydı satırlarını kullanıyor);
  - `pdks.duzeltme`'nin `amir_okur` politikası (`eski_deger`, `yeni_deger`, `gerekce`).
- **Ne oldu:** `izin` tablosunu amir göremiyor; `v_izin_amir` türü gizleyip "izinli" yazıyor. Ama aynı bilgi şu yollardan açık:
  - gün kaydının durumu "raporlu" ile "izinli"yi ayırıyor;
  - canlı puantajda `raporlu_gun` sütunu var;
  - İK bir günü "raporlu" yaparsa düzeltmenin yeni değeri ve serbest metin gerekçesi (İK tanı yazarsa tanı dahil) amire görünüyor.
- **Ne olmalıydı:** CLAUDE.md ve `docs/ornek_veri.md` (S18): "Gün izinli; amir türü göremez." Amir için rapor ile izin ayrılmamalı; rapor gerekçesi görünmemeli.
- **Kanıt:** `scratch/a3_izin_turu.sql`, amir oturumu:
  ```
  izin satırı: 0
  v_izin_amir: 2007 2026-11-23–2026-11-25 tur=izinli · 2008 2026-11-26–2026-11-27 tur=izinli
  gun_kaydi:   2007 2026-11-23 durum=raporlu (24, 25 de) · 2008 2026-11-26 durum=izinli · 1004 2026-11-06 durum=raporlu
  v_puantaj_canli: 2007 raporlu_gun=3 izinli_gun=0 · 2008 raporlu_gun=0 izinli_gun=2 · 1004 raporlu_gun=1
  duzeltme: 1004 2026-11-06 durum: tamam → raporlu | gerekçe: Rapor: üst solunum yolu enfeksiyonu
  ```
- **Sade dille:** Sistem amire "bu çalışan izinli" diyor ve izin türünü saklıyor; bu doğru. Ama aynı amir çalışanın gün listesinde "raporlu" yazısını, puantajda "rapor günü: 3" sayısını görüyor. İK düzeltmeye "Rapor: üst solunum yolu enfeksiyonu" yazdıysa amir hastalığı da okuyabiliyor. Sağlık bilgisi KVKK'da özel korunan veri; amirin bunu bilmesi gerekmiyor. Projede bilinçli olarak gizlenen bilgi yan kapıdan açılıyor.
- **Öneri:**
  1. Amir için gün kaydı, düzeltme ve canlı puantaj, durumu "izinli"ye indiren ayrı görünümlerden okunsun (`v_izin_amir` gibi); doğrudan tablo politikaları kaldırılsın ya da daraltılsın.
  2. `v_puantaj_canli`'da amir için `raporlu_gun` `izinli_gun`'e katılsın.
  3. `duzeltme`'de durum düzeltmelerinin gerekçesi amire gösterilmesin.

  Ekranlar (Gökalp) bu görünümlere geçmeli.
- **Durum:** ✅ Düzeltildi (seçenek a, feature/T12-rapor-gizliligi). Migration: `20261214010000_rapor_gizliligi.sql`, test: `rapor_gizliligi_testi.sql`. `gun_kaydi.durum` ve `raporlu_gun` bilinçli olarak açık (bilinen sınırlılık).

#### T-12 · Çözüm seçenekleri (kod yazılmadı, 21 Kasım)

**Bugün ekranda ne görünüyor:**
- **Puantaj ekranı** (`app/(panel)/puantaj`, `v_puantaj_canli` ve "Raporlu gün" sütunu) yalnızca İK menüsünde. Amir bu ekranı açamıyor.
- **Çalışan sayfası ve döküm** (`lib/dokum.ts`) `gun_kaydi` ve `duzeltme` tablolarını doğrudan okuyor. "raporlu" durumunu ve düzeltmenin eski / yeni değerini İK dışındaki rollere ekranda **"İzinli"** gösteriyor (`durumEtiketi`).
- **Düzeltme gerekçesi** (`d.gerekce`) çalışan sayfasında (`calisanlar/[id]/page.tsx`) herkese olduğu gibi yazılıyor. PDF'i yalnızca İK indirebiliyor.

Yani ekrandan sızan tek şey **gerekçe metni**. Diğer iki yol (durum, `raporlu_gun`), amirin kendi oturumuyla API'yi doğrudan çağırmasıyla açık; CLAUDE.md §4 "yetki kontrolü yalnızca ekrana bırakılmaz".

**(a) "raporlu"nun amire görünmesini kabul et, belgele; durum düzeltmelerinin gerekçesini amire gizle**
- **Ne yapılır:**
  - **Veritabanı:**
    - `duzeltme`'nin `amir_okur` politikası kaldırılır;
    - yerine `v_izin_amir` gibi süzen bir `v_duzeltme_amir` görünümü gelir;
    - görünüm, `alan = 'durum'` ise ya da düzeltme bir izne dayanıyorsa (`izin_id` dolu) gerekçeyi "İK tarafından düzeltildi" diye gösterir;
    - eski / yeni değerde "raporlu"yu "izinli" yapar.
  - **Belge:** `gun_kaydi.durum` ve `v_puantaj_canli.raporlu_gun`'ün amire görünmesi `docs/veritabani.md` "Bilinçli tercihler"e yazılır. KVKK gerekçesi örneğin: "Amir ekibinin raporlu olduğunu bilir, nedenini bilmez."
  - **Ekran (Gökalp):** `lib/dokum.ts`'de amir için düzeltmeler `v_duzeltme_amir`'den okunur (İK ve yönetici tablodan okumaya devam eder).
- **İş süresi:** veritabanı 1–1,5 saat (migration, görünüm, politika, test); ekran 0,5 saat.
- **Etkilenen:** `duzeltme` politikası, yeni görünüm, `lib/dokum.ts`, `calisanlar/[id]/page.tsx`. Başka bir ekran amir için `duzeltme` okumuyor (arandı: yalnızca `lib/dokum.ts`).
- **Risk:**
  - Düşük: tek okuma yeri var.
  - Görünüm `security_invoker` olmadığı için süzme koşulu (`tum_veriyi_gorur() or amirin_calisani_mi(...)`) görünümün içinde doğru yazılmalı; `v_izin_amir` örnek alınır ve test edilir.
  - KVKK açısından "raporlu" bilgisi amire açık kalır; ama ekran zaten "İzinli" gösteriyor, yani yalnızca API'yi elle çağıran bir amir görebilir.

**(b) Amire "raporlu" yerine "izinli" göster (veritabanı düzeyinde)**
- **Ne yapılır:** Üç yol iki yöntemden biriyle kapatılır:
  - **b1, görünümlerle:**
    - `gun_kaydi` ve `duzeltme`'nin amir politikaları kaldırılır; yerlerine "raporlu" → "izinli" çeviren `v_gun_kaydi_amir` ve `v_duzeltme_amir` gelir;
    - `v_puantaj_canli`'da İK ya da yönetici değilse `raporlu_gun` `izinli_gun`'e eklenir ve 0 gösterilir.
  - **b2, durum değerinden vazgeçmek:**
    - "raporlu" durumu tamamen kaldırılır; gece işi raporu da "izinli" yazar;
    - puantaj kodu (RPR) zaten izin türünden üretiliyor (`gun_kod_satirlari`, `izinli` dalı).
- **İş süresi:**
  - b1: veritabanı 2–3 saat, ekran 2–3 saat.
  - b2: veritabanı 4–6 saat ve ekran.
- **Etkilenen:**
  - **b1:** `gun_kaydi` ve `duzeltme` politikaları ile iki görünüm. Ekranda şunlar `gun_kaydi`'nı ilişki üzerinden okuyor:
    - `sorular/page.tsx` (`gun:gun_kaydi_id(...)`);
    - `itirazlar/page.tsx`;
    - `lib/dokum.ts`;
    - `puantaj/page.tsx`'in sayım sorguları.

    Amir politikası kalkınca soru ve itiraz ekranlarının amirdeki ilişki okumaları boş döner; bunlar görünümlere taşınmalı. PostgREST'in görünümlerde ilişki bulması da ayrıca denenmeli.
  - **b2:** `gece_isi_gun_kayitlari`, `gun_kod_satirlari`, `gun_katkisi`, `v_puantaj_canli`, `duzeltme_uygula` (PR #33'ün durum listesi), `kayit_duzelt`'in durum seçenekleri; ekranda `calisanlar/[id]/actions.ts` (`DURUMLAR`) ve `lib/dokum.ts`; testler (`ornek_veri_testi` S18, `ay_kilidi_testi` RPR sayıları, `durum_duzeltmesi_testi`).
- **Risk:**
  - b1 orta: amirin soru ve itiraz ekranları kırılabilir; 26 Kasım'a az kaldı.
  - b2 yüksek: puantaj kodları ve ERP aktarımı değişir; İK'nın izin kaydı olmadan elle verdiği rapor durumu RPR kodunu kaybeder.

**Önerim:** (a). Ekrandaki tek gerçek sızıntıyı (gerekçe) kapatıyor, değişiklik tek ekran dosyasıyla sınırlı, 26 Kasım öncesi güvenle yapılabilir. "raporlu"nun API'de açık kalması bilinçli bir sınırlılık olarak yazılır. İstenirse, yine düşük riskle, `v_puantaj_canli`'nın amir maskesi (b1'in yalnızca bu parçası) de eklenebilir.

### T-13 · İK, dosya yükleyerek kendi çalışılmış gününü üretebiliyor ve yükleyen kaydedilmiyor
- **Adım:** 3 · **Önem:** Yüksek (görevler ayrılığı atlanıyor ve iz yok; Kritik'e yakın)
- **Yer:**
  - `pdks.dosya_yukle` (son sürüm: `20261128010000_dosya_yukle_duzeltmesi.sql`): satırlarda yükleyenin kendi kartı denetlenmiyor;
  - `pdks.aktarim` ve `pdks.ham_okutma`: yükleyen kişi sütunu yok.
- **Ne oldu:**
  1. Üretim müdürü (İdari'nin amiri), İK müdürü Ahmet Er'e (4002) 9 Aralık için olağan bir vardiya planı girdi.
  2. İK müdürü kendi kartıyla (K4002) 07:55 giriş ve 17:05 çıkış içeren bir PDKS dosyası yükledi.
  3. Gece işini çalıştırdı.

  Sonuç: kendisi için "tamam, 480 dk" gün kaydı oluştu. Giriş kaynağı `pdks` görünüyor, gerçek bir okutmadan ayırt edilemiyor. `aktarim` tablosunda dosyayı kimin yüklediği yok; `ham_okutma`'da da yok.
- **Ne olmalıydı:** "Kimse kendi kaydında işlem yapamaz." Sistemdeki bütün doğrudan yollar engelli (yukarıdaki tabloda 21 deneme reddedildi). Okutma verisi bir çalışanın gününü belirlediği için, kendi kartının okutmasını İK'nın kendisi yükleyememeli; en azından yükleyen kaydedilmeli.
- **Kanıt:** `scratch/a3_kapsam_gorev.sql`, bölüm (c):
  ```
  dolayli|hazırlık: üretim müdürü 4002'ye 9 Aralık planı|çalıştı|1615
  dolayli|İK kendi kartıyla PDKS dosyası yükler (K4002)|çalıştı|122
  dolayli|İK gece işini çalıştırır (9 Aralık)|çalıştı|basarili
  sonuç: 4002 9 Aralık gün kaydı → tamam, 480 dk, giriş kaynağı pdks
  aktarim sütunları: id, kaynak, dosya_adi, dosya_ozeti, veri_tarihi, satir_sayisi, aktarim_zamani
  ```
- **Sade dille:** İK, kendi gününü düzeltemiyor; bu doğru. Ama işe gelmediği bir gün için kendi kartıyla "girdim, çıktım" satırları olan küçük bir dosya yükleyip gece işini çalıştırırsa, sistem o günü çalışılmış sayıyor ve maaşa giriyor. Dosyayı kimin yüklediği hiçbir yerde yazmadığı için sonradan bulmak da mümkün değil. Projede dosyaları İK yüklediği için bu ana veri yolu.
- **Öneri:**
  1. `aktarim`'a `yukleyen_id` eklensin (zorunlu; `dosya_yukle` oturumdan doldursun).
  2. `dosya_yukle`, yükleyenin kendi kartının (asıl ya da o an zimmetli geçici kartı) okutmasını içeren satırları reddetsin ya da İK'ya uyarı yazsın. Gerçek PDKS dosyasında İK'nın kendi okutmaları da olacağı için reddetmek yerine "kendi okutmasını içeren dosya" uyarısı ve ikinci İK onayı daha uygulanabilir.
- **Durum:** ✅ Düzeltildi (feature/T13-yukleyen). Migration: `20261213010000_yukleyen.sql`, test: `yukleyen_testi.sql`. Yükleyen kaydedilir; kendi okutmasını içeren dosyada diğer İK'ya uyarı gider. Okutmanın gerçekliği doğrulanmaz (bilinen sınırlılık).

#### T-13 · Çözüm seçenekleri (kod yazılmadı, 21 Kasım)

**Önerilen: yükleyeni kaydet + kendi okutmasını içeren dosyada uyarı**
- **Ne yapılır:**
  1. `aktarim`'a `yukleyen_id bigint references kullanici` eklenir. Seed'deki ve eski satırlar boş kalır; `dosya_yukle` her yeni satıra oturumdaki kullanıcıyı yazar. `aktarim` değiştirilemez bir tablo, ama sütun eklemek satırları güncellemediği için tetikleyiciye takılmaz.
  2. `dosya_yukle`, yazdığı okutmalar arasında **yükleyenin kendi kartını** (asıl kartı ya da o an zimmetli geçici kartı; `okutma_sahibi(...) = kullanici_calisani(yukleyen)`) içeren satır varsa dosya başına **bir** uyarı yazar. Örnek: tür `kendi_okutmasi_yuklendi`, çalışan = yükleyen, mesaj "Ahmet Er kendi kartının 2 okutmasını içeren pdks_20261209.csv dosyasını yükledi."
  3. Uyarının çalışanı yükleyen olduğu için, yükleyen bu uyarıyı **"görüldü" yapamaz** (görevler ayrılığı; Adım 3'te `uyari.goren_id` kontrolünün çalıştığı denendi). Uyarı başka İK'ya ya da yöneticiye kalır.
- **İş süresi:** veritabanı 2–3 saat (migration, `dosya_yukle`'nin son sürümünü temel alan yeniden yazım, `uyari.tur` kısıtı varsa yeni tür, test); ekran 0,5–1 saat.
- **Etkilenen:**
  - **Veritabanı:** `pdks.aktarim` (yeni sütun); `pdks.dosya_yukle` (son sürüm: `20261128010000`); `pdks.uyari` (tür listesi).
  - **Ekran (Gökalp):**
    - `veri-aktarimi/page.tsx`: aktarım listesine "Yükleyen" sütunu;
    - `lib/etiketler.ts`: yeni uyarı türünün Türkçe adı;
    - `uyarilar/page.tsx`: değişiklik gerekmez.
  - **Belgeler:** `docs/ekran_fonksiyonlari.md` (`dosya_yukle`), `docs/veritabani.md`.
- **Risk:**
  - **Gürültü:** gerçek bir günlük PDKS dosyasında İK'nın kendi okutmaları da olur. Her İK'nın kendi gününü içeren her dosya için bir uyarı çıkar; İK iki kişiyse her gün en az bir uyarı. Uyarı dosya başına bir kez yazılırsa ve mesaj satır sayısını söylerse yönetilebilir. Daha az gürültü için yalnızca **küçük dosyalarda** (ör. 20 satırın altı) ya da **o gün için ikinci kez gelen** PDKS dosyasında uyarmak düşünülebilir; bu kural Fırat'ın kararı.
  - **Demo:** 7 Aralık dosyalarında İK hesaplarının kartı yok (yalnızca Montaj), uyarı çıkmaz.
  - **Eski satırlar:** `yukleyen_id` boş kalır; "bilinmiyor" diye gösterilmeli.

**Elle yüklemenin genel riski (ayrıca not):** Sorun yalnızca "İK kendi gününü üretir" değil. Dosyaları İK elle yüklediği için, **herhangi bir İK herhangi bir çalışanın okutmasını uydurabilir**: gelmeyen birini gelmiş gösterebilir, ya da birini geç gelmiş gösterip aleyhine sonuç doğurabilir. Gece işi bu okutmayı gerçek PDKS okutmasından ayırt etmiyor (`giris_kaynagi = 'pdks'`). Yükleyenin kaydedilmesi bunu engellemez, yalnızca izini bırakır. Tam çözüm projenin kapsamı dışında:
- dosyaların PDKS sisteminden otomatik gelmesi (ör. SFTP, imzalı dosya, kaynak sistemin özetiyle karşılaştırma);
- elle yüklemenin "acil durum" sayılıp ikinci bir İK onayı istemesi.

Raporda **bilinen sınırlılık** olarak yazılmalı: "Demo ve ders projesi kapsamında dosyalar İK tarafından elle yüklenir; yükleyen kaydedilir, ama okutmanın gerçekliği doğrulanmaz."

### T-14 · Vekil amir her zaman yetkili; vekillik tarihi ya da koşulu yok
- **Adım:** 3 · **Önem:** Orta
- **Yer:** `pdks.oturum_departmanlari` (`oturum_kullanici_id() in (amir_id, vekil_amir_id)`) ↔ `pdks.soru_atanacak`
- **Ne oldu:** `departman.vekil_amir_id` dolu olduğu sürece vekil amir, asıl amir izinli olsun olmasın, o departmanın bütün gün kayıtlarını, düzeltmelerini, planlarını, itirazlarını görüyor; plan, itiraz ve fazla mesai talebi girebiliyor. Vekilliğin başlangıç ve bitiş tarihi yok. Oysa sorular vekile yalnızca asıl amir `izinli_mi = true` iken gidiyor (`soru_atanacak`). İki kural "vekil" kavramını farklı anlıyor.
- **Ne olmalıydı:** Planın beklentisi "vekillik bitince görmüyor mu". Vekillik bir süreyle ya da asıl amirin izniyle sınırlı olmalı. Ya da sürekli "yardımcı amir" olduğu bilinçli olarak yazılmalı.
- **Kanıt:** `scratch/a3_kapsam_gorev.sql`:
  ```
  sahip: Bobinaj gün kaydı=209, Bobinaj amiri izinli_mi=false      (scratch/a3_vekil.sql)
  vekil (montaj.amiri): Bobinaj gün kaydı=209
  vekil Bobinaj'a vardiya planı girebiliyor → çalıştı (plan 1611)
  vekillik kaldırılınca Bobinaj görünmüyor → 0 · plan girişi → "Bu çalışan sizin departmanınızda değil."
  vekillik tarihleri için sütun: departman.vekil_amir_id (tarih sütunu yok)
  ```
- **Sade dille:** Montaj amiri, Bobinaj amiri işteyken bile Bobinaj'ın bütün devam kayıtlarını her gün görüyor ve değiştirebiliyor. Vekillik "amir izindeyken" demek olmalıydı; sistemde ise süresiz bir ikinci amirlik. KVKK'nın "gerektiği kadar veri" ilkesine aykırı.
- **Öneri:**
  - Görünürlük ve işlem yetkisi soru yönlendirmesiyle aynı kurala bağlansın: vekil, yalnızca asıl amir `izinli_mi = true` iken yetkili olsun.
  - Ya da `departman`'a vekillik başlangıç ve bitiş tarihi eklensin.
  - Bilinçli tercihse `docs/veritabani.md`'ye yazılsın.
- **Durum:** Açık

### T-15 · İK kendi itirazını "incelemeye alabiliyor"
- **Adım:** 3 · **Önem:** Düşük
- **Yer:** `pdks.itiraz_incelemeye_al` (son sürüm: `20261119010000_ekran_fonksiyonlari.sql`); `itiraz_gorev_ayriligi` tetikleyicisi yalnızca `karar_veren_id`'yi denetliyor.
- **Ne oldu:** Başka bir İK'nın girdiği, İK müdürünün kendi günü hakkındaki itirazı İK müdürü "inceleniyor" durumuna aldı. Karar vermesi ise engellendi.
- **Ne olmalıydı:** Kişi kendi itirazının durumunu değiştirmemeli.
- **Kanıt:** `gorev|İK kendi itirazını incelemeye alamaz|reddedilmeli|çalıştı|`
- **Sade dille:** Kendi itirazına karar veremiyor, ama itirazı "inceleniyor" diye işaretleyip başka İK'ya "ben bakıyorum" izlenimi verebiliyor. Zararı küçük, kural yine de tutarsız.
- **Öneri:** `itiraz_incelemeye_al`'a `kullanici_calisani(v_ben) = calisan_id` kontrolü; ya da itiraza `inceleyen_id` sütunu eklenip tetikleyiciye dahil edilsin.
- **Durum:** Açık

### T-16 · "Talep eden onaylayamaz" kuralı ham İngilizce hata mesajıyla dönüyor
- **Adım:** 3 · **Önem:** Düşük
- **Yer:** `pdks.fazla_mesai_plani`'nın `fazla_mesai_talep_onay_farkli` CHECK kısıtı (`20261118020000_gorevler_ayriligi.sql`)
- **Ne oldu:** Kural çalışıyor, ama ekrana şu mesaj gidiyor: `new row for relation "fazla_mesai_plani" violates check constraint "fazla_mesai_talep_onay_farkli"`. Diğer bütün görevler ayrılığı kuralları "Görevler ayrılığı: …" diye Türkçe mesaj veriyor.
- **Ne olmalıydı:** Türkçe, anlaşılır mesaj.
- **Kanıt:** `gorev|talep eden İK kendi talebini onaylayamaz|reddedilmeli|reddedildi|new row for relation "fazla_mesai_plani" violates check constraint …`
- **Sade dille:** İK kendi istediği fazla mesaiyi onaylamaya çalışınca sistem doğru olarak durduruyor, ama ekranda İngilizce, teknik bir hata görüyor.
- **Öneri:** `fazla_mesai_karar`'a, kısıta varmadan önce Türkçe bir kontrol eklensin.
- **Durum:** Açık

### Denediklerim
- RLS: 44 nesne × 8 oturum, sayılar beklenenle (`scratch/a3_rls_sonuc.txt`).
- Amirin başka departmandaki kayda id ile okuma (3 tablo) ve yazma (4 RPC) denemeleri.
- Vekillik: asıl amir işteyken, vekillik kaldırılınca; vekillik tarihleri için şema.
- İzin türü: `izin`, `v_izin_amir`, `gun_kaydi.durum`, `v_puantaj_canli`, `duzeltme` (gerekçe dahil), `uyari`, `v_departman_ozet`.
- Görevler ayrılığı: 22 doğrudan deneme (İK, amir, güvenlik), 1 dolaylı yol (dosya yükleme + gece işi).

### Denemediklerim
- **Uyarı mesajlarında izin türü:** amir uyarıları hiç göremiyor (0 satır), o yüzden içeriklerine amir gözüyle bakmadım. İK ve yönetici görüyor; bu beklenen.
- **Diğer dolaylı yollar:**
  - `ariza_gir` ile kendi PDKS okuyucusuna arıza girip kapı kaydıyla kendi gününü düzeltmek (gece işi arızalı aralıkta kanıtla düzeltiyor);
  - kendi kart numarasını başkasının kartına tanımlamak.

  İkincisi kart tablosundaki kurallarla Adım 10'da.
- **İki İK'nın birbirinin kaydını düzeltmesi (anlaşmalı):** görevler ayrılığının kapsamı dışında.
- **RLS'in yazma yönü:** `authenticated`'ın hiçbir tabloda yazma yetkisi yok (Adım 1 K5), o yüzden INSERT / UPDATE politikaları denenmedi.

### Şüpheler
- **(Adım 5'te kapandı: bu turdaki "eskale yok" görüntüsü, sorgunun amir oturumuyla çalıştırılmasından; amir RLS yüzünden İK'nın e-postasını göremiyor. S22 gerçekte İK'ya eskale oluyor.)** **S22'nin eskale durumu bu turda "eskale yok":** Adım 2'deki hazırlıkta S22 İK'ya eskale edilmişti; bu turda (Kasım'ın tamamı işlenince) soru üretim müdüründe, eskale olmadan duruyor. Eskalasyonun oluşturma zamanına (`now()`) bağlı olmasından kaynaklanıyor olabilir: `son_cevap_tarihi` gece işinin çalıştığı güne göre hesaplanıyor. Adım 7'de incelenecek.

---

## Adım 4 — Veri aktarımı (`dosya_yukle`) (21 Kasım 2026)

**Betikler:**

| Betik | Ne sınıyor |
|---|---|
| `scratch/a4_dosya.sql` | 45 deneme |
| `scratch/a4_sonuc.sql` | Yanlış gün, geç dosya, ileri tarih |
| `scratch/a4_ileri_tarih.sql` | Erken eskalasyon |
| `scratch/a4_kilitli.sql` | Kilitli aya yükleme |

**Nasıl denendi:**
- Oturum: İK (`ik.muduru`).
- Her deneme ayrı bir alt işlemde çalıştı; öncesinde ve sonrasında `aktarim`, `ham_okutma` ve `kanit_kaydi` satır sayıları alındı. Reddedilen bir dosyada bu sayılar değişmemeli, yani yarım yükleme kalmamalı.
- Hatalı satır denemelerinde her dosyada 2 doğru satır ve 1 hatalı satır var.
- Fonksiyonun son sürümü `pg_get_functiondef` ile okundu (`scratch/a4_dosya_yukle_def.sql`, kaynak `20261128010000_dosya_yukle_duzeltmesi.sql`).

### Sonuç tablosu

| Deneme | Beklenen | Sonuç | Mesaj / dönen aktarım no | Yarım yükleme | ms |
|---|---|---|---|---|---|
| == sonuçlar (ad | beklenen | durum | mesaj | **VAR** | ms) |
| 1 geçerli PDKS dosyası (3 satır, SHA-256 verildi) | kabul, 3 satır | kabul | 122 | — | 4 |
| 1b özet verilmezse | kabul; özet md5 | kabul | 123 | — | 2 |
| 2 aynı dosya (aynı özet) ikinci kez | red | red | Bu dosya daha önce yüklenmiş. | yok | 1 |
| 2b aynı içerik, farklı ad, özet verilmeden (md5 aynı) | red? | red | Bu dosya daha önce yüklenmiş. | yok | 1 |
| 2c aynı içerik, ekran farklı özet gönderirse | kabul? 0 yeni satır | kabul | 124 | — | 1 |
| 3 aynı gün, farklı içerik (yeni okutmalar) | kabul, ek satırlar | kabul | 125 | — | 2 |
| 4a boş kart | red | red | 4. satırda kart numarası boş ya da geçersiz. | yok | 1 |
| 4b boş zaman | red | red | 4. satırda zaman geçersiz; saat dilimiyle gelmeli (ör. 2026-11-13T07:52:00+03:00). | yok | 1 |
| 4c geçersiz saat 25:00 | red | red | Satırlardan birinde zaman okunamadı (ör. 31.02 gibi olmayan bir tarih). | yok | 1 |
| 4d olmayan gün 31 Şubat | red | red | Satırlardan birinde zaman okunamadı (ör. 31.02 gibi olmayan bir tarih). | yok | 1 |
| 4e saat dilimi yok | red | red | 4. satırda zaman geçersiz; saat dilimiyle gelmeli (ör. 2026-11-13T07:52:00+03:00). | yok | 1 |
| 4f UTC (Z) saat dilimi | kabul | kabul | 126 | — | 1 |
| 4g olmayan okuyucu | red | red | Okuyucu tanımlı değil ya da bu kaynağa ait değil: PDKS-9 (4. satır) | yok | 1 |
| 4h başka kaynağın okuyucusu (KAPI-1, pdks dosyası) | red | red | Okuyucu tanımlı değil ya da bu kaynağa ait değil: KAPI-1 (4. satır) | yok | 1 |
| 4i okuyucu küçük harf | kabul | kabul | 127 | — | 1 |
| 4j bilinmeyen kart | kabul (gece işi işaretler) | kabul | 128 | — | 1 |
| 4k Türkçe karakterli kart (KÇ01) | red | red | 4. satırda kart numarası boş ya da geçersiz. | yok | 1 |
| 4l 33 karakter kart | red | red | 4. satırda kart numarası boş ya da geçersiz. | yok | 1 |
| 4m tırnak, noktalı virgül, -- içeren kart | red | red | 4. satırda kart numarası boş ya da geçersiz. | yok | 1 |
| 4n tırnak ve -- içeren okuyucu | red | red | Okuyucu tanımlı değil ya da bu kaynağa ait değil: PDKS-1'-- (4. satır) | yok | 1 |
| 4o 1000 karakter okuyucu | red | red | Okuyucu tanımlı değil ya da bu kaynağa ait değil: XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX… | yok | 1 |
| 4p yön GIRIS (büyük harf) | kabul | kabul | 129 | — | 1 |
| 4q yön geçersiz (in) | red | red | 4. satırda yön "giris", "cikis" ya da boş olmalı. | yok | 1 |
| 4r yön boş | kabul | kabul | 130 | — | 1 |
| 4s ileri tarih (2030) | ? | kabul | 131 | — | 1 |
| 4t dosyanın gününden çok farklı tarih (2020) | ? | kabul | 132 | — | 1 |
| 4u Türkçe karakterli dosya adı | kabul | kabul | 133 | — | 1 |
| 4v SQL içeren dosya adı | kabul (metin olarak) | kabul | 134 | — | 1 |
| 4w 300 karakter dosya adı | red | red | Dosya adı boş ya da 255 karakterden uzun. | yok | 0 |
| 4x satır nesne değil | red | red | 1. satır okunamadı. | yok | 1 |
| 4y boş dizi | red | red | Dosyada satır yok. | yok | 1 |
| 4z geçersiz kaynak | red | red | Dosya türü geçersiz: xyz. Beklenen: pdks, kapi, yemekhane, servis. | yok | 0 |
| 4aa özet biçimi geçersiz | red | red | Dosya özeti geçersiz (64 haneli SHA-256 bekleniyor). | yok | 0 |
| 4ab dosyanın günü ile satırlar farklı (gün 12 Aralık, satırlar 10 Aralık) | ? | kabul | 135 | — | 1 |
| 5a 50.000 satır | kabul; süre | kabul | 136 | — | 994 |
| 5b 200.001 satır | red | red | Bir dosyada en fazla 200.000 satır olabilir (gelen: 200001). | yok | 317 |
| 6 montaj.amiri | red | red | Bu işlem için yetkiniz yok. | yok | 1 |
| 6 guvenlik | red | red | Bu işlem için yetkiniz yok. | yok | 1 |
| 6 fabrika.muduru | red | red | Bu işlem için yetkiniz yok. | yok | 1 |
| 6 isg.uzmani | red | red | Bu işlem için yetkiniz yok. | yok | 1 |
| 6 sistem.yoneticisi | red | red | Bu işlem için yetkiniz yok. | yok | 1 |
| 7a İK aktarim satırını doğrudan günceller | red | red | permission denied for table aktarim | yok | 1 |
| 7b İK ham okutmayı doğrudan siler | red | red | permission denied for table ham_okutma | yok | 1 |
| 7c İK doğrudan ham okutma ekler (RPC dışından) | red | red | permission denied for table ham_okutma | yok | 1 |

**Ek kontroller:**
- **Geçerli dosyanın aktarım kaydı:** `(pdks, pdks_20261210.csv, 2026-12-10, satir_sayisi=3, özet=verilen SHA-256, aktarim_zamani dolu)`; o aktarıma bağlı 3 ham okutma. ✅
- **Özet verilmezse:** `dosya_ozeti` 32 haneli md5 (`md5(p_satirlar::text)`); aynı içerik ikinci kez reddediliyor (2b). ✅
- **Aynı gün, farklı içerik (3):** ikinci aktarım kabul ediliyor. Dosyada önceden gelmiş okutma (K1001 07:55) atlanıyor, yeni okutma (K1003) ekleniyor: `ham` 3176 → 3177. Mantıklı. ✅
- **Kilitli aya yükleme:** Ekim kilitliyken Ekim'e ait dosya kabul edildi (aktarım 124). Puantajı değiştirmiyor, çünkü gece işi kilitli aya gün kaydı yazamıyor; ama veri sessizce ekleniyor (T-17).
- **Yanlış günle adlandırılmış dosya (A):** dosyanın günü 7 Aralık, satırlar 10 Aralık. Gece işi 7 Aralık'ı "PDKS verisi tam" saydı ve **Montaj'ın 10 kişisinin 10'una "hiç kayıt yok" sorusu** açtı (T-17).
- **İşlenmiş güne geç gelen dosya (B):** Ali'nin (1003) 4 Kasım PDKS girişi sonradan yüklendi. Okutma kaydedildi, ama gece işi yeniden çalışınca gün değişmedi: `soru_bekliyor`, giriş yok, soru açık (T-19).
- **İleri tarihli dosya (C):** 2030 tarihli bir dosyadan sonra gece işi 31 Aralık 2029 için de çalıştırılabildi. O sırada açık olan **10 sorunun 10'u, süreleri dolmadan eskale oldu** (T-18).

### Kod incelemesi (Ek A, `dosya_yukle`)

| # | Soru | Sonuç |
|---|---|---|
| 1 | Yetki | ✅ İlk satır `yetki_gerekli('ik')`. Diğer 5 rol reddedildi (6) |
| 2 | Görevler ayrılığı | ❌ Yükleyenin kendi kartı denetlenmiyor (T-13, Adım 3) |
| 3 | Kapsam | — Yükleme yalnızca İK'nın işi; departman sınırı yok, olması da beklenmez |
| 4 | Zincirleme etki | ⚠️ Yeni okutma, işlenmiş günün gün kaydına yansımıyor ve bunu söylemiyor (T-19) |
| 5 | Kilitli ay | ⚠️ Kilitli aya ait okutma kabul ediliyor (T-17) |
| 6 | İz | ❌ Yükleyen kaydedilmiyor (T-13). Dosya adı, özeti, günü, zamanı ve yazılan satır sayısı kaydediliyor |
| 7 | Kenar durumlar | ⚠️ Satır tarihleri dosyanın günüyle karşılaştırılmıyor (T-17); dosyanın günü ileri olabiliyor (T-18); özet istemciden geliyor (T-20). Dosya içi tekrarlar bir kez yazılıyor ✅; boş yön kabul ✅ |
| 8 | Saat dilimi | ✅ Saat dilimi olmayan zaman reddediliyor (4e); `Z` (UTC) kabul ediliyor ve doğru çevriliyor (4f) |
| 9 | Güvenlik | ✅ `search_path = pdks, pg_temp`; bu, `pg_temp`'i sona koyan tek `security definer` fonksiyon (bkz. T-03). Dinamik SQL yok; tırnak, `;` ve `--` içeren değerler veri olarak kaldı (4m, 4n, 4v). Geçici tablo `dosya_satiri` oturumun kendi geçici şemasında |
| 10 | Test | ⚠️ `dosya_yukle_testi.sql` 24 kontrol; satır tarihi ile dosyanın günü, ileri tarih, kilitli ay, işlenmiş güne geç dosya sınanmıyor |

### Bulgular

### T-17 · Satır tarihleri dosyanın günüyle karşılaştırılmıyor; yanlış adlı dosya bütün bir günü "hiç kayıt yok" yapıyor
- **Adım:** 4 · **Önem:** Orta (demo günü gerçekleşebilir)
- **Yer:** `pdks.dosya_yukle` (son sürüm: `20261128010000`); `pdks.pdks_verisi_tam_mi`
- **Ne oldu:** `p_veri_tarihi` ile satırların tarihleri karşılaştırılmıyor; 2030, 2020 ve dosyanın gününden farklı satırlar kabul ediliyor. Kilitli aya ait satırlar da kabul ediliyor. Gece işi bir günün PDKS verisini, o gün için `veri_tarihi`'si olan bir PDKS aktarımı varsa "tam" sayıyor. Satırların gerçekten o güne ait olup olmadığına bakmıyor.
- **Ne olmalıydı:** Satırlar dosyanın gününe ya da ertesi güne düşmeli (gece vardiyası). Ekran (`lib/aktarim/denetim.ts`) bunu zaten **uyarı** olarak gösteriyor, ama yüklemeyi durdurmuyor; veritabanı hiç denetlemiyor.
- **Kanıt:** `scratch/a4_sonuc.sql` (A):
  ```
  A yükleme: aktarim 137     (dosya günü 2026-12-07, satırlar 2026-12-10)
  A gece işi 7 Aralık: basarili {"soru": 10, "gun_kaydi": 10, ...}
  A sonuç 7 Aralık: gün kaydı=10, durumlar=soru_bekliyor, amir sorusu=10 (hic_kayit_yok)
  ```
  Ayrıca `scratch/a4_dosya.sql` 4s, 4t, 4ab (kabul) ve `scratch/a4_kilitli.sql` (kilitli Ekim'e aktarım 124).
- **Sade dille:** İK yanlışlıkla 10 Aralık'ın dosyasını "7 Aralık" diye yüklerse, sistem 7 Aralık'ın kayıtları geldi sanıyor. O gün kimsenin okutması olmadığı için 10 çalışanın hepsi için amire "bu kişi hiç gelmemiş" sorusu gidiyor. Demo günü yanlış dosya seçilirse, demo ekranında 10 yanlış soru görünür. Dosya bir kez yüklenince silinemediği için o gün bir daha "boş" sayılamıyor.
- **Öneri:**
  - `dosya_yukle`, satırların en az %X'i `p_veri_tarihi` ile ertesi gün dışındaysa reddetsin (ya da `p_zorla` istesin).
  - Kilitli aya ait satırları reddetsin.
  - `dosya_yukle_testi`'ne üç kontrol eklensin.
- **Durum:** Açık

### T-18 · İleri tarihli bir dosya, gece işinin gelecekteki bir gün için çalışmasına ve açık soruların hepsinin erken eskale olmasına yol açıyor
- **Adım:** 4 · **Önem:** Orta
- **Yer:** `pdks.dosya_yukle` (`p_veri_tarihi` için üst sınır yok) → `pdks.gece_isi_calistir`'ın "işlenebilir gün" sınırı (`greatest(current_date - 1, max(veri_tarihi))`) → `pdks.gece_isi_eskale(p_gun)` (`son_cevap_tarihi <= p_gun`)
- **Ne oldu:** İK, 1 Ocak 2030 tarihli tek satırlık bir PDKS dosyası yükledi. Bu, gece işinin 2030'a kadar herhangi bir gün için çalıştırılmasını mümkün kıldı. Gece işi 31 Aralık 2029 için çalıştırılınca eskalasyon adımı o günü "bugün" saydı ve 7 Aralık'ta açılmış, süresi 11 Aralık'ta dolacak 10 sorunun 10'unu hemen üst amire gönderdi. Ayrıca 2029 için 4 "dosya gelmedi" uyarısı yazıldı ve `gece_isi` tablosuna 2029 satırı eklendi.
- **Ne olmalıydı:** Dosyanın günü bugünden (en fazla ertesi günden) ileri olamamalı. Gece işi, verisi olmayan gelecek bir gün için çalışmamalı; eskalasyon da "bugün"ü gerçek tarihten almalı.
- **Kanıt:** `scratch/a4_ileri_tarih.sql`:
  ```
  önce:  açık soru=10, eskale=0, son cevap tarihleri=2026-12-11
  sonra: açık soru=0, eskale=10
  yeni uyarılar: dosya_gelmedi ×4, soru_eskale ×10
  gece_isi satırı 2029-12-31: 1
  ```
- **Sade dille:** Tarihi yanlış yazılmış tek bir dosya, örneğin 2026 yerine 2030, sistemin takvimini ileri alıyor. Biri o ileri tarih için gece işini çalıştırırsa, amirlerin cevaplamak için 3 günü olan bütün sorular hemen "süresi geçti" sayılıp üst amire ve İK'ya gidiyor; uyarı listesi de sahte "dosya gelmedi" uyarılarıyla doluyor. Silme olmadığı için geri alınamıyor.
- **Öneri:**
  - `dosya_yukle`: `p_veri_tarihi <= bugün + 1` kontrolü.
  - `gece_isi_calistir`'ın sınırı `current_date`'i aşmasın; demo da bugünden ileriye gitmiyor (7 Aralık dosyası 7 Aralık'ta yükleniyor).
  - Bunun ayrıca bir de testi yazılsın.
- **Durum:** Açık

### T-19 · İşlenmiş bir güne sonradan gelen dosya sessizce yok sayılıyor
- **Adım:** 4 · **Önem:** Görüş
- **Yer:** `pdks.dosya_yukle` ↔ `pdks.gece_isi_gun_kayitlari` ("var olan kayıt bozulmaz, yalnızca eksikler eklenir")
- **Ne oldu:** Ali Demir'in (1003) 4 Kasım günü işlenmişti: PDKS girişi yok, amire soru açık. Sonradan, eksik PDKS girişini (07:50) içeren bir dosya yüklendi ve kabul edildi; okutma kaydedildi. Gece işi o gün için yeniden çalıştırıldı, ama gün kaydı değişmedi ve soru açık kaldı. `dosya_yukle` İK'ya "bu gün zaten işlenmiş; yeni okutmalar gün kaydına yansımaz" demiyor.
- **Ne olmalıydı:** Bu davranış bilinçli ve belgelenmiş (`docs/veritabani.md`: "Tekrar çalıştırmak güvenlidir…"). Ama İK dosyayı yükleyince sorunun çözüldüğünü sanabilir. Ya uyarılmalı ya da yeni okutma, açık sorusu olan günde bir öneriye dönüşmeli.
- **Kanıt:** `scratch/a4_sonuc.sql` (B):
  ```
  B önce:  1003 4 Kas → durum=soru_bekliyor, giriş=yok, soru=kanit_vardiya_sonrasi/acik
  B geç dosya: aktarim 138 · gece işi yeniden: basarili
  B sonra: 1003 4 Kas → durum=soru_bekliyor, giriş=yok, soru=kanit_vardiya_sonrasi/acik · bu güne ait PDKS okutması: 2
  ```
- **Sade dille:** Okuyucudan geç gelen bir kayıt sisteme giriyor ama günün hesabına girmiyor. İK "dosyayı yükledim, düzeldi" sanıyor; oysa amirin sorusu hâlâ bekliyor ve sonuç ancak elle cevapla düzeliyor.
- **Öneri:** `dosya_yukle`, satırlarından biri gün kaydı açılmış bir güne düşüyorsa sonuçta (ya da uyarı tablosunda) bunu bildirsin: "3 okutma işlenmiş günlere ait; o günler elle düzeltilmeli." Ekran bunu yükleme özetinde göstersin.
- **Durum:** Açık

### T-20 · Dosya özeti istemciden geliyor; aynı dosya başka bir özetle yeniden "yüklenebiliyor"
- **Adım:** 4 · **Önem:** Düşük
- **Yer:** `pdks.dosya_yukle` (`p_dosya_ozeti`)
- **Ne oldu:** SHA-256 özetini ekran hesaplayıp gönderiyor. Sunucu yalnızca biçimine bakıyor (64 haneli onaltılık), içerikle eşleşip eşleşmediğini bilmiyor. Aynı satırlar farklı bir özetle gönderilince ikinci bir aktarım satırı oluşuyor (2c). Okutmalar tekrar yazılmadığı için zararı küçük: satır sayısı 0. Özet verilmezse `md5` kullanılıyor, yani aynı sütunda iki farklı algoritmanın özeti duruyor.
- **Ne olmalıydı:** "Aynı dosya ikinci kez yüklenemez" kuralı istemcinin dürüstlüğüne bağlı olmamalı. Sunucu özeti kendisi hesaplasın; ya da satırların kanonik özetini ayrıca tutsun.
- **Kanıt:** `2c aynı içerik, ekran farklı özet gönderirse | kabul | aktarım 124 | ham 3176 → 3176`
- **Sade dille:** Ekranı atlayıp API'yi doğrudan çağıran biri aynı dosyayı tekrar tekrar "yükleyebilir". Veri çoğalmaz, ama aktarım listesinde boş, gereksiz satırlar birikir.
- **Öneri:** Sunucuda satırların kanonik biçiminin SHA-256'sı (`encode(sha256(...), 'hex')`) hesaplanıp ikinci bir tekil anahtar olarak tutulsun.
- **Durum:** Açık

### T-21 · Hata mesajı kullanıcı girdisini kısaltmadan geri yansıtıyor
- **Adım:** 4 · **Önem:** Düşük
- **Yer:** `pdks.dosya_yukle` ("Okuyucu tanımlı değil ya da bu kaynağa ait değil: %")
- **Ne oldu:** 1000 karakterlik okuyucu kodu, hata mesajında 1000 karakter olarak döndü.
- **Ne olmalıydı:** Mesajdaki değer kısaltılmalı, ör. ilk 40 karakter ve "…".
- **Kanıt:** `4o 1000 karakter okuyucu | red | Okuyucu tanımlı değil …: XXXXXXXX… (1000 karakter)`
- **Sade dille:** Bozuk bir dosyada ekrana sayfa uzunluğunda bir hata mesajı çıkar. Güvenlik sorunu değil (SQL metnine eklenmiyor), yalnızca görünüm.
- **Öneri:** `left(v_deger, 40)`.
- **Durum:** Açık

### Denediklerim
- **45 deneme** (sonuç tablosu):
  - geçerli dosya ve kayıt alanları;
  - aynı dosya ve aynı içerik;
  - aynı gün farklı içerik;
  - 26 hatalı satır ya da dosya türü;
  - 50.000 ve 200.001 satır;
  - 5 yetkisiz rol;
  - İK'nın tablolara doğrudan yazması.
- **Gece işine etki:** yanlış günlü dosya (A), işlenmiş güne geç dosya (B), ileri tarihli dosya ve erken eskalasyon (C).
- **Kilitli aya yükleme.**
- **Kod okuma:** Ek A'nın 10 sorusu.

### Denemediklerim
- **Ekran üzerinden CSV yükleme:** Papa Parse, `crypto.subtle` ile özet ve dosya adından gün okuma (`lib/aktarim/denetim.ts`) denenmedi. Ekranın uyarıları yalnızca kod okunarak not edildi.
- **50.000 satırın HTTP üzerinden gönderilmesi:** yalnızca veritabanı süresi ölçüldü (994 ms). Supabase / PostgREST'in istek boyutu sınırı ve ağ süresi denenmedi. 50.000 satırlık JSON yaklaşık 5 MB eder.
- **"Aynı anda başka bir aktarım yapıldı" yolu:** eş zamanlı iki yükleme gerektiriyor, denenmedi.
- **Yemekhane ve servis dosyaları:** ayrı ayrı denenmedi; kapı ve PDKS dosyası denendi. Kod dört kaynak için aynı yolu kullanıyor.

### Şüpheler
- **Çok büyük dosyada HTTP sınırı:** PostgREST ve Supabase'in varsayılan istek gövdesi sınırı 50.000 satırlık dosyayı geri çevirebilir; o zaman hata ekranda anlaşılmaz bir ağ hatası olarak görünür. 2000 çalışanlı bir fabrikada günlük PDKS dosyası yaklaşık 4.000–8.000 satır eder; bu sınırın altında kalması muhtemel.
- **Gece vardiyası ertesi güne geçiyor:** bu yüzden T-17'nin kuralı "dosyanın günü ya da ertesi günü" olmalı. Gece yarısını geçen vardiyanın çıkış okutması ertesi günün dosyasında da gelebilir. Adım 5'te bakılacak.

---

## Adım 5 — Gece işi ve örnek veri senaryoları (21 Kasım 2026)

**Betikler:**

| Betik | Ne sınıyor |
|---|---|
| `scratch/a5_senaryo.sql` | S1–S32 |
| `scratch/a5_ek.sql` | Tekrar, eksik dosya, ayın son günü, kilitli ay, hata |
| `scratch/a5_tz.sql` | Üç saat dilimi |
| `scratch/a5_sure.sql`, `scratch/a5_zaman_asimi.sql` | Süre ve zaman aşımı |
| `scratch/a5_kod/*.sql` | Okunan 21 fonksiyonun son sürümleri |

Hepsi tek işlem ve sonda `ROLLBACK`. Not: test sırasında Docker kapalıydı; Docker Desktop açılıp yerel Supabase yeniden kuruldu (yalnızca yerel).

### S1–S32 (Kasım, İK oturumuyla `gece_isi_tetikle('2026-11-01', '2026-11-30')`; 30 günün 30'u `basarili`)

| # | Beklenen (`docs/ornek_veri.md`) | Gerçekleşen | |
|---|---|---|---|
| S1 | kanıtla düzeltilir | giriş 03.11 08:00 kaynak=kanit, durum=tamam, düzeltme=gece_isi:giris_zamani | ✅ |
| S2 | soru kanit_vardiya_sonrasi | kanit_vardiya_sonrasi/eskale → montaj.amiri@example.com (eskale: uretim.muduru@example.com) | ✅ |
| S3 | çıkış 17:12 (kanıt) | çıkış 05.11 17:12 kaynak=kanit | ✅ |
| S4 | soru cikis_yok | cikis_yok/eskale → montaj.amiri@example.com (eskale: uretim.muduru@example.com) | ✅ |
| S5 | ikinci giriş mukerrer | mukerrer 07:41:45 | ✅ |
| S6 | GK-01 okutmaları İbrahim'e; gecici_kart_cakisma | gün tamam 10.11 07:42–10.11 17:09, uyarı=1 | ✅ |
| S7 | sik_kart_unutma | uyarı=1 | ✅ |
| S8 | eski kart iptal_kart işaretli | iptal_kart, uyarı iptal_kart_okutma=1 | ✅ |
| S9 | iade_edilmedi + cakisma | iade_edilmedi=1 cakisma=1 | ✅ |
| S10 | arıza şüphesi; girişler kapı kaydıyla | arıza=1, uyarı=1, 19 Kas Bobinaj V1 girişleri: kanit,kanit,kanit | ✅ |
| S11 | kart_paylasim_suphesi 2002–2003 | Kart paylaşımı şüphesi: 2002 (Kemal Aslan) ve 2003 (Murat Polat) kartları 11.2026 ayında 5 farklı günde 5 saniye içinde arka arkaya okutuldu. Ceza değ… | ✅ |
| S12 | tek iş günü 16 Kas | giriş 16.11 21:48, çıkış 17.11 06:10, durum=tamam | ✅ |
| S13 | gün işlenmez; 1597 gün kaydı | gün=yok, plan=bekliyor, toplam=1597 | ✅ |
| S14 | geç 35 dk, erken 40 dk | geç=35 erken=40 | ✅ |
| S15 | planlı fazla mesai 120 | fazla_mesai=120 fm50=120 çıkış 20.11 19:05 | ✅ |
| S16 | fm_plansiz_calisma; karar İK | uyarı=1, havuz=150/inceleme_bekliyor | ✅ |
| S17 | fm_onay_yok | uyarı=1 | ✅ |
| S18 | gün "izinli" (amir türü göremez) | 2007 23=raporlu, 2007 24=raporlu, 2007 25=raporlu, 2008 26=izinli, 2008 27=izinli | ❌ |
| S19 | hic_kayit_yok; devamsızlık İK'da | hic_kayit_yok/eskale → bobinaj.amiri@example.com (eskale: uretim.muduru@example.com), gün=soru_bekliyor | ✅ |
| S20 | bilinmeyen kart | bilinmeyen_kart | ✅ |
| S21 | dosya_gelmedi (servis 27 Kas) | 27.11.2026 günü için servis dosyası yüklenmedi. | ✅ |
| S22 | soru üst amire (Levent) | giris_yok/eskale → uretim.muduru@example.com (eskale: ik.uzmani@example.com) | ✅ |
| S23 | gecici_kart_zimmetsiz GK-05 | Geçici kart GK-05, kimseye zimmetli değilken 27.11.2026 08:10 saatinde okutuldu. | ✅ |
| S24 | Ferhat 17 Kas tek gün, mola 60, gece 315; Gökhan 2 Kas çıkışı 3 Kas | Ferhat giriş 16.11 23:39 mola=60 gece=315; Gökhan çıkış 03.11 00:07 | ✅ |
| S25 | dolmus bir kez (+ doluyor), bölge uyarısı yok | dolmus=1 doluyor=1 yetkisiz=0 | ✅ |
| S26 | doluyor (muayene 15.12) | 5302: periyodik sağlık muayenesi 15.12.2026 tarihinde doluyor. | ✅ |
| S27 | Selim yetkisiz, Hakan değil | Selim=1 Hakan=0 | ✅ |
| S28 | 3 havuz: 150, 100, 485 | 3004:150:vardiya_sonrasi, 3005:100:vardiya_sonrasi, 5102:485:tatil_calismasi | ✅ |
| S29 | FM100 480, kod FM100 | fm100=480, kod=FM100:480 | ✅ |
| S30 | FM100 0, havuz tatil_calismasi | fm100=0, havuz=tatil_calismasi:485 | ✅ |
| S31 | Onur −152, İrem +29 | 6002=-152, 6202=29 | ✅ |
| S32 | giriş 09:17 kanıtla, soru yok | giriş 18.11 09:17 kaynak=kanit, soru yok | ✅ |

**32'nin 31'i ✅.**
- **S18 ❌:** belge "Gün izinli" diyor, veritabanında rapor günleri `raporlu`. İzin türü, ekranda olduğu gibi gizlenmiyor; aynı konu T-12'de. Belge düzeltilmeli (T-22).
- **Adım 3'teki şüphe kapandı:** S22, üretim müdürüne atanıyor ve süre dolunca İK'ya eskale oluyor (`→ uretim.muduru (eskale: ik.uzmani)`). Adım 3'te "eskale yok" görünmesi, sorguyu amir oturumuyla çalıştırmamdan kaynaklanıyordu: amir, RLS yüzünden İK kullanıcısının e-postasını göremiyor.

### Ek denemeler

| # | Deneme | Beklenen | Gerçekleşen | |
|---|---|---|---|---|
| 1 | Kasım'ı ikinci kez işlemek | Çift kayıt yok | Gün kaydı (1597), düzeltme (10), soru (4), uyarı (20), işaret (4), arıza (1) ve havuz (3) sayıları aynı. Gün kayıtlarının içerik özeti aynı | ✅ |
| 2a | PDKS dosyası yok, kapı var (12 Ekim) | Yalnızca "dosya gelmedi"; gün kaydı yok | Gün kaydı 0; pdks, yemekhane, servis için "dosya gelmedi" | ✅ |
| 2b | PDKS var, kapı yok (13 Ekim) | ? | Gün kayıtları açıldı. PDKS girişi olmayan EK02 için **hemen** amire `giris_yok` sorusu; kapı için "dosya gelmedi" | ⚠️ T-23 |
| 2c | 2b'den sonra kapı dosyası gelir (EK02 kapı 07:50) ve gece işi yeniden çalışır | Kanıtla düzelmeli | Gün `soru_bekliyor`, giriş yok, soru açık. İki dosya birlikte gelseydi gün 08:00 kanıtla tamamlanırdı (aynı kurulumla denendi) | ❌ T-23 |
| 3 | Gece yarısını geçen vardiyalar, 30 Kasım → 1 Aralık | Doğru güne | 2002–2004 V2, 2005–2007 V3 (çıkış 1 Aralık 06:04–06:10), 5002 ve 5102 16–24 (çıkış 1 Aralık 00:01–00:08): 8'i de 30 Kasım'a, `tamam`. S12 ve S24 de doğru | ✅ |
| 4 | Oturum saat dilimi UTC, İstanbul, New York | Aynı sonuç | Zamanlar saat diliminden bağımsız (epoch) biçime çevrildi; 7 parmak izinin 7'si üç saat diliminde aynı: gün kaydı, düzeltme, soru, uyarı, işaret, esnek fark, 2277 puantaj kodu | ✅ |
| 5a | Kilitli Kasım'da işlenmiş bir günü yeniden işlemek | Değiştirmemeli | `basarili`, gün kayıtları değişmedi | ✅ |
| 5b | Kilitli Kasım'da işlenmemiş planlı gün (plan sahibin gözüyle eklendi) | Değiştirmemeli | Değiştirmedi; ama gece işi o gün için `hatali` bitti: "2026-11-28 günü kilitli bir döneme ait…" | ⚠️ T-26 |
| 6 | Bir çalışanda hata (amiri olmayan departman + bütün İK hesapları pasif → soru atanamıyor) | ? | **Günün tamamı geri alındı:** 77 planlı kişiden 0 gün kaydı. `gece_isi` satırı `hatali`; mesaj `null value in column "atanan_id" of relation "amir_sorusu" violates not-null constraint` | ⚠️ T-25 |
| 7 | Süre: 76 çalışan, Kasım 30 gün | — | 3,8 s (gün başına yaklaşık 0,13 s) | ✅ |
| 8 | Süre: 2000 çalışan (1924 kişi eklendi), 3 iş günü | — | 7,9 s / 11,0 s / 9,7 s (gün başına); 5772 gün kaydı, 117'si kanıtla düzeltildi | ⚠️ T-24 |
| 9 | Aynı gün ekrandan (İK oturumu, `authenticated`) | Çalışmalı | `authenticated` rolünde `statement_timeout = 8s`. `gece_isi_tetikle` 8,0 s'de "canceling statement due to statement timeout" ile kesildi | ❌ T-24 |

**Yan gözlem:** `duzeltme.yeni_deger` ve `eski_deger` metin olarak saklanıyor ve oturumun saat dilimiyle yazılıyor. UTC oturumunda `2026-11-03 05:00:00+00`, İstanbul oturumunda `2026-11-03 08:00:00+03`. İkisi de aynı anı gösteriyor; ekran ve fark hesabı değeri yeniden zamana çevirdiği için sonuç doğru. Bulgu değil.

### Kod incelemesi (Ek A; 21 fonksiyonun son sürümü)

| # | Soru | Sonuç |
|---|---|---|
| 1 | Yetki | ✅ Dışarıya yalnızca `gece_isi_tetikle` açık (`yetki_gerekli('ik')`). `gece_isi_calistir` ve adım fonksiyonları `authenticated`'a kapalı (Adım 2) |
| 2 | Görevler ayrılığı | ❌ İK kendi okutmasını yükleyip gece işini çalıştırabiliyor (T-13). Soru, amirin kendi günüyse üst amire yönleniyor (`amir_sorusu_yonlendir`) ✅ |
| 3 | Kapsam | ✅ `soru_atanacak` departmanın amirini (amir izinliyse vekili), yoksa İK'yı seçiyor |
| 4 | Zincirleme etki | ⚠️ Var olan gün kaydı yeniden işlenmiyor: sonradan gelen PDKS (T-19) ve kanıt (T-23) dosyaları güne yansımıyor |
| 5 | Kilitli ay | ✅ Kilitli gün değişmiyor. ⚠️ İşlenmemiş planlı gün için o günün tamamı hata veriyor (T-26) |
| 6 | İz | ✅ Kanıtla düzeltme `duzeltme`'ye `kaynak = gece_isi`, dayanak `kanit_kaydi_id`, gerekçe metniyle yazılıyor (S1, S3, S32) |
| 7 | Kenar durumlar | ✅ İkinci tur, gece yarısı, ayın son günü, resmi tatil (FM100 / RT), eksik PDKS dosyası. ⚠️ Atanacak kimse yoksa bütün gün düşüyor (T-25) |
| 8 | Saat dilimi | ✅ Bütün gün sınırları `at time zone 'Europe/Istanbul'` ile; üç saat diliminde aynı sonuç. Yalnızca `gece_isi_calistir`'ın "işlenebilir gün" sınırı oturumun `current_date`'ini kullanıyor (UTC oturumunda Türkiye'de 00:00–03:00 arası bir gün geride; etkisi yalnızca o saatlerde "henüz veri yok" demesi) |
| 9 | Güvenlik | ✅ Dinamik SQL yok. `search_path = pdks` (`pg_temp` yok, T-03) |
| 10 | Test | ⚠️ `gece_isi_testi.sql` 49 kontrol; UTC oturumu (T-04), geç gelen kanıt dosyası, bir çalışanda hata ve büyük ölçek sınanmıyor |

### Bulgular

### T-22 · `docs/ornek_veri.md` S18'in beklenen sonucu veritabanıyla tutmuyor
- **Adım:** 5 · **Önem:** Düşük
- **Yer:** `docs/ornek_veri.md`, S18 satırı
- **Ne oldu:** Belge "Gün 'izinli'; amir türü göremez" diyor. Veritabanında Can Kılıç'ın (2007) rapor günleri `raporlu`, Deniz Aksoy'un (2008) yıllık izni `izinli`. "Amir türü göremez" kısmı da tam doğru değil (T-12).
- **Ne olmalıydı:** Belge gerçek durumu yazmalı. Örnek: "Rapor günleri `raporlu`, yıllık izin `izinli`. Amire ekranda ikisi de 'İzinli' görünür; veritabanında ayrım vardır (T-12)."
- **Kanıt:** `S18 | 2007 23=raporlu, 2007 24=raporlu, 2007 25=raporlu, 2008 26=izinli, 2008 27=izinli | ❌`
- **Sade dille:** Örnek veri belgesi, sistemin rapor gününü "izinli" diye kaydettiğini söylüyor; sistem ise "raporlu" diye kaydediyor. Belgeyi okuyan, sağlık bilgisinin hiç saklanmadığını sanabilir.
- **Öneri:** T-12'nin kararından sonra S18 satırı güncellensin.
- **Durum:** ✅ Düzeltildi (belge, `feature/T103-belge-duzeltmeleri`). S18 satırı rapor (`raporlu`) ve yıllık izin (`izinli`) ayrımını ve T-12 bağlantısını yazıyor; yerelde Kasım gece işinden geçirilerek doğrulandı.

### T-23 · Kapı / servis dosyası PDKS'den sonra gelirse kanıt kullanılmıyor; amire gereksiz soru gidiyor
- **Adım:** 5 · **Önem:** Orta
- **Yer:**
  - `pdks.gece_isi_calistir` → `pdks_verisi_tam_mi`: yalnızca PDKS aktarımına bakıyor;
  - `pdks.gece_isi_kanitla_duzelt` ve `pdks.gece_isi_sorular`: yalnızca `durum = 'eksik'` günlerle çalışıyor.
- **Ne oldu:**
  1. 13 Ekim için yalnızca PDKS dosyası vardı; EK02'nin PDKS girişi yoktu.
  2. Gece işi kapı dosyasını beklemeden günü açtı ve amire `giris_yok` sorusu gönderdi. Gün `soru_bekliyor` oldu.
  3. Kapı dosyası sonradan geldi (EK02 kapı girişi 07:50) ve gece işi yeniden çalıştırıldı. Gün değişmedi, soru açık kaldı.

  Aynı kurulumda iki dosya birlikte gelseydi gün kapı kaydıyla 08:00 olarak düzelecek ve soru açılmayacaktı.
- **Ne olmalıydı:** Projenin ana iddiası "kanıt varsa sistem kendisi düzeltir, yoksa amire sorar". Bu, dosyaların geliş sırasına bağlı olmamalı. Ya kanıt dosyaları da gelmeden soru açılmamalı (o gün "kanıt bekleniyor"), ya da sonradan gelen kanıt, açık sorusu olan günü kendisi düzeltip soruyu kapatmalı.
- **Kanıt:** `scratch/a5_ek.sql` (2b, 2c):
  ```
  2b 13 Ekim (PDKS var, kapı yok): gece işi basarili {"soru": 1, "gun_kaydi": 2, ...}
  2b sonuç: EK01=tamam, EK02=soru_bekliyor soru:giris_yok · uyarılar=… kapi dosyası yüklenmedi.
  2c kapı dosyası sonradan gelince: EK02=soru_bekliyor, giriş=yok, soru=giris_yok/acik
  ```
- **Sade dille:** Turnike kayıtları PDKS dosyasından bir gün sonra gelirse sistem "kanıt yok" deyip amire soruyor. Ertesi gün kanıt gelse de soruyu geri çekmiyor; amir aslında sistemin kendisinin bilebileceği bir şeyi cevaplamak zorunda kalıyor. Dosyaların her gece aynı anda gelmediği bir fabrikada bu, gereksiz soru yükü demek.
- **Öneri:**
  1. Kanıt dosyaları da gelene kadar (ya da bir bekleme süresi boyunca) soru açılmasın; ya da
  2. Gece işi her çalıştığında, açık sorusu olan günlere yeni gelen kanıtla `kanitla_duzelt` uygulasın ve soruyu "kanıtla kapandı" diye kapatsın. İkinci yol T-19'u da çözer.
- **Durum:** Açık

### T-24 · Gece işi 2000 çalışanda ekrandan çalışmıyor (8 saniye zaman aşımı); süre çalışan sayısıyla karesel büyüyor
- **Adım:** 5 · **Önem:** Orta (demo etkilenmez: 7 Aralık 10 kişi, Kasım 30 gün 3,8 s)
- **Yer:**
  - `pdks.gece_isi_gun_kayitlari`: `okut` adımı, her plan için penceredeki bütün okutmalar × `pdks.okutma_sahibi(...)`;
  - `pdks.calisan_pdks_okuyucusu`: 16 günlük okutmaları kişi kişi tarıyor;
  - Supabase'in `authenticated` rolü: `statement_timeout = 8s`.
- **Ne oldu:**
  - 76 çalışanda bir gün yaklaşık 0,13 s; 2000 çalışanda 7,9–11,0 s. Çalışan sayısı 26 kat arttı, süre yaklaşık 77 kat.
  - Ekrandaki "Gece işini çalıştır" düğmesi `gece_isi_tetikle`'yi `authenticated` rolüyle çağırıyor. 2000 çalışanlı tek bir gün 8,0 s'de kesildi, hiçbir şey yazılmadı. Zaman aşımı `when others` ile yakalanmadığı için `gece_isi` tablosuna "hatalı" satırı da düşmedi.
  - Canlıdaki gece cron'u `postgres` olarak çalıştığı için bu sınıra takılmıyor (gecede 2 gün, yaklaşık 20 s).
- **Ne olmalıydı:** İK'nın elle tetiklediği gece işi gerçek ölçekte de çalışmalı. Okutmanın sahibi her plan-okutma çifti için değil, okutma başına bir kez bulunmalı.
- **Kanıt:**
  ```
  a5_sure.sql:  b 2000 çalışan, 2026-12-14: 7851 ms · 12-15: 10987 ms · 12-16: 9668 ms   (76 çalışan Kasım 30 gün: 3,77 s)
  pg_roles:     authenticated: statement_timeout=8s · anon: 3s · authenticator: 8s
  a5_zaman_asimi.sql:  ERROR: canceling statement due to statement timeout
                       CONTEXT: SQL function "okutma_sahibi" … gece_isi_gun_kayitlari … gece_isi_tetikle   Time: 8003.732 ms
  ```
- **Sade dille:** Demodaki küçük veriyle düğme anında çalışıyor. Ama 2000 kişilik gerçek fabrikada İK düğmeye bastığında sistem 8 saniye bekleyip işi yarıda bırakıyor; ekranda yalnızca bir hata görünüyor. Gece kendiliğinden çalışan iş etkilenmiyor. Yavaşlığın sebebi şu: sistem her çalışanın her okutmasında "bu kart kimin?" sorusunu, o gün işe gelen herkes için tekrar tekrar soruyor.
- **Öneri:**
  1. `okut` adımı önce penceredeki okutmaların sahibini bir kez hesaplasın (`okutma_sahibi` bir kez, sonra `calisan_id` ile birleştirme); `calisan_pdks_okuyucusu` aynı şekilde.
  2. Ekrandan tetiklemede `gece_isi_tetikle`'nin içinde `set local statement_timeout` (ör. 120 s) ya da işin arka plana alınması (ör. `pg_cron` ile bir kerelik).
  3. T-02'deki eksik indexlerle birlikte değerlendirilsin.
- **Durum:** Açık

### T-25 · Bir çalışanda çıkan hata o günün bütün çalışanlarını işlenmemiş bırakıyor; mesaj kişiyi söylemiyor
- **Adım:** 5 · **Önem:** Düşük
- **Yer:** `pdks.gece_isi_calistir` (bütün adımlar tek alt işlemde; `exception when others` → `hatali`); `pdks.soru_atanacak` ve `amir_sorusu_yonlendir` (atanacak kimse yoksa `null`)
- **Ne oldu:** Amiri olmayan bir departmandaki tek bir çalışanın sorusu, bütün İK hesapları pasifken kimseye atanamadı (`atanan_id` null). Bu tek hata yüzünden 30 Kasım'ın 77 planlı çalışanının **hiçbirinin** gün kaydı açılmadı. `gece_isi` satırı `hatali`, mesaj ham İngilizce kısıt mesajı; hangi çalışan olduğu yazmıyor.
- **Ne olmalıydı:** "Bir adımda hata olursa o günün hiçbir değişikliği kalmaz" `docs/veritabani.md`'de bilinçli olarak yazılmış. Ama mesaj hangi çalışanın hangi adımda takıldığını söylemeli. Atanacak kimse yoksa da anlaşılır bir hata verilmeli. Bugün soru eklemeye çalışıp kısıta takılıyor; `amir_sorusu_yonlendir`'in kendi Türkçe hatası ise yalnızca "amirin kendi sorusu" durumunda çalışıyor.
- **Kanıt:** `scratch/a5_ek.sql` (5):
  ```
  5 30 Kasım gece işi: hatali — null value in column "atanan_id" of relation "amir_sorusu" violates not-null constraint
  5 sonuç: 30 Kasım gün kaydı=0 (planlı: 77)
  ```
- **Sade dille:** Tek bir kişinin kaydındaki bir sorun, fabrikanın o günkü bütün kayıtlarını bekletiyor; İK hatayı görünce kimin yüzünden olduğunu da bilmiyor. Bu örnekteki durum (amirsiz departman ve hiç aktif İK yok) seyrek, ama aynı yapı başka hatalarda da geçerli.
- **Öneri:**
  - `soru_atanacak` null dönerse gece işi o çalışan ve gün için açıklayıcı bir hata versin (sicil, gün, "soruyu atayacak amir ya da İK yok").
  - İstenirse sorunlu çalışanı atlayıp `uyari` yazmak, günün geri kalanını işlemek tartışılabilir (tasarım kararı).
- **Durum:** Açık

### T-26 · Kilitli aydaki işlenmemiş planlı gün için gece işi "hatalı" bitiyor
- **Adım:** 5 · **Önem:** Görüş
- **Yer:** `pdks.gece_isi_gun_kayitlari` (kilitli günü süzmüyor) → `gun_kaydi_koru` tetikleyicisi
- **Ne oldu:** Kilitli Kasım'a sahibin gözüyle bir plan eklendi (28 Kasım) ve gece işi o gün için çalıştırıldı. Gün kaydı açılmaya çalışıldı, tetikleyici "kilitli bir döneme ait" hatası verdi, gece işi `hatali` bitti. Veri bozulmadı.
- **Ne olmalıydı:** Gece işi kilitli günleri baştan atlamalı ve `basarili` (0 iş) bitmeli; kilitli bir aralığı ekrandan yeniden işletmek "hatalı" satırları üretmemeli. Bu durum ancak plan RPC dışından eklenirse oluşuyor, çünkü `vardiya_plani_gir` kilitli aya plan kabul etmiyor. Bu yüzden önemi düşük.
- **Kanıt:** `4b kilitli Kasım, işlenmemiş planlı gün (28 Kas): hatali — 2026-11-28 günü kilitli bir döneme ait; değişiklik sonraki aya fark olarak yazılır.`
- **Sade dille:** Kapanmış bir ayın bir gününü yeniden işletmeye kalkınca sistem kibarca "yapacak bir şey yok" demek yerine hata veriyor.
- **Öneri:** `gece_isi_gun_kayitlari`'na `not pdks.donem_kilitli_mi(p_gun)` koşulu.
- **Durum:** Açık

### Denediklerim
- Kasım'ı ekranın yolundan (İK, `gece_isi_tetikle`) işleyip S1–S32'nin her satırı.
- Aynı ayı ikinci kez işlemek (sayılar ve içerik özeti).
- Eksik dosya iki yönde ve kanıt dosyasının sonradan gelmesi.
- 30 Kasım → 1 Aralık gece vardiyaları.
- Üç saat dilimi, normalleştirilmiş parmak iziyle.
- Kilitli ayda yeniden işleme.
- Bir çalışanda hata.
- Süre: 76 ve 2000 çalışan; `authenticated` zaman aşımı.
- 21 fonksiyonun son sürümünün okunması: `scratch/a5_kod/`.

### Denemediklerim
- **pg_cron'un kendisi:** zamanlamanın gerçekten 03:30 UTC'de çalışması. Yerelde cron işinin varlığına ve komutuna bakmadım; komutun `gece_isi_calistir`'ı `postgres` ile çağırdığını varsaydım. Canlıda cron kaldırılacağı için (`docs/canli_kurulum.md`) demo açısından önemsiz.
- **Kart paylaşımı, geçici kart ve İSG kontrollerinin büyük ölçekte süresi:** yalnızca toplam gece işi süresi ölçüldü.
- **Gece işinin eş zamanlı iki çağrısı:** `pg_advisory_xact_lock` var, denenmedi.
- **Resmi tatil arifesi (yarım gün):** seed'de Kasım'da yok; Adım 6'da. → Adım 6'da denendi (T-28).

### Şüpheler
- **`calisan_pdks_okuyucusu` ve arıza şüphesi:** bu fonksiyon her eksik gün için 16 günlük okutmayı `okutma_sahibi` ile tarıyor. 2000 çalışanda çok eksik gün olan bir günde (ör. bir okuyucu bütün gün arızalıysa) arıza adımı T-24'teki süreyi çok aşabilir. Ölçülmedi.
- **Mükerrer okutma, okuyucuya bakmadan işaretleniyor** (`partition by kart_no, yon`). Aynı kartın iki farklı okuyucuda 3 dakika içinde aynı yönde okutulması da mükerrer sayılıyor. Bilinçli olabilir; Adım 6'da örnekle bakılacak. → Adım 6'da kapandı (T-29).

---

## Adım 6 — Hesap kuralları (21 Kasım 2026)

**Betikler:**

| Betik | Ne sınıyor |
|---|---|
| `scratch/a6_hesap.sql` | 31 vaka: `gun_hesabi` doğrudan, elle hesaplanan beklenen değerle karşılaştırma (tolerans, mola, gece, FM, tatil, arife, esnek, esnek ay farkı) |
| `scratch/a6_kenar.sql` | Gece işinin içinden: mükerrer okutma (farklı / aynı okuyucu), giriş–çıkış kenar durumları, arife günü ve puantaj kodu |
| `scratch/a6_kod/*.sql` | Okunan 13 fonksiyonun son sürümleri |

Hepsi tek işlem ve sonda `ROLLBACK`. Deneme verisi kendi departmanlarında (HS Deneme, MK Deneme); 28 Ekim (arife, `yarim_gun = true`) ve 29 Ekim işlem içinde `resmi_tatil`'e eklendi.

**Ayarlar (o anki değerler):** geç kalma toleransı 10 dk, erken çıkış toleransı 5 dk, yuvarlama 0, mola sınırları 240 / 450 dk (15 / 30 / 60 dk mola), mükerrer eşiği 3 dk, gece çalışma uyarı sınırı 450 dk.

### Sonuç tablosu

| # | Kural | Sonuç |
|---|---|---|
| 1 | Geç kalma / erken çıkış toleransı | ✅ 08:05:00, 08:05:01, 08:10:00, 08:11:00 ve 16:55:00, 16:54:00 beklendiği gibi. ❌ 08:10:01 ve 08:10:59 → geç 0: saniyeler tolerans karşılaştırmasından önce atılıyor, gerçek tolerans 10 dk 59 sn (T-27). Tolerans ve yuvarlama **ayardan** okunuyor |
| 2 | Mola | ✅ brüt 240 → 15, 241 → 30, 450 → 30, 451 → 60. Sınırlar ve süreler **ayardan** |
| 3 | Saatlik izin | ✅ 13–15 izin: çalışmadan düşüyor (390), brüt 420 olduğu için mola 30'a iniyor, izin saatleri geç / erken sayılmıyor |
| 4 | Gece çalışması | ✅ 22–06 → 420, 16–24 → 210, 00–08 (giriş önceki gün 23:50) → 315, 14–22 → 105. Aralık 20:00–06:00, **kodda sabit** (`gece_araligi`); yalnızca 450 dk uyarı sınırı ayarda |
| 5 | Vardiya sonrası kalma | ✅ Onaylı plan 60 / 60 kaldı → FM50 60; plan 30 / 60 kaldı → FM50 30 + onaysız 30; plansız kalma (yazılı onay olsun ya da olmasın) → onaysız 60 |
| 6 | Hafta tatili, resmi tatil | ✅ Pazar ve 29 Ekim yazılı onaylı → FM100 480; Pazar onaysız → çalışma 0, onaysız 540 |
| 7 | Yarım gün arife | ❌ 28 Ekim tam iş günü sayılıyor: 13:00'te çıkana **240 dk erken çıkış**, 17:00'ye kadar çalışana **FM100 0**. Gece işinden geçince de aynı: erken 238, kod NÇ 272 (T-28) |
| 8 | Esnek mesai | ✅ 09:00–18:00 → 480, 09:40–17:30 → 410; ay hedefi 960, gerçekleşen 890, fark −70 |
| 9 | Kenar: giriş var çıkış yok / çıkış var giriş yok | ✅ `cikis_yok` / `giris_yok` sorusu, gün `soru_bekliyor`, dakika yazılmıyor |
| 10 | Kenar: giriş çıkıştan sonra (17:00 giriş, 08:05 çıkış) | ⚠️ Çıkış okutması yok sayılıyor, amire "çıkış yok" soruluyor (T-30). Giriş ile çıkış aynı anda: yine `cikis_yok` |
| 11 | Mükerrer, farklı okuyucu | Sayılıyor (okuyucuya bakılmıyor). Girişte doğru (ilk giriş kalıyor). ⚠️ Çıkışta **ilk** çıkış kalıyor, son çıkış atılıyor (T-29) |

Not: 14:00–22:00 için beklenen gece dakikasını 90 yazmıştım; doğrusu 105 (120 dk gece − mola payı round(60·120/480) = 15). Sistemin hatası değil, benim hesap hatam.

### Bulgular

### T-27 · Tolerans saniyeleri atarak karşılaştırılıyor; 10 dk tolerans fiilen 10 dk 59 sn
- **Adım:** 6 · **Önem:** Düşük
- **Yer:** `pdks.gun_hesabi` → `dakika_toplami` (aşağı yuvarlıyor) → `tolerans_uygula`
- **Ne oldu:** 08:00 vardiyasında 08:10:01 ve 08:10:59 girişleri geç kalma 0 sayıldı; 08:11:00 geç 11. Erken çıkışta da aynı: 16:54:01 → 0 (fiilen 5 dk 59 sn).
- **Ne olmalıydı:** Belgede "10 dakikaya kadar tolerans" yazıyor. Sınır saniyeyle uygulanmalı (08:10:01 → geç 11 ya da 10), ya da belgede "dakika tamamlanmadan sayılmaz" diye açıkça yazılmalı.
- **Kanıt:** `a6_hesap`: `giriş 08:10:01 | beklenen 10,… | gerçekleşen 0,… | ❌`, `giriş 08:10:59 | 0 | ❌`, `giriş 08:11:00 | 11 | ✅`.
- **Sade dille:** Sistem geç kalmayı saniyesiz ölçüyor. 08:10'u 59 saniye geçen kişi hâlâ "zamanında" sayılıyor. Çalışan lehine bir sapma; ama kural kâğıtta yazandan bir dakika gevşek.
- **Öneri:** Kararı İK versin. Ya tolerans karşılaştırması saniyeyle yapılsın (`aralik` süresini saniye olarak karşılaştırıp sonra dakikaya çevirmek), ya da mevcut davranış belgeye yazılsın. İkinci yol kod değişikliği gerektirmez.
- **Durum:** Açık

### T-28 · Yarım gün arife tam iş günü sayılıyor: öğleden sonra çıkana erken çıkış, çalışana FM100 yok
- **Adım:** 6 · **Önem:** Yüksek (22 Kasım'da Orta'dan yükseltildi: arife öğleden sonrası yasal tatil, bugünkü hesap kanuna aykırı ve çalışan aleyhine)
- **Yer:** `resmi_tatil.yarim_gun` yalnızca "tam tatil değil" diye kullanılıyor (`fm100_gunu_mu`, gece işi, puantaj). Vardiya aralığı, erken çıkış ve FM100 hesabı arifeyi hiç bilmiyor.
- **Ne oldu:** 28 Ekim (arife, `yarim_gun = true`) GÜNDÜZ vardiyası:
  - 08:00–13:00 çalışana erken çıkış **240 dk** yazıldı. Gece işinden geçince gün `tamam`, erken 238, puantaj kodu NÇ 272 dk.
  - 08:00–17:00 çalışana FM100 **0** yazıldı; öğleden sonraki 4 saat normal çalışma sayıldı.
- **Ne olmalıydı:** Türkiye'de 28 Ekim ve bayram arifeleri 13:00'ten sonra yarım gün resmî tatil (2429 sayılı Kanun). Öğleden sonra çalışılmaması erken çıkış olmamalı; öğleden sonra çalışılırsa (yazılı onayla) o süre FM100 olmalı. `docs/veritabani.md` satır 314 "arife (yarım gün) normal iş günüdür" diyor: sistem belgesine uyuyor, ama belgedeki karar yasal uygulamayla çelişiyor görünüyor.
- **Kanıt:**
  ```
  a6_hesap: arife 28 Ekim, 13:00'te çıktı | beklenen 0,0,270,…,30 | gerçekleşen 0,240,270,…,30 | ❌
  a6_hesap: arife 28 Ekim, 17:00'ye kadar | beklenen …,fm100 240 | gerçekleşen …,fm100 0 | ❌
  a6_kenar: AR01|tamam|07:55:00|13:02:00|0|238|272|-   ·   AR01|NÇ|1|272
  ```
- **Sade dille:** Arife günü öğleden sonra tatildir. Sistem bunu bilmiyor: öğlen evine giden herkese "4 saat erken çıktı" yazıyor, öğleden sonra çalışana da tatil mesaisi vermiyor. Bu çalışan aleyhine bir hata ve yılda birkaç gün bütün fabrikayı etkiliyor.
- **Öneri:** Kod yazmadan önce İK ile karar: (a) arifede vardiya bitişi 13:00'e çekilsin (13:00 sonrası erken çıkış sayılmasın), 13:00 sonrası onaylı çalışma FM100 olsun; ya da (b) arife günleri için vardiya planı ayrıca "yarım gün" vardiyasıyla girilsin ve bu belgeye yazılsın. (a) tek bir yerde (`gun_hesabi` / `vardiya_araligi`) çözülür.
- **Karar (Fırat, 25 Kasım):** Arife günlerinde çalışma 13:00'te biter. 13:00'ten sonraki erken çıkış sayılmaz; 13:00'ten sonraki çalışma FM100 olur (onay ve yazılı onay kuralları T-56 / T-57'deki gibi).
- **Durum:** ✅ Düzeltildi (feature/T28-arife). Migration: `20261222010000_arife.sql`, test: `arife_testi.sql`. Arife `resmi_tatil.yarim_gun`'dan okunur (`arife_siniri`); 2026–2027 arifeleri tamam. `vardiya_araligi` arifede 13:00'te biter, `gun_hesabi` sonrasını FM100 yazar.
- **Uygulamada çıkan sonuçlar:** Gece vardiyası is_gunu'ya göre: arife gecesi 22-06'nın tamamı FM100; bir önceki geceninki normaldir. 13:00'te ya da sonra başlayan vardiyaya gelmeyen "tatil" olur (soru açılmaz); öğleden önce başlayan vardiyaya gelmeyene soru açılır. 13:00'ü 15 dk'ya kadar geçen çıkış çalışma sayılmaz. Esnek mesaide arife hedefi yarımdır, FM100 hedefe sayılmaz.

### T-29 · Mükerrer çıkışta ilk okutma tutuluyor, son okutma atılıyor
- **Adım:** 6 · **Önem:** Düşük
- **Yer:** `pdks.gece_isi_isaretle`, `lag(...) over (partition by kart_no, yon order by okutma_zamani)`
- **Ne oldu:**
  - Farklı okuyucu: PDKS-1 07:50 giriş, PDKS-2 07:52 giriş → ikincisi `mukerrer`. PDKS-2 16:59 çıkış, PDKS-1 17:01 çıkış → **17:01** `mukerrer`, gün çıkışı 16:59.
  - Aynı okuyucu: 16:58:00 ve 17:00:30 çıkış → 17:00:30 `mukerrer`, çıkış 16:58, çalışma 478.
- **Ne olmalıydı:** Girişte ilkini tutmak doğru ve çalışan lehine. Çıkışta kişi binadan son okutmada çıkmıştır; sonuncusu tutulmalı. Okuyucuya bakmamak bence doğru: iki PDKS okuyucusu (idari bina, Bobinaj atölyesi) aynı kişinin aynı yöndeki iki geçişidir.
- **Kanıt:** `a6_kenar`: `KK-MK01|PDKS-1|17:01:00|cikis|mukerrer`, `KK-MK02|PDKS-1|17:00:30|cikis|mukerrer`, `MK01|tamam|07:50:00|16:59:00|0|0|479`.
- **Sade dille:** Kartını çıkışta iki kez okutan kişinin ilk okutması "çıkış saati" sayılıyor. Kayıp en fazla 3 dakika, ama tolerans sınırında sonuç değiştirebilir. Elle hesap (denenmedi): 16:53 ve 16:56'da çıkış okutan kişi 16:53'le 7 dk erken çıkış alır; 16:56 tutulsaydı 4 dk, yani 0.
- **Ek:** Karşılaştırma bir önceki okutmayla yapılıyor (`lag`), son tutulan okutmayla değil. 2'şer dakika arayla zincirleme okutmalarda yalnızca ilki kalır; bu da çıkışta kaybı 3 dakikanın üstüne çıkarabilir.
- **Öneri:** Çıkış yönünde sıralamayı tersine çevirmek (`order by okutma_zamani desc`, yani `lead` mantığı) yeter; giriş aynı kalır.
- **Durum:** Açık

### T-30 · Giriş çıkıştan sonra gelirse amire "çıkış yok" soruluyor
- **Adım:** 6 · **Önem:** Görüş
- **Yer:** Gece işinin giriş / çıkış seçimi (çıkış, girişten sonra olmalı)
- **Ne oldu:** Aynı gün 17:00 giriş, 08:05 çıkış (okuyucu yönleri ters ya da kişi yanlış yöne okutmuş). 08:05 çıkışı yok sayıldı, gün `soru_bekliyor`, soru `cikis_yok`. Giriş ile çıkış aynı anda (08:00, iki okuyucu) olduğunda da `cikis_yok`.
- **Ne olmalıydı:** Amire soru gitmesi doğru, kanıt da yok. Ama soru türü gerçeği tam söylemiyor: ortada bir çıkış okutması var, sıra ters. Amir "çıkış yok" görünce kişinin çıkışta okutmadığını sanar.
- **Kanıt:** `a6_kenar`: `MK05|soru_bekliyor|17:00:00|-|…|cikis_yok`, `MK06|soru_bekliyor|08:00:00|-|…|cikis_yok`.
- **Sade dille:** Kişi iki kez okutmuş ama sıra karışmış. Sistem amire "çıkışta okutmadı" diyor; "okutmalar ters sırada" demesi amirin işini kolaylaştırır.
- **Öneri:** Ayrı bir soru türü (`sira_hatali`) ya da sorunun açıklamasına iki okutmanın saati. Küçük iş; Adım 14'te karar.
- **Durum:** Açık

### Soruların cevapları
- **Mükerrer, farklı okuyucu:** Evet, ikincisi mükerrer sayılıyor. Girişte doğru; çıkışta yanlış olan, hangisinin atıldığı (T-29).
- **Yarım gün arife:** Tam iş günü gibi hesaplanıyor; çalışan aleyhine (T-28).
- **Tolerans sınırı:** 08:05:00 ve 08:05:01 ikisi de geç 0 (doğru, tolerans 10). Asıl sınır 08:10'da ve 59 saniye gevşek (T-27).
- **Gece yarısını geçen vardiya:** 22–06 → gece 420, mola 60. 00–08 (23:50 giriş) → gece 315. Mola, gece dakikasından payı oranında düşülüyor; doğru.
- **Ayar mı, sabit mi:** tolerans, yuvarlama, mola sınırları ve süreleri, mükerrer eşiği ayarda. Gece aralığı 20:00–06:00 ve saat dilimi kodda sabit. Gece aralığı İş Kanunu m.69'daki tanımla (en geç 20:00 – en geç 06:00) aynı; sabit olması bence sorun değil, bulgu yazmadım.

### Denediklerim
- 31 vaka `gun_hesabi` ile doğrudan, beklenen değerler elle hesaplanarak.
- Gece işinden geçerek: mükerrer (farklı ve aynı okuyucu), giriş yok, çıkış yok, ters sıra, aynı an, arife (çalışan ve hiç okutmayan).
- Esnek ay farkı.
- 13 fonksiyonun son sürümünün okunması: `scratch/a6_kod/`.

### Denemediklerim
- **Yuvarlama ayarı 0 dışında** (`tolerans_yuvarlama_dk`): yalnızca kodu okudum, 0 dışında bir değerle denemedim.
- **Cumartesi hafta sonu ayarı = 1:** kodda var (`fm100_gunu_mu`), denenmedi.
- **Bayram arifesi ile bayramın art arda geldiği uzun dönem** ve arifenin gece vardiyası: denenmedi; T-28'in kararı bunları da etkiler.
- **T-29'daki 16:53 / 16:56 örneği:** elle hesap, çalıştırılmadı.

### Şüpheler
- **`ham_okutma` tekil anahtarı `(okuyucu_id, kart_no, okutma_zamani)` yönü içermiyor.** Aynı okuyucuda aynı saniyede bir giriş ve bir çıkış yazılamıyor (deneme betiği bu yüzden bir kez hata verdi). Adım 4'te dosya içi tekrarların bir kez yazıldığını görmüştüm; böyle bir satır dosyada gelirse ikincisi muhtemelen sessizce düşüyor. Gerçek hayatta neredeyse olmaz, `dosya_yukle` ile denenmedi.
- **Arifede hiç okutmayan çalışan (AR02):** `hic_kayit_yok` sorusu açıldı. Arife tam iş günü sayıldığı için bu doğru; T-28 düzeltilirse yarım günün eksik sayılıp sayılmayacağı da karara bağlanmalı.

---

## Endpoint testi — ekran ↔ backend ↔ veritabanı (22 Kasım 2026)

Ayrı iş; ayrıntı `docs/endpoint_testi.md` (endpoint haritası, HTTP ve hata yolu) ve `docs/veri_akisi.md` (veri akışı matrisi).

**Betikler:**

| Betik | Ne sınıyor |
|---|---|
| `scratch/e_calistir.sh` | Bütün betikleri yalnızca yerel adresle çalıştırır (adres `supabase status`'tan) |
| `scratch/e3_veri_akisi.sql`, `scratch/e3_ek.sql` | 34 RPC × 35 tablo önce / sonra farkı; beklenmedik satırların ayrıntısı |
| `scratch/e3_okuma.sql` | Koddan okunan / yazılan tablolar |
| `scratch/e4_http.mjs`, `scratch/e4_hazirlik.sql`, `scratch/e4_anon.mjs` | Gerçek HTTP: 11 yerel Auth hesabı, 34 yazma × (yetkili / yetkisiz / anon), 8 okuma × 11 rol, 63 hata denemesi |
| `scratch/e5_maskeli.sql` | HTTP'de başka hataya takılan 3 hata denemesinin temiz tekrarı |

HTTP testi veriyi kalıcı değiştirdiği için yerel veritabanı önce ve sonra `supabase db reset` ile sıfırlandı.

**Sayılar:**
- Uçlar: 34 yazma RPC'si (ekran 32'sini çağırıyor), 1 okuma RPC'si, 30 tablo ve 4 view.
- HTTP isteği: 273.
- Yetkisiz istekler: rol 34 / 34 ve anon 35 / 35 reddedildi, hiçbir tablo değişmedi.
- Okuma: HTTP sayımı SQL sayımıyla 88 / 88 aynı.
- Ekrana teknik İngilizce mesaj: `rpcCagir` yolunda 0, `dosya_yukle` yolunda 1.

### T-31 · `dosya_yukle` ekrandan (HTTP) hiç çalışmıyor: "UPDATE requires a WHERE clause"
- **Adım:** Endpoint · **Önem:** Kritik
- **Yer:** `pdks.dosya_yukle` (son sürüm: `20261128010000_dosya_yukle_duzeltmesi.sql`, satır 134: `update dosya_satiri set okutma_zamani = zaman_metni::timestamptz;`)
- **Ne oldu:**
  - Geçerli tek satırlık bir PDKS dosyası, İK oturumuyla ekranın gönderdiği istekle HTTP'den yüklendi. Cevap 400, kod `21000`, mesaj `UPDATE requires a WHERE clause`. Hiçbir satır yazılmadı.
  - Aynı çağrı psql'den (Adım 4, madde 3) çalışıyor.
  - Neden: Supabase, HTTP isteklerini taşıyan `authenticator` rolüne `session_preload_libraries = supautils, safeupdate` veriyor. `safeupdate`, `WHERE`'siz `UPDATE` / `DELETE`'i reddediyor; fonksiyonun içindeki geçici tablo güncellemesi de buna takılıyor.
  - Hata yolu denemelerinde (olmayan okuyucu, geçersiz zaman, geçersiz özet) fonksiyon bu satırdan önce durduğu için mesajlar doğru geliyor. Yani **yalnızca geçerli dosyalar** başarısız oluyor.
- **Ne olmalıydı:** Geçerli dosya yazılmalı; `aktarim` +1 ve `ham_okutma` (ya da `kanit_kaydi`) +n.
- **Kanıt:**
  ```
  e4_http: dosya_yukle|ik.muduru|400 HATA 21000: UPDATE requires a WHERE clause||-|—|…
  rol ayarı: authenticator|{"session_preload_libraries=supautils, safeupdate",statement_timeout=8s,…}
  kod taraması (117 fonksiyon): WHERE'siz UPDATE/DELETE yalnızca dosya_yukle'de, 1 tane
  ```
- **Sade dille:** Ekrandaki "Dosyayı yükle" düğmesi her geçerli dosyada hata veriyor. Bu durumda sistemin girişi kapalı demek: okutma gelmezse gece işi hiçbir şey üretemez. Bizim SQL testlerimiz veritabanına doğrudan bağlandığı için bu korumayı görmüyor ve hepsi geçiyor. Hata ancak ekrandan denenince ortaya çıkıyor.
- **Öneri:**
  - Yeni bir migration ile `dosya_yukle` yeniden oluşturulsun ve satıra `where true` (ya da `where okutma_zamani is null`) eklensin.
  - Kalıcı test:
    1. `supabase/tests/` altına bütün `pdks` fonksiyonlarında `WHERE`'siz `UPDATE` / `DELETE` arayan bir kod taraması. `safeupdate` psql'de yüklenemiyor ("access to library "safeupdate" is not allowed"), bu yüzden davranış testi SQL'de yapılamıyor.
    2. `scratch/e4_http.mjs` gibi bir HTTP duman testi.
  - Canlıda bu migration varsa canlı da etkilenir; Fırat kontrol etmeli (bkz. Denemediklerim).
- **Düzeltme (dal `fix/t31-dosya-yukle`):**
  - `20261204010000_dosya_yukle_where.sql`: fonksiyon son sürümünden (`pg_get_functiondef`) birebir alındı, yalnızca o satıra `where zaman_metni is not null` eklendi. Bir üstteki denetim boş ya da biçimsiz zamanı zaten reddettiği için koşul bütün satırları kapsar. Yetkiler (`authenticated` çalıştırır, `anon` / `public` çalıştıramaz) ve açıklama aynı.
  - HTTP, eski / yeni kod (`scratch/e4_http.mjs`; dört kaynak eklendi):
    ```
    eski: dosya_yukle|ik.muduru|400 HATA 21000: UPDATE requires a WHERE clause|-
          pdks / kapi / yemekhane / servis: 400 21000, değişiklik yok
    yeni: dosya_yukle|ik.muduru|200|aktarim+1,ham_okutma+1|aynı (matrisle)
          pdks: 200 aktarim+1,ham_okutma+2 · kapi / yemekhane / servis: 200 aktarim+1,kanit_kaydi+2
    yetkisiz (montaj.amiri) 400 "Bu işlem için yetkiniz yok." · anon 401 · her ikisinde değişiklik yok
    diğer 33 RPC ve 63 hata denemesinin sonucu değişmedi (iki çıktının farkı yalnızca dosya_yukle satırları)
    ```
  - Kalıcı test `supabase/tests/where_siz_guncelleme_testi.sql` (9 test): bütün `pdks` fonksiyonlarını tarar. Önce kendini sınar (hatalı örnekleri yakalar; WHERE'li, `ON CONFLICT DO UPDATE`, `SELECT ... FOR UPDATE`, yorum ve metni yakalamaz). Eski kodda `dosya_yukle`'yi bulup KALDI, yenisinde GEÇTİ.
  - İki tur: örnek veriyle 22/22 dosya GEÇTİ; verisiz 21/22 (`ornek_veri_testi` örnek veri ister, öncekiyle aynı).
  - Denenmedi: ekranın kendisi (G4), canlı (bağlanmak yasak).
- **Durum:** ✅ Düzeltildi — PR #35 (`main`'de, 22 Kasım). Canlıya 26 Kasım kurulumunda uygulanır (Fırat).

### T-32 · İK kararı, soruyu cevaplayan amirin adını siliyor
- **Adım:** Endpoint · **Önem:** Orta
- **Yer:** `pdks.soru_ik_karari`: `update pdks.amir_sorusu set durum = 'kapandi', cevaplayan_id = v_ben, …`
- **Ne oldu:**
  - Montaj amiri soruya "bilmiyorum" demişti (`cevaplayan_id` = montaj.amiri). İK kararından sonra `cevaplayan_id` = ik.muduru oldu; `cevap` "bilmiyorum" olarak kaldı.
  - Amirin cevabı başka bir yerde de yok. "Gelmedi" ve "bilmiyorum" cevapları gün kaydını değiştirmediği için `duzeltme`'ye satır yazılmıyor; amirin bu soru için `duzeltme` satırı 0.
- **Ne olmalıydı:** Amirin cevabı (kim, ne zaman, ne dedi) kalmalı; İK'nın kararı ayrı sütunlarda tutulmalı (ör. `ik_karar_veren_id`, `ik_karar_zamani`).
- **Kanıt:**
  ```
  önce  cevap=bilmiyorum cevaplayan=montaj.amiri@example.com
  sonra cevap=bilmiyorum cevaplayan=ik.muduru@example.com durum=kapandi
  amirin adı başka bir tabloda: duzeltme=0
  ```
- **Sade dille:** Devamsızlık kararı (çalışan aleyhine) amirin "gelmedi" demesine dayanıyor. İK karar verince "gelmedi"yi kimin söylediği kayıttan siliniyor. Çalışan itiraz ederse ya da iş mahkemesine giderse, kararın dayanağını gösteremeyiz.
- **Öneri:** Yeni migration: `amir_sorusu`'na İK kararı için ayrı sütunlar; `soru_ik_karari` `cevaplayan_id`'ye dokunmasın. Kalıcı test: İK kararından sonra `cevaplayan_id` değişmemiş olmalı.
- **Durum:** Açık

### T-33 · Kullanıcı ekleme ve rol / aktiflik değişikliği iz bırakmıyor
- **Adım:** Endpoint · **Önem:** Orta
- **Yer:** `pdks.kullanici_ekle`, `pdks.kullanici_guncelle`; `kullanici` tablosunda "kim ekledi / kim değiştirdi" sütunu ve geçmiş tablosu yok.
- **Ne oldu:**
  - Admin, kalite amirinin rolünü `ik` yaptı. Değişen tek tablo `kullanici` (1 satır); eski rol hiçbir yerde kalmadı.
  - Aynı yetki aktiflik ve üst amir için de geçerli. `kullanici_ekle` de kimin eklediğini yazmıyor.
  - Karşılaştırma: ayar değişikliği `ayar_gecmisi`'ne, bölge yetkisi `bolge_yetkisi_gecmisi`'ne yazılıyor.
- **Ne olmalıydı:** Rol, aktiflik ve üst amir değişikliği kim / ne zaman / eski / yeni değerle silinemeyen bir tabloya yazılmalı.
- **Kanıt:** `e3_ek d) değişen tablo: kullanici (1) · kalite.amiri rolü şimdi: ik`. `kullanici` sütunları: `id ad_soyad eposta rol ust_amir_id izinli_mi auth_kullanici_id aktif olusturma_zamani calisan_id`.
- **Sade dille:** Sistem yöneticisi birine bir günlüğüne İK rolü verip geri alabilir; sistemde bunun izi kalmaz. O gün yapılan kararlar o kişinin adıyla görünür, ama "bu kişi neden İK yetkisine sahipti" sorusunun cevabı yoktur. T-10'daki (ayarlar) kaygının kullanıcı tarafı.
- **Öneri:** `kullanici_gecmisi` tablosu ve bir tetikleyici (ayar_gecmisi gibi). Kalıcı test: rol değişince geçmişe bir satır.
- **Durum:** ✅ Düzeltildi (feature/T72-rol-onayi, T-72 ile). `kullanici_gecmisi` ve `kullanici_iz` tetikleyicisi: hesap, rol, aktiflik, üst amir, çalışan bağı ve e-posta değişiklikleri; yapan, zaman, eski / yeni değer. Test: `rol_onayi_testi.sql`.

### T-34 · Düzeltmeye başka çalışanın, başka günün ya da reddedilmiş bir itirazı bağlanabiliyor
- **Adım:** Endpoint · **Önem:** Düşük
- **Yer:** `pdks.kayit_duzelt` → `duzeltme_uygula` → `duzeltme_hazirla` (itiraz denetimi yok; yalnızca yabancı anahtar). Ekran: `calisanlar/[id]/duzeltme-alanlari.tsx` ve `page.tsx` (itiraz listesi süzülmüyor).
- **Ne oldu:**
  - 1004'ün 5 Kasım günü düzeltildi ve düzeltme 1006'nın 6 Kasım itirazına bağlandı; kabul edildi.
  - Ekranda liste o günün itirazlarıyla sınırlı, ama durum süzülmüyor. Tek itiraz varsa (reddedilmiş olsa bile) varsayılan olarak seçili geliyor.
- **Ne olmalıydı:** Veritabanı, bağlanan itirazın aynı gün kaydına ait olduğunu denetlemeli. Ekran yalnızca açık, incelenen ya da kabul edilmiş itirazları listelemeli; varsayılanı yalnızca kabul edilmiş itiraz için seçmeli.
- **Kanıt:** `e3_ek b) duzeltme satırı: gün çalışanı=1004 · itirazın çalışanı=1006 · itirazın günü=2026-11-06`.
- **Sade dille:** Düzeltme kaydında "bu düzeltme şu itiraz üzerine yapıldı" yazıyor, ama o itiraz başka birinin başka bir gününe ait olabilir. Denetimde iz yanıltıcı olur.
- **Öneri:** `duzeltme_hazirla`'ya `itiraz.gun_kaydi_id = new.gun_kaydi_id` denetimi (yeni migration ve test). Ekran için Gökalp: G3.
- **Durum:** Ekran tarafı düzeltildi (PR #40: reddedilmiş itiraz düzeltme penceresinde listelenmez). Veritabanı tarafı açık (`kayit_duzelt` hâlâ kabul ediyor), Yusuf.

### T-35 · İtirazı incelemeye alma ve arıza kararında "kim, ne zaman" eksik
- **Adım:** Endpoint · **Önem:** Görüş
- **Yer:** `pdks.itiraz_incelemeye_al` (yalnızca `durum`), `pdks.ariza_karar` (`giren_id = v_ben`)
- **Ne oldu:**
  - `itiraz_incelemeye_al` yalnızca `durum`'u değiştiriyor; kimin, ne zaman incelemeye aldığı yazılmıyor.
  - `ariza_karar` karar vereni `giren_id` sütununa yazıyor ve karar zamanını tutmuyor. Gece işinin açtığı şüphede `giren_id` boş olduğu için bu örnekte bilgi kaybolmadı, ama sütunun anlamı "giren"den "karar veren"e kayıyor.
- **Ne olmalıydı:** Diğer kararlar gibi (`itiraz_karar`, `fazla_mesai_karar`) ayrı `karar_veren_id` ve `karar_zamani`.
- **Kanıt:** Madde 3 matrisi: `itiraz_incelemeye_al|itiraz|0|1|0|durum`, `ariza_karar|ariza|0|1|0|durum,giren_id`.
- **Sade dille:** İki küçük işlemde kimin ne zaman yaptığı kayda geçmiyor. Önemi düşük, ama kayıt düzeninde istisna.
- **Öneri:** Adım 14'te karar. Düzeltilecekse iki sütun ve fonksiyon güncellemesi.
- **Durum:** Açık

### T-36 · `kart_tanimla` kart numarasının biçimini denetlemiyor
- **Adım:** Endpoint · **Önem:** Düşük
- **Yer:** `pdks.kart_tanimla`
- **Ne oldu:** `ÇOK-UZUN-KART-NUMARASI-1234567890-ABCDEFG` kabul edildi (kart no 79). İçinde Türkçe harf var ve 32 karakterden uzun.
  - Ekran bunu engelliyor (`^[A-Z0-9-]{1,32}$`).
  - `dosya_yukle` okutmadaki kart numarasını aynı kuralla reddediyor. Bu kartla yapılan okutma hiçbir zaman içeri alınamaz.
- **Ne olmalıydı:** Veritabanı da aynı kuralı uygulamalı (ekrandaki denetim tek başına yeterli değil; CLAUDE.md §4).
- **Kanıt:** `e5_maskeli: kart_tanimla uzun ve Türkçe karakterli kart no|P0001|GERI_AL:79` (başarılı; alt işlem geri alındı).
- **Sade dille:** Ekran dışından (ör. ileride başka bir araçla) tanımlanan bozuk numaralı kart sessizce kabul edilir; o kişinin okutmaları sisteme hiç girmez.
- **Öneri:** `kart.kart_no`'ya `check (kart_no ~ '^[A-Z0-9-]{1,32}$')`. Önce mevcut verinin uyduğu doğrulanmalı. Yeni migration ve test.
- **Durum:** Açık

### T-37 · Veri aktarımı formu veritabanı hatasını ham gösteriyor
- **Adım:** Endpoint · **Önem:** Düşük (Gökalp için)
- **Yer:** `app/(panel)/veri-aktarimi/aktarim-formu.tsx`
  - `setYukleme({ tur: "hata", mesaj: error.message })`
  - `Dosya okunamadı: ${e.message}`
- **Ne oldu:** T-31'deki hatada ekranda "UPDATE requires a WHERE clause Hiçbir satır kaydedilmedi." görünür. Diğer bütün yazmalar `rpcCagir`'in `hataMesaji` çevirisinden geçiyor; bu form tarayıcıdan doğrudan çağırdığı için geçmiyor. Production'da da görünür, çünkü hata tarayıcıda oluşuyor ve Next.js onu gizlemiyor.
- **Ne olmalıydı:** Aynı Türkçe çeviri. `hataMesaji` `server-only` dosyada; tarayıcıda da kullanılabilecek ortak bir dosyaya taşınabilir.
- **Kanıt:** e4_http madde 4 ilk satır ve madde 5'in `dosya_yukle` satırları (ekran sütunu = ham mesaj).
- **Sade dille:** İK, dosya yüklerken İngilizce teknik bir cümle görür ve ne yapacağını bilemez.
- **Öneri:** Gökalp: G1.
- **Durum:** ✅ Düzeltildi — PR #40 (`lib/supabase/hata.ts`: yükleme formu ve `rpcCagir` aynı Türkçe çeviriyi kullanır).

### T-38 · İşe giriş ve işten çıkış için ekran yok
- **Adım:** Endpoint · **Önem:** Orta (Gökalp için)
- **Yer:** `calisan_ekle`, `isten_cikis_gir` (`20261130010000_ise_giris_cikis.sql`); `app/` altında çağıran yok.
- **Ne oldu:** İki fonksiyon veritabanında var, yetkileri doğru (yalnızca İK; HTTP'de çalıştı, admin reddedildi). Ama hiçbir ekran onları çağırmıyor. README'de işe giriş / işten çıkış ✅.
- **Ne olmalıydı:** Çalışanlar sayfasında "Çalışan ekle" ve çalışan sayfasında "İşten çıkış" pencereleri.
- **Kanıt:** Ekranda `rpcCagir` / `.rpc(` geçen 33 çağrı listesi; ikisi yok (`docs/endpoint_testi.md` madde 1).
- **Sade dille:** İK yeni başlayan birini ya da ayrılan birini sisteme giremez; bunu ancak veritabanından elle yapabiliriz. Demoda bu akış gösterilemez.
- **Öneri:** Gökalp: G2. Parametreler ve mesajlar `docs/ekran_fonksiyonlari.md` satır 98–99'da hazır.
- **Durum:** ✅ Düzeltildi — PR #37 (Çalışanlar: "Çalışan ekle"; çalışan sayfası: "İşten çıkış").

### Gökalp için
- **G1 (T-37):** `aktarim-formu.tsx` hataları `rpcCagir`'deki Türkçe çeviriden geçirsin.
- **G2 (T-38):** "Çalışan ekle" ve "İşten çıkış" pencereleri.
- **G3 (T-34):** Düzeltme penceresinde itiraz listesi yalnızca açık, incelenen ve kabul edilmiş itirazları göstersin; reddedilmiş itiraz varsayılan olarak seçilmesin.
- **G4 (T-31 düzeltilince):** Ekrandan bir PDKS ve bir kapı dosyası gerçekten yüklenip sonucu görülsün.

### Denediklerim
- 34 yazma RPC'sinin ekrandaki zinciri (sayfa → düğme → action → RPC → parametre kaynağı).
- 34 RPC × 35 tablo önce / sonra farkı (SQL) ve aynı 34 çağrı HTTP'den: yetkili, yetkisiz ve anon.
- 8 tablo / view × 11 rol okuma (HTTP ve SQL).
- 63 hata denemesi ve 4 tekrar.
- 117 fonksiyonda `WHERE`'siz `UPDATE` / `DELETE` taraması.

### Denemediklerim
- Tarayıcıda gerçek ekran (Server Action katmanı yalnızca okundu).
- Canlıda T-31 (bağlanmak yasak; canlıya 28 Kasım migration'ının uygulanıp uygulanmadığını bilmiyorum).
- PDKS dışındaki dosya kaynakları.
- Veri olan bir ayın kilitlenmesi (Adım 12).
- İndirmeler ve eş zamanlı istekler.

### Şüpheler
- `PGRST202`'nin "migration uygulanmamış" diye çevrilmesi, parametre adı hatasını gizleyebilir.
- `kart_tanimla`'nın çalışan numarası adresten geliyor; yetki veritabanında, ama adres değiştirilirse yanlış kişiye kart tanımlanabilir. Denenmedi.

---

## Adım 7 — Amir soruları ve İK kararları (22 Kasım 2026)

**Başlangıç:** `main` @ `79ad042` (T-31 düzeltmesi dahil, 31 migration). Yerel veritabanı `supabase db reset` ile kuruldu.

**Betikler:**

| Betik | Ne sınıyor |
|---|---|
| `scratch/a7_soru.sql` | 30 vaka; her cevap türü, İK kararları, eskalasyon zinciri, kanıtın sonradan gelmesi, vekil, devamsızlık denemeleri (7 rol × 8 yol + sistem), kilitli ay |
| `scratch/a7_soru_sonuc.txt`, `scratch/a7_soru_ozet.txt` | Ham çıktı; her vakada yalnızca değişen aşamalar |
| `scratch/a7_kod/*.sql` | Okunan 16 fonksiyonun son sürümü |

**Kurulum:**
- Hepsi tek işlem; sonda `ROLLBACK`.
- Üç deneme departmanı:
  - **S7 Deneme:** amiri montaj.amiri, onun üst amiri üretim müdürü; üretim müdürünün üst amiri yok.
  - **S7 GM:** amiri genel müdür; üst amiri yok.
  - **V7 Deneme:** amiri kalite amiri, vekili Bobinaj amiri.
- Günler 14 ve 15 Ekim; GÜNDÜZ vardiyası (08:00–17:00).
- Gece işi doğrudan çalıştırıldı. Cevaplar ve kararlar rol taklidiyle verildi; amir olarak montaj.amiri, İK olarak ik.muduru.

### Sonuç tablosu 1 — her cevap türü günü nasıl değiştiriyor

"Düzeltme" sütunu: `duzeltme` tablosuna yazılan satır (alan / kaynak). "Hemen hesap": cevap ya da kararla aynı işlemde `gun_hesapla` çalıştı mı (`hesap_tamam`, `calisma_dk`).

| Soru türü → cevap | Ne yaptım | Beklenen | Gerçekleşen gün | Düzeltme kaydı | Hemen hesap | |
|---|---|---|---|---|---|---|
| giriş yok → geldi, saat doğru | GY1 | Giriş = plan 08:00, gün tamam | tamam 08:00–17:00, 480 dk | giriş / amir | ✓ | ✅ |
| giriş yok → saat farklı (08:20) | GY2 | Giriş 08:20, geç 20 | tamam 08:20–17:00, 460 dk | giriş / amir | ✓ | ✅ (aleyhe işareti yok, T-44) |
| giriş yok → kart unuttu | GY3 | "Saat doğru" ile aynı | tamam 08:00–17:00, 480 dk | giriş / amir | ✓ | ✅ |
| giriş yok → gelmedi | GY4 | Gün değişmez, İK'ya geçer | soru_bekliyor, soru `ik_karari_bekliyor` | yok | — | ✅ |
| … → İK devamsız | GY4 | devamsız, dakikalar temiz | devamsız, dakika yok, hesap ✓ | durum / ik / **aleyhe** | ✓ | ✅ |
| giriş yok → bilmiyorum → İK geldi 08:05 | GY5 | Giriş 08:05 | tamam 08:05–17:00, 475 dk | giriş / ik | ✓ | ✅ |
| giriş yok → saat farklı, ama yalnızca çıkış girildi (17:30) | GY6 | Reddetmeli ya da giriş yine sorulmalı | **soru_bekliyor, giriş yok, hesap ✗; soru "cevaplandı"** | çıkış / amir | ✗ | ❌ T-41 |
| çıkış yok → saat doğru | CY1 | Çıkış 17:00 | tamam 07:58–17:00, 480 dk | çıkış / amir | ✓ | ✅ |
| çıkış yok → saat farklı (16:00) | CY2 | Erken 60 | tamam 07:58–16:00, 420 dk | çıkış / amir | ✓ | ✅ (aleyhe işareti yok, T-44) |
| çıkış yok → kart unuttu | CY3 | Çıkış 17:00 | tamam, 480 dk | çıkış / amir | ✓ | ✅ |
| çıkış yok → gelmedi → İK geldi (17:00) | CY4 | Çıkış 17:00 | tamam, 480 dk | çıkış / ik | ✓ | ✅ |
| çıkış yok → bilmiyorum → İK devamsız | CY5 | devamsız | devamsız, dakika yok | durum / ik / aleyhe | ✓ | ✅ |
| hiç kayıt yok → saat doğru | HK1 | 08:00–17:00 | tamam, 480 dk | giriş + çıkış / amir | ✓ | ✅ |
| hiç kayıt yok → saat farklı (08:00–12:00) | HK2 | 4 saat | tamam, 225 dk (mola 15) | giriş + çıkış / amir | ✓ | ✅ |
| hiç kayıt yok → kart unuttu | HK3 | 08:00–17:00 | tamam, 480 dk | 2 / amir | ✓ | ✅ |
| hiç kayıt yok → gelmedi → İK devamsız | HK4 | devamsız | devamsız, dakika yok | durum / ik / aleyhe | ✓ | ✅ |
| hiç kayıt yok → bilmiyorum → İK geldi, yalnızca giriş | HK5 | Reddetmeli ya da çıkış sorulmalı | **soru_bekliyor, çıkış yok, hesap ✗; soru "kapandı"** | giriş / ik | ✗ | ❌ T-41 |
| hiç kayıt yok → saat farklı, yalnızca giriş | HK6 | Reddetmeli ya da çıkış sorulmalı | **soru_bekliyor, çıkış yok, hesap ✗; soru "cevaplandı"** | giriş / amir | ✗ | ❌ T-41 |
| kapı 08:30, PDKS girişi yok → saat doğru | KV1 | Kanıt + 5 dk yürüme payı = 08:35 | tamam 08:35–17:00, 445 dk | giriş / amir | ✓ | ✅ |
| hiç kayıt yok → saat farklı 08:00–08:00 | Z1 | Reddetmeli | Reddedildi: `gun_kaydi_check` (ekranda "Girilen değer geçersiz.") | yok | — | ✅ |
| Kapanmış sorunun günü sonradan değişir: İK çıkışı 16:30 yapar | KD1 | Gün yeniden hesaplanır, soru kapalı kalır | tamam 07:58–16:30, 450 dk; soru "cevaplandı" | çıkış / amir + çıkış / ik | ✓ | ✅ |
| Kilitli ayda (Ekim) cevap | LK1 | Gün değişmez, düzeltme sonraki aya fark | Gün değişmedi; 2 düzeltme `FARK`, hedef dönem 2026-11; soru "cevaplandı" | 2 / amir / fark | — | ✅ |

Planlı GÜNDÜZ olup 16:00–23:58 okutan kişi (VU1) için vardiya önerisi sorusu bekliyordum. Çıkmadı, çünkü öneri önceki günün (13 Ekim) PDKS dosyasını da istiyor ve ben yüklememiştim. Kurulum eksiği; bulgu değil (bkz. Şüpheler).

### Sonuç tablosu 2 — diğer maddeler

| # | Madde | Ne yaptım | Beklenen | Gerçekleşen | |
|---|---|---|---|---|---|
| 1 | Devamsızlığı İK dışında kimse oluşturamaz | 6 İK dışı rol (amir, üst amir, güvenlik, yönetici, İSG, admin) × 8 yol: `kayit_duzelt`, `soru_ik_karari`, `duzeltme_uygula`, `gun_kaydi` UPDATE / INSERT, `duzeltme` INSERT, `amir_sorusu` UPDATE, `gece_isi_tetikle`. Ayrıca pasif İK (2 yol) ve sistemin kendisi (postgres: kaynak `gece_isi`, `amir`, ya da `ik` ama yapan amir) | Hepsi reddedilir | **53 / 53 reddedildi** ("Bu işlem için yetkiniz yok", `permission denied`, "Devamsızlığı yalnızca İK verebilir", "İK kaynaklı düzeltmeyi yalnızca İK rolü yapabilir", "Oturum bulunamadı"). Amirin "gelmedi"si günü değiştirmiyor. Sonda yalnızca İK'nın verdiği 4 gün devamsız (CY5, DV1, GY4, HK4) | ✅ |
| 2 | Süresi dolan soru üst amire | 18 Ekim eskalasyonu (son cevap günü = gün + 1 + 3) | 8 soru üst amire | 8 soru eskale; montaj → üretim müdürü; `soru_eskale` uyarısı yazıldı | ✅ |
| 3 | Üst amiri olmayanın sorusu İK'ya; İK kapatabilir | ZN3 (amir = genel müdür) | İK'ya gider, İK kapatır | Eskale: ik.uzmani; ik.muduru `soru_ik_karari` ile kapattı, gün tamam | ✅ |
| 4 | Üst amir de cevaplamazsa (amir → üst amir → İK) | ZN1: 31 Ekim ve 30 Kasım'da eskalasyon yeniden; sonra İK karar vermeye çalışır | İK'ya gitmeli | **Soru üretim müdüründe kaldı** (ikinci eskalasyonda 0 soru); İK: "İK kararı bekleyen soru bulunamadı." Z1'de İK günün iki saatini düzeltti: **hesap ✗, dakika yok** | ❌ T-39 |
| 5 | Zincirde kim ne dedi kalıyor mu (T-32) | ZN2: amir cevaplamadı → üst amir "bilmiyorum" ("Vardiyada değildim") → İK geldi | Her adım kayıtta | Atanan (montaj) ✅. Eskale edilen (üretim) ✅ + `soru_eskale` uyarısı ✅. **Üst amirin "bilmiyorum"unu kimin dediği İK kararından sonra kayboldu** (`cevaplayan` = ik.muduru); metni `cevap_aciklama`'da duruyor. İK'nın kararı ✅ (`duzeltme`, kaynak ik) | ❌ T-32 (aynı kök) |
| 6 | Kanıt sonradan gelir (T-23) | KS1: giriş yok sorusu açıldı; kapı kanıtı (07:50) yüklendi; gece işi yeniden; 18 Ekim eskalasyonu; amir "saat doğru" | Soru kanıtla kapanmalı ya da kanıt saati önerilmeli | Gece işi yeniden: **soru açık kaldı**. 18 Ekim'de **üst amire eskale oldu**. Amir "saat doğru" deyince giriş **08:00 (plan)** yazıldı, 07:55 (kanıt + yürüme payı) değil | ❌ T-42 |
| 7 | İK soru açıkken günü düzeltir | KS2: İK girişi 07:50 yaptı; sonra amir "saat doğru" | Soru kapanmalı, gün hesaplanmalı; sonraki cevap İK'nın düzeltmesini bozmamalı | İK düzeltmesinden sonra gün **soru_bekliyor, hesap ✗** (soru açık). Amirin cevabı girişi **08:00'e geri yazdı**; İK'nın 07:50'si ezildi | ❌ T-40 |
| 8 | İK devamsız dedikten sonra açık soru | DV1: soru üst amirdeyken İK `kayit_duzelt` ile devamsız yaptı; sonra üst amir "saat doğru" | Soru kapanmalı; devamsız güne saat yazılmamalı | Soru açık kaldı. Üst amirin cevabı kabul edildi: gün **devamsız ama 08:00–17:00**, hesap ✗; soru "cevaplandı" | ❌ T-40 |
| 9 | Amir başka departmanın sorusunu cevaplayamaz | Bobinaj amiri, S7'nin sorusu (DV1) | Red | "Soru bulunamadı ya da size atanmamış." | ✅ |
| 10 | Vekil amir cevaplayabilir | VK2: amir izindeyken açılan soru → vekil | Kabul | Soru vekile atandı, vekil cevapladı | ✅ |
| 11 | Amir izne çıkmadan açılmış soru | VK1: soru açıldıktan sonra amir izinli oldu; vekil dener | Vekil cevaplayabilmeli | **Vekil reddedildi** ("size atanmamış"). İzindeki amir cevaplayabildi | ❌ T-43 |
| 12 | Aynı soruyu iki kez cevaplamak | Endpoint testinde HTTP ile | Red | "Bu soru zaten cevaplanmış." | ✅ |
| 13 | Devamsız günde dakikalar temizleniyor, gün beklemede kalmıyor (PR #33) | GY4, CY5, HK4, DV1 | Dakikalar boş, hesap tamam | Hepsinde `durum = devamsiz`, dakika yok, `hesap_tamam = true` | ✅ |
| 14 | Kilitli ay → fark satırı | LK1 (tablo 1) | Fark | ✅ hedef dönem 2026-11. Kilit özeti: "Zorla geçilenler: 3 açık sorulu gün. Puantaja kodsuz giren gün: 6." | ✅ |

### Kod incelemesi (Ek A)

Okunan fonksiyonlar: `soru_cevapla`, `soru_ik_karari`, `kayit_duzelt`, `duzeltme_uygula`, `duzeltme_hazirla`, `gun_kaydi_koru`, `amir_sorusu_kontrol`, `amir_sorusu_yonlendir`, `saat_yaz`, `gun_hesapla`, `gece_isi_sorular`, `gece_isi_eskale`, `soru_atanacak`, `ik_sorumlusu`.

| # | Soru | Gözlem |
|---|---|---|
| 1 | Yetki | Her RPC `yetki_gerekli` ile başlıyor ✅. Devamsızlık üç katmanda korunuyor: `kayit_duzelt` / `soru_ik_karari` yalnızca İK; `duzeltme_hazirla` kaynak ve rol uyumu; `gun_kaydi_koru` doğrudan değişikliği reddediyor ✅ |
| 2 | Görevler ayrılığı | Amirin kendisiyle ilgili soru `amir_sorusu_yonlendir` ile üst amire / İK'ya yönleniyor ✅ |
| 3 | Kapsam | `soru_cevapla` yalnızca `atanan_id` ve `eskale_edilen_id`'ye bakıyor; vekillik yalnızca soru açılırken değerlendiriliyor (T-43) |
| 4 | Zincirleme etki | ❌ `kayit_duzelt` açık soruya bakmıyor, onu kapatmıyor; `gun_hesapla` açık soru varken günü hesaplamıyor (T-40). `soru_cevapla` günün o anki durumuna bakmıyor (devamsız güne saat yazıyor, T-40). Yarım cevapta eksik saat için yeni soru açılmıyor (T-41) |
| 5 | Kilitli ay | ✅ `duzeltme_hazirla` fark satırına çeviriyor; `gun_hesapla` kilitli ayda hesaplamıyor |
| 6 | İz | ✅ Saat ve durum değişiklikleri `duzeltme`'de (kaynak amir / ik, `soru_id` bağlı). ❌ `cevaplayan_id` İK kararıyla eziliyor (T-32). Amirin aleyhe saati `calisan_aleyhine` işaretlenmiyor (T-44) |
| 7 | Kenar durumlar | ❌ Tek saatli cevap (T-41). ❌ İkinci kademe eskalasyon yok (T-39) |
| 8 | Saat dilimi | ✅ Önerilen saatler `timestamptz`; çıktılar `Europe/Istanbul` ile doğru |
| 9 | Güvenlik | ✅ `search_path` sabit; dinamik SQL yok |
| 10 | Test | `gece_isi_testi` tek kademe eskalasyonu ve "üst amiri yoksa İK"yı sınıyor; ikinci kademe, yarım cevap, açık soruda İK düzeltmesi ve devamsız günde amir cevabı için test yok |

### Bulgular

### T-39 · Üst amir de cevaplamazsa soru hiçbir zaman İK'ya gitmiyor; İK ne soruyu kapatabiliyor ne günü hesaplatabiliyor
- **Adım:** 7 · **Önem:** Yüksek
- **Yer:**
  - `pdks.gece_isi_eskale`: yalnızca `durum = 'acik'` soruları ilerletiyor.
  - `pdks.soru_ik_karari`: `eskale` durumundaki soruyu yalnızca eskale edilen kişi İK ise kabul ediyor.
  - `pdks.gun_hesapla`: açık (`acik` / `eskale` / `ik_karari_bekliyor`) soru varken hesaplamıyor.
- **Ne oldu:**
  - ZN1'in sorusu 18 Ekim'de üretim müdürüne eskale oldu. 31 Ekim ve 30 Kasım eskalasyonlarında hiç ilerlemedi (yalnızca o gün süresi dolan başka bir soru eskale oldu); soru `eskale` durumunda kaldı.
  - İK karar vermeye çalıştı: "İK kararı bekleyen soru bulunamadı."
  - Aynı durumdaki Z1'de İK günün giriş ve çıkışını `kayit_duzelt` ile yazdı: gün `soru_bekliyor`, `hesap_tamam = false`, dakika yok. İK durumu `tamam` yapınca gün "tamam" oldu, ama dakikalar boş ve hesap ✗.
  - Kilit özeti bu günleri "açık sorulu gün" olarak zorla geçiyor ve puantaja kodsuz giriyor.
- **Ne olmalıydı:** Üst amir de süresinde cevaplamazsa soru İK'ya gitmeli (amir → üst amir → İK). Ya da İK her açık soruyu kapatabilmeli.
- **Kanıt:**
  ```
  ZN1|6 eskale (18 Ekim)|soru_bekliyor …|hic_kayit_yok:eskale [atanan montaj.amiri, eskale uretim.muduru]
  eskale 31 Ekim: 1 · eskale 30 Kasım: 0      (ZN1 yerinde kaldı)
  ZN1|ik.muduru|HATA P0001: İK kararı bekleyen soru bulunamadı.
  Z1|13c İK üst amirde takılı günü düzeltti|soru_bekliyor · 08:00–17:00 · dk yok · hesap ✗
  Z1|13d İK durumu tamam yapmayı denedi|tamam · 08:00–17:00 · dk yok · hesap ✗
  ```
- **Sade dille:** Amir izindeyse ya da ilgilenmiyorsa soru üretim müdürüne gidiyor. Üretim müdürü de bakmazsa soru orada sonsuza kadar bekliyor. İK'nın elinde de çözüm yok: günü kendisi düzeltse bile sistem "bu günün açık sorusu var" diyip hesap yapmıyor. Ay sonunda bu günler puantaja kodsuz giriyor; çalışanın o günü ne çalışılmış ne de izinli sayılıyor. 2000 kişilik bir fabrikada üst amirlerin her soruya bakmasını beklemek gerçekçi değil.
- **Öneri:**
  - `gece_isi_eskale` `eskale` durumundaki ve süresi ikinci kez dolan soruları İK'ya (`ik_sorumlusu`) yeniden eskale etsin; yeni bir `ikinci_eskale_zamani` ya da sayaç.
  - Ayrıca `soru_ik_karari` her açık soruyu kabul edebilir (İK son karar verici). Ya da `kayit_duzelt` açık soruyu kapatsın (T-40 ile birlikte).
  - Yeni migration ve `gece_isi_testi`'ne ikinci kademe testi.
- **Durum:** ✅ Düzeltildi — PR #55 (migration: `20261210010000_ikinci_eskale.sql`, test: `soru_eskale_testi.sql`).
  - `gece_isi_eskale`: amir → üst amir → İK. Üst amir de son cevap tarihinden `soru_eskalasyon_gun` (3) gün sonra cevaplamadıysa soru `ik_karari_bekliyor` olur; üst amirin adı (`eskale_edilen_id`) silinmez, yeni `amir_sorusu.ik_eskale_zamani` dolar, İK'ya uyarı yazılır. Bir gecede en çok bir kademe. Üst amiri olmayan amirin sorusu ilk kademede İK'ya gider, bir daha taşınmaz.
  - `soru_ik_karari`: İK her açık soruya (`acik` / `eskale` / `ik_karari_bekliyor`) karar verebilir; son karar İK'da (K2 kural 1).
  - Ekran (Sorular, İK karar penceresi): "Amir ve üst amir (…) süresinde cevaplamadı; soru İK'ya gitti."
  - Yerelde yeniden üretildi ve ekranda doğrulandı: Ali Demir (S2) ve Mustafa Şahin (S4) soruları 1 Aralık gecesi eskalasyonunda Levent Sarı'dan İK'ya geçti; Elif Şen "Karar ver" ile kapattı.
  - Örnek veride Kasım sonunda S2 ve S4 artık İK'da (`ay_kilidi_testi`, `ornek_veri_testi`, `docs/demo_akisi.md` buna göre güncellendi).
  - Not (karar gerekir, bu PR'da değil): üst amir, başka departmanın çalışanını RLS yüzünden göremiyor; Sorularım'da "Görüntülenemiyor" çıkıyor (bkz. Adım 12 "Üst amir görünümü" görüşü). Üst amirin cevaplamamasının bir sebebi bu olabilir.

### T-40 · İK'nın kayıt düzeltmesi açık soruyu kapatmıyor; sonraki amir cevabı İK'nın düzeltmesini ve devamsızlık kararını bozuyor
- **Adım:** 7 · **Önem:** Orta
- **Yer:** `pdks.kayit_duzelt` (soruya dokunmuyor), `pdks.soru_cevapla` (günün durumuna ve son düzeltmeye bakmadan `saat_yaz`), `pdks.gun_hesapla` (açık soru varken hesaplamıyor)
- **Ne oldu:**
  - **KS2:** Soru açıkken İK girişi 07:50 yaptı. Gün `soru_bekliyor`, hesap ✗ kaldı. Amir sonradan "saat doğru" dedi: giriş 08:00 (plan) yazıldı, İK'nın 07:50'si ezildi. Gün tamam oldu.
  - **DV1:** Soru üst amirdeyken İK günü devamsız yaptı; soru açık kaldı. Üst amir "saat doğru" dedi ve kabul edildi. Gün `devamsiz`, ama giriş 08:00 – çıkış 17:00 yazılı ve hesap ✗. Soru "cevaplandı".
- **Ne olmalıydı:**
  - İK'nın düzeltmesi (özellikle bir karar) o günün açık sorularını "İK düzeltti" diye kapatmalı.
  - `soru_cevapla` kapanmış ya da İK'nın karar verdiği günde saat yazmamalı.
- **Kanıt:**
  ```
  KS2|4 İK düzeltti (soru açık)|soru_bekliyor · 07:50–17:00 · dk yok · hesap ✗|giris_yok:acik
  KS2|5 amir sonra cevapladı|tamam · 08:00–17:00 · 480 dk|… 2 düzeltme (giris=07:50/ik, giris=08:00/amir)
  DV1|13 İK devamsız|devamsiz · —–— · hesap ✓|hic_kayit_yok:eskale
  DV1|13b üst amir devamsızdan sonra cevapladı|devamsiz · 08:00–17:00 · dk yok · hesap ✗|…:cevaplandi:geldi_saat_dogru
  ```
- **Sade dille:** İK bir günü düzeltse bile amirin ekranında soru durmaya devam ediyor. Amir haftalar sonra "geldi, saat doğru" diye cevap verince İK'nın kararı sessizce eziliyor. Devamsız sayılmış bir günde sistem hem "gelmedi" hem "08:00–17:00 çalıştı" diyor. Puantaj, itiraz ve iş mahkemesinde hangisinin doğru olduğu belirsiz kalır.
- **Öneri:**
  - `kayit_duzelt` o günün açık sorularını kapatsın (`durum = 'kapandi'`, açıklama "İK kayıt düzeltmesi", ayrı karar sütunlarıyla; T-32). Sonra `gun_hesapla`.
  - `soru_cevapla` gün `devamsiz` / `izinli` / `raporlu` ise ya da sorudan sonra İK düzeltmesi varsa reddetsin.
  - Yeni migration ve test.
- **Durum:** Açık

### T-41 · Tek saatli cevap günü askıda bırakıyor: soru kapanıyor, eksik saat için yeni soru açılmıyor
- **Adım:** 7 · **Önem:** Orta
- **Yer:** `pdks.soru_cevapla` ve `pdks.soru_ik_karari` ("giriş ya da çıkış" yeterli sayılıyor); `pdks.gece_isi_sorular` yalnızca `durum = 'eksik'` günlere soru açıyor. Ekran da tek saati kabul ediyor (`sorular/actions.ts`: `!giris && !cikis` ise hata).
- **Ne oldu:**
  - **GY6** (giriş yok): Amir "saat farklı" deyip yalnızca çıkış (17:30) girdi. Soru "cevaplandı"; giriş hâlâ yok.
  - **HK6** (hiç kayıt yok): Amir yalnızca giriş girdi.
  - **HK5:** İK "geldi" deyip yalnızca giriş girdi.
  - Üçünde de gün `soru_bekliyor`, hesap ✗ ve açık soru yok. Gün `eksik` olmadığı için gece işi yeni soru da açmıyor.
- **Ne olmalıydı:** Soru türünün gerektirdiği saat eksikse cevap reddedilmeli (hiç kayıt yok → iki saat; giriş yok → giriş; çıkış yok → çıkış). Ya da eksik saat için yeni soru açılmalı.
- **Kanıt:**
  ```
  GY6|2 amir cevabı|soru_bekliyor · —–17:30 · dk yok · hesap ✗|giris_yok:cevaplandi:geldi_saat_farkli
  HK6|2 amir cevabı|soru_bekliyor · 08:00–— · dk yok · hesap ✗|hic_kayit_yok:cevaplandi:geldi_saat_farkli
  HK5|3 İK kararı|soru_bekliyor · 08:00–— · dk yok · hesap ✗|hic_kayit_yok:kapandi:bilmiyorum
  ```
- **Sade dille:** Amir aceleyle yalnızca bir saati yazarsa soru kapanıyor ama gün hesaplanamıyor. Kimse bunu fark etmiyor, çünkü artık açık soru da yok. Ay sonunda bu gün puantaja kodsuz giriyor.
- **Öneri:** `soru_cevapla` / `soru_ik_karari` soru türüne göre gerekli saati denetlesin ("Bu soru için giriş saatini de girin."). Ekran da aynı denetimi yapsın (Gökalp). Yeni migration ve test.
- **Durum:** Kısmen düzeltildi (ekran, `feature/53-t41-t11-ekran`). Veritabanı tarafı açık (Yusuf, K2).

### T-42 · Kanıt sonradan gelince açık soru kapanmıyor, üst amire eskale oluyor; "saat doğru" cevabı kanıt saatini değil plan saatini yazıyor
- **Adım:** 7 · **Önem:** Orta (T-23 ile aynı kök)
- **Yer:** `pdks.gece_isi_calistir` (var olan gün kaydını yeniden işlemiyor; T-19 / T-23), `pdks.soru_cevapla` (`onerilen_zaman` yoksa `planli_baslangic`)
- **Ne oldu:**
  - KS1'in giriş yok sorusu açıldıktan sonra kapı kanıtı (07:50) yüklendi ve gece işi aynı gün için yeniden çalıştı: soru açık kaldı, gün değişmedi.
  - 18 Ekim'de soru üst amire eskale oldu.
  - Amir sonra "saat doğru" dedi: giriş 08:00 (plan) yazıldı.
  - Karşılaştırma: kanıt baştan olsaydı (KV1) soru `kanit_vardiya_sonrasi` türünde açılır, kanıt + 5 dk önerilirdi.
- **Ne olmalıydı:** Gece işi yeniden çalışınca açık soruların günlerinde yeni kanıtı aramalı: kanıt vardiya başından önceyse `kanitla_duzelt` ile düzeltip soruyu kapatmalı; sonraysa soruya önerilen saat olarak eklemeli.
- **Kanıt:**
  ```
  KS1|4 kanıt geldi, gece işi yeniden|soru_bekliyor · —–17:00|giris_yok:acik
  KS1|6 eskale (18 Ekim)|…|giris_yok:eskale [atanan montaj.amiri, eskale uretim.muduru]
  KS1|7 amir kanıttan sonra cevapladı|tamam · 08:00–17:00|… 1 düzeltme (giris=08:00/amir)
  ```
- **Sade dille:** Kapı kaydı geç geldiyse sistem onu görmüyor. Soru amirden üst amire gidiyor; amir "geldi" dediğinde sistem kapıdaki gerçek saati değil plandaki saati yazıyor. T-23'te gereksiz soruyu görmüştük; burada sorunun üst amire kadar gittiğini ve yanlış saatle kapandığını görüyoruz.
- **Öneri:** T-23'ün 2. önerisi (gece işi her çalıştığında açık sorulu günlere yeni kanıtı uygulasın) bunu da çözer. Adım 14'te T-19 ve T-23 ile birlikte karar.
- **Durum:** Açık

### T-43 · Amir izne çıkınca önceden açılmış soruları vekile geçmiyor
- **Adım:** 7 · **Önem:** Düşük
- **Yer:** `pdks.soru_atanacak` (vekil yalnızca soru açılırken), `pdks.soru_cevapla` (yalnızca `atanan_id` / `eskale_edilen_id`)
- **Ne oldu:** VK1'in sorusu kalite amirine atandı. Kalite amiri sonra izinli yapıldı (`izinli_mi = true`). Vekil (Bobinaj amiri) cevaplamayı denedi: "Soru bulunamadı ya da size atanmamış." İzindeki kalite amiri ise cevaplayabildi. Soru 18 Ekim'de üretim müdürüne eskale oldu.
- **Ne olmalıydı:** Amir izinliyken vekil, amirin açık sorularını cevaplayabilmeli. Ya da izne çıkarken açık sorular vekile devredilmeli.
- **Kanıt:** `VK1|bobinaj.amiri|HATA P0001: Soru bulunamadı ya da size atanmamış.` · `VK1|kalite.amiri|OK`
- **Sade dille:** Amir izne çıkmadan önceki günlerin soruları amirde kalıyor. Vekil göremiyor; sorular gereksiz yere üst amire gidiyor.
- **Öneri:** `soru_cevapla`'nın yetki denetimine "atanan izinliyse departmanın vekili" koşulu. RLS'in vekile o soruyu gösterdiği de kontrol edilmeli. Yeni migration ve test.
- **Durum:** Açık

### T-44 · Amirin girdiği aleyhe saat "çalışan aleyhine" işaretlenmiyor
- **Adım:** 7 · **Önem:** Görüş
- **Yer:** `pdks.soru_cevapla` → `saat_yaz` → `duzeltme_uygula` (`p_aleyhine` yalnızca devamsızlıkta true)
- **Ne oldu:** GY2'de amir girişi 08:20 yazdı (geç kalma 20 dk). CY2'de çıkışı 16:00 yazdı (erken çıkış 60 dk). İki düzeltme de `calisan_aleyhine = false`.
- **Ne olmalıydı:** CLAUDE.md'de amire yasak olan aleyhe kararlar devamsızlık, itiraz reddi ve kart paylaşımı; saat bu listede yok. Ama geç kalma ya da eksik çalışma doğuran bir saat, çalışan aleyhine bir değişikliktir. İK'nın bu düzeltmeleri süzebilmesi için işaretlenmeli (ya da bilinçli tercih olarak belgeye yazılmalı).
- **Kanıt:** `GY2|… 08:20–17:00 · 460 dk|… (giris_zamani=…08:20/amir)`. Satırda `/aleyhe` yok; DV1'de İK'nın devamsızlığı `/aleyhe` olarak görünüyor.
- **Sade dille:** Amir "geldi ama 08:20'de geldi" dediğinde çalışan geç kalmış sayılıyor. Sistem bunu "çalışan aleyhine" diye işaretlemediği için İK aleyhe düzeltmeleri listelerken bunu görmez.
- **Öneri:** Adım 14'te karar. Planlı saatten kötü sonuç doğuran amir saatleri için `p_aleyhine => true` (ve İK'ya bildirim). Ya da "amirin saat beyanı aleyhe sayılmaz" diye belgeye yazmak.
- **Durum:** Açık

### Denediklerim
- 23 cevap / karar satırı (tablo 1).
- 53 devamsızlık denemesi (6 rol × 8 yol, pasif İK × 2, sistem × 3).
- Eskalasyon: tek kademe, ikinci kademe, üst amiri olmayan.
- Zincirde kim ne dedi.
- Kanıtın sonradan gelmesi.
- Açık soruda İK düzeltmesi.
- Devamsızdan sonra amir cevabı.
- Vekil: iki durum.
- Kilitli ayda cevap.
- 16 fonksiyonun son sürümü (`scratch/a7_kod/`).

### Denemediklerim
- **Vardiya uyuşmazlığı sorusu (`vardiya_uyusmazligi`)** ve onaylandığında vardiyanın değişmesi. Kurulumda 13 Ekim PDKS dosyası olmadığı için öneri üretilmedi. Adım 5'teki örnek veri senaryosu bunu ✅ geçmişti; burada tekrar denenmedi.
- **`ariza_kaniti_yok` soru türü.**
- **Gece vardiyasında (gece yarısını geçen) soru ve cevap.**
- **Aynı soruya iki kişinin aynı anda cevap vermesi** (`for update` var, denenmedi).
- **Ekrandan (HTTP) cevap:** endpoint testinde 2 cevap türü denendi; burada SQL ile rol taklidi.
- **Sorunun eskale olduktan sonra asıl amirin cevap vermesi:** ZN1'de kabul edildi. Bunun istenen davranış olup olmadığını belgede bulamadım.

### Şüpheler
- **VU1:** Planı GÜNDÜZ olan kişi 16:00–23:58 okuttu. Öneri üretilemeyince (önceki günün dosyası yok) gün "çıkış yok" sorusuna düştü. 23:58 çıkışı penceresi dışında kaldığı için görülmedi. Amirin "saat doğru" cevabı çıkışı 17:00 yazdı: 45 dk. Gerçekte önceki günün dosyası eksik olduğunda, akşam vardiyasında çalışan biri 7 saat kaybedebilir. T-30 ile aynı aile ("okutma var ama soru yok diyor"); öneri üretilemeyen gerçek veriyle denenmeli.
- **`kart_unuttu` cevabı "saat doğru" ile aynı işi yapıyor** (plan saati). Kart unutmanın geçici kart kaydıyla ilişkilendirilmesi beklenebilir; belgede bulamadım.
- **Kilit özeti:** "3 açık sorulu gün" ve "6 kodsuz gün" sayıları T-39 / T-41'deki askıda günleri içeriyor. Ay sonunda İK'nın bunları "zorla" geçmekten başka yolu yok.

---

## Adım 8 — İtiraz, izin, vardiya planı, plan onayı, arıza (22 Kasım 2026)

**Başlangıç:** `main` @ `79ad042` (31 migration). Yerel veritabanı `supabase db reset` ile kuruldu.

**Betikler:**

| Betik | Ne sınıyor |
|---|---|
| `scratch/a8_akis.sql` | 31 çalışan, 148 çağrı: itiraz, izin, saatlik izin, `v_izin_amir`, plan ve plan onayı, arıza, kilitli ay, geçici kart tarihi |
| `scratch/a8_akis_sonuc.txt` | Ham çıktı. Her çağrının sonucu ve her günün yalnızca değişen aşamaları |
| `scratch/a8_saat_dilimi.sql`, `scratch/a8_saat_dilimi_sonuc.txt` | Planın "geriye dönük" kararı UTC ve İstanbul oturumunda (İstanbul 01:57'de çalıştırıldı) |
| `scratch/a8_kod/*.sql` | Okunan 19 fonksiyonun son sürümü |

**Kurulum:**
- Hepsi tek işlem; sonda `ROLLBACK`.
- Departman "S8 Deneme"; amiri montaj.amiri.
- Günler 15 Eylül (kilitlenecek ay) ve 13–20 Ekim; plan GÜNDÜZ (08:00–17:00).
- Gece işi doğrudan çalıştırıldı. Çağrılar rol taklidiyle yapıldı.

### Sonuç tablosu

| # | Konu | Ne yaptım | Beklenen | Gerçekleşen | |
|---|---|---|---|---|---|
| 1 | İtiraz gir | 6 rol dener (IT1) | Yalnızca kendi departmanının amiri ve İK | montaj.amiri OK. Güvenlik, yönetici, İSG ve admin "yetkiniz yok"; bobinaj.amiri "departmanınızda değil" | ✅ |
| 2 | Boş metinli itiraz | `'   '` | Ret | Kısıt hatası (ham İngilizce, T-16 ailesi) | ✅ |
| 3 | İncelemeye al | amir, yönetici, iki İK | Yalnızca İK | Amir ve yönetici "yetkiniz yok"; ik.uzmani OK; ikinci İK "Açık itiraz bulunamadı" | ✅ (kim/ne zaman yok, T-35) |
| 4 | Reddi İK dışında kimse yapamaz | 8 rol `itiraz_karar(false)` dener: 4 amir, güvenlik, yönetici, İSG, admin | Hepsi ret | 8/8 "yetkiniz yok" | ✅ |
| 5 | Red: doğrudan tablo | amir, yönetici ve İK `update itiraz set durum='red'` | Ret | 3/3 `permission denied` | ✅ |
| 6 | Red: tetikleyici (sistem yolu) | postgres, amiri karar veren yazar / karar vereni boş bırakır | Ret | 2/2 "İtirazı yalnızca İK reddedebilir." | ✅ |
| 7 | Kabul (İK dışı) | amir ve yönetici | Ret | 2/2 "yetkiniz yok" | ✅ |
| 8 | Karar sonrası değişiklik | Reddedilen itirazı kabule çevirme | Ret | "Karar bekleyen itiraz bulunamadı." | ✅ |
| 9 | Kabulde gün düzeliyor mu | IT2: kabul, sonra `kayit_duzelt(…, itiraz no)` | Belgeye göre kabul günü değiştirmez; düzeltme ayrı yapılır ve gün hemen hesaplanır | Kabulden sonra gün aynı (08:30, geç 30). `kayit_duzelt`'ten sonra hemen 08:00, 480 dk, geç 0; düzeltmede itiraz no var | ✅ tasarım gereği (izleme yok: T-52) |
| 10 | Aynı güne ikinci itiraz (ilki açık) | IT3: amir, İK, amir | Ret ya da ilkine bağlanma | 3 ayrı açık itiraz | ❌ T-51 |
| 11 | Aynı güne ikinci itiraz (ilki reddedilmiş) | IT4 | Kabul edilir (yeni bilgi olabilir) | Girildi, kabul edildi | ✅ |
| 12 | Kilitli aydaki güne itiraz | LK2: itiraz, kabul, `kayit_duzelt` | Gün değişmez, fark satırı | Gün aynı; düzeltme `FARK` | ✅ |
| 13 | İzin gir (işlenmemiş gün) | IZ1: gece işinden önce yıllık | Gün izinli | izinli, hesap ✓ | ✅ |
| 14 | İzin gir (işlenmiş gün, "hiç kayıt yok") | IZ2: gece işinden sonra yıllık | Gün izinli olur, açık soru kapanır | Gün `soru_bekliyor`; soru açık kaldı, sonra eskale oldu | ❌ T-46 |
| 15 | İzin gir (işlenmiş, tamam gün) | IZ9 | Çalışılmış gün bozulmamalı | Gün tamam kaldı | ✅ |
| 16 | Çakışan izin | IZ3: yıllık 20–22, rapor 21–23, aynı yıllık tekrar | Ret | Üçü de girildi | ❌ T-47 |
| 17 | Aynı güne yıllık + rapor | IZ8 | Ret; olmazsa rapor öncelikli | İkisi de girildi; gün `izinli` (rapor kayboldu) | ❌ T-47 |
| 18 | İzin iptal (işlenmemiş) | IZ4: iptal, sonra gece işi | Gün okutmaya göre | tamam 08:00–17:00, 480 dk | ✅ |
| 19 | İzin iptal (işlenmiş, izinli) | IZ5 | Belgeye göre ret; önce `kayit_duzelt` | "Bu iznin 1 günü işlenmiş…" ret. `kayit_duzelt durum=eksik` sonrası iptal OK | ✅ tasarım gereği (gün kendiliğinden eski haline dönmüyor) |
| 20 | İzin iptal (işlenmiş, tamam gün) | IZ9 | İptal edilir, gün aynı | OK, gün tamam | ✅ |
| 21 | İptal: kısa neden / amir | IZ5 | Ret | "en az 5 karakter" / "yetkiniz yok" | ✅ |
| 22 | İzin gir: İK dışı / kendi izni | 5 rol; ik.uzmani kendine | Ret | 5/5 "yetkiniz yok"; görevler ayrılığı hatası | ✅ |
| 23 | Kilitli aya izin | LK2: 15 Eylül; 30 Eylül–2 Ekim | Ret (saatlik izin ve plan gibi) | İkisi de girildi | ❌ T-48 |
| 24 | Saatlik izin (işlenmiş gün) | SI1: 08:00–15:00 çalıştı; izin 15:00–17:00 | Erken çıkış 0, izin 120 dk | erken 120 → 0, `saatlik_izin_dk` 120, hemen | ✅ |
| 25 | Saatlik izin (işlenmemiş gün) | SI6: izin 08:00–10:00, okutma 10:00–17:00 | Geç 0, izin 120 | geç 0, izin 120 | ✅ |
| 26 | Çakışan saatlik izin | SI1: 16:00–17:30 | Ret | "Bu saat aralığında başka bir saatlik izin var." | ✅ |
| 27 | Saatlik izin + tam gün izin aynı gün | SI3 | Ret ya da uyarı | İkisi de girildi | ❌ T-47 |
| 28 | Saatlik izin iptal | SI1: İK `delete`; sistem `delete`; iptal fonksiyonu arandı | Bir iptal yolu | İK `permission denied`; tetikleyici "değiştirilemez"; fonksiyon yok | ❌ T-50 |
| 29 | Saatlik izin: kilitli ay / amir / kendine | LK2, SI1, ik.uzmani | Ret | 3/3 ret | ✅ |
| 30 | İzin türü amire görünüyor mu | IZR (rapor): amir `izin`, `v_izin_amir`, `gun_kaydi`, `v_puantaj_canli` okur | Tür görünmez | `izin` 0 satır ✅, `v_izin_amir` `tur=izinli` ✅. Ama `gun_kaydi.durum=raporlu`, `raporlu_gun=1` | ❌ T-12 hâlâ açık |
| 31 | Başka departmanın amiri | bobinaj.amiri `v_izin_amir` | 0 satır | 0 | ✅ |
| 32 | İleri tarihli plan | VP1: amir, 10 Aralık | Onaysız geçerli | `gerekmez` | ✅ |
| 33 | Geriye dönük plan | VP2: amir, 13 Ekim | İK onayı bekler | `bekliyor/geri` | ✅ |
| 34 | Onay bekleyen plan hesapta kullanılmıyor | VP2: gece işi 13 Ekim | Gün açılmaz | Gün kaydı yok | ✅ |
| 35 | Onayda gün hemen oluşuyor | VP2: ik.uzmani onaylar | Gün aynı işlemde açılır | tamam 08:00–17:00, 480 dk | ✅ |
| 36 | Onayda işlenmiş gün hemen düzeliyor | VP3: GÜNDÜZ'le işlenmiş 06:00–14:00 (erken 180) → V1 → onay | Vardiya V1, erken 0 | V1, 420 dk, erken 0; düzeltme `vardiya_id` | ✅ |
| 37 | Bekleyen plan, gece işi yeniden çalışınca | VP3 | Gün eski planla kalır | Değişmedi | ✅ |
| 38 | Ret, işlenmiş gün | VP4 | Gün aynı | Gün aynı (GÜNDÜZ). Plan satırı `V1/reddedildi`; eski GÜNDÜZ planı silinmiş | ⚠️ T-49 |
| 39 | Ret, işlenmemiş gün | VP5: ileri girilmiş GÜNDÜZ; dosyadan önce amir V2 → İK ret → dosya gelir | Eski plan geçerli kalır, gün işlenir | Gün hiç açılmadı (08:00–17:00 çalıştı); eski plan kayıp | ❌ T-49 |
| 40 | Planı giren onaylayamaz | VP6: ik.uzmani girer, onay/ret dener | Ret | 2/2 "kendi girdiğiniz planı onaylayamazsınız" | ✅ |
| 41 | Kimse kendi planını onaylayamaz | VP7: ik.muduru'nun kaydına ik.uzmani plan girer, ik.muduru onaylar | Ret | "kimse kendi kaydında işlem yapamaz (vardiya_plani.onay)" | ✅ |
| 42 | Kendine plan / başka departman / yetkisiz rol | VP8, VP12 | Ret | Görevler ayrılığı / "departmanınızda değil" / 4× "yetkiniz yok" | ✅ |
| 43 | Onay: İK dışı roller | VP2: 5 rol | Ret | 5/5 "yetkiniz yok" | ✅ |
| 44 | Onaylanmış planı yeniden karara bağlama | VP2 | Ret | "Onay bekleyen plan bulunamadı." | ✅ |
| 45 | Kilitli aya plan | LK2: amir RPC ile 15 Eylül | Ret | "kilitli bir döneme ait" | ✅ |
| 46 | Bekleyen plan, ay zorla kilitlenir, sonra onay | LK1 | Kilit mesajı söyler; onay fark satırı olur | "Zorla geçilenler: 1 onay bekleyen geriye dönük plan." Onay → düzeltme `vardiya_id/FARK`, gün değişmedi | ✅ (fark satırında dakika: Adım 12) |
| 47 | Geriye dönük kararının saat dilimi | `a8_saat_dilimi.sql`: İstanbul 01:57'de, İstanbul'un dünü için plan | Onay bekler | UTC oturumu `gerekmez`; İstanbul oturumu `bekliyor` | ❌ T-45 |
| 48 | Arıza gir: İK dışı | 5 rol | Ret | 5/5 "yetkiniz yok" | ✅ |
| 49 | Arıza: bitiş başlangıçtan önce | | Ret | Kısıt hatası (ham İngilizce) | ✅ |
| 50 | Arıza: ileri tarihli, bitişsiz | PDKS-2, 2027-01-01, bitiş yok | Ret ya da uyarı | Kaydedildi | ❌ T-55 |
| 51 | Arızanın gece işine etkisi (kanıt var) | AR1: PDKS-1 arızalı 07:30–10:00, kapı 07:50 | Giriş 08:00; düzeltme arızaya bağlı | 08:00, 480 dk, düzeltme `ariza1` | ✅ |
| 52 | Arızanın gece işine etkisi (kanıt yok) | AR2 | Amire arızadan söz eden soru (`ariza_kaniti_yok`) | Sıradan `giris_yok` sorusu, arıza bağı yok | ❌ T-53 |
| 53 | Otomatik arıza şüphesi | AS1–AS3: PDKS-2 sessiz, 3 kişide kapı var | Şüphe + uyarı | Arıza `suphe` 07:50–07:51; `ariza_suphesi` uyarısı; 3 gün düzeltildi | ✅ |
| 54 | Şüphe kararı | 5 rol, sonra İK ret | Yalnızca İK | 5/5 ret; İK OK. Kararı veren `giren_id`'ye yazıldı (T-35) | ✅ |
| 55 | Ret sonrası | Gece işi 17 Ekim yeniden | Yeni şüphe açılmaz | Açılmadı. Ama 3 düzeltme hâlâ reddedilen arızaya bağlı | ⚠️ T-55 |
| 56 | Uyarı görüldü | amir; İK; İK ikinci kez | Yalnızca İK, bir kez | Amir ret; İK OK; ikinci "zaten görülmüş" | ✅ |
| 57 | İşlenmiş güne sonradan arıza | AS1 | Gün değişmez | Değişmedi | ✅ |
| 58 | Geçici kart zimmeti ileri tarihli (RPC) | `gecici_kart_ver` parametreleri; `p_verilis_zamani` ile çağrı; doğrudan INSERT | Girilemez | Fonksiyonda tarih parametresi yok, zaman `clock_timestamp()`; tarih parametresiyle çağrı "function does not exist"; güvenlik INSERT `permission denied` | ✅ (sistem yolu: Şüpheler) |

### T-45 · Geriye dönük plan kararı UTC tarihiyle veriliyor; İstanbul 00:00–03:00 arası dünün planı İK onayı olmadan geçiyor
- **Adım:** 8 · **Önem:** Yüksek
- **Yer:** `pdks.vardiya_plani_gir` (son sürüm: `20261203010000_plan_onayi.sql`): `v_geri boolean := p_tarih < current_date`. Fonksiyonda saat dilimi ayarı yok (`proconfig = search_path=pdks`); veritabanının varsayılanı `UTC`. `authenticator` ve `authenticated` rollerinde `timezone` ayarı yok.
- **Ne oldu:** İstanbul saati 22.11 01:57 iken UTC tarihi hâlâ 21.11. Amir, İstanbul'un dünkü günü olan 21.11 için plan girdi. UTC oturumunda `21.11 < 21.11` yanlış çıktı; plan `geriye_donuk=false`, `ik_onay_durumu=gerekmez` oldu. Aynı çağrı İstanbul oturumunda `bekliyor` oldu.
- **Ne olmalıydı:** "Geriye dönük" kararı İstanbul tarihine göre verilmeli. Dünün planı her saatte İK onayı beklemeli.
- **Kanıt:** `scratch/a8_saat_dilimi_sonuc.txt`
  ```
  saat: UTC 2026-11-21 22:57 · İstanbul 2026-11-22 01:57
  veritabanı varsayılan saat dilimi: UTC
  UTC oturum: current_date=2026-11-21 · plan tarihi (İstanbul dünü)=2026-11-21
  UTC oturum sonucu: geriye_donuk=false · ik_onay_durumu=gerekmez
  İstanbul oturum: current_date=2026-11-22
  İstanbul oturum sonucu: geriye_donuk=true · ik_onay_durumu=bekliyor
  ```
- **Sade dille:** Veritabanının saati Londra'ya göre (UTC), fabrika İstanbul'da, arada 3 saat var. Gece 00:00 ile 03:00 arasında veritabanı hâlâ "dün"ün içinde olduğunu sanıyor. Bu saatlerde amir dünkü vardiyayı değiştirirse sistem bunu "ileri tarihli" sayıyor ve İK onayı istemiyor. Gece vardiyası olan bir fabrikada bu saatlerde ekran başında amir bulunur. Gece işi de bu saatlerde çalışırsa değişiklik o günün hesabına onaysız girer. PR #34'teki onay kuralı her gece 3 saat boyunca delinmiş oluyor. Ekrandaki istekler PostgREST üzerinden UTC oturumla geldiği için bu durum canlıda da olur.
- **Tarih taraması** (`scratch/a8_tarih_listesi.txt`): 13 fonksiyonda 24 satır, ayrıca tablo varsayılanları ve görünümler tarandı. Hiçbir fonksiyonda `TimeZone` ayarı yok; `now()::date` hiç kullanılmıyor.

  | Yer | İfade | Ne yapıyor | Saat dilimine bağlı mı |
  |---|---|---|---|
  | `vardiya_plani_gir` | `p_tarih < current_date` | Planın geriye dönük olup olmadığı | **Evet** (bu bulgu) |
  | `fazla_mesai_plani_kontrol` | `old.is_gunu < current_date` | "Geçmiş günün onaylı fazla mesai planı iptal edilemez" | **Evet** |
  | `gece_isi_calistir` | `p_gun > greatest(current_date - 1, …)` | Hangi günün işlenebileceği | **Evet** |
  | `v_gece_isi_durumu` (görünüm) | `CURRENT_DATE - 1` | "Dün gece işi çalıştı mı" göstergesi | **Evet** |
  | `v_isg_durum` (görünüm) | `gecerlilik_bitis < CURRENT_DATE` (+ `isg_uyari_gun`) | İSG belgesi doldu / doluyor | **Evet** |
  | `kart.verilis_tarihi` (varsayılan) | `DEFAULT CURRENT_DATE` | Kartın veriliş tarihi | **Evet** |
  | `isten_cikis_gir` | `(now() at time zone 'Europe/Istanbul')::date` | Bugünün tarihi | Hayır, doğru yazılmış örnek |
  | `kart_paylasim_kontrol` | `(okutma_zamani at time zone 'Europe/Istanbul')::date` | Okutmanın günü | Hayır, doğru |
  | `pdks_verisi_tam_mi` | `(p_bas at time zone 'Europe/Istanbul')::date` | Pencerenin kapsadığı günler | Hayır, doğru |
  | `ay_kilitle`, `duzeltme_hazirla`, `gece_araligi`, `gece_isi_tetikle`, `gun_kodlari_hesapla`, `hedef_donem`, `puantaj_yaz` | `date_trunc('month', <tarih>)::date`, `generate_series(...)::date` vb. | Bir tarihten ay başı / ay sonu / gün listesi türetme | Hayır (tarihten tarihe) |

  Bu tablo yalnızca listedir. İlk altı satırdan ikisi gece penceresinde denendi: `vardiya_plani_gir` (bu bulgu) ve `fazla_mesai_plani_kontrol`. İkincisi Adım 9'da kanıtlandı: `fazla_mesai_onayi_geri_al` RPC'si UTC oturumunda dünkü onaylı planı iptal etti, İstanbul oturumunda reddetti (`scratch/a9_saat_dilimi_geri_al_sonuc.txt`, T-59). Kalan dördü denenmedi.
- **Öneri:** `v_geri := p_tarih < (now() at time zone 'Europe/Istanbul')::date`. Yukarıdaki tablonun ilk altı satırı da aynı kalıpla yazılmalı (ya da veritabanı/rol düzeyinde `timezone = 'Europe/Istanbul'`). Kalıcı test UTC oturumuyla, sabit bir saatte yazılmalı (T-04).
- **Durum:** ✅ Düzeltildi — PR #46 (kod), PR #47 (kilitli ay testi / canlı kontrol listesi). (PR #46 migration: `20261205010000_istanbul_tarihi.sql`, test: `istanbul_tarihi_testi.sql`). `pdks.bugun()` eklendi; tablodaki ilk altı satırın hepsi (`vardiya_plani_gir`, `fazla_mesai_plani_kontrol`, `gece_isi_calistir`, `v_gece_isi_durumu`, `v_isg_durum`, `kart.verilis_tarihi`) buna çevrildi. Aşağıdaki Adım 10 notu da bununla kapandı.
- **Adım 10 notu (`v_isg_durum`, kod okunarak; gece penceresinde çalıştırılmadı):** Görünüm `gecerlilik_bitis < CURRENT_DATE` ve `< CURRENT_DATE + isg_uyari_gun` ile durum veriyor. Yerelde veritabanının varsayılan saat dilimi `UTC`; `authenticated` / `authenticator` rollerinde saat dilimi ayarı yok, yani ekrandan (PostgREST) gelen oturum da UTC olur (çıkarım; HTTP ile denenmedi). İstanbul 00:00–03:00 arasında `CURRENT_DATE` dünü gösterir: dün biten belge 3 saat boyunca `doluyor` (ya da `gecerli`) görünür, `doluyor` penceresi de bir gün kayar. Etkisi yalnızca ekrandaki İSG listesi: uyarıları üreten `isg_kontrol(p_gun)` tarihi parametre olarak alıyor, saat diliminden etkilenmiyor. Önem: Düşük (T-45'in kalıbıyla birlikte düzeltilebilir: `(now() at time zone 'Europe/Istanbul')::date`).

### T-46 · İşlenmiş güne girilen izin günü değiştirmiyor; amire giden "hiç kayıt yok" sorusu açık kalıyor
- **Adım:** 8 · **Önem:** Yüksek
- **Yer:** `pdks.izin_gir`: yalnızca `insert into pdks.izin`, gün kaydına dokunmuyor. İzin türü gün kaydına yalnızca gece işinde yazılıyor (`gece_isi_gun_kayitlari`, `izin_turu`). Saatlik izin ise günü hemen yeniden hesaplıyor.
- **Ne oldu:** IZ2'nin 14 Ekim'de hiç okutması yok. Gece işi günü `soru_bekliyor` yaptı, amire `hic_kayit_yok` sorusu açtı. Sonra İK aynı güne yıllık izin girdi. Gün `soru_bekliyor` kaldı. Soru açık kaldı, sonraki gece işinde üst amire eskale oldu. Tam gün izin girilen SI3'te de aynısı oldu.
- **Ne olmalıydı:** İzin, işlenmiş ama çalışılmamış güne girilince gün `izinli` / `raporlu` olmalı (`duzeltme_uygula` ile, `p_izin_id` dolu). O günün açık sorusu kapanmalı. Saatlik izin bunu zaten yapıyor.
- **Kanıt:** `scratch/a8_akis_sonuc.txt`
  ```
  85|IZ2|ik.uzmani|işlenmiş (eksik) güne izin 14 Ekim|OK 17
  IZ2|1 gece işi|soru_bekliyor · —–— · hesap ✗|hic_kayit_yok:acik|0 düzeltme
  IZ2|Z son|soru_bekliyor · —–— · hesap ✗|hic_kayit_yok:eskale|0 düzeltme
  ```
- **Ek kanıt: rapor varken amir "gelmedi", İK devamsız** (`scratch/a8_soru_izin.sql`, `scratch/a8_soru_izin_sonuc.txt`). Hiç okutması olmayan güne gece işinden sonra rapor girildi. Amir "gelmedi" dedi. İK devamsız kararı verdi; hiçbir denetim durdurmadı:
  ```
  1 gece işi      | gün=soru_bekliyor | soru=acik                       | izin=0 | düzeltme=-
  2 rapor girildi | gün=soru_bekliyor | soru=acik                       | izin=1 | düzeltme=-
  3 amir cevabı   | gün=soru_bekliyor | soru=ik_karari_bekliyor:gelmedi | izin=1 | düzeltme=-
  4 İK kararı     | gün=devamsiz      | soru=kapandi:gelmedi            | izin=1 | düzeltme=durum=devamsiz/aleyhe
  ```
  - `pdks.soru_ik_karari(p_soru_id, p_devamsiz, p_gerekce, p_giris, p_cikis)` iki sonuçtan birini verir: `p_devamsiz = true` → `durum = devamsiz`; değilse giriş/çıkış saati zorunlu (`saat_yaz`). **"izinli" ya da "raporlu" seçeneği yok.** İK soruyu doğru sonuçla kapatamıyor.
  - Fonksiyonda **o gün için geçerli izin var mı denetimi yok.** Rapor kaydı dururken gün "devamsız" ve "çalışan aleyhine" olarak işaretlendi.
  - **T-40 ile bağlantı:** İK soruyu kapatmadan `kayit_duzelt` ile günü "raporlu" yaparsa soru açık kalır (T-40: İK düzeltmesi açık soruyu kapatmıyor). Sonra amir cevap verirse bu cevap İK'nın düzeltmesini bozabilir. Yani İK'nın önündeki üç yolun hiçbiri doğru sonuç vermiyor: devamsız (yanlış), saat girmek (yanlış), elle düzeltmek (soru açık kalır, bozulabilir).
- **Sade dille:** Hastalanan biri raporunu genelde 2-3 gün sonra getirir. O zamana kadar gece işi o günleri çoktan işlemiş, amire "bu kişi hiç gelmedi, ne oldu?" diye sormuştur. İK raporu girdiğinde sistem günü "raporlu" yapmıyor, amire giden soruyu da kapatmıyor. Amir "gelmedi" derse İK'nın önüne devamsızlık kararı gelir. İK gün gün elle `kayit_duzelt` yapmayı unutursa raporlu bir çalışan devamsız görünür. Bu, çalışan aleyhine yanlış bir sonuçtur.
- **Öneri:** `izin_gir` sonunda iznin işlenmiş günleri için (`durum not in ('tamam')` ya da çalışma yoksa) `duzeltme_uygula(…, 'durum', 'izinli'/'raporlu', …, p_izin_id => v_id)` ve açık soruları kapatma. Kilitli aydaki günler fark satırı olur. İzin iptali de bu düzeltmeyi geri almalı (bugünkü "önce kayit_duzelt" kuralının yerine). `soru_ik_karari`: o gün geçerli izin varsa devamsız kararını reddetmeli ve "izinli/raporlu" ile kapatma seçeneği sunmalı. T-40'ın düzeltmesiyle (İK düzeltmesi açık soruyu kapatır) birlikte ele alınmalı.
- **Durum:** Açık

### T-47 · Çakışan izinler reddedilmiyor; aynı güne yıllık izin ve rapor girilince gün "izinli" oluyor, rapor kayboluyor
- **Adım:** 8 · **Önem:** Yüksek
- **Yer:** `pdks.izin_gir` ve `pdks.izin` tablosu. Çakışma denetimi yok: dışlama (exclusion) kısıtı da tetikleyici de yok. Gece işi çakışmada `order by i.id limit 1` ile ilk girilen izni seçiyor. Saatlik izin ile tam gün izin arasında da denetim yok.
- **Ne oldu:**
  - IZ3'e yıllık 20–22 Ekim, rapor 21–23 Ekim ve başka bir İK'dan aynı yıllık izin (20–22) girildi. Üçü de kabul edildi.
  - IZ8'e 15 Ekim için önce yıllık, sonra rapor girildi. Gece işi günü `izinli` yaptı.
  - SI3'e aynı gün hem saatlik hem tam gün izin girildi.
- **Ne olmalıydı:** `docs/ekran_fonksiyonlari.md` saatlik izin için "Çakışan izin … reddedilir" diyor. Tam gün izin için de aynısı beklenir: aynı kişi için iptal edilmemiş iki izin aynı günü kapsayamamalı. Yanlış izin önce iptal edilmeli.
- **Kanıt:**
  ```
  9|IZ3|ik.uzmani|yıllık 20–22 Ekim|OK 11
  10|IZ3|ik.uzmani|çakışan rapor 21–23 Ekim|OK 12
  11|IZ3|ik.muduru|aynı yıllık 20–22 Ekim tekrar|OK 13
  IZ8|8|yillik|2026-10-15–2026-10-15|geçerli
  IZ8|9|rapor|2026-10-15–2026-10-15|geçerli
  IZ8|1 gece işi|izinli · —–— · hesap ✓
  106|IZ8|montaj.amiri|iki izinli gün: v_izin_amir satır|OK 8 tur=izinli; 9 tur=izinli
  ```
- **Sade dille:** İK önce yanlışlıkla yıllık izin girip sonra doğru olan raporu girerse sistem ikisini de kabul ediyor. Günü de ilk girilene, yani yıllık izne göre yazıyor. Çalışan raporluyken yıllık izin hakkından gün düşer ve puantaj ERP'ye yanlış kodla gider. İki İK uzmanı aynı izni ayrı ayrı girerse de bunu fark eden bir şey yok.
- **Öneri:** `izin` tablosuna `exclude using gist (calisan_id with =, daterange(baslangic, bitis, '[]') with &&) where (iptal_zamani is null)` (btree_gist gerekir) ya da `izin_gir`'de denetim ve Türkçe hata. Saatlik izin, tam gün izinli güne girilmemeli. Bu eklenmezse gece işinde rapor öncelikli seçilmeli.
- **Durum:** ✅ Düzeltildi (feature/T47-cakisan-izin). Migration: `20261218010000_cakisan_izin.sql`, test: `cakisan_izin_testi.sql`. `izin_gir` kesişen geçerli izni, `saatlik_izin_gir` tam gün izinli günü Türkçe mesajla reddeder; iki fonksiyon da çalışan satırını kilitler (iki İK aynı anda giremez). Ters yön (saatlik izinden sonra aynı güne tam gün izin) bilerek açık: viziteden sonra rapor alınabilir, saatlik izin silinemez.

### T-48 · Kilitli aya izin girilebiliyor
- **Adım:** 8 · **Önem:** Orta
- **Yer:** `pdks.izin_gir`: `donem_kilitli_mi` denetimi yok. `saatlik_izin_kontrol` ve `vardiya_plani_gir` ise kilitli ayı reddediyor.
- **Ne oldu:** Eylül zorla kilitlendikten sonra LK2'ye 15 Eylül için ve 30 Eylül–2 Ekim için yıllık izin girildi; ikisi de OK. LK2'nin 15 Eylül günü `tamam` kaldı. Aynı gün için saatlik izin "kilitli bir döneme ait" hatasıyla reddedildi.
- **Ne olmalıydı:** Kilitli ayın herhangi bir gününü kapsayan izin reddedilmeli. Gerçekten gerekiyorsa (sonradan gelen rapor) düzeltme fark satırı olarak girilmeli (T-46 ile birlikte).
- **Kanıt:**
  ```
  41|LK2|ik.uzmani|kilitli aya izin|OK 15
  42|LK2|ik.uzmani|kilitli ayı da kapsayan izin 30 Eylül–2 Ekim|OK 16
  43|LK2|ik.uzmani|kilitli aya saatlik izin|HATA P0001: 2026-09-15 günü kilitli bir döneme ait; saatlik izin girilemez.
  LK2|kilitli ay denemeleri|tamam · 08:00–17:00 · çalışma 480 …
  ```
- **Sade dille:** Eylül kapanmış, puantajı ERP'ye gitmiş. İK yine de Eylül'e izin girebiliyor. İzin listesinde ve PDF dökümde kişi "15 Eylül'de izinli" görünüyor, puantajda ise "çalıştı". Hangisinin doğru olduğu belli değil. Saatlik izinde ve planda bu kapı kapalı, tam gün izinde açık.
- **Öneri:** `izin_gir`'e `generate_series(baslangic, bitis)` üzerinde `donem_kilitli_mi` denetimi ve Türkçe mesaj. Ay sınırını aşan izinde de kilitli günler reddedilmeli.
- **Durum:** Açık

### T-49 · Geriye dönük plan geçerli planın üstüne yazılıyor; İK reddedince eski plan geri gelmiyor, gün hiç işlenmiyor
- **Adım:** 8 · **Önem:** Orta
- **Yer:** `pdks.vardiya_plani_gir`: `on conflict (calisan_id, tarih) do update` eski satırın vardiyasını ve onay durumunu eziyor. `pdks.vardiya_plani_onayla` ret dalında yalnızca `ik_onay_durumu = 'reddedildi'` yapıp çıkıyor. Gece işi `reddedildi` planı kullanmıyor.
- **Ne oldu:**
  - **VP5:** 19 Ekim için önceden GÜNDÜZ planı vardı (`gerekmez`). PDKS dosyası gelmeden amir planı V2 yaptı (`bekliyor`). İK reddetti. Plan satırı `V2/reddedildi` kaldı; GÜNDÜZ planı artık hiçbir yerde yok. Çalışan 08:00–17:00 okuttu. 19 ve 20 Ekim dosyaları gelip gece işi iki kez çalıştı, gün kaydı yine açılmadı.
  - **VP4:** Gün GÜNDÜZ'le işlenmişti. Amir V1 girdi, İK reddetti. Gün doğru biçimde GÜNDÜZ kaldı, ama plan satırı `V1/reddedildi` oldu; artık gerçekte uygulanan planı göstermiyor. Amir aynı V1'i yeniden girince yine `bekliyor` oldu.
- **Ne olmalıydı:** PR #34'ün kuralı "ret hiçbir şey değiştirmez". Ret, geçerli plana dönmeli. Ya eski plan bir geçmiş tablosunda tutulup ret sonrası geri yüklenmeli, ya da bekleyen değişiklik ayrı bir satırda (öneri satırı) tutulup onaylanınca asıl plana yazılmalı.
- **Kanıt:**
  ```
  VP5|0 gece işinden önce|GÜN KAYDI YOK|…|GUNDUZ/gerekmez/giren ik.uzmani
  VP5|2 plan değişti|GÜN KAYDI YOK|…|V2/bekliyor/geri/giren montaj.amiri
  VP5|3 ret|GÜN KAYDI YOK|…|V2/reddedildi/geri/giren montaj.amiri
  (19 ve 20 Ekim dosyaları geldi, gece işi 2 kez: VP5 için satır değişmedi)
  VP4|4 ret|tamam · 06:00–14:00 · … · vardiya GUNDUZ|…|V1/reddedildi/geri/giren montaj.amiri
  ```
- **Sade dille:** Amir yanlışlıkla bir vardiya değişikliği girse, İK de "hayır" dese bile çalışanın asıl planı silinmiş oluyor. O gün hesaplanmıyor. Ay sonunda kilit "reddedilmiş plan var, doğru planı girin" diyerek durur. Doğru plan da geriye dönük olduğu için yeniden İK onayı ister. Yani İK'nın "hayır"ı fazladan iki iş doğuruyor, çalışan da o güne kadar puantajda görünmüyor. Plan geçmişi tutulmadığı için sonradan "bu gün aslında hangi vardiyaydı?" sorusunun cevabı da kayboluyor.
- **Öneri:** Bekleyen değişikliği ayrı tutmak (ör. `vardiya_plani_talebi`) ya da `vardiya_plani`'na `onceki_vardiya_id` ekleyip ret dalında geri yüklemek. Kalıcı test: ileri plan → geriye dönük değişiklik → ret → gece işi → gün eski planla işlenmeli.
- **Durum:** Açık

### T-50 · Yanlış girilen saatlik izin geri alınamıyor
- **Adım:** 8 · **Önem:** Orta
- **Yer:** `pdks.saatlik_izin`: `saatlik_izin_degistirilemez` (UPDATE/DELETE yasak), `authenticated`'da yalnızca SELECT, `saatlik_izin_iptal` gibi bir fonksiyon yok. `gun_hesabi` saatlik izni her hesapta yeniden okuduğu için `kayit_duzelt` de etkisini kaldıramıyor.
- **Ne oldu:** SI1'e 15:00–17:00 izin girildi; erken çıkış 120 → 0. İK silmeyi denedi: `permission denied`. Sistem rolü silmeyi denedi: "değiştirilemez ve silinemez". `saatlik` + `iptal|sil|geri` adlı fonksiyon yok.
- **Ne olmalıydı:** Tam gün izindeki gibi iz bırakan bir iptal (`iptal_zamani`, `iptal_eden_id`, `iptal_nedeni`) ve iptal sonrası günün yeniden hesaplanması.
- **Kanıt:**
  ```
  SI1|2 saatlik izin|tamam · 08:00–15:00 · çalışma 390 · erken 0 · s.izin 120
  96|SI1|ik.uzmani|saatlik izni iptal: doğrudan DELETE|HATA 42501: permission denied for table saatlik_izin
  97|SI1|postgres|sistem: saatlik izni DELETE|HATA 42501: saatlik_izin tablosu değiştirilemez ve silinemez (yalnızca ekleme yapılır).
  98|SI1|postgres|iptal fonksiyonu var mı|OK yok
  ```
- **Sade dille:** İK yanlış kişiye ya da yanlış saate saatlik izin girerse bunu düzeltmenin yolu yok. Kayıt sonsuza kadar kalıyor ve her hesapta o saatler "izinli" sayılıyor. Erken çıkan biri yanlışlıkla izinli görünebilir; tersine, izinli sayılmaması gereken saat de puantaja izin olarak gider.
- **Öneri:** `izin_iptal`'in aynısı: `saatlik_izin`'e iptal sütunları, `saatlik_izin_iptal(p_id, p_neden)` (yalnızca İK, kendi kaydı değil, kilitli ay değil), hesapta `iptal_zamani is null` filtresi ve `gun_hesabini_yenile`.
- **Durum:** Açık

### T-51 · Aynı güne birden çok açık itiraz girilebiliyor
- **Adım:** 8 · **Önem:** Düşük
- **Yer:** `pdks.itiraz_gir` ve `pdks.itiraz`. Aynı gün için açık itiraz denetimi ya da kısmi tekil index yok.
- **Ne oldu:** IT3'ün 14 Ekim gününe amir, İK ve yine amir art arda itiraz girdi: üç ayrı `acik` itiraz.
- **Ne olmalıydı:** Bir günde açık (`acik` / `inceleniyor`) en fazla bir itiraz olmalı; yeni bilgi mevcut itiraza eklenmeli. Reddedildikten sonra yeni itiraz (IT4) kabul edilebilir.
- **Kanıt:** `IT3|5|acik|-`, `IT3|6|acik|-`, `IT3|7|acik|-`
- **Sade dille:** Çalışan aynı şikâyeti hem amirine hem İK'ya söylerse iki ayrı itiraz kaydı oluşuyor. İK ikisini ayrı ayrı karara bağlamak zorunda; birini kabul edip diğerini reddederse kayıt çelişkili olur. Ay kilidinde de "3 açık itiraz" diye sayılır.
- **Öneri:** `create unique index … on pdks.itiraz (gun_kaydi_id) where durum in ('acik','inceleniyor')` ve `itiraz_gir`'de Türkçe mesaj ("Bu güne ait açık itiraz var: no …").
- **Durum:** Açık

### T-52 · Kabul edilip düzeltmesi yapılmayan itiraz hiçbir yerde görünmüyor
- **Adım:** 8 · **Önem:** Görüş
- **Yer:** `pdks.itiraz_karar` (kabul yalnızca durum yazar; belgedeki tasarım: `itiraz_karar` sonra `kayit_duzelt(…, p_itiraz_id)`).
- **Ne oldu:** IT4'ün ikinci itirazı kabul edildi, ardından düzeltme yapılmadı. Gün `tamam 08:30, geç 30` kaldı. Kilit, uyarı ya da görünüm bunu yakalamıyor; ay kilidi yalnızca açık itirazları sayıyor.
- **Ne olmalıydı:** Kabul edilmiş ama `duzeltme.itiraz_id` ile hiçbir düzeltmeye bağlanmamış itirazlar İK'ya listelenmeli, kilitte uyarı olmalı. Ya da kabul ve düzeltme tek adımda yapılmalı.
- **Kanıt:** `84|IT4|ik.muduru|2. itirazı kabul|OK` · `IT4|9|kabul|ik.muduru` · IT4'ün günü `tamam 08:30–17:00 · geç 30 · 0 düzeltme`.
- **Sade dille:** İK "haklısın" deyip itirazı kabul ediyor ama ikinci adımı (saati düzeltmeyi) unutuyor. Çalışan haklı çıktığı halde puantajında geç kalma duruyor. Bunu hatırlatan hiçbir şey yok.
- **Öneri:** Kilit özetine "düzeltmesiz kabul edilmiş itiraz" sayısı; ekranda kabulden sonra doğrudan düzeltme formunu açmak.
- **Durum:** Açık

### T-53 · `ariza_kaniti_yok` sorusu hiç üretilmiyor; arızalı okuyucuda amire sıradan "giriş yok" soruluyor
- **Adım:** 8 · **Önem:** Düşük
- **Yer:** `pdks.amir_sorusu`: `soru_turu` kısıtında `ariza_kaniti_yok` var, tabloda `ariza_id` sütunu var, `soru_cevapla` bu türü işliyor. Ama soru açan tek fonksiyonda (`gece_isi_sorular`) bu tür hiç yazılmıyor ve `ariza_id` doldurulmuyor.
- **Ne oldu:** PDKS-1 için 07:30–10:00 arızası önceden girildi. AR2'nin kapı kaydı yok, 17:00 çıkışı var. Gece işi `giris_yok` sorusu açtı; soruda arıza bağı yok.
- **Ne olmalıydı:** Arıza aralığında okutması eksik ve kanıtı olmayan kişi için `ariza_kaniti_yok` sorusu, `ariza_id` dolu ve açıklamada "okuyucu arızalıydı".
- **Kanıt:** `AR2|1 gece işi|soru_bekliyor · —–17:00 …|giris_yok:acik|0 düzeltme` (soru satırında `ariza=` yok). `insert into pdks.amir_sorusu` geçen tek fonksiyon `gece_isi_sorular`; içinde `ariza` sözcüğü yok.
- **Sade dille:** Okuyucu bozukken kartını okutamayan biri için amire "bu kişi sabah kart basmamış" diye soruluyor; okuyucunun bozuk olduğu söylenmiyor. Amir bunu bilse "geldi" demesi kolaylaşır; bilmezse "bilmiyorum" deyip işi İK'ya atabilir. Tasarımda düşünülmüş ama bağlanmamış bir yol.
- **Öneri:** `gece_isi_sorular`'da `giris_yok`/`cikis_yok` açılırken o kişinin PDKS okuyucusunda onaylı arıza varsa türü `ariza_kaniti_yok` yapıp `ariza_id` yazmak. Ya da kullanılmıyorsa türü ve sütunu kaldırmak.
- **Durum:** Açık

### T-54 · İzinli günde okutma varsa gün sessizce "izinli" oluyor
- **Adım:** 8 · **Önem:** Görüş
- **Yer:** `pdks.gece_isi_gun_kayitlari` (izin, okutmadan önce gelir).
- **Ne oldu:** IZ7'ye 15 Ekim mazeret izni girildi; aynı gün 08:00–17:00 okuttu. Gün `izinli`, giriş ve çıkış saatleri yazılı, çalışma dakikası yok. Soru açılmadı, İK'ya uyarı çıkmadı (IZ7'nin uyarıları yalnızca İSG).
- **Ne olmalıydı:** "İzinli görünüyor ama çalışmış" durumu İK'ya uyarı olmalı (izin yanlış kişiye ya da yanlış güne girilmiş olabilir; ya da çalışan izni bozup gelmiş).
- **Kanıt:** `IZ7|1 gece işi|izinli · 08:00–17:00 · çalışma ? · … · hesap ✓|-|0 düzeltme` · `IZ7 uyarı: isg_belgesi_yok …`
- **Sade dille:** İzinli birinin tam gün çalıştığını sistem görüyor ama kimseye söylemiyor. Çalışılan 8 saat puantaja girmiyor; çalışan bunu ancak bordroyu görünce fark eder.
- **Öneri:** Gece işinde `izin_turu is not null and (giris or cikis)` için `uyari_yaz('izinli_gunde_okutma', …)`.
- **Durum:** Açık

### T-55 · Arıza kayıtlarında süre ve karar tutarlılığı denetlenmiyor
- **Adım:** 8 · **Önem:** Düşük
- **Yer:** `pdks.ariza_gir` (tarih denetimi yok), `pdks.gece_isi_kanitla_duzelt` (`coalesce(a.bitis, 'infinity')`, `durum <> 'reddedildi'`), `pdks.ariza_karar`.
- **Ne oldu:**
  - PDKS-2 için 2027-01-01 başlangıçlı, bitişsiz arıza kabul edildi.
  - AS1–AS3'ün düzeltmeleri otomatik şüpheye (arıza 4) bağlandı. İK şüpheyi "arıza değil" diye reddetti; üç düzeltme hâlâ arıza 4'e bağlı.
- **Ne olmalıydı:** İleri tarihli ya da bitişsiz arıza en azından uyarı vermeli (bitişsiz arıza, o okuyucudaki bundan sonraki her kanıt düzeltmesini "arıza" diye etiketler). Reddedilen şüpheye bağlı düzeltmeler raporda ayrıca görünmeli.
- **Kanıt:** `28|AR|ik.uzmani|gelecek tarihli, bitişsiz arıza (kaydedilir mi)|OK 3` · `136|AS|postgres|ret sonrası arıza|OK 4 reddedildi giren=ik.muduru` · `AS1|… 1 düzeltme (giris_zamani=2026-10-17 08:00/gece_isi/…/ariza4)`
- **Sade dille:** İK yanlışlıkla bitiş saati girmeden ya da yanlış yıl yazarak arıza kaydederse sistem bunu kabul ediyor; okuyucu aylarca "arızalı" kabul edilir. Sistemin kendi açtığı şüpheyi İK "arıza değil" dese de o günün düzeltmeleri "arıza yüzünden" diye işaretli kalıyor. Gün sonucu değişmiyor (düzeltme kanıta dayanıyor), ama kayıt yanıltıcı.
- **Öneri:** `ariza_gir`: başlangıç gelecekte olamaz, bitişsiz arıza en fazla N gün açık kalır ya da uyarı. Ret sonrası bağlı düzeltmeler için ek not ya da görünümde `ariza.durum` gösterimi.
- **Durum:** Açık

### Bulgular önem sırasıyla
1. **T-45** · Yüksek · Gece 00:00–03:00 arası dünün planı İK onayı olmadan geçiyor (UTC tarih).
2. **T-46** · Yüksek · İşlenmiş güne girilen izin günü değiştirmiyor, amir sorusu açık kalıyor.
3. **T-47** · Yüksek · Çakışan izin reddedilmiyor; yıllık + rapor → gün izinli (rapor kayboluyor).
4. **T-12** · Yüksek (Adım 3'ten, yeniden doğrulandı) · Amir `gun_kaydi.durum=raporlu` ve `raporlu_gun=1` görüyor; `v_izin_amir` doğru gizliyor.
5. **T-48** · Orta · Kilitli aya izin girilebiliyor.
6. **T-49** · Orta · Plan değişikliği eski planı eziyor; ret eski planı geri getirmiyor, gün işlenmiyor.
7. **T-50** · Orta · Saatlik izin geri alınamıyor.
8. **T-51** · Düşük · Aynı güne birden çok açık itiraz.
9. **T-53** · Düşük · `ariza_kaniti_yok` sorusu hiç üretilmiyor.
10. **T-55** · Düşük · Bitişsiz / ileri tarihli arıza; reddedilen şüpheye bağlı düzeltmeler.
11. **T-52** · Görüş · Düzeltmesiz kabul edilmiş itiraz izlenmiyor.
12. **T-54** · Görüş · İzinli günde okutma uyarısız.

Yeniden görülen eski bulgular: T-16 (ham İngilizce kısıt mesajı: boş itiraz metni, arıza bitişi), T-35 (`itiraz_incelemeye_al` kim/ne zaman yok; `ariza_karar` kararı `giren_id`'ye yazıyor).

### Denediklerim
- 148 çağrı (tablo; ham hali `scratch/a8_akis_sonuc.txt`).
- İtiraz reddi: 8 rol RPC ile, 3 rol doğrudan tabloyla, 2 sistem yolu tetikleyiciyle.
- İzin: işlenmemiş / işlenmiş (eksik ve tamam) gün, çakışma (3 biçim), iptal (işlenmemiş, işlenmiş izinli, işlenmiş tamam), kilitli ay, kendi izni.
- Saatlik izin: işlenmiş / işlenmemiş gün, çakışma, tam gün izinle aynı gün, iptal yolu, kilitli ay.
- `v_izin_amir` ve T-12'nin iki yolu (`gun_kaydi`, `v_puantaj_canli`).
- Plan: ileri, geriye dönük, onay (işlenmiş ve işlenmemiş gün), ret (işlenmiş ve işlenmemiş gün), görevler ayrılığı (giren, kendi kaydı, kendine plan), yetkisiz roller, kilitli ay, kilitten sonra onay, saat dilimi.
- Arıza: manuel (kanıtlı ve kanıtsız), otomatik şüphe, karar, ret sonrası gece işi, sonradan arıza, uyarı.
- Geçici kart zimmetinin tarihi: RPC parametreleri, tarih parametresiyle çağrı, doğrudan INSERT.
- 19 fonksiyonun son sürümü (`scratch/a8_kod/`).

### Denemediklerim
- **`izin_iptal` ile kilitli aydaki izin:** T-48'de girilen Eylül izinlerinin iptali denenmedi.
- **Gece vardiyasında (V3, gece yarısını geçen) izin ve saatlik izin:** `saatlik_izin_kontrol`'deki "ertesi güne düşer" kuralı denenmedi.
- **Saatlik izinin mola etkisi** (7,5 saat altına düşünce mola 60 → 30): Adım 6'da denenmişti, burada tekrarlanmadı.
- **Aynı planın iki İK tarafından aynı anda onaylanması:** `for update` var, denenmedi.
- **`vardiya_plani_gir`'in "bugün" için (p_tarih = bugün) davranışı:** onaysız geçiyor; vardiya başladıktan sonra bugünün planını değiştirmenin istenip istenmediğini belgede bulamadım.
- **Ekrandan (HTTP) çağrı:** hepsi SQL ile rol taklidi. T-45 ekranda da olur, çünkü PostgREST oturumu UTC; HTTP ile ayrıca doğrulanmadı.
- **Kilitten sonra onaylanan planın fark satırında dakika farkı:** düzeltme `FARK` oldu; puantaj fark satırının içeriği Adım 12'de.

### Şüpheler
- **Geçici kart, sistem yolu:** RPC ileri tarihli zimmet girdirmiyor ✅. Ama `gecici_kart_zimmet_kontrol` tetikleyicisi, servis rolüyle doğrudan yapılan `verilis_zamani = 2026-12-31` INSERT'ini kabul etti (zimmet 8). Ekrandan bu yol yok; Adım 10'da tetikleyicinin neyi denetlediğine bakılmalı.
- **`current_date` başka yerlerde:** T-45'teki kalıp başka fonksiyonlarda da olabilir (ör. ileri tarih denetimleri, kart ve fazla mesai). Taranmadı.
- **İzin iptalinde gün eski haline dönmüyor:** İşlenmiş izinli günde iptal reddediliyor; İK'nın önce her günü `kayit_duzelt` ile elle değiştirmesi gerekiyor. 10 günlük yanlış bir izinde bu 10 ayrı düzeltme demek. Tasarım belgeye yazılmış, ama T-46 düzeltilirse iptal de otomatikleşmeli.
- **Eskale:** IZ2 ve SI3'ün soruları, aynı işlemde 14 ve 19 Ekim gece işleri yeniden çalışınca eskale oldu. Deneme günleri 1 ay geride olduğu için süre dolmuş sayılmış olabilir; gerçek akışta hata değil. T-18 ile aynı mekanizma.
- **VP6:** İK uzmanının girdiği planın üstüne amir yazınca `giren_id` amir oldu ve İK uzmanı artık onaylayabildi. Onaylanan şey amirin girdisi olduğu için görevler ayrılığı bozulmuyor. Ama planı ilk giren İK'nın izi kayboluyor (T-49'daki geçmiş eksikliği).

---

## Adım 9 — Fazla mesai (22 Kasım 2026)

**Başlangıç:** `main` @ `79ad042` (31 migration). Yerel veritabanı `supabase db reset` ile kuruldu. Raporun commit edilmemiş hali önce yedeklendi (`scratch/a9_rapor_yedek_reset_oncesi.md`); sıfırlamadan önce ve sonra özeti aynı.

**Betikler:**

| Betik | Ne sınıyor |
|---|---|
| `scratch/a9_fm.sql`, `scratch/a9_fm_sonuc.txt` | 33 çalışan, 99 çağrı: FM50/FM100, havuz, günlük ve yıllık sınır, yazılı onay ve geri alma, yetki ve görevler ayrılığı, kilitli ay, `v_fazla_mesai_yillik` |
| `scratch/a9_saat_dilimi.sql`, `scratch/a9_saat_dilimi_geri_al.sql` (+ `_sonuc.txt`) | `fazla_mesai_plani_kontrol`'deki `current_date`; İstanbul 02:32 ve 02:36'da çalıştırıldı |
| `scratch/a9_kod/*.sql` | Okunan 17 fonksiyonun ve görünümün son sürümü |

**Kurulum:**
- Hepsi tek işlem; sonda `ROLLBACK`.
- Departman "S9 Deneme"; amiri montaj.amiri. Talepler montaj.amiri'den, kararlar ik.muduru'dan (aksi yazmadıkça).
- Yazılı onay 2 Ocak 2026 imzalı; H6 ve P3'te yazılı onay yok.
- Günler: 15–16 Eylül (kilitlenecek), 12–18 Ekim (14 Ekim Çarşamba, 18 Ekim Pazar), 28 Ekim arife, 29 Ekim resmi tatil.
- GÜNDÜZ 08:00–17:00. Mola 7,5 saat üstünde 60 dk. Havuz eşiği 15 dk. Yıllık sınır 16.200 dk.

### Sonuç tablosu

| # | Konu | Ne yaptım | Beklenen | Gerçekleşen | |
|---|---|---|---|---|---|
| 1 | Hafta içi, plan 120 | H1: 08:00–19:00 | FM50 120, çalışma 600 | FM50 120, çalışma 600 | ✅ |
| 2 | Planın altında çalışma | H2: 08:00–18:00 | FM50 60 | FM50 60 | ✅ |
| 3 | Planın üstünde çalışma | H3: 08:00–19:30 | FM50 120, 30 dk havuza | FM50 120; havuz `vardiya_sonrasi 30` | ✅ |
| 4 | Plansız, havuz → İK onay | H4: 08:00–19:00 | Önce FM 0, havuz 120; onayla FM50 120 | Aynen; gün onayla hemen yeniden hesaplandı | ✅ |
| 5 | Plansız, eşik altı | H5: 08:00–17:10 | 10 dk ≤ 15 dk eşik: havuz yok | FM 0, havuz yok | ✅ (tasarım) |
| 6 | Havuz → İK ret | H7 | FM 0; ret gerekçesi zorunlu | Kısa gerekçe reddedildi; ret sonrası FM 0 | ✅ |
| 7 | Yazılı onay yokken plan | H6: talep | Ret | "geçerli yazılı fazla mesai onayı yok" | ✅ |
| 8 | Yazılı onay yokken havuz onayı | H6: 08:00–19:00, İK havuzu onaylar | Ret (yazılı onay şartı) | OK, FM50 120 | ❌ T-56 |
| 9 | Pazar, yazılı onay var, plan yok | P1: 08:00–17:00 | Belgeye göre bütün çalışma FM100 | FM100 480, talep / İK kararı yok | ✅ belge (yıllık sınıra sayılmıyor: T-57) |
| 10 | Pazar, plan 120 | P2: 08:00–19:00 | FM100 600 | FM100 600 | ✅ |
| 11 | Pazar, yazılı onay yok | P3: havuz → İK onay | Havuza düşer; onay yazılı onay şartına takılır | Havuz `tatil_calismasi 540`; onayla FM100 480 | ❌ T-56 |
| 12 | Resmi tatil | R1: 29 Ekim 08:00–17:00 | FM100 480 | FM100 480 | ✅ |
| 13 | Arife, plan 120 | A1: 28 Ekim 08:00–19:00 | Yasal uygulamaya göre 13:00 sonrası FM100 (T-28) | FM50 120, FM100 0 | ❌ T-28 (açık) |
| 14 | Arife, plansız | A2: 08:00–17:00 | T-28 | FM 0, öğleden sonra normal çalışma | ❌ T-28 (açık) |
| 15 | Günlük sınır, GÜNDÜZ | D1: 120 / 121 dk | 120 kabul, 121 ret | 120 OK; 121 "661 dakika olur; sınır 660" | ✅ (mola dahil hesap: T-64) |
| 16 | Günlük sınır, V1 (06–14) | D1: 180 / 181 dk | 180 kabul, 181 ret | 181 ret; 180 OK | ✅ |
| 17 | Gece vardiyasına plan | D1: V3 | Ret (m.69) | Ret | ✅ |
| 18 | Günlük sınır, havuz yolu | D2: plansız 08:00–20:59 → havuz 239 → İK onay | Ret ya da uyarı (11 saat) | OK; çalışma 719 dk (11 sa 59 dk), uyarı yok | ❌ T-58 |
| 19 | Planı olmayan gün / 0 dk / aynı güne ikinci talep | D1 | Ret | 3/3 ret (ikisi ham İngilizce, T-16) | ✅ |
| 20 | Yıllık sınır, tam sınır | Y1: 134×120 + 119 + 1 = 16.200 | Kabul | Hepsi onaylandı; toplam 16.200 | ✅ |
| 21 | Yıllık sınır, 1 dk aşım | Y1: +1 dk talep | Ret | "onaylı 16200 dk + 1 dk > 16200 dk (kalan 0 dk)" | ✅ |
| 22 | %80 uyarısı | Y1 | 12.960 dk'da bir kez | "12960 / 16200 dakikaya ulaştı" | ✅ |
| 23 | Sınır doluyken havuz onayı | Y2: 16.200 plan + havuz 120 | Ret | OK; FM50 120 yazıldı; yalnızca `fm_yillik_sinir_asildi` uyarısı (16.320) | ❌ T-57 |
| 24 | Havuz onaylıyken planlar | Y3: havuz 120, sonra 135×120 plan | Son plan reddedilmeli | 135/135 onaylandı; toplam 16.200 + 120 | ❌ T-57 |
| 25 | Geri alma: sonraki talep | W1: bildirim 20.10 (geçerlilik 19.11) | 20.11 talebi iptal; 12.10 onaylı plan ve günü bozulmaz | 1 plan iptal, uyarı; 12.10 FM50 120 aynı | ✅ |
| 26 | Geri alma sonrası yeni talep | W1: 23.11 | Ret | "geçerli yazılı fazla mesai onayı yok" | ✅ |
| 27 | Geri alma sonrası yeni yazılı onay (aynı yıl) | W1 | Çalışan yeniden onay verebilmeli | `duplicate key … fazla_mesai_onayi_calisan_id_yil_key` | ❌ T-60 |
| 28 | Geçmiş tarihli geri alma | W2: bildirim 01.09 (geçerlilik 01.10); 12.10 onaylı ve işlenmiş | Geri alma kaydedilir; geçmiş onaylı plan bozulmaz | Geri alma **tümüyle reddedildi**: "Geçmiş bir günün onaylı planı iptal edilemez." 12.10 günü sağlam | ⚠️ T-59 |
| 29 | Geri alma, plan kilitli ayda | W3: bildirim 10.08, 15 Eylül planı | Geri alma kaydedilir | Tümüyle reddedildi: "kilitli bir döneme ait" | ❌ T-59 |
| 30 | Geri alma: ileri tarih / ikinci kez / İK dışı | W3, W1 | — / ret / ret | 2027 bildirim kabul; ikinci kez "değiştirilemez"; amir "yetkiniz yok" | ✅ |
| 31 | `current_date`, gece penceresi | `a9_saat_dilimi_geri_al.sql`: dünkü onaylı plan, geri alma RPC'si | Her saatte aynı sonuç | UTC: plan iptal edildi. İstanbul: reddedildi | ❌ T-45 / T-59 |
| 32 | Plan kararı: İK dışı | W1: 6 rol RPC; amir ve İK doğrudan UPDATE | Ret | 6/6 "yetkiniz yok"; 2/2 `permission denied` | ✅ |
| 33 | Havuz kararı: İK dışı | H4: 6 rol RPC; amir doğrudan UPDATE | Ret | 6/6 "yetkiniz yok"; `permission denied` | ✅ |
| 34 | Talep: yetkisiz rol / başka departman | 5 rol | Ret | 4× "yetkiniz yok"; bobinaj.amiri "departmanınızda değil" | ✅ |
| 35 | Yazılı onay gir: İK dışı | 5 rol | Ret | 5/5 "yetkiniz yok" | ✅ |
| 36 | Talep eden = onaylayan | W2: ik.uzmani talep eder ve onaylar | Ret | Ret, ham İngilizce kısıt mesajı (`fazla_mesai_talep_onay_farkli`, T-16) | ✅ |
| 37 | Amir kendi fazla mesaisi | montaj.amiri kendine talep | Ret | "kimse kendi kaydında… (talep_eden_id)" | ✅ |
| 38 | Kendi kaydında karar | ik.muduru: kendi planına ve kendi havuz kaydına karar; ik.uzmani kendine yazılı onay | Ret | 3/3 görevler ayrılığı hatası | ✅ |
| 39 | Karara bağlanmış havuz kaydı | H4: onaydan sonra ret | Ret | "zaten karara bağlanmış" | ✅ |
| 40 | İşlenmiş güne sonradan plan onayı | K1, K2: havuzda 120 bekliyor; plan 120 talep ve onay | Gün hemen FM50 120 | Gün FM 0 kaldı. K1: havuz onaylanınca 120. K2: havuz reddedildi, FM 0; ilgisiz bir düzeltmeyle yeniden hesaplanınca 120 | ❌ T-61 |
| 41 | Kilitli aya talep | L1: 16 Eylül | Ret | "kilitli bir döneme ait" | ✅ |
| 42 | Kilitten önceki talebe kilitten sonra karar | L1: 15 Eylül | Ret; kilit bunu söylemeli | Karar reddedildi; talep sonsuza kadar `talep`. Kilit mesajında yok ("1 açık sorulu gün, 1 onaysız fazla mesai") | ❌ T-63 |
| 43 | Kilitten sonra havuz onayı | L2: 15 Eylül havuz 120 | Gün değişmez, fark satırı | Gün aynı; havuz `onaylandi/FARK` | ✅ |
| 44 | `v_fazla_mesai_yillik` | 33 çalışan: görünüm ile elle toplam | Görünüm gerçek fazla mesaiyi göstermeli | Yalnızca planlı günler. H4, H6, P1, P3, R1, D2 görünümde yok; Y2 "gerçekleşen 0" (gün 120); `kalan_dk` havuzu düşmüyor | ❌ T-62 |

### T-56 · İK, yazılı onayı olmayan çalışanın onaysız fazla mesaisini puantaja alabiliyor
- **Adım:** 9 · **Önem:** Yüksek
- **Yer:** `pdks.fazla_mesai_inceleme_karar` (yazılı onay denetimi yok); `pdks.gun_hesabi` (havuz dakikası `v_onay`'dan bağımsız eklenir: `v_ek := least(v_sonra, v_plan + v_havuz)`, tatilde `fm100_dk := least(v_ici + v_sonra, v_havuz)`). `gun_kaydi_fazla_mesai_kontrol` havuzu da yazılı onaydan bağımsız sayar.
- **Ne oldu:**
  - H6'nın 2026 için yazılı onayı yok. Plan talebi doğru biçimde reddedildi. Ama 08:00–19:00 çalışınca 120 dk havuza düştü; İK onaylayınca gün FM50 120 oldu.
  - P3'ün de yazılı onayı yok. Pazar 08:00–17:00 çalıştı; havuz `tatil_calismasi 540`. İK onaylayınca FM100 480 oldu.
- **Ne olmalıydı:** `docs/veritabani.md`: "Her yıl yazılı onay; yoksa fazla mesai planlanamaz". İş Kanunu m.41 fazla çalışmayı işçinin yazılı onayına bağlıyor. Havuz kararı da bu şarta tabi olmalı: yazılı onay yoksa onay reddedilmeli ya da en azından ayrı ve açık bir uyarıyla verilmeli.
- **Kanıt:** `scratch/a9_fm_sonuc.txt`
  ```
  18|H6|montaj.amiri|talep 2026-10-14 120 dk|HATA P0001: Çalışanın 2026-10-14 günü için geçerli yazılı fazla mesai onayı yok.
  63|H6|ik.muduru|havuz kararı 2026-10-14 onay|OK
  H6|2026-10-14|2 havuz kararı|tamam · 08:00–19:00 · çalışma 600 · … FM 120 (FM50 120, FM100 0) | havuz: vardiya_sonrasi 120 dk/onaylandi
  P3|2026-10-18|2 havuz kararı|tamam · 08:00–17:00 · çalışma 480 · … FM 480 (FM50 0, FM100 480) | havuz: tatil_calismasi 540 dk/onaylandi
  ```
- **Sade dille:** Kanuna göre işçi yılbaşında "fazla mesaiye kalmayı kabul ediyorum" diye imza vermeden fazla mesai yaptırılamaz. Sistem ön kapıyı kapatmış: imzası olmayana fazla mesai planlanamıyor. Ama arka kapı açık: imzası olmayan kişi yine de geç saate kadar kalırsa, İK tek tıkla bu süreyi fazla mesai olarak puantaja yazabiliyor. Denetimde "imzası olmayan çalışana fazla mesai yaptırılmış" sonucu çıkar.
- **Öneri:** `fazla_mesai_inceleme_karar`'da `p_onay` ise `fm_onay_gecerli_mi(calisan, gün)` denetimi. Yoksa ret ya da ayrı bir onay türü ("yazılı onay yok; kanuna aykırı çalışma olarak kayda geçer"), ücret etkisi İK ile kararlaştırılır. `gun_hesabi`'nda havuz dakikası da `v_onay`'a bağlanmalı.
- **Karar (Fırat, 25 Kasım):** Yazılı onay işveren yükümlülüğüdür; fiilen yapılan çalışma puantaja girer, eksiklik işaretlenir ve İK'ya bildirilir.
- **Durum:** ✅ Düzeltildi (feature/T56-havuz-yazili-onay). Migration: `20261220010000_havuz_yazili_onay.sql`, test: `havuz_yazili_onay_testi.sql`. Yazılı onay yokken onaylanan kayıt `fazla_mesai_inceleme.yazili_onaysiz` ile işaretlenir, İK'ya `yazili_onay_eksik` uyarısı yazılır; havuz ekranında "Yazılı onay yok" etiketi. `gun_hesabi` ve gün kaydı kuralı değişmedi (karara uygundu). Kilitli ayın tatil çalışmasında belge sonradan girilirse fark doğru yazılır.

### T-57 · Yıllık 270 saat sınırı yalnızca planları sayıyor; havuz onayları ve tatil fazla mesaisi sınırı aşıyor
- **Adım:** 9 · **Önem:** Yüksek
- **Yer:**
  - `pdks.fm_plan_denetle`: yalnızca `fazla_mesai_plani.planli_dk` (onaylı) toplanıyor.
  - `pdks.fazla_mesai_inceleme_karar`: plan + havuz toplanıyor ama aşımda yalnızca `uyari_yaz('fm_yillik_sinir_asildi')`, ret yok.
  - Pazar / resmi tatilde yazılı onayla gelen FM100 (planı yoksa) iki toplamda da yok.
- **Ne oldu:**
  - **Y2:** Planlar tam sınırda (16.200). İK havuzdaki 120 dk'yı onayladı; gün FM50 120 oldu. Sonuç: yalnızca uyarı ("onaylı fazla mesai 16320 dk").
  - **Y3:** Önce havuzdan 120 dk onaylandı. Sonra 135×120 dk plan, sınıra takılmadan onaylandı: 16.200 + 120.
  - **P1, R1:** Pazar ve resmi tatilde 480'er dk FM100 yazıldı. Hiçbir sınır toplamında yok.
- **Ne olmalıydı:** İş Kanunu m.41: fazla çalışma yılda 270 saati geçemez. Sınır, puantaja giren bütün fazla mesai dakikalarıyla (FM50 + FM100) denetlenmeli; havuz onayı da plan onayı gibi sınırda durmalı. `docs/veritabani.md` satır 312 ("onaylı planlar toplamı") ve 325 ("geçerse uyarı yazılır") bugünkü davranışı tarif ediyor; yani belgedeki karar bilerek bırakılmış bir açık.
- **Kanıt:**
  ```
  80|Y2|postgres|135 × 120 dk plan (16.200)|OK 135 plan onaylandı
  81|Y2|ik.muduru|havuz kararı 2026-10-14 onay|OK
  82|Y2|postgres|sınır aşıldı uyarısı|OK 2026 yılı onaylı fazla mesai 16320 dk; yıllık sınır 16200 dk (270 saat).
  83|Y3|ik.muduru|havuz kararı 2026-10-14 onay|OK
  84|Y3|postgres|135 × 120 dk plan (havuz 120 onaylıyken)|OK 135 plan onaylandı
  85|Y3|postgres|plan + havuz toplamı|OK 16200 + 120
  P1|… FM 480 (FM50 0, FM100 480) | plan: - | havuz: -
  ```
- **Sade dille:** Kanun bir işçiye yılda en fazla 270 saat fazla mesai yaptırılmasına izin veriyor. Sistem bu sınırı yalnızca "önceden planlanmış" fazla mesai için uyguluyor. Habersiz kalınan saatler İK onayıyla eklenince sınır aşılıyor ve sistem yalnızca "aşıldı" diye not düşüyor. Pazar ve bayram mesaileri ise hiç sayılmıyor. Ay sonunda bir çalışanın 300 saat fazla mesaisi olabilir; sistem ekranında "kalan 0" yazar ama kimse durdurmaz.
- **Öneri:** Tek bir `fm_yillik_toplam(calisan, yil)` fonksiyonu: onaylı plan + onaylı havuz + planı olmayan tatil FM100 (ya da doğrudan `gun_kaydi.fazla_mesai_dk` toplamı ile gelecekteki onaylı planlar). `fm_plan_denetle` ve `fazla_mesai_inceleme_karar` bunu kullansın; havuzda aşım ret olsun. Tatil çalışmasının 270 saate sayılıp sayılmayacağı İK / hukukla kararlaştırılıp belgeye yazılmalı.
- **Karar (Fırat, 25 Kasım):** Tatil çalışması da 270 saate sayılır (çalışanı koruyan seçenek). Sınır, ileriye dönük plan talebinde ret sebebidir; havuzdaki fiilen yapılmış çalışma reddedilmez: onaylanır, puantaja girer, işaretlenir ve İK'ya bildirilir.
- **Durum:** ✅ Düzeltildi (feature/T57-yillik-toplam). Migration: `20261221010000_yillik_fazla_mesai.sql`, test: `yillik_fazla_mesai_testi.sql`. Tek toplam `fm_yillik_toplam` (onaylı plan + onaylı havuz + tatil çalışması); `fm_plan_denetle` bununla reddeder. Aşan havuz onayı `fazla_mesai_inceleme.yillik_sinir_asildi` ile işaretlenir; yazılı onaylı tatil çalışması aşarsa da `fm_yillik_sinir_asildi` uyarısı yazılır.

### T-58 · Havuz onayında günlük 11 saat sınırı denetlenmiyor
- **Adım:** 9 · **Önem:** Orta
- **Yer:** `pdks.fazla_mesai_inceleme_karar` (günlük sınır yok). Sınır yalnızca planda var: `fm_plan_denetle` (`vardiya_suresi_dk + planli_dk ≤ gunluk_azami_calisma_dk`).
- **Ne oldu:** D2 planı yokken 08:00–20:59 çalıştı. Havuza 239 dk düştü. İK onayladı. Gün: çalışma 719 dk (11 sa 59 dk), FM50 239. Uyarı çıkmadı. Aynı kişiye plan yoluyla 121 dk bile verilemiyor ("661 dakika olur; sınır 660").
- **Ne olmalıydı:** İş Kanunu m.63: günlük çalışma 11 saati aşamaz. Havuz onayı sınırı aşan kısmı reddetmeli ya da en azından İK'yı uyarmalı (`gece_calisma_siniri_asildi` uyarısı gibi).
- **Kanıt:**
  ```
  D2|2026-10-14|1 gece işi|tamam · 08:00–20:59 · çalışma 480 · … FM 0 | havuz: vardiya_sonrasi 239 dk/inceleme_bekliyor
  69|D2|ik.muduru|havuz kararı 2026-10-14 onay|OK
  D2|2026-10-14|2 havuz kararı|tamam · 08:00–20:59 · çalışma 719 · mola 60 · FM 239 (FM50 239, FM100 0)
  20|D1|montaj.amiri|talep 2026-10-13 121 dk|HATA P0001: Günlük çalışma 661 dakika olur; sınır 660 dakika (11 saat).
  ```
- **Sade dille:** Önceden planlanan fazla mesai 11 saati geçemiyor. Ama biri plansız 13 saat kalırsa İK hepsini onaylayabiliyor ve sistem itiraz etmiyor. Kanunun yasakladığı bir gün puantaja "onaylı" diye giriyor.
- **Öneri:** `fazla_mesai_inceleme_karar`'da onay sonrası `calisma_dk > gunluk_azami_calisma_dk` ise ret ya da kısmi onay (yalnızca sınıra kadar). En azından `gunluk_sinir_asildi` uyarısı.
- **Durum:** Açık

### T-59 · Yazılı onayın geri alınması bazı durumlarda hiç kaydedilemiyor; sonuç gece saatine göre değişiyor
- **Adım:** 9 · **Önem:** Orta
- **Yer:**
  - `pdks.fazla_mesai_onayi_geri_alindi`: `is_gunu >= gecerlilik_bitisi` olan `talep` ve `onaylandi` planları `durum = 'iptal'` yapıyor ama `karar_veren_id`'yi temizlemiyor.
  - `pdks.fazla_mesai_plani_kontrol`: bu yüzden iptal "kişili iptal" dalına giriyor; orada `old.is_gunu < current_date` ve kilitli ay denetimleri var. Biri tutunca geri almanın tamamı geri dönüyor.
- **Ne oldu:**
  - **W2:** Bildirim 01.09 (geçerlilik 01.10). 12 Ekim'de onaylı ve çalışılmış bir plan var. Geri alma reddedildi: "Geçmiş bir günün onaylı planı iptal edilemez."
  - **W3:** Bildirim 10.08 (geçerlilik 09.09). İptal edilecek 15 Eylül planı kilitli ayda. Geri alma reddedildi: "kilitli bir döneme ait".
  - **Gece penceresi:** Dünkü onaylı plan için aynı geri alma, İstanbul 02:36'da UTC oturumunda başarılı oldu (plan iptal), İstanbul oturumunda reddedildi (T-45).
- **Ne olmalıydı:** Çalışan onayını geri aldığında bu bilgi her zaman kaydedilebilmeli. Geçmiş ve kilitli aydaki onaylı planlar korunmalı (çalışılmış gün bozulmasın), ileri tarihli olanlar iptal edilmeli. Sonuç saate göre değişmemeli.
- **Kanıt:** `scratch/a9_fm_sonuc.txt`, `scratch/a9_saat_dilimi_geri_al_sonuc.txt`
  ```
  93|W2|ik.uzmani|geri al, bildirim 01.09 (geçerlilik 01.10, geçmişte)|HATA P0001: Geçmiş bir günün onaylı planı iptal edilemez.
  96|W3|ik.uzmani|geri al, bildirim 10.08 (geçerlilik 09.09; 15 Eylül planı kilitli ayda)|HATA P0001: 2026-09-15 günü kilitli bir döneme ait; fazla mesai planı değişmez.
  saat: UTC 2026-11-21 23:36 · İstanbul 2026-11-22 02:36
  UTC oturum: current_date=2026-11-21 · plan günü=2026-11-21 · geri alma: OK · plan=iptal
  İstanbul oturum: current_date=2026-11-22 · geri alma: HATA: Geçmiş bir günün onaylı planı iptal edilemez.
  ```
- **Sade dille:** İşçi "artık fazla mesaiye kalmak istemiyorum" diye dilekçe verdi, İK bunu birkaç hafta geç sisteme giriyor. Arada onaylanıp çalışılmış bir fazla mesai varsa sistem "geçmiş planı iptal edemem" deyip dilekçeyi hiç kaydetmiyor. İşçinin geri çekilmesi kayıtta görünmüyor, sonraki fazla mesailer de engellenmiyor. Aynı işlem gece 03:00'ten önce yapılırsa sonuç farklı çıkıyor ve dünkü onaylı fazla mesai iptal edilebiliyor.
- **Öneri:** `fazla_mesai_onayi_geri_alindi`: iptali yalnızca `is_gunu >= greatest(gecerlilik_bitisi, bugün_istanbul)` olan ve kilitli olmayan planlara uygula, `karar_veren_id = null` yaz (sistem iptali). Geçmişte kalanlar için İK'ya uyarı. `fazla_mesai_plani_kontrol`'deki `current_date`'i İstanbul tarihine çevir (T-45).
- **Durum:** ✅ Düzeltildi — PR #46 (kod), PR #47 (kilitli ay testi / canlı kontrol listesi). (PR #46 migration: `20261205010000_istanbul_tarihi.sql`, test: `istanbul_tarihi_testi.sql`). Geri alma artık her zaman kaydedilir: ileri tarihli (bugün dahil) onaylı planlar ve talepler sistemce iptal edilir (`karar_veren_id` boş); geçmişteki onaylı ve kilitli aydaki planlar korunur, sayısı İK uyarısına yazılır. "Geçmiş gün" kararı İstanbul tarihiyle verilir.

### T-60 · Onayını geri alan çalışan aynı yıl yeniden yazılı onay veremiyor
- **Adım:** 9 · **Önem:** Düşük
- **Yer:** `pdks.fazla_mesai_onayi`: `UNIQUE (calisan_id, yil)`; geri alınmış onay da değiştirilemez.
- **Ne oldu:** W1'in onayı geri alındı (geçerlilik 19.11). İK aynı yıl için yeni onay girmeyi denedi: `duplicate key … fazla_mesai_onayi_calisan_id_yil_key`.
- **Ne olmalıydı:** Çalışan fikrini değiştirip yeniden imza verebilmeli. Yılda birden çok onay satırı olmalı; geçerlilik aralıkları çakışmamalı.
- **Kanıt:** `91|W1|ik.uzmani|aynı yıl için yeni yazılı onay|HATA 23505: duplicate key value violates unique constraint "fazla_mesai_onayi_calisan_id_yil_key"`
- **Sade dille:** Kasım'da "artık kalmayacağım" diyen bir işçi, Aralık'ta sipariş yoğunluğunda "tamam, kalırım" diye yeniden imza verirse sistem bunu kaydedemiyor. O işçiye yıl sonuna kadar fazla mesai yazılamaz. Hata mesajı da İngilizce ve teknik.
- **Öneri:** Tekil kısıt yerine `exclude` (çalışan, geçerlilik aralığı) ya da "yılda en fazla bir *geçerli* onay" kuralı; `fm_onay_gecerli_mi` zaten aralığa bakıyor.
- **Durum:** Açık

### T-61 · İşlenmiş güne sonradan onaylanan fazla mesai planı günü yeniden hesaplamıyor
- **Adım:** 9 · **Önem:** Orta
- **Yer:** `pdks.fazla_mesai_karar`: yalnızca planın durumunu yazıyor; `gun_hesabini_yenile` çağırmıyor. Havuz kararı (`fazla_mesai_inceleme_karar`) ve saatlik izin ise çağırıyor.
- **Ne oldu:**
  - **K1:** Gün işlendi, 120 dk havuzda. Amir 14 Ekim için plan talep etti, İK onayladı: gün FM 0 kaldı. İK havuzu da onaylayınca FM50 120 oldu.
  - **K2:** Aynı durum, ama İK bu kez havuzu reddetti ("plan zaten var" diyerek): FM 0. Sonra ilgisiz bir `kayit_duzelt` (çıkışı aynı saate yazmak) günü yeniden hesaplattı: FM50 120.
- **Ne olmalıydı:** Plan onayı, gün işlenmişse onu hemen yeniden hesaplamalı (vardiya planı onayında olduğu gibi). Aynı plan onayı ve havuz reddi her zaman aynı sonucu vermeli.
- **Kanıt:**
  ```
  K2|2026-10-14|2 sonradan plan onayı|… çalışma 480 · … FM 0 | plan: 120 dk/onaylandi | havuz: vardiya_sonrasi 120 dk/inceleme_bekliyor
  K2|2026-10-14|3 havuz reddedildi|… çalışma 480 · … FM 0 | plan: 120 dk/onaylandi | havuz: … 120 dk/reddedildi
  K2|2026-10-14|4 gün yeniden hesaplandı|… çalışma 600 · … FM 120 (FM50 120, FM100 0) | plan: 120 dk/onaylandi | havuz: … 120 dk/reddedildi
  ```
- **Sade dille:** Amir "dün iki saat fazla mesai yaptırdım" deyip talebi sonradan giriyor, İK onaylıyor, ama puantajda fazla mesai görünmüyor. Bir gün başka bir sebeple o gün yeniden hesaplanırsa fazla mesai birden ortaya çıkıyor. Puantajın sonucu, alakasız bir düzeltmenin yapılıp yapılmadığına bağlı hale geliyor; ay kilitlenmişse fark hiç gelmeyebilir.
- **Öneri:** `fazla_mesai_karar`'da onaydan sonra o günün kaydı varsa `gun_hesabini_yenile` + `gun_sonrasi_kontroller` (havuz kaydı plan kadar azalır). Kilitli ayda fark satırı. Ayrıca geçmiş güne plan talebinin kabul edilip edilmeyeceği belgeye yazılmalı.
- **Durum:** Açık

### T-62 · `v_fazla_mesai_yillik` yalnızca planlı fazla mesaiyi gösteriyor
- **Adım:** 9 · **Önem:** Orta
- **Yer:** `pdks.v_fazla_mesai_yillik`: `fazla_mesai_plani` (onaylı) üzerinden `left join gun_kaydi`; havuz ve planı olmayan günler yok; `kalan_dk = sınır − planli_dk`.
- **Ne oldu:** İK oturumunda görünüm ile elle toplam karşılaştırıldı (33 çalışan):
  ```
  H4|görünüm: plan -, gerçekleşen -, kalan -    || elle: plan 0, gün FM toplamı 120 (FM50 120), onaylı havuz 120
  P1|görünüm: plan -, gerçekleşen -, kalan -    || elle: plan 0, gün FM toplamı 480 (FM100 480), onaylı havuz 0
  P3|görünüm: plan -, gerçekleşen -, kalan -    || elle: plan 0, gün FM toplamı 480 (FM100 480), onaylı havuz 540
  D2|görünüm: plan -, gerçekleşen -, kalan -    || elle: plan 0, gün FM toplamı 239 (FM50 239), onaylı havuz 239
  Y2|görünüm: plan 16200, gerçekleşen 0, kalan 0 || elle: plan 16200, gün FM toplamı 120, onaylı havuz 120
  H2|görünüm: plan 120, gerçekleşen 60, kalan 16080 || elle: plan 120, gün FM toplamı 60   (✓ planlı günlerde tutuyor)
  ```
- **Ne olmalıydı:** Ekrandaki yıllık özet, sınır denetimiyle aynı toplamı göstermeli: gerçekleşen = bütün `gun_kaydi.fazla_mesai_dk`; kalan = sınır − (onaylı plan + onaylı havuz [+ tatil, T-57 kararına göre]).
- **Sade dille:** İK'nın "bu işçinin bu yıl ne kadar fazla mesai hakkı kaldı" diye baktığı tablo yalnızca önceden planlanan mesaileri sayıyor. Habersiz kalınan ama onaylanan saatler ve pazar mesaileri tabloda yok. Tabloda "kalan 16.080 dk" yazan biri aslında sınıra çok daha yakın olabilir.
- **Öneri:** Görünümü `gun_kaydi` (yıl, çalışan) üzerinden kurmak; plan ve havuzu ayrı sütun olarak eklemek; `kalan_dk`'yı T-57'deki tek toplam fonksiyonundan almak.
- **Durum:** ✅ Düzeltildi (feature/T57-yillik-toplam, T-57 ile). `v_fazla_mesai_yillik`, `fm_yillik_toplam` ile aynı günleri (`v_fm_yillik_gun`) toplar: plan, havuz, gerçekleşen, toplam ve kalan. Yıllık sınır sekmesi görünümden okur; gösterilen toplam ve kalan sınır denetimiyle aynıdır. Test: `yillik_fazla_mesai_testi.sql`.

### T-63 · Kilitli ayda karar bekleyen fazla mesai talebi askıda kalıyor; kilit bunu söylemiyor
- **Adım:** 9 · **Önem:** Düşük
- **Yer:** `pdks.ay_kilitle` (bekleyen işlerde yalnızca `fazla_mesai_inceleme` sayılıyor; `fazla_mesai_plani.durum = 'talep'` yok); `fazla_mesai_plani_kontrol` kilitli ayda her güncellemeyi reddediyor.
- **Ne oldu:** Kilitten önce Eylül'de 1 bekleyen talep ve 1 havuz kaydı vardı. Zorla kilit mesajı yalnızca havuzu söyledi ("1 onaysız fazla mesai"). Kilitten sonra talebe karar verilemedi; talep `talep` olarak kaldı.
- **Ne olmalıydı:** Kilit, karar bekleyen talepleri de saymalı (zorla geçilebilir) ve kilitle birlikte bunları otomatik "iptal (dönem kilitlendi)" yapmalı.
- **Kanıt:**
  ```
  4|L|postgres|kilitten önce Eylül bekleyen plan talepleri / havuz|OK 1 talep · 1 havuz
  5|L|ik.muduru|Eylül zorla kilit|OK 9/2026 kilitlendi. Zorla geçilenler: 1 açık sorulu gün, 1 onaysız fazla mesai. …
  6|L1|ik.muduru|plan kararı 2026-09-15 onay|HATA P0001: 2026-09-15 günü kilitli bir döneme ait; fazla mesai planı değişmez.
  9|L1|postgres|kilitten sonra 15 Eylül talebi|OK talep
  ```
- **Sade dille:** Ay kapanırken unutulmuş bir fazla mesai talebi varsa kilit bundan söz etmiyor. Ay kapandıktan sonra o talep ne onaylanabiliyor ne reddedilebiliyor; İK ekranında sonsuza kadar "karar bekliyor" olarak duruyor.
- **Öneri:** `ay_kilitle`'ye `bekleyen_fm_talebi` sayısı ve kilitte bu talepleri sistem iptali.
- **Durum:** Açık

### T-64 · Günlük 11 saat sınırı molayı da çalışma sayıyor
- **Adım:** 9 · **Önem:** Görüş
- **Yer:** `pdks.fm_plan_denetle`: `vardiya_suresi_dk(vardiya) + planli_dk`. `vardiya_suresi_dk` vardiyanın başlangıç–bitiş farkı (GÜNDÜZ 540 dk, 60 dk mola dahil).
- **Ne oldu:** GÜNDÜZ'e en fazla 120 dk plan verilebildi (540 + 120 = 660). Bu günün net çalışması 600 dk (10 saat).
- **Ne olmalıydı:** İş Kanunu m.68'e göre ara dinlenmesi çalışma süresinden sayılmaz; m.63'teki 11 saat net çalışma süresidir. Bugünkü hesap kanundan katı (çalışan aleyhine değil, işveren aleyhine). Bilinçli bir tercihse belgeye yazılmalı.
- **Kanıt:** `19|D1|…|talep 2026-10-12 120 dk|OK 11` · `20|D1|…|talep 2026-10-13 121 dk|HATA … 661 dakika olur; sınır 660`
- **Sade dille:** Sistem 1 saatlik yemek molasını da çalışma saatine sayıyor. Bu yüzden normalde 3 saat yazılabilecek fazla mesaiye en fazla 2 saat izin veriyor. Yasal bir sorun değil, ama üretim planlamasını gereksiz yere kısıtlar.
- **Öneri:** İK ile karar: `vardiya_suresi_dk − mola_suresi(...)` + plan ≤ 660, ya da bugünkü katı kural belgeye yazılsın.
- **Durum:** Açık

### T-76 · Geçmiş, çalışılmış bir güne "planlı" fazla mesai talebi girilip onaylanabiliyor
- **Adım:** 9 · **Önem:** Orta
- **Yer:** `pdks.fazla_mesai_talep_et` ve `pdks.fm_plan_denetle`: `is_gunu` için "bugünden önce olamaz" ya da "gün işlenmişse olamaz" kontrolü yok.
- **Ne oldu:** K1 14.10'da plansız 08:00–19:00 çalıştı; gece işi 120 dk'yı havuza (`vardiya_sonrasi`, onay bekliyor) koydu. Sonra amir aynı gün için 120 dk "planlı" talep girdi, İK onayladı. Plan önceden yapılmış gibi kayda geçti. (Gün hemen yeniden hesaplanmadı: T-61.)
- **Ne olmalıydı:** "Planlı fazla mesai" çalışmadan önce verilen karardır. Geçmiş güne yalnızca havuz yolu (onaysız çalışmanın İK incelemesi) kullanılmalı; geçmiş tarihli plan talebi reddedilmeli ya da İK'nın ayrıca gördüğü "geriye dönük" bir işaret almalı (vardiya planındaki `geriye_donuk` gibi).
- **Kanıt:** `a9_fm_sonuc.txt`: `72|K1|montaj.amiri|talep 2026-10-14 120 dk|OK 456` · `73|K1|ik.muduru|plan kararı 2026-10-14 onay|OK` · `K1|2026-10-14|2 sonradan plan onayı|… | plan: 120 dk/onaylandi | havuz: vardiya_sonrasi 120 dk/inceleme_bekliyor`.
- **Sade dille:** Sistem "önceden planlanmış fazla mesai" ile "habersiz kalınan fazla mesai"yi ayrı tutuyor; ikincisi İK'nın ayrı incelemesinden geçiyor. Ama amir, çalışma bittikten sonra geriye dönük bir "plan" girerek habersiz kalınan saati planlıymış gibi gösterebiliyor. Raporlarda "plansız çalışma" azalmış görünür, gerçekte değişen bir şey yoktur.
- **Öneri:** `fazla_mesai_talep_et`: `p_is_gunu < bugün (İstanbul)` ise ret (T-45'teki saat dilimine dikkat), ya da talebe `geriye_donuk` işareti ve İK ekranında ayrı liste. Kalıcı test: dünkü güne talep reddedilir.
- **Durum:** Açık

### T-77 · 15 dakikanın altındaki plansız çalışma hiçbir yere yazılmıyor
- **Adım:** 9 · **Önem:** Orta (mevzuat kontrol edilecek)
- **Yer:** `pdks.fazla_mesai_inceleme` üretimi, `ayar.fm_plansiz_esik_dk = 15`.
- **Ne oldu:** H5 vardiya bitişinden sonra 10 dk kaldı (08:00–17:10). Gün FM 0; havuza kayıt düşmedi; uyarı yok. Eşik altındaki süre hem fazla mesai hem inceleme dışında kalıyor.
- **Ne olmalıydı:** Eşik "uyarı gürültüsünü azaltmak" için olabilir, ama süre kaybolmamalı: en azından günlük kayıtta ya da ay toplamında görünmeli. Mevzuat kontrol edilecek: Fazla Çalışma ve Fazla Sürelerle Çalışma Yönetmeliği'nde "yarım saatten az süreler yarım saat sayılır" kuralı olabilir. Öyleyse eşik altı süre atılmamalı, yarım saate yuvarlanmalı.
- **Kanıt:** `a9_fm_sonuc.txt`: `H5|2026-10-14|1 gece işi|tamam · 08:00–17:10 · çalışma 480 · mola 60 · FM 0 (FM50 0, FM100 0) · hesap ✓ | plan: - | havuz: -` · görünüm: `H5|… elle: plan 0, gün FM toplamı 0 …, onaylı havuz 0`.
- **Sade dille:** Her gün vardiyadan sonra 10–14 dakika kalan biri ayda 4–5 saat çalışır; sistem bunun hiçbirini göstermiyor. Yönetmelik yarım saatin altını yarım saat saymayı istiyorsa, sistem çalışan aleyhine hesap yapıyor demektir.
- **Öneri:** Önce mevzuat ve İK görüşü. Sonra ya eşik altı süre ayrı bir alanda tutulsun (ör. `gun_kaydi.esik_alti_dk`) ve ay toplamında görünsün, ya da yönetmelik öyle diyorsa yarım saate yuvarlanıp havuza düşsün. Karar `docs/veritabani.md`'ye yazılsın.
- **Durum:** Açık

### T-78 · Pazar vardiyası amirin tek kararıyla FM100 oluyor; İK onayı yok
- **Adım:** 9 · **Önem:** Görüş
- **Yer:** `pdks.vardiya_plani_gir` (ileri tarihli plan İK onayı istemiyor, Adım 8) + gün hesabı: yazılı onayı olan çalışanın hafta tatili / Pazar çalışmasının tamamı FM100 (`docs/veritabani.md` satır 316).
- **Ne oldu:** Yazılı onayı olan P1'e Pazar (18.10) GÜNDÜZ planı girildi. Fazla mesai talebi ve İK kararı olmadan 480 dk FM100 yazıldı. Yıllık sınıra da sayılmadı (T-57).
- **Ne olmalıydı:** Belgeye uygun. Ama "fazla mesaiyi İK onaylar" ilkesiyle çelişiyor: hafta içi 1 saatlik fazla mesai İK onayı isterken, 8 saatlik Pazar fazla mesaisi amirin plan girmesiyle oluyor.
- **Kanıt:** `a9_fm_sonuc.txt`: `P1|2026-10-18|1 gece işi|tamam · 08:00–17:00 · çalışma 480 · mola 60 · FM 480 (FM50 0, FM100 480) · hesap ✓ | plan: - | havuz: -`.
- **Sade dille:** Amir bir çalışanı Pazar'a yazdığında, İK'nın haberi olmadan o çalışana 8 saat %100 zamlı fazla mesai yazılıyor. Hata değil, belgede böyle karar verilmiş; ama İK'nın bilmesi gereken bir boşluk.
- **Öneri:** İK ile karar: hafta tatili / resmî tatil günlerine girilen vardiya planı İK onayı istesin (`geriye_donuk` gibi `tatil_plani` işareti), ya da bu bilinçli kabul belgeye "İK onayı gerekmez" diye açıkça yazılsın.
- **Durum:** Açık

### Bulgular önem sırasıyla
1. **T-56** · Yüksek · Yazılı onay olmadan havuzdan fazla mesai onaylanabiliyor.
2. **T-57** · Yüksek · 270 saat sınırı havuzu ve tatil FM100'ü saymıyor; havuz onayı sınırı aşıyor.
3. **T-28** · Yüksek (Adım 6'dan, yeniden doğrulandı; Orta'dan yükseltildi) · Arife öğleden sonra FM100 yok.
4. **T-58** · Orta · Havuz onayında 11 saat sınırı yok (719 dk onaylandı).
5. **T-59** · Orta · Yazılı onayın geri alınması bazen hiç kaydedilemiyor; gece saatine göre sonuç değişiyor (T-45 ile bağlantılı).
6. **T-61** · Orta · Sonradan onaylanan plan günü yeniden hesaplamıyor.
7. **T-62** · Orta · `v_fazla_mesai_yillik` yalnızca planlı günleri gösteriyor.
8. **T-76** · Orta · Geçmiş güne "planlı" fazla mesai talebi girilebiliyor (22 Kasım'da eklendi).
9. **T-77** · Orta · 15 dk altı plansız çalışma kayboluyor; mevzuat kontrol edilecek (22 Kasım'da eklendi).
10. **T-60** · Düşük · Geri alınan onay aynı yıl yenilenemiyor.
11. **T-63** · Düşük · Kilitli ayda bekleyen talep askıda; kilit söylemiyor.
12. **T-64** · Görüş · 11 saat sınırına mola dahil.
13. **T-78** · Görüş · Pazar vardiyası İK onayı olmadan FM100 (22 Kasım'da eklendi).

Yeniden görülen eski bulgular: T-16 (talep eden = onaylayan, 0 dk ve mükerrer talep ham İngilizce kısıt mesajıyla dönüyor), T-45 (`fazla_mesai_plani_kontrol`'deki `current_date`, T-59'ta RPC ile kanıtlandı).

### T-45 bağlantısı: `fazla_mesai_plani_kontrol`'deki `current_date`
- **Doğrudan iptal yolu:** `scratch/a9_saat_dilimi.sql` İstanbul 02:32'de çalıştırıldı. UTC oturumunda dünkü onaylı plan bir amir adına iptal edilebildi; İstanbul oturumunda reddedildi. Bu yol yalnızca doğrudan tablo güncellemesiyle açılıyor (`authenticated`'ın UPDATE yetkisi yok). `isten_cikis_gir` yalnızca `talep` durumundakileri iptal ediyor, bu satıra uğramıyor.
- **RPC yolu:** `fazla_mesai_onayi_geri_al` bu satıra uğruyor (T-59), sonuç saate göre değişiyor. Kanıt yukarıda.

### Denediklerim
- 99 çağrı ve 33 çalışanın gün izi (`scratch/a9_fm_sonuc.txt`).
- FM50: plan, planın altı ve üstü, plansız (eşik altı ve üstü), havuz onayı ve reddi.
- FM100: Pazar (planlı, plansız, yazılı onaysız), resmi tatil, arife.
- Günlük sınır: GÜNDÜZ, V1, gece vardiyası, havuz yolu.
- Yıllık sınır: tam sınır, 1 dk aşım, %80 uyarısı, havuzla iki yönde aşım.
- Yazılı onay: yok, geri alma (ileri, geçmiş, kilitli ay, ileri yıl, ikinci kez), yeniden onay.
- Yetki: talep 5 rol, plan kararı 6 rol + doğrudan UPDATE, havuz kararı 6 rol + doğrudan UPDATE, yazılı onay 5 rol.
- Görevler ayrılığı: talep eden = karar veren, amir kendine, İK kendi planına / havuzuna / yazılı onayına.
- Kilitli ay: talep, kilitten önceki talebe karar, havuz onayı.
- Gece penceresi (`current_date`): doğrudan ve RPC yolu.
- `v_fazla_mesai_yillik` ile elle toplam.

### Denemediklerim
- **Gece vardiyasının (V3) gerçekleşen fazla çalışması ve havuzu:** Plan reddediliyor; plansız uzayan gece vardiyasının havuza ve gece çalışma sınırına etkisi denenmedi.
- **Esnek mesai (ESNEK) ve fazla mesai.**
- **Cumartesi hafta sonu ayarı (`cumartesi_hafta_sonu = 1`).**
- **Aynı çalışana iki onayın aynı anda gelmesi:** `fm_plan_denetle` çalışan satırını kilitliyor; eşzamanlı denenmedi.
- **Puantaja yansıma:** `v_puantaj_canli` / `puantaj_satiri`'ndaki FM50/FM100 kodları ve havuzun fark satırının sonraki aya geçişi (Adım 12).
- **Ekrandan (HTTP) çağrı:** hepsi SQL ile rol taklidi.
- **Yıllık sınırın yıl sınırında bölünmesi** (31 Aralık gece vardiyası; `extract(year from is_gunu)`).

### Şüpheler
- **Pazar vardiyası amirin tek kararıyla FM100 oluyor:** → T-78 olarak bulgulara alındı. İleri tarihli vardiya planı İK onayı istemiyor (Adım 8). Yazılı onayı olan çalışana amir Pazar günü GÜNDÜZ planı girerse, fazla mesai talebi ve İK kararı olmadan 480 dk FM100 yazılıyor (P1). Belgeye uygun (`docs/veritabani.md` satır 316), ama "fazla mesaiyi İK onaylar" ilkesiyle çelişiyor görünüyor; İK ile konuşulmalı.
- **Havuz eşiği:** → T-77 olarak bulgulara alındı. 15 dk'nın altındaki plansız çalışma (H5: 10 dk) hiçbir yere yazılmıyor. Her gün 14 dk geç çıkan biri ayda 5 saat kaybeder. Ayar bilinçli olabilir; belgede gerekçe yok.
- **Geçmiş güne plan talebi:** → T-76 olarak bulgulara alındı. Talepte tarih denetimi yok; çalışılmış güne sonradan "planlı fazla mesai" girilebiliyor (K1/K2). Planlı ile plansız ayrımını anlamsız kılabilir.
- **İleri yıla bildirim:** 2026 onayı için 2027 tarihli geri alma bildirimi kabul edildi (W3); etkisi yok ama veri tutarsız.

---

## Adım 10 — Kart, geçici kart, kart paylaşımı, İSG (22 Kasım 2026)

> Adım 10 atlanmıştı; Adım 11'den sonra yapıldı. Bulgu numaraları bu yüzden Adım 11'inkilerden (T-65…T-75) ve sonradan eklenenlerden (T-76…T-80) sonra geliyor.

**Başlangıç:** `main` @ `79ad042` (31 migration). Yerel veritabanı `supabase db reset` ile kuruldu. Raporun commit edilmemiş hali önce yedeklendi (`scratch/a10_rapor_yedek_reset_oncesi.md`); sıfırlamadan önce ve sonra özeti aynı.

**Betikler:**

| Betik | Ne sınıyor |
|---|---|
| `scratch/a10_kart_isg.sql`, `_sonuc.txt` | 162 çağrı: asıl kart, geçici kart (şimdiki saatle RPC ve Ekim'e yazılan zaman senaryoları), görevler ayrılığı, 6 rol × 8 fonksiyon yetki matrisi, kart paylaşımı eşiği, İSG belgesi ve bölge yetkisi, ileri tarihli zimmet, plansız Cumartesi ve admin görünümü (T-79, T-80 kanıtı) |
| `scratch/a10_kod/hepsi.sql` | Okunan 21 fonksiyonun ve `v_isg_durum`'un son sürümü |

**Kurulum:** Tek işlem, sonda `ROLLBACK`. Departmanlar "S10 Mavi" ve "S10 Beyaz" (amiri montaj.amiri). Geçici kart RPC'si zimmeti her zaman o anın saatiyle yazdığı için (`clock_timestamp()`), saatli senaryolar (Z1–Z7) `postgres` ile `gecici_kart_zimmet`'e yazıldı; tetikleyiciler ve kontroller aynen çalıştı. Bunun için 4 test geçici kartı (GK-T1…T4) eklendi: seed kartlarının Kasım'da zimmeti olduğu için Ekim'e açık zimmet yazılamıyor (bkz. T-83). Eski kartla okutma için 23.11 kullanıldı (kart iptali "şimdi" olduğu için). Kanıtlardaki `#n` = `a10_kart_isg_sonuc.txt`'deki çağrı numarası.

### Sonuç tablosu

| # | Konu | Ne yaptım | Beklenen | Gerçekleşen | |
|---|---|---|---|---|---|
| 1 | Aynı kart iki kişiye, aynı anda | A'da aktif K10-A'yı B'ye tanımla | Ret, anlaşılır mesaj | Ret, ham `duplicate key … kart_kart_no_key` (#3) | ✅ ret / ❌ mesaj (T-75) |
| 2 | Aynı kart iki kişiye, farklı zamanda | A'nın kartı iptal; aynı numara B'ye | Ret ya da bilinçli karar | Ret, aynı ham mesaj (#6). Numara hiçbir zaman yeniden kullanılamıyor | ✅ (T-75'teki karar) |
| 3 | Kart geçmişi | A: K10-A iptal (yenilendi), K10-A2 yeni | İki satır, kim iptal etti | İki satır; iptal eden, neden, veriliş tarihi var (#10) | ✅ |
| 4 | Kartı kim tanımladı | `kart` sütunları | İz | "Tanımlayan" sütunu yok (#11) | ❌ T-82 |
| 5 | İptal nedeni | geçersiz neden; boş neden | Ret | Geçersiz: ham `check constraint` (#8). Boş: **kabul** (#9) | ❌ T-86 |
| 6 | İkinci kez iptal | K10-A | Ret | "Aktif kart bulunamadı." (#7) | ✅ |
| 7 | Kartı değişen çalışanın eski kartıyla okutma | A 23.11: giriş eski K10-A, çıkış yeni K10-A2 | Uyarı; eski kart sayılmaz | `iptal_kart` işareti, `iptal_kart_okutma` uyarısı; gün `giris_yok` sorusu (#13) | ✅ |
| 8 | İptal kartla bütün gün | B 23.11: iki okutma iptal kartla | Uyarı | 2 uyarı; gün `hic_kayit_yok` sorusu (#14) | ✅ |
| 9 | Geçici kart aynı anda iki kişiye | GK-04 C'de açıkken D'ye; GK-02 Burak'ta açıkken D'ye | Ret, anlaşılır mesaj | "GK-04 kartı AdC Deneme'ye 22.11.2026 15:29'da verilmiş zimmetle çakışıyor (henüz iade edilmedi)." (#16, #18) | ✅ |
| 10 | Bir kişiye aynı anda iki geçici kart | C'de GK-04 açıkken GK-03 | Ret, anlaşılır mesaj | Ret; ama mesaj GK-03'ü değil GK-04'ü anlatıyor, "bu çalışanda zaten açık kart var" demiyor (#17) | ✅ ret / ❌ mesaj T-86 |
| 11 | Olmayan geçici kart / çalışan | id 99999; çalışan 99999999 | Türkçe ret | Ham `foreign key` (#19–20) | ❌ T-86 |
| 12 | İade | İSG, amir, güvenlik; ikinci kez | Yalnızca güvenlik / İK | İSG ve amir "yetkiniz yok"; güvenlik OK; ikinci kez "Açık zimmet bulunamadı." (#21–24) | ✅ |
| 13 | İadeden sonra yeniden verme | GK-04 → D | Kabul | Kabul (#25) | ✅ |
| 14 | Doğrudan yazma | güvenlik zimmet UPDATE, geçici kart UPDATE | Ret | 2/2 `permission denied` (#26–27) | ✅ |
| 15 | Geçici kartı kayıp / iptal yapmak | fonksiyon arandı | Bir yol olmalı | Fonksiyon yok, tablo yazılamıyor (#28) | ❌ T-85 |
| 16 | Zimmet saatindeki okutma | Z1: zimmet 07:30–17:30, okutma 07:55 / 17:05 | E'ye yazılır | `tamam 07:55–17:05` (#127) | ✅ |
| 17 | Zimmetten önceki okutma | Z2: zimmet 08:10, giriş 07:58 | Uyarı | `bilinmeyen_kart`, `gecici_kart_zimmetsiz` uyarısı; gün `giris_yok` sorusu (#127–129) | ✅ kural / ⚠️ T-83 |
| 18 | İadeden sonraki okutma | Z3: iade 12:00, çıkış 17:05 | Uyarı | Aynı; gün `cikis_yok` sorusu (#127–129) | ✅ |
| 19 | İade edilmeyen kart | Z4: 16.10 07:30, iade yok; asıl kartı da 12:00'de okutuldu | Uyarı | `gecici_kart_iade_edilmedi` ve `gecici_kart_cakisma` ("kartı başkası kullanıyor olabilir") (#129). Ertesi gün okutma yine E'ye yazılıyor | ✅ |
| 20 | Gece vardiyası, zimmet gece yarısını geçer | Z5: N1 V3, zimmet 21:45 – 06:15, okutma 21:55 / 06:05 | Gün tamam | `13.10 tamam 21:55–06:05` (#130) | ✅ |
| 21 | Gece, güvenlik çıkıştan önce iade alır | Z6: iade 05:50, çıkış 06:05 | Uyarı | `cikis_yok` sorusu, `gecici_kart_zimmetsiz` (#131) | ✅ |
| 22 | Gece, iade edilmedi | Z7: N3 14.10 21:45, iki gece | Uyarı | İki gece de tamam; `gecici_kart_iade_edilmedi` bir kez (#132) | ✅ |
| 23 | Geçmişe zimmet yazmak | GK-01'e 05.10 zimmeti (kartın Kasım'da zimmetleri var) | Kayıt girilebilmeli | Ret: "GK-01 kartı İbrahim Arslan'a 10.11.2026 … çakışıyor" (#154). RPC zaten yalnızca "şimdi"yi yazıyor | ❌ T-83 |
| 24 | İleri tarihli zimmet (sistem yolu) | `postgres`: GK-T1 → F, 31.12.2026 | Ret | **Kabul** (#155). Sonra GK-T1 bugün kimseye verilemiyor, F'ye bugün başka kart verilemiyor; mesaj "31.12.2026 08:00'de verilmiş" diyor (#156–157). GK-T1'in bugünkü okutması kimseye yazılmıyor (#162) | ❌ T-84 |
| 25 | İade tarihi tutarsız (sistem yolu) | İade verilişten önce; iade 2027'de | Ret | Önce: ham `range lower bound …` (#158). 2027: **kabul** (#159) | ❌ T-84 |
| 26 | Veren güvenlik / İK değil (sistem yolu) | veren montaj.amiri | Ret | "Geçici kartı yalnızca güvenlik ya da İK verebilir." (#160) | ✅ |
| 27 | Kart paylaşımı, eşikte | PA/PB: 5 gün, 5 sn arayla (giriş ve çıkış) | Uyarı | Uyarı: "5 farklı günde 5 saniye içinde" (#133) | ✅ |
| 28 | Kart paylaşımı, eşik + 1 sn | QA/QB: 5 gün, 6 sn | Uyarı yok | Yok (#133) | ✅ |
| 29 | Kart paylaşımı, gün eşiğinin altı | RA/RB: 4 gün 2 sn, 5. gün 2 dk | Uyarı yok | Yok (#133) | ✅ |
| 30 | Paylaşım uyarısını kim görür | 6 rol | İK (ve yönetici) | İK 2, yönetici 2; amir, güvenlik, İSG, admin 0 (#135–140) | ✅ |
| 31 | Paylaşım kararı kimde | `uyari_goruldu` 6 rol | Yalnızca İK | 5/5 "yetkiniz yok"; İK OK (#141–146) | ✅ |
| 32 | Kararın güne etkisi | İK "görüldü" dedikten sonra PB'nin günleri | Bir karar kaydı ve sonucu | Karar alanı yok (yalnızca `goruldu`); PB'nin 5 günü `tamam` kaldı; karar fonksiyonu yok (#147–148) | ❌ T-81 |
| 33 | İSG: belge yok | I1 | Uyarı, kapı kilitlenmez | 2 uyarı `isg_belgesi_yok`, "Kapı kilitlenmedi"; gün `tamam` (#113, #118) | ✅ |
| 34 | İSG: süresi dolmuş | I2 eğitim 01.10; I5 eğitim 12.10 | Uyarı | `isg_belgesi_suresi_dolmus` (#114, #117) | ✅ |
| 35 | İSG: bitiş günü sınırı | I3 muayene bitiş 13.10 | 13.10 geçerli, 14.10 dolmuş | 13.10 `doluyor`, 14.10 `dolmus` (#115) | ✅ |
| 36 | İSG: beyaz yaka | I4 belge yok | Kurala göre uyarı yok | Uyarı yok (#116); ama `v_isg_durum` "yok" gösteriyor (#121) | ⚠️ T-87 |
| 37 | İSG: aynı belge her gün | I2 iki gün okuttu | — | Belge başına bir uyarı (#114) | ⚠️ Şüphe |
| 38 | İSG: yanlış ikinci kayıt | I3'e 2027'ye kadar geçerli eğitimden sonra 01.01.2026 bitişli kayıt | Geçerli belge korunmalı ya da uyarı | `v_isg_durum` artık `dolmus` (#119–120); `isg_belge` değiştirilemez | ❌ T-87 |
| 39 | İSG: tarih aralığı | 1900, 2999 | Ret | İkisi de kabul (#102–103) | ❌ T-87 |
| 40 | İSG: tür, boş tarih, çıkmış çalışan | | Ret | 3/3 Türkçe ret (#100–101, #42) | ✅ |
| 41 | İSG belgesini kim girer | 6 rol + doğrudan INSERT | Yalnızca İSG uzmanı | 5/5 "yetkiniz yok"; İSG OK; doğrudan `permission denied` (#67–72, #91) | ✅ |
| 42 | Bölge yetkisi olmadan giriş | I1 YG-KAPI 13.10 | Uyarı, kapı kilitlenmez | "…bölgesine yetkisi olmadan okuttu (13.10.2026 09:00). Kapı kilitlenmedi." (#112) | ✅ |
| 43 | Yetki verildikten sonra giriş | 14.10 YG-KAPI | Uyarı yok | Yok (#112: tek uyarı) | ✅ |
| 44 | Bölge yetkisi izi | ver, ikinci kez ver, kaldır, olmayanı kaldır | İz, anlaşılır mesaj | `verildi` / `kaldirildi`, yapan isg.uzmani (#111). İkinci kez ver: sessiz, iz yok (doğru). Olmayan: Türkçe ret (#110) | ✅ |
| 45 | Bölge yetkisini kim verir | 6 rol + doğrudan DELETE | Yalnızca İSG | 5/5 ret ×2 fonksiyon; doğrudan `permission denied` (#73–84, #92) | ✅ |
| 46 | `v_isg_durum`'u kim görür | amir, güvenlik, admin, İSG | İSG (+ İK, yönetici) | 0 / 0 / 0 / 196 (#123–126) | ✅ |
| 47 | `v_isg_durum`'daki `current_date` | Kod okundu (gece penceresi kapalı) | — | UTC oturumda 00:00–03:00 arası dünü kullanır; yalnızca ekran | ⚠️ T-45 notu |
| 48 | Görevler ayrılığı: güvenlik | kendine geçici kart; kendi zimmetinin iadesi | Ret | 2/2 ret (#29, #31); İK yapınca OK (#30, #32) | ✅ |
| 49 | Görevler ayrılığı: İK | kendine geçici kart; kendi kartını iptal | Ret | 2/2 ret (#33–34) | ✅ |
| 50 | Görevler ayrılığı: İK kendine kart | ik.muduru, ik.uzmani'nın kartını iptal eder; ik.uzmani kendine kart tanımlar | Ret | **Kabul** (#35–36); kimin tanımladığı yazılmıyor (#37) | ❌ T-82 |
| 51 | Görevler ayrılığı: İSG | kendi sağlık muayenesi | Ret | Ret (#38) | ✅ |
| 52 | Yetki matrisi | 6 rol × 8 fonksiyon (başarılı çağrı geri alındı) | Kart: İK; geçici kart: güvenlik + İK; İSG / bölge: İSG; uyarı: İK | 48 hücre beklenenle aynı (#43–90) | ✅ |
| 53 | İşten çıkmış çalışana kart | X çıktı; geçici kart, asıl kart, İSG belgesi | Ret | Geçici kart ve asıl kart **kabul** (#40–41), İSG belgesi ret (#42) | ❌ T-68 (yeniden doğrulandı) |
| 54 | Seed'deki zimmetler | 6 seed zimmeti listelendi | — | Hepsi geçmiş tarihli; GK-02 (Burak, 18.11) açık. Osman'ın GK-01 zimmeti 19.11 (24.11 değil). Adım 8'deki ileri tarihli zimmet (31.12) seed'den değil, o adımın kendi denemesiydi | ℹ️ |

### Kod incelemesi (Ek A)
- **`kart_tanimla` / `kart_iptal_et`:** Yalnızca İK. Çakışma ve olmayan çalışan ham kısıt hatasıyla dönüyor (T-75). İptal nedeni boş geçilebiliyor. `kart` tablosunda kartı kimin tanımladığı yok; görevler ayrılığı tetikleyicisi yalnızca `iptal_eden_id`'ye bakıyor (T-82).
- **`kart_no_cakisma_kontrol`:** Asıl kart ve geçici kart numaraları birbirine karışmıyor; doğru.
- **`gecici_kart_ver` / `gecici_kart_iade_al`:** Güvenlik ve İK. Zaman her zaman `clock_timestamp()`; geçmiş ya da ileri tarih RPC'den girilemez. Çalışanın aktifliğine bakmıyor (T-68).
- **`gecici_kart_zimmet_kontrol`:** Veren / iade alan rolü, kartın durumu, silme yasağı, değiştirilemezlik ve aralık çakışması (aynı kart ya da aynı çalışan) denetleniyor; mesajlar Türkçe ve isimli. Veriliş / iade zamanının "şimdi"den ileri olup olmadığı ve iadenin verilişten sonra olup olmadığı denetlenmiyor (T-84). Olmayan kartta `durum` boş geldiği için kontrol atlanıyor, ham FK hatasına düşüyor.
- **`okutma_sahibi`:** Önce asıl kart (durumuna bakmadan), sonra zimmet aralığı. Asıl kartın iptal sonrası okutmasını `gece_isi_isaretle` ayırıyor.
- **`gecici_kart_kontrol`:** 4 uyarı (asıl kart da okutuldu, zimmetsiz okutma, iade edilmedi, sık unutma); hepsi çalıştı.
- **`kart_paylasim_kontrol`:** Okuyucu başına zaman sırasıyla ardışık iki farklı kişi, `≤ kart_paylasim_sn`, ayda `≥ kart_paylasim_gun` farklı gün. Uyarı çiftin yalnızca birine (`least`) bağlanıyor. Sonucu yalnızca uyarı; karar fonksiyonu yok (T-81).
- **`isg_kontrol`:** Yalnızca mavi yaka; geçerli okutması olan herkes (bölgeye bakmadan). Belge "en son girilen" (`order by id desc`), en geç biten değil (T-87). Uyarı tekilliği belge başına; aynı belgeyle her gün okutma bir kez uyarılıyor.
- **`isg_belge_gir` / `isg_belge_kontrol`:** Yalnızca İSG, çalışan aktif olmalı, tür ve boş tarih denetleniyor; tarih aralığı yok. Belge değiştirilemez ve silinemez.
- **`bolge_kontrol` / `bolge_yetkisi_*`:** Departman düzeyinde yetki; ham okutma ve kapı kanıtı birlikte. İz tetikleyicisi verme ve kaldırmayı yapan kişiyle yazıyor.
- **`v_isg_durum`:** `CURRENT_DATE` (T-45 notu); bütün departmanları gösteriyor, uyarı ise yalnızca mavi yakaya.

### Bulgular

### T-81 · Kart paylaşımı şüphesinde karar verilemiyor; uyarı yalnızca "görüldü" olarak işaretleniyor, çalışanın günü değişmiyor
- **Adım:** 10 · **Önem:** Orta
- **Yer:** `pdks.kart_paylasim_kontrol` (uyarı üretir), `pdks.uyari_goruldu` (tek işlem). `uyari` tablosunda karar / sonuç alanı yok.
- **Ne oldu:**
  - PA ve PB'nin kartları 5 gün boyunca aynı okuyucuda 5 sn arayla okutuldu. Uyarı doğru üretildi (eşik ve sınırlar doğru, 6 sn ve 4 gün uyarı üretmedi).
  - Uyarı yalnızca PA'ya bağlı. Hangi günler, hangi saatler ve hangi okuyucu olduğu mesajda yok.
  - İK'nın yapabildiği tek şey `uyari_goruldu`. Sonrasında uyarıda yalnızca `goruldu = true, goren = ik.uzmani` var; "paylaşım doğrulandı / yanlış alarm" gibi bir karar ya da gerekçe yok. PB'nin 5 günü `tamam` kaldı.
  - Karar yalnızca İK'da (diğer 5 rol reddedildi): bu kısım doğru.
- **Ne olmalıydı:** Planın beklentisi "karar yalnızca İK'da". Karar verilebilmesi için (a) uyarının hangi okutmalardan çıktığını göstermesi, (b) İK'nın "paylaşım var / yok" kararını gerekçesiyle kaydedebilmesi, (c) "var" kararında ilgili günlerin İK'nın önüne düzeltme için gelmesi gerekir (çalışan aleyhine karar İK'da, KVKK m.11).
- **Kanıt:** #133 `[S10PA] Kart paylaşımı şüphesi: S10PA … ve S10PB … kartları 10.2026 ayında 5 farklı günde 5 saniye içinde arka arkaya okutuldu. Ceza değildir; İK incelemeli.` · #141–146 5 rol "yetkiniz yok", İK OK · #147 `true goren=ik.uzmani@example.com | uyari sütunları: id,tur,calisan_id,okuyucu_id,mesaj,olusturma_zamani,goruldu,goren_id,gorulme_zamani,tekillik_anahtari | PB: 12.10 tamam …; 16.10 tamam` · #148 `paylas` adlı tek fonksiyon `kart_paylasim_kontrol`.
- **Sade dille:** Sistem "bu iki kişi birbirinin kartını basıyor olabilir" diye İK'yı uyarıyor, ama İK'nın elinde yalnızca "okudum" düğmesi var. Hangi günler olduğunu bulmak için İK'nın okutmaları tek tek araması gerekir; vardığı kararı da sistemde bir yere yazamaz. Gerçekten paylaşım varsa, gelmeyen kişinin günleri "çalıştı" olarak puantaja gitmeye devam eder.
- **Öneri:** `kart_paylasim_inceleme` tablosu (çift, ay, günler, karar `var`/`yok`, gerekçe, karar veren) ya da uyarıya karar alanları; mesajda günler ve saatler; "var" kararında ilgili günler için `kayit_duzelt` listesi (otomatik devamsızlık yok, karar İK'da). Kalıcı test: yalnızca İK karar verir; karar gerekçesiz kaydedilmez.
- **Durum:** Açık

### T-82 · İK kendine asıl kart tanımlayabiliyor; kartı kimin tanımladığı hiçbir yerde yazmıyor
- **Adım:** 10 · **Önem:** Orta
- **Yer:** `pdks.kart_tanimla`; `kart` tablosu (`id, kart_no, calisan_id, durum, iptal_nedeni, verilis_tarihi, iptal_zamani, iptal_eden_id`); `kart_gorev_ayriligi` tetikleyicisi yalnızca `iptal_eden_id`'ye bakıyor.
- **Ne oldu:** İK kendi kartını iptal edemedi (doğru). Ama ik.muduru, ik.uzmani'nın kartını iptal edince ik.uzmani kendine yeni bir kart (`K10-IKU`) tanımlayabildi. Kart satırında tanımlayan kişi yok; yalnızca tarih var.
- **Ne olmalıydı:** "Kimse kendi kaydında işlem yapamaz" kuralı kart tanımlamada da geçerli olmalı. Kartı kimin tanımladığı silinemeyen bir sütunda durmalı (iptal için olduğu gibi).
- **Kanıt:** #34 `İK kendi asıl kartını iptal | Görevler ayrılığı … (kart.iptal_eden_id)` · #35 `ik.muduru, ik.uzmani'nın kartını iptal OK` · #36 `İK kendine yeni asıl kart tanımlar OK 160` · #37 `K4001/iptal verilis=2024-11-25, K10-IKU/aktif verilis=2026-11-22` · #11 `kart` sütunları.
- **Sade dille:** Kart, PDKS'de kimin geldiğini belirleyen şey. Bir İK çalışanı kendine kart tanımlayabiliyorsa, örneğin bir arkadaşının elindeki kartın numarasını kendi adına kaydedip onun okutmalarını kendi günü gibi gösterebilir. Bunu kimin yaptığı da sonradan bulunamaz.
- **Öneri:** `kart`'a `tanimlayan_id` (zorunlu, `kart_tanimla` doldurur) ve `kart_gorev_ayriligi` tetikleyicisinin argümanlarına eklenmesi. Kalıcı test: İK kendine kart tanımlayamaz; tanımlayan yazılır.
- **Durum:** Açık

### T-83 · Geçici kart zimmeti yalnızca "şu an" girilebiliyor; zimmet sisteme geç girilirse ilk okutma kayboluyor, unutulan zimmet sonradan yazılamıyor
- **Adım:** 10 · **Önem:** Düşük
- **Yer:** `pdks.gecici_kart_ver` (`verilis_zamani = clock_timestamp()`); `pdks.gecici_kart_zimmet_kontrol` (yeni zimmet açık uçlu `[veriliş, ∞)` sayıldığı için, kartın sonraki zimmetleriyle çakışıyor).
- **Ne oldu:**
  - Z2: kart 08:10'da sisteme zimmetlendi, çalışan 07:58'de okuttu. Okutma kimseye yazılmadı (`bilinmeyen_kart`, `gecici_kart_zimmetsiz` uyarısı); amire "giriş yok" soruldu.
  - Güvenlik bir zimmeti girmeyi unutursa sonradan giremiyor: RPC yalnızca şimdiki saati yazıyor; sistem yolunda da GK-01'e 05.10 zimmeti, kartın Kasım'daki zimmetleriyle çakıştığı için reddedildi.
- **Ne olmalıydı:** Uyarı doğru (kural çalışıyor). Ama sabah kapıdaki yoğunlukta "önce kart, sonra kayıt" sık olur. Güvenliğe birkaç dakika geriye tarihli zimmet (ör. en fazla 30 dk, gerekçeyle) ya da İK'ya izli bir "geçmiş zimmet" girişi yolu olmalı.
- **Kanıt:** #127 `14.10 soru_bekliyor–17:05 [giris_yok]` · #128 `14.10 07:58:00 bilinmeyen_kart` · #129 `gecici_kart_zimmetsiz: Geçici kart GK-05, kimseye zimmetli değilken 14.10.2026 07:58 saatinde okutuldu.` · #154 `GK-01 kartı İbrahim Arslan'a 10.11.2026 07:25'te verilmiş zimmetle çakışıyor (iade: 10.11.2026 17:25).`
- **Sade dille:** Güvenlik görevlisi geçici kartı verip sisteme 10 dakika sonra yazarsa, işçinin o arada bastığı giriş "sahipsiz kart" sayılıyor ve amire "bu kişi gelmedi mi?" diye soruluyor. Görevli kaydı tamamen unutursa, geriye dönüp yazmanın bir yolu yok; işçinin bütün günü sorulu kalıyor.
- **Öneri:** `gecici_kart_ver`'e isteğe bağlı `p_verilis_zamani` (şimdiden en fazla N dk önce, ayar), ya da İK için `gecici_kart_gecmis_zimmet(kart, calisan, verilis, iade, gerekce)`; tetikleyicide çakışma kontrolü kapalı aralıkla yapılsın (iade biliniyorsa `[veriliş, iade)`).
- **Durum:** Açık

### T-84 · Sistem yolunda ileri tarihli zimmet ve ileri tarihli iade kabul ediliyor; kart ileri tarihe kadar kimseye verilemiyor
- **Adım:** 10 (Adım 8 şüphesi) · **Önem:** Düşük
- **Yer:** `pdks.gecici_kart_zimmet_kontrol`: `verilis_zamani` ve `iade_zamani` için "şimdiden ileri olamaz" ve "iade verilişten önce olamaz" kontrolü yok.
- **Ne oldu:**
  - `postgres` ile GK-T1 → F, veriliş 31.12.2026 yazıldı: kabul.
  - Sonuç: GK-T1 bugün kimseye verilemiyor; F'ye bugün başka bir geçici kart verilemiyor. İkisinde de mesaj "GK-T1 kartı AdF Deneme'ye 31.12.2026 08:00'de verilmiş zimmetle çakışıyor (henüz iade edilmedi)". Güvenlik için anlaşılmaz. GK-T1'in bugünkü okutması kimseye yazılmıyor.
  - İade 05.01.2027 olarak yazıldı: kabul. İade verilişten önce: ham `range lower bound must be less than or equal to range upper bound`.
  - Not: Planın andığı "seed'deki Osman GK-01, 24 Kasım" seed'de yok: Osman'ın GK-01 zimmeti 19.11 ve iade edilmiş. Adım 8'deki ileri tarihli zimmet (31.12) o adımın kendi denemesiydi. Seed'in bugünkü zimmetlerinin hepsi geçmiş tarihli.
- **Ne olmalıydı (değerlendirme):** Evet, tetikleyici reddetmeli. RPC bu yolu zaten kapatıyor, yani bugün yalnızca seed ve migration'lar (servis rolü) etkileniyor. Ama tetikleyici son savunma hattı: seed'deki bir yazım hatası (yanlış yıl) demo verisinde bir kartı aylarca kilitler ve hatayı bulmak zordur.
- **Kanıt:** #155 `doğrudan INSERT: GK-T1 → F, verilis 31.12.2026 | OK eklendi` · #156–157 çakışma mesajları · #158 `HATA 22000: range lower bound …` · #159 `iade ileri tarihte (2027) | OK güncellendi` · #161 `GK-T1 31.12.2026 08:00→05.01.2027 08:00` · #162 `GK-T1 bugün okutulsa kime yazılır | kimse`.
- **Sade dille:** Biri veritabanına doğrudan yanlış yılla bir zimmet yazarsa, o geçici kart o tarihe kadar kimseye verilemez; güvenlik ekranda "kart 31 Aralık'ta verilmiş" gibi anlamsız bir hata görür. Ekrandan bu hata yapılamıyor; yalnızca örnek veri ya da bakım betikleri için risk.
- **Öneri:** Tetikleyiciye: `new.verilis_zamani <= now() + interval '5 minutes'`, `new.iade_zamani is null or (new.iade_zamani >= new.verilis_zamani and new.iade_zamani <= now() + interval '5 minutes')`, Türkçe mesajla. Kalıcı test: ileri tarihli veriliş ve iade reddedilir.
- **Durum:** Açık

### T-85 · Kaybolan geçici kart sistemde "kayıp" yapılamıyor
- **Adım:** 10 · **Önem:** Düşük
- **Yer:** `gecici_kart.durum` (`aktif` / kayıp / iptal) ve tetikleyici "kayıp ya da iptal kart verilemez" kuralını biliyor; ama durumu değiştiren fonksiyon yok, `authenticated`'ın tabloya yazma yetkisi yok.
- **Ne oldu:** Güvenlik GK-05'i `kayip` yapmayı doğrudan UPDATE ile denedi: `permission denied`. Bunu yapan bir `security definer` fonksiyon aranınca: yok.
- **Ne olmalıydı:** Geçici kart kaybolunca güvenlik ya da İK kartı `kayip` yapabilmeli; böylece kart yeniden verilmez, okutulursa uyarı çıkar (asıl kartta `iptal_kart_okutma` gibi).
- **Kanıt:** #27 `gecici_kart UPDATE kayıp (güvenlik) | HATA 42501: permission denied for table gecici_kart` · #28 `geçici kartı kayıp / iptal yapan fonksiyon var mı | OK yok`.
- **Sade dille:** Bir geçici kart kaybolursa sistemde bunu işaretlemenin yolu yok. Kart hâlâ "kullanılabilir" görünür; bulan biri kullanırsa okutmalar son zimmet sahibine ya da "sahipsiz karta" yazılır.
- **Öneri:** `gecici_kart_durum(p_kart_id, p_durum, p_neden)` (güvenlik / İK, açık zimmeti varken kayıp yapılırsa zimmeti de kapatsın) ve `kayip` karttaki okutmaya uyarı.
- **Durum:** Açık

### T-86 · Kart ve geçici kart işlemlerinde ham ya da yanıltıcı mesajlar; iptal nedeni boş geçilebiliyor
- **Adım:** 10 · **Önem:** Düşük
- **Yer:** `pdks.kart_iptal_et`, `pdks.gecici_kart_ver`, `pdks.gecici_kart_zimmet_kontrol`.
- **Ne oldu:**
  - Aynı çalışana ikinci geçici kart (GK-03, çalışanda GK-04 açık): ret doğru, ama mesaj "GK-04 kartı AdC Deneme'ye … verilmiş zimmetle çakışıyor". Güvenlik GK-03'ü vermeye çalışıyor; mesaj "bu çalışanda zaten açık geçici kart var (GK-04)" demiyor.
  - Olmayan geçici kart / çalışan: ham `foreign key constraint "gecici_kart_zimmet_…_fkey"`.
  - Geçersiz iptal nedeni: ham `check constraint "kart_iptal_nedeni_check"`. Boş neden: kabul; kartın neden iptal edildiği bilinmiyor.
- **Ne olmalıydı:** Türkçe, işlemi yapanın anlayacağı mesajlar; iptal nedeni zorunlu ve listeden.
- **Kanıt:** #17, #19–20, #8, #9.
- **Sade dille:** Güvenlik görevlisi yanlış bir şey yaptığında ekranda İngilizce bir veritabanı hatası ya da başka bir kartı anlatan bir mesaj görüyor. Kartın neden iptal edildiği de boş bırakılabiliyor; sonra "kayıp mıydı, yenilendi mi?" sorusunun cevabı olmuyor.
- **Öneri:** Tetikleyicide çakışma "aynı çalışan" ise ayrı mesaj; `gecici_kart_ver`'de kart ve çalışan var mı kontrolü; `kart_iptal_et`'te neden zorunlu ve geçerli değerlerin listesiyle Türkçe hata (T-16, T-36, T-75 ile birlikte).
- **Durum:** Açık

### T-87 · İSG belgesinde "son girilen kayıt" geçerli sayılıyor; yanlışlıkla girilen eski tarihli belge geçerli belgeyi geçersiz kılıyor, tarih aralığı yok
- **Adım:** 10 · **Önem:** Düşük
- **Yer:** `pdks.isg_kontrol` ve `pdks.v_isg_durum`: `order by b.id desc limit 1`; `pdks.isg_belge_gir`: tarih aralığı yok; `isg_belge` değiştirilemez ve silinemez.
- **Ne oldu:**
  - I3'ün 2027'ye kadar geçerli İSG eğitimi varken 01.01.2026 bitişli ikinci bir kayıt girildi: kabul. `v_isg_durum` I3'ü `dolmus` gösteriyor. Kayıt silinemediği için tek düzeltme, geçerli belgeyi yeniden girmek.
  - Bitiş 01.01.1900 ve 31.12.2999 kabul.
  - Beyaz yaka I4 için uyarı yok (kurala uygun: `isg_kontrol` yalnızca mavi yaka), ama `v_isg_durum` I4'ü "yok" gösteriyor; ekran ile uyarı aynı şeyi söylemiyor.
- **Ne olmalıydı:** Geçerli belge, son girilen değil en geç biten belge olmalı (ya da yeni kayıt eskisinden önce bitiyorsa uyarı). Tarih makul bir aralıkta olmalı. `v_isg_durum` hangi yakanın izlendiğini göstermeli.
- **Kanıt:** #119 `I3 eğitim, eski tarihli ikinci kayıt (01.01.2026) OK` · #120 `v_isg_durum I3 eğitim | dolmus bitiş=2026-01-01` · #102–103 `OK` · #116 I4 uyarı `-` · #121 `isg_egitimi=yok, saglik_muayenesi=yok`.
- **Sade dille:** İSG uzmanı eski bir sertifikayı sisteme sonradan girerse, çalışanın yeni ve geçerli sertifikası yok sayılıyor ve çalışan "eğitimi dolmuş" listesine düşüyor. Tersine, bitiş tarihine yanlışlıkla 2999 yazılırsa o çalışan hiçbir zaman uyarı listesine girmiyor.
- **Öneri:** `order by b.gecerlilik_bitis desc, b.id desc`; `isg_belge_gir`'de bitiş "bugün − 10 yıl … bugün + 10 yıl" aralığında olsun ve yeni kayıt mevcut geçerli belgeden önce bitiyorsa Türkçe uyarı versin. `v_isg_durum`'a `izleniyor` (mavi yaka) sütunu.
- **Durum:** Açık

### T-88 · İSG uyarısı okutmanın nerede yapıldığına bakmıyor; yüksek gerilim laboratuvarına giriş ile sıradan PDKS okutması aynı uyarıyı veriyor
- **Adım:** 10 · **Önem:** Görüş
- **Yer:** `pdks.isg_kontrol`: "okutan" listesi o günün bütün geçerli PDKS okutmaları ve kapı kanıtlarından çıkıyor; okuyucunun bölgesi (`okuyucu.bolge_id`) kullanılmıyor. Uyarı tekilliği belge başına (`isg_dolmus:<belge_id>`, `isg_yok:<calisan>:<tür>`).
- **Ne oldu:** I1'in (belgesi yok) 13.10'da hem PDKS-1'de hem YG-KAPI'da (Yüksek Gerilim Test Laboratuvarı) okutması var. İSG uyarısı "çalışan 13.10.2026 günü okuttu" diyor; nerede okuttuğunu söylemiyor. Yalnızca PDKS-1'de okutan I2'nin (eğitimi dolmuş) uyarısı da aynı biçimde. Laboratuvara giriş ayrıca yalnızca "bölge yetkisi yok" uyarısı olarak çıkıyor (I1'in departmanının yetkisi olmadığı için); departmanın yetkisi olsaydı belgesi olmayan birinin laboratuvara girişi için ayrı bir işaret olmayacaktı.
- **Ne olmalıydı:** Hata değil, tasarım kararı. Ama İSG açısından risk aynı değil: eğitimi ya da muayenesi dolmuş birinin yüksek gerilim alanına girmesi, fabrikaya girmesinden daha acil. Riskli bölgedeki okutma ayrı (ve her seferinde) uyarı üretebilir.
- **Kanıt:** `a10_kart_isg_sonuc.txt` #113 `isg_belgesi_yok: S10I1: İSG eğitimi kaydı yok; çalışan 13.10.2026 günü okuttu. Kapı kilitlenmedi.` · #112 `S10I1: Yüksek Gerilim Test Laboratuvarı bölgesine yetkisi olmadan okuttu (13.10.2026 09:00). Kapı kilitlenmedi.` · #114 I2 aynı biçimde · kod: `isg_kontrol` içinde `okuyucu` / `bolge` birleşimi yok.
- **Sade dille:** Sistem "bu işçinin İSG eğitimi dolmuş ama işe geldi" diyor; işçi ister yemekhaneye ister yüksek gerilim laboratuvarına girmiş olsun, uyarı aynı. Üstelik aynı belge için uyarı bir kez çıkıyor; işçi sonraki günlerde riskli alana girse de yeni uyarı gelmiyor. İSG uzmanı en tehlikeli durumu ayırt edemiyor.
- **Öneri:** İSG uzmanı ile karar. Seçenek: bölgeye `isg_belgesi_gerekli` alanı; bu bölgelerdeki okutmada belgesi yok ya da dolmuşsa her okutma için ayrı uyarı (`isg_riskli_bolge_girisi`, tekillik okutma başına), mesajda bölge ve saat. Kapı yine kilitlenmez.
- **Durum:** Açık

### T-45 bağlantısı: `v_isg_durum`'daki `current_date`
Kod okunarak değerlendirildi, gece penceresinde çalıştırılmadı. Ayrıntı ve önem T-45'in altındaki "Adım 10 notu"nda: yalnızca ekrandaki İSG listesi etkileniyor (00:00–03:00 arası dünün tarihi), uyarılar etkilenmiyor.

### T-68 ile karşılaştırma
İşten çıkmış çalışana geçici kart (#40) ve asıl kart (#41) yine verilebildi; İSG belgesi ise reddedildi (#42: `isg_belge_gir` çalışanın aktif olmasını şart koşuyor). Yani üç kart / belge fonksiyonundan yalnızca biri çıkışı biliyor. T-68'in önerisi (ortak "çalışan aktif ve çalışma tarihleri içinde" kontrolü) `gecici_kart_ver` ve `kart_tanimla` için de geçerli; asıl kartta bu, çıkmış kişinin fabrikaya girebilmesi demek.

### Bulgular önem sırasıyla
1. **T-81** · Orta · Kart paylaşımı şüphesinde karar verilemiyor; gün değişmiyor.
2. **T-82** · Orta · İK kendine kart tanımlayabiliyor; tanımlayan yazılmıyor.
3. **T-83** · Düşük · Zimmet yalnızca "şu an"; geç girilen zimmetin ilk okutması kayboluyor, unutulan zimmet yazılamıyor.
4. **T-84** · Düşük · Sistem yolunda ileri tarihli zimmet / iade kabul; kart kilitleniyor.
5. **T-85** · Düşük · Geçici kart kayıp yapılamıyor.
6. **T-87** · Düşük · İSG'de son girilen belge geçerli; tarih aralığı yok.
7. **T-86** · Düşük · Ham / yanıltıcı mesajlar; iptal nedeni boş geçilebiliyor.
8. **T-88** · Görüş · İSG uyarısı bölgeye bakmıyor; riskli bölgeye giriş ayrıca işaretlenmiyor (onaydan sonra şüpheden alındı).

Yeniden görülen eski bulgular: T-68 (çıkmış çalışana kart ve geçici kart), T-75 (kart numarası çakışmasında ham mesaj; iptal kart numarası yeniden kullanılamıyor), T-16 (ham kısıt mesajları), T-45 (`v_isg_durum`).

### Denediklerim
- 162 çağrı (`scratch/a10_kart_isg_sonuc.txt`).
- Asıl kart: aynı numara aynı anda ve farklı zamanda, iptal (ikinci kez, geçersiz ve boş neden), kart geçmişi, kartı değişen çalışanın eski kartıyla okutma, iptal kartla bütün gün.
- Geçici kart: aynı kart iki kişiye, iki kart bir kişiye, açık seed zimmeti, olmayan kart / çalışan, iade yetkisi ve ikinci iade, doğrudan yazma, kayıp yapma.
- Zaman senaryoları: zimmet içinde, zimmetten önce, iadeden sonra, iade edilmeyen (asıl kart da okutuldu), gece vardiyasında gece yarısını geçen zimmet (normal, erken iade, iade yok), geçmişe zimmet, ileri tarihli veriliş ve iade, iade verilişten önce, yetkisiz veren.
- Kart paylaşımı: eşikte (5 sn, 5 gün), eşik + 1 sn, 4 gün; kim görür (6 rol), kim karar verir (6 rol), kararın güne etkisi.
- İSG: belge yok, dolmuş, bitiş günü sınırı, beyaz yaka, aynı belgeyle iki gün, eski tarihli ikinci kayıt, tarih aralığı, tür / boş / çıkmış çalışan, kim girer (6 rol + doğrudan), `v_isg_durum`'u kim görür.
- Bölge: yetkisiz giriş, yetki sonrası giriş, ver / ikinci kez ver / kaldır / olmayanı kaldır ve iz, kim verir (6 rol × 2 + doğrudan).
- Görevler ayrılığı: güvenlik (kendine kart, kendi iadesi), İK (kendine geçici kart, kendi kartını iptal, kendine kart tanımlama), İSG (kendi belgesi).
- Yetki matrisi: 6 rol × 8 fonksiyon (başarılı çağrılar geri alındı).
- Eksik eklemeler için kanıt: plansız Cumartesi (T-79), admin'in çalışan görünümü (T-80).

### Denemediklerim
- **Ekrandan (HTTP) çağrı:** Hepsi SQL ile rol taklidi.
- **İki güvenlik görevlisinin aynı anda aynı kartı vermesi:** Tetikleyicide kilit yok (`for update` ya da `exclude` kısıtı değil, `select … limit 1`); eşzamanlı iki INSERT'in ikisinin de geçebileceği düşünülüyor ama denenmedi.
- **Kart paylaşımında ay sınırı ve mükerrer okutma:** Ayın son günleriyle sonraki ayın ilk günlerine bölünen paylaşım ve mükerrer işaretli okutmanın sayılmaması denenmedi (kod okundu).
- **Kapı okuyucusundaki (kanıt) paylaşım:** `kart_paylasim_kontrol` yalnızca PDKS okuyucularına bakıyor; kapıda paylaşım denenmedi.
- **`v_isg_durum` gece penceresi:** Yalnızca kod okundu (planın istediği gibi).
- **Bölge yetkisinin geçmiş güne etkisi:** Yetki kaldırıldıktan sonra o güne ait eski okutmalar için gece işi yeniden çalışırsa ne olduğu.
- **`sik_kart_unutma` uyarısı (ayda 3 geçici kart):** Bu adımda denenmedi.

### Şüpheler
- **Aynı belgeyle her gün okutma yalnızca bir kez uyarılıyor:** `isg_dolmus:<belge_id>` tekilliği yüzünden, eğitimi dolmuş biri aylarca çalışsa da tek uyarı çıkıyor. İK uyarıyı "görüldü" yaptıktan sonra hatırlatma yok. Bilinçli olabilir (uyarı yorgunluğu), belgede yazmıyor.
- **İSG uyarısı bölgeye bakmıyor:** → T-88 olarak bulgulara alındı. Belgesi dolmuş biri sıradan PDKS'de okutsa da yüksek gerilim laboratuvarına girse de aynı uyarı çıkıyor. Riskli bölgeye girişin ayrıca işaretlenmesi beklenebilir.
- **Paylaşım uyarısı yalnızca çiftin birine bağlı:** `calisan_id = least(a, b)`. Çalışan bazlı uyarı listesinde (ör. PB'nin sayfası) uyarı görünmeyebilir.
- **Eski kartla gelen çalışanın günü sorulu kalıyor:** Doğru davranış (iptal kart sayılmaz), ama amire giden soru "giriş yok"; uyarıdaki "iptal kartla okuttu" bilgisi soruya eklenmiyor. Amir "geldi" derse gün düzeliyor; amirin bunu bilmesi kolaylaşabilir.
- **Bölge yetkisini veren İSG uzmanı kendi departmanına da yetki verebilir:** Departman düzeyinde olduğu için görevler ayrılığı kapsamına girmiyor; bilinçli kabul edilebilir.

---

## Adım 11 — İşe giriş / işten çıkış, kullanıcılar, ayarlar (22 Kasım 2026)

**Başlangıç:** `main` @ `79ad042` (31 migration). Yerel veritabanı `supabase db reset` ile kuruldu. Raporun commit edilmemiş hali önce yedeklendi (`scratch/a11_rapor_yedek_reset_oncesi.md`); sıfırlamadan önce ve sonra özeti aynı.

**Betikler:**

| Betik | Ne sınıyor |
|---|---|
| `scratch/a11_giris_cikis.sql`, `_sonuc.txt` | 182 çağrı: giriş zinciri, yeniden ekleme, 11 çıkış senaryosu, çıkış sonrası işlemler, kilitli ay, kullanıcı yetkisi / rol / pasiflik / görevler ayrılığı |
| `scratch/a11_ek.sql`, `_sonuc.txt` | 69 çağrı: ayar sınırları ve etkisi (admin rolü bozulmadan), zincirin doğru sırası, çıkış sonrası soru / geçici kart / iptal kart, kilitli ayda çıkışın ayrıntısı |
| `scratch/a11_kod/*.sql` | Okunan 20 fonksiyonun son sürümü (`pg_get_functiondef`) |

**Kurulum:** Hepsi tek işlem, sonda `ROLLBACK`. Departmanlar "S11 Deneme" (amiri montaj.amiri), "S11 Amirli" (amiri yeni A1 hesabı), "S11 Rol" (amiri yeni B1 hesabı). Yeni hesaplar için yerel `auth.users`'a e-postayla satır eklendi; `kullanici_ekle` üçünü de kendiliğinden bağladı. Günler: 14–18 Eylül (kilitlendi), 12–21 Ekim (17 Ekim Cumartesi). Kanıtlardaki `#n` = sonuç dosyasındaki çağrı numarası (`G` = `a11_giris_cikis_sonuc.txt`, `E` = `a11_ek_sonuc.txt`).

### Sonuç tablosu

| # | Konu | Ne yaptım | Beklenen | Gerçekleşen | |
|---|---|---|---|---|---|
| 1 | Zincir | E1 `calisan_ekle` (giriş 14.10) → `kart_tanimla` → okutmalar 12–16.10 → amir 12–16.10 planı girer → İK onaylar → gece işi | 14–16.10 işlenir, 12–13.10 işlenmez | 14–16.10 `tamam`, 12–13.10 gün kaydı yok (E#30–46) | ✅ |
| 2 | Zincir, plan önceden | E3: plan önceden, gece işi 12–16.10 | Aynı | Aynı. 12–13.10'daki 4 okutma sessizce yok sayıldı, uyarı yok (E#47) | ✅ (uyarı yok: Şüphe) |
| 3 | Girişten önceki planlar | 4 plan girişten önce | Ay kilidine engel olmamalı | `ay_kilitle` bu planları sayımdan çıkarıyor (kod: `vp.tarih >= c.ise_giris_tarihi`) | ✅ (kod) |
| 4 | Plan onayı okutmadan önce | İlk betikte plan onayı okutmalardan önce yapıldı | — | Onay geçmiş günü hemen işledi (`soru_bekliyor`, okutma yok); sonra gelen okutma kullanılmadı (G#34, #48) | ⚠️ T-19 ile aynı kök |
| 5 | İleri tarihli giriş | E2 giriş 15.12.2026: girişten önce plan, izin, geçici kart | Ret ya da uyarı | Üçü de kabul (G#18–20) | ❌ T-68 |
| 6 | Giriş tarihi aralığı | 01.01.2099 ve 01.01.1900 | Ret | İkisi de kabul (G#21–22) | ❌ T-75 |
| 7 | Aynı sicil | "S11E1", " S11E1 " | Anlaşılır hata | "Bu sicil numarası başka bir çalışanda kayıtlı: Ad Zincir." (G#23–24) | ✅ |
| 8 | Aynı sicil, küçük harf | "s11e1" | Ret | Kabul, ikinci çalışan (G#25) | ❌ T-75 |
| 9 | Ayrılmış çalışanın sicili | X1 çıktıktan sonra "S11X1" | Anlaşılır hata | "işten ayrılmış bir çalışana ait; yeniden işe giriş desteklenmiyor" (G#90) | ✅ |
| 10 | Aynı kart numarası | E2'ye E1'in kartı; E2'ye X1'in iptal kartı | Anlaşılır hata | Ham İngilizce `duplicate key … kart_kart_no_key` (G#28, #82) | ❌ T-75 |
| 11 | Kartın diğer kontrolleri | aktif kartı varken ikinci kart; geçici kart numarası; olmayan çalışan | Ret | İlk ikisi Türkçe; olmayan çalışan ham `foreign key` (G#29–31) | ✅ / ❌ T-75 |
| 12 | Çıkış günü ertesi gece işleniyor | X1 çıkış 14.10, 14.10 işlenmeden; sonra gece işi | 14.10 işlenir | 14.10 işlendi (`izinli`: çıkış gününü kapsayan izin, T-54) (G#43) | ✅ |
| 13 | Sonraki planlar silinir | X1 | 15.10 sonrası planlar silinir | 9 plan silindi; 12–14.10 kaldı (G#38–39) | ✅ |
| 14 | Kart iptal | X1 | `iptal/isten_cikis` | Aynen | ✅ |
| 15 | Hesap pasif | X1'in İK hesabı | `aktif=false`, RPC çalışmaz | Pasif; gün kaydı 0, `izin_gir` "Oturum bulunamadı" (G#87–88). `ayar_al` hâlâ çalışıyor (T-09) | ✅ |
| 16 | İzinler iptal | X1: 14–15.10, 19–20.10, 10–12.12 | Sonrakiler iptal | 2 iptal; çıkış gününü kapsayan 14–15.10 olduğu gibi kaldı (belgeye uygun) | ✅ |
| 17 | FM talebi iptal | X1 01.12 talebi | İptal | İptal | ✅ |
| 18 | İşlenmiş gün, okutmalı, çıkıştan sonra | X2: 15.10 okutmalı ve işlenmiş, çıkış 14.10 | Ret | "Çıkış tarihinden sonra çalışılmış gün var (15.10.2026)" (G#56) | ✅ |
| 19 | Okutma yüklü, gün işlenmemiş | X3: 15.10 okutması yüklü, gece işi çalışmamış; çıkış 14.10 | Ret | **Kabul.** Sonra gece işi 15.10'u X3 için hiç işlemedi; 2 okutma kayboldu, uyarı yok (G#45–47) | ❌ T-65 |
| 20 | Plansız gün okutması | X4: 17.10 Cumartesi plansız okutma; çıkış 16.10 | Ret | Kabul (G#58) | ❌ T-65 |
| 21 | Açık geçici kart zimmeti | X5 GK-01 | Ret | "iade edilmemiş geçici kart var (GK-01, …)"; iadeden sonra kabul (G#60–62) | ✅ |
| 22 | Çıkıştan sonraki işlenmiş günler | X5, X6: 15–17.10 "hiç kayıt yok" | `vardiya_yok`, sorular kapanır | 3 gün `vardiya_yok`, 3 soru `kapandi` (G#63, #65) | ✅ |
| 23 | Çıkıştan önceki açık soru | X6 13.10 (`cikis_yok`, eskale) | Açık kalır, cevaplanabilir | Açık kaldı; amir cevapladı, gün `tamam` (E#51–52) | ✅ |
| 24 | Açık itiraz | X6: 12.10 ve 16.10 itirazları | Çıkıştan sonraki günün itirazı kapanmalı ya da İK'ya bildirilmeli | İkisi de `acik` kaldı; 16.10 (`vardiya_yok`) itirazı kabul edilebildi; o güne yeni itiraz girilebildi (G#65–70) | ❌ T-69 |
| 25 | Çıkış doğrulamaları | ileri tarih, girişten önce, boş, amir, admin, kendi kaydı, ikinci kez | Ret | 7/7 Türkçe mesajla ret (G#71–77) | ✅ |
| 26 | Çıkıştan sonra yeni işlem | X1: plan 21.12, izin 20–25.12, yeni kart, geçici kart | Ret | Plan, izin, yeni kart, geçici kart kabul (G#78–81, E#53). FM talebi plan olmadığı için ret (G#83) | ❌ T-68 |
| 27 | İptal kartla okutma | X8: kart çıkış girilince iptal, sonra okutma | Uyarı | `iptal_kart_okutma` uyarısı (E#58) | ✅ |
| 28 | İptal kartla okutma, kart iptalinden önce | X1: çıkış 14.10 (22.11'de girildi); 20.10 okutma | Uyarı ya da ret (çıkıştan sonra çalışmış) | Uyarı yok; gün yok (G#86) | ❌ T-65 |
| 29 | Kilitli ay, sonrası okutmalı | L1 çıkış 15.09, 16–18.09 okutmalı | Ret | Ret (G#102) | ✅ |
| 30 | Kilitli ay, sonrası okutmasız | L2 çıkış 15.09, 16–18.09 "hiç kayıt yok" | Gün değişmez, fark satırı; kilitli ayın verisi değişmez | Gün değişmedi, 3 fark düzeltmesi Ekim'e yazıldı, puantaj satırı aynı. **Ama 16–18.09 vardiya planları silindi** (E#63–68) | ❌ T-67 |
| 31 | Yanlış çıkışı geri alma | yeni fonksiyon, aynı sicille ekleme, İK `UPDATE`, admin yeni hesap | Bir yol olmalı | Yol yok: fonksiyon yok, sicil reddi, `permission denied`, "aktif değil" (G#90–92, #97) | ❌ T-66 |
| 32 | `kullanici_ekle` / `kullanici_guncelle` yetkisi | 5 rol × 2 fonksiyon; admin ve İK doğrudan `UPDATE` | Yalnızca admin | 10/10 "yetkiniz yok"; 2/2 `permission denied` (G#107–118) | ✅ |
| 33 | Hesap doğrulamaları | geçersiz rol, bozuk e-posta, büyük harfli mevcut e-posta, hesabı olan çalışan, admin kendi çalışanı, pasif üst amir | Ret | 6/6 Türkçe mesajla ret (G#119–125) | ✅ |
| 34 | Rol değişikliği anında mı | kalite.amiri → ik; aynı oturumla tekrar | Hemen | Önce 0 gün, `izin_gir` ret; sonra 74 gün, `izin_gir` OK (G#126–130) | ✅ |
| 35 | Admin kendine İK rolü | `kullanici_guncelle(admin, 'ik')` | Ret | "kendi hesabınızı değiştiremezsiniz" (G#124) | ✅ |
| 36 | Admin başkasına İK rolü | kalite.amiri → ik | Bilinçli karar ya da ikinci onay | Tek başına yapıldı, iz yok (T-33) | ⚠️ T-33 |
| 37 | Admin dolaylı yoldan İK / kendi kaydı | Admin, hesabı olmayan U1 çalışanına bağlı, kendi denetlediği e-postayla `ik` hesabı açar | Engellenmeli | Açıldı; bu hesapla admin'in kendi kaydına izin girildi (G#146–148). Ayrıca bu hesap admin yapıldı ve admin'i `ik` yaptı (G#151–152) | ❌ T-72 |
| 38 | Pasif kullanıcı RPC | montaj.amiri pasif | Çalışmamalı | `vardiya_plani_gir` "Oturum bulunamadı"; gün kaydı, kullanıcı, puantaj 0; `ayar_al` 10 (T-09) (G#133–138) | ✅ |
| 39 | Çıkmış çalışanın hesabını yeniden açma | X1 çıktı; admin `kullanici_guncelle(aktif=true)` | Ret | Kabul; X1 62 gün kaydı görüyor, başkasına izin giriyor (G#93–95) | ❌ T-71 |
| 40 | Başkasının çalışan kaydına bağlama | `kullanici_guncelle` çalışanı değiştiremiyor; `kullanici_ekle` hesabı olan çalışana ret | — | Yalnızca hesabı olmayan çalışana yeni hesapla mümkün (madde 37) | ⚠️ T-72 |
| 41 | Amir hesabı pasif / rolü değişti | A1 çıktı; B1 `guvenlik` oldu; ikisi departman amiri | Departman yeni amire geçmeli ya da uyarı | Yeni sorular pasif A1'e ve güvenlik rolündeki B1'e açıldı; B1 cevaplayamıyor ("yetkiniz yok"), göremiyor (G#49–53). kalite.amiri `ik` olunca da departman amiri o kaldı (G#132) | ❌ T-70 |
| 42 | Üst amir | döngü (üretim ↔ montaj), güvenlik rolünü üst amir yapma, üst amiri kaldırma | Ret / mümkün olmalı | Döngü ve güvenlik kabul; `ust_amir_id = null` hiçbir şey değiştirmiyor (G#140–145) | ❌ T-73 |
| 43 | Kullanıcı değişikliğinin izi | geçmiş tablosu, sütunlar | İz | Yok (G#157–158), T-33 ile aynı | ❌ T-33 |
| 44 | Ayar: negatif, boş, olmayan ad | −1, null, `yok_boyle_ayar` | Ret | 3/3 Türkçe ret (E#1–3) | ✅ |
| 45 | Ayar: metin, ondalık, int taşması | 'abc', 10.5, 2147483648 | Ret | Ret, ama ham İngilizce (`invalid input syntax`, `function … does not exist`) (E#16–19). '12' metni kabul (E#17) | ✅ (mesaj ham, T-16) |
| 46 | Ayar: aşırı büyük / anlamsız | tolerans 100000 ve 2147483647, günlük 1440, yıllık 60000, gece sınırı 0, bayrak 7, yüzde 500, mola sınırları tersine, uzun mola 0, eskalasyon 0, paylaşım 0 sn | Ret | **13/13 kabul** (E#5–15, #20) | ❌ T-74 |
| 47 | Aşırı ayarın etkisi | tolerans 100000, mola_uzun 0 iken 08:00 vardiyasına 10:30 giriş | — | Geç kalma 0 (tolerans 10 iken aynı gün 150) (E#26, G#182) | ❌ T-74 |
| 48 | Ayar geri alınınca | tolerans 10'a döndü | İşlenmiş gün düzelir ya da uyarı | Gün geç kalma 0 ile kaldı (E#29) | ❌ T-74 |
| 49 | `ayar_gecmisi` | 13 değişiklik; İK dener; doğrudan `UPDATE` / `DELETE` | İz yazılır, değişmez | 13 satır, eski → yeni, yapan admin; İK ret; `permission denied`; postgres da silemiyor ve değiştiremiyor (E#22–24, G#177–180) | ✅ |

### Kod incelemesi (Ek A)
- **`calisan_ekle`:** Yetki, boşluk, departman ve aynı sicil kontrolü var. Tarih aralığı yok, sicil büyük/küçük harf duyarlı. Kart açmıyor (ayrı adım).
- **`isten_cikis_gir`:** Kontroller sırası doğru (kendi kaydı, ikinci çıkış, ileri tarih, girişten önce, zimmet). "Çıkıştan sonra çalışılmış gün" kontrolü yalnızca `gun_kaydi`'na bakıyor, `ham_okutma`'ya bakmıyor (T-65). Kilitli ay için ayrı kontrol yok; planları tarih sınırı olmadan siliyor (T-67). Açık itirazlara ve departman amirliğine dokunmuyor (T-69, T-70). Geri alma fonksiyonu yok (T-66).
- **`kullanici_ekle`:** Çalışan aktif mi, kendine hesap, ikinci hesap, e-posta tekliği kontrol ediliyor. Hesabın kime ait olduğu yalnızca admin'in seçtiği `p_calisan_id`'ye dayanıyor (T-72).
- **`kullanici_guncelle`:** Kendi hesabını değiştirme yasak. Çalışanın aktifliğine (T-71), üst amir döngüsüne ve rolüne (T-73), departman amirliğine (T-70) bakmıyor. `coalesce` yüzünden üst amir kaldırılamıyor.
- **`auth_hesabi_bagla`:** E-postayla, boş olan ve başka hesaba bağlı olmayan Auth kullanıcısını bağlıyor. Doğru çalıştı (3/3).
- **`oturum_kullanici_id`:** `kullanici.aktif` ve `calisan_id`'ye bakıyor, `calisan.aktif`'e bakmıyor (T-71'in kökü).
- **`ayar_guncelle`:** Yalnızca "var mı" ve "≥ 0". Ayar başına alt / üst sınır ya da tür (bayrak, yüzde) yok (T-74).
- **`ayar_iz`:** INSERT ve değişen UPDATE'te `ayar_gecmisi`'ne yazıyor, DELETE'i engelliyor. Aynı değer iz bırakmıyor (doğru).
- **`kendi_kaydi_engelle`:** Kişi sütununun çalışanı ile satırın çalışanını karşılaştırıyor; doğru. Ama "kişi" `kullanici.calisan_id`'den geliyor; bu bağ yanlış kurulursa (T-72) koruma işe yaramıyor.
- **`kart_tanimla`:** Çalışanın aktif olup olmadığına bakmıyor; çakışma ve olmayan çalışan ham kısıt hatasıyla dönüyor.

### Bulgular

### T-65 · Çıkış tarihinden sonraki okutma, gün henüz işlenmemişse ya da plansızsa fark edilmiyor; okutmalar sessizce kayboluyor
- **Adım:** 11 · **Önem:** Yüksek
- **Yer:** `pdks.isten_cikis_gir` (son sürüm: `20261130010000_ise_giris_cikis.sql`), "Çıkıştan sonra okutması olan gün" kontrolü yalnızca `gun_kaydi`'na bakıyor. `pdks.gece_isi_gun_kayitlari` çıkıştan sonraki günü işlemiyor.
- **Ne oldu:**
  - X3: 15.10 okutması yüklü, gece işi henüz çalışmamış. Çıkış 14.10 olarak girildi, kabul edildi. Sonra 15.10 gece işi X3 için gün açmadı; 2 okutma `ham_okutma`'da kaldı, uyarı yok.
  - X4: 17.10 Cumartesi planı yokken okutma var; çıkış 16.10 kabul edildi.
  - X1: çıkış 14.10, 22.11'de girildi; 20.10'da iptal kartıyla okutma var. `iptal_kart_okutma` uyarısı yalnızca kartın iptal **anından** sonraki okutmalara bakıyor; uyarı çıkmadı.
- **Ne olmalıydı:** Çıkış tarihinden sonra çalışanın kartıyla (ya da zimmetli geçici kartıyla) herhangi bir okutma varsa, işlenmiş olsun olmasın, çıkış reddedilmeli ya da en azından İK uyarılmalı.
- **Kanıt:** G#45 `isten_cikis_gir X3 14.10 … OK {"silinen_plan": 6, …}` · G#47 `X3 … 14.10 tamam | ham okutma 15.10: 2 | uyarı: isg_belgesi_yok` · G#58 `isten_cikis_gir X4 16.10 (17.10 plansız okutma) OK` · G#86 X1 `… 14.10 izinli | uyarı: isg_belgesi_yok` (20.10 okutması yok sayıldı). Karşılaştırma: G#56 X2 (15.10 işlenmiş) "Çıkış tarihinden sonra çalışılmış gün var".
- **Sade dille:** İK işten çıkış tarihini yanlışlıkla bir gün erken yazarsa ve o son gün henüz gece işinden geçmemişse, sistem itiraz etmiyor. Çalışanın gerçekten çalıştığı son gün puantaja hiç girmiyor, kimse de uyarılmıyor. Çalışan bir günlük ücretini kaybeder; fark ancak çalışan itiraz ederse anlaşılır, o zaman da çıkış geri alınamıyor (T-66).
- **Öneri:** Kontrol `ham_okutma` üzerinden yapılsın: `okutma_sahibi(kart_no, okutma_zamani) = p_calisan_id` ve `okutma_zamani` İstanbul saatiyle çıkış gününden (gece vardiyası penceresi dahil) sonra. `iptal_kart_okutma` uyarısı da kartın iptal anı yerine çıkış tarihine göre bakabilir. Kalıcı test: işlenmemiş günde okutma varken çıkış reddedilir.
- **Karar (Fırat, 25 Kasım):** Uyarı değil ret: çıkıştan sonra okutma varsa, gün işlenmemiş ya da plansız olsa da çıkış girilemez.
- **Durum:** ✅ Düzeltildi (feature/T65-cikis-okutma). Migration: `20261219010000_cikis_okutma.sql`, test: `cikis_okutma_testi.sql`. `isten_cikis_gir`, `cikistan_sonraki_okutma` ile `ham_okutma`'ya bakar (asıl ve geçici kart, İstanbul saati, çıkış gününün vardiya penceresi dahil). İptal edilmiş kartın iptalden sonraki okutması sayılmaz.
- **Kalan (kapsam dışı):** Çıkış girildikten **sonra** yüklenen dosyadaki okutma yine sessiz kalır; okutma kartın iptal anından önceyse `iptal_kart_okutma` uyarısı çıkmaz.

### T-66 · Yanlış girilen işten çıkış geri alınamıyor
- **Adım:** 11 · **Önem:** Orta
- **Yer:** `pdks.isten_cikis_gir`; geri alan fonksiyon yok. `pdks.calisan_ekle` ayrılmış sicili reddediyor; `authenticated`'ın `calisan` UPDATE yetkisi yok.
- **Ne oldu:** Çıkış girilince planlar silindi, kart iptal, izinler iptal, hesap pasif oldu. Geri almak için denenen 4 yolun hepsi kapalı. Çalışanın yeniden çalışması için yeni sicille yeni bir çalışan açmak gerekiyor; eski günleri eski kayıtta kalıyor.
- **Ne olmalıydı:** Yanlış çıkış için İK'nın kullanabileceği, izli bir geri alma yolu (ör. aynı gün içinde ya da ay kilitlenmeden önce) ya da en azından belgede "veritabanı yöneticisi düzeltir" diye yazılı bir prosedür.
- **Kanıt:** G#90 "yeniden işe giriş desteklenmiyor" · G#91 `permission denied for table calisan` · G#92 "Çalışan bulunamadı ya da aktif değil." · G#97 "geri alan fonksiyon: yok".
- **Sade dille:** İK yanlış kişiyi ya da yanlış tarihi işten çıkarırsa, sistemde bunu düzeltecek bir düğme yok. Çalışanın kartı iptal olur, izinleri silinir, ertesi günden itibaren puantajı oluşmaz. Ancak biri veritabanına doğrudan müdahale ederse düzelir; bu da kayıt dışı bir işlem olur.
- **Öneri:** `isten_cikis_geri_al(p_calisan_id, p_gerekce)`: yalnızca İK, ay kilitlenmemişse; çıkış tarihi ve `aktif` geri gelir, iptal edilen kart / izin / hesap özetteki gibi geri açılır ya da İK'ya liste verilir; silinen planlar için uyarı. Ya da bilinçli kabul edilip `docs/veritabani.md`'ye yazılsın.
- **Durum:** Açık

### T-67 · Çıkış kilitli aya düşerse kilitli ayın vardiya planları siliniyor
- **Adım:** 11 · **Önem:** Orta
- **Yer:** `pdks.isten_cikis_gir`: `delete from pdks.vardiya_plani where calisan_id = … and tarih > p_cikis_tarihi` (dönem kontrolü yok). `vardiya_plani`'nda silmeyi engelleyen dönem tetikleyicisi yok.
- **Ne oldu:** Eylül kilitlendi. L2'nin çıkışı 15.09 olarak girildi. Gün kayıtları kilit yüzünden değişmedi (doğru), 3 düzeltme fark olarak Ekim'e yazıldı (doğru), puantaj satırı aynı kaldı (doğru). Ama 16–18.09'un vardiya planları silindi. Kilitli Eylül'de artık planı olmayan 3 "soru bekliyor" gün var; `v_puantaj_canli` Eylül için hâlâ `bekleyen_gun: 3` gösteriyor.
- **Ne olmalıydı:** Kilitli ayın hiçbir verisi değişmemeli (CLAUDE.md §2). Ya çıkış kilitli aya düşünce kilitli günlerin planı korunmalı, ya da çıkış "kilitli aya düşüyor, fark satırı oluşacak" diye açıkça uyarılmalı.
- **Kanıt:** E#61 "9/2026 kilitlendi" · E#63 `{"silinen_plan": 3, …, "vardiya_yok_yapilan_gun": 3}` · E#64 L2 planları: `14.09,15.09` · E#66 `16.09 durum soru_bekliyor→vardiya_yok fark=true hedef_donem=2026/10` (×3) · E#68 `"bekleyen_gun":3`.
- **Sade dille:** Kapatılmış bir ayın vardiya planı, işten çıkış girilince sessizce siliniyor. Puantaj rakamları değişmiyor, ama kapanmış ayın kaydı artık kendi içinde tutarsız: planı olmayan gün için "soru bekliyor" yazıyor. Denetimde "bu kişinin 16 Eylül'de vardiyası var mıydı?" sorusunun cevabı kaybolmuş olur.
- **Öneri:** Silme `and not pdks.donem_kilitli_mi(tarih)` ile sınırlansın; ayrıca `vardiya_plani`'na kilitli dönemde DELETE / UPDATE'i engelleyen tetikleyici. Kalıcı test: kilitli aya düşen çıkıştan sonra kilitli ayın plan sayısı aynı.
- **Durum:** Açık

### T-68 · Çıkıştan sonra ve girişten önce plan, izin, kart ve geçici kart kabul ediliyor
- **Adım:** 11 · **Önem:** Düşük
- **Yer:** `pdks.vardiya_plani_gir`, `pdks.izin_gir`, `pdks.kart_tanimla`, `pdks.gecici_kart_ver`: hiçbiri işe giriş / çıkış tarihine ya da `calisan.aktif`'e bakmıyor.
- **Ne oldu:**
  - Çıkmış X1'e 21.12 planı, 20–25.12 izni ve yeni bir kart (`K11-X1B`, aktif) tanımlandı; çıkmış X6'ya geçici kart verildi.
  - Henüz işe girmemiş E2'ye (giriş 15.12) 10.12 planı, 01–05.12 izni ve geçici kart verildi.
  - Gece işi bunları yok sayıyor; puantaja yansımıyor.
- **Ne olmalıydı:** Belge (`docs/veritabani.md` satır 430) `aktif`'in yalnızca İSG ve hesap işlemlerini durdurduğunu söylüyor; yani bu davranış belgeyle çelişmiyor. Ama çalışma tarihleri dışındaki kayıt hiçbir işe yaramıyor, yalnızca yanıltıyor. Çıkmış çalışana kart ve geçici kart verilmesi ise kapıdan geçiş riski.
- **Kanıt:** G#78 `vardiya_plani_gir X1 … OK 1698` · G#79 `izin_gir X1 … OK 8` · G#81 `kart_tanimla X1 yeni kart … OK 96` · E#53 `gecici_kart_ver X6 GK-01 (çıkmış çalışan) OK` · G#18–20 E2 üçü de OK.
- **Sade dille:** İşten ayrılmış birine sistem yeni kart verdiriyor. Kartı kapıda çalışıyorsa ayrılmış kişi fabrikaya girebilir. Puantaj bozulmuyor, ama ekranda "ayrılmış kişinin Aralık'ta izni var" gibi anlamsız kayıtlar görünüyor.
- **Öneri:** Dört fonksiyona ortak bir kontrol: tarih `ise_giris_tarihi` ile `isten_cikis_tarihi` arasında olmalı; kart ve geçici kart için çalışan aktif olmalı.
- **Durum:** Açık

### T-69 · Çıkıştan sonraki güne ait itiraz açık kalıyor; `vardiya_yok` güne yeni itiraz girilip kabul edilebiliyor
- **Adım:** 11 · **Önem:** Düşük
- **Yer:** `pdks.isten_cikis_gir` soruları kapatıyor, itirazlara dokunmuyor. `pdks.itiraz_gir` / `pdks.itiraz_karar` çalışanın çıkmış olmasına bakmıyor.
- **Ne oldu:** X6'nın 16.10 günü (çıkış 14.10) itiraz açıkken `vardiya_yok` oldu; itiraz `acik` kaldı. İK bu itirazı kabul etti; o güne amir ikinci bir itiraz girdi. 12.10 (çıkıştan önce) itirazı da açık kaldı ve normal biçimde karara bağlandı (bu doğru).
- **Ne olmalıydı:** Çıkıştan sonraki günlerin açık itirazları çıkışla birlikte gerekçeyle kapanmalı ya da çıkış özetinde İK'ya sayılmalı. Kapanmış güne yeni itiraz girilmemeli.
- **Kanıt:** G#65 `itiraz: 12.10/acik, 16.10/acik` (çıkıştan sonra) · G#66 `itiraz_karar X6 16.10 … OK` · G#69 `itiraz_gir X6 16.10 (vardiya_yok gün, ikinci itiraz) OK 3` · G#70 `itiraz: 12.10/red, 16.10/acik, 16.10/kabul`.
- **Sade dille:** Çalışan ayrıldıktan sonra, ayrılık tarihinden sonraki bir gün için yapılmış itiraz kimsenin listesinden düşmüyor. İK "kabul" dese bile o gün zaten puantajda yok; kabulün bir anlamı kalmıyor (bkz. T-52).
- **Öneri:** `isten_cikis_gir`: çıkıştan sonraki günlerin `acik`/`inceleme` itirazlarını gerekçeyle kapatsın ve özete `kapatilan_itiraz` eklesin. `itiraz_gir`: `vardiya_yok` güne ve çalışma tarihi dışına itirazı reddetsin.
- **Durum:** Açık

### T-70 · Departman amirinin hesabı pasif olunca ya da rolü değişince yeni sorular ona açılmaya devam ediyor
- **Adım:** 11 · **Önem:** Orta
- **Yer:** `pdks.isten_cikis_gir` ve `pdks.kullanici_guncelle` `departman.amir_id` / `vekil_amir_id`'ye bakmıyor. Soru atayan gece işi adımı amirin aktifliğine ve rolüne bakmıyor.
- **Ne oldu:**
  - A1 ("S11 Amirli" amiri) işten çıktı, hesabı pasif oldu. Departman amiri A1 kaldı; W1'in sonraki 4 günlük sorusu pasif A1'e açıldı.
  - B1 ("S11 Rol" amiri) `guvenlik` yapıldı. W2'nin 4 sorusu B1'e açıldı; B1 cevaplayamıyor ("yetkiniz yok"), W2'nin günlerini göremiyor (0).
  - kalite.amiri `ik` yapılınca Kalite departmanının amiri o kaldı.
  - Sorular ancak `soru_eskalasyon_gun` (3 gün) sonra üst amire gidiyor (T-39'daki sınırla).
- **Ne olmalıydı:** Amir pasif olunca ya da rolü amir olmaktan çıkınca ya işlem reddedilmeli ("önce departmana yeni amir atayın"), ya da sorular vekil / üst amire gitmeli ve İK'ya uyarı çıkmalı.
- **Kanıt:** G#49 `14.10 hic_kayit_yok → a1.s11@example.com/aktif=false acik` (×4) · G#50 `S11 Amirli amir: a1.s11/aktif=false/rol=amir` · G#51 `→ b1.s11@example.com/rol=guvenlik acik` (×4) · G#52 B1 cevap: "Bu işlem için yetkiniz yok." · G#53 B1 W2 gün kaydı: 0 · G#132 Kalite amiri `kalite.amiri/ik`.
- **Sade dille:** Bir departmanın amiri emekli olunca ya da başka bir göreve geçince sistem bunu fark etmiyor. O departmanın çalışanları için "kartı okutmamış, geldi mi?" soruları, artık giriş yapamayan ya da yetkisi olmayan kişiye gidiyor. Sorular en az 3 gün kimse görmeden bekliyor; bu sırada çalışanın günü "soru bekliyor" kalıyor.
- **Öneri:** `kullanici_guncelle` (pasif ya da rol ≠ amir) ve `isten_cikis_gir`: kullanıcı bir departmanın amiri ya da vekiliyse reddetsin, ya da İK'ya `amirsiz_departman` uyarısı yazsın. Soru atamada amir aktif ve rolü `amir` değilse vekile / üst amire atansın. Açık soruların devri T-43 ile birlikte çözülebilir.
- **Durum:** Açık

### T-71 · Çıkmış çalışanın hesabı admin tarafından yeniden açılabiliyor; hesap tam yetkiyle çalışıyor
- **Adım:** 11 · **Önem:** Yüksek
- **Yer:** `pdks.kullanici_guncelle(p_aktif => true)` çalışanın `calisan.aktif` / `isten_cikis_tarihi`'ne bakmıyor. `pdks.oturum_kullanici_id` yalnızca `kullanici.aktif`'e bakıyor. (`kullanici_ekle` ise "Çalışan bulunamadı ya da aktif değil" diye reddediyor.)
- **Ne oldu:** X1 (İK rolü) 14.10'da çıktı; hesabı pasif oldu, giriş yapamadı. Admin `kullanici_guncelle(X1, aktif => true)` çağırdı, kabul edildi. X1 yeniden 62 gün kaydı görüyor ve başka bir çalışana izin girebiliyor. Bu değişikliğin izi yok (T-33).
- **Ne olmalıydı:** İşten ayrılmış çalışanın hesabı yeniden açılamamalı (`kullanici_ekle` ile aynı kural). `oturum_kullanici_id` de bağlı çalışanın aktif olmasını şart koşmalı.
- **Kanıt:** G#88 pasifken `izin_gir`: "Oturum bulunamadı…" · G#92 `kullanici_ekle çıkmış X1 için yeni hesap`: "Çalışan bulunamadı ya da aktif değil." · G#93 `kullanici_guncelle X1 hesabı aktif=true OK` · G#94 `X1 (yeniden aktif, çalışan çıkmış): gün kaydı sayısı OK 62` · G#95 `izin_gir W1 OK 9`.
- **Sade dille:** İşten ayrılan bir İK çalışanının hesabı, sistem yöneticisinin tek tıklamasıyla geri açılabiliyor. Ayrılmış kişi bütün çalışanların puantajını görebilir ve kayıt değiştirebilir (KVKK açısından ciddi). Kimin, ne zaman açtığı da hiçbir yerde yazmıyor.
- **Öneri:** `kullanici_guncelle`: `p_aktif = true` ise bağlı çalışan aktif olmalı. `oturum_kullanici_id`: `join calisan c on c.id = k.calisan_id and c.aktif`. Kalıcı test: çıkış → hesabı aç → ret; çıkış → oturum → yetki yok.
- **Durum:** ✅ Düzeltildi — PR #56 (migration: `20261211010000_cikmis_hesap.sql`, test: `cikmis_hesap_testi.sql`).
  - `kullanici_guncelle`: `p_aktif = true` iken bağlı çalışan aktif değilse ret: "Çalışan işten ayrılmış (çıkış: 14.10.2026); hesabı yeniden açılamaz."
  - `oturum_kullanici_id`: hesap aktif olsa bile bağlı çalışan aktif değilse oturum yok; bütün yetki fonksiyonları ve RLS buradan geçtiği için çıkmış çalışanın açık kalmış hesabı hiçbir şey göremez, işlem yapamaz ("Oturum bulunamadı…").
  - Temizlik: çalışanı aktif olmayan ama hesabı açık kalmış kayıtlar migration'da kapatılır.
  - Yerelde ekranda doğrulandı (Elif çıkışı girdi → Alper hesabı açtı → Ahmet İK ekranlarına girdi; düzeltmeden sonra Ahmet "Hesabınız sisteme bağlı değil", Alper'in yeniden açma denemesi hata).
  - Kapsam dışı: hesabı kimin ne zaman açtığının izi (`kullanici_gecmisi`, T-33 / T-72).

### T-72 · Admin, başka bir çalışana bağlı bir İK (ya da admin) hesabı açarak görevler ayrılığını ve "admin karar vermez" kuralını aşabiliyor
- **Adım:** 11 · **Önem:** Yüksek
- **Yer:** `pdks.kullanici_ekle`: hesabın hangi çalışana ait olduğu yalnızca admin'in seçtiği `p_calisan_id`; e-posta ile çalışanın gerçekten aynı kişi olduğuna dair bir kontrol ya da ikinci onay yok. `pdks.kendi_kaydi_engelle` bu bağa güveniyor.
- **Ne oldu:**
  1. Admin, hesabı olmayan U1 çalışanına bağlı, `sahte.s11@example.com` e-postalı, `ik` rollü bir hesap açtı (Auth hesabı o e-postayla vardı, kendiliğinden bağlandı).
  2. Bu hesapla admin'in **kendi** çalışan kaydına 28–31.12 izni girildi. Görevler ayrılığı devreye girmedi, çünkü sistem bu hesabı U1 sanıyor. İzinde "giren" olarak `sahte.s11` görünüyor.
  3. Aynı yolla açılan hesap admin yapıldı ve asıl admin hesabını `ik` yaptı. Asıl admin kendi rolünü değiştiremiyor, ama ikinci hesapla değiştirebiliyor.
- **Ne olmalıydı:** Admin hesap açabilmeli, ama İK ve admin rolü verme (ya da yükseltme) ikinci bir kişinin onayı olmadan olmamalı, ve kim verdiği silinmeyen bir izde durmalı.
- **Kanıt:** G#146 `kullanici_ekle sahte.s11 rol ik → U1 çalışanı OK 29` · G#148 `sahte (ik): sistem.yoneticisi'ne izin_gir OK 13` · G#156 `28.12–31.12 giren=sahte.s11@example.com` · G#151–152 sahte → admin, sahte: sistem.yoneticisi → ik, OK · G#155 sistem.yoneticisi (ik) montaj.amiri'ne izin OK. Karşılaştırma: G#123–124 doğrudan yollar (kendine hesap, kendine rol) reddediliyor.
- **Sade dille:** Sistem yöneticisi "kendime İK yetkisi veremem" kuralını, adı başka bir işçi olan ikinci bir hesap açarak bir dakikada aşabiliyor. O hesapla kendi kaydına izin yazabiliyor ya da istediği kişinin puantajını değiştirebiliyor. Kayıtlarda bunu yapan kişi masum bir üretim işçisi olarak görünüyor. U1 de daha sonra kendi hesabını açtıramaz, çünkü "zaten hesabı var".
- **Öneri:** (karar konusu)
  - `ik` ve `admin` rolü verme / yükseltme iki adımlı olsun: admin önerir, İK müdürü (rol `ik`, farklı kişi) onaylar.
  - T-33'teki `kullanici_gecmisi` mutlaka eklensin (kim, kime, hangi rol, hangi çalışan).
  - Hesap açılınca bağlanan çalışanın departman amirine ya da İK'ya bildirim gitsin.
  - En azından `docs/veritabani.md`'de "admin güvenilir kişidir; bu yol bilinçli açık bırakıldı" diye yazılsın.
- **Karar (Fırat, 25 Kasım):** İK ya da admin rolü verilmesi ve yükseltme iki adımlıdır: admin önerir, rolü 'ik' olan başka bir kullanıcı onaylar; onaylanana kadar hesap eski rolüyle (yeni hesapsa pasif) kalır.
- **Durum:** ✅ Düzeltildi (feature/T72-rol-onayi). Migration: `20261223010000_rol_onayi.sql`, test: `rol_onayi_testi.sql`. `rol_onerisi` (kim, kime, hangi rol, hangi çalışan, kim karar verdi), `kullanici_gecmisi` (T-33), `rol_onerisi_karar`. Öneren, hesabın sahibi ve onların çalışan kaydına bağlı kimse karar veremez. Bu roldeki pasif hesabı yeniden açmak da onaya gider. İK'nın Kullanıcılar ekranında "Onay bekleyen rol değişiklikleri" bölümü.
- **Kalan:** Sistemde başka aktif İK yoksa öneri onaylanamaz. Bağlanan çalışanın amirine bildirim (önerideki üçüncü madde) kapsam dışı.

### T-73 · Üst amir zincirinde döngü ve amir olmayan üst amir kabul ediliyor; üst amir kaldırılamıyor
- **Adım:** 11 · **Önem:** Düşük
- **Yer:** `pdks.kullanici_guncelle`: yalnızca `p_ust_amir_id = p_kullanici_id` engelleniyor; `ust_amir_id = coalesce(p_ust_amir_id, ust_amir_id)`.
- **Ne oldu:** uretim.muduru'nun üst amiri montaj.amiri yapıldı (montaj'ın üst amiri zaten uretim.muduru): döngü kabul. bobinaj.amiri'nin üst amiri `guvenlik` yapıldı: kabul. `ust_amir_id => null` çağrısı montaj'ın üst amirini değiştirmedi.
- **Ne olmalıydı:** Döngü ve `amir` rolünde olmayan üst amir reddedilmeli; üst amiri kaldırmanın bir yolu olmalı.
- **Kanıt:** G#140–142 `uretim.muduru→montaj.amiri; montaj.amiri→uretim.muduru; bobinaj.amiri→guvenlik` · G#143–145 `montaj üst=5` önce ve sonra.
- **Sade dille:** İki amir birbirinin üstü olarak girilebiliyor. Cevapsız soru bir üst amire gittiğinde ikisi arasında gidip gelir ya da güvenlik görevlisine gider; ikisi de çözmez.
- **Öneri:** Özyinelemeli sorguyla döngü kontrolü; üst amirin rolü `amir` olmalı; üst amiri kaldırmak için ayrı bir parametre (ör. `p_ust_amir_kaldir boolean`).
- **Durum:** Açık

### T-74 · Ayarlar için yalnızca "0'dan küçük olamaz" kontrolü var; yasal sınırlar ve puantaj kuralları tek çağrıyla anlamsız değerlere çekilebiliyor
- **Adım:** 11 · **Önem:** Yüksek
- **Yer:** `pdks.ayar_guncelle` (son sürüm: `20261125010000_organizasyon_ve_roller.sql`; `p_deger < 0` dışında kontrol yok). `ayar` tablosunda alt / üst sınır ya da tür sütunu yok.
- **Ne oldu:** Admin 13 değişikliğin hepsini yapabildi:
  - Yasal sınırlar: `gunluk_azami_calisma_dk` 660 → 1440 (İş Kanunu m.63: 11 saat), `fm_yillik_sinir_dk` 16200 → 60000 (m.41: 270 saat), `gece_calisma_sinir_dk` 450 → 0.
  - Puantaj: `gec_kalma_tolerans_dk` 100000 ve 2147483647, `mola_uzun_dk` 0, `mola_kisa_sinir_dk` 600 (orta sınırdan büyük).
  - Bayrak ve yüzde: `cumartesi_hafta_sonu` 7, `fm_yaklasma_uyari_yuzde` 500.
  - Diğer: `soru_eskalasyon_gun` 0, `kart_paylasim_sn` 0.
  - Etki: tolerans 100000 iken 08:00 vardiyasına 10:30'da gelen T1'in geç kalması **0**. Aynı gün tolerans 10 iken 150 dk. Ayar 10'a geri alınınca işlenmiş gün 0'da kaldı.
- **Ne olmalıydı:** Her ayarın bir aralığı olmalı (ör. tolerans 0–60, bayrak 0/1, yüzde 1–100, mola sınırları sıralı). Yasal üst sınırlar (660, 16200, 450) yasa değerinin üstüne çıkamamalı. Reddedilen metin ve ondalık değerler de Türkçe mesajla dönmeli (bugün ham İngilizce).
- **Kanıt:** E#5–15, #20 hepsi `OK` · E#23 `ayar_gecmisi … gunluk_azami_calisma_dk 660→1440 (sistem.yoneticisi@example.com); fm_yillik_sinir_dk 16200→60000 …` · E#26 `T1 21.10: … giriş 10:30, tolerans 100000 → tamam gec=0` · G#182 aynı gün tolerans 10: `gec=150` · E#29 geri aldıktan sonra `gec=0` · E#16, #18, #19 `invalid input syntax for type integer`, `function … does not exist`.
- **Sade dille:** Sistem yöneticisi bir yazım hatasıyla ("10" yerine "100000") bütün fabrikada geç kalmayı ortadan kaldırabilir, ya da yıllık fazla mesai sınırını yasanın dört katına çıkarıp sistemin yasadışı fazla mesaiyi onaylamasına yol açabilir. Hata fark edilip düzeltilse bile o arada işlenen günler yanlış kalır. İz var (`ayar_gecmisi`), ama yanlış değer girilmesini engelleyen bir şey yok. T-10'daki "ayarı yalnızca admin değiştirir" kaygısıyla birleşince risk büyüyor.
- **Öneri:** `ayar` tablosuna `en_az` / `en_cok` sütunları (yasal sınırlar için `en_cok` = yasa değeri), `ayar_guncelle`'de bu aralık kontrolü, mola sınırları için sıralama kontrolü. Puantajı etkileyen ayar değişince İK'ya uyarı. Kalıcı test: her ayarda aralık dışı değer reddedilir. T-10 kararıyla birlikte ele alınmalı.
- **Durum:** ✅ Düzeltildi (feature/T74-ayar-sinirlari). Migration: `20261212010000_ayar_sinirlari.sql`, test: `ayar_sinirlari_testi.sql`. Geri alınan ayardan önce işlenmiş günler kendiliğinden yeniden hesaplanmaz; İK uyarıda bunu görür.

### T-75 · `calisan_ekle` ve `kart_tanimla`: tarih aralığı ve büyük/küçük harf kontrolü yok, kart hataları ham İngilizce
- **Adım:** 11 · **Önem:** Düşük
- **Yer:** `pdks.calisan_ekle`, `pdks.kart_tanimla`.
- **Ne oldu:**
  - İşe giriş 01.01.1900 ve 01.01.2099 kabul edildi.
  - "s11e1" sicili, "S11E1" varken ikinci bir çalışan olarak eklendi.
  - Başka çalışanın ya da iptal edilmiş bir kartın numarası: `duplicate key value violates unique constraint "kart_kart_no_key"`. Olmayan çalışan: `violates foreign key constraint "kart_calisan_id_fkey"`.
  - İptal edilen kartın numarası bir daha hiç kimseye verilemiyor (fiziksel kart yeniden kullanılamaz).
- **Ne olmalıydı:** Tarih makul bir aralıkta olmalı (ör. şirketin kuruluşu – bugün + 1 yıl), sicil büyük/küçük harfe duyarsız tekil olmalı, kart hataları Türkçe ve kimde olduğunu söylemeli.
- **Kanıt:** G#21–22 `OK 95`, `OK 96` · G#25 `aynı sicil küçük harf "s11e1" OK 97` · G#28, #82 `duplicate key …` · G#30 `foreign key …`.
- **Sade dille:** İK bir yazım hatasıyla aynı kişiyi iki kez ekleyebilir ya da 2099 yılında işe başlayan bir çalışan yaratabilir. Kart zaten başkasındaysa ekranda İngilizce bir veritabanı hatası çıkar; İK kartın kimde olduğunu anlayamaz.
- **Öneri:** `lower(sicil_no)` üzerinde tekil index ya da kontrol; tarih aralığı kontrolü; `kart_tanimla`'da çalışan var mı ve kart kimde kontrolü (T-36 ile birlikte). İptal kart numarasının yeniden kullanımı için karar (bugünkü `kart_no` tekilliği tarihçeyi koruyor, bu bilinçli olabilir).
- **Durum:** Açık

### T-79 · Planı olmayan günde (ör. Cumartesi) yapılan çalışma hiçbir yere yazılmıyor
- **Adım:** 11 (Adım 10 betiğinde yeniden doğrulandı) · **Önem:** Yüksek
- **Yer:** `pdks.gece_isi_gun_kayitlari`: gün kaydı yalnızca `vardiya_plani` satırı olan çalışana açılıyor. Fazla mesai havuzu (`fazla_mesai_inceleme`) ve fazla mesai uyarıları gün kaydından üretiliyor.
- **Ne oldu:**
  - X4 (Adım 11) ve S1 (Adım 10): hafta içi planlı, 17.10 Cumartesi planı yok. Cumartesi 08:00–13:00 iki geçerli okutma (işaretsiz).
  - Gece işi 17.10 `basarili`. Gün kaydı yok, havuz kaydı yok, fazla mesai uyarısı yok. S1'in yazılı fazla mesai onayı olduğu halde de aynı.
  - Tek uyarı İSG belgesiyle ilgili (okutma görüldüğü için); çalışmanın kendisi için hiçbir şey yok.
- **Ne olmalıydı:** Planı olmayan günde geçerli okutma varsa gece işi bunu düşürmemeli: en azından İK'ya "plansız gün çalışması" uyarısı vermeli ya da günü havuza (`tatil_calismasi` / `plansiz_gun`) koymalı. Belgede (`docs/veritabani.md`, puantaj kodu `HT`) planı olmayan gün hafta tatili sayılıyor; o gün çalışılırsa ne olacağı yazılı değil.
- **Kanıt:** `a11_giris_cikis_sonuc.txt` G#57 `X4 … 16.10 soru_bekliyor | ham 17.10: 2` (17.10 gün yok) · `a10_kart_isg_sonuc.txt` #150 `S1 17.10 Cumartesi plansız 08:00–13:00 | gün: yok | havuz: yok | uyarı: isg_belgesi_yok … | işaret: 17.10 08:00:00 işaretsiz; 17.10 13:00:00 işaretsiz` · #149 gece işi 17.10 `basarili`.
- **Sade dille:** Amir bir işçiyi Cumartesi'ye çağırır ama sisteme vardiya yazmayı unutursa, işçi 5 saat çalışır, kartını okutur ve bu çalışma hiçbir yerde görünmez. Ne puantaja girer, ne fazla mesai listesine düşer, ne de İK'ya uyarı gider. İşçi emeğinin karşılığını alamaz; fark ancak kendisi itiraz ederse anlaşılır. Amir sonradan geriye dönük plan girerse (İK onayıyla) gün işlenir, ama kimse hatırlatmadığı için bu nadiren olur.
- **Öneri:** Gece işine bir adım: o gün planı olmayan, işe giriş–çıkış tarihleri içindeki bir çalışanın geçerli PDKS okutması varsa `plansiz_gun_calismasi` uyarısı (İK ve amire) ve isteğe bağlı olarak `fazla_mesai_inceleme`'ye `tatil_calismasi` kaydı. Karar İK ile: havuz mu, yalnızca uyarı mı. Kalıcı test: planı olmayan güne okutma → uyarı (ve/veya havuz kaydı).
- **Durum:** Açık

### T-80 · Admin `calisan` tablosunun bütün satırlarını ve sütunlarını görüyor; CLAUDE.md "admin çalışan kayıtlarını görmez" diyor
- **Adım:** 11 (Adım 10 betiğinde yeniden doğrulandı) · **Önem:** Düşük
- **Yer:** `calisan` RLS politikası `admin_okur` (`oturum_rolu() = 'admin'`). Adım 3 matrisi de bunu "beklenen" saymıştı.
- **Ne oldu:** Admin 99 çalışan satırının hepsini, bütün sütunlarıyla görüyor: sicil, ad, soyad, departman, işe giriş tarihi, **işten çıkış tarihi**, aktiflik. Gün kaydı, kart, İSG belgesi, uyarı ve geçici kart zimmetini görmüyor (0 / 0 / 0 / 0 / 0). Bölge yetkilerini görüyor (departman düzeyinde; kişisel değil).
- **Ne olmalıydı (değerlendirme):** İkisi de kısmen doğru. Admin'in hesap açarken (`kullanici_ekle`) hangi çalışana bağlayacağını seçmesi gerekiyor; bu yüzden çalışan listesine bir ölçüde erişmesi şart. Ama işten çıkış tarihi ve işe giriş tarihi İK bilgisi; hesap açmak için gerekmiyor. KVKK'daki "ölçülülük / veri en aza indirme" ilkesine göre doğru olan: admin yalnızca hesap açmak için gereken alanları görsün. CLAUDE.md'deki cümle de buna göre netleşsin ("admin gün kaydı, puantaj, izin, kart ve İSG verisini görmez; hesap açmak için çalışan adını ve sicilini görür").
- **Kanıt:** `a10_kart_isg_sonuc.txt` #151 `admin: calisan satırları / sütunlar | OK 99 satır; örnek: {"id":…,"sicil_no":"S10X","ad":"AdX","soyad":"Deneme","departman_id":…,"ise_giris_tarihi":"2025-01-01","isten_cikis_tarihi":"2026-11-20","aktif":false,…}` · #152 `gun_kaydi / kart / isg_belge / uyari / gecici_kart_zimmet: 0 / 0 / 0 / 0 / 0` · #153 `bölge yetkisi / geçmişi: 4 / 6`. Adım 3 RLS matrisi: `calisan` admin 76.
- **Sade dille:** Sistem yöneticisi kimin ne zaman işten ayrıldığını görebiliyor. Bu bilgi ona iş için gerekmiyor; yalnızca kime hesap açacağını bilmesi yeterli. Büyük bir sızıntı değil (maaş, sağlık ya da puantaj yok), ama proje belgesi "admin çalışan kaydı görmez" dediği için sunumda soru çıkarır.
- **Öneri:** (a) `calisan` üzerindeki `admin_okur` politikası kaldırılsın; yerine yalnızca `id, sicil_no, ad, soyad, departman_id` ve "hesabı var mı" döndüren, yalnızca aktif çalışanları listeleyen `security definer` bir fonksiyon (ör. `hesap_acilacak_calisanlar()`), ya da (b) bilinçli kabul edilip CLAUDE.md ve `docs/veritabani.md`'deki cümle düzeltilsin. Öneri (a); T-72 ile birlikte ele alınabilir.
- **Durum:** Açık

### T-33 ile karşılaştırma
T-33 (kullanıcı değişikliğinin izi yok) Adım 11'de üç yeni sonuçla ağırlaştı: çıkmış çalışanın hesabını yeniden açmak (T-71), başka çalışana bağlı İK / admin hesabı açmak (T-72) ve amirin rolünü değiştirip departmanı sahipsiz bırakmak (T-70). Üçü de yalnızca `kullanici` tablosunu değiştiriyor; sonradan "kim yaptı" sorusunun cevabı yok (G#157–158: geçmiş tablosu yok; sütunlarda kim/ne zaman değiştirdi yok).

### T-09 ve T-10 ile karşılaştırma
- **T-09:** Pasif kullanıcı ve çıkmış çalışanın pasif hesabı `ayar_al`'ı hâlâ çağırabiliyor (G#89, #137: 10). Başka hiçbir veriye ulaşamıyorlar. Bulgu aynı, yeni bir şey yok.
- **T-10:** Ayarı yalnızca admin değiştiriyor ve `ayar_gecmisi` doğru çalışıyor (değişmez, silinmez, yapan kişi yazılı). Ama T-74'le birlikte okununca: tek kişi, herhangi bir sınır olmadan, yasal sınırları ve puantajı değiştirebiliyor. T-10'un "Görüş" önemi T-74 çözülmezse yetersiz kalır.

### Bulgular önem sırasıyla
1. **T-71** · Yüksek · Çıkmış çalışanın hesabı yeniden açılıyor; tam yetkiyle çalışıyor.
2. **T-72** · Yüksek · Admin, başka çalışana bağlı İK / admin hesabı açarak görevler ayrılığını aşıyor.
3. **T-74** · Yüksek · Ayarlarda aralık kontrolü yok; yasal sınırlar ve tolerans anlamsız değerlere çekilebiliyor.
4. **T-65** · Yüksek · Çıkıştan sonraki işlenmemiş / plansız okutma fark edilmiyor; son çalışılan gün kayboluyor.
5. **T-70** · Orta · Pasif ya da rolü değişen amire soru açılmaya devam ediyor.
6. **T-66** · Orta · Yanlış çıkış geri alınamıyor.
7. **T-67** · Orta · Kilitli aya düşen çıkış kilitli ayın planlarını siliyor.
8. **T-68** · Düşük · Çalışma tarihleri dışına plan, izin, kart, geçici kart veriliyor.
9. **T-69** · Düşük · Çıkış sonrası günün itirazı açık kalıyor; kapanmış güne itiraz girilebiliyor.
10. **T-73** · Düşük · Üst amir döngüsü / amir olmayan üst amir; üst amir kaldırılamıyor.
11. **T-75** · Düşük · Giriş tarihi aralığı, sicil büyük/küçük harf, ham kart hataları.

Sonradan eklenenler (22 Kasım, Adım 10 sırasında; kanıt Adım 10 betiğinde yeniden alındı):
- **T-79** · Yüksek · Planı olmayan günde (Cumartesi) yapılan çalışma hiçbir yere yazılmıyor. Sıralamada T-71 ile T-72'nin yanına girer.
- **T-80** · Düşük · Admin çalışan tablosunun bütün satır ve sütunlarını görüyor; CLAUDE.md ile çelişiyor.

Yeniden görülen eski bulgular: T-09 (pasif kullanıcı `ayar_al`), T-16 (ham İngilizce kısıt mesajları: kart, ayar türü), T-19 (işlenmiş güne sonradan gelen okutma: geriye dönük plan onayı günü hemen işleyince sonraki okutma kullanılmadı, G#34), T-33 (iz yok), T-54 (izinli günde okutma: X1 14.10 `izinli`).

### Denediklerim
- 251 çağrı (`scratch/a11_giris_cikis_sonuc.txt`, `scratch/a11_ek_sonuc.txt`).
- Giriş zinciri iki sırayla (önce okutma / önce plan onayı) ve ileri tarihli plan, girişten önceki planlar, ileri tarihli giriş, tarih aralığı.
- Yeniden ekleme: aynı sicil (düz, boşluklu, küçük harf), ayrılmış sicil, aynı / iptal kart numarası, olmayan çalışan, geçici kart numarası.
- Çıkış: ertesi gece işleme; plan, kart, hesap, izin, FM talebi; işlenmiş / işlenmemiş / plansız okutma; açık zimmet; açık soru ve itiraz; iptal kartla okutma (kart iptalinden önce ve sonra); kilitli ay (okutmalı, okutmasız, sonrası olmayan); 7 doğrulama; 4 geri alma yolu; çıkış sonrası 6 işlem.
- Kullanıcılar: 5 rol × 2 fonksiyon + doğrudan UPDATE; 6 doğrulama; rol değişikliğinin anlık etkisi; admin kendine / başkasına rol; pasif kullanıcı (RPC, RLS, `ayar_al`, görünüm); çıkmış çalışanın hesabını açma; başka çalışana bağlı hesap; üst amir döngüsü ve kaldırma; amir pasif / rol değişince sorular.
- Ayarlar: 21 değer (negatif, boş, olmayan ad, metin, ondalık, taşma, aşırı büyük, bayrak, yüzde, sıralama, 0); İK; doğrudan UPDATE / DELETE; `ayar_gecmisi`'nin değişmezliği; aşırı değerin bir güne etkisi ve geri alınınca durum.

### Denemediklerim
- **Ekrandan (HTTP) çağrı:** Hepsi SQL ile rol taklidi. Supabase Auth tarafında pasif kullanıcının oturumunun (JWT, yenileme belirteci) ne olduğu denenmedi; yalnızca veritabanı tarafı.
- **Gerçek Auth kaydı:** Yeni hesaplar için `auth.users`'a doğrudan satır eklendi; davet / şifre akışı denenmedi. T-72'nin canlıda yapılabilmesi admin'in o e-postayla Auth hesabı oluşturabilmesine bağlı (Supabase panelinden ya da açık sign-up'la; T-09'daki sign-up kaygısı).
- **Fark satırının sonraki aydaki puantajı:** L2'nin Ekim'e yazılan 3 `vardiya_yok` fark düzeltmesinin Ekim kilidindeki etkisi (Adım 12).
- **Gece vardiyasında çıkış günü:** Çıkış günü V3 (gece yarısını aşan) vardiyasıyla biten çalışanın ertesi sabahki okutması.
- **Departman değiştirme ve yeniden işe giriş:** İkisi de bilinçli olarak yok (`docs/veritabani.md` satır 431); denenmedi.
- **Eşzamanlı çıkış:** İki İK'nın aynı anda çıkış girmesi (`for update` var, denenmedi).
- **Ayarların her birinin etkisi:** Yalnızca tolerans ve uzun mola bir günde denendi; `gunluk_azami_calisma_dk` 1440 ile fazla mesai talebi, `soru_eskalasyon_gun` 0 ile eskalasyon, `cumartesi_hafta_sonu` 7 ile Cumartesi hesabı denenmedi.
- **`ayar_guncelle`'ye `null` anahtar:** Çağrı yapıldı ama betikteki birleştirme satırı boş yazdı (E#4); sonucu okunamadı.

### Şüpheler
- **Girişten önceki okutmalar:** E3'ün işe girişten önceki 2 günde 4 okutması sessizce yok sayıldı. İşe giriş tarihi yanlış (geç) girilirse çalışanın ilk günleri T-65'teki gibi kaybolur; uyarı yok. Çıkış için olan kontrol giriş için hiç yok.
- **Plansız gün çalışması hiç kaydedilmiyor:** → T-79 olarak bulgulara alındı. X4'ün 17.10 Cumartesi okutması (planı yok) için gün kaydı açılmadı (G#57). Belgeye göre planı olmayan gün hafta tatili (`HT`); ama plansız Cumartesi gelen birinin çalışması puantaja hiç girmiyor, fazla mesai havuzuna da düşmüyor. Adım 9'da denenmemiş; ayrıca bakılmalı.
- **Geriye dönük plan onayı günü hemen işliyor:** İK onayı geldiği anda gün, o anda okutma yoksa "hiç kayıt yok" olarak işleniyor ve sonra gelen okutma kullanılmıyor (G#34, #48). Onay genelde okutmadan sonra geldiği için sık olmaz; T-19 ile aynı kök.
- **Çıkış gününü kapsayan izin:** X1'in 14–15.10 izni çıkıştan sonra da `geçerli` kaldı (belgeye uygun). Puantaja 15.10 girmiyor, ama izin kaydının bitişi çıkışla kısaltılmıyor; izin raporlarında ayrılmış kişinin çıkış sonrası izinli göründüğü bir yer olabilir.
- **Admin bütün çalışan satırlarını görüyor:** → T-80 olarak bulgulara alındı. `calisan` tablosunda admin 76/76 (Adım 3 matrisinde bekleneni buydu, hesap açmak için gerekli). CLAUDE.md'deki "admin çalışan kayıtlarını görmez" cümlesi gün kayıtları için doğru (0), çalışan listesi için değil; belgede netleştirilmeli.

---

## Adım 12 — Puantaj, ay kilidi, fark satırı, ERP (22 Kasım 2026)

**Başlangıç:** `main` @ `79ad042` (31 migration). Yerel veritabanı `supabase db reset` ile kuruldu. Raporun commit edilmemiş hali önce yedeklendi (`scratch/a12_rapor_yedek_reset_oncesi.md`); sıfırlamadan önce ve sonra özeti aynı.

**Not:** Bu adımın istem metni "Zorla kilit:" maddesinde kesilmişti. Bu maddeyi planın maddesiyle tamamladım ("kodsuz gün sayısı gerçekten kodsuz kalan günlerle aynı mı?"). Ayrıca kimin zorlayabildiğine ve zorla kilidin izine baktım.

**Betikler:**

| Betik | Ne sınıyor |
|---|---|
| `scratch/a12_puantaj.sql`, `_sonuc.txt` | 119 çağrı: Eylül (zorla kilit) ve Ekim (engeller tek tek, sonra zorlamadan kilit) ve Kasım (seed + iki ay sonraki fark); kapsama, satır = canlı görünüm, satır = kalem, fark satırları, ERP, değiştirilemezlik ve yetki |
| `scratch/a12_ileri.sql`, `_sonuc.txt` | İleri bir ayın (Ocak 2027) kilitlenmesi ve sonucu |
| `scratch/a12_kod/*.sql` | Okunan 17 fonksiyonun, 4 görünümün ve tetikleyicilerin son sürümü |

**Kurulum:** Tek işlem, sonda `ROLLBACK`. Departman "S12 Mavi" (amiri montaj.amiri). 25 çalışan; Eylül ve Ekim 2026'da hafta içi GÜNDÜZ planı, okutmalar ve 4 kaynaktan dosya.

| Vaka | Eylül | Vaka | Ekim |
|---|---|---|---|
| N1 | normal | EU1 | işlenmemiş gün + onay bekleyen geriye dönük plan (21.10) |
| G1 | işe giriş 14.09 | EU2 | işlenmemiş planlı gün (22.10) |
| C1 | işten çıkış 18.09 | EP1 | işlenmiş güne onay bekleyen plan (05.10, V1) |
| S1 | plansız Cumartesi 12.09 (T-79) | EF1 | onaysız fazla mesai (06.10) |
| IZ1 | 10–11.09 izin; 11.09 Cuma planı yok | EQ1 | açık soru (28.10) |
| Q1 | açık soru (29.09) | EI1 | açık itiraz (07.10) |
| Q2 | eskale, üst amirde kalan soru (07.09, T-39) | ET1 | karar bekleyen FM talebi (08.10, T-63) |
| Q3 | tek saatli cevap, askıda gün (08.09, T-41) | E41 | tek saatli cevap, askıda gün (09.10, T-41) |
| Q4 | soru açıkken İK "tamam" yaptı, hesap ✗ (09.09, T-39 Z1) | | |
| IT1, FM1, FT1, GP1 | açık itiraz, onaysız FM, FM talebi, işlenmiş güne bekleyen plan | | |
| PA/PB | kart paylaşımı şüphesi (T-81) | | |
| L2 | kilitli Eylül'e düşen işten çıkış (15.09) | | |
| F1 | 08:00–17:00; kilitten sonra düzeltmeler (22, 23, 24.09) | | |

Kanıtlardaki `#n` = `a12_puantaj_sonuc.txt`'deki çağrı numarası; `İ#n` = `a12_ileri_sonuc.txt`.

### Sonuç tablosu

| # | Konu | Ne yaptım | Beklenen | Gerçekleşen | |
|---|---|---|---|---|---|
| 1 | Engel: işlenmemiş planlı gün + işlenmemiş güne bekleyen plan | Ekim, EU1 + EU2 | Zorla da geçilmez | "gece işinden geçmemiş 2 planlı gün … 1 günün geriye dönük planı İK onayı bekliyor … zorla geçilemez"; zorla da aynı (#54–55) | ✅ |
| 2 | EU1 planı onaylanınca | | Gün işlenir | Onayla hemen işlendi (`tamam`); kalan EU2 için mesaj (#57) | ✅ |
| 3 | EU2 gece işi | | | `tamam` (#58–59) | ✅ |
| 4 | Engel: işlenmiş güne bekleyen plan | EP1 | Zorla geçilir, zorlamadan değil | "İK onayı bekleyen 1 geriye dönük vardiya planı" (#60); Eylül'de zorla geçti (#12) | ✅ |
| 5 | Engel: onaysız fazla mesai | EF1 | Zorlamadan geçilmez | "İK kararı bekleyen **2** onaysız fazla mesai" (#62): EP1'in planı onaylanınca gün V1 ile yeniden işlendi, yeni bir havuz kaydı (185 dk) doğdu (#65) | ✅ / ⚠️ T-96 |
| 6 | Engel: açık soru + açık itiraz | EQ1, EI1 | Zorlamadan geçilmez | "açık soru veya itirazı olan 2 gün" → 1 → kilit (#67–72) | ✅ |
| 7 | Engel: eskale soru (T-39) | Q2 07.09 üst amirde | Zorlamadan geçilmez | Açık sorulu gün sayısına giriyor; zorla geçti (#8, #12) | ✅ |
| 8 | Bekleyen FM talebi (T-63) | FT1, ET1 | Engel ya da uyarı | Engel değil, özette yok; kilitten sonra karar verilemiyor: "kilitli bir döneme ait; fazla mesai planı değişmez" (#33); ET1 sonsuza kadar `talep` (#80) | ❌ T-63 (yeniden doğrulandı) |
| 9 | Kararı verilmemiş kart paylaşımı (T-81) | PA/PB + Eylül'de 73 görülmemiş paylaşım uyarısı | Engel ya da uyarı | Engel değil, özette yok (#8, #30) | ❌ T-81 (yeniden doğrulandı) |
| 10 | Engeller tek tek mi bildiriliyor | Ekim, 7 deneme | Hepsi birden | Her denemede yalnızca ilk engel; 7 kilit denemesi gerekti (#54–72) | ⚠️ T-96 |
| 11 | Zorlamadan kilit | Ekim, bütün engeller kapandıktan sonra | Kilit; özet doğru | Kilitlendi; `zorla_gecilen` hepsi 0, `kodsuz_gun: 1` (E41, T-41) (#72) | ✅ özet / ❌ T-90 |
| 12 | Zorla kilit özeti | Eylül | Sayılar gerçekte kalanla aynı | Özet 6 açık sorulu gün / 1 itiraz / 1 FM / 1 plan / 7 kodsuz; bağımsız sayım 6 / 1 / 1 / 1 / 7 (#8, #12, #15) | ✅ |
| 13 | Zorla kilit: kodsuz gün sayısı | Eylül, Ekim, Kasım | Gerçekten kodsuz kalanla aynı | Eylül 7 = 7 (L2 ×3, Q1, Q2, Q3, Q4); Ekim 1 = 1 (E41) (#15, #74) | ✅ |
| 14 | Zorla kilidin izi | Eylül `donem` satırı | Zorla, geçilenler, gerekçe | Yalnızca `kilitleyen_id`, `kilit_zamani`; zorla bilgisi ve gerekçe yok (#14) | ❌ T-92 |
| 15 | Zorlayabilen | 6 rol `ay_kilitle` | Yalnızca İK | İK OK; 5 rol "yetkiniz yok" (#90–95) | ✅ |
| 16 | T-39 / T-41 günleri puantajda | Q2, Q3, Q4, E41 | Görünür biçimde "karar bekliyor" | Q2, Q3, E41 kodsuz; puantaj satırında "bekleyen" sütunu yok; ERP'de bu günler hiç yok (#15–16, #29) | ❌ T-90 |
| 17 | Her gün tam bir kez | Eylül 485, Ekim 248 çalışan-gün | 0 eksik, 0 çift | Çift 0. Eksik yalnızca kodsuz günler (Eylül 7, Ekim 1) (#15, #74) | ✅ çift / ❌ T-90 eksik |
| 18 | Satır = `v_puantaj_canli` | Eylül 17, Ekim 8 satır | Birebir | 0 fark (#16, #75) | ✅ |
| 19 | Satır = kalem | Eylül, Ekim | Birebir | Eylül'de Q4: satırda çalışılan 22, kalemde 21 (#17); Ekim 0 fark (#76) | ❌ T-91 |
| 20 | Ay ortası işe giriş | G1, 14.09 | 17 gün (14–30) | 17 gün; giriş öncesi planlar kodlanmadı (#19, #27) | ✅ |
| 21 | Ay ortası çıkış | C1, 18.09 | 18 gün (1–18) | 18 gün; çıkış sonrası 8 gün `vardiya_yok`, kodlanmadı (#7, #20, #27) | ✅ |
| 22 | Plansız Cumartesi (T-79) | S1 12.09 08:00–13:00 | Çalışma görünmeli | Puantajda **HT** (hafta tatili), gün kaydı yok (#28) | ❌ T-79 (puantajda da doğrulandı) |
| 23 | Planı olmayan güne düşen izin | IZ1 10–11.09 yıllık izin; 11.09 Cuma planı yok | 2 gün Yİ | 10.09 Yİ, 11.09 **HT** (#22, #28) | ❌ T-94 |
| 24 | Kilitli ayda gün kaydı | F1 22–24.09 üç düzeltme; `postgres` doğrudan UPDATE | Değişmez | Üç gün aynı (#42); doğrudan UPDATE "kilitli bir döneme ait; değişiklik sonraki aya fark olarak yazılır." (#44) | ✅ |
| 25 | Kilitli aya plan | F1 26.09 | Ret | "kilitli bir döneme ait." (#45) | ✅ |
| 26 | Fark: tek düzeltme, elle hesap | F1 22.09 giriş 08:00→09:00 | Çalışma −60, geç +60 | Elle (`gun_hesabi` bağımsız): 480→420, geç 0→60 (#46); Ekim fark satırına dahil (aşağıda) | ✅ |
| 27 | Fark: aynı güne iki düzeltme, aynı hedef ay | F1 23.09 çıkış 16:00, sonra giriş 08:30 | Çalışma −60, geç +30, erken +60, mola −30 | Ekim F1 fark satırı: çalışma −120, geç 90, erken 60, mola −30; NÇ −120 dk = 22.09 + 23.09 toplamı (#77) | ✅ |
| 28 | Fark: aynı güne üçüncü düzeltme, başka ay | F1 23.09 çıkış 16:00→17:00 (Ekim kilitli) | Önceki farkın üstüne: çalışma +30, erken −60, mola +30 | Kasım'a gitti; Kasım F1 fark satırı (24.09 ile toplam): çalışma +10, geç +20, erken −60, mola +30 (#83, #88) | ✅ |
| 29 | İki ay sonra gelen düzeltme | F1 24.09 giriş 08:20 (Eylül ve Ekim kilitli) | İlk açık ay (Kasım), kaynak Eylül | Hedef 2026/11, kaynak 2026-09 (#83, #89) | ✅ |
| 30 | Kilitten sonra soru cevabı | Q1 29.09 | Fark | Ekim'e fark: çalışılan +1, 480 dk, NÇ 1/480 (#37, #77) | ✅ |
| 31 | Kilitten sonra havuz onayı | FM1 16.09 | Fark | Ekim'e FM50 120 (#37, #77) | ✅ |
| 32 | Kilitten sonra plan onayı | GP1 21.09 V1 (06–14), çalışan 07:55–17:05 | Fark; vardiya dışı çalışma havuza | Ekim'e çalışma −145, geç +115; **havuz kaydı yok** (#32, #77). Açık ayda aynı durum (EP1) 185 dk havuz kaydı doğurdu (#65) | ❌ T-93 |
| 33 | Kilitli aya düşen çıkışın farkı | L2 çıkış 15.09; 16–18.09 `vardiya_yok` düzeltmesi Ekim'e | Ekim'de fark ya da Eylül'deki 3 kodsuz günün kapanması | 3 düzeltme hedef Ekim (#41); Ekim'de L2 için **satır yok** (#78). Eylül'deki 3 gün kodsuz kaldı | ❌ T-95 |
| 34 | Kilidi açma | İK ve admin doğrudan UPDATE; `postgres` UPDATE; `postgres` DELETE | Ret | `permission denied` ×2; "9/2026 dönemi kilitli; değiştirilemez."; "Dönem silinemez." (#100–103) | ✅ |
| 35 | İkinci kez kilit | Ekim, normal ve zorla | Ret | "10/2026 dönemi kilitli; değiştirilemez." (#98–99) | ✅ |
| 36 | Puantaj satırı / kalemi değiştirme, silme | İK, admin; `postgres` | Ret | `authenticated`: 5/5 `permission denied`; `postgres`: 3/3 "değiştirilemez ve silinemez" (#104–111). Açık döneme satır: ret (#112) | ✅ |
| 37 | Kilitli döneme elle satır ekleme | `postgres`: Ekim'e kalemsiz 999 dk fark satırı | Ret | **Kabul** (#113); kalemsiz olduğu için ERP'de görünmüyor (#114) | ❌ T-97 |
| 38 | `duzeltme` değiştirme | `postgres` UPDATE | Ret | Ret (#115) | ✅ |
| 39 | ERP satır sayısı ve kodlar | Eylül | Kalem sayısı kadar satır | 35 = 35; kodlar HT, NÇ, Yİ (#29) | ✅ |
| 40 | ERP fark satırlarının kaynak dönemi | Ekim, Kasım | Kaynak = düzeltilen günün ayı | Ekim'de 4 fark satırı, hepsi `2026-09`; Kasım'da F1 `2026-09`; normal satırlarda kaynak boş (#79, #89) | ✅ |
| 41 | ERP'yi kim görür | 4 rol | İK, yönetici | İK 223, yönetici 223, amir 0, admin 0 (#116–119) | ✅ |
| 42 | İleri ay kilidi | Ocak 2027 (bugün 22.11.2026) | Ret | **Kilitlendi** (İ#1). Sonra o aya plan girilemiyor (İ#3), kilit `postgres` ile bile açılamıyor (İ#5) | ❌ T-89 |
| 43 | İçinde bulunulan ay | Kasım, işlenmemiş günler varken | Ret | Ret: "1598 planlı gün" (İ#6) | ✅ |
| 44 | Boş geçmiş ay | Ağustos 2026, veri yok | — | Kilitlendi (#90) | ✅ (kabul edilebilir) |

### Kod incelemesi (Ek A)
- **`ay_kilitle`:** Sırayla: hesaplanmamış günleri hesapla; işlenmemiş planlı gün (zorla geçilmez); işlenmiş güne bekleyen plan ve onaysız FM (zorla geçilir); açık soru / itiraz (`donem_kilitle`'de, zorla geçilir); puantaj; kodsuz gün sayımı.
  - Ayın bitip bitmediğine bakmıyor (T-89).
  - Kodsuz günü engel saymıyor, yalnızca sayıyor (T-90).
  - FM talebine (T-63) ve paylaşım şüphesine (T-81) bakmıyor.
  - Engelleri tek tek `raise` ediyor (T-96).
  - Döndürdüğü özet hiçbir yere yazılmıyor (T-92).
- **`donem_kilitle` / `donem_kontrol`:** Kilitli dönem değiştirilemez ve silinemez, kilidi yalnızca İK koyar; doğru.
- **`donem_bul` / `hedef_donem` / `duzeltme_hazirla`:** Kilitli günün düzeltmesi ilk açık aya `fark_satiri = true` ile gidiyor; iki ay sonra da doğru (#83).
- **`puantaj_yaz`:**
  - Normal satır `v_puantaj_canli`'den, kalemler `gun_kodlari_hesapla`'dan geliyor. İkisi "gün tamam ama hesaplanmamış" durumunu farklı sayıyor (T-91).
  - Fark satırı için gün başına "önceki farklar" ve "bu dönemin farkları" ile `gun_katkisi` iki kez hesaplanıyor; doğru birikiyor (#88).
  - Satır, yalnızca sayısal alanlar sıfırdan farklıysa yazılıyor; yalnızca kodu değişen fark düşüyor (T-95).
  - Fark için havuz (`fazla_mesai_inceleme`) üretilmiyor (T-93).
- **`gun_kodlari_hesapla` / `gun_kod_satirlari`:**
  - Gün kaydı olmayan gün `HT` (ya da `RT`) oluyor. Planı olmayan izin günü de, plansız çalışılan Cumartesi de bu yüzden HT (T-94, T-79).
  - `eksik`, `soru_bekliyor`, `devamsiz_suphesi` ve hesabı tamamlanmamış `tamam` için kod yok.
  - Çalışma tarihleri dışındaki günler kodlanmıyor (doğru).
- **`puantaj_kontrol`:** Yalnızca "dönem kilitli mi"ye bakıyor; kilitli döneme sonradan satır eklenmesine izin veriyor (T-97).
- **`gun_katkisi`:** Düzeltmeleri gün kaydının üstüne sırayla uygulayıp `gun_hesabi`'nı yeniden çağırıyor. Ayar değişmişse (T-74) "önce" değeri de bugünkü ayarla hesaplanıyor (Şüphe).
- **`v_puantaj_aktarim`:** Yalnızca kilitli dönemler, kalem başına bir satır, fark satırında kaynak dönem; doğru.

### Bulgular

### T-89 · İleri bir ay kilitlenebiliyor; kilit açılamadığı için o ay kalıcı olarak kullanılamaz hale geliyor
- **Adım:** 12 · **Önem:** Yüksek
- **Yer:** `pdks.ay_kilitle`: ayın bitip bitmediğine bakmıyor. Tek engel "işlenmemiş planlı gün"; planı henüz girilmemiş bir ay bu engeli geçiyor. `pdks.donem_kontrol` kilitli dönemi değiştirmiyor ve silmiyor (bilinçli).
- **Ne oldu:** 22.11.2026'da İK, Ocak 2027'yi kilitledi: "1/2027 kilitlendi." Sonra o aya vardiya planı girilemedi ("kilitli bir döneme ait"). Kilit `postgres` ile bile açılamadı. (İzin girilebildi: T-48.) Aralık 2026 ise yalnızca seed'de planı olduğu için reddedildi.
- **Ne olmalıydı:** Ay, son günü bittikten sonra kilitlenebilmeli (İstanbul saatiyle `p_ay`'ın son günü < bugün). Kilit açılamadığı için bu kontrol özellikle gerekli.
- **Kanıt:** İ#1 `ay_kilitle 2027/1 | OK {"donem": "2027-01", "mesaj": "1/2027 kilitlendi.", "zorla": false, "kodsuz_gun": 0, …}` · İ#3 `vardiya_plani_gir 05.01.2027 | HATA … kilitli bir döneme ait.` · İ#5 `postgres: 2027/1 kilidini aç | HATA … 1/2027 dönemi kilitli; değiştirilemez.` · #97 Aralık: ret (seed'in 7 Aralık planları yüzünden).
- **Sade dille:** İK ekranında ay listesinden yanlış ayı seçip "kilitle"ye basarsa, gelecekteki bir ay sonsuza kadar kapanır. O ay için vardiya planı girilemez, gece işi o ayın günlerini işleyemez. Sistem bunu geri alamadığı için tek çare veritabanına el ile müdahaledir; bu da "kilitli ay açılamaz" kuralını çiğner.
- **Öneri:** `ay_kilitle` başında: `if make_date(p_yil, p_ay, 1) + interval '1 month' > (now() at time zone 'Europe/Istanbul')::date then raise exception 'Ay bitmeden kilitlenemez.'`. Kalıcı test: içinde bulunulan ay ve ileri ay reddedilir.
- **Durum:** ✅ Düzeltildi — ekran PR #39, veritabanı PR #49 (migration: `20261207010000_ay_kilidi_zamani.sql`, test: `ay_kilidi_zamani_testi.sql`).
  - `ay_kilitle` en başta, ayın son günü İstanbul tarihiyle (`pdks.bugun()`) bugünden önce değilse "henüz bitmedi" hatası verir; zorla da geçilemez. Yerelde yeniden üretildi (23.11.2026'da Ocak 2027 kilitlendi), düzeltmeden sonra reddediliyor.
  - Test: içinde bulunulan ay, gelecek ay ve iki ay sonrası reddedilir; bitmiş ay kilitlenir; ayın son günü sınırı (30.06 ret, 01.07 kabul).
  - **Testler için tarih ayarı:** `pdks.bugun()`, doğrudan veritabanı bağlantısında (`session_user = 'postgres'`) `set local pdks.test_bugun = 'YYYY-MM-DD'` ayarını kullanır; ekrandan gelen istek (`authenticator`) ayarı görmez. Kasım / Aralık 2026'yı kilitleyen 5 test dosyası (`ay_kilidi`, `erp_aktarim`, `plan_onayi`, `puantaj_kurallari`, `puantaj`) bu ayarla (15.01.2027) tarihten bağımsız çalışır.
  - Sistem yolu `donem_kilitle` (yalnızca `postgres` çalıştırır) değişmedi; T-97 ile birlikte sınırlılık.

### T-90 · Askıdaki gün puantaja kodsuz giriyor ve hiçbir yerde görünmüyor; zorlamadan kilit de buna izin veriyor
- **Adım:** 12 · **Önem:** Yüksek
- **Yer:** `pdks.ay_kilitle` (kodsuz günü yalnızca sayıyor, engel saymıyor); `puantaj_satiri` (bekleyen / kodsuz gün sütunu yok); `v_puantaj_aktarim` (yalnızca kalemler). Kökler: T-39 (üst amirde kalan soru) ve T-41 (tek saatli cevap).
- **Ne oldu:**
  - **Ekim, zorlamadan kilit:** Bütün engeller kapandıktan sonra kilit başarılı oldu. E41'in 09.10 günü (tek saatli cevap, açık sorusu yok, hesap ✗) "Puantaja kodsuz giren gün: 1" diye geçti. Zorla gerekmedi.
  - **Eylül, zorla kilit:** 7 gün kodsuz girdi: Q1, Q2 (üst amirde kalan soru), Q3 (tek saat), Q4, L2 ×3.
  - Bu günler puantaj satırında görünmüyor: `v_puantaj_canli`'deki `bekleyen_gun` (Eylül'de 7) `puantaj_satiri`'na aktarılmıyor. ERP'ye ne kod ne bir "eksik" işareti gidiyor; Q2'nin ERP satırı yalnızca "HT 8, NÇ 21".
  - Sonradan cevap gelirse gün fark satırıyla sonraki aya geliyor (Q1: Ekim'e NÇ 1/480). Ama T-39'daki gibi cevap hiç gelmeyecekse gün sonsuza kadar kodsuz kalıyor.
- **Ne olmalıydı:** Kodsuz gün ya kilidi engellemeli (zorla geçilebilir olsun ve özetin "zorla geçilenler"ine yazılsın), ya da puantaja ve ERP'ye açık bir kodla ("BEKLİYOR" / "KARARSIZ") gitmeli ki bordrocu görsün.
- **Kanıt:** #72 `10/2026 kilitlendi. Puantaja kodsuz giren gün: 1. "zorla": false` · #74 `kodsuz (0): 1 | kodsuzlar: S12E41 09.10 soru_bekliyor✗` · #15 Eylül 7 kodsuz gün listesi · #16 `v_puantaj_canli bekleyen_gun toplamı: 7 (puantaj_satiri'nda bu sütun yok)` · #29 `S12Q2 HT 8.0/0, S12Q2 NÇ 21.0/10080` (21 iş gününden biri yok) · #77 Q1'in Ekim farkı.
- **Sade dille:** Amir bir soruya yarım cevap verirse ya da üst amir hiç bakmazsa, o gün ay kapanınca puantajda "boş" kalıyor. Ne çalıştı ne gelmedi ne izinli yazıyor. Bordroya giden dosyada o gün hiç yok; bordrocu bir günün eksik olduğunu ancak günleri tek tek sayarsa fark eder. Çalışan o günün ücretini alamayabilir. Bunun için zorla kilit bile gerekmiyor: her şey "temiz" görünürken kilit bu günü sessizce geçiriyor; uyarı yalnızca özet mesajının sonunda.
- **Öneri:**
  - `ay_kilitle`: kodsuz gün > 0 ise zorlamadan reddet ("% gün kodsuz kalacak: … (sicil, gün)"), zorla ise `zorla_gecilen`'e ekle.
  - `puantaj_satiri`'na `bekleyen_gun` (ya da bir `KARARSIZ` kodu) eklensin, ERP görünümüne geçsin.
  - T-39 ve T-41'in düzeltmesi bu günlerin çoğunu zaten önler.
  - Kalıcı test: tek saatli cevaplı gün varken zorlamadan kilit reddedilir.
- **Durum:** ✅ Düzeltildi — PR #54 (migration: `20261209010000_kodsuz_gun.sql`, test: `kodsuz_gun_testi.sql`).
  - `ay_kilitle`: puantaja kodsuz girecek gün varsa zorlamadan kilit reddedilir; hata günleri adıyla söyler ("10/2026 döneminde 1 gün puantaja kodsuz girecek: KG01 09.10.2026 (eksik). …", en çok 10 gün, kalanı "ve N gün daha"). Zorla kilitte kodsuz günler "Zorla geçilenler"e ve özetin `kodsuz_gun_listesi` alanına (sicil, gün, durum, neden) yazılır. Sayım eskisi gibi kilitten sonra; hata kilidi de geri alır, açık soru / itiraz mesajları önce gelir.
  - Yerelde yeniden üretildi: Ekim'de eksik gün varken zorlamadan kilit "10/2026 kilitlendi. Puantaja kodsuz giren gün: 1." dedi; çalışanın Ekim puantajı 31 yerine 30 gün (HT 29, RT 1). Düzeltmeden sonra reddediliyor.
  - Kapsam dışı (ayrı iş, karar Fırat): zorla kilitlenen ayda kodsuz günü `puantaj_satiri` / ERP dosyasına ayrı bir kodla ("BEKLİYOR") yazmak; ERP biçimini ve Excel ekranını değiştirir.

### T-91 · Puantaj satırı ile gün kodları "tamam ama hesaplanmamış" günü farklı sayıyor
- **Adım:** 12 · **Önem:** Orta
- **Yer:** `v_puantaj_canli` (`calisilan_gun = count(*) filter (where durum = 'tamam')`, `hesap_tamam`'a bakmadan) → `puantaj_satiri`; `gun_kodlari_hesapla` (`durum = 'tamam' and not hesap_tamam` → `eksik` → kod yok) → `puantaj_kalemi`.
- **Ne oldu:** Q4'ün 09.09 sorusu açıkken İK giriş, çıkış ve durumu `tamam` yaptı. Gün `tamam` oldu ama hesap ✗, dakika boş (T-39 Z1 vakası). Kilitte puantaj satırı "çalışılan 22 gün", kalemler "NÇ 21 gün" dedi. ERP'ye kalemler gidiyor (21), satır ekranda 22 gösteriyor.
- **Ne olmalıydı:** Satır ve kalem aynı kuralla sayılmalı. Hesabı tamamlanmamış gün ikisinde de "bekliyor" olmalı (T-90).
- **Kanıt:** #10 `Q4 09.09: tamam hesap=false dk=∅` · #17 `satır ≠ kalem: 1 | S12Q4: çalışılan 22.0/21.0` · #25 `Q4 kalemleri | HT 8.0/0, NÇ 21.0/10080 | satır: çalışılan 22.0`. Ek denemede yönetici paneli de aynı günü iki kez sayıyor: `v_departman_ozet` Montaj çalışılan 208 → 209, bekleyen 3 aynı kaldı (Ek#5–6).
- **Sade dille:** Aynı çalışan için iki resmî rakam çıkıyor: puantaj ekranında 22 gün, bordroya giden dosyada 21 gün. Hangisinin doğru olduğu belli değil. İtiraz ya da denetimde sistem kendi kendisiyle çelişiyor.
- **Öneri:** `v_puantaj_canli`'de `calisilan_gun` için `durum = 'tamam' and hesap_tamam`; `bekleyen_gun` ile aynı kural. Kalıcı test: her kilitte satır alanları kalem toplamlarına eşit (NÇ+FM100 gün = çalışılan gün vb.).
- **Durum:** Açık

### T-92 · Zorla kilidin izi yok: hangi engellerin geçildiği ve neden geçildiği saklanmıyor
- **Adım:** 12 · **Önem:** Orta
- **Yer:** `pdks.ay_kilitle` özeti yalnızca çağırana döndürüyor; `donem` sütunları `id, yil, ay, durum, kilitleyen_id, kilit_zamani`. Zorla için gerekçe parametresi yok.
- **Ne oldu:** Eylül zorla kilitlendi: 6 açık sorulu gün, 1 itiraz, 1 onaysız FM, 1 bekleyen plan geçildi, 7 gün kodsuz girdi. `donem` satırında bunların hiçbiri yok. Kilidi kimin koyduğu var, zorla olup olmadığı yok. Sonradan "Eylül neden zorla kapatıldı, hangi günler açıktı?" sorusuna cevap yok.
- **Ne olmalıydı:** Zorla kilit, KVKK m.11 kapsamındaki açık itirazları da geçebildiği için gerekçeli ve izli olmalı: `zorla`, `zorla_gerekce` ve kilit özetinin (geçilen sayılar, kodsuz günler) silinemeyen bir kaydı.
- **Kanıt:** #12 özet · #14 `{"id":…,"yil":2026,"ay":9,"durum":"kilitli","kilitleyen_id":2,"kilit_zamani":"…"}`.
- **Sade dille:** İK müdürü ay sonunda bekleyen her şeyi tek tıkla "zorla" geçebiliyor. Açık itirazı olan çalışanın itirazı karara bağlanmadan ayın puantajı kapanıyor. Ama sistemde "bu ay zorla kapatıldı" diye bir kayıt kalmıyor; iş mahkemesinde ya da denetimde bu kararın izini sürmek mümkün değil.
- **Öneri:** `donem`'e `zorla boolean`, `zorla_gerekce text`, `kilit_ozeti jsonb` (değiştirilemez); `ay_kilitle(p_yil, p_ay, p_zorla, p_gerekce)`: zorla ise gerekçe zorunlu (≥ 10 karakter). Kalıcı test: gerekçesiz zorla reddedilir; özet dönem satırında durur.
- **Durum:** Açık

### T-93 · Kilitli ayda geriye dönük plan onayı fark satırına yalnızca kaybı yazıyor; yeni vardiyanın dışında kalan çalışma havuza düşmüyor
- **Adım:** 12 · **Önem:** Orta
- **Yer:** `pdks.puantaj_yaz` / `pdks.gun_katkisi` (fark yalnızca gün hesabından); `fazla_mesai_inceleme` kaydı yalnızca `gun_hesapla` / gece işinde üretiliyor, kilitli günde `gun_hesapla` çalışmıyor.
- **Ne oldu:**
  - **Açık ay (EP1, 05.10):** İşlenmiş güne V1 (06:00–14:00) planı onaylandı. Gün yeniden işlendi; 14:00 sonrası 185 dk havuza (`vardiya_sonrasi`) düştü, İK karar verdi.
  - **Kilitli ay (GP1, 21.09):** Aynı işlem kilitten sonra yapıldı. Ekim'e fark: çalışma −145, geç +115, NÇ −145 dk. Havuz kaydı yok; 14:00–17:05 arası çalışma hiçbir yerde değil.
- **Ne olmalıydı:** Aynı karar, ay açık da olsa kilitli de olsa aynı sonucu vermeli. Kilitli günde de vardiya dışı süre havuza (`fark_satiri = true`, hedef sonraki ay) düşmeli. Havuzun kilitten sonra onaylanması zaten fark olarak çalışıyor (FM1: Ekim'e FM50 120).
- **Kanıt:** #49 + #61 + #65 `S12EP1 05.10 vardiya_sonrasi 185 dk` · #32 `GP1 … düzeltme: vardiya_id→2 fark=true hedef=2026/10 | havuz: -` · #77 `S12GP1 kaynak=2026/9: çalışma -145, geç 115 … | kalem: NÇ 0.0/-145`.
- **Sade dille:** Ay kapandıktan sonra İK "o gün aslında sabah vardiyasındaydı" diye planı düzeltirse, çalışanın öğleden sonra çalıştığı 3 saat silinip gidiyor; sistem yalnızca "geç geldi, eksik çalıştı" diye kesinti yazıyor. Ay açıkken aynı düzeltme bu 3 saati fazla mesai incelemesine gönderiyordu. Çalışan aleyhine bir sonuç.
- **Öneri:** Kilitli günde vardiya / saat düzeltmesi sonrası `fazla_mesai_inceleme`'ye fark olarak kayıt (kilitli ay mantığı havuz için zaten var: `fark_satiri`, `hedef_donem_id`). Ya da kilitli ayın vardiya planı onayı reddedilsin ve İK `kayit_duzelt` ile ilerlesin. Karar İK ile.
- **Durum:** Açık

### T-94 · Planı olmayan güne düşen izin puantajda "HT" (hafta tatili) kodlanıyor
- **Adım:** 12 · **Önem:** Orta
- **Yer:** `pdks.gece_isi_gun_kayitlari` (gün kaydı yalnızca planlı günlere); `pdks.gun_kodlari_hesapla` (gün kaydı olmayan gün → `gun_kod_satirlari(null)` → HT/RT); izin tablosuna bakılmıyor.
- **Ne oldu:** IZ1'in 10–11.09 yıllık izni var. 10.09'un planı vardı: `izinli` → Yİ. 11.09 (Cuma, iş günü) için plan girilmemişti: gün kaydı yok → **HT**. İzin 2 gün, puantaj 1 gün Yİ + 1 gün hafta tatili diyor.
- **Ne olmalıydı:** İzin kaydı olan gün, plan olsun olmasın izin kodunu almalı (ya da gece işi izinli güne plan olmadan da `izinli` gün kaydı açmalı). Amirlerin izindeki kişiye plan girmemesi sık görülür.
- **Kanıt:** #28 `S12IZ1 10.09: Yİ:1/0 gün=izinli | S12IZ1 11.09: HT:1/0 gün=gün kaydı yok` · #22 `IZ1 kalemleri | HT 12.0/0, NÇ 17.0/8160, Yİ 1.0/0`.
- **Sade dille:** Bir çalışan Perşembe–Cuma yıllık izin alır, amir de "nasılsa izinde" diye Cuma'ya vardiya yazmazsa, bordroya giden dosyada Cuma "hafta tatili" olarak görünür. Çalışanın izin bakiyesinden bir gün eksik düşülür, ya da bordro yıllık izin ücreti yerine hafta tatili yazar. İzin takibi ile puantaj birbirini tutmaz.
- **Öneri:** `gun_kodlari_hesapla`: gün kaydı yoksa önce geçerli izne bak (`Yİ`/`MZR`/`ÜCSZ`/`RPR`), sonra HT/RT. Ya da gece işi izinli güne plansız `izinli` gün kaydı açsın. Hafta sonu izni sayılmamalı; iş günü tanımı İK ile netleşmeli. Kalıcı test: planı olmayan izin günü Yİ kodlanır.
- **Durum:** Açık

### T-95 · Yalnızca gün kodunu değiştiren fark kayboluyor; kilitli aya düşen işten çıkışın 3 günü kodsuz kalıyor
- **Adım:** 12 · **Önem:** Düşük
- **Yer:** `pdks.puantaj_yaz`, fark satırı: `having sum(abs(calisilan_gun)) + … > 0` (yalnızca sayısal satır alanları). `kod_farklari` hesaplanıyor ama satır yazılmadığı için kalemler de yazılmıyor.
- **Ne oldu:** L2'nin 16–18.09 günleri Eylül kilidinde kodsuz (`soru_bekliyor`) girdi. Çıkış 15.09 girilince bu günlere `vardiya_yok` düzeltmesi Ekim'e fark olarak yazıldı. Değişim yalnızca koddaydı (kodsuz → HT); sayısal alanların hepsi 0. Ekim kilidinde L2 için ne satır ne kalem oluştu. Eylül'deki 3 gün kalıcı olarak kodsuz.
- **Ne olmalıydı:** Kod farkı varsa (ör. kodsuz → HT, HT → RT) fark satırı da yazılmalı.
- **Kanıt:** #41 `{"silinen_plan": 3, …, "vardiya_yok_yapilan_gun": 3}` · #78 `16.09 durum→vardiya_yok hedef=2026/10 (×3) | Ekim L2 satırı: yok` · #15 Eylül kodsuzlar arasında L2 16–18.09.
- **Sade dille:** Ay kapandıktan sonra "bu kişi zaten 15'inde ayrılmıştı" diye düzeltilen 3 gün, bordroya hiç ulaşmıyor. Ödeme açısından fark yok (çalışılmamış günler), ama ERP'deki puantajda o 3 gün sonsuza kadar boş kalıyor.
- **Öneri:** `having` koşuluna kod farkı eklensin (`or exists (select 1 from kod_farklari …)`). Kalıcı test: kilitli günde `soru_bekliyor` → `vardiya_yok` sonraki ayda HT fark kalemi üretir.
- **Durum:** Açık

### T-96 · Kilit engelleri tek tek bildiriliyor; bir engeli çözmek yeni engel doğurabiliyor, ön kontrol yok
- **Adım:** 12 · **Önem:** Görüş
- **Yer:** `pdks.ay_kilitle`: engeller sırayla `raise exception`.
- **Ne oldu:** Ekim'i temiz kapatmak için 7 kilit denemesi gerekti. Her denemede yalnızca ilk engel geldi. EP1'in bekleyen planı onaylanınca gün yeniden işlendi ve yeni bir onaysız fazla mesai (185 dk) doğdu; mesaj "1" yerine "2 onaysız fazla mesai" dedi.
- **Ne olmalıydı:** İK'nın kilitten önce hepsini bir arada görebileceği bir ön kontrol (aynı sayımlar, kilitlemeden).
- **Kanıt:** #54 → #60 → #62 → #64 → #67 → #69 → #72; #65 `S12EP1 05.10 vardiya_sonrasi 185 dk`.
- **Sade dille:** Ay sonunda İK "kilitle"ye bastıkça yeni bir eksik öğreniyor; birini düzeltince bir başkası çıkıyor. 2000 kişilik fabrikada bu, ay sonu kapanışını saatlerce uzatır.
- **Öneri:** `ay_kilit_on_kontrol(p_yil, p_ay)`: bütün engelleri ve kodsuz kalacak günleri (sicil, gün, neden) tek seferde dönen, yalnızca okuyan bir fonksiyon; ekranda kilit düğmesinin yanında. `ay_kilitle` aynı fonksiyonu kullanabilir.
- **Durum:** Açık

### T-97 · Sistem yolunda kilitli döneme sonradan puantaj satırı eklenebiliyor
- **Adım:** 12 · **Önem:** Düşük
- **Yer:** `pdks.puantaj_kontrol` yalnızca "dönem kilitli mi" diye bakıyor; `degistirilemez` UPDATE / DELETE'i engelliyor, INSERT'i değil.
- **Ne oldu:** `postgres` ile kilitli Ekim'e N1 için kaynak Eylül, 999 dk'lık kalemsiz bir fark satırı eklendi: kabul. Kalemsiz olduğu için ERP görünümüne girmedi, ama `puantaj_satiri`'nda duruyor ve puantaj ekranında görünür. `authenticated` için tabloya INSERT yetkisi yok (doğru).
- **Ne olmalıydı:** Puantaj satırı yalnızca `puantaj_yaz` içinden, kilit anında yazılabilmeli.
- **Kanıt:** #113 `postgres: puantaj_satiri INSERT kilitli döneme (elle ek satır) | OK eklendi` · #114 `0 satır (kalemsiz satır ERP görünümüne girmez); puantaj_satiri: 1` · #108 İK INSERT `permission denied`.
- **Sade dille:** Ekrandan yapılamıyor; ama veritabanına doğrudan erişen biri (ya da hatalı bir bakım betiği) kapanmış bir aya sahte bir satır ekleyebilir ve bu "değiştirilemez" puantajın parçası gibi görünür.
- **Öneri:** `puantaj_yaz` başında `set_config('pdks.puantaj_yaziliyor', 'evet', true)`; `puantaj_kontrol` bu ayarı yoksa reddetsin. Kalıcı test: doğrudan INSERT reddedilir.
- **Durum:** Açık

### Ek denemeler (onaydan sonra): `v_departman_ozet`, `v_esnek_mesai` ve üç şüphe

**Betik:** `scratch/a12_ek.sql`, `_sonuc.txt` (54 çağrı; tek işlem, sonda `ROLLBACK`). Kasım seed'i gece işinden geçirildi (30 gün); esnek mesai için seed'deki 4 esnek çalışan (84 gün) kullanıldı. Kanıtlardaki `Ek#n` = `a12_ek_sonuc.txt`'deki çağrı numarası.

| # | Konu | Ne yaptım | Beklenen | Gerçekleşen | |
|---|---|---|---|---|---|
| E1 | `v_departman_ozet` = elle | Kasım, 19 departman × 10 sütun; `gun_kaydi`'ndan ayrı yazılmış sorgu | Birebir | 0 fark; görünümde eksik departman yok (Ek#4) | ✅ |
| E2 | Toplamlar = `v_puantaj_canli` | Çalışılan gün, fazla mesai | Aynı | 1588 = 1588; 600 = 600 (Ek#7) | ✅ |
| E3 | Hem çalışılan hem bekleyen | Bir günde soru açıkken İK `tamam` yaptı (hesap ✗) | Gün bir kez sayılır | Montaj: çalışılan 208 → 209, bekleyen 3 olduğu gibi kaldı; aynı gün iki sütunda (Ek#2–6) | ❌ T-91 |
| E4 | Amir kendi departmanını mı görüyor | montaj.amiri, bobinaj.amiri, uretim.muduru, genel.mudur | Yalnızca kendi (ve vekili olduğu) departman | montaj: Montaj + Bobinaj (seed'de Bobinaj'ın vekili); bobinaj: Bobinaj; uretim.muduru: yalnızca İdari İşler; genel.mudur: yalnızca Üst Yönetim (Ek#9–12, #20) | ✅ (üst amirin bağlı departmanları görmemesi: Görüş, aşağıda) |
| E5 | Amirin gördüğü sayılar elle ile aynı mı | Montaj: çalışılan / bekleyen / açık soru | 209 / 3 / 3 | Amir: 209 / 3 / **2**; Bobinaj'ı vekil olarak görürken açık soru **0** (Bobinaj amiri 1 görüyor) (Ek#9–10, #18–19) | ❌ T-98 |
| E6 | Yönetici ve İK | fabrika.muduru, ik.uzmani | 19 departman | 19 / 19; sayılar elle ile aynı (Ek#13–14) | ✅ |
| E7 | Güvenlik, İSG, admin | | Hiçbir şey | 0 / 0 / 0 (Ek#15–17) | ✅ |
| E8 | `v_esnek_mesai` = elle | 4 çalışan: hedef gün, hedef dk, gerçekleşen, fark, bekleyen | Birebir | 0 fark (ör. 6002: hedef 21 gün / 10080 dk, gerçekleşen 9928, fark −152) (Ek#22) | ✅ |
| E9 | `v_esnek_mesai` = `v_puantaj_canli` | `esnek_hedef_dk`, `esnek_fark_dk` | Aynı | 0 fark (Ek#23) | ✅ |
| E10 | `v_esnek_mesai`'yi kim görüyor | 8 rol | Esnek çalışanın amiri, yönetici, İK | arge.amiri 2 (kendi), satış çalışanlarını yalnızca yönetici ve İK görüyor; montaj, bobinaj, güvenlik, İSG, admin 0 (Ek#25–33) | ✅ |
| E11 | Saniyesiz okutma zamanı | `dosya_yukle` ile `07:55+03:00` (saniyesiz) | Kabul ya da ret, bilinçli | Kabul; `07:55:00` olarak yazıldı (Ek#34–41) | ⚠️ T-99 |
| E12 | Saniyesiz okutma ve kart paylaşımı | SA ve SB 5 gün aynı dakikada, saniyesiz. SC ve SD aynı dakikada, saniyeli, 30 sn arayla | Paylaşım uyarısı yok | SA/SB: **"5 farklı günde 5 saniye içinde"** uyarısı; SC/SD: uyarı yok (Ek#43) | ❌ T-99 |
| E13 | Kilitten sonra ayar değişince fark | H1 22.09 giriş 08:05 (tolerans 10 → geç 0), Eylül kilitlendi. Admin toleransı 0 yaptı; İK girişi 08:12 olarak düzeltti; Ekim kilitlendi | Geç kalma 12 dk (eski kuralla da yeni kuralla da) | Ekim fark satırı: geç **+7**, çalışma −7. Kilit + fark = geç **7** dk. `gun_katkisi`'nın "önce" değeri bugünkü ayarla geç 5 (Ek#47–54) | ❌ T-100 |

**Üst amir görünümü (Görüş, bulgu değil):** uretim.muduru 7 departmanın üst amiri, ama yönetici panelinde yalnızca amiri olduğu İdari İşler'i görüyor (Ek#11). RLS'e göre doğru (`oturum_departmanlari` yalnızca `amir_id` / `vekil_amir_id`). Üst amirin bağlı departmanları görmesi isteniyorsa bilinçli bir karar gerekir.

### T-98 · Yönetici panelinde "açık soru" sayısı bakan kişiye göre değişiyor; amir kendi departmanının üst amire gitmiş sorularını, vekil amir vekili olduğu departmanın sorularını görmüyor
- **Adım:** 12 (ek) · **Önem:** Düşük
- **Yer:** `v_departman_ozet` (`security_invoker = true`) içindeki `acik_soru` alt sorgusu `amir_sorusu`'nu sayıyor. `amir_sorusu` RLS'i amire yalnızca `atanan_id` ya da `eskale_edilen_id` kendisi olan soruları gösteriyor.
- **Ne oldu:**
  - Montaj'da 3 açık soru var. Yönetici ve İK 3 görüyor; montaj.amiri 2 görüyor (birisi üst amire eskale olmuş).
  - montaj.amiri seed'de Bobinaj'ın vekili; panelde Bobinaj satırını görüyor ama açık soru 0. Bobinaj amiri aynı satırda 1 görüyor.
  - Diğer sütunlar (çalışılan, bekleyen) bakandan bağımsız, doğru.
- **Ne olmalıydı:** Aynı satırda aynı sayı. Ya sütun departmanın bütün açık sorularını saysın, ya da adı "size atanmış açık soru" olsun.
- **Kanıt:** Ek#18 `montaj.amiri: 209/3/2` · Ek#19 elle `209/3/3` · Ek#9 `Bobinaj (203 gün, açık soru 0)` · Ek#10 bobinaj.amiri `Bobinaj (… açık soru 1)` · `amir_okur` politikası: `oturum_kullanici_id() = atanan_id or = eskale_edilen_id`.
- **Sade dille:** Montaj amiri panelde "2 açık soru" görüyor, fabrika müdürü aynı departman için "3" görüyor. Amir, üst amire giden sorunun hâlâ açık olduğunu panelden anlayamıyor. Vekil amir de vekili olduğu departmanda hiç açık soru yokmuş gibi görüyor (T-43 ile aynı kök).
- **Öneri:** `acik_soru` alt sorgusu bir `security definer` yardımcı fonksiyonla (yalnızca sayı döner, satır göstermez) departmanın bütün açık sorularını saysın; ya da sütun ikiye ayrılsın: "departmanda açık" ve "bana atanmış".
- **Durum:** Açık

### T-99 · Saniyesiz okutma zamanı kabul ediliyor; dosya saniyesiz gelirse aynı dakikada okutan herkes "kart paylaşımı şüphesi"ne düşüyor
- **Adım:** 12 (ek; Adım 12 şüphesinden) · **Önem:** Orta
- **Yer:** `pdks.dosya_yukle`: zaman deseni `HH:MM(:SS)?` (saniye isteğe bağlı); `pdks.kart_paylasim_kontrol`: aynı okuyucuda ardışık iki farklı kart arasındaki süre `≤ kart_paylasim_sn` (5 sn).
- **Ne oldu:** SA ve SB 5 gün boyunca aynı okuyucuda aynı dakikada okuttu, dosyada saniye yok. İkisi de `07:55:00` olarak yazıldı; aralarındaki süre 0 sn sayıldı ve "5 farklı günde 5 saniye içinde" uyarısı çıktı. Aynı dakikada ama saniyeli, 30 sn arayla okutan SC ve SD için uyarı çıkmadı. Günlerin kendisi doğru hesaplandı.
- **Ne olmalıydı:** Paylaşım kontrolü dakika hassasiyetli veriyle çalışamaz. Ya dosya saniyeli olmak zorunda olmalı (deseni zorunlu saniye), ya da dosyanın hassasiyeti (ör. `aktarim.saniyeli`) kaydedilip saniyesiz dosyada paylaşım kontrolü atlanmalı ve bu İK'ya söylenmeli.
- **Kanıt:** Ek#34–40 `dosya_yukle … OK` (saniyesiz satırlar) · Ek#41 `07:55:00, 17:05:00` · Ek#43 `Kart paylaşımı şüphesi: S12SA … ve S12SB … 5 farklı günde 5 saniye içinde …` · SC/SD için uyarı yok · Adım 12'de aynı saniyede okutan 17 kişiden 73 uyarı (#8).
- **Sade dille:** Fabrikanın PDKS cihazı dosyayı saniyesiz verirse, vardiya başında aynı dakikada kart okutan yüzlerce işçi sistemin gözünde "aynı anda" okutmuş olur. Her ay her gün yan yana gelen çiftler için "kart paylaşımı şüphesi" çıkar. İK bu yanlış alarmlarda boğulur, gerçek paylaşımı gözden kaçırır. Kararın kaydedilememesi (T-81) bunu daha da kötüleştiriyor.
- **Öneri:** Önce gerçek PDKS çıktısının biçimi öğrenilsin (Atlas Trafo BT'si). Saniyeli ise `dosya_yukle`'de saniye zorunlu olsun; saniyesizse kart paylaşımı kontrolü bu dosyalar için kapatılsın ve İK ekranında "dosya dakika hassasiyetinde; paylaşım kontrolü yapılamıyor" yazsın. Kalıcı test: saniyesiz dosya reddedilir (ya da paylaşım uyarısı üretmez).
- **Durum:** Açık

### T-100 · Fark hesabı kilitli ayın "önce" değerini bugünkü ayarla hesaplıyor; ayar kilitten sonra değişmişse fark yanlış çıkıyor
- **Adım:** 12 (ek; Adım 12 şüphesinden) · **Önem:** Orta
- **Yer:** `pdks.puantaj_yaz` → `pdks.gun_katkisi(gün, önceki_düzeltmeler)` → `pdks.gun_hesabi(...)`. "Önce" durumu kilitteki puantajdan değil, gün kaydından bugünkü ayarlarla yeniden hesaplanıyor. Bağlantı: T-74 (ayar sınırları), T-10 (ayarı admin değiştirir).
- **Ne oldu:**
  - H1 22.09'da 08:05'te geldi. Tolerans 10 dk olduğu için geç kalma 0; Eylül böyle kilitlendi.
  - Admin toleransı 0 yaptı. İK sonra girişi kapı kaydına göre 08:12 olarak düzeltti.
  - Doğru sonuç: 08:12, 10 dk toleransı aştığı için eski kuralla da 12 dk, yeni kuralla da 12 dk geç.
  - Fark hesabı "önce"yi bugünkü toleransla 5 dk geç saydı, "sonra"yı 12 dk; fark +7 yazdı. Kilit (0) + fark (7) = **7 dk**. Bordroya 5 dk eksik geç kalma gitti.
- **Ne olmalıydı:** "Önce" değeri kilit anında puantaja ne yazıldıysa o olmalı (ya da günün kilit anındaki hesap sonucu saklanmalı). Fark yalnızca düzeltmenin etkisini taşımalı, ayar değişikliğinin değil.
- **Kanıt:** Ek#47 `H1 22.09 kilitteki puantaj (tolerans 10) | gün: geç 0, çalışma 475 | satır: geç 0` · Ek#48 tolerans 10 → 0 · Ek#50 `gun_katkisi "önce" (bugünkü ayarla) | geç 5` · Ek#52 `Ekim fark satırı (H1) | geç 7, çalışma -7` · Ek#53 `kilit + fark = 7` · Ek#54 `gun_hesabi 08:12 (bugünkü ayar) | geç 12, çalışma 468`.
- **Sade dille:** Bir ay kapandıktan sonra biri geç kalma toleransını değiştirir, sonra da o kapalı aydan bir kaydı düzeltirse, sistem farkı yanlış hesaplıyor. Bu örnekte işçinin 12 dakikalık geç kalması bordroya 7 dakika olarak gitti; ayar ters yöne değişseydi işçinin aleyhine olurdu. Hata hiçbir yerde uyarı vermiyor; ancak elle hesapla bulunur.
- **Öneri:** Fark için "önce" değeri `gun_katkisi` ile yeniden hesaplanmasın; kilit anındaki gün katkısı (gün başına puantaj ayrıntısı) kilitte saklansın (ör. `puantaj_gunu` tablosu: gün, kod, dakikalar) ve fark "yeni hesap − saklanan" olsun. Kısa yol: ayarlar tarihli tutulsun (`ayar_gecmisi` zaten var) ve `gun_hesabi` günün kilit tarihindeki ayarla çalışsın. Kalıcı test: kilitten sonra tolerans değişip düzeltme gelince fark yalnızca düzeltmeyi yansıtır.
- **Durum:** Açık

### T-101 · Kilit, kodsuz kalan günlerin listesini vermiyor; yalnızca sayıyor
- **Adım:** 12 (ek; Adım 12 şüphesinden) · **Önem:** Görüş
- **Yer:** `pdks.ay_kilitle`: `kodsuz_gun` yalnızca `count(*)`; mesaj "Puantaja kodsuz giren gün: 7."
- **Ne oldu:** Eylül kilidi "7 kodsuz gün" dedi. Hangi çalışanın hangi günü olduğu yalnızca ayrı bir sorguyla bulundu (L2 16–18.09, Q1 29.09, Q2 07.09, Q3 08.09, Q4 09.09). Ekim'de "1" dedi (E41 09.10). Hesaplanamayan günlerin neden hesaplanamadığı (açık soru, tek saatli cevap, hesap ✗) da yazılmıyor.
- **Ne olmalıydı:** Özet kodsuz günlerin listesini (sicil, gün, neden) döndürmeli ve T-92'deki kilit kaydına yazmalı; kilitten önce de aynı liste görülebilmeli (T-96'daki ön kontrol).
- **Kanıt:** #12 `"kodsuz_gun": 7` · #15 kapsama listesi (ayrı sorguyla) · #72 `"kodsuz_gun": 1`.
- **Sade dille:** Sistem "7 gün boş kaldı" diyor ama hangi 7 gün olduğunu söylemiyor. İK bunları bulmak için ekranda çalışanları tek tek açmak zorunda.
- **Öneri:** `kodsuz_gun_listesi jsonb` (sicil, gün, durum, neden); T-92 ve T-96 ile birlikte tek değişiklik.
- **Durum:** ✅ Düzeltildi — PR #54 (T-90 ile; `kodsuz_gun_listesi` ve hata mesajındaki gün listesi). Ön kontrol (T-96) ve kilit kaydına yazma (T-92) açık.

### Eski bulgularla karşılaştırma
- **T-39 / T-41:** Kilitte ne olduğu bu adımda görüldü. Eskale soru (Q2) zorla geçiliyor; tek saatli cevap (Q3, E41) zorla bile gerekmeden geçiyor. İkisi de kodsuz giriyor ve ERP'de görünmüyor (T-90). T-39'daki Z1 vakası (Q4) ayrıca satır / kalem çelişkisi yaratıyor (T-91).
- **T-63:** Yeniden doğrulandı. Bekleyen FM talebi kilidi engellemiyor, özette yok; kilitten sonra karar verilemiyor (#33). Tutarsızlık: aynı kilitli ayda havuz onayı (#34) ve vardiya planı onayı (#31) kabul edilip fark olarak yazılıyor; yalnızca FM planı kararı reddediliyor.
- **T-79:** Plansız Cumartesi puantajda HT olarak görünüyor (#28); emek kaybı ERP'ye kadar gidiyor.
- **T-81:** Kararı verilmemiş paylaşım şüphesi kilidi engellemiyor, özette yok.
- **T-67:** Kilitli aya düşen çıkışın fark kısmı burada sınandı: düzeltmeler Ekim'e gidiyor, ama satır oluşmuyor (T-95).
- **T-48:** Kilitli aya izin girilebiliyor; ileri ay kilidinde de (İ#4).

### Bulgular önem sırasıyla
1. **T-89** · Yüksek · İleri ay kilitlenebiliyor; kilit açılamıyor.
2. **T-90** · Yüksek · Askıdaki gün kodsuz ve görünmez; zorlamadan kilit de geçiriyor.
3. **T-91** · Orta · Satır ile kalem "tamam ama hesaplanmamış" günü farklı sayıyor.
4. **T-92** · Orta · Zorla kilit gerekçesiz ve izsiz.
5. **T-93** · Orta · Kilitli ayda plan onayı yalnızca kaybı yazıyor; havuz yok.
6. **T-94** · Orta · Planı olmayan izin günü HT kodlanıyor.
7. **T-95** · Düşük · Yalnızca kodu değişen fark kayboluyor.
8. **T-97** · Düşük · Kilitli döneme sistem yoluyla satır eklenebiliyor.
9. **T-96** · Görüş · Kilit engelleri tek tek; ön kontrol yok.

Ek denemelerden (onaydan sonra eklendi):
- **T-99** · Orta · Saniyesiz okutma zamanı kabul ediliyor; aynı dakikada okutan herkes kart paylaşımı şüphesine düşüyor.
- **T-100** · Orta · Fark hesabı kilitli ayı bugünkü ayarla yeniden hesaplıyor; ayar değişince fark yanlış (T-74 ile bağlantılı).
- **T-98** · Düşük · Yönetici panelindeki açık soru sayısı bakan kişiye göre değişiyor.
- **T-101** · Görüş · Kilit kodsuz günlerin listesini vermiyor.

Yeniden görülen eski bulgular: T-39, T-41, T-48, T-63, T-67, T-79, T-81.

### Denediklerim
- 119 + 6 çağrı (`scratch/a12_puantaj_sonuc.txt`, `scratch/a12_ileri_sonuc.txt`).
- Engeller tek tek: işlenmemiş planlı gün, işlenmemiş güne bekleyen plan (zorla da), işlenmiş güne bekleyen plan, onaysız FM, açık soru, eskale soru, açık itiraz, bekleyen FM talebi, paylaşım şüphesi, askıdaki gün.
- Zorlamadan kilit (Ekim) ve zorla kilit (Eylül, Kasım); özet ile bağımsız sayım; kodsuz gün sayısı ile gerçek kodsuz günler; zorla kilidin izi; kim kilitler (6 rol).
- Kapsama (733 çalışan-gün; eksik ve çift kod), satır = `v_puantaj_canli`, satır = kalem; ay ortası giriş ve çıkış; plansız Cumartesi; planı olmayan izin günü.
- Kilitli ayda: gün kaydının değişmemesi (RPC ve doğrudan), plan girişi, tek ve çift düzeltmenin farkı (elle hesapla), aynı güne başka aylara giden düzeltmeler, iki ay sonra gelen düzeltme; kilitten sonra soru cevabı, havuz onayı, plan onayı, FM talebi kararı, itiraz kararı; kilitli aya düşen çıkış.
- Kilidi açma, ikinci kez kilit (normal ve zorla), dönem silme, puantaj satırı / kalemi değiştirme, silme, ekleme, `duzeltme` değiştirme.
- ERP: satır sayısı, kodlar, fark satırlarının kaynak dönemi, kim görür.
- İleri ay, içinde bulunulan ay, boş geçmiş ay kilidi.

### Denemediklerim
- **Ekrandan (HTTP) kilit:** 2000 çalışanda `ay_kilitle` ve `puantaj_yaz`'ın 8 sn zaman aşımına sığıp sığmadığı (T-24'e benzer risk).
- **İki İK'nın aynı anda kilitlemesi:** `donem_kilitle` dönem satırını `for update` ile kilitliyor; denenmedi.
- **FM100, gece vardiyası, esnek mesai, raporlu, devamsız ve resmî tatil günlerinin kodları ve farkları:** Ekim'deki 29.10 (RT) günleri kapsamada "tam 1" çıktı, ama kod türleri tek tek doğrulanmadı.
- **`v_departman_ozet` ve `v_esnek_mesai`:** Ek denemelerde yapıldı (yukarıda). Esnek günde devamsızlık ya da soru bekleyen gün seed'de olmadığı için `hedef_gun`'un bu günleri nasıl saydığı veriyle denenmedi (kod: hedefe sayılıyor).
- **Ayar değiştikten sonra gelen fark:** Ek denemelerde yapıldı (T-100).
- **Saat dilimi:** `ay_kilitle` ve fark hesabında İstanbul / UTC farkı (gün sınırındaki gece vardiyası).

### Şüpheler
- **Kart paylaşımı yanlış alarm üretebilir:** → T-99 olarak bulgulara alındı (saniyesiz dosyayla kanıtlandı). Bu adımda çalışanlar aynı okuyucuda aynı saniyede (07:55:00) okuttuğu için Eylül'de 73, Ekim'de 28 "kart paylaşımı şüphesi" çıktı (#8, #53). Benim kurduğum veri gerçekçi değil; ama `dosya_yukle` saniyesiz zamanı da kabul ediyor (`HH:MM`). Gerçek PDKS dosyası saniyesiz gelirse, aynı dakikada okutan herkes "0 sn arayla" sayılır. Vardiya başında tek okuyucunun önündeki kuyrukta sürekli yan yana duran iki işçi de 5 sn eşiğine takılabilir. Gerçek bir PDKS dosyasının zaman biçimi ve vardiya başı okutma sıklığıyla bakılmalı (T-81 ile birlikte).
- **Fark hesabı bugünkü ayarla yapılıyor:** → T-100 olarak bulgulara alındı (kanıtlandı). `gun_katkisi`, kilitli ayın "önce" durumunu da `gun_hesabi`'nı yeniden çağırarak hesaplıyor. Kilitten sonra bir ayar (tolerans, mola) değişmişse (T-74), "önce" değeri kilit anındaki puantajla tutmayabilir; fark, düzeltmeden değil ayar değişikliğinden de pay alır.
- **Boş geçmiş ay kilitlenebiliyor:** Ağustos 2026 (veri yok) kilitlendi. Canlıya geçişten önceki aylar için zararsız; ama yanlışlıkla kilitlenen boş bir ay, sonradan geçmiş veri aktarılmak istenirse (geç gelen dosya, T-19) fark yoluna zorlar.
- **Kilit, gün hesabı yapılamayan günleri sessizce yeniden hesaplamayı deniyor:** → liste eksikliği T-101 olarak bulgulara alındı. `ay_kilitle`'nin ilk adımı hesaplanmamış her gün için `gun_hesapla` çağırıyor; hesaplanamayanlar sessizce kalıyor. Sonuç özetin sonundaki "kodsuz gün" sayısında görünüyor, ama hangi günler olduğu söylenmiyor (T-96 ile birlikte).

---

## Adım 13 — Uçtan uca: Kasım'ın tamamı ve demo akışı (22 Kasım 2026)

**Başlangıç:** `main` @ `79ad042` (31 migration). Yerel veritabanı `supabase db reset` ile kuruldu. Raporun commit edilmemiş hali önce yedeklendi (`scratch/a13_rapor_yedek_reset_oncesi.md`); sıfırlamadan önce ve sonra özeti aynı. `docs/duzeltme_rehberi.md`'ye dokunulmadı.

**Betikler:**

| Betik | Ne sınıyor |
|---|---|
| `scratch/a13_ortak.sql` | Ortak yardımcılar: rol taklidi, CSV'yi ekranın biçimine çevirip `dosya_yukle`'ye verme, puantaj doğrulama |
| `scratch/a13_ay.sql`, `_sonuc.txt` | A: Kasım'ı gerçek bir ay gibi oynama (50 çağrı) |
| `scratch/a13_demo.sql`, `_sonuc.txt` | B: `docs/demo_akisi.md` adım adım (49 çağrı) |

**Yöntem:**
- Her işlem, ekranın çağırdığı RPC ile ve o rolün kullanıcısıyla yapıldı (rol taklidi). RPC adları ekran kodundan çıkarıldı (`app/(panel)/*/actions.ts`, `veri-aktarimi/aktarim-formu.tsx`).
- 7 Aralık CSV'leri `demo/` klasöründen okundu ve ekranın yaptığı gibi `+03:00`'lı zamanla `dosya_yukle`'ye verildi.
- Her betik tek işlem, sonda `ROLLBACK`. A ve B birbirinden bağımsız: B, A'nın değişikliklerini görmüyor.
- Kanıtlardaki `A#n` / `B#n` = ilgili sonuç dosyasındaki çağrı numarası.

### A. Kasım'ı gerçek bir ay gibi oynama

| # | Adım | Ne yaptım (rol → RPC) | Beklenen | Gerçekleşen | |
|---|---|---|---|---|---|
| A1 | Gece işi | ik.uzmani → `gece_isi_tetikle(01.11, 30.11)` | 30 gün başarılı | 30/30 `basarili`; 1597 gün kaydı; 4 açık soru, 3 havuz kaydı, 1 işlenmemiş gün (S13) (A#1–3) | ✅ |
| A2 | Soruların durumu | — | Amirde açık | 4 sorunun **dördü de `eskale`**: S2, S4, S19 üretim müdürü Levent Sarı'da; S22 (Levent'e atanmıştı) İK'da (Elif Şen) (A#2) | ⚠️ T-39 ile aynı kök (aşağıda) |
| A3 | Soruları amir cevaplar | montaj.amiri → S2 "geldi, saat doğru", S4 "bilmiyorum"; bobinaj.amiri → S19 "gelmedi"; uretim.muduru → S22 "saat farklı", giriş 07:58 (`soru_cevapla`) | Kabul (eskale olsa da atanan cevaplayabilir) | 4/4 OK (A#4–7) | ✅ |
| A4 | İK kararı | ik.muduru → S4 devamsız değil, çıkış 17:00; S19 devamsız (`soru_ik_karari`) | Kabul | 2/2 OK; açık soru 0. Ali 08:30–17:03 (geç 30, 450 dk), Mustafa 07:45–17:00 (480), Kaan devamsız, Hasan 07:58–17:07 (480) (A#8–11) | ✅ |
| A5 | İtiraz kabul | kalite.amiri → `itiraz_gir` (Selin 09.11, geç 35); ik.uzmani → `itiraz_incelemeye_al`, `itiraz_karar(kabul)`, `kayit_duzelt(giriş 08:00, itiraza bağlı)` | Geç 0 | Geç 0, 480 dk; giriş kaynağı `ik` (A#12–17, #19) | ✅ |
| A6 | İtiraz ret | kalite.amiri → `itiraz_gir` (Gizem 20.11); ik.uzmani → `itiraz_karar(ret)` | Gün değişmez | Değişmedi; itiraz `red` (A#14, #18–19) | ✅ |
| A7 | Havuz kararı | ik.muduru → `fazla_mesai_inceleme_karar`: Ece 150 dk onay (yazılı onay var), Merve 100 ret, Erkan 485 ret (yazılı onay yok) | Kabul | 3/3 OK (A#20–23) | ✅ |
| A8 | S13 planı | ik.uzmani (planı giren) onaylamayı dener; ik.muduru onaylar (`vardiya_plani_onayla`) | Giren onaylayamaz; müdür onaylar, gün işlenir | "kendi girdiğiniz planı onaylayamazsınız"; müdür OK; Okan 13.11 V2 ile `tamam`, 420 dk; yeni havuz kaydı yok (A#24–27) | ✅ |
| A9 | Zorlamadan kilit | ik.muduru → `ay_kilitle(2026, 11, false)` | Kilit | **Kilitlendi**, kodsuz 0, zorla geçilen 0. Kalan tek şey görülmemiş 1 paylaşım uyarısı (engel değil, T-81 ile aynı) (A#28–30) | ✅ |
| A10 | Her gün tam bir kez | 76 çalışan × 30 gün | 0 eksik, 0 çift | 2280 / 2280 tam 1 (A#31) | ✅ |
| A11 | Çalışılan gün | satır / gün kaydı (hesap ✓) | Aynı | 1591 / 1591; NÇ 1589 + FM100 2 = 1591 (A#32) | ✅ |
| A12 | Devamsız | | 1 (Kaan) | Satır 1, DVMSZ 1, gün kaydı 1 (A#32) | ✅ |
| A13 | HT | Çalışma tarihleri içinde gün kaydı olmayan günler, elle | Aynı | Kalem 682 = elle 682 (A#32) | ✅ |
| A14 | RT | Kasım'da resmî tatil yok | 0 | 0 (A#32) | ✅ |
| A15 | İzin / rapor | | | İzinli 3 = Yİ 2 + MZR 1; raporlu 3 = RPR 3 (A#32) | ✅ |
| A16 | Fazla mesai | | FM50 = Gizem 120 + Ece 150; FM100 = Mehmet 480 | FM50 270 dk, FM100 480 dk; satır = kalem = gün kaydı (A#32) | ✅ |
| A17 | Reddedilen Pazar çalışması | Erkan 29.11 (yazılı onay yok, havuz reddedildi) | Çalışılmış gün ya da HT, açık bir kodla | ERP'de **FM100 1 gün / 0 dk** (A#36) | ❌ T-102 |
| A18 | Satır = `v_puantaj_canli`, satır = kalem | | Birebir | 0 fark / 0 fark (A#33–34) | ✅ |
| A19 | ERP | `v_puantaj_aktarim` | Kalem sayısı kadar satır | 160 = 160; kodlar DVMSZ, FM100, FM50, HT, MZR, NÇ, RPR, Yİ (A#32, #35) | ✅ |
| A20 | Kilitten sonra itiraz kabul | kalite.amiri → `itiraz_gir` (Selin 13.11, erken 40); ik.uzmani → kabul, `kayit_duzelt(çıkış 17:00)` | Gün değişmez, hedef Aralık | Gün aynı (erken 40); düzeltme `fark=true hedef=2026/12` (A#37–40) | ✅ |
| A21 | Aralık fark satırı | 7 Aralık dosyaları + gece işi + 2 soru; `ay_kilitle(2026, 12, false)` | Fark: NÇ +40 dk, erken −40, kaynak Kasım | NÇ 0/+40, erken −40, kaynak `2026-11` (A#41–50). Fark satırı ancak Aralık kilitlenince oluştu; Aralık bugün (22.11) kilitlenebildi | ✅ / ⚠️ T-89 ile aynı |

**Zorlamadan kilit mümkün oldu.** Tek şartı: dört sorunun doğru kişiyle kapatılması, havuzun karara bağlanması ve S13 planının **planı girmeyen** bir İK kullanıcısıyla onaylanması.

### B. Demo akışı (`docs/demo_akisi.md`, yazıldığı gibi)

| # | Belgedeki adım | Belgede yazan | Veritabanında | |
|---|---|---|---|---|
| B1 | 1. Kasım'ın 4 açık sorusu | S2, S4, S19, S22 | 4 soru, aynı kişiler (B#2) | ✅ |
| B2 | 1. S22 | Hasan'ın kendi kaydı; üst amiri Levent Sarı'ya gitti | Atanan Levent Sarı ✅; ama gece işi bütün Kasım'ı işleyince soru **İK'ya (Elif Şen) eskale olmuş**. S2, S4, S19 de Levent'e eskale (B#2–3) | ⚠️ T-103 |
| B3 | 1. Uyarılar | S6 İbrahim ve S9 Burak çakışma; S9 iade yok; S7 Osman 3 kez; S11 paylaşım; S23 zimmetsiz | Altısı da var, kişiler aynı (B#5) | ✅ |
| B4 | 2. İbrahim 10 Kasım | Gün boyu GK-01, okutmalar ona | GK-01 07:42 ve 17:09 İbrahim'e; gün tamam 480 (B#7) | ✅ |
| B5 | 2. Osman | 11, 17, 19 Kasım | GK-03 11.11, GK-03 17.11, GK-01 19.11 (B#8) | ✅ |
| B6 | 2.1 GK-02 iade | S9 kapanır | Zimmet kapandı; S9'un iki uyarısı "görülmedi" olarak duruyor (B#9–10) | ✅ (ifade: "zimmet kapanır") |
| B7 | 2.2–2.3 Osman'a GK-01, iade | Saatle zimmet, hemen iade | OK / OK; açık zimmet 0 (B#11, #13–14) | ✅ |
| B8 | 2.4 Çakışma mesajı | "GK-01 kartı Osman Doğan'a … verilmiş zimmetle çakışıyor (henüz iade edilmedi)" | Birebir aynı mesaj (B#12). **Ama** yalnızca 2.2 ile 2.3 arasında gösterilirse çıkıyor; belgede 2.3'ten sonra yazılı | ⚠️ T-103 |
| B9 | 3.1 Dört dosya | Satırları denetler, yükler | pdks 16, kapı 19, yemekhane 10, servis 12 satır (B#16–20) | ✅ |
| B10 | 3.2–3.3 Gece işi özeti | 10 gün kaydı, 2 kanıtla düzeltme, 2 amir sorusu, 8 hesaplanan gün, yeni uyarı yok | `gun_kaydi 10, duzeltme 2, soru 2, hesap 8, uyari 0, eskale 0`; yeni uyarı 0 (B#21, #24) | ✅ |
| B11 | 3. Yalnızca Montaj'ın 10 kişisi planlı | | 10 plan, yalnızca Montaj (B#22) | ✅ |
| B12 | 3. Veli | Giriş 08:00, kanıt | 08:00, giriş kaynağı `kanit` (B#23) | ✅ |
| B13 | 3. Hüseyin | Çıkış 17:09 | 17:09, çıkış kaynağı `kanit` (B#23) | ✅ |
| B14 | 3. Ali | Soru "kanıt vardiya başından sonra", öneri 08:29 | `kanit_vardiya_sonrasi`, öneri 08:29 (B#23) | ✅ |
| B15 | 3. Mustafa | Soru "çıkış yok" | `cikis_yok` (B#23) | ✅ |
| B16 | 3. Diğer 6 kişi | Tamam, 480 dk | 6 / 6 tamam 480 (B#23) | ✅ |
| B17 | 3. Veli'nin düzeltme izi | Gerekçe "Kapı kaydı 07:46, vardiya başından önce; giriş vardiya başı olarak yazıldı"; silinemez | Birebir aynı gerekçe, kaynak `gece_isi`; silme `permission denied` (B#26–27) | ✅ |
| B18 | Hazırlık: aynı dosya ikinci kez | "Bu dosya daha önce yüklenmiş." | Birebir aynı (B#28) | ✅ |
| B19 | 4.1 Ali "Geldi, saat doğru" | Giriş 08:29, hemen hesaplanır | 08:29–17:01, hesap ✓ (B#29–30) | ✅ |
| B20 | 4.2 Mustafa "Bilmiyorum" | İK kararına gider; amir devamsızlık veremez | `ik_karari_bekliyor`; amirin `soru_ik_karari` denemesi "yetkiniz yok" (B#31–33) | ✅ |
| B21 | 5. Mustafa İK kararı | Devamsız değil, çıkış 17:00 | OK (B#34) | ✅ |
| B22 | 5. Sonuç | Ali geç 29, çalışma 451; Mustafa 480 | Ali geç 29, 451; Mustafa 07:44–17:00, 480 (B#35) | ✅ |
| B23 | 6. Havuzda 3 kayıt | Ece 150; Merve 100, yazılı onay yok; Erkan 485, 29 Kasım Pazar, yazılı onay yok | Üçü de aynı; yazılı onay Ece var, Merve ve Erkan yok (B#36–37) | ✅ |
| B24 | 6. Mehmet 22 Kasım | FM100 480 | FM100 480, kod FM100 480 (B#38) | ✅ |
| B25 | 6. Esnek | Onur −152, İrem +29 | −152, +29 (ayrıca Pınar −37, Kerem +35) (B#39) | ✅ |
| B26 | 6. İrem 18 Kasım | Giriş 09:17 kapı kaydından; amire soru yok | 09:17, kaynak `kanit`; soru yok (B#40) | ✅ |
| B27 | 6. Excel / PDF | FM50 / FM100 / gece / mola sütunları | `v_puantaj_canli`'de dört sütun da dolu (B#41); Excel ve PDF'in kendisi denenmedi | ⚠️ denenmedi |
| B28 | 7. Uğur | Eğitim 10 Kasım'da doldu; uyarı; kapı kilitlenmedi; bölge uyarısı yok | `_doluyor` + `_dolmus` ("Kapı kilitlenmedi"); bölge uyarısı yok; `v_isg_durum` dolmus (B#42–43) | ✅ |
| B29 | 7. Taner | Muayene 15 Aralık'ta doluyor | `_doluyor` 15.12.2026; `v_isg_durum` doluyor (B#42–43) | ✅ |
| B30 | 7. Selim / Hakan | Selim yetkisiz, Hakan'a uyarı yok | Selim 19.11 14:10 yetkisiz; Hakan için uyarı yok (B#42) | ✅ |
| B31 | 8. Fabrika müdürü | Her şeyi görür, karar veremez | 1607 gün kaydı, 6 soru, 20 uyarı, 20 departman özeti satırı; `itiraz_gir` ve `uyari_goruldu` "yetkiniz yok" (B#44–46) | ✅ |
| B32 | 8. Sistem yöneticisi | Gün kaydı, izin, puantaj göremez | 0 / 0 / 0; kullanıcılar 25, ayarlar 26 (B#47). Çalışan listesini görüyor (T-80 ile aynı) | ✅ / ⚠️ T-80 |
| B33 | 9. Görüntü hazırlığı | S13 planı zorla da geçilmez | "gece işinden geçmemiş 1 planlı gün … zorla geçilemez" (B#48) | ✅ |
| B34 | 9. Görüntü hazırlığı | 4 soru kapatılır, sonra zorlamadan kilit | A'da yapıldı ve çalıştı (A9). Belge soruların **kim tarafından** kapatılacağını söylemiyor; S2, S4, S19 üst amirde, S22 İK'da (B#49) | ⚠️ T-103 |
| B35 | 9.5 Kilitten sonra düzeltmenin fark satırı | Görüntüsü alınır | Fark satırı ancak **sonraki ay da kilitlenince** puantajda oluşuyor (A21). Belge bunu söylemiyor; Aralık'ı yerelde kilitlemek gerekiyor | ⚠️ T-103 |

### Demo risk listesi (bilinen bulgular)

| Bulgu | Demoda nerede çıkabilir | Ne olur | Nasıl kaçınılır |
|---|---|---|---|
| T-39 | 1. adım, Sorular | Kasım'ın 4 sorusu: S2 ve S4 üst amirden İK'ya geçmiş, S19 Levent'te (7 Aralık'ta o da İK'da), S22 İK'da | ✅ Düzeltildi (PR #55; canlıya 20261210010000 uygulandıktan sonra): İK dört soruya da karar verebilir. Anlatım: "amir → üst amir → İK" |
| T-40 | 4–5. adım | Ali'nin ya da Mustafa'nın sorusu açıkken İK günü `kayit_duzelt` ile düzeltirse, sonraki amir cevabı İK'nın düzeltmesini ezer | Sıra belgedeki gibi: önce amir, sonra İK kararı. İK, açık sorulu günü Çalışanlar ekranından düzeltmesin |
| T-41 | 4. adım | Amir "Saat farklı" deyip yalnızca bir saat girerse gün askıda kalır, soru kapanır | Ali için "Geldi, saat doğru" (saat girmeden); Mustafa için "Bilmiyorum". Doğaçlama yapılmasın |
| T-46 | 4–6. adım | 7 Aralık işlendikten sonra o güne izin girilirse gün değişmez | Demoda izin girilecekse işlenmemiş bir güne (ör. 8 Aralık sonrası) girilsin |
| T-56 | 6. adım | ✅ Düzeltildi: İK Merve'nin ya da Erkan'ın havuz kaydını onaylarsa süre puantaja girer, kayıt "Yazılı onay yok" diye işaretlenir ve uyarı oluşur | Etiket ve uyarı gösterilebilir |
| T-102 (yeni) | 6. adım, Puantaj / Excel | Erkan'ın havuzu reddedilirse ERP'de "FM100 1 gün / 0 dk" görünür | Demoda havuz reddedilmesin; ya da kodun anlamı önceden anlatılsın |
| T-79 | — | 7 Aralık'ta plansız çalışan yok | Yeni veri eklenmesin |
| T-81 | 1. adım, Uyarılar | Paylaşım uyarısında İK yalnızca "görüldü" diyebilir; "karar nerede?" sorusunun cevabı yok | "Sistem uyarır, karar İK'nın elle düzeltmesiyle olur" diye anlatılsın; "görüldü" butonu sonuç bekleniyormuş gibi gösterilmesin |
| T-83 | 2. adım | Osman'a kart demo saatiyle verilir; geçmiş saat seçilemez | Belgedeki gibi "o anın saatiyle" anlatılsın |
| T-86 | 2.4 | Aynı kişiye ikinci geçici kart denenirse mesaj başka kartı anlatır | Çakışmayı belgedeki gibi **başka bir kişiyle** (ör. Burak) ve 2.2 ile 2.3 arasında göster |
| T-89 | 9. adım, Puantaj | Canlıda yanlış ay seçilip "Ayı kilitle"ye basılırsa ay (gelecek ay bile) kalıcı kilitlenir | ✅ Düzeltildi (PR #39 ekran, PR #49 veritabanı; canlıya 20261207010000 uygulandıktan sonra): bitmemiş ay kilitlenemez. Belgedeki kural yine geçerli: canlıda kilit düğmesine basılmaz (bitmiş ay kalıcı kilitlenir) |
| T-90 / T-91 / T-92 | 9. adım görüntüleri | Zorla kilitlenirse kodsuz gün, satır / kalem çelişkisi ve izsiz zorla kilit görüntüye girer | T-90 ✅ (PR #54): kodsuz gün varken zorlamadan kilit reddedilir ve günleri söyler. Görüntüler yine A'daki sırayla, zorlamadan kilitle alınsın (kodsuz 0) |
| T-104 | 8. adım, yönetici paneli | Amir hesabıyla Departmanlar açılırsa sayfa 8 sn'de "Sayfa açılamadı"ya düşer (İK ve yönetici 3,5–4 sn) | ✅ Düzeltildi (PR #48; canlıya 20261206010000 uygulandıktan sonra geçerli): Departmanlar ve Vardiya planı amir hesabıyla da gösterilebilir |
| T-24 | 3. adım | Gece işi ekrandan çok günle çalıştırılırsa 8 sn zaman aşımı | Yalnızca 07.12 – 07.12 çalıştırılsın (belgedeki gibi). Kasım canlı kurulumda SQL Editor'den işlenir |
| T-45 | 3. adım | Demo İstanbul 00:00–03:00 arasında yapılmaz; risk yok | — |
| T-99 | 3. adım | Demo CSV'leri saniyeli; risk yok | Dosyalar değiştirilmesin |
| T-12 | Sorular / Çalışanlar, amir hesabı | Montaj amiri bir çalışanın izin türünü (rapor) görebilir. Belgede yok, ama `docs/ornek_veri.md` S18 "amir türü göremez" diyor | Amir hesabıyla izin ayrıntısı açılmasın; "amir türü göremez" denmesin |
| T-80 | 8. adım | Sistem yöneticisi çalışan listesini görüyor | "Çalışanın gün kaydını, iznini, puantajını göremez" (belgedeki ifade) doğru; "çalışan kayıtlarını hiç görmez" denmesin |
| T-71 / T-72 | 8. adım | Kullanıcılar ekranında çıkmış birinin hesabı açılabilir, başka çalışana İK hesabı açılabilir | Kullanıcılar ekranında hesap açma / aktif yapma gösterilmesin |
| T-74 | 8. adım, Ayarlar | Ayar değeri sınırsız; yanlış değer bütün sonraki hesapları bozar | Ayarlar yalnızca gösterilsin, değiştirilmesin |
| Canlı zamanlama | Demo öncesi | `docs/canli_kurulum.md` 5. adımdaki `cron.unschedule` unutulursa her gece gece işi çalışır: 1–6 Aralık için `dosya_gelmedi` uyarıları birikir, Uyarılar ekranı kalabalıklaşır | Demodan önceki akşam `cron.job`'da `pdks-gece-isi` olmadığı kontrol edilsin (belgenin "canlı kurulum doğrulanmış olmalı" maddesine eklenebilir) |

### Bulgular

### T-102 · Reddedilen tatil çalışması puantajda "FM100 1 gün / 0 dk" kodlanıyor
- **Adım:** 13 · **Önem:** Orta
- **Yer:** `pdks.gun_kod_satirlari`: `durum = 'tamam'` ve `fm100_gunu_mu(gün)` ise kod her zaman `FM100`, gün 1, dakika = `fm100_dk`. Yazılı onayı olmayanın Pazar çalışması `fm100_dk = 0` ile havuza düşüyor (`tatil_calismasi`); havuz reddedilince dakika 0 kalıyor.
- **Ne oldu:** Erkan Duman (5102) 29 Kasım Pazar 08–16 çalıştı, yazılı onayı yok. İK havuz kaydını reddetti. Kasım kilitlendi. ERP'ye Erkan için "NÇ 21 gün" ve "FM100 1 gün / 0 dk" gitti. Puantaj satırında da bu gün "çalışılan gün"e sayıldı (21 + 1 = 22).
- **Ne olmalıydı:** İK'nın reddettiği tatil çalışması için puantajda açık ve tek anlamlı bir kod olmalı. Ya HT (çalışma tatil ücretine dahil değil) ya da bilinçli bir "onaysız tatil çalışması" kodu. "FM100 1 gün" kodu bordro tarafında "tatil mesaisi günü" diye okunabilir: dakika 0 olsa da gün sayısı üzerinden ödeme yapan bir bordro bu günü %100 zamlı öder. Onaylanan (Mehmet: FM100 1 / 480) ile reddedilen (Erkan: FM100 1 / 0) arasındaki tek fark dakika.
- **Kanıt:** A#20 `5102 Erkan Duman 29.11 tatil_calismasi 485 dk yazılı onay=false` · A#23 ret OK · A#36 `5102: FM100 1.0/0, HT 8.0/0, NÇ 21.0/8820` · karşılaştırma `1002: FM100 1.0/480, HT 8.0/0, NÇ 21.0/10080`.
- **Sade dille:** İK "bu Pazar çalışmasını ödemiyoruz" dedi. Ama bordroya giden dosyada o gün "tatil mesaisi, 1 gün" yazıyor. Bordrocu dakikaya değil güne bakarsa işçiye tatil mesaisi öder; dakikaya bakarsa bu günün ne olduğunu anlamaz. Kararın sonucu dosyada açıkça görünmüyor.
- **Öneri:** İK ile karar. Seçenekler:
  - `fm100_dk = 0` ve havuz reddedilmişse kod HT;
  - ya da yeni bir kod (ör. `OTÇ`, onaysız tatil çalışması, gün 1 / dakika = gerçek süre) ve ERP'de ödenmeyen kod olarak tanımlanması.

  Ayrıca `calisilan_gun` bu günü sayıyor mu, belgede yazılsın. Kalıcı test: reddedilen tatil havuzunda kod ve satır tutarlı.
- **Durum:** Açık

### T-103 · `docs/demo_akisi.md`'de üç eksik ya da belirsiz adım
- **Adım:** 13 · **Önem:** Düşük
- **Yer:** `docs/demo_akisi.md`, 1, 2 ve 9. bölümler.
- **Ne oldu:**
  1. **S22 ve diğer Kasım soruları (1. bölüm):** Belge "S22 üst amiri Levent Sarı'ya gitti" diyor. Kasım'ın tamamı gece işinden geçince dört soru da eskale oluyor. S22 İK'ya (Elif Şen), S2 / S4 / S19 Levent'e. Ekranda "kime atanmış" sütunu belgeyle farklı görünebilir.
  2. **Çakışma mesajı (2. bölüm):** 4. madde ("aynı kart ikinci kişiye verilmeye çalışılırsa…") 3. maddeden ("hemen iade al") sonra yazılı. Belgedeki sırayla yapılırsa kart zaten iade edilmiş olur ve mesaj çıkmaz. Mesaj yalnızca 2. ile 3. madde arasında gösterilirse çıkıyor.
  3. **Kilit görüntüleri (9. bölüm):**
     - "Önce bekleyenler kapatılır: 4 soru" diyor, kimin kapatacağını söylemiyor. S2 ve S4 Montaj amiri, S19 Bobinaj amiri ya da Levent, S22 Levent ya da İK kapatabilir. İK S2 / S4 / S19'u kapatamaz (T-39).
     - 5. görüntü (kilitten sonraki düzeltmenin fark satırı) için sonraki ayın da kilitlenmesi gerekiyor. Fark satırı ancak hedef ay kilitlenince puantajda oluşuyor. Belgede bu adım yok; yerelde Aralık'ın (7 Aralık işlendikten sonra) kilitlenmesi gerekir. Aralık bitmeden kilitlenebildiği için (T-89) bu yerelde mümkün, canlıda asla yapılmamalı.
- **Ne olmalıydı:** Belge, sunucunun doğaçlama yapmasına gerek bırakmamalı.
- **Kanıt:** B#2–3 (dört soru eskale; S22 İK'da) · B#12 (mesaj, zimmet açıkken) · A#4–9 (soruları kim kapattı) · A#40, A#48–50 (fark satırı Aralık kilidinde).
- **Sade dille:** Demo günü sunucu belgeyi satır satır izlerse iki yerde takılır: çakışma mesajını göstermek istediğinde kart çoktan iade edilmiş olur; ay kilidi görüntülerini hazırlarken de hangi soruyu kimin kapatacağını bilmez. "Kilitten sonra fark satırı" görüntüsü de belgede anlatılan adımlarla hiç oluşmaz.
- **Öneri:** Belgeye:
  - 2. bölümde 4. maddeyi 2. ile 3. arasına taşı;
  - 1. bölüme "sorular eskale görünür; S22 İK'da" notu;
  - 9. bölüme soru başına kapatan hesap (A'daki sıra);
  - 5. görüntü için "7 Aralık'ı işle, sorularını kapat, Aralık'ı yerelde kilitle" adımları.

  Kod değişikliği gerekmez (Fırat onaylarsa belge düzeltmesi).
- **Durum:** ✅ Düzeltildi (belge, `feature/T103-belge-duzeltmeleri`). Çakışma mesajı iade almadan önceki adıma taşındı; 1. bölüme eskale notu, 9. bölüme soru başına kapatan hesap eklendi. 5. görüntü: T-89 düzeltmesinden sonra Aralık, 1 Ocak 2027'den önce ekrandan kilitlenemiyor; seçenekler belgede, karar Fırat'ın.

### Bilinen bulgulara takılanlar (yeniden numara verilmedi)
- **T-39 ile aynı:** Kasım soruları ayın tamamı tek seferde işlenince üst amire, S22 İK'ya eskale oluyor. Atanan amir yine cevaplayabildiği için A'da sorun çıkmadı.
- **T-81 ile aynı:** Kilit öncesi görülmemiş 1 paylaşım uyarısı (S11) kaldı; kilidi engellemedi.
- **T-89 ile aynı:** Aralık 22 Kasım'da kilitlenebildi (A21).
- **T-80 ile aynı:** Sistem yöneticisi çalışan listesini görüyor (B32).
- **T-24 ile ilgili:** Kasım'ın gece işi SQL ile çalıştırıldı. Ekrandan 30 gün tek seferde 8 sn sınırını aşabilir; demo bunu ekrandan yapmıyor.

### Denediklerim
- A: 50 çağrı. Kasım gece işi; 4 sorunun ilgili amirle cevaplanması ve 2 İK kararı; itiraz kabul (düzeltmeyle) ve ret; 3 havuz kararı; S13 planı (giren ve müdür); zorlamadan kilit; kapsama, satır = canlı görünüm, satır = kalem; çalışılan, devamsız, izin, rapor, HT, RT, FM50, FM100 toplamları elle; ERP; kilitten sonra itiraz kabulü ve Aralık'ta fark satırı.
- B: 49 çağrı. Demo belgesinin 1–9. bölümlerindeki her sayı ve mesaj; geçici kart akışı; 7 Aralık'ın dört dosyasının ekranın biçimiyle yüklenmesi; gece işi özeti; kişi kişi sonuç; düzeltme izi ve silinemezlik; aynı dosyanın ikinci kez yüklenmesi; amir ve İK kararları; havuz, FM100, esnek; İSG; yönetici ve sistem yöneticisi sınırları; kilit hazırlığının S13 kısmı.

### Denemediklerim
- **Ekranların kendisi:** Excel indirme, PDF döküm, ERP için CSV / XML düğmeleri, ana sayfa ve uyarı ekranlarının görünümü. Hepsi SQL ile rol taklidi; HTTP ve oturum açma yok.
- **Ekranın CSV denetimi:** `lib/aktarim/denetim.ts`'nin yaptığı satır denetimi yerine CSV doğrudan SQL'de çevrildi. Dosya özeti ekranınki gibi dosyanın kendisinden değil, satırlardan hesaplandı.
- **Gerçek saat:** Zimmetler bu testte 22 Kasım saatiyle yazıldı (RPC `clock_timestamp()` kullanıyor). Demo 7 Aralık'ta yapılınca Osman'ın zimmeti Aralık'a düşer; `sik_kart_unutma` sayımı farklı ama uyarı üretmez (ayda 1).
- **Canlı:** Canlı kurulumun Kasım'ı nasıl işlediği (`docs/canli_kurulum.md` 6. adım) ve `cron.unschedule`'ün yapılıp yapılmadığı.
- **8 sn zaman aşımı:** 7 Aralık gece işinin ve dosya yüklemenin ekrandan süresi.
- **Kasım'ı zorla kilitleme:** A'da gerek kalmadı; Adım 12'de denenmişti.

---

## PR incelemesi — ekran PR'ları #37, #39, #40, #41 (22 Kasım 2026)

**Kapsam:** Gökalp'in dört ekran PR'ı birleştirilmeden önce incelendi; #37 o sırada zaten birleşmişti. Migration yok. Kural ihlali yok:
- `.env` commit edilmemiş;
- `SUPABASE_SECRET_KEY` uygulama kodunda kullanılmıyor ve tarayıcıya giden dosyalarda yok;
- SQL metnine kullanıcı girdisi eklenmiyor;
- sayfaların rol kontrolleri korunmuş.

`main`'den ayrı bir çalışma klasöründe #39 → #40 → #41 çakışmasız birleşti. `npm run build` ve ESLint hatasız. Yerel Supabase ile İK, amir, güvenlik ve yönetici menülerindeki sayfalar açıldı. Bulunan tek yeni sorun aşağıda. Ardından #39, #40, #41 bu sırayla `main`'e birleştirildi.

Durumu değişen bulgular:
- T-37 ✅ (PR #40);
- T-38 ✅ (PR #37);
- T-34 ve T-89: ekran tarafı düzeltildi (PR #40 / #39), veritabanı tarafı açık.

### T-104 · Amirin Departmanlar sayfası RLS'li görünümler yüzünden 8 saniyede zaman aşımına düşüyor
- **Adım:** PR incelemesi · **Önem:** Yüksek
- **Yer:** `pdks.v_esnek_mesai` ve `pdks.v_departman_ozet` (`security_invoker = true`, son sürüm: `20261124010000_vardiya_kurallari.sql` ve `20261122010000_izin_iptal_ve_departman_ozeti.sql`). Bu görünümler `gun_kaydi`, `calisan` ve `amir_sorusu` gibi tabloların RLS politikalarıyla çalışıyor. Ekran: `app/(panel)/departmanlar/page.tsx` (PR #37). `authenticated` rolünün sorgu süresi sınırı 8 saniye (`statement_timeout = 8s`, Supabase varsayılanı; canlıda da aynı).
- **Ne oldu:**
  - Yerel Supabase'te Kasım gece işinden geçirildi (76 çalışan, 1597 gün kaydı). `npm run dev` ile dört rolün sayfaları istendi.
  - **Amir (montaj.amiri):** Departmanlar sayfası **iki denemenin ikisinde de** 8,1 saniyede "canceling statement due to statement timeout" ile düştü; ekranda "Sayfa açılamadı".
  - **İK ve yönetici:** Aynı sayfa 3,5 ve 3,8 saniyede açıldı. Diğer bütün sayfalar 1,5 saniyenin altında.
  - Aynı sorgular SQL'de, rol taklidiyle ölçüldü (tablo aşağıda). Yavaşlık veride değil, RLS'li değerlendirmede: aynı sorgu RLS'siz 6 ms.
  - Sayfa iki görünümü ve çalışan listesini birlikte okuduğu için amirde süreler toplanıp 8 saniyeyi aşıyor.
- **Ne olmalıydı:** Yönetici paneli 2000 çalışanda da her rolde birkaç saniyede açılmalı. Bugün 76 çalışanla bile amirde açılmıyor; İK ve yönetici sınıra yarı yarıya yakın. Çalışan sayısı arttıkça bu rollerde de zaman aşımı beklenir (T-24 ile aynı ölçek sorunu).
- **Kanıt:** SQL, rol taklidiyle, Kasım 2026 (`statement_timeout` ölçüm için 60 s'ye çıkarıldı):

  | Oturum | Sorgu | Satır | Süre |
  |---|---|---:|---:|
  | amir (montaj.amiri) | `select count(*) from pdks.v_departman_ozet where yil = 2026 and ay = 11` | 2 | 1092 ms |
  | amir (montaj.amiri) | `select count(*) from pdks.v_esnek_mesai where yil = 2026 and ay = 11` | 0 | 4397 ms |
  | İK (ik.uzmani) | `v_departman_ozet` (aynı süzgeç) | 19 | 788 ms |
  | RLS'siz (`postgres`) | `v_departman_ozet` (aynı süzgeç) | 19 | 6 ms |

  Geliştirme sunucusu günlüğü (amir, iki deneme):
  ```
  ⨯ Error: canceling statement due to statement timeout
      at tumSatirlar (lib/supabase/sayfali.ts:14:22)
      at async DepartmanlarSayfasi (app/(panel)/departmanlar/page.tsx:60:58)
   GET /departmanlar 200 in 8.1s (application-code: 8.1s)
  ```
  İK: `GET /departmanlar 200 in 3.5s`; yönetici: `GET /departmanlar 200 in 3.8s`.
- **Sade dille:** Bir departman amiri yönetici panelinde "Departmanlar" sayfasını açınca sayfa 8 saniye bekleyip hata veriyor. Sebep sayfanın kendisi değil: veritabanı, amirin yalnızca kendi departmanını görmesi için her satırda yetki denetimi yapıyor ve bu denetim çok yavaş. Örnek veride 76 kişi var; gerçek fabrikada 2000 kişi olunca İK ve fabrika müdürü de aynı hatayı görür. Demoda amir hesabıyla bu sayfa açılırsa hata ekrana gelir.
- **Öneri:**
  - Özet görünümleri, rolü ve departmanı bir kez çözen `security definer` fonksiyonlara çevir: `pdks.departman_ozeti(p_yil, p_ay)` ve `pdks.esnek_mesai_ozeti(p_yil, p_ay)`. İçeride `tum_veriyi_gorur()` ise hepsi, amir ise `oturum_departmanlari()`; ekran `rpc` ile çağırır (Gökalp için küçük değişiklik).
  - Ya da RLS politikalarındaki oturum fonksiyonlarını `(select pdks.oturum_...())` kalıbıyla bir kez değerlendirilir hale getir.
  - Önce `explain analyze` ile hangi politikanın yavaş olduğu çıkarılmalı.
  - Kalıcı test: amir oturumunda iki özetin süresi örnek veriyle 500 ms'nin altında, satırlar bugünkü görünümle aynı.
  - Kime: Yusuf (veritabanı), ardından Gökalp (sayfa çağrısı). Demo öncesi.
- **Durum:** ✅ Düzeltildi — PR #48 (migration: `20261206010000_rls_hizi.sql`, test: `rls_hizi_testi.sql`).
  - **Ne yapıldı:** 9 tablonun 20 okuma politikası `(select pdks.f())` kalıbına çevrildi; oturum artık satır başına değil sorgu başına bir kez denetleniyor. `amirin_calisani_mi(calisan_id)` yerine `pdks.oturum_calisanlari()` kullanılıyor. Kim hangi satırı görür değişmedi (test her rolde birebir karşılaştırır). Ekranda değişiklik gerekmedi (Gökalp'e iş yok).
  - **Kapsam:** Departmanlar sayfasının 6 tablosu (`gun_kaydi`, `calisan`, `amir_sorusu`, `itiraz`, `departman`, `vardiya_tanim`) ve amir olarak bütün tablolar ölçülünce bugün yavaş çıkan 3 tablo (`vardiya_plani` 5,2 sn, `kanit_kaydi` 5,1 sn, `ham_okutma` 2,8 sn). **Düzeltme:** yukarıdaki "diğer bütün sayfalar 1,5 saniyenin altında" ölçümü amir için geçerli değil; Vardiya planı sayfası amirde 4,8 sn sürüyordu (yerel, Montaj amiri, Kasım işlenmiş).
  - **`explain analyze` (Montaj amiri):** Eski planda `Filter: (pdks.tum_veriyi_gorur() OR pdks.amirin_calisani_mi(calisan_id))` her satırda çalışıyor (`vardiya_plani` 1608 satır, 1479 ms; `v_esnek_mesai` 1612 ms). Yeni planda iki `InitPlan` bir kez hesaplanıyor, filtre `(InitPlan 1).col1 OR (calisan_id = ANY ((InitPlan 2).col1))` (49 ms; 40 ms).
  - **Ekranda (yerel, `npm run dev`, Montaj amiri):** Departmanlar 8,2 / 8,9 sn "statement timeout" → 1,5–1,6 sn, açılıyor.
  - **Test süreleri (Montaj amiri):** departman özeti 643 → 56 ms, esnek mesai 1472 → 49 ms, vardiya planları 1650 → 50 ms, kanıt kayıtları 771 → 0 ms.
  - **Devamı (25 Kasım):** politikaların çağırdığı yardımcı fonksiyonların içi bu PR'da çevrilmemişti; amirde okumalar 50 ms'den 400–850 ms'ye çıktı. T-108'de düzeltildi.
- **Kalan (ayrı iş, 26 Kasım – 3 Aralık):** Diğer 26 tablonun 46 politikası hâlâ satır başına denetliyor. Bugün amirde her biri 0,2 sn'nin altında; 2000 çalışanda yavaşlayabilir. Aynı kalıpla çevrilecek; `rls_hizi_testi.sql`'deki tablo listesi genişletilecek.
- **Not (test ortamı):** `gecici_kart_ve_paylasim_testi.sql`, Kasım gece işinden geçmiş bir veritabanında ("kart paylaşımı günlük kaydı değiştirmedi") düşüyor; eski kodda da aynı. Test temiz veritabanı bekliyor (`db reset` sonrası geçiyor). Bu PR ile ilgili değil.


## Normalizasyon incelemesi — `kullanici` tablosu (23 Kasım 2026)

### T-105 · `kullanici` tablosunda iki çift kayıt: `izinli_mi` hiç değişmiyor, `ad_soyad` çalışandan bağımsız
- **Adım:** Normalizasyon · **Önem:** Orta (`izinli_mi`), Düşük (`ad_soyad`)
- **Yer:** `pdks.kullanici.izinli_mi`, `pdks.soru_atanacak`; `pdks.kullanici.ad_soyad`, `pdks.kullanici_ekle`
- **Ne oldu:**
  - `izinli_mi`: izin bilgisi zaten `izin` tablosunda var. Bayrağı değiştiren hiçbir ekran ya da fonksiyon yoktu (`kullanici_guncelle`'de parametresi yok), bu yüzden uygulamada hep `false` kalıyordu. Amir `izin` tablosunda izinliyken bile sorular ona gidiyordu; "izinliyse vekile" kuralı fiilen çalışmıyordu.
  - `ad_soyad`: kullanıcı `calisan_id` ile bir çalışana bağlı ve ad `calisan.ad` / `soyad`'da. `kullanici_ekle` ismi admin'den alıyor ve çalışanla tutup tutmadığına bakmıyordu (3NF: kullanıcı → çalışan → ad).
- **Durum:** ✅ Düzeltildi — migration `20261208010000_kullanici_cift_kayit.sql`, test `kullanici_cift_kayit_testi.sql` (20 test).
  - `izinli_mi` kolonu silindi. Yeni `pdks.kullanici_izinli_mi(kullanıcı, tarih = bugün)`: çalışan kaydı için iptal edilmemiş izin ya da rapor var mı. `soru_atanacak` bunu kullanır.
  - `ad_soyad` kolonu kaldı (15 ekran okuyor), kaynağı çalışan: `kullanici_ad_soyad` trigger'ı yazarken, `calisan_adi_degisti` trigger'ı çalışanın adı değişince eşitler; var olan satırlar bir kez eşitlendi. `kullanici_ekle(p_eposta, p_rol, p_calisan_id, p_ust_amir_id?)` artık ad soyad almaz; Kullanıcılar ekranındaki "Ad soyad" alanı kalktı.
  - `organizasyon_roller_testi.sql` yeni imzaya göre güncellendi (35 test geçiyor).
- **İlgili açık maddeler:** T-14 (vekilin görünürlüğü) ve T-43 (izinden önce açılmış sorular) artık `izinli_mi` yerine `pdks.kullanici_izinli_mi()` üzerine kurulmalı.

## T-12 düzeltmesinde bulunan (24 Kasım 2026)

### T-106 · İK'nın soru kararındaki gerekçe (sağlık bilgisi olabilir) amire açık
- **Adım:** T-12 düzeltmesi · **Önem:** Yüksek (KVKK m.6; T-12 ile aynı kök neden, K9)
- **Yer:** `pdks.soru_ik_karari` (son sürüm: `20261210010000_ikinci_eskale.sql`), `pdks.v_duzeltme_amir` (T-12)
- **Ne oldu:**
  - `soru_ik_karari` gerekçeyi `amir_sorusu.cevap_aciklama`'ya "İK: …" diye ekliyordu. Soruyu atanan amir ve eskale edilen üst amir okuyabiliyor.
  - Karar "geldi" ise gerekçe saat düzeltmesine de yazılıyor; T-12'nin görünümü saat düzeltmesinin gerekçesini gizlemediği için amire oradan da açıktı.
- **Ne olmalıydı:** Amir kararın sonucunu görmeli (devamsız / çalışmış), gerekçesini görmemeli.
- **Kanıt:** `ik_karar_gerekcesi_testi.sql` eski kodda kalıyor: `KALDI  amir: İK gerekçesi soruda yok`.
- **Sade dille:** İK "hastane evrakı geçersiz" diye gerekçe yazarsa amir bunu kendi sorular listesinde okuyordu. Düzeltme listesindeki gerekçeyi gizlemiştik, ama aynı cümle sorunun içinde duruyordu.
- **Durum:** ✅ Düzeltildi (feature/T106-ik-karar-gerekcesi). Migration: `20261215010000_ik_karar_gerekcesi.sql`, test: `ik_karar_gerekcesi_testi.sql`.
  - Yeni `amir_sorusu.ik_karari` (`devamsiz` / `geldi`); gerekçe yalnızca `duzeltme`'de (İK ve yönetici). `cevap_aciklama` amirin kendi açıklaması olarak kalır.
  - `v_duzeltme_amir`, İK'nın soru kararından gelen düzeltmede de gerekçeyi gizler.
  - Eski kayıtlardaki "İK: …" parçası, birebir aynısı `duzeltme`'de varsa sorudan silinir.
- **Kalan:**
  - `isten_cikis_gir` çıkış açıklamasını kapattığı soruya ve fazla mesai talebine yazıyor; amir okuyabilir.
  - İtiraz ve fazla mesai karar açıklamaları amire açık (karar, çalışana / talep edene bildirilen metindir).
  - Elle saat düzeltmesinin gerekçesi açık (T-12 sınırlılığı). Amirin adının silinmesi T-32'de.
- **Numara notu:** T-107, planlanan "kart paylaşımı kanıt kuralı" için ayrıldı.


## T-104 devamında bulunan (25 Kasım 2026)

### T-108 · Oturum yardımcıları oturumu kendi içlerinde satır başına soruyor; amirin "çalışanlarım" listesi yarım saniye
- **Adım:** T-104 devamı (T-74 testleri sırasında `rls_hizi_testi` hız sınırına takıldı) · **Önem:** Yüksek (T-104 ile aynı kök neden, K16; ölçekte zaman aşımı)
- **Yer:** `pdks.oturum_departmanlari`, `pdks.oturum_calisanlari` (son sürüm: `20261206010000_rls_hizi.sql`), `pdks.amirin_calisani_mi`, `pdks.oturum_rolu`, `pdks.oturum_calisan_id`.
- **Ne oldu:**
  - T-104 politikaları `(select pdks.f())` kalıbına çevirdi, ama politikaların çağırdığı yardımcıların İÇİ çevrilmedi.
  - `oturum_departmanlari` departman tablosunun her satırında `oturum_rolu()` ve `oturum_kullanici_id()`'yi; `oturum_calisanlari` çalışan tablosunun her satırında `oturum_departmanlari()`'yı yeniden hesaplıyordu (tekrarın içinde tekrar).
  - T-71 `oturum_kullanici_id`'ye "çalışan aktif mi" şartını ekleyince her çağrı uzadı; tekrar görünür oldu. `rls_hizi_testi`'nin 500 ms sınırı (ölçülen değerin 10 katı) gerilemeyi geç yakaladı; test 154 sn sürmeye başladı.
  - T-12 ve T-106'nın yeni politikaları da `oturum_calisanlari`'ni kullanıyor.
- **Ne olmalıydı:** Oturum (kim, rolü, departmanları, çalışanları) sorgu başına bir kez hesaplanmalı.
- **Kanıt (yerel, Montaj amiri, 5 ölçüm ortalaması):**

  | Ölçüm | Önce | Sonra |
  |---|---:|---:|
  | `oturum_departmanlari()` | 3,5 ms | 1,0 ms |
  | `oturum_calisanlari()` (79 çalışan × 3,5 ms) | 262,6 ms | 1,0 ms |
  | `vardiya_plani` okuması (Vardiya planı) | 286,5 ms | 1,6 ms |
  | `fazla_mesai_plani` okuması (`amirin_calisani_mi` politikası) | 8,6 ms | 1,4 ms |
  | `rls_hizi_testi`: departman özeti / esnek mesai / vardiya planları | 480 / 436 / 458 ms | 9 / 5 / 2 ms |
  | `rls_hizi_testi` süresi · bütün test turu | 154 sn · 10+ dk | 22 sn · 105 sn |

  Sonuç aynı: Hasan 2 departman, 20 çalışan; testte 8 oturumda 9 tablonun satırları eski politikayla birebir aynı.
- **Sade dille:** T-104'te veritabanına "amirin çalışan listesini bir kez çıkar, her satırda o listeye bak" dedik. Ama listeyi çıkaran yardımcı, listeyi hazırlarken her çalışan için "amirin departmanları hangileri?" sorusunu baştan soruyordu. 76 çalışanda yarım saniye; 2000 çalışanda saniyeler sürer ve T-104'teki zaman aşımı geri gelirdi.
- **Durum:** ✅ Düzeltildi — PR #63 (migration: `20261217010000_oturum_yardimcilari.sql`, test: `rls_hizi_testi.sql`).
  - Beş yardımcının içinde oturum fonksiyonları `(select pdks.f())` ile çağrılır (sorgu başına bir kez, InitPlan). İmza, özellikler (STABLE, SECURITY DEFINER, search_path) ve yetkiler aynı.
  - `rls_hizi_testi`: yardımcıların yapısı da denetlenir (1b); hız sınırları ölçülen değere yakın: "çalışanlarım" listesi < 30 ms, sayfa okumaları < 150 ms (eskiden 500 ms).
  - `fazla_mesai_plani` ve `fazla_mesai_inceleme`'nin `amirin_calisani_mi` politikaları da hızlandı (T-104'ün "kalan 46 politika" listesindeydiler).
- **Numara notu:** T-107, Fırat'ın planladığı "kart paylaşımı kanıt kuralı" için ayrılmış olduğundan bu bulgu T-108.
