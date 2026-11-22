import Link from "next/link";
import { Badge } from "@/components/ui/badge";
import { buttonVariants } from "@/components/ui/button";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { BosDurum } from "@/components/panel/bos-durum";
import { OzetIzgarasi, OzetKarti } from "@/components/panel/ozet-karti";
import { tekDeger } from "@/lib/arama";
import { bugun } from "@/lib/hafta";
import { rolGerekli } from "@/lib/oturum";
import { ayAdi, ayKaydir, saatDakika } from "@/lib/puantaj";
import { tumSatirlar } from "@/lib/supabase/sayfali";
import { sunucuIstemcisi } from "@/lib/supabase/server";
import { cn } from "@/lib/utils";

export const metadata = { title: "Departmanlar" };

// pdks.v_departman_ozet: ay + departman başına devam özeti (gece işinin kurduğu gün kayıtlarından)
type DepartmanOzeti = {
  departman_id: number;
  departman: string;
  calisan_sayisi: number;
  calisilan_gun: number;
  devamsiz_gun: number;
  gec_kalinan_gun: number;
  gec_kalma_dk: number;
  erken_cikis_dk: number;
  fazla_mesai_dk: number;
  bekleyen_gun: number;
  acik_soru: number;
  acik_itiraz: number;
};

// pdks.v_esnek_mesai: esnek mesaili çalışanın aylık hedefi ve gerçekleşen süresi
type EsnekSatiri = { calisan_id: number; hedef_gun: number; hedef_dk: number; gerceklesen_dk: number; fark_dk: number; bekleyen_gun: number };
type Calisan = { id: number; sicil_no: string; ad: string; soyad: string; departman: { ad: string } | null };

// Görünümler sayıları metin (bigint) olarak döndürebilir; hesaptan önce sayıya çevrilir
function sayilastir<T extends Record<string, unknown>>(satir: T): T {
  return Object.fromEntries(
    Object.entries(satir).map(([k, v]) => [k, typeof v === "string" && /^-?\d+(\.\d+)?$/.test(v) ? Number(v) : v]),
  ) as T;
}

// "+1:30" / "−0:45": esnek mesaide hedefin üstü ya da altı
function isaretliSure(dk: number): string {
  if (dk === 0) return "0:00";
  return `${dk > 0 ? "+" : "−"}${saatDakika(Math.abs(dk))}`;
}

// Yönetici paneli: departmanların aylık devam özeti. Yönetici ve İK tüm departmanları,
// amir yalnızca kendi departmanını görür (RLS). Sayfa yalnızca okur.
export default async function DepartmanlarSayfasi({ searchParams }: PageProps<"/departmanlar">) {
  const kullanici = await rolGerekli(["yonetici", "ik", "amir"]);
  const parametre = await searchParams;
  const istenen = tekDeger(parametre.ay);
  const ay = /^\d{4}-(0[1-9]|1[0-2])$/.test(istenen) ? istenen : bugun().slice(0, 7);
  const [yil, ayNo] = ay.split("-").map(Number);

  const supabase = await sunucuIstemcisi();
  const [ozetSonucu, yakaSonucu, esnekler, calisanlar] = await Promise.all([
    supabase.from("v_departman_ozet").select("*").eq("yil", yil).eq("ay", ayNo).order("departman"),
    supabase.from("departman").select("id, yaka"),
    tumSatirlar<EsnekSatiri>((bas, son) =>
      supabase
        .from("v_esnek_mesai")
        .select("calisan_id, hedef_gun, hedef_dk, gerceklesen_dk, fark_dk, bekleyen_gun")
        .eq("yil", yil)
        .eq("ay", ayNo)
        .order("calisan_id")
        .range(bas, son),
    ),
    tumSatirlar<Calisan>((bas, son) =>
      supabase.from("calisan").select("id, sicil_no, ad, soyad, departman:departman_id(ad)").order("id").range(bas, son),
    ),
  ]);
  if (ozetSonucu.error) throw new Error(`Departman özeti okunamadı: ${ozetSonucu.error.message}`);

  const departmanlar = ((ozetSonucu.data ?? []) as DepartmanOzeti[]).map(sayilastir);
  const yaka = new Map(((yakaSonucu.data ?? []) as { id: number; yaka: string }[]).map((d) => [d.id, d.yaka]));
  const calisanById = new Map(calisanlar.map((c) => [c.id, c]));
  const esnek = esnekler.map(sayilastir).sort((a, b) => a.fark_dk - b.fark_dk);

  // Fabrika (ya da amirin bölümü) geneli
  const top = (alan: keyof DepartmanOzeti) => departmanlar.reduce((t, d) => t + Number(d[alan] ?? 0), 0);
  const calisilan = top("calisilan_gun");
  const devamsiz = top("devamsiz_gun");
  const devamOrani = calisilan + devamsiz > 0 ? (calisilan / (calisilan + devamsiz)) * 100 : null;
  const acikIs = top("acik_soru") + top("acik_itiraz");

  const adres = (a: string) => `/departmanlar?ay=${a}`;

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-col gap-1">
        <h1 className="text-2xl font-semibold">Departmanlar · {ayAdi(ay)}</h1>
        <p className="text-sm text-muted-foreground">
          {kullanici.rol === "amir"
            ? "Sorumlu olduğunuz departmanların aylık devam özeti."
            : "Departmanların aylık devam özeti. Sayılar gece işinin kurduğu günlük kayıtlardan gelir."}
        </p>
      </div>

      <nav aria-label="Ay" className="flex flex-wrap gap-2">
        <Link href={adres(ayKaydir(ay, -1))} className={buttonVariants({ variant: "outline", size: "sm" })}>← {ayAdi(ayKaydir(ay, -1))}</Link>
        <Link href="/departmanlar" className={buttonVariants({ variant: "ghost", size: "sm" })}>Bu ay</Link>
        <Link href={adres(ayKaydir(ay, 1))} className={buttonVariants({ variant: "outline", size: "sm" })}>{ayAdi(ayKaydir(ay, 1))} →</Link>
      </nav>

      {departmanlar.length === 0 ? (
        <BosDurum>Bu ay için günlük kayıt yok. Özet, gece işi çalışınca oluşur.</BosDurum>
      ) : (
        <>
          <OzetIzgarasi>
            <OzetKarti
              baslik="Devam oranı"
              deger={devamOrani === null ? "—" : `%${devamOrani.toLocaleString("tr-TR", { maximumFractionDigits: 1 })}`}
              aciklama={`${top("calisan_sayisi")} çalışan, ${departmanlar.length} departman · ${devamsiz} devamsız gün`}
              ton={devamsiz ? "dikkat" : "iyi"}
            />
            <OzetKarti
              baslik="Geç kalma"
              deger={saatDakika(top("gec_kalma_dk"))}
              aciklama={`${top("gec_kalinan_gun")} gün · erken çıkış ${saatDakika(top("erken_cikis_dk"))} (sa:dk)`}
            />
            <OzetKarti baslik="Fazla mesai" deger={saatDakika(top("fazla_mesai_dk"))} aciklama="Onaylı, sa:dk" />
            <OzetKarti
              baslik="Açık iş"
              deger={acikIs}
              aciklama={`${top("acik_soru")} soru · ${top("acik_itiraz")} itiraz · ${top("bekleyen_gun")} kesinleşmemiş gün`}
              ton={acikIs ? "dikkat" : "iyi"}
            />
          </OzetIzgarasi>

          <div className="rounded-lg border">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Departman</TableHead>
                  <TableHead className="text-right">Çalışan</TableHead>
                  <TableHead className="text-right">Çalışılan gün</TableHead>
                  <TableHead className="text-right">Devamsız</TableHead>
                  <TableHead className="text-right">Geç kalma</TableHead>
                  <TableHead className="text-right">Erken çıkış</TableHead>
                  <TableHead className="text-right">Fazla mesai</TableHead>
                  <TableHead className="text-right">Açık iş</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {departmanlar.map((d) => (
                  <TableRow key={d.departman_id}>
                    <TableCell className="min-w-52 max-w-72 whitespace-normal">
                      <Link href={`/calisanlar?departman=${d.departman_id}`} className="underline-offset-4 hover:underline">{d.departman}</Link>
                      {yaka.get(d.departman_id) && <div className="text-xs text-muted-foreground">{yaka.get(d.departman_id)} yaka</div>}
                    </TableCell>
                    <TableCell className="text-right tabular-nums">{d.calisan_sayisi}</TableCell>
                    <TableCell className="text-right tabular-nums">{d.calisilan_gun}</TableCell>
                    <TableCell className={cn("text-right tabular-nums", d.devamsiz_gun > 0 && "font-medium text-destructive")}>{d.devamsiz_gun || "—"}</TableCell>
                    <TableCell className="text-right tabular-nums">
                      {d.gec_kalma_dk ? saatDakika(d.gec_kalma_dk) : "—"}
                      {d.gec_kalinan_gun > 0 && <div className="text-xs text-muted-foreground">{d.gec_kalinan_gun} gün</div>}
                    </TableCell>
                    <TableCell className="text-right tabular-nums">{d.erken_cikis_dk ? saatDakika(d.erken_cikis_dk) : "—"}</TableCell>
                    <TableCell className="text-right tabular-nums">{d.fazla_mesai_dk ? saatDakika(d.fazla_mesai_dk) : "—"}</TableCell>
                    <TableCell className="text-right">
                      {d.acik_soru + d.acik_itiraz > 0 ? (
                        <Badge variant="default">{d.acik_soru + d.acik_itiraz}</Badge>
                      ) : (
                        <span className="text-muted-foreground">—</span>
                      )}
                      {d.bekleyen_gun > 0 && <div className="text-xs text-muted-foreground">{d.bekleyen_gun} gün bekliyor</div>}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        </>
      )}

      <section aria-labelledby="esnek-baslik" className="flex flex-col gap-3">
        <div className="flex flex-col gap-1">
          <h2 id="esnek-baslik" className="text-lg font-semibold">Esnek mesai</h2>
          <p className="text-sm text-muted-foreground">
            Esnek mesaili çalışanlar geliş saatini seçer; ay sonunda günlük hedefin toplamına bakılır. Eksi değer hedefin altını
            gösterir. İzinli ve tatil günleri hedefe girmez.
          </p>
        </div>
        {esnek.length === 0 ? (
          <BosDurum>Bu ay esnek mesaili çalışan kaydı yok.</BosDurum>
        ) : (
          <div className="rounded-lg border">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Çalışan</TableHead>
                  <TableHead>Departman</TableHead>
                  <TableHead className="text-right">Hedef gün</TableHead>
                  <TableHead className="text-right">Hedef</TableHead>
                  <TableHead className="text-right">Gerçekleşen</TableHead>
                  <TableHead className="text-right">Fark</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {esnek.map((e) => {
                  const c = calisanById.get(e.calisan_id);
                  return (
                    <TableRow key={e.calisan_id}>
                      <TableCell>
                        {c ? `${c.ad} ${c.soyad}` : "—"}
                        {c && <span className="ml-1 font-mono text-xs text-muted-foreground">({c.sicil_no})</span>}
                      </TableCell>
                      <TableCell className="text-sm">{c?.departman?.ad ?? "—"}</TableCell>
                      <TableCell className="text-right tabular-nums">{e.hedef_gun}</TableCell>
                      <TableCell className="text-right tabular-nums">{saatDakika(e.hedef_dk)}</TableCell>
                      <TableCell className="text-right tabular-nums">{saatDakika(e.gerceklesen_dk)}</TableCell>
                      <TableCell className={cn("text-right font-medium tabular-nums", e.fark_dk < 0 ? "text-destructive" : "text-iyi")}>
                        {isaretliSure(e.fark_dk)}
                        {e.bekleyen_gun > 0 && <div className="text-xs font-normal text-muted-foreground">{e.bekleyen_gun} gün bekliyor</div>}
                      </TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          </div>
        )}
      </section>
    </div>
  );
}
