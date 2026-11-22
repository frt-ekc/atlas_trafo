import type { ReactNode } from "react";
import type { Ton } from "@/lib/etiketler";
import { cn } from "@/lib/utils";

// Listelerdeki durum rozeti. Renk anlamı destekler; anlamı her zaman yazı taşır.
// Tonların anlamı: lib/etiketler.ts (Ton)

export function DurumRozeti({ ton = "notr", children, className }: { ton?: Ton; children: ReactNode; className?: string }) {
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-[0.8125rem] font-medium whitespace-nowrap",
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
