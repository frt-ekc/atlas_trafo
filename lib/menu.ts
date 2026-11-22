import type { Rol } from "@/lib/oturum";

export type MenuOgesi = { baslik: string; yol: string };

const ANA_SAYFA: MenuOgesi = { baslik: "Ana sayfa", yol: "/" };
const SORULAR: MenuOgesi = { baslik: "Sorular", yol: "/sorular" };
const SORULARIM: MenuOgesi = { baslik: "Sorularım", yol: "/sorular" };
const UYARILAR: MenuOgesi = { baslik: "Uyarılar", yol: "/uyarilar" };
const ITIRAZLAR: MenuOgesi = { baslik: "İtirazlar", yol: "/itirazlar" };
const PUANTAJ: MenuOgesi = { baslik: "Puantaj", yol: "/puantaj" };
const VARDIYA_PLANI: MenuOgesi = { baslik: "Vardiya planı", yol: "/vardiya-plani" };
const FAZLA_MESAI: MenuOgesi = { baslik: "Fazla mesai", yol: "/fazla-mesai" };
const CALISANLAR: MenuOgesi = { baslik: "Çalışanlar", yol: "/calisanlar" };
const GECICI_KARTLAR: MenuOgesi = { baslik: "Geçici kartlar", yol: "/gecici-kartlar" };
const IZINLER: MenuOgesi = { baslik: "İzinler", yol: "/izinler" };
const DEPARTMANLAR: MenuOgesi = { baslik: "Departmanlar", yol: "/departmanlar" };
const ISG: MenuOgesi = { baslik: "İSG", yol: "/isg" };
const KULLANICILAR: MenuOgesi = { baslik: "Kullanıcılar", yol: "/kullanicilar" };
const AYARLAR: MenuOgesi = { baslik: "Ayarlar", yol: "/ayarlar" };
const VERI_AKTARIMI: MenuOgesi = { baslik: "Veri aktarımı", yol: "/veri-aktarimi" };

// Her rol yalnızca kendi menüsünü görür. Yeni ekran eklendikçe buraya satır eklenir.
// Sayfaların kendisi de rolGerekli(...) ile aynı listeyi kontrol eder.
// Not: menüde görünmemek yetki değildir; asıl kontrol veritabanında (RLS) yapılır.
export const MENU: Record<Rol, MenuOgesi[]> = {
  amir: [ANA_SAYFA, SORULARIM, ITIRAZLAR, VARDIYA_PLANI, FAZLA_MESAI, DEPARTMANLAR, CALISANLAR],
  ik: [ANA_SAYFA, UYARILAR, SORULAR, ITIRAZLAR, PUANTAJ, IZINLER, VARDIYA_PLANI, FAZLA_MESAI, DEPARTMANLAR, CALISANLAR, GECICI_KARTLAR, ISG, VERI_AKTARIMI],
  guvenlik: [ANA_SAYFA, GECICI_KARTLAR, CALISANLAR],
  yonetici: [ANA_SAYFA, DEPARTMANLAR, UYARILAR, SORULAR, ITIRAZLAR, VARDIYA_PLANI, FAZLA_MESAI, CALISANLAR, GECICI_KARTLAR, ISG, VERI_AKTARIMI],
  isg: [ANA_SAYFA, ISG, UYARILAR, CALISANLAR],
  // Sistem yöneticisi çalışan kayıtlarını (gün, izin, puantaj) görmez; yalnızca kullanıcı ve ayar yönetir
  admin: [ANA_SAYFA, KULLANICILAR, AYARLAR, CALISANLAR],
};
