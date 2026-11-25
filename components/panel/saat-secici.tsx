"use client";

import { Popover } from "@base-ui/react/popover";
import { ClockIcon } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { cn } from "@/lib/utils";

// Sistemin saat alanı: tarayıcının saat kutusu yerine takvimle aynı tarzda.
// Saat elle yazılabilir (yazarken iki nokta kendiliğinden eklenir: "0825" → "08:25")
// ya da saat simgesine basınca açılan iki sütundan (saat / dakika) seçilir.
// Form değeri tarayıcının saat kutusuyla aynı biçimdedir: "ss:dd".

const SAATLER = Array.from({ length: 24 }, (_, i) => String(i).padStart(2, "0"));
const DAKIKALAR = Array.from({ length: 60 }, (_, i) => String(i).padStart(2, "0"));
const DESEN = "([01][0-9]|2[0-3]):[0-5][0-9]";

// Yazılanı "ss:dd" biçimine yaklaştırır: yalnızca rakam, en çok 4 hane
function bicimle(girdi: string): string {
  const r = girdi.replace(/\D/g, "").slice(0, 4);
  return r.length > 2 ? `${r.slice(0, 2)}:${r.slice(2)}` : r;
}

export function SaatSecici({
  id,
  name,
  defaultValue = "",
  value,
  onChange,
  required,
  className,
  "aria-label": ariaLabel,
}: {
  id?: string;
  name?: string;
  defaultValue?: string;
  value?: string;
  onChange?: (deger: string) => void;
  required?: boolean;
  className?: string;
  "aria-label"?: string;
}) {
  const kontrollu = value !== undefined;
  const [ic, setIc] = useState(defaultValue.slice(0, 5));
  const [onceki, setOnceki] = useState(defaultValue);
  if (!kontrollu && defaultValue !== onceki) {
    setOnceki(defaultValue);
    setIc(defaultValue.slice(0, 5));
  }
  const deger = kontrollu ? value : ic;
  const degistir = (v: string) => {
    if (!kontrollu) setIc(v);
    onChange?.(v);
  };

  const [acik, setAcik] = useState(false);
  const panel = useRef<HTMLDivElement>(null);
  const [ss, dd] = /^\d{2}:\d{2}$/.test(deger) ? deger.split(":") : ["", ""];

  // Açılınca seçili saat ve dakika sütunun ortasına kayar (yalnızca DOM kaydırması)
  useEffect(() => {
    if (!acik) return;
    const t = setTimeout(() => {
      panel.current?.querySelectorAll<HTMLElement>("[data-secili=true]").forEach((e) => e.scrollIntoView({ block: "center" }));
    }, 0);
    return () => clearTimeout(t);
  }, [acik]);

  const sutun = (ogeler: string[], secili: string, sec: (v: string) => void, etiket: string) => (
    <div role="listbox" aria-label={etiket} className="flex max-h-56 w-14 flex-col gap-0.5 overflow-y-auto [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
      {ogeler.map((o) => (
        <button
          key={o}
          type="button"
          role="option"
          aria-selected={o === secili}
          data-secili={o === secili}
          onClick={() => sec(o)}
          className={cn(
            "rounded-md py-1 text-center text-[0.8125rem] tabular-nums outline-none transition-colors",
            "hover:bg-accent hover:text-accent-foreground focus-visible:ring-2 focus-visible:ring-ring",
            o === secili && "bg-primary bg-[image:var(--dugme-gecis)] font-medium text-primary-foreground hover:text-primary-foreground",
          )}
        >
          {o}
        </button>
      ))}
    </div>
  );

  return (
    <div
      className={cn(
        "flex h-9 min-w-0 items-center rounded-lg border border-input bg-card pr-1 transition-colors focus-within:border-ring focus-within:ring-3 focus-within:ring-ring/40 dark:bg-input/30",
        className,
      )}
    >
      <input
        id={id}
        name={name}
        value={deger}
        onChange={(e) => degistir(bicimle(e.target.value))}
        required={required}
        pattern={DESEN}
        title="Saat ss:dd biçiminde olmalı (ör. 08:30)"
        inputMode="numeric"
        autoComplete="off"
        placeholder="ss:dd"
        aria-label={ariaLabel}
        className="h-full w-full min-w-0 bg-transparent px-2.5 text-base tabular-nums outline-none placeholder:text-muted-foreground md:text-sm"
      />
      <Popover.Root open={acik} onOpenChange={setAcik}>
        <Popover.Trigger
          aria-label="Saat seç"
          className="grid size-7 shrink-0 place-items-center rounded-md text-muted-foreground outline-none hover:bg-accent hover:text-accent-foreground focus-visible:ring-2 focus-visible:ring-ring"
        >
          <ClockIcon className="size-4" aria-hidden />
        </Popover.Trigger>
        <Popover.Portal>
          <Popover.Positioner sideOffset={8} align="end" className="z-[60] outline-none">
            <Popover.Popup
              ref={panel}
              aria-label="Saat seç"
              className="flex gap-1 rounded-xl border bg-popover p-2 text-popover-foreground shadow-lg shadow-black/10 outline-none"
            >
              {sutun(SAATLER, ss, (h) => degistir(`${h}:${dd || "00"}`), "Saat")}
              <div className="w-px self-stretch bg-border" aria-hidden />
              {sutun(DAKIKALAR, dd, (m) => {
                degistir(`${ss || "00"}:${m}`);
                setAcik(false);
              }, "Dakika")}
            </Popover.Popup>
          </Popover.Positioner>
        </Popover.Portal>
      </Popover.Root>
    </div>
  );
}
