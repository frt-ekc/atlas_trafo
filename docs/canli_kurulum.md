# Canlı veritabanını yeniden kurma (atlas-pdks)

Canlı veritabanı (Supabase projesi **atlas-pdks**) seed değişince baştan kurulur. İlk kez 19 Kasım 2026'da bu adımlarla kuruldu. Sıradaki kurulum F grubu (demo senaryoları) birleşince, Fırat ve Gökalp birlikte yapacak.

**Kurallar**
- Her adımı **Fırat** onaylar ve çalıştırır.
- SQL adımları Supabase → **SQL Editor**'de çalıştırılır.
- Bağlantı adresi, şifre ve anahtar bu belgeye, koda ya da sohbete yazılmaz.
- Silinen yalnızca `pdks` şeması ve migration kaydıdır. **`auth.users` (giriş hesapları) korunur**, bu yüzden 25 demo hesabı yeniden açılmaz.
- Hiçbir ay kilitlenmez. Ay kilidi canlıda gösterilmez (bkz. `docs/demo_akisi.md`).

## 0. Hazırlık
- `main` güncel olmalı: `git checkout main && git pull`.
- Yerelde bütün testler örnek veriyle ve örnek verisiz geçmiş olmalı.
- Gökalp'e haber verilir: kurulum boyunca ekranlar çalışmaz.

## 1. Yedek
Yedek bilgisayarda, depo dışındaki `~/atlas_yedek/<tarih>/` klasörüne alınır:

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
supabase db dump --remote --data-only --schema auth -f ~/atlas_yedek/$(date +%F)/auth_veri.sql
```

- Her komutun çıktısında `Target: project atlas-pdks … · production` yazısını görmeden devam edilmez.
- `auth_veri.sql` şifre özetleri içerir. Kurulum doğrulandıktan birkaç gün sonra silinir. Diğer iki dosya teslime kadar saklanır.

## 2. Sıfırlama (SQL Editor)
```sql
drop schema pdks cascade;
delete from supabase_migrations.schema_migrations;
```

- `auth` şemasına dokunulmaz.
- `pg_cron` eklentisi ve `cron` şeması yerinde kalır. Gece işi zamanlaması 3. adımda migration ile yeniden kurulur, 5. adımda kapatılır.

## 3. Migration'lar
Önce deneme: hiçbir şey değişmez, uygulanacak dosyaları listeler.

```bash
supabase db push --remote --dry-run
```

Liste `supabase/migrations/` altındaki dosyaların hepsini (şu an 38) göstermeli. Sonra gerçek uygulama:

```bash
supabase db push --remote
```

## 4. Örnek veri ve şema yenileme (SQL Editor)
1. `supabase/seed.sql` dosyasının tamamı SQL Editor'e yapıştırılıp çalıştırılır.
   - Seed'in son bölümü (10. bölüm), `auth.users`'taki hesapları e-posta üzerinden `kullanici` tablosuna kendisi bağlar.
2. Ekranların yeni fonksiyonları görmesi için API şeması yenilenir:

```sql
notify pgrst, 'reload schema';
```

## 5. Gece işi zamanlamasını kapatma (SQL Editor)
Canlıya gerçek PDKS verisi gelmeyecek. Zamanlama açık kalırsa 1 Aralık'tan itibaren her gece dört kaynak için "dosya gelmedi" uyarısı yazılır ve İK'nın uyarı listesi demoya kadar dolar. Dosyası gelmeyen günde gün kaydı açılmaz, bu yüzden soru açılmaz; ama demo günü dosya yüklenince o günü zamanlama da işlemeye kalkar ve demodaki sıra karışır.

```sql
select cron.unschedule('pdks-gece-isi');
select count(*) as kalan_zamanlama from cron.job where jobname = 'pdks-gece-isi';   -- 0 olmalı
```

Demo günü gece işi ekrandaki **Gece işlemini başlat** düğmesiyle tetiklenir.

## 6. Kasım'ı gece işinden geçirme (SQL Editor)
Seed yalnızca girdileri yazar: okutmalar, planlar, izinler. Gün kayıtlarını, soruları ve uyarıları gece işi üretir. Kasım'ın her günü sırayla işlenir:

```sql
do $$
declare d date;
begin
    for d in select g::date from generate_series(date '2026-11-01', date '2026-11-30', interval '1 day') g loop
        perform pdks.gece_isi_calistir(d);
    end loop;
end $$;
select durum, count(*) from pdks.gece_isi group by durum;   -- yalnızca "basarili" (30) olmalı
```

## 7. Doğrulama (SQL Editor, yalnızca okur)
1. `supabase/scripts/canli_migration_kontrol.sql`: her satırda `kayitli = evet` ve `nesne = evet` olmalı.
2. `supabase/scripts/canli_veri_durumu.sql` ve şu sayılar:

```sql
select (select count(*) from pdks.calisan)                                       as calisan,      -- 76
       (select count(*) from pdks.kullanici)                                     as kullanici,    -- 25
       (select count(*) from pdks.kullanici where auth_kullanici_id is not null) as bagli_hesap,  -- 25
       (select count(*) from pdks.gun_kaydi)                                     as gun_kaydi,    -- 1597 (S13 Okan'ın 13 Kasım günü plan onayı beklediği için işlenmez)
       (select count(*) from pdks.amir_sorusu where durum in ('acik', 'eskale')) as acik_soru,    -- 4 (S2, S4, S19, S22)
       (select count(*) from pdks.donem where durum = 'kilitli')                 as kilitli_ay;   -- 0
```

3. Ekranda birkaç hesapla giriş denenir: İK uzmanı, Montaj amiri, güvenlik, İSG uzmanı.

## 8. Son ayarlar (Supabase panelinde)
- **Authentication → Sign In / Providers → "Allow new users to sign up" kapalı** olmalı.
  - `supabase/config.toml`'daki `enable_signup = false` yalnızca yerel Supabase'i etkiler; canlıyı bu ayar belirler.

## Bir şey ters giderse: yedekten dönüş
1. SQL Editor'de `drop schema pdks cascade;` çalıştırılır.
2. 1. adımdaki dosyalar sırayla yüklenir, önce şema sonra veri. Komutu Fırat kendi terminalinde çalıştırır; bağlantı adresi yalnızca o terminalde kalır:

```bash
psql "$CANLI_DB_URL" -v ON_ERROR_STOP=1 -f ~/atlas_yedek/<tarih>/pdks_sema.sql
```

```bash
psql "$CANLI_DB_URL" -v ON_ERROR_STOP=1 -f ~/atlas_yedek/<tarih>/veri.sql
```

3. Migration kaydı silindiği için, sonraki `db push` öncesinde kontrol sorgusu (`canli_migration_kontrol.sql`) çalıştırılır. Kayıt ile şemanın uyuşmadığı bu sorguda görünür.
