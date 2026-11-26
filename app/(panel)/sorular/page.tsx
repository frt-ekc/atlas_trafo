import Link from "next/link";
import { TarihSecici } from "@/components/panel/tarih-secici";
import { Input } from "@/components/ui/input";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { IslemPenceresi } from "@/components/panel/islem-penceresi";
import { Secim } from "@/components/panel/secim";
import { aralikta, aramaSuzgeci, tarihParametresi } from "@/components/liste/arama";
import { BosDurum } from "@/components/liste/bos-durum";
import { DurumIslem } from "@/components/liste/durum-islem";
import { DurumRozeti } from "@/components/liste/durum-rozeti";
import { FiltreAlani, FiltreCubugu } from "@/components/liste/filtre-cubugu";
import { TabloKutusu } from "@/components/liste/tablo-kutusu";
import { tekDeger } from "@/lib/arama";
import { saat, tarih, tarihSaat, yerelZamanGirdisi } from "@/lib/bicim";
import { IK_KARARI, SORU_CEVABI, SORU_DURUMU, SORU_TURU } from "@/lib/etiketler";
import { bugun } from "@/lib/hafta";
import { rolGerekli } from "@/lib/oturum";
import { tumSatirlar } from "@/lib/supabase/sayfali";
import { sunucuIstemcisi } from "@/lib/supabase/server";
import { soruCevapla, soruIkKarari } from "./actions";
import { CevapAlanlari } from "./cevap-alanlari";
import { IkKararAlanlari } from "./ik-karar-alanlari";

export const metadata = { title: "Sorular" };

type Soru = {
  id: number;
  soru_turu: string;
  aciklama: string;
  onerilen_zaman: string | null;
  durum: string;
  olusturma_zamani: string;
  son_cevap_tarihi: string;
  cevap: string | null;
  cevap_giris: string | null;
  cevap_cikis: string | null;
  cevap_aciklama: string | null;
  ik_karari: string | null;
  kapanis_nedeni: string | null; // cevapla değil başka bir işlemle kapandıysa (T-46, T-40)
  // İK kararının gerekçesi düzeltmededir; amir için okunmaz (T-106)
  duzeltmeler?: { gerekce: string; kaynak: string }[];
  cevap_zamani: string | null;
  ik_eskale_zamani: string | null; // üst amir de cevaplamayınca İK'ya geçtiği an (T-39)
  atanan: { ad_soyad: string; rol: string } | null;
  eskale: { ad_soyad: string; rol: string } | null;
  cevaplayan: { ad_soyad: string } | null;
  gun: {
    is_gunu: string;
    planli_baslangic: string | null;
    planli_bitis: string | null;
    giris_zamani: string | null;
    cikis_zamani: string | null;
    calisan: { id: number; sicil_no: string; ad: string; soyad: string } | null;
  } | null;
};

const SUZGECLER = {
  bekleyen: { ad: "Cevap bekleyenler", durumlar: ["acik", "eskale"] },
  // Açık / eskale sorulardan İK'da duranlar aşağıda ayrıca süzülür (ikteBekliyor)
  ik: { ad: "İK kararı bekleyenler", durumlar: ["ik_karari_bekliyor", "acik", "eskale"] },
  kapanan: { ad: "Cevaplanan ve kapananlar", durumlar: ["cevaplandi", "kapandi"] },
  tumu: { ad: "Tümü", durumlar: null },
} as const;
type Suzgec = keyof typeof SUZGECLER;

// İK'nın karar vereceği soru (soru_ik_karari): amirin "gelmedi / bilmiyorum" dediği soru, üst amir de
// süresinde cevaplamadığı için İK'ya geçen soru (ik_karari_bekliyor, T-39) ya da İK'ya eskale edilmiş /
// doğrudan İK'ya atanmış açık soru (ör. üst amiri olmayan amirin kendi günü).
function ikteBekliyor(s: Soru) {
  if (s.durum === "ik_karari_bekliyor") return true;
  return (s.durum === "acik" || s.durum === "eskale") && (s.eskale ?? s.atanan)?.rol === "ik";
}

// Gece işi kanıt bulamadığı kayıtlar için amire sabah soru açar.
// Amir yalnızca kendisine atanan (ya da kendisine eskale edilen) soruları görür (RLS).
export default async function SorularSayfasi({ searchParams }: PageProps<"/sorular">) {
  const kullanici = await rolGerekli(["amir", "ik", "yonetici"]);
  const parametre = await searchParams;
  const istenen = tekDeger(parametre.durum);
  const suzgec: Suzgec = istenen in SUZGECLER ? (istenen as Suzgec) : kullanici.rol === "amir" ? "bekleyen" : "tumu";
  const durumlar = SUZGECLER[suzgec].durumlar;
  const varsayilanSuzgec: Suzgec = kullanici.rol === "amir" ? "bekleyen" : "tumu";
  const araMetni = tekDeger(parametre.ara).slice(0, 100);
  const bas = tarihParametresi(tekDeger(parametre.bas));
  const bit = tarihParametresi(tekDeger(parametre.bit));
  const uyar = aramaSuzgeci(araMetni);
  const suzgecVar = suzgec !== varsayilanSuzgec || Boolean(araMetni || bas || bit);

  const supabase = await sunucuIstemcisi();
  const tumSorular = await tumSatirlar<Soru>((bas, son) => {
    let q = supabase
      .from("amir_sorusu")
      .select(
        "id, soru_turu, aciklama, onerilen_zaman, durum, olusturma_zamani, son_cevap_tarihi, " +
          "cevap, cevap_giris, cevap_cikis, cevap_aciklama, cevap_zamani, ik_karari, kapanis_nedeni, ik_eskale_zamani, " +
          "atanan:kullanici!atanan_id(ad_soyad, rol), eskale:kullanici!eskale_edilen_id(ad_soyad, rol), cevaplayan:kullanici!cevaplayan_id(ad_soyad), " +
          "gun:gun_kaydi_id(is_gunu, planli_baslangic, planli_bitis, giris_zamani, cikis_zamani, calisan:calisan_id(id, sicil_no, ad, soyad))" +
          (kullanici.rol === "amir" ? "" : ", duzeltmeler:duzeltme!soru_id(gerekce, kaynak)"),
      )
      .order("son_cevap_tarihi")
      .order("id")
      .range(bas, son);
    if (durumlar) q = q.in("durum", [...durumlar]);
    return q;
  });
  // Gün aralığı ve ad / sicil araması ekranda süzülür (gün ve çalışan, gün kaydının içinden gelir)
  const sorular = (suzgec === "ik" ? tumSorular.filter(ikteBekliyor) : tumSorular).filter(
    (s) => aralikta(s.gun?.is_gunu, bas, bit) && uyar(s.gun?.calisan?.ad, s.gun?.calisan?.soyad, s.gun?.calisan?.sicil_no),
  );

  const bugunTarih = bugun();
  const amir = kullanici.rol === "amir";
  const ik = kullanici.rol === "ik";

  return (
    <div className="flex flex-col gap-5">
      <div className="flex flex-col gap-1">
        <h1 className="text-2xl font-semibold">{amir ? "Sorularım" : "Amir soruları"}</h1>
        <p className="text-sm text-muted-foreground">
          Otomatik düzeltilemeyen kayıtlar amire sorulur. Süresinde cevaplanmayan sorular üst amire, ardından İK&apos;ya iletilir. Devamsızlık kararı İK tarafından verilir.
        </p>
      </div>

      <FiltreCubugu temizleAdres="/sorular" suzgecVar={suzgecVar}>
        <FiltreAlani etiket="Durum" htmlFor="durum">
          <Secim id="durum" name="durum" defaultValue={suzgec}>
            {Object.entries(SUZGECLER).map(([k, v]) => <option key={k} value={k}>{v.ad}</option>)}
          </Secim>
        </FiltreAlani>
        <div className="flex gap-3">
          <FiltreAlani etiket="Gün, başlangıç" htmlFor="bas">
            <TarihSecici id="bas" name="bas" defaultValue={bas} className="w-36 sm:w-40" />
          </FiltreAlani>
          <FiltreAlani etiket="Bitiş" htmlFor="bit">
            <TarihSecici id="bit" name="bit" defaultValue={bit} className="w-36 sm:w-40" />
          </FiltreAlani>
        </div>
        <FiltreAlani etiket="Çalışan ara" htmlFor="ara" className="min-w-48 flex-1 sm:max-w-xs">
          <Input id="ara" name="ara" type="search" defaultValue={araMetni} placeholder="Ad, soyad veya sicil" />
        </FiltreAlani>
      </FiltreCubugu>

      <p className="text-sm text-muted-foreground" aria-live="polite">{sorular.length} soru</p>

      {sorular.length === 0 ? (
        <BosDurum
          aciklama={
            suzgecVar
              ? "Seçilen filtrelere uygun kayıt bulunmuyor."
              : suzgec === "bekleyen"
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
                <TableHead className="w-full">Soru</TableHead>
                <TableHead className="whitespace-normal">Kanıt saati</TableHead>
                <TableHead>Son cevap tarihi</TableHead>
                {!amir && <TableHead>Atanan</TableHead>}
                <TableHead>Durum</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {sorular.map((s) => {
                const c = s.gun?.calisan;
                const ikGerekcesi = s.duzeltmeler?.find((d) => d.kaynak === "ik")?.gerekce;
                const gecikti = (s.durum === "acik" || s.durum === "eskale") && s.son_cevap_tarihi < bugunTarih;
                return (
                  <TableRow key={s.id}>
                    <TableCell className="tarih-hucre">{s.gun ? tarih(s.gun.is_gunu) : "—"}</TableCell>
                    <TableCell>
                      {c ? (
                        <Link href={`/calisanlar/${c.id}?ay=${s.gun!.is_gunu.slice(0, 7)}`} className="underline-offset-4 hover:underline">
                          {c.ad} {c.soyad} <span className="block font-mono text-xs font-normal text-muted-foreground">{c.sicil_no}</span>
                        </Link>
                      ) : (
                        // Eskale edilen üst amir, başka bölümün gün kaydını RLS yüzünden göremeyebilir
                        <span className="text-muted-foreground">Görüntülenemiyor</span>
                      )}
                    </TableCell>
                    <TableCell className="min-w-72 whitespace-normal">
                      <div className="font-medium">{SORU_TURU[s.soru_turu] ?? s.soru_turu}</div>
                      <div className="text-sm text-muted-foreground">{s.aciklama.replace(/^\d{2}\.\d{2}\.\d{4}:\s*/, "")}</div>
                      {s.cevap && (
                        <div className="mt-1 text-sm">
                          Cevap: {SORU_CEVABI[s.cevap] ?? s.cevap}
                          {(s.cevap_giris || s.cevap_cikis) && ` (${saat(s.cevap_giris)}–${saat(s.cevap_cikis)})`}
                          {s.cevap_aciklama && ` · ${s.cevap_aciklama}`}
                          <span className="text-muted-foreground"> · {s.cevaplayan?.ad_soyad ?? "—"}, {tarihSaat(s.cevap_zamani)}</span>
                        </div>
                      )}
                      {s.kapanis_nedeni && <div className="mt-1 text-sm">Kapanış nedeni: {s.kapanis_nedeni}</div>}
                      {s.ik_karari && (
                        <div className="mt-1 text-sm">
                          İK kararı: {IK_KARARI[s.ik_karari] ?? s.ik_karari}
                          {ikGerekcesi && <span className="text-muted-foreground"> · Gerekçe: {ikGerekcesi}</span>}
                        </div>
                      )}
                    </TableCell>
                    <TableCell className="tabular-nums">{s.onerilen_zaman ? saat(s.onerilen_zaman) : "—"}</TableCell>
                    <TableCell className="tabular-nums">
                      {tarih(s.son_cevap_tarihi)}
                      {gecikti && <div className="text-xs text-destructive">Süresi doldu</div>}
                    </TableCell>
                    {!amir && (
                      <TableCell className="min-w-28 whitespace-normal text-muted-foreground">
                        {s.atanan?.ad_soyad ?? "—"}
                        {s.eskale && <div className="text-xs">İletilen: {s.eskale.ad_soyad}</div>}
                      </TableCell>
                    )}
                    <TableCell>
                      <DurumIslem
                        durum={<DurumRozeti ton={SORU_DURUMU[s.durum]?.ton}>{SORU_DURUMU[s.durum]?.ad ?? s.durum}</DurumRozeti>}
                      >
                        {amir && (s.durum === "acik" || s.durum === "eskale") && <CevaplaPenceresi soru={s} />}
                        {/* Görevler ayrılığı: İK kendi günündeki soruya karar veremez; soru diğer İK'ya düşer */}
                        {ik && ikteBekliyor(s) && c?.id !== kullanici.calisanId && <IkKararPenceresi soru={s} />}
                      </DurumIslem>
                    </TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        </TabloKutusu>
      )}

    </div>
  );
}

function CevaplaPenceresi({ soru }: { soru: Soru }) {
  const g = soru.gun;
  const kisi = g?.calisan ? `${g.calisan.ad} ${g.calisan.soyad}` : "Çalışan";
  // "Saat farklı" seçilince yalnızca eksik saat doldurulur (önce kanıttaki öneri, yoksa plan).
  // Kayıtlı saat boş gelir: boş alan gönderilmez, böylece değişmeyen saat için düzeltme açılmaz.
  const girisVarsayilan = g?.giris_zamani ? "" : yerelZamanGirdisi((soru.soru_turu !== "cikis_yok" ? soru.onerilen_zaman : null) ?? g?.planli_baslangic);
  const cikisVarsayilan = g?.cikis_zamani ? "" : yerelZamanGirdisi((soru.soru_turu === "cikis_yok" ? soru.onerilen_zaman : null) ?? g?.planli_bitis);
  return (
    <IslemPenceresi
      dugme="Cevapla"
      dugmeTuru="default"
      baslik={`${kisi} · ${g ? tarih(g.is_gunu) : ""}`}
      aciklama={
        <>
          {SORU_TURU[soru.soru_turu] ?? soru.soru_turu}. {soru.aciklama}
          {g && ` Plan: ${saat(g.planli_baslangic)}–${saat(g.planli_bitis)}.`}
          {soru.onerilen_zaman && ` Kanıt saati: ${saat(soru.onerilen_zaman)}.`}
        </>
      }
      onay="Cevabı kaydet"
      islem={soruCevapla}
      gizli={{ soru_id: soru.id }}
    >
      <CevapAlanlari
        soruTuru={soru.soru_turu}
        gunde={g ? { giris: Boolean(g.giris_zamani), cikis: Boolean(g.cikis_zamani) } : null}
        girisVarsayilan={girisVarsayilan}
        cikisVarsayilan={cikisVarsayilan}
        kayitliGiris={g?.giris_zamani ? saat(g.giris_zamani) : null}
        kayitliCikis={g?.cikis_zamani ? saat(g.cikis_zamani) : null}
      />
    </IslemPenceresi>
  );
}

function IkKararPenceresi({ soru }: { soru: Soru }) {
  const g = soru.gun;
  const kisi = g?.calisan ? `${g.calisan.ad} ${g.calisan.soyad}` : "Çalışan";
  return (
    <IslemPenceresi
      dugme="Karar ver"
      dugmeTuru="default"
      baslik={`${kisi} · ${g ? tarih(g.is_gunu) : ""}`}
      aciklama={
        <>
          {SORU_TURU[soru.soru_turu] ?? soru.soru_turu}.{" "}
          {soru.cevap ? (
            <>
              Amirin cevabı: {SORU_CEVABI[soru.cevap] ?? soru.cevap}
              {soru.cevap_aciklama && ` (${soru.cevap_aciklama})`}.
            </>
          ) : (
            <>
              {soru.aciklama}{" "}
              {soru.ik_eskale_zamani
                ? `Amir ve üst amir${soru.eskale ? ` (${soru.eskale.ad_soyad})` : ""} süresinde cevaplamadığı için soru İK'ya iletildi.`
                : soru.durum === "eskale"
                  ? "Soru süresinde cevaplanmadığı için İK'ya iletildi."
                  : "Tanımlı amir bulunmadığı için soru İK'ya atandı."}
              {soru.onerilen_zaman && ` Kanıt saati: ${saat(soru.onerilen_zaman)}.`}
            </>
          )}
          {g && ` Plan: ${saat(g.planli_baslangic)}–${saat(g.planli_bitis)}.`}
        </>
      }
      onay="Kararı kaydet"
      islem={soruIkKarari}
      gizli={{ soru_id: soru.id }}
    >
      <IkKararAlanlari
        soruTuru={soru.soru_turu}
        gunde={g ? { giris: Boolean(g.giris_zamani), cikis: Boolean(g.cikis_zamani) } : null}
        girisVarsayilan={yerelZamanGirdisi(g?.giris_zamani ? null : ((soru.soru_turu !== "cikis_yok" ? soru.onerilen_zaman : null) ?? g?.planli_baslangic))}
        cikisVarsayilan={yerelZamanGirdisi(g?.cikis_zamani ? null : ((soru.soru_turu === "cikis_yok" ? soru.onerilen_zaman : null) ?? g?.planli_bitis))}
        kayitliGiris={g?.giris_zamani ? saat(g.giris_zamani) : null}
        kayitliCikis={g?.cikis_zamani ? saat(g.cikis_zamani) : null}
      />
    </IslemPenceresi>
  );
}
