import Link from "next/link";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { buttonVariants } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { OzetIzgarasi, OzetKarti } from "@/components/panel/ozet-karti";
import { tekDeger } from "@/lib/arama";
import { sureMetni, tarih, tarihSaat } from "@/lib/bicim";
import { ayBittiMi, bugun } from "@/lib/hafta";
import { rolGerekli } from "@/lib/oturum";
import { ayAdi, ayKaydir, type PuantajSatiri } from "@/lib/puantaj";
import { tumSatirlar } from "@/lib/supabase/sayfali";
import { sunucuIstemcisi } from "@/lib/supabase/server";
import type { ErpSatiri } from "@/lib/erp-aktarim";
import { IslemPenceresi } from "@/components/panel/islem-penceresi";
import { ayKilitle } from "./actions";
import { ZorlaKilitAlanlari } from "./zorla-kilit-alanlari";
import { ErpIndir } from "./erp-indir";
import { ExcelIndir } from "./excel-indir";
import { aramaSuzgeci } from "@/components/liste/arama";
import { BosDurum } from "@/components/liste/bos-durum";
import { FiltreAlani, FiltreCubugu } from "@/components/liste/filtre-cubugu";
import { TabloKutusu } from "@/components/liste/tablo-kutusu";

export const metadata = { title: "Puantaj" };

type Calisan = { id: number; sicil_no: string; ad: string; soyad: string; aktif: boolean; departman: { ad: string } | null };

// v_puantaj_canli (açık ay) ve puantaj_satiri (kilitli ay) aynı sayısal sütunları taşır
type Sayilar = {
  calisan_id: number;
  calisilan_gun: number;
  calisma_dk: number;
  fazla_mesai_dk: number;
  fm50_dk: number;
  fm100_dk: number;
  gece_calisma_dk: number;
  mola_dk: number;
  gec_kalma_dk: number;
  erken_cikis_dk: number;
  devamsiz_gun: number;
  izinli_gun: number;
  raporlu_gun: number;
  tatil_gun: number;
  bekleyen_gun?: number;
  satir_turu?: "normal" | "fark";
  kaynak?: { yil: number; ay: number } | null;
};

const SAYI_SUTUNLARI =
  "calisan_id, calisilan_gun, calisma_dk, fazla_mesai_dk, fm50_dk, fm100_dk, gece_calisma_dk, mola_dk, gec_kalma_dk, erken_cikis_dk, devamsiz_gun, izinli_gun, raporlu_gun, tatil_gun";

// pdks.v_puantaj_aktarim: kilitli ayın puantaj kodları (ERP aktarımı)
type AktarimSatiri = {
  donem: string;
  sicil: string;
  satir_turu: "normal" | "fark";
  kaynak_donem: string | null;
  kod: string;
  gun: number;
  dakika: number;
};

// Puantaj bordroya gider ve rapor (sağlık) bilgisi içerir: yalnızca İK.
export default async function PuantajSayfasi({ searchParams }: PageProps<"/puantaj">) {
  const kullanici = await rolGerekli(["ik"]);
  const parametre = await searchParams;

  const istenen = tekDeger(parametre.ay);
  const araMetni = tekDeger(parametre.ara).slice(0, 100);
  const uyar = aramaSuzgeci(araMetni);
  const ay = /^\d{4}-(0[1-9]|1[0-2])$/.test(istenen) ? istenen : bugun().slice(0, 7);
  // Bitmemiş ay kilitlenemez (T-89): kilit geri açılamaz, kalan günler puantaja hiç girmezdi
  const ayBitti = ayBittiMi(ay, bugun());
  const [yil, ayNo] = ay.split("-").map(Number);

  const supabase = await sunucuIstemcisi();

  const [donemSonucu, calisanlar] = await Promise.all([
    supabase
      .from("donem")
      .select("id, durum, kilit_zamani, kilitleyen:kullanici!kilitleyen_id(ad_soyad)")
      .eq("yil", yil)
      .eq("ay", ayNo)
      .maybeSingle(),
    tumSatirlar<Calisan>((bas, son) =>
      supabase.from("calisan").select("id, sicil_no, ad, soyad, aktif, departman:departman_id(ad)").order("sicil_no").range(bas, son),
    ),
  ]);
  if (donemSonucu.error) throw new Error(`Dönem okunamadı: ${donemSonucu.error.message}`);

  const donem = donemSonucu.data as {
    id: number;
    durum: "acik" | "kilitli";
    kilit_zamani: string | null;
    kilitleyen: { ad_soyad: string } | null;
  } | null;
  const kilitli = donem?.durum === "kilitli";

  // Kilidin izi (T-92, donem_kilit_izi): zorla kilitlendiyse gerekçe ve kilit anında sonuçlanmamış
  // kayıtların sayısı gösterilir. Yalnızca İK ve yönetici okur. T-92 öncesi kilitlenen ayların izi yoktur.
  const kilitIzi = kilitli && donem
    ? ((await supabase.from("donem_kilit_izi").select("zorla, gerekce, ozet").eq("donem_id", donem.id).maybeSingle()).data as {
        zorla: boolean;
        gerekce: string | null;
        ozet: {
          zorla_gecilen?: { acik_soru_gun?: number; acik_itiraz?: number; bekleyen_fazla_mesai?: number; bekleyen_plan_onayi?: number };
          kodsuz_gun?: number;
        };
      } | null)
    : null;
  const gecilenler = kilitIzi?.zorla
    ? [
        kilitIzi.ozet.zorla_gecilen?.acik_soru_gun ? `${kilitIzi.ozet.zorla_gecilen.acik_soru_gun} açık sorulu gün` : null,
        kilitIzi.ozet.zorla_gecilen?.acik_itiraz ? `${kilitIzi.ozet.zorla_gecilen.acik_itiraz} açık itiraz` : null,
        kilitIzi.ozet.zorla_gecilen?.bekleyen_fazla_mesai ? `${kilitIzi.ozet.zorla_gecilen.bekleyen_fazla_mesai} onaysız fazla mesai` : null,
        kilitIzi.ozet.zorla_gecilen?.bekleyen_plan_onayi ? `${kilitIzi.ozet.zorla_gecilen.bekleyen_plan_onayi} onay bekleyen geriye dönük plan` : null,
        kilitIzi.ozet.kodsuz_gun ? `${kilitIzi.ozet.kodsuz_gun} kodsuz gün` : null,
      ].filter(Boolean)
    : [];

  // Kilidi engelleyen açık işler: soru, itiraz, kararı bekleyen onaysız fazla mesai,
  // İK onayı bekleyen geriye dönük vardiya planı
  const ayBasi = `${ay}-01`;
  const sonrakiAyBasi = `${ayKaydir(ay, 1)}-01`;
  const SAYIM = { count: "exact", head: true } as const;
  const [acikSoru, acikItiraz, bekleyenHavuz, bekleyenPlan] = kilitli
    ? [null, null, null, null]
    : await Promise.all([
        supabase
          .from("amir_sorusu")
          .select("id, gun:gun_kaydi_id!inner(is_gunu)", SAYIM)
          .in("durum", ["acik", "eskale", "ik_karari_bekliyor"])
          .gte("gun.is_gunu", ayBasi)
          .lt("gun.is_gunu", sonrakiAyBasi),
        supabase
          .from("itiraz")
          .select("id, gun:gun_kaydi_id!inner(is_gunu)", SAYIM)
          .in("durum", ["acik", "inceleniyor"])
          .gte("gun.is_gunu", ayBasi)
          .lt("gun.is_gunu", sonrakiAyBasi),
        supabase
          .from("fazla_mesai_inceleme")
          .select("id", SAYIM)
          .eq("durum", "inceleme_bekliyor")
          .gte("is_gunu", ayBasi)
          .lt("is_gunu", sonrakiAyBasi),
        supabase
          .from("vardiya_plani")
          .select("id", SAYIM)
          .eq("geriye_donuk", true)
          .eq("ik_onay_durumu", "bekliyor")
          .gte("tarih", ayBasi)
          .lt("tarih", sonrakiAyBasi),
      ]);
  const acikIsler = [
    acikSoru?.count ? `${acikSoru.count} açık soru` : null,
    acikItiraz?.count ? `${acikItiraz.count} açık itiraz` : null,
    bekleyenHavuz?.count ? `${bekleyenHavuz.count} kararı bekleyen onaysız fazla mesai` : null,
    bekleyenPlan?.count ? `${bekleyenPlan.count} İK onayı bekleyen geriye dönük plan` : null,
  ].filter(Boolean) as string[];

  // Kilitli ay: değişmez puantaj satırları. Açık ay: gün kayıtlarından canlı hesap.
  const sayilar = kilitli
    ? await tumSatirlar<Sayilar>((bas, son) =>
        supabase
          .from("puantaj_satiri")
          .select(`${SAYI_SUTUNLARI}, satir_turu, kaynak:donem!kaynak_donem_id(yil, ay)`)
          .eq("donem_id", donem!.id)
          .order("id")
          .range(bas, son),
      )
    : await tumSatirlar<Sayilar>((bas, son) =>
        supabase
          .from("v_puantaj_canli")
          .select(`${SAYI_SUTUNLARI}, bekleyen_gun`)
          .eq("yil", yil)
          .eq("ay", ayNo)
          .order("calisan_id")
          .range(bas, son),
      );

  // Kilitli ayın kod kırılımı: Excel'in "Puantaj kodları" sayfası ve ERP dosyaları (CSV / XML)
  const kodlar: ErpSatiri[] = kilitli
    ? (
        await tumSatirlar<AktarimSatiri>((bas, son) =>
          supabase
            .from("v_puantaj_aktarim")
            .select("donem, sicil, satir_turu, kaynak_donem, kod, gun, dakika")
            .eq("donem_id", donem!.id)
            .order("puantaj_satiri_id")
            .order("kod")
            .range(bas, son),
        )
      ).map((k) => ({
        donem: k.donem,
        sicil: k.sicil,
        satirTuru: k.satir_turu,
        kaynakDonem: k.kaynak_donem,
        kod: k.kod,
        gun: Number(k.gun),
        dakika: Number(k.dakika),
      }))
    : [];

  const normal = new Map(sayilar.filter((s) => s.satir_turu !== "fark").map((s) => [s.calisan_id, s]));
  const calisanById = new Map(calisanlar.map((c) => [c.id, c]));

  const satiraCevir = (c: Calisan, s: Sayilar | undefined): PuantajSatiri => ({
    sicil: c.sicil_no,
    adSoyad: `${c.ad} ${c.soyad}`,
    bolum: c.departman?.ad ?? "",
    calisilanGun: Number(s?.calisilan_gun ?? 0),
    calismaDk: Number(s?.calisma_dk ?? 0),
    fazlaMesaiDk: Number(s?.fazla_mesai_dk ?? 0),
    fm50Dk: Number(s?.fm50_dk ?? 0),
    fm100Dk: Number(s?.fm100_dk ?? 0),
    geceCalismaDk: Number(s?.gece_calisma_dk ?? 0),
    molaDk: Number(s?.mola_dk ?? 0),
    gecKalmaDk: Number(s?.gec_kalma_dk ?? 0),
    erkenCikisDk: Number(s?.erken_cikis_dk ?? 0),
    devamsizGun: Number(s?.devamsiz_gun ?? 0),
    izinliGun: Number(s?.izinli_gun ?? 0),
    raporluGun: Number(s?.raporlu_gun ?? 0),
    tatilGun: Number(s?.tatil_gun ?? 0),
    bekleyenGun: Number(s?.bekleyen_gun ?? 0),
    kaynakDonem: s?.kaynak ? `${s.kaynak.yil}-${String(s.kaynak.ay).padStart(2, "0")}` : undefined,
  });

  // Bordroya çalışan herkes girer; ay içinde ayrılan da kaydı varsa girer.
  const satirlar = calisanlar.filter((c) => c.aktif || normal.has(c.id)).map((c) => satiraCevir(c, normal.get(c.id)));
  const farkSatirlari = sayilar
    .filter((s) => s.satir_turu === "fark")
    .flatMap((s) => {
      const c = calisanById.get(s.calisan_id);
      return c ? [satiraCevir(c, s)] : [];
    });

  const toplamDk = satirlar.reduce((t, s) => t + s.calismaDk, 0);
  const toplamFmDk = satirlar.reduce((t, s) => t + s.fazlaMesaiDk, 0);
  const bekleyenGun = satirlar.reduce((t, s) => t + s.bekleyenGun, 0);
  const veriVar = sayilar.length > 0;
  // Ad / sicil / bölüm araması yalnızca ekrandaki listeyi süzer; Excel ve ERP dosyası her zaman tüm satırları içerir
  const gosterilenSatirlar = satirlar.filter((s) => uyar(s.adSoyad, s.sicil, s.bolum));

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-col gap-1">
        <h1 className="text-2xl font-semibold">Puantaj · {ayAdi(ay)}</h1>
        <p className="text-sm text-muted-foreground">Bordroya aktarılacak gün ve süre özeti. Ücret bilgisi içermez.</p>
      </div>

      <div className="flex flex-wrap items-center justify-between gap-3">
        <nav aria-label="Ay" className="flex flex-wrap gap-2">
          <Link href={`/puantaj?ay=${ayKaydir(ay, -1)}`} className={buttonVariants({ variant: "outline", size: "sm" })}>
            ← {ayAdi(ayKaydir(ay, -1))}
          </Link>
          <Link href="/puantaj" className={buttonVariants({ variant: "ghost", size: "sm" })}>Bu ay</Link>
          <Link href={`/puantaj?ay=${ayKaydir(ay, 1)}`} className={buttonVariants({ variant: "outline", size: "sm" })}>
            {ayAdi(ayKaydir(ay, 1))} →
          </Link>
        </nav>
        <div className="flex flex-wrap gap-2">
          {kilitli && <ErpIndir ay={ay} satirlar={kodlar} />}
          <ExcelIndir
            ay={ay}
            durum={kilitli ? "kilitli" : "acik"}
            satirlar={satirlar}
            farkSatirlari={farkSatirlari}
            kodlar={kodlar}
            hazirlayan={kullanici.adSoyad}
          />
        </div>
      </div>

      <OzetIzgarasi>
        <OzetKarti
          baslik="Dönem"
          deger={kilitli ? "Kilitli" : "Açık"}
          aciklama={
            kilitli
              ? `${donem?.kilitleyen?.ad_soyad ?? "—"} · ${tarihSaat(donem?.kilit_zamani)}`
              : "Ay kilitlendiğinde kesinleşir"
          }
          ton={kilitli ? "iyi" : "notr"}
        />
        <OzetKarti baslik="Çalışan" deger={satirlar.length} aciklama={farkSatirlari.length ? `${farkSatirlari.length} fark satırı` : "Bordroya aktarılacak"} />
        <OzetKarti baslik="Toplam çalışma" deger={sureMetni(toplamDk)} aciklama={`Fazla mesai ${sureMetni(toplamFmDk)}`} />
        {!kilitli && (
          <OzetKarti
            baslik="Kesinleşmemiş gün"
            deger={bekleyenGun}
            aciklama={!veriVar ? "Kayıt bulunmuyor" : bekleyenGun ? "Soru, eksik kayıt veya hesaplama bekleniyor" : "Tüm günler kesinleşti"}
            ton={!veriVar ? "notr" : bekleyenGun ? "dikkat" : "iyi"}
          />
        )}
      </OzetIzgarasi>

      {kilitIzi?.zorla && (
        <Alert className="border-dikkat/40 bg-dikkat-zemin/60">
          <AlertTitle>Bu ay zorla kilitlendi</AlertTitle>
          <AlertDescription>
            <span className="block">Gerekçe: {kilitIzi.gerekce ?? "—"}</span>
            {gecilenler.length > 0 && (
              <span className="block">Kilit anında sonuçlanmamış kayıtlar: {gecilenler.join(", ")}.</span>
            )}
          </AlertDescription>
        </Alert>
      )}

      {!veriVar && !kilitli && (
        <Alert>
          <AlertTitle>Kayıt bulunmuyor</AlertTitle>
          <AlertDescription>
            Puantaj, gece işleminden sonra hesaplanır.
          </AlertDescription>
        </Alert>
      )}

      {!kilitli && !ayBitti && (
        <p className="rounded-lg border border-dashed p-4 text-sm text-muted-foreground">
          {ayAdi(ay)} henüz bitmedi. Ay kilidi {tarih(`${ayKaydir(ay, 1)}-01`)} tarihinden itibaren yapılabilir.
          {acikIsler.length > 0 && ` Şu an ${acikIsler.join(", ")} var.`}
        </p>
      )}

      {!kilitli && ayBitti && (
        <div className="flex flex-col gap-2 rounded-lg border border-dashed p-4">
          <div className="self-start">
            <IslemPenceresi
              dugme="Ayı kilitle"
              dugmeTuru="destructive"
              baslik={`${ayAdi(ay)} dönemini kilitle`}
              aciklama="Puantaj kesinleşir. Kilit geri açılamaz; sonraki düzeltmeler izleyen aya fark satırı olarak aktarılır."
              onay="Ayı kilitle"
              onayTuru="destructive"
              islem={ayKilitle}
              gizli={{ ay }}
            >
              {acikIsler.length > 0 ? (
                <div className="flex flex-col gap-2 rounded-lg bg-destructive/10 p-3 text-sm">
                  <p className="font-medium text-destructive">Bu ayda {acikIsler.join(", ")} var.</p>
                  <p>Bu kayıtlar sonuçlanmadan kilitleme yapılırsa sonuçlar izleyen aya fark satırı olarak aktarılır.</p>
                  {(bekleyenPlan?.count ?? 0) > 0 && (
                    <p>İşlenmemiş günü bulunan bekleyen planlar, ay kilitlenmeden önce onaylanmalı veya reddedilmelidir.</p>
                  )}
                  <ZorlaKilitAlanlari />
                </div>
              ) : (
                <p className="rounded-lg bg-muted p-3 text-sm">Bu ayda bekleyen kayıt bulunmuyor.</p>
              )}
              {bekleyenGun > 0 && (
                <p className="text-sm text-muted-foreground">{bekleyenGun} gün kesinleşmemiştir (eksik kayıt veya bekleyen hesaplama).</p>
              )}
              <p className="text-sm text-muted-foreground">
                İşlenmemiş planlı günü bulunan ay kilitlenemez.
              </p>
              <label className="flex items-start gap-2 text-sm">
                <input type="checkbox" name="onay" value="evet" required className="mt-0.5" />
                Kilidin geri açılamayacağını onaylıyorum.
              </label>
            </IslemPenceresi>
          </div>
          <p className="text-sm text-muted-foreground">
            Kilitlenen ay geri açılamaz; sonraki düzeltmeler izleyen aya fark satırı olarak aktarılır.
            {acikIsler.length > 0 && ` Şu an ${acikIsler.join(", ")} var.`}
          </p>
        </div>
      )}

      <FiltreCubugu temizleAdres={`/puantaj?ay=${ay}`} suzgecVar={Boolean(araMetni)}>
        <input type="hidden" name="ay" value={ay} />
        <FiltreAlani etiket="Çalışan ara" htmlFor="ara" className="min-w-48 flex-1 sm:max-w-xs">
          <Input id="ara" name="ara" type="search" defaultValue={araMetni} placeholder="Ad, sicil veya departman" />
        </FiltreAlani>
        {araMetni && (
          <p className="self-center text-xs text-muted-foreground">
            {gosterilenSatirlar.length} / {satirlar.length} çalışan gösteriliyor. Excel dosyası tüm çalışanları içerir.
          </p>
        )}
      </FiltreCubugu>

      {gosterilenSatirlar.length === 0 ? (
        <BosDurum aciklama={araMetni ? "Seçilen filtrelere uygun kayıt bulunmuyor." : "Kayıt bulunmuyor."} />
      ) : (
        // Dar ekranda sayı sütunları yana kayar; çalışan sütunu solda sabit kalır, kimin satırı olduğu hep görünür
        <TabloKutusu>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead className="sticky left-0 z-10 min-w-44 bg-card shadow-[inset_-1px_0_0_var(--border)]">Çalışan</TableHead>
                <TableHead className="text-right whitespace-normal">Çalışılan gün</TableHead>
                <TableHead className="text-right whitespace-normal">Çalışma</TableHead>
                <TableHead className="text-right whitespace-normal">Fazla mesai</TableHead>
                <TableHead className="text-right whitespace-normal">Geç kalma</TableHead>
                <TableHead className="text-right whitespace-normal">Erken çıkış</TableHead>
                <TableHead className="text-right whitespace-normal">Devamsız</TableHead>
                <TableHead className="text-right whitespace-normal">İzinli</TableHead>
                <TableHead className="text-right whitespace-normal">Raporlu</TableHead>
                <TableHead className="text-right whitespace-normal">Tatil</TableHead>
                {!kilitli && <TableHead className="text-right whitespace-normal">Kesinleşmemiş</TableHead>}
              </TableRow>
            </TableHeader>
            <TableBody>
              {gosterilenSatirlar.map((s) => (
                <TableRow key={s.sicil}>
                  <TableCell className="sticky left-0 z-10 bg-card whitespace-normal shadow-[inset_-1px_0_0_var(--border)]">
                    <div className="font-medium">{s.adSoyad}</div>
                    <div className="text-xs text-muted-foreground">
                      <span className="font-mono">{s.sicil}</span> · {s.bolum}
                    </div>
                  </TableCell>
                  <Sayi deger={s.calisilanGun} />
                  <TableCell className="text-right tabular-nums">{sureMetni(s.calismaDk)}</TableCell>
                  <TableCell className="text-right tabular-nums">{s.fazlaMesaiDk ? sureMetni(s.fazlaMesaiDk) : "—"}</TableCell>
                  <Sayi deger={s.gecKalmaDk} birim="dk" />
                  <Sayi deger={s.erkenCikisDk} birim="dk" />
                  <Sayi deger={s.devamsizGun} />
                  <Sayi deger={s.izinliGun} />
                  <Sayi deger={s.raporluGun} />
                  <Sayi deger={s.tatilGun} />
                  {!kilitli && (
                    <TableCell className="text-right">
                      {s.bekleyenGun ? <Badge variant="default">{s.bekleyenGun}</Badge> : "—"}
                    </TableCell>
                  )}
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </TabloKutusu>
      )}

      {farkSatirlari.length > 0 && (
        <p className="text-sm text-muted-foreground">
          Bu ayda önceki aylara ait {farkSatirlari.length} fark satırı bulunuyor. Fark satırları Excel dosyasında ayrı sayfada yer alır.
        </p>
      )}
    </div>
  );
}

function Sayi({ deger, birim }: { deger: number; birim?: string }) {
  return (
    <TableCell className="text-right tabular-nums">
      {deger ? `${deger.toLocaleString("tr-TR")}${birim ? ` ${birim}` : ""}` : "—"}
    </TableCell>
  );
}
