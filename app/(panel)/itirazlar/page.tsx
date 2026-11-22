import Link from "next/link";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { BosDurum } from "@/components/panel/bos-durum";
import { HizliIslem } from "@/components/panel/hizli-islem";
import { IslemPenceresi } from "@/components/panel/islem-penceresi";
import { KararAlanlari } from "@/components/panel/karar-alanlari";
import { SuzgecFormu } from "@/components/panel/suzgec-formu";
import { Secim } from "@/components/panel/secim";
import { tekDeger } from "@/lib/arama";
import { tarih, tarihSaat } from "@/lib/bicim";
import { ITIRAZ_DURUMU } from "@/lib/etiketler";
import { rolGerekli } from "@/lib/oturum";
import { tumSatirlar } from "@/lib/supabase/sayfali";
import { sunucuIstemcisi } from "@/lib/supabase/server";
import { itirazIncelemeyeAl, itirazKarar } from "./actions";

export const metadata = { title: "İtirazlar" };

type Itiraz = {
  id: number;
  metin: string;
  durum: string;
  olusturma_zamani: string;
  karar_aciklama: string | null;
  karar_zamani: string | null;
  calisan: { id: number; sicil_no: string; ad: string; soyad: string } | null;
  gun: { is_gunu: string } | null;
  karar_veren: { ad_soyad: string } | null;
};

// Çalışan itirazını amire ya da İK'ya sözlü/yazılı iletir; amir ya da İK sisteme girer.
// İtirazın reddi çalışan aleyhine bir karardır: yalnızca İK verir.
export default async function ItirazlarSayfasi({ searchParams }: PageProps<"/itirazlar">) {
  const kullanici = await rolGerekli(["amir", "ik", "yonetici"]);
  const parametre = await searchParams;
  const tumu = tekDeger(parametre.goster) === "tumu";
  const ik = kullanici.rol === "ik";

  const supabase = await sunucuIstemcisi();
  const itirazlar = await tumSatirlar<Itiraz>((bas, son) => {
    let q = supabase
      .from("itiraz")
      .select(
        "id, metin, durum, olusturma_zamani, karar_aciklama, karar_zamani, " +
          "calisan:calisan_id(id, sicil_no, ad, soyad), gun:gun_kaydi_id(is_gunu), karar_veren:kullanici!karar_veren_id(ad_soyad)",
      )
      .order("olusturma_zamani", { ascending: false })
      .order("id")
      .range(bas, son);
    if (!tumu) q = q.in("durum", ["acik", "inceleniyor"]);
    return q;
  });

  return (
    <div className="flex flex-col gap-5">
      <div className="flex flex-col gap-1">
        <h1 className="text-2xl font-semibold">İtirazlar</h1>
        <p className="text-sm text-muted-foreground">
          {kullanici.rol === "amir"
            ? "Bölümünüzdeki çalışanların kayıtlarına itirazları. Kararı İK verir."
            : "Çalışanların kayıtlarına itirazları. Kabul ya da red kararı İK'dadır."}
        </p>
      </div>

      <SuzgecFormu className="flex items-end gap-2">
        <div className="flex flex-col gap-1.5">
          <label htmlFor="goster" className="text-sm font-medium">Göster</label>
          <Secim id="goster" name="goster" defaultValue={tumu ? "tumu" : ""}>
            <option value="">Açık olanlar</option>
            <option value="tumu">Tümü</option>
          </Secim>
        </div>
        <Button type="submit" size="sm">Göster</Button>
      </SuzgecFormu>

      <p className="text-sm text-muted-foreground" aria-live="polite">{itirazlar.length} itiraz</p>

      {itirazlar.length === 0 ? (
        <BosDurum>{tumu ? "Hiç itiraz yok." : "Açık itiraz yok."}</BosDurum>
      ) : (
        <div className="rounded-lg border">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Giriş</TableHead>
                <TableHead>Çalışan</TableHead>
                <TableHead>Gün</TableHead>
                <TableHead>İtiraz</TableHead>
                <TableHead>Durum</TableHead>
                {ik && <TableHead><span className="sr-only">İşlem</span></TableHead>}
              </TableRow>
            </TableHeader>
            <TableBody>
              {itirazlar.map((i) => (
                <TableRow key={i.id}>
                  <TableCell className="tarih-hucre">{tarihSaat(i.olusturma_zamani)}</TableCell>
                  <TableCell>
                    {i.calisan ? (
                      <Link
                        href={`/calisanlar/${i.calisan.id}${i.gun ? `?ay=${i.gun.is_gunu.slice(0, 7)}` : ""}`}
                        className="underline-offset-4 hover:underline"
                      >
                        {i.calisan.ad} {i.calisan.soyad} <span className="font-mono text-xs text-muted-foreground">({i.calisan.sicil_no})</span>
                      </Link>
                    ) : "—"}
                  </TableCell>
                  <TableCell className="tabular-nums">{i.gun ? tarih(i.gun.is_gunu) : "—"}</TableCell>
                  <TableCell className="min-w-80 max-w-[32rem] whitespace-normal">
                    {i.metin}
                    {i.karar_zamani && (
                      <div className="mt-1 text-sm text-muted-foreground">
                        Karar: {i.karar_aciklama ?? "—"} · {i.karar_veren?.ad_soyad ?? "—"}, {tarihSaat(i.karar_zamani)}
                      </div>
                    )}
                  </TableCell>
                  <TableCell>
                    <Badge variant={ITIRAZ_DURUMU[i.durum]?.tur ?? "outline"}>{ITIRAZ_DURUMU[i.durum]?.ad ?? i.durum}</Badge>
                  </TableCell>
                  {ik && (
                    <TableCell>
                      <div className="flex justify-end gap-2">
                        {i.durum === "acik" && <HizliIslem dugme="İncelemeye al" islem={itirazIncelemeyeAl} gizli={{ itiraz_id: i.id }} />}
                        {(i.durum === "acik" || i.durum === "inceleniyor") && <KararPenceresi itiraz={i} />}
                      </div>
                    </TableCell>
                  )}
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      )}

      {kullanici.rol !== "yonetici" && (
        <p className="text-sm text-muted-foreground">
          Yeni itiraz, çalışanın sayfasında ilgili günün yanındaki <span className="font-medium">İtiraz</span> düğmesiyle girilir.
        </p>
      )}
    </div>
  );
}

function KararPenceresi({ itiraz }: { itiraz: Itiraz }) {
  const kisi = itiraz.calisan ? `${itiraz.calisan.ad} ${itiraz.calisan.soyad}` : "Çalışan";
  return (
    <IslemPenceresi
      dugme="Karar ver"
      dugmeTuru="default"
      baslik={`${kisi} · ${itiraz.gun ? tarih(itiraz.gun.is_gunu) : ""} itirazı`}
      aciklama={`"${itiraz.metin}"`}
      onay="Kararı kaydet"
      islem={itirazKarar}
      gizli={{ itiraz_id: itiraz.id }}
    >
      <KararAlanlari
        onayAdi="Kabul et"
        retAdi="Reddet"
        gerekceZorunlu="her_zaman"
        retUyarisi="Red çalışan aleyhine bir karardır. Gerekçe çalışana verilecek dökümde görünür."
      />
      <p className="text-xs text-muted-foreground">
        Kabul, kaydı kendiliğinden düzeltmez. Kabulden sonra çalışan sayfasında o günün &quot;Düzelt&quot; düğmesiyle düzeltmeyi bu itiraza bağlayın.
      </p>
    </IslemPenceresi>
  );
}
