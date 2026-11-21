# Endpoint testi — ekran ↔ backend ↔ veritabanı eşleşmesi

- **Tarih:** 22 Kasım 2026
- **Ortam:** yalnızca yerel Supabase (Docker); canlıya bağlanılmadı.
- **Kod:** `main` @ `15ee334`; kod değiştirilmedi.
- **Veri akışı matrisi** (madde 3) ayrı belgede: `docs/veri_akisi.md`.
- **Bulgular:** `docs/backend_test_raporu.md`, T-31 – T-38.
- **Sonradan:** T-31 `fix/t31-dosya-yukle` dalında düzeltildi (`20261204010000_dosya_yukle_where.sql`). Aşağıdaki tablolar düzeltmeden önceki sonuçtur; değişen yerler "→ düzeltildi" ile işaretli.

## Özet

| | Sayı |
|---|---|
| Ekranın yazma uçları (RPC) | 34 fonksiyon veritabanında; ekran **32**'sini çağırıyor. `calisan_ekle` ve `isten_cikis_gir`'in ekranı yok |
| Ekranın okuma uçları | 1 RPC (`oturum_departmanlari`) + 30 tablo + 4 view |
| Giriş | Supabase Auth: `signInWithPassword`, `signOut` |
| HTTP isteği | **273**: 263'ü betikte; 10'u giriş yapmadan ham REST okuması |
| Yazma: yetkili çağrı | 34. Biri başarısız: `dosya_yukle` (T-31 → düzeltildi, artık 34'ü de başarılı). 33'ü başarılı; veritabanı değişikliği madde 3'teki matrisle aynı |
| Yazma: yetkisiz rol | 34 / 34 reddedildi, hiçbir tablo değişmedi |
| Yazma: giriş yapmamış (anon) | 35 / 35 reddedildi (HTTP 401, `42501`), hiçbir tablo değişmedi |
| Okuma: 8 tablo / view × 11 rol | 88 sayım. HTTP sonucu, aynı oturumla SQL sonucuyla **88 / 88 aynı**. Anon 10 / 10 reddedildi |
| Hata yolu | 63 deneme + 4 tekrar. 4'ü kabul edildi (açıklaması aşağıda). Ekrana teknik İngilizce mesaj: `rpcCagir` yolunda **0**; `dosya_yukle` yolunda **var** (T-37) |
| Beklenmedik sonuç | 8 bulgu (T-31 – T-38); ekranla ilgili 4 iş "Gökalp için" listesinde |

## Güvenlik önlemleri

- **Adres yalnızca `supabase status` çıktısından alındı** (`scratch/e_calistir.sh`). Betik bağlantıdan önce veritabanı ve API adresinin `127.0.0.1` ya da `localhost` olduğunu denetliyor; değilse duruyor. Node betikleri de aynı denetimi ayrıca yapıyor.
- **Hiçbir anahtar, şifre ya da adres ekrana, dosyaya ya da bu belgeye yazılmadı.**
  - Test hesaplarının şifresi rastgele üretildi ve yalnızca bellekte tutuldu.
  - Hata mesajlarında psql komut satırı (ve dolayısıyla adres) gösterilmiyor.
- **`.env` ve `.env.local` okunmadı.** `.env.example` bir kez açıldı, değerleri `<gizli>` diye maskelenerek. Dosyada yalnızca değişken adları ve yer tutucular var.
- **HTTP testi veriyi kalıcı değiştirdiği için yerel veritabanı önce ve sonra sıfırlandı** (`supabase db reset`). Bu işlem yerel Auth kullanıcılarını da siler.

## 1. Endpoint haritası (kod okuma)

Ekranın bütün yazmaları aynı yoldan gider:

```
düğme → pencere / form → Server Action (actions.ts) → rpcCagir(ad, parametreler) → supabase.rpc → pdks.<fonksiyon>
```

`dosya_yukle` bu yolun tek istisnası: tarayıcıdaki bileşenden doğrudan `supabase.rpc` ile çağrılıyor.

"Kim yaptı" bilgisi hiçbir çağrıda gönderilmiyor; veritabanı kullanıcıyı oturumdan kendisi buluyor.

Parametre kaynakları için kısaltmalar:
- **gizli:** formdaki gizli alan (satırın kendi kaydının numarası)
- **sicil:** formdaki sicil numarasından `sicildenCalisan` ile bulunan çalışan no. RLS amire yalnızca kendi bölümünü gösterir.
- **TR saati:** `datetime-local` alanı + `:00+03:00`

| Sayfa | Düğme (pencere onayı) | Server Action | RPC | Parametreler ← değerin kaynağı | Anlam uyumu |
|---|---|---|---|---|---|
| Veri aktarımı | Yükle (tarayıcıdan) | — (`aktarim-formu.tsx`) | `dosya_yukle` | `p_kaynak` ← seçim ya da dosya adından tahmin · `p_dosya_adi` ← dosya adı · `p_veri_tarihi` ← tarayıcıdaki denetim · `p_satirlar` ← denetlenmiş satırlar · `p_dosya_ozeti` ← tarayıcıda SHA-256 | ✅ |
| Veri aktarımı | Gece işini çalıştır (Çalıştır) | `geceIsiTetikle` | `gece_isi_tetikle` | `p_baslangic`, `p_bitis` ← tarih alanları (bitiş boşsa başlangıç) | ✅ |
| Veri aktarımı | Arıza gir (Kaydet) | `arizaGir` | `ariza_gir` | `p_okuyucu_id` ← seçim · `p_baslangic`, `p_bitis` ← TR saati · `p_aciklama` | ✅ |
| Veri aktarımı | "Arıza" / "Arıza değil" | `arizaKarari` | `ariza_karar` | `p_ariza_id` ← gizli `a.id` · `p_onay` ← gizli `karar` = onay / ret | ✅ |
| Sorular | Cevapla | `soruCevapla` | `soru_cevapla` | `p_soru_id` ← gizli `soru.id` · `p_cevap` ← seçim · `p_giris`, `p_cikis` ← TR saati (yalnızca "saat farklı") · `p_aciklama` | ✅ |
| Sorular | Karar ver (İK) | `soruIkKarari` | `soru_ik_karari` | `p_soru_id` ← gizli · `p_devamsiz` ← karar = devamsız · `p_gerekce` · `p_giris`, `p_cikis` ← TR saati (yalnızca "geldi") | ✅ |
| Çalışan sayfası | Düzelt (Düzeltmeyi kaydet) | `kayitDuzelt` | `kayit_duzelt` | `p_gun_kaydi_id` ← gizli `g.gunKaydiId` · `p_alan` ← seçim (giriş / çıkış / durum) · `p_yeni_deger` ← TR saati ya da durum · `p_gerekce` · `p_itiraz_id` ← seçim (o günün itirazları). `p_izin_id` hiç gönderilmiyor | ✅ ⚠️ İtiraz listesi (T-34) |
| Çalışan sayfası | İtiraz (İtirazı kaydet) | `itirazGir` | `itiraz_gir` | `p_gun_kaydi_id` ← gizli · `p_metin` | ✅ |
| Çalışan sayfası | Kart tanımla | `kartTanimla` | `kart_tanimla` | `p_calisan_id` ← gizli (adresteki no) · `p_kart_no` ← büyük harfe çevrilmiş, `^[A-Z0-9-]{1,32}$` | ✅ |
| Çalışan sayfası | Kartı iptal et | `kartIptalEt` | `kart_iptal_et` | `p_kart_id` ← gizli `aktifKart.id` · `p_neden` ← seçim | ✅ |
| İtirazlar | İncelemeye al | `itirazIncelemeyeAl` | `itiraz_incelemeye_al` | `p_itiraz_id` ← gizli | ✅ |
| İtirazlar | Karar ver | `itirazKarar` | `itiraz_karar` | `p_itiraz_id` ← gizli · `p_kabul` ← karar = onay · `p_aciklama` | ✅ "Reddet" → `p_kabul=false` → durum `red` (HTTP ile doğrulandı) |
| İzinler | İzin gir | `izinGir` | `izin_gir` | `p_calisan_id` ← sicil · `p_tur` ← seçim · `p_baslangic`, `p_bitis` ← tarih · `p_aciklama` | ✅ |
| İzinler | Saatlik izin gir | `saatlikIzinGir` | `saatlik_izin_gir` | `p_calisan_id` ← sicil · `p_tarih` · `p_baslangic`, `p_bitis` ← `${tarih}T${saat}:00+03:00` · `p_tur` · `p_aciklama` | ✅ 13:00–14:00 olarak yazıldı |
| İzinler | İptal et | `izinIptal` | `izin_iptal` | `p_izin_id` ← gizli · `p_neden` | ✅ |
| Vardiya planı | Vardiya gir | `vardiyaPlaniGir` | `vardiya_plani_gir` | `p_calisan_id` ← sicil · `p_tarih` · `p_vardiya_id` ← seçim · `p_aciklama` | ✅ |
| Vardiya planı | "Onayla" / "Reddet" | `vardiyaPlaniOnayla` | `vardiya_plani_onayla` | `p_plan_id` ← gizli `p.id` · `p_onay` ← gizli `karar` = onay | ✅ |
| Fazla mesai | Fazla mesai talebi aç | `fazlaMesaiTalepEt` | `fazla_mesai_talep_et` | `p_calisan_id` ← sicil · `p_is_gunu` · `p_planli_dk` ← saat × 60 · `p_gerekce` | ✅ |
| Fazla mesai | Karar ver (talep) | `fazlaMesaiKarar` | `fazla_mesai_karar` | `p_plan_id` ← gizli · `p_onay` ← karar · `p_aciklama` | ✅ "Reddet" → durum `reddedildi` (HTTP ile doğrulandı) |
| Fazla mesai | Karar ver (onaysız havuz) | `havuzKarari` | `fazla_mesai_inceleme_karar` | `p_inceleme_id` ← gizli · `p_onay` · `p_aciklama` | ✅ |
| Fazla mesai | Yazılı onay gir | `yaziliOnayGir` | `fazla_mesai_onayi_gir` | `p_calisan_id` ← sicil · `p_yil` · `p_imza_tarihi` · `p_belge_no` | ✅ |
| Fazla mesai | Onayı geri al | `yaziliOnayGeriAl` | `fazla_mesai_onayi_geri_al` | `p_onay_id` ← önce `fazla_mesai_onayi`'nden (sicil + yıl) okunur · `p_bildirim_tarihi` | ✅ |
| Geçici kartlar | Ver (Kartı ver) | `kartVer` | `gecici_kart_ver` | `p_gecici_kart_id` ← gizli `kartId` · `p_calisan_id` ← sicil · `p_aciklama` | ✅ |
| Geçici kartlar | İade al | `kartIadeAl` | `gecici_kart_iade_al` | `p_zimmet_id` ← gizli `zimmet.id` | ✅ |
| İSG | Belge gir | `isgBelgeGir` | `isg_belge_gir` | `p_calisan_id` ← sicil · `p_tur` ← seçim · `p_gecerlilik_bitis` · `p_belge_no` | ✅ |
| İSG | "Ver" / "Kaldır" | `bolgeYetkisi` | `bolge_yetkisi_ver` / `bolge_yetkisi_kaldir` | `p_bolge_id`, `p_departman_id` ← gizli · hangi fonksiyon ← gizli `islem` (hücrede yetki varsa "kaldir") | ✅ |
| Uyarılar | Görüldü | `uyariGoruldu` | `uyari_goruldu` | `p_uyari_id` ← gizli | ✅ |
| Ayarlar | Değiştir | `ayarGuncelle` | `ayar_guncelle` | `p_anahtar` ← gizli · `p_deger` ← tam sayı | ✅ |
| Kullanıcılar | Kullanıcı ekle | `kullaniciEkle` | `kullanici_ekle` | `p_ad_soyad`, `p_eposta`, `p_rol` · `p_calisan_id` ← sicil · `p_ust_amir_id` ← seçim | ✅ |
| Kullanıcılar | Düzenle | `kullaniciGuncelle` | `kullanici_guncelle` | `p_kullanici_id` ← gizli · `p_rol` · `p_ust_amir_id` (boş = değiştirme) · `p_aktif` ← kutu (önceden işaretli) | ✅ |
| Puantaj | Ayı kilitle | `ayKilitle` | `ay_kilitle` | `p_yil`, `p_ay` ← gizli `ay` (YYYY-MM) · `p_zorla` ← kutu. Ayrıca "geri açılamaz" onay kutusu zorunlu | ✅ |
| Her sayfa (amir) | — | `gorunurBolumler` | `oturum_departmanlari` (okuma) | — | ✅ |
| — | **yok** | — | `calisan_ekle` | — | ❌ Ekranı yok (T-38, Gökalp listesi G2) |
| — | **yok** | — | `isten_cikis_gir` | — | ❌ Ekranı yok (T-38, G2) |

**Kontrol sonuçları:**
- **Buton adı ile gönderilen karar:** 9 karar düğmesinin hepsinde tutarlı. "Reddet" iki yerde HTTP ile denendi: itiraz durumu `red`, fazla mesai talebi `reddedildi` oldu.
- **Kayıt numaraları:** Her gizli alanda, düğmenin durduğu satırın kendi kaydının numarası var (`soru.id`, `p.id`, `g.gunKaydiId`, `zimmet.id`…).
  - `kart_tanimla`'nın `p_calisan_id`'si adresten geliyor. Adres elle değiştirilirse başka çalışana kart tanımlanabilir; ama yetkiyi veritabanı denetliyor (yalnızca İK).
- **Türkiye saati:** Saat gönderen 5 yerin hepsi `+03:00` ekliyor (`zamanAl` ve `saatlikIzinGir`). HTTP ile yazılan değerler Türkiye saatiyle okundu: kayıt düzeltme 08:00, İK kararı 17:00, saatlik izin 13:00–14:00.
  - Ekrandaki "bugün" (`lib/hafta.ts`) `Europe/Istanbul`'a göre hesaplanıyor.
- **Parametre adları:** 33 RPC'nin hepsi ekranın gönderdiği parametre adlarıyla HTTP'de çağrıldı. Ad uyuşmasaydı PostgREST fonksiyonu bulamaz (`PGRST202`) hatası verirdi; hiç görülmedi.
- **Veritabanında olup ekranın çağırmadığı fonksiyonlar:**
  - Yazma: `calisan_ekle`, `isten_cikis_gir`.
  - Okuma yardımcıları: `gun_kodlari`, `ayar_al`, `oturum_rolu`, `oturum_kullanici_id`, `tum_veriyi_gorur`, `amirin_calisani_mi`. Bunlar RLS ve diğer fonksiyonlar için var; ekranın çağırması gerekmiyor.
- **Ekranın çağırıp veritabanında olmayan fonksiyon yok.**
- **Okuma sorguları:** listesi `docs/veri_akisi.md` bölüm 3'te. Arama kutusu PostgREST süzgecine konmadan önce temizleniyor (`aramaTemizle`: harf, rakam, boşluk, tire). Adresten gelen ay `YYYY-MM` biçiminde denetleniyor.

## 2. Oturum ve anahtar

| Kontrol | Sonuç |
|---|---|
| Yazma ve okuma kimin oturumuyla gidiyor? | Hepsi kullanıcının kendi oturumuyla. Sunucuda `createServerClient` (çerezdeki oturum), tarayıcıda `createBrowserClient`. İkisi de yalnızca `NEXT_PUBLIC_SUPABASE_URL` ve `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` kullanıyor (`lib/supabase/ayarlar.ts`) |
| `SUPABASE_SECRET_KEY` nerede? | **Hiçbir uygulama dosyasında kullanılmıyor** (`app`, `lib`, `components`, `proxy.ts`, `next.config.ts` tarandı; yalnızca "buraya eklenmez" yorumu var). Tarayıcıya gitmiyor |
| `db.schema` | Sunucu ve tarayıcı istemcisinde `"pdks"` ✅. `proxy.ts`'teki oturum tazeleyici şema vermiyor; yalnızca `auth.getClaims()` çağırdığı için gerekmiyor ✅ |
| Giriş | Sunucuda (`app/giris/actions.ts`), şifre tarayıcıda saklanmıyor. Hatalı girişte "E-posta ya da şifre hatalı" (hesap var mı belli olmuyor) |
| Giriş yapmamış istek | REST: `permission denied for schema pdks` (401). RPC: 401 `42501` |
| Sayfa koruması | `proxy.ts` giriş yapmamışı `/giris`'e yönlendiriyor; asıl yetki veritabanında (RLS ve `yetki_gerekli`) |

## 3. Veri akışı

Bkz. `docs/veri_akisi.md`.

Kısaca: ekranın çağırdığı 34 fonksiyonun hepsi beklenen tablolara yazıyor ve ilgisiz bir tabloya dokunmuyor. İz tablolarından `duzeltme`, `ayar_gecmisi` ve `bolge_yetkisi_gecmisi` gereken yerde doluyor. Dört yerde iz eksik ya da üzerine yazılıyor: T-32, T-33, T-34 ve T-35.

## 4. Gerçek HTTP denemesi

**Kurulum** (`scratch/e4_http.mjs`, `scratch/e4_hazirlik.sql`):
- Yerel Auth'ta 11 test hesabı açıldı. Plandaki 10 hesap ve `ik.uzmani`; şifreler rastgele.
- Hesaplar, seed'in son bölümündeki sorguyla e-postaya göre `pdks.kullanici`'ya bağlandı (11 / 11).
- Kasım 1–24 gece işinden geçirildi. Adım 2'deki açık soru, itiraz ve fazla mesai talebi hazırlandı.
- Her hesapla `signInWithPassword` yapıldı. İstemci ekranla aynı: yayınlanabilir anahtar, `db.schema = "pdks"`, parametreler `actions.ts` ile aynı.

**Her yazma için sıra:**
1. Yetkisiz rol
2. Giriş yapmamış istek
3. Yetkili rol

Her istekten önce ve sonra 35 tablonun satır sayısı ve içerik özeti alındı.

| RPC | Yetkili | HTTP | Değişen tablolar | Madde 3'le | Yetkisiz rol → ekrandaki mesaj | Anon |
|---|---|---|---|---|---|---|
| `dosya_yukle` | ik.muduru | **400 `21000` "UPDATE requires a WHERE clause"** → düzeltildi: 200 | **yok** → `aktarim`+1, `ham_okutma`+1 | ❌ (T-31) → aynı | montaj.amiri → "Bu işlem için yetkiniz yok." | 401 |
| `gece_isi_tetikle` | ik.muduru | 200 | `gece_isi`+1 | farklı gün* | fabrika.muduru → "Bu işlem için yetkiniz yok." | 401 |
| `soru_cevapla` | montaj.amiri | 204 | `amir_sorusu`~, `duzeltme`+1, `gun_kaydi`~ | aynı | bobinaj.amiri → "Soru bulunamadı ya da size atanmamış." | 401 |
| `soru_ik_karari` | ik.muduru | 204 | `amir_sorusu`~, `duzeltme`+1, `gun_kaydi`~ | aynı | montaj.amiri → yetki yok | 401 |
| `kayit_duzelt` | ik.muduru | 200 (no) | `duzeltme`+1, `gun_kaydi`~ | aynı | montaj.amiri → yetki yok | 401 |
| `itiraz_gir` | montaj.amiri | 200 | `itiraz`+1 | aynı | guvenlik → yetki yok | 401 |
| `itiraz_incelemeye_al` | ik.muduru | 204 | `itiraz`~ | aynı | montaj.amiri → yetki yok | 401 |
| `itiraz_karar` (ret) | ik.muduru | 204 | `itiraz`~ → `red` | aynı | montaj.amiri → yetki yok | 401 |
| `izin_gir` | ik.muduru | 200 | `izin`+1 | aynı | montaj.amiri → yetki yok | 401 |
| `izin_iptal` | ik.muduru | 204 | `izin`~ | aynı | montaj.amiri → yetki yok | 401 |
| `saatlik_izin_gir` | ik.muduru | 200 | `gun_kaydi`~, `saatlik_izin`+1 | aynı | montaj.amiri → yetki yok | 401 |
| `vardiya_plani_gir` | montaj.amiri | 200 | `vardiya_plani`+1 | aynı | bobinaj.amiri → "Bu çalışan sizin departmanınızda değil." | 401 |
| `vardiya_plani_onayla` | ik.muduru | 204 | `gece_isi`+1, `gun_kaydi`+1, `vardiya_plani`~ | aynı | montaj.amiri → yetki yok | 401 |
| `fazla_mesai_talep_et` | montaj.amiri | 200 | `fazla_mesai_plani`+1 | aynı | guvenlik → yetki yok | 401 |
| `fazla_mesai_karar` (ret) | ik.muduru | 204 | `fazla_mesai_plani`~ → `reddedildi` | aynı | montaj.amiri → yetki yok | 401 |
| `fazla_mesai_inceleme_karar` | ik.muduru | 204 | `fazla_mesai_inceleme`~, `gun_kaydi`~ | aynı | montaj.amiri → yetki yok | 401 |
| `fazla_mesai_onayi_gir` | ik.muduru | 200 | `fazla_mesai_onayi`+1 | aynı | montaj.amiri → yetki yok | 401 |
| `fazla_mesai_onayi_geri_al` | ik.muduru | 204 | `fazla_mesai_onayi`~, `uyari`+1 | aynı | montaj.amiri → yetki yok | 401 |
| `gecici_kart_ver` | guvenlik | 200 | `gecici_kart_zimmet`+1 | aynı | montaj.amiri → yetki yok | 401 |
| `gecici_kart_iade_al` | guvenlik | 204 | `gecici_kart_zimmet`~ | aynı | montaj.amiri → yetki yok | 401 |
| `kart_tanimla` | ik.muduru | 200 | `kart`+1 | aynı | guvenlik → yetki yok | 401 |
| `kart_iptal_et` | ik.muduru | 204 | `kart`~ | aynı | guvenlik → yetki yok | 401 |
| `calisan_ekle` | ik.muduru | 200 | `calisan`+1 | aynı | sistem.yoneticisi → yetki yok | 401 |
| `isten_cikis_gir` | ik.muduru | 200 (özet) | `calisan`~, `duzeltme`+2, `gun_kaydi`~, `izin`~, `kart`~, `vardiya_plani`−6 | aynı | sistem.yoneticisi → yetki yok | 401 |
| `ariza_gir` | ik.muduru | 200 | `ariza`+1 | aynı | guvenlik → yetki yok | 401 |
| `ariza_karar` | ik.muduru | 204 | `ariza`~ | aynı | guvenlik → yetki yok | 401 |
| `uyari_goruldu` | ik.muduru | 204 | `uyari`~ | aynı | montaj.amiri → yetki yok | 401 |
| `ayar_guncelle` | sistem.yoneticisi | 204 | `ayar`~, `ayar_gecmisi`+1 | aynı | ik.muduru → yetki yok | 401 |
| `kullanici_ekle` | sistem.yoneticisi | 200 | `kullanici`+1 | aynı | ik.muduru → yetki yok | 401 |
| `kullanici_guncelle` | sistem.yoneticisi | 204 | — (aynı değerler) | aynı | ik.muduru → yetki yok | 401 |
| `isg_belge_gir` | isg.uzmani | 200 | `isg_belge`+1 | aynı | ik.muduru → yetki yok | 401 |
| `bolge_yetkisi_ver` | isg.uzmani | 204 | `bolge_yetkisi`+1, `bolge_yetkisi_gecmisi`+1 | aynı | ik.muduru → yetki yok | 401 |
| `bolge_yetkisi_kaldir` | isg.uzmani | 204 | `bolge_yetkisi`−1, `bolge_yetkisi_gecmisi`+1 | aynı | ik.muduru → yetki yok | 401 |
| `ay_kilitle` (Ekim, zorla) | ik.muduru | 200 (özet) | `donem`+1 | aynı | fabrika.muduru → yetki yok | 401 |
| `oturum_departmanlari` | montaj.amiri | 200 `[1,5]` | okuma | — | — | 401 |

\* Madde 3'te 25 Kasım işlendi. HTTP'de, bugünün tarihi (22 Kasım) yüzünden daha önce işlenmiş 21 Kasım yeniden işlendi. Yeniden işlemede yalnızca `gece_isi` satırı eklenmesi beklenen davranış: var olan gün kaydı bozulmuyor.

**Okuma** (8 tablo / view × 11 rol). HTTP sayısı (`count: exact`), aynı anda aynı oturumla SQL'de sayılanla karşılaştırıldı:

| Tablo / view | ik (2 hesap) | montaj | bobinaj | kalite | üretim md. | genel md. | güvenlik | yönetici | isg | admin | anon |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `calisan` | 77 | 21 | 10 | 5 | 6 | 3 | 77 | 77 | 77 | 77 | 401 |
| `gun_kaydi` | 1293 | 341 | 170 | 85 | 102 | 51 | 0 | 1293 | 0 | 0 | 401 |
| `amir_sorusu` | 2 | 2 | 0 | 0 | 2 | 0 | 0 | 2 | 0 | 0 | 401 |
| `izin` | 4 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 | 0 | 401 |
| `v_izin_amir` | 2 | 1 | 0 | 0 | 1 | 0 | 0 | 2 | 0 | 0 | 401 |
| `uyari` | 17 | 0 | 0 | 0 | 0 | 0 | 0 | 17 | 4 | 0 | 401 |
| `duzeltme` | 15 | 14 | 9 | 0 | 0 | 0 | 0 | 15 | 0 | 0 | 401 |
| `gecici_kart_zimmet` | 7 | 0 | 0 | 0 | 0 | 0 | 7 | 7 | 0 | 0 | 401 |

HTTP ile SQL **88 / 88 aynı**. Adım 3'teki RLS matrisiyle karşılaştırma:
- Desen aynı: güvenlik, İSG ve admin gün kaydı görmüyor; İSG yalnızca kendi 4 uyarısını görüyor.
- Sayılar veri durumu kadar farklı. Örneğin `calisan` 76 → 77, çünkü `calisan_ekle` bir kişi ekledi. `gun_kaydi` farklı, çünkü burada yalnızca 1–24 Kasım işlendi.
- Montaj amirinin 21 çalışanı: 10 Montaj çalışanı, vekili olduğu Bobinaj'ın 10 çalışanı ve az önce Montaj'a eklenen Y900. Ayrı bir SQL sorgusuyla doğrulandı: `oturum_departmanlari() = {1,5}`.

## 5. Hata yolu

63 hata denemesi yapıldı. Her yazma fonksiyonundan en az bir hata alındı: yetkisiz rol yukarıda, geçersiz değer, görevler ayrılığı ihlali ve ikinci kez işlem burada. Her denemeden önce ve sonra tablolar karşılaştırıldı.

**Sonuç:**
- **59 / 63 reddedildi ve hiçbir tablo değişmedi.**
- **`rpcCagir`'den geçen her mesaj Türkçe.** Yakalanan PostgreSQL hata kodları bu mesajlara çevriliyor:
  - `23514`, `22008` → "Girilen değer geçersiz."
  - `23503` → "İlgili kayıt bulunamadı."
  - `23505` → "Bu kayıt zaten var."
- **Teknik ek siliniyor:** "(izin.giren_id)" gibi parantez içi sonek mesajdan atılıyor.

| Tür | Örnek deneme | Veritabanının mesajı | Ekranda görünen |
|---|---|---|---|
| Görevler ayrılığı | İK kendi izni, kendi günü, kendi çıkışı; güvenlik kendine kart; İSG kendi belgesi; amir kendi günü, kendine fazla mesai; admin kendi hesabı, kendine hesap (9 deneme) | "Görevler ayrılığı: kimse kendi kaydında işlem yapamaz (izin.giren_id)." | "Görevler ayrılığı: kimse kendi kaydında işlem yapamaz." ✅ |
| Check kısıtı | Geçersiz izin türü, bitiş başlangıçtan önce, geçersiz durum, kısa gerekçe, arıza bitişi önce | `new row for relation "izin" violates check constraint "izin_tur_check"` | "Girilen değer geçersiz." ✅ (Türkçe ama neyin geçersiz olduğunu söylemiyor; ekran bu değerleri zaten önceden denetliyor) |
| Yabancı anahtar | Olmayan çalışan, itiraz, vardiya, geçici kart | `insert or update on table "izin" violates foreign key constraint …` | "İlgili kayıt bulunamadı." ✅ |
| Tekil kısıt | Aynı yılın onayı, kullanılan kart no | `duplicate key value violates unique constraint …` | "Bu kayıt zaten var." → `kartTanimla` ve `yaziliOnayGir` bunu daha açık bir cümleye çeviriyor ✅ |
| Saat biçimi | `"25.11.2026 08:00"` | `date/time field value out of range` | "Girilen değer geçersiz." ✅ |
| İkinci kez işlem | Cevaplanmış soru, kapanmış İK kararı, karar verilmiş itiraz, onaylanmış plan, iptal edilmiş izin / kart, iade edilmiş zimmet, karara bağlanmış havuz / arıza, geri alınmış onay, kilitli ay (11 deneme) | Fonksiyonun Türkçe mesajı (ör. "Bu soru zaten cevaplanmış.") | Aynı ✅ |
| Fonksiyon denetimleri | Olmayan ayar, eksi değer, geçersiz e-posta / rol / belge türü, ileri tarihli çıkış, 11 saat sınırı, ters tarih aralığı, verisi olmayan gün, kilitli ay, olmayan okuyucu, geçersiz dosya zamanı / özeti | Fonksiyonun Türkçe mesajı | Aynı ✅ |
| **`dosya_yukle` başarılı yükleme** | Geçerli bir PDKS satırı | `UPDATE requires a WHERE clause` (`21000`) | **"UPDATE requires a WHERE clause Hiçbir satır kaydedilmedi."**: ham İngilizce (T-31, T-37) → T-31 düzeltildi, yükleme başarılı; ham mesaj sorunu (T-37) diğer hatalarda sürüyor |

**Kabul edilen 4 deneme:**
1. **`kayit_duzelt`, alan `vardiya_id`:** Ekranda bu seçenek yok, ama veritabanı İK'ya izin veriyor (`duzeltme_uygula` bu alanı destekliyor; PDF dökümünde "Vardiya" etiketi var). Tasarım; bulgu değil.
2. **`itiraz_gir` ve `vardiya_plani_gir`, Montaj amiri Bobinaj çalışanı için:** Montaj amiri Bobinaj'ın vekil amiri (`departman.vekil_amir_id`). Kabul doğru; "yetkisiz" seçimim yanlıştı. Vekilliğin tarihsiz olması T-14'te kayıtlı.
3. **`bolge_yetkisi_ver`, zaten verilmiş yetki:** Hata vermeden kabul ediyor ve hiçbir satır yazmıyor (geçmişe de yazmıyor). Ekran bu durumda zaten "Kaldır" gösterdiği için ancak eski bir sayfadan olur. Görüş.

**HTTP sırasında başka bir hataya takılan 3 deneme**, temiz durumda SQL'de tekrarlandı (`scratch/e5_maskeli.sql`):
- Geçersiz cevap → "Geçersiz cevap: belki" ✅
- 15 saat fazla mesai → "Günlük çalışma 1440 dakika olur; sınır 660 dakika (11 saat)." ✅
- Başka çalışanın kart no'su → `23505` → ekranda "… numaralı kart başka bir kayıtta kullanılıyor." ✅
- Uzun ve Türkçe harfli kart no **kabul edildi** ❌ (T-36)

## Gökalp için (ekran)

- **G1 · T-37:** Veri aktarımı formu (`aktarim-formu.tsx`) `dosya_yukle` hatasını ve özet okuma hatasını `error.message` ile ham gösteriyor. Diğer bütün yazmalar `rpcCagir`'in Türkçe mesajından geçiyor; bu form geçmiyor. Production'da da görünür, çünkü bu hata tarayıcıda oluşuyor.
- **G2 · T-38:** `calisan_ekle` ve `isten_cikis_gir` için ekran yok. İK yeni çalışanı ve işten çıkışı sistemden giremiyor; ikisi de README'de ✅ olarak geçiyor.
- **G3 · T-34:** Düzeltme penceresindeki "Bağlı itiraz" listesi o günün bütün itirazlarını gösteriyor, reddedilmişler dahil. Gün tek itirazlıysa o itiraz otomatik seçiliyor. Reddedilmiş bir itiraz farkında olmadan düzeltmeye bağlanabilir.
- **G4 (T-31 düzeltildi, sıra bunda):** Bir PDKS ve bir kapı dosyası ekrandan bir kez gerçekten yüklenmeli. HTTP'de dört kaynak yazılıyor (`scratch/e4_http.mjs`), ama tarayıcıdaki form denenmedi. Testler `psql` ile çalıştığı için bu yolu hiç görmüyor.

## Denemediklerim

- **Ekranın kendisi:** tarayıcıda Next.js sayfalarını açıp düğmelere basmadım. İstekleri supabase-js ile ekranın gönderdiği biçimde ürettim; Server Action katmanını (form okuma, `revalidatePath`) çalıştırmadım, yalnızca kodunu okudum.
- **Canlı:** T-31'in canlıda da olup olmadığını denemedim. Canlıya bağlanmak yasak. Yerelde `authenticator` rolü `session_preload_libraries = supautils, safeupdate` ile çalışıyor; canlı Supabase'in de aynı ayarla çalıştığını varsayıyorum, doğrulamadım. Canlıya 28 Kasım migration'ının (`20261128010000_dosya_yukle_duzeltmesi.sql`) uygulanıp uygulanmadığını da bilmiyorum.
- **Kapı / yemekhane / servis dosyası:** Testte yalnızca PDKS kaynağı denenmişti. T-31 düzeltilirken dördü de HTTP'den denendi: eski kodda dördü de 400 `21000`, yenisinde dördü de 200.
- **`ay_kilitle`'nin puantaj yazması:** Ekim'de gün kaydı yok. Kasım işlenmemiş günler yüzünden reddedildi. Puantaj yazımı Adım 12'de.
- **PDF / Excel / ERP indirmeleri:** yalnızca okuma; HTTP ile denemedim.
- **Oturum süresi ve yenileme:** `proxy.ts`'in süresi dolan oturumu tazelemesi denenmedi.
- **Eş zamanlı iki istek** (ör. aynı soruya iki amir aynı anda): denenmedi.

## Şüpheler

- **Parametre adı uyuşmazlığı canlıda farklı görünebilir:** `rpcCagir` `PGRST202`'yi "Migration canlıya uygulanmamış olabilir" diye çeviriyor. Bu da parametre adı hatasını gizleyebilir. Yerelde bu kod hiç görülmedi.
- **`statement_timeout`:** `authenticator` rolünde 8 sn. HTTP denemesinde 21 Kasım tek gün olarak hızlı işlendi; 2000 çalışanlık süre sorunu T-24'te.
- **`kart_tanimla`'daki `p_calisan_id` adresten geliyor:** Yetki veritabanında (yalnızca İK) olduğu için güvenlik açığı görmedim; ama İK başka bir çalışanın sayfasındayken adresi değiştirirse "yanlış kişiye kart" hatası olabilir. Denemedim.
