import type { ReactNode } from "react";
import type { Ton } from "@/lib/etiketler";
import { cn } from "@/lib/utils";

// Listelerdeki durum rozeti. Renk anlamı destekler; anlamı her zaman yazı taşır.
// Tonların anlamı: lib/etiketler.ts (Ton)

export function DurumRozeti({ ton = "notr", children, className }: { ton?: Ton; children: ReactNode; className?: string }) {
  return (
    <span
      className={cn(
        // İnce, renkle uyumlu bir çerçeve ve hafif ışıyan nokta: sade ama canlı
        "inline-flex items-center gap-1.5 rounded-full px-2 py-0.5 text-xs font-semibold tracking-[0.01em] whitespace-nowrap",
        "ring-1 ring-inset ring-[color-mix(in_oklab,currentColor_22%,transparent)]",
        ton === "iyi" && "bg-iyi-zemin text-iyi",
        ton === "dikkat" && "bg-dikkat-zemin text-dikkat",
        ton === "kotu" && "bg-kotu-zemin text-kotu",
        ton === "notr" && "bg-secondary text-muted-foreground",
        className,
      )}
    >
      <span className="size-1.5 rounded-full bg-current shadow-[0_0_0_3px_color-mix(in_oklab,currentColor_16%,transparent)]" aria-hidden />
      {children}
    </span>
  );
}
