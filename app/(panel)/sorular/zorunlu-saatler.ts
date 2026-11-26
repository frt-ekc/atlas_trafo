// Cevapta girilmesi zorunlu saatler (T-41). Hem pencere (required) hem Server Action
// aynı kuralı buradan okur; böylece ekran ile sunucu farklı davranmaz.
//
// Kural sonuca bakar (veritabanındaki cevap_saatleri_denetle ile aynı): cevap uygulanınca günde
// hem giriş hem çıkış olmalı. Günde zaten kayıtlı olan saat (PDKS, kanıt, İK düzeltmesi) eksiği
// tamamlar; kayıtlı olmayan saat zorunludur. Böylece "kanıt vardiya sonrası", "arıza kanıtı yok"
// ve "vardiya uyuşmazlığı" gibi türlerde de tek saatli cevap günü askıda bırakmaz.
//
// Gün kaydı kullanıcıya görünmüyorsa (ör. soru başka bölümün üst amirine iletildiyse RLS gizler)
// gündeki saatler bilinmez: o zaman soru türüne göre en az kural uygulanır ve son kararı
// veritabanı verir. Böylece günde var olan bir saat yüzünden cevap haksız yere engellenmez.
export type ZorunluSaatler = { giris: boolean; cikis: boolean };
export type GundekiSaatler = { giris: boolean; cikis: boolean } | null; // null: gün görünmüyor

const TURE_GORE: Record<string, ZorunluSaatler> = {
  hic_kayit_yok: { giris: true, cikis: true },
  giris_yok: { giris: true, cikis: false },
  cikis_yok: { giris: false, cikis: true },
};

export function zorunluSaatler(soruTuru: string, gunde: GundekiSaatler): ZorunluSaatler {
  if (!gunde) return TURE_GORE[soruTuru] ?? { giris: false, cikis: false };
  return { giris: !gunde.giris, cikis: !gunde.cikis };
}

// Eksik saat varsa kullanıcıya gösterilecek mesaj, yoksa null
export function eksikSaatMesaji(soruTuru: string, gunde: GundekiSaatler, giris: string | null, cikis: string | null): string | null {
  const zorunlu = zorunluSaatler(soruTuru, gunde);
  const girisEksik = zorunlu.giris && !giris;
  const cikisEksik = zorunlu.cikis && !cikis;
  if (girisEksik && cikisEksik) return "Günde giriş ve çıkış saati yok; iki saati de girin.";
  if (girisEksik) return "Günde giriş saati yok; giriş saatini de girin.";
  if (cikisEksik) return "Günde çıkış saati yok; çıkış saatini de girin.";
  if (!giris && !cikis) return "Düzeltilecek giriş veya çıkış saatini girin.";
  return null;
}
