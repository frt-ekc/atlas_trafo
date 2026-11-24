"use server";

import { revalidatePath } from "next/cache";
import type { IslemSonucu } from "@/lib/islem-sonucu";
import { metinAl, rpcCagir, sayiAl, sicildenCalisan } from "@/lib/supabase/rpc";

const ROLLER = ["amir", "ik", "guvenlik", "yonetici", "isg", "admin"];

// Sistem yöneticisi sisteme girecek kişiyi tanımlar. Giriş hesabı Supabase Auth'ta aynı e-postayla
// açılır; hesap zaten varsa hemen bağlanır. Admin kendine hesap açamaz (görevler ayrılığı).
// Ad soyad yazılmaz: veritabanı onu çalışan kaydından alır (T-105).
export async function kullaniciEkle(_onceki: IslemSonucu, form: FormData): Promise<IslemSonucu> {
  const eposta = metinAl(form, "eposta");
  const rol = metinAl(form, "rol");
  if (!eposta) return { durum: "hata", mesaj: "E-posta adresi girilmelidir." };
  if (!rol || !ROLLER.includes(rol)) return { durum: "hata", mesaj: "Rol seçilmelidir." };

  const bulunan = await sicildenCalisan(form);
  if (!bulunan.tamam) return { durum: "hata", mesaj: bulunan.mesaj };

  const sonuc = await rpcCagir<number>("kullanici_ekle", {
    p_eposta: eposta,
    p_rol: rol,
    p_calisan_id: bulunan.calisan.id,
    p_ust_amir_id: sayiAl(form, "ust_amir_id"),
  });
  if (!sonuc.tamam) return { durum: "hata", mesaj: sonuc.mesaj };
  revalidatePath("/kullanicilar");
  return { durum: "tamam", mesaj: `${bulunan.calisan.adSoyad} kullanıcı olarak tanımlandı. Giriş hesabı aynı e-posta adresiyle oluşturulmalıdır.` };
}

// Rol, üst amir ya da aktiflik değişir; gönderilmeyen alan değişmez. Admin kendi hesabını değiştiremez.
export async function kullaniciGuncelle(_onceki: IslemSonucu, form: FormData): Promise<IslemSonucu> {
  const kullaniciId = sayiAl(form, "kullanici_id");
  const rol = metinAl(form, "rol");
  if (!kullaniciId) return { durum: "hata", mesaj: "Kullanıcı seçilmelidir." };
  if (rol && !ROLLER.includes(rol)) return { durum: "hata", mesaj: "Geçerli bir rol seçilmelidir." };

  const sonuc = await rpcCagir("kullanici_guncelle", {
    p_kullanici_id: kullaniciId,
    p_rol: rol,
    p_ust_amir_id: sayiAl(form, "ust_amir_id"),
    p_aktif: metinAl(form, "aktif") === "evet",
  });
  if (!sonuc.tamam) return { durum: "hata", mesaj: sonuc.mesaj };
  revalidatePath("/kullanicilar");
  return { durum: "tamam", mesaj: "Kullanıcı güncellendi." };
}
