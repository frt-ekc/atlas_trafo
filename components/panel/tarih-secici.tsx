"use client";

import { Popover } from "@base-ui/react/popover";
import { CalendarDaysIcon, ChevronLeftIcon, ChevronRightIcon } from "lucide-react";
import { useEffect, useRef, useState, type KeyboardEvent } from "react";
import { cn } from "@/lib/utils";

// Sistemin tarih alanı: tarayıcının biçimlendirilemeyen takvimi yerine kendi takvimimiz.
// Form için değer "yyyy-aa-gg" (saatli ise "yyyy-aa-ggTss:dd") olarak verilen "name" ile gönderilir;
// sunucu tarafı hiç değişmez. Süzgeç formunun (data-suzgec) içindeyse gün seçilince süzgeç uygulanır.
// Klavye: oklar gün / hafta, PageUp / PageDown ay değiştirir, Enter seçer, Esc kapatır.

const AYLAR = ["Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran", "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık"];
const GUNLER = ["Pt", "Sa", "Ça", "Pe", "Cu", "Ct", "Pz"];

// Tarihler saat dilimi kaymasın diye UTC gün olarak hesaplanır
const parcala = (t: string) => t.split("-").map(Number) as [number, number, number];
const yaz = (d: Date) => d.toISOString().slice(0, 10);
const gunEkle = (t: string, n: number) => {
  const [y, a, g] = parcala(t);
  return yaz(new Date(Date.UTC(y, a - 1, g + n)));
};
const ayEkle = (t: string, n: number) => {
  const [y, a, g] = parcala(t);
  const son = new Date(Date.UTC(y, a + n, 0)).getUTCDate(); // hedef ayın son günü
  return yaz(new Date(Date.UTC(y, a - 1 + n, Math.min(g, son))));
};
const gosterim = (t: string) => (t ? `${t.slice(8, 10)}.${t.slice(5, 7)}.${t.slice(0, 4)}` : "");
const bugun = () => {
  // Türkiye saatine göre bugün
  const p = new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Istanbul" }).format(new Date());
  return p;
};
const gecerli = (t: string) => /^\d{4}-\d{2}-\d{2}$/.test(t);

type Ozellikler = {
  id?: string;
  name: string;
  defaultValue?: string;
  required?: boolean;
  min?: string;
  max?: string;
  saatli?: boolean; // tarih + saat (datetime-local yerine)
  className?: string;
};

export function TarihSecici({ id, name, defaultValue = "", required, min, max, saatli, className }: Ozellikler) {
  const ilkTarih = defaultValue.slice(0, 10);
  const ilkSaat = saatli ? defaultValue.slice(11, 16) : "";
  const [tarih, setTarih] = useState(gecerli(ilkTarih) ? ilkTarih : "");
  const [saat, setSaat] = useState(ilkSaat);
  const [onceki, setOnceki] = useState(defaultValue);
  // Süzgeç sayfası yeni adresle çizilince (geri tuşu, "Süzgeçleri temizle") sunucunun değeri gelir
  if (defaultValue !== onceki) {
    setOnceki(defaultValue);
    setTarih(gecerli(defaultValue.slice(0, 10)) ? defaultValue.slice(0, 10) : "");
    setSaat(saatli ? defaultValue.slice(11, 16) : "");
  }

  const [acik, setAcik] = useState(false);
  const [odak, setOdak] = useState(tarih || bugun());
  const tetik = useRef<HTMLButtonElement>(null);
  const izgara = useRef<HTMLDivElement>(null);

  const izinli = (t: string) => (!min || t >= min.slice(0, 10)) && (!max || t <= max.slice(0, 10));
  const formDegeri = saatli ? (tarih && saat ? `${tarih}T${saat}` : "") : tarih;

  // Klavyeyle gezinirken odak, seçili güne taşınır (yalnızca DOM odağı; durum değişmez)
  useEffect(() => {
    if (acik) izgara.current?.querySelector<HTMLButtonElement>(`[data-gun="${odak}"]`)?.focus();
  }, [acik, odak]);

  function sec(t: string) {
    if (!izinli(t)) return;
    setTarih(t);
    setAcik(false);
    tetik.current?.focus();
    const form = tetik.current?.closest("form");
    if (form?.hasAttribute("data-suzgec")) setTimeout(() => form.requestSubmit(), 0);
  }

  function tus(e: KeyboardEvent<HTMLDivElement>) {
    const adim: Record<string, () => string> = {
      ArrowLeft: () => gunEkle(odak, -1),
      ArrowRight: () => gunEkle(odak, 1),
      ArrowUp: () => gunEkle(odak, -7),
      ArrowDown: () => gunEkle(odak, 7),
      PageUp: () => ayEkle(odak, -1),
      PageDown: () => ayEkle(odak, 1),
    };
    if (adim[e.key]) {
      e.preventDefault();
      setOdak(adim[e.key]());
    }
  }

  // Görünen ay: odaktaki günün ayı; Pazartesi'den başlayan 6 haftalık ızgara
  const [oy, oa] = parcala(odak);
  const ayBasi = `${oy}-${String(oa).padStart(2, "0")}-01`;
  const haftaGunu = (new Date(Date.UTC(oy, oa - 1, 1)).getUTCDay() + 6) % 7;
  const ilkGun = gunEkle(ayBasi, -haftaGunu);
  const gunler = Array.from({ length: 42 }, (_, i) => gunEkle(ilkGun, i));
  const bugunTarih = bugun();

  return (
    <div className={cn("relative flex min-w-0 gap-2", className)}>
      <Popover.Root
        open={acik}
        onOpenChange={(a) => {
          if (a) setOdak(tarih || (max && bugunTarih > max ? max.slice(0, 10) : bugunTarih));
          setAcik(a);
        }}
      >
        <Popover.Trigger
          ref={tetik}
          id={id}
          className={cn(
            "flex h-9 min-w-0 flex-1 items-center gap-2 rounded-lg border border-input bg-card px-2.5 text-left text-sm outline-none transition-colors",
            "hover:border-ring/60 focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/40 data-[popup-open]:border-ring dark:bg-input/30",
          )}
        >
          <CalendarDaysIcon className="size-4 shrink-0 text-muted-foreground" aria-hidden />
          <span className={cn("truncate tabular-nums", !tarih && "text-muted-foreground")}>{tarih ? gosterim(tarih) : "gg.aa.yyyy"}</span>
        </Popover.Trigger>
        <Popover.Portal>
          <Popover.Positioner sideOffset={6} align="start" className="z-[60] outline-none">
            <Popover.Popup
              aria-label="Tarih seç"
              className={cn(
                "w-[17.5rem] rounded-xl border bg-popover p-3 text-popover-foreground shadow-lg shadow-black/10 outline-none",
                "origin-[var(--transform-origin)] transition-[transform,opacity] data-[ending-style]:scale-95 data-[ending-style]:opacity-0 data-[starting-style]:scale-95 data-[starting-style]:opacity-0",
              )}
            >
              <div className="mb-2 flex items-center justify-between">
                <button
                  type="button"
                  onClick={() => setOdak(ayEkle(odak, -1))}
                  className="grid size-7 place-items-center rounded-lg text-muted-foreground outline-none hover:bg-accent hover:text-accent-foreground focus-visible:ring-2 focus-visible:ring-ring"
                  aria-label="Önceki ay"
                >
                  <ChevronLeftIcon className="size-4" aria-hidden />
                </button>
                <div className="font-heading text-sm font-semibold" aria-live="polite">
                  {AYLAR[oa - 1]} {oy}
                </div>
                <button
                  type="button"
                  onClick={() => setOdak(ayEkle(odak, 1))}
                  className="grid size-7 place-items-center rounded-lg text-muted-foreground outline-none hover:bg-accent hover:text-accent-foreground focus-visible:ring-2 focus-visible:ring-ring"
                  aria-label="Sonraki ay"
                >
                  <ChevronRightIcon className="size-4" aria-hidden />
                </button>
              </div>

              <div className="grid grid-cols-7 text-center text-[11px] font-medium text-muted-foreground" aria-hidden>
                {GUNLER.map((g) => (
                  <div key={g} className="py-1">{g}</div>
                ))}
              </div>
              <div ref={izgara} role="grid" aria-label={`${AYLAR[oa - 1]} ${oy}`} onKeyDown={tus} className="grid grid-cols-7 gap-0.5">
                {gunler.map((g) => {
                  const buAy = g.slice(0, 7) === ayBasi.slice(0, 7);
                  const secili = g === tarih;
                  const izin = izinli(g);
                  return (
                    <button
                      key={g}
                      type="button"
                      data-gun={g}
                      tabIndex={g === odak ? 0 : -1}
                      disabled={!izin}
                      onClick={() => sec(g)}
                      aria-pressed={secili}
                      aria-label={gosterim(g)}
                      className={cn(
                        "relative grid h-8 place-items-center rounded-lg text-[0.8125rem] tabular-nums outline-none transition-colors",
                        "hover:bg-accent hover:text-accent-foreground focus-visible:ring-2 focus-visible:ring-ring",
                        !buAy && "text-muted-foreground/60",
                        g === bugunTarih && !secili && "font-semibold text-vurgu",
                        secili && "bg-primary font-medium text-primary-foreground hover:bg-primary hover:text-primary-foreground",
                        !izin && "pointer-events-none opacity-30",
                      )}
                    >
                      {Number(g.slice(8, 10))}
                      {g === bugunTarih && !secili && <span className="absolute bottom-1 size-1 rounded-full bg-current" aria-hidden />}
                    </button>
                  );
                })}
              </div>

              <div className="mt-2 flex items-center justify-between border-t pt-2">
                <button
                  type="button"
                  onClick={() => sec(bugunTarih)}
                  disabled={!izinli(bugunTarih)}
                  className="rounded-md px-2 py-1 text-xs font-medium text-vurgu outline-none hover:bg-accent focus-visible:ring-2 focus-visible:ring-ring disabled:opacity-40"
                >
                  Bugün
                </button>
                {!required && tarih && (
                  <button
                    type="button"
                    onClick={() => {
                      setTarih("");
                      setAcik(false);
                      const form = tetik.current?.closest("form");
                      if (form?.hasAttribute("data-suzgec")) setTimeout(() => form.requestSubmit(), 0);
                    }}
                    className="rounded-md px-2 py-1 text-xs text-muted-foreground outline-none hover:bg-accent hover:text-foreground focus-visible:ring-2 focus-visible:ring-ring"
                  >
                    Temizle
                  </button>
                )}
              </div>
            </Popover.Popup>
          </Popover.Positioner>
        </Popover.Portal>
      </Popover.Root>

      {saatli && (
        <input
          type="time"
          aria-label="Saat"
          value={saat}
          onChange={(e) => setSaat(e.target.value)}
          required={required || Boolean(tarih)}
          className="h-9 w-[6.25rem] shrink-0 rounded-lg border border-input bg-card px-2 text-base tabular-nums md:text-sm outline-none focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/40 dark:bg-input/30"
        />
      )}

      {/* Formun okuduğu değer. Görünmez ama tarayıcının "zorunlu alan" denetimi bu alanda çalışır. */}
      <input
        name={name}
        value={formDegeri}
        required={required}
        onChange={() => {}}
        onFocus={() => tetik.current?.focus()}
        tabIndex={-1}
        aria-hidden
        className="pointer-events-none absolute size-px opacity-0"
      />
    </div>
  );
}
