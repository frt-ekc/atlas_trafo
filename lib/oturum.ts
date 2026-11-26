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

// Oturumu ve kullanıcı satırını okur; yönlendirmez. Hem oturumKullanicisi hem kök düzen (tema)
// kullanır. cache(): aynı istek içinde birden çok yer çağırsa da veritabanına bir kez gidilir.
const oturumKaydi = cache(async () => {
  // Bu bir istek anı işlemi: Next.js sayfayı build sırasında sabit üretmesin.
  await connection();
  if (!supabaseAyarlari()) return { durum: "ayar_yok" as const };

  const supabase = await sunucuIstemcisi();
  const { data: oturum } = await supabase.auth.getClaims();
  const authId = oturum?.claims?.sub;
  if (!authId) return { durum: "giris_yok" as const };

  const { data, error } = await supabase
    .from("kullanici")
    .select("id, ad_soyad, eposta, rol, calisan_id")
    .eq("auth_kullanici_id", authId)
    .maybeSingle();
  return { durum: "tamam" as const, data, error };
});

// Oturumdaki kullanıcının rolü; giriş yoksa ya da okunamazsa null (yönlendirmez, hata atmaz).
export async function oturumRolu(): Promise<Rol | null> {
  const kayit = await oturumKaydi();
  return kayit.durum === "tamam" && kayit.data ? (kayit.data.rol as Rol) : null;
}

// Oturumdaki kullanıcıyı pdks.kullanici tablosundan okur.
// - Giriş yoksa (ya da ayarlar eksikse) /giris sayfasına yönlendirir.
// - Giriş var ama hesap pdks.kullanici'ya bağlı ya da aktif değilse null döner
//   (RLS bu durumda kullanıcının kendi satırını bile göstermez).
export const oturumKullanicisi = cache(async (): Promise<OturumKullanicisi | null> => {
  const kayit = await oturumKaydi();
  // Ayarlar eksikse giriş sayfası ne yapılacağını anlatır.
  if (kayit.durum !== "tamam") redirect("/giris");
  const { data, error } = kayit;

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
