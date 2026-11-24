# Metin envanteri

Kullanıcıya görünen metinlerin listesi ve önerilen karşılıkları (24 Kasım 2026). Öneriler `feature/ekran-metinleri` dalında uygulandı (veritabanı: `20261216010000_ekran_metinleri.sql`).

- Kaynak: `app/`, `components/`, `lib/` (TypeScript ayrıştırıcısıyla çıkarıldı), `pdks.ayar`, veritabanı fonksiyonları. `{…}` çalışma anında dolan yerdir.
- "—": değişmez. Aynı ekrandaki aynı metin bir kez yazılır.
- Başlık kuralı: her yerde (menü, başlık, sekme, tablo sütunu, düğme, etiket) yalnızca ilk harf büyük.
- Süre biçimi: `168:00` → `168 sa`, `690 dk` → `11 sa 30 dk`. Excel ve ERP dosyalarında sayı olarak dakika kalır (dosya biçimi değişmez).
- Teknik okuma hataları ("… okunamadı: {hata}") kullanıcıya gösterilmez (hata sayfası genel mesaj verir); listeye alınmadı.

## Özet

| Ekran | Rol | Metin | Değişecek |
|---|---|---|---|
| Veri aktarımı | İK, Yönetici | 136 | 56 |
| Fazla mesai | İK, Amir, Yönetici | 109 | 52 |
| Çalışan sayfası | İK, Amir, Yönetici | 129 | 47 |
| Ana sayfa | Tümü | 79 | 39 |
| Puantaj | İK | 86 | 37 |
| Sorular | İK, Amir, Yönetici | 70 | 35 |
| Geçici kartlar | Güvenlik, İK, Yönetici | 48 | 24 |
| İzinler | İK | 66 | 24 |
| Ortak adlar (etiketler) | Tümü | 51 | 19 |
| İSG | İSG, İK, Yönetici | 53 | 18 |
| Vardiya planı | İK, Amir, Yönetici | 57 | 18 |
| Kullanıcılar | Admin | 38 | 17 |
| İtirazlar | İK, Amir, Yönetici | 34 | 14 |
| Uyarılar | İK, Yönetici, İSG | 37 | 14 |
| Ortak | Tümü | 60 | 13 |
| Ayarlar | Admin | 28 | 12 |
| Çalışanlar | Tümü | 31 | 12 |
| Departmanlar | İK, Amir, Yönetici | 38 | 12 |
| Veri aktarımı | İK | 16 | 7 |
| Giriş | Tümü | 13 | 6 |
| Çalışan dökümü | İK, Amir, Yönetici | 32 | 3 |
| Çerçeve | Tümü | 9 | 2 |
| Puantaj (Excel / ERP) | İK | 16 | 1 |
| Menü | Tümü | 24 | 0 |
| **Toplam** | | **1260** | **482** |

## Terimler sözlüğü

| Bugün kullanılanlar | Önerilen tek terim | Not |
|---|---|---|
| gece işi | **gece işlemi** | Ekran, uyarı ve mesajlar; veritabanı nesne adları değişmez |
| günlük kayıt, gün kaydı, kayıt | **gün kaydı** | |
| ham kayıt, ham okutma | **okutma kaydı / okutma** | Okuyucudan gelen her kayıt "okutma" |
| kart basma, okutma, okuttu | **okutma** | |
| kanıt, kanıttaki saat, kapı / servis kaydı | **kanıt kaydı, kanıt saati** | |
| soru, amir sorusu | **soru** | "Onay talebi" kullanılmaz |
| eskale, üst amire gitti, İK'ya gitti | **üst amire / İK'ya iletildi** | |
| uyarı, işaret, bilgi raporu | **uyarı** | "düştü / gitti" yerine "iletilir" |
| şüphe, arıza şüphesi | **arıza şüphesi** | Yalnızca okuyucu arızası ve kart paylaşımında |
| karar gerekli, karar bekliyor, İK kararı bekliyor | **İK incelemesi bekliyor** (uyarı), **İK kararı bekliyor** (soru, talep) | |
| bölüm, departman | **departman** | |
| personel, kişi, çalışan | **çalışan** | "Esnek çalışan personel" istisna |
| fazla çalışma, fazla mesai | **fazla mesai** | |
| onaysız çalışma, plansız çalışma, havuz | **onaysız fazla mesai** | |
| esnek mesai, esnek çalışma | **esnek çalışma** | |
| red, ret | **ret** (isim), **reddet** (fiil) | |
| süzgeç, filtre | **filtre** | |
| gir, ekle, aç (izin gir, talep aç) | **ekle** (kayıt), **oluştur** (talep) | |
| dışarıda, kimde, zimmetli | **zimmetli** | |
| boşta, verilebilir | **kullanılabilir** | |
| ver, kartı ver | **zimmetle** | |
| aktarım, yükleme | **yükleme** (işlem), **aktarım** (kayıt listesi) | |
| gelmeyen dosya, eksik dosya | **eksik dosya** | |
| açık iş, bekleyen gün, kesinleşmemiş gün | **kesinleşmemiş gün** (gün), **açık işlem** (soru + itiraz) | |
| sonraki aya geçer / fark olur | **izleyen aya fark satırı olarak aktarılır** | |
| plan, vardiya planı | **vardiya planı** | Fazla mesaide "fazla mesai planı" |
| giriş hesabı, hesap, Supabase Auth hesabı | **giriş hesabı** | Ürün adı görünmez |
| aleyhe, aleyhte | **çalışan aleyhine** | |
| yarın / sonraki, düşer / gider / yazılır | **iletilir, kaydedilir, oluşturulur** | Edilgen ve resmi |


## Ayarlar (Admin)

Ayarlar ekranında teknik anahtar görünmez. `cumartesi_hafta_sonu` "Açık / Kapalı" seçimi olur. Dakika ayarları "sa dk" biçiminde de gösterilir (giriş dakika ile kalır).

| Kategori | Ad | Açıklama (önerilen) | Şu anki açıklama |
|---|---|---|---|
| Puantaj | Geç kalma toleransı | Bu süreye kadar olan geç girişler geç kalma olarak değerlendirilmez. | Sorun 9: bu kadar geç kalma geç sayılmaz |
| Puantaj | Erken çıkış toleransı | Bu süreye kadar olan erken çıkışlar erken çıkış olarak değerlendirilmez. | Sorun 9: bu kadar erken çıkış erken sayılmaz |
| Puantaj | Yuvarlama dilimi | Tolerans aşıldığında geç kalma ve erken çıkış süreleri bu dilime yukarı yuvarlanır. Sıfır değerinde yuvarlama yapılmaz. | Tolerans aşılınca geç kalma / erken çıkış bu dakikalık dilimlere yukarı yuvarlanır (0 = kapalı) |
| Puantaj | Yürüme süresi | Kapı veya servis kaydına göre belirlenen giriş saatine eklenir. | Sorun 1: kapı ile PDKS okuyucu arası yürüme payı |
| Puantaj | Esnek çalışma günlük hedefi | Esnek çalışan personelin planlı her günü için beklenen net çalışma süresi. Aylık hedef bu süre üzerinden hesaplanır. | Esnek mesai: planlı her esnek gün için net çalışma hedefi (ay hedefi = gün sayısı × bu değer) |
| Puantaj | Cumartesi hafta tatili | Açık olduğunda Cumartesi çalışması hafta tatili çalışması (FM100) olarak hesaplanır. Kapalı olduğunda Cumartesi normal iş günüdür. | 1 ise Cumartesi çalışması FM100 sayılır; 0 ise Cumartesi normal iş günüdür (vardiyayı aşan kısım FM50) |
| Puantaj | Vardiya eşleştirme süresi | Okutmaların başka bir vardiyanın başlangıç ve bitişine bu süre içinde yakın olması durumunda vardiya önerisi oluşturulur. | Otomatik vardiya tanıma: okutmalar başka bir vardiyanın başına ve sonuna bu kadar yakınsa öneri yapılır |
| Fazla mesai | Günlük çalışma sınırı | Vardiya ve fazla mesai toplamı için günlük yasal üst sınır. | Fazla mesai: vardiya + fazla mesai günlük toplamı (11 saat) |
| Fazla mesai | Yıllık fazla mesai sınırı | Bir takvim yılında onaylanabilecek en fazla fazla mesai süresi. | Fazla mesai: yıllık en fazla onaylı fazla mesai (270 saat) |
| Fazla mesai | Yıllık sınır uyarı oranı | Yıllık fazla mesai sınırının bu oranına ulaşıldığında İK'ya uyarı gönderilir. | Fazla mesai: yıllık sınırın bu yüzdesine gelince İK'ya uyarı |
| Fazla mesai | Plansız fazla mesai toleransı | Vardiya sonrasında bu süreye kadar olan çalışmalar için uyarı oluşturulmaz. | Fazla mesai: vardiya sonrası bu kadar kalmak plansız çalışma uyarısı sayılmaz |
| Fazla mesai | Gece çalışması sınırı | 20.00–06.00 saatleri arasındaki çalışma bu süreyi aştığında İK'ya uyarı gönderilir. | Gece çalışması (20:00–06:00) bu süreyi aşarsa İK'ya uyarı (İş Kanunu m.69: 7,5 saat) |
| Mola | Kısa mola süresi | Kısa süreli çalışmalarda çalışma süresinden düşülen ara dinlenmesi. | Mola (m.68): 4 saate kadar çalışmada düşülen mola |
| Mola | Orta mola süresi | Orta süreli çalışmalarda çalışma süresinden düşülen ara dinlenmesi. | Mola (m.68): 4–7,5 saat çalışmada düşülen mola |
| Mola | Uzun mola süresi | Uzun süreli çalışmalarda çalışma süresinden düşülen ara dinlenmesi. | Mola (m.68): 7,5 saatten uzun çalışmada düşülen mola |
| Mola | Kısa mola çalışma sınırı | Bu süreye kadar olan çalışmalarda kısa mola süresi uygulanır. | Mola (m.68): bu süreye kadar olan çalışmada kısa mola düşülür (4 saat) |
| Mola | Orta mola çalışma sınırı | Bu süreye kadar olan çalışmalarda orta mola süresi, aşan çalışmalarda uzun mola süresi uygulanır. | Mola (m.68): bu süreye kadar olan çalışmada orta mola düşülür (7,5 saat) |
| Okuyucu ve kart | Mükerrer okutma süresi | Aynı kartın bu süre içinde aynı yöndeki okutmaları tek okutma olarak değerlendirilir. | Sorun 3: bu süre içindeki aynı yönlü okutmalar tek sayılır |
| Okuyucu ve kart | Okuyucu arıza süresi | Diğer okuyucular çalışırken bu süre boyunca okutma almayan okuyucu için arıza şüphesi oluşturulur. | Sorun 5: diğerleri çalışırken bu kadar sessiz kalan okuyucu için arıza şüphesi |
| Okuyucu ve kart | Okuyucu arıza kişi sayısı | Kapı kaydı bulunan ancak PDKS okutması bulunmayan çalışan sayısı bu değere ulaştığında arıza şüphesi oluşturulur. | Aynı gün bir PDKS okuyucusunda okutması olmayan ama kapı kaydı olan bu kadar kişi varsa arıza şüphesi |
| Okuyucu ve kart | Geçici kart iade süresi | Bu süre içinde iade edilmeyen geçici kartlar için İK'ya uyarı gönderilir. | Sorun 4: geçici kart bu kadar saattir iade edilmediyse İK'ya uyarı |
| Okuyucu ve kart | Geçici kart kullanım sınırı | Bir ay içinde bu sayıda geçici kart kullanan çalışan için İK'ya bilgi gönderilir. | Sorun 4: ayda bu kadar kart unutmada İK'ya bilgi raporu |
| Okuyucu ve kart | Kart paylaşımı süre aralığı | Aynı okuyucuda bu süre içinde art arda okutulan iki farklı kart, kart paylaşımı incelemesine dahil edilir. | Sorun 6: aynı okuyucuda bu kadar saniye içindeki iki farklı kart "ardışık çift" sayılır |
| Okuyucu ve kart | Kart paylaşımı gün sayısı | Aynı iki kartın bir ay içinde bu sayıda farklı günde art arda okutulması durumunda İK'ya uyarı gönderilir. | Sorun 6: aynı iki çalışan ayda bu kadar farklı günde ardışık çift oluşturursa İK'ya uyarı |
| İSG | Belge bitiş uyarı süresi | İSG eğitimi veya sağlık muayenesinin geçerlilik bitişinden bu süre önce uyarı oluşturulur. | İSG eğitimi / sağlık muayenesi bitişine bu kadar gün kala uyarı |
| Soru akışı | Soru cevap süresi | Bu süre içinde cevaplanmayan sorular üst amire, ardından İK'ya gönderilir. | Sorun 13: cevapsız soru bu kadar gün sonra üst amire ve İK'ya gider |

## Ekran metinleri

### Ayarlar
Rol: Admin

| Tür | Şu anki metin | Önerilen metin |
|---|---|---|
| mesaj | Ayar seçilmedi. | Ayar seçilmelidir. |
| mesaj | Yeni değeri yazın. | Yeni değer girilmelidir. |
| mesaj | Ayar güncellendi. Yeni değer bir sonraki hesapta kullanılır. | Ayar güncellendi. Yeni değer bir sonraki hesaplamadan itibaren geçerlidir. |
| başlık | Ayarlar | — |
| açıklama | Kuralların eşikleri. Değişiklik bir sonraki gece işinde ve hesapta kullanılır; kilitli ayları etkilemez. | Sistem kurallarında kullanılan değerler. Değişiklikler bir sonraki hesaplamadan itibaren geçerli olur, kilitli ayları etkilemez. |
| alan | Ayarlar bölümleri | — |
| metin | Eşikler | Ayarlar |
| metin | Değişiklik geçmişi | — |
| alan | Ayar ara | — |
| ipucu | ör. mola, fazla mesai, tolerans | — |
| açıklama | Aramaya uyan ayar yok. | Kayıt bulunmuyor. |
| sütun | Ayar | — |
| sütun | Değer | — |
| sütun | Son değişiklik | — |
| metin | İşlem | — |
| metin | İzin verilen aralık: | — |
| düğme | Değiştir | — |
| açıklama | Şu an: {a.deger.toLocaleString("tr-TR"} {a.birim}. Eski ve yeni değer geçmişe yazılır.{a.puantaji_etkiler ? " Puantaj} | Mevcut değer: {değer}. Değişiklik geçmişe kaydedilir. |
| açıklama | Puantajı etkilediği için İK'ya uyarı gider. | Değişiklik İK'ya bildirilir. |
| düğme | Kaydet | — |
| alan | Yeni değer ( | — |
| açıklama | Son 20 değişiklik. Kayıtlar silinemez; kim, ne zaman, neyi değiştirdi görünür. | Son 20 değişiklik gösterilir. Kayıtlar silinemez. |
| açıklama | Henüz ayar değiştirilmedi. | Kayıt bulunmuyor. |
| sütun | Zaman | — |
| sütun | Değişiklik | — |
| sütun | Yapan | İşlemi yapan |
| durum | İlk değer | — |
| metin | Sistem (kurulum) | Sistem |

### Çalışan sayfası
Rol: İK, Amir, Yönetici

| Tür | Şu anki metin | Önerilen metin |
|---|---|---|
| mesaj | Gün seçilmedi. | Gün seçilmelidir. |
| mesaj | Düzeltilecek alanı seçin. | Düzeltilecek alan seçilmelidir. |
| mesaj | Gerekçeyi yazın. | Gerekçe girilmelidir. |
| mesaj | Yeni değeri girin. | Yeni değer girilmelidir. |
| mesaj | Düzeltme kaydedildi (no {sonuc.veri}), gün yeniden hesaplandı. Ay kilitliyse fark satırı olarak sonraki aya geçer. | Düzeltme kaydedildi ve gün kaydı güncellendi. |
| mesaj | Çalışanın itirazını en az birkaç kelimeyle yazın. | İtiraz metni girilmelidir (en az 5 karakter). |
| mesaj | İtiraz kaydedildi (no {sonuc.veri}). Kararı İK verecek. | İtiraz kaydedildi ve İK'ya iletildi. |
| mesaj | Çalışan seçilmedi. | Çalışan seçilmelidir. |
| mesaj | Kart numarası harf, rakam ve tireden oluşmalı. | Kart numarası yalnızca harf, rakam ve tire içermelidir. |
| mesaj | Bu kayıt zaten var. | Bu kayıt daha önce eklenmiştir. |
| mesaj | {kartNo} numaralı kart başka bir kayıtta kullanılıyor. | — |
| mesaj | {kartNo} kartı tanımlandı. | {kartNo} numaralı kart tanımlandı. |
| mesaj | Kart seçilmedi. | Kart seçilmelidir. |
| mesaj | İptal nedenini seçin. | İptal nedeni seçilmelidir. |
| mesaj | Kart iptal edildi. | — |
| metin | Çalışan | — |
| mesaj | Son çalışma gününü girin. | Son çalışma günü girilmelidir. |
| metin | {o.iptal_edilen_kart} kart iptal | {n} kart iptal edildi |
| metin | {o.silinen_plan} plan silindi | {n} vardiya planı silindi |
| metin | {o.iptal_edilen_izin} izin iptal | {n} izin iptal edildi |
| metin | {o.iptal_edilen_fm_talebi} fazla mesai talebi iptal | {n} fazla mesai talebi iptal edildi |
| metin | {o.vardiya_yok_yapilan_gun} gün "vardiya yok" | {n} gün "Vardiya yok" olarak güncellendi |
| metin | kullanıcı hesabı pasif | kullanıcı hesabı pasife alındı |
| mesaj | {adSoyad} için işten çıkış kaydedildi{parcalar.length ? `: ${parcala}. | — |
| metin | Tamam (çalıştı) | Çalıştı |
| metin | Devamsız | — |
| metin | İzinli | — |
| metin | Raporlu | — |
| metin | Tatil | — |
| metin | Plan yok | Vardiya planı yok |
| alan | Düzeltilecek alan | — |
| seçenek | Giriş saati | — |
| seçenek | Çıkış saati | — |
| seçenek | Gün durumu | — |
| alan | Yeni değer | — |
| seçenek | Seçin | — |
| alan | Bağlı itiraz (isteğe bağlı) | — |
| seçenek | İtiraza bağlı değil | Bağlı itiraz yok |
| alan | Gerekçe | — |
| ipucu | ör. İtiraz kabul edildi, servis kaydı 07:40 | — |
| açıklama | Ham kayıt değişmez. Düzeltme kim, ne zaman, eski ve yeni değer ve gerekçesiyle silinemeyen bir tabloya yazılır. "Devamsız" çalışan aleyhine işaretlenir. Ay kilitliyse düzeltme sonraki aya fark satırı olur. | Okutma kaydı değiştirilmez. Düzeltme; tarih, kullanıcı ve gerekçe bilgisiyle kalıcı olarak saklanır. "Devamsız" kararı çalışan aleyhine kaydedilir. Kilitli aya ait düzeltmeler sonraki aya fark satırı olarak aktarılır. |
| metin | ← Çalışanlar | — |
| durum | Ayrıldı | — |
| durum | Başlayacak · | — |
| açıklama | Sicil | — |
| açıklama | · İşe giriş | — |
| açıklama | · Son çalışma günü | — |
| açıklama | · Kart | — |
| metin | Ay | — |
| düğme | Kart tanımla | — |
| başlık | {calisan.adSoyad} · yeni kart | — |
| açıklama | Kartın üzerindeki numarayı girin. Numara harf, rakam ve tireden oluşur; başka bir kartta kullanılamaz. | Kartın üzerindeki numara girilmelidir. Her kart numarası yalnızca bir kez kullanılabilir. |
| düğme | Kartı tanımla | — |
| alan | Kart numarası | — |
| ipucu | ör. K1031 | — |
| düğme | Kartı iptal et | — |
| başlık | {aktifKart.kart_no} kartını iptal et | — |
| açıklama | İptal edilen kart artık geçerli sayılmaz; okutulursa İK'ya uyarı düşer. Yeni kart iptalden sonra tanımlanır. | İptal edilen kart geçersiz olur ve okutulduğunda İK'ya uyarı iletilir. Yeni kart, iptal işleminden sonra tanımlanabilir. |
| düğme | İptal et | — |
| alan | Neden | — |
| seçenek | Kayıp | — |
| seçenek | Yenilendi | — |
| seçenek | İşten çıkış | — |
| seçenek | Diğer | — |
| başlık | {calisan.adSoyad} · işten çıkış | — |
| açıklama | Son çalışma günü girilir; ileri tarih olamaz. Kartı iptal edilir, sonraki planları silinir, sonraki izinleri ve bekleyen fazla mesai talepleri iptal edilir, kullanıcı hesabı varsa pasif olur. Son günler yarın sabah gece işinde yine işlenir. Geri alınamaz. | Çalışanın kartı iptal edilir, sonraki vardiya planları silinir, sonraki izinleri ve bekleyen fazla mesai talepleri iptal edilir, kullanıcı hesabı pasife alınır. Son çalışma günü ileri tarihli olamaz. Bu işlem geri alınamaz. |
| düğme | Çıkışı kaydet | — |
| alan | Son çalışma günü | — |
| alan | Açıklama (isteğe bağlı) | — |
| ipucu | ör. İstifa | — |
| başlık | Planlı gün | — |
| açıklama | İzinli günler hariç | — |
| başlık | İzinli gün | — |
| başlık | Çalışma | — |
| açıklama | Fazla mesai {saatDakika(ozet.fazlaMesaiDk)} (sa:dk) | Fazla mesai {sa dk} |
| başlık | Düzeltme | — |
| açıklama | Bu ayın kayıtlarında | Seçili ay |
| başlık | Bu ay için gün kaydı yok | Kayıt bulunmuyor |
| metin | Giriş-çıkış saatleri gece işi çalışınca oluşur. Plan, izin ve fazla mesai bilgileri aşağıda. | Giriş ve çıkış saatleri gece işleminden sonra görüntülenir. |
| alan | Çalışan kayıtları | — |
| metin | Günler | — |
| metin | Düzeltmeler | — |
| sütun | Gün | — |
| sütun | Plan | — |
| sütun | Giriş | — |
| sütun | Çıkış | — |
| sütun | Not | — |
| sütun | Durum | — |
| metin | Resmi tatil: {g.tatil} | — |
| metin | Fazla mesai {g.fazlaMesai} | — |
| metin | Geçici kart {g.geciciKart} | — |
| metin | Geç kalma {g.gecKalmaDk} dk | Geç kalma {sa dk} |
| metin | Erken çıkış {g.erkenCikisDk} dk | Erken çıkış {sa dk} |
| düğme | Düzelt | — |
| başlık | {calisan.adSoyad} · {g.tarihMetni} kaydını düzelt | — |
| açıklama | Şu an: giriş {g.giris ?? "—"}, çıkış {g.cikis ?? "—"}, {g.durum ?? "—"}. | Mevcut kayıt: giriş {saat}, çıkış {saat}, {durum}. |
| düğme | Düzeltmeyi kaydet | — |
| düğme | İtiraz gir | İtiraz ekle |
| başlık | {calisan.adSoyad} · {g.tarihMetni} itirazı | — |
| açıklama | Kayıt: giriş {g.giris ?? "—"}, çıkış {g.cikis ?? "—"}, {g.durum ?? "—"}. Çalışanın söylediğini yazın; kabul ya da red kararını İK verir. | Mevcut kayıt: giriş {saat}, çıkış {saat}, {durum}. İtiraz kararı İK tarafından verilir. |
| düğme | İtirazı kaydet | — |
| alan | İtiraz | — |
| ipucu | ör. 08:00'de geldim, kartım okumadı | — |
| açıklama | Ham kayıt değiştirilmez; her düzeltme kim, ne zaman, eski-yeni değer ve gerekçesiyle saklanır. | Okutma kaydı değiştirilmez; tüm düzeltmeler gerekçesiyle birlikte saklanır. |
| açıklama | Bu ay bu çalışanın kayıtlarında düzeltme yapılmadı. | Kayıt bulunmuyor. |
| sütun | Alan | — |
| sütun | Eski | — |
| sütun | Yeni | — |
| sütun | Yapan | İşlemi yapan |
| durum | Aleyhe | Çalışan aleyhine |
| metin | PDF oluşturulamadı. | PDF oluşturulamadı. Lütfen tekrar deneyin. |
| düğme | PDF hazırlanıyor… | — |
| düğme | Dökümü PDF olarak indir | PDF indir |
| metin | PDKS dökümü {calisan.sicil} {dokum.ay} | — |
| metin | Atlas Trafo PDKS | — |
| metin | PDKS kayıt dökümü | — |
| alan | Ad soyad | — |
| alan | Bölüm | Departman |
| alan | İşe giriş | — |
| alan | Planlı / izinli gün | — |
| alan | Çalışma (sa:dk) | Çalışma |
| metin | Tatil: {g.tatil} | — |
| metin | FM {g.fazlaMesai} | — |
| metin | Geç {g.gecKalmaDk} dk | — |
| metin | Erken {g.erkenCikisDk} dk | — |
| metin | Bu ay kayıtlarınızda düzeltme yapılmadı. | Kayıt bulunmuyor. |
| metin | (aleyhe, İK kararı) | (çalışan aleyhine, İK kararı) |
| metin | Bu belge PDKS kayıtlarından üretilmiştir ve ücret bilgisi içermez. Kayıtlara itirazınızı amirinize ya da İK'ya iletebilirsiniz. | Bu belge PDKS kayıtlarından oluşturulmuştur ve ücret bilgisi içermez. Kayıtlara ilişkin itirazlar amire veya İnsan Kaynaklarına iletilebilir. |
| metin | Hazırlayan: | — |

### Çalışanlar
Rol: Tümü

| Tür | Şu anki metin | Önerilen metin |
|---|---|---|
| mesaj | Sicil numarası harf, rakam ve tireden oluşmalı. | Sicil numarası yalnızca harf, rakam ve tire içermelidir. |
| mesaj | Ad ve soyadı yazın. | Ad ve soyad girilmelidir. |
| mesaj | Departmanı seçin. | Departman seçilmelidir. |
| mesaj | İşe giriş tarihini girin. | İşe giriş tarihi girilmelidir. |
| mesaj | {ad} {soyad} eklendi. Sırada: kart tanımlama ve vardiya planı (plan yoksa gece işi gün kaydı açmaz). | {ad} {soyad} eklendi. Kart ve vardiya planı tanımlanmalıdır. |
| başlık | Çalışanlar | — |
| açıklama | Yalnızca sorumlu olduğunuz bölümlerin çalışanları listelenir. | Sorumlu olunan departmanların çalışanları. |
| açıklama | Fabrikadaki çalışanlar. | Tüm çalışanlar. |
| düğme | Çalışan ekle | — |
| başlık | Yeni çalışan | — |
| açıklama | İşe giriş ileri tarihli olabilir; o güne kadar gece işi gün kaydı açmaz. Kart ve vardiya planı ayrıca girilir. Departman sonradan değiştirilemez. | İşe giriş tarihi ileri tarihli olabilir. Kart ve vardiya planı ayrıca tanımlanır. Departman sonradan değiştirilemez. |
| düğme | Ekle | — |
| alan | Sicil no | — |
| alan | İşe giriş | — |
| alan | Ad | — |
| alan | Soyad | — |
| alan | Departman | — |
| seçenek | Seçin | — |
| alan | Ara | — |
| ipucu | Sicil, ad ya da soyad | Sicil, ad veya soyad |
| alan | Bölüm | Departman |
| alan | Durum | — |
| seçenek | Ayrılanlar dahil | — |
| açıklama | kişi | — |
| açıklama | Süzgeçlere uyan çalışan yok. Süzgeçleri temizleyip yeniden deneyin. | Seçilen filtrelere uygun kayıt bulunmuyor. |
| açıklama | Görebileceğiniz çalışan kaydı yok. | Kayıt bulunmuyor. |
| sütun | Sicil | — |
| sütun | Ad soyad | — |
| durum | Başlayacak · | — |
| metin | Çalışıyor | — |
| durum | Ayrıldı | — |

### Departmanlar
Rol: İK, Amir, Yönetici

| Tür | Şu anki metin | Önerilen metin |
|---|---|---|
| başlık | Departmanlar | — |
| başlık | Departmanlar · | — |
| açıklama | Sorumlu olduğunuz departmanların aylık devam özeti. | Sorumlu olunan departmanların aylık devam özeti. |
| açıklama | Departmanların aylık devam özeti. Sayılar gece işinin kurduğu günlük kayıtlardan gelir. | Departmanların aylık devam özeti. |
| metin | Ay | — |
| metin | Bu ay | — |
| alan | Departman bölümleri | — |
| metin | Devam özeti | — |
| metin | Esnek mesai | Esnek çalışma |
| alan | Çalışan ara | — |
| alan | Departman ara | — |
| ipucu | Ad, sicil ya da departman | Ad, sicil veya departman |
| ipucu | ör. Bobinaj | — |
| açıklama | Bu ay için günlük kayıt yok. Özet, gece işi çalışınca oluşur. | Kayıt bulunmuyor. |
| başlık | Devam oranı | — |
| açıklama | {top("calisan_sayisi")} çalışan, {departmanlar.length} departman · {devamsiz} devamsız gün | — |
| başlık | Geç kalma | — |
| açıklama | {top("gec_kalinan_gun")} gün · erken çıkış {saatDakika(top("erken_cikis_dk} (sa:dk) | {n} gün · erken çıkış {sa dk} |
| başlık | Fazla mesai | — |
| açıklama | Onaylı, sa:dk | Onaylı |
| başlık | Açık iş | Açık işlem |
| açıklama | {top("acik_soru")} soru · {top("acik_itiraz")} itiraz · {top("bekleyen_gun")} kesinleşmemiş gün | — |
| açıklama | Aramaya uyan departman yok. | Seçilen filtrelere uygun kayıt bulunmuyor. |
| sütun | Departman | — |
| sütun | Çalışan | — |
| sütun | Çalışılan gün | — |
| sütun | Devamsız | — |
| sütun | Erken çıkış | — |
| metin | yaka | — |
| metin | gün | — |
| metin | gün bekliyor | — |
| açıklama | Esnek mesaili çalışanlar geliş saatini seçer; ay sonunda günlük hedefin toplamına bakılır. Eksi değer hedefin altını gösterir. İzinli ve tatil günleri hedefe girmez. | Esnek çalışan personelin aylık hedef ve gerçekleşen süreleri. Eksi değer, hedefin altında kalan süreyi gösterir. İzin ve tatil günleri hedefe dahil edilmez. |
| açıklama | Bu ay esnek mesaili çalışan kaydı yok. | Kayıt bulunmuyor. |
| açıklama | Aramaya uyan çalışan yok. | Seçilen filtrelere uygun kayıt bulunmuyor. |
| sütun | Hedef gün | — |
| sütun | Hedef | — |
| sütun | Gerçekleşen | — |
| sütun | Fark | — |

### Fazla mesai
Rol: İK, Amir, Yönetici

| Tür | Şu anki metin | Önerilen metin |
|---|---|---|
| mesaj | Fazla mesai gününü seçin. | Fazla mesai günü seçilmelidir. |
| mesaj | Süreyi 0,5 ile 11 saat arasında girin. | Süre 0,5 ile 11 saat arasında olmalıdır. |
| mesaj | Gerekçeyi yazın (ör. sipariş teslimi). | Gerekçe girilmelidir. |
| mesaj | {bulunan.calisan.adSoyad} için fazla mesai talebi açıldı. Kararı İK verecek. | {ad} için fazla mesai talebi oluşturuldu ve İK onayına gönderildi. |
| mesaj | Talep seçilmedi. | Talep seçilmelidir. |
| mesaj | Onay ya da red seçin. | Onay veya ret seçilmelidir. |
| mesaj | Red gerekçesini yazın. | Ret gerekçesi girilmelidir. |
| mesaj | Fazla mesai talebi onaylandı. | — |
| mesaj | Fazla mesai talebi reddedildi. | — |
| mesaj | Kayıt seçilmedi. | Kayıt seçilmelidir. |
| mesaj | Fazla çalışma onaylandı, puantaja eklendi. | Fazla mesai onaylandı ve puantaja eklendi. |
| mesaj | Fazla çalışma reddedildi; puantaja girmez. | Fazla mesai reddedildi. |
| mesaj | Yılı girin. | Yıl girilmelidir. |
| mesaj | İmza tarihini girin. | İmza tarihi girilmelidir. |
| mesaj | İmza tarihi onayın yılından sonra olamaz. | İmza tarihi, onay yılından sonra olamaz. |
| mesaj | Belge numarasını girin. | Belge numarası girilmelidir. |
| mesaj | Bu kayıt zaten var. | Bu kayıt daha önce eklenmiştir. |
| mesaj | {bulunan.calisan.adSoyad} için {yil} onayı zaten kayıtlı. | {ad} için {yil} yılı onayı daha önce kaydedilmiştir. |
| mesaj | {bulunan.calisan.adSoyad} için {yil} yazılı onayı kaydedildi. | — |
| mesaj | Bildirim tarihini girin. | Bildirim tarihi girilmelidir. |
| mesaj | {bulunan.calisan.adSoyad} için {yil} yazılı onayı yok. | {ad} için {yil} yılına ait yazılı onay bulunmuyor. |
| mesaj | Bu onay zaten geri alınmış. | Bu onay daha önce geri alınmıştır. |
| mesaj | Onay geri alındı; 30 gün sonra geçersiz olacak. | Onay geri alındı. Onay, bildirim tarihinden 30 gün sonra geçersiz olur. |
| başlık | Fazla mesai | — |
| metin | Vardiya sonrası | — |
| metin | Pazar / tatil çalışması | — |
| metin | İK kararı bekliyor | — |
| metin | Onaylandı | — |
| metin | Reddedildi | — |
| metin | İptal | — |
| başlık | Fazla mesai · | — |
| açıklama | Fazla mesai önceden planlanır: amir talep eder, İK onaylar. Yazılı onayı olmayan çalışana plan yapılamaz; günlük 11 saat ve yıllık | Fazla mesai, amirin talebi ve İK onayı ile planlanır. Yazılı onayı bulunmayan çalışan için plan yapılamaz. Günlük sınır 11 saat, yıllık sınır |
| açıklama | sınırını veritabanı denetler. | saattir. |
| düğme | Fazla mesai talebi aç | Talep oluştur |
| başlık | Fazla mesai talebi | — |
| açıklama | Talep İK onayına gider. Çalışanın o yıl için yazılı onayı yoksa ya da günlük 11 saat aşılıyorsa veritabanı talebi reddeder. | Talep İK onayına gönderilir. Çalışanın ilgili yıla ait yazılı onayı bulunmalı ve günlük 11 saat sınırı aşılmamalıdır. |
| düğme | Talebi aç | Talebi gönder |
| alan | Çalışanın sicil numarası | — |
| ipucu | Yazmaya başlayınca liste açılır. | Sicil numarası veya ad ile arama yapılabilir. |
| alan | Gün | — |
| alan | Süre (saat) | — |
| alan | Gerekçe | — |
| ipucu | ör. Sipariş teslimi için sargı işi | — |
| alan | Fazla mesai bölümleri | — |
| metin | Planlar | — |
| metin | karar bekliyor | — |
| metin | Onaysız çalışma | Onaysız fazla mesai |
| metin | Yıllık sınır | — |
| metin | Yazılı onaylar | — |
| metin | çalışanın onayı yok | çalışanın yazılı onayı yok |
| alan | Durum | — |
| alan | Çalışan ara | — |
| ipucu | Ad, soyad ya da sicil | Ad, soyad veya sicil |
| açıklama | plan | — |
| açıklama | · {bekleyenSayisi} tanesi İK kararı bekliyor | · {n} kayıt İK kararı bekliyor |
| açıklama | {yil} yılında fazla mesai planı yok. | Kayıt bulunmuyor. |
| açıklama | Süzgeçlere uyan plan yok. | Seçilen filtrelere uygun kayıt bulunmuyor. |
| sütun | Çalışan | — |
| sütun | Vardiya | — |
| sütun | Süre | — |
| sütun | Talep eden | — |
| metin | Gündüz | — |
| metin | Karar notu: | Karar açıklaması: |
| metin | Sistem | — |
| düğme | Karar ver | — |
| açıklama | Gerekçe: {p.gerekce}. Talep eden: {p.talep_eden?.ad_soyad ?? "—"}. | — |
| düğme | Kararı kaydet | — |
| başlık | Onaysız fazla çalışma | Onaysız fazla mesai |
| açıklama | Planı olmadan vardiya sonrasında ya da tatilde çalışılan süre. İK kararına kadar puantaja girmez. | Onaylı planı olmadan vardiya sonrasında veya tatilde çalışılan süreler. İK kararı verilene kadar puantaja dahil edilmez. |
| açıklama | {havuzBekleyen.length} kayıt karar bekliyor. | — |
| açıklama | {yil} yılında onaysız fazla çalışma kaydı yok. Kayıtlar gece işi çalışınca oluşur. | Kayıt bulunmuyor. |
| açıklama | Süzgeçlere uyan kayıt yok. | Seçilen filtrelere uygun kayıt bulunmuyor. |
| sütun | Tür | — |
| metin | · sonraki aya fark | · sonraki aya fark satırı |
| açıklama | {HAVUZ_TURU[h.tur]}. Onaylanırsa puantaja fazla mesai olarak girer; ay kilitliyse sonraki aya fark satırı olur. Yıllık sınır aşılsa da onaylanır, ayrıca uyarı yazılır. | {tür}. Onaylanan süre puantaja fazla mesai olarak eklenir; kilitli aya ait süre izleyen aya fark satırı olarak aktarılır. Yıllık sınır aşıldığında uyarı oluşturulur. |
| metin | Ret çalışan aleyhine bir karardır; süre puantaja girmez. | Ret kararı çalışan aleyhine kaydedilir ve süre puantaja dahil edilmez. |
| açıklama | Onaylı planların toplamı; sınır | Onaylı fazla mesai toplamı. Yıllık sınır |
| açıklama | . Sınırın % | — |
| açıklama | 'ine gelen çalışan için İK'ya uyarı düşer. | oranına ulaşıldığında İK'ya uyarı iletilir. |
| açıklama | Bu yıl fazla mesai planı olan çalışan yok. | Kayıt bulunmuyor. |
| açıklama | Aramaya uyan çalışan yok. | Seçilen filtrelere uygun kayıt bulunmuyor. |
| sütun | Onaylı | — |
| sütun | Bekleyen talep | — |
| sütun | Kalan | — |
| sütun | Doluluk | Kullanım oranı |
| açıklama | çalışanın | — |
| açıklama | için geçerli yazılı onayı var | için geçerli yazılı onay bulunuyor |
| açıklama | · {geriAlinanlar.length} onay geri alındı | — |
| açıklama | . Onayı olmayan çalışana fazla mesai planlanamaz. | . Yazılı onayı bulunmayan çalışan için fazla mesai planlanamaz. |
| düğme | Yazılı onay gir | Yazılı onay ekle |
| başlık | Yıllık yazılı fazla mesai onayı | — |
| açıklama | Çalışanın imzaladığı yıllık onay belgesi. Onayı olmayan çalışana fazla mesai planlanamaz. | Çalışanın imzaladığı yıllık onay belgesi kaydedilir. |
| düğme | Kaydet | — |
| alan | Yıl | — |
| alan | İmza tarihi | — |
| alan | Belge no | — |
| düğme | Onayı geri al | — |
| başlık | Yazılı onayın geri alınması | — |
| açıklama | Çalışan onayını yazılı bildirimle geri çeker; onay bildirimden 30 gün sonra geçersiz olur. | Çalışanın yazılı bildirimi kaydedilir. Onay, bildirim tarihinden 30 gün sonra geçersiz olur. |
| düğme | Geri al | — |
| alan | Bildirim tarihi | — |
| açıklama | Bütün çalışanların geçerli yazılı onayı var. | Kayıt bulunmuyor. |
| sütun | Onayı olmayan çalışan | — |
| sütun | Bölüm | Departman |
| durum | Geri alındı · | — |
| durum | itibarıyla geçersiz | — |
| metin | yılını göster | — |
| metin | yılına dön | — |
| metin | Yıllık sınır doluluğu | — |

### Geçici kartlar
Rol: Güvenlik, İK, Yönetici

| Tür | Şu anki metin | Önerilen metin |
|---|---|---|
| metin | Geçici kart | — |
| mesaj | Kart seçilmedi. | Kart seçilmelidir. |
| mesaj | {kartNo} kartı {calisan.adSoyad} adına verildi. | {kartNo} numaralı kart {ad} adına zimmetlendi. |
| mesaj | Zimmet seçilmedi. | Zimmet seçilmelidir. |
| mesaj | {kartNo} kartı iade alındı. | {kartNo} numaralı kart iade alındı. |
| başlık | Geçici kartlar | — |
| açıklama | kart · | — |
| açıklama | boşta · | kullanılabilir · |
| açıklama | zimmetli | — |
| açıklama | · {gecikenSayisi} kart {iadeSaati} saatten uzun süredir iade edilmedi | — |
| başlık | Kartlar | — |
| açıklama | Kayıtlı geçici kart yok. | Kayıt bulunmuyor. |
| metin | Kimde | Zimmetli çalışan |
| metin | Veriliş | Veriliş zamanı |
| metin | Süre | — |
| metin | Süre: | — |
| açıklama | Boşta, verilebilir. | Kullanılabilir. |
| açıklama | Kullanılamaz. | — |
| başlık | Son zimmet hareketleri | — |
| açıklama | En yeni | Son |
| açıklama | kayıt. Zimmet kayıtları silinemez. | kayıt gösterilir. Zimmet kayıtları silinemez. |
| alan | Çalışan ya da kart ara | Çalışan veya kart ara |
| ipucu | Ad, sicil ya da GK-01 | Ad, sicil veya GK-01 |
| açıklama | Henüz zimmet kaydı yok. | Kayıt bulunmuyor. |
| açıklama | Aramaya uyan zimmet kaydı yok. | Seçilen filtrelere uygun kayıt bulunmuyor. |
| sütun | Kart | — |
| sütun | Çalışan | — |
| sütun | İade | — |
| sütun | Veren / İade alan | — |
| sütun | Açıklama | — |
| durum | İade edilmedi | İade bekleniyor |
| durum | Zimmetli | — |
| düğme | Ver | Zimmetle |
| başlık | {kartNo} kartını ver | — |
| açıklama | Kartını unutan çalışana geçici kart zimmetlenir. Kart gün sonunda iade alınmalıdır. | Geçici kart çalışana zimmetlenir. Kart gün sonunda iade alınmalıdır. |
| düğme | Kartı ver | Zimmetle |
| alan | Çalışanın sicil numarası | — |
| ipucu | Yazmaya başlayınca liste açılır. Kendinize kart veremezsiniz. | Kullanıcı kendisine kart zimmetleyemez. |
| alan | Açıklama (isteğe bağlı) | — |
| ipucu | ör. Kartını evde unuttu | ör. Kart unutuldu |
| metin | çalışan | — |
| düğme | İade al | — |
| başlık | {kartNo} kartını iade al | — |
| açıklama | {kisi} kartı {tarihSaat(zimmet.verilis_zaman} tarihinde almıştı. İade zamanı şu an olarak yazılır ve sonradan değiştirilemez. | {kişi} kartı {tarih} tarihinde teslim almıştır. İade zamanı sonradan değiştirilemez. |
| düğme | İade alındı | İade al |
| durum | Kayıp | — |
| durum | İptal | — |
| durum | Boşta | Kullanılabilir |

### İSG
Rol: İSG, İK, Yönetici

| Tür | Şu anki metin | Önerilen metin |
|---|---|---|
| mesaj | Belge türünü seçin. | Belge türü seçilmelidir. |
| mesaj | Geçerlilik bitiş tarihini girin. | Geçerlilik bitiş tarihi girilmelidir. |
| mesaj | {bulunan.calisan.adSoyad} için belge kaydedildi. | — |
| mesaj | Bölge ya da departman seçilmedi. | Bölge ve departman seçilmelidir. |
| mesaj | Bölge yetkisi verildi. | — |
| mesaj | Bölge yetkisi kaldırıldı. | — |
| başlık | İSG | — |
| metin | İSG eğitimi | — |
| metin | Sağlık muayenesi | — |
| metin | Kayıt yok | — |
| metin | Süresi dolmuş | — |
| metin | Süresi doluyor | — |
| metin | Geçerli | — |
| açıklama | İSG eğitimi ve periyodik sağlık muayenesinin yalnızca geçerlilik tarihi tutulur; sonuç ya da teşhis tutulmaz. Kapı kilitlenmez: belgesi olmayan ya da yetkisiz bölgeye giren çalışan için uyarı üretilir. | İSG eğitimi ve periyodik sağlık muayenesinin yalnızca geçerlilik tarihi kaydedilir; sağlık bilgisi tutulmaz (KVKK). Belgesi eksik olan veya yetkisiz bölgeye giren çalışan için uyarı oluşturulur. |
| açıklama | Mavi yaka, belge türü başına | Mavi yaka, belge türü bazında |
| açıklama | Uyarı süresi içinde | — |
| alan | İSG bölümleri | — |
| metin | Belgeler | — |
| metin | eksik ya da dolan belge | eksik veya süresi dolan belge |
| metin | Bölge yetkileri | — |
| açıklama | satır | — |
| düğme | Belge gir | Belge ekle |
| başlık | İSG belgesi | — |
| açıklama | Yenileme yeni kayıttır; en son girilen geçerli sayılır. Kendi belgenizi giremezsiniz. | Yenilenen belge yeni kayıt olarak eklenir ve son kayıt geçerli olur. Kullanıcı kendi belgesini ekleyemez. |
| düğme | Kaydet | — |
| alan | Çalışanın sicil numarası | — |
| ipucu | Yazmaya başlayınca liste açılır. | Sicil numarası veya ad ile arama yapılabilir. |
| alan | Tür | — |
| seçenek | Seçin | — |
| alan | Geçerlilik bitişi | — |
| alan | Belge no (isteğe bağlı) | — |
| alan | Göster | — |
| seçenek | Eksik / dolan (mavi yaka) | Eksik veya süresi dolan (mavi yaka) |
| alan | Çalışan ara | — |
| ipucu | Ad, soyad ya da sicil | Ad, soyad veya sicil |
| açıklama | Aramaya uyan belge kaydı yok. | Seçilen filtrelere uygun kayıt bulunmuyor. |
| açıklama | Mavi yakada eksik ya da süresi dolan belge yok. | Kayıt bulunmuyor. |
| açıklama | Belge kaydı yok. | Kayıt bulunmuyor. |
| sütun | Çalışan | — |
| sütun | Departman | — |
| sütun | Belge | — |
| sütun | Geçerlilik | — |
| sütun | Durum | — |
| metin | yaka) | — |
| başlık | Bölge giriş yetkileri | — |
| açıklama | Yetkisiz departmandan biri bölge kapısında okutursa İK ve İSG'ye uyarı düşer. Verme ve kaldırma kim / ne zaman bilgisiyle saklanır. ✓ yetkili, — yetkisiz. | Yetkisiz bölge girişlerinde İK ve İSG birimine uyarı iletilir. Yetki değişiklikleri tarih ve kullanıcı bilgisiyle saklanır. ✓ yetkili, — yetkisiz. |
| açıklama | Tanımlı bölge yok. | Kayıt bulunmuyor. |
| metin | Yetkili | — |
| metin | Yetkisiz | — |
| düğme | Kaldır | Yetkiyi kaldır |
| düğme | Ver | Zimmetle |
| başlık | Son değişiklikler | — |
| metin | kaldırıldı | — |

### İtirazlar
Rol: İK, Amir, Yönetici

| Tür | Şu anki metin | Önerilen metin |
|---|---|---|
| mesaj | İtiraz seçilmedi. | İtiraz seçilmelidir. |
| mesaj | İtiraz incelemeye alındı. | — |
| mesaj | Kabul ya da red seçin. | Kabul veya ret seçilmelidir. |
| mesaj | Kararın gerekçesini yazın. | Karar gerekçesi girilmelidir. |
| mesaj | İtiraz kabul edildi. Kaydı çalışan sayfasından düzeltin. | İtiraz kabul edildi. Kayıt, çalışan sayfasından düzeltilmelidir. |
| mesaj | İtiraz reddedildi. | — |
| başlık | İtirazlar | — |
| açıklama | Bölümünüzdeki çalışanların kayıtlarına itirazları. Kararı İK verir. | Sorumlu olunan departmanlardaki itirazlar. İtiraz kararı İK tarafından verilir. |
| açıklama | Çalışanların kayıtlarına itirazları. Kabul ya da red kararı İK'dadır. | Çalışanların kayıtlarına ilişkin itirazlar. |
| alan | Durum | — |
| seçenek | Açık olanlar | — |
| alan | Gün, başlangıç | — |
| alan | Bitiş | — |
| alan | Çalışan ara | — |
| ipucu | Ad, soyad ya da sicil | Ad, soyad veya sicil |
| açıklama | itiraz | — |
| açıklama | Süzgeçlere uyan itiraz yok. Süzgeçleri temizleyip yeniden deneyin. | Seçilen filtrelere uygun kayıt bulunmuyor. |
| açıklama | Henüz itiraz girilmedi. | Kayıt bulunmuyor. |
| açıklama | Açık itiraz yok. | Kayıt bulunmuyor. |
| sütun | Gün | — |
| sütun | Çalışan | — |
| sütun | İtiraz | — |
| alan | Kayıt | — |
| metin | Karar: | — |
| düğme | İncelemeye al | — |
| açıklama | Yeni itiraz, çalışanın sayfasında ilgili günün yanındaki | Yeni itiraz, çalışan sayfasında ilgili günün yanındaki |
| açıklama | düğmesiyle girilir. | düğmesi ile eklenir. |
| düğme | Karar ver | — |
| başlık | {kisi} · {itiraz.gun ? tarih(itiraz.gun.} itirazı | — |
| düğme | Kararı kaydet | — |
| metin | Kabul et | — |
| metin | Reddet | — |
| metin | Red çalışan aleyhine bir karardır. Gerekçe çalışana verilecek dökümde görünür. | Ret kararı çalışan aleyhine kaydedilir. Gerekçe, çalışana verilen dökümde yer alır. |
| açıklama | Kabul, kaydı kendiliğinden düzeltmez. Kabulden sonra çalışan sayfasında o günün "Düzelt" düğmesiyle düzeltmeyi bu itiraza bağlayın. | Kabul kararı kaydı otomatik olarak düzeltmez. Düzeltme, çalışan sayfasında ilgili günün "Düzelt" işlemi ile bu itiraza bağlanmalıdır. |

### İzinler
Rol: İK

| Tür | Şu anki metin | Önerilen metin |
|---|---|---|
| mesaj | İzin türünü seçin. | İzin türü seçilmelidir. |
| mesaj | Başlangıç gününü seçin. | Başlangıç günü seçilmelidir. |
| mesaj | Bitiş günü başlangıçtan önce olamaz. | Bitiş günü, başlangıç gününden önce olamaz. |
| mesaj | {bulunan.calisan.adSoyad} için izin kaydedildi. | — |
| mesaj | İzin seçilmedi. | İzin seçilmelidir. |
| mesaj | İptal nedenini yazın (en az 5 karakter). | İptal nedeni girilmelidir (en az 5 karakter). |
| mesaj | İzin iptal edildi. | — |
| mesaj | Günü seçin. | Gün seçilmelidir. |
| mesaj | Başlangıç ve bitiş saatini girin. | Başlangıç ve bitiş saati girilmelidir. |
| mesaj | Bitiş saati başlangıçtan sonra olmalı. | Bitiş saati, başlangıç saatinden sonra olmalıdır. |
| mesaj | {bulunan.calisan.adSoyad} için saatlik izin kaydedildi. | — |
| başlık | İzinler | — |
| metin | Yıllık izin | — |
| metin | Rapor | — |
| metin | Mazeret izni | — |
| metin | Ücretsiz izin | — |
| metin | Diğer | — |
| metin | Vizite | — |
| metin | Mazeret | — |
| başlık | İzinler · | — |
| açıklama | Gün ve saat bazlı izinler. Yanlış girilen izin silinmez, iptal edilir. İzin türü yalnızca İK'ya görünür; amir "İzinli" görür. | Gün ve saat bazlı izinler. İzin kayıtları silinmez, iptal edilir. İzin türü yalnızca İK tarafından görüntülenir (KVKK). |
| metin | Ay | — |
| metin | Bu ay | — |
| düğme | İzin gir | İzin ekle |
| başlık | Gün bazlı izin | — |
| açıklama | Kendi izninizi giremezsiniz. İzinli günler gece işinde “izinli / raporlu” olarak işlenir. | Kullanıcı kendi iznini ekleyemez. İzin günleri gece işleminde kayıtlara yansıtılır. |
| düğme | İzni kaydet | Kaydet |
| alan | Çalışanın sicil numarası | — |
| ipucu | Yazmaya başlayınca liste açılır. | Sicil numarası veya ad ile arama yapılabilir. |
| alan | Tür | — |
| seçenek | Seçin | — |
| alan | Başlangıç | — |
| alan | Bitiş | — |
| alan | Açıklama (isteğe bağlı) | — |
| düğme | Saatlik izin gir | Saatlik izin ekle |
| başlık | Saatlik izin | — |
| açıklama | Gün içinde saat aralıklı izin (vizite, mazeret). Çakışan izin, kilitli ay ve iş günüyle uyuşmayan saat reddedilir. | Gün içindeki saatlik izinler (vizite, mazeret). İzin; başka bir izinle çakışmamalı, açık bir aya ait olmalı ve iş günü içinde yer almalıdır. |
| alan | Gün | — |
| alan | İzin türü | — |
| metin | Gün bazlı | — |
| metin | Saatlik | — |
| alan | Çalışan ara | — |
| ipucu | Ad, soyad ya da sicil | Ad, soyad veya sicil |
| başlık | Gün bazlı izinler | — |
| açıklama | izin | — |
| açıklama | · {izinler.length - gecerli.lengt} iptal edilmiş | — |
| açıklama | Aramaya uyan izin yok. | Seçilen filtrelere uygun kayıt bulunmuyor. |
| açıklama | Bu ayda gün bazlı izin girilmemiş. | Kayıt bulunmuyor. |
| sütun | Tarih | — |
| sütun | Çalışan | — |
| sütun | Açıklama | — |
| sütun | Giren | Ekleyen |
| sütun | Durum | — |
| metin | İptal nedeni: {i.iptal_nedeni ?? "—"} | — |
| metin | İptal edildi | — |
| metin | Geçerli | — |
| düğme | İptal et | — |
| başlık | İzni iptal et | — |
| açıklama | {i.calisan ? `${i.calisan.ad} $} · {turAdi} · {tarih(i.baslangic)}{i.bitis !== i.baslangic ? ` – }. İzin silinmez; iptal bilgisiyle saklanır. Gece işinden geçmiş günü varsa iptal edilemez, o günler kayıt düzeltmeyle düzeltilir. | {çalışan} · {tür} · {tarih}. İzin kaydı silinmez, iptal bilgisiyle saklanır. İşlenmiş günü bulunan izin iptal edilemez; ilgili günler kayıt düzeltme ile güncellenmelidir. |
| alan | İptal nedeni | — |
| ipucu | ör. Yanlış çalışana girilmiş | ör. Hatalı çalışan seçimi |
| başlık | Saatlik izinler | — |
| açıklama | izin. Saatlik izin dakikası puantajda ayrıca tutulur. | izin. Saatlik izin süresi puantajda ayrıca gösterilir. |
| açıklama | Aramaya uyan saatlik izin yok. | Seçilen filtrelere uygun kayıt bulunmuyor. |
| açıklama | Bu ayda saatlik izin girilmemiş. | Kayıt bulunmuyor. |
| sütun | Saat | — |

### Kullanıcılar
Rol: Admin

| Tür | Şu anki metin | Önerilen metin |
|---|---|---|
| mesaj | E-posta yazın. | E-posta adresi girilmelidir. |
| mesaj | Rolü seçin. | Rol seçilmelidir. |
| mesaj | {bulunan.calisan.adSoyad} kullanıcı olarak tanımlandı. Giriş hesabı Supabase Auth'ta aynı e-postayla açılmalı. | {ad} kullanıcı olarak tanımlandı. Giriş hesabı aynı e-posta adresiyle oluşturulmalıdır. |
| mesaj | Kullanıcı seçilmedi. | Kullanıcı seçilmelidir. |
| mesaj | Geçersiz rol. | Geçerli bir rol seçilmelidir. |
| mesaj | Kullanıcı güncellendi. | — |
| başlık | Kullanıcılar | — |
| açıklama | Sisteme giren her kişi bir çalışan kaydına bağlıdır. Giriş hesabı Supabase Auth'ta aynı e-postayla açılır; açılınca kendiliğinden bağlanır. Kullanıcı silinmez, pasif yapılır. | Her kullanıcı bir çalışan kaydına bağlıdır. Giriş hesabı aynı e-posta adresiyle oluşturulduğunda kullanıcıya otomatik olarak bağlanır. Kullanıcılar silinmez, pasife alınır. |
| açıklama | kullanıcı · | — |
| açıklama | tanesinin giriş hesabı yok | giriş hesabı bekliyor |
| düğme | Kullanıcı ekle | — |
| başlık | Yeni kullanıcı | — |
| açıklama | Kendinize hesap açamazsınız. Aynı e-posta ya da hesabı olan çalışan reddedilir. | Her çalışan ve e-posta adresi için yalnızca bir kullanıcı tanımlanabilir. Kullanıcı kendisine hesap tanımlayamaz. |
| düğme | Ekle | — |
| alan | Çalışanın sicil numarası | — |
| ipucu | Yazmaya başlayınca liste açılır. Ad soyad çalışan kaydından gelir. | Ad soyad bilgisi çalışan kaydından alınır. |
| alan | Rol | — |
| seçenek | Seçin | — |
| alan | Üst amir (isteğe bağlı) | — |
| seçenek | Yok | — |
| seçenek | Tüm roller | — |
| alan | Durum | — |
| seçenek | Aktif | — |
| seçenek | Pasif | — |
| seçenek | Giriş hesabı olmayanlar | Giriş hesabı bekleyenler |
| alan | Ara | — |
| ipucu | Ad, e-posta ya da sicil | Ad, e-posta veya sicil |
| açıklama | Süzgeçlere uyan kullanıcı yok. Süzgeçleri temizleyip yeniden deneyin. | Seçilen filtrelere uygun kayıt bulunmuyor. |
| açıklama | Henüz kullanıcı tanımlanmadı. | Kayıt bulunmuyor. |
| sütun | Ad soyad | — |
| sütun | E-posta | — |
| sütun | Üst amir | — |
| metin | · hesap yok | · giriş hesabı yok |
| düğme | Düzenle | — |
| açıklama | Rol değişikliği bir sonraki girişte geçerli olur. Pasif kullanıcı giriş yapamaz. | Rol değişikliği bir sonraki girişte geçerli olur. Pasif kullanıcılar sisteme giriş yapamaz. |
| düğme | Kaydet | — |
| ipucu | Kaldırılamaz, yalnızca değiştirilir. | Üst amir kaldırılamaz, değiştirilebilir. |
| seçenek | Değiştirme | Değişiklik yok |

### Çerçeve
Rol: Tümü

| Tür | Şu anki metin | Önerilen metin |
|---|---|---|
| başlık | Hesabınız sisteme bağlı değil | Hesap tanımlı değil |
| metin | Giriş yaptınız, ancak hesabınız bir PDKS kullanıcısına bağlı değil ya da pasif. İK ile görüşün. | Hesap, aktif bir PDKS kullanıcısına bağlı değil. İnsan Kaynakları ile iletişime geçilmelidir. |
| düğme | Çıkış yap | — |
| metin | Atlas Trafo | — |
| metin | PDKS Kayıt Düzeltme | — |
| metin | Ana menü | — |
| ipucu | Çalışan ara (sicil, ad)… | — |
| metin | Çalışan ara | — |
| metin | Sayfa yükleniyor… | — |

### Ana sayfa
Rol: Tümü

| Tür | Şu anki metin | Önerilen metin |
|---|---|---|
| başlık | Hoş geldiniz, | — |
| metin | Sorular | — |
| metin | İtirazlar | — |
| metin | Uyarılar | — |
| metin | Vardiya onayları | — |
| metin | Fazla mesai talepleri | — |
| metin | Zimmetler | — |
| metin | İzinler | — |
| metin | İK kararı bekliyor | — |
| metin | Kararınızı bekliyor | Karar bekliyor |
| başlık | Gece işi henüz hiç çalışmadı | Gece işlemi henüz çalıştırılmadı |
| metin | Günlük kayıtlar, amir soruları ve uyarılar gece işi çalışınca oluşur. O zamana kadar bu sayılar sıfır görünür. | Gün kayıtları, sorular ve uyarılar gece işleminden sonra görüntülenir. |
| başlık | Bekleyen işler | Bekleyen işlemler |
| başlık | Geriye dönük vardiya değişikliği | — |
| açıklama | Bekleyen yok | Bekleyen kayıt bulunmuyor |
| başlık | Fazla mesai talebi | — |
| başlık | İK kararı bekleyen kayıt | İK kararı bekleyen soru |
| açıklama | Amirin 'gelmedi' dediği ya da cevapsız kalan günler | Amirin "Gelmedi" cevabı verdiği günler |
| başlık | Açık itiraz | — |
| açıklama | Sonuçlandırılmayı bekliyor | Karar bekliyor |
| açıklama | Açık itiraz yok | Açık itiraz bulunmuyor |
| başlık | Bugün | — |
| başlık | İzinli çalışan | — |
| başlık | Dışarıdaki geçici kart | Zimmetli geçici kart |
| açıklama | İade edilmedi | İade bekleniyor |
| açıklama | Bütün kartlar güvenlikte | Zimmetli kart bulunmuyor |
| başlık | Amirlerde bekleyen soru | Cevap bekleyen soru |
| açıklama | Kanıt bulunamayan kayıtlar | Amir cevabı bekleniyor |
| başlık | Görülmemiş uyarı | Yeni uyarı |
| açıklama | Arıza, dosya gelmedi, kart paylaşımı şüphesi… | Henüz görüldü olarak işaretlenmedi |
| açıklama | Son gece işi: | Son gece işlemi: |
| açıklama | günü · | — |
| açıklama | başarılı ({tarihSaat(geceIsi.bitis)}) | — |
| açıklama | şu an çalışıyor | çalışıyor |
| açıklama | hata verdi{geceIsi.hata_mesaji ? `: ${gec} | — |
| metin | Düzeltmeler | — |
| başlık | Hatalı kayıtlar nasıl düzeldi? | Kayıt düzeltme dağılımı |
| açıklama | Son 30 gün ( | — |
| açıklama | ). Sistemin kimseye sormadan, kanıt ya da izin kaydıyla düzelttiği kayıt oranı: | ). Sistem tarafından otomatik düzeltilen kayıt oranı: |
| metin | kayıt | — |
| metin | Sistem düzeltti (kanıt / izin kaydı) | Otomatik düzeltme |
| metin | Amirin cevabıyla düzeldi | Amir cevabı ile düzeltme |
| metin | İK düzeltti | İK düzeltmesi |
| metin | Cevap bekliyor | — |
| başlık | Cevap bekleyen soru | — |
| açıklama | Cevapsız soru 3 gün sonra üst amire ve İK'ya gider | Süresinde cevaplanmayan sorular üst amire iletilir |
| açıklama | Bekleyen soru yok | Bekleyen soru bulunmuyor |
| başlık | Fazla mesai talebiniz | Fazla mesai talebi |
| açıklama | Bekleyen talep yok | Bekleyen talep bulunmuyor |
| açıklama | Bölümünüzdeki çalışanların itirazları | Sorumlu olunan departmanlar |
| başlık | Bugün ekibiniz | Bugünkü ekip durumu |
| başlık | Planlı çalışan | — |
| açıklama | Bugün planlı vardiya yok | Bugün için vardiya planı bulunmuyor |
| başlık | İzinli | — |
| başlık | Geçici kartlar | — |
| başlık | Verilebilir kart | Kullanılabilir kart |
| başlık | Dışarıdaki kart | Zimmetli kart |
| açıklama | Henüz iade edilmedi | İade bekleniyor |
| başlık | Geciken iade | — |
| açıklama | {IADE_SURESI_SAAT} saatten uzun süredir dışarıda | {n} saatten uzun süredir zimmetli |
| metin | İSG belgeleri | — |
| başlık | İSG | — |
| başlık | Belgesi olmayan | — |
| açıklama | Mavi yaka, belge türü başına | Mavi yaka, belge türü bazında |
| başlık | Süresi dolmuş | — |
| başlık | Süresi doluyor | — |
| açıklama | Uyarı süresi içinde | — |
| açıklama | İSG ve yetkisiz bölge | — |
| metin | Kullanıcılar | — |
| başlık | Sistem | — |
| başlık | Aktif kullanıcı | — |
| başlık | Giriş hesabı yok | Giriş hesabı bekleyen |
| açıklama | Supabase Auth'ta açılmalı | Giriş hesabı oluşturulmalıdır |
| başlık | Son gece işi | Son gece işlemi |
| metin | Başarılı | — |
| metin | Hatalı | — |
| metin | Çalışıyor | — |
| açıklama | {tarih(gece.islenen_gun)} günü{gece.hata_mesaji ? ` · ${gece.} | — |
| açıklama | Hiç çalışmadı | Kayıt bulunmuyor |

### Puantaj
Rol: İK

| Tür | Şu anki metin | Önerilen metin |
|---|---|---|
| mesaj | Ay seçilmedi. | Ay seçilmelidir. |
| mesaj | Bu ay henüz bitmedi; yalnızca bitmiş ay kilitlenebilir. | Yalnızca tamamlanmış aylar kilitlenebilir. |
| mesaj | Kilidin geri açılamayacağını onaylayın. | Kilidin geri açılamayacağı onaylanmalıdır. |
| metin | Ay kilitlendi. | — |
| mesaj | {ozet} Puantaj yazıldı; Excel ve ERP dosyaları artık kesin.{kodsuz ? " Kodsuz günler bordr} | {özet} Puantaj kesinleşti; Excel ve ERP dosyaları kullanılabilir. |
| mesaj | Kodsuz günler bordroda elle kontrol edilmeli. | Kodsuz günler bordroda ayrıca kontrol edilmelidir. |
| düğme | ERP için CSV | ERP dosyası (CSV) |
| düğme | ERP için XML | ERP dosyası (XML) |
| başlık | Ait olduğu ay | — |
| metin | Puantaj | — |
| metin | Fark satırları | — |
| metin | Sicil | — |
| metin | Satır türü | — |
| metin | Kod | — |
| metin | Gün | — |
| metin | Dakika | — |
| metin | Puantaj kodları | — |
| metin | Dönem | — |
| metin | Durum | — |
| metin | Kilitli (kesin) | Kilitli |
| metin | Açık (canlı hesap, kesin değil) | Açık (kesinleşmemiş) |
| metin | Hazırlayan | — |
| metin | Hazırlanma zamanı | — |
| metin | Not | — |
| metin | Ücret hesaplanmaz; yalnızca gün ve dakika vardır. Fark satırları önceki aylara ait düzeltmelerdir. | Dosya yalnızca gün ve süre bilgisi içerir. Fark satırları önceki aylara ait düzeltmelerdir. |
| metin | Kodlar | — |
| metin | NÇ normal çalışma · FM50 hafta içi fazla mesai · FM100 Pazar / resmi tatil çalışması · Yİ yıllık izin · RPR rapor · MZR mazeret · ÜCSZ ücretsiz izin · Dİ diğer izin · DVMSZ devamsız · RT resmi tatil · HT hafta tatili. Kod sayfası yalnızca kilitli ayda vardır. | — |
| metin | Bilgi | Bilgilendirme |
| düğme | Hazırlanıyor… | — |
| düğme | Excel olarak indir | Excel indir |
| düğme | Taslağı Excel olarak indir | Taslak Excel indir |
| metin | {acikSoru.count} açık soru | {n} açık soru |
| metin | {acikItiraz.count} açık itiraz | — |
| metin | {bekleyenHavuz.count} kararı bekleyen onaysız fazla mesai | — |
| metin | {bekleyenPlan.count} İK onayı bekleyen geriye dönük plan | — |
| başlık | Puantaj · | — |
| açıklama | Bordroya giden gün ve dakika özeti. Ücret hesaplanmaz. | Bordroya aktarılacak gün ve süre özeti. Ücret bilgisi içermez. |
| metin | Ay | — |
| metin | Bu ay | — |
| metin | Kilitli | — |
| metin | Açık | — |
| açıklama | Canlı hesap; ay kilitlenince kesinleşir | Ay kilitlendiğinde kesinleşir |
| başlık | Çalışan | — |
| açıklama | {farkSatirlari.length} fark satırı | — |
| açıklama | Bordroya girecek | Bordroya aktarılacak |
| başlık | Toplam çalışma | — |
| açıklama | Fazla mesai {saatDakika(toplamFmDk)} (sa:dk) | Fazla mesai {sa dk} |
| başlık | Kesinleşmemiş gün | — |
| açıklama | Hesaplanmış gün yok | Kayıt bulunmuyor |
| açıklama | Soru, eksik kayıt ya da hesap bekliyor | Soru, eksik kayıt veya hesaplama bekleniyor |
| açıklama | Hepsi kesin | Tüm günler kesinleşti |
| başlık | Bu ay için hesaplanmış gün yok | Kayıt bulunmuyor |
| metin | Puantaj, gece işinin ürettiği günlük kayıtlardan hesaplanır. Gece işi çalışınca sayılar dolar; liste şimdilik sıfırlarla gösteriliyor. | Puantaj, gece işleminden sonra hesaplanır. |
| açıklama | henüz bitmedi. Ay kilidi | — |
| açıklama | tarihinden itibaren yapılabilir. | — |
| açıklama | Şu an {acikIsler.join(", ")} var. | — |
| düğme | Ayı kilitle | — |
| başlık | {ayAdi(ay)} dönemini kilitle | — |
| açıklama | Puantaj kesinleşir ve bordroya gider. Kilit geri açılamaz; sonradan gelen düzeltme sonraki aya fark satırı olarak yazılır. | Puantaj kesinleşir. Kilit geri açılamaz; sonraki düzeltmeler izleyen aya fark satırı olarak aktarılır. |
| açıklama | Bu ayda | — |
| açıklama | var. | — |
| açıklama | Bunlar kapanmadan kilitlenirse sonuçları sonraki aya fark satırı olarak geçer. | Bu kayıtlar sonuçlanmadan kilitleme yapılırsa sonuçlar izleyen aya fark satırı olarak aktarılır. |
| açıklama | Onay bekleyen planın günü gece işinden hiç geçmediyse ay zorla da kilitlenmez; planı önce onaylayın ya da reddedin. | İşlenmemiş günü bulunan bekleyen planlar, ay kilitlenmeden önce onaylanmalı veya reddedilmelidir. |
| alan | Yine de kilitle | Bekleyen kayıtlarla birlikte kilitle |
| açıklama | Bu ayda açık soru, itiraz, kararı bekleyen fazla mesai ya da onay bekleyen plan yok. | Bu ayda bekleyen kayıt bulunmuyor. |
| açıklama | gün henüz kesinleşmemiş (eksik kayıt ya da hesap bekliyor). | gün kesinleşmemiştir (eksik kayıt veya bekleyen hesaplama). |
| açıklama | Gece işinden geçmemiş planlı gün varsa (ör. o günün dosyası yüklenmediyse) ay kilitlenmez; veritabanı hangi günler olduğunu söyler. | İşlenmemiş planlı günü bulunan ay kilitlenemez. |
| alan | Kilidin geri açılamayacağını biliyorum. | Kilidin geri açılamayacağını onaylıyorum. |
| açıklama | Kilitlenen ay geri açılamaz; sonradan gelen düzeltme sonraki aya fark satırı olarak yazılır. | Kilitlenen ay geri açılamaz; sonraki düzeltmeler izleyen aya fark satırı olarak aktarılır. |
| alan | Çalışan ara | — |
| ipucu | Ad, sicil ya da bölüm | Ad, sicil veya departman |
| açıklama | çalışan gösteriliyor. Excel her zaman tüm çalışanları içerir. | çalışan gösteriliyor. Excel dosyası tüm çalışanları içerir. |
| açıklama | Aramaya uyan çalışan yok. | Seçilen filtrelere uygun kayıt bulunmuyor. |
| açıklama | Bu ay bordroya girecek çalışan yok. | Kayıt bulunmuyor. |
| sütun | Çalışılan gün | — |
| sütun | Çalışma | — |
| sütun | Fazla mesai | — |
| sütun | Geç kalma | — |
| sütun | Erken çıkış | — |
| sütun | Devamsız | — |
| sütun | İzinli | — |
| sütun | Raporlu | — |
| sütun | Tatil | — |
| sütun | Kesinleşmemiş | — |
| açıklama | Bu ayda önceki aylara ait | — |
| açıklama | fark satırı var; Excel dosyasında ayrı sayfada yer alır. | fark satırı bulunuyor. Fark satırları Excel dosyasında ayrı sayfada yer alır. |

### Sorular
Rol: İK, Amir, Yönetici

| Tür | Şu anki metin | Önerilen metin |
|---|---|---|
| metin | Soru okunamadı. Lütfen tekrar deneyin. | — |
| metin | Soru bulunamadı ya da görme yetkiniz yok. | Soru bulunamadı veya görüntüleme yetkisi yok. |
| mesaj | Soru seçilmedi. | Soru seçilmelidir. |
| mesaj | Bir cevap seçin. | Cevap seçilmelidir. |
| mesaj | Cevap kaydedildi. Karar İK'ya geçti. | Cevap kaydedildi ve İK kararına gönderildi. |
| mesaj | Cevap kaydedildi; gün kaydı düzeltildi ve hesaplandı. | Cevap kaydedildi, gün kaydı güncellendi. |
| mesaj | Bir karar seçin. | Karar seçilmelidir. |
| mesaj | Gerekçeyi yazın. | Gerekçe girilmelidir. |
| mesaj | Gün devamsız olarak işaretlendi. | Gün "Devamsız" olarak kaydedildi. |
| mesaj | Saat yazıldı, gün hesaplandı; soru kapandı. | Karar kaydedildi, gün kaydı güncellendi. |
| alan | Cevap | — |
| alan | Giriş | — |
| metin | (zorunlu) | — |
| metin | (kayıtlı | — |
| alan | Çıkış | — |
| açıklama | Giriş ve çıkış saatini birlikte yazın. | Giriş ve çıkış saati girilmelidir. |
| açıklama | Giriş saatini yazın; çıkış boş bırakılırsa değişmez. | Giriş saati girilmelidir. Boş bırakılan çıkış saati değişmez. |
| açıklama | Çıkış saatini yazın; giriş boş bırakılırsa değişmez. | Çıkış saati girilmelidir. Boş bırakılan giriş saati değişmez. |
| açıklama | Yalnızca düzeltilecek saati girin; boş bırakılan değişmez. | Düzeltilecek saat girilmelidir. Boş bırakılan saat değişmez. |
| açıklama | Gece vardiyasında çıkış ertesi gündür. | Gece vardiyasında çıkış ertesi güne aittir. |
| açıklama | Gün kaydı değişmez; karar İK'ya geçer. Devamsızlık kararını yalnızca İK verir. | Cevap İK kararına gönderilir. Devamsızlık kararı yalnızca İK tarafından verilir. |
| alan | Açıklama (isteğe bağlı) | — |
| ipucu | ör. Servis geç geldi | — |
| alan | Karar | — |
| alan | Çalışmış: saati yaz | Çalıştı (saat girilir) |
| alan | Devamsız say | Devamsız |
| açıklama | Gün "devamsız" olur ve düzeltme çalışan aleyhine işaretlenir. Bu karar geri alınmaz; gerekirse sonradan itirazla düzeltilir. | Gün "Devamsız" olarak ve çalışan aleyhine kaydedilir. Karar geri alınamaz; çalışan itiraz edebilir. |
| alan | Gerekçe | — |
| ipucu | ör. Çalışanla görüşüldü, mazeret belgesi yok | ör. Mazeret belgesi sunulmadı |
| başlık | Sorular | — |
| metin | Cevap bekleyenler | — |
| metin | İK kararı bekleyenler | — |
| metin | Cevaplanan ve kapananlar | — |
| başlık | Sorularım | — |
| başlık | Amir soruları | — |
| açıklama | Gece işi kanıt (kapı, yemekhane, servis kaydı) bulamadığı kayıtları sabah amire sorar. Cevapsız soru son günden sonra üst amire ve İK'ya gider. "Gelmedi" cevabında kararı İK verir. | Otomatik düzeltilemeyen kayıtlar amire sorulur. Süresinde cevaplanmayan sorular üst amire, ardından İK'ya iletilir. Devamsızlık kararı İK tarafından verilir. |
| alan | Durum | — |
| alan | Gün, başlangıç | — |
| alan | Bitiş | — |
| alan | Çalışan ara | — |
| ipucu | Ad, soyad ya da sicil | Ad, soyad veya sicil |
| açıklama | soru | — |
| açıklama | Süzgeçlere uyan soru yok. Süzgeçleri temizleyip yeniden deneyin. | Seçilen filtrelere uygun kayıt bulunmuyor. |
| açıklama | Cevap bekleyen soru yok. Sorular gece işi çalıştığında oluşur. | Kayıt bulunmuyor. |
| açıklama | Henüz soru yok. Sorular gece işi çalıştığında oluşur. | Kayıt bulunmuyor. |
| sütun | Gün | — |
| sütun | Çalışan | — |
| sütun | Soru | — |
| sütun | Kanıttaki saat | Kanıt saati |
| sütun | Son gün | Son cevap tarihi |
| sütun | Atanan | — |
| metin | Görüntülenemiyor | — |
| metin | Cevap: | — |
| metin | İK kararı: | — |
| metin | · Gerekçe: | — |
| metin | Süresi geçti | Süresi doldu |
| metin | Eskale: | İletilen: |
| düğme | Cevapla | — |
| açıklama | Kanıttaki saat: {saat(soru.onerilen_zaman)}. | — |
| düğme | Cevabı kaydet | — |
| düğme | Karar ver | — |
| açıklama | Amirin cevabı: | — |
| açıklama | Amir ve üst amir{soru.eskale ? ` (${soru.eskale} süresinde cevaplamadı; soru İK'ya gitti. | Amir ve üst amir süresinde cevaplamadığı için soru İK'ya iletildi. |
| açıklama | Amir süresinde cevaplamadı; üst amiri olmadığı için soru İK'ya eskale edildi. | Soru süresinde cevaplanmadığı için İK'ya iletildi. |
| açıklama | Cevaplayacak amir olmadığı için soru doğrudan İK'ya atandı. | Tanımlı amir bulunmadığı için soru İK'ya atandı. |
| düğme | Kararı kaydet | — |
| metin | Bu soru için giriş ve çıkış saatini yazın. | Giriş ve çıkış saati girilmelidir. |
| metin | Bu soru için giriş saatini yazın. | Giriş saati girilmelidir. |
| metin | Bu soru için çıkış saatini yazın. | Çıkış saati girilmelidir. |
| metin | Giriş ya da çıkış saatini yazın. | Giriş veya çıkış saati girilmelidir. |

### Uyarılar
Rol: İK, Yönetici, İSG

| Tür | Şu anki metin | Önerilen metin |
|---|---|---|
| mesaj | Uyarı seçilmedi. | Uyarı seçilmelidir. |
| mesaj | Uyarı görüldü olarak işaretlendi. | — |
| mesaj | Bir seferde en fazla {TOPLU_SINIR} uyarı seçilebilir. | — |
| mesaj | Uyarılar işaretlenemedi. | — |
| mesaj | {basarili} uyarı görüldü yapıldı; {idler.length - basarili} uyarı yapılamadı: {ilkHata} | {n} uyarı görüldü olarak işaretlendi; {m} uyarı işaretlenemedi: {hata} |
| mesaj | {basarili} uyarı görüldü olarak işaretlendi. | — |
| başlık | Uyarılar | — |
| metin | Diğer | — |
| metin | Okuyucu {u.okuyucu.kod} | — |
| alan | Kayıt | — |
| alan | Seç: {turAdi}{kisiAdi ? `, ${kisiAdi}` : ""} | — |
| metin | Okuyucu | — |
| metin | Görüldü | — |
| metin | Arıza kayıtlarını aç | — |
| metin | Çalışan kaydını aç | — |
| düğme | Görüldü yap | Görüldü olarak işaretle |
| başlık | Karar gerekli | İK incelemesi bekleyenler |
| açıklama | Okuyucu arızası ve geçici kart çakışması şüpheleri. İK inceler; şüphe tek başına ceza değildir. | Okuyucu arızası ve geçici kart çakışması kayıtları. |
| başlık | Bilgi | Bilgilendirme |
| açıklama | Gece işinin ve veritabanı kurallarının ürettiği uyarılar. Uyarı ceza değildir; çalışan aleyhine karar İK'dadır. | Sistem tarafından oluşturulan uyarılar. Çalışan aleyhine kararlar yalnızca İK tarafından verilir. |
| alan | Uyarı listesi | — |
| metin | Yeni | — |
| metin | Görülenler | — |
| alan | Tür | — |
| seçenek | Tüm türler | — |
| alan | Kayıt tarihi, başlangıç | — |
| alan | Bitiş | — |
| alan | Çalışan ara | — |
| ipucu | Ad, soyad ya da sicil | Ad, soyad veya sicil |
| açıklama | uyarı · | — |
| açıklama | karar gerekli · | İK incelemesi bekliyor · |
| açıklama | bilgi | — |
| metin | Türlere göre dağılım ▾ | Türlere göre dağılım |
| açıklama | Süzgeçlere uyan uyarı yok. Süzgeçleri temizleyip yeniden deneyin. | Seçilen filtrelere uygun kayıt bulunmuyor. |
| açıklama | Henüz görüldü olarak işaretlenmiş uyarı yok. | Kayıt bulunmuyor. |
| açıklama | Görülmemiş uyarı yok. Uyarılar gece işi çalıştığında oluşur. | Kayıt bulunmuyor. |
| düğme | Seçilenleri görüldü yap | Seçilenleri görüldü olarak işaretle |

### Vardiya planı
Rol: İK, Amir, Yönetici

| Tür | Şu anki metin | Önerilen metin |
|---|---|---|
| mesaj | Günü seçin. | Gün seçilmelidir. |
| mesaj | Vardiyayı seçin. | Vardiya seçilmelidir. |
| mesaj | {bulunan.calisan.adSoyad} için geçmiş güne plan girildi; İK onayı bekliyor. Onaylanana kadar gün eski haliyle kalır. | {ad} için geriye dönük plan kaydedildi ve İK onayına gönderildi. |
| mesaj | {bulunan.calisan.adSoyad} için vardiya planı kaydedildi. | — |
| mesaj | Plan ya da karar seçilmedi. | Plan ve karar seçilmelidir. |
| mesaj | Geriye dönük plan onaylandı; gün yeni plana göre hemen hesaplandı. | Geriye dönük plan onaylandı ve gün kaydı güncellendi. |
| mesaj | Geriye dönük plan reddedildi; gün değişmedi. Doğru plan gerekiyorsa yeniden girilmeli. | Geriye dönük plan reddedildi. Gün kaydı değişmedi. |
| başlık | Vardiya planı | — |
| metin | Yıllık izin | — |
| metin | Rapor | — |
| metin | Mazeret | — |
| metin | Ücretsiz izin | — |
| metin | İzinli | — |
| açıklama | Sorumlu olduğunuz bölümlerin haftalık planı. | Sorumlu olunan departmanların haftalık vardiya planı. |
| açıklama | Çalışanların haftalık vardiya planı. | — |
| metin | Hafta | — |
| metin | ← Önceki hafta | — |
| metin | Bu hafta | — |
| metin | Sonraki hafta → | — |
| alan | Bölüm | Departman |
| düğme | Göster | — |
| düğme | Vardiya gir | Vardiya ekle |
| başlık | Vardiya planı gir | Vardiya planı ekle |
| açıklama | Aynı güne girilen yeni plan eskisinin yerine geçer. Geçmiş güne giriş İK onayına düşer; kilitli aya giriş yapılamaz. | Aynı gün için girilen yeni plan öncekinin yerine geçer. Geçmiş günlere ait planlar İK onayına gönderilir. Kilitli aylar için plan girilemez. |
| düğme | Kaydet | — |
| alan | Çalışanın sicil numarası | — |
| ipucu | Yazmaya başlayınca liste açılır. | Sicil numarası veya ad ile arama yapılabilir. |
| alan | Gün | — |
| alan | Vardiya | — |
| seçenek | Seçin | — |
| alan | Açıklama (geçmiş gün için gerekçe) | — |
| ipucu | ör. Vardiya değişimi, A grubuna geçti | ör. Grup değişikliği |
| başlık | Onay bekleyen geriye dönük değişiklikler | — |
| açıklama | Geçmiş güne girilen plan, onaylanana kadar puantajı değiştirmez. Planı giren kişi onaylayamaz. | Geçmiş günlere ait planlar onaylanana kadar puantaja yansımaz. Planı ekleyen kullanıcı onay veremez. |
| alan | Kayıt | — |
| düğme | Onayla | — |
| düğme | Reddet | — |
| başlık | Planı reddet | — |
| açıklama | Plan reddedilecek; bu işlem geri alınamaz. | Plan reddedilecektir. Bu işlem geri alınamaz. |
| metin | Giren: | Ekleyen: |
| açıklama | çalışan · | — |
| açıklama | izinli gün | — |
| açıklama | · {bekleyenSayisi} geriye dönük değişiklik İK onayı bekliyor | — |
| metin | Bu süzgeçle görebileceğiniz çalışan yok. | Seçilen filtrelere uygun kayıt bulunmuyor. |
| sütun | Çalışan | — |
| metin | {tatil.ad}{tatil.yarim_gun ? " (yarım gün} | — |
| metin | (yarım gün) | — |
| metin | Tatil | — |
| metin | Ayrıldı · | — |
| metin | İşe giriş · | — |
| başlık | Açıklama | — |
| metin | Geriye dönük değişiklik, İK onayı bekliyor | — |
| metin | Planlı fazla mesai | — |
| metin | Planlı vardiya: {v.ad} | — |
| metin | Geriye dönük değişiklik: İK onayı bekliyor | — |
| metin | İK değişikliği reddetti | Değişiklik İK tarafından reddedildi |
| metin | İK onayı bekliyor | — |

### Veri aktarımı
Rol: İK, Yönetici

| Tür | Şu anki metin | Önerilen metin |
|---|---|---|
| mesaj | Okuyucuyu seçin. | Okuyucu seçilmelidir. |
| mesaj | Arızanın başlangıcını girin. | Arıza başlangıcı girilmelidir. |
| mesaj | Bitiş başlangıçtan sonra olmalı. | Bitiş, başlangıçtan sonra olmalıdır. |
| mesaj | Arıza kaydedildi. Etkisi bir sonraki gece işinde görülür. | Arıza kaydedildi. Kayıt, bir sonraki gece işleminde dikkate alınır. |
| mesaj | Arıza ya da karar seçilmedi. | Arıza ve karar seçilmelidir. |
| mesaj | Arıza onaylandı. | — |
| mesaj | Arıza şüphesi reddedildi. | — |
| metin | gün kaydı | — |
| metin | kanıtla düzeltme | otomatik düzeltme |
| metin | amire soru | soru |
| metin | üst amire giden | üst amire iletilen |
| metin | uyarı | — |
| mesaj | Başlangıç gününü seçin. | Başlangıç günü seçilmelidir. |
| mesaj | Bitiş günü başlangıçtan önce olamaz. | Bitiş günü, başlangıç gününden önce olamaz. |
| mesaj | {gunler.length} günün {hatali.length} tanesi hatalı: {hatali[0].gun} · {hatali[0].hata_mesaji ?? "bili} | {n} günden {m} gün işlenemedi: {gün}. Sistem yöneticisi ile iletişime geçilmelidir. |
| mesaj | bilinmeyen hata | — |
| mesaj | {gunler.length} gün işlendi{ozet ? `: ${ozet}` : ""}. | — |
| mesaj | Dosya 20 MB'tan büyük. Günlük dosyalar bundan küçük olmalı. | Dosya boyutu 20 MB'ı aşmamalıdır. |
| mesaj | Dosya okunamadı. Dosya başka bir programda açıksa kapatın ve yeniden seçin. | Dosya okunamadı. Dosya kapatılıp yeniden seçilmelidir. |
| alan | Dosya türü | — |
| alan | CSV dosyası | — |
| açıklama | Dosya denetleniyor… | — |
| başlık | Dosya aktarıldı | Dosya yüklendi |
| metin | okutma kaydedildi | — |
| metin | , daha önce başka dosyayla gelmiş {zaten_vardi.toLocaleString("tr} okutma atlandı | , daha önce yüklenmiş {n} okutma atlandı |
| metin | . Kayıtlar gece işinde işlenecek. | . Kayıtlar gece işleminde işlenir. |
| başlık | Bu dosyanın ayı kilitli | Dosya kilitli bir aya ait |
| metin | Ham kayıtlar alındı. Bu kayıtlardan çıkan düzeltmeler kilitli aya yazılmaz, sonraki aya fark satırı olarak geçer. | Okutmalar kaydedildi. Bu kayıtlardan doğan düzeltmeler izleyen aya fark satırı olarak aktarılır. |
| başlık | Dosyadaki satır | — |
| başlık | Yüklenecek satır | — |
| başlık | Hata | — |
| açıklama | Düzeltilmeden yüklenemez | Yükleme için hatalar giderilmelidir |
| açıklama | Hata yok | — |
| başlık | Verinin günü | — |
| açıklama | Dosya adından ya da satırlardan | Dosya adı veya satırlardan belirlenir |
| başlık | Bu dosya daha önce yüklenmiş | Dosya daha önce yüklenmiş |
| metin | Aynı içerikteki | — |
| metin | dosyası | — |
| metin | tarihinde aktarılmış. Aynı dosya ikinci kez yüklenemez. | — |
| başlık | Uyarılar | — |
| başlık | Hatalar | — |
| sütun | Satır | — |
| sütun | Sorun | Açıklama |
| açıklama | İlk 200 hata gösteriliyor. | — |
| başlık | Önizleme (ilk | — |
| başlık | satır) | — |
| sütun | Okuyucu | — |
| sütun | Kart | — |
| sütun | Zaman | — |
| sütun | Yön | — |
| metin | Giriş | — |
| metin | Çıkış | — |
| durum | Yok | — |
| başlık | Dosya aktarılamadı | Dosya yüklenemedi |
| metin | Hiçbir satır kaydedilmedi. | — |
| düğme | Yükleniyor… | — |
| düğme | {sonuc.satirlar.length.toLocale} satırı yükle | — |
| düğme | Yükle | — |
| açıklama | Dosya yüklemeye hazır. Kayıtlar tek seferde yazılır; bir hata olursa hiçbiri yazılmaz. Yüklenen kayıt değiştirilemez ve silinemez. | Dosya yüklemeye hazır. Yüklenen kayıtlar değiştirilemez ve silinemez. |
| açıklama | Bu dosya daha önce aktarıldığı için yüklenemez. | Dosya daha önce yüklenmiştir. |
| açıklama | Hatalar giderilmeden dosya yüklenemez. | Yükleme için hatalar giderilmelidir. |
| başlık | Veri aktarımı | — |
| metin | Şüphe · İK kararı bekliyor | — |
| metin | Arıza | — |
| metin | Reddedildi | — |
| metin | Çalışıyor | — |
| metin | Başarılı | — |
| metin | Hatalı | — |
| metin | düzeltme | — |
| metin | Değişiklik yok | — |
| açıklama | PDKS, kapı, yemekhane ve servis sistemlerinin günlük dosyaları buradan alınır. Ham kayıtlar bir kez yazılır; değiştirilemez ve silinemez. | PDKS, kapı, yemekhane ve servis sistemlerinin günlük dosyaları. Yüklenen kayıtlar değiştirilemez ve silinemez. |
| alan | Veri aktarımı bölümleri | — |
| metin | Aktarımlar | — |
| metin | eksik dosya | — |
| metin | Okuyucu arızaları | — |
| metin | karar bekliyor | — |
| metin | Okuyucular | — |
| başlık | Dosya yükle | — |
| açıklama | Biçim: başlık satırı | Dosya biçimi: |
| açıklama | , zaman Türkiye saatiyle ( | , zaman ( |
| açıklama | ). Dosya adına günü yazın: | ). Dosya adı: |
| metin | Örnek dosyayı indir | — |
| başlık | Gece işi | Gece işlemi |
| açıklama | Her gece kendiliğinden çalışır: okutmaları işaretler, günlük kayıtları kurar, kanıt varsa düzeltir, yoksa amire sorar, uyarıları yazar. Demoda aşağıdaki düğmeyle de çalıştırılır. | Gece işlemi her gece otomatik olarak çalışır; gün kayıtlarını, düzeltmeleri, soruları ve uyarıları oluşturur. Gerektiğinde bu ekrandan da başlatılabilir. |
| düğme | Gece işini çalıştır | Gece işlemini başlat |
| açıklama | Seçilen günler sırayla işlenir (en fazla 62 gün). Tekrar çalıştırmak güvenlidir: var olan kayıtlar bozulmaz, yalnızca eksikler eklenir. Verisi yüklenmemiş gün işlenmez. | Seçilen günler sırayla işlenir (en fazla 62 gün). Mevcut kayıtlar korunur, eksik kayıtlar eklenir. Verisi yüklenmemiş günler işlenmez. |
| düğme | Çalıştır | Başlat |
| alan | Başlangıç | — |
| alan | Bitiş | — |
| açıklama | Gece işi henüz hiç çalışmadı. | Kayıt bulunmuyor. |
| sütun | İşlenen gün | — |
| sütun | Çalışma zamanı | — |
| sütun | Durum | — |
| sütun | Sonuç | — |
| başlık | Gelmeyen dosyalar · | Eksik dosyalar · |
| açıklama | {tarih(ayBasi)} – {tarih(sonGun)} arasında her gün her sistemden bir dosya beklenir. | {tarih} – {tarih} dönemi. |
| açıklama | Bu ay henüz dosya gelmedi. | Kayıt bulunmuyor. |
| başlık | Eksik dosya yok | Eksik dosya bulunmuyor |
| açıklama | Bu ay beklenen bütün dosyalar geldi. | Beklenen tüm dosyalar yüklenmiştir. |
| başlık | Son aktarımlar | — |
| açıklama | Henüz dosya aktarılmadı. | Kayıt bulunmuyor. |
| sütun | Tür | — |
| sütun | Dosya | — |
| sütun | Yükleyen | — |
| sütun | Aktarım zamanı | — |
| metin | Bilinmiyor | — |
| açıklama | Arıza süresince okutması eksik çalışan devamsız sayılmaz: gece işi kanıt arar, yoksa amire sorar. Hiç okutma gelmeyen okuyucu için gece işi “arıza şüphesi” açar; kararı İK verir. | Arıza süresindeki eksik okutmalar devamsızlık olarak değerlendirilmez. Okutma alınmayan okuyucular için arıza şüphesi oluşturulur; karar İK tarafından verilir. |
| düğme | Arıza gir | Arıza ekle |
| başlık | Okuyucu arızası | — |
| açıklama | Bitişi bilinmiyorsa boş bırakın; arıza sürüyor sayılır. | Bitiş zamanı bilinmiyorsa boş bırakılır ve arıza devam ediyor olarak kaydedilir. |
| düğme | Kaydet | — |
| seçenek | Seçin | — |
| alan | Bitiş (isteğe bağlı) | — |
| alan | Açıklama (isteğe bağlı) | — |
| ipucu | ör. Turnike kart okuyucusu yanıt vermiyor | — |
| başlık | Karar gerekli | İK incelemesi bekleyenler |
| başlık | Okuyucu arıza şüphesi | — |
| metin | · sürüyor | · devam ediyor |
| metin | İK girdi | İK kaydı |
| metin | Gece işi buldu | Sistem kaydı |
| düğme | Arıza değil | Reddet |
| başlık | Arıza şüphesini reddet | — |
| açıklama | Okuyucu arızası reddedilecek; eksik okutmalar normal soru akışına girecek. | Arıza şüphesi reddedilecektir. Eksik okutmalar için soru oluşturulur. |
| metin | Açıklama yok. | Açıklama bulunmuyor. |
| başlık | Kararı verilmiş arızalar | Sonuçlanan arızalar |
| açıklama | Kararı verilmiş arıza kaydı yok. | Kayıt bulunmuyor. |
| açıklama | Kayıtlı arıza yok. | Kayıt bulunmuyor. |
| sütun | Açıklama | — |
| metin | Sürüyor | Devam ediyor |
| açıklama | okuyucu · | — |
| açıklama | pasif | — |
| sütun | Kod | — |
| sütun | Ad | — |
| sütun | Sistem | — |
| metin | Aktif | — |
| metin | Pasif | — |

### Ortak
Rol: Tümü

| Tür | Şu anki metin | Önerilen metin |
|---|---|---|
| metin | Sayfa yüklenemedi. | — |
| metin | Bir sorun oluştu | Hata |
| başlık | Sayfa açılamadı | — |
| açıklama | Bağlantı geçici olarak kopmuş olabilir. Tekrar deneyin; sorun sürerse sistem yöneticisine haber verin. | Sayfa yüklenemedi. Sorun devam ederse sistem yöneticisi ile iletişime geçilmelidir. |
| düğme | Tekrar dene | — |
| metin | Ana sayfaya dön | — |
| metin | Atlas Trafo PDKS | — |
| metin | PDKS kayıt düzeltme sistemi | — |
| başlık | Sayfa bulunamadı | — |
| açıklama | Aradığınız sayfa ya da kayıt yok. Adres yanlış yazılmış ya da bu kayda erişim yetkiniz olmayabilir. | Sayfa veya kayıt bulunamadı ya da erişim yetkisi yok. |
| metin | Gösterilecek kayıt yok | Kayıt bulunmuyor |
| düğme | Uygula | — |
| metin | Süzgeçleri temizle | Filtreleri temizle |
| metin | İşlemler | — |
| metin | Yeni: | — |
| alan | Tümünü seç | — |
| metin | seçili | — |
| düğme | İşleniyor… | — |
| açıklama | Toplam | — |
| metin | Vazgeç | — |
| düğme | Kaydediliyor… | — |
| metin | Onayla | — |
| metin | Reddet | — |
| alan | Karar | — |
| alan | Gerekçe | — |
| alan | (isteğe bağlı) | — |
| metin | Konum | — |
| metin | Atlas Trafo | — |
| metin | Ayrıntı | — |
| metin | Ana sayfa | — |
| metin | Koyu temaya geç | — |
| metin | Açık temaya geç | — |
| metin | Koyu tema | — |
| metin | Açık tema | — |
| metin | Gündüz | — |
| metin | {gun} gün {sa} sa | — |
| metin | Pzt | — |
| metin | Sal | — |
| metin | Çar | — |
| metin | Per | — |
| metin | Cum | — |
| metin | Cmt | — |
| metin | Paz | — |
| metin | Amir | — |
| metin | İnsan Kaynakları | — |
| metin | Güvenlik | — |
| metin | Yönetici | — |
| metin | İSG Uzmanı | — |
| metin | Sistem Yöneticisi | — |
| metin | Veritabanına ulaşılamadı. Bağlantıyı kontrol edip tekrar deneyin. | Sisteme ulaşılamadı. Lütfen tekrar deneyin. |
| metin | Bu işlem için yetkiniz yok. | Bu işlem için yetki bulunmuyor. |
| metin | Bu kayıt zaten var. | Bu kayıt daha önce eklenmiştir. |
| metin | İlgili kayıt bulunamadı. | — |
| metin | Girilen değer geçersiz. | Geçerli bir değer girilmelidir. |
| metin | Veritabanı fonksiyonu bulunamadı. Migration canlıya uygulanmamış olabilir. | İşlem şu anda yapılamıyor. Sistem yöneticisi ile iletişime geçilmelidir. |
| metin | İşlem yapılamadı. Lütfen tekrar deneyin. | — |
| mesaj | Çalışanın sicil numarasını yazın. | Çalışanın sicil numarası girilmelidir. |
| mesaj | Çalışan aranamadı. Lütfen tekrar deneyin. | — |
| mesaj | {sicil} sicil numaralı çalışan bulunamadı ya da görme yetkiniz yok. | {sicil} sicil numaralı çalışan bulunamadı veya görüntüleme yetkisi yok. |
| mesaj | {data.ad} {data.soyad} aktif çalışan değil. | {ad} {soyad} aktif bir çalışan değildir. |

### Giriş
Rol: Tümü

| Tür | Şu anki metin | Önerilen metin |
|---|---|---|
| metin | E-posta ve şifre girin. | E-posta ve şifre girilmelidir. |
| metin | E-posta ya da şifre hatalı. | E-posta veya şifre hatalı. |
| metin | E-posta | — |
| metin | Şifre | — |
| düğme | Giriş yapılıyor… | — |
| düğme | Giriş yap | — |
| başlık | Giriş | — |
| metin | Atlas Trafo | — |
| başlık | PDKS Kayıt Düzeltme | — |
| açıklama | Kurum e-postanız ve şifrenizle giriş yapın. | Kurumsal e-posta adresi ve şifre ile giriş yapılır. |
| başlık | Supabase ayarları eksik | Sistem yapılandırması eksik |
| metin | dosyasını | (kaldırılır; "Sistem yöneticisi ile iletişime geçilmelidir.") |
| metin | olarak kopyalayın, değerleri doldurun ve geliştirme sunucusunu yeniden başlatın. | (kaldırılır) |

### Menü
Rol: Tümü

| Tür | Şu anki metin | Önerilen metin |
|---|---|---|
| metin | Ana menü | — |
| metin | Menüyü kapat | — |
| metin | Menüyü aç | — |
| metin | Genel | — |
| metin | Günlük işler | — |
| metin | Planlama | — |
| metin | Kayıtlar | — |
| metin | Yönetim | — |
| başlık | Ana sayfa | — |
| başlık | Departmanlar | — |
| başlık | Uyarılar | — |
| başlık | Sorular | — |
| başlık | Sorularım | — |
| başlık | İtirazlar | — |
| başlık | Geçici kartlar | — |
| başlık | Vardiya planı | — |
| başlık | Fazla mesai | — |
| başlık | İzinler | — |
| başlık | Çalışanlar | — |
| başlık | Puantaj | — |
| başlık | İSG | — |
| başlık | Veri aktarımı | — |
| başlık | Kullanıcılar | — |
| başlık | Ayarlar | — |

### Veri aktarımı
Rol: İK

| Tür | Şu anki metin | Önerilen metin |
|---|---|---|
| metin | Kapı turnikesi | — |
| metin | Yemekhane | — |
| metin | Servis | — |
| metin | Başlık satırında şu sütunlar yok: {eksik.join(", ")}. Beklenen: okuyucu;kart_no;zaman;yon | — |
| metin | "{kod}" adında bir okuyucu yok. | "{kod}" okuyucusu tanımlı değil. |
| metin | Okuyucu kodu boş. | — |
| metin | {kod} bir {KAYNAK_ADI[okuyucu.sistem]} okuyucusu; seçilen dosya türü {KAYNAK_ADI[kaynak]}. | — |
| metin | Kart numarası geçersiz: "{kartNo}" | — |
| metin | Kart numarası boş. | — |
| metin | Zaman okunamadı: "{ham.zaman ?? ""}". Örnek: 2026-11-26 08:01 | — |
| metin | Yön "giris", "cikis" ya da boş olmalı: "{ham.yon}" | Yön "giris", "cikis" veya boş olmalıdır: "{yon}" |
| mesaj | {tekrarSayisi} satır dosyada birden fazla geçiyor; bir kez yüklenecek. | {n} yinelenen satır bir kez yüklenir. |
| metin | Dosyada veri satırı yok. | Dosyada veri satırı bulunmuyor. |
| mesaj | {uzak} satır dosyanın günü ({veriTarihi}) ve ertesi gün dışında. | {n} satır, dosya günü ({tarih}) ve izleyen günün dışındadır. |
| metin | Dosyanın hangi güne ait olduğu bulunamadı. Dosya adına tarihi ekleyin: pdks_20261126.csv | Dosya tarihi belirlenemedi. Dosya adı tarih içermelidir (ör. pdks_20261126.csv). |
| mesaj | Pasif okuyucudan kayıt var: {[...pasif].join(", ")} | Pasif okuyuculara ait kayıtlar: {liste} |

### Çalışan dökümü
Rol: İK, Amir, Yönetici

| Tür | Şu anki metin | Önerilen metin |
|---|---|---|
| metin | Paz | — |
| metin | Pzt | — |
| metin | Sal | — |
| metin | Çar | — |
| metin | Per | — |
| metin | Cum | — |
| metin | Cmt | — |
| metin | Yıllık izin | — |
| metin | Rapor | — |
| metin | Mazeret izni | — |
| metin | Ücretsiz izin | — |
| metin | İzinli | — |
| metin | Tamam | — |
| metin | Eksik kayıt | — |
| metin | Amire soruldu | Amir cevabı bekleniyor |
| metin | Raporlu | — |
| metin | Tatil | — |
| metin | Plan yok | Vardiya planı yok |
| metin | Devamsızlık şüphesi | — |
| metin | Devamsız | — |
| metin | Kanıt | — |
| metin | Amir | — |
| metin | İK | — |
| metin | Giriş | — |
| metin | Çıkış | — |
| metin | Vardiya | — |
| metin | Durum | — |
| metin | Gece işi | Gece işlemi |
| metin | Geriye dönük değişiklik, İK onayı bekliyor{p.aciklama ? `: ${p.aciklama}`} | — |
| metin | Geriye dönük değişiklik reddedildi | — |
| metin | (onaylı) | — |
| metin | Sistem | — |

### Ortak adlar (etiketler)
Rol: Tümü

| Tür | Şu anki metin | Önerilen metin |
|---|---|---|
| metin | Giriş kaydı yok | — |
| metin | Giriş vardiya başından sonra | Vardiya başlangıcından sonra giriş |
| metin | Çıkış kaydı yok | — |
| metin | Hiç kayıt yok | Okutma kaydı yok |
| metin | Okuyucu arızası, kanıt yok | Okuyucu arızası, kanıt kaydı yok |
| metin | Okutmalar başka vardiyaya uyuyor | Vardiya uyuşmazlığı |
| metin | Cevap bekliyor | — |
| metin | Üst amire gitti | Üst amire iletildi |
| metin | Cevaplandı | — |
| metin | İK kararı bekliyor | — |
| metin | Kapandı | Sonuçlandı |
| metin | Geldi, önerilen saat doğru | — |
| metin | Geldi, saat farklı | — |
| metin | Kartını unuttu | — |
| metin | Gelmedi (İK karar verir) | Gelmedi |
| metin | Bilmiyorum | — |
| metin | Devamsız | — |
| metin | Çalışmış, saat yazıldı | Çalıştı |
| metin | İptal edilmiş kart okutuldu | — |
| metin | Sık kart unutma | Sık geçici kart kullanımı |
| metin | Okuyucu arıza şüphesi | — |
| metin | Cevapsız soru üst amire gitti | Cevaplanmayan soru iletildi |
| metin | Gece işi çalışmadı | Gece işlemi çalışmadı |
| metin | Dosya gelmedi | Eksik dosya |
| metin | Geriye dönük vardiya değişikliği | — |
| metin | Yazılı onay olmadan fazla çalışma | Yazılı onaysız fazla mesai |
| metin | Plansız fazla çalışma | Plansız fazla mesai |
| metin | Günlük 11 saat aşıldı | Günlük çalışma sınırı aşıldı |
| metin | Yıllık fazla mesai sınırına yaklaştı | — |
| metin | Fazla mesai onayı geri alındı | — |
| metin | Geçici kart ve asıl kart birlikte okutuldu | Geçici ve asıl kartın birlikte kullanımı |
| metin | Zimmetsiz geçici kart okutuldu | — |
| metin | Geçici kart iade edilmedi | — |
| metin | Kart paylaşımı şüphesi | — |
| metin | Gece çalışma sınırı aşıldı | — |
| metin | Yıllık fazla mesai sınırı aşıldı | — |
| metin | İSG belgesi kaydı yok | İSG belgesi eksik |
| metin | İSG belgesinin süresi dolmuş | — |
| metin | İSG belgesinin süresi doluyor | — |
| metin | Yetkisiz bölgeye giriş | — |
| metin | Puantajı etkileyen ayar değişti | Puantaj ayarı değişikliği |
| metin | Yükleyenin kendi okutmasını içeren dosya | Yükleyenin kendi okutması |
| metin | Soru ve vardiya | — |
| metin | Kart | — |
| metin | Çalışma süresi | — |
| metin | Sistem ve cihaz | — |
| metin | İSG | — |
| metin | Açık | — |
| metin | İnceleniyor | — |
| metin | Kabul edildi | — |
| metin | Reddedildi | — |

### Puantaj (Excel / ERP)
Rol: İK

| Tür | Şu anki metin | Önerilen metin |
|---|---|---|
| başlık | Sicil | — |
| başlık | Ad soyad | — |
| başlık | Bölüm | Departman |
| başlık | Çalışılan gün | — |
| başlık | Çalışma (dk) | — |
| başlık | Fazla mesai (dk) | — |
| başlık | FM50 (dk) | — |
| başlık | FM100 (dk) | — |
| başlık | Gece çalışma (dk) | — |
| başlık | Mola (dk) | — |
| başlık | Geç kalma (dk) | — |
| başlık | Erken çıkış (dk) | — |
| başlık | Devamsız gün | — |
| başlık | İzinli gün | — |
| başlık | Raporlu gün | — |
| başlık | Tatil gün | — |

## Veritabanının ürettiği metinler (uyarı, soru, düzeltme gerekçesi)

Yeni kayıtlarda değişir; eski kayıtlar olduğu gibi kalır (`duzeltme` zaten değiştirilemez).

| Fonksiyon | Şu anki metin | Önerilen metin |
|---|---|---|
| `ayar_guncelle` | %s ayarı %s değerinden %s değerine çekildi (%s; değiştiren: %s). Bundan sonra hesaplanan günleri etkiler; işlenmiş günler kendiliğinden yeniden hesaplanmaz. | "{ayar adı}" ayarı {eski} değerinden {yeni} değerine güncellendi ({kullanıcı}). Önceden işlenmiş günler yeniden hesaplanmaz. |
| `bolge_kontrol` | %s: %s bölgesine yetkisi olmadan okuttu (%s). Kapı kilitlenmedi. | {tarih} tarihinde {bölge} bölgesine yetkisiz giriş kaydedildi ({okuyucu}). |
| `dosya_yukle` | %s (%s) kendi kartının %s okutmasını içeren %s dosyasını yükledi (%s). | {ad} ({sicil}), kendi kartına ait {n} okutma içeren {dosya} dosyasını yükledi ({tarih}). |
| `fazla_mesai_inceleme_karar` | %s yılı onaylı fazla mesai %s dk; yıllık sınır %s dk (270 saat). | {yıl} yılı onaylı fazla mesai {sa dk} (yasal sınır 270 sa). |
| `fazla_mesai_onayi_geri_alindi` | Yazılı onay geri alındı (bildirim %s) | (değişmez) |
| `fazla_mesai_onayi_geri_alindi` | Fazla mesai onayı geri alındı; %s tarihinden itibaren geçersiz. %s plan iptal edildi.%s | Fazla mesai onayı geri alındı ve {tarih} itibarıyla geçersizdir. {n} plan iptal edildi. |
| `fazla_mesai_onayi_geri_alindi` | %s plan geçmiş bir güne ya da kilitli aya ait olduğu için iptal edilmedi; İK incelemeli. | {n} plan geçmiş güne veya kilitli aya ait olduğu için İK incelemesi bekliyor. |
| `fazla_mesai_plani_kontrol` | Yıllık onaylı fazla mesai %s / %s dakikaya ulaştı. | Yıllık onaylı fazla mesai {sa dk} düzeyine ulaştı (yasal sınır 270 sa). |
| `gece_isi_ariza_suphesi` | %s kişinin PDKS okutması yok ama kapı kaydı var; okuyucu bu aralıkta sessiz. | {n} çalışanın kapı kaydı bulunmasına rağmen PDKS okutması yok; okuyucudan bu aralıkta okutma alınmadı. |
| `gece_isi_ariza_suphesi` | %s okuyucusu %s civarında okutma almamış olabilir; İK onayı bekliyor. | {okuyucu} okuyucusundan {zaman} itibarıyla okutma alınmadı. İK incelemesi bekleniyor. |
| `gece_isi_eskale` | %s tarihli soruyu üst amir de süresinde cevaplamadı; İK kararı bekliyor. | {tarih} tarihli soru üst amir tarafından süresinde cevaplanmadı ve İK'ya iletildi. |
| `gece_isi_eskale` | %s tarihli soru süresinde cevaplanmadı; üst amire / İK'ya gitti. | {tarih} tarihli soru süresinde cevaplanmadı ve bir üst kademeye iletildi. |
| `gece_isi_isaretle` | İptal edilmiş kart %s, %s tarihinde okutuldu. | {kart} numaralı iptal edilmiş kart {tarih} tarihinde okutuldu. |
| `gece_isi_kanitla_duzelt` | Esnek mesai: %s kaydı %s + yürüme payı; giriş %s olarak yazıldı | {Kapı/Servis} kaydı {saat}; yürüme süresi eklenerek giriş {saat} olarak kaydedildi. |
| `gece_isi_kanitla_duzelt` | %s kaydı %s, vardiya başından önce; giriş vardiya başı olarak yazıldı | {Kapı/Servis} kaydı {saat}; giriş vardiya başlangıcı olarak kaydedildi. |
| `gece_isi_kanitla_duzelt` | %s kaydı %s; çıkış kanıttaki saat olarak yazıldı | {Kapı/Servis} kaydı {saat}; çıkış bu saat olarak kaydedildi. |
| `gece_isi_sorular` | %s: okutmalar planlı vardiyaya (%s) uymuyor; %s vardiyasına uyuyor (giriş %s, çıkış %s). Onaylarsanız vardiya ve saatler düzeltilir. | {tarih}: Okutmalar planlı vardiya ({v1}) yerine {v2} vardiyası ile uyumlu (giriş {s}, çıkış {s}). Onaylandığında vardiya ve saatler güncellenir. |
| `gece_isi_sorular` | %s: vardiya planı var; izin ve hiçbir okutma (PDKS, kapı, servis, yemekhane) yok. | {tarih}: Vardiya planı bulunmasına rağmen izin veya okutma kaydı yok. |
| `gece_isi_sorular` | %s: PDKS girişi yok; %s kaydı %s (vardiya başından sonra). Giriş saatini onaylayın. | {tarih}: PDKS giriş kaydı yok; {kapı/servis} kaydı {saat} (vardiya başlangıcından sonra). Giriş saati onaylanmalıdır. |
| `gece_isi_sorular` | %s: giriş okutması yok, kapı ya da servis kaydı da yok. | {tarih}: Giriş okutması ile kapı veya servis kaydı yok. |
| `gece_isi_sorular` | %s: çıkış okutması yok, kapı ya da servis kaydı da yok. | {tarih}: Çıkış okutması ile kapı veya servis kaydı yok. |
| `gece_isi_uyarilar` | %s: vardiya sonrası %s dk kaldı; yazılı fazla mesai onayı yok. Karar İK'da. | {tarih} tarihinde vardiya sonrası {sa dk} çalışıldı; yazılı fazla mesai onayı yok. |
| `gece_isi_uyarilar` | %s: vardiya sonrası %s dk kaldı; onaylı plan %s dk. Fazlası puantaja yazılmadı, karar İK'da. | {tarih} tarihinde vardiya sonrası {sa dk} çalışıldı (onaylı plan {sa dk}). Aşan süre İK kararı bekliyor. |
| `gece_isi_uyarilar` | %s: günlük çalışma %s dk; sınır %s dk (11 saat). | {tarih} tarihinde {sa dk} çalışıldı (yasal sınır 11 sa). |
| `gece_isi_uyarilar` | %s günü için %s dosyası yüklenmedi. | {tarih} tarihli {sistem} dosyası yüklenmedi. |
| `gecici_kart_kontrol` | Çalışanın geçici kartı (%s) zimmetliyken asıl kartı (%s) %s saatinde okutuldu. Kartı başkası kullanıyor olabilir; İK incelemeli. | {geçici kart} zimmetli iken asıl kart ({kart}) {zaman} tarihinde okutuldu. |
| `gecici_kart_kontrol` | Geçici kart %s, kimseye zimmetli değilken %s saatinde okutuldu. | Zimmetli olmayan {kart} geçici kartı {zaman} tarihinde okutuldu. |
| `gecici_kart_kontrol` | Geçici kart %s, %s tarihinden beri iade edilmedi. | {kart} geçici kartı {tarih} tarihinden itibaren iade edilmedi. |
| `gecici_kart_kontrol` | Çalışan %s ayında %s kez geçici kart aldı (eşik %s). Bilgi amaçlıdır. | {ay} döneminde {n} kez geçici kart kullanıldı. |
| `gun_sonrasi_kontroller` | %s: gece çalışması (20:00–06:00) %s dk; sınır %s dk (7,5 saat). | {tarih} tarihinde {sa dk} gece çalışması yapıldı (yasal sınır 7 sa 30 dk). |
| `isg_kontrol` | %s: %s kaydı yok; çalışan %s günü okuttu. Kapı kilitlenmedi. | {belge} kaydı bulunmuyor; {tarih} tarihinde okutma yapıldı. |
| `isg_kontrol` | %s: %s süresi %s tarihinde doldu; çalışan %s günü okuttu. Kapı kilitlenmedi. | {belge} geçerliliği {tarih} tarihinde sona erdi; {tarih} tarihinde okutma yapıldı. |
| `kart_paylasim_kontrol` | Kart paylaşımı şüphesi: %s (%s %s) ve %s (%s %s) kartları %s ayında %s farklı günde %s saniye içinde arka arkaya okutuldu. Ceza değildir; İK incelemeli. | {kişi 1} ve {kişi 2} kartları {ay} döneminde {n} farklı günde {s} saniye içinde art arda okutuldu. |
| `isten_cikis_gir` | İşten çıkış ( | (değişmez) |
| `soru_cevapla` | Amir cevabı: {cevap kodu} | Amir cevabı: {cevabın Türkçe adı} (bugün "geldi_saat_farkli" gibi kod yazılıyor) |
| `vardiya_plani_onayla` | Geriye dönük vardiya planı onaylandı | (değişmez) |

## Veritabanı hata mesajları (raise exception)

Yalnızca liste. Öneri yalnızca teknik ad / kod içeren ya da konuşma dilindeki mesajlar için yazıldı; "—" olanlara dokunulmayacak.

| Fonksiyon | Şu anki mesaj | Önerilen |
|---|---|---|
| `amir_sorusu_kontrol` | Bu soruyu yalnızca İK kapatabilir. | — |
| `amir_sorusu_yonlendir` | Soru amirin kendisiyle ilgili; üst amiri ve İK kullanıcısı tanımlı değil. | — |
| `ariza_karar` | Şüphe durumunda arıza bulunamadı. | — |
| `ay_kilitle` | %/% dönemi henüz bitmedi (son gün %). Ay, son günü geçtikten sonra kilitlenir. | — |
| `ay_kilitle` | %/% döneminde % gün puantaja kodsuz girecek: %. Bu günler bordroya hiçbir kodla gitmez; önce karara bağlayın (soru cevabı, İK kararı ya da kayıt düzeltme) ya da zorla kilitleyin. | {dönem} döneminde {n} gün için puantaj kodu oluşmadı: {liste}. Bu günler kilitlemeden önce sonuçlandırılmalıdır. |
| `ay_kilitle` | %/% döneminde gece işinden geçmemiş % planlı gün var (% çalışan; ilk gün %)%. Önce o günlerin dosyalarını yükleyip gece işini çalıştırın%. Bu kontrol zorla geçilemez. | {dönem} döneminde işlenmemiş {n} planlı gün bulunuyor ({n} çalışan, ilk gün {tarih}). Kilitlemeden önce bu günler işlenmelidir. |
| `ay_kilitle` | %/% döneminde İK kararı bekleyen % onaysız fazla mesai var. | — |
| `ay_kilitle` | %/% döneminde İK onayı bekleyen % geriye dönük vardiya planı var. | — |
| `ayar_guncelle` | % için değer % ile % arasında olmalı. | Değer {en az} ile {en çok} arasında olmalıdır. (teknik anahtar görünmez) |
| `ayar_guncelle` | % için tam sayı girin (ondalık ya da metin olmaz). | Tam sayı girilmelidir. |
| `ayar_guncelle` | Ayar bulunamadı: % | Ayar bulunamadı. |
| `ayar_guncelle` | Mola süreleri sıralı olmalı: kısa (%) < orta (%) < uzun (%) dakika. | Mola süreleri kısa, orta ve uzun sırasıyla artmalıdır. |
| `ayar_guncelle` | Mola sınırları sıralı olmalı: kısa sınır (%) < orta sınır (%) dakika. | Kısa mola çalışma sınırı, orta mola çalışma sınırından küçük olmalıdır. |
| `ayar_iz` | Ayar silinemez, yalnızca değeri değiştirilir. | — |
| `bolge_yetkisi_kaldir` | Bu departmanın bu bölgede yetkisi yok. | — |
| `bolge_yetkisi_ver` | Bölge bulunamadı. | — |
| `bolge_yetkisi_ver` | Departman bulunamadı. | — |
| `calisan_ekle` | Bu sicil işten ayrılmış bir çalışana ait; yeniden işe giriş desteklenmiyor. | — |
| `calisan_ekle` | Bu sicil numarası başka bir çalışanda kayıtlı: % %. | — |
| `calisan_ekle` | Departman bulunamadı. | — |
| `calisan_ekle` | Sicil numarası, ad ve soyad boş olamaz. | — |
| `calisan_ekle` | İşe giriş tarihi girilmeli. | — |
| `calisan_yetkisi` | Bu çalışan sizin departmanınızda değil. | — |
| `degistirilemez` | % tablosu değiştirilemez ve silinemez (yalnızca ekleme yapılır). | — |
| `donem_kilitle` | %/% döneminde açık soru veya itirazı olan % gün var. | — |
| `donem_kilitle` | Dönem bulunamadı: % | — |
| `donem_kontrol` | %/% dönemi kilitli; değiştirilemez. | — |
| `donem_kontrol` | Dönem silinemez. | — |
| `donem_kontrol` | Dönemi yalnızca İK kilitleyebilir. | — |
| `dosya_yukle` | %. satır okunamadı. | — |
| `dosya_yukle` | %. satırda kart numarası boş ya da geçersiz. | — |
| `dosya_yukle` | %. satırda yön "giris", "cikis" ya da boş olmalı. | — |
| `dosya_yukle` | %. satırda zaman geçersiz; saat dilimiyle gelmeli (ör. 2026-11-13T07:52:00+03:00). | {n}. satırda zaman bilgisi geçersiz. |
| `dosya_yukle` | Aynı anda başka bir aktarım yapıldı; lütfen dosyayı yeniden yükleyin. | — |
| `dosya_yukle` | Bir dosyada en fazla 200.000 satır olabilir (gelen: %). | — |
| `dosya_yukle` | Bu dosya daha önce yüklenmiş. | — |
| `dosya_yukle` | Dosya adı boş ya da 255 karakterden uzun. | — |
| `dosya_yukle` | Dosya türü geçersiz: %. Beklenen: pdks, kapi, yemekhane, servis. | Dosya türü geçersiz. |
| `dosya_yukle` | Dosya özeti geçersiz (64 haneli SHA-256 bekleniyor). | Dosya doğrulanamadı. Dosya yeniden yüklenmelidir. |
| `dosya_yukle` | Dosyada satır yok. | — |
| `dosya_yukle` | Dosyanın ait olduğu gün boş. | — |
| `dosya_yukle` | Okuyucu tanımlı değil ya da bu kaynağa ait değil: % (%. satır) | — |
| `dosya_yukle` | Satırlardan birinde zaman okunamadı (ör. 31.02 gibi olmayan bir tarih). | — |
| `duzeltme_hazirla` | Amir kaynaklı düzeltmeyi yalnızca amir yapabilir. | — |
| `duzeltme_hazirla` | Devamsızlık kararını yalnızca İK verebilir. | — |
| `duzeltme_hazirla` | Düzeltmeyi yapan kullanıcı bulunamadı ya da pasif. | — |
| `duzeltme_hazirla` | İK kaynaklı düzeltmeyi yalnızca İK rolü yapabilir. | — |
| `duzeltme_uygula` | Günlük kayıt bulunamadı: % | — |
| `fazla_mesai_inceleme_karar` | Bu kayıt zaten karara bağlanmış. | — |
| `fazla_mesai_inceleme_karar` | Karar (onay / ret) belirtilmeli. | — |
| `fazla_mesai_inceleme_karar` | Ret gerekçesi yazılmalı (en az 5 karakter). | — |
| `fazla_mesai_inceleme_karar` | İnceleme kaydı bulunamadı. | — |
| `fazla_mesai_inceleme_kontrol` | Fazla mesai inceleme kaydı silinemez. | — |
| `fazla_mesai_inceleme_kontrol` | Karar bilgisi durumla birlikte girilir. | — |
| `fazla_mesai_inceleme_kontrol` | Karar verilirken süre değiştirilemez. | — |
| `fazla_mesai_inceleme_kontrol` | Karara bağlanmış inceleme kaydı değiştirilemez. | — |
| `fazla_mesai_inceleme_kontrol` | Onaysız fazla mesaiye yalnızca İK karar verir. | — |
| `fazla_mesai_inceleme_kontrol` | Yeni kayıt "inceleme_bekliyor" olarak girilir; kararı İK verir. | — |
| `fazla_mesai_inceleme_kontrol` | İnceleme kaydının günü ve çalışanı değiştirilemez. | — |
| `fazla_mesai_karar` | Karar bekleyen fazla mesai talebi bulunamadı. | — |
| `fazla_mesai_onayi_geri_al` | Yazılı onay bulunamadı. | — |
| `fazla_mesai_onayi_kontrol` | Geri alınmış onay değiştirilemez. | — |
| `fazla_mesai_onayi_kontrol` | Onay geri alınmış olarak girilemez; önce onay girilir, sonra geri alınır. | — |
| `fazla_mesai_onayi_kontrol` | Onayın geri alındığını yalnızca İK girer. | — |
| `fazla_mesai_onayi_kontrol` | Onayın kendisi değiştirilemez; yalnızca geri alma bilgisi girilir. | — |
| `fazla_mesai_onayi_kontrol` | Yazılı fazla mesai onayını yalnızca İK girer. | — |
| `fazla_mesai_onayi_kontrol` | Yazılı onay silinemez; geri alınır. | — |
| `fazla_mesai_plani_kontrol` | % günü kilitli bir döneme ait; fazla mesai planı değişmez. | — |
| `fazla_mesai_plani_kontrol` | Fazla mesai planı silinemez; iptal edilir. | — |
| `fazla_mesai_plani_kontrol` | Fazla mesai planını yalnızca İK onaylar veya reddeder. | — |
| `fazla_mesai_plani_kontrol` | Fazla mesaiyi yalnızca amir ya da İK talep eder. | — |
| `fazla_mesai_plani_kontrol` | Geçersiz durum geçişi: % -> % | — |
| `fazla_mesai_plani_kontrol` | Geçmiş bir günün onaylı planı iptal edilemez. | — |
| `fazla_mesai_plani_kontrol` | Karara bağlanmış plan değiştirilemez. | — |
| `fazla_mesai_plani_kontrol` | Onaylı plan yalnızca iptal edilebilir. | — |
| `fazla_mesai_plani_kontrol` | Plan kararı değiştirilemez. | — |
| `fazla_mesai_plani_kontrol` | Planı yalnızca amir ya da İK iptal eder. | — |
| `fazla_mesai_plani_kontrol` | Planın içeriği değiştirilemez; iptal edip yeni talep girin. | — |
| `fazla_mesai_plani_kontrol` | Yeni plan "talep" olarak girilir; onayı İK verir. | — |
| `fazla_mesai_plani_kontrol` | Çalışanın % günü için vardiya planı yok. | — |
| `fazla_mesai_plani_kontrol` | İptal eden kullanıcı belirtilmeli. | — |
| `fm_plan_denetle` | Gece vardiyasına fazla mesai planlanamaz (İş Kanunu m.69: gece çalışması 7,5 saati geçemez). | Gece vardiyası için fazla mesai planlanamaz (İş Kanunu m. 69). |
| `fm_plan_denetle` | Günlük çalışma % dakika olur; sınır % dakika (11 saat). | Günlük çalışma {sa dk} olur; yasal sınır 11 saattir. |
| `fm_plan_denetle` | Yıllık fazla mesai sınırı aşılır: onaylı % dk + % dk > % dk (kalan % dk). | Yıllık fazla mesai sınırı aşılıyor. Kalan süre: {sa dk}. |
| `fm_plan_denetle` | Çalışanın % günü için geçerli yazılı fazla mesai onayı yok. | — |
| `gece_isi_calistir` | Bu gün için henüz veri yok: % | — |
| `gece_isi_tetikle` | Bir seferde en fazla 62 gün işlenebilir. | — |
| `gece_isi_tetikle` | Tarih aralığı geçersiz. | — |
| `gecici_kart_iade_al` | Açık zimmet bulunamadı. | — |
| `gecici_kart_zimmet_kontrol` | % kartı % % % verilmiş zimmetle çakışıyor (%). | — |
| `gecici_kart_zimmet_kontrol` | Bu geçici kart kayıp ya da iptal; verilemez. | — |
| `gecici_kart_zimmet_kontrol` | Geçici kartı yalnızca güvenlik ya da İK verebilir. | — |
| `gecici_kart_zimmet_kontrol` | Geçici kartın iadesini yalnızca güvenlik ya da İK alabilir. | — |
| `gecici_kart_zimmet_kontrol` | Zimmet iade edilmiş olarak girilemez; önce verilir, sonra iade alınır. | — |
| `gecici_kart_zimmet_kontrol` | Zimmet kaydı silinemez. | — |
| `gecici_kart_zimmet_kontrol` | Zimmetin kendisi değiştirilemez; yalnızca iade bilgisi yazılır. | — |
| `gecici_kart_zimmet_kontrol` | İade edilmiş zimmet değiştirilemez. | — |
| `gun_kaydi_fazla_mesai_kontrol` | % günü için geçerli yazılı fazla mesai onayı yok. | — |
| `gun_kaydi_fazla_mesai_kontrol` | % günü için onaylı fazla mesai planı yok; plansız çalışma puantaja yazılmaz (İK'ya uyarı verilir). | — |
| `gun_kaydi_fazla_mesai_kontrol` | Fazla mesai % dk, izin verilen % dk (onaylı plan ve İK onayı); fazlası puantaja yazılmaz. | — |
| `gun_kaydi_koru` | % alanı yalnızca pdks.duzeltme_uygula() ile değiştirilebilir. | — |
| `gun_kaydi_koru` | % günü kilitli bir döneme ait; değişiklik sonraki aya fark olarak yazılır. | — |
| `gun_kaydi_koru` | Devamsızlık kararını yalnızca İK, düzeltme ile verebilir. | — |
| `gun_kaydi_koru` | Günlük kaydın çalışanı veya günü değiştirilemez. | — |
| `gun_kaydi_koru` | Günlük kayıt silinemez. | — |
| `gun_kaydi_koru` | Tek seferde tek alan düzeltilir. | — |
| `gun_kaydi_koru` | Yeni günlük kayıtta saat yalnızca PDKS kaynaklı olabilir; diğerleri düzeltme ile girilir. | — |
| `gun_kodlari` | Bu işlem için yetkiniz yok. | — |
| `isg_belge_gir` | Geçerlilik bitiş tarihi girilmeli. | — |
| `isg_belge_gir` | Geçersiz belge türü: % (isg_egitimi / saglik_muayenesi) | Geçerli bir belge türü seçilmelidir. |
| `isg_belge_gir` | Çalışan bulunamadı ya da aktif değil. | — |
| `isg_belge_kontrol` | İSG belgesini yalnızca İSG uzmanı girer. | — |
| `isten_cikis_gir` | Bu çalışanın işten çıkışı zaten girilmiş. | — |
| `isten_cikis_gir` | Görevler ayrılığı: kimse kendi kaydında işlem yapamaz (calisan.isten_cikis). | — |
| `isten_cikis_gir` | Çalışan bulunamadı. | — |
| `isten_cikis_gir` | Çalışanda iade edilmemiş geçici kart var (%, % tarihinde verildi); önce iade alın. | — |
| `isten_cikis_gir` | Çıkış tarihi girilmeli. | — |
| `isten_cikis_gir` | Çıkış tarihi ileri olamaz; son çalışma günü ya da sonrasında girin. | — |
| `isten_cikis_gir` | Çıkış tarihi işe giriş tarihinden (%) önce olamaz. | — |
| `isten_cikis_gir` | Çıkış tarihinden sonra çalışılmış gün var (%); çıkış tarihini kontrol edin. | — |
| `itiraz_gir` | Görevler ayrılığı: kendi itirazınızı giremezsiniz. | — |
| `itiraz_gir` | Gün kaydı bulunamadı. | — |
| `itiraz_incelemeye_al` | Açık itiraz bulunamadı. | — |
| `itiraz_karar` | Karar bekleyen itiraz bulunamadı. | — |
| `itiraz_kontrol` | Karar veren kullanıcı belirtilmeli. | — |
| `itiraz_kontrol` | Karara bağlanmış itiraz değiştirilemez. | — |
| `itiraz_kontrol` | İtirazı yalnızca İK reddedebilir. | — |
| `izin_iptal` | Bu izin zaten iptal edilmiş. | — |
| `izin_iptal` | Bu iznin % günü işlenmiş; o günleri önce kayıt düzeltmeyle düzeltin. | İznin {n} günü işlenmiştir. Bu günler önce kayıt düzeltme ile güncellenmelidir. |
| `izin_iptal` | İptal nedeni yazılmalı (en az 5 karakter). | — |
| `izin_iptal` | İzin bulunamadı. | — |
| `kart_iptal_et` | Aktif kart bulunamadı. | — |
| `kart_no_cakisma_kontrol` | % numarası bir çalışanın asıl kartı; geçici kart olamaz. | — |
| `kart_no_cakisma_kontrol` | % numarası geçici kart olarak kayıtlı; asıl kart olamaz. | — |
| `kart_tanimla` | Çalışanın aktif kartı var; önce iptal edin. | — |
| `kendi_kaydi_engelle` | Görevler ayrılığı: kimse kendi kaydında işlem yapamaz (%.%). | — |
| `kullanici_ekle` | Bu e-posta başka bir kullanıcıda kayıtlı. | — |
| `kullanici_ekle` | Bu çalışanın zaten bir kullanıcı hesabı var. | — |
| `kullanici_ekle` | Geçerli bir e-posta yazılmalı. | — |
| `kullanici_ekle` | Geçersiz rol: % | — |
| `kullanici_ekle` | Görevler ayrılığı: kendinize hesap açamazsınız. | — |
| `kullanici_ekle` | Çalışan bulunamadı ya da aktif değil. | — |
| `kullanici_ekle` | Üst amir bulunamadı ya da aktif değil. | — |
| `kullanici_guncelle` | Geçersiz rol: % | — |
| `kullanici_guncelle` | Görevler ayrılığı: kendi hesabınızı değiştiremezsiniz. | — |
| `kullanici_guncelle` | Kullanıcı bulunamadı. | — |
| `kullanici_guncelle` | Kullanıcı kendisinin üst amiri olamaz. | — |
| `kullanici_guncelle` | Çalışan işten ayrılmış%; hesabı yeniden açılamaz. | — |
| `kullanici_guncelle` | Üst amir bulunamadı ya da aktif değil. | — |
| `puantaj_kontrol` | Puantaj yalnızca kilitlenmiş döneme yazılır. | — |
| `puantaj_yaz` | Puantaj yalnızca kilitlenmiş döneme yazılır. | — |
| `saatlik_izin_gir` | Bu saat aralığında başka bir saatlik izin var. | — |
| `saatlik_izin_gir` | İzin bitişi başlangıçtan sonra olmalı. | — |
| `saatlik_izin_kontrol` | % günü kilitli bir döneme ait; saatlik izin girilemez. | — |
| `saatlik_izin_kontrol` | Saatlik izni yalnızca İK girer. | — |
| `saatlik_izin_kontrol` | İzin saati % iş günüyle uyuşmuyor. | — |
| `soru_cevapla` | Bu soru türünde saatleri girin. | — |
| `soru_cevapla` | Bu soru zaten cevaplanmış. | — |
| `soru_cevapla` | Geçersiz cevap: % | — |
| `soru_cevapla` | Saat farklıysa giriş ya da çıkış saatini girin. | — |
| `soru_cevapla` | Soru bulunamadı ya da size atanmamış. | — |
| `soru_ik_karari` | Devamsız değilse giriş ya da çıkış saatini girin. | — |
| `soru_ik_karari` | İK kararı bekleyen soru bulunamadı. | — |
| `uyari_goruldu` | Uyarı bulunamadı ya da zaten görülmüş. | — |
| `vardiya_plani_gir` | % günü kilitli bir döneme ait. | — |
| `vardiya_plani_onayla` | Görevler ayrılığı: kendi girdiğiniz planı onaylayamazsınız. | — |
| `vardiya_plani_onayla` | Görevler ayrılığı: kimse kendi kaydında işlem yapamaz (vardiya_plani.onay). | — |
| `vardiya_plani_onayla` | Onay bekleyen plan bulunamadı. | — |
| `yetki_gerekli` | Bu işlem için yetkiniz yok. | — |
| `yetki_gerekli` | Oturum bulunamadı ya da hesap bir çalışana bağlı değil. | — |
