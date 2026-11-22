"use server";

import { revalidatePath } from "next/cache";
import type { IslemSonucu } from "@/lib/islem-sonucu";
import { SORU_CEVABI } from "@/lib/etiketler";
import { metinAl, rpcCagir, sayiAl, zamanAl } from "@/lib/supabase/rpc";

// Amir soruyu cevaplar. Veritabanı (soru_cevapla) şunları denetler: soru bu amire atanmış ya da
// eskale edilmiş mi, hâlâ açık mı, "saat farklı" cevabında saat girilmiş mi. "Gelmedi" ve
// "bilmiyorum" kaydı değiştirmez; soru İK kararına geçer (çalışan aleyhine kararı İK verir).
export async function soruCevapla(_onceki: IslemSonucu, form: FormData): Promise<IslemSonucu> {
  const soruId = sayiAl(form, "soru_id");
  const cevap = metinAl(form, "cevap");
  if (!soruId) return { durum: "hata", mesaj: "Soru seçilmedi." };
  if (!cevap || !(cevap in SORU_CEVABI)) return { durum: "hata", mesaj: "Bir cevap seçin." };

  // Saat yalnızca "saat farklı" cevabında gönderilir; diğerlerinde veritabanı önerilen saati yazar.
  const saatFarkli = cevap === "geldi_saat_farkli";
  const giris = saatFarkli ? zamanAl(form, "giris") : null;
  const cikis = saatFarkli ? zamanAl(form, "cikis") : null;
  if (saatFarkli && !giris && !cikis) return { durum: "hata", mesaj: "Giriş ya da çıkış saatini girin." };

  const sonuc = await rpcCagir("soru_cevapla", {
    p_soru_id: soruId,
    p_cevap: cevap,
    p_giris: giris,
    p_cikis: cikis,
    p_aciklama: metinAl(form, "aciklama"),
  });
  if (!sonuc.tamam) return { durum: "hata", mesaj: sonuc.mesaj };

  revalidatePath("/sorular");
  revalidatePath("/");
  return {
    durum: "tamam",
    mesaj: cevap === "gelmedi" || cevap === "bilmiyorum" ? "Cevap kaydedildi. Karar İK'ya geçti." : "Cevap kaydedildi; gün kaydı düzeltildi ve hesaplandı.",
  };
}

// İK, amirin "gelmedi / bilmiyorum" dediği ya da İK'ya düşen (eskale / İK'ya atanmış) soruyu kapatır:
// devamsız sayar ya da saati yazar. Gün hemen hesaplanır.
export async function soruIkKarari(_onceki: IslemSonucu, form: FormData): Promise<IslemSonucu> {
  const soruId = sayiAl(form, "soru_id");
  const karar = metinAl(form, "karar");
  const gerekce = metinAl(form, "gerekce");
  if (!soruId) return { durum: "hata", mesaj: "Soru seçilmedi." };
  if (karar !== "devamsiz" && karar !== "geldi") return { durum: "hata", mesaj: "Bir karar seçin." };
  if (!gerekce || gerekce.length < 5) return { durum: "hata", mesaj: "Gerekçeyi yazın." };

  const devamsiz = karar === "devamsiz";
  const giris = devamsiz ? null : zamanAl(form, "giris");
  const cikis = devamsiz ? null : zamanAl(form, "cikis");
  if (!devamsiz && !giris && !cikis) return { durum: "hata", mesaj: "Giriş ya da çıkış saatini girin." };

  const sonuc = await rpcCagir("soru_ik_karari", {
    p_soru_id: soruId,
    p_devamsiz: devamsiz,
    p_gerekce: gerekce,
    p_giris: giris,
    p_cikis: cikis,
  });
  if (!sonuc.tamam) return { durum: "hata", mesaj: sonuc.mesaj };

  revalidatePath("/sorular");
  revalidatePath("/");
  return { durum: "tamam", mesaj: devamsiz ? "Gün devamsız olarak işaretlendi." : "Saat yazıldı, gün hesaplandı; soru kapandı." };
}
