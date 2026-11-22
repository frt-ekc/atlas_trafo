import { aramaTemizle } from "@/lib/arama";

// Liste ekranlarındaki ad / sicil araması ekranda (sunucuda, sorgudan sonra) yapılır.
// Yazılan her kelime verilen alanlardan birinde geçmelidir; büyük/küçük harf ve Türkçe İ/ı dikkate alınır.
// Boş aramada her kayıt uyar.
export function aramaSuzgeci(ara: string): (...alanlar: (string | null | undefined)[]) => boolean {
  const kelimeler = aramaTemizle(ara).map((k) => k.toLocaleLowerCase("tr"));
  if (kelimeler.length === 0) return () => true;
  return (...alanlar) => {
    const metin = alanlar.filter(Boolean).join(" ").toLocaleLowerCase("tr");
    return kelimeler.every((k) => metin.includes(k));
  };
}

// Adres çubuğundan gelen tarih (yyyy-aa-gg) geçerliyse kendisi, değilse boş metin
export function tarihParametresi(deger: string): string {
  return /^\d{4}-\d{2}-\d{2}$/.test(deger) ? deger : "";
}

// "yyyy-aa-gg" biçimindeki gün, [bas, bit] aralığında mı (boş uç sınırsız sayılır)
export function aralikta(gun: string | null | undefined, bas: string, bit: string): boolean {
  if (!bas && !bit) return true;
  if (!gun) return false;
  const g = gun.slice(0, 10);
  return (!bas || g >= bas) && (!bit || g <= bit);
}
