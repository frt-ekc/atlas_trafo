"use client";

import { Popover } from "@base-ui/react/popover";
import { ChevronDownIcon } from "lucide-react";
import { Children, cloneElement, isValidElement, useState, type ReactElement, type ReactNode } from "react";
import { Button } from "@/components/ui/button";

type DugmeTuru = "default" | "outline" | "secondary" | "ghost" | "destructive";
type IslemOgesi = ReactElement<{ dugmeTuru?: DugmeTuru }>;

// Bir satırın ikincil işlemleri (İptal et, Reddet, İncelemeye al, Arıza değil, Düzenle…).
// Kural tek yerde, burada uygulanır; ekranlar yalnızca ikincil işlemleri içine koyar:
//   0 işlem  → hiçbir şey çizilmez (satırda yalnızca ana düğme kalır)
//   1 işlem  → menü yok; ana düğmenin yanında çerçeveli (outline) ikinci düğme
//   2+ işlem → "İşlemler ▾" menüsü
// İşlemin kendi onay penceresi (ör. İptal et → gerekçe sorar) olduğu gibi kalır; burada yalnızca görünüm değişir.
export function IslemMenusu({ children, etiket = "İşlemler" }: { children: ReactNode; etiket?: string }) {
  const [acik, setAcik] = useState(false);
  // Koşulu tutmayan işlemler (false / null) sayılmaz
  const islemler = Children.toArray(children).filter(isValidElement) as IslemOgesi[];

  if (islemler.length === 0) return null;
  if (islemler.length === 1) return cloneElement(islemler[0], { dugmeTuru: "outline" });

  return (
    <Popover.Root open={acik} onOpenChange={setAcik}>
      <Popover.Trigger render={<Button size="sm" variant="outline" />}>
        {etiket}
        <ChevronDownIcon aria-hidden />
      </Popover.Trigger>
      {/* keepMounted: menü kapansa da içerik silinmez, menüden açılan onay penceresi açık kalır */}
      <Popover.Portal keepMounted>
        <Popover.Positioner side="bottom" align="end" sideOffset={4} className="z-50">
          <Popover.Popup
            aria-label={etiket}
            // Bir işleme basılınca menü kapanır (pencere açılıyorsa pencere açık kalır)
            onClickCapture={(e) => {
              if ((e.target as HTMLElement).closest("button")) setAcik(false);
            }}
            className="flex min-w-44 flex-col gap-1 rounded-lg border bg-popover p-1.5 text-popover-foreground shadow-md outline-none [&_button]:w-full [&_button]:justify-start [&_form]:w-full"
          >
            {islemler.map((islem) => cloneElement(islem, { dugmeTuru: "ghost" }))}
          </Popover.Popup>
        </Popover.Positioner>
      </Popover.Portal>
    </Popover.Root>
  );
}
