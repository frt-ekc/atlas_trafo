// =====================================================================
// Sentetik (sahte) veri seti üreticisi — ~180 çalışan, bir aylık okutma
//
// Gerçek Atlas Trafo verisi İÇERMEZ. Kişiler, sicil ve kart numaraları uydurmadır;
// yalnızca gerçek bir fabrikanın verisine BENZEMESİ hedeflenir (sicil düzeni, kart
// numarası biçimi, departman büyüklükleri, servis kümelenmesi, hata oranları).
//
// Çalıştırma (repo kökünde):
//   node scripts/sentetik_veri.mjs                 # varsayılan: Ekim 2026, 180 kişi
//   node scripts/sentetik_veri.mjs --bas 2026-10-01 --bit 2026-10-31 --tohum 7
//   node scripts/sentetik_veri.mjs --kurulum       # seed'siz canlı kurulum: kadro (25 kullanıcı) dahil,
//                                                  # planlar 7 Aralık dahil, okutmalar --bit'e kadar; çıktı veri/kurulum/
//
// Çıktı: veri/sentetik/ (git'e girmez; her çalıştırmada aynı tohumla birebir aynı çıkar)
//   calisanlar.csv, kartlar.csv, vardiya_plani.csv, izinler.csv, isg_belgeleri.csv,
//   gecici_kart_zimmet.csv, okutma/<kaynak>_<YYYYMMDD>.csv, okutma/dosyalar.csv,
//   yukle.sql (psql ile yükler), ozet.md (ne üretildiğinin sayımı)
//
// Ayrıntı: docs/sentetik_veri.md
// =====================================================================
import { createHash } from "node:crypto";
import { mkdirSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import * as I from "./isimler.mjs";
import { KADRO, BOBINAJ_VEKILI, MAVI_UST_AMIR, BEYAZ_UST_AMIR } from "./kadro.mjs";

// ---------------------------------------------------------------------
// 0. Parametreler
// ---------------------------------------------------------------------
const arg = (ad, varsayilan) => {
  const i = process.argv.indexOf(`--${ad}`);
  return i > 0 ? process.argv[i + 1] : varsayilan;
};
// --kurulum: seed'siz kurulum. Verilmezse davranış ve çıktı eskisiyle birebir aynıdır.
const KURULUM = process.argv.includes("--kurulum");
const BAS = arg("bas", "2026-10-01");
const BIT = arg("bit", KURULUM ? "2026-12-06" : "2026-10-31");
// Kurulumda üretim hep bu güne kadar yapılır, okutmalar sonra --bit'te kesilir: --bit değişse de
// ortak günler birebir aynı kalır ve demo gününün (7 Aralık) planları hazır olur.
const KURULUM_PLAN_BIT = "2026-12-07";
if (KURULUM && BIT > KURULUM_PLAN_BIT) throw new Error(`--kurulum için --bit en çok ${KURULUM_PLAN_BIT} olabilir.`);
const TOHUM = Number(arg("tohum", "20261001"));
const CIKTI = arg("cikti", KURULUM ? "veri/kurulum" : "veri/sentetik");
const BUGUN = arg("bugun", "2026-11-20"); // "aktif" alanı ve İSG belge tarihleri buna göre

// Tohumlu rastgele sayı üreteci (mulberry32): aynı tohum → aynı veri
function uretec(tohum) {
  let a = tohum >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const r = uretec(TOHUM);
const aralik = (alt, ust) => alt + Math.floor(r() * (ust - alt + 1)); // [alt, ust] tam sayı
const olasilik = (p) => r() < p;
const sec = (dizi) => dizi[Math.floor(r() * dizi.length)];
// Yaklaşık normal dağılım (3 düzgün sayının toplamı)
const normal = (ort, sapma) => ort + sapma * ((r() + r() + r() - 1.5) / 0.5);
// Sıklık sırasına göre ağırlıklı seçim (listenin başı daha sık: Zipf)
function zipfSecici(dizi, us = 0.9) {
  const agirlik = dizi.map((_, i) => 1 / Math.pow(i + 1, us));
  const toplam = agirlik.reduce((a, b) => a + b, 0);
  return () => {
    let x = r() * toplam;
    for (let i = 0; i < dizi.length; i++) if ((x -= agirlik[i]) <= 0) return dizi[i];
    return dizi[dizi.length - 1];
  };
}

// ---------------------------------------------------------------------
// 1. Tarih ve saat yardımcıları (Türkiye'de yaz saati yok: UTC+3 sabit,
//    bu yüzden tüm saatler "yerel saat" olarak UTC Date içinde tutulur)
// ---------------------------------------------------------------------
const gun = (s) => new Date(`${s}T00:00:00Z`);
const gunMetni = (d) => d.toISOString().slice(0, 10);
const gunEkle = (d, n) => new Date(d.getTime() + n * 86400000);
const dkEkle = (d, dk) => new Date(d.getTime() + Math.round(dk * 60000));
const snEkle = (d, sn) => new Date(d.getTime() + sn * 1000);
const zamanMetni = (d) => d.toISOString().slice(0, 19).replace("T", " ");
const saatte = (tarih, hhmm) => {
  const [h, m] = hhmm.split(":").map(Number);
  return dkEkle(tarih, h * 60 + m);
};
const haftaGunu = (d) => ((d.getUTCDay() + 6) % 7) + 1; // 1 = Pazartesi … 7 = Pazar

const RESMI_TATIL = new Set(["2026-01-01", "2026-03-20", "2026-03-21", "2026-03-22", "2026-04-23", "2026-05-01",
  "2026-05-19", "2026-05-27", "2026-05-28", "2026-05-29", "2026-05-30", "2026-07-15", "2026-08-30", "2026-10-29"]);
// Kurulumda arife günü çalışma 13:00'te biter; 13:00'te ya da sonra başlayan vardiyaya gelinmez (T-28).
const ARIFE = new Set(["2026-03-19", "2026-05-26", "2026-10-28"]);
// Kurulum dışında arifelerde (28 Ekim vb.) tam gün okutma üretilir; 13:00 sonrası sistemde FM100 ya da havuz olur (docs/veritabani.md).

// Vardiya tanımları (veritabanındaki pdks.vardiya_tanim ile aynı kodlar)
const VARDIYA = {
  GUNDUZ: ["08:00", "17:00"], GUNDUZ_8: ["08:00", "16:00"], BEYAZ: ["08:30", "18:00"], ESNEK: ["07:00", "19:00"],
  V1: ["06:00", "14:00"], V2: ["14:00", "22:00"], V3: ["22:00", "06:00"],
  AKSAM_8: ["16:00", "00:00"], GECE_8: ["00:00", "08:00"],
};
const GUNDUZ_VARDIYALARI = new Set(["GUNDUZ", "GUNDUZ_8", "BEYAZ", "ESNEK", "V1"]);

// ---------------------------------------------------------------------
// 2. Organizasyon (departman adları seed.sql ile birebir aynı olmalı)
//    düzen: G=Gündüz 08-17 · G8=08-16 · A/B/C=V1/V2/V3 haftalık dönüşüm ·
//           R1/R2/R3=08-16/16-24/00-08 haftalık dönüşüm · BY=08:30-18:00 · E=esnek
// ---------------------------------------------------------------------
const DEPARTMANLAR = [
  { ad: "Aktif Kısım ve Montaj", yaka: "mavi", kisi: 30, pdks: "PDKS-1", duzen: () => "G" },
  { ad: "Bobinaj", yaka: "mavi", kisi: 32, pdks: "PDKS-2", duzen: (i) => (i < 2 ? "G" : "ABC"[i % 3]) },
  { ad: "Kalite Kontrol ve YG Test Laboratuvarı", yaka: "mavi", kisi: 11, pdks: "PDKS-1", duzen: () => "G", bolge: "YG-KAPI" },
  { ad: "İdari İşler", yaka: "mavi", kisi: 9, pdks: "PDKS-1", duzen: (i) => (i < 6 ? "G" : `R${(i % 3) + 1}`) },
  { ad: "Nüve Dizme", yaka: "mavi", kisi: 17, pdks: "PDKS-3", duzen: (i) => (i < 1 ? "G8" : `R${(i % 3) + 1}`) },
  { ad: "Kazan İmalat ve Kaynak", yaka: "mavi", kisi: 21, pdks: "PDKS-3", duzen: (i) => (i < 1 ? "G8" : `R${(i % 3) + 1}`) },
  { ad: "Boyahane ve Yüzey İşlem", yaka: "mavi", kisi: 8, pdks: "PDKS-1", duzen: () => "G8", bolge: "BOYA-KAPI" },
  { ad: "Bakım ve Onarım", yaka: "mavi", kisi: 8, pdks: "PDKS-1", duzen: (i) => (i < 5 ? "G8" : `R${(i % 3) + 1}`), bolge: "IKISI" },
  { ad: "Depo ve Sevkiyat", yaka: "mavi", kisi: 11, pdks: "PDKS-1", duzen: () => "G8" },
  { ad: "Ar-Ge ve Tasarım", yaka: "beyaz", kisi: 6, pdks: "PDKS-1", duzen: (i) => (i % 2 ? "E" : "BY") },
  { ad: "Üretim Planlama", yaka: "beyaz", kisi: 4, pdks: "PDKS-1", duzen: () => "BY" },
  { ad: "Satış ve Pazarlama", yaka: "beyaz", kisi: 4, pdks: "PDKS-1", duzen: (i) => (i % 2 ? "E" : "BY") },
  { ad: "Dış Ticaret ve Lojistik", yaka: "beyaz", kisi: 3, pdks: "PDKS-1", duzen: () => "BY" },
  { ad: "Satın Alma", yaka: "beyaz", kisi: 3, pdks: "PDKS-1", duzen: () => "BY" },
  { ad: "İnsan Kaynakları", yaka: "beyaz", kisi: 3, pdks: "PDKS-1", duzen: () => "BY" },
  { ad: "İSG", yaka: "beyaz", kisi: 2, pdks: "PDKS-1", duzen: () => "BY" },
  { ad: "Finans ve Muhasebe", yaka: "beyaz", kisi: 3, pdks: "PDKS-1", duzen: () => "BY" },
  { ad: "Bilgi İşlem", yaka: "beyaz", kisi: 3, pdks: "PDKS-1", duzen: () => "BY" },
  { ad: "Üst Yönetim", yaka: "beyaz", kisi: 2, pdks: "PDKS-1", duzen: () => "BY" },
];

// Seed'de olmayan, bu veri setiyle eklenen okuyucular
const YENI_OKUYUCULAR = [
  ["PDKS-3", "Kazan-Nüve atölye PDKS", "pdks", "Kazan ve nüve atölyesi girişi"],
  ["KAPI-2", "Personel kapısı turnike", "kapi", "Fabrika arka personel kapısı"],
  ["SRV-3", "Servis 3 (Karşıyaka)", "servis", "Servis aracı"],
  ["SRV-4", "Servis 4 (Çiğli)", "servis", "Servis aracı"],
  ["SRV-5", "Servis 5 (Menemen)", "servis", "Servis aracı"],
  ["SRV-6", "Servis 6 (Kemalpaşa)", "servis", "Servis aracı"],
  ["SRV-7", "Servis 7 (Torbalı)", "servis", "Servis aracı"],
];
const SERVISLER = ["SRV-1", "SRV-2", "SRV-3", "SRV-4", "SRV-5", "SRV-6", "SRV-7"];

// ---------------------------------------------------------------------
// 3. İsimler (listeler scripts/isimler.mjs'te)
//    Ad, kişinin doğum kuşağına göre seçilir: 1955–79 / 1980–94 / 1995 sonrası.
//    Soyad: %55 sık soyadlarından (Zipf), %45 uzun kuyruktan (eşit ağırlık).
// ---------------------------------------------------------------------
const tekil = (dizi) => [...new Set(dizi)];
const secici = {
  E: { genel: zipfSecici(tekil(I.ERKEK_GENEL), 0.7), eski: zipfSecici(tekil(I.ERKEK_ESKI), 0.4),
       orta: zipfSecici(tekil(I.ERKEK_ORTA), 0.4), yeni: zipfSecici(tekil(I.ERKEK_YENI), 0.3), cift: I.ERKEK_CIFT },
  K: { genel: zipfSecici(tekil(I.KADIN_GENEL), 0.7), eski: zipfSecici(tekil(I.KADIN_ESKI), 0.4),
       orta: zipfSecici(tekil(I.KADIN_ORTA), 0.4), yeni: zipfSecici(tekil(I.KADIN_YENI), 0.4), cift: I.KADIN_CIFT },
};
// Kuşağa göre hangi listeden seçileceği: [genel, eski, orta, yeni]
const KUSAK_AGIRLIK = { eski: [0.5, 0.42, 0.08, 0], orta: [0.4, 0.08, 0.44, 0.08], yeni: [0.3, 0, 0.18, 0.52] };
function adSec(cinsiyet, dogumYili) {
  const s = secici[cinsiyet];
  if (olasilik(0.07)) return sec(s.cift);
  const kusak = dogumYili < 1980 ? "eski" : dogumYili < 1995 ? "orta" : "yeni";
  const [g, e, o] = KUSAK_AGIRLIK[kusak];
  const x = r();
  return (x < g ? s.genel : x < g + e ? s.eski : x < g + e + o ? s.orta : s.yeni)();
}
const sikSoyad = zipfSecici(tekil(I.SOYAD_SIK), 0.3);
const seyrekSoyadlar = tekil(I.SOYAD_SEYREK).filter((x) => !I.SOYAD_SIK.includes(x));
const soyad = () => (olasilik(0.55) ? sikSoyad() : sec(seyrekSoyadlar));
// İşe girişteki yaş (mavi yaka 19–40, beyaz yaka 22–45); bugün 63 yaşını geçmez
function dogumYili(iseGiris, yaka) {
  const girisYili = iseGiris.getUTCFullYear();
  const enYasli = Math.min(yaka === "mavi" ? 40 : 45, 63 - (bugun.getUTCFullYear() - girisYili));
  const enGenc = yaka === "mavi" ? 19 : 22;
  return girisYili - aralik(enGenc, Math.max(enGenc, Math.round(Math.min(enYasli, normal(27, 5)))));
}

// ---------------------------------------------------------------------
// 4. Çalışanlar, sicil ve kart numaraları
//    Sicil: işe giriş yılı + o yıl içindeki sıra no, 8 hane, ör. 20180014 (ayrıntı aşağıda).
//           Seed'in 4 haneli demo sicilleriyle (1001…6903) çakışmaz.
//    Kart:  10 haneli ondalık kart numarası (125 kHz EM kartlarının üzerinde basılı
//           biçim, ör. 0004817263). Her kart tek; geçici kartlar (GK-..) ile çakışmaz.
// ---------------------------------------------------------------------
const donemBas = gun(BAS);
const donemBit = gun(KURULUM ? KURULUM_PLAN_BIT : BIT);
const okutmaSonu = gunEkle(gun(BIT), 1); // bu andan önceki okutmalar yazılır (kurulum)
const bugun = gun(BUGUN);

function iseGirisTarihi(yaka) {
  // Kıdem: mavi yakada ortalama ~6, beyaz yakada ~8 yıl (üstel dağılım), en eski 1998
  const ortalamaYil = yaka === "mavi" ? 6 : 8;
  let yil;
  do yil = -Math.log(1 - r()) * ortalamaYil; while (yil > 28);
  const d = gunEkle(donemBas, -Math.round(yil * 365) - aralik(1, 30));
  return haftaGunu(d) >= 6 ? gunEkle(d, 8 - haftaGunu(d)) : d; // işe giriş hafta içi
}

// Kurulum kadrosunun sicilleri: kendi sabit tohumuyla üretilir; --tohum ya da tarih değişse de aynı çıkar.
// Biçim ve sıra kuralı diğer çalışanlarla aynıdır (aşağıda "Sicil").
const YILLIK_ISE_ALIM = 30;
const siraHedefi = (d) => 1 + Math.floor(((d - gun(`${d.getUTCFullYear()}-01-01`)) / 86400000 / 366) * YILLIK_ISE_ALIM);
const kadroSicilleri = new Set();
const kadro = KURULUM ? KADRO.map((x) => ({ ...x, ise_giris: gun(x.ise_giris) })) : [];
if (KURULUM) {
  const kr = uretec(20260101);
  [...kadro].sort((a, b) => a.ise_giris - b.ise_giris).forEach((x) => {
    if (haftaGunu(x.ise_giris) >= 6) throw new Error(`Kadro işe giriş tarihi hafta sonu: ${x.ad} ${x.soyad}`);
    let sira = siraHedefi(x.ise_giris) + Math.floor(kr() * 2);
    const no = () => `${x.ise_giris.getUTCFullYear()}${String(sira).padStart(4, "0")}`;
    while (kadroSicilleri.has(no())) sira += 1;
    x.sicil = no();
    kadroSicilleri.add(x.sicil);
  });
  for (const x of kadro) if (!DEPARTMANLAR.some((d) => d.ad === x.departman)) throw new Error(`Kadro departmanı yok: ${x.departman}`);
}

const kisiler = [];
DEPARTMANLAR.forEach((dep) => {
  const depKadro = kadro.filter((x) => x.departman === dep.ad); // departmanın ilk kişileri kadrodur
  if (depKadro.length > dep.kisi) throw new Error(`Kadro departman mevcudunu aşıyor: ${dep.ad}`);
  for (let i = 0; i < dep.kisi; i++) {
    const x = depKadro[i];
    if (x) {
      kisiler.push({
        kadro: x, ad: x.ad, soyad: x.soyad, sicil: x.sicil, dogum: x.dogum, dep, duzen: dep.duzen(i),
        ise_giris: x.ise_giris, isten_cikis: null,
        servis: olasilik(dep.yaka === "mavi" ? 0.65 : 0.22) ? sec(SERVISLER) : null,
        yemek: dep.yaka === "mavi" ? 0.9 : 0.72,
        erkenci: normal(13, 5),
        kapi: olasilik(0.8) ? "KAPI-1" : "KAPI-2",
      });
      continue;
    }
    const cinsiyet = olasilik(dep.yaka === "mavi" ? 0.07 : 0.42) ? "K" : "E";
    const iseGiris = iseGirisTarihi(dep.yaka);
    const duzen = dep.duzen(i);
    kisiler.push({
      cinsiyet, dogum: dogumYili(iseGiris, dep.yaka), soyad: soyad(), dep, duzen,
      ise_giris: iseGiris,
      isten_cikis: null,
      servis: olasilik(dep.yaka === "mavi" ? 0.65 : 0.22) ? sec(SERVISLER) : null,
      yemek: dep.yaka === "mavi" ? 0.9 : 0.72,  // yemekhanede okutma olasılığı
      erkenci: normal(13, 5),                     // kişisel alışkanlık: vardiyadan kaç dk önce gelir
      kapi: olasilik(0.8) ? "KAPI-1" : "KAPI-2",
    });
  }
});
// Dönem içinde işe girenler (2 kişi) ve işten çıkanlar (2 kişi)
const donemGunleri = [];
for (let d = donemBas; d <= donemBit; d = gunEkle(d, 1)) donemGunleri.push(d);
const isGunleri = donemGunleri.filter((d) => haftaGunu(d) <= 5 && !RESMI_TATIL.has(gunMetni(d)));
// Kurulumda giriş / çıkışlar geçmişte kalır (veri ileri tarihli günleri de kapsar)
const hareketGunleri = KURULUM ? isGunleri.filter((d) => d < bugun) : isGunleri;
const mavi = kisiler.filter((k) => k.dep.yaka === "mavi" && !k.kadro);
for (let i = 0; i < 2; i++) {
  const k = sec(mavi);
  k.ise_giris = sec(hareketGunleri.slice(1, -3));
  k.dogum = dogumYili(k.ise_giris, "mavi");
}
for (let i = 0; i < 2; i++) {
  const k = sec(kisiler.filter((x) => x.ise_giris < donemBas && !x.isten_cikis && !x.kadro));
  k.isten_cikis = sec(hareketGunleri.slice(3, -1));
}
// Geçmişte ayrılmış ~8 eski çalışan (pasif; okutması yok, ama çalışan listesinde görünür)
DEPARTMANLAR.filter((d) => d.yaka === "mavi").forEach((dep) => {
  const adet = Math.round((8 * dep.kisi) / mavi.length);
  for (let i = 0; i < adet; i++) {
    const giris = iseGirisTarihi("mavi");
    let cikis = gunEkle(donemBas, -aralik(20, 600));
    if (cikis <= giris) cikis = gunEkle(giris, aralik(60, 400));
    if (cikis >= donemBas) continue;
    kisiler.push({ cinsiyet: olasilik(0.07) ? "K" : "E", dogum: dogumYili(giris, "mavi"), soyad: soyad(), dep, duzen: "-",
      ise_giris: giris, isten_cikis: cikis, servis: null, eski: true });
  }
});

// Adlar (kuşağa göre)
kisiler.forEach((k) => { if (!k.kadro) k.ad = adSec(k.cinsiyet, k.dogum); });

// Sicil: <işe giriş yılı (4 hane)><o yıl içindeki sıra no (4 hane)> = 8 hane, ör. 20180214
//   (2018'de işe giren 14. kişi). Firma her yıl ~YILLIK_ISE_ALIM kişi işe alır ve yılbaşında
//   sıra 0001'den başlar. Ayrılanın numarası yeniden verilmez; bugün çalışanlar o yılın işe
//   alınanlarından kalanlardır: eski yıllarda numaralar seyrek, son yıllarda sık.
//   Kurulumda kadronun numaraları ayrılmıştır; diğerleri onları atlar.
const oncekiSira = new Map();
[...kisiler].filter((k) => !k.kadro).sort((a, b) => a.ise_giris - b.ise_giris).forEach((k) => {
  const yil = k.ise_giris.getUTCFullYear();
  let sira = Math.max((oncekiSira.get(yil) ?? 0) + 1, siraHedefi(k.ise_giris) + aralik(0, 1));
  while (kadroSicilleri.has(`${yil}${String(sira).padStart(4, "0")}`)) sira += 1;
  oncekiSira.set(yil, sira);
  k.sicil = `${yil}${String(sira).padStart(4, "0")}`;
});

// Kart numaraları
const kullanilanKart = new Set();
const yeniKartNo = () => {
  let no;
  do no = String(aralik(1_000_000, 16_777_215)).padStart(10, "0");
  while (kullanilanKart.has(no));
  kullanilanKart.add(no);
  return no;
};
const kartlar = [];
kisiler.forEach((k) => {
  let verilis = k.ise_giris;
  // ~%5'inin kartı geçmişte kayboldu ya da yıprandığı için yenilendi
  if (!k.eski && olasilik(0.05)) {
    const iptal = gunEkle(donemBas, -aralik(15, 700));
    if (iptal > verilis) {
      kartlar.push({ no: yeniKartNo(), sicil: k.sicil, durum: "iptal", neden: olasilik(0.6) ? "kayip" : "yenilendi",
        verilis, iptal: zamanMetni(saatte(iptal, "09:15")) });
      verilis = iptal;
    }
  }
  k.kart = yeniKartNo();
  const ayrildi = k.isten_cikis && k.isten_cikis < bugun;
  kartlar.push({ no: k.kart, sicil: k.sicil, durum: ayrildi ? "iptal" : "aktif", neden: ayrildi ? "isten_cikis" : "",
    verilis, iptal: ayrildi ? zamanMetni(saatte(gunEkle(k.isten_cikis, 1), "10:00")) : "" }); // son vardiya gece bitebilir
});

// ---------------------------------------------------------------------
// 5. İzinler (kişi başına dönemde en fazla bir izin) ve vardiya planı
// ---------------------------------------------------------------------
const aktifKisiler = kisiler.filter((k) => !k.eski);
const izinler = [];
aktifKisiler.forEach((k) => {
  const x = r();
  const [tur, gunSayisi, aciklama] =
    x < 0.08 ? ["yillik", aralik(1, 5), "Yıllık izin"]
    : x < 0.11 ? ["rapor", aralik(1, 3), "Doktor raporu"]
    : x < 0.13 ? ["mazeret", 1, sec(["Mazeret izni", "Evlilik / doğum / vefat mazereti"])]
    : x < 0.135 ? ["ucretsiz", aralik(1, 2), "Ücretsiz izin"]
    : [null];
  if (!tur) return;
  const uygun = isGunleri.filter((d) => d >= k.ise_giris && (!k.isten_cikis || d <= k.isten_cikis));
  if (uygun.length < gunSayisi + 1) return;
  const i = aralik(0, uygun.length - gunSayisi);
  k.izin = { tur, bas: uygun[i], bit: uygun[i + gunSayisi - 1] };
  izinler.push({ sicil: k.sicil, tur, bas: gunMetni(uygun[i]), bit: gunMetni(uygun[i + gunSayisi - 1]), aciklama });
});

const ilkPazartesi = gunEkle(donemBas, 1 - haftaGunu(donemBas));
function vardiyaKodu(k, d) {
  const hafta = Math.floor((d - ilkPazartesi) / (7 * 86400000));
  if (k.duzen === "G") return "GUNDUZ";
  if (k.duzen === "G8") return "GUNDUZ_8";
  if (k.duzen === "BY") return "BEYAZ";
  if (k.duzen === "E") return "ESNEK";
  if ("ABC".includes(k.duzen)) return ["V1", "V2", "V3"][("ABC".indexOf(k.duzen) + hafta) % 3];
  return ["GUNDUZ_8", "AKSAM_8", "GECE_8"][(Number(k.duzen[1]) - 1 + hafta) % 3];
}
const planlar = [];
aktifKisiler.forEach((k) => {
  isGunleri.forEach((d) => {
    if (d < k.ise_giris || (k.isten_cikis && d > k.isten_cikis)) return;
    const v = vardiyaKodu(k, d);
    planlar.push({ k, d, v });
  });
});

// ---------------------------------------------------------------------
// 6. Okutmalar
// ---------------------------------------------------------------------
const okutmalar = []; // { kaynak, okuyucu, kart, zaman(Date), yon }
const ekle = (kaynak, okuyucu, kart, zaman, yon) => okutmalar.push({ kaynak, okuyucu, kart, zaman, yon });
const sayac = {};
let sayilir = true; // kurulumda okutması yazılmayan günler özete sayılmaz
const say = (ad) => { if (sayilir) sayac[ad] = (sayac[ad] ?? 0) + 1; };

// Servis seferleri: aynı gün, aynı hat, aynı vardiya için tek sefer → kişiler birkaç saniye arayla okutur
const sefer = new Map();
function seferZamani(hat, tarih, v, yon, taban) {
  const anahtar = `${hat}|${tarih}|${v}|${yon}`;
  if (!sefer.has(anahtar)) {
    sefer.set(anahtar, { saat: yon === "giris" ? dkEkle(taban, -aralik(22, 30)) : dkEkle(taban, aralik(12, 16)), sira: 0 });
  }
  const s = sefer.get(anahtar);
  s.sira += 1;
  return snEkle(s.saat, s.sira * aralik(3, 9));
}

// Geçici kart havuzu GK-10 … GK-39 (seed GK-01 … GK-05'i kullanır)
const geciciKartlar = Array.from({ length: 30 }, (_, i) => ({ no: `GK-${i + 10}`, bosZaman: new Date(0) }));
const zimmetler = [];

planlar.forEach(({ k, d, v }) => {
  const tarih = gunMetni(d);
  sayilir = !KURULUM || d < okutmaSonu;
  if (k.izin && d >= k.izin.bas && d <= k.izin.bit) return say("izinli_gun");
  if (olasilik(0.003)) return say("devamsiz_gun"); // haber vermeden gelmedi: hiç okutma yok

  const [bs, bt] = VARDIYA[v];
  const bas = saatte(d, bs);
  let bit = saatte(v === "AKSAM_8" || v === "V3" ? gunEkle(d, 1) : d, bt);
  const arife = KURULUM && ARIFE.has(tarih) ? saatte(d, "13:00") : null;
  if (arife) {
    if (bas >= arife) return say("arife_tatil_gunu");
    if (bit > arife) bit = arife;
  }

  // PDKS giriş ve çıkış saatleri
  let giris, cikis;
  let gec = false;
  if (v === "ESNEK") {
    giris = dkEkle(saatte(d, "08:00"), aralik(0, 90) + r());
    cikis = dkEkle(giris, 540 + aralik(-35, 35));
    if (arife) cikis = dkEkle(arife, aralik(1, 10) + r());
  } else {
    giris = dkEkle(bas, -Math.max(1, normal(k.erkenci, 4)) + r());
    if (olasilik(0.03)) { giris = dkEkle(bas, aralik(6, 45) + r()); gec = true; say("gec_kalma"); }
    cikis = dkEkle(bit, aralik(1, 10) + r());
    if (olasilik(0.01)) { cikis = dkEkle(bit, -aralik(15, 90) - r()); say("erken_cikis"); }
    else if (olasilik(0.007)) { cikis = dkEkle(bit, aralik(30, 120) + r()); say("gec_cikis_fazla_mesai"); }
  }

  // Kart: ~%0,25 olasılıkla kartını unuttu → güvenlikten geçici kart
  let kart = k.kart;
  let gecici = null;
  const gunIlkOkutma = okutmalar.length;
  if (olasilik(0.0025)) {
    // Kart boşta mı? (kesin veriliş / iade saati, o günün okutmaları yazıldıktan sonra belirlenir)
    const gk = geciciKartlar.find((g) => g.bosZaman < dkEkle(giris, -20));
    // Kartı veren güvenlik görevlisi kendine kart veremez (görevler ayrılığı)
    if (gk && k.kadro?.rol !== "guvenlik") {
      kart = gk.no;
      gecici = gk;
      say("gecici_kart_gunu");
    }
  }

  // Bilerek konan hatalar (gerçek PDKS'deki tipik oranlar)
  const x = r();
  const girisYok = x < 0.012;                   // PDKS'de giriş unutuldu, kapı kaydı var
  const cikisYok = x >= 0.012 && x < 0.027;     // PDKS'de çıkış unutuldu, kapı kaydı var
  const izYok = x >= 0.027 && x < 0.029;        // çıkışa dair hiçbir kayıt yok (kapı da)
  const mukerrer = x >= 0.029 && x < 0.037;     // giriş iki kez okutuldu
  if (girisYok) say("pdks_giris_eksik");
  if (cikisYok) say("pdks_cikis_eksik");
  if (izYok) say("cikis_hic_yok");
  if (mukerrer) say("mukerrer_okutma");

  // Servisle gelenler (geç kalan o gün servisi kaçırmıştır): önce servis, sonra kapı (servis inişi), sonra PDKS
  let kapiGiris = dkEkle(giris, -aralik(2, 6) - r());
  let kapiCikis = dkEkle(cikis, aralik(2, 5) + r());
  const servisle = k.servis && !gecici && !gec && v !== "ESNEK";
  if (servisle) {
    const sg = seferZamani(k.servis, tarih, v, "giris", bas);
    ekle("servis", k.servis, kart, sg, "giris");
    kapiGiris = dkEkle(sg, aralik(1, 3) + r());
    if (giris <= kapiGiris) giris = dkEkle(kapiGiris, aralik(2, 6) + r());
    const sc = seferZamani(k.servis, tarih, v, "cikis", bit);
    if (cikis < sc && !izYok) { // servisi kaçırmadıysa
      ekle("servis", k.servis, kart, sc, "cikis");
      if (kapiCikis > sc) kapiCikis = dkEkle(sc, -aralik(1, 3));
    }
  }

  ekle("kapi", k.kapi, kart, kapiGiris, "giris");
  if (!girisYok) ekle("pdks", k.dep.pdks, kart, giris, "giris");
  if (mukerrer) ekle("pdks", k.dep.pdks, kart, snEkle(giris, aralik(4, 50)), "giris");
  if (!cikisYok && !izYok) ekle("pdks", k.dep.pdks, kart, cikis, "cikis");
  if (!izYok) ekle("kapi", k.kapi, kart, kapiCikis, "cikis");

  // Yemekhane (vardiyanın ortasına yakın)
  if (olasilik(k.yemek)) {
    const ogun = { GUNDUZ: "12:00", GUNDUZ_8: "12:00", BEYAZ: "12:15", ESNEK: "12:15", V1: "10:00",
      V2: "18:00", V3: "02:00", AKSAM_8: "19:30", GECE_8: "03:30" }[v];
    const yemekGunu = v === "V3" ? gunEkle(d, 1) : d;
    ekle("yemekhane", "YMK-1", kart, dkEkle(saatte(yemekGunu, ogun), aralik(0, 45) + r()), null);
  }

  // İSG bölge kapıları
  const bolge = k.dep.bolge;
  if (bolge && GUNDUZ_VARDIYALARI.has(v) && olasilik(bolge === "IKISI" ? 0.15 : 0.35)) {
    const kapi = bolge === "IKISI" ? sec(["YG-KAPI", "BOYA-KAPI"]) : bolge;
    ekle("kapi", kapi, kart, dkEkle(giris, aralik(30, 300) + r()), "giris");
  }
  if (k.dep.ad === "Depo ve Sevkiyat" && v === "GUNDUZ_8" && olasilik(0.01)) {
    ekle("kapi", "BOYA-KAPI", kart, dkEkle(giris, aralik(60, 360) + r()), "giris");
    say("yetkisiz_bolge_gecisi");
  }

  // Geçici kart: güvenlik ilk okutmadan önce verir, son okutmadan sonra iade alır
  if (gecici) {
    const zamanlar = okutmalar.slice(gunIlkOkutma).map((o) => o.zaman.getTime());
    const verilis = dkEkle(new Date(Math.min(...zamanlar)), -aralik(2, 5));
    const iade = dkEkle(new Date(Math.max(...zamanlar)), aralik(1, 4));
    gecici.bosZaman = iade;
    zimmetler.push({ kart: gecici.no, sicil: k.sicil, verilis: zamanMetni(verilis), iade: zamanMetni(iade) });
  }
});

// Aynı okuyucu + kart + zaman (saniye) iki kez olamaz (veritabanında unique)
const benzersiz = new Map();
okutmalar.forEach((o) => {
  o.zaman = new Date(Math.floor(o.zaman.getTime() / 1000) * 1000);
  benzersiz.set(`${o.okuyucu}|${o.kart}|${o.zaman.getTime()}`, o);
});
const tumOkutmalar = [...benzersiz.values()].filter((o) => !KURULUM || o.zaman < okutmaSonu).sort((a, b) => a.zaman - b.zaman);
if (KURULUM) {
  // Son günden sonra verilen kart yazılmaz; son günden sonra iade edilecek kart iade edilmemiş kalır
  const sinir = zamanMetni(okutmaSonu);
  const kalan = zimmetler.filter((z) => z.verilis < sinir).map((z) => (z.iade < sinir ? z : { ...z, iade: "" }));
  zimmetler.splice(0, zimmetler.length, ...kalan);
  // İleri tarihli rapor ve mazeret bilinemez; yıllık / ücretsiz izin önceden girilmiş olabilir
  const gecerli = izinler.filter((i) => i.bas <= BIT || !["rapor", "mazeret"].includes(i.tur));
  izinler.splice(0, izinler.length, ...gecerli);
}

// ---------------------------------------------------------------------
// 7. Dosyaları yaz
// ---------------------------------------------------------------------
rmSync(CIKTI, { recursive: true, force: true });
mkdirSync(join(CIKTI, "okutma"), { recursive: true });
const yaz = (ad, basliklar, satirlar) =>
  writeFileSync(join(CIKTI, ad), [basliklar.join(";"), ...satirlar.map((s) => s.join(";"))].join("\n") + "\n", "utf8");

const tumKisiler = [...kisiler].sort((a, b) => a.sicil.localeCompare(b.sicil));
yaz("calisanlar.csv",
  ["sicil_no", "ad", "soyad", "departman", "yaka", "vardiya_duzeni", "ise_giris_tarihi", "isten_cikis_tarihi", "kart_no", "servis"],
  tumKisiler.map((k) => [k.sicil, k.ad, k.soyad, k.dep.ad, k.dep.yaka, k.duzen, gunMetni(k.ise_giris),
    k.isten_cikis ? gunMetni(k.isten_cikis) : "", k.kart, k.servis ?? ""]));
if (KURULUM) yaz("kullanicilar.csv", ["eposta", "rol", "sicil_no"], kadro.map((x) => [x.eposta, x.rol, x.sicil]));
yaz("kartlar.csv", ["kart_no", "sicil_no", "durum", "iptal_nedeni", "verilis_tarihi", "iptal_zamani"],
  kartlar.map((c) => [c.no, c.sicil, c.durum, c.neden, gunMetni(c.verilis), c.iptal]));
yaz("vardiya_plani.csv", ["sicil_no", "tarih", "vardiya_kod"], planlar.map((p) => [p.k.sicil, gunMetni(p.d), p.v]));
yaz("izinler.csv", ["sicil_no", "tur", "baslangic", "bitis", "aciklama"],
  izinler.map((i) => [i.sicil, i.tur, i.bas, i.bit, i.aciklama]));
yaz("gecici_kart_zimmet.csv", ["gecici_kart_no", "sicil_no", "verilis_zamani", "iade_zamani"],
  zimmetler.map((z) => [z.kart, z.sicil, z.verilis, z.iade]));

// İSG belgeleri: mavi yakada herkesin eğitimi ve muayenesi; birkaçının süresi doluyor / dolmuş
const isg = [];
let belgeSira = 0;
aktifKisiler.filter((k) => k.dep.yaka === "mavi").forEach((k) => {
  [["isg_egitimi", "E"], ["saglik_muayenesi", "M"]].forEach(([tur, kisa]) => {
    const x = r();
    const bitis = x < 0.01 ? gunEkle(bugun, -aralik(1, 40))       // süresi dolmuş
      : x < 0.03 ? gunEkle(bugun, aralik(1, 30))                   // 30 gün içinde doluyor
      : gunEkle(bugun, aralik(45, 900));
    isg.push([k.sicil, tur, gunMetni(bitis), `ISG-${kisa}-${String(++belgeSira).padStart(5, "0")}`]);
  });
});
yaz("isg_belgeleri.csv", ["sicil_no", "tur", "gecerlilik_bitis", "belge_no"], isg);

// Yazılı fazla mesai onayı (yalnızca kurulum): çalışanların ~%90'ında, 2026 yılbaşı imzalı; yıl içinde
// girenlerde işe giriş tarihli. Kendi üretecini kullanır, diğer veriyi etkilemez.
const fmOnaylari = [];
if (KURULUM) {
  const fr = uretec(TOHUM + 1);
  [...aktifKisiler].sort((a, b) => a.sicil.localeCompare(b.sicil)).forEach((k) => {
    if (fr() >= 0.9) return;
    const yilBasi = gun("2026-01-05"); // yılın ilk iş haftası
    fmOnaylari.push([k.sicil, gunMetni(k.ise_giris > yilBasi ? k.ise_giris : yilBasi), `FMO-2026-${k.sicil}`]);
  });
  yaz("fazla_mesai_onaylari.csv", ["sicil_no", "imza_tarihi", "belge_no"], fmOnaylari);
}

// Okutma dosyaları: her kaynak için her gün bir dosya (uygulamanın Veri Aktarımı ekranındaki biçim)
const dosyalar = [];
// Dönemin her günü (+ ertesi sabah) için dosya yazılır, boş olsa bile: "dosya gelmedi" uyarısı çıkmasın
// Kurulumda son günden sonrasına boş dosya yazılmaz: o günün dosyası demoda yüklenecek olabilir
const gunler = [...new Set((KURULUM ? donemGunleri.filter((d) => d < okutmaSonu) : [...donemGunleri, gunEkle(donemBit, 1)]).map(gunMetni)
  .concat(tumOkutmalar.map((o) => gunMetni(o.zaman))))].sort();
for (const kaynak of ["pdks", "kapi", "yemekhane", "servis"]) {
  for (const g of gunler) {
    const satirlar = tumOkutmalar.filter((o) => o.kaynak === kaynak && gunMetni(o.zaman) === g);
    if (!satirlar.length && (g < BAS || (g > BIT && ["yemekhane", "servis"].includes(kaynak)))) continue;
    const ad = `${kaynak}_${g.replaceAll("-", "")}.csv`;
    const icerik = ["okuyucu;kart_no;zaman;yon", ...satirlar.map((o) => `${o.okuyucu};${o.kart};${zamanMetni(o.zaman)};${o.yon ?? ""}`)]
      .join("\n") + "\n";
    writeFileSync(join(CIKTI, "okutma", ad), icerik, "utf8");
    dosyalar.push([kaynak, ad, g, satirlar.length, createHash("sha256").update(satirlar.length ? icerik : ad + icerik, "utf8").digest("hex")]);
  }
}
yaz("okutma/dosyalar.csv", ["kaynak", "dosya_adi", "veri_tarihi", "satir_sayisi", "dosya_ozeti"], dosyalar);

// ---------------------------------------------------------------------
// 8. Yükleme betiği (psql) — tüm satırlar \copy ile CSV'den okunur
// ---------------------------------------------------------------------
const yol = (ad) => `${CIKTI}/${ad}`.replaceAll("\\", "/");
const kopya = (tablo, ad) => `\\copy ${tablo} from '${yol(ad)}' with (format csv, header true, delimiter ';', encoding 'UTF8')`;
// Kayıtları giren kullanıcılar. Kurulumda kadrodan, yoksa seed'in demo sicillerinden bulunur.
const kisiBul = (rol, gorev) => kadro.find((x) => x.rol === rol && (!gorev || x.gorev === gorev))?.sicil;
const SICIL_IK = KURULUM ? kisiBul("ik", "İK uzmanı") : "4001";
const SICIL_IK_MUDUR = KURULUM ? kisiBul("ik", "İK müdürü") : null;
const SICIL_GUVENLIK = KURULUM ? kisiBul("guvenlik") : "4003";
const SICIL_ISG = KURULUM ? kisiBul("isg") : "6602";
const kullaniciSec = (sicil, rol) =>
  `(select k.id from pdks.kullanici k join pdks.calisan x on x.id = k.calisan_id where x.sicil_no = '${sicil}' and k.rol = '${rol}')`;
// İK uzmanının kendi kayıtlarını İK müdürü girer (görevler ayrılığı)
const girenIk = (sutun) => (KURULUM
  ? `case when ${sutun} = '${SICIL_IK}' then ${kullaniciSec(SICIL_IK_MUDUR, "ik")} else ${kullaniciSec(SICIL_IK, "ik")} end`
  : kullaniciSec(SICIL_IK, "ik"));
const tirnak = (x) => `'${x.replaceAll("'", "''")}'`;

const onKosul = KURULUM ? `do $$
begin
    if (select count(*) from pdks.departman) <> 19 or not exists (select 1 from pdks.bolge where kod = 'YG-LAB') then
        raise exception 'Önce supabase/canli/kurulum.sql yüklenmeli (19 departman ve bölgeler yok).';
    end if;
    if exists (select 1 from pdks.calisan) or exists (select 1 from pdks.kullanici) then
        raise exception 'Veritabanında çalışan ya da kullanıcı var; kurulum yalnızca boş veriye yüklenir.';
    end if;
end $$;` : `do $$
begin
    if not exists (select 1 from pdks.kullanici k join pdks.calisan x on x.id = k.calisan_id where x.sicil_no = '4001' and k.rol = 'ik') then
        raise exception 'Önce supabase/seed.sql yüklenmeli (sicil 4001 İK kullanıcısı yok).';
    end if;
    if exists (select 1 from pdks.calisan where sicil_no ~ '^(19|20)[0-9]{6}$') then
        raise exception 'Sentetik veri zaten yüklü (20180214 biçiminde 8 haneli sicil var); işlem yapılmadı.';
    end if;
end $$;`;

// Kullanıcılar: çalışanlardan sonra, kartlardan önce (iptal eden, giren ve veren kullanıcılar gerekir)
const depYaka = (ad) => DEPARTMANLAR.find((d) => d.ad === ad).yaka;
const ustAmir = (x) => (x.amiri && ![MAVI_UST_AMIR, BEYAZ_UST_AMIR].includes(x.eposta)
  ? (depYaka(x.departman) === "mavi" ? MAVI_UST_AMIR : BEYAZ_UST_AMIR) : null);
const kullaniciSql = KURULUM ? `
-- Kullanıcılar (hepsi bir çalışana bağlı). İK ve admin hesapları AKTİF açılır: ilk kurulumda rol önerisini
-- onaylayacak İK henüz yoktur; kullanici_gecmisi'ne "yapan" boş yazılır (T-72, T-33).
create temp table s_kullanici (eposta text, rol text, sicil_no text) on commit drop;
${kopya("s_kullanici", "kullanicilar.csv")}
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, aktif)
select '', s.eposta, s.rol, c.id, true   -- ad_soyad'ı trigger çalışan kaydından yazar (T-105)
from s_kullanici s join pdks.calisan c on c.sicil_no = s.sicil_no
order by s.eposta;

-- Üst amir zinciri, departman amirleri ve vekil
update pdks.kullanici k set ust_amir_id = u.id
from (values
${kadro.filter(ustAmir).map((x) => `    (${tirnak(x.eposta)}, ${tirnak(ustAmir(x))})`).join(",\n")}) v(eposta, ust)
join pdks.kullanici u on u.eposta = v.ust
where k.eposta = v.eposta;

update pdks.departman d set amir_id = k.id
from (values
${kadro.filter((x) => x.amiri).map((x) => `    (${tirnak(x.amiri)}, ${tirnak(x.eposta)})`).join(",\n")}) v(departman, eposta)
join pdks.kullanici k on k.eposta = v.eposta
where d.ad = v.departman;

update pdks.departman set vekil_amir_id = (select id from pdks.kullanici where eposta = ${tirnak(BOBINAJ_VEKILI)}) where ad = 'Bobinaj';

-- Bölge yetkileri (İSG uzmanı verir)
insert into pdks.bolge_yetkisi (bolge_id, departman_id, veren_id)
select b.id, d.id, ${kullaniciSec(SICIL_ISG, "isg")}
from (values ('YG-LAB', 'Kalite Kontrol ve YG Test Laboratuvarı'), ('YG-LAB', 'Bakım ve Onarım'),
             ('BOYAHANE', 'Boyahane ve Yüzey İşlem'), ('BOYAHANE', 'Bakım ve Onarım')) v(bolge, departman)
join pdks.bolge b on b.kod = v.bolge join pdks.departman d on d.ad = v.departman;
` : "";

const fmOnaySql = KURULUM ? `
-- Yazılı fazla mesai onayları (İş K. m.41)
create temp table s_fm_onay (sicil_no text, imza_tarihi date, belge_no text) on commit drop;
${kopya("s_fm_onay", "fazla_mesai_onaylari.csv")}
insert into pdks.fazla_mesai_onayi (calisan_id, yil, imza_tarihi, belge_no, giren_id)
select c.id, 2026, f.imza_tarihi, f.belge_no, ${girenIk("f.sicil_no")}
from s_fm_onay f join pdks.calisan c on c.sicil_no = f.sicil_no;
` : "";

const kontrolSql = KURULUM ? `
-- Kontrol bloğu: biri tutmazsa bütün yükleme geri alınır
do $$
declare
    v_hata text;
begin
    v_hata := concat_ws('; ',
        case when (select count(*) from pdks.kullanici where rol = 'ik' and aktif) < 2 then 'aktif İK 2''den az' end,
        case when (select count(*) from pdks.kullanici where rol = 'admin' and aktif) < 1 then 'aktif admin yok' end,
        case when (select count(*) from pdks.kullanici) <> 25 then 'kullanıcı sayısı 25 değil' end,
        case when exists (select 1 from pdks.kullanici k left join pdks.calisan c on c.id = k.calisan_id
                          where c.id is null or not c.aktif) then 'çalışana bağlı olmayan ya da çalışanı pasif kullanıcı var' end,
        case when exists (select 1 from pdks.departman d left join pdks.kullanici k on k.id = d.amir_id and k.aktif and k.rol = 'amir'
                          where k.id is null) then 'aktif amiri olmayan departman var' end,
        case when exists (select 1 from pdks.calisan group by sicil_no having count(*) > 1) then 'sicil tekrarı var' end,
        case when exists (select 1 from pdks.calisan where sicil_no !~ '^(19|20)[0-9]{6}$') then '8 haneli olmayan sicil var' end,
        case when exists (select 1 from pdks.kart group by kart_no having count(*) > 1)
               or exists (select 1 from pdks.kart where durum = 'aktif' group by calisan_id having count(*) > 1)
               or exists (select 1 from pdks.kart k join pdks.gecici_kart g on g.kart_no = k.kart_no) then 'kart tekrarı var' end,
        case when exists (select 1 from pdks.kullanici k where not exists
                          (select 1 from pdks.kart x where x.calisan_id = k.calisan_id and x.durum = 'aktif')) then 'kartı olmayan kullanıcı var' end);
    if v_hata <> '' then
        raise exception 'Kurulum kontrolü tutmadı: %', v_hata;
    end if;
    raise notice 'Kurulum kontrolü tamam: 25 kullanıcı, % aktif İK, % aktif admin, 19 departman amirli.',
        (select count(*) from pdks.kullanici where rol = 'ik' and aktif), (select count(*) from pdks.kullanici where rol = 'admin' and aktif);
end $$;
` : "";

const sql = `-- =====================================================================
-- Sentetik veri seti yükleyici (scripts/sentetik_veri.mjs üretti; elle değiştirmeyin)
-- Dönem: ${BAS} – ${BIT} · tohum ${TOHUM}
${KURULUM ? "-- Önce supabase/canli/kurulum.sql yüklenmiş olmalı (seed'siz kurulum; docs/canli_kurulum.md)." : "-- Önce supabase/seed.sql yüklenmiş olmalı (departmanlar; İK 4001, güvenlik 4003, İSG 6602 kullanıcıları)."}
-- Repo kökünden çalıştırın:
--   psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f ${yol("yukle.sql")}
-- Ardından gece işini dönemin her günü için çalıştırın (iş günü başına ~1 dk):
--   select g::date, pdks.gece_isi_calistir(g::date)
--   from generate_series(date '${BAS}', date '${BIT}', interval '1 day') g;
-- =====================================================================
\\set ON_ERROR_STOP on
begin;
set local timezone = 'Europe/Istanbul';

${onKosul}

create temp table s_calisan (sicil_no text, ad text, soyad text, departman text, yaka text, vardiya_duzeni text,
    ise_giris_tarihi date, isten_cikis_tarihi date, kart_no text, servis text) on commit drop;
create temp table s_kart (kart_no text, sicil_no text, durum text, iptal_nedeni text, verilis_tarihi date,
    iptal_zamani timestamptz) on commit drop;
create temp table s_plan (sicil_no text, tarih date, vardiya_kod text) on commit drop;
create temp table s_izin (sicil_no text, tur text, baslangic date, bitis date, aciklama text) on commit drop;
create temp table s_isg (sicil_no text, tur text, gecerlilik_bitis date, belge_no text) on commit drop;
create temp table s_zimmet (gecici_kart_no text, sicil_no text, verilis_zamani timestamptz, iade_zamani timestamptz) on commit drop;
create temp table s_dosya (kaynak text, dosya_adi text, veri_tarihi date, satir_sayisi int, dosya_ozeti text) on commit drop;
create temp table s_okutma (okuyucu text, kart_no text, zaman timestamptz, yon text, dosya_adi text) on commit drop;

${kopya("s_calisan", "calisanlar.csv")}
${kopya("s_kart", "kartlar.csv")}
${kopya("s_plan", "vardiya_plani.csv")}
${kopya("s_izin", "izinler.csv")}
${kopya("s_isg", "isg_belgeleri.csv")}
${kopya("s_zimmet", "gecici_kart_zimmet.csv")}
${kopya("s_dosya", "okutma/dosyalar.csv")}
${dosyalar.map(([, ad]) => `${kopya("s_okutma (okuyucu, kart_no, zaman, yon)", `okutma/${ad}`)}\nupdate s_okutma set dosya_adi = '${ad}' where dosya_adi is null;`).join("\n")}

do $$
begin
    if exists (select 1 from s_calisan s left join pdks.departman d on d.ad = s.departman where d.id is null) then
        raise exception 'Seed''de olmayan departman var: %',
            (select string_agg(distinct s.departman, ', ') from s_calisan s left join pdks.departman d on d.ad = s.departman where d.id is null);
    end if;
end $$;

-- Okuyucular (seed'de olanlara dokunulmaz)
insert into pdks.okuyucu (kod, ad, sistem, konum) values
${YENI_OKUYUCULAR.map((o) => `    (${o.map((x) => `'${x}'`).join(", ")})`).join(",\n")}
on conflict (kod) do nothing;

-- Çalışanlar ve kartlar
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi, isten_cikis_tarihi, aktif)
select s.sicil_no, s.ad, s.soyad, d.id, s.ise_giris_tarihi, s.isten_cikis_tarihi,
       s.isten_cikis_tarihi is null or s.isten_cikis_tarihi >= current_date
from s_calisan s join pdks.departman d on d.ad = s.departman
order by s.sicil_no;
${kullaniciSql}
insert into pdks.kart (kart_no, calisan_id, durum, iptal_nedeni, verilis_tarihi, iptal_zamani, iptal_eden_id)
select k.kart_no, c.id, k.durum, nullif(k.iptal_nedeni, ''), k.verilis_tarihi, k.iptal_zamani,
       case when k.durum = 'iptal' then ${girenIk("k.sicil_no")} end
from s_kart k join pdks.calisan c on c.sicil_no = k.sicil_no
order by k.durum desc, k.verilis_tarihi;  -- önce iptal edilmiş eski kartlar (tek aktif kart kuralı)

-- Vardiya planı (dönemden önce girilmiş sayılır), izinler, İSG belgeleri
insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id, giren_id, giris_zamani)
select c.id, p.tarih, v.id, ${girenIk("p.sicil_no")},
       timestamptz '${gunMetni(gunEkle(donemBas, -6))} 10:00'
from s_plan p join pdks.calisan c on c.sicil_no = p.sicil_no join pdks.vardiya_tanim v on v.kod = p.vardiya_kod;

insert into pdks.izin (calisan_id, tur, baslangic, bitis, aciklama, giren_id)
select c.id, i.tur, i.baslangic, i.bitis, i.aciklama, ${girenIk("i.sicil_no")}
from s_izin i join pdks.calisan c on c.sicil_no = i.sicil_no;

insert into pdks.isg_belge (calisan_id, tur, gecerlilik_bitis, belge_no, giren_id)
select c.id, b.tur, b.gecerlilik_bitis, b.belge_no, ${kullaniciSec(SICIL_ISG, "isg")}
from s_isg b join pdks.calisan c on c.sicil_no = b.sicil_no;
${fmOnaySql}
-- Geçici kartlar ve zimmetler: kurallar gereği önce verilir, sonra iade alınır (sırayla)
insert into pdks.gecici_kart (kart_no) select distinct gecici_kart_no from s_zimmet on conflict (kart_no) do nothing;
do $$
declare
    r record;
    v_id bigint;
    v_guv bigint := ${kullaniciSec(SICIL_GUVENLIK, "guvenlik")};
begin
    for r in select * from s_zimmet order by verilis_zamani loop
        insert into pdks.gecici_kart_zimmet (gecici_kart_id, calisan_id, verilis_zamani, veren_id, aciklama)
        values ((select id from pdks.gecici_kart where kart_no = r.gecici_kart_no),
                (select id from pdks.calisan where sicil_no = r.sicil_no), r.verilis_zamani, v_guv, 'Kartını evde unuttu')
        returning id into v_id;
        ${KURULUM ? "if r.iade_zamani is null then continue; end if;\n        " : ""}update pdks.gecici_kart_zimmet set iade_zamani = r.iade_zamani, iade_alan_id = v_guv where id = v_id;
    end loop;
end $$;

-- Dosya aktarımları ve okutmalar
insert into pdks.aktarim (kaynak, dosya_adi, dosya_ozeti, veri_tarihi, satir_sayisi, aktarim_zamani)
select kaynak, dosya_adi, dosya_ozeti, veri_tarihi, satir_sayisi, (veri_tarihi + 1 + time '00:30') at time zone 'Europe/Istanbul'
from s_dosya order by veri_tarihi, kaynak;

insert into pdks.ham_okutma (aktarim_id, okuyucu_id, kart_no, okutma_zamani, yon)
select a.id, o2.id, o.kart_no, o.zaman, nullif(o.yon, '')
from s_okutma o
join s_dosya f on f.dosya_adi = o.dosya_adi and f.kaynak = 'pdks'
join pdks.aktarim a on a.kaynak = f.kaynak and a.dosya_ozeti = f.dosya_ozeti
join pdks.okuyucu o2 on o2.kod = o.okuyucu
order by o.zaman;

insert into pdks.kanit_kaydi (aktarim_id, okuyucu_id, kaynak, kart_no, okutma_zamani, yon)
select a.id, o2.id, f.kaynak, o.kart_no, o.zaman, nullif(o.yon, '')
from s_okutma o
join s_dosya f on f.dosya_adi = o.dosya_adi and f.kaynak <> 'pdks'
join pdks.aktarim a on a.kaynak = f.kaynak and a.dosya_ozeti = f.dosya_ozeti
join pdks.okuyucu o2 on o2.kod = o.okuyucu
order by o.zaman;

-- Sayım: CSV'deki satırların hepsi yazıldı mı?
do $$
begin
    if (select count(*) from s_okutma) <> (select sum(satir_sayisi) from s_dosya) then
        raise exception 'Okutma sayısı dosya listesiyle tutmuyor.';
    end if;
    raise notice 'Sentetik veri yüklendi: % çalışan, % plan, % okutma.',
        (select count(*) from s_calisan), (select count(*) from s_plan), (select count(*) from s_okutma);
end $$;
${kontrolSql}
commit;
`;
writeFileSync(join(CIKTI, "yukle.sql"), sql, "utf8");

// ---------------------------------------------------------------------
// 9. Özet
// ---------------------------------------------------------------------
const kaynakSayisi = (k) => tumOkutmalar.filter((o) => o.kaynak === k).length;
const ozet = `# Sentetik veri özeti

Üretildi: \`node scripts/sentetik_veri.mjs${KURULUM ? " --kurulum" : ""} --bas ${BAS} --bit ${BIT} --tohum ${TOHUM}\`

| | Adet |
|---|---|
| Çalışan (aktif dönem) | ${aktifKisiler.length} |
| Eski çalışan (pasif) | ${kisiler.length - aktifKisiler.length} |
| Kart (iptal dahil) | ${kartlar.length} (${kartlar.filter((c) => c.durum === "iptal").length} iptal) |
| Vardiya planı (kişi-gün) | ${planlar.length} |
| İzin kaydı | ${izinler.length} |
| İSG belgesi | ${isg.length} |
${KURULUM ? `| Yazılı fazla mesai onayı | ${fmOnaylari.length} |\n` : ""}| Geçici kart zimmeti | ${zimmetler.length} |
| Okutma dosyası | ${dosyalar.length} |
| PDKS okutması | ${kaynakSayisi("pdks")} |
| Kapı / yemekhane / servis kaydı | ${kaynakSayisi("kapi")} / ${kaynakSayisi("yemekhane")} / ${kaynakSayisi("servis")} |

## Bilerek konmuş durumlar (kişi-gün)

| Durum | Adet |
|---|---|
${Object.entries(sayac).sort().map(([k, v]) => `| ${k} | ${v} |`).join("\n")}

## Departmanlar

| Departman | Yaka | Kişi |
|---|---|---|
${DEPARTMANLAR.map((d) => `| ${d.ad} | ${d.yaka} | ${aktifKisiler.filter((k) => k.dep === d).length} |`).join("\n")}
`;
const kadroOzeti = KURULUM ? `
## Kadro (kullanıcı hesapları)

| Ad soyad | Görev | Rol | Departman | Sicil | İşe giriş |
|---|---|---|---|---|---|
${[...kadro].sort((a, b) => a.sicil.localeCompare(b.sicil)).map((x) => `| ${x.ad} ${x.soyad} | ${x.gorev} | ${x.rol} | ${x.departman} | ${x.sicil} | ${x.ise_giris.getUTCFullYear()} |`).join("\n")}
` : "";
writeFileSync(join(CIKTI, "ozet.md"), ozet + kadroOzeti, "utf8");
console.log(ozet + kadroOzeti);
