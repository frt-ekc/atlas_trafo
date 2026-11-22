import { cn } from "@/lib/utils";

// Gün kaydının durumu renkli etiketle gösterilir. Renk anlamı destekler, yazı her zaman vardır.
//   iyi    → gün kesin, sorun yok
//   dikkat → sonuç bekleniyor (amire soruldu, eksik kayıt, şüphe)
//   kötü   → çalışan aleyhine sonuç (devamsız)
//   nötr   → çalışma beklenmeyen gün (izin, tatil, plan yok)
const TON: Record<string, "iyi" | "dikkat" | "kotu" | "notr"> = {
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
  const ton = TON[kod] ?? "notr";
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-xs font-medium whitespace-nowrap",
        ton === "iyi" && "bg-iyi-zemin text-iyi",
        ton === "dikkat" && "bg-dikkat-zemin text-dikkat",
        ton === "kotu" && "bg-kotu-zemin text-kotu",
        ton === "notr" && "bg-secondary text-muted-foreground",
      )}
    >
      <span className="size-1.5 rounded-full bg-current" aria-hidden />
      {children}
    </span>
  );
}
