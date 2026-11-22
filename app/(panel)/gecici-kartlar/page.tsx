import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { CalisanListesi, type ListeCalisani } from "@/components/panel/calisan-listesi";
import { Alan, IslemPenceresi } from "@/components/panel/islem-penceresi";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { sure, tarihSaat } from "@/lib/bicim";
import { rolGerekli } from "@/lib/oturum";
import { tumSatirlar } from "@/lib/supabase/sayfali";
import { sunucuIstemcisi } from "@/lib/supabase/server";
import { kartIadeAl, kartVer } from "./actions";

export const metadata = { title: "Geçici kartlar" };

// Veritabanındaki varsayılan (ayar: gecici_kart_iade_saat). Güvenlik ayar tablosunu
// okuyamadığı için o rolde bu değer kullanılır.
const VARSAYILAN_IADE_SAATI = 16;
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

export default async function GeciciKartlarSayfasi() {
  const kullanici = await rolGerekli(["guvenlik", "ik", "yonetici"]);
  // Kart verip iade alabilenler: güvenlik ve İK (veritabanı da aynısını denetler). Yönetici yalnızca okur.
  const yazabilir = kullanici.rol === "guvenlik" || kullanici.rol === "ik";
  const supabase = await sunucuIstemcisi();

  const [kartSonucu, acikSonucu, sonSonucu, ayarSonucu] = await Promise.all([
    supabase.from("gecici_kart").select("id, kart_no, durum").order("kart_no"),
    supabase.from("gecici_kart_zimmet").select(ZIMMET_ALANLARI).is("iade_zamani", null),
    supabase
      .from("gecici_kart_zimmet")
      .select(ZIMMET_ALANLARI)
      .order("verilis_zamani", { ascending: false })
      .limit(SON_HAREKET_SAYISI),
    kullanici.rol === "guvenlik"
      ? Promise.resolve(null)
      : supabase.from("ayar").select("deger").eq("anahtar", "gecici_kart_iade_saat").maybeSingle(),
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
  const iadeSaati = Number(ayarSonucu?.data?.deger) || VARSAYILAN_IADE_SAATI;

  const simdi = new Date();
  const kartNo = new Map(kartlar.map((k) => [k.id, k.kart_no]));
  const kimde = new Map(acikZimmetler.map((z) => [z.gecici_kart_id, z]));
  const gecikti = (z: ZimmetSatiri) =>
    !z.iade_zamani && simdi.getTime() - new Date(z.verilis_zamani).getTime() > iadeSaati * 3600_000;

  const bostaSayisi = kartlar.filter((k) => k.durum === "aktif" && !kimde.has(k.id)).length;
  const gecikenSayisi = acikZimmetler.filter(gecikti).length;

  return (
    <div className="flex flex-col gap-8">
      <div className="flex flex-col gap-1">
        <h1 className="text-2xl font-semibold">Geçici kartlar</h1>
        <p className="text-sm text-muted-foreground">
          {kartlar.length} kart · {bostaSayisi} boşta · {acikZimmetler.length} zimmetli
          {gecikenSayisi > 0 && ` · ${gecikenSayisi} kart ${iadeSaati} saatten uzun süredir iade edilmedi`}
        </p>
      </div>

      <section className="flex flex-col gap-3" aria-labelledby="kartlar-baslik">
        <h2 id="kartlar-baslik" className="text-lg font-semibold">Kartlar</h2>
        {kartlar.length === 0 ? (
          <BosDurum>Kayıtlı geçici kart yok.</BosDurum>
        ) : (
          <div className="rounded-lg border">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead className="w-28">Kart</TableHead>
                  <TableHead>Durum</TableHead>
                  <TableHead>Kimde</TableHead>
                  <TableHead>Veriliş</TableHead>
                  <TableHead>Süre</TableHead>
                  {yazabilir && <TableHead className="w-28"><span className="sr-only">İşlem</span></TableHead>}
                </TableRow>
              </TableHeader>
              <TableBody>
                {kartlar.map((k) => {
                  const z = kimde.get(k.id);
                  return (
                    <TableRow key={k.id}>
                      <TableCell className="font-mono font-medium">{k.kart_no}</TableCell>
                      <TableCell><KartDurumu durum={k.durum} zimmetli={Boolean(z)} gecikti={z ? gecikti(z) : false} /></TableCell>
                      <TableCell>{z ? <KisiAdi kisi={z.calisan} /> : "—"}</TableCell>
                      <TableCell className="tabular-nums">{z ? tarihSaat(z.verilis_zamani) : "—"}</TableCell>
                      <TableCell className="tabular-nums">{z ? sure(z.verilis_zamani, null, simdi) : "—"}</TableCell>
                      {yazabilir && (
                        <TableCell className="text-right">
                          {z ? (
                            <IadeAlPenceresi kartNo={k.kart_no} zimmet={z} />
                          ) : k.durum === "aktif" ? (
                            <KartVerPenceresi kartId={k.id} kartNo={k.kart_no} />
                          ) : null}
                        </TableCell>
                      )}
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          </div>
        )}
        {yazabilir && (
          <CalisanListesi id="calisan-listesi" calisanlar={calisanlar} />
        )}
      </section>

      <section className="flex flex-col gap-3" aria-labelledby="hareket-baslik">
        <div className="flex flex-col gap-1">
          <h2 id="hareket-baslik" className="text-lg font-semibold">Son zimmet hareketleri</h2>
          <p className="text-sm text-muted-foreground">En yeni {SON_HAREKET_SAYISI} kayıt. Zimmet kayıtları silinemez.</p>
        </div>
        {sonHareketler.length === 0 ? (
          <BosDurum>Henüz zimmet kaydı yok.</BosDurum>
        ) : (
          <div className="rounded-lg border">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead className="w-28">Kart</TableHead>
                  <TableHead>Çalışan</TableHead>
                  <TableHead>Veriliş</TableHead>
                  <TableHead>İade</TableHead>
                  <TableHead>Süre</TableHead>
                  <TableHead>Veren / İade alan</TableHead>
                  <TableHead>Açıklama</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {sonHareketler.map((z) => (
                  <TableRow key={z.id}>
                    <TableCell className="font-mono">{kartNo.get(z.gecici_kart_id) ?? "—"}</TableCell>
                    <TableCell><KisiAdi kisi={z.calisan} /></TableCell>
                    <TableCell className="tarih-hucre">{tarihSaat(z.verilis_zamani)}</TableCell>
                    <TableCell className="tabular-nums">
                      {z.iade_zamani ? (
                        tarihSaat(z.iade_zamani)
                      ) : (
                        <Badge variant={gecikti(z) ? "destructive" : "default"}>
                          {gecikti(z) ? "İade edilmedi" : "Zimmetli"}
                        </Badge>
                      )}
                    </TableCell>
                    <TableCell className="tabular-nums">{sure(z.verilis_zamani, z.iade_zamani, simdi)}</TableCell>
                    <TableCell className="text-muted-foreground">
                      {z.veren?.ad_soyad ?? "—"} / {z.iade_zamani ? (z.iade_alan?.ad_soyad ?? "—") : "—"}
                    </TableCell>
                    <TableCell className="max-w-64 truncate text-muted-foreground" title={z.aciklama ?? undefined}>
                      {z.aciklama ?? "—"}
                    </TableCell>
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

function KartVerPenceresi({ kartId, kartNo }: { kartId: number; kartNo: string }) {
  return (
    <IslemPenceresi
      dugme="Ver"
      baslik={`${kartNo} kartını ver`}
      aciklama="Kartını unutan çalışana geçici kart zimmetlenir. Kart gün sonunda iade alınmalıdır."
      onay="Kartı ver"
      islem={kartVer}
      gizli={{ kart_id: kartId, kart_no: kartNo }}
    >
      <Alan etiket="Çalışanın sicil numarası" htmlFor="sicil" ipucu="Yazmaya başlayınca liste açılır. Kendinize kart veremezsiniz.">
        <Input id="sicil" name="sicil" list="calisan-listesi" required autoComplete="off" inputMode="numeric" autoFocus />
      </Alan>
      <Alan etiket="Açıklama (isteğe bağlı)" htmlFor="aciklama">
        <Textarea id="aciklama" name="aciklama" rows={2} maxLength={500} placeholder="ör. Kartını evde unuttu" />
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
      aciklama={`${kisi} kartı ${tarihSaat(zimmet.verilis_zamani)} tarihinde almıştı. İade zamanı şu an olarak yazılır ve sonradan değiştirilemez.`}
      onay="İade alındı"
      islem={kartIadeAl}
      gizli={{ zimmet_id: zimmet.id, kart_no: kartNo }}
    />
  );
}

function KartDurumu({ durum, zimmetli, gecikti }: { durum: string; zimmetli: boolean; gecikti: boolean }) {
  if (durum === "kayip") return <Badge variant="destructive">Kayıp</Badge>;
  if (durum === "iptal") return <Badge variant="outline">İptal</Badge>;
  if (zimmetli) return <Badge variant={gecikti ? "destructive" : "default"}>{gecikti ? "İade edilmedi" : "Zimmetli"}</Badge>;
  return <Badge variant="secondary">Boşta</Badge>;
}

function KisiAdi({ kisi }: { kisi: Kisi }) {
  if (!kisi) return <span className="text-muted-foreground">—</span>;
  return (
    <span>
      {kisi.ad} {kisi.soyad} <span className="font-mono text-xs text-muted-foreground">({kisi.sicil_no})</span>
    </span>
  );
}

function BosDurum({ children }: { children: React.ReactNode }) {
  return <div className="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">{children}</div>;
}
