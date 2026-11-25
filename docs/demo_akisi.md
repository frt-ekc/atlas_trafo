# Demo akışı (7 Aralık 2026, Pazartesi)

Demo canlı sistemde (atlas-pdks) yalnızca **sahte veriyle** yapılır. Kasım 2026'nın tamamı önceden gece işinden geçmiştir (`docs/canli_kurulum.md`). 7 Aralık'ın okutmaları demo sırasında `demo/` klasöründeki dört CSV ile yüklenir.

> **Ay kilidi canlıda gösterilmez; yerelde ekran görüntüsüyle anlatılır.**
> Kilit geri açılamaz ve Kasım'ın bilerek açık bırakılmış 4 sorusu var. Provada da, demoda da canlıda **Ayı kilitle** düğmesine basılmaz.

## Hazırlık
- **Demodan önceki akşam:** canlı kurulum doğrulanmış olmalı (`docs/canli_kurulum.md` 7. adım).
- **Prova yerelde yapılır.** 7 Aralık dosyaları canlıya provada yüklenirse demo günü "Bu dosya daha önce yüklenmiş." hatası çıkar ve 7 Aralık soruları önceden açılmış olur. Canlıda prova yapıldıysa canlı yeniden kurulur.
- **Ekran görüntüleri:** ay kilidi bölümünün görüntüleri önceden yerelde alınır (bkz. son bölüm).
- **Dosyalar:** `demo/pdks_20261207.csv`, `kapi_20261207.csv`, `yemekhane_20261207.csv`, `servis_20261207.csv`, sunum bilgisayarında hazır olmalı.
- **Hesaplar:** demo hesaplarının şifreleri hesabı açan kişidedir; bu belgeye yazılmaz.

| Kısa ad | E-posta | Rol |
|---|---|---|
| İK | `elif.sen@atlastrafo.example.com` | ik |
| Montaj amiri | `hasan.yilmaz@atlastrafo.example.com` | amir |
| Güvenlik | `recep.bayram@atlastrafo.example.com` | guvenlik |
| İSG | `tuba.erkoc@atlastrafo.example.com` | isg |
| Fabrika müdürü | `nur.tekin@atlastrafo.example.com` | yonetici |
| Sistem yöneticisi | `alper.cinar@atlastrafo.example.com` | admin |

## Demo sırası

### 1. Sorun ve Kasım ayı (İK)
- **Ana sayfa:** Kasım'ın özeti, açık sorular ve uyarılar.
- **Uyarılar:** sistem karar vermez, İK'ya uyarı yazar. Gösterilecekler:
  - geçici kart zimmetliyken asıl kartın okutulması (S6 İbrahim, S9 Burak);
  - iade edilmeyen geçici kart (S9);
  - ayda 3 kez kart unutma (S7 Osman);
  - kart paylaşımı şüphesi (S11);
  - zimmetsiz geçici kart (S23).
- **Sorular:** Kasım'ın 4 açık sorusu (S2, S4, S19, S22). S22'de soru Montaj amiri Hasan'ın kendi kaydı olduğu için ona değil, üst amiri Levent Sarı'ya gitti (görevler ayrılığı).
  - **Ekranda "eskale" ve "İK kararı bekliyor" görünür:** Kasım'ın tamamı gece işinden geçtiği için dördünün de cevap süresi dolmuştur. Soru önce amire, amir 3 günde cevaplamazsa üst amire, üst amir de 3 günde cevaplamazsa İK'ya gider (T-39). Kasım sonunda S2 ve S4 üst amir Levent Sarı'dan İK'ya geçmiş, S19 Levent'te, S22 İK'da (Elif Şen) görünür. Gece işi Aralık'ta her gece çalıştığı için 7 Aralık'ta S19 da İK'dadır (son cevabı 29.11, üst amirin süresi 02.12'de doldu). "Kime atanmış" sütunu bu yüzden yukarıdaki cümleden farklı görünebilir; anlatırken önce "ilk kime gitti", sonra "süresi dolunca kime geçti" söylenir.

### 2. Kart unutma (Kasım verisi + Güvenlik ekranı)
Kart unutma Kasım'daki kayıtlarla anlatılır; 7 Aralık dosyalarında geçici kart yoktur.

**İK, Çalışanlar ekranı:**
- **İbrahim Arslan (1007), 10 Kasım:** gün boyu GK-01 ile okuttu, okutmalar ona yazıldı.
- **Osman Doğan (1008):** 11, 17 ve 19 Kasım'da geçici kart aldı.

**Güvenlik hesabı, Geçici kartlar ekranı:**
1. Burak Kurt'un (1010) 18 Kasım'dan beri iade etmediği **GK-02**'yi **iade al** (S9 kapanır).
2. Osman'a **GK-01**'i ver: kart o anın saatiyle zimmetlenir.
3. **Kart Osman'dayken** aynı GK-01'i başka bir çalışana vermeyi dene: hata mesajı çakışan zimmeti söyler, örneğin "GK-01 kartı Osman Doğan'a … verilmiş zimmetle çakışıyor (henüz iade edilmedi)." Bu adım iade almadan önce yapılmalıdır; kart iade edildikten sonra mesaj çıkmaz.
4. Osman'dan GK-01'i **iade al**. Demo bitmeden açık zimmet bırakılmaz.

### 3. 7 Aralık dosyalarını yükleme ve gece işi (İK, Veri aktarımı)
1. **Dosya yükle:** dört dosya sırayla yüklenir. Gün dosya adından okunur (07.12.2026). Ekran yüklemeden önce satırları denetler ve özet gösterir.
2. **Gece işlemini başlat:** başlangıç ve bitiş 07.12.2026.
3. **Beklenen özet:** 10 gün kaydı, 2 kanıtla düzeltme, 2 amir sorusu, 8 hesaplanan gün, yeni uyarı yok.

7 Aralık'ta yalnızca Montaj'ın 10 kişisi planlıdır (Gündüz 08:00–17:00):

| Kişi | Dosyada ne var | Gece işinin sonucu |
|---|---|---|
| Veli Çelik (1004) | PDKS girişi yok; kapı girişi 07:46 | **Kanıtla düzeltme:** giriş 08:00 (kapı + yürüme payı vardiya başından önce) |
| Hüseyin Aydın (1006) | PDKS çıkışı yok; kapı çıkışı 17:09 | **Kanıtla düzeltme:** çıkış 17:09 |
| Ali Demir (1003) | PDKS girişi yok; kapı girişi 08:24 | **Amire soru:** "kanıt vardiya başından sonra", öneri 08:29 |
| Mustafa Şahin (1005) | Çıkışa dair hiçbir kayıt yok | **Amire soru:** "çıkış yok" |
| Diğer 6 kişi | Normal gün | Tamam, 480 dk |

**İK, Çalışanlar → Veli Çelik:** 7 Aralık girişinin yanında kaynak "kanıt", düzeltme izinde gerekçe görünür: "Kapı kaydı 07:46; giriş vardiya başlangıcı olarak kaydedildi". Düzeltme silinemez.

### 4. Amire soru (Montaj amiri, Sorularım)
1. **Ali:** "Geldi, saat doğru" → giriş 08:29 yazılır ve gün hemen hesaplanır.
2. **Mustafa:** "Bilmiyorum" → soru İK kararına gider. Amir devamsızlık kararı veremez.

### 5. İK kararı (İK, Sorular)
1. Mustafa'nın sorusu: "devamsız değil", çıkış 17:00, gerekçe yazılır.
2. **Sonuç** (cevap ve karar verilir verilmez hesaplanır; gece işini yeniden çalıştırmak gerekmez):
   - Ali: geç kalma 29 dk, çalışma 451 dk.
   - Mustafa: çalışma 480 dk.

### 6. Fazla mesai, esnek mesai, puantaj (İK)
**Fazla mesai ekranı, onaysız havuzda 3 kayıt İK kararı bekliyor:**
- Ece Ateş: 150 dk.
- Merve Yücel: 100 dk, yazılı onayı yok ("Yazılı onay yok" etiketi).
- Erkan Duman: 485 dk, 29 Kasım Pazar, yazılı onayı yok ("Yazılı onay yok" etiketi).

**Puantaj (Kasım):**
- Mehmet Kaya 22 Kasım Pazar: FM100 480 dk.
- Esnek mesai farkı: Onur Baysal −152 dk, İrem Toprak +29 dk. İrem'in 18 Kasım girişi kapı kaydından 09:17 olarak yazıldı; amire soru gitmedi.
- **Excel indir:** açık ay; FM50 / FM100 / gece / mola sütunları.

**Çalışanlar → bir çalışan → PDF döküm:** çalışan isterse İK verir.

### 7. İSG (İSG uzmanı, İSG ekranı)
- **Uğur Keskin (5303):** İSG eğitimi 10 Kasım'da doldu. Uyarı yazıldı, kapı kilitlenmedi. YG Lab'a yetkili olduğu için bölge uyarısı yok.
- **Taner Yazıcı (5302):** sağlık muayenesi 15 Aralık'ta doluyor.
- **Selim Ünal (5402, Depo):** 19 Kasım'da Boyahane'ye yetkisiz girdi. Aynı kapıdan geçen Hakan Ekinci'ye (Boyahane) uyarı yok.

### 8. Yönetici ve sistem yöneticisi
- **Fabrika müdürü, ana sayfa:** İK özetinin salt okunur hâli. Her şeyi görür, karar veremez.
  - Departman başına özet (`v_departman_ozet`) veritabanında hazır, ama henüz bir ekranda gösterilmiyor. Gökalp eklerse burada gösterilir.
- **Sistem yöneticisi:** kullanıcılar ve ayarlar. Çalışanın gün kaydını, iznini ve puantajını göremez.

### 9. Ay kilidi (ekran görüntüleriyle)
Canlıda kilit yapılmaz. Yerelde alınmış görüntülerle anlatılır:
1. Kilitten önce Puantaj (açık ay).
2. **Ayı kilitle** onayı.
3. Kilitli ayda ERP için CSV ve XML düğmeleri.
4. Excel'in "Puantaj kodları" sayfası.
5. Kilitten sonra gelen bir düzeltmenin sonraki aya fark satırı olarak yazılması (aşağıdaki nota bakın).

**Görüntüler nasıl alınır (yerelde, Fırat):**
- Kasım'ı zorlamadan kilitlemek için önce bekleyenler kapatılır: 4 soru (S2, S4, S19, S22), havuzdaki 3 fazla mesai ve Okan'ın (S13) onay bekleyen geriye dönük planı. Bu planı İK uzmanı girdiği için İK müdürü onaylar. Zorla kilitlenirse kilit sonucu, geçilen kalemleri ve puantaja kodsuz giren gün sayısını gösterir. S13 (Okan) planı zorla da geçilmez; kilitten önce İK müdürü planı onaylamalı ya da reddetmeli.
- **4 soruyu kim kapatır:** İK her açık soruya karar verebilir (son karar İK'da, T-39). Amir ya da üst amir soruyu yalnızca soru İK'ya geçmeden cevaplayabilir.

  | Soru | Kasım sonunda nerede | Kim kapatır |
  |---|---|---|
  | S2 (Ali Demir, 4 Kas) | İK (üst amir de cevaplamadı) | İK (Elif Şen) |
  | S4 (Mustafa Şahin, 5 Kas) | İK (üst amir de cevaplamadı) | İK (Elif Şen) |
  | S19 (Kaan Bulut, 25 Kas) | Levent Sarı | Bobinaj amiri Serkan Öztürk, Levent Sarı ya da İK. Hasan Bobinaj vekili olsa da bu soruyu cevaplayamaz (T-43) |
  | S22 (Hasan Yılmaz, 26 Kas) | İK | Levent Sarı ya da İK (Elif Şen) |

1. `supabase db reset` (örnek veriyle).
2. Kasım'ı gece işinden geçir.
3. Ekranları yerel Supabase'e bağlayıp aç.
4. Görüntüleri al.
5. Bitince yine `supabase db reset`.

> **5. görüntü (fark satırı) ekrandan alınamaz.** Fark satırı, düzeltmenin yazıldığı sonraki ay (Aralık) kilitlenince puantajda oluşur. Ay, son günü geçmeden kilitlenemez (T-89, zorla da). Bu yüzden Aralık, 1 Ocak 2027'den önce ekrandan kilitlenemez. Seçenekler (karar Fırat'ın):
> - Görüntüyü çıkarıp fark satırını sözlü anlatmak: Kasım kilitlendikten sonra Kasım'daki bir güne yapılan düzeltme `duzeltme` tablosuna `fark_satiri = true` ve hedef dönem Aralık olarak yazılır; Aralık kilitlenince puantaja fark satırı olarak girer.
> - Aralık'ı yerelde, doğrudan veritabanı bağlantısıyla (psql) test tarihi ayarıyla kilitlemek (`set local pdks.test_bugun = '2027-01-05'`). Bu ayar yalnızca doğrudan bağlantıda geçerlidir, ekrandan çalışmaz; canlıda asla yapılmaz.

## Demodan sonra
- Açık geçici kart zimmeti kalmadığı Güvenlik ekranından kontrol edilir.
- Canlıda hiçbir ay kilitlenmez.

## Demo kullanıcıları

Bütün adresler sahtedir; example.com test için ayrılmış bir alan adıdır, e-posta gitmez.

| E-posta | Ad soyad | Rol | Görev |
|---|---|---|---|
| ahmet.er@atlastrafo.example.com | Ahmet Er | ik | İK müdürü |
| elif.sen@atlastrafo.example.com | Elif Şen | ik | İK uzmanı |
| recep.bayram@atlastrafo.example.com | Recep Bayram | guvenlik | Güvenlik |
| nur.tekin@atlastrafo.example.com | Nur Tekin | yonetici | Fabrika müdürü |
| riza.kalkan@atlastrafo.example.com | Rıza Kalkan | amir | Genel müdür (beyaz yaka üst amiri) |
| levent.sari@atlastrafo.example.com | Levent Sarı | amir | Üretim müdürü (mavi yaka üst amiri) |
| hasan.yilmaz@atlastrafo.example.com | Hasan Yılmaz | amir | Montaj amiri (Bobinaj vekili) |
| serkan.ozturk@atlastrafo.example.com | Serkan Öztürk | amir | Bobinaj amiri |
| zeynep.acar@atlastrafo.example.com | Zeynep Acar | amir | Kalite amiri |
| baris.yalcin@atlastrafo.example.com | Barış Yalçın | amir | Nüve amiri |
| sinan.guler@atlastrafo.example.com | Sinan Güler | amir | Kazan amiri |
| cengiz.sezer@atlastrafo.example.com | Cengiz Sezer | amir | Boyahane amiri |
| volkan.simsek@atlastrafo.example.com | Volkan Şimşek | amir | Bakım amiri |
| ramazan.cetin@atlastrafo.example.com | Ramazan Çetin | amir | Depo amiri |
| aylin.kaplan@atlastrafo.example.com | Aylin Kaplan | amir | Ar-Ge amiri |
| cansu.akin@atlastrafo.example.com | Cansu Akın | amir | Planlama amiri |
| serdar.coskun@atlastrafo.example.com | Serdar Coşkun | amir | Satış amiri |
| gamze.yuksel@atlastrafo.example.com | Gamze Yüksel | amir | Dış ticaret amiri |
| nihat.uysal@atlastrafo.example.com | Nihat Uysal | amir | Satın alma amiri |
| filiz.oral@atlastrafo.example.com | Filiz Oral | amir | İnsan kaynakları departman amiri |
| mert.alkan@atlastrafo.example.com | Mert Alkan | amir | İSG departman amiri |
| hulya.gundogdu@atlastrafo.example.com | Hülya Gündoğdu | amir | Finans amiri |
| tamer.oguz@atlastrafo.example.com | Tamer Oğuz | amir | Bilgi işlem amiri |
| tuba.erkoc@atlastrafo.example.com | Tuba Erkoç | isg | İSG uzmanı |
| alper.cinar@atlastrafo.example.com | Alper Çınar | admin | Sistem yöneticisi |
