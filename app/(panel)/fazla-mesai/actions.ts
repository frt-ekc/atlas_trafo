"use server";

import { revalidatePath } from "next/cache";
import type { IslemSonucu } from "@/lib/islem-sonucu";
import { kararAl, metinAl, rpcCagir, sayiAl, sicildenCalisan, tarihAl } from "@/lib/supabase/rpc";
import { sunucuIstemcisi } from "@/lib/supabase/server";

// Amir (ya da İK) fazla mesai talebi açar; İK onaylar. Veritabanı denetler: çalışan amirin bölümünde mi,
// yazılı onayı var mı, günlük 11 saat ve yıllık sınır aşılıyor mu, kimse kendine talep açamaz.
export async function fazlaMesaiTalepEt(_onceki: IslemSonucu, form: FormData): Promise<IslemSonucu> {
  const isGunu = tarihAl(form, "is_gunu");
  const saatMetni = metinAl(form, "saat")?.replace(",", ".");
  const saat = saatMetni ? Number(saatMetni) : NaN;
  const gerekce = metinAl(form, "gerekce");

  if (!isGunu) return { durum: "hata", mesaj: "Fazla mesai günü seçilmelidir." };
  if (!Number.isFinite(saat) || saat <= 0 || saat > 11) return { durum: "hata", mesaj: "Süre 0,5 ile 11 saat arasında olmalıdır." };
  if (!gerekce || gerekce.length < 5) return { durum: "hata", mesaj: "Gerekçe girilmelidir." };

  const bulunan = await sicildenCalisan(form);
  if (!bulunan.tamam) return { durum: "hata", mesaj: bulunan.mesaj };

  const sonuc = await rpcCagir<number>("fazla_mesai_talep_et", {
    p_calisan_id: bulunan.calisan.id,
    p_is_gunu: isGunu,
    p_planli_dk: Math.round(saat * 60),
    p_gerekce: gerekce,
  });
  if (!sonuc.tamam) return { durum: "hata", mesaj: sonuc.mesaj };

  revalidatePath("/fazla-mesai");
  revalidatePath("/vardiya-plani");
  revalidatePath("/");
  return { durum: "tamam", mesaj: `${bulunan.calisan.adSoyad} için fazla mesai talebi oluşturuldu ve İK onayına gönderildi.` };
}

// İK, amirin önceden açtığı fazla mesai talebini onaylar ya da reddeder.
export async function fazlaMesaiKarar(_onceki: IslemSonucu, form: FormData): Promise<IslemSonucu> {
  const planId = sayiAl(form, "plan_id");
  const onay = kararAl(form);
  const aciklama = metinAl(form, "aciklama");
  if (!planId) return { durum: "hata", mesaj: "Talep seçilmelidir." };
  if (onay === null) return { durum: "hata", mesaj: "Onay veya ret seçilmelidir." };
  if (!onay && (!aciklama || aciklama.length < 5)) return { durum: "hata", mesaj: "Ret gerekçesi girilmelidir." };

  const sonuc = await rpcCagir("fazla_mesai_karar", { p_plan_id: planId, p_onay: onay, p_aciklama: aciklama });
  if (!sonuc.tamam) return { durum: "hata", mesaj: sonuc.mesaj };
  revalidatePath("/fazla-mesai");
  revalidatePath("/vardiya-plani");
  // İşlenmiş güne gelen onay günü yeniden hesaplar (T-61)
  revalidatePath("/puantaj");
  revalidatePath("/");
  return { durum: "tamam", mesaj: onay ? "Fazla mesai talebi onaylandı." : "Fazla mesai talebi reddedildi." };
}

// Onaysız fazla mesai havuzu: plansız çalışılan süre İK kararına kadar puantaja girmez.
// Onay puantaja ekler (kilitli aya aitse sonraki aya fark olur); ret için gerekçe zorunlu.
export async function havuzKarari(_onceki: IslemSonucu, form: FormData): Promise<IslemSonucu> {
  const incelemeId = sayiAl(form, "inceleme_id");
  const onay = kararAl(form);
  const aciklama = metinAl(form, "aciklama");
  if (!incelemeId) return { durum: "hata", mesaj: "Kayıt seçilmelidir." };
  if (onay === null) return { durum: "hata", mesaj: "Onay veya ret seçilmelidir." };

  const sonuc = await rpcCagir("fazla_mesai_inceleme_karar", { p_inceleme_id: incelemeId, p_onay: onay, p_aciklama: aciklama });
  if (!sonuc.tamam) return { durum: "hata", mesaj: sonuc.mesaj };
  revalidatePath("/fazla-mesai");
  revalidatePath("/puantaj");
  revalidatePath("/");
  return { durum: "tamam", mesaj: onay ? "Fazla mesai onaylandı ve puantaja eklendi." : "Fazla mesai reddedildi." };
}

// Çalışanın yıllık yazılı fazla mesai onayı (İş Kanunu m.41). Onay olmadan fazla mesai planlanamaz.
export async function yaziliOnayGir(_onceki: IslemSonucu, form: FormData): Promise<IslemSonucu> {
  const yil = sayiAl(form, "yil");
  const imzaTarihi = tarihAl(form, "imza_tarihi");
  const belgeNo = metinAl(form, "belge_no");
  if (!yil || yil < 2000 || yil > 2100) return { durum: "hata", mesaj: "Yıl girilmelidir." };
  if (!imzaTarihi) return { durum: "hata", mesaj: "İmza tarihi girilmelidir." };
  if (Number(imzaTarihi.slice(0, 4)) > yil) return { durum: "hata", mesaj: "İmza tarihi, onay yılından sonra olamaz." };
  if (!belgeNo) return { durum: "hata", mesaj: "Belge numarası girilmelidir." };

  const bulunan = await sicildenCalisan(form);
  if (!bulunan.tamam) return { durum: "hata", mesaj: bulunan.mesaj };

  const sonuc = await rpcCagir<number>("fazla_mesai_onayi_gir", {
    p_calisan_id: bulunan.calisan.id,
    p_yil: yil,
    p_imza_tarihi: imzaTarihi,
    p_belge_no: belgeNo,
  });
  if (!sonuc.tamam) {
    return { durum: "hata", mesaj: sonuc.mesaj === "Bu kayıt daha önce eklenmiştir." ? `${bulunan.calisan.adSoyad} için ${yil} yılı onayı daha önce kaydedilmiştir.` : sonuc.mesaj };
  }
  revalidatePath("/fazla-mesai");
  return { durum: "tamam", mesaj: `${bulunan.calisan.adSoyad} için ${yil} yazılı onayı kaydedildi.` };
}

// Çalışan onayını geri çekerse: bildirimden 30 gün sonra onay geçersiz olur.
export async function yaziliOnayGeriAl(_onceki: IslemSonucu, form: FormData): Promise<IslemSonucu> {
  const yil = sayiAl(form, "yil");
  const bildirim = tarihAl(form, "bildirim_tarihi");
  if (!yil) return { durum: "hata", mesaj: "Yıl girilmelidir." };
  if (!bildirim) return { durum: "hata", mesaj: "Bildirim tarihi girilmelidir." };

  const bulunan = await sicildenCalisan(form);
  if (!bulunan.tamam) return { durum: "hata", mesaj: bulunan.mesaj };

  const supabase = await sunucuIstemcisi();
  const { data: onay } = await supabase
    .from("fazla_mesai_onayi")
    .select("id, geri_alma_bildirim_tarihi")
    .eq("calisan_id", bulunan.calisan.id)
    .eq("yil", yil)
    .maybeSingle();
  if (!onay) return { durum: "hata", mesaj: `${bulunan.calisan.adSoyad} için ${yil} yılına ait yazılı onay bulunmuyor.` };
  if (onay.geri_alma_bildirim_tarihi) return { durum: "hata", mesaj: "Bu onay daha önce geri alınmıştır." };

  const sonuc = await rpcCagir("fazla_mesai_onayi_geri_al", { p_onay_id: onay.id, p_bildirim_tarihi: bildirim });
  if (!sonuc.tamam) return { durum: "hata", mesaj: sonuc.mesaj };
  revalidatePath("/fazla-mesai");
  revalidatePath("/uyarilar");
  return { durum: "tamam", mesaj: "Onay geri alındı. Onay, bildirim tarihinden 30 gün sonra geçersiz olur." };
}
