# Atlas Trafo PDKS Kayıt Düzeltme Sistemi

Bilişim Sistemleri Analizi ve Tasarımı dersi ekip projesi.
**Ekip:** Mehmet · Gökalp · Yusuf · Fırat · **Teslim:** 07.12.2026

> Gerçek bir şirket için tasarlandı. Repoda **yalnızca sahte (sentetik) veri** bulunur; gerçek Atlas Trafo verisi asla yüklenmez.

---

## 1. Ne yapar?

Atlas Trafo (İzmir, ~2000 çalışan, gece vardiyası dahil vardiyalı üretim) kartlı PDKS kullanıyor. Kart okutmayı unutma, mükerrer okutma, okuyucu arızası, gece vardiyası gibi nedenlerle kayıtlar hatalı oluyor ve İK bunları ay sonunda Excel'de elle düzeltiyor.

Bu sistem mevcut PDKS'yi **değiştirmez**, kayıtlarını alıp yanında çalışır:

1. PDKS, kapı, yemekhane ve servis kayıtlarını içe alır. Ham kayda hiç dokunmaz.
2. Hatalı ve eksik kayıtları bulur.
3. **Kanıt varsa** (kapı / yemekhane / servis kaydı) kaydı kendisi düzeltir.
4. **Kanıt yoksa** ertesi sabah amire sorar. Cevapsız soru 3 gün sonra üst amire ve İK'ya gider.
5. Her düzeltme kim / ne zaman / eski-yeni değer / gerekçe / dayanak ile **silinemeyen** bir tabloya yazılır.
6. Fazla mesaide yazılı onay, günlük 11 saat ve yıllık 270 saat sınırlarını denetler.
7. Ay sonunda İK ayı kilitler; bordroya hazır puantaj (gün ve dakika, NÇ / FM50 / FM100 / izin kodları) Excel olarak, ERP'ye aktarılacak icmal CSV ve XML olarak alınır.

### Temel kararlar
- **Çalışan aleyhine her karar İK'dadır** (KVKK m.11): devamsızlık, itirazın reddi, kart paylaşımı, plansız fazla mesai. Sistem en fazla "şüphe" ya da "uyarı" üretir.
- Personel PDKS kartıyla tanınır.
- Çalışan isterse İK, sistemden kayıt dökümünü PDF olarak verir; itirazı amir ya da İK sisteme girer.
- **Kart unutana:** güvenlikten zimmetli **geçici kart**; o da yoksa amir onayı.
- Kilitli ay geri açılamaz; sonradan gelen düzeltme sonraki aya "fark satırı" olur.

Sorun–tablo eşlemesi (17 sorun): [docs/veritabani.md](docs/veritabani.md).

---

## 2. Teknoloji

| Katman | Teknoloji | Not |
|---|---|---|
| Veritabanı | **Supabase (PostgreSQL)** | `pdks` şeması, 35 tablo |
| İş kuralları | PostgreSQL fonksiyonları ve trigger'lar | Gece işi, düzeltme, görevler ayrılığı, ay kilidi veritabanının içinde çalışır; ekran atlansa bile kural delinemez |
| Giriş ve yetki | **Supabase Auth + RLS** | Roller: `amir`, `ik`, `guvenlik`, `yonetici`, `isg`, `admin`. Her kullanıcı yalnızca rolünün izin verdiği satırları görür |
| Frontend | **Next.js + TypeScript** | Tailwind CSS + shadcn/ui |
| Veri bağlantısı | supabase-js | Veritabanı fonksiyonları RPC ile çağrılır |
| CSV okuma | Papa Parse | PDKS, kapı, yemekhane, servis dosyaları |
| PDF döküm | @react-pdf/renderer | Çalışanın kayıt dökümü |
| Excel çıktısı | SheetJS | Bordroya hazır puantaj |
| Gece işi zamanlama | pg_cron | Her gece kendiliğinden çalışır; demoda ekrandaki butonla da tetiklenir |
| Test | SQL testleri (`supabase/tests`) | Testler sonda ROLLBACK ile iz bırakmaz |
| Raporlama | Yönetici paneli + Excel / CSV / PDF çıktıları | Ayrı raporlama aracı kullanılmaz |
| Yayın | Vercel | |
| Kod | GitHub | |

---

## 3. Klasör yapısı

```
atlas_trafo/
├─ README.md
├─ CLAUDE.md                 # Claude Code için proje kuralları
├─ .env.example              # ortam değişkenleri şablonu (değersiz)
├─ docs/
│  ├─ veritabani.md          # veritabanı dokümanı ve ER diyagramı
│  ├─ ornek_veri.md          # örnek verideki kişiler, demo hesapları ve senaryolar
│  └─ ekran_fonksiyonlari.md # ekranların çağırdığı RPC fonksiyonları (parametreler, örnekler)
├─ supabase/
│  ├─ config.toml            # Supabase CLI ayarları
│  ├─ migrations/            # sıra numaralı veritabanı değişiklikleri (mevcutlar asla değiştirilmez)
│  ├─ seed.sql               # örnek (sahte) veri: Kasım 2026
│  ├─ scripts/               # canlı için salt-okunur kontrol sorguları (SQL Editor'da çalıştırılır)
│  └─ tests/                 # SQL kural testleri
└─ .github/workflows/        # PR yetki koruması
```

Next.js uygulaması eklendiğinde planlanan yapı:

```
├─ package.json
├─ app/                      # sayfalar: giriş, amir, İK, güvenlik
├─ components/               # arayüz bileşenleri (shadcn/ui)
└─ lib/supabase/             # tarayıcı ve sunucu için Supabase istemcileri
```

---

## 4. Veritabanı

`pdks` şemasında **35 tablo** (temel 24 + fazla mesai 2 + geçici kart 2 + puantaj kuralları 3 + İSG 4). Ayrıntı ve ER diyagramı: [docs/veritabani.md](docs/veritabani.md).

| Grup | Tablolar |
|---|---|
| Kişiler ve organizasyon | kullanici (amir, İK, güvenlik, yönetici, İSG, admin), departman (mavi / beyaz yaka), calisan, kart, gecici_kart, gecici_kart_zimmet |
| Vardiya, izin, ayar | vardiya_tanim, vardiya_plani, izin, saatlik_izin, resmi_tatil, ayar, ayar_gecmisi |
| Ham veri (değiştirilemez) | aktarim, okuyucu, ham_okutma, kanit_kaydi, okutma_isareti |
| İSG | bolge, bolge_yetkisi, bolge_yetkisi_gecmisi, isg_belge (yalnızca geçerlilik tarihi) |
| İşleme | gece_isi, ariza, uyari |
| Gün, karar, düzeltme, dönem | gun_kaydi, amir_sorusu, itiraz, duzeltme, donem, puantaj_satiri, puantaj_kalemi |
| Fazla mesai | fazla_mesai_onayi, fazla_mesai_plani, fazla_mesai_inceleme (onaysız fazla mesai havuzu) |

**Veritabanının zorladığı kurallar:** ham kayıt, `duzeltme` ve `puantaj_satiri` değiştirilemez ve silinemez · `gun_kaydi` yalnızca `pdks.duzeltme_uygula()` ile değişir · devamsızlık ve itiraz reddi yalnızca İK · kilitli ay açılamaz · kimse kendi kaydında işlem yapamaz (görevler ayrılığı) · her kullanıcı yalnızca rolünün izin verdiği satırları görür (RLS).

| Migration | İçerik |
|---|---|
| `20261114000100_tablolar.sql` | Şema ve 24 tablo |
| `20261114000200_kurallar.sql` | Trigger'lar, fonksiyonlar, görünümler |
| `20261114000300_roller_ve_yetkiler.sql` | `pdks_uygulama` ve `pdks_gece_isi` rolleri (20261118030000'de kaldırıldı) |
| `20261114000400_varsayilan_ayarlar.sql` | Varsayılan ayarlar ve 4 vardiya |
| `20261115000500_fazla_mesai.sql` | Yazılı onay, plan, 11 / 270 saat sınırı |
| `20261117010000_kiosk_kaldir.sql` | Şema düzenlemesi: PIN alanları ve ilgili fonksiyonlar |
| `20261117020000_gecici_kart.sql` | Geçici kart ve zimmet, güvenlik rolü, geçici kart uyarıları |
| `20261117030000_kart_paylasimi.sql` | Kart paylaşımı şüphe kuralı |
| `20261118010000_sema_temizligi.sql` | Tablo açıklamaları ve ayar geçmişi düzenlemesi |
| `20261118020000_gorevler_ayriligi.sql` | Kullanıcı ↔ çalışan bağı, "kimse kendi kaydında işlem yapamaz" kuralları |
| `20261118030000_giris_ve_yetki.sql` | Supabase Auth bağlantısı, RLS politikaları, görünüm yetkileri |
| `20261118040000_ayar_al_yetkisi.sql` | `ayar_al()` sahibinin yetkisiyle çalışır, `authenticated` çalıştırabilir |
| `20261119010000_ekran_fonksiyonlari.sql` | Ekranların çağırdığı 22 RPC fonksiyonu (amir, güvenlik, İK) |
| `20261120010000_gece_isi.sql` | Gece işi, demo düğmesi, pg_cron zamanlaması |
| `20261121010000_puantaj.sql` | Ay kilidinde puantaj (`normal` + `fark` satırları) |
| `20261122010000_izin_iptal_ve_departman_ozeti.sql` | İzin iptali, yönetici paneli için departman özeti |
| `20261123010000_puantaj_kurallari.sql` | Tolerans 10/5 dk ve yuvarlama, onaysız fazla mesai havuzu, FM50 / FM100, gece çalışması, saatlik izin, puantaj kodları |
| `20261124010000_vardiya_kurallari.sql` | Yeni vardiyalar, esnek mesai, otomatik vardiya tanıma, mola (m.68) |
| `20261125010000_organizasyon_ve_roller.sql` | Mavi / beyaz yaka, `isg` ve `admin` rolleri, kullanıcı ve ayar yönetimi (admin) |
| `20261126010000_isg.sql` | Bölge yetkisi, İSG eğitimi / sağlık muayenesi geçerlilik tarihleri ve uyarıları (kapı kilitlenmez) |
| `20261127010000_bolge_yetkisi_izi.sql` | Bölge yetkisinin verilme / kaldırılma izi |
| `20261127020000_erp_aktarim.sql` | ERP aktarımı: kilitli ayın puantaj kodları (`v_puantaj_aktarim`) |
| `20261128010000_dosya_yukle_duzeltmesi.sql` | `dosya_yukle`: dosyanın SHA-256 özeti, doğru satır sayısı, satır satır sunucu denetimi |
| `20261129010000_esnek_kanit.sql` | Esnek mesaide PDKS girişi eksikse kanıt saati (kapı / servis + yürüme payı) doğrudan yazılır |
| `20261129020000_zimmet_cakisma_mesaji.sql` | Geçici kart zimmeti çakışınca hata, çakışan zimmeti söyler (kart, kişi, tarih, saat) |

---

## 5. Yerelde çalıştırma

**Gerekenler:** Node.js 20 veya üstü, npm, [Supabase CLI](https://supabase.com/docs/guides/cli), psql.

```bash
# 1) Repoyu indir
git clone https://github.com/frt-ekc/atlas_trafo.git
cd atlas_trafo

# 2) Ortam değişkenleri
cp .env.example .env.local          # değerleri Supabase > Project Settings > API Keys'ten doldurun

# 3) Veritabanı (tek kişi, bir kez)
supabase link --project-ref <proje-kodu>
supabase db push                    # supabase/migrations altındaki dosyaları sırayla kurar
psql "$SUPABASE_DB_URL" -f supabase/seed.sql   # örnek veri (bkz. docs/ornek_veri.md)

# 4) Uygulama (Next.js iskeleti eklendikten sonra)
npm install
npm run dev                         # http://localhost:3000
```

**Testler:** `supabase/tests` altındaki her dosya `psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f <dosya>` ile çalıştırılır; sonda "... GEÇTİ" yazmalı. Testler veritabanında iz bırakmaz ve örnek veri yüklü olsa da olmasa da çalışır. `ornek_veri_testi.sql` örnek verinin yüklü olmasını bekler.

---

## 6. Ortam değişkenleri

`.env.example` dosyası `.env.local` olarak kopyalanır ve doldurulur. `.env.local` GitHub'a gitmez.

| Değişken | Ne işe yarar | Nerede kullanılır |
|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | Supabase proje adresi | Tarayıcı ve sunucu |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | Yayınlanabilir anahtar; neyin görüneceğini RLS belirler | Tarayıcı ve sunucu |
| `SUPABASE_SECRET_KEY` | Gizli anahtar; RLS'yi atlar. İK'nın kullanıcı hesabı açması gibi sunucu işlerinde | **Yalnızca sunucu** (`NEXT_PUBLIC_` öneki almaz) |
| `SUPABASE_DB_URL` | Veritabanına doğrudan bağlantı | Yalnızca geliştirici bilgisayarı (testler) |

Vercel'de ilk üç değişken **Project Settings → Environment Variables** bölümüne girilir.

---

## 7. Durum ve yol haritası

| Parça | Durum |
|---|---|
| Veritabanı şeması ve kurallar (27 test) | ✅ |
| Fazla mesai (34 test) | ✅ |
| Geçici kart ve zimmet (39 test, kart paylaşımıyla birlikte) | ✅ |
| Kart paylaşımı şüphe kuralı (testli) | ✅ |
| Giriş ve yetki: Supabase Auth bağlantısı, RLS politikaları (29 test) | ✅ |
| Görevler ayrılığı: kimse kendi kaydında işlem yapamaz (20 test) | ✅ |
| Ekran fonksiyonları (RPC): soru cevaplama, itiraz, geçici kart, İK kararları, dosya yükleme (42 test) | ✅ |
| Next.js iskeleti (TypeScript, Tailwind CSS, shadcn/ui, supabase-js) | ✅ |
| Fiili fazla mesai uyarıları: günlük 11 saat (gece işi), yıllık 270 saat (havuz onayında) | ✅ |
| Onaysız fazla mesai havuzu: plansız çalışma İK kararına kadar puantaja girmez | ✅ |
| Saatlik izin (vizite dahil) | ✅ |
| Tolerans 10 / 5 dk ve yuvarlama ayarı | ✅ |
| FM50 / FM100, gece çalışması (m.69), puantaj kodları ve kalemleri (68 test) | ✅ |
| Yeni vardiyalar (08-16, 16-24, 00-08, 08:30-18:00), esnek mesai, otomatik vardiya tanıma, mola (28 test) | ✅ |
| Esnek mesaide PDKS girişi eksikse amire soru yerine kanıt saatini (kapı / servis + yürüme payı) doğrudan yazmak | ✅ |
| Geçici kart zimmeti çakışma hatasında çakışan zimmeti göstermek | ✅ |
| Örnek veri: Kasım 2026, 19 departman, 76 çalışan, 32 senaryo; 1 Aralık sabah dosyaları ve 7 Aralık demo planı (58 kontrol) | ✅ |
| Mavi / beyaz yaka, İSG uzmanı ve sistem yöneticisi rolleri, kullanıcı ve ayar yönetimi (35 test) | ✅ |
| İSG: bölge yetkisi (verilme / kaldırılma izi dahil), eğitim / muayene geçerliliği, yalnızca uyarı (30 test) | ✅ |
| CSV içe aktarma (Papa Parse): ekranda denetim ve Yükle düğmesi `dosya_yukle`'ye bağlı (24 test) | ✅ |
| Gece işi fonksiyonu (işaretleme → günlük kayıt → kanıtla düzeltme → amire soru → uyarı) ve pg_cron zamanlaması | ✅ |
| Amir ekranı (sorular, itiraz girişi) | ✅ |
| İK ekranı (uyarılar, kararlar, ay kilidi) | ✅ |
| Güvenlik ekranı (geçici kart ver / iade al) | ✅ |
| Bordro Excel çıktısı (SheetJS; FM50 / FM100 / gece / mola sütunları ve kilitli ayda "Puantaj kodları" sayfası), çalışan PDF dökümü (@react-pdf/renderer) | ✅ |
| ERP aktarımı: kilitli ayın puantaj icmali CSV ve XML (sicil, dönem, kod, gün, dakika; 9 test) | ✅ |
| İşe giriş ve işten çıkış (`calisan_ekle`, `isten_cikis_gir`); gece işi çalışanı tarihe göre süzer (35 test) | ✅ |
| Ay kilidi düzeltmeleri ve anında hesap: kilit öncesi hesap, işlenmemiş gün kontrolü, İK'ya eskale soru, onay bekleyen plan, kilit özeti (39 test, örnek veriyle uçtan uca) | ✅ |
| Vercel'de yayın | ⬜ Yapılacak |
| Rapor diyagramları (Use Case, DFD, AS-IS, TO-BE) | ⬜ Yapılacak |

---

## 8. Çalışma kuralları

- `main` korumalıdır; doğrudan push yapılmaz. PR'ları birleştirme, kapatma, etiketleme ve atama yalnızca ekip liderindedir (otomasyonla korunur).
- Her iş için dal: `feature/<issue-no>-kisa-ad`. Her iş bir issue olarak açılır.
- Her PR en az 1 onay alır.
- Commit mesajları Türkçe ve kısa: `feat(db): ...`, `fix: ...`, `docs: ...`, `test: ...`.
- `supabase/migrations` altındaki mevcut dosyalar **asla değiştirilmez**; her değişiklik yeni numaralı dosyadır ve testiyle gelir.
- Gizli bilgiler (şifre, anahtar, bağlantı adresi) koda, loglara, ekran görüntülerine yazılmaz; yalnızca `.env.local` dosyasında ve Vercel ortam değişkenlerinde tutulur.
- `SUPABASE_SECRET_KEY` yalnızca sunucu tarafı kodda kullanılır, tarayıcıya gönderilmez.
- Her tabloda RLS açıktır; yetki kontrolü veritabanında yapılır.
- Kullanıcı girdisi SQL metnine eklenmez; veritabanına supabase-js sorgu oluşturucusu ve RPC ile erişilir.
- Ekran görüntülerinde çalışan adları ve sicil numaraları bulanıklaştırılır.
