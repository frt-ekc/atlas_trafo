import type { ReactNode } from "react";

// Tabloların ortak çerçevesi: kart zemini, ince kenar, yuvarlak köşe.
// Zemin her yerde aynı olduğu için orta genişlikte sağa sabitlenen işlem sütunu
// satırdan ayrı bir panel gibi görünmez (bkz. globals.css).
export function TabloKutusu({ children }: { children: ReactNode }) {
  return <div className="overflow-hidden rounded-xl border bg-card">{children}</div>;
}
