"use client";

import { usePathname, useRouter } from "next/navigation";
import { useTransition, type ChangeEvent, type FormEvent, type ReactNode } from "react";
import { cn } from "@/lib/utils";

// Liste ekranlarındaki süzgeç formu. Açılır liste, tarih ya da onay kutusu değişince süzgeç
// kendiliğinden uygulanır; metin aramada Enter ya da düğme yeterli.
// Sayfa baştan yüklenmez: adres çubuğu güncellenir, Next.js yalnızca içeriği yeniden çizer.
// JavaScript kapalıysa sıradan bir GET formu gibi çalışır (method="get").
export function SuzgecFormu({ className, children }: { className?: string; children: ReactNode }) {
  const router = useRouter();
  const adres = usePathname();
  const [bekliyor, gecis] = useTransition();

  function uygula(form: HTMLFormElement) {
    const parametreler = new URLSearchParams();
    for (const [ad, deger] of new FormData(form)) {
      // Boş alan adrese yazılmaz (?ara=&bolum= yerine temiz adres)
      if (typeof deger === "string" && deger.trim() !== "") parametreler.append(ad, deger.trim());
    }
    const sorgu = parametreler.toString();
    gecis(() => router.push(sorgu ? `${adres}?${sorgu}` : adres, { scroll: false }));
  }

  function gonder(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    uygula(e.currentTarget);
  }

  function degisti(e: ChangeEvent<HTMLFormElement>) {
    const alan = e.target as unknown as HTMLInputElement | HTMLSelectElement;
    const kendiliginden = alan.tagName === "SELECT" || ["checkbox", "radio", "date", "month", "week"].includes(alan.type);
    if (kendiliginden) uygula(e.currentTarget);
  }

  return (
    <form
      method="get"
      onSubmit={gonder}
      onChange={degisti}
      aria-busy={bekliyor}
      className={cn(className, "transition-opacity", bekliyor && "opacity-60")}
    >
      {children}
    </form>
  );
}
