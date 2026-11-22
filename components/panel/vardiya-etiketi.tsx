import { cn } from "@/lib/utils";

// Vardiyalar paletin tonlarıyla ayrılır (globals.css: .vardiya-*); renk tek başına anlam taşımasın diye etikette kod da yazar.
const VARDIYA_RENGI: Record<string, string> = {
  GUNDUZ: "vardiya-gunduz",
  V1: "vardiya-v1",
  V2: "vardiya-v2",
  V3: "vardiya-v3",
};
// Kodun ekranda görünen kısa adı (V1, V2, V3 zaten kısa); tam adı vardiya tablosundadır
const VARDIYA_KISA: Record<string, string> = {
  GUNDUZ: "Gündüz",
  GUNDUZ_8: "Gündüz-8",
  AKSAM_8: "Akşam-8",
  GECE_8: "Gece-8",
  BEYAZ: "Beyaz yaka",
  ESNEK: "Esnek",
};

export function vardiyaAdi(kod: string): string {
  return VARDIYA_KISA[kod] ?? kod;
}

export function VardiyaEtiketi({ kod, ustuCizili = false }: { kod: string; ustuCizili?: boolean }) {
  return (
    <span
      className={cn(
        "inline-flex min-w-14 justify-center rounded px-1.5 py-0.5 text-xs font-semibold whitespace-nowrap",
        VARDIYA_RENGI[kod] ?? "bg-secondary text-secondary-foreground",
        ustuCizili && "line-through opacity-60",
      )}
    >
      {vardiyaAdi(kod)}
    </span>
  );
}
