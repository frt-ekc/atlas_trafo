# Backend Test Raporu — Atlas Trafo PDKS

Plan: `BACKEND_TEST_PLANI.md` · Ortam: yalnızca yerel Supabase (`supabase db reset`), canlıya bağlanılmadı.
Deneme sorguları ve ham çıktılar `scratch/` klasöründe (git'e girmez).

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
- **Durum:** Açık

### T-05 · README'de işe giriş / işten çıkış test sayısı yanlış
- **Adım:** 1 · **Önem:** Düşük
- **Yer:** `README.md`, ilerleme tablosu ("İşe giriş ve işten çıkış … (35 test)")
- **Ne oldu:** `ise_giris_cikis_testi.sql` 33 kontrol çalıştırıyor. Dosyada geçen 35 `test.dogrula(` / `test.hata(` eşleşmesinin 2'si yardımcı fonksiyonların tanımı. Sayı PR #30'da yanlış verilmişti.
- **Ne olmalıydı:** 33.
- **Kanıt:** Örnek veriyle çalıştırmada `GEÇTİ` satırı sayısı 33; diğer 20 dosyanın README'deki sayıları gerçek sayılarla aynı.
- **Sade dille:** Belgede yazan test sayısı gerçekte olandan 2 fazla. Sistemi etkilemiyor, ama rapordaki rakamlar güvenilir olmalı.
- **Öneri:** README'de 35 → 33.
- **Durum:** Açık

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
- **Durum:** Açık

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
- **Durum:** Açık

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
- **Durum:** Açık

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
- **Durum:** Açık

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
- **Durum:** Açık

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
- **Adım:** 6 · **Önem:** Orta
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
- **Durum:** Açık

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
- **Durum:** Düzeltildi (yerelde; birleştirme ve canlıya uygulama Fırat'ta)

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
- **Durum:** Açık

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
- **Durum:** Açık

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
- **Durum:** Açık

### T-38 · İşe giriş ve işten çıkış için ekran yok
- **Adım:** Endpoint · **Önem:** Orta (Gökalp için)
- **Yer:** `calisan_ekle`, `isten_cikis_gir` (`20261130010000_ise_giris_cikis.sql`); `app/` altında çağıran yok.
- **Ne oldu:** İki fonksiyon veritabanında var, yetkileri doğru (yalnızca İK; HTTP'de çalıştı, admin reddedildi). Ama hiçbir ekran onları çağırmıyor. README'de işe giriş / işten çıkış ✅.
- **Ne olmalıydı:** Çalışanlar sayfasında "Çalışan ekle" ve çalışan sayfasında "İşten çıkış" pencereleri.
- **Kanıt:** Ekranda `rpcCagir` / `.rpc(` geçen 33 çağrı listesi; ikisi yok (`docs/endpoint_testi.md` madde 1).
- **Sade dille:** İK yeni başlayan birini ya da ayrılan birini sisteme giremez; bunu ancak veritabanından elle yapabiliriz. Demoda bu akış gösterilemez.
- **Öneri:** Gökalp: G2. Parametreler ve mesajlar `docs/ekran_fonksiyonlari.md` satır 98–99'da hazır.
- **Durum:** Açık

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
