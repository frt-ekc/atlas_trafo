// Soru türüne göre girilmesi zorunlu saatler (T-41). Hem pencere (required) hem Server Action
// aynı kuralı buradan okur; böylece ekran ile sunucu farklı davranmaz.
export type ZorunluSaatler = { giris: boolean; cikis: boolean };

const KURAL: Record<string, ZorunluSaatler> = {
  hic_kayit_yok: { giris: true, cikis: true },
  giris_yok: { giris: true, cikis: false },
  cikis_yok: { giris: false, cikis: true },
};

// Listede olmayan türlerde (kanit_vardiya_sonrasi, ariza_kaniti_yok, vardiya_uyusmazligi)
// iki saatten biri yeterlidir.
export function zorunluSaatler(soruTuru: string): ZorunluSaatler {
  return KURAL[soruTuru] ?? { giris: false, cikis: false };
}

// Eksik saat varsa kullanıcıya gösterilecek mesaj, yoksa null
export function eksikSaatMesaji(soruTuru: string, giris: string | null, cikis: string | null): string | null {
  const zorunlu = zorunluSaatler(soruTuru);
  const girisEksik = zorunlu.giris && !giris;
  const cikisEksik = zorunlu.cikis && !cikis;
  if (girisEksik && cikisEksik) return "Giriş ve çıkış saati girilmelidir.";
  if (girisEksik) return "Giriş saati girilmelidir.";
  if (cikisEksik) return "Çıkış saati girilmelidir.";
  if (!giris && !cikis) return "Giriş veya çıkış saati girilmelidir.";
  return null;
}
