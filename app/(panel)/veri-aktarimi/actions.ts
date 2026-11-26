"use server";

import { revalidatePath } from "next/cache";
import { bugun } from "@/lib/hafta";
import type { IslemSonucu } from "@/lib/islem-sonucu";
import { metinAl, rpcCagir, sayiAl, tarihAl, zamanAl } from "@/lib/supabase/rpc";

// İK okuyucu arızasını girer. Arıza süresince o okuyucudan beklenen okutmalar eksik sayılmaz;
// gece işi kanıt arar, yoksa amire "arıza, kanıt yok" sorusu açar.
export async function arizaGir(_onceki: IslemSonucu, form: FormData): Promise<IslemSonucu> {
  const okuyucuId = sayiAl(form, "okuyucu_id");
  const baslangic = zamanAl(form, "baslangic");
  const bitis = zamanAl(form, "bitis");
  if (!okuyucuId) return { durum: "hata", mesaj: "Okuyucu seçilmelidir." };
  if (!baslangic) return { durum: "hata", mesaj: "Arıza başlangıcı girilmelidir." };
  if (bitis && bitis <= baslangic) return { durum: "hata", mesaj: "Bitiş, başlangıçtan sonra olmalıdır." };

  const sonuc = await rpcCagir<number>("ariza_gir", {
    p_okuyucu_id: okuyucuId,
    p_baslangic: baslangic,
    p_bitis: bitis,
    p_aciklama: metinAl(form, "aciklama"),
  });
  if (!sonuc.tamam) return { durum: "hata", mesaj: sonuc.mesaj };
  revalidatePath("/veri-aktarimi");
  return { durum: "tamam", mesaj: "Arıza kaydedildi. Kayıt, bir sonraki gece işleminde dikkate alınır." };
}

// Gece işinin "arıza şüphesi" olarak açtığı kaydı İK onaylar ya da reddeder.
export async function arizaKarari(_onceki: IslemSonucu, form: FormData): Promise<IslemSonucu> {
  const arizaId = sayiAl(form, "ariza_id");
  const karar = metinAl(form, "karar");
  if (!arizaId || (karar !== "onay" && karar !== "ret")) return { durum: "hata", mesaj: "Arıza ve karar seçilmelidir." };

  const sonuc = await rpcCagir("ariza_karar", { p_ariza_id: arizaId, p_onay: karar === "onay" });
  if (!sonuc.tamam) return { durum: "hata", mesaj: sonuc.mesaj };
  revalidatePath("/veri-aktarimi");
  return { durum: "tamam", mesaj: karar === "onay" ? "Arıza onaylandı." : "Arıza şüphesi reddedildi." };
}

type GunSonucu = { gun: string; durum: "basarili" | "hatali" | "calisiyor"; ozet: Record<string, unknown> | null };

// Özet alanlarının ekrandaki adları (gece_isi.ozet)
const OZET_ADI: Record<string, string> = {
  gun_kaydi: "gün kaydı",
  duzeltme: "otomatik düzeltme",
  soru: "soru",
  eskale: "üst amire iletilen",
  uyari: "uyarı",
};

// Demo düğmesi: seçilen günü gece işinden geçirir (normalde pg_cron her gece yapar).
// Tekrar çalıştırmak güvenlidir; var olan kayıtlar bozulmaz, yalnızca eksikler eklenir.
// T-24: ekrandan yalnızca tek gün. Çok gün tek istekte işlenirse veritabanının 8 saniyelik istek
// sınırına takılır ve işlem yarıda kalır; toplu işlem SQL Editor'den ya da pg_cron ile yapılır.
export async function geceIsiTetikle(_onceki: IslemSonucu, form: FormData): Promise<IslemSonucu> {
  const gun = tarihAl(form, "gun");
  if (!gun) return { durum: "hata", mesaj: "İşlenecek gün seçilmelidir." };
  if (gun >= bugun()) return { durum: "hata", mesaj: "Yalnızca geçmiş günler işlenebilir." };
  const baslangic = gun;
  const bitis = gun;

  const sonuc = await rpcCagir<GunSonucu[]>("gece_isi_tetikle", { p_baslangic: baslangic, p_bitis: bitis });
  if (!sonuc.tamam) return { durum: "hata", mesaj: sonuc.mesaj };

  const gunler = sonuc.veri ?? [];
  const hatali = gunler.filter((g) => g.durum === "hatali");
  const toplam = new Map<string, number>();
  for (const g of gunler) {
    for (const [anahtar, deger] of Object.entries(g.ozet ?? {})) {
      if (typeof deger === "number") toplam.set(anahtar, (toplam.get(anahtar) ?? 0) + deger);
    }
  }
  const ozet = Object.entries(OZET_ADI)
    .filter(([k]) => toplam.get(k))
    .map(([k, ad]) => `${toplam.get(k)} ${ad}`)
    .join(", ");

  // Gece işi neredeyse her ekranı etkiler
  revalidatePath("/", "layout");

  if (hatali.length) {
    return {
      durum: "hata",
      mesaj: `İşlem tamamlanamadı: ${gunler.length} günden ${hatali.length} gün işlenemedi. Sistem yöneticisi ile iletişime geçilmelidir.`,
    };
  }
  return { durum: "tamam", mesaj: `${gunler.length} gün işlendi${ozet ? `: ${ozet}` : ""}.` };
}
