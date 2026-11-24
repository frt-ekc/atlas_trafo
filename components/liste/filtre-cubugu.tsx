import Link from "next/link";
import type { ReactNode } from "react";
import { Button } from "@/components/ui/button";
import { SuzgecFormu } from "@/components/panel/suzgec-formu";
import { cn } from "@/lib/utils";

// Liste ekranlarının üstündeki ortak süzgeç çubuğu. Alanlar ekrana göre değişir
// (tür, durum, tarih aralığı, ad/sicil arama). Süzgeç adres çubuğuna yazılır, sorgu sunucuda süzülür.
export function FiltreCubugu({
  children,
  temizleAdres,
  suzgecVar,
}: {
  children: ReactNode;
  temizleAdres: string; // süzgeçsiz adres (sekme gibi korunacak parametreler dahil)
  suzgecVar: boolean; // "Süzgeçleri temizle" bağlantısı yalnızca bir süzgeç seçiliyken görünür
}) {
  return (
    <SuzgecFormu className="flex flex-wrap items-end gap-3 rounded-xl border bg-card/60 p-3">
      {children}
      <div className="flex items-center gap-3">
        <Button type="submit" size="sm" className="h-9">Uygula</Button>
        {suzgecVar && (
          <Link
            href={temizleAdres}
            scroll={false}
            className="rounded-sm text-sm text-muted-foreground underline underline-offset-4 outline-none hover:text-foreground focus-visible:ring-2 focus-visible:ring-ring"
          >
            Filtreleri temizle
          </Link>
        )}
      </div>
    </SuzgecFormu>
  );
}

// Süzgeç çubuğundaki tek alan: üstte etiket, altta giriş.
export function FiltreAlani({
  etiket,
  htmlFor,
  children,
  className,
}: {
  etiket: string;
  htmlFor: string;
  children: ReactNode;
  className?: string;
}) {
  return (
    <div className={cn("flex flex-col gap-1.5", className)}>
      <label htmlFor={htmlFor} className="text-sm font-medium">{etiket}</label>
      {children}
    </div>
  );
}
