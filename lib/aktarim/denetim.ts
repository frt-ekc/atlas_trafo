import Papa from "papaparse";

// PDKS / kapı / yemekhane / servis dosyalarının denetimi.
// Tarayıcıda çalışır: dosya sunucuya gitmeden önce okunur, hatalar kullanıcıya gösterilir.
// Veritabanı da kendi kurallarını ayrıca uygular (ör. aynı dosya iki kez yüklenemez).
//
// Beklenen biçim (başlık satırı zorunlu, ayraç ";" ya da ","):
//   okuyucu;kart_no;zaman;yon
//   PDKS-1;K1002;2026-11-26 07:52;giris
// zaman: Türkiye saati, "YYYY-MM-DD SS:DD[:ss]" ya da "GG.AA.YYYY SS:DD[:ss]"
// yon: giris / cikis (okuyucu yön vermiyorsa boş bırakılır)

export type Kaynak = "pdks" | "kapi" | "yemekhane" | "servis";

export const KAYNAK_ADI: Record<Kaynak, string> = {
  pdks: "PDKS",
  kapi: "Kapı turnikesi",
  yemekhane: "Yemekhane",
  servis: "Servis",
};

export type Okuyucu = { id: number; kod: string; ad: string; sistem: Kaynak; aktif: boolean };

export type Satir = {
  satirNo: number; // dosyadaki satır numarası (başlık 1. satır)
  okuyucuId: number;
  okuyucuKod: string;
  kartNo: string;
  zaman: string; // ISO, +03:00
  yerelTarih: string; // YYYY-MM-DD (Türkiye)
  yon: "giris" | "cikis" | null;
};

export type Sorun = { satirNo: number | null; mesaj: string };

export type DenetimSonucu = {
  satirlar: Satir[]; // yüklenebilir satırlar (tekrarlar çıkarılmış)
  hatalar: Sorun[]; // yüklemeyi engeller
  uyarilar: Sorun[]; // bilgi; yüklemeyi engellemez
  toplamSatir: number;
  veriTarihi: string | null;
};

// Başlıklar farklı yazılabilir; hepsi tek bir ada çevrilir.
const BASLIK_ESLEME: Record<string, keyof HamSatir> = {
  okuyucu: "okuyucu",
  okuyucu_kodu: "okuyucu",
  okuyucu_kod: "okuyucu",
  cihaz: "okuyucu",
  kart: "kart_no",
  kart_no: "kart_no",
  kartno: "kart_no",
  zaman: "zaman",
  okutma_zamani: "zaman",
  tarih_saat: "zaman",
  yon: "yon",
};

type HamSatir = { okuyucu?: string; kart_no?: string; zaman?: string; yon?: string };

function basligiDuzelt(baslik: string): string {
  const sade = baslik
    .replace(/^﻿/, "") // Excel'in eklediği BOM
    .trim()
    .toLocaleLowerCase("tr-TR")
    .replaceAll("ö", "o")
    .replaceAll("ı", "i")
    .replaceAll("ü", "u")
    .replaceAll("ş", "s")
    .replaceAll("ç", "c")
    .replaceAll("ğ", "g")
    .replace(/\s+/g, "_");
  return BASLIK_ESLEME[sade] ?? sade;
}

// Saat tek haneli de olabilir (7:20); gün ve ay iki hanelidir.
const ISO_ZAMAN = /^(\d{4})-(\d{2})-(\d{2})[ T](\d{1,2}):(\d{2})(?::(\d{2}))?$/;
const TR_ZAMAN = /^(\d{2})\.(\d{2})\.(\d{4}) (\d{1,2}):(\d{2})(?::(\d{2}))?$/;

// Türkiye 2016'dan beri yıl boyu UTC+3; yaz saati yok.
function zamaniOku(deger: string): { iso: string; yerelTarih: string } | null {
  const d = deger.trim();
  let y: string, a: string, g: string, s: string, dk: string, sn: string | undefined;
  const iso = ISO_ZAMAN.exec(d);
  const tr = TR_ZAMAN.exec(d);
  if (iso) [, y, a, g, s, dk, sn] = iso;
  else if (tr) [, g, a, y, s, dk, sn] = tr;
  else return null;

  s = s.padStart(2, "0");
  const sonuc = `${y}-${a}-${g}T${s}:${dk}:${sn ?? "00"}+03:00`;
  const kontrol = new Date(sonuc);
  // 31.02 gibi olmayan tarihler ve 25:00 gibi saatler reddedilir
  if (Number.isNaN(kontrol.getTime()) || Number(a) > 12 || Number(g) > 31 || Number(s) > 23 || Number(dk) > 59) return null;
  const geriDonusum = new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Istanbul" }).format(kontrol);
  if (geriDonusum !== `${y}-${a}-${g}`) return null;
  return { iso: sonuc, yerelTarih: `${y}-${a}-${g}` };
}

function yonuOku(deger: string | undefined): "giris" | "cikis" | null | undefined {
  const d = (deger ?? "").trim().toLocaleLowerCase("tr-TR").replaceAll("ş", "s").replaceAll("ı", "i").replaceAll("ç", "c");
  if (d === "") return null;
  if (["giris", "g", "in"].includes(d)) return "giris";
  if (["cikis", "c", "out"].includes(d)) return "cikis";
  return undefined; // tanınmadı
}

// "pdks_20261126.csv" → "2026-11-26"
export function dosyaAdindanTarih(dosyaAdi: string): string | null {
  const m = /(\d{4})(\d{2})(\d{2})/.exec(dosyaAdi);
  if (!m) return null;
  const t = `${m[1]}-${m[2]}-${m[3]}`;
  // JavaScript olmayan tarihi hata vermeden kaydırır (31.11 → 01.12); geri çevirince aynı gün çıkmalı.
  const d = new Date(`${t}T00:00:00Z`);
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === t ? t : null;
}

const KART_NO = /^[A-Za-z0-9-]{1,32}$/;
const EN_FAZLA_SORUN = 200;

export function dosyayiDenetle(metin: string, dosyaAdi: string, kaynak: Kaynak, okuyucular: Okuyucu[]): DenetimSonucu {
  const hatalar: Sorun[] = [];
  const uyarilar: Sorun[] = [];
  const hata = (satirNo: number | null, mesaj: string) => {
    if (hatalar.length < EN_FAZLA_SORUN) hatalar.push({ satirNo, mesaj });
  };

  const okunan = Papa.parse<HamSatir>(metin, {
    header: true,
    skipEmptyLines: "greedy",
    transformHeader: basligiDuzelt,
    delimitersToGuess: [";", ",", "\t"],
  });

  const basliklar = okunan.meta.fields ?? [];
  const eksik = (["okuyucu", "kart_no", "zaman"] as const).filter((b) => !basliklar.includes(b));
  if (eksik.length) {
    hata(1, `Başlık satırında şu sütunlar yok: ${eksik.join(", ")}. Beklenen: okuyucu;kart_no;zaman;yon`);
    return { satirlar: [], hatalar, uyarilar, toplamSatir: okunan.data.length, veriTarihi: null };
  }
  for (const e of okunan.errors.slice(0, 20)) {
    hata(e.row != null ? e.row + 2 : null, `Dosya okunamadı: ${e.message}`);
  }

  const okuyucuByKod = new Map(okuyucular.map((o) => [o.kod.toUpperCase(), o]));
  const gorulen = new Set<string>();
  const satirlar: Satir[] = [];
  let tekrarSayisi = 0;

  okunan.data.forEach((ham, i) => {
    const satirNo = i + 2;
    const kod = (ham.okuyucu ?? "").trim().toUpperCase();
    const kartNo = (ham.kart_no ?? "").trim().toUpperCase();
    const okuyucu = okuyucuByKod.get(kod);
    const zaman = zamaniOku(ham.zaman ?? "");
    const yon = yonuOku(ham.yon);
    let gecerli = true;

    if (!okuyucu) {
      hata(satirNo, kod ? `"${kod}" okuyucusu tanımlı değil.` : "Okuyucu kodu boş.");
      gecerli = false;
    } else if (okuyucu.sistem !== kaynak) {
      hata(satirNo, `${kod} bir ${KAYNAK_ADI[okuyucu.sistem]} okuyucusu; seçilen dosya türü ${KAYNAK_ADI[kaynak]}.`);
      gecerli = false;
    }
    if (!KART_NO.test(kartNo)) {
      hata(satirNo, kartNo ? `Kart numarası geçersiz: "${kartNo}"` : "Kart numarası boş.");
      gecerli = false;
    }
    if (!zaman) {
      hata(satirNo, `Zaman okunamadı: "${ham.zaman ?? ""}". Örnek: 2026-11-26 08:01`);
      gecerli = false;
    }
    if (yon === undefined) {
      hata(satirNo, `Yön "giris", "cikis" veya boş olmalıdır: "${ham.yon}"`);
      gecerli = false;
    }
    if (!gecerli || !okuyucu || !zaman || yon === undefined) return;

    // Veritabanında (okuyucu, kart, zaman) tekildir; aynı satır ikinci kez yazılamaz
    const anahtar = `${okuyucu.id}|${kartNo}|${zaman.iso}`;
    if (gorulen.has(anahtar)) {
      tekrarSayisi += 1;
      return;
    }
    gorulen.add(anahtar);
    satirlar.push({ satirNo, okuyucuId: okuyucu.id, okuyucuKod: okuyucu.kod, kartNo, zaman: zaman.iso, yerelTarih: zaman.yerelTarih, yon });
  });

  if (tekrarSayisi) uyarilar.push({ satirNo: null, mesaj: `${tekrarSayisi} yinelenen satır bir kez yüklenir.` });
  if (okunan.data.length === 0) hata(null, "Dosyada veri satırı bulunmuyor.");

  // Dosyanın ait olduğu gün: dosya adından, yoksa en çok geçen günden
  const gunler = new Map<string, number>();
  for (const s of satirlar) gunler.set(s.yerelTarih, (gunler.get(s.yerelTarih) ?? 0) + 1);
  const enCok = [...gunler.entries()].sort((a, b) => b[1] - a[1])[0]?.[0] ?? null;
  const veriTarihi = dosyaAdindanTarih(dosyaAdi) ?? enCok;

  if (veriTarihi) {
    // Gece vardiyası ertesi sabaha taşar; daha uzak günler şüphelidir.
    const ertesiGun = new Date(new Date(`${veriTarihi}T00:00:00Z`).getTime() + 86_400_000).toISOString().slice(0, 10);
    const uzak = satirlar.filter((s) => s.yerelTarih !== veriTarihi && s.yerelTarih !== ertesiGun).length;
    if (uzak) uyarilar.push({ satirNo: null, mesaj: `${uzak} satır, dosya günü (${veriTarihi}) ve izleyen günün dışındadır.` });
  } else {
    hata(null, "Dosya tarihi belirlenemedi. Dosya adı tarih içermelidir (ör. pdks_20261126.csv).");
  }

  const pasif = new Set(satirlar.filter((s) => !okuyucuByKod.get(s.okuyucuKod.toUpperCase())?.aktif).map((s) => s.okuyucuKod));
  if (pasif.size) uyarilar.push({ satirNo: null, mesaj: `Pasif okuyuculara ait kayıtlar: ${[...pasif].join(", ")}` });

  return { satirlar, hatalar, uyarilar, toplamSatir: okunan.data.length, veriTarihi };
}

// Dosyanın SHA-256 özeti (aynı dosyanın ikinci kez yüklenmesini veritabanı bununla engeller)
export async function dosyaOzeti(icerik: ArrayBuffer): Promise<string> {
  const ozet = await crypto.subtle.digest("SHA-256", icerik);
  return [...new Uint8Array(ozet)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
