"use client";

import { ChevronRightIcon } from "lucide-react";
import { usePathname } from "next/navigation";
import { useId, useState, type ReactNode } from "react";
import { cn } from "@/lib/utils";

// Kenar çubuğunda açılır-kapanır menü grubu (ör. "Planlama" → İzinler, Vardiya planı, Fazla mesai).
// Açık sayfa bu gruptaysa grup açık başlar ve o sayfaya gidilince kendiliğinden açılır.
// Kapalıyken alt sayfalardaki bekleyen işlerin toplamı başlıkta görünür.
export function MenuGrubu({
  baslik,
  yollar,
  sayi,
  children,
}: {
  baslik: string;
  yollar: string[]; // gruptaki sayfaların adresleri (açık sayfa bu grupta mı?)
  sayi?: number; // alt sayfalardaki bekleyen işlerin toplamı
  children: ReactNode;
}) {
  const adres = usePathname();
  const icinde = yollar.some((y) => adres === y || adres.startsWith(`${y}/`));
  const [acik, setAcik] = useState(icinde);
  const [oncekiIcinde, setOncekiIcinde] = useState(icinde);
  const id = useId();

  // Başka bir yoldan (arama, bağlantı) bu gruptaki sayfaya gelinince grup açılır.
  // Effect yerine çizim sırasında: React'in önerdiği "önceki değere göre durumu ayarla" kalıbı.
  if (icinde !== oncekiIcinde) {
    setOncekiIcinde(icinde);
    if (icinde) setAcik(true);
  }

  return (
    <div className="flex flex-col">
      <button
        type="button"
        onClick={() => setAcik((a) => !a)}
        aria-expanded={acik}
        aria-controls={id}
        className={cn(
          "flex items-center gap-2 rounded-lg px-3 py-2 text-left md:py-1.5 text-[0.8125rem] font-semibold transition-colors outline-none",
          "text-sidebar-foreground/75 hover:bg-sidebar-foreground/[0.07] hover:text-sidebar-foreground",
          "focus-visible:ring-2 focus-visible:ring-sidebar-ring",
          icinde && "text-sidebar-foreground",
        )}
      >
        <ChevronRightIcon className={cn("size-3.5 shrink-0 transition-transform", acik && "rotate-90")} aria-hidden />
        <span className="flex-1">{baslik}</span>
        {!acik && sayi ? (
          <span className="rounded-full bg-sidebar-primary/15 px-2 py-0.5 text-xs font-medium tabular-nums text-sidebar-primary" aria-label={`${sayi} bekleyen`}>
            {sayi}
          </span>
        ) : null}
      </button>
      <div id={id} hidden={!acik} className="mt-0.5 ml-[1.15rem] flex flex-col gap-0.5 border-l border-sidebar-border pl-2">
        {children}
      </div>
    </div>
  );
}
