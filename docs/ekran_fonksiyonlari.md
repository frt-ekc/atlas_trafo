# Ekran fonksiyonları (RPC)

Ekranlar veritabanına **yazmak** için yalnızca bu fonksiyonları çağırır. Tablolara doğrudan `insert` / `update` yetkisi yoktur; okuma ise `select` ile yapılır ve RLS her kullanıcıya yalnızca rolünün izin verdiği satırları gösterir.

Kaynak: `supabase/migrations/20261119010000_ekran_fonksiyonlari.sql` · Testler: `supabase/tests/ekran_fonksiyonlari_testi.sql`
Sonradan eklenenler: gece işi ve puantaj (`20261120…`, `20261121…`), izin iptali (`20261122…`), onaysız fazla mesai, saatlik izin ve puantaj kodları (`20261123010000_puantaj_kurallari.sql`, testi `puantaj_kurallari_testi.sql`).

## Nasıl çağrılır

```ts
const { data, error } = await supabase
  .schema('pdks')
  .rpc('soru_cevapla', { p_soru_id: 42, p_cevap: 'geldi_saat_dogru' })

if (error) toast.error(error.message)   // mesajlar Türkçe ve kullanıcıya gösterilebilir
```

- Parametre adları SQL'deki gibidir (`p_` önekli). Varsayılanı olan parametreler gönderilmeyebilir.
- Zamanlar ISO metin olarak gönderilir: `'2026-11-13T08:05:00+03:00'`. Tarihler `'2026-11-13'`.
- Fonksiyon, oturumdaki kullanıcıyı kendisi bulur; "kim yaptı" bilgisi ekrandan gönderilmez.
- Her fonksiyon önce rolü kontrol eder. Yetkisiz çağrı `Bu işlem için yetkiniz yok.` hatası verir.
- Amir yalnızca kendi departmanının çalışanları için işlem yapabilir.
- Kimse kendi kaydında işlem yapamaz (görevler ayrılığı); deneme `Görevler ayrılığı: ...` hatası verir.

## Amir

| Fonksiyon | Parametreler | Ne yapar |
|---|---|---|
| `soru_cevapla` | `p_soru_id`, `p_cevap`, `p_giris?`, `p_cikis?`, `p_aciklama?` | Kendisine atanmış (ya da kendisine eskale edilmiş) açık soruyu cevaplar. Saat yazıldıysa gün **hemen hesaplanır** (dakikalar ve durum `tamam`); gece işini beklemez. `gelmedi` / `bilmiyorum` cevabında gün hesaplanmaz, İK kararına gider |
| `itiraz_gir` | `p_gun_kaydi_id`, `p_metin` | Çalışanın itirazını sisteme girer; itiraz no döner |
| `fazla_mesai_talep_et` | `p_calisan_id`, `p_is_gunu`, `p_planli_dk`, `p_gerekce` | Fazla mesai talebi açar (vardiya, vardiya planından alınır); talep no döner |
| `vardiya_plani_gir` | `p_calisan_id`, `p_tarih`, `p_vardiya_id`, `p_aciklama?` | Vardiya planı girer ya da değiştirir. Geçmiş tarih İK onayına düşer; kilitli aya girilemez. Onay bekleyen plan gün kaydını değiştirmez ve gece işinde kullanılmaz (gün işlenmediyse onaya kadar işlenmez) |

`p_cevap` değerleri:

| Cevap | Sonuç |
|---|---|
| `geldi_saat_dogru` | Saat gönderilmezse sistemin önerdiği saat, o da yoksa vardiya başı/sonu yazılır |
| `kart_unuttu` | `geldi_saat_dogru` ile aynı; ayrıca gerekçede kart unutma görünür |
| `geldi_saat_farkli` | `p_giris` ve/veya `p_cikis` zorunlu; girilen saat yazılır |
| `gelmedi` | Kayıt değişmez; soru İK kararına geçer (`ik_karari_bekliyor`) |
| `bilmiyorum` | `gelmedi` ile aynı: karar İK'nındır |

`vardiya_uyusmazligi` sorusu, okutmalar başka bir vardiyaya uyduğunda açılır; soruda öneri vardır (`onerilen_vardiya_id`, `onerilen_zaman` = giriş, `onerilen_cikis`). `geldi_saat_dogru` (saat girmeden) öneriyi uygular: günün vardiyası, planlı saatleri, girişi ve çıkışı düzeltilir. `geldi_saat_farkli` ile girilen saatler yazılır, vardiya değişmez. Önerisi olmayan bu tür soruda saatler girilmelidir.

## Güvenlik

| Fonksiyon | Parametreler | Ne yapar |
|---|---|---|
| `gecici_kart_ver` | `p_gecici_kart_id`, `p_calisan_id`, `p_aciklama?` | Kartını unutan çalışana geçici kart zimmetler; zimmet no döner. Kart ya da çalışan başka bir zimmetle çakışırsa hata çakışan zimmeti söyler: "GK-01 kartı Osman Doğan'a 24.11.2026 07:25'te verilmiş zimmetle çakışıyor (henüz iade edilmedi)." |
| `gecici_kart_iade_al` | `p_zimmet_id` | Geçici kartı geri alır |

İK de bu iki fonksiyonu çağırabilir.

## İSG uzmanı (isg)

| Fonksiyon | Parametreler | Ne yapar |
|---|---|---|
| `isg_belge_gir` | `p_calisan_id`, `p_tur`, `p_gecerlilik_bitis`, `p_belge_no?` | İSG eğitimi (`isg_egitimi`) ya da periyodik sağlık muayenesi (`saglik_muayenesi`) geçerlilik tarihini girer; kayıt no döner. Sonuç / teşhis girilmez. Yenileme yeni kayıttır; en son girilen geçerlidir. Kendi belgesini giremez |
| `bolge_yetkisi_ver` | `p_bolge_id`, `p_departman_id` | Departmana bölgeye giriş yetkisi verir |
| `bolge_yetkisi_kaldir` | `p_bolge_id`, `p_departman_id` | Yetkiyi kaldırır. Verme ve kaldırma kim / ne zaman bilgisiyle `bolge_yetkisi_gecmisi`'ne yazılır |

Okuma: `v_isg_durum` (çalışan ve tür başına `yok` / `dolmus` / `doluyor` / `gecerli`), `isg_belge`, `bolge`, `bolge_yetkisi`, `okuyucu`; İSG uzmanı `uyari` tablosunda yalnızca İSG ve bölge uyarılarını görür.

```ts
await supabase.schema('pdks').from('v_isg_durum').select('*').in('durum', ['yok', 'dolmus', 'doluyor'])
```

## Sistem yöneticisi (admin)

| Fonksiyon | Parametreler | Ne yapar |
|---|---|---|
| `kullanici_ekle` | `p_eposta`, `p_rol`, `p_calisan_id`, `p_ust_amir_id?` | Sisteme giren kişiyi tanımlar; kullanıcı no döner. Ad soyad çalışan kaydından gelir (T-105). Giriş hesabı Supabase Auth'ta aynı e-postayla açılır; hesap varsa hemen bağlanır. Aynı e-posta ya da hesabı olan çalışan reddedilir. Admin kendine hesap açamaz |
| `kullanici_guncelle` | `p_kullanici_id`, `p_rol?`, `p_ust_amir_id?`, `p_aktif?` | Rolü, üst amiri ya da aktifliği değiştirir (gönderilmeyen değişmez); Auth hesabı sonradan açıldıysa bağlar. Admin kendi hesabını değiştiremez |
| `ayar_guncelle` | `p_anahtar`, `p_deger` (metin) | Ayar değerini değiştirir (tolerans, mola, eşikler …); tam sayı, `en_az`–`en_cok` aralığı ve mola sıralaması denetlenir; puantajı etkileyen ayarda İK'ya uyarı (T-74); eski / yeni değer ve değiştiren `ayar_gecmisi`'ne yazılır |

Admin çalışan kayıtları üzerinde karar veremez: düzeltme, izin, itiraz, fazla mesai, ay kilidi ve soru cevabı fonksiyonları admin için `Bu işlem için yetkiniz yok.` hatası verir.

## İK

| Fonksiyon | Parametreler | Ne yapar |
|---|---|---|
| `uyari_goruldu` | `p_uyari_id` | Uyarıyı "görüldü" yapar |
| `soru_ik_karari` | `p_soru_id`, `p_devamsiz`, `p_gerekce`, `p_giris?`, `p_cikis?` | İK'da duran soruyu kapatır: (1) amirin "gelmedi / bilmiyorum" dediği soru (`ik_karari_bekliyor`) ve **yeni:** (2) İK'ya eskale edilmiş soru (`eskale`; ör. üst amiri olmayan amirin süresi geçen sorusu) ya da (3) doğrudan İK'ya atanmış açık soru (`acik`; ör. üst amiri olmayan amirin kendi günü). `p_devamsiz = true` → gün devamsız (çalışan aleyhine işaretlenir); `false` → saat zorunlu. Saat yazıldıysa gün hemen hesaplanır. İK kendi günündeki soruya karar veremez (görevler ayrılığı; soru diğer İK'ya düşer). Sonuç `ik_karari`'na, gerekçe yalnızca `duzeltme`'ye yazılır; amir gerekçeyi görmez (T-106) |
| `itiraz_incelemeye_al` | `p_itiraz_id` | İtirazı "incelemede" yapar |
| `itiraz_karar` | `p_itiraz_id`, `p_kabul`, `p_aciklama` | İtirazı kabul ya da reddeder |
| `kayit_duzelt` | `p_gun_kaydi_id`, `p_alan`, `p_yeni_deger`, `p_gerekce`, `p_itiraz_id?`, `p_izin_id?` | Gün kaydında tek alanı düzeltir (`giris_zamani`, `cikis_zamani`, `durum` …); düzeltme no döner. Gün hemen yeniden hesaplanır. Kilitli aydaki günde gün değişmez ve hesaplanmaz; düzeltme sonraki açık aya fark satırı olur (itiraz kabulü de böyle girilir: `itiraz_karar` sonra `kayit_duzelt(..., p_itiraz_id)`) |
| `vardiya_plani_onayla` | `p_plan_id`, `p_onay` | Geçmişe dönük vardiya planını onaylar/reddeder; planı giren kişi onaylayamaz. **Onay:** gün işlenmişse vardiya düzeltmesi yazılır ve gün hemen yeniden hesaplanır (kilitli ayda gün değişmez, düzeltme sonraki açık aya fark satırı olur); gün işlenmemişse o gün hemen gece işinden geçer. **Ret:** hiçbir şey değişmez; gün işlenmemişse ay kilidi "reddedilmiş plan" diyerek kilidi reddeder, İK doğru planı `vardiya_plani_gir` ile girer (o da yeniden onaya düşer). Görevler ayrılığı: kimse kendi çalışan kaydına ait planı onaylayamaz ya da reddedemez |
| `izin_gir` | `p_calisan_id`, `p_tur`, `p_baslangic`, `p_bitis`, `p_aciklama?` | İzin kaydı girer; izin no döner. Çalışanın bu tarihlerle kesişen, iptal edilmemiş bir izni varsa reddedilir (önce o izin iptal edilir) |
| `izin_iptal` | `p_izin_id`, `p_neden` | Yanlış girilen izni iptal eder (silmez; kim/ne zaman/neden tutulur). İznin bir günü gece işinden "izinli/raporlu" olarak geçmişse reddeder: o günler `kayit_duzelt` ile düzeltilir. İK kendi iznini iptal edemez |
| `fazla_mesai_karar` | `p_plan_id`, `p_onay`, `p_aciklama?` | Fazla mesai talebini onaylar/reddeder |
| `fazla_mesai_inceleme_karar` | `p_inceleme_id`, `p_onay`, `p_aciklama?` | Onaysız fazla mesai havuzundaki kaydı onaylar ya da reddeder. Ret için gerekçe zorunlu (en az 5 karakter). Onay puantaja girer; kilitli aya aitse sonraki açık aya fark olur. Yıllık sınır aşılsa da onaylanır, İK'ya uyarı yazılır. İK kendi kaydına karar veremez |
| `saatlik_izin_gir` | `p_calisan_id`, `p_tarih`, `p_baslangic`, `p_bitis`, `p_tur`, `p_aciklama?` | Saat aralıklı izin girer (`p_tur`: `vizite` / `mazeret` / `diger`); izin no döner. Çakışan saatlik izin, tam gün izinli gün, kilitli ay ve iş günüyle uyuşmayan saat reddedilir. Hesaplanmış gün yeniden hesaplanır (mola dahil: izin çalışmayı 7,5 saatin altına indirirse mola 60'tan 30 dakikaya iner; sonuç gece işinin hesabıyla aynıdır). İK kendi iznini giremez |
| `fazla_mesai_onayi_gir` | `p_calisan_id`, `p_yil`, `p_imza_tarihi`, `p_belge_no` | Çalışanın yıllık yazılı fazla mesai onayını kaydeder |
| `fazla_mesai_onayi_geri_al` | `p_onay_id`, `p_bildirim_tarihi` | Çalışan onayını geri çektiğinde kaydeder |
| `kart_iptal_et` | `p_kart_id`, `p_neden` | Kartı iptal eder |
| `kart_tanimla` | `p_calisan_id`, `p_kart_no` | Yeni kart tanımlar (aktif kartı olana tanımlanmaz) |
| `calisan_ekle` | `p_sicil_no`, `p_ad`, `p_soyad`, `p_departman_id`, `p_ise_giris_tarihi` | Yeni çalışan ekler; çalışan no döner. İşe giriş ileri tarihli olabilir (ör. pazartesi başlayacak biri; o güne kadarki planlar işlenmez). Sicil, ad ve soyad boş olamaz; departman var olmalı. Sicil kullanılıyorsa "Bu sicil numarası başka bir çalışanda kayıtlı: Ad Soyad."; işten ayrılmış birine aitse "Bu sicil işten ayrılmış bir çalışana ait; yeniden işe giriş desteklenmiyor." Kart ayrıca `kart_tanimla` ile verilir |
| `isten_cikis_gir` | `p_calisan_id`, `p_cikis_tarihi`, `p_aciklama?` | İşten çıkışı girer. `p_cikis_tarihi` son çalışma günüdür; ileri olamaz, işe girişten önce olamaz. İade edilmemiş geçici kart varsa ya da çıkıştan sonra okutması olan gün varsa reddeder (mesaj kartı ya da günü söyler). Yaptıkları: çalışan pasif olur; aktif kartlar `isten_cikis` nedeniyle iptal; çıkıştan sonraki vardiya planları silinir; tamamı çıkıştan sonraya düşen izinler ve onay bekleyen fazla mesai talepleri "İşten çıkış (GG.AA.YYYY)" gerekçesiyle iptal (çıkış gününü kapsayan izin olduğu gibi kalır); çıkış geç girildiyse çıkıştan sonra işlenmiş günler "vardiya yok" olur ve açık soruları kapanır; bağlı kullanıcı hesabı pasif olur. Son günler (çıkış günü dahil) ertesi sabah gece işinde yine işlenir. Özet döner: `iptal_edilen_kart`, `vardiya_yok_yapilan_gun`, `silinen_plan`, `iptal_edilen_izin`, `iptal_edilen_fm_talebi`, `pasif_yapilan_hesap`. İK kendi çıkışını giremez |
| `ariza_gir` | `p_okuyucu_id`, `p_baslangic`, `p_bitis?`, `p_aciklama?` | Okuyucu arızası girer |
| `ariza_karar` | `p_ariza_id`, `p_onay` | Sistemin şüphe olarak açtığı arızayı onaylar/reddeder |
| `ay_kilitle` | `p_yil`, `p_ay`, `p_zorla?` | Ayı kilitler ve puantajı yazar: her çalışan için `normal` satır (canlı puantajın aynısı) ve önceki kilitli aylara sonradan gelen düzeltmeler ya da havuz onayları için `fark` satırı (`kaynak_donem_id` ile); her satırın kod kırılımı `puantaj_kalemi`'ne yazılır. Kilitten önce o ayın hesabı bekleyen günlerini hesaplar. Gece işinden geçmemiş planlı gün varsa (gün kaydı hiç açılmamış; reddedilmiş ya da İK onayı bekleyen planın günü dahil) kilitlemez; mesaj bunların sayısını ve ne yapılacağını söyler ("…; 1 günün geriye dönük planı reddedilmiş; 1 günün geriye dönük planı İK onayı bekliyor… reddedilmiş plan için doğru planı girin; İK onayı bekleyen planı önce onaylayın ya da reddedin"); mesaj gün sayısını, kişi sayısını ve ilk günü söyler, ör. "12/2026 döneminde gece işinden geçmemiş 10 planlı gün var (10 çalışan; ilk gün 07.12.2026)…"; bu kontrol `p_zorla` ile **geçilmez**. Açık soru/itiraz, İK kararı bekleyen onaysız fazla mesai ya da **İK onayı bekleyen geriye dönük vardiya planı** (günü eski planla işlenmişse) varsa kilitlemez; bunlar `p_zorla = true` ile geçilir. Kilit geri açılamaz. **Sonuç döner (jsonb)**, ekran kilitten sonra gösterir: `donem` (`2026-11`), `zorla`, `zorla_gecilen` (`acik_soru_gun`, `acik_itiraz`, `bekleyen_fazla_mesai`, `bekleyen_plan_onayi`), `kodsuz_gun` (puantaja hiçbir kodla girmeyen gün sayısı; zorla kilitlenen açık sorulu gün ne NÇ ne HT olur) ve hazır `mesaj`, ör. "9/2026 kilitlendi. Zorla geçilenler: 1 açık sorulu gün, 1 açık itiraz, 1 onay bekleyen geriye dönük plan. Puantaja kodsuz giren gün: 1." `kodsuz_gun > 0` ise ekranda uyarı olarak gösterilmeli |
| `dosya_yukle` | `p_kaynak`, `p_dosya_adi`, `p_veri_tarihi`, `p_satirlar`, `p_dosya_ozeti?` | CSV'den okunan satırları yükler; aktarım no döner. Yükleyen oturumdan `aktarim.yukleyen_id`'ye yazılır; yükleyenin kendi kartının okutması varsa diğer İK'ya `kendi_okutmasi_yuklendi` uyarısı (T-13) |
| `gece_isi_tetikle` | `p_baslangic`, `p_bitis?` | **Demo düğmesi.** Tarih aralığını gün gün gece işinden geçirir (en fazla 62 gün). Her gün için `gun`, `durum` (`basarili` / `hatali`), `ozet`, `hata_mesaji` satırı döner. Verisi yüklenmemiş gün işlenmez |

### `gece_isi_tetikle` (demo)

Gece işi normalde her gece 06:30'da kendiliğinden çalışır (pg_cron). Demoda İK ekranındaki düğme örnek ayı tek seferde işletir:

```ts
const { data, error } = await supabase.schema('pdks')
  .rpc('gece_isi_tetikle', { p_baslangic: '2026-11-01', p_bitis: '2026-11-30' })
// data: [{ gun: '2026-11-01', durum: 'basarili', ozet: { gun_kaydi: 31, soru: 0, ... }, hata_mesaji: null }, ...]
```

Tekrar çalıştırmak güvenlidir; var olan kayıtlar bozulmaz, yalnızca eksikler eklenir. Son çalışmanın durumu `v_gece_isi_durumu` görünümünden okunur.

### `dosya_yukle` satır biçimi

Ekran CSV'yi Papa Parse ile okur ve satırları JSON dizisi olarak gönderir:

```ts
await supabase.schema('pdks').rpc('dosya_yukle', {
  p_kaynak: 'pdks',                 // pdks | kapi | yemekhane | servis
  p_dosya_adi: 'pdks_20261113.csv',
  p_veri_tarihi: '2026-11-13',
  p_satirlar: [
    { okuyucu: 'PDKS-1', kart_no: 'K1001', zaman: '2026-11-13T07:52:00+03:00', yon: 'giris', satir_no: 2 },
  ],
  p_dosya_ozeti: '9f86d08…',        // dosyanın SHA-256 özeti (64 hane); ekran crypto.subtle ile çıkarır
})
```

- `pdks` kaynağı ham okutmaya, diğerleri kanıt kaydına yazılır.
- Hepsi ya da hiçbiri: bir satırda bile hata varsa hiçbir satır yazılmaz. Hata mesajı dosyadaki satır numarasını (`satir_no`) söyler.
- Sunucu denetimi: okuyucu tanımlı ve o kaynağa ait olmalı; kart no `A-Z 0-9 -` (en fazla 32, büyük harfe çevrilir); yön `giris` / `cikis` / boş; zaman **saat dilimiyle** (`+03:00`), aksi halde reddedilir.
- Aynı dosya (kaynak + özet) ikinci kez yüklenirse `Bu dosya daha önce yüklenmiş.` hatası döner. `p_dosya_ozeti` verilmezse satırların md5'i kullanılır (eski çağrı biçimi).
- Başka bir dosyayla zaten gelmiş okutmalar atlanır; `aktarim.satir_sayisi` yalnızca yazılan okutmaları sayar. Okutmaların tamamı önceden gelmişse aktarım 0 satırla yine kaydedilir, çünkü gece işi bir günün verisini o gün için aktarım satırı varsa tam sayar.

## Okuma (select)

Listeler doğrudan tablo ve görünümlerden okunur; RLS süzgeci otomatik uygulanır:

```ts
const { data } = await supabase.schema('pdks')
  .from('amir_sorusu')
  .select('id, soru_turu, aciklama, son_cevap_tarihi, gun_kaydi(is_gunu, calisan(ad, soyad))')
  .in('durum', ['acik', 'eskale'])
```

İzin listesi için amir `v_izin_amir` görünümünü kullanır (izin türü gizlidir; iptal edilen izinler görünmez). Saatlik izinler için de `v_saatlik_izin_amir` (tür her zaman `saatlik_izin`).

Onaysız fazla mesai havuzu `fazla_mesai_inceleme` tablosundan okunur (İK ve yönetici hepsini, amir kendi departmanını görür):

```ts
await supabase.schema('pdks').from('fazla_mesai_inceleme')
  .select('id, is_gunu, tur, dakika, durum, calisan(sicil_no, ad, soyad)')
  .eq('durum', 'inceleme_bekliyor')
```

Gün gün puantaj kodları (yalnızca İK ve yönetici; izin türünü içerir):

```ts
const { data } = await supabase.schema('pdks').rpc('gun_kodlari', { p_yil: 2026, p_ay: 11 })
// data: [{ calisan_id: 12, tarih: '2026-11-02', kod: 'NÇ', gun: 1, dakika: 540 }, { ..., kod: 'FM50', gun: 0, dakika: 60 }, ...]
```

ERP aktarımı için kilitli ayın kalemleri `v_puantaj_aktarim` görünümünden okunur (yalnızca İK ve yönetici; açık ay yer almaz):

```ts
await supabase.schema('pdks').from('v_puantaj_aktarim')
  .select('donem, sicil, satir_turu, kaynak_donem, kod, gun, dakika')
  .eq('donem_id', donemId).order('puantaj_satiri_id').order('kod')
```

Puantaj ekranı bu satırlardan iki dosya üretir (`lib/erp-aktarim.ts`); biçim bu projenin tanımladığı sade bir standarttır:

- **CSV** (`puantaj_YYYY-MM.csv`): UTF-8 (BOM'lu), ayırıcı `;`, sütunlar `sicil;donem;satir_turu;kaynak_donem;kod;gun;dakika`. Örnek: `1001;2026-11;normal;;NÇ;20;9600`
- **XML** (`puantaj_YYYY-MM.xml`): `<PuantajIcmali donem="2026-11" olusturma="…" birim="dakika">` içinde her çalışanın her puantaj satırı için `<Satir sicil="1001" satirTuru="normal">` (fark satırında `kaynakDonem="2026-10"`), onun içinde `<Kalem kod="NÇ" gun="20" dakika="9600"/>`.

Excel dosyası kilitli ayda ayrıca "Puantaj kodları" sayfası içerir; puantaj sayfasında FM50, FM100, gece çalışması ve mola sütunları vardır.

Kilitli ayın kod kırılımı `puantaj_kalemi` tablosundadır (`puantaj_satiri_id`, `kod`, `gun`, `dakika`). `puantaj_satiri` ve `v_puantaj_canli` ayrıca `fm50_dk`, `fm100_dk`, `gece_calisma_dk`, `saatlik_izin_dk`, `mola_dk`, `esnek_hedef_dk`, `esnek_fark_dk` sütunlarını verir.

Esnek mesaili çalışanların aylık hedef durumu `v_esnek_mesai` görünümündedir (`hedef_gun`, `hedef_dk`, `gerceklesen_dk`, `fark_dk`, `bekleyen_gun`):

```ts
await supabase.schema('pdks').from('v_esnek_mesai').select('*').eq('yil', 2026).eq('ay', 11)
```

**İK `izin` tablosunu doğrudan okuyorsa iptal edilen izinleri süzmelidir:**

```ts
await supabase.schema('pdks').from('izin').select('*').is('iptal_zamani', null)
```

Yönetici paneli için `v_departman_ozet` görünümü ay ve departman başına özet verir: `calisan_sayisi`, `calisilan_gun`, `devamsiz_gun`, `gec_kalinan_gun`, `gec_kalma_dk`, `erken_cikis_dk`, `fazla_mesai_dk`, `bekleyen_gun`, `acik_soru`, `acik_itiraz`. İK ve yönetici tüm departmanları, amir yalnızca kendi departmanını görür.

```ts
await supabase.schema('pdks').from('v_departman_ozet').select('*').eq('yil', 2026).eq('ay', 11)
```
