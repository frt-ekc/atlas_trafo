import "server-only";
import { saat, tarih, tarihSaat } from "@/lib/bicim";
import { gunEkle } from "@/lib/hafta";
import type { Rol } from "@/lib/oturum";
import { ayAdi } from "@/lib/puantaj";
import { tumSatirlar } from "@/lib/supabase/sayfali";
import type { sunucuIstemcisi } from "@/lib/supabase/server";

// Bir çalışanın bir aylık dökümü. Detay sayfası ve PDF aynı veriyi kullanır;
// böylece ekranda görünen ile çalışana verilen belge hiçbir zaman ayrışmaz.

type Istemci = Awaited<ReturnType<typeof sunucuIstemcisi>>;

export type DokumGunu = {
  tarih: string;
  tarihMetni: string; // "26.11.2026"
  gunAdi: string; // "Per"
  haftaSonu: boolean;
  tatil: string | null;
  vardiya: string | null; // "Gündüz (08-17)"
  vardiyaKod: string | null;
  planNotu: string | null; // geriye dönük değişiklik vb.
  izin: string | null;
  fazlaMesai: string | null;
  geciciKart: string | null;
  giris: string | null;
  cikis: string | null;
  girisKaynagi: string | null;
  cikisKaynagi: string | null;
  durum: string | null;
  durumKodu: string | null; // renk için ham durum (rapor İK dışına "izinli" görünür)
  gunKaydiId: number | null; // itiraz ve düzeltme bu kayda bağlanır
  girisZamani: string | null; // ham değer (düzeltme penceresinin varsayılanı)
  cikisZamani: string | null;
  planliBaslangic: string | null;
  planliBitis: string | null;
  calismaDk: number | null;
  gecKalmaDk: number | null;
  erkenCikisDk: number | null;
};

export type DokumDuzeltmesi = {
  gun: string;
  alan: string;
  eski: string;
  yeni: string;
  gerekce: string;
  kaynak: string;
  yapan: string;
  zaman: string;
  aleyhine: boolean;
};

export type Dokum = {
  calisan: {
    id: number; sicil: string; adSoyad: string; bolum: string; iseGiris: string; aktif: boolean; kart: string | null;
    iseGirisTarihi: string; // "2026-12-01" (karşılaştırma için)
    cikis: string | null; // "25.11.2026"
  };
  ay: string;
  ayMetni: string;
  gunler: DokumGunu[];
  duzeltmeler: DokumDuzeltmesi[];
  ozet: { planliGun: number; izinliGun: number; calismaDk: number; fazlaMesaiDk: number; gunKaydi: number };
  hazirlanma: string;
};

const GUN_ADI = ["Paz", "Pzt", "Sal", "Çar", "Per", "Cum", "Cmt"];

const IZIN_TURU: Record<string, string> = {
  yillik: "Yıllık izin",
  rapor: "Rapor",
  mazeret: "Mazeret izni",
  ucretsiz: "Ücretsiz izin",
  diger: "İzinli",
};

const DURUM: Record<string, string> = {
  tamam: "Tamam",
  eksik: "Eksik kayıt",
  soru_bekliyor: "Amire soruldu",
  izinli: "İzinli",
  raporlu: "Raporlu",
  tatil: "Tatil",
  vardiya_yok: "Plan yok",
  devamsiz_suphesi: "Devamsızlık şüphesi",
  devamsiz: "Devamsız",
};

const KAYIT_KAYNAGI: Record<string, string> = { pdks: "PDKS", kanit: "Kanıt", amir: "Amir", ik: "İK" };
const DUZELTME_ALANI: Record<string, string> = { giris_zamani: "Giriş", cikis_zamani: "Çıkış", vardiya_id: "Vardiya", durum: "Durum" };
const DUZELTME_KAYNAGI: Record<string, string> = { gece_isi: "Gece işi", amir: "Amir", ik: "İK" };

// Sağlık verisi (rapor) yalnızca İK'ya açıktır; diğer rollere "İzinli" görünür.
function izinEtiketi(tur: string, ikMi: boolean): string {
  return ikMi ? (IZIN_TURU[tur] ?? "İzinli") : "İzinli";
}
function durumEtiketi(durum: string, ikMi: boolean): string {
  if (durum === "raporlu" && !ikMi) return "İzinli";
  return DURUM[durum] ?? durum;
}

// Çalışan görünmüyorsa (yok ya da RLS izin vermiyor) null döner.
export async function aylikDokum(supabase: Istemci, calisanId: number, ay: string, rol: Rol): Promise<Dokum | null> {
  const ikMi = rol === "ik";
  const tumunuGorur = rol === "ik" || rol === "yonetici";
  const ayBasi = `${ay}-01`;
  const sonrakiAy = `${gunEkle(ayBasi, 31).slice(0, 7)}-01`;
  const aySonu = gunEkle(sonrakiAy, -1);

  const calisanSonucu = await supabase
    .from("calisan")
    .select("id, sicil_no, ad, soyad, ise_giris_tarihi, isten_cikis_tarihi, aktif, departman:departman_id(ad)")
    .eq("id", calisanId)
    .maybeSingle();
  if (calisanSonucu.error) throw new Error(`Çalışan okunamadı: ${calisanSonucu.error.message}`);
  const c = calisanSonucu.data as unknown as {
    id: number; sicil_no: string; ad: string; soyad: string; ise_giris_tarihi: string; isten_cikis_tarihi: string | null; aktif: boolean; departman: { ad: string } | null;
  } | null;
  if (!c) return null;

  type Plan = { tarih: string; ik_onay_durumu: string; aciklama: string | null; vardiya: { kod: string; ad: string } | null };
  type Izin = { tur: string; baslangic: string; bitis: string };
  type Fm = { is_gunu: string; planli_dk: number; durum: string };
  type Zimmet = { verilis_zamani: string; iade_zamani: string | null; kart: { kart_no: string } | null };
  type Gun = {
    id: number; is_gunu: string; planli_baslangic: string | null; planli_bitis: string | null; giris_zamani: string | null; cikis_zamani: string | null; giris_kaynagi: string | null; cikis_kaynagi: string | null;
    durum: string; calisma_dk: number | null; gec_kalma_dk: number | null; erken_cikis_dk: number | null; fazla_mesai_dk: number | null;
  };
  type Duz = {
    is_gunu: string; alan: string; eski_deger: string | null; yeni_deger: string | null; gerekce: string; kaynak: string;
    calisan_aleyhine: boolean; yapilma_zamani: string; yapan: { ad_soyad: string } | null;
  };

  const sayfali = <T,>(tablo: string, alanlar: string, tarihSutunu: string) =>
    tumSatirlar<T>((bas, son) =>
      supabase.from(tablo).select(alanlar).eq("calisan_id", calisanId).gte(tarihSutunu, ayBasi).lte(tarihSutunu, aySonu).order("id").range(bas, son),
    );

  const [planlar, izinler, fmler, zimmetler, gunKayitlari, duzeltmeler, tatilSonucu, kartSonucu] = await Promise.all([
    sayfali<Plan>("vardiya_plani", "tarih, ik_onay_durumu, aciklama, vardiya:vardiya_id(kod, ad)", "tarih"),
    // İptal edilen izinler silinmez: izin tablosunda süzülür, v_izin_amir onları zaten göstermez.
    tumSatirlar<Izin>((bas, son) => {
      const q = ikMi
        ? supabase.from("izin").select("tur, baslangic, bitis").is("iptal_zamani", null)
        : supabase.from("v_izin_amir").select("tur, baslangic, bitis");
      return q.eq("calisan_id", calisanId).lte("baslangic", aySonu).gte("bitis", ayBasi).order("id").range(bas, son);
    }),
    sayfali<Fm>("fazla_mesai_plani", "is_gunu, planli_dk, durum", "is_gunu"),
    // Geçici kart zimmetini amir göremez (RLS); yalnızca İK ve yönetici için okunur.
    tumunuGorur
      ? tumSatirlar<Zimmet>((bas, son) =>
          supabase
            .from("gecici_kart_zimmet")
            .select("verilis_zamani, iade_zamani, kart:gecici_kart_id(kart_no)")
            .eq("calisan_id", calisanId)
            .lt("verilis_zamani", `${sonrakiAy}T00:00:00+03:00`)
            .or(`iade_zamani.is.null,iade_zamani.gte.${ayBasi}T00:00:00+03:00`)
            .order("id")
            .range(bas, son),
        )
      : Promise.resolve([] as Zimmet[]),
    sayfali<Gun>(
      "gun_kaydi",
      "id, is_gunu, planli_baslangic, planli_bitis, giris_zamani, cikis_zamani, giris_kaynagi, cikis_kaynagi, durum, calisma_dk, gec_kalma_dk, erken_cikis_dk, fazla_mesai_dk",
      "is_gunu",
    ),
    // Amir düzeltmeyi yalnızca v_duzeltme_amir'den okur: durum ve izin düzeltmelerinin gerekçesi
    // orada gizlidir, "raporlu" yerine "izinli" gelir (T-12). Tabloyu RLS zaten vermez.
    sayfali<Duz>(
      tumunuGorur ? "duzeltme" : "v_duzeltme_amir",
      "is_gunu, alan, eski_deger, yeni_deger, gerekce, kaynak, calisan_aleyhine, yapilma_zamani, yapan:kullanici!yapan_id(ad_soyad)",
      "is_gunu",
    ),
    supabase.from("resmi_tatil").select("tarih, ad").gte("tarih", ayBasi).lte("tarih", aySonu),
    tumunuGorur
      ? supabase.from("kart").select("kart_no").eq("calisan_id", calisanId).eq("durum", "aktif").maybeSingle()
      : Promise.resolve(null),
  ]);
  if (tatilSonucu.error) throw new Error(`Resmi tatiller okunamadı: ${tatilSonucu.error.message}`);

  const planByGun = new Map(planlar.map((p) => [p.tarih, p]));
  const fmByGun = new Map(fmler.map((f) => [f.is_gunu, f]));
  const kayitByGun = new Map(gunKayitlari.map((g) => [g.is_gunu, g]));
  const tatilByGun = new Map((tatilSonucu.data ?? []).map((t) => [t.tarih as string, t.ad as string]));
  const istanbulGunu = (z: string) => new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Istanbul" }).format(new Date(z));

  const gunler: DokumGunu[] = [];
  for (let t = ayBasi; t <= aySonu; t = gunEkle(t, 1)) {
    const haftaninGunu = new Date(`${t}T12:00:00Z`).getUTCDay();
    const p = planByGun.get(t);
    const izin = izinler.find((i) => i.baslangic <= t && t <= i.bitis);
    const fm = fmByGun.get(t);
    const k = kayitByGun.get(t);
    const z = zimmetler.find((x) => istanbulGunu(x.verilis_zamani) <= t && (!x.iade_zamani || istanbulGunu(x.iade_zamani) >= t));

    gunler.push({
      tarih: t,
      tarihMetni: tarih(t),
      gunAdi: GUN_ADI[haftaninGunu],
      haftaSonu: haftaninGunu === 0 || haftaninGunu === 6,
      tatil: tatilByGun.get(t) ?? null,
      vardiya: p?.vardiya?.ad ?? null,
      vardiyaKod: p?.vardiya?.kod ?? null,
      planNotu:
        p?.ik_onay_durumu === "bekliyor"
          ? `Geriye dönük değişiklik, İK onayı bekliyor${p.aciklama ? `: ${p.aciklama}` : ""}`
          : p?.ik_onay_durumu === "reddedildi"
            ? "Geriye dönük değişiklik reddedildi"
            : null,
      izin: izin ? izinEtiketi(izin.tur, ikMi) : null,
      fazlaMesai: fm ? `${Math.round((fm.planli_dk / 60) * 10) / 10} sa ${fm.durum === "onaylandi" ? "(onaylı)" : "(talep)"}`.replace(".", ",") : null,
      geciciKart: z?.kart?.kart_no ?? null,
      giris: k?.giris_zamani ? saat(k.giris_zamani) : null,
      cikis: k?.cikis_zamani ? saat(k.cikis_zamani) : null,
      girisKaynagi: k?.giris_kaynagi ? KAYIT_KAYNAGI[k.giris_kaynagi] : null,
      cikisKaynagi: k?.cikis_kaynagi ? KAYIT_KAYNAGI[k.cikis_kaynagi] : null,
      durum: k ? durumEtiketi(k.durum, ikMi) : null,
      durumKodu: k ? (k.durum === "raporlu" && !ikMi ? "izinli" : k.durum) : null,
      gunKaydiId: k?.id ?? null,
      girisZamani: k?.giris_zamani ?? null,
      cikisZamani: k?.cikis_zamani ?? null,
      planliBaslangic: k?.planli_baslangic ?? null,
      planliBitis: k?.planli_bitis ?? null,
      calismaDk: k?.calisma_dk ?? null,
      gecKalmaDk: k?.gec_kalma_dk ?? null,
      erkenCikisDk: k?.erken_cikis_dk ?? null,
    });
  }

  // Düzeltme değerleri metin olarak saklanır; "durum" alanında rapor bilgisi İK dışına gösterilmez.
  const degerGoster = (alan: string, deger: string | null) => {
    if (!deger) return "—";
    if (alan === "durum") return durumEtiketi(deger, ikMi);
    if (alan.endsWith("_zamani") && !Number.isNaN(Date.parse(deger))) return tarihSaat(deger);
    return deger;
  };

  return {
    calisan: {
      id: c.id,
      sicil: c.sicil_no,
      adSoyad: `${c.ad} ${c.soyad}`,
      bolum: c.departman?.ad ?? "—",
      iseGiris: tarih(c.ise_giris_tarihi),
      iseGirisTarihi: c.ise_giris_tarihi,
      cikis: c.isten_cikis_tarihi ? tarih(c.isten_cikis_tarihi) : null,
      aktif: c.aktif,
      kart: (kartSonucu?.data as { kart_no: string } | null)?.kart_no ?? null,
    },
    ay,
    ayMetni: ayAdi(ay),
    gunler,
    duzeltmeler: duzeltmeler.map((d) => ({
      gun: tarih(d.is_gunu),
      alan: DUZELTME_ALANI[d.alan] ?? d.alan,
      eski: degerGoster(d.alan, d.eski_deger),
      yeni: degerGoster(d.alan, d.yeni_deger),
      gerekce: d.gerekce,
      kaynak: DUZELTME_KAYNAGI[d.kaynak] ?? d.kaynak,
      yapan: d.yapan?.ad_soyad ?? (d.kaynak === "gece_isi" ? "Sistem" : "—"),
      zaman: tarihSaat(d.yapilma_zamani),
      aleyhine: d.calisan_aleyhine,
    })),
    ozet: {
      planliGun: gunler.filter((g) => g.vardiya && !g.izin).length,
      izinliGun: gunler.filter((g) => g.izin && !g.haftaSonu).length,
      calismaDk: gunKayitlari.reduce((t, g) => t + (g.calisma_dk ?? 0), 0),
      fazlaMesaiDk: gunKayitlari.reduce((t, g) => t + (g.fazla_mesai_dk ?? 0), 0),
      gunKaydi: gunKayitlari.length,
    },
    hazirlanma: tarihSaat(new Date().toISOString()),
  };
}
