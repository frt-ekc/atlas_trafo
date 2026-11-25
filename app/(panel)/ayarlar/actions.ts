"use server";

import { revalidatePath } from "next/cache";
import type { IslemSonucu } from "@/lib/islem-sonucu";
import { metinAl, rpcCagir } from "@/lib/supabase/rpc";

// Sistem yöneticisi bir ayarın değerini değiştirir (tolerans, eşikler…).
// Eski / yeni değer ve değiştiren ayar_gecmisi tablosuna veritabanı tarafından yazılır.
// Tam sayı, izin verilen aralık ve mola sıralaması veritabanında denetlenir (ayar_guncelle);
// değer bu yüzden olduğu gibi metin gönderilir, mesaj veritabanından gelir.
export async function ayarGuncelle(_onceki: IslemSonucu, form: FormData): Promise<IslemSonucu> {
  const anahtar = metinAl(form, "anahtar");
  const deger = metinAl(form, "deger");
  if (!anahtar) return { durum: "hata", mesaj: "Ayar seçilmelidir." };
  if (deger === null) return { durum: "hata", mesaj: "Yeni değer girilmelidir." };

  const sonuc = await rpcCagir("ayar_guncelle", { p_anahtar: anahtar, p_deger: deger });
  if (!sonuc.tamam) return { durum: "hata", mesaj: sonuc.mesaj };
  revalidatePath("/ayarlar");
  return { durum: "tamam", mesaj: "Ayar güncellendi. Yeni değer bir sonraki hesaplamadan itibaren geçerlidir." };
}
