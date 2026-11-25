# Sentetik veri seti (180 çalışan, Ekim 2026)

Bilgi işlemden gerçek veri alınamadığı için, sistemi firmanın gerçek ölçeğinde denemek üzere **sahte ama gerçeğe benzeyen** bir veri seti üretilir. Hiçbir satır gerçek Atlas Trafo verisi değildir.

`supabase/seed.sql` (76 kişi, 32 senaryo, Kasım) olduğu gibi kalır; bu veri seti onun **üstüne** Ekim ayını ekler. Demo kişileri 4 haneli (1001), sentetik çalışanlar 8 haneli (20180214) sicil taşır; ikisi çakışmaz.

## Üretme

```bash
node scripts/sentetik_veri.mjs                                   # Ekim 2026, tohum 20261001
node scripts/sentetik_veri.mjs --bas 2026-09-01 --bit 2026-09-30 # başka bir ay
```

JSON istenirse ardından `node scripts/sentetik_json.mjs` çalıştırılır: her servis için bir dosya `veri/sentetik/json/` altına yazılır ve her dosyada `"veri_turu": "sentetik"` etiketi bulunur.

Çıktı `veri/sentetik/` klasörüne yazılır (git'e girmez, ~12 MB). Aynı tohumla her çalıştırma birebir aynı dosyaları üretir; bu yüzden repoya yalnızca betik girer. `veri/sentetik/ozet.md` neyin kaç adet üretildiğini gösterir.

| Dosya | İçerik |
|---|---|
| `calisanlar.csv` | sicil, ad, soyad, departman, yaka, vardiya düzeni, işe giriş / çıkış, kart, servis hattı |
| `kartlar.csv` | Asıl kartlar ve geçmişte iptal edilenler (kayıp, yenilendi, işten çıkış) |
| `vardiya_plani.csv`, `izinler.csv`, `isg_belgeleri.csv`, `gecici_kart_zimmet.csv` | Gece işinin girdileri |
| `okutma/<kaynak>_<YYYYMMDD>.csv` | Her kaynak için günlük dosya; **Veri Aktarımı ekranının biçimi** (`okuyucu;kart_no;zaman;yon`) |
| `okutma/dosyalar.csv` | Dosya listesi, satır sayısı ve SHA-256 özeti |
| `yukle.sql` | Hepsini tek işlemde yükleyen psql betiği |

## Yükleme (önce seed yüklü olmalı)

```bash
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f veri/sentetik/yukle.sql
```

Sonra Ekim'i gece işinden geçirin (psql'den; `gece_isi_tetikle` İK oturumu ister, burada çalışmaz):

```sql
select g::date, pdks.gece_isi_calistir(g::date)
from generate_series(date '2026-10-01', date '2026-10-31', interval '1 day') g;
```

Betik tek işlemdir: hata olursa hiçbir şey yazılmaz. İkinci kez çalıştırılırsa yazmadan durur. Canlı Supabase'e yüklemek Fırat'ın onayıyla yapılır; önce yerelde denenir.

## Gerçeğe benzerlik ölçütleri

| Alan | Nasıl üretildi |
|---|---|
| Sicil | 8 hane: işe giriş yılı (4 hane) + o yıl içindeki sıra no (4 hane), ör. `20180014` = 2018'de işe giren 14. kişi. Firma her yıl ~30 kişi işe alır, sıra her yılbaşı 0001'den başlar; ayrılanın numarası yeniden verilmez. Bu yüzden eski yıllarda numaralar seyrek (1999: 19990029, 2001: 20010003 …), son yıllarda sık (2026: 20260029, 20260030, 20260031) |
| Kart numarası | 10 haneli ondalık (125 kHz kartların üzerinde basılı biçim, ör. `0004817263`), tekil |
| Ad | Listeler `scripts/isimler.mjs`te (~650 ad). Kişinin doğum kuşağına göre seçilir: 1955–79 doğumluda Nevzat, Hanife, Nurten; 1980–94'te Serkan, Tuğba, Gözde; 1995 sonrası Furkan, Büşra, İrem. Her kuşakta yaygın adlar (Mehmet, Ayşe …) ortak; %7 çift ad (Mehmet Ali, Hatice Kübra) |
| Soyad | ~400 soyad: %55 en sık 60 soyaddan (Yılmaz ~%3), %45 uzun kuyruktan: Ege / İzmir yöresi (Zeybek, Ödemişli, Tireli), "-oğlu" ekli (Hacıoğlu, Terzioğlu) ve birleşik soyadları (Gökdemir, Akyıldız). Tanınmış ailelerle özdeşleşen soyadları kullanılmaz. Aynı ad-soyadlı farklı kişiler var (eşleşme sicille yapılmalı) |
| Doğum yılı | Yalnızca ad seçmek için üretilir, dosyaya yazılmaz (işe girişte mavi yaka 19–40, beyaz yaka 22–45 yaş; kimse 63 yaşını geçmez) |
| Cinsiyet | Mavi yakada ~%7, beyaz yakada ~%42 kadın (sütun olarak tutulmaz) |
| Kıdem | Üstel dağılım (mavi yaka ort. 6, beyaz yaka 8 yıl); dönem içinde 2 işe giriş, 2 işten çıkış; geçmişte ayrılmış 7 pasif çalışan |
| Departman büyüklüğü | 19 departman, 180 çalışan: 147 mavi / 33 beyaz yaka (Bobinaj 32, Montaj 30, Kazan 21, Nüve 17, Kalite 11, Depo 11, İdari 9, Boyahane 8, Bakım 8; beyaz yakada 2–6 kişi) |
| Vardiya | Bobinaj V1/V2/V3, Nüve-Kazan ve güvenlik 08-16/16-24/00-08 haftalık dönüşüm; Ar-Ge ve Satış'ın yarısı esnek |
| Tatil | 29 Ekim tatil (plan yok). 28 Ekim arife: üretilen veride tam gün çalışılır; 13:00 sonrası sistemde FM100 ya da havuz olur (`docs/veritabani.md`) |
| Saatler | Kişinin kendi alışkanlığı (hep erken gelen / son dakika gelen); servisle gelenler aynı sefer saatinde, birkaç saniye arayla okutur |
| Okuyucular | Seed'dekilere ek PDKS-3 (Kazan-Nüve atölyesi), KAPI-2 (personel kapısı), 5 servis hattı (Karşıyaka, Çiğli, Menemen, Kemalpaşa, Torbalı) |

## Bilerek konmuş hatalar (yaklaşık oranlar, kişi-gün başına)

| Durum | Oran | Beklenen |
|---|---|---|
| PDKS girişi eksik, kapı kaydı var | %1,2 | Gece işi kanıtla düzeltir (kapı geç ise amire soru) |
| PDKS çıkışı eksik, kapı kaydı var | %1,5 | Kapı saatiyle düzeltilir |
| Çıkışa dair hiçbir kayıt yok | %0,2 | Amire soru (`cikis_yok`) |
| Mükerrer giriş (4–50 sn arayla) | %0,8 | `mukerrer` işareti |
| Geç kalma (6–45 dk) / erken çıkış | %3 / %1 | Geç kalma, erken çıkış dakikası |
| Vardiya sonrası 30–120 dk kalma | %0,7 | Onaysız fazla mesai havuzu |
| Haber vermeden gelmeme | %0,3 | Amire soru (`hic_kayit_yok`), karar İK'da |
| Kart unutma → geçici kart (GK-10 … GK-39) | %0,25 | Okutma çalışana yazılır |
| İzin (yıllık, rapor, mazeret, ücretsiz) | kişilerin ~%13'ü | Gün "izinli" |
| İSG belgesi dolmuş / 30 gün içinde doluyor | %1 / %2 | İSG uyarıları |
| Depo çalışanının Boyahane kapısından geçmesi | birkaç kez | `yetkisiz_bolge_okutmasi` |

Kesin sayılar her üretimde `veri/sentetik/ozet.md` dosyasındadır.

## Bilerek yapılmayanlar

- **TC kimlik no, doğum tarihi, adres, telefon üretilmez.** Şemada yoktur ve PDKS için gerekmez (KVKK: veri en aza indirme).
- **Fazla mesai yazılı onayı üretilmez**; bu yüzden vardiya sonrası kalanlar havuza düşer.
- Yeni çalışanların Kasım planı yoktur; Kasım ekranlarında yalnızca seed'in 76 kişisi işlenir.
