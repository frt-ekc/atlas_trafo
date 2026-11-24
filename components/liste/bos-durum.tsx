import type { ReactNode } from "react";
import { InboxIcon } from "lucide-react";

// Liste boşken her ekranda aynı kutu görünür: sabit başlık + gerekiyorsa o listeye özel kısa açıklama.
export function BosDurum({ aciklama, baslik = "Kayıt bulunmuyor" }: { aciklama?: ReactNode; baslik?: string }) {
  return (
    <div className="flex flex-col items-center gap-1.5 rounded-xl border border-dashed px-6 py-8 text-center">
      <InboxIcon className="mb-1 size-5 text-muted-foreground" aria-hidden />
      <p className="text-sm font-medium">{baslik}</p>
      {aciklama && aciklama !== `${baslik}.` && <p className="max-w-prose text-sm text-muted-foreground">{aciklama}</p>}
    </div>
  );
}
