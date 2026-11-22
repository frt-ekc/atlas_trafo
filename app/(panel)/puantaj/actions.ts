"use server";

import { revalidatePath } from "next/cache";
import type { IslemSonucu } from "@/lib/islem-sonucu";
import { metinAl, rpcCagir } from "@/lib/supabase/rpc";

// ay_kilitle'nin döndürdüğü özet (20261201020000_kilit_ozeti.sql)
type KilitOzeti = {
  donem: string;
  zorla: boolean;
  kodsuz_gun: number;
  mesaj: string;
  zorla_gecilen: { acik_soru_gun: number; acik_itiraz: number; bekleyen_fazla_mesai: number; bekleyen_plan_onayi: number };
};

// Ayı kilitler ve puantajı yazar (ay_kilitle). Kilit GERİ AÇILAMAZ; sonradan gelen düzeltme
// sonraki aya fark satırı olur. Açık soru / itiraz ya da kararı bekleyen onaysız fazla mesai varsa
// veritabanı reddeder; "zorla" işaretlenirse yine de kilitler.
export async function ayKilitle(_onceki: IslemSonucu, form: FormData): Promise<IslemSonucu> {
  const ay = metinAl(form, "ay");
  if (!ay || !/^\d{4}-(0[1-9]|1[0-2])$/.test(ay)) return { durum: "hata", mesaj: "Ay seçilmedi." };
  if (metinAl(form, "onay") !== "evet") return { durum: "hata", mesaj: "Kilidin geri açılamayacağını onaylayın." };
  const [yil, ayNo] = ay.split("-").map(Number);

  const sonuc = await rpcCagir<KilitOzeti>("ay_kilitle", { p_yil: yil, p_ay: ayNo, p_zorla: metinAl(form, "zorla") === "evet" });
  if (!sonuc.tamam) return { durum: "hata", mesaj: sonuc.mesaj };

  revalidatePath("/", "layout");
  // Veritabanının kilit özeti gösterilir: zorla geçilenler ve puantaja kodsuz giren gün sayısı.
  // Kilit geri açılamadığı için İK bunu tam bu anda görmeli.
  const ozet = sonuc.veri?.mesaj ?? "Ay kilitlendi.";
  // Puantaja hiçbir kodla girmeyen gün varsa (zorla kilitlenen açık sorulu gün) uyarı olarak gösterilir.
  const kodsuz = (sonuc.veri?.kodsuz_gun ?? 0) > 0;
  return {
    durum: "tamam",
    mesaj: `${ozet} Puantaj yazıldı; Excel ve ERP dosyaları artık kesin.${kodsuz ? " Kodsuz günler bordroda elle kontrol edilmeli." : ""}`,
    uyari: kodsuz || Boolean(sonuc.veri?.zorla),
  };
}
