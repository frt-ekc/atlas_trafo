"use server";

import { revalidatePath } from "next/cache";
import type { IslemSonucu } from "@/lib/islem-sonucu";
import { bugun } from "@/lib/hafta";
import { calismaDonemiDisi, metinAl, rpcCagir, sayiAl, sicildenCalisan } from "@/lib/supabase/rpc";
import { sunucuIstemcisi } from "@/lib/supabase/server";

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
  // T-68: işe henüz başlamamış çalışana geçici kart verilmez (çıkmış çalışan zaten aktif değildir)
  const donemDisi = calismaDonemiDisi(calisan, bugun());
  if (donemDisi) return { durum: "hata", mesaj: donemDisi };

  // T-86: çalışanda iade edilmemiş bir geçici kart varsa açıkça söylenir. Veritabanının çakışma mesajı
  // aynı kart ve aynı çalışan için ortak olduğu için bu durumda başka bir kartı anlatıyormuş gibi okunuyordu.
  const supabase = await sunucuIstemcisi();
  const { data: acik } = await supabase
    .from("gecici_kart_zimmet")
    .select("verilis_zamani, kart:gecici_kart_id(kart_no)")
    .eq("calisan_id", calisan.id)
    .is("iade_zamani", null)
    .maybeSingle();
  const acikZimmet = acik as { verilis_zamani: string; kart: { kart_no: string } | null } | null;
  if (acikZimmet) {
    const verilis = new Intl.DateTimeFormat("tr-TR", {
      timeZone: "Europe/Istanbul",
      day: "2-digit",
      month: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
    }).format(new Date(acikZimmet.verilis_zamani));
    return {
      durum: "hata",
      mesaj: `${calisan.adSoyad} adına iade edilmemiş ${acikZimmet.kart?.kart_no ?? "bir geçici kart"} var (verildi: ${verilis}). Yeni kart vermeden önce o kart iade alınmalıdır.`,
    };
  }

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
