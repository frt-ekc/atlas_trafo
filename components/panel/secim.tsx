"use client";

import { Select } from "@base-ui/react/select";
import { CheckIcon, ChevronDownIcon } from "lucide-react";
import { Children, isValidElement, useRef, useState, type ReactElement, type ReactNode } from "react";
import { cn } from "@/lib/utils";

// Sistemin bütün açılır listeleri. Tarayıcının kendi listesi (işletim sisteminin mavi seçim çubuğu)
// biçimlendirilemediği için listeyi biz çiziyoruz; çağıran sayfalar yine <option> / <optgroup> yazar.
// Form için seçilen değer, verilen "name" ile gizli bir alana yazılır (FormData ve GET süzgeçleri aynen çalışır).
// Süzgeç formunun (SuzgecFormu, data-suzgec) içindeyse seçim yapılınca süzgeç kendiliğinden uygulanır.

type Oge = { value: string; label: string; disabled: boolean };
type Grup = { baslik?: string; ogeler: Oge[] };

type Ozellikler = {
  id?: string;
  name?: string;
  defaultValue?: string | number;
  value?: string;
  onChange?: (olay: { target: { value: string } }) => void; // <select> ile aynı biçim: e.target.value
  required?: boolean;
  disabled?: boolean;
  className?: string;
  "aria-label"?: string;
  children: ReactNode;
};

type SecenekOzellikleri = { value?: string | number; disabled?: boolean; children?: ReactNode; label?: string };

// <option> içindeki yazıyı düz metne çevirir (ör. {ad} (08:00–17:00) gibi parçalı içerik)
function metin(dugum: ReactNode): string {
  if (dugum === null || dugum === undefined || typeof dugum === "boolean") return "";
  if (typeof dugum === "string" || typeof dugum === "number") return String(dugum);
  if (Array.isArray(dugum)) return dugum.map(metin).join("");
  if (isValidElement<{ children?: ReactNode }>(dugum)) return metin(dugum.props.children);
  return "";
}

// <option> ve <optgroup> çocuklarını gruplu öğe listesine çevirir
function gruplar(children: ReactNode): Grup[] {
  const sonuc: Grup[] = [{ ogeler: [] }];
  const oge = (e: ReactElement<SecenekOzellikleri>): Oge => ({
    value: String(e.props.value ?? metin(e.props.children)),
    label: metin(e.props.children),
    disabled: Boolean(e.props.disabled),
  });
  for (const c of Children.toArray(children)) {
    if (!isValidElement<SecenekOzellikleri>(c)) continue;
    if (c.type === "option") sonuc[sonuc.length - 1].ogeler.push(oge(c));
    else if (c.type === "optgroup") {
      const ic = Children.toArray(c.props.children).filter(
        (x): x is ReactElement<SecenekOzellikleri> => isValidElement(x) && x.type === "option",
      );
      sonuc.push({ baslik: c.props.label, ogeler: ic.map(oge) }, { ogeler: [] });
    }
  }
  return sonuc.filter((g) => g.ogeler.length > 0);
}

export function Secim({ id, name, defaultValue, value, onChange, required, disabled, className, children, ...rest }: Ozellikler) {
  const kontrollu = value !== undefined;
  const baslangic = String(value ?? defaultValue ?? "");
  const [ic, setIc] = useState(baslangic);
  // Süzgeç sayfası yeni adresle yeniden çizilince (sekme, geri tuşu, özet bağlantısı) sunucunun değeri gelir
  const [oncekiVarsayilan, setOncekiVarsayilan] = useState(defaultValue);
  if (!kontrollu && defaultValue !== oncekiVarsayilan) {
    setOncekiVarsayilan(defaultValue);
    setIc(String(defaultValue ?? ""));
  }
  const secili = kontrollu ? value : ic;
  const tetik = useRef<HTMLButtonElement>(null);

  const liste = gruplar(children);
  const tumu = liste.flatMap((g) => g.ogeler);
  // Boş değerli, seçilemeyen ilk seçenek ("Seçin") yer tutucudur; listede görünmez
  const yerTutucu = tumu.find((o) => o.value === "" && o.disabled);
  const gorunen = liste
    .map((g) => ({ ...g, ogeler: g.ogeler.filter((o) => o !== yerTutucu) }))
    .filter((g) => g.ogeler.length > 0);
  const etiketler = Object.fromEntries(tumu.map((o) => [o.value, o.label]));
  const kokDeger = secili === "" && yerTutucu ? null : secili;
  // Tarayıcının listesi gibi: düğme en uzun seçenek kadar geniş (ekrandan taşmaz, className genişliği önceliklidir)
  const enUzun = Math.min(Math.max(...tumu.map((o) => o.label.length), 6), 34);

  return (
    <Select.Root
      name={name}
      required={required}
      disabled={disabled}
      value={kokDeger}
      items={etiketler}
      onValueChange={(yeni) => {
        const v = yeni ?? "";
        if (!kontrollu) setIc(v);
        onChange?.({ target: { value: v } });
        // Süzgeç formundaysa seçim hemen uygulanır (gizli alan güncellendikten sonra)
        const form = tetik.current?.closest("form");
        if (form?.hasAttribute("data-suzgec")) setTimeout(() => form.requestSubmit(), 0);
      }}
    >
      <Select.Trigger
        ref={tetik}
        id={id}
        aria-label={rest["aria-label"]}
        style={{ minWidth: `min(100%, calc(${enUzun}ch + 2.75rem))` }}
        className={cn(
          "flex h-9 min-w-0 items-center justify-between gap-2 rounded-lg border border-input bg-card px-2.5 text-left text-sm outline-none transition-colors",
          "hover:border-ring/60 focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/40 data-[popup-open]:border-ring",
          "disabled:cursor-not-allowed disabled:opacity-50 dark:bg-input/30",
          className,
        )}
      >
        <Select.Value className="truncate data-[placeholder]:text-muted-foreground">
          {(v: string | null) => (v === null || v === undefined ? (yerTutucu?.label ?? "") : (etiketler[v] ?? v))}
        </Select.Value>
        <Select.Icon className="shrink-0 text-muted-foreground">
          <ChevronDownIcon className="size-4" aria-hidden />
        </Select.Icon>
      </Select.Trigger>
      <Select.Portal>
        <Select.Positioner sideOffset={6} alignItemWithTrigger={false} className="z-[60] outline-none">
          <Select.Popup
            className={cn(
              "max-h-[min(20rem,var(--available-height))] min-w-[var(--anchor-width)] overflow-y-auto rounded-xl border bg-popover p-1 text-popover-foreground shadow-lg shadow-black/10 outline-none",
              "origin-[var(--transform-origin)] transition-[transform,opacity] data-[ending-style]:scale-95 data-[ending-style]:opacity-0 data-[starting-style]:scale-95 data-[starting-style]:opacity-0",
            )}
          >
            {gorunen.map((g, gi) => {
              const ogeler = g.ogeler.map((o) => (
                <Select.Item
                  key={o.value}
                  value={o.value}
                  disabled={o.disabled}
                  className={cn(
                    "flex cursor-default items-center justify-between gap-3 rounded-lg px-2.5 py-1.5 text-sm outline-none select-none",
                    "data-[highlighted]:bg-accent data-[highlighted]:text-accent-foreground data-[selected]:font-medium",
                    "data-[disabled]:pointer-events-none data-[disabled]:opacity-50",
                    g.baslik && "pl-4",
                  )}
                >
                  <Select.ItemText>{o.label}</Select.ItemText>
                  <Select.ItemIndicator className="text-vurgu">
                    <CheckIcon className="size-3.5" aria-hidden />
                  </Select.ItemIndicator>
                </Select.Item>
              ));
              return g.baslik ? (
                <Select.Group key={`g${gi}`} className={cn(gi > 0 && "mt-1 border-t pt-1")}>
                  <Select.GroupLabel className="px-2.5 pt-1.5 pb-1 text-[11px] font-semibold tracking-wide text-muted-foreground uppercase">
                    {g.baslik}
                  </Select.GroupLabel>
                  {ogeler}
                </Select.Group>
              ) : (
                <div key={`g${gi}`} className={cn(gi > 0 && "mt-1 border-t pt-1")}>
                  {ogeler}
                </div>
              );
            })}
          </Select.Popup>
        </Select.Positioner>
      </Select.Portal>
    </Select.Root>
  );
}
