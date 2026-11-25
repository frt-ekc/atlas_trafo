import Link from "next/link";
import { cn } from "@/lib/utils";

// sayiAciklama: sayının ne olduğu (ör. "karar bekliyor"); fareyle üzerine gelince ve ekran okuyucuda söylenir
export type Sekme = { ad: string; adres: string; sayi?: number; sayiAciklama?: string; aktif: boolean };

// Liste üstündeki sekmeler (ör. Yeni / Görülenler). Her sekme bir bağlantıdır; seçili olan
// yalnızca renkle değil, kalın yazı, alt çizgi ve aria-current ile de belli olur.
// Dar ekranda sığmayan sekme alt satıra iner; hiçbir sekme ekran dışında kalmaz.
export function Sekmeler({ sekmeler, etiket }: { sekmeler: Sekme[]; etiket: string }) {
  return (
    <nav aria-label={etiket} className="flex flex-wrap gap-x-1 shadow-[inset_0_-1px_0_var(--border)]">
      {sekmeler.map((s) => (
        <Link
          key={s.ad}
          href={s.adres}
          scroll={false}
          aria-current={s.aktif ? "page" : undefined}
          className={cn(
            "relative inline-flex shrink-0 items-center gap-2 whitespace-nowrap rounded-t-lg border-b-2 px-3 py-2 text-sm outline-none transition-colors",
            "focus-visible:ring-2 focus-visible:ring-ring",
            s.aktif
              ? "border-vurgu font-semibold text-foreground"
              : "border-transparent text-muted-foreground hover:text-foreground",
          )}
        >
          {s.ad}
          {s.sayi !== undefined && (
            <span
              title={s.sayiAciklama ? `${s.sayi} ${s.sayiAciklama}` : undefined}
              className="rounded-full bg-secondary px-2 py-0.5 text-xs font-medium tabular-nums text-secondary-foreground"
            >
              {s.sayi}
              {s.sayiAciklama && <span className="sr-only"> {s.sayiAciklama}</span>}
            </span>
          )}
        </Link>
      ))}
    </nav>
  );
}
