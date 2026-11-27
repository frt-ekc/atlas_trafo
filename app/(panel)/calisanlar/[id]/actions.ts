"use server";

import { revalidatePath } from "next/cache";
import type { IslemSonucu } from "@/lib/islem-sonucu";
import { metinAl, rpcCagir, sayiAl, tarihAl, zamanAl } from "@/lib/supabase/rpc";
import { sunucuIstemcisi } from "@/lib/supabase/server";

const ALANLAR = ["giris_zamani", "cikis_zamani", "durum"] as const;
const DURUMLAR = ["tamam", "devamsiz", "izinli", "raporlu", "tatil", "vardiya_yok"];

// İK gün kaydında tek alanı düzeltir (kayit_duzelt). Eski / yeni değer, gerekçe ve yapan
// silinemeyen duzeltme tablosuna yazılır; isteğe bağlı olarak bir itiraza bağlanır.
export async function kayitDuzelt(_onceki: IslemSonucu, form: FormData): Promise<IslemSonucu> {
  const gunKaydiId = sayiAl(form, "gun_kaydi_id");
  const alan = metinAl(form, "alan") as (typeof ALANLAR)[number] | null;
  const gerekce = metinAl(form, "gerekce");
  if (!gunKaydiId) return { durum: "hata", mesaj: "Gün seçilmelidir." };
  if (!alan || !ALANLAR.includes(alan)) return { durum: "hata", mesaj: "Düzeltilecek alan seçilmelidir." };
  if (!gerekce || gerekce.length < 5) return { durum: "hata", mesaj: "Gerekçe girilmelidir." };

  const yeniDeger = alan === "durum" ? metinAl(form, "yeni_deger") : zamanAl(form, "yeni_deger");
  if (!yeniDeger || (alan === "durum" && !DURUMLAR.includes(yeniDeger))) {
    return { durum: "hata", mesaj: "Yeni değer girilmelidir." };
  }

  const sonuc = await rpcCagir<number>("kayit_duzelt", {
    p_gun_kaydi_id: gunKaydiId,
    p_alan: alan,
    p_yeni_deger: yeniDeger,
    p_gerekce: gerekce,
    p_itiraz_id: sayiAl(form, "itiraz_id"),
  });
  if (!sonuc.tamam) return { durum: "hata", mesaj: sonuc.mesaj };

  revalidatePath("/calisanlar", "layout");
  revalidatePath("/puantaj");
  revalidatePath("/itirazlar");
  revalidatePath("/");
  return {
    durum: "tamam",
    mesaj: "Düzeltme kaydedildi ve gün kaydı güncellendi.",
  };
}

// Çalışan itirazını sözlü ya da yazılı olarak amire veya İK'ya iletir; onlar sisteme girer.
// Veritabanı (itiraz_gir) denetler: amir yalnızca kendi bölümünün çalışanı için girebilir,
// kimse kendi itirazını giremez. Kabul / red kararı İK'dadır.
export async function itirazGir(_onceki: IslemSonucu, form: FormData): Promise<IslemSonucu> {
  const gunKaydiId = sayiAl(form, "gun_kaydi_id");
  const metin = metinAl(form, "metin");
  if (!gunKaydiId) return { durum: "hata", mesaj: "Gün seçilmelidir." };
  if (!metin || metin.length < 5) return { durum: "hata", mesaj: "İtiraz metni girilmelidir (en az 5 karakter)." };

  const sonuc = await rpcCagir<number>("itiraz_gir", { p_gun_kaydi_id: gunKaydiId, p_metin: metin });
  if (!sonuc.tamam) return { durum: "hata", mesaj: sonuc.mesaj };

  revalidatePath("/itirazlar");
  revalidatePath("/calisanlar", "layout");
  revalidatePath("/");
  return { durum: "tamam", mesaj: "İtiraz kaydedildi ve İK'ya iletildi." };
}

const IPTAL_NEDENLERI = ["kayip", "yenilendi", "isten_cikis", "diger"];

// İK çalışana yeni kart tanımlar. Aktif kartı olana tanımlanmaz; önce eskisi iptal edilir.
export async function kartTanimla(_onceki: IslemSonucu, form: FormData): Promise<IslemSonucu> {
  const calisanId = sayiAl(form, "calisan_id");
  const kartNo = metinAl(form, "kart_no")?.toUpperCase() ?? null;
  if (!calisanId) return { durum: "hata", mesaj: "Çalışan seçilmelidir." };
  if (!kartNo || !/^[A-Z0-9-]{1,32}$/.test(kartNo)) return { durum: "hata", mesaj: "Kart numarası yalnızca harf, rakam ve tire içermelidir." };

  // T-75: kart numarası zaten kayıtlıysa kimde olduğu söylenir (veritabanı yalnızca "tekillik" hatası verir)
  const supabase = await sunucuIstemcisi();
  const { data: mevcut } = await supabase
    .from("kart")
    .select("durum, calisan:calisan_id(sicil_no, ad, soyad)")
    .eq("kart_no", kartNo)
    .maybeSingle();
  const kart = mevcut as { durum: "aktif" | "iptal"; calisan: { sicil_no: string; ad: string; soyad: string } | null } | null;
  if (kart) {
    const kisi = kart.calisan ? `${kart.calisan.ad} ${kart.calisan.soyad} (${kart.calisan.sicil_no})` : "başka bir çalışan";
    return {
      durum: "hata",
      mesaj:
        kart.durum === "aktif"
          ? `${kartNo} numaralı kart şu anda ${kisi} adına tanımlı.`
          : `${kartNo} numaralı kart daha önce ${kisi} adına tanımlanmış ve iptal edilmiş; iptal edilen kart numarası yeniden kullanılamaz.`,
    };
  }

  const sonuc = await rpcCagir<number>("kart_tanimla", { p_calisan_id: calisanId, p_kart_no: kartNo });
  if (!sonuc.tamam) return { durum: "hata", mesaj: sonuc.mesaj };
  revalidatePath("/calisanlar", "layout");
  return { durum: "tamam", mesaj: `${kartNo} numaralı kart tanımlandı.` };
}

// Kayıp, yenileme ya da işten çıkışta kart iptal edilir. İptal edilen kart okutulursa uyarı üretilir.
export async function kartIptalEt(_onceki: IslemSonucu, form: FormData): Promise<IslemSonucu> {
  const kartId = sayiAl(form, "kart_id");
  const neden = metinAl(form, "neden");
  if (!kartId) return { durum: "hata", mesaj: "Kart seçilmelidir." };
  if (!neden || !IPTAL_NEDENLERI.includes(neden)) return { durum: "hata", mesaj: "İptal nedeni seçilmelidir." };

  const sonuc = await rpcCagir("kart_iptal_et", { p_kart_id: kartId, p_neden: neden });
  if (!sonuc.tamam) return { durum: "hata", mesaj: sonuc.mesaj };
  revalidatePath("/calisanlar", "layout");
  return { durum: "tamam", mesaj: "Kart iptal edildi." };
}

type CikisOzeti = {
  iptal_edilen_kart: number;
  vardiya_yok_yapilan_gun: number;
  silinen_plan: number;
  iptal_edilen_izin: number;
  iptal_edilen_fm_talebi: number;
  pasif_yapilan_hesap: number;
  // T-67: çıkış kilitli aya düştüyse (kilitli ayın planı ve izni değişmez)
  kilitli_ay_uyarisi?: string;
};

// İK işten çıkışı girer (isten_cikis_gir). Veritabanı denetler: iade edilmemiş geçici kart,
// çıkıştan sonra çalışılmış gün, ileri tarih, kendi çıkışı. Dönen özet bildirimde gösterilir.
export async function istenCikis(_onceki: IslemSonucu, form: FormData): Promise<IslemSonucu> {
  const calisanId = sayiAl(form, "calisan_id");
  const adSoyad = metinAl(form, "ad_soyad") ?? "Çalışan";
  const cikisTarihi = tarihAl(form, "cikis_tarihi");
  if (!calisanId) return { durum: "hata", mesaj: "Çalışan seçilmelidir." };
  if (!cikisTarihi) return { durum: "hata", mesaj: "Son çalışma günü girilmelidir." };

  const sonuc = await rpcCagir<CikisOzeti>("isten_cikis_gir", {
    p_calisan_id: calisanId,
    p_cikis_tarihi: cikisTarihi,
    p_aciklama: metinAl(form, "aciklama"),
  });
  if (!sonuc.tamam) return { durum: "hata", mesaj: sonuc.mesaj };

  const o = sonuc.veri;
  const parcalar = [
    o?.iptal_edilen_kart ? `${o.iptal_edilen_kart} kart iptal edildi` : null,
    o?.silinen_plan ? `${o.silinen_plan} vardiya planı silindi` : null,
    o?.iptal_edilen_izin ? `${o.iptal_edilen_izin} izin iptal edildi` : null,
    o?.iptal_edilen_fm_talebi ? `${o.iptal_edilen_fm_talebi} fazla mesai talebi iptal edildi` : null,
    o?.vardiya_yok_yapilan_gun ? `${o.vardiya_yok_yapilan_gun} gün "Vardiya planı yok" olarak güncellendi` : null,
    o?.pasif_yapilan_hesap ? "kullanıcı hesabı pasife alındı" : null,
  ].filter(Boolean);

  revalidatePath("/", "layout");
  const mesaj = `${adSoyad} için işten çıkış kaydedildi${parcalar.length ? `: ${parcalar.join(", ")}` : ""}.`;
  return { durum: "tamam", mesaj: o?.kilitli_ay_uyarisi ? `${mesaj} ${o.kilitli_ay_uyarisi}` : mesaj };
}
