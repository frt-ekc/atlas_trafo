import Link from "next/link";
import { Badge } from "@/components/ui/badge";
import { Button, buttonVariants } from "@/components/ui/button";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { CalisanListesi } from "@/components/panel/calisan-listesi";
import { HizliIslem } from "@/components/panel/hizli-islem";
import { DurumRozeti } from "@/components/liste/durum-rozeti";
import { IslemMenusu } from "@/components/liste/islem-menusu";
import { ListeKarti } from "@/components/liste/liste-karti";
import { Zaman } from "@/components/liste/zaman";
import { Alan, IslemPenceresi } from "@/components/panel/islem-penceresi";
import { SuzgecFormu } from "@/components/panel/suzgec-formu";
import { Secim } from "@/components/panel/secim";
import { VardiyaEtiketi } from "@/components/panel/vardiya-etiketi";
import { tekDeger } from "@/lib/arama";
import { bolumNumarasi, gorunurBolumler } from "@/lib/bolumler";
import { bugun, gecerliTarihMi, gunEkle, haftaBasi, haftaBasligi, haftaninGunleri } from "@/lib/hafta";
import { rolGerekli } from "@/lib/oturum";
import { tumSatirlar } from "@/lib/supabase/sayfali";
import { sunucuIstemcisi } from "@/lib/supabase/server";
import { tarih } from "@/lib/bicim";
import { cn } from "@/lib/utils";
import { vardiyaPlaniGir, vardiyaPlaniOnayla } from "./actions";

export const metadata = { title: "Vardiya planı" };

type Calisan = {
  id: number;
  sicil_no: string;
  ad: string;
  soyad: string;
  ise_giris_tarihi: string;
  isten_cikis_tarihi: string | null;
  departman: { ad: string } | null;
};
type Plan = { calisan_id: number; tarih: string; vardiya_id: number; geriye_donuk: boolean; ik_onay_durumu: string; aciklama: string | null };
type Izin = { calisan_id: number; tur: string; baslangic: string; bitis: string };
type FazlaMesai = { calisan_id: number; is_gunu: string; planli_dk: number; durum: string };
type BekleyenPlan = {
  id: number;
  tarih: string;
  aciklama: string | null;
  giris_zamani: string;
  calisan: { sicil_no: string; ad: string; soyad: string } | null;
  vardiya: { ad: string } | null;
  giren: { ad_soyad: string } | null;
};
type Vardiya = { id: number; kod: string; ad: string; baslangic: string; bitis: string };

// İzin türü sağlık verisi içerebilir (rapor). Türü yalnızca İK görür; diğerleri "İzinli" görür.
const IZIN_TURU: Record<string, string> = {
  yillik: "Yıllık izin",
  rapor: "Rapor",
  mazeret: "Mazeret",
  ucretsiz: "Ücretsiz izin",
  diger: "İzinli",
};

export default async function VardiyaPlaniSayfasi({ searchParams }: PageProps<"/vardiya-plani">) {
  const kullanici = await rolGerekli(["amir", "ik", "yonetici"]);
  const parametre = await searchParams;

  const istenenTarih = tekDeger(parametre.hafta);
  const bugunTarih = bugun();
  const pazartesi = haftaBasi(gecerliTarihMi(istenenTarih) ? istenenTarih : bugunTarih);
  const pazar = gunEkle(pazartesi, 6);
  const gunler = haftaninGunleri(pazartesi);
  const departmanId = bolumNumarasi(tekDeger(parametre.departman));
  const izinTuruGorur = kullanici.rol === "ik";
  // Planı amir ve İK girer; yönetici yalnızca okur
  const planGirebilir = kullanici.rol === "amir" || kullanici.rol === "ik";

  const supabase = await sunucuIstemcisi();

  // Hepsi RLS'den geçer: amir yalnızca kendi bölümlerinin satırlarını alır.
  const [bolumler, vardiyaSonucu, tatilSonucu, calisanlar, planlar, izinler, fazlaMesailer] = await Promise.all([
    gorunurBolumler(supabase, kullanici.rol),
    supabase.from("vardiya_tanim").select("id, kod, ad, baslangic, bitis").order("baslangic"),
    supabase.from("resmi_tatil").select("tarih, ad, yarim_gun").gte("tarih", pazartesi).lte("tarih", pazar),
    tumSatirlar<Calisan>((bas, son) => {
      let q = supabase
        .from("calisan")
        .select("id, sicil_no, ad, soyad, ise_giris_tarihi, isten_cikis_tarihi, departman:departman_id(ad)")
        // O hafta işte olanlar: haftanın son gününe kadar işe girmiş, ilk gününden önce ayrılmamış.
        // ("aktif" alanına bakılmaz; yoksa ayrılan çalışan geçmiş haftalarda da kaybolurdu.)
        .lte("ise_giris_tarihi", pazar)
        .or(`isten_cikis_tarihi.is.null,isten_cikis_tarihi.gte.${pazartesi}`)
        .order("sicil_no")
        .range(bas, son);
      if (departmanId) q = q.eq("departman_id", departmanId);
      return q;
    }),
    tumSatirlar<Plan>((bas, son) => {
      // Bölüm seçiliyse planlar çalışan tablosuyla birleştirilip veritabanında süzülür (!inner).
      let q = supabase
        .from("vardiya_plani")
        .select(`calisan_id, tarih, vardiya_id, geriye_donuk, ik_onay_durumu, aciklama${departmanId ? ", calisan!inner(departman_id)" : ""}`)
        .gte("tarih", pazartesi)
        .lte("tarih", pazar)
        .order("id")
        .range(bas, son);
      if (departmanId) q = q.eq("calisan.departman_id", departmanId);
      return q;
    }),
    // İK izin tablosunu okur; amir ve yönetici türü gizleyen v_izin_amir görünümünü.
    // İptal edilen izinler silinmez: izin tablosunda süzülür, görünüm onları zaten göstermez.
    tumSatirlar<Izin>((bas, son) => {
      const q = izinTuruGorur
        ? supabase.from("izin").select("calisan_id, tur, baslangic, bitis").is("iptal_zamani", null)
        : supabase.from("v_izin_amir").select("calisan_id, tur, baslangic, bitis");
      return q.lte("baslangic", pazar).gte("bitis", pazartesi).order("id").range(bas, son);
    }),
    tumSatirlar<FazlaMesai>((bas, son) =>
      supabase
        .from("fazla_mesai_plani")
        .select("calisan_id, is_gunu, planli_dk, durum")
        .gte("is_gunu", pazartesi)
        .lte("is_gunu", pazar)
        .in("durum", ["talep", "onaylandi"])
        .order("id")
        .range(bas, son),
    ),
  ]);

  if (vardiyaSonucu.error) throw new Error(`Vardiyalar okunamadı: ${vardiyaSonucu.error.message}`);
  if (tatilSonucu.error) throw new Error(`Resmi tatiller okunamadı: ${tatilSonucu.error.message}`);

  // İK: tüm haftalardaki onay bekleyen geriye dönük planlar
  const bekleyenPlanlar =
    kullanici.rol === "ik"
      ? await tumSatirlar<BekleyenPlan>((bas, son) =>
          supabase
            .from("vardiya_plani")
            .select(
              "id, tarih, aciklama, giris_zamani, calisan:calisan_id(sicil_no, ad, soyad), " +
                "vardiya:vardiya_id(ad), giren:kullanici!giren_id(ad_soyad)",
            )
            .eq("ik_onay_durumu", "bekliyor")
            .order("tarih")
            .order("id")
            .range(bas, son),
        )
      : [];

  const vardiyalar = (vardiyaSonucu.data ?? []) as Vardiya[];
  const vardiyaById = new Map(vardiyalar.map((v) => [v.id, v]));
  const tatiller = new Map((tatilSonucu.data ?? []).map((t) => [t.tarih as string, t]));
  const anahtar = (calisanId: number, tarih: string) => `${calisanId}|${tarih}`;
  const planMap = new Map(planlar.map((p) => [anahtar(p.calisan_id, p.tarih), p]));
  const fmMap = new Map(fazlaMesailer.map((f) => [anahtar(f.calisan_id, f.is_gunu), f]));
  const izinBul = (calisanId: number, tarih: string) =>
    izinler.find((i) => i.calisan_id === calisanId && i.baslangic <= tarih && tarih <= i.bitis);

  const gorunenIdler = new Set(calisanlar.map((c) => c.id));
  const bekleyenSayisi = planlar.filter((p) => p.ik_onay_durumu === "bekliyor" && gorunenIdler.has(p.calisan_id)).length;
  const izinliGun = calisanlar.reduce(
    (toplam, c) => toplam + gunler.filter((g) => !g.haftaSonu && izinBul(c.id, g.tarih)).length,
    0,
  );

  // Hafta değişirken seçili bölüm korunur
  const adres = (hafta: string) => {
    const p = new URLSearchParams({ hafta });
    if (departmanId) p.set("departman", String(departmanId));
    return `/vardiya-plani?${p}`;
  };

  return (
    <div className="flex flex-col gap-5">
      <div className="flex flex-col gap-1">
        <h1 className="text-2xl font-semibold">Vardiya planı</h1>
        <p className="text-sm text-muted-foreground">
          {kullanici.rol === "amir"
            ? "Sorumlu olunan departmanların haftalık vardiya planı."
            : "Çalışanların haftalık vardiya planı."}
        </p>
      </div>

      <div className="flex flex-wrap items-end justify-between gap-3">
        <div className="flex flex-col gap-2">
          <div className="text-lg font-semibold" aria-live="polite">{haftaBasligi(pazartesi)}</div>
          <nav aria-label="Hafta" className="flex flex-wrap gap-2">
            <Link href={adres(gunEkle(pazartesi, -7))} className={buttonVariants({ variant: "outline", size: "sm" })}>
              ← Önceki hafta
            </Link>
            <Link href={adres(bugunTarih)} className={buttonVariants({ variant: "ghost", size: "sm" })}>
              Bu hafta
            </Link>
            <Link href={adres(gunEkle(pazartesi, 7))} className={buttonVariants({ variant: "outline", size: "sm" })}>
              Sonraki hafta →
            </Link>
          </nav>
        </div>

        <SuzgecFormu className="flex w-full items-end gap-2 sm:w-auto">
          <input type="hidden" name="hafta" value={pazartesi} />
          <div className="flex min-w-0 flex-1 flex-col gap-1.5">
            <label htmlFor="departman" className="text-sm font-medium">Departman</label>
            <Secim id="departman" name="departman" defaultValue={departmanId ?? ""} className="w-full min-w-0">
              <option value="">Tümü</option>
              {bolumler.map((b) => (
                <option key={b.id} value={b.id}>{b.ad}</option>
              ))}
            </Secim>
          </div>
          <Button type="submit" size="sm">Göster</Button>
        </SuzgecFormu>
      </div>

      {planGirebilir && (
        <div className="self-start">
          <IslemPenceresi
            dugme="Vardiya ekle"
            dugmeTuru="default"
            baslik="Vardiya planı ekle"
            aciklama="Aynı gün için girilen yeni plan öncekinin yerine geçer. Geçmiş günlere ait planlar İK onayına gönderilir. Kilitli aylar için plan girilemez."
            onay="Kaydet"
            islem={vardiyaPlaniGir}
          >
            <Alan etiket="Çalışanın sicil numarası" htmlFor="sicil" ipucu="Sicil numarası veya ad ile arama yapılabilir.">
              <Input id="sicil" name="sicil" list="vp-calisanlar" required autoComplete="off" inputMode="numeric" />
            </Alan>
            <div className="grid grid-cols-2 gap-3">
              <Alan etiket="Gün" htmlFor="tarih">
                <Input id="tarih" name="tarih" type="date" required defaultValue={pazartesi <= bugunTarih && bugunTarih <= pazar ? bugunTarih : pazartesi} />
              </Alan>
              <Alan etiket="Vardiya" htmlFor="vardiya_id">
                <Secim id="vardiya_id" name="vardiya_id" required defaultValue="" className="h-9">
                  <option value="" disabled>Seçin</option>
                  {vardiyalar.map((v) => (
                    <option key={v.id} value={v.id}>
                      {/* Adında saat yoksa (ör. "Esnek mesai") saat aralığı eklenir */}
                      {/\d/.test(v.ad) ? v.ad : `${v.ad} (${v.baslangic.slice(0, 5)}–${v.bitis.slice(0, 5)})`}
                    </option>
                  ))}
                </Secim>
              </Alan>
            </div>
            <Alan etiket="Açıklama (geçmiş gün için gerekçe)" htmlFor="aciklama">
              <Textarea id="aciklama" name="aciklama" rows={2} maxLength={500} placeholder="ör. Grup değişikliği" />
            </Alan>
          </IslemPenceresi>
          <CalisanListesi id="vp-calisanlar" calisanlar={calisanlar} />
        </div>
      )}

      {bekleyenPlanlar.length > 0 && (
        <section aria-labelledby="onay-baslik" className="flex flex-col gap-3">
          <div className="flex flex-col gap-1">
            <h2 id="onay-baslik" className="flex items-center gap-2 text-lg font-semibold">
              Onay bekleyen geriye dönük değişiklikler
              <DurumRozeti ton="dikkat">{bekleyenPlanlar.length}</DurumRozeti>
            </h2>
            <p className="text-sm text-muted-foreground">
              Geçmiş günlere ait planlar onaylanana kadar puantaja yansımaz. Planı ekleyen kullanıcı onay veremez.
            </p>
          </div>
          {bekleyenPlanlar.map((p) => (
            <ListeKarti
              key={p.id}
              vurgu="karar"
              baslik={
                <>
                  <span className="tabular-nums">{tarih(p.tarih)}</span> → {p.vardiya?.ad ?? "—"}
                </>
              }
              kisi={
                p.calisan ? (
                  <span className="font-medium">
                    {p.calisan.ad} {p.calisan.soyad}
                    <span className="ml-1.5 font-mono text-xs text-muted-foreground">{p.calisan.sicil_no}</span>
                  </span>
                ) : undefined
              }
              zaman={<Zaman deger={p.giris_zamani} etiket="Kayıt" />}
              eylemler={
                <>
                  <HizliIslem dugme="Onayla" dugmeTuru="default" islem={vardiyaPlaniOnayla} gizli={{ plan_id: p.id, karar: "onay" }} />
                  <IslemMenusu>
                    {/* Geri alınamaz: tek tıkla değil, onay penceresiyle (aynı işlem, aynı RPC) */}
                    <IslemPenceresi
                      dugme="Reddet"
                      baslik="Planı reddet"
                      aciklama="Plan reddedilecektir. Bu işlem geri alınamaz."
                      onay="Reddet"
                      onayTuru="destructive"
                      islem={vardiyaPlaniOnayla}
                      gizli={{ plan_id: p.id, karar: "ret" }}
                    />
                  </IslemMenusu>
                </>
              }
            >
              Ekleyen: {p.giren?.ad_soyad ?? "—"}
              {p.aciklama && ` · ${p.aciklama}`}
            </ListeKarti>
          ))}
        </section>
      )}

      <p className="text-sm text-muted-foreground">
        {calisanlar.length} çalışan · {izinliGun} izinli gün
        {bekleyenSayisi > 0 && ` · ${bekleyenSayisi} geriye dönük değişiklik İK onayı bekliyor`}
      </p>

      {calisanlar.length === 0 ? (
        <div className="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
          Seçilen filtrelere uygun kayıt bulunmuyor.
        </div>
      ) : (
        <div className="rounded-lg border">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead className="sticky left-0 z-10 min-w-44 bg-background">Çalışan</TableHead>
                {gunler.map((g) => {
                  const tatil = tatiller.get(g.tarih);
                  const bugunMu = g.tarih === bugunTarih;
                  return (
                    <TableHead
                      key={g.tarih}
                      className={cn("min-w-24 text-center", g.haftaSonu && "text-muted-foreground", bugunMu && "bg-primary/5")}
                      title={tatil ? `${tatil.ad}${tatil.yarim_gun ? " (yarım gün)" : ""}` : undefined}
                    >
                      <div className={cn("font-medium", bugunMu && "text-primary")}>{g.ad}</div>
                      <div className="text-xs font-normal tabular-nums">{g.gunAy}</div>
                      {tatil && <div className="text-xs font-normal text-destructive">Tatil</div>}
                    </TableHead>
                  );
                })}
              </TableRow>
            </TableHeader>
            <TableBody>
              {calisanlar.map((c) => (
                <TableRow key={c.id}>
                  <TableCell className="sticky left-0 z-10 bg-background">
                    <div className="font-medium">{c.ad} {c.soyad}</div>
                    <div className="text-xs text-muted-foreground">
                      <span className="font-mono">{c.sicil_no}</span> · {c.departman?.ad ?? "—"}
                    </div>
                    {c.isten_cikis_tarihi && <div className="text-xs text-muted-foreground">Ayrıldı · {tarih(c.isten_cikis_tarihi)}</div>}
                    {c.ise_giris_tarihi > pazartesi && <div className="text-xs text-muted-foreground">İşe giriş · {tarih(c.ise_giris_tarihi)}</div>}
                  </TableCell>
                  {gunler.map((g) => (
                    <TableCell
                      key={g.tarih}
                      className={cn("text-center align-middle", g.tarih === bugunTarih && "bg-primary/5", tatiller.has(g.tarih) && "bg-muted/60")}
                    >
                      <Hucre
                        plan={planMap.get(anahtar(c.id, g.tarih))}
                        vardiya={vardiyaById}
                        izin={izinBul(c.id, g.tarih)}
                        izinTuruGorur={izinTuruGorur}
                        fazlaMesai={fmMap.get(anahtar(c.id, g.tarih))}
                        haftaSonu={g.haftaSonu}
                      />
                    </TableCell>
                  ))}
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      )}

      <section aria-labelledby="aciklama-baslik" className="flex flex-col gap-2">
        <h2 id="aciklama-baslik" className="text-sm font-semibold">Açıklama</h2>
        <ul className="flex flex-wrap gap-x-5 gap-y-2 text-sm">
          {vardiyalar.map((v) => (
            <li key={v.id} className="flex items-center gap-2">
              <VardiyaEtiketi kod={v.kod} />
              <span className="text-muted-foreground tabular-nums">{v.baslangic.slice(0, 5)}–{v.bitis.slice(0, 5)}</span>
            </li>
          ))}
          <li className="flex items-center gap-2"><Badge variant="outline">İzinli</Badge></li>
          <li className="flex items-center gap-2">
            <span className="size-2 rounded-full bg-dikkat" aria-hidden /> Geriye dönük değişiklik, İK onayı bekliyor
          </li>
          <li className="flex items-center gap-2">
            <span className="text-xs font-medium text-primary">+FM</span> Planlı fazla mesai
          </li>
        </ul>
      </section>
    </div>
  );
}

function Hucre({
  plan,
  vardiya,
  izin,
  izinTuruGorur,
  fazlaMesai,
  haftaSonu,
}: {
  plan: Plan | undefined;
  vardiya: Map<number, Vardiya>;
  izin: Izin | undefined;
  izinTuruGorur: boolean;
  fazlaMesai: FazlaMesai | undefined;
  haftaSonu: boolean;
}) {
  const v = plan ? vardiya.get(plan.vardiya_id) : undefined;

  if (izin) {
    const etiket = izinTuruGorur ? (IZIN_TURU[izin.tur] ?? "İzinli") : "İzinli";
    return (
      <Badge variant="outline" title={v ? `Planlı vardiya: ${v.ad}` : undefined}>
        {etiket}
      </Badge>
    );
  }

  if (!plan || !v) {
    return <span className="text-muted-foreground">{haftaSonu ? "" : "—"}</span>;
  }

  const bekliyor = plan.ik_onay_durumu === "bekliyor";
  const reddedildi = plan.ik_onay_durumu === "reddedildi";
  const baslik = [v.ad, plan.aciklama, bekliyor && "Geriye dönük değişiklik: İK onayı bekliyor", reddedildi && "Değişiklik İK tarafından reddedildi"]
    .filter(Boolean)
    .join(" · ");

  return (
    <div className="flex flex-col items-center gap-1" title={baslik}>
      <div className="relative">
        <VardiyaEtiketi kod={v.kod} ustuCizili={reddedildi} />
        {bekliyor && (
          <span className="absolute -top-1 -right-1 size-2 rounded-full bg-dikkat ring-2 ring-background">
            <span className="sr-only">İK onayı bekliyor</span>
          </span>
        )}
      </div>
      {fazlaMesai && (
        <span className="text-xs font-medium text-primary">
          +FM {Math.round((fazlaMesai.planli_dk / 60) * 10) / 10} sa{fazlaMesai.durum === "talep" ? " (talep)" : ""}
        </span>
      )}
    </div>
  );
}
