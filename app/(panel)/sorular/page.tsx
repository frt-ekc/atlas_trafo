import Link from "next/link";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { BosDurum } from "@/components/panel/bos-durum";
import { IslemPenceresi } from "@/components/panel/islem-penceresi";
import { Secim } from "@/components/panel/secim";
import { tekDeger } from "@/lib/arama";
import { saat, tarih, tarihSaat, yerelZamanGirdisi } from "@/lib/bicim";
import { SORU_CEVABI, SORU_DURUMU, SORU_TURU } from "@/lib/etiketler";
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
  cevap_zamani: string | null;
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

// İK'nın karar vereceği soru (soru_ik_karari): amirin "gelmedi / bilmiyorum" dediği soru ya da
// İK'ya eskale edilmiş / doğrudan İK'ya atanmış açık soru (ör. üst amiri olmayan amirin kendi günü).
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

  const supabase = await sunucuIstemcisi();
  const tumSorular = await tumSatirlar<Soru>((bas, son) => {
    let q = supabase
      .from("amir_sorusu")
      .select(
        "id, soru_turu, aciklama, onerilen_zaman, durum, olusturma_zamani, son_cevap_tarihi, " +
          "cevap, cevap_giris, cevap_cikis, cevap_aciklama, cevap_zamani, " +
          "atanan:kullanici!atanan_id(ad_soyad, rol), eskale:kullanici!eskale_edilen_id(ad_soyad, rol), cevaplayan:kullanici!cevaplayan_id(ad_soyad), " +
          "gun:gun_kaydi_id(is_gunu, planli_baslangic, planli_bitis, giris_zamani, cikis_zamani, calisan:calisan_id(id, sicil_no, ad, soyad))",
      )
      .order("son_cevap_tarihi")
      .order("id")
      .range(bas, son);
    if (durumlar) q = q.in("durum", [...durumlar]);
    return q;
  });
  const sorular = suzgec === "ik" ? tumSorular.filter(ikteBekliyor) : tumSorular;

  const bugunTarih = bugun();
  const amir = kullanici.rol === "amir";
  const ik = kullanici.rol === "ik";

  return (
    <div className="flex flex-col gap-5">
      <div className="flex flex-col gap-1">
        <h1 className="text-2xl font-semibold">{amir ? "Sorularım" : "Amir soruları"}</h1>
        <p className="text-sm text-muted-foreground">
          Gece işi kanıt (kapı, yemekhane, servis kaydı) bulamadığı kayıtları sabah amire sorar. Cevapsız soru son günden
          sonra üst amire ve İK&apos;ya gider. &quot;Gelmedi&quot; cevabında kararı İK verir.
        </p>
      </div>

      <form method="get" className="flex items-end gap-2">
        <div className="flex flex-col gap-1.5">
          <label htmlFor="durum" className="text-sm font-medium">Göster</label>
          <Secim id="durum" name="durum" defaultValue={suzgec}>
            {Object.entries(SUZGECLER).map(([k, v]) => <option key={k} value={k}>{v.ad}</option>)}
          </Secim>
        </div>
        <Button type="submit" size="sm">Göster</Button>
      </form>

      <p className="text-sm text-muted-foreground" aria-live="polite">{sorular.length} soru</p>

      {sorular.length === 0 ? (
        <BosDurum>
          {suzgec === "bekleyen" ? "Cevap bekleyen soru yok." : "Bu süzgece uyan soru yok."} Sorular gece işi çalıştığında oluşur.
        </BosDurum>
      ) : (
        <div className="rounded-lg border">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Gün</TableHead>
                <TableHead>Çalışan</TableHead>
                <TableHead>Soru</TableHead>
                <TableHead>Kanıttaki saat</TableHead>
                <TableHead>Son gün</TableHead>
                <TableHead>Durum</TableHead>
                {!amir && <TableHead>Atanan</TableHead>}
                {(amir || ik) && <TableHead><span className="sr-only">İşlem</span></TableHead>}
              </TableRow>
            </TableHeader>
            <TableBody>
              {sorular.map((s) => {
                const c = s.gun?.calisan;
                const gecikti = (s.durum === "acik" || s.durum === "eskale") && s.son_cevap_tarihi < bugunTarih;
                return (
                  <TableRow key={s.id}>
                    <TableCell className="tabular-nums">{s.gun ? tarih(s.gun.is_gunu) : "—"}</TableCell>
                    <TableCell>
                      {c ? (
                        <Link href={`/calisanlar/${c.id}?ay=${s.gun!.is_gunu.slice(0, 7)}`} className="underline-offset-4 hover:underline">
                          {c.ad} {c.soyad} <span className="font-mono text-xs text-muted-foreground">({c.sicil_no})</span>
                        </Link>
                      ) : (
                        // Eskale edilen üst amir, başka bölümün gün kaydını RLS yüzünden göremeyebilir
                        <span className="text-muted-foreground">Görüntülenemiyor</span>
                      )}
                    </TableCell>
                    <TableCell className="max-w-80 whitespace-normal">
                      <div className="font-medium">{SORU_TURU[s.soru_turu] ?? s.soru_turu}</div>
                      <div className="text-sm text-muted-foreground">{s.aciklama}</div>
                      {s.cevap && (
                        <div className="mt-1 text-sm">
                          Cevap: {SORU_CEVABI[s.cevap] ?? s.cevap}
                          {(s.cevap_giris || s.cevap_cikis) && ` (${saat(s.cevap_giris)}–${saat(s.cevap_cikis)})`}
                          {s.cevap_aciklama && ` · ${s.cevap_aciklama}`}
                          <span className="text-muted-foreground"> · {s.cevaplayan?.ad_soyad ?? "—"}, {tarihSaat(s.cevap_zamani)}</span>
                        </div>
                      )}
                    </TableCell>
                    <TableCell className="tabular-nums">{s.onerilen_zaman ? saat(s.onerilen_zaman) : "—"}</TableCell>
                    <TableCell className="tabular-nums">
                      {tarih(s.son_cevap_tarihi)}
                      {gecikti && <div className="text-xs text-destructive">Süresi geçti</div>}
                    </TableCell>
                    <TableCell>
                      <Badge variant={SORU_DURUMU[s.durum]?.tur ?? "outline"}>{SORU_DURUMU[s.durum]?.ad ?? s.durum}</Badge>
                    </TableCell>
                    {!amir && (
                      <TableCell className="text-muted-foreground">
                        {s.atanan?.ad_soyad ?? "—"}
                        {s.eskale && <div className="text-xs">Eskale: {s.eskale.ad_soyad}</div>}
                      </TableCell>
                    )}
                    {amir && (
                      <TableCell className="text-right">
                        {(s.durum === "acik" || s.durum === "eskale") && <CevaplaPenceresi soru={s} />}
                      </TableCell>
                    )}
                    {ik && (
                      <TableCell className="text-right">
                        {/* Görevler ayrılığı: İK kendi günündeki soruya karar veremez; soru diğer İK'ya düşer */}
                        {ikteBekliyor(s) && c?.id !== kullanici.calisanId && <IkKararPenceresi soru={s} />}
                      </TableCell>
                    )}
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        </div>
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
          {soru.onerilen_zaman && ` Kanıttaki saat: ${saat(soru.onerilen_zaman)}.`}
        </>
      }
      onay="Cevabı kaydet"
      islem={soruCevapla}
      gizli={{ soru_id: soru.id }}
    >
      <CevapAlanlari
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
              {soru.durum === "eskale"
                ? "Amir süresinde cevaplamadı; üst amiri olmadığı için soru İK'ya eskale edildi."
                : "Cevaplayacak amir olmadığı için soru doğrudan İK'ya atandı."}
              {soru.onerilen_zaman && ` Kanıttaki saat: ${saat(soru.onerilen_zaman)}.`}
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
        girisVarsayilan={yerelZamanGirdisi(g?.giris_zamani ? null : ((soru.soru_turu !== "cikis_yok" ? soru.onerilen_zaman : null) ?? g?.planli_baslangic))}
        cikisVarsayilan={yerelZamanGirdisi(g?.cikis_zamani ? null : ((soru.soru_turu === "cikis_yok" ? soru.onerilen_zaman : null) ?? g?.planli_bitis))}
      />
    </IslemPenceresi>
  );
}
