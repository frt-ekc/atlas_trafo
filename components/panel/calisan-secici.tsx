"use client";

import { Autocomplete } from "@base-ui/react/autocomplete";
import { useState } from "react";
import { cn } from "@/lib/utils";

// Çalışanın sicil numarası alanı: yazdıkça ad ya da sicile göre öneri listesi açılır, seçilen çalışanın
// sicili alana yazılır. Form yine "sicil" alanını gönderir; çalışanı sunucu sicilden bulur.
// Öneriler sayfadaki <CalisanListesi id="..."> (datalist) içinden okunur: liste bir kez sayfaya yazılır,
// aynı sayfadaki bütün pencereler onu kullanır.
type Oneri = { sicil: string; ad: string };

function listeyiOku(listeId: string): Oneri[] {
  const liste = document.getElementById(listeId);
  if (!(liste instanceof HTMLDataListElement)) return [];
  return [...liste.options].map((o) => ({ sicil: o.value, ad: o.textContent?.trim() ?? "" }));
}

const kucuk = (s: string) => s.toLocaleLowerCase("tr");

export function CalisanSecici({
  listeId,
  id,
  name = "sicil",
  required,
  autoFocus,
}: {
  listeId: string; // sayfadaki CalisanListesi'nin id'si
  id: string;
  name?: string;
  required?: boolean;
  autoFocus?: boolean;
}) {
  const [oneriler, setOneriler] = useState<Oneri[] | null>(null);
  const [deger, setDeger] = useState("");

  // Yazılan her kelime adda ya da sicilde geçmeli; en fazla 50 öneri
  const kelimeler = kucuk(deger).split(/\s+/).filter(Boolean);
  const suzulmus = (oneriler ?? [])
    .filter((o) => kelimeler.every((k) => kucuk(`${o.sicil} ${o.ad}`).includes(k)))
    .slice(0, 50);

  return (
    <Autocomplete.Root
      name={name}
      required={required}
      value={deger}
      onValueChange={(v) => setDeger(v)}
      onOpenChange={(acik) => {
        if (acik && oneriler === null) setOneriler(listeyiOku(listeId));
      }}
      items={oneriler ?? []}
      filteredItems={suzulmus}
      itemToStringValue={(o: Oneri) => o.sicil}
    >
      <Autocomplete.Input
        id={id}
        autoFocus={autoFocus}
        autoComplete="off"
        placeholder="Sicil ya da ad yazın"
        className={cn(
          "h-9 w-full min-w-0 rounded-lg border border-input bg-transparent px-2.5 py-1 text-base outline-none transition-colors md:text-sm",
          "placeholder:text-muted-foreground focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/40 dark:bg-input/30",
        )}
      />
      <Autocomplete.Portal>
        <Autocomplete.Positioner sideOffset={6} className="z-[60] outline-none">
          <Autocomplete.Popup className="max-h-[min(18rem,var(--available-height))] w-[var(--anchor-width)] overflow-y-auto rounded-xl border bg-popover p-1 text-popover-foreground shadow-lg shadow-black/10 outline-none empty:hidden">
            <Autocomplete.Empty className="px-2.5 py-2 text-sm text-muted-foreground empty:hidden">
              {deger ? "Eşleşen çalışan yok." : null}
            </Autocomplete.Empty>
            <Autocomplete.List>
              {(o: Oneri) => (
                <Autocomplete.Item
                  key={o.sicil}
                  value={o}
                  className="flex cursor-default items-baseline gap-2.5 rounded-lg px-2.5 py-1.5 text-sm outline-none select-none data-[highlighted]:bg-accent data-[highlighted]:text-accent-foreground"
                >
                  <span className="font-mono text-xs text-muted-foreground tabular-nums">{o.sicil}</span>
                  <span className="truncate">{o.ad}</span>
                </Autocomplete.Item>
              )}
            </Autocomplete.List>
          </Autocomplete.Popup>
        </Autocomplete.Positioner>
      </Autocomplete.Portal>
    </Autocomplete.Root>
  );
}
