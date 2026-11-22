import { DurumRozeti } from "@/components/liste/durum-rozeti";
import type { Ton } from "@/lib/etiketler";

// Gün kaydının durumu renkli etiketle gösterilir. Renk anlamı destekler, yazı her zaman vardır.
//   iyi    → gün kesin, sorun yok
//   dikkat → sonuç bekleniyor (amire soruldu, eksik kayıt, şüphe)
//   kötü   → çalışan aleyhine sonuç (devamsız)
//   nötr   → çalışma beklenmeyen gün (izin, tatil, plan yok)
const TON: Record<string, Ton> = {
  tamam: "iyi",
  soru_bekliyor: "dikkat",
  eksik: "dikkat",
  devamsiz_suphesi: "dikkat",
  devamsiz: "kotu",
  izinli: "notr",
  raporlu: "notr",
  tatil: "notr",
  vardiya_yok: "notr",
};

export function DurumEtiketi({ kod, children }: { kod: string | null; children: React.ReactNode }) {
  if (!kod) return <span className="text-muted-foreground">—</span>;
  return <DurumRozeti ton={TON[kod]}>{children}</DurumRozeti>;
}
