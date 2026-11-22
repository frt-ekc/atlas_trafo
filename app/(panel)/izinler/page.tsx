import Link from "next/link";
import { Badge } from "@/components/ui/badge";
import { buttonVariants } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Textarea } from "@/components/ui/textarea";
import { BosDurum } from "@/components/panel/bos-durum";
import { CalisanListesi, type ListeCalisani } from "@/components/panel/calisan-listesi";
import { Alan, IslemPenceresi } from "@/components/panel/islem-penceresi";
import { Secim } from "@/components/panel/secim";
import { tekDeger } from "@/lib/arama";
import { saat, tarih, tarihSaat } from "@/lib/bicim";
import { bugun } from "@/lib/hafta";
import { rolGerekli } from "@/lib/oturum";
import { ayAdi, ayKaydir } from "@/lib/puantaj";
import { tumSatirlar } from "@/lib/supabase/sayfali";
import { sunucuIstemcisi } from "@/lib/supabase/server";
import { izinGir, izinIptal, saatlikIzinGir } from "./actions";

export const metadata = { title: "İzinler" };

const IZIN_TURU: Record<string, string> = {
  yillik: "Yıllık izin",
  rapor: "Rapor",
  mazeret: "Mazeret izni",
  ucretsiz: "Ücretsiz izin",
  diger: "Diğer",
};

const SAATLIK_TUR: Record<string, string> = { vizite: "Vizite", mazeret: "Mazeret", diger: "Diğer" };

type Kisi = { id: number; sicil_no: string; ad: string; soyad: string } | null;

type Izin = {
  id: number;
  tur: string;
  baslangic: string;
  bitis: string;
  aciklama: string | null;
  giris_zamani: string;
  iptal_zamani: string | null;
  iptal_nedeni: string | null;
  calisan: Kisi;
  giren: { ad_soyad: string } | null;
};

type SaatlikIzin = {
  id: number;
  tarih: string;
  baslangic: string;
  bitis: string;
  tur: string;
  aciklama: string | null;
  calisan: Kisi;
  giren: { ad_soyad: string } | null;
};

// İzin türü sağlık verisi içerebilir (rapor, vizite): bu sayfa yalnızca İK'ya açıktır.
// Amir ve yönetici izinleri vardiya planında türü gizli olarak ("İzinli") görür.
export default async function IzinlerSayfasi({ searchParams }: PageProps<"/izinler">) {
  const kullanici = await rolGerekli(["ik"]);
  const parametre = await searchParams;
  const istenen = tekDeger(parametre.ay);
  const ay = /^\d{4}-(0[1-9]|1[0-2])$/.test(istenen) ? istenen : bugun().slice(0, 7);
  const ayBasi = `${ay}-01`;
  const sonrakiAyBasi = `${ayKaydir(ay, 1)}-01`;
  const bugunTarih = bugun();

  const supabase = await sunucuIstemcisi();
  const [izinler, saatlikler, calisanlar] = await Promise.all([
    // Ayla çakışan izinler (iptal edilenler de görünür, soluk)
    tumSatirlar<Izin>((bas, son) =>
      supabase
        .from("izin")
        .select(
          "id, tur, baslangic, bitis, aciklama, giris_zamani, iptal_zamani, iptal_nedeni, " +
            "calisan:calisan_id(id, sicil_no, ad, soyad), giren:kullanici!giren_id(ad_soyad)",
        )
        .lt("baslangic", sonrakiAyBasi)
        .gte("bitis", ayBasi)
        .order("baslangic")
        .order("id")
        .range(bas, son),
    ),
    tumSatirlar<SaatlikIzin>((bas, son) =>
      supabase
        .from("saatlik_izin")
        .select("id, tarih, baslangic, bitis, tur, aciklama, calisan:calisan_id(id, sicil_no, ad, soyad), giren:kullanici!giren_id(ad_soyad)")
        .gte("tarih", ayBasi)
        .lt("tarih", sonrakiAyBasi)
        .order("tarih")
        .order("id")
        .range(bas, son),
    ),
    tumSatirlar<ListeCalisani>((bas, son) =>
      supabase.from("calisan").select("sicil_no, ad, soyad").eq("aktif", true).order("sicil_no").range(bas, son),
    ),
  ]);

  const gecerli = izinler.filter((i) => !i.iptal_zamani);
  const adres = (a: string) => `/izinler?ay=${a}`;

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-col gap-1">
        <h1 className="text-2xl font-semibold">İzinler · {ayAdi(ay)}</h1>
        <p className="text-sm text-muted-foreground">
          Gün ve saat bazlı izinler. Yanlış girilen izin silinmez, iptal edilir. İzin türü yalnızca İK&apos;ya görünür; amir
          &quot;İzinli&quot; görür.
        </p>
      </div>

      <div className="flex flex-wrap items-center justify-between gap-3">
        <nav aria-label="Ay" className="flex flex-wrap gap-2">
          <Link href={adres(ayKaydir(ay, -1))} className={buttonVariants({ variant: "outline", size: "sm" })}>← {ayAdi(ayKaydir(ay, -1))}</Link>
          <Link href="/izinler" className={buttonVariants({ variant: "ghost", size: "sm" })}>Bu ay</Link>
          <Link href={adres(ayKaydir(ay, 1))} className={buttonVariants({ variant: "outline", size: "sm" })}>{ayAdi(ayKaydir(ay, 1))} →</Link>
        </nav>
        <div className="flex flex-wrap gap-2">
          <IslemPenceresi
            dugme="İzin gir"
            dugmeTuru="default"
            baslik="Gün bazlı izin"
            aciklama="Kendi izninizi giremezsiniz. İzinli günler gece işinde “izinli / raporlu” olarak işlenir."
            onay="İzni kaydet"
            islem={izinGir}
          >
            <Alan etiket="Çalışanın sicil numarası" htmlFor="sicil" ipucu="Yazmaya başlayınca liste açılır.">
              <Input id="sicil" name="sicil" list="izin-calisanlar" required autoComplete="off" inputMode="numeric" />
            </Alan>
            <Alan etiket="Tür" htmlFor="tur">
              <Secim id="tur" name="tur" required defaultValue="" className="h-9">
                <option value="" disabled>Seçin</option>
                {Object.entries(IZIN_TURU).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
              </Secim>
            </Alan>
            <div className="grid grid-cols-2 gap-3">
              <Alan etiket="Başlangıç" htmlFor="baslangic">
                <Input id="baslangic" name="baslangic" type="date" required defaultValue={bugunTarih} />
              </Alan>
              <Alan etiket="Bitiş" htmlFor="bitis">
                <Input id="bitis" name="bitis" type="date" required defaultValue={bugunTarih} />
              </Alan>
            </div>
            <Alan etiket="Açıklama (isteğe bağlı)" htmlFor="aciklama">
              <Textarea id="aciklama" name="aciklama" rows={2} maxLength={500} />
            </Alan>
          </IslemPenceresi>

          <IslemPenceresi
            dugme="Saatlik izin gir"
            baslik="Saatlik izin"
            aciklama="Gün içinde saat aralıklı izin (vizite, mazeret). Çakışan izin, kilitli ay ve iş günüyle uyuşmayan saat reddedilir."
            onay="İzni kaydet"
            islem={saatlikIzinGir}
          >
            <Alan etiket="Çalışanın sicil numarası" htmlFor="s-sicil" ipucu="Yazmaya başlayınca liste açılır.">
              <Input id="s-sicil" name="sicil" list="izin-calisanlar" required autoComplete="off" inputMode="numeric" />
            </Alan>
            <div className="grid grid-cols-3 gap-3">
              <Alan etiket="Gün" htmlFor="s-tarih">
                <Input id="s-tarih" name="tarih" type="date" required defaultValue={bugunTarih} />
              </Alan>
              <Alan etiket="Başlangıç" htmlFor="s-bas">
                <Input id="s-bas" name="bas_saat" type="time" required defaultValue="10:00" />
              </Alan>
              <Alan etiket="Bitiş" htmlFor="s-bit">
                <Input id="s-bit" name="bit_saat" type="time" required defaultValue="12:00" />
              </Alan>
            </div>
            <Alan etiket="Tür" htmlFor="s-tur">
              <Secim id="s-tur" name="tur" required defaultValue="" className="h-9">
                <option value="" disabled>Seçin</option>
                {Object.entries(SAATLIK_TUR).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
              </Secim>
            </Alan>
            <Alan etiket="Açıklama (isteğe bağlı)" htmlFor="s-aciklama">
              <Textarea id="s-aciklama" name="aciklama" rows={2} maxLength={500} />
            </Alan>
          </IslemPenceresi>
          <CalisanListesi id="izin-calisanlar" calisanlar={calisanlar} />
        </div>
      </div>

      <section aria-labelledby="gun-baslik" className="flex flex-col gap-3">
        <div className="flex flex-col gap-1">
          <h2 id="gun-baslik" className="text-lg font-semibold">Gün bazlı izinler</h2>
          <p className="text-sm text-muted-foreground">
            {gecerli.length} izin{izinler.length > gecerli.length && ` · ${izinler.length - gecerli.length} iptal edilmiş`}
          </p>
        </div>
        {izinler.length === 0 ? (
          <BosDurum>Bu ayda izin yok.</BosDurum>
        ) : (
          <div className="rounded-lg border">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Çalışan</TableHead>
                  <TableHead>Tür</TableHead>
                  <TableHead>Tarih</TableHead>
                  <TableHead>Açıklama</TableHead>
                  <TableHead>Giren</TableHead>
                  <TableHead><span className="sr-only">İşlem</span></TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {izinler.map((i) => (
                  <TableRow key={i.id} className={i.iptal_zamani ? "text-muted-foreground" : undefined}>
                    <TableCell><KisiBaglantisi kisi={i.calisan} ay={ay} /></TableCell>
                    <TableCell>
                      {i.iptal_zamani ? <Badge variant="outline">İptal</Badge> : <Badge variant="secondary">{IZIN_TURU[i.tur] ?? i.tur}</Badge>}
                      {i.iptal_zamani && <span className="ml-2 line-through">{IZIN_TURU[i.tur] ?? i.tur}</span>}
                    </TableCell>
                    <TableCell className="tabular-nums whitespace-nowrap">
                      {tarih(i.baslangic)}{i.bitis !== i.baslangic && ` – ${tarih(i.bitis)}`}
                    </TableCell>
                    <TableCell className="min-w-56 max-w-80 whitespace-normal text-sm">
                      {i.iptal_zamani ? `İptal nedeni: ${i.iptal_nedeni ?? "—"}` : (i.aciklama ?? "—")}
                    </TableCell>
                    <TableCell className="text-sm text-muted-foreground">
                      {i.giren?.ad_soyad ?? "—"}<div className="text-xs">{tarihSaat(i.giris_zamani)}</div>
                    </TableCell>
                    <TableCell className="text-right">
                      {!i.iptal_zamani && i.calisan?.id !== kullanici.calisanId && (
                        <IslemPenceresi
                          dugme="İptal et"
                          dugmeTuru="ghost"
                          baslik="İzni iptal et"
                          aciklama={`${i.calisan ? `${i.calisan.ad} ${i.calisan.soyad}` : "Çalışan"} · ${IZIN_TURU[i.tur] ?? i.tur} · ${tarih(i.baslangic)}${i.bitis !== i.baslangic ? ` – ${tarih(i.bitis)}` : ""}. İzin silinmez; iptal bilgisiyle saklanır. Gece işinden geçmiş günü varsa iptal edilemez, o günler kayıt düzeltmeyle düzeltilir.`}
                          onay="İptal et"
                          onayTuru="destructive"
                          islem={izinIptal}
                          gizli={{ izin_id: i.id }}
                        >
                          <Alan etiket="İptal nedeni" htmlFor="neden">
                            <Textarea id="neden" name="neden" rows={2} required minLength={5} maxLength={500} placeholder="ör. Yanlış çalışana girilmiş" />
                          </Alan>
                        </IslemPenceresi>
                      )}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        )}
      </section>

      <section aria-labelledby="saat-baslik" className="flex flex-col gap-3">
        <div className="flex flex-col gap-1">
          <h2 id="saat-baslik" className="text-lg font-semibold">Saatlik izinler</h2>
          <p className="text-sm text-muted-foreground">{saatlikler.length} izin. Saatlik izin dakikası puantajda ayrıca tutulur.</p>
        </div>
        {saatlikler.length === 0 ? (
          <BosDurum>Bu ayda saatlik izin yok.</BosDurum>
        ) : (
          <div className="rounded-lg border">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Çalışan</TableHead>
                  <TableHead>Gün</TableHead>
                  <TableHead>Saat</TableHead>
                  <TableHead>Tür</TableHead>
                  <TableHead>Açıklama</TableHead>
                  <TableHead>Giren</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {saatlikler.map((s) => (
                  <TableRow key={s.id}>
                    <TableCell><KisiBaglantisi kisi={s.calisan} ay={ay} /></TableCell>
                    <TableCell className="tarih-hucre">{tarih(s.tarih)}</TableCell>
                    <TableCell className="tabular-nums">{saat(s.baslangic)}–{saat(s.bitis)}</TableCell>
                    <TableCell><Badge variant="secondary">{SAATLIK_TUR[s.tur] ?? s.tur}</Badge></TableCell>
                    <TableCell className="min-w-56 max-w-80 whitespace-normal text-sm">{s.aciklama ?? "—"}</TableCell>
                    <TableCell className="text-sm text-muted-foreground">{s.giren?.ad_soyad ?? "—"}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        )}
      </section>
    </div>
  );
}

function KisiBaglantisi({ kisi, ay }: { kisi: Kisi; ay: string }) {
  if (!kisi) return <span className="text-muted-foreground">—</span>;
  return (
    <Link href={`/calisanlar/${kisi.id}?ay=${ay}`} className="underline-offset-4 hover:underline">
      {kisi.ad} {kisi.soyad} <span className="font-mono text-xs text-muted-foreground">({kisi.sicil_no})</span>
    </Link>
  );
}
