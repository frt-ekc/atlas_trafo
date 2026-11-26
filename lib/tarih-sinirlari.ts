// Formlardaki tarihlerin makul aralıkları. Yanlışlıkla girilen 2099 ya da 1900 gibi tarihleri
// form gönderilmeden yakalar. Asıl kural veritabanındadır; bu, kullanıcıya erken ve açık mesaj içindir.
// Hem sunucuda hem tarayıcıda kullanılır; tarihler "yyyy-aa-gg" metnidir.

// "yyyy-aa-gg" tarihine yıl ekler (29 Şubat artık olmayan yıla düşerse 1 Mart olur)
export function yilEkle(gun: string, yil: number): string {
  const d = new Date(`${gun}T00:00:00Z`);
  d.setUTCFullYear(d.getUTCFullYear() + yil);
  return d.toISOString().slice(0, 10);
}

// T-75: işe giriş en fazla 1 yıl sonrası, en çok 50 yıl öncesi
export function iseGirisAraligi(bugun: string) {
  return { min: yilEkle(bugun, -50), max: yilEkle(bugun, 1) };
}

// T-87: İSG belgesinin geçerlilik bitişi bugünden ±10 yıl
export function isgBelgeAraligi(bugun: string) {
  return { min: yilEkle(bugun, -10), max: yilEkle(bugun, 10) };
}

// Gösterim için "gg.aa.yyyy"
export const gunMetni = (gun: string) => `${gun.slice(8, 10)}.${gun.slice(5, 7)}.${gun.slice(0, 4)}`;
