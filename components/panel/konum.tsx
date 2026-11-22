"use client";

import Link from "next/link";
import { ChevronRightIcon } from "lucide-react";
import { usePathname } from "next/navigation";

// Üst bardaki konum satırı: "Atlas Trafo › Çalışanlar › Ayrıntı".
// Açık sayfa, menüdeki en uzun eşleşen yoldan bulunur.
export function Konum({ sayfalar }: { sayfalar: { yol: string; baslik: string }[] }) {
  const adres = usePathname();
  const sayfa = [...sayfalar]
    .sort((a, b) => b.yol.length - a.yol.length)
    .find((s) => (s.yol === "/" ? adres === "/" : adres === s.yol || adres.startsWith(`${s.yol}/`)));
  const ayrinti = sayfa && sayfa.yol !== "/" && adres !== sayfa.yol;

  return (
    <nav aria-label="Konum" className="flex min-w-0 items-center gap-1.5 text-sm">
      <Link href="/" className="shrink-0 text-muted-foreground transition-colors hover:text-foreground">
        Atlas Trafo
      </Link>
      {sayfa && sayfa.yol !== "/" && (
        <>
          <ChevronRightIcon className="size-3.5 shrink-0 text-muted-foreground" aria-hidden />
          {ayrinti ? (
            <Link href={sayfa.yol} className="truncate text-muted-foreground transition-colors hover:text-foreground">
              {sayfa.baslik}
            </Link>
          ) : (
            <span className="truncate font-medium" aria-current="page">{sayfa.baslik}</span>
          )}
        </>
      )}
      {ayrinti && (
        <>
          <ChevronRightIcon className="size-3.5 shrink-0 text-muted-foreground" aria-hidden />
          <span className="truncate font-medium" aria-current="page">Ayrıntı</span>
        </>
      )}
      {sayfa?.yol === "/" && (
        <>
          <ChevronRightIcon className="size-3.5 shrink-0 text-muted-foreground" aria-hidden />
          <span className="truncate font-medium" aria-current="page">Ana sayfa</span>
        </>
      )}
    </nav>
  );
}
