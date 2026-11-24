import "server-only";
import type { sunucuIstemcisi } from "@/lib/supabase/server";

type Istemci = Awaited<ReturnType<typeof sunucuIstemcisi>>;

// Geçici kartın iade süresi (ayar: gecici_kart_iade_saat). Güvenlik rolü ayar tablosunu
// okuyamaz; değer ayar_al fonksiyonuyla alınır.
export async function geciciKartIadeSaati(supabase: Istemci): Promise<number> {
  const { data, error } = await supabase.rpc("ayar_al", { p_anahtar: "gecici_kart_iade_saat" });
  if (error) throw new Error(`Geçici kart iade süresi okunamadı: ${error.message}`);
  return Number(data);
}
