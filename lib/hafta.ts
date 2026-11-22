// Tarihler "YYYY-MM-DD" metni olarak taşınır (veritabanındaki date tipiyle aynı).
// Hesaplar UTC'de yapılır; böylece sunucunun saat dilimi sonucu değiştirmez.

const GUN = 86_400_000;
const GUN_ADLARI = ["Pzt", "Sal", "Çar", "Per", "Cum", "Cmt", "Paz"];

function oku(t: string): Date {
  return new Date(`${t}T00:00:00Z`);
}

function yaz(d: Date): string {
  return d.toISOString().slice(0, 10);
}

export function gecerliTarihMi(t: string): boolean {
  return /^\d{4}-\d{2}-\d{2}$/.test(t) && !Number.isNaN(oku(t).getTime()) && yaz(oku(t)) === t;
}

export function gunEkle(t: string, gun: number): string {
  return yaz(new Date(oku(t).getTime() + gun * GUN));
}

// Verilen tarihin haftasının pazartesisi
export function haftaBasi(t: string): string {
  const haftaninGunu = (oku(t).getUTCDay() + 6) % 7; // pazartesi = 0
  return gunEkle(t, -haftaninGunu);
}

// Türkiye'de bugünün tarihi (sunucu UTC'de çalışsa bile)
export function bugun(): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Istanbul" }).format(new Date());
}

// Ay ("2026-11") bitti mi? Ayın son günü geçmeden bitmiş sayılmaz: 30 Kasım'da hayır, 1 Aralık'ta evet.
// Metin karşılaştırması yeterli: ikisi de "YYYY-MM".
export function ayBittiMi(ay: string, bugunTarih: string): boolean {
  return ay < bugunTarih.slice(0, 7);
}

export type HaftaGunu = { tarih: string; ad: string; gunAy: string; haftaSonu: boolean };

export function haftaninGunleri(pazartesi: string): HaftaGunu[] {
  return GUN_ADLARI.map((ad, i) => {
    const tarih = gunEkle(pazartesi, i);
    return { tarih, ad, gunAy: `${tarih.slice(8, 10)}.${tarih.slice(5, 7)}`, haftaSonu: i >= 5 };
  });
}

// "16–22 Kasım 2026" gibi başlık
export function haftaBasligi(pazartesi: string): string {
  const pazar = gunEkle(pazartesi, 6);
  const ay = (t: string) => new Intl.DateTimeFormat("tr-TR", { month: "long", timeZone: "UTC" }).format(oku(t));
  const gun = (t: string) => Number(t.slice(8, 10));
  const yil = pazar.slice(0, 4);
  return ay(pazartesi) === ay(pazar)
    ? `${gun(pazartesi)}–${gun(pazar)} ${ay(pazar)} ${yil}`
    : `${gun(pazartesi)} ${ay(pazartesi)} – ${gun(pazar)} ${ay(pazar)} ${yil}`;
}
