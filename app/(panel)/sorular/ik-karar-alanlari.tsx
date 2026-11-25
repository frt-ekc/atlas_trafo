"use client";

import { useState } from "react";
import { TarihSecici } from "@/components/panel/tarih-secici";
import { Textarea } from "@/components/ui/textarea";
import { zorunluSaatler } from "./zorunlu-saatler";

// Amirin "gelmedi / bilmiyorum" dediği soruda İK kararı: devamsız say ya da saat yaz.
// Devamsızlık çalışan aleyhine karardır (KVKK m.11); gerekçe her zaman zorunludur.
export function IkKararAlanlari({ soruTuru, girisVarsayilan, cikisVarsayilan }: { soruTuru: string; girisVarsayilan: string; cikisVarsayilan: string }) {
  const [karar, setKarar] = useState<"" | "devamsiz" | "geldi">("");
  const zorunlu = zorunluSaatler(soruTuru);

  return (
    <>
      <fieldset className="flex flex-col gap-2">
        <legend className="mb-1 text-sm font-medium">Karar</legend>
        <label className="flex items-center gap-2 text-sm">
          <input type="radio" name="karar" value="geldi" required checked={karar === "geldi"} onChange={() => setKarar("geldi")} />
          Çalıştı (saat girilir)
        </label>
        <label className="flex items-center gap-2 text-sm">
          <input type="radio" name="karar" value="devamsiz" required checked={karar === "devamsiz"} onChange={() => setKarar("devamsiz")} />
          Devamsız
        </label>
      </fieldset>

      {karar === "geldi" && (
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <div className="flex flex-col gap-1.5">
            <label htmlFor="giris" className="text-sm font-medium">Giriş{zorunlu.giris && <span className="text-destructive"> (zorunlu)</span>}</label>
            <TarihSecici saatli id="giris" name="giris" defaultValue={girisVarsayilan} required={zorunlu.giris} />
          </div>
          <div className="flex flex-col gap-1.5">
            <label htmlFor="cikis" className="text-sm font-medium">Çıkış{zorunlu.cikis && <span className="text-destructive"> (zorunlu)</span>}</label>
            <TarihSecici saatli id="cikis" name="cikis" defaultValue={cikisVarsayilan} required={zorunlu.cikis} />
          </div>
        </div>
      )}
      {karar === "devamsiz" && (
        <p className="rounded-lg bg-destructive/10 p-3 text-sm text-destructive">
          Gün &quot;Devamsız&quot; olarak ve çalışan aleyhine kaydedilir. Karar geri alınamaz; çalışan itiraz edebilir.
        </p>
      )}

      <div className="flex flex-col gap-1.5">
        <label htmlFor="gerekce" className="text-sm font-medium">Gerekçe</label>
        <Textarea id="gerekce" name="gerekce" rows={2} required minLength={5} maxLength={1000} placeholder="ör. Mazeret belgesi sunulmadı" />
      </div>
    </>
  );
}
