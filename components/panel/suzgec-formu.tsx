"use client";

import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useEffect, useRef, useTransition, type ChangeEvent, type FormEvent, type ReactNode } from "react";
import { cn } from "@/lib/utils";

// Liste ekranlarındaki süzgeç formu. Açılır liste, tarih ya da onay kutusu değişince süzgeç
// kendiliğinden uygulanır; metin aramada Enter ya da düğme yeterli.
// Sayfa baştan yüklenmez: adres çubuğu güncellenir, Next.js yalnızca içeriği yeniden çizer.
// JavaScript kapalıysa sıradan bir GET formu gibi çalışır (method="get").
export function SuzgecFormu({ className, children }: { className?: string; children: ReactNode }) {
  const router = useRouter();
  const adres = usePathname();
  const [bekliyor, gecis] = useTransition();
  const sorguMetni = useSearchParams().toString();
  const formRef = useRef<HTMLFormElement>(null);

  // defaultValue yalnızca ilk çizimde işe yarar. Adres başka yoldan değişirse (özet tablosundaki
  // bağlantı, tarayıcının geri tuşu) açılır listeler sunucunun kullandığı değere uydurulur.
  useEffect(() => {
    for (const liste of formRef.current?.querySelectorAll<HTMLSelectElement>("select[data-varsayilan]") ?? []) {
      liste.value = liste.dataset.varsayilan ?? "";
    }
  }, [sorguMetni, children]);

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
      ref={formRef}
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
