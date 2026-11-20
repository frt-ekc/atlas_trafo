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
| İK | `ik.uzmani@example.com` | ik |
| Montaj amiri | `montaj.amiri@example.com` | amir |
| Güvenlik | `guvenlik@example.com` | guvenlik |
| İSG | `isg.uzmani@example.com` | isg |
| Fabrika müdürü | `fabrika.muduru@example.com` | yonetici |
| Sistem yöneticisi | `sistem.yoneticisi@example.com` | admin |

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

### 2. Kart unutma (Kasım verisi + Güvenlik ekranı)
Kart unutma Kasım'daki kayıtlarla anlatılır; 7 Aralık dosyalarında geçici kart yoktur.

**İK, Çalışanlar ekranı:**
- **İbrahim Arslan (1007), 10 Kasım:** gün boyu GK-01 ile okuttu, okutmalar ona yazıldı.
- **Osman Doğan (1008):** 11, 17 ve 19 Kasım'da geçici kart aldı.

**Güvenlik hesabı, Geçici kartlar ekranı:**
1. Burak Kurt'un (1010) 18 Kasım'dan beri iade etmediği **GK-02**'yi **iade al** (S9 kapanır).
2. Osman'a **GK-01**'i ver: kart o anın saatiyle zimmetlenir.
3. Hemen **iade al**. Demo bitmeden açık zimmet bırakılmaz.
4. Gösterilebilir bir kural: zimmetteyken aynı kart ikinci kişiye verilmeye çalışılırsa hata mesajı çakışan zimmeti söyler, örneğin "GK-01 kartı Osman Doğan'a … verilmiş zimmetle çakışıyor (henüz iade edilmedi)."

### 3. 7 Aralık dosyalarını yükleme ve gece işi (İK, Veri aktarımı)
1. **Dosya yükle:** dört dosya sırayla yüklenir. Gün dosya adından okunur (07.12.2026). Ekran yüklemeden önce satırları denetler ve özet gösterir.
2. **Gece işini çalıştır:** başlangıç ve bitiş 07.12.2026.
3. **Beklenen özet:** 10 gün kaydı, 2 kanıtla düzeltme, 2 amir sorusu, 8 hesaplanan gün, yeni uyarı yok.

7 Aralık'ta yalnızca Montaj'ın 10 kişisi planlıdır (Gündüz 08:00–17:00):

| Kişi | Dosyada ne var | Gece işinin sonucu |
|---|---|---|
| Veli Çelik (1004) | PDKS girişi yok; kapı girişi 07:46 | **Kanıtla düzeltme:** giriş 08:00 (kapı + yürüme payı vardiya başından önce) |
| Hüseyin Aydın (1006) | PDKS çıkışı yok; kapı çıkışı 17:09 | **Kanıtla düzeltme:** çıkış 17:09 |
| Ali Demir (1003) | PDKS girişi yok; kapı girişi 08:24 | **Amire soru:** "kanıt vardiya başından sonra", öneri 08:29 |
| Mustafa Şahin (1005) | Çıkışa dair hiçbir kayıt yok | **Amire soru:** "çıkış yok" |
| Diğer 6 kişi | Normal gün | Tamam, 480 dk |

**İK, Çalışanlar → Veli Çelik:** 7 Aralık girişinin yanında kaynak "kanıt", düzeltme izinde gerekçe görünür: "Kapı kaydı 07:46, vardiya başından önce; giriş vardiya başı olarak yazıldı". Düzeltme silinemez.

### 4. Amire soru (Montaj amiri, Sorularım)
1. **Ali:** "Geldi, saat doğru" → giriş 08:29 yazılır.
2. **Mustafa:** "Bilmiyorum" → soru İK kararına gider. Amir devamsızlık kararı veremez.

### 5. İK kararı (İK, Sorular)
1. Mustafa'nın sorusu: "devamsız değil", çıkış 17:00, gerekçe yazılır.
2. **Veri aktarımı → Gece işini çalıştır (07.12.2026) bir kez daha.** Cevaplanan günlerin dakikaları gece işinin hesap adımında hesaplanır.
3. **Sonuç:**
   - Ali: geç kalma 29 dk, çalışma 451 dk.
   - Mustafa: çalışma 480 dk.

### 6. Fazla mesai, esnek mesai, puantaj (İK)
**Fazla mesai ekranı, onaysız havuzda 3 kayıt İK kararı bekliyor:**
- Ece Ateş: 150 dk.
- Merve Yücel: 100 dk, yazılı onayı yok.
- Erkan Duman: 485 dk, 29 Kasım Pazar, yazılı onayı yok.

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
5. Kilitten sonra gelen bir düzeltmenin sonraki aya fark satırı olarak yazılması.

**Görüntüler nasıl alınır (yerelde, Fırat):**
1. `supabase db reset` (örnek veriyle).
2. Kasım'ı gece işinden geçir.
3. Ekranları yerel Supabase'e bağlayıp aç.
4. Görüntüleri al.
5. Bitince yine `supabase db reset`.

## Demodan sonra
- Açık geçici kart zimmeti kalmadığı Güvenlik ekranından kontrol edilir.
- Canlıda hiçbir ay kilitlenmez.
