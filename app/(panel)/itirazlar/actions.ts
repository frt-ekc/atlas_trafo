"use server";

import { revalidatePath } from "next/cache";
import type { IslemSonucu } from "@/lib/islem-sonucu";
import { kararAl, metinAl, rpcCagir, sayiAl } from "@/lib/supabase/rpc";
import { sunucuIstemcisi } from "@/lib/supabase/server";

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
// Bu yüzden kabulden sonra İK doğrudan o günün düzeltme penceresine götürülür (T-52).
// Gidilecek gün formdan değil, veritabanındaki itiraz kaydından okunur.
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
  if (!kabul) return { durum: "tamam", mesaj: "İtiraz reddedildi." };

  const supabase = await sunucuIstemcisi();
  const { data } = await supabase
    .from("itiraz")
    .select("calisan_id, gun_kaydi_id, gun:gun_kaydi_id(is_gunu)")
    .eq("id", itirazId)
    .maybeSingle();
  const kayit = data as { calisan_id: number; gun_kaydi_id: number; gun: { is_gunu: string } | null } | null;
  return {
    durum: "tamam",
    mesaj: "İtiraz kabul edildi. Şimdi kaydı düzeltip bu itiraza bağlayın.",
    adres: kayit?.gun
      ? `/calisanlar/${kayit.calisan_id}?ay=${kayit.gun.is_gunu.slice(0, 7)}&duzelt=${kayit.gun_kaydi_id}`
      : undefined,
  };
}
