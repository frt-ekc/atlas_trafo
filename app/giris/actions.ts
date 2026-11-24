"use server";

import { redirect } from "next/navigation";
import { sunucuIstemcisi } from "@/lib/supabase/server";

export type GirisDurumu = { hata?: string; eposta?: string };

// Giriş formu bu fonksiyonu sunucuda çalıştırır; şifre tarayıcıda saklanmaz.
export async function girisYap(_onceki: GirisDurumu, form: FormData): Promise<GirisDurumu> {
  const eposta = String(form.get("eposta") ?? "").trim();
  const sifre = String(form.get("sifre") ?? "");

  if (!eposta || !sifre) {
    return { hata: "E-posta ve şifre girilmelidir.", eposta };
  }

  const supabase = await sunucuIstemcisi();
  const { error } = await supabase.auth.signInWithPassword({ email: eposta, password: sifre });

  if (error) {
    // Hangi bilginin yanlış olduğunu söylemiyoruz (hesap var mı yok mu belli olmasın).
    return { hata: "E-posta veya şifre hatalı.", eposta };
  }

  redirect("/");
}

export async function cikisYap() {
  const supabase = await sunucuIstemcisi();
  await supabase.auth.signOut();
  redirect("/giris");
}
