import Link from "next/link";
import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { CalisanListesi, type ListeCalisani } from "@/components/panel/calisan-listesi";
import { Alan, IslemPenceresi } from "@/components/panel/islem-penceresi";
import { KararAlanlari } from "@/components/panel/karar-alanlari";
import { Secim } from "@/components/panel/secim";
import { vardiyaAdi } from "@/components/panel/vardiya-etiketi";
import { aramaSuzgeci } from "@/components/liste/arama";
import { BosDurum } from "@/components/liste/bos-durum";
import { DurumIslem } from "@/components/liste/durum-islem";
import { FiltreAlani, FiltreCubugu } from "@/components/liste/filtre-cubugu";
import { Sekmeler } from "@/components/liste/sekmeler";
import { TabloKutusu } from "@/components/liste/tablo-kutusu";
import { Zaman } from "@/components/liste/zaman";
import { tekDeger } from "@/lib/arama";
import { sureMetni, tarih } from "@/lib/bicim";
import { bugun } from "@/lib/hafta";
import { rolGerekli } from "@/lib/oturum";
import { tumSatirlar } from "@/lib/supabase/sayfali";
import { sunucuIstemcisi } from "@/lib/supabase/server";
import { cn } from "@/lib/utils";
import { fazlaMesaiKarar, fazlaMesaiTalepEt, havuzKarari, yaziliOnayGeriAl, yaziliOnayGir } from "./actions";

export const metadata = { title: "Fazla mesai" };

// Veritabanındaki varsayılanlar (ayar tablosu). Amir ayar tablosunu okuyamaz; o zaman bunlar kullanılır.
const VARSAYILAN_YILLIK_SINIR_DK = 16_200; // 270 saat
const VARSAYILAN_YAKLASMA_YUZDE = 80;

type Kisi = { sicil_no: string; ad: string; soyad: string } | null;

type Plan = {
  id: number;
  calisan_id: number;
  is_gunu: string;
  planli_dk: number;
  gerekce: string;
  durum: "talep" | "onaylandi" | "reddedildi" | "iptal";
  talep_zamani: string;
  karar_zamani: string | null;
  karar_aciklama: string | null;
  calisan: Kisi;
  vardiya: { kod: string } | null;
  talep_eden: { ad_soyad: string } | null;
  karar_veren: { ad_soyad: string } | null;
};

// Onaysız fazla mesai havuzu (pdks.fazla_mesai_inceleme): gece işi, plansız çalışılan süreyi buraya koyar
type HavuzKaydi = {
  id: number;
  calisan_id: number;
  is_gunu: string;
  tur: "vardiya_sonrasi" | "tatil_calismasi";
  dakika: number;
  durum: "inceleme_bekliyor" | "onaylandi" | "reddedildi";
  karar_zamani: string | null;
  karar_aciklama: string | null;
  fark_satiri: boolean;
  yazili_onaysiz: boolean;
  yillik_sinir_asildi: boolean;
  calisan: Kisi;
  karar_veren: { ad_soyad: string } | null;
};

const HAVUZ_TURU: Record<HavuzKaydi["tur"], string> = {
  vardiya_sonrasi: "Vardiya sonrası",
  tatil_calismasi: "Pazar / tatil çalışması",
};

const HAVUZ_DURUMU: Record<HavuzKaydi["durum"], { ad: string; tur: "default" | "secondary" | "destructive" }> = {
  inceleme_bekliyor: { ad: "İK kararı bekliyor", tur: "default" },
  onaylandi: { ad: "Onaylandı", tur: "secondary" },
  reddedildi: { ad: "Reddedildi", tur: "destructive" },
};

type Onay = {
  calisan_id: number;
  imza_tarihi: string;
  belge_no: string;
  geri_alma_bildirim_tarihi: string | null;
  gecerlilik_bitisi: string | null;
};

type YillikDurum = {
  calisan_id: number;
  sicil_no: string;
  ad: string;
  soyad: string;
  toplam_dk: number;
  kalan_dk: number;
  sinir_dk: number;
};

type Calisan = { id: number; sicil_no: string; ad: string; soyad: string; departman: { ad: string } | null };

const DURUM: Record<Plan["durum"], { ad: string; tur: "default" | "secondary" | "destructive" | "outline" }> = {
  talep: { ad: "İK kararı bekliyor", tur: "default" },
  onaylandi: { ad: "Onaylandı", tur: "secondary" },
  reddedildi: { ad: "Reddedildi", tur: "destructive" },
  iptal: { ad: "İptal", tur: "outline" },
};

const saat = (dk: number) => `${Math.round((dk / 60) * 10) / 10} sa`.replace(".", ",");

export default async function FazlaMesaiSayfasi({ searchParams }: PageProps<"/fazla-mesai">) {
  const kullanici = await rolGerekli(["amir", "ik", "yonetici"]);
  const parametre = await searchParams;

  const buYil = Number(bugun().slice(0, 4));
  const yil = Number.parseInt(tekDeger(parametre.yil), 10) || buYil;
  const durumSuzgeci = tekDeger(parametre.durum);
  const araMetni = tekDeger(parametre.ara).slice(0, 100);
  const uyar = aramaSuzgeci(araMetni);
  const bugunTarih = bugun();
  // Yazılı onaylar tablosunu yalnızca İK ve yönetici okuyabilir (RLS).
  const onaylariGorur = kullanici.rol !== "amir";
  // Talebi amir ve İK açar; yönetici yalnızca okur
  const talepEdebilir = kullanici.rol === "amir" || kullanici.rol === "ik";

  const supabase = await sunucuIstemcisi();

  const [planlar, ayarSonucu, onaylar, calisanlar, listeCalisanlari, havuz, yillikDurum] = await Promise.all([
    tumSatirlar<Plan>((bas, son) =>
      supabase
        .from("fazla_mesai_plani")
        .select(
          "id, calisan_id, is_gunu, planli_dk, gerekce, durum, talep_zamani, karar_zamani, karar_aciklama, " +
            "calisan:calisan_id(sicil_no, ad, soyad), vardiya:vardiya_id(kod), " +
            "talep_eden:kullanici!talep_eden_id(ad_soyad), karar_veren:kullanici!karar_veren_id(ad_soyad)",
        )
        .gte("is_gunu", `${yil}-01-01`)
        .lte("is_gunu", `${yil}-12-31`)
        .order("is_gunu", { ascending: false })
        .order("id")
        .range(bas, son),
    ),
    onaylariGorur
      ? supabase.from("ayar").select("anahtar, deger").in("anahtar", ["fm_yillik_sinir_dk", "fm_yaklasma_uyari_yuzde"])
      : Promise.resolve(null),
    onaylariGorur
      ? tumSatirlar<Onay>((bas, son) =>
          supabase
            .from("fazla_mesai_onayi")
            .select("calisan_id, imza_tarihi, belge_no, geri_alma_bildirim_tarihi, gecerlilik_bitisi")
            .eq("yil", yil)
            .order("id")
            .range(bas, son),
        )
      : Promise.resolve([] as Onay[]),
    onaylariGorur
      ? tumSatirlar<Calisan>((bas, son) =>
          supabase
            .from("calisan")
            .select("id, sicil_no, ad, soyad, departman:departman_id(ad)")
            .eq("aktif", true)
            .order("sicil_no")
            .range(bas, son),
        )
      : Promise.resolve([] as Calisan[]),
    // Talep penceresindeki sicil önerileri (amir yalnızca kendi bölümünü görür)
    talepEdebilir
      ? tumSatirlar<ListeCalisani>((bas, son) =>
          supabase.from("calisan").select("sicil_no, ad, soyad").eq("aktif", true).order("sicil_no").range(bas, son),
        )
      : Promise.resolve([] as ListeCalisani[]),
    // Amir yalnızca kendi bölümünün kayıtlarını görür (RLS)
    tumSatirlar<HavuzKaydi>((bas, son) =>
      supabase
        .from("fazla_mesai_inceleme")
        .select(
          "id, calisan_id, is_gunu, tur, dakika, durum, karar_zamani, karar_aciklama, fark_satiri, yazili_onaysiz, yillik_sinir_asildi, " +
            "calisan:calisan_id(sicil_no, ad, soyad), karar_veren:kullanici!karar_veren_id(ad_soyad)",
        )
        .gte("is_gunu", `${yil}-01-01`)
        .lte("is_gunu", `${yil}-12-31`)
        .order("is_gunu", { ascending: false })
        .order("id")
        .range(bas, son),
    ),
    tumSatirlar<YillikDurum>((bas, son) =>
      supabase
        .from("v_fazla_mesai_yillik")
        .select("calisan_id, sicil_no, ad, soyad, toplam_dk, kalan_dk, sinir_dk")
        .eq("yil", yil)
        .order("calisan_id")
        .range(bas, son),
    ),
  ]);
  const ik = kullanici.rol === "ik";
  const havuzBekleyen = havuz.filter((h) => h.durum === "inceleme_bekliyor");

  const ayar = new Map((ayarSonucu?.data ?? []).map((a) => [a.anahtar as string, Number(a.deger)]));
  const yillikSinir = ayar.get("fm_yillik_sinir_dk") ?? yillikDurum[0]?.sinir_dk ?? VARSAYILAN_YILLIK_SINIR_DK;
  const yaklasmaYuzde = ayar.get("fm_yaklasma_uyari_yuzde") ?? VARSAYILAN_YAKLASMA_YUZDE;

  // Yıllık durum: toplam ve kalan v_fazla_mesai_yillik'ten gelir (270 saat denetimiyle aynı hesap:
  // onaylı plan + onaylı havuz + tatil çalışması). Bekleyen talepler planlardan eklenir.
  const yillik = new Map<number, { kisi: Kisi; toplamDk: number; kalanDk: number; bekleyenDk: number }>();
  for (const y of yillikDurum) {
    yillik.set(y.calisan_id, { kisi: { sicil_no: y.sicil_no, ad: y.ad, soyad: y.soyad }, toplamDk: y.toplam_dk, kalanDk: y.kalan_dk, bekleyenDk: 0 });
  }
  for (const p of planlar) {
    if (p.durum !== "talep") continue;
    const satir = yillik.get(p.calisan_id) ?? { kisi: p.calisan, toplamDk: 0, kalanDk: yillikSinir, bekleyenDk: 0 };
    satir.bekleyenDk += p.planli_dk;
    yillik.set(p.calisan_id, satir);
  }
  const yillikSatirlar = [...yillik.values()].sort((a, b) => b.toplamDk - a.toplamDk);

  // Yazılı onay: geri alındıysa bildirimden 30 gün sonra geçersiz olur
  const gecerliOnay = new Map(
    onaylar
      .filter((o) => !o.gecerlilik_bitisi || o.gecerlilik_bitisi > bugunTarih)
      .map((o) => [o.calisan_id, o]),
  );
  const geriAlinanlar = onaylar.filter((o) => o.geri_alma_bildirim_tarihi);
  // Havuz kaydında yazılı onay: onaylanan kayıtta karar anındaki işaret, diğerlerinde o günkü durum
  // (veritabanındaki fm_onay_gecerli_mi ile aynı kural). Amir onayları okuyamaz; yalnızca işareti görür.
  const yaziliOnayYok = (h: HavuzKaydi) =>
    h.durum === "onaylandi"
      ? h.yazili_onaysiz
      : onaylariGorur &&
        !onaylar.some(
          (o) =>
            o.calisan_id === h.calisan_id &&
            o.imza_tarihi <= h.is_gunu &&
            (!o.gecerlilik_bitisi || h.is_gunu < o.gecerlilik_bitisi),
        );
  const onaySizlar = calisanlar.filter((c) => !gecerliOnay.has(c.id));

  const bekleyenSayisi = planlar.filter((p) => p.durum === "talep").length;

  // Uzun sayfa sekmelere bölünür; her sekme kendi listesini gösterir (adres: ?sekme=...)
  type SekmeKodu = "planlar" | "havuz" | "yillik" | "onaylar";
  const istenenSekme = tekDeger(parametre.sekme);
  const sekme: SekmeKodu =
    istenenSekme === "havuz" || istenenSekme === "yillik" || (istenenSekme === "onaylar" && onaylariGorur)
      ? istenenSekme
      : "planlar";
  const sekmeAdresi = (k: SekmeKodu) => {
    const p = new URLSearchParams();
    if (yil !== buYil) p.set("yil", String(yil));
    if (k !== "planlar") p.set("sekme", k);
    const sorgu = p.toString();
    return sorgu ? `/fazla-mesai?${sorgu}` : "/fazla-mesai";
  };
  const kisiUyar = (k: Kisi) => uyar(k?.ad, k?.soyad, k?.sicil_no);
  // Durum süzgeci sekmeye göre: planlarda plan durumu, onaysız çalışmada inceleme durumu
  const gosterilenPlanlar = planlar.filter((p) => (!durumSuzgeci || p.durum === durumSuzgeci) && kisiUyar(p.calisan));
  const gosterilenHavuz = havuz.filter((h) => (!durumSuzgeci || h.durum === durumSuzgeci) && kisiUyar(h.calisan));
  const gosterilenYillik = yillikSatirlar.filter((y) => kisiUyar(y.kisi));
  const gosterilenOnaysizlar = onaySizlar.filter((c) => kisiUyar(c));
  const durumSecenekleri: [string, string][] =
    sekme === "planlar"
      ? Object.entries(DURUM).map(([k, d]) => [k, d.ad])
      : sekme === "havuz"
        ? Object.entries(HAVUZ_DURUMU).map(([k, d]) => [k, d.ad])
        : [];
  const suzgecVar = Boolean(araMetni || (durumSecenekleri.length > 0 && durumSuzgeci));

  return (
    <div className="flex flex-col gap-5">
      <div className="flex flex-col gap-1">
        <h1 className="text-2xl font-semibold">Fazla mesai · {yil}</h1>
        <p className="text-sm text-muted-foreground">
          Fazla mesai, amirin talebi ve İK onayı ile planlanır. Yazılı onayı bulunmayan çalışan için plan yapılamaz. Günlük sınır 11 sa, yıllık sınır {saat(yillikSinir)} olarak uygulanır.
        </p>
      </div>

      {talepEdebilir && (
        <div className="flex flex-col gap-2 self-start">
          <IslemPenceresi
            dugme="Talep oluştur"
            dugmeTuru="default"
            baslik="Fazla mesai talebi"
            aciklama="Talep İK onayına gönderilir. Çalışanın ilgili yıla ait yazılı onayı bulunmalı ve günlük 11 saat sınırı aşılmamalıdır."
            onay="Talebi gönder"
            islem={fazlaMesaiTalepEt}
          >
            <Alan etiket="Çalışanın sicil numarası" htmlFor="sicil" ipucu="Sicil numarası veya ad ile arama yapılabilir.">
              <Input id="sicil" name="sicil" list="fm-calisanlar" required autoComplete="off" inputMode="numeric" />
            </Alan>
            <div className="grid grid-cols-2 gap-3">
              <Alan etiket="Gün" htmlFor="is_gunu">
                <Input id="is_gunu" name="is_gunu" type="date" required defaultValue={bugunTarih} />
              </Alan>
              <Alan etiket="Süre (saat)" htmlFor="saat">
                <Input id="saat" name="saat" type="number" required min={0.5} max={11} step={0.5} defaultValue={2} />
              </Alan>
            </div>
            <Alan etiket="Gerekçe" htmlFor="gerekce">
              <Textarea id="gerekce" name="gerekce" rows={2} required minLength={5} maxLength={500} placeholder="ör. Sipariş teslimi için sargı işi" />
            </Alan>
          </IslemPenceresi>
          <CalisanListesi id="fm-calisanlar" calisanlar={listeCalisanlari} />
        </div>
      )}

      <Sekmeler
        etiket="Fazla mesai bölümleri"
        sekmeler={[
          { ad: "Planlar", adres: sekmeAdresi("planlar"), sayi: bekleyenSayisi || undefined, sayiAciklama: "karar bekliyor", aktif: sekme === "planlar" },
          { ad: "Onaysız fazla mesai", adres: sekmeAdresi("havuz"), sayi: havuzBekleyen.length || undefined, sayiAciklama: "karar bekliyor", aktif: sekme === "havuz" },
          { ad: "Yıllık sınır", adres: sekmeAdresi("yillik"), aktif: sekme === "yillik" },
          ...(onaylariGorur
            ? [{ ad: "Yazılı onaylar", adres: sekmeAdresi("onaylar"), sayi: onaySizlar.length || undefined, sayiAciklama: "çalışanın yazılı onayı yok", aktif: sekme === "onaylar" }]
            : []),
        ]}
      />

      <FiltreCubugu temizleAdres={sekmeAdresi(sekme)} suzgecVar={suzgecVar}>
        {yil !== buYil && <input type="hidden" name="yil" value={yil} />}
        {sekme !== "planlar" && <input type="hidden" name="sekme" value={sekme} />}
        {durumSecenekleri.length > 0 && (
          <FiltreAlani etiket="Durum" htmlFor="durum">
            <Secim id="durum" name="durum" defaultValue={durumSuzgeci}>
              <option value="">Tümü</option>
              {durumSecenekleri.map(([deger, ad]) => <option key={deger} value={deger}>{ad}</option>)}
            </Secim>
          </FiltreAlani>
        )}
        <FiltreAlani etiket="Çalışan ara" htmlFor="ara" className="min-w-48 flex-1 sm:max-w-xs">
          <Input id="ara" name="ara" type="search" defaultValue={araMetni} placeholder="Ad, soyad veya sicil" />
        </FiltreAlani>
      </FiltreCubugu>

      {sekme === "planlar" && (
        <section aria-labelledby="planlar-baslik" className="flex flex-col gap-3">
          <div className="flex flex-col gap-1">
            <h2 id="planlar-baslik" className="text-lg font-semibold">Planlar</h2>
            <p className="text-sm text-muted-foreground">
              {planlar.length} plan{bekleyenSayisi > 0 && ` · ${bekleyenSayisi} kayıt İK kararı bekliyor`}
            </p>
          </div>
          {gosterilenPlanlar.length === 0 ? (
            <BosDurum aciklama={planlar.length === 0 ? "Kayıt bulunmuyor." : "Seçilen filtrelere uygun kayıt bulunmuyor."} />
          ) : (
            <TabloKutusu>
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Gün</TableHead>
                    <TableHead>Çalışan</TableHead>
                    <TableHead>Vardiya</TableHead>
                    <TableHead className="text-right">Süre</TableHead>
                    <TableHead className="w-full">Gerekçe</TableHead>
                    <TableHead>Talep eden</TableHead>
                    <TableHead>Durum</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {gosterilenPlanlar.map((p) => (
                    <TableRow key={p.id}>
                      <TableCell className="tarih-hucre">{tarih(p.is_gunu)}</TableCell>
                      <TableCell><KisiAdi kisi={p.calisan} /></TableCell>
                      <TableCell>{p.vardiya ? vardiyaAdi(p.vardiya.kod) : "—"}</TableCell>
                      <TableCell className="text-right tabular-nums">{saat(p.planli_dk)}</TableCell>
                      <TableCell className="min-w-56 whitespace-normal">
                        {p.gerekce}
                        {p.karar_aciklama && <div className="mt-1 text-xs text-muted-foreground">Karar açıklaması: {p.karar_aciklama}</div>}
                      </TableCell>
                      <TableCell className="text-muted-foreground">
                        <div>{p.talep_eden?.ad_soyad ?? "—"}</div>
                        <div className="text-xs"><Zaman deger={p.talep_zamani} /></div>
                      </TableCell>
                      <TableCell>
                        <DurumIslem durum={<Badge variant={DURUM[p.durum].tur}>{DURUM[p.durum].ad}</Badge>}>
                          {p.karar_zamani && (
                            <span className="text-xs text-muted-foreground">
                              {p.karar_veren?.ad_soyad ?? "Sistem"} · {tarih(p.karar_zamani)}
                            </span>
                          )}
                          {ik && p.durum === "talep" && (
                            <IslemPenceresi
                              dugme="Karar ver"
                              dugmeTuru="default"
                              baslik={`${p.calisan ? `${p.calisan.ad} ${p.calisan.soyad}` : "Çalışan"} · ${tarih(p.is_gunu)} · ${saat(p.planli_dk)}`}
                              aciklama={`Gerekçe: ${p.gerekce}. Talep eden: ${p.talep_eden?.ad_soyad ?? "—"}.`}
                              onay="Kararı kaydet"
                              islem={fazlaMesaiKarar}
                              gizli={{ plan_id: p.id }}
                            >
                              <KararAlanlari />
                            </IslemPenceresi>
                          )}
                        </DurumIslem>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </TabloKutusu>
          )}
        </section>
      )}

      {sekme === "havuz" && (
        <section aria-labelledby="havuz-baslik" className="flex flex-col gap-3">
          <div className="flex flex-col gap-1">
            <h2 id="havuz-baslik" className="text-lg font-semibold">Onaysız fazla mesai</h2>
            <p className="text-sm text-muted-foreground">
              Onaylı planı olmadan vardiya sonrasında veya tatilde çalışılan süreler. İK kararı verilene kadar puantaja dahil edilmez.
              {havuzBekleyen.length > 0 && ` ${havuzBekleyen.length} kayıt karar bekliyor.`}
            </p>
          </div>
          {gosterilenHavuz.length === 0 ? (
            <BosDurum
              aciklama={
                havuz.length === 0
                  ? "Kayıt bulunmuyor."
                  : "Seçilen filtrelere uygun kayıt bulunmuyor."
              }
            />
          ) : (
            <TabloKutusu>
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Gün</TableHead>
                    <TableHead>Çalışan</TableHead>
                    <TableHead className="w-full">Tür</TableHead>
                    <TableHead className="text-right">Süre</TableHead>
                    <TableHead>Durum</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {gosterilenHavuz.map((h) => (
                    <TableRow key={h.id}>
                      <TableCell className="tarih-hucre">{tarih(h.is_gunu)}</TableCell>
                      <TableCell><KisiAdi kisi={h.calisan} /></TableCell>
                      <TableCell className="whitespace-normal">
                        {HAVUZ_TURU[h.tur]}
                        {yaziliOnayYok(h) && <Badge variant="outline" className="ml-2">Yazılı onay yok</Badge>}
                        {h.yillik_sinir_asildi && <Badge variant="outline" className="ml-2">Yıllık sınır aşıldı</Badge>}
                        {h.karar_aciklama && <div className="mt-1 text-xs text-muted-foreground">Karar açıklaması: {h.karar_aciklama}</div>}
                      </TableCell>
                      <TableCell className="text-right tabular-nums">{sureMetni(h.dakika)}</TableCell>
                      <TableCell>
                        <DurumIslem durum={<Badge variant={HAVUZ_DURUMU[h.durum].tur}>{HAVUZ_DURUMU[h.durum].ad}</Badge>}>
                          {h.karar_zamani && (
                            <span className="text-xs text-muted-foreground">
                              {h.karar_veren?.ad_soyad ?? "—"} · {tarih(h.karar_zamani)}
                              {h.fark_satiri && " · izleyen aya fark satırı"}
                            </span>
                          )}
                          {ik && h.durum === "inceleme_bekliyor" && (
                            <IslemPenceresi
                              dugme="Karar ver"
                              dugmeTuru="default"
                              baslik={`${h.calisan ? `${h.calisan.ad} ${h.calisan.soyad}` : "Çalışan"} · ${tarih(h.is_gunu)} · ${sureMetni(h.dakika)}`}
                              aciklama={`${HAVUZ_TURU[h.tur]}. Onaylanan süre puantaja fazla mesai olarak eklenir; kilitli aya ait süre izleyen aya fark satırı olarak aktarılır. Yıllık sınır aşıldığında kayıt işaretlenir ve uyarı oluşturulur.`}
                              onay="Kararı kaydet"
                              islem={havuzKarari}
                              gizli={{ inceleme_id: h.id }}
                            >
                              {yaziliOnayYok(h) && (
                                <p role="note" className="rounded-md border bg-muted px-3 py-2 text-sm">
                                  Çalışanın bu gün için geçerli yazılı onayı bulunmuyor. Onaylanan süre puantaja eklenir, kayıt yazılı onaysız olarak işaretlenir ve yazılı onay alınması için İK&apos;ya uyarı iletilir.
                                </p>
                              )}
                              <KararAlanlari retUyarisi="Ret kararı çalışan aleyhine kaydedilir ve süre puantaja dahil edilmez." />
                            </IslemPenceresi>
                          )}
                        </DurumIslem>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </TabloKutusu>
          )}
        </section>
      )}

      {sekme === "yillik" && (
        <section aria-labelledby="yillik-baslik" className="flex flex-col gap-3">
          <div className="flex flex-col gap-1">
            <h2 id="yillik-baslik" className="text-lg font-semibold">Yıllık sınır</h2>
            <p className="text-sm text-muted-foreground">
              Onaylı planlar, havuzdan onaylanan süreler ve tatil çalışmalarının toplamı. Yıllık sınır {saat(yillikSinir)}. Sınırın %{yaklasmaYuzde} oranına ulaşıldığında İK&apos;ya uyarı iletilir.
            </p>
          </div>
          {gosterilenYillik.length === 0 ? (
            <BosDurum aciklama={yillikSatirlar.length === 0 ? "Kayıt bulunmuyor." : "Seçilen filtrelere uygun kayıt bulunmuyor."} />
          ) : (
            <TabloKutusu>
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Çalışan</TableHead>
                    <TableHead className="text-right">Toplam</TableHead>
                    <TableHead className="text-right">Bekleyen talep</TableHead>
                    <TableHead className="text-right">Kalan</TableHead>
                    <TableHead className="w-full min-w-48">Kullanım oranı</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {gosterilenYillik.map((s, i) => {
                    const yuzde = Math.round((s.toplamDk / yillikSinir) * 100);
                    return (
                      <TableRow key={s.kisi?.sicil_no ?? i}>
                        <TableCell><KisiAdi kisi={s.kisi} /></TableCell>
                        <TableCell className="text-right tabular-nums">{saat(s.toplamDk)}</TableCell>
                        <TableCell className="text-right tabular-nums">{s.bekleyenDk ? saat(s.bekleyenDk) : "—"}</TableCell>
                        <TableCell className="text-right tabular-nums">{saat(Math.max(0, s.kalanDk))}</TableCell>
                        <TableCell>
                          <Doluluk yuzde={yuzde} yaklasma={yaklasmaYuzde} />
                        </TableCell>
                      </TableRow>
                    );
                  })}
                </TableBody>
              </Table>
            </TabloKutusu>
          )}
        </section>
      )}

      {sekme === "onaylar" && onaylariGorur && (
        <section aria-labelledby="onay-baslik" className="flex flex-col gap-3">
          <div className="flex flex-wrap items-end justify-between gap-3">
            <div className="flex flex-col gap-1">
              <h2 id="onay-baslik" className="text-lg font-semibold">Yazılı onaylar</h2>
              <p className="text-sm text-muted-foreground">
                {calisanlar.length - onaySizlar.length} çalışanın {yil} yılı için geçerli yazılı onayı bulunuyor
                {geriAlinanlar.length > 0 && ` · ${geriAlinanlar.length} onay geri alındı`}. Yazılı onayı bulunmayan çalışan için fazla mesai planlanamaz.
              </p>
            </div>
            {ik && (
              <div className="flex flex-wrap gap-2">
                <IslemPenceresi
                  dugme="Yazılı onay ekle"
                  dugmeTuru="default"
                  baslik="Yıllık yazılı fazla mesai onayı"
                  aciklama="Çalışanın imzaladığı yıllık onay belgesi kaydedilir."
                  onay="Kaydet"
                  islem={yaziliOnayGir}
                >
                  <Alan etiket="Çalışanın sicil numarası" htmlFor="o-sicil">
                    <Input id="o-sicil" name="sicil" list="fm-calisanlar" required autoComplete="off" inputMode="numeric" />
                  </Alan>
                  <div className="grid grid-cols-3 gap-3">
                    <Alan etiket="Yıl" htmlFor="o-yil">
                      <Input id="o-yil" name="yil" type="number" required min={2000} max={2100} defaultValue={yil} />
                    </Alan>
                    <Alan etiket="İmza tarihi" htmlFor="o-imza">
                      <Input id="o-imza" name="imza_tarihi" type="date" required defaultValue={bugunTarih} />
                    </Alan>
                    <Alan etiket="Belge no" htmlFor="o-belge">
                      <Input id="o-belge" name="belge_no" required maxLength={50} />
                    </Alan>
                  </div>
                </IslemPenceresi>
                <IslemPenceresi
                  dugme="Onayı geri al"
                  dugmeTuru="outline"
                  baslik="Yazılı onayın geri alınması"
                  aciklama="Çalışanın yazılı bildirimi kaydedilir. Onay, bildirim tarihinden 30 gün sonra geçersiz olur."
                  onay="Geri al"
                  onayTuru="destructive"
                  islem={yaziliOnayGeriAl}
                >
                  <Alan etiket="Çalışanın sicil numarası" htmlFor="g-sicil">
                    <Input id="g-sicil" name="sicil" list="fm-calisanlar" required autoComplete="off" inputMode="numeric" />
                  </Alan>
                  <div className="grid grid-cols-2 gap-3">
                    <Alan etiket="Yıl" htmlFor="g-yil">
                      <Input id="g-yil" name="yil" type="number" required min={2000} max={2100} defaultValue={yil} />
                    </Alan>
                    <Alan etiket="Bildirim tarihi" htmlFor="g-bildirim">
                      <Input id="g-bildirim" name="bildirim_tarihi" type="date" required defaultValue={bugunTarih} />
                    </Alan>
                  </div>
                </IslemPenceresi>
              </div>
            )}
          </div>
          {gosterilenOnaysizlar.length === 0 ? (
            <BosDurum aciklama={onaySizlar.length === 0 ? "Kayıt bulunmuyor." : "Seçilen filtrelere uygun kayıt bulunmuyor."} />
          ) : (
            <TabloKutusu>
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Onayı olmayan çalışan</TableHead>
                    <TableHead className="w-full">Departman</TableHead>
                    <TableHead>Durum</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {gosterilenOnaysizlar.map((c) => {
                    const geriAlinan = onaylar.find((o) => o.calisan_id === c.id);
                    return (
                      <TableRow key={c.id}>
                        <TableCell><KisiAdi kisi={c} /></TableCell>
                        <TableCell className="whitespace-normal">{c.departman?.ad ?? "—"}</TableCell>
                        <TableCell>
                          {/* Tablonun başlığı zaten "onayı olmayan" der; satırda yalnızca geri alınanlar belirtilir */}
                          {geriAlinan ? (
                            <Badge variant="outline">Geri alındı · {tarih(geriAlinan.gecerlilik_bitisi)} itibarıyla geçersiz</Badge>
                          ) : (
                            <span className="text-muted-foreground">—</span>
                          )}
                        </TableCell>
                      </TableRow>
                    );
                  })}
                </TableBody>
              </Table>
            </TabloKutusu>
          )}
        </section>
      )}

      {yil === buYil ? (
        <Link href={`/fazla-mesai?yil=${buYil - 1}`} className="self-start text-sm text-primary underline-offset-4 hover:underline">
          {buYil - 1} yılını göster
        </Link>
      ) : (
        <Link href="/fazla-mesai" className="self-start text-sm text-primary underline-offset-4 hover:underline">
          {buYil} yılına dön
        </Link>
      )}
    </div>
  );
}

function Doluluk({ yuzde, yaklasma }: { yuzde: number; yaklasma: number }) {
  const renk = yuzde >= 100 ? "bg-destructive" : yuzde >= yaklasma ? "bg-dikkat" : "bg-primary";
  // Çubuk 10px yüksek, zemini kenarlıklı: düşük oranlar da görünsün diye dolu kısım en az 6px
  const genislik = yuzde > 0 ? `max(0.375rem, ${Math.min(yuzde, 100)}%)` : "0";
  return (
    <div className="flex items-center gap-2">
      <div
        className="h-2.5 min-w-24 flex-1 overflow-hidden rounded-full bg-secondary ring-1 ring-border ring-inset"
        role="meter"
        aria-valuemin={0}
        aria-valuemax={100}
        aria-valuenow={Math.min(yuzde, 100)}
        aria-label="Yıllık sınır doluluğu"
      >
        <div className={cn("h-full rounded-full", renk)} style={{ width: genislik }} />
      </div>
      <span className="w-10 text-right text-xs tabular-nums">%{yuzde}</span>
    </div>
  );
}

function KisiAdi({ kisi }: { kisi: Kisi }) {
  if (!kisi) return <span className="text-muted-foreground">—</span>;
  return (
    <span>
      {kisi.ad} {kisi.soyad}
      <span className="block font-mono text-xs text-muted-foreground">{kisi.sicil_no}</span>
    </span>
  );
}
