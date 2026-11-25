import Link from "next/link";
import { TarihSecici } from "@/components/panel/tarih-secici";
import { Input } from "@/components/ui/input";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { buttonVariants } from "@/components/ui/button";
import { HizliIslem } from "@/components/panel/hizli-islem";
import { IslemPenceresi } from "@/components/panel/islem-penceresi";
import { KararAlanlari } from "@/components/panel/karar-alanlari";
import { aralikta, aramaSuzgeci, tarihParametresi } from "@/components/liste/arama";
import { BosDurum } from "@/components/liste/bos-durum";
import { DurumIslem } from "@/components/liste/durum-islem";
import { DurumRozeti } from "@/components/liste/durum-rozeti";
import { FiltreAlani, FiltreCubugu } from "@/components/liste/filtre-cubugu";
import { IslemMenusu } from "@/components/liste/islem-menusu";
import { TabloKutusu } from "@/components/liste/tablo-kutusu";
import { Zaman } from "@/components/liste/zaman";
import { Secim } from "@/components/panel/secim";
import { tekDeger } from "@/lib/arama";
import { tarih } from "@/lib/bicim";
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
  const araMetni = tekDeger(parametre.ara).slice(0, 100);
  const basGun = tarihParametresi(tekDeger(parametre.bas));
  const bitGun = tarihParametresi(tekDeger(parametre.bit));
  const uyar = aramaSuzgeci(araMetni);
  const suzgecVar = tumu || Boolean(araMetni || basGun || bitGun);

  const supabase = await sunucuIstemcisi();
  const tumItirazlar = await tumSatirlar<Itiraz>((bas, son) => {
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
  // Kabul edilmiş ama hiçbir düzeltmeye bağlanmamış itirazlar (T-52): çalışan haklı çıktığı halde
  // kaydı düzeltilmemiş olabilir. İK'ya hatırlatılır; düzeltme yapılınca listeden düşer.
  const duzeltmeBekleyen = ik ? await duzeltmeBekleyenler(supabase) : [];

  // Gün aralığı ve ad / sicil araması ekranda süzülür
  const itirazlar = tumItirazlar.filter(
    (i) => aralikta(i.gun?.is_gunu, basGun, bitGun) && uyar(i.calisan?.ad, i.calisan?.soyad, i.calisan?.sicil_no),
  );

  return (
    <div className="flex flex-col gap-5">
      <div className="flex flex-col gap-1">
        <h1 className="text-2xl font-semibold">İtirazlar</h1>
        <p className="text-sm text-muted-foreground">
          {kullanici.rol === "amir"
            ? "Sorumlu olunan departmanlardaki itirazlar. İtiraz kararı İK tarafından verilir."
            : "Çalışanların kayıtlarına ilişkin itirazlar."}
        </p>
      </div>

      <FiltreCubugu temizleAdres="/itirazlar" suzgecVar={suzgecVar}>
        <FiltreAlani etiket="Durum" htmlFor="goster">
          <Secim id="goster" name="goster" defaultValue={tumu ? "tumu" : ""}>
            <option value="">Açık olanlar</option>
            <option value="tumu">Tümü</option>
          </Secim>
        </FiltreAlani>
        <div className="flex gap-3">
          <FiltreAlani etiket="Gün, başlangıç" htmlFor="bas">
            <TarihSecici id="bas" name="bas" defaultValue={basGun} className="w-36 sm:w-40" />
          </FiltreAlani>
          <FiltreAlani etiket="Bitiş" htmlFor="bit">
            <TarihSecici id="bit" name="bit" defaultValue={bitGun} className="w-36 sm:w-40" />
          </FiltreAlani>
        </div>
        <FiltreAlani etiket="Çalışan ara" htmlFor="ara" className="min-w-48 flex-1 sm:max-w-xs">
          <Input id="ara" name="ara" type="search" defaultValue={araMetni} placeholder="Ad, soyad veya sicil" />
        </FiltreAlani>
      </FiltreCubugu>

      {duzeltmeBekleyen.length > 0 && (
        <section aria-labelledby="duzeltme-bekleyen" className="flex flex-col gap-2 rounded-xl border border-dikkat/40 bg-dikkat-zemin/60 p-4">
          <h2 id="duzeltme-bekleyen" className="flex items-center gap-2 font-semibold">
            Düzeltme bekleyen kabul edilmiş itirazlar
            <DurumRozeti ton="dikkat">{duzeltmeBekleyen.length}</DurumRozeti>
          </h2>
          <p className="text-sm text-muted-foreground">
            Bu itirazlar kabul edildi ama kayıt henüz düzeltilmedi. Düzeltme yapılıp itiraza bağlanınca listeden düşer.
          </p>
          <ul className="flex flex-col divide-y divide-dikkat/20">
            {duzeltmeBekleyen.map((d) => (
              <li key={d.id} className="flex flex-wrap items-center justify-between gap-2 py-2 text-sm">
                <span className="min-w-0">
                  <span className="font-medium">{d.calisan ? `${d.calisan.ad} ${d.calisan.soyad}` : "—"}</span>
                  {d.calisan && <span className="ml-1.5 font-mono text-xs text-muted-foreground">{d.calisan.sicil_no}</span>}
                  <span className="text-muted-foreground"> · {d.gun ? tarih(d.gun.is_gunu) : "—"} · {d.metin.slice(0, 60)}</span>
                </span>
                {d.calisan && d.gun && (
                  <Link
                    href={`/calisanlar/${d.calisan.id}?ay=${d.gun.is_gunu.slice(0, 7)}&duzelt=${d.gun_kaydi_id}`}
                    className={buttonVariants({ size: "sm" })}
                  >
                    Düzeltmeyi yap
                  </Link>
                )}
              </li>
            ))}
          </ul>
        </section>
      )}

      <p className="text-sm text-muted-foreground" aria-live="polite">{itirazlar.length} itiraz</p>

      {itirazlar.length === 0 ? (
        <BosDurum
          aciklama={
            araMetni || basGun || bitGun
              ? "Seçilen filtrelere uygun kayıt bulunmuyor."
              : tumu
                ? "Kayıt bulunmuyor."
                : "Kayıt bulunmuyor."
          }
        />
      ) : (
        <TabloKutusu>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Gün</TableHead>
                <TableHead>Çalışan</TableHead>
                <TableHead className="w-full">İtiraz</TableHead>
                <TableHead>Durum</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {itirazlar.map((i) => (
                <TableRow key={i.id}>
                  {/* Olayın günü öne; itirazın sisteme girildiği an metnin altında "Kayıt" olarak */}
                  <TableCell className="tarih-hucre">{i.gun ? tarih(i.gun.is_gunu) : "—"}</TableCell>
                  <TableCell>
                    {i.calisan ? (
                      <Link
                        href={`/calisanlar/${i.calisan.id}${i.gun ? `?ay=${i.gun.is_gunu.slice(0, 7)}` : ""}`}
                        className="underline-offset-4 hover:underline"
                      >
                        {i.calisan.ad} {i.calisan.soyad}
                        <span className="block font-mono text-xs text-muted-foreground">{i.calisan.sicil_no}</span>
                      </Link>
                    ) : "—"}
                  </TableCell>
                  <TableCell className="min-w-72 whitespace-normal">
                    {i.metin}
                    <div className="mt-1 text-xs text-muted-foreground">
                      <Zaman deger={i.olusturma_zamani} etiket="Kayıt" />
                    </div>
                    {i.karar_zamani && (
                      <div className="mt-1 text-sm text-muted-foreground">
                        Karar: {i.karar_aciklama ?? "—"} · {i.karar_veren?.ad_soyad ?? "İK"}, <Zaman deger={i.karar_zamani} />
                      </div>
                    )}
                  </TableCell>
                  <TableCell>
                    <DurumIslem
                      durum={<DurumRozeti ton={ITIRAZ_DURUMU[i.durum]?.ton}>{ITIRAZ_DURUMU[i.durum]?.ad ?? i.durum}</DurumRozeti>}
                    >
                      {ik && (i.durum === "acik" || i.durum === "inceleniyor") && <KararPenceresi itiraz={i} />}
                      {ik && i.durum === "acik" && (
                        <IslemMenusu>
                          <HizliIslem dugme="İncelemeye al" dugmeTuru="ghost" islem={itirazIncelemeyeAl} gizli={{ itiraz_id: i.id }} />
                        </IslemMenusu>
                      )}
                    </DurumIslem>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </TabloKutusu>
      )}

      {kullanici.rol !== "yonetici" && (
        <p className="text-sm text-muted-foreground">
          Yeni itiraz, çalışan sayfasında ilgili günün yanındaki <span className="font-medium">İtiraz ekle</span> düğmesi ile eklenir.
        </p>
      )}
    </div>
  );
}

type DuzeltmeBekleyen = Pick<Itiraz, "id" | "metin" | "calisan" | "gun"> & { gun_kaydi_id: number };

async function duzeltmeBekleyenler(supabase: Awaited<ReturnType<typeof sunucuIstemcisi>>): Promise<DuzeltmeBekleyen[]> {
  const [kabuller, bagliDuzeltmeler] = await Promise.all([
    tumSatirlar<DuzeltmeBekleyen>((bas, son) =>
      supabase
        .from("itiraz")
        .select("id, metin, gun_kaydi_id, calisan:calisan_id(id, sicil_no, ad, soyad), gun:gun_kaydi_id(is_gunu)")
        .eq("durum", "kabul")
        .order("karar_zamani", { ascending: true })
        .order("id")
        .range(bas, son),
    ),
    tumSatirlar<{ itiraz_id: number }>((bas, son) =>
      supabase.from("duzeltme").select("itiraz_id").not("itiraz_id", "is", null).order("id").range(bas, son),
    ),
  ]);
  const bagli = new Set(bagliDuzeltmeler.map((d) => d.itiraz_id));
  return kabuller.filter((k) => !bagli.has(k.id));
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
        retUyarisi="Ret kararı çalışan aleyhine kaydedilir. Gerekçe, çalışana verilen dökümde yer alır."
      />
      <p className="text-xs text-muted-foreground">
        Kabul kararı kaydı otomatik olarak düzeltmez. Kabulden sonra çalışan sayfasında bu günün düzeltme penceresi açılır; düzeltme bu itiraza bağlanır.
      </p>
    </IslemPenceresi>
  );
}
