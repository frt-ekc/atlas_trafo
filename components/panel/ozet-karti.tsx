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
  const icerik = (
    <>
      <div className="text-sm text-muted-foreground">{baslik}</div>
      <div
        className={cn(
          "text-3xl font-semibold tabular-nums",
          ton === "dikkat" && "text-dikkat",
          ton === "iyi" && "text-iyi",
        )}
      >
        {deger}
      </div>
      {aciklama && <div className="text-sm text-muted-foreground">{aciklama}</div>}
    </>
  );

  const sinif = cn(
    "flex flex-col gap-1 rounded-xl border bg-card p-4",
    ton === "dikkat" && "border-dikkat/40",
  );

  return href ? (
    <Link href={href} className={cn(sinif, "transition-colors hover:bg-muted/50 focus-visible:ring-3 focus-visible:ring-ring/50 outline-none")}>
      {icerik}
    </Link>
  ) : (
    <div className={sinif}>{icerik}</div>
  );
}

export function OzetIzgarasi({ children }: { children: ReactNode }) {
  return <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">{children}</div>;
}
