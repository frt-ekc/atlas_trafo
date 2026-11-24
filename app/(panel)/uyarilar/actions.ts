"use server";

import { revalidatePath } from "next/cache";
import type { IslemSonucu } from "@/lib/islem-sonucu";
import { rpcCagir, sayiAl } from "@/lib/supabase/rpc";

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
const TOPLU_SINIR = 200;

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
