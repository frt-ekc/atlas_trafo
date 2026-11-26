"use client";

import { useState, type CSSProperties } from "react";
import { cn } from "@/lib/utils";

// Sistem yöneticisi için gece işi geçmişi: "gecenin ufkunda ışık sütunları".
// - Her gece ufuk çizgisinden yükselen ince bir ışık sütunu; yüksekliği işlemin süresi.
// - Sorunsuz gece gümüş ışık (yazı renginden), yalnızca istisnalar renkli: hatalı gece kırmızı parlar,
//   hiç çalışmayan gece ufukta boş bir halka. Çizginin altında sütunun soluk yansıması.
// - Üzerine gelince (ya da klavyeyle odaklanınca) diğer sütunlar söner, o gecenin özeti açılır.
// - Aynı veri altta tablo olarak da açılır (ekran okuyucu ve çıktı için).
// Kütüphane yok, düz HTML ve CSS (components/panel/grafik.tsx ile aynı yaklaşım).

export type GeceIsiGunu = {
  gun: string; // işlenen gün (yyyy-aa-gg)
  durum: "basarili" | "hatali" | "calisiyor" | null; // null: o gün için gece işi kaydı yok
  sureSn: number | null;
  ozet: Record<string, number>;
  hata: string | null;
  tekrar: number; // aynı gün için kaç kez çalıştırıldı
};

// Gece işinin özet alanlarının ekrandaki adları (pdks.gece_isi.ozet), gösterim sırasıyla
const OZET_ADI: Record<string, string> = {
  gun_kaydi: "Gün kaydı",
  hesap: "Hesaplanan gün",
  duzeltme: "Otomatik düzeltme",
  soru: "Amire soru",
  eskale: "Üst amire iletilen",
  uyari: "Uyarı",
  ariza: "Arıza şüphesi",
  plansiz: "Plansız gün",
  isaret: "İşaretlenen okutma",
};
const SIRA = Object.keys(OZET_ADI);
const siraliOzet = (o: Record<string, number>) =>
  Object.entries(o).sort(([x], [y]) => (SIRA.indexOf(x) + 1 || 99) - (SIRA.indexOf(y) + 1 || 99));

// Işığın rengi: sorunsuz gece yazı renginde (koyu temada gümüş), istisnalar durum renginde
const ISIK = {
  basarili: { ad: "Sorunsuz", renk: "var(--foreground)" },
  hatali: { ad: "Hatalı", renk: "var(--kotu)" },
  calisiyor: { ad: "Çalışıyor", renk: "var(--dikkat)" },
} as const;

const kisaTarih = (g: string) => `${g.slice(8, 10)}.${g.slice(5, 7)}`;
const uzunTarih = (g: string) => `${g.slice(8, 10)}.${g.slice(5, 7)}.${g.slice(0, 4)}`;
const AYLAR = ["Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran", "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık"];
const gunAy = (g: string) => `${Number(g.slice(8, 10))} ${AYLAR[Number(g.slice(5, 7)) - 1]}`;
function sureMetni(sn: number | null) {
  if (sn == null) return "—";
  if (sn < 60) return `${Math.max(1, Math.round(sn))} sn`;
  return `${Math.floor(sn / 60)} dk ${Math.round(sn % 60)} sn`;
}

export function GeceIsiGrafigi({ gunler }: { gunler: GeceIsiGunu[] }) {
  const [secili, setSecili] = useState<number | null>(null);
  const enUzun = Math.max(1, ...gunler.map((g) => g.sureSn ?? 0));
  const sorunsuz = gunler.filter((g) => g.durum === "basarili").length;
  const hatali = gunler.filter((g) => g.durum === "hatali").length;
  const calismadi = gunler.filter((g) => g.durum === null).length;
  const s = secili != null ? gunler[secili] : null;

  return (
    <div className="flex flex-col gap-4">
      {/* Öne çıkan sayı: kaç gece sorunsuz geçti */}
      <div className="flex flex-wrap items-end justify-between gap-x-6 gap-y-2">
        <div className="flex items-baseline gap-2">
          <span className="yazi-gecis text-4xl leading-none font-semibold tracking-tight tabular-nums">{sorunsuz}</span>
          <span className="text-base text-muted-foreground tabular-nums">/{gunler.length}</span>
          <span className="ml-1 text-sm text-muted-foreground">gece sorunsuz</span>
        </div>
        <ul className="flex flex-wrap gap-x-4 gap-y-1 text-xs text-muted-foreground">
          <li className="flex items-center gap-1.5">
            <span className="size-1.5 rounded-full bg-foreground shadow-[0_0_6px_var(--foreground)]" aria-hidden /> Sorunsuz
          </li>
          <li className="flex items-center gap-1.5">
            <span className="size-1.5 rounded-full bg-kotu shadow-[0_0_6px_var(--kotu)]" aria-hidden /> Hatalı{hatali > 0 && ` (${hatali})`}
          </li>
          <li className="flex items-center gap-1.5">
            <span className="size-1.5 rounded-full ring-1 ring-muted-foreground" aria-hidden /> Çalışmadı{calismadi > 0 && ` (${calismadi})`}
          </li>
        </ul>
      </div>

      <div className="relative pt-5">
        <span className="pointer-events-none absolute top-0 right-0 text-[11px] text-muted-foreground tabular-nums" aria-hidden>
          en uzun {sureMetni(enUzun)}
        </span>

        {/* Ufuk: sütunlar çizgiden yükselir (üst %75), altında yansımaları (alt %25) */}
        <div
          role="group"
          aria-label="Son 30 gecenin gece işi sonuçları"
          className="relative flex h-32 items-stretch"
          onMouseLeave={() => setSecili(null)}
        >
          {/* Ufuk çizgisi: uçlarda kaybolan ince ışık */}
          <div
            className="pointer-events-none absolute inset-x-0 top-[75%] h-px bg-[linear-gradient(90deg,transparent,color-mix(in_oklab,var(--foreground)_35%,transparent)_15%,color-mix(in_oklab,var(--foreground)_35%,transparent)_85%,transparent)]"
            aria-hidden
          />
          {/* Bilgi kartı: imlecin olduğu sütunun ucunun hemen üstünde açılır; grafiğin kenarından taşmaz */}
          {s && secili != null && (
            <div
              role="status"
              className="pointer-events-none absolute z-20 w-40 rounded-lg border bg-popover/95 px-2.5 py-2 text-[11px] leading-snug text-popover-foreground shadow-xl shadow-black/40 backdrop-blur"
              style={{
                left: `clamp(0px, calc(${((secili + 0.5) / gunler.length) * 100}% - 5rem), calc(100% - 10rem))`,
                bottom: `calc(${25 + (s.sureSn != null ? Math.max(0.05, s.sureSn / enUzun) : 0) * 75}% + 12px)`,
              }}
            >
              <div className="flex items-baseline justify-between gap-2 text-muted-foreground">
                <span className="font-medium text-popover-foreground">{gunAy(s.gun)}</span>
                <span className={cn(s.durum === "hatali" && "text-kotu")}>{s.durum ? ISIK[s.durum].ad : "Çalışmadı"}</span>
              </div>
              {s.durum ? (
                <>
                  {/* İşlem süresi: o gecenin gece işinin başlangıcı ile bitişi arasında geçen süre */}
                  <div className="mt-0.5 flex items-baseline justify-between gap-2">
                    <span className="text-muted-foreground">İşlem süresi</span>
                    <span className="yazi-gecis text-sm font-semibold tabular-nums">{sureMetni(s.sureSn)}</span>
                  </div>
                  {s.tekrar > 1 && <div className="text-muted-foreground">{s.tekrar} kez çalıştırıldı</div>}
                  {/* Yalnızca sıfır olmayan ilk dört sayı; tam döküm tabloda */}
                  {siraliOzet(s.ozet).some(([, v]) => v) && (
                    <dl className="mt-1 grid grid-cols-[1fr_auto] gap-x-2 border-t border-border pt-1 text-muted-foreground">
                      {siraliOzet(s.ozet)
                        .filter(([, v]) => v)
                        .slice(0, 4)
                        .map(([k, v]) => (
                          <div key={k} className="contents">
                            <dt className="truncate">{OZET_ADI[k] ?? k}</dt>
                            <dd className="text-right font-medium text-popover-foreground tabular-nums">{v}</dd>
                          </div>
                        ))}
                    </dl>
                  )}
                </>
              ) : (
                <p className="text-muted-foreground">Kayıt yok</p>
              )}
              {s.hata && <p className="mt-1 line-clamp-2 text-kotu">{s.hata}</p>}
            </div>
          )}
          {gunler.map((g, i) => {
            const oran = g.sureSn != null ? Math.max(0.05, g.sureSn / enUzun) : 0;
            const renk = g.durum ? ISIK[g.durum].renk : "var(--muted-foreground)";
            const sonuk = secili != null && secili !== i;
            const etiket = g.durum ? `${uzunTarih(g.gun)}: ${ISIK[g.durum].ad}, ${sureMetni(g.sureSn)}` : `${uzunTarih(g.gun)}: gece işi çalışmadı`;
            return (
              <button
                key={g.gun}
                type="button"
                aria-label={etiket}
                onMouseEnter={() => setSecili(i)}
                onFocus={() => setSecili(i)}
                onBlur={() => setSecili(null)}
                // Tıklama alanı sütunun bütün yüksekliği; ince ışığa denk getirmek gerekmez
                className="group relative min-w-0 flex-1 outline-none"
                style={{ "--isik": renk } as CSSProperties}
              >
                {/* Seçiliyken tarihi işaret eden ince dikey çizgi */}
                <span
                  className={cn(
                    "pointer-events-none absolute inset-y-0 left-1/2 w-px -translate-x-1/2 bg-[linear-gradient(180deg,transparent,color-mix(in_oklab,var(--isik)_40%,transparent),transparent)] transition-opacity",
                    secili === i ? "opacity-100" : "opacity-0",
                  )}
                  aria-hidden
                />
                {/* Klavye odağı */}
                <span className="pointer-events-none absolute inset-x-0.5 inset-y-0 rounded-md opacity-0 ring-1 ring-ring group-focus-visible:opacity-100" aria-hidden />

                {/* Ufkun üstü: ışık sütunu */}
                <span className="absolute inset-x-0 top-0 bottom-[25%] flex items-end justify-center" aria-hidden>
                  {g.durum ? (
                    <span
                      className="isik-sutunu relative w-[3px] rounded-full transition-[opacity,filter] duration-200 sm:w-1"
                      style={{
                        height: `${oran * 100}%`,
                        animationDelay: `${i * 22}ms`,
                        opacity: sonuk ? 0.25 : 1,
                        background: "linear-gradient(0deg, transparent 0%, color-mix(in oklab, var(--isik) 55%, transparent) 45%, var(--isik) 100%)",
                        filter: secili === i ? "drop-shadow(0 0 6px var(--isik))" : undefined,
                      }}
                    >
                      {/* Uçta parlayan nokta */}
                      <span
                        className="absolute -top-0.5 left-1/2 size-1.5 -translate-x-1/2 rounded-full sm:size-2"
                        style={{ background: "var(--isik)", boxShadow: `0 0 ${g.durum === "hatali" ? 12 : 8}px var(--isik)` }}
                      />
                    </span>
                  ) : (
                    // Çalışmayan gece: ufukta boş halka
                    <span
                      className="mb-[-3px] size-1.5 rounded-full ring-1 ring-muted-foreground transition-opacity sm:size-2"
                      style={{ opacity: sonuk ? 0.3 : 0.9 }}
                    />
                  )}
                </span>

                {/* Ufkun altı: soluk yansıma */}
                {g.durum && (
                  <span className="absolute inset-x-0 top-[75%] bottom-0 flex justify-center overflow-hidden" aria-hidden>
                    <span
                      className="w-[3px] rounded-full transition-opacity sm:w-1"
                      style={{
                        height: `${oran * 100}%`,
                        opacity: sonuk ? 0.05 : 0.18,
                        background: "linear-gradient(180deg, var(--isik), transparent 80%)",
                      }}
                    />
                  </span>
                )}
              </button>
            );
          })}
        </div>

        {/* Tarih ekseni: baş, orta ve son */}
        <div className="mt-2 flex justify-between text-[11px] tracking-wide text-muted-foreground tabular-nums" aria-hidden>
          <span>{kisaTarih(gunler[0].gun)}</span>
          <span>{kisaTarih(gunler[Math.floor(gunler.length / 2)].gun)}</span>
          <span>{kisaTarih(gunler[gunler.length - 1].gun)}</span>
        </div>
      </div>

      {/* Aynı veri tablo olarak */}
      <details className="group/tablo text-sm">
        <summary className="flex cursor-pointer list-none items-center gap-1.5 text-xs text-muted-foreground hover:text-foreground [&::-webkit-details-marker]:hidden">
          <span className="transition-transform group-open/tablo:rotate-90" aria-hidden>
            ›
          </span>
          Tablo olarak göster
        </summary>
        <div className="mt-3 max-h-72 overflow-auto">
          <table className="w-full text-left text-xs">
            <thead className="sticky top-0 bg-card text-muted-foreground">
              <tr className="border-b">
                <th className="py-2 pr-3 font-medium">Gün</th>
                <th className="py-2 pr-3 font-medium">Sonuç</th>
                <th className="py-2 pr-3 text-right font-medium">Süre</th>
                <th className="py-2 font-medium">Özet</th>
              </tr>
            </thead>
            <tbody>
              {[...gunler].reverse().map((g) => (
                <tr key={g.gun} className="border-b border-border/60 last:border-0">
                  <td className="py-1.5 pr-3 tabular-nums">{uzunTarih(g.gun)}</td>
                  <td className={cn("py-1.5 pr-3", g.durum === "hatali" && "text-kotu", !g.durum && "text-muted-foreground")}>
                    {g.durum ? ISIK[g.durum].ad : "Çalışmadı"}
                  </td>
                  <td className="py-1.5 pr-3 text-right tabular-nums">{sureMetni(g.sureSn)}</td>
                  <td className="py-1.5 text-muted-foreground">
                    {siraliOzet(g.ozet).map(([k, v]) => `${OZET_ADI[k] ?? k} ${v}`).join(" · ") || "—"}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </details>
    </div>
  );
}
