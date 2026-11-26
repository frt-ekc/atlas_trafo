import "server-only";
import { oturumRolu } from "@/lib/oturum";

export type Tema = "acik" | "koyu";

// Tema kullanıcı tarafından seçilmez, role göre gelir:
// - Sistem yöneticisi (admin) paneli koyu temadır (nötr siyah tonlar, renk geçişli).
// - Diğer bütün roller ve giriş sayfası açık temadır.
// Sunucuda belirlenir; sayfa doğru renkle çizilir, açılışta yanıp sönmez.
export async function temaOku(): Promise<Tema> {
  return (await oturumRolu()) === "admin" ? "koyu" : "acik";
}
