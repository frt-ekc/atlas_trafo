import type { ReactNode } from "react";
import { cn } from "@/lib/utils";

// Listelerdeki durum rozeti. Renk anlamı destekler; anlamı her zaman yazı taşır.
//   iyi    → tamamlandı, sorun yok
//   dikkat → karar ya da işlem bekliyor
//   kotu   → çalışan aleyhine sonuç, ret, kayıp
//   notr   → bilgi, pasif, iptal
export type Ton = "iyi" | "dikkat" | "kotu" | "notr";

export function DurumRozeti({ ton = "notr", children, className }: { ton?: Ton; children: ReactNode; className?: string }) {
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-xs font-medium whitespace-nowrap",
        ton === "iyi" && "bg-iyi-zemin text-iyi",
        ton === "dikkat" && "bg-dikkat-zemin text-dikkat",
        ton === "kotu" && "bg-kotu-zemin text-kotu",
        ton === "notr" && "bg-secondary text-muted-foreground",
        className,
      )}
    >
      <span className="size-1.5 rounded-full bg-current" aria-hidden />
      {children}
    </span>
  );
}
