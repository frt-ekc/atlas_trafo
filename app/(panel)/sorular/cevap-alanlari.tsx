"use client";

import { useState } from "react";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { SORU_CEVABI } from "@/lib/etiketler";
import { zorunluSaatler } from "./zorunlu-saatler";

// Soru cevaplama penceresinin alanları. Saat alanları yalnızca "saat farklı" seçilince görünür;
// bu yüzden tarayıcıda çalışan küçük bir bileşen.
export function CevapAlanlari({
  soruTuru,
  girisVarsayilan,
  cikisVarsayilan,
  kayitliGiris,
  kayitliCikis,
}: {
  soruTuru: string;
  girisVarsayilan: string;
  cikisVarsayilan: string;
  kayitliGiris: string | null; // "07:45": kayıtta zaten olan saat
  kayitliCikis: string | null;
}) {
  const [cevap, setCevap] = useState("");
  const zorunlu = zorunluSaatler(soruTuru);

  return (
    <>
      <fieldset className="flex flex-col gap-2">
        <legend className="mb-1 text-sm font-medium">Cevap</legend>
        {Object.entries(SORU_CEVABI).map(([deger, ad]) => (
          <label key={deger} className="flex items-center gap-2 text-sm">
            <input type="radio" name="cevap" value={deger} required checked={cevap === deger} onChange={() => setCevap(deger)} />
            {ad}
          </label>
        ))}
      </fieldset>

      {cevap === "geldi_saat_farkli" && (
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <div className="flex flex-col gap-1.5">
            <label htmlFor="giris" className="text-sm font-medium">Giriş{zorunlu.giris && <span className="text-destructive"> (zorunlu)</span>}{kayitliGiris && <span className="font-normal text-muted-foreground"> (kayıtlı {kayitliGiris})</span>}</label>
            <Input id="giris" name="giris" type="datetime-local" defaultValue={girisVarsayilan} required={zorunlu.giris} />
          </div>
          <div className="flex flex-col gap-1.5">
            <label htmlFor="cikis" className="text-sm font-medium">Çıkış{zorunlu.cikis && <span className="text-destructive"> (zorunlu)</span>}{kayitliCikis && <span className="font-normal text-muted-foreground"> (kayıtlı {kayitliCikis})</span>}</label>
            <Input id="cikis" name="cikis" type="datetime-local" defaultValue={cikisVarsayilan} required={zorunlu.cikis} />
          </div>
          <p className="text-xs text-muted-foreground sm:col-span-2">
            {zorunlu.giris && zorunlu.cikis
              ? "Giriş ve çıkış saatini birlikte yazın."
              : zorunlu.giris
                ? "Giriş saatini yazın; çıkış boş bırakılırsa değişmez."
                : zorunlu.cikis
                  ? "Çıkış saatini yazın; giriş boş bırakılırsa değişmez."
                  : "Yalnızca düzeltilecek saati girin; boş bırakılan değişmez."}{" "}
            Gece vardiyasında çıkış ertesi gündür.
          </p>
        </div>
      )}

      {(cevap === "gelmedi" || cevap === "bilmiyorum") && (
        <p className="rounded-lg bg-muted p-3 text-sm">
          Gün kaydı değişmez; karar İK&apos;ya geçer. Devamsızlık kararını yalnızca İK verir.
        </p>
      )}

      <div className="flex flex-col gap-1.5">
        <label htmlFor="aciklama" className="text-sm font-medium">Açıklama (isteğe bağlı)</label>
        <Textarea id="aciklama" name="aciklama" rows={2} maxLength={500} placeholder="ör. Servis geç geldi" />
      </div>
    </>
  );
}
