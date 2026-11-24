"use server";

import { revalidatePath } from "next/cache";
import type { IslemSonucu } from "@/lib/islem-sonucu";
import { metinAl, rpcCagir, sayiAl, sicildenCalisan } from "@/lib/supabase/rpc";

// Server Action: tarayıcıdaki form gönderilince sunucuda çalışan fonksiyon.
// Yetki burada değil veritabanında denetlenir: gecici_kart_ver yalnızca güvenlik ve İK'ya açıktır,
// kimse kendine kart veremez (görevler ayrılığı), kayıp/iptal ya da zimmetli kart verilemez.

function yenile() {
  revalidatePath("/gecici-kartlar");
  revalidatePath("/"); // ana sayfadaki geçici kart sayıları
}

export async function kartVer(_onceki: IslemSonucu, form: FormData): Promise<IslemSonucu> {
  const kartId = sayiAl(form, "kart_id");
  const kartNo = metinAl(form, "kart_no") ?? "Geçici kart";
  if (!kartId) return { durum: "hata", mesaj: "Kart seçilmelidir." };

  const bulunan = await sicildenCalisan(form);
  if (!bulunan.tamam) return { durum: "hata", mesaj: bulunan.mesaj };
  const { calisan } = bulunan;

  const sonuc = await rpcCagir<number>("gecici_kart_ver", {
    p_gecici_kart_id: kartId,
    p_calisan_id: calisan.id,
    p_aciklama: metinAl(form, "aciklama"),
  });
  if (!sonuc.tamam) return { durum: "hata", mesaj: sonuc.mesaj };

  yenile();
  return { durum: "tamam", mesaj: `${kartNo} numaralı kart ${calisan.adSoyad} adına zimmetlendi.` };
}

export async function kartIadeAl(_onceki: IslemSonucu, form: FormData): Promise<IslemSonucu> {
  const zimmetId = sayiAl(form, "zimmet_id");
  const kartNo = metinAl(form, "kart_no") ?? "Geçici kart";
  if (!zimmetId) return { durum: "hata", mesaj: "Zimmet seçilmelidir." };

  const sonuc = await rpcCagir("gecici_kart_iade_al", { p_zimmet_id: zimmetId });
  if (!sonuc.tamam) return { durum: "hata", mesaj: sonuc.mesaj };

  yenile();
  return { durum: "tamam", mesaj: `${kartNo} numaralı kart iade alındı.` };
}
