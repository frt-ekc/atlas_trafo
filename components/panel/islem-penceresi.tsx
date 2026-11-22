"use client";

import { startTransition, useActionState, useState, type ReactNode } from "react";
import { toast } from "sonner";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { BOS_SONUC, type Islem } from "@/lib/islem-sonucu";

type Ozellikler = {
  dugme: string; // pencereyi açan düğmenin yazısı
  dugmeTuru?: "default" | "outline" | "secondary" | "destructive" | "ghost";
  baslik: string;
  aciklama?: ReactNode;
  onay: string; // penceredeki gönder düğmesinin yazısı
  onayTuru?: "default" | "destructive";
  islem: Islem; // Server Action
  gizli?: Record<string, string | number>; // forma gizli alan olarak eklenir (ör. kayıt no)
  children?: ReactNode; // form alanları
};

// Bir yazma işlemini onay penceresinde yapar: düğme → pencere → form → Server Action.
// Başarılıysa pencere kapanır ve sağ üstte kısa bir bildirim çıkar; sayfa sunucuda yenilenir.
// Hata olursa pencere açık kalır ve veritabanının mesajı pencerenin içinde gösterilir.
export function IslemPenceresi(o: Ozellikler) {
  const [acik, setAcik] = useState(false);
  // Pencere her açıldığında form sıfırdan başlasın (eski hata mesajı kalmasın)
  const [acilis, setAcilis] = useState(0);

  return (
    <Dialog
      open={acik}
      onOpenChange={(yeni) => {
        if (yeni) setAcilis((n) => n + 1);
        setAcik(yeni);
      }}
    >
      <DialogTrigger render={<Button size="sm" variant={o.dugmeTuru ?? "outline"} />}>{o.dugme}</DialogTrigger>
      {/* Uzun formlarda pencere ekrandan taşmasın, kendi içinde kaysın */}
      <DialogContent className="max-h-[calc(100dvh-2rem)] overflow-y-auto">
        <IcForm key={acilis} {...o} kapat={() => setAcik(false)} />
      </DialogContent>
    </Dialog>
  );
}

function IcForm({ baslik, aciklama, onay, onayTuru, islem, gizli, children, kapat }: Ozellikler & { kapat: () => void }) {
  const [sonuc, gonder, bekliyor] = useActionState(async (onceki: Parameters<Islem>[0], form: FormData) => {
    const yeni = await islem(onceki, form);
    if (yeni.durum === "tamam") {
      kapat();
      if (yeni.uyari) toast.warning(yeni.mesaj, { duration: 15000 });
      else toast.success(yeni.mesaj);
    }
    return yeni;
  }, BOS_SONUC);

  return (
    <form
      // action={gonder} yerine onSubmit: React form gönderilince alanları boşaltır,
      // hata durumunda kullanıcının yazdıkları silinmesin diye form elle gönderilir.
      onSubmit={(e) => {
        e.preventDefault();
        const veri = new FormData(e.currentTarget);
        startTransition(() => gonder(veri));
      }}
      className="flex flex-col gap-4"
    >
      <DialogHeader>
        <DialogTitle>{baslik}</DialogTitle>
        {aciklama && <DialogDescription>{aciklama}</DialogDescription>}
      </DialogHeader>

      {gizli && Object.entries(gizli).map(([ad, deger]) => <input key={ad} type="hidden" name={ad} value={deger} />)}
      {children}

      {sonuc.durum === "hata" && (
        <Alert variant="destructive" aria-live="assertive">
          <AlertDescription>{sonuc.mesaj}</AlertDescription>
        </Alert>
      )}

      <DialogFooter>
        <DialogClose render={<Button type="button" variant="outline" />}>Vazgeç</DialogClose>
        <Button type="submit" variant={onayTuru ?? "default"} disabled={bekliyor}>
          {bekliyor ? "Kaydediliyor…" : onay}
        </Button>
      </DialogFooter>
    </form>
  );
}

// Penceredeki bir form alanı: etiket + alan + isteğe bağlı açıklama
export function Alan({ etiket, htmlFor, ipucu, children }: { etiket: string; htmlFor: string; ipucu?: ReactNode; children: ReactNode }) {
  return (
    <div className="flex flex-col gap-1.5">
      <label htmlFor={htmlFor} className="text-sm font-medium">{etiket}</label>
      {children}
      {ipucu && <p className="text-xs text-muted-foreground">{ipucu}</p>}
    </div>
  );
}
