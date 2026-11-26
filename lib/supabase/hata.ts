import type { PostgrestError } from "@supabase/supabase-js";

// Veritabanı hatasının kullanıcıya gösterilecek hâli. Hem sunucuda (rpcCagir) hem tarayıcıda
// (dosya yükleme formu) kullanılır; bu yüzden burada sunucuya özel bir şey yoktur.
// Fonksiyonların kendi hataları (raise exception) Türkçedir ve olduğu gibi gösterilir.
// PostgreSQL'in kendi hataları İngilizce gelir; onlar sade bir Türkçe cümleye çevrilir.
// Bilinen kısıtların kullanıcıya söyleyeceği şey (T-16, T-75, T-86). PostgreSQL kısıtın adını
// İngilizce mesajın içinde verir ("... violates check constraint "fazla_mesai_talep_onay_farkli"");
// genel cümle ("Geçerli bir değer girilmelidir.") yerine ne olduğu ve ne yapılacağı söylenir.
// Veritabanı ileride bu durumları Türkçe raise ile önden yakalarsa o mesaj (P0001) gösterilir; bu liste zararsız kalır.
const KISIT_MESAJI: Record<string, string> = {
  fazla_mesai_talep_onay_farkli:
    "Görevler ayrılığı: Fazla mesai talebini giren kullanıcı onaylayamaz; kararı başka bir İK kullanıcısı vermelidir.",
  fazla_mesai_plani_tek_etkin: "Bu çalışanın bu gün için zaten bir fazla mesai talebi ya da planı var.",
  calisan_sicil_no_key: "Bu sicil numarası başka bir çalışanda kayıtlı.",
  kart_kart_no_key: "Bu kart numarası daha önce tanımlanmış (başka bir çalışanda ya da iptal edilmiş bir kartta). Kart numarasını kontrol edin.",
  kart_tek_aktif: "Çalışanın aktif kartı var; yeni kart tanımlamadan önce mevcut kartı iptal edin.",
  kart_calisan_id_fkey: "Çalışan bulunamadı.",
  kart_iptal_nedeni_check: "İptal nedeni listeden seçilmelidir.",
  gecici_kart_kart_no_key: "Bu geçici kart numarası zaten kayıtlı.",
  zimmet_acik_kart: "Bu geçici kart şu anda başka bir çalışanda; önce iade alınmalıdır.",
  zimmet_acik_calisan: "Bu çalışanda iade edilmemiş bir geçici kart var; önce o kart iade alınmalıdır.",
};

export function hataMesaji(hata: Pick<PostgrestError, "code" | "message">): string {
  // İstek veritabanına hiç varmadıysa kod boştur ("Failed to fetch", "fetch failed")
  if (!hata.code && /fetch|network/i.test(hata.message)) {
    return "Sisteme ulaşılamadı. Lütfen tekrar deneyin.";
  }
  // Adı bilinen bir kısıt ihlali: o duruma özel mesaj
  if (hata.code === "23505" || hata.code === "23514" || hata.code === "23503") {
    const kisit = /"([a-z0-9_]+)"\s*$/.exec(hata.message.trim())?.[1];
    if (kisit && KISIT_MESAJI[kisit]) return KISIT_MESAJI[kisit];
  }
  switch (hata.code) {
    case "P0001": // raise exception: fonksiyonun Türkçe mesajı
      return sadelestir(hata.message);
    case "42501":
      return "Bu işlem için yetkiniz yok.";
    case "23505":
      return "Bu kayıt daha önce eklenmiştir.";
    case "23503":
      return "İlgili kayıt bulunamadı.";
    case "23514":
    case "22P02":
    case "22007":
    case "22008":
      return "Geçerli bir değer girilmelidir.";
    case "PGRST202":
      return "İşlem şu anda yapılamıyor. Sistem yöneticisi ile iletişime geçilmelidir.";
    default:
      // Türkçe karakter içeren mesaj büyük ihtimalle bizim fonksiyonlarımızdan gelir
      return /[çğıöşüÇĞİÖŞÜ]/.test(hata.message) ? sadelestir(hata.message) : "İşlem yapılamadı. Lütfen tekrar deneyin.";
  }
}

// Mesajın sonundaki teknik ek (ör. "(gecici_kart_zimmet.veren_id)") kullanıcıya gösterilmez
function sadelestir(mesaj: string): string {
  return mesaj.replace(/\s*\([a-z_]+\.[a-z_]+\)\.?$/, ".");
}
