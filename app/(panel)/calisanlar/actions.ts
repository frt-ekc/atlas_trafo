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
  if (!sicil || !/^[A-Z0-9-]{1,20}$/.test(sicil)) return { durum: "hata", mesaj: "Sicil numarası harf, rakam ve tireden oluşmalı." };
  if (!ad || !soyad) return { durum: "hata", mesaj: "Ad ve soyadı yazın." };
  if (!departmanId) return { durum: "hata", mesaj: "Departmanı seçin." };
  if (!iseGiris) return { durum: "hata", mesaj: "İşe giriş tarihini girin." };

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
    mesaj: `${ad} ${soyad} eklendi. Sırada: kart tanımlama ve vardiya planı (plan yoksa gece işi gün kaydı açmaz).`,
  };
}
