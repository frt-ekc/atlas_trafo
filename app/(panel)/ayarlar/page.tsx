import { ArrowRightIcon } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { IslemPenceresi } from "@/components/panel/islem-penceresi";
import { tarih, saat, tarihSaat } from "@/lib/bicim";
import { rolGerekli } from "@/lib/oturum";
import { sunucuIstemcisi } from "@/lib/supabase/server";
import { ayarGuncelle } from "./actions";

export const metadata = { title: "Ayarlar" };

type Ayar = {
  anahtar: string;
  deger: number;
  birim: string;
  aciklama: string;
  guncelleme_zamani: string;
  guncelleyen: { ad_soyad: string } | null;
};
type Gecmis = { id: number; anahtar: string; eski_deger: number | null; yeni_deger: number; degisim_zamani: string; guncelleyen: { ad_soyad: string } | null };

// Kuralların eşikleri (tolerans, mola, fazla mesai sınırları…) koda değil bu tabloya yazılıdır.
// Yalnızca sistem yöneticisi değiştirir; her değişiklik geçmişe yazılır.
export default async function AyarlarSayfasi() {
  await rolGerekli(["admin"]);
  const supabase = await sunucuIstemcisi();

  const [ayarSonucu, gecmisSonucu] = await Promise.all([
    supabase.from("ayar").select("anahtar, deger, birim, aciklama, guncelleme_zamani, guncelleyen:kullanici!guncelleyen_id(ad_soyad)").order("anahtar"),
    supabase
      .from("ayar_gecmisi")
      .select("id, anahtar, eski_deger, yeni_deger, degisim_zamani, guncelleyen:kullanici!guncelleyen_id(ad_soyad)")
      .order("id", { ascending: false })
      .limit(20),
  ]);
  if (ayarSonucu.error) throw new Error(`Ayarlar okunamadı: ${ayarSonucu.error.message}`);

  const ayarlar = (ayarSonucu.data ?? []) as unknown as Ayar[];
  const gecmis = (gecmisSonucu.data ?? []) as unknown as Gecmis[];
  // Geçmişte anahtar yerine ayarın Türkçe açıklaması ve birimi gösterilir
  const ayarBilgisi = new Map(ayarlar.map((a) => [a.anahtar, a]));
  const sayi = (d: number) => d.toLocaleString("tr-TR");

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-col gap-1">
        <h1 className="text-2xl font-semibold">Ayarlar</h1>
        <p className="text-sm text-muted-foreground">
          Kuralların eşikleri. Değişiklik bir sonraki gece işinde ve hesapta kullanılır; kilitli ayları etkilemez.
        </p>
      </div>

      <div className="rounded-lg border">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Ayar</TableHead>
              <TableHead className="text-right">Değer</TableHead>
              <TableHead>Son değişiklik</TableHead>
              <TableHead><span className="sr-only">İşlem</span></TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {ayarlar.map((a) => (
              <TableRow key={a.anahtar}>
                <TableCell className="min-w-80 max-w-[32rem] whitespace-normal">
                  <div className="text-sm">{a.aciklama}</div>
                  <div className="font-mono text-xs text-muted-foreground">{a.anahtar}</div>
                </TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap">
                  {a.deger.toLocaleString("tr-TR")} <span className="text-muted-foreground">{a.birim}</span>
                </TableCell>
                <TableCell className="text-sm text-muted-foreground">
                  {a.guncelleyen ? `${a.guncelleyen.ad_soyad}, ${tarihSaat(a.guncelleme_zamani)}` : "—"}
                </TableCell>
                <TableCell className="text-right">
                  <IslemPenceresi
                    dugme="Değiştir"
                    dugmeTuru="ghost"
                    baslik={a.aciklama}
                    aciklama={`Şu an: ${a.deger.toLocaleString("tr-TR")} ${a.birim}. Eski ve yeni değer geçmişe yazılır.`}
                    onay="Kaydet"
                    islem={ayarGuncelle}
                    gizli={{ anahtar: a.anahtar }}
                  >
                    <label htmlFor={`deger-${a.anahtar}`} className="text-sm font-medium">Yeni değer ({a.birim})</label>
                    <Input id={`deger-${a.anahtar}`} name="deger" type="number" min={0} step={1} required defaultValue={a.deger} />
                  </IslemPenceresi>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>

      <section aria-labelledby="gecmis-baslik" className="flex flex-col gap-3">
        <div className="flex flex-col gap-1">
          <h2 id="gecmis-baslik" className="text-lg font-semibold">Değişiklik geçmişi</h2>
          <p className="text-sm text-muted-foreground">Son 20 değişiklik. Kayıtlar silinemez; kim, ne zaman, neyi değiştirdi görünür.</p>
        </div>
        {gecmis.length === 0 ? (
          <p className="text-sm text-muted-foreground">Henüz değişiklik yok.</p>
        ) : (
          <div className="rounded-lg border">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Zaman</TableHead>
                  <TableHead>Ayar</TableHead>
                  <TableHead>Değişiklik</TableHead>
                  <TableHead>Yapan</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {gecmis.map((g) => {
                  const ayar = ayarBilgisi.get(g.anahtar);
                  const birim = ayar?.birim ?? "";
                  return (
                    <TableRow key={g.id}>
                      <TableCell className="tarih-hucre">
                        {tarih(g.degisim_zamani)} <span className="ml-1 opacity-80">{saat(g.degisim_zamani)}</span>
                      </TableCell>
                      <TableCell className="min-w-64 max-w-md whitespace-normal" title={g.anahtar}>
                        {ayar?.aciklama ?? g.anahtar}
                      </TableCell>
                      <TableCell>
                        {g.eski_deger === null ? (
                          <span className="inline-flex items-center gap-2">
                            <Badge variant="secondary">İlk değer</Badge>
                            <span className="font-semibold tabular-nums">{sayi(g.yeni_deger)}</span>
                            <span className="text-xs text-muted-foreground">{birim}</span>
                          </span>
                        ) : (
                          <span className="inline-flex items-center gap-2 tabular-nums">
                            <span className="text-muted-foreground line-through decoration-muted-foreground/50">{sayi(g.eski_deger)}</span>
                            <ArrowRightIcon className="size-3.5 text-muted-foreground" aria-label="yerine" />
                            <span className="font-semibold">{sayi(g.yeni_deger)}</span>
                            <span className="text-xs text-muted-foreground">{birim}</span>
                          </span>
                        )}
                      </TableCell>
                      <TableCell>
                        {g.guncelleyen ? (
                          g.guncelleyen.ad_soyad
                        ) : (
                          <span className="text-muted-foreground">Sistem (kurulum)</span>
                        )}
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
