import { ArrowRightIcon } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { IslemPenceresi } from "@/components/panel/islem-penceresi";
import { aramaSuzgeci } from "@/components/liste/arama";
import { BosDurum } from "@/components/liste/bos-durum";
import { FiltreAlani, FiltreCubugu } from "@/components/liste/filtre-cubugu";
import { Sekmeler } from "@/components/liste/sekmeler";
import { TabloKutusu } from "@/components/liste/tablo-kutusu";
import { Zaman } from "@/components/liste/zaman";
import { tekDeger } from "@/lib/arama";
import { rolGerekli } from "@/lib/oturum";
import { sunucuIstemcisi } from "@/lib/supabase/server";
import { ayarGuncelle } from "./actions";

export const metadata = { title: "Ayarlar" };

type Ayar = {
  anahtar: string;
  deger: number;
  en_az: number;
  en_cok: number;
  puantaji_etkiler: boolean;
  birim: string;
  aciklama: string;
  guncelleme_zamani: string;
  guncelleyen: { ad_soyad: string } | null;
};
type Gecmis = { id: number; anahtar: string; eski_deger: number | null; yeni_deger: number; degisim_zamani: string; guncelleyen: { ad_soyad: string } | null };

// Kuralların eşikleri (tolerans, mola, fazla mesai sınırları…) koda değil bu tabloya yazılıdır.
// Yalnızca sistem yöneticisi değiştirir; her değişiklik geçmişe yazılır.
// Aralık (en_az – en_cok) veritabanından gelir; asıl denetim ayar_guncelle'dedir, input yalnızca yardımcıdır.
export default async function AyarlarSayfasi({ searchParams }: PageProps<"/ayarlar">) {
  await rolGerekli(["admin"]);
  const parametre = await searchParams;
  const gecmisSekmesi = tekDeger(parametre.sekme) === "gecmis";
  const araMetni = tekDeger(parametre.ara).slice(0, 100);
  const uyar = aramaSuzgeci(araMetni);
  const supabase = await sunucuIstemcisi();

  const [ayarSonucu, gecmisSonucu] = await Promise.all([
    supabase.from("ayar").select("anahtar, deger, en_az, en_cok, puantaji_etkiler, birim, aciklama, guncelleme_zamani, guncelleyen:kullanici!guncelleyen_id(ad_soyad)").order("anahtar"),
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
  const aralik = (a: Ayar) => `${sayi(a.en_az)} – ${sayi(a.en_cok)}`;
  // Ayar adı / açıklaması araması ekranda yapılır
  const gosterilenAyarlar = ayarlar.filter((a) => uyar(a.aciklama, a.anahtar));

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-col gap-1">
        <h1 className="text-2xl font-semibold">Ayarlar</h1>
        <p className="text-sm text-muted-foreground">
          Kuralların eşikleri. Değişiklik bir sonraki gece işinde ve hesapta kullanılır; kilitli ayları etkilemez.
        </p>
      </div>

      <Sekmeler
        etiket="Ayarlar bölümleri"
        sekmeler={[
          { ad: "Eşikler", adres: "/ayarlar", sayi: ayarlar.length, aktif: !gecmisSekmesi },
          { ad: "Değişiklik geçmişi", adres: "/ayarlar?sekme=gecmis", aktif: gecmisSekmesi },
        ]}
      />

      {!gecmisSekmesi && (
        <>
          <FiltreCubugu temizleAdres="/ayarlar" suzgecVar={Boolean(araMetni)}>
            <FiltreAlani etiket="Ayar ara" htmlFor="ara" className="min-w-48 flex-1 sm:max-w-sm">
              <Input id="ara" name="ara" type="search" defaultValue={araMetni} placeholder="ör. mola, fazla mesai, tolerans" />
            </FiltreAlani>
          </FiltreCubugu>
          {gosterilenAyarlar.length === 0 ? (
            <BosDurum aciklama="Aramaya uyan ayar yok." />
          ) : (
            <TabloKutusu>
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead className="w-full">Ayar</TableHead>
                    <TableHead className="text-right">Değer</TableHead>
                    <TableHead className="max-sm:hidden">Son değişiklik</TableHead>
                    <TableHead><span className="sr-only">İşlem</span></TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {gosterilenAyarlar.map((a) => (
                    <TableRow key={a.anahtar}>
                      <TableCell className="min-w-32 whitespace-normal break-words sm:min-w-48">
                        <div className="text-sm">{a.aciklama}</div>
                        <div className="font-mono text-xs break-all text-muted-foreground">{a.anahtar}</div>
                      </TableCell>
                      <TableCell className="text-right tabular-nums">
                        {a.deger.toLocaleString("tr-TR")} <span className="text-muted-foreground">{a.birim}</span>
                        <div className="text-xs text-muted-foreground"><span className="sr-only">İzin verilen aralık: </span>{aralik(a)}</div>
                      </TableCell>
                      <TableCell className="text-sm text-muted-foreground max-sm:hidden">
                        {a.guncelleyen ? (
                          <>
                            {a.guncelleyen.ad_soyad}
                            <div className="text-xs"><Zaman deger={a.guncelleme_zamani} /></div>
                          </>
                        ) : "—"}
                      </TableCell>
                      <TableCell className="text-right">
                        <IslemPenceresi
                          dugme="Değiştir"
                          dugmeTuru="outline"
                          baslik={a.aciklama}
                          aciklama={`Şu an: ${a.deger.toLocaleString("tr-TR")} ${a.birim}. Eski ve yeni değer geçmişe yazılır.${a.puantaji_etkiler ? " Puantajı etkilediği için İK'ya uyarı gider." : ""}`}
                          onay="Kaydet"
                          islem={ayarGuncelle}
                          gizli={{ anahtar: a.anahtar }}
                        >
                          <label htmlFor={`deger-${a.anahtar}`} className="text-sm font-medium">Yeni değer ({a.birim})</label>
                          <Input id={`deger-${a.anahtar}`} name="deger" type="number" min={a.en_az} max={a.en_cok} step={1} required defaultValue={a.deger} />
                          <p className="text-xs text-muted-foreground">İzin verilen aralık: {aralik(a)} {a.birim}</p>
                        </IslemPenceresi>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </TabloKutusu>
          )}
        </>
      )}

      {gecmisSekmesi && (
      <section aria-labelledby="gecmis-baslik" className="flex flex-col gap-3">
        <div className="flex flex-col gap-1">
          <h2 id="gecmis-baslik" className="text-lg font-semibold">Değişiklik geçmişi</h2>
          <p className="text-sm text-muted-foreground">Son 20 değişiklik. Kayıtlar silinemez; kim, ne zaman, neyi değiştirdi görünür.</p>
        </div>
        {gecmis.length === 0 ? (
          <BosDurum aciklama="Henüz ayar değiştirilmedi." />
        ) : (
          <TabloKutusu>
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Zaman</TableHead>
                  <TableHead className="w-full">Ayar</TableHead>
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
                      <TableCell className="tarih-hucre"><Zaman deger={g.degisim_zamani} /></TableCell>
                      <TableCell className="min-w-64 whitespace-normal" title={g.anahtar}>
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
          </TabloKutusu>
        )}
      </section>
      )}
    </div>
  );
}
