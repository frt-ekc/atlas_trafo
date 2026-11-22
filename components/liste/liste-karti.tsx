import type { ReactNode } from "react";
import { cn } from "@/lib/utils";

type Ozellikler = {
  baslik: ReactNode; // ör. uyarı türü
  kisi?: ReactNode; // ilgili kişi(ler) ve sicil
  zaman?: ReactNode; // sağ üstte
  children: ReactNode; // mesajın tamamı (kesilmez, satır içinde sarar)
  alt?: ReactNode; // sol altta küçük bilgi (ör. kim gördü)
  eylemler?: ReactNode; // sağ altta düğmeler
  secim?: ReactNode; // solda onay kutusu (toplu işlem)
  vurgu?: "karar" | "bilgi"; // "karar": solda kalın şerit
  yeni?: boolean; // başta küçük nokta + kalın başlık
  soluk?: boolean; // görülmüş / kapanmış kayıt
};

// Tablo yerine kart olarak gösterilen liste satırı. Uzun metin kesilmez, kartın içinde sarar.
export function ListeKarti({ baslik, kisi, zaman, children, alt, eylemler, secim, vurgu = "bilgi", yeni, soluk }: Ozellikler) {
  return (
    <article
      className={cn(
        "flex gap-3 rounded-xl border bg-card transition-colors",
        vurgu === "karar" ? "border-l-4 border-l-dikkat p-4" : "px-4 py-3",
        soluk && "bg-card/50 text-muted-foreground",
      )}
    >
      {secim && <div className="pt-0.5">{secim}</div>}
      <div className="flex min-w-0 flex-1 flex-col gap-2">
        <header className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
          <h3 className={cn("flex items-center gap-2 text-sm", yeni ? "font-semibold text-foreground" : "font-medium")}>
            {yeni && (
              <>
                <span className="size-2 shrink-0 rounded-full bg-vurgu" aria-hidden />
                <span className="sr-only">Yeni:</span>
              </>
            )}
            {baslik}
          </h3>
          {zaman && <div className="text-xs text-muted-foreground">{zaman}</div>}
        </header>
        {kisi && <div className="text-sm">{kisi}</div>}
        {/* Mesaj solda sarar; düğmeler sağ altta durur, yer yoksa alt satıra iner */}
        <div className="flex flex-wrap items-end justify-between gap-x-6 gap-y-2">
          <p className="min-w-[min(100%,20rem)] flex-1 text-sm leading-relaxed break-words">{children}</p>
          {eylemler && <div className="ml-auto flex flex-wrap items-center gap-2">{eylemler}</div>}
        </div>
        {alt && <footer className="text-xs text-muted-foreground">{alt}</footer>}
      </div>
    </article>
  );
}
