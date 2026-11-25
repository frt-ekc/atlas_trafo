import Link from "next/link";
import type { ReactNode } from "react";
import { cn } from "@/lib/utils";

type Ton = "notr" | "dikkat" | "iyi";

// Ana sayfadaki sayı kartı. Bağlantı verilirse kartın tamamı ilgili ekrana gider.
export function OzetKarti({
  baslik,
  deger,
  aciklama,
  href,
  ton = "notr",
}: {
  baslik: string;
  deger: ReactNode;
  aciklama?: ReactNode;
  href?: string;
  ton?: Ton;
}) {
  // Sade, kısa kart: solda başlık ve tek satırlık açıklama, sağda sayı. Açıklama sığmazsa
  // kesilir; tamamı fareyle üzerine gelince ve ekran okuyucuda okunur.
  // Uzun değer (ör. "12.416 sa 41 dk") başlığı sıkıştırmasın diye başlığın altına iner.
  const uzun = typeof deger === "string" && deger.length > 7;
  // Izgara: kısa değerde sayı sağda iki satırı kaplar; uzun değerde başlık, sayı ve açıklama alt alta.
  const icerik = (
    <>
      <div className="min-w-0 truncate text-[0.8125rem] font-medium">{baslik}</div>
      <div
        className={cn(
          "font-semibold whitespace-nowrap tabular-nums",
          uzun ? "text-lg" : "col-start-2 row-span-2 row-start-1 self-center text-xl",
          ton === "dikkat" && "text-dikkat",
          ton === "iyi" && "text-iyi",
        )}
      >
        {deger}
      </div>
      {aciklama && (
        <div className="min-w-0 truncate text-xs text-muted-foreground" title={typeof aciklama === "string" ? aciklama : undefined}>
          {aciklama}
        </div>
      )}
    </>
  );

  const sinif = cn(
    "grid items-center gap-x-3 gap-y-0.5 rounded-lg border bg-card px-3.5 py-2.5",
    uzun ? "grid-cols-1" : "grid-cols-[minmax(0,1fr)_auto]",
    ton === "dikkat" && "border-l-[3px] border-l-dikkat",
  );

  return href ? (
    <Link href={href} className={cn(sinif, "transition-[transform,box-shadow,background-color] hover:-translate-y-px hover:bg-accent/40 hover:shadow-md focus-visible:ring-3 focus-visible:ring-ring/50 outline-none")}>
      {icerik}
    </Link>
  ) : (
    <div className={sinif}>{icerik}</div>
  );
}

export function OzetIzgarasi({ children }: { children: ReactNode }) {
  return <div className="grid gap-2.5 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">{children}</div>;
}
