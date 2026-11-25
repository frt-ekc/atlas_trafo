"use client";

import { useActionState } from "react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { girisYap, type GirisDurumu } from "./actions";

export function GirisFormu() {
  // useActionState: formu sunucudaki girisYap'a gönderir, dönen hatayı ekranda tutar.
  const [durum, gonder, bekliyor] = useActionState<GirisDurumu, FormData>(girisYap, {});

  return (
    <form action={gonder} className="flex flex-col gap-4">
      <div className="flex flex-col gap-2">
        <Label htmlFor="eposta">E-posta</Label>
        <Input
          id="eposta"
          name="eposta"
          type="email"
          autoComplete="username"
          defaultValue={durum.eposta}
          required
        />
      </div>
      <div className="flex flex-col gap-2">
        <Label htmlFor="sifre">Şifre</Label>
        <Input id="sifre" name="sifre" type="password" autoComplete="current-password" required />
      </div>

      {durum.hata && (
        <Alert variant="destructive" aria-live="polite">
          <AlertDescription>{durum.hata}</AlertDescription>
        </Alert>
      )}

      <Button type="submit" size="lg" className="mt-1 h-10" disabled={bekliyor}>
        {bekliyor ? "Giriş yapılıyor…" : "Giriş yap"}
      </Button>
    </form>
  );
}
