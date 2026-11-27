"use server";

import { revalidatePath } from "next/cache";
import type { IslemSonucu } from "@/lib/islem-sonucu";
import { rpcCagir, sayiAl } from "@/lib/supabase/rpc";
import { TOPLU_SINIR } from "./toplu-sinir";

// Uyarıyı "görüldü" yapar (yalnızca İK). Kim, ne zaman gördü veritabanında tutulur.
export async function uyariGoruldu(_onceki: IslemSonucu, form: FormData): Promise<IslemSonucu> {
  const uyariId = sayiAl(form, "uyari_id");
  if (!uyariId) return { durum: "hata", mesaj: "Uyarı seçilmelidir." };

  const sonuc = await rpcCagir("uyari_goruldu", { p_uyari_id: uyariId });
  if (!sonuc.tamam) return { durum: "hata", mesaj: sonuc.mesaj };

  revalidatePath("/uyarilar");
  revalidatePath("/");
  return { durum: "tamam", mesaj: "Uyarı görüldü olarak işaretlendi." };
}

// Seçilen uyarıları toplu "görüldü" yapar. Yeni veritabanı fonksiyonu yoktur: aynı
// uyari_goruldu RPC'si her uyarı için sırayla çağrılır; yetkiyi ve "kim, ne zaman gördü"
// kaydını her çağrıda veritabanı kendisi yapar.
export async function uyarilarGoruldu(_onceki: IslemSonucu, form: FormData): Promise<IslemSonucu> {
  const idler = [
    ...new Set(
      form
        .getAll("uyari_id")
        .filter((d): d is string => typeof d === "string" && /^\d+$/.test(d))
        .map(Number),
    ),
  ];
  if (idler.length === 0) return { durum: "hata", mesaj: "Uyarı seçilmelidir." };
  if (idler.length > TOPLU_SINIR) return { durum: "hata", mesaj: `Bir seferde en fazla ${TOPLU_SINIR} uyarı seçilebilir.` };

  let basarili = 0;
  let ilkHata: string | null = null;
  for (const id of idler) {
    const sonuc = await rpcCagir("uyari_goruldu", { p_uyari_id: id });
    if (sonuc.tamam) basarili++;
    else ilkHata ??= sonuc.mesaj;
  }

  revalidatePath("/uyarilar");
  revalidatePath("/");
  if (basarili === 0) return { durum: "hata", mesaj: ilkHata ?? "Uyarılar işaretlenemedi." };
  if (basarili < idler.length) {
    return {
      durum: "tamam",
      uyari: true,
      mesaj: `${basarili} uyarı görüldü olarak işaretlendi; ${idler.length - basarili} uyarı işaretlenemedi: ${ilkHata}`,
    };
  }
  return { durum: "tamam", mesaj: `${basarili} uyarı görüldü olarak işaretlendi.` };
}

// T-81: Kart paylaşımı şüphesinde İK kararı (kart_paylasim_karar). Yalnızca İK; gerekçe en az 10 karakter;
// karar bir kez verilir ve değiştirilemez; şüpheli çiftteki iki çalışan da kendi şüphesine karar veremez.
// "Paylaşım var" kararı gün kayıtlarına dokunmaz (çalışan aleyhine düzeltme İK'nın elle yapacağı iştir,
// KVKK m.11); bu yüzden düzeltilmesi gereken günler sonuç mesajında listelenir.
type PaylasimSonucu = { karar: "paylasim_var" | "yanlis_alarm"; gunler: { tarih: string }[]; mesaj: string };

export async function kartPaylasimKarar(_onceki: IslemSonucu, form: FormData): Promise<IslemSonucu> {
  const uyariId = sayiAl(form, "uyari_id");
  const karar = form.get("paylasim");
  const gerekce = typeof form.get("gerekce") === "string" ? String(form.get("gerekce")).trim() : "";
  if (!uyariId) return { durum: "hata", mesaj: "Uyarı seçilmelidir." };
  if (karar !== "var" && karar !== "yok") return { durum: "hata", mesaj: "Karar (paylaşım var / yanlış alarm) seçilmelidir." };
  if (gerekce.length < 10) return { durum: "hata", mesaj: "Karar gerekçesi yazılmalı (en az 10 karakter)." };

  const sonuc = await rpcCagir<PaylasimSonucu>("kart_paylasim_karar", {
    p_uyari_id: uyariId,
    p_paylasim_var: karar === "var",
    p_gerekce: gerekce,
  });
  if (!sonuc.tamam) return { durum: "hata", mesaj: sonuc.mesaj };

  revalidatePath("/uyarilar");
  revalidatePath("/");
  const veri = sonuc.veri;
  if (veri?.karar === "paylasim_var") {
    const gunler = (veri.gunler ?? []).map((g) => `${g.tarih.slice(8, 10)}.${g.tarih.slice(5, 7)}`);
    return {
      durum: "tamam",
      uyari: true,
      mesaj: `${veri.mesaj}${gunler.length ? ` Şüpheli günler: ${gunler.join(", ")}.` : ""}`,
    };
  }
  return { durum: "tamam", mesaj: veri?.mesaj ?? "Karar kaydedildi." };
}
