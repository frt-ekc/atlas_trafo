import type { ReactNode } from "react";

// Hata ve "bulunamadı" ekranlarının ortak düzeni: ortada sade bir kart, büyük simge, kısa açıklama.
export function BilgiEkrani({
  simge,
  ust,
  baslik,
  aciklama,
  children,
}: {
  simge: ReactNode;
  ust: string;
  baslik: string;
  aciklama: ReactNode;
  children?: ReactNode;
}) {
  return (
    <main className="flex flex-1 items-center justify-center px-4 py-16">
      <div className="flex w-full max-w-md flex-col items-center gap-5 rounded-2xl border bg-card p-8 text-center shadow-sm">
        <div className="grid size-14 place-items-center rounded-2xl text-white" style={{ background: "var(--kenar-zemin)" }}>
          {simge}
        </div>
        <div className="flex flex-col gap-2">
          <p className="text-xs font-semibold tracking-[0.14em] text-muted-foreground uppercase">{ust}</p>
          <h1 className="text-2xl font-semibold">{baslik}</h1>
          <div className="text-sm text-muted-foreground">{aciklama}</div>
        </div>
        {children && <div className="flex flex-wrap justify-center gap-2">{children}</div>}
      </div>
    </main>
  );
}
