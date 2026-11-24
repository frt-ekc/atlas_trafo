"use server";

import { revalidatePath } from "next/cache";
import type { IslemSonucu } from "@/lib/islem-sonucu";
import { kararAl, metinAl, rpcCagir, sayiAl } from "@/lib/supabase/rpc";

function yenile() {
  revalidatePath("/itirazlar");
  revalidatePath("/calisanlar", "layout");
  revalidatePath("/");
}

// İK itirazı incelemeye alır (amire ve çalışana "bakılıyor" bilgisi).
export async function itirazIncelemeyeAl(_onceki: IslemSonucu, form: FormData): Promise<IslemSonucu> {
  const itirazId = sayiAl(form, "itiraz_id");
  if (!itirazId) return { durum: "hata", mesaj: "İtiraz seçilmelidir." };
  const sonuc = await rpcCagir("itiraz_incelemeye_al", { p_itiraz_id: itirazId });
  if (!sonuc.tamam) return { durum: "hata", mesaj: sonuc.mesaj };
  yenile();
  return { durum: "tamam", mesaj: "İtiraz incelemeye alındı." };
}

// İtirazı kabul ya da red. Red çalışan aleyhine karardır: yalnızca İK verir, gerekçe zorunludur.
// Kabul kaydı kendiliğinden düzeltmez; düzeltme çalışan sayfasından bu itiraza bağlanarak yapılır.
export async function itirazKarar(_onceki: IslemSonucu, form: FormData): Promise<IslemSonucu> {
  const itirazId = sayiAl(form, "itiraz_id");
  const kabul = kararAl(form);
  const aciklama = metinAl(form, "aciklama");
  if (!itirazId) return { durum: "hata", mesaj: "İtiraz seçilmelidir." };
  if (kabul === null) return { durum: "hata", mesaj: "Kabul veya ret seçilmelidir." };
  if (!aciklama || aciklama.length < 5) return { durum: "hata", mesaj: "Karar gerekçesi girilmelidir." };

  const sonuc = await rpcCagir("itiraz_karar", { p_itiraz_id: itirazId, p_kabul: kabul, p_aciklama: aciklama });
  if (!sonuc.tamam) return { durum: "hata", mesaj: sonuc.mesaj };
  yenile();
  return {
    durum: "tamam",
    mesaj: kabul ? "İtiraz kabul edildi. Kayıt, çalışan sayfasından düzeltilmelidir." : "İtiraz reddedildi.",
  };
}
