# CLAUDE.md — Atlas Trafo PDKS Kayıt Düzeltme Sistemi

Claude Code bu dosyayı her oturumda okur. Buradaki kurallar her istekte geçerlidir.

## 1. Proje özeti
- Bilişim Sistemleri Analizi ve Tasarımı ders projesi; 4 kişilik ekip (Mehmet, Gökalp, Yusuf, Fırat), teslim 07.12.2026.
- Firma: Atlas Trafo (İzmir), ~2000 çalışan, gece vardiyası dahil vardiyalı üretim.
- Mevcut kartlı PDKS değişmez. Sistem onun kayıtlarını alır, hatalı/eksik olanları bulur:
  kanıt (kapı, yemekhane, servis kaydı) varsa kendisi düzeltir, yoksa amire sorar.
- Çalışan aleyhine karar (devamsızlık, itiraz reddi, kart paylaşımı) her zaman İK'dadır (KVKK m.11).
- Biyometri kullanma; akıllı telefon varsayma (KVKK ve proje kararı).
- Veritabanı: Supabase (PostgreSQL). Tüm tablolar `pdks` şemasında (38 tablo). Ayrıntı: `docs/veritabani.md`.
- İş kuralları veritabanındadır: PostgreSQL fonksiyonları ve trigger'lar (gece işi, düzeltme, görevler ayrılığı, ay kilidi).
- Giriş ve yetki: Supabase Auth + RLS. Roller: `amir`, `ik`, `guvenlik`, `yonetici`, `isg` (İSG uzmanı), `admin` (sistem yöneticisi; çalışan kayıtlarını görmez, karar veremez) (`kullanici.rol`).
- Görevler ayrılığı: her kullanıcı `kullanici.calisan_id` ile çalışan kaydına bağlıdır; kimse kendi kaydında işlem yapamaz.
- Çalışan isterse İK sistemden PDF döküm verir; itirazı amir ya da İK girer.
- Kart unutana güvenlikten zimmetli geçici kart (`gecici_kart`, `gecici_kart_zimmet`).
- Frontend: Next.js + TypeScript, Tailwind CSS + shadcn/ui. Veri bağlantısı: supabase-js; fonksiyonlar RPC ile çağrılır.
- CSV okuma: Papa Parse · PDF döküm: @react-pdf/renderer · Excel çıktısı: SheetJS.
- Gece işi pg_cron ile her gece çalışır; demoda ekrandaki butonla da tetiklenir. Yayın: Vercel.
- Raporlama: ayrı araç yok; yönetici paneli (departman özeti), puantaj Excel'i, ERP aktarımı ve PDF döküm.

## 2. Değişmez veritabanı kuralları
- `ham_okutma`, `kanit_kaydi`, `aktarim`, `okutma_isareti` değiştirilemez ve silinemez.
- `gun_kaydi` doğrudan UPDATE edilmez; yalnızca `pdks.duzeltme_uygula(...)` ile değişir.
- `duzeltme` ve `puantaj_satiri` silinemez, değiştirilemez.
- Kilitli ay (`donem.durum = 'kilitli'`) açılamaz; sonradan gelen düzeltme fark satırı olur.
- Ücret hesaplanmaz; puantajda yalnızca gün ve dakika vardır.

## 3. Migration kuralı
- `supabase/migrations/` altındaki mevcut dosyalar ASLA değiştirilmez.
- Her değişiklik yeni, sıra numaralı bir dosyadır: `YYYYMMDDHHMMSS_kisa_ad.sql`
  (ör. `20261115000500_fazla_mesai.sql`).
- Her yeni kural için `supabase/tests/` altına test eklenir; testler sonda ROLLBACK ile iz bırakmaz.

## 4. Güvenlik (asla ihlal etme)
- `.env` ve `.env.*` dosyaları (`.env.local` dahil) okunmaz, yazdırılmaz, commit edilmez (`.env.example` hariç).
- Şifre, bağlantı adresi veya anahtar koda, loglara, ekran çıktısına yazılmaz.
- Repoda yalnızca sahte (sentetik) veri olur; gerçek Atlas Trafo verisi asla.
- Kullanıcı girdisi SQL metnine eklenmez; veritabanına supabase-js sorgu oluşturucusu ve RPC ile erişilir.
- `SUPABASE_SECRET_KEY` yalnızca sunucu tarafı kodda kullanılır; `NEXT_PUBLIC_` öneki almaz, tarayıcıya gönderilmez.
- Her yeni tabloda RLS açılır ve rol bazlı politika yazılır; yetki kontrolü yalnızca ekrana bırakılmaz.
- Supabase'e veya herhangi bir canlı veritabanına Fırat'ın açık onayı olmadan komut çalıştırılmaz.
- `main` dalına ve başkasının dalına push yapılmaz.

## 5. Git düzeni
- Her iş ayrı dalda: `feature/<no>-kisa-ad`.
- Commit mesajları Türkçe ve kısa: `feat(db): ...`, `fix: ...`, `chore: ...`, `test: ...`.
- Commit ve push öncesi Fırat'a ne değiştiğini göster ve onay al.

## 6. Fırat ile çalışma şekli (öğreterek ilerle)
Fırat YBS 3. sınıf; SQL'de JOIN ve GROUP BY biliyor, TypeScript ve Next.js'te yeni. Her adımda:
1. Ne yapacağını önce 2-3 cümleyle anlat.
2. Yeni kavramları sade dille, ilk kez gören birine anlatır gibi açıkla.
3. Kodu tamamen sen yaz (süre kısa); her dosyadan sonra önemli satırları sade dille açıkla.
4. Adım sonunda anladığını ölçen 2-3 soru sor ve cevabını bekle.
