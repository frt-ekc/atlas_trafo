import type { Metadata } from "next";
import { Geist, Geist_Mono, Outfit } from "next/font/google";
import { Toaster } from "@/components/ui/sonner";
import { temaOku } from "@/lib/tema";
import "./globals.css";

// latin-ext: ğ, ş, ı, İ gibi Türkçe harfler için gerekli
const geistSans = Geist({
  variable: "--font-sans",
  subsets: ["latin", "latin-ext"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin", "latin-ext"],
});

// Başlıklar için yuvarlak hatlı, sade bir yazı tipi
const outfit = Outfit({
  variable: "--font-baslik",
  subsets: ["latin", "latin-ext"],
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
      className={`${geistSans.variable} ${geistMono.variable} ${outfit.variable} h-full antialiased ${tema === "koyu" ? "dark" : ""}`}
    >
      <body className="flex min-h-full flex-col">
        {children}
        {/* Yazma işlemlerinden sonra çıkan kısa bildirimler */}
        <Toaster position="top-right" theme={tema === "koyu" ? "dark" : "light"} />
      </body>
    </html>
  );
}
