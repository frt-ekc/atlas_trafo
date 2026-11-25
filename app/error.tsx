"use client";

import Link from "next/link";
import { TriangleAlertIcon } from "lucide-react";
import { BilgiEkrani } from "@/components/panel/bilgi-ekrani";
import { Button, buttonVariants } from "@/components/ui/button";

// Beklenmeyen bir hata olursa (ör. veritabanına ulaşılamadı) bu ekran görünür.
// Kökte duruyor ki (panel)/layout.tsx içindeki hataları da yakalasın.
// Yayında (production) Next.js hata ayrıntısını tarayıcıya göndermez; yalnızca genel mesaj görünür.
export default function Hata({ error, retry }: { error: unknown; retry: () => void }) {
  const mesaj = error instanceof Error && error.message ? error.message : "Sayfa yüklenemedi.";

  return (
    <BilgiEkrani
      simge={<TriangleAlertIcon className="size-6" />}
      ust="Hata"
      baslik="Sayfa açılamadı"
      aciklama={
        <>
          <p>{mesaj}</p>
          <p className="mt-2">Sayfa yüklenemedi. Sorun devam ederse sistem yöneticisi ile iletişime geçilmelidir.</p>
        </>
      }
    >
      <Button onClick={() => retry()}>Tekrar dene</Button>
      <Link href="/" className={buttonVariants({ variant: "outline" })}>
        Ana sayfaya dön
      </Link>
    </BilgiEkrani>
  );
}
