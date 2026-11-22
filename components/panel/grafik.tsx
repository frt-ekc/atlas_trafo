import Link from "next/link";
import type { ReactNode } from "react";
import { cn } from "@/lib/utils";

// Sade çubuk grafikler: kütüphane yok, düz HTML. Her değer yazıyla da gösterilir;
// renk ayırt edemeyen ya da ekran okuyucu kullanan biri de grafiği okuyabilir.

const yuzde = (pay: number, payda: number) => (payda > 0 ? Math.round((pay / payda) * 100) : 0);

export function GrafikKarti({ baslik, aciklama, children }: { baslik: string; aciklama?: ReactNode; children: ReactNode }) {
  return (
    <section className="flex flex-col gap-4 rounded-xl border bg-card p-5">
      <div className="flex flex-col gap-1">
        <h2 className="text-base font-semibold">{baslik}</h2>
        {aciklama && <p className="text-sm text-muted-foreground">{aciklama}</p>}
      </div>
      {children}
    </section>
  );
}

// ---------------------------------------------------------------------
// Parçalı tek çubuk: bir bütünün nasıl bölündüğü (ör. düzeltmeleri kim yaptı)
// ---------------------------------------------------------------------
export type Dilim = { etiket: string; deger: number; renk: string; desenli?: boolean; href?: string };

export function ParcaliCubuk({ dilimler, birim }: { dilimler: Dilim[]; birim: string }) {
  const toplam = dilimler.reduce((t, d) => t + d.deger, 0);
  const gorunen = dilimler.filter((d) => d.deger > 0);

  return (
    <div className="flex flex-col gap-4">
      <div className="flex h-3.5 w-full overflow-hidden rounded-full bg-muted" role="img" aria-label={dilimler.map((d) => `${d.etiket}: ${d.deger}`).join(", ")}>
        {gorunen.map((d) => (
          <div
            key={d.etiket}
            className={cn("h-full border-r-2 border-card last:border-r-0", d.desenli && "desenli")}
            style={{ width: `${(d.deger / toplam) * 100}%`, backgroundColor: d.renk }}
          />
        ))}
      </div>

      <ul className="grid gap-x-6 gap-y-2.5 sm:grid-cols-2">
        {dilimler.map((d) => {
          const icerik = (
            <>
              <span className={cn("size-3 shrink-0 rounded-sm", d.desenli && "desenli")} style={{ backgroundColor: d.renk }} aria-hidden />
              <span className="flex-1 text-sm">{d.etiket}</span>
              <span className="text-sm font-semibold tabular-nums">{d.deger}</span>
              <span className="w-10 text-right text-xs text-muted-foreground tabular-nums">%{yuzde(d.deger, toplam)}</span>
            </>
          );
          return (
            <li key={d.etiket}>
              {d.href ? (
                <Link href={d.href} className="-mx-2 flex items-center gap-2.5 rounded-md px-2 py-1 transition-colors hover:bg-muted">
                  {icerik}
                </Link>
              ) : (
                <div className="flex items-center gap-2.5 py-1">{icerik}</div>
              )}
            </li>
          );
        })}
      </ul>
      <p className="text-xs text-muted-foreground">
        Toplam {toplam} {birim}
      </p>
    </div>
  );
}
