import type { Metadata } from "next";
import { Plus_Jakarta_Sans } from "next/font/google";
import { Toaster } from "@/components/ui/sonner";
import { temaOku } from "@/lib/tema";
import "./globals.css";

// Plus Jakarta Sans: geometrik, sade ve okunaklı; hem metin hem başlıkta tek aile (sakin, tutarlı görünüm).
// latin-ext: ğ, ş, ı, İ gibi Türkçe harfler için gerekli. Yazı tipi derlemede indirilip sunucudan verilir;
// display: swap ile sayfa yazı tipini beklemeden açılır.
const jakarta = Plus_Jakarta_Sans({
  variable: "--font-sans",
  subsets: ["latin", "latin-ext"],
  display: "swap",
});


export const metadata: Metadata = {
  title: { default: "Atlas Trafo PDKS", template: "%s · Atlas Trafo PDKS" },
  description: "PDKS kayıt düzeltme sistemi",
};

export default async function RootLayout({ children }: LayoutProps<"/">) {
  // Tema çerezden okunur; sayfa sunucuda doğru renkle çizilir, açılışta yanıp sönmez.
  const tema = await temaOku();
  return (
    <html
      lang="tr"
      className={`${jakarta.variable} h-full antialiased ${tema === "koyu" ? "dark" : ""}`}
    >
      <body className="flex min-h-full flex-col">
        {children}
        {/* Yazma işlemlerinden sonra çıkan kısa bildirimler */}
        <Toaster position="top-right" theme={tema === "koyu" ? "dark" : "light"} />
      </body>
    </html>
  );
}
