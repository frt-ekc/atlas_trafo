"use client";

import { createContext, useActionState, useContext, useEffect, useRef, useState, type ReactNode } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { BOS_SONUC, type Islem } from "@/lib/islem-sonucu";

// Listede birden çok kaydı seçip tek düğmeyle işlem yapmak için.
// Seçim tarayıcıda tutulur; düğmeye basınca seçilen numaralar Server Action'a gider.
// Liste yenilenince (ör. görülen uyarılar listeden çıkınca) artık olmayan seçimler kendiliğinden düşer.
type Baglam = { secili: Set<number>; degistir: (id: number, secildi: boolean) => void };
const SecimBaglami = createContext<Baglam | null>(null);

export function TopluSecim({
  idler,
  alanAdi,
  dugme,
  islem,
  children,
}: {
  idler: number[]; // seçilebilir kayıtlar (ekranda görünenler)
  alanAdi: string; // Server Action'ın okuduğu form alanı, ör. "uyari_id"
  dugme: string; // ör. "Seçilenleri görüldü yap"
  islem: Islem;
  children: ReactNode;
}) {
  const [ham, setHam] = useState<Set<number>>(new Set());
  const gecerli = new Set(idler);
  const secili = new Set([...ham].filter((id) => gecerli.has(id)));

  const [, gonder, bekliyor] = useActionState(async (onceki: Parameters<Islem>[0], form: FormData) => {
    const sonuc = await islem(onceki, form);
    if (sonuc.durum === "tamam") {
      (sonuc.uyari ? toast.warning : toast.success)(sonuc.mesaj);
      setHam(new Set());
    }
    if (sonuc.durum === "hata") toast.error(sonuc.mesaj);
    return sonuc;
  }, BOS_SONUC);

  const hepsiRef = useRef<HTMLInputElement>(null);
  const hepsi = idler.length > 0 && secili.size === idler.length;
  const biraz = secili.size > 0 && !hepsi;
  useEffect(() => {
    if (hepsiRef.current) hepsiRef.current.indeterminate = biraz;
  }, [biraz]);

  function degistir(id: number, secildi: boolean) {
    setHam((onceki) => {
      const yeni = new Set([...onceki].filter((x) => gecerli.has(x)));
      if (secildi) yeni.add(id);
      else yeni.delete(id);
      return yeni;
    });
  }

  return (
    <SecimBaglami.Provider value={{ secili, degistir }}>
      <form
        action={gonder}
        // Aşağıdaki kartları seçerken düğme görünür kalsın diye sayfanın üstüne yapışır
        className="sticky top-3 z-20 flex flex-wrap items-center gap-x-4 gap-y-2 rounded-xl border bg-card px-4 py-2.5 shadow-sm"
      >
        {[...secili].map((id) => (
          <input key={id} type="hidden" name={alanAdi} value={id} />
        ))}
        <label className="flex items-center gap-2 text-sm">
          <input
            ref={hepsiRef}
            type="checkbox"
            className="size-4 accent-primary"
            checked={hepsi}
            onChange={(e) => setHam(e.target.checked ? new Set(idler) : new Set())}
          />
          Tümünü seç
        </label>
        <span className="text-sm text-muted-foreground tabular-nums" aria-live="polite">
          {secili.size} seçili
        </span>
        <Button type="submit" size="sm" className="ml-auto" disabled={secili.size === 0 || bekliyor}>
          {bekliyor ? "İşleniyor…" : dugme}
        </Button>
      </form>
      {children}
    </SecimBaglami.Provider>
  );
}

// Kartın solundaki onay kutusu. "etiket" ekran okuyucuya hangi kaydın seçildiğini söyler.
export function SecimKutusu({ id, etiket }: { id: number; etiket: string }) {
  const baglam = useContext(SecimBaglami);
  if (!baglam) return null;
  return (
    <input
      type="checkbox"
      className="size-4 accent-primary"
      aria-label={etiket}
      checked={baglam.secili.has(id)}
      onChange={(e) => baglam.degistir(id, e.target.checked)}
    />
  );
}
