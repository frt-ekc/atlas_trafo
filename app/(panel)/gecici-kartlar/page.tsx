import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { CalisanListesi, type ListeCalisani } from "@/components/panel/calisan-listesi";
import { Alan, IslemPenceresi } from "@/components/panel/islem-penceresi";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { aramaSuzgeci } from "@/components/liste/arama";
import { BosDurum } from "@/components/liste/bos-durum";
import { FiltreAlani, FiltreCubugu } from "@/components/liste/filtre-cubugu";
import { TabloKutusu } from "@/components/liste/tablo-kutusu";
import { Zaman } from "@/components/liste/zaman";
import { tekDeger } from "@/lib/arama";
import { geciciKartIadeSaati } from "@/lib/ayar";
import { sure, tarihSaat } from "@/lib/bicim";
import { cn } from "@/lib/utils";
import { rolGerekli } from "@/lib/oturum";
import { tumSatirlar } from "@/lib/supabase/sayfali";
import { sunucuIstemcisi } from "@/lib/supabase/server";
import { kartIadeAl, kartVer } from "./actions";

export const metadata = { title: "Geçici kartlar" };

const SON_HAREKET_SAYISI = 50;

type Kisi = { sicil_no: string; ad: string; soyad: string } | null;

type ZimmetSatiri = {
  id: number;
  gecici_kart_id: number;
  verilis_zamani: string;
  iade_zamani: string | null;
  aciklama: string | null;
  calisan: Kisi;
  veren: { ad_soyad: string } | null;
  iade_alan: { ad_soyad: string } | null;
};

// Zimmetle birlikte çalışanı ve işlemi yapan kullanıcıları da getirir.
// kullanici tablosuna iki ayrı bağ (veren_id, iade_alan_id) olduğu için hangisi olduğu "!" ile belirtilir.
// Güvenlik rolü başka kullanıcıların satırını göremez; o alanlar boş (null) gelir.
const ZIMMET_ALANLARI =
  "id, gecici_kart_id, verilis_zamani, iade_zamani, aciklama, " +
  "calisan:calisan_id(sicil_no, ad, soyad), " +
  "veren:kullanici!veren_id(ad_soyad), iade_alan:kullanici!iade_alan_id(ad_soyad)";

export default async function GeciciKartlarSayfasi({ searchParams }: PageProps<"/gecici-kartlar">) {
  const kullanici = await rolGerekli(["guvenlik", "ik", "yonetici"]);
  const araMetni = tekDeger((await searchParams).ara).slice(0, 100);
  const uyar = aramaSuzgeci(araMetni);
  // Kart verip iade alabilenler: güvenlik ve İK (veritabanı da aynısını denetler). Yönetici yalnızca okur.
  const yazabilir = kullanici.rol === "guvenlik" || kullanici.rol === "ik";
  const supabase = await sunucuIstemcisi();

  const [kartSonucu, acikSonucu, sonSonucu, iadeSaati] = await Promise.all([
    supabase.from("gecici_kart").select("id, kart_no, durum").order("kart_no"),
    supabase.from("gecici_kart_zimmet").select(ZIMMET_ALANLARI).is("iade_zamani", null),
    supabase
      .from("gecici_kart_zimmet")
      .select(ZIMMET_ALANLARI)
      .order("verilis_zamani", { ascending: false })
      .limit(SON_HAREKET_SAYISI),
    geciciKartIadeSaati(supabase),
  ]);

  // Kart verirken sicil numarası listeden seçilebilsin diye aktif çalışanlar
  const calisanlar = yazabilir
    ? await tumSatirlar<ListeCalisani>((bas, son) =>
        supabase.from("calisan").select("sicil_no, ad, soyad").eq("aktif", true).order("sicil_no").range(bas, son),
      )
    : [];

  for (const s of [kartSonucu, acikSonucu, sonSonucu]) {
    if (s.error) throw new Error(`Geçici kart bilgisi okunamadı: ${s.error.message}`);
  }

  const kartlar = kartSonucu.data ?? [];
  const acikZimmetler = (acikSonucu.data ?? []) as unknown as ZimmetSatiri[];
  const sonHareketler = (sonSonucu.data ?? []) as unknown as ZimmetSatiri[];

  const simdi = new Date();
  const kartNo = new Map(kartlar.map((k) => [k.id, k.kart_no]));
  const kimde = new Map(acikZimmetler.map((z) => [z.gecici_kart_id, z]));
  const gecikti = (z: ZimmetSatiri) =>
    !z.iade_zamani && simdi.getTime() - new Date(z.verilis_zamani).getTime() > iadeSaati * 3600_000;

  const bostaSayisi = kartlar.filter((k) => k.durum === "aktif" && !kimde.has(k.id)).length;
  const gecikenSayisi = acikZimmetler.filter(gecikti).length;
  // Hareketlerde ad / sicil / kart numarası araması ekranda yapılır
  const gosterilenHareketler = sonHareketler.filter((z) =>
    uyar(z.calisan?.ad, z.calisan?.soyad, z.calisan?.sicil_no, kartNo.get(z.gecici_kart_id)),
  );

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-col gap-1">
        <h1 className="text-2xl font-semibold">Geçici kartlar</h1>
        <p className="text-sm text-muted-foreground">
          {kartlar.length} kart · {bostaSayisi} kullanılabilir · {acikZimmetler.length} zimmetli
          {gecikenSayisi > 0 && ` · ${gecikenSayisi} kart ${iadeSaati} saatten uzun süredir iade edilmedi`}
        </p>
      </div>

      <section className="flex flex-col gap-3" aria-labelledby="kartlar-baslik">
        <h2 id="kartlar-baslik" className="text-lg font-semibold">Kartlar</h2>
        {kartlar.length === 0 ? (
          <BosDurum aciklama="Kayıt bulunmuyor." />
        ) : (
          // Kart başına küçük bir kutu: boşta ise "Ver", zimmetliyse kişi ve süreyle "İade al"
          <ul className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-5">
            {kartlar.map((k) => {
              const z = kimde.get(k.id);
              const gec = z ? gecikti(z) : false;
              return (
                <li
                  key={k.id}
                  className={cn(
                    "flex flex-col gap-3 rounded-xl border bg-card p-4",
                    gec && "border-l-4 border-l-kotu",
                    (k.durum === "kayip" || k.durum === "iptal") && "bg-card/50 text-muted-foreground",
                  )}
                >
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <span className="font-mono text-base font-semibold whitespace-nowrap">{k.kart_no}</span>
                    <KartDurumu durum={k.durum} zimmetli={Boolean(z)} gecikti={gec} />
                  </div>
                  {z ? (
                    <dl className="flex flex-1 flex-col gap-1 text-sm">
                      <dt className="sr-only">Zimmetli çalışan</dt>
                      <dd><KisiAdi kisi={z.calisan} /></dd>
                      <dt className="sr-only">Veriliş zamanı</dt>
                      <dd className="text-xs text-muted-foreground"><Zaman deger={z.verilis_zamani} etiket="Veriliş zamanı" /></dd>
                      <dt className="sr-only">Süre</dt>
                      <dd className={cn("text-xs tabular-nums", gec ? "font-medium text-kotu" : "text-muted-foreground")}>
                        Süre: {sure(z.verilis_zamani, null, simdi)}
                      </dd>
                    </dl>
                  ) : (
                    <p className="flex-1 text-sm text-muted-foreground">
                      {k.durum === "aktif" ? "Zimmetlenebilir." : "Kullanılamaz."}
                    </p>
                  )}
                  {yazabilir && (z ? (
                    <IadeAlPenceresi kartNo={k.kart_no} zimmet={z} />
                  ) : k.durum === "aktif" ? (
                    <KartVerPenceresi kartId={k.id} kartNo={k.kart_no} />
                  ) : null)}
                </li>
              );
            })}
          </ul>
        )}
        {yazabilir && (
          <CalisanListesi id="calisan-listesi" calisanlar={calisanlar} />
        )}
      </section>

      <section className="flex flex-col gap-3" aria-labelledby="hareket-baslik">
        <div className="flex flex-col gap-1">
          <h2 id="hareket-baslik" className="text-lg font-semibold">Son zimmet hareketleri</h2>
          <p className="text-sm text-muted-foreground">Son {SON_HAREKET_SAYISI} kayıt gösterilir. Zimmet kayıtları silinemez.</p>
        </div>
        <FiltreCubugu temizleAdres="/gecici-kartlar" suzgecVar={Boolean(araMetni)}>
          <FiltreAlani etiket="Çalışan veya kart ara" htmlFor="ara" className="min-w-48 flex-1 sm:max-w-xs">
            <Input id="ara" name="ara" type="search" defaultValue={araMetni} placeholder="Ad, sicil veya GK-01" />
          </FiltreAlani>
        </FiltreCubugu>
        {gosterilenHareketler.length === 0 ? (
          <BosDurum aciklama={sonHareketler.length === 0 ? "Kayıt bulunmuyor." : "Seçilen filtrelere uygun kayıt bulunmuyor."} />
        ) : (
          <TabloKutusu>
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Veriliş zamanı</TableHead>
                  <TableHead>Kart</TableHead>
                  <TableHead>Çalışan</TableHead>
                  <TableHead>İade</TableHead>
                  <TableHead>Süre</TableHead>
                  <TableHead>Veren / İade alan</TableHead>
                  <TableHead className="w-full">Açıklama</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {gosterilenHareketler.map((z) => (
                  <TableRow key={z.id}>
                    <TableCell className="tarih-hucre">{tarihSaat(z.verilis_zamani)}</TableCell>
                    <TableCell className="font-mono">{kartNo.get(z.gecici_kart_id) ?? "—"}</TableCell>
                    <TableCell><KisiAdi kisi={z.calisan} /></TableCell>
                    <TableCell className="tabular-nums">
                      {z.iade_zamani ? (
                        tarihSaat(z.iade_zamani)
                      ) : (
                        <Badge variant={gecikti(z) ? "destructive" : "default"}>
                          {gecikti(z) ? "İade bekleniyor" : "Zimmetli"}
                        </Badge>
                      )}
                    </TableCell>
                    <TableCell className="tabular-nums">{sure(z.verilis_zamani, z.iade_zamani, simdi)}</TableCell>
                    <TableCell className="min-w-36 whitespace-normal text-muted-foreground">
                      {z.veren?.ad_soyad ?? "—"} / {z.iade_zamani ? (z.iade_alan?.ad_soyad ?? "—") : "—"}
                    </TableCell>
                    <TableCell className="min-w-48 whitespace-normal text-muted-foreground">{z.aciklama ?? "—"}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </TabloKutusu>
        )}
      </section>
    </div>
  );
}

function KartVerPenceresi({ kartId, kartNo }: { kartId: number; kartNo: string }) {
  return (
    <IslemPenceresi
      dugme="Zimmetle"
      dugmeTuru="default"
      baslik={`${kartNo} kartını zimmetle`}
      aciklama="Geçici kart çalışana zimmetlenir. Kart gün sonunda iade alınmalıdır."
      onay="Zimmetle"
      islem={kartVer}
      gizli={{ kart_id: kartId, kart_no: kartNo }}
    >
      <Alan etiket="Çalışanın sicil numarası" htmlFor="sicil" ipucu="Kullanıcı kendisine kart zimmetleyemez.">
        <Input id="sicil" name="sicil" list="calisan-listesi" required autoComplete="off" inputMode="numeric" autoFocus />
      </Alan>
      <Alan etiket="Açıklama (isteğe bağlı)" htmlFor="aciklama">
        <Textarea id="aciklama" name="aciklama" rows={2} maxLength={500} placeholder="ör. Kart unutuldu" />
      </Alan>
    </IslemPenceresi>
  );
}

function IadeAlPenceresi({ kartNo, zimmet }: { kartNo: string; zimmet: ZimmetSatiri }) {
  const kisi = zimmet.calisan ? `${zimmet.calisan.ad} ${zimmet.calisan.soyad}` : "çalışan";
  return (
    <IslemPenceresi
      dugme="İade al"
      dugmeTuru="secondary"
      baslik={`${kartNo} kartını iade al`}
      aciklama={`${kisi} kartı ${tarihSaat(zimmet.verilis_zamani)} tarihinde teslim almıştır. İade zamanı sonradan değiştirilemez.`}
      onay="İade al"
      islem={kartIadeAl}
      gizli={{ zimmet_id: zimmet.id, kart_no: kartNo }}
    />
  );
}

function KartDurumu({ durum, zimmetli, gecikti }: { durum: string; zimmetli: boolean; gecikti: boolean }) {
  if (durum === "kayip") return <Badge variant="destructive">Kayıp</Badge>;
  if (durum === "iptal") return <Badge variant="outline">İptal</Badge>;
  if (zimmetli) return <Badge variant={gecikti ? "destructive" : "default"}>{gecikti ? "İade bekleniyor" : "Zimmetli"}</Badge>;
  return <Badge variant="secondary">Kullanılabilir</Badge>;
}

function KisiAdi({ kisi }: { kisi: Kisi }) {
  if (!kisi) return <span className="text-muted-foreground">—</span>;
  return (
    <span>
      {kisi.ad} {kisi.soyad} <span className="font-mono text-xs text-muted-foreground">{kisi.sicil_no}</span>
    </span>
  );
}
