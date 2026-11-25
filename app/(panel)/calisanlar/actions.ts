"use server";

import { revalidatePath } from "next/cache";
import type { IslemSonucu } from "@/lib/islem-sonucu";
import { metinAl, rpcCagir, sayiAl, tarihAl } from "@/lib/supabase/rpc";

// İK yeni çalışanı tanımlar (calisan_ekle). İşe giriş ileri tarihli olabilir; o güne kadarki
// planlar gece işinde işlenmez. Kart ayrıca çalışanın sayfasından tanımlanır.
export async function calisanEkle(_onceki: IslemSonucu, form: FormData): Promise<IslemSonucu> {
  const sicil = metinAl(form, "sicil_no")?.toUpperCase() ?? null;
  const ad = metinAl(form, "ad");
  const soyad = metinAl(form, "soyad");
  const departmanId = sayiAl(form, "departman_id");
  const iseGiris = tarihAl(form, "ise_giris_tarihi");
  if (!sicil || !/^[A-Z0-9-]{1,20}$/.test(sicil)) return { durum: "hata", mesaj: "Sicil numarası yalnızca harf, rakam ve tire içermelidir." };
  if (!ad || !soyad) return { durum: "hata", mesaj: "Ad ve soyad girilmelidir." };
  if (!departmanId) return { durum: "hata", mesaj: "Departman seçilmelidir." };
  if (!iseGiris) return { durum: "hata", mesaj: "İşe giriş tarihi girilmelidir." };

  const sonuc = await rpcCagir<number>("calisan_ekle", {
    p_sicil_no: sicil,
    p_ad: ad,
    p_soyad: soyad,
    p_departman_id: departmanId,
    p_ise_giris_tarihi: iseGiris,
  });
  if (!sonuc.tamam) return { durum: "hata", mesaj: sonuc.mesaj };

  revalidatePath("/calisanlar", "layout");
  revalidatePath("/vardiya-plani");
  return {
    durum: "tamam",
    mesaj: `${ad} ${soyad} eklendi. Kart ve vardiya planı tanımlanmalıdır.`,
  };
}
