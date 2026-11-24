// Veritabanındaki kodların ekrandaki Türkçe karşılıkları.
// Kod listeleri migration'lardaki CHECK kısıtlarıyla aynıdır; yeni kod eklenirse buraya da eklenir.

export const SORU_TURU: Record<string, string> = {
  giris_yok: "Giriş kaydı yok",
  kanit_vardiya_sonrasi: "Giriş vardiya başından sonra",
  cikis_yok: "Çıkış kaydı yok",
  hic_kayit_yok: "Hiç kayıt yok",
  ariza_kaniti_yok: "Okuyucu arızası, kanıt yok",
  vardiya_uyusmazligi: "Okutmalar başka vardiyaya uyuyor",
};

export const SORU_DURUMU: Record<string, { ad: string; tur: "default" | "secondary" | "destructive" | "outline" }> = {
  acik: { ad: "Cevap bekliyor", tur: "default" },
  eskale: { ad: "Üst amire gitti", tur: "destructive" },
  cevaplandi: { ad: "Cevaplandı", tur: "secondary" },
  ik_karari_bekliyor: { ad: "İK kararı bekliyor", tur: "default" },
  kapandi: { ad: "Kapandı", tur: "outline" },
};

export const SORU_CEVABI: Record<string, string> = {
  geldi_saat_dogru: "Geldi, önerilen saat doğru",
  geldi_saat_farkli: "Geldi, saat farklı",
  kart_unuttu: "Kartını unuttu",
  gelmedi: "Gelmedi (İK karar verir)",
  bilmiyorum: "Bilmiyorum",
};

export const UYARI_TURU: Record<string, string> = {
  iptal_kart_okutma: "İptal edilmiş kart okutuldu",
  sik_kart_unutma: "Sık kart unutma",
  ariza_suphesi: "Okuyucu arıza şüphesi",
  soru_eskale: "Cevapsız soru üst amire gitti",
  gece_isi_calismadi: "Gece işi çalışmadı",
  dosya_gelmedi: "Dosya gelmedi",
  geriye_donuk_vardiya: "Geriye dönük vardiya değişikliği",
  fm_onay_yok: "Yazılı onay olmadan fazla çalışma",
  fm_plansiz_calisma: "Plansız fazla çalışma",
  fm_gunluk_sinir_asildi: "Günlük 11 saat aşıldı",
  fm_yillik_sinir_yaklasti: "Yıllık fazla mesai sınırına yaklaştı",
  fm_onay_geri_alindi: "Fazla mesai onayı geri alındı",
  gecici_kart_cakisma: "Geçici kart ve asıl kart birlikte okutuldu",
  gecici_kart_zimmetsiz: "Zimmetsiz geçici kart okutuldu",
  gecici_kart_iade_edilmedi: "Geçici kart iade edilmedi",
  kart_paylasim_suphesi: "Kart paylaşımı şüphesi",
  gece_calisma_siniri_asildi: "Gece çalışma sınırı aşıldı",
  fm_yillik_sinir_asildi: "Yıllık fazla mesai sınırı aşıldı",
  isg_belgesi_yok: "İSG belgesi kaydı yok",
  isg_belgesi_suresi_dolmus: "İSG belgesinin süresi dolmuş",
  isg_belgesi_suresi_doluyor: "İSG belgesinin süresi doluyor",
  yetkisiz_bolge_okutmasi: "Yetkisiz bölgeye giriş",
  puantaj_ayari_degisti: "Puantajı etkileyen ayar değişti",
};

// Uyarı özetinde türler konuya göre gruplanır. Listede olmayan tür "Diğer" altında görünür.
export const UYARI_KONULARI: { ad: string; turler: string[] }[] = [
  { ad: "Soru ve vardiya", turler: ["soru_eskale", "geriye_donuk_vardiya"] },
  {
    ad: "Kart",
    turler: [
      "kart_paylasim_suphesi",
      "sik_kart_unutma",
      "iptal_kart_okutma",
      "gecici_kart_iade_edilmedi",
      "gecici_kart_cakisma",
      "gecici_kart_zimmetsiz",
    ],
  },
  {
    ad: "Çalışma süresi",
    turler: [
      "fm_plansiz_calisma",
      "fm_onay_yok",
      "fm_onay_geri_alindi",
      "fm_gunluk_sinir_asildi",
      "fm_yillik_sinir_yaklasti",
      "fm_yillik_sinir_asildi",
      "gece_calisma_siniri_asildi",
    ],
  },
  { ad: "Sistem ve cihaz", turler: ["ariza_suphesi", "dosya_gelmedi", "gece_isi_calismadi", "puantaj_ayari_degisti"] },
  { ad: "İSG", turler: ["isg_belgesi_yok", "isg_belgesi_suresi_dolmus", "isg_belgesi_suresi_doluyor", "yetkisiz_bolge_okutmasi"] },
];

export const ITIRAZ_DURUMU: Record<string, { ad: string; tur: "default" | "secondary" | "destructive" | "outline" }> = {
  acik: { ad: "Açık", tur: "default" },
  inceleniyor: { ad: "İnceleniyor", tur: "default" },
  kabul: { ad: "Kabul edildi", tur: "secondary" },
  red: { ad: "Reddedildi", tur: "destructive" },
};
