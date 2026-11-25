import type { Rol } from "@/lib/oturum";

// Simge adı metin olarak tutulur: menü sunucudan tarayıcı bileşenine geçerken
// fonksiyon (simge bileşeni) taşınamaz. Ad → simge eşlemesi menu-baglantisi.tsx'te.
export type MenuSimgesi =
  | "ana"
  | "uyari"
  | "soru"
  | "itiraz"
  | "puantaj"
  | "izin"
  | "vardiya"
  | "mesai"
  | "departman"
  | "calisan"
  | "kart"
  | "isg"
  | "aktarim"
  | "kullanici"
  | "ayar";

export type MenuGrubu = "Genel" | "Günlük işler" | "Planlama" | "Kayıtlar" | "Yönetim";
const GRUP_SIRASI: MenuGrubu[] = ["Genel", "Günlük işler", "Planlama", "Kayıtlar", "Yönetim"];

export type MenuOgesi = { baslik: string; yol: string; simge: MenuSimgesi; grup: MenuGrubu };

const ANA_SAYFA: MenuOgesi = { baslik: "Ana sayfa", yol: "/", simge: "ana", grup: "Genel" };
const DEPARTMANLAR: MenuOgesi = { baslik: "Departmanlar", yol: "/departmanlar", simge: "departman", grup: "Genel" };
const UYARILAR: MenuOgesi = { baslik: "Uyarılar", yol: "/uyarilar", simge: "uyari", grup: "Günlük işler" };
const SORULAR: MenuOgesi = { baslik: "Sorular", yol: "/sorular", simge: "soru", grup: "Günlük işler" };
const SORULARIM: MenuOgesi = { ...SORULAR, baslik: "Sorularım" };
const ITIRAZLAR: MenuOgesi = { baslik: "İtirazlar", yol: "/itirazlar", simge: "itiraz", grup: "Günlük işler" };
const GECICI_KARTLAR: MenuOgesi = { baslik: "Geçici kartlar", yol: "/gecici-kartlar", simge: "kart", grup: "Günlük işler" };
const VARDIYA_PLANI: MenuOgesi = { baslik: "Vardiya planı", yol: "/vardiya-plani", simge: "vardiya", grup: "Planlama" };
const FAZLA_MESAI: MenuOgesi = { baslik: "Fazla mesai", yol: "/fazla-mesai", simge: "mesai", grup: "Planlama" };
const IZINLER: MenuOgesi = { baslik: "İzinler", yol: "/izinler", simge: "izin", grup: "Planlama" };
const CALISANLAR: MenuOgesi = { baslik: "Çalışanlar", yol: "/calisanlar", simge: "calisan", grup: "Kayıtlar" };
const PUANTAJ: MenuOgesi = { baslik: "Puantaj", yol: "/puantaj", simge: "puantaj", grup: "Kayıtlar" };
const ISG: MenuOgesi = { baslik: "İSG", yol: "/isg", simge: "isg", grup: "Kayıtlar" };
const VERI_AKTARIMI: MenuOgesi = { baslik: "Veri aktarımı", yol: "/veri-aktarimi", simge: "aktarim", grup: "Kayıtlar" };
const KULLANICILAR: MenuOgesi = { baslik: "Kullanıcılar", yol: "/kullanicilar", simge: "kullanici", grup: "Yönetim" };
const AYARLAR: MenuOgesi = { baslik: "Ayarlar", yol: "/ayarlar", simge: "ayar", grup: "Yönetim" };

// Her rol yalnızca kendi menüsünü görür. Yeni ekran eklendikçe buraya satır eklenir.
// Sayfaların kendisi de rolGerekli(...) ile aynı listeyi kontrol eder.
// Not: menüde görünmemek yetki değildir; asıl kontrol veritabanında (RLS) yapılır.
export const MENU: Record<Rol, MenuOgesi[]> = {
  amir: [ANA_SAYFA, SORULARIM, ITIRAZLAR, VARDIYA_PLANI, FAZLA_MESAI, DEPARTMANLAR, CALISANLAR],
  ik: [ANA_SAYFA, UYARILAR, SORULAR, ITIRAZLAR, PUANTAJ, IZINLER, VARDIYA_PLANI, FAZLA_MESAI, DEPARTMANLAR, CALISANLAR, GECICI_KARTLAR, ISG, VERI_AKTARIMI, KULLANICILAR],
  guvenlik: [ANA_SAYFA, GECICI_KARTLAR, CALISANLAR],
  yonetici: [ANA_SAYFA, DEPARTMANLAR, UYARILAR, SORULAR, ITIRAZLAR, VARDIYA_PLANI, FAZLA_MESAI, CALISANLAR, GECICI_KARTLAR, ISG, VERI_AKTARIMI],
  isg: [ANA_SAYFA, ISG, UYARILAR, CALISANLAR],
  // Sistem yöneticisi çalışan kayıtlarını (gün, izin, puantaj) görmez; yalnızca kullanıcı ve ayar yönetir
  admin: [ANA_SAYFA, KULLANICILAR, AYARLAR, CALISANLAR],
};

// Kenar çubuğu için: rolün menüsü gruplara ayrılır (boş grup gösterilmez).
export function gruplanmisMenu(rol: Rol): { grup: MenuGrubu; ogeler: MenuOgesi[] }[] {
  return GRUP_SIRASI.map((grup) => ({ grup, ogeler: MENU[rol].filter((o) => o.grup === grup) })).filter(
    (g) => g.ogeler.length > 0,
  );
}
