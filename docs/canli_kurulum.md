# Canlı veritabanını yeniden kurma (atlas-pdks)

Canlı veritabanı (Supabase projesi **atlas-pdks**) **seed'siz** kurulur: yapı `supabase/canli/kurulum.sql`'den, kişiler ve okutmalar `scripts/sentetik_veri.mjs --kurulum` çıktısından gelir. Bütün veri sahtedir. `supabase/seed.sql` canlıya yüklenmez; yalnızca yerel testler içindir.

**Kurallar**
- Her adımı **Fırat** onaylar ve çalıştırır.
- Bağlantı adresi, şifre ve anahtar bu belgeye, koda ya da sohbete yazılmaz. `psql` adımlarında adres yalnızca Fırat'ın terminalinde `CANLI_DB_URL` değişkenindedir.
- Silinen yalnızca `pdks` şeması ve migration kaydıdır. **`auth.users` (giriş hesapları) korunur**, 25 hesap yeniden açılmaz.
- **Kurulum gününden ileri tarihli okutma yüklenmez.** `--bit` en çok kurulumdan bir önceki gündür. Vardiya planları her kurulumda 7 Aralık 2026 dahil gelir.
- Hiçbir ay canlıda kilitlenmez (bkz. `docs/demo_akisi.md`).
- **Demo:** `docs/demo_akisi.md` ve `demo/` CSV'leri seed'in kişilerine (4 haneli sicil, `K1003` gibi kartlar) göre yazılmıştır. Bu kurulumdan sonra demo dosyaları ve akışı yeni sicil ve kartlara göre yenilenmeden kullanılamaz. 7 Aralık'ın planları hazırdır.

## 0. Hazırlık
- `main` güncel olmalı; yerelde bütün testler seed ile geçmiş olmalı.
- Gökalp'e haber verilir: kurulum boyunca ekranlar çalışmaz.
- Veri üretilir (repo kökünde; çıktı `veri/kurulum/`, git'e girmez, her seferinde aynıdır):

İlk kurulum (30 Kasım):

```bash
node scripts/sentetik_veri.mjs --kurulum --bas 2026-10-01 --bit 2026-11-29
```

İkinci kurulum (6 Aralık):

```bash
node scripts/sentetik_veri.mjs --kurulum --bas 2026-10-01 --bit 2026-12-05
```

Aynı tohumla iki kurulumun ortak günleri birebir aynıdır (okutma dosyaları, plan, kadro). `--bit 2026-12-05` 6 Aralık'ın (Pazar, planlı vardiya yok) hiçbir okutmasını içermez. 7 Aralık 00-08 vardiyasının 6 Aralık 23:50 civarındaki girişleri de yüklenmez; demo günü işlenecekse bu girişler demo dosyalarında olmalıdır.

## 1. Yedek
```bash
mkdir -p ~/atlas_yedek/$(date +%F)
```

```bash
supabase db dump --remote --schema pdks -f ~/atlas_yedek/$(date +%F)/pdks_sema.sql
```

```bash
supabase db dump --remote --data-only --schema pdks -f ~/atlas_yedek/$(date +%F)/veri.sql
```

```bash
supabase db dump --remote --data-only --schema supabase_migrations -f ~/atlas_yedek/$(date +%F)/gecmis.sql
```

```bash
supabase db dump --remote --data-only --schema auth -f ~/atlas_yedek/$(date +%F)/auth_veri.sql
```

- Her komutun çıktısında `Target: project atlas-pdks … · production` yazısını görmeden devam edilmez.
- `auth_veri.sql` şifre özetleri içerir. Kurulum doğrulandıktan birkaç gün sonra silinir; diğerleri teslime kadar saklanır.

## 2. Cron kapalı mı? (SQL Editor)
Gece işi kurulum sırasında kendiliğinden çalışmamalı:

```sql
select jobid, jobname, active from cron.job where jobname = 'pdks-gece-isi';   -- active = false olmalı
-- açıksa:
select cron.alter_job(jobid, active => false) from cron.job where jobname = 'pdks-gece-isi';
```

## 3. pdks şemasını silme ve migration kaydını temizleme (SQL Editor)
```sql
drop schema pdks cascade;
delete from supabase_migrations.schema_migrations;
```

`auth` ve `cron` şemalarına dokunulmaz.

## 4. Migration'lar
```bash
supabase db push --remote --dry-run
```

Liste `supabase/migrations/` altındaki dosyaların hepsini (şu an 58) göstermeli. Sonra:

```bash
supabase db push --remote
```

Migration'lar gece işini yeniden zamanlar: **2. adımdaki sorgu bir kez daha çalıştırılır, açılmışsa kapatılır.**

## 5. Yapı: kurulum.sql
`supabase/canli/kurulum.sql` (SQL Editor'e yapıştırılır ya da psql ile çalıştırılır). Boş olmayan veritabanında yazmadan durur.

```bash
psql "$CANLI_DB_URL" -v ON_ERROR_STOP=1 -f supabase/canli/kurulum.sql
```

19 departman, 15 okuyucu, 2 bölge, 2026 resmi tatilleri. Çalışan ve kullanıcı yoktur.

## 6. Sentetik veri (psql, repo kökünden)
Dosyalar `\copy` ile okunduğu için SQL Editor'de çalışmaz.

```bash
psql "$CANLI_DB_URL" -v ON_ERROR_STOP=1 -f veri/kurulum/yukle.sql
```

Beklenen son iki satır:

```
Sentetik veri yüklendi: 188 çalışan, 8370 plan, 43242 okutma.      (30 Kasım kurulumu; 6 Aralık: 48423 okutma)
Kurulum kontrolü tamam: 25 kullanıcı, 2 aktif İK, 1 aktif admin, 19 departman amirli.
```

- Tek işlemdir: kontrol bloğu (en az 2 aktif İK, 1 aktif admin, 25 kullanıcı ve hepsi aktif çalışana bağlı, her departmanın aktif amiri, sicil / kart tekrarı) tutmazsa hiçbir şey yazılmaz.
- İK ve admin hesapları doğrudan aktif açılır; rol onayı (T-72) sonraki değişiklikler içindir.
- Bölge yetkileri de burada girilir (yetkiyi veren İSG uzmanı zorunlu alandır).

## 7. İstatistikler
```sql
analyze;
```

## 8. Gece işi, gün gün (psql)
Her gün ayrı komut olarak çalışır; tek komutta bütün günler zaman aşımına takılabilir. Bitiş, kurulumun `--bit` günüdür.

İlk kurulum (30 Kasım):

```bash
psql "$CANLI_DB_URL" -v ON_ERROR_STOP=1 -c '\timing on' -f - <<'SQL'
select format('select %L as gun, pdks.gece_isi_calistir(%L)', g::date, g::date)
from generate_series(date '2026-10-01', date '2026-11-29', interval '1 day') g \gexec
select durum, count(*) from pdks.gece_isi group by durum;
SQL
```

İkinci kurulum (6 Aralık):

```bash
psql "$CANLI_DB_URL" -v ON_ERROR_STOP=1 -c '\timing on' -f - <<'SQL'
select format('select %L as gun, pdks.gece_isi_calistir(%L)', g::date, g::date)
from generate_series(date '2026-10-01', date '2026-12-05', interval '1 day') g \gexec
select durum, count(*) from pdks.gece_isi group by durum;
SQL
```

Son sorgu yalnızca `basarili | 60` (ikinci kurulumda `66`) göstermeli. Yerelde 60 gün 94 sn (en uzun gün 3,8 sn), 66 gün 112 sn (en uzun gün 3,7 sn) sürdü.

## 9. Şema yenileme
```sql
notify pgrst, 'reload schema';
```

## 10. Auth hesaplarını e-postaya göre bağlama (SQL Editor)
```sql
update pdks.kullanici k set auth_kullanici_id = u.id
from auth.users u
where lower(u.email) = lower(k.eposta) and k.auth_kullanici_id is null;
select count(*) from pdks.kullanici where auth_kullanici_id is null;   -- 0 olmalı
```

## 11. Doğrulama (yalnızca okur)
1. `supabase/scripts/canli_migration_kontrol.sql`: her satırda `kayitli = evet` ve `nesne = evet` (bilinen iki "—" hariç: `roller_ve_yetkiler`, `sema_temizligi`).
2. Beklenen sayılar (yerel denemeden, tohum 20261001):

```sql
select (select count(*) from pdks.calisan)                                       as calisan,
       (select count(*) from pdks.kullanici)                                     as kullanici,
       (select count(*) from pdks.kullanici where auth_kullanici_id is not null) as bagli_hesap,
       (select count(*) from pdks.fazla_mesai_onayi)                             as yazili_onay,
       (select count(*) from pdks.gun_kaydi)                                     as gun_kaydi,
       (select count(*) from pdks.duzeltme)                                      as duzeltme,
       (select count(*) from pdks.amir_sorusu)                                   as soru,
       (select count(*) from pdks.fazla_mesai_inceleme)                          as havuz,
       (select count(*) from pdks.uyari)                                         as uyari,
       (select count(*) from pdks.donem where durum = 'kilitli')                 as kilitli_ay;
```

| | 30 Kasım kurulumu (`--bit 2026-11-29`) | 6 Aralık kurulumu (`--bit 2026-12-05`) |
|---|---:|---:|
| Çalışan (aktif) | 188 (178) | 188 (178) |
| Kullanıcı / bağlı hesap | 25 / 25 | 25 / 25 |
| Yazılı fazla mesai onayı | 164 | 164 |
| Gün kaydı | 7302 | 8192 |
| Düzeltme | 195 | 213 |
| Soru | 35 | 39 |
| Havuz | 37 | 41 |
| Uyarı | 115 | 123 |
| Kilitli ay | 0 | 0 |

| Ay | Gün kaydı | Düzeltme | Soru | Havuz |
|---|---:|---:|---:|---:|
| Ekim 2026 | 3742 | 88 | 21 | 18 |
| Kasım 2026 (29'una kadar) | 3560 | 107 | 14 | 19 |
| Kasım 2026 (tamamı, ikinci kurulum) | 3738 | 111 | 15 | 19 |
| 1–5 Aralık 2026 (ikinci kurulum) | 712 | 14 | 3 | 4 |

İleri tarihli okutma olmamalı (sonuç en çok `--bit` günü; yerelde 29 Kasım 23:57 ve 5 Aralık 06:16):

```sql
select max(okutma_zamani at time zone 'Europe/Istanbul')
from (select okutma_zamani from pdks.ham_okutma union all select okutma_zamani from pdks.kanit_kaydi) x;
```

`--bit` gününe kadar işlenmemiş planlı gün 0 olmalı (sonrası planlıdır, henüz işlenmez):

```sql
select count(*) from pdks.vardiya_plani vp
where vp.tarih <= (select max(islenen_gun) from pdks.gece_isi)
  and not exists (select 1 from pdks.gun_kaydi g where g.calisan_id = vp.calisan_id and g.is_gunu = vp.tarih);
```

`supabase/scripts/canli_veri_durumu.sql` seed sicillerini tanır; bu kurulumda bütün çalışanlar "örnek veri dışında" görünür.

3. Ekranda birkaç hesapla giriş: İK uzmanı, bir amir, güvenlik, İSG uzmanı, yönetici, admin.

## 12. Son ayarlar
- **Supabase → Authentication → Sign In / Providers → "Allow new users to sign up" kapalı** (`supabase/config.toml` yalnızca yereli etkiler).
- **Authentication → URL Configuration → Site URL** canlı Vercel adresi.
- **Vercel:** güncel `main` yayında; fonksiyon bölgesi Supabase'e yakın (Frankfurt, `fra1`); ortam değişkenleri tanımlı.

## Bir şey ters giderse
**Ana yol: kurulumu baştan çalıştırmak.** Veri sentetiktir ve aynı tohumla birebir aynı çıkar; kaybedilecek gerçek veri yoktur. 2. adımdan (cron) başlanıp 12. adıma kadar yeniden uygulanır. Giriş hesapları `auth.users`'ta korunur, 10. adımda yeniden bağlanır. `yukle.sql` tek işlemdir; yalnızca o hata verdiyse hiçbir şey yazılmamıştır, dosya üretilip 6. adım tekrarlanır.

**Yedek seçenek: yedekten dönüş** (eski duruma dönmek gerekiyorsa):
1. SQL Editor'de `drop schema pdks cascade;`.
2. 1. adımdaki dosyalar sırayla yüklenir. Veri yedeğinde döngüsel bağ olduğu için tetikleyiciler o oturumda kapatılır. Yalnızca yerelde denendi; canlıda bu yetki yoksa ana yola dönülür.

```bash
psql "$CANLI_DB_URL" -v ON_ERROR_STOP=1 -f ~/atlas_yedek/<tarih>/pdks_sema.sql
```

```bash
psql "$CANLI_DB_URL" -v ON_ERROR_STOP=1 -c "set session_replication_role = replica" -f ~/atlas_yedek/<tarih>/veri.sql
```

3. Migration kaydı silindiyse `gecmis.sql` de yüklenir. Sonraki `db push` öncesinde `canli_migration_kontrol.sql` çalıştırılır; kayıt ile şema uyuşmazlığı orada görünür.
