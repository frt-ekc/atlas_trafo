"use client";

import { Button } from "@/components/ui/button";
import { csvMetni, xmlMetni, type ErpSatiri } from "@/lib/erp-aktarim";

// Kilitli ayın puantaj icmalini ERP'ye aktarılacak CSV ya da XML dosyası olarak indirir.
// Dosya tarayıcıda üretilir; sunucuya bir şey gitmez.
export function ErpIndir({ ay, satirlar }: { ay: string; satirlar: ErpSatiri[] }) {
  function indir(icerik: string, tur: string, uzanti: string) {
    const url = URL.createObjectURL(new Blob([icerik], { type: tur }));
    const a = document.createElement("a");
    a.href = url;
    a.download = `puantaj_${ay}.${uzanti}`;
    a.click();
    URL.revokeObjectURL(url);
  }

  const bos = satirlar.length === 0;
  return (
    <div className="flex gap-2">
      <Button variant="outline" disabled={bos} onClick={() => indir("﻿" + csvMetni(satirlar), "text/csv;charset=utf-8", "csv")}>
        ERP dosyası (CSV)
      </Button>
      <Button
        variant="outline"
        disabled={bos}
        onClick={() => indir(xmlMetni(ay, satirlar, new Date().toISOString()), "application/xml;charset=utf-8", "xml")}
      >
        ERP dosyası (XML)
      </Button>
    </div>
  );
}
