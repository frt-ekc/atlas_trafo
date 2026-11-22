import Link from "next/link";
import { CompassIcon } from "lucide-react";
import { BilgiEkrani } from "@/components/panel/bilgi-ekrani";
import { buttonVariants } from "@/components/ui/button";

export const metadata = { title: "Sayfa bulunamadı" };

// Yanlış adres ya da artık olmayan bir kayıt (ör. silinmiş çalışan numarası) için.
export default function Bulunamadi() {
  return (
    <BilgiEkrani
      simge={<CompassIcon className="size-6" />}
      ust="404"
      baslik="Sayfa bulunamadı"
      aciklama="Aradığınız sayfa ya da kayıt yok. Adres yanlış yazılmış ya da bu kayda erişim yetkiniz olmayabilir."
    >
      <Link href="/" className={buttonVariants()}>
        Ana sayfaya dön
      </Link>
    </BilgiEkrani>
  );
}
