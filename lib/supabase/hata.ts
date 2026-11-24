import type { PostgrestError } from "@supabase/supabase-js";

// Veritabanı hatasının kullanıcıya gösterilecek hâli. Hem sunucuda (rpcCagir) hem tarayıcıda
// (dosya yükleme formu) kullanılır; bu yüzden burada sunucuya özel bir şey yoktur.
// Fonksiyonların kendi hataları (raise exception) Türkçedir ve olduğu gibi gösterilir.
// PostgreSQL'in kendi hataları İngilizce gelir; onlar sade bir Türkçe cümleye çevrilir.
export function hataMesaji(hata: Pick<PostgrestError, "code" | "message">): string {
  // İstek veritabanına hiç varmadıysa kod boştur ("Failed to fetch", "fetch failed")
  if (!hata.code && /fetch|network/i.test(hata.message)) {
    return "Sisteme ulaşılamadı. Lütfen tekrar deneyin.";
  }
  switch (hata.code) {
    case "P0001": // raise exception: fonksiyonun Türkçe mesajı
      return sadelestir(hata.message);
    case "42501":
      return "Bu işlem için yetkiniz yok.";
    case "23505":
      return "Bu kayıt daha önce eklenmiştir.";
    case "23503":
      return "İlgili kayıt bulunamadı.";
    case "23514":
    case "22P02":
    case "22007":
    case "22008":
      return "Geçerli bir değer girilmelidir.";
    case "PGRST202":
      return "İşlem şu anda yapılamıyor. Sistem yöneticisi ile iletişime geçilmelidir.";
    default:
      // Türkçe karakter içeren mesaj büyük ihtimalle bizim fonksiyonlarımızdan gelir
      return /[çğıöşüÇĞİÖŞÜ]/.test(hata.message) ? sadelestir(hata.message) : "İşlem yapılamadı. Lütfen tekrar deneyin.";
  }
}

// Mesajın sonundaki teknik ek (ör. "(gecici_kart_zimmet.veren_id)") kullanıcıya gösterilmez
function sadelestir(mesaj: string): string {
  return mesaj.replace(/\s*\([a-z_]+\.[a-z_]+\)\.?$/, ".");
}
