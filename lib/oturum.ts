import "server-only";
import { cache } from "react";
import { redirect } from "next/navigation";
import { connection } from "next/server";
import { supabaseAyarlari } from "@/lib/supabase/ayarlar";
import { sunucuIstemcisi } from "@/lib/supabase/server";

// Veritabanındaki roller (pdks.kullanici.rol)
export type Rol = "amir" | "ik" | "guvenlik" | "yonetici" | "isg" | "admin";

export const ROL_ADI: Record<Rol, string> = {
  amir: "Amir",
  ik: "İnsan Kaynakları",
  guvenlik: "Güvenlik",
  yonetici: "Yönetici",
  isg: "İSG uzmanı",
  admin: "Sistem yöneticisi",
};

export type OturumKullanicisi = {
  id: number;
  adSoyad: string;
  eposta: string;
  rol: Rol;
  calisanId: number | null; // görevler ayrılığı: kullanıcının kendi çalışan kaydı
};

// Oturumdaki kullanıcıyı pdks.kullanici tablosundan okur.
// - Giriş yoksa /giris sayfasına yönlendirir.
// - Giriş var ama hesap pdks.kullanici'ya bağlı ya da aktif değilse null döner
//   (RLS bu durumda kullanıcının kendi satırını bile göstermez).
// cache(): aynı istek içinde birden çok bileşen çağırsa da veritabanına bir kez gidilir.
export const oturumKullanicisi = cache(async (): Promise<OturumKullanicisi | null> => {
  // Bu bir istek anı işlemi: Next.js sayfayı build sırasında sabit üretmesin.
  await connection();

  // Ayarlar eksikse giriş sayfası ne yapılacağını anlatır.
  if (!supabaseAyarlari()) redirect("/giris");

  const supabase = await sunucuIstemcisi();

  const { data: oturum } = await supabase.auth.getClaims();
  const authId = oturum?.claims?.sub;
  if (!authId) redirect("/giris");

  const { data, error } = await supabase
    .from("kullanici")
    .select("id, ad_soyad, eposta, rol, calisan_id")
    .eq("auth_kullanici_id", authId)
    .maybeSingle();

  if (error) {
    throw new Error(`Kullanıcı bilgisi okunamadı: ${error.message}`);
  }
  if (!data) return null;

  return {
    id: data.id,
    adSoyad: data.ad_soyad,
    eposta: data.eposta,
    rol: data.rol as Rol,
    calisanId: data.calisan_id ?? null,
  };
});

// Sayfanın başında çağrılır: kullanıcının rolü listede yoksa ana sayfaya döner.
// Bu, yanlış sayfaya girmeyi engelleyen bir kolaylıktır; veriyi asıl koruyan RLS'dir.
export async function rolGerekli(roller: Rol[]): Promise<OturumKullanicisi> {
  const kullanici = await oturumKullanicisi();
  if (!kullanici || !roller.includes(kullanici.rol)) redirect("/");
  return kullanici;
}
