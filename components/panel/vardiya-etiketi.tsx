import { cn } from "@/lib/utils";

// Vardiyalar paletin tonlarıyla ayrılır (globals.css: .vardiya-*); renk tek başına anlam taşımasın diye etikette ad da yazar.
const VARDIYA_RENGI: Record<string, string> = {
  GUNDUZ: "vardiya-gunduz",
  V1: "vardiya-v1",
  V2: "vardiya-v2",
  V3: "vardiya-v3",
};
// Vardiya kodunun kısa adı (kod ekranda görünmez); tam ad ve saatler vardiya tanımındadır
const VARDIYA_KISA: Record<string, string> = {
  GUNDUZ: "Gündüz",
  V1: "Sabah",
  V2: "Akşam",
  V3: "Gece",
  GUNDUZ_8: "08–16",
  AKSAM_8: "16–24",
  GECE_8: "00–08",
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
