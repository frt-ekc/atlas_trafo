// Cevapta girilmesi zorunlu saatler (T-41). Hem pencere (required) hem Server Action
// aynı kuralı buradan okur; böylece ekran ile sunucu farklı davranmaz.
//
// Kural soru türüne değil sonuca bakar (veritabanındaki cevap_saatleri_denetle ile aynı):
// cevap uygulanınca günde hem giriş hem çıkış olmalı. Günde zaten kayıtlı olan saat (PDKS,
// kanıt, İK düzeltmesi) eksiği tamamlar; kayıtlı olmayan saat zorunludur. Böylece "kanıt
// vardiya sonrası", "arıza kanıtı yok" ve "vardiya uyuşmazlığı" gibi türlerde de tek saatli
// cevap günü askıda bırakmaz.
export type ZorunluSaatler = { giris: boolean; cikis: boolean };

// gunde: gün kaydında hangi saatler zaten var
export function zorunluSaatler(gunde: { giris: boolean; cikis: boolean }): ZorunluSaatler {
  return { giris: !gunde.giris, cikis: !gunde.cikis };
}

// Eksik saat varsa kullanıcıya gösterilecek mesaj, yoksa null
export function eksikSaatMesaji(
  gunde: { giris: boolean; cikis: boolean },
  giris: string | null,
  cikis: string | null,
): string | null {
  const zorunlu = zorunluSaatler(gunde);
  const girisEksik = zorunlu.giris && !giris;
  const cikisEksik = zorunlu.cikis && !cikis;
  if (girisEksik && cikisEksik) return "Günde giriş ve çıkış saati yok; iki saati de girin.";
  if (girisEksik) return "Günde giriş saati yok; giriş saatini de girin.";
  if (cikisEksik) return "Günde çıkış saati yok; çıkış saatini de girin.";
  if (!giris && !cikis) return "Düzeltilecek giriş veya çıkış saatini girin.";
  return null;
}
