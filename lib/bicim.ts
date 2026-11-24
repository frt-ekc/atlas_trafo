// Ekranlarda tarih ve saat hep Türkiye saatiyle gösterilir.
// Veritabanı zamanı UTC tutar; sunucu (ör. Vercel) da UTC'de çalışır.
// Bu yüzden saat dilimi açıkça verilir, yoksa saatler 3 saat kayık görünür.
const SAAT_DILIMI = "Europe/Istanbul";

const tarihBicimi = new Intl.DateTimeFormat("tr-TR", {
  timeZone: SAAT_DILIMI,
  day: "2-digit",
  month: "2-digit",
  year: "numeric",
});

const tarihSaatBicimi = new Intl.DateTimeFormat("tr-TR", {
  timeZone: SAAT_DILIMI,
  day: "2-digit",
  month: "2-digit",
  year: "numeric",
  hour: "2-digit",
  minute: "2-digit",
});

const uzunTarihBicimi = new Intl.DateTimeFormat("tr-TR", {
  timeZone: SAAT_DILIMI,
  weekday: "long",
  day: "numeric",
  month: "long",
  year: "numeric",
});

// "18 Kasım 2026 Çarşamba"
export function uzunTarih(deger: string): string {
  return uzunTarihBicimi.format(new Date(`${deger}T12:00:00Z`));
}

// "2026-11-10" (date) ya da "2026-11-10T05:12:00+00" (timestamptz) alır.
export function tarih(deger: string | null | undefined): string {
  if (!deger) return "—";
  // Yalnızca tarih ise gün kaymasın diye öğlen saatiyle okunur.
  const d = deger.length === 10 ? new Date(`${deger}T12:00:00Z`) : new Date(deger);
  return tarihBicimi.format(d);
}

export function tarihSaat(deger: string | null | undefined): string {
  if (!deger) return "—";
  return tarihSaatBicimi.format(new Date(deger));
}

const saatBicimi = new Intl.DateTimeFormat("tr-TR", { timeZone: SAAT_DILIMI, hour: "2-digit", minute: "2-digit" });

// "07:52" (Türkiye saati)
export function saat(deger: string | null | undefined): string {
  if (!deger) return "—";
  return saatBicimi.format(new Date(deger));
}

// Dakikayı "11 sa 30 dk" biçiminde yazar (690 → "11 sa 30 dk", 600 → "10 sa", 15 → "15 dk")
export function sureMetni(dk: number): string {
  const mutlak = Math.abs(Math.round(dk));
  const sa = Math.floor(mutlak / 60);
  const kalan = mutlak % 60;
  const metin = sa > 0 ? (kalan > 0 ? `${sa.toLocaleString("tr-TR")} sa ${kalan} dk` : `${sa.toLocaleString("tr-TR")} sa`) : `${kalan} dk`;
  return dk < 0 ? `−${metin}` : metin;
}

// İki zaman arasındaki süre: "3 sa 20 dk" / "2 gün 4 sa"
export function sure(baslangic: string, bitis: string | null | undefined, simdi = new Date()): string {
  const dk = Math.max(0, Math.round(((bitis ? new Date(bitis) : simdi).getTime() - new Date(baslangic).getTime()) / 60000));
  const gun = Math.floor(dk / 1440);
  const sa = Math.floor((dk % 1440) / 60);
  const kalanDk = dk % 60;
  if (gun > 0) return `${gun} gün ${sa} sa`;
  return sureMetni(sa * 60 + kalanDk);
}

// datetime-local alanı için Türkiye saatiyle "2026-11-26T08:01" (alanın varsayılan değeri)
const yerelBicim = new Intl.DateTimeFormat("sv-SE", {
  timeZone: SAAT_DILIMI,
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  hour: "2-digit",
  minute: "2-digit",
});
export function yerelZamanGirdisi(deger: string | null | undefined): string {
  if (!deger) return "";
  return yerelBicim.format(new Date(deger)).replace(" ", "T");
}
