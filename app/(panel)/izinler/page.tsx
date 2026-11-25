import Link from "next/link";
import { Badge } from "@/components/ui/badge";
import { buttonVariants } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Textarea } from "@/components/ui/textarea";
import { CalisanListesi, type ListeCalisani } from "@/components/panel/calisan-listesi";
import { CalisanSecici } from "@/components/panel/calisan-secici";
import { Alan, IslemPenceresi } from "@/components/panel/islem-penceresi";
import { Secim } from "@/components/panel/secim";
import { aramaSuzgeci } from "@/components/liste/arama";
import { BosDurum } from "@/components/liste/bos-durum";
import { DurumIslem } from "@/components/liste/durum-islem";
import { DurumRozeti } from "@/components/liste/durum-rozeti";
import { FiltreAlani, FiltreCubugu } from "@/components/liste/filtre-cubugu";
import { IslemMenusu } from "@/components/liste/islem-menusu";
import { Sekmeler } from "@/components/liste/sekmeler";
import { TabloKutusu } from "@/components/liste/tablo-kutusu";
import { Zaman } from "@/components/liste/zaman";
import { tekDeger } from "@/lib/arama";
import { saat, tarih } from "@/lib/bicim";
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
  const saatlikSekme = tekDeger(parametre.sekme) === "saatlik";
  const araMetni = tekDeger(parametre.ara).slice(0, 100);
  const uyar = aramaSuzgeci(araMetni);

  const supabase = await sunucuIstemcisi();
  const [ayinIzinleri, ayinSaatlikleri, calisanlar] = await Promise.all([
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

  // Ad / sicil araması ekranda süzülür
  const izinler = ayinIzinleri.filter((i) => uyar(i.calisan?.ad, i.calisan?.soyad, i.calisan?.sicil_no));
  const saatlikler = ayinSaatlikleri.filter((s) => uyar(s.calisan?.ad, s.calisan?.soyad, s.calisan?.sicil_no));
  const gecerli = izinler.filter((i) => !i.iptal_zamani);
  const adres = (a: string) => `/izinler?ay=${a}${saatlikSekme ? "&sekme=saatlik" : ""}`;
  const sekmeAdresi = (saatlik: boolean) => {
    const p = new URLSearchParams({ ay });
    if (saatlik) p.set("sekme", "saatlik");
    if (araMetni) p.set("ara", araMetni);
    return `/izinler?${p}`;
  };
  // Açıklama türün adını tekrar ediyorsa (ör. tür "Yıllık izin", açıklama "Yıllık izin") gösterilmez
  const ayniMi = (a: string | null, b: string) => !a || a.trim().toLocaleLowerCase("tr") === b.toLocaleLowerCase("tr");

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-col gap-1">
        <h1 className="text-2xl font-semibold">İzinler · {ayAdi(ay)}</h1>
        <p className="text-sm text-muted-foreground">
          Gün ve saat bazlı izinler. İzin kayıtları silinmez, iptal edilir. İzin türü yalnızca İK tarafından görüntülenir (KVKK).
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
            dugme="İzin ekle"
            dugmeTuru="default"
            baslik="Gün bazlı izin"
            aciklama="Kullanıcı kendi iznini ekleyemez. İzin günleri gece işleminde kayıtlara yansıtılır."
            onay="Kaydet"
            islem={izinGir}
          >
            <Alan etiket="Çalışanın sicil numarası" htmlFor="sicil" ipucu="Sicil numarası veya ad ile arama yapılabilir.">
              <CalisanSecici listeId="izin-calisanlar" id="sicil" required />
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
            dugme="Saatlik izin ekle"
            baslik="Saatlik izin"
            aciklama="Gün içindeki saatlik izinler (vizite, mazeret). İzin; başka bir izinle çakışmamalı, açık bir aya ait olmalı ve iş günü içinde yer almalıdır."
            onay="Kaydet"
            islem={saatlikIzinGir}
          >
            <Alan etiket="Çalışanın sicil numarası" htmlFor="s-sicil" ipucu="Sicil numarası veya ad ile arama yapılabilir.">
              <CalisanSecici listeId="izin-calisanlar" id="s-sicil" required />
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

      <Sekmeler
        etiket="İzin türü"
        sekmeler={[
          { ad: "Gün bazlı", adres: sekmeAdresi(false), sayi: gecerli.length, aktif: !saatlikSekme },
          { ad: "Saatlik", adres: sekmeAdresi(true), sayi: saatlikler.length, aktif: saatlikSekme },
        ]}
      />

      <FiltreCubugu temizleAdres={saatlikSekme ? `/izinler?ay=${ay}&sekme=saatlik` : `/izinler?ay=${ay}`} suzgecVar={Boolean(araMetni)}>
        <input type="hidden" name="ay" value={ay} />
        {saatlikSekme && <input type="hidden" name="sekme" value="saatlik" />}
        <FiltreAlani etiket="Çalışan ara" htmlFor="ara" className="min-w-48 flex-1 sm:max-w-xs">
          <Input id="ara" name="ara" type="search" defaultValue={araMetni} placeholder="Ad, soyad veya sicil" />
        </FiltreAlani>
      </FiltreCubugu>

      {!saatlikSekme ? (
        <section aria-labelledby="gun-baslik" className="flex flex-col gap-3">
          <div className="flex flex-col gap-1">
            <h2 id="gun-baslik" className="text-lg font-semibold">Gün bazlı izinler</h2>
            <p className="text-sm text-muted-foreground">
              {gecerli.length} izin{izinler.length > gecerli.length && ` · ${izinler.length - gecerli.length} iptal edilmiş`}
            </p>
          </div>
          {izinler.length === 0 ? (
            <BosDurum aciklama={araMetni ? "Seçilen filtrelere uygun kayıt bulunmuyor." : "Kayıt bulunmuyor."} />
          ) : (
            <TabloKutusu>
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Tarih</TableHead>
                    <TableHead>Çalışan</TableHead>
                    <TableHead>Tür</TableHead>
                    <TableHead className="w-full">Açıklama</TableHead>
                    <TableHead>Ekleyen</TableHead>
                    <TableHead>Durum</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {izinler.map((i) => {
                    const turAdi = IZIN_TURU[i.tur] ?? i.tur;
                    return (
                      <TableRow key={i.id} className={i.iptal_zamani ? "text-muted-foreground" : undefined}>
                        <TableCell className="tabular-nums">
                          {tarih(i.baslangic)}{i.bitis !== i.baslangic && ` – ${tarih(i.bitis)}`}
                        </TableCell>
                        <TableCell><KisiBaglantisi kisi={i.calisan} ay={ay} /></TableCell>
                        <TableCell>
                          <Badge variant={i.iptal_zamani ? "outline" : "secondary"} className={i.iptal_zamani ? "line-through" : undefined}>
                            {turAdi}
                          </Badge>
                        </TableCell>
                        <TableCell className="min-w-56 whitespace-normal text-sm">
                          {i.iptal_zamani ? `İptal nedeni: ${i.iptal_nedeni ?? "—"}` : ayniMi(i.aciklama, turAdi) ? "" : i.aciklama}
                        </TableCell>
                        <TableCell className="text-sm text-muted-foreground">
                          {i.giren?.ad_soyad ?? "—"}
                          <div className="text-xs"><Zaman deger={i.giris_zamani} /></div>
                        </TableCell>
                        <TableCell>
                          <DurumIslem
                            durum={i.iptal_zamani ? <DurumRozeti ton="notr">İptal edildi</DurumRozeti> : <DurumRozeti ton="iyi">Geçerli</DurumRozeti>}
                          >
                            {!i.iptal_zamani && i.calisan?.id !== kullanici.calisanId && (
                              <IslemMenusu>
                                <IslemPenceresi
                                  dugme="İptal et"
                                  dugmeTuru="ghost"
                                  baslik="İzni iptal et"
                                  aciklama={`${i.calisan ? `${i.calisan.ad} ${i.calisan.soyad}` : "Çalışan"} · ${turAdi} · ${tarih(i.baslangic)}${i.bitis !== i.baslangic ? ` – ${tarih(i.bitis)}` : ""}. İzin kaydı silinmez, iptal bilgisiyle saklanır. İzin girildiğinde değiştirilen günler önceki durumuna döner. İzinli olarak işlenmiş diğer günler önce kayıt düzeltme ile güncellenmelidir.`}
                                  onay="İptal et"
                                  onayTuru="destructive"
                                  islem={izinIptal}
                                  gizli={{ izin_id: i.id }}
                                >
                                  <Alan etiket="İptal nedeni" htmlFor="neden">
                                    <Textarea id="neden" name="neden" rows={2} required minLength={5} maxLength={500} placeholder="ör. Hatalı çalışan seçimi" />
                                  </Alan>
                                </IslemPenceresi>
                              </IslemMenusu>
                            )}
                          </DurumIslem>
                        </TableCell>
                      </TableRow>
                    );
                  })}
                </TableBody>
              </Table>
            </TabloKutusu>
          )}
        </section>
      ) : (
        <section aria-labelledby="saat-baslik" className="flex flex-col gap-3">
          <div className="flex flex-col gap-1">
            <h2 id="saat-baslik" className="text-lg font-semibold">Saatlik izinler</h2>
            <p className="text-sm text-muted-foreground">{saatlikler.length} izin. Saatlik izin süresi puantajda ayrıca gösterilir.</p>
          </div>
          {saatlikler.length === 0 ? (
            <BosDurum aciklama={araMetni ? "Seçilen filtrelere uygun kayıt bulunmuyor." : "Kayıt bulunmuyor."} />
          ) : (
            <TabloKutusu>
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Gün</TableHead>
                    <TableHead>Saat</TableHead>
                    <TableHead>Çalışan</TableHead>
                    <TableHead>Tür</TableHead>
                    <TableHead className="w-full">Açıklama</TableHead>
                    <TableHead>Ekleyen</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {saatlikler.map((s) => {
                    const turAdi = SAATLIK_TUR[s.tur] ?? s.tur;
                    return (
                      <TableRow key={s.id}>
                        <TableCell className="tarih-hucre">{tarih(s.tarih)}</TableCell>
                        <TableCell className="tabular-nums">{saat(s.baslangic)}–{saat(s.bitis)}</TableCell>
                        <TableCell><KisiBaglantisi kisi={s.calisan} ay={ay} /></TableCell>
                        <TableCell><Badge variant="secondary">{turAdi}</Badge></TableCell>
                        <TableCell className="min-w-56 whitespace-normal text-sm">{ayniMi(s.aciklama, turAdi) ? "" : s.aciklama}</TableCell>
                        <TableCell className="text-sm text-muted-foreground">{s.giren?.ad_soyad ?? "—"}</TableCell>
                      </TableRow>
                    );
                  })}
                </TableBody>
              </Table>
            </TabloKutusu>
          )}
        </section>
      )}
    </div>
  );
}

function KisiBaglantisi({ kisi, ay }: { kisi: Kisi; ay: string }) {
  if (!kisi) return <span className="text-muted-foreground">—</span>;
  return (
    <Link href={`/calisanlar/${kisi.id}?ay=${ay}`} className="underline-offset-4 hover:underline">
      {kisi.ad} {kisi.soyad}
      <span className="block font-mono text-xs text-muted-foreground">{kisi.sicil_no}</span>
    </Link>
  );
}
