import { cookies } from "next/headers";

export type Tema = "acik" | "koyu";
export const TEMA_CEREZI = "tema";

// Seçilen tema tarayıcıda çerezde durur (kişisel tercih; veritabanına yazılmaz).
// Çerez yoksa açık tema açılır (logo lacivert-beyaz; açık tema varsayılan).
export async function temaOku(): Promise<Tema> {
  const deger = (await cookies()).get(TEMA_CEREZI)?.value;
  return deger === "koyu" ? "koyu" : "acik";
}
