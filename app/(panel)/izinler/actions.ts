"use server";

import { revalidatePath } from "next/cache";
import type { IslemSonucu } from "@/lib/islem-sonucu";
import { metinAl, rpcCagir, sayiAl, sicildenCalisan, tarihAl } from "@/lib/supabase/rpc";

const IZIN_TURLERI = ["yillik", "rapor", "mazeret", "ucretsiz", "diger"];
const SAATLIK_TURLER = ["vizite", "mazeret", "diger"];

function yenile() {
  revalidatePath("/izinler");
  revalidatePath("/vardiya-plani");
  revalidatePath("/calisanlar", "layout");
  revalidatePath("/");
}

// İK gün bazlı izin girer. Görevler ayrılığı: İK kendi iznini giremez (veritabanı denetler).
export async function izinGir(_onceki: IslemSonucu, form: FormData): Promise<IslemSonucu> {
  const tur = metinAl(form, "tur");
  const baslangic = tarihAl(form, "baslangic");
  const bitis = tarihAl(form, "bitis") ?? baslangic;
  if (!tur || !IZIN_TURLERI.includes(tur)) return { durum: "hata", mesaj: "İzin türü seçilmelidir." };
  if (!baslangic || !bitis) return { durum: "hata", mesaj: "Başlangıç günü seçilmelidir." };
  if (bitis < baslangic) return { durum: "hata", mesaj: "Bitiş günü, başlangıç gününden önce olamaz." };

  const bulunan = await sicildenCalisan(form);
  if (!bulunan.tamam) return { durum: "hata", mesaj: bulunan.mesaj };

  const sonuc = await rpcCagir<number>("izin_gir", {
    p_calisan_id: bulunan.calisan.id,
    p_tur: tur,
    p_baslangic: baslangic,
    p_bitis: bitis,
    p_aciklama: metinAl(form, "aciklama"),
  });
  if (!sonuc.tamam) return { durum: "hata", mesaj: sonuc.mesaj };
  yenile();
  return { durum: "tamam", mesaj: `${bulunan.calisan.adSoyad} için izin kaydedildi.` };
}

// Yanlış girilen izin silinmez, iptal edilir (kim / ne zaman / neden tutulur).
// Gece işinden geçmiş günü olan izin iptal edilemez: o günler kayıt düzeltmeyle düzeltilir.
export async function izinIptal(_onceki: IslemSonucu, form: FormData): Promise<IslemSonucu> {
  const izinId = sayiAl(form, "izin_id");
  const neden = metinAl(form, "neden");
  if (!izinId) return { durum: "hata", mesaj: "İzin seçilmelidir." };
  if (!neden || neden.length < 5) return { durum: "hata", mesaj: "İptal nedeni girilmelidir (en az 5 karakter)." };

  const sonuc = await rpcCagir("izin_iptal", { p_izin_id: izinId, p_neden: neden });
  if (!sonuc.tamam) return { durum: "hata", mesaj: sonuc.mesaj };
  yenile();
  return { durum: "tamam", mesaj: "İzin iptal edildi." };
}

// Saat aralıklı izin (vizite, mazeret). Saatler o günün Türkiye saatiyle girilir.
export async function saatlikIzinGir(_onceki: IslemSonucu, form: FormData): Promise<IslemSonucu> {
  const tarih = tarihAl(form, "tarih");
  const bas = metinAl(form, "bas_saat");
  const bit = metinAl(form, "bit_saat");
  const tur = metinAl(form, "tur");
  const saatGecerli = (s: string | null) => s !== null && /^\d{2}:\d{2}$/.test(s);
  if (!tarih) return { durum: "hata", mesaj: "Gün seçilmelidir." };
  if (!saatGecerli(bas) || !saatGecerli(bit)) return { durum: "hata", mesaj: "Başlangıç ve bitiş saati girilmelidir." };
  if (bit! <= bas!) return { durum: "hata", mesaj: "Bitiş saati, başlangıç saatinden sonra olmalıdır." };
  if (!tur || !SAATLIK_TURLER.includes(tur)) return { durum: "hata", mesaj: "İzin türü seçilmelidir." };

  const bulunan = await sicildenCalisan(form);
  if (!bulunan.tamam) return { durum: "hata", mesaj: bulunan.mesaj };

  const sonuc = await rpcCagir<number>("saatlik_izin_gir", {
    p_calisan_id: bulunan.calisan.id,
    p_tarih: tarih,
    p_baslangic: `${tarih}T${bas}:00+03:00`,
    p_bitis: `${tarih}T${bit}:00+03:00`,
    p_tur: tur,
    p_aciklama: metinAl(form, "aciklama"),
  });
  if (!sonuc.tamam) return { durum: "hata", mesaj: sonuc.mesaj };
  yenile();
  revalidatePath("/puantaj");
  return { durum: "tamam", mesaj: `${bulunan.calisan.adSoyad} için saatlik izin kaydedildi.` };
}
