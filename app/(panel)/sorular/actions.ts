"use server";

import { revalidatePath } from "next/cache";
import type { IslemSonucu } from "@/lib/islem-sonucu";
import { SORU_CEVABI } from "@/lib/etiketler";
import { metinAl, rpcCagir, sayiAl, zamanAl } from "@/lib/supabase/rpc";
import { sunucuIstemcisi } from "@/lib/supabase/server";
import { eksikSaatMesaji } from "./zorunlu-saatler";

// Zorunlu saat denetimi. Günde hangi saatlerin kayıtlı olduğu formdan değil veritabanından okunur:
// formdaki değer tarayıcıda değiştirilebilir. RLS yüzünden kullanıcı yalnızca görebildiği soruyu bulur.
// Veritabanı (cevap_saatleri_denetle) aynı kuralı ayrıca denetler; bu, kullanıcıya erken ve açık mesaj içindir.
async function saatHatasi(soruId: number, giris: string | null, cikis: string | null): Promise<string | null> {
  const supabase = await sunucuIstemcisi();
  const { data, error } = await supabase
    .from("amir_sorusu")
    .select("gun:gun_kaydi_id(giris_zamani, cikis_zamani)")
    .eq("id", soruId)
    .maybeSingle();
  if (error) return "Soru okunamadı. Lütfen tekrar deneyin.";
  if (!data) return "Soru bulunamadı veya görüntüleme yetkisi yok.";
  const gun = data.gun as unknown as { giris_zamani: string | null; cikis_zamani: string | null } | null;
  return eksikSaatMesaji({ giris: Boolean(gun?.giris_zamani), cikis: Boolean(gun?.cikis_zamani) }, giris, cikis);
}

// Amir soruyu cevaplar. Veritabanı (soru_cevapla) şunları denetler: soru bu amire atanmış ya da
// eskale edilmiş mi, hâlâ açık mı, "saat farklı" cevabında saat girilmiş mi. "Gelmedi" ve
// "bilmiyorum" kaydı değiştirmez; soru İK kararına geçer (çalışan aleyhine kararı İK verir).
export async function soruCevapla(_onceki: IslemSonucu, form: FormData): Promise<IslemSonucu> {
  const soruId = sayiAl(form, "soru_id");
  const cevap = metinAl(form, "cevap");
  if (!soruId) return { durum: "hata", mesaj: "Soru seçilmelidir." };
  if (!cevap || !(cevap in SORU_CEVABI)) return { durum: "hata", mesaj: "Cevap seçilmelidir." };

  // Saat yalnızca "saat farklı" cevabında gönderilir; diğerlerinde veritabanı önerilen saati yazar.
  const saatFarkli = cevap === "geldi_saat_farkli";
  const giris = saatFarkli ? zamanAl(form, "giris") : null;
  const cikis = saatFarkli ? zamanAl(form, "cikis") : null;
  if (saatFarkli) {
    const hata = await saatHatasi(soruId, giris, cikis);
    if (hata) return { durum: "hata", mesaj: hata };
  }

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
    mesaj: cevap === "gelmedi" || cevap === "bilmiyorum" ? "Cevap kaydedildi ve İK kararına gönderildi." : "Cevap kaydedildi, gün kaydı güncellendi.",
  };
}

// İK, amirin "gelmedi / bilmiyorum" dediği ya da İK'ya düşen (eskale / İK'ya atanmış) soruyu kapatır:
// devamsız sayar ya da saati yazar. Gün hemen hesaplanır.
export async function soruIkKarari(_onceki: IslemSonucu, form: FormData): Promise<IslemSonucu> {
  const soruId = sayiAl(form, "soru_id");
  const karar = metinAl(form, "karar");
  const gerekce = metinAl(form, "gerekce");
  if (!soruId) return { durum: "hata", mesaj: "Soru seçilmelidir." };
  if (karar !== "devamsiz" && karar !== "geldi") return { durum: "hata", mesaj: "Karar seçilmelidir." };
  if (!gerekce || gerekce.length < 5) return { durum: "hata", mesaj: "Gerekçe girilmelidir." };

  const devamsiz = karar === "devamsiz";
  const giris = devamsiz ? null : zamanAl(form, "giris");
  const cikis = devamsiz ? null : zamanAl(form, "cikis");
  if (!devamsiz) {
    const hata = await saatHatasi(soruId, giris, cikis);
    if (hata) return { durum: "hata", mesaj: hata };
  }

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
  return { durum: "tamam", mesaj: devamsiz ? 'Gün "Devamsız" olarak kaydedildi.' : "Karar kaydedildi, gün kaydı güncellendi." };
}
