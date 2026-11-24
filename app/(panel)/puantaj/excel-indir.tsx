"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import type { ErpSatiri } from "@/lib/erp-aktarim";
import { PUANTAJ_SUTUNLARI, ayAdi, type PuantajSatiri } from "@/lib/puantaj";

// Puantajı Excel dosyası olarak indirir. Dosya tarayıcıda üretilir; sunucuya bir şey gitmez.
// SheetJS büyük bir kütüphane; yalnızca düğmeye basılınca yüklenir.
export function ExcelIndir({
  ay,
  durum,
  satirlar,
  farkSatirlari,
  kodlar,
  hazirlayan,
}: {
  ay: string;
  durum: "acik" | "kilitli";
  satirlar: PuantajSatiri[];
  farkSatirlari: PuantajSatiri[];
  kodlar: ErpSatiri[]; // kilitli ayın puantaj kodları (açık ayda boş)
  hazirlayan: string;
}) {
  const [hazirlaniyor, setHazirlaniyor] = useState(false);

  async function indir() {
    setHazirlaniyor(true);
    try {
      const XLSX = await import("xlsx");
      const kitap = XLSX.utils.book_new();

      const sayfa = (liste: PuantajSatiri[], farkMi: boolean) => {
        const sutunlar = farkMi
          ? [{ baslik: "Ait olduğu ay", deger: (s: PuantajSatiri) => s.kaynakDonem ?? "", genislik: 13 }, ...PUANTAJ_SUTUNLARI]
          : PUANTAJ_SUTUNLARI;
        const tablo = XLSX.utils.aoa_to_sheet([sutunlar.map((s) => s.baslik), ...liste.map((r) => sutunlar.map((s) => s.deger(r)))]);
        tablo["!cols"] = sutunlar.map((s) => ({ wch: s.genislik }));
        tablo["!autofilter"] = { ref: tablo["!ref"] ?? "A1" };
        return tablo;
      };

      XLSX.utils.book_append_sheet(kitap, sayfa(satirlar, false), "Puantaj");
      if (farkSatirlari.length) XLSX.utils.book_append_sheet(kitap, sayfa(farkSatirlari, true), "Fark satırları");
      if (kodlar.length) {
        const kodSayfasi = XLSX.utils.aoa_to_sheet([
          ["Sicil", "Satır türü", "Ait olduğu ay", "Kod", "Gün", "Dakika"],
          ...kodlar.map((k) => [k.sicil, k.satirTuru, k.kaynakDonem ?? "", k.kod, k.gun, k.dakika]),
        ]);
        kodSayfasi["!cols"] = [{ wch: 8 }, { wch: 10 }, { wch: 13 }, { wch: 8 }, { wch: 6 }, { wch: 8 }];
        kodSayfasi["!autofilter"] = { ref: kodSayfasi["!ref"] ?? "A1" };
        XLSX.utils.book_append_sheet(kitap, kodSayfasi, "Puantaj kodları");
      }

      const bilgi = XLSX.utils.aoa_to_sheet([
        ["Dönem", ayAdi(ay)],
        ["Durum", durum === "kilitli" ? "Kilitli" : "Açık (kesinleşmemiş)"],
        ["Hazırlayan", hazirlayan],
        ["Hazırlanma zamanı", new Date().toLocaleString("tr-TR", { timeZone: "Europe/Istanbul" })],
        ["Not", "Dosya yalnızca gün ve süre bilgisi içerir. Fark satırları önceki aylara ait düzeltmelerdir."],
        [
          "Kodlar",
          "NÇ normal çalışma · FM50 hafta içi fazla mesai · FM100 Pazar / resmi tatil çalışması · Yİ yıllık izin · RPR rapor · MZR mazeret · ÜCSZ ücretsiz izin · Dİ diğer izin · DVMSZ devamsız · RT resmi tatil · HT hafta tatili. Kod sayfası yalnızca kilitli ayda vardır.",
        ],
      ]);
      bilgi["!cols"] = [{ wch: 18 }, { wch: 80 }];
      XLSX.utils.book_append_sheet(kitap, bilgi, "Bilgi");

      XLSX.writeFile(kitap, `puantaj_${ay}${durum === "kilitli" ? "" : "_taslak"}.xlsx`, { compression: true });
    } finally {
      setHazirlaniyor(false);
    }
  }

  return (
    <Button onClick={indir} disabled={hazirlaniyor || satirlar.length === 0}>
      {hazirlaniyor ? "Hazırlanıyor…" : durum === "kilitli" ? "Excel indir" : "Taslak Excel indir"}
    </Button>
  );
}
