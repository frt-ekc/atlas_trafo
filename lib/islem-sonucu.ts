// Bir yazma işleminin (Server Action) ekrana dönen sonucu.
// Hem sunucuda hem tarayıcıda kullanılır; bu yüzden burada sunucuya özel bir şey yoktur.
export type IslemSonucu =
  | { durum: "bos" } // henüz gönderilmedi
  | { durum: "tamam"; mesaj: string; uyari?: boolean } // uyari: işlem oldu ama dikkat edilecek bir şey var
  | { durum: "hata"; mesaj: string };

export const BOS_SONUC: IslemSonucu = { durum: "bos" };

// Server Action imzası: useActionState önceki sonucu ve form verisini verir.
export type Islem = (onceki: IslemSonucu, form: FormData) => Promise<IslemSonucu>;
