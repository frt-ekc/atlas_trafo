// Puantaj satırı: ekranda ve Excel'de aynı sütunlar kullanılır.
// Ücret hesaplanmaz; yalnızca gün ve dakika vardır (proje kuralı).

export type PuantajSatiri = {
  sicil: string;
  adSoyad: string;
  bolum: string;
  calisilanGun: number;
  calismaDk: number;
  fazlaMesaiDk: number;
  fm50Dk: number; // hafta içi fazla mesai (%50)
  fm100Dk: number; // Pazar / resmi tatil çalışması (%100)
  geceCalismaDk: number; // 20:00–06:00 arası çalışma
  molaDk: number; // düşülen yasal mola
  gecKalmaDk: number;
  erkenCikisDk: number;
  devamsizGun: number;
  izinliGun: number;
  raporluGun: number;
  tatilGun: number;
  bekleyenGun: number; // yalnızca canlı hesapta: henüz kesinleşmemiş gün
  kaynakDonem?: string; // yalnızca fark satırında: düzeltmenin ait olduğu ay ("2026-10")
};

type Sutun = { baslik: string; deger: (s: PuantajSatiri) => string | number; genislik: number; sayi?: boolean };

export const PUANTAJ_SUTUNLARI: Sutun[] = [
  { baslik: "Sicil", deger: (s) => s.sicil, genislik: 8 },
  { baslik: "Ad soyad", deger: (s) => s.adSoyad, genislik: 22 },
  { baslik: "Bölüm", deger: (s) => s.bolum, genislik: 12 },
  { baslik: "Çalışılan gün", deger: (s) => s.calisilanGun, genislik: 13, sayi: true },
  { baslik: "Çalışma (dk)", deger: (s) => s.calismaDk, genislik: 12, sayi: true },
  { baslik: "Fazla mesai (dk)", deger: (s) => s.fazlaMesaiDk, genislik: 15, sayi: true },
  { baslik: "FM50 (dk)", deger: (s) => s.fm50Dk, genislik: 10, sayi: true },
  { baslik: "FM100 (dk)", deger: (s) => s.fm100Dk, genislik: 11, sayi: true },
  { baslik: "Gece çalışma (dk)", deger: (s) => s.geceCalismaDk, genislik: 16, sayi: true },
  { baslik: "Mola (dk)", deger: (s) => s.molaDk, genislik: 10, sayi: true },
  { baslik: "Geç kalma (dk)", deger: (s) => s.gecKalmaDk, genislik: 14, sayi: true },
  { baslik: "Erken çıkış (dk)", deger: (s) => s.erkenCikisDk, genislik: 15, sayi: true },
  { baslik: "Devamsız gün", deger: (s) => s.devamsizGun, genislik: 13, sayi: true },
  { baslik: "İzinli gün", deger: (s) => s.izinliGun, genislik: 11, sayi: true },
  { baslik: "Raporlu gün", deger: (s) => s.raporluGun, genislik: 12, sayi: true },
  { baslik: "Tatil gün", deger: (s) => s.tatilGun, genislik: 10, sayi: true },
];

// "2026-11" → "Kasım 2026"
export function ayAdi(ay: string): string {
  return new Intl.DateTimeFormat("tr-TR", { month: "long", year: "numeric", timeZone: "UTC" }).format(
    new Date(`${ay}-01T00:00:00Z`),
  );
}

export function ayKaydir(ay: string, fark: number): string {
  const [y, a] = ay.split("-").map(Number);
  const d = new Date(Date.UTC(y, a - 1 + fark, 1));
  return d.toISOString().slice(0, 7);
}
