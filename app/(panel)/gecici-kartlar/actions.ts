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

// T-85: Geçici kartın durumunu değiştirir (gecici_kart_durum): kayıp bildir, kayıp kart bulundu (aktif),
// iptal et. Güvenlik ya da İK; gerekçe en az 5 karakter. Kart kayıp ya da iptal yapılırsa üstündeki açık
// zimmet kapanır (veritabanı yapar); kayıp kart okutulursa İK'ya uyarı gider.
const KART_DURUMLARI = { kayip: "kayıp olarak işaretlendi", aktif: "bulundu, yeniden kullanılabilir", iptal: "iptal edildi" } as const;

export async function kartDurumu(_onceki: IslemSonucu, form: FormData): Promise<IslemSonucu> {
  const kartId = sayiAl(form, "kart_id");
  const kartNo = metinAl(form, "kart_no") ?? "Geçici kart";
  const durum = metinAl(form, "durum");
  const gerekce = metinAl(form, "gerekce")?.trim() ?? "";
  if (!kartId) return { durum: "hata", mesaj: "Kart seçilmelidir." };
  if (durum !== "kayip" && durum !== "aktif" && durum !== "iptal") return { durum: "hata", mesaj: "Yeni durum seçilmelidir." };
  if (gerekce.length < 5) return { durum: "hata", mesaj: "Durum değişikliğinin gerekçesi yazılmalı (en az 5 karakter)." };

  const sonuc = await rpcCagir("gecici_kart_durum", { p_gecici_kart_id: kartId, p_durum: durum, p_gerekce: gerekce });
  if (!sonuc.tamam) return { durum: "hata", mesaj: sonuc.mesaj };

  yenile();
  return { durum: "tamam", mesaj: `${kartNo} ${KART_DURUMLARI[durum]}.`, uyari: durum !== "aktif" };
}
