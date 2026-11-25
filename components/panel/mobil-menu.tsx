"use client";

import { MenuIcon, XIcon } from "lucide-react";
import { useState, type ReactNode } from "react";
import { createPortal } from "react-dom";

// Dar ekranda kenar çubuğu gizlenir; bu düğme onu soldan açılan bir panel olarak gösterir.
// Panelin içeriği (kenar çubuğu) sunucuda çizilip children olarak gelir.
// Bir bağlantıya tıklanınca ya da Esc'e basılınca panel kapanır.
// Panel body'ye taşınır (portal): üst bardaki bulanıklık efekti, içindeki "fixed" öğeyi
// ekrana değil üst bara göre konumlandırır.
export function MobilMenu({ children }: { children: ReactNode }) {
  const [acik, setAcik] = useState(false);

  const panel = (
    <div className="fixed inset-0 z-50 md:hidden" onKeyDown={(e) => e.key === "Escape" && setAcik(false)}>
      <div className="absolute inset-0 bg-black/55" onClick={() => setAcik(false)} aria-hidden />
      <div
        role="dialog"
        aria-modal="true"
        aria-label="Ana menü"
        className="absolute inset-y-3 left-3 flex w-72 max-w-[calc(100vw-1.5rem)] flex-col animate-in fade-in slide-in-from-left-4"
        onClick={(e) => (e.target as HTMLElement).closest("a") && setAcik(false)}
      >
        {children}
        <button
          type="button"
          onClick={() => setAcik(false)}
          className="absolute top-4 right-4 grid size-8 place-items-center rounded-full text-sidebar-foreground/70 hover:bg-sidebar-foreground/10 hover:text-sidebar-foreground"
          aria-label="Menüyü kapat"
          autoFocus
        >
          <XIcon className="size-4" />
        </button>
      </div>
    </div>
  );

  return (
    <>
      <button
        type="button"
        onClick={() => setAcik(true)}
        className="grid size-9 place-items-center rounded-full border bg-card/60 md:hidden"
        aria-label="Menüyü aç"
        aria-expanded={acik}
      >
        <MenuIcon className="size-4" />
      </button>
      {acik && createPortal(panel, document.body)}
    </>
  );
}
