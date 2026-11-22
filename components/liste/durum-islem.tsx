import type { ReactNode } from "react";
import { cn } from "@/lib/utils";

// Tablonun son sütunu: durum rozeti ve işlemler tek, dar bir sütunda.
// Orta genişlikte sağa sabitlendiğinde satırdaki metnin üstünü az kapatır.
// İşlemler: ana düğme + IslemMenusu (ikincil işlem sayısına göre yan düğme ya da menü).
// 1280px ve üstünde düğmeler yan yana durur; daha dar ekranda sığmazsa alt alta dizilir, menüye dönüşmez.
// yatay: durum ve düğmeler aynı satırda (satır sayısı çok olan tablolarda satırlar kısa kalsın diye)
export function DurumIslem({ durum, children, yatay }: { durum?: ReactNode; children?: ReactNode; yatay?: boolean }) {
  return (
    <div className={cn("flex gap-1.5", yatay ? "flex-wrap items-center xl:flex-nowrap" : "flex-col items-start")}>
      {durum}
      {children && <div className="flex flex-wrap items-center gap-1.5 xl:flex-nowrap">{children}</div>}
    </div>
  );
}
