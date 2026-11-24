"use server";

import { revalidatePath } from "next/cache";
import type { IslemSonucu } from "@/lib/islem-sonucu";
import { bugun } from "@/lib/hafta";
import { metinAl, rpcCagir, sayiAl, sicildenCalisan, tarihAl } from "@/lib/supabase/rpc";

// Amir (ya da İK) bir günün vardiyasını girer ya da değiştirir. Veritabanı (vardiya_plani_gir) denetler:
// çalışan amirin bölümünde mi, ay kilitli mi. Geçmiş güne giriş "geriye dönük" sayılır ve İK onayına düşer.
export async function vardiyaPlaniGir(_onceki: IslemSonucu, form: FormData): Promise<IslemSonucu> {
  const gun = tarihAl(form, "tarih");
  const vardiyaId = sayiAl(form, "vardiya_id");
  if (!gun) return { durum: "hata", mesaj: "Gün seçilmelidir." };
  if (!vardiyaId) return { durum: "hata", mesaj: "Vardiya seçilmelidir." };

  const bulunan = await sicildenCalisan(form);
  if (!bulunan.tamam) return { durum: "hata", mesaj: bulunan.mesaj };

  const sonuc = await rpcCagir<number>("vardiya_plani_gir", {
    p_calisan_id: bulunan.calisan.id,
    p_tarih: gun,
    p_vardiya_id: vardiyaId,
    p_aciklama: metinAl(form, "aciklama"),
  });
  if (!sonuc.tamam) return { durum: "hata", mesaj: sonuc.mesaj };

  revalidatePath("/vardiya-plani");
  revalidatePath("/");
  const geriye = gun < bugun();
  return {
    durum: "tamam",
    mesaj: geriye
      ? `${bulunan.calisan.adSoyad} için geriye dönük plan kaydedildi ve İK onayına gönderildi.`
      : `${bulunan.calisan.adSoyad} için vardiya planı kaydedildi.`,
  };
}

// İK, geçmiş güne girilmiş (geriye dönük) vardiya planını onaylar ya da reddeder.
// Planı giren kişi ve planın sahibi onaylayamaz (görevler ayrılığı; veritabanı denetler).
// Onay günü hemen düzeltir ya da işletir; ret hiçbir şeyi değiştirmez.
export async function vardiyaPlaniOnayla(_onceki: IslemSonucu, form: FormData): Promise<IslemSonucu> {
  const planId = sayiAl(form, "plan_id");
  const karar = metinAl(form, "karar");
  if (!planId || (karar !== "onay" && karar !== "ret")) return { durum: "hata", mesaj: "Plan ve karar seçilmelidir." };

  const sonuc = await rpcCagir("vardiya_plani_onayla", { p_plan_id: planId, p_onay: karar === "onay" });
  if (!sonuc.tamam) return { durum: "hata", mesaj: sonuc.mesaj };
  // Onay gün kaydını ve puantajı değiştirebilir; bütün panel yenilenir.
  revalidatePath("/", "layout");
  return {
    durum: "tamam",
    mesaj:
      karar === "onay"
        ? "Geriye dönük plan onaylandı ve gün kaydı güncellendi."
        : "Geriye dönük plan reddedildi. Gün kaydı değişmedi.",
  };
}
