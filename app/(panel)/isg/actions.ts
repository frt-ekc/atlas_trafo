"use server";

import { revalidatePath } from "next/cache";
import type { IslemSonucu } from "@/lib/islem-sonucu";
import { metinAl, rpcCagir, sayiAl, sicildenCalisan, tarihAl } from "@/lib/supabase/rpc";

const BELGE_TURLERI = ["isg_egitimi", "saglik_muayenesi"];

// İSG uzmanı eğitim / sağlık muayenesi geçerlilik tarihini girer. Sonuç ya da teşhis girilmez (KVKK).
// Yenileme yeni kayıttır; en son girilen geçerlidir. Kendi belgesini giremez.
export async function isgBelgeGir(_onceki: IslemSonucu, form: FormData): Promise<IslemSonucu> {
  const tur = metinAl(form, "tur");
  const bitis = tarihAl(form, "gecerlilik_bitis");
  if (!tur || !BELGE_TURLERI.includes(tur)) return { durum: "hata", mesaj: "Belge türü seçilmelidir." };
  if (!bitis) return { durum: "hata", mesaj: "Geçerlilik bitiş tarihi girilmelidir." };

  const bulunan = await sicildenCalisan(form);
  if (!bulunan.tamam) return { durum: "hata", mesaj: bulunan.mesaj };

  const sonuc = await rpcCagir<number>("isg_belge_gir", {
    p_calisan_id: bulunan.calisan.id,
    p_tur: tur,
    p_gecerlilik_bitis: bitis,
    p_belge_no: metinAl(form, "belge_no"),
  });
  if (!sonuc.tamam) return { durum: "hata", mesaj: sonuc.mesaj };
  revalidatePath("/isg");
  revalidatePath("/");
  return { durum: "tamam", mesaj: `${bulunan.calisan.adSoyad} için belge kaydedildi.` };
}

// Departmana bölgeye giriş yetkisi verir ya da kaldırır. İz (kim / ne zaman) veritabanında tutulur.
export async function bolgeYetkisi(_onceki: IslemSonucu, form: FormData): Promise<IslemSonucu> {
  const bolgeId = sayiAl(form, "bolge_id");
  const departmanId = sayiAl(form, "departman_id");
  const islem = metinAl(form, "islem");
  if (!bolgeId || !departmanId || (islem !== "ver" && islem !== "kaldir")) return { durum: "hata", mesaj: "Bölge ve departman seçilmelidir." };

  const sonuc = await rpcCagir(islem === "ver" ? "bolge_yetkisi_ver" : "bolge_yetkisi_kaldir", {
    p_bolge_id: bolgeId,
    p_departman_id: departmanId,
  });
  if (!sonuc.tamam) return { durum: "hata", mesaj: sonuc.mesaj };
  revalidatePath("/isg");
  return { durum: "tamam", mesaj: islem === "ver" ? "Bölge yetkisi verildi." : "Bölge yetkisi kaldırıldı." };
}
