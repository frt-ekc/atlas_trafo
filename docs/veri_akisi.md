# Veri akışı — ekran fonksiyonu → okuduğu ve yazdığı tablolar

Bu belge, ekranın çağırdığı 34 veritabanı fonksiyonunun (RPC) hangi tablolara yazdığını ve hangilerini okuduğunu gösterir. Proje raporunun mimari ve veri akış diyagramı (DFD) bölümleri buradan alınabilir.

- **Tarih:** 22 Kasım 2026
- **Ortam:** yalnızca yerel Supabase; örnek veri, Kasım 1–24 gece işinden geçmiş.
- **Kapsam dışı:** canlı veritabanı.

## Nasıl ölçüldü

**Yazdığı tablolar ölçüldü** (`scratch/e3_veri_akisi.sql`). Her fonksiyon yetkili bir rolle ve geçerli parametreyle çağrıldı. Parametreler Adım 2'nin yetki matrisindekilerle aynı.

Çağrıdan hemen önce ve hemen sonra `pdks` şemasındaki 35 tablonun bütün satırları alındı (birincil anahtar ve satırın tamamı). İki görüntü karşılaştırıldı. Her çağrı kendi alt işleminde yapıldı ve geri alındı; çağrılar birbirini etkilemedi.

Tablodaki işaretler:
- `+1` bir satır eklendi
- `~1` bir satır değişti
- `−6` altı satır silindi

Değişen sütunlar ayrıca yazıldı.

**Okuduğu tablolar koddan çıkarıldı** (`scratch/e3_okuma.sql`). Kaynak, fonksiyonların yerel veritabanındaki son sürümü. Fonksiyonun çağırdığı iç fonksiyonlar ve yazdığı tabloların tetikleyicileri de izlendi. Bu liste metin aramasıyla çıkarıldı (`from` / `join` / `insert into` / `update` / `delete from`). Doğru ama kesin değil: hiç çalışmayan bir koldaki okuma da listeye girer.

**HTTP ile doğrulandı.** Aynı 34 çağrı, ekranın gönderdiği istekle gerçek HTTP üzerinden de yapıldı. Yalnızca `dosya_yukle` farklı sonuç verdi: SQL'den çalışıyor, HTTP'den hata veriyor (bkz. `docs/endpoint_testi.md` ve T-31). T-31 düzeltildi (`20261204010000_dosya_yukle_where.sql`); HTTP'de de aynı tablolar değişiyor.

## 1. Fonksiyon → yazdığı tablolar (ölçülen)

**İz tablosu** sütunu: değişikliğin kim / ne zaman / eski–yeni değer bilgisini tutan, silinemeyen kayıt. "—" o işlemin ayrı bir izi olmadığı anlamına gelir; işlemin kendi tablosundaki "kim, ne zaman" sütunları ayrıca belirtildi.

| Fonksiyon | Kim çağırır | Ölçülen değişiklik (değişen sütunlar) | İz tablosu | Beklenenle uyum |
|---|---|---|---|---|
| `dosya_yukle` | İK | `aktarim` +1, `ham_okutma` +1 | — (yükleyen tutulmuyor, T-13) | ✅ SQL'de. ✅ HTTP'de (T-31 düzeltildi) |
| `gece_isi_tetikle` | İK | `gece_isi` +1, `gun_kaydi` +76, `amir_sorusu` +1, `duzeltme` +2, `fazla_mesai_inceleme` +1, `okutma_isareti` +7, `uyari` +7 | `duzeltme`, `gece_isi` | ✅ |
| `soru_cevapla` | amir | `amir_sorusu` ~1 (cevap, cevap_giris, cevap_zamani, cevaplayan_id, durum), `duzeltme` +1, `gun_kaydi` ~1 (giriş + bütün dakika alanları) | `duzeltme` | ✅ Gün hemen yeniden hesaplanıyor |
| `soru_ik_karari` | İK | `amir_sorusu` ~1 (cevap_aciklama, **cevaplayan_id**, durum), `duzeltme` +1, `gun_kaydi` ~1 | `duzeltme` | ⚠️ Amirin adı soru kaydından siliniyor (T-32) |
| `kayit_duzelt` | İK | `duzeltme` +1, `gun_kaydi` ~1 (giris_zamani, giris_kaynagi) | `duzeltme` | ✅ Gün yeniden hesaplanıyor; bu örnekte dakikalar değişmedi (erken geliş sayılmaz). ⚠️ Başka günün itirazı bağlanabiliyor (T-34) |
| `itiraz_gir` | amir, İK | `itiraz` +1 | `itiraz` (giren, zaman) | ✅ |
| `itiraz_incelemeye_al` | İK | `itiraz` ~1 (yalnızca durum) | — | ⚠️ Kim / ne zaman yok (T-35) |
| `itiraz_karar` | İK | `itiraz` ~1 (durum, karar_aciklama, karar_veren_id, karar_zamani) | `itiraz` | ✅ Kabul kaydı düzeltmiyor (tasarım: düzeltme ayrıca yapılır) |
| `izin_gir` | İK | `izin` +1 | `izin` (giren) | ✅ |
| `izin_iptal` | İK | `izin` ~1 (iptal_eden_id, iptal_nedeni, iptal_zamani) | `izin` | ✅ Silmiyor, iptal ediyor |
| `saatlik_izin_gir` | İK | `saatlik_izin` +1, `gun_kaydi` ~1 (calisma_dk, saatlik_izin_dk) | `saatlik_izin` | ✅ İşlenmiş gün hemen yeniden hesaplanıyor |
| `vardiya_plani_gir` | amir, İK | `vardiya_plani` +1 | `vardiya_plani` (giren) | ✅ |
| `vardiya_plani_onayla` | İK | `vardiya_plani` ~1 (ik_onay_durumu), `gece_isi` +1, `gun_kaydi` +1 | `gece_isi` | ✅ Onaylanan geçmiş gün hemen işleniyor |
| `fazla_mesai_talep_et` | amir, İK | `fazla_mesai_plani` +1 | `fazla_mesai_plani` (talep eden) | ✅ |
| `fazla_mesai_karar` | İK | `fazla_mesai_plani` ~1 (durum, karar_aciklama, karar_veren_id, karar_zamani) | `fazla_mesai_plani` | ✅ |
| `fazla_mesai_inceleme_karar` | İK | `fazla_mesai_inceleme` ~1 (karar alanları, etki dakikaları, hedef dönem), `gun_kaydi` ~1 (calisma_dk, fazla_mesai_dk, fm50_dk) | `fazla_mesai_inceleme` | ✅ |
| `fazla_mesai_onayi_gir` | İK | `fazla_mesai_onayi` +1 | `fazla_mesai_onayi` (giren) | ✅ |
| `fazla_mesai_onayi_geri_al` | İK | `fazla_mesai_onayi` ~1 (gecerlilik_bitisi, geri_alma_bildirim_tarihi, geri_alma_giren_id), `uyari` +1 | `uyari` | ✅ |
| `gecici_kart_ver` | güvenlik, İK | `gecici_kart_zimmet` +1 | `gecici_kart_zimmet` (veren) | ✅ |
| `gecici_kart_iade_al` | güvenlik, İK | `gecici_kart_zimmet` ~1 (iade_alan_id, iade_zamani) | `gecici_kart_zimmet` | ✅ |
| `kart_tanimla` | İK | `kart` +1 | — | ✅ ⚠️ Kart numarası biçimi denetlenmiyor (T-36) |
| `kart_iptal_et` | İK | `kart` ~1 (durum, iptal_eden_id, iptal_nedeni, iptal_zamani) | `kart` | ✅ |
| `calisan_ekle` | İK | `calisan` +1 | — | ✅ |
| `isten_cikis_gir` | İK | `calisan` ~1 (aktif, isten_cikis_tarihi), `kart` ~1, `izin` ~1, `gun_kaydi` ~2 (durum), `duzeltme` +2, `vardiya_plani` −6 | `duzeltme` (gün değişiklikleri) | ✅ Belgede yazdığı gibi. Silinen 6 plan için iz yok (belgede "silinir" diyor) |
| `ariza_gir` | İK | `ariza` +1 | `ariza` (giren) | ✅ |
| `ariza_karar` | İK | `ariza` ~1 (durum, **giren_id**) | — | ⚠️ Karar veren `giren_id`'ye yazılıyor, karar zamanı yok (T-35) |
| `uyari_goruldu` | İK | `uyari` ~1 (goren_id, goruldu, gorulme_zamani) | `uyari` | ✅ |
| `ayar_guncelle` | admin | `ayar` ~1 (deger, guncelleme_zamani, guncelleyen_id), `ayar_gecmisi` +1 | `ayar_gecmisi` | ✅ |
| `kullanici_ekle` | admin | `kullanici` +1 | — | ⚠️ Kim ekledi tutulmuyor (T-33) |
| `kullanici_guncelle` | admin | (aynı değerle çağrıldı: değişiklik yok). Rol değişikliğinde yalnızca `kullanici` ~1 | — | ⚠️ Rol / aktiflik değişikliği iz bırakmıyor (T-33) |
| `isg_belge_gir` | İSG | `isg_belge` +1 | `isg_belge` (giren) | ✅ |
| `bolge_yetkisi_ver` | İSG | `bolge_yetkisi` +1, `bolge_yetkisi_gecmisi` +1 | `bolge_yetkisi_gecmisi` | ✅ |
| `bolge_yetkisi_kaldir` | İSG | `bolge_yetkisi` −1, `bolge_yetkisi_gecmisi` +1 | `bolge_yetkisi_gecmisi` | ✅ |
| `ay_kilitle` | İK | `donem` +1 (Ekim; Ekim'de gün kaydı olmadığı için puantaj satırı 0) | `donem` | ✅ Kasım denenemedi: 25–30 Kasım işlenmediği için veritabanı haklı olarak reddetti. Puantaj yazımı Adım 12'de |

**Hiçbir ekran fonksiyonunun doğrudan yazmadığı tablolar:**
- Tanım tabloları: `okuyucu`, `vardiya_tanim`, `departman`, `bolge`, `resmi_tatil`, `gecici_kart`.
- Ayın puantajı: `puantaj_satiri` ve `puantaj_kalemi`. Bunları yalnızca veri olan bir ay kilitlenirken `ay_kilitle` yazar.
- `kanit_kaydi`: `dosya_yukle` kapı, yemekhane ve servis dosyalarında buraya yazar; PDKS dosyasında `ham_okutma`'ya.

**İlgisi olmayan tabloya dokunan fonksiyon görülmedi.** Ölçülen her değişiklik, fonksiyonun belgesinde yazan ya da tetikleyiciyle gelen bir değişiklik.

## 2. Fonksiyon → okuduğu tablolar (koddan)

Ortak okuma: her fonksiyon yetki denetimi için `kullanici` tablosunu okur. Aşağıda bu tablo ayrıca yazılmadı.

| Fonksiyon | Okuduğu tablolar | Çağırdığı iç fonksiyonlar |
|---|---|---|
| `dosya_yukle` | `aktarim`, `ham_okutma`, `kanit_kaydi`, `okuyucu` | — |
| `gece_isi_tetikle` | 28 tablo: okutmalar, kanıtlar, planlar, izinler, kartlar, geçici kartlar, arızalar, İSG ve bölge tabloları, ayarlar, tatiller, sorular, gün kayıtları | `gece_isi_calistir` (ve onun bütün adımları) |
| `soru_cevapla`, `soru_ik_karari` | `amir_sorusu`, `gun_kaydi`, `duzeltme`, `donem`, `ayar`, `resmi_tatil`, `saatlik_izin`, `vardiya_tanim`, `fazla_mesai_*` | `duzeltme_uygula`, `saat_yaz`, `gun_hesapla` |
| `kayit_duzelt` | `gun_kaydi`, `duzeltme`, `amir_sorusu`, `donem`, `ayar`, `resmi_tatil`, `saatlik_izin`, `vardiya_tanim`, `fazla_mesai_*` | `duzeltme_uygula`, `gun_hesapla` |
| `itiraz_gir` | `gun_kaydi`, `calisan`, `departman` | `calisan_yetkisi`, `kullanici_calisani` |
| `itiraz_incelemeye_al`, `itiraz_karar` | `itiraz` | — |
| `izin_gir` / `izin_iptal` | `izin`, `gun_kaydi` (işlenmiş gün denetimi) | — |
| `saatlik_izin_gir` | `saatlik_izin`, `gun_kaydi`, `donem`, `ayar`, `resmi_tatil`, `vardiya_tanim`, `fazla_mesai_*` | `gun_hesabini_yenile`, `gun_sonrasi_kontroller` |
| `vardiya_plani_gir` | `calisan`, `departman`, `donem`, `gun_kaydi` | `calisan_yetkisi`, `donem_kilitli_mi` |
| `vardiya_plani_onayla` | `vardiya_plani` ve gece işinin okuduğu tablolar | `gece_isi_calistir`, `duzeltme_uygula`, `gun_hesapla` |
| `fazla_mesai_talep_et` | `calisan`, `departman`, `vardiya_plani`, `vardiya_tanim`, `fazla_mesai_onayi`, `fazla_mesai_plani`, `ayar`, `donem`, `gun_kaydi` | `calisan_yetkisi` |
| `fazla_mesai_karar`, `fazla_mesai_onayi_gir`, `fazla_mesai_onayi_geri_al` | `fazla_mesai_plani`, `fazla_mesai_onayi`, `vardiya_plani`, `vardiya_tanim`, `calisan`, `ayar`, `donem`, `gun_kaydi` | — |
| `fazla_mesai_inceleme_karar` | `fazla_mesai_inceleme`, `gun_kaydi`, `duzeltme`, `donem`, `ayar`, `resmi_tatil`, `saatlik_izin`, `vardiya_tanim`, `fazla_mesai_*` | `gun_hesabi`, `gun_hesabini_yenile`, `hedef_donem`, `uyari_yaz` |
| `gecici_kart_ver` / `gecici_kart_iade_al` | `gecici_kart`, `gecici_kart_zimmet`, `calisan` | — |
| `kart_tanimla` / `kart_iptal_et` | `kart`, `gecici_kart` | — |
| `calisan_ekle` | `calisan`, `departman` | — |
| `isten_cikis_gir` | `calisan`, `kart`, `gecici_kart`, `gecici_kart_zimmet`, `vardiya_plani`, `izin`, `fazla_mesai_*`, `gun_kaydi`, `duzeltme`, `donem`, `ayar`, `resmi_tatil`, `vardiya_tanim` | `duzeltme_uygula`, `kullanici_calisani` |
| `ariza_gir`, `ariza_karar`, `uyari_goruldu` | kendi tablosu | — |
| `ayar_guncelle` | `ayar` | — |
| `kullanici_ekle` / `kullanici_guncelle` | `kullanici`, `calisan` | `auth_hesabi_bagla`, `kullanici_calisani` |
| `isg_belge_gir` | `calisan` | — |
| `bolge_yetkisi_ver` / `bolge_yetkisi_kaldir` | `bolge`, `departman`, `bolge_yetkisi` | — |
| `ay_kilitle` | `donem`, `gun_kaydi`, `amir_sorusu`, `itiraz`, `fazla_mesai_*`, `vardiya_plani`, `izin`, `saatlik_izin`, `calisan`, `ayar`, `resmi_tatil`, `vardiya_tanim`, `puantaj_satiri`, `v_puantaj_canli` | `donem_kilitle`, `puantaj_yaz`, `gun_kod_satirlari`, `gun_hesapla` |
| `oturum_departmanlari` (okuma) | `departman` | `oturum_kullanici_id`, `oturum_rolu` |

`fazla_mesai_*` = `fazla_mesai_plani`, `fazla_mesai_onayi`, `fazla_mesai_inceleme`.

## 3. Ekranların okuduğu tablolar ve view'lar

Bu okumalar doğrudan yapılır (`supabase.from(...).select(...)`). Satırları RLS süzer.

| Sayfa | Okuduğu tablo / view |
|---|---|
| Ana sayfa (`/`) | `amir_sorusu`, `fazla_mesai_plani`, `gece_isi`, `gecici_kart`, `gecici_kart_zimmet`, `itiraz`, `izin`, `kullanici`, `uyari`, `v_isg_durum`, `v_izin_amir`, `vardiya_plani` |
| Çalışanlar (`/calisanlar`) | `calisan`, `departman` |
| Çalışan sayfası ve PDF döküm (`/calisanlar/[id]`, `lib/dokum.ts`) | `calisan`, `vardiya_plani`, `izin` (İK) ya da `v_izin_amir` (diğerleri), `fazla_mesai_plani`, `gecici_kart_zimmet` (İK, yönetici), `gun_kaydi`, `duzeltme`, `resmi_tatil`, `kart`, `itiraz` |
| Sorular | `amir_sorusu` |
| İtirazlar | `itiraz` |
| İzinler | `calisan`, `izin`, `saatlik_izin` |
| Vardiya planı | `calisan`, `vardiya_plani`, `vardiya_tanim`, `fazla_mesai_plani`, `izin`, `v_izin_amir`, `resmi_tatil` |
| Fazla mesai | `ayar`, `calisan`, `fazla_mesai_plani`, `fazla_mesai_onayi`, `fazla_mesai_inceleme` |
| Geçici kartlar | `ayar`, `calisan`, `gecici_kart`, `gecici_kart_zimmet` |
| İSG | `bolge`, `bolge_yetkisi`, `bolge_yetkisi_gecmisi`, `calisan`, `departman`, `v_isg_durum` |
| Uyarılar | `uyari` |
| Veri aktarımı | `aktarim`, `ariza`, `gece_isi`, `okuyucu`, `donem` |
| Puantaj | `amir_sorusu`, `calisan`, `donem`, `fazla_mesai_inceleme`, `itiraz`, `puantaj_satiri`, `v_puantaj_aktarim`, `v_puantaj_canli` |
| Ayarlar | `ayar`, `ayar_gecmisi` |
| Kullanıcılar | `calisan`, `kullanici` |
| Her sayfa (oturum, menü) | `kullanici` (`lib/oturum.ts`), `departman` + `oturum_departmanlari()` (`lib/bolumler.ts`) |

Toplam: 30 tablo ve 4 view.
- Ekranın hiç okumadığı tablolar: `ham_okutma`, `kanit_kaydi`, `okutma_isareti`, `puantaj_kalemi`, `isg_belge`. `isg_belge` `v_isg_durum` üzerinden okunur.
- Ekranın hiç kullanmadığı fonksiyonlar: `gun_kodlari` (puantaj ekranı `v_puantaj_canli`'yı okuyor) ve `ayar_al` (fazla mesai ekranı bunu bilerek kullanmıyor).

## 4. DFD için özet akışlar

```
PDKS / kapı / yemekhane / servis CSV ──(İK, tarayıcı)──▶ dosya_yukle ──▶ aktarim, ham_okutma | kanit_kaydi
                                                                         │
pg_cron (her gece) ya da İK düğmesi ──▶ gece_isi_tetikle ──▶ okutma_isareti, gun_kaydi, duzeltme (kanıtla),
                                                             amir_sorusu, fazla_mesai_inceleme, ariza, uyari, gece_isi
Amir ──▶ soru_cevapla ──▶ amir_sorusu, duzeltme, gun_kaydi            ("gelmedi / bilmiyorum" → İK'ya)
İK   ──▶ soru_ik_karari / kayit_duzelt ──▶ amir_sorusu, duzeltme, gun_kaydi
Amir / İK ──▶ itiraz_gir ──▶ itiraz ──(İK)──▶ itiraz_karar
İK   ──▶ izin_gir, saatlik_izin_gir, vardiya_plani_onayla, fazla_mesai_* ──▶ ilgili tablo (+ gün yeniden hesap)
Güvenlik ──▶ gecici_kart_ver / iade ──▶ gecici_kart_zimmet
İSG ──▶ isg_belge_gir, bolge_yetkisi_* ──▶ isg_belge, bolge_yetkisi (+ geçmiş)
Admin ──▶ ayar_guncelle (+ ayar_gecmisi), kullanici_ekle / guncelle
İK   ──▶ ay_kilitle ──▶ donem (kilitli), puantaj_satiri, puantaj_kalemi ──▶ Excel / ERP dosyası (ekran)
```
