# Düzeltme Rehberi — Backend test bulguları

Bu rehber, backend testinde (14 adım) bulunan sorunların nasıl düzeltileceğini anlatır.
**Düzeltmeleri Yusuf yürütür; her PR'ı Fırat inceler ve birleştirir.**

---

## 1. Nereye bakacaksın

| Ne | Nerede |
|---|---|
| Bütün bulgular (T-01, T-02, …), kanıtları ve "Sade dille" açıklamaları | `docs/backend_test_raporu.md` |
| En başta: güncel özet tablo (kaç Kritik / Yüksek / Orta …) | `docs/backend_test_raporu.md` → ilk bölüm |
| **Düzeltme listesi** (kök neden grupları, sıra, kime düştüğü, tahmini süre) | `docs/backend_test_raporu.md` → "Düzeltme listesi" bölümü |
| Düzeltilmeyecekler | `docs/backend_test_raporu.md` → "Bilinen sınırlılıklar" |
| Proje kuralları (migration, güvenlik, git) | `CLAUDE.md` |
| Tablolar ve fonksiyonlar | `docs/veritabani.md` |
| Hangi fonksiyon hangi tabloya yazıyor | `docs/veri_akisi.md` |
| Ekranların çağırdığı fonksiyonlar | `docs/endpoint_testi.md` |
| Kurulum ve test komutları | `README.md` |
| İş takibi (kim hangi grubu aldı, durum) | GitHub → **Issues** (her kök neden grubu bir issue) |

> Rapordaki "scratch/…" dosyaları Fırat'ın bilgisayarındaki deneme betikleridir; GitHub'da yoktur.
> Gerekmez: rapordaki kanıt yeterli, Claude Code sorunu yerelde yeniden üretebilir.

---

## 2. Bulguyu okumak

Her bulgunun yapısı aynı:

- **Başlık:** `### T-39 · …` — numara ve kısa tanım
- **Adım · Önem:** hangi test adımında bulundu, ne kadar ciddi
- **Yer:** sorunun olduğu fonksiyon, tetikleyici ya da görünüm (son sürümün migration'ı)
- **Ne oldu / Ne olmalıydı:** gerçekleşen ve beklenen
- **Kanıt:** sorgu ve sonucu; sorunu nasıl üreteceğin
- **Sade dille:** sorunu birine anlatır gibi
- **Öneri:** nasıl düzeltilebileceği
- **Durum:** Açık / ✅ Düzeltildi — PR #..

Adımların sonundaki "Sonuç tablosu"nda ise her deneme için **Ne yaptım / Beklenen / Gerçekleşen** sütunları var.

**Önem sırası:** Kritik → Yüksek → Orta → Düşük → Görüş.
**Kural:** Yüksek'ler **26 Kasım'daki canlı kurulumdan önce** main'e girmiş olmalı.

---

## 3. Bir kez yapılır: kurulum

1. Repoyu çek: `gh repo clone frt-ekc/atlas_trafo`
2. README'deki "Gerekenler" kısmını kur (Node, Supabase CLI, psql).
3. Yerel veritabanını başlat: `supabase start`
4. Sıfırla (migration'lar + örnek veri): `supabase db reset`
5. Testleri çalıştır (README'deki komut). Hepsi "GEÇTİ" demeli. Demiyorsa başlamadan Fırat'a yaz.

**Yalnızca yerel veritabanında çalış.** Bağlantı adresi `127.0.0.1` ya da `localhost` değilse dur.

---

## 4. Her düzeltme için 8 adım

Bir seferde **tek bir grup** (ya da tek bulgu) düzeltilir.

1. **Seç:** Düzeltme listesindeki sıradaki grubu al. GitHub'daki issue'ya "Ben alıyorum" yaz.
2. **Güncelle:** `git checkout main && git pull`
3. **Dal aç:** `git checkout -b feature/<T-no>-kisa-ad` (ör. `feature/T39-soru-eskalasyon`)
4. **Claude Code'a ver:** Aşağıdaki şablon (bölüm 6).
5. **Migration:** Değişiklik **yeni** bir dosyadır: `supabase/migrations/YYYYMMDDHHMMSS_kisa_ad.sql`.
   Numara, main'deki son migration'dan **sonra** olmalı. Mevcut migration dosyaları **asla değiştirilmez.**
6. **Test:** Her düzeltme için `supabase/tests/` altına kalıcı test (sonda ROLLBACK).
   Test önce **eski kodda düşmeli**, düzeltmeden sonra **geçmeli.** Sonra `supabase db reset` + **bütün** testler.
7. **Raporu işaretle:** `docs/backend_test_raporu.md`'de ilgili bulgunun altına:
   `**Durum:** ✅ Düzeltildi — PR #.. (migration: …, test: …)`
8. **PR aç:** Açıklamada bölüm 7'deki şablon. Fırat'a haber ver. **Birleştirmeyi Fırat yapar.**

Birleşmeden sonra bir sonraki gruba geç (yeniden 2. adımdan).

---

## 5. Kurallar (CLAUDE.md'den, asla ihlal etme)

- Canlı veritabanına (Supabase) **hiçbir komut çalıştırma.** Canlıya gönderimi yalnızca Fırat yapar.
- `.env` ve `.env.*` dosyalarını açma, yazdırma, commit etme.
- `main`'e ve başkasının dalına push yapma.
- Mevcut migration'ları değiştirme; her değişiklik yeni dosya.
- Değiştirilemez tablolar (`ham_okutma`, `kanit_kaydi`, `aktarim`, `okutma_isareti`, `duzeltme`, `puantaj_satiri`) değiştirilemez ve silinemez kalmalı.
- `gun_kaydi` yalnızca `pdks.duzeltme_uygula(...)` ile değişir.
- Çalışan aleyhine kararlar (devamsızlık, itiraz reddi, kart paylaşımı) yalnızca İK'da kalmalı.
- Yeni tabloda RLS açılır ve rol bazlı politika yazılır.
- Repoda yalnızca sahte veri.

**Migration çakışması:** İki PR aynı anda açıksa ve biri birleştiyse, diğerinin dalını main'e göre güncelle
(`git pull origin main` ya da rebase) ve migration numarasının hâlâ en sonda olduğunu kontrol et.

---

## 6. Claude Code prompt şablonu

```
Atlas Trafo PDKS'de bir test bulgusunu düzeltiyoruz. Önce şunları oku:
- CLAUDE.md
- docs/duzeltme_rehberi.md
- docs/backend_test_raporu.md'de şu bulgular: <T-xx, T-yy> ve "Düzeltme listesi"nde bu grubun satırı
Kurallar: canlıya bağlanma, .env dosyalarını okuma, mevcut migration'ları değiştirme.
Yerel adresleri ve anahtarları `supabase status` ile al; adres 127.0.0.1/localhost değilse dur.

1. Sorunu önce yerelde yeniden üret ve bana göster (düzeltmeden önce).
2. Düzeltme planını 3-5 maddeyle anlat, onayımı bekle.
3. Onaydan sonra: yeni migration (main'deki son numaradan sonra) + supabase/tests/ altına kalıcı test.
   Test eski kodda düşmeli, yeni kodda geçmeli.
4. supabase db reset + bütün testleri çalıştır, sonucu göster.
5. docs/backend_test_raporu.md'de bulguların altına "Durum: ✅ Düzeltildi" satırını ekle.
6. Ne değiştiğini (dosya listesi + önemli satırlar) sade dille göster. Commit etme, onayımı bekle.
```

---

## 7. PR açıklama şablonu

```
## Düzeltilen bulgular
- T-xx: <kısa tanım>
- T-yy: <kısa tanım>

## Ne değişti
- Migration: supabase/migrations/<dosya>.sql — <1-2 cümle>
- Test: supabase/tests/<dosya>.sql — <ne sınıyor>

## Nasıl doğrulandı
- Test eski kodda düştü, yeni kodda geçti.
- supabase db reset + bütün testler: GEÇTİ (<sayı> dosya)

## Etki / risk
- <ekranı etkiliyor mu? Gökalp'in yapması gereken bir şey var mı?>
```

---

## 8. Kime düşer

| Düşen yer | Ne yapılır |
|---|---|
| **Backend / veritabanı** | Bu rehberle Yusuf düzeltir |
| **Frontend (ekran)** | GitHub'da Gökalp'e issue aç; bulgu numarasını yaz |
| **Rapor metni / bilinen sınırlılık** | Mehmet'e ilet (rapora girecek cümle) |

---

## 9. Takvim

| Ne | Ne zaman |
|---|---|
| Yüksek önemli gruplar | 25 Kasım'a kadar main'de |
| Endpoint testinin HTTP kısmı yeniden | 25 Kasım |
| Canlı yeniden kurulum (Fırat) | 26 Kasım |
| Orta / Düşük (zaman kalırsa) | 26 Kasım – 3 Aralık |
| Teslim | 7 Aralık |

Takıldığın her yerde Fırat'a yaz. Emin olmadığın bir kural değişikliği varsa önce sor, sonra yap.
