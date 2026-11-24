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
import { Secim } from "@/components/panel/secim";
import { Zaman } from "@/components/liste/zaman";
import { tekDeger } from "@/lib/arama";
import { sureMetni } from "@/lib/bicim";
import { rolGerekli } from "@/lib/oturum";
import { sunucuIstemcisi } from "@/lib/supabase/server";
import { ayarGuncelle } from "./actions";

export const metadata = { title: "Ayarlar" };

type Ayar = {
  anahtar: string;
  ad: string;
  kategori: string;
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

// Evet / hayır ayarı ekranda Açık / Kapalı seçimidir; veritabanında 1 / 0 kalır
const acikKapali = (birim: string) => birim === "evet/hayır";
const birimAdi = (birim: string) => (birim === "dakika" ? "dk" : birim === "saat" ? "sa" : birim);
function degerMetni(deger: number, birim: string): string {
  if (acikKapali(birim)) return deger === 1 ? "Açık" : "Kapalı";
  if (birim === "dakika") return sureMetni(deger);
  if (birim === "yüzde") return `%${deger}`;
  return `${deger.toLocaleString("tr-TR")} ${birimAdi(birim)}`;
}

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
    supabase.from("ayar").select("anahtar, ad, kategori, deger, en_az, en_cok, puantaji_etkiler, birim, aciklama, guncelleme_zamani, guncelleyen:kullanici!guncelleyen_id(ad_soyad)").order("sira"),
    supabase
      .from("ayar_gecmisi")
      .select("id, anahtar, eski_deger, yeni_deger, degisim_zamani, guncelleyen:kullanici!guncelleyen_id(ad_soyad)")
      .order("id", { ascending: false })
      .limit(20),
  ]);
  if (ayarSonucu.error) throw new Error(`Ayarlar okunamadı: ${ayarSonucu.error.message}`);

  const ayarlar = (ayarSonucu.data ?? []) as unknown as Ayar[];
  const gecmis = (gecmisSonucu.data ?? []) as unknown as Gecmis[];
  // Geçmişte anahtar yerine ayarın adı ve birimi gösterilir
  const ayarBilgisi = new Map(ayarlar.map((a) => [a.anahtar, a]));
  // Listede değerle aynı biçimde ("8 sa – 11 sa"), pencerede girişin birimiyle ("480 – 660 dk")
  const aralik = (a: Ayar) => `${degerMetni(a.en_az, a.birim)} – ${degerMetni(a.en_cok, a.birim)}`;
  const girisAraligi = (a: Ayar) => `${a.en_az.toLocaleString("tr-TR")} – ${a.en_cok.toLocaleString("tr-TR")} ${birimAdi(a.birim)}`;
  // Ayar adı / açıklaması araması ekranda yapılır
  const gosterilenAyarlar = ayarlar.filter((a) => uyar(a.ad, a.aciklama, a.kategori));

  // Kategoriler veritabanındaki sıraya göre
  const kategoriler = [...new Set(gosterilenAyarlar.map((a) => a.kategori))];

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-col gap-1">
        <h1 className="text-2xl font-semibold">Ayarlar</h1>
        <p className="text-sm text-muted-foreground">
          Sistem kurallarında kullanılan değerler. Değişiklikler bir sonraki hesaplamadan itibaren geçerli olur, kilitli ayları etkilemez.
        </p>
      </div>

      <Sekmeler
        etiket="Ayarlar bölümleri"
        sekmeler={[
          { ad: "Ayarlar", adres: "/ayarlar", sayi: ayarlar.length, aktif: !gecmisSekmesi },
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
            <BosDurum aciklama="Kayıt bulunmuyor." />
          ) : (
            kategoriler.map((kategori) => (
              <section key={kategori} aria-label={kategori} className="flex flex-col gap-2">
                <h2 className="text-lg font-semibold">{kategori}</h2>
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
                      {gosterilenAyarlar.filter((a) => a.kategori === kategori).map((a) => (
                        <TableRow key={a.anahtar}>
                          <TableCell className="min-w-32 whitespace-normal break-words sm:min-w-48">
                            <div className="text-sm font-medium">{a.ad}</div>
                            <div className="text-xs text-muted-foreground">{a.aciklama}</div>
                          </TableCell>
                          <TableCell className="text-right tabular-nums">
                            {degerMetni(a.deger, a.birim)}
                            {!acikKapali(a.birim) && (
                              <div className="text-xs text-muted-foreground"><span className="sr-only">İzin verilen aralık: </span>{aralik(a)}</div>
                            )}
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
                              baslik={a.ad}
                              aciklama={`${a.aciklama} Mevcut değer: ${degerMetni(a.deger, a.birim)}.${a.puantaji_etkiler ? " Değişiklik İK'ya bildirilir." : ""}`}
                              onay="Kaydet"
                              islem={ayarGuncelle}
                              gizli={{ anahtar: a.anahtar }}
                            >
                              {acikKapali(a.birim) ? (
                                <>
                                  <label htmlFor={`deger-${a.anahtar}`} className="text-sm font-medium">Yeni değer</label>
                                  <Secim id={`deger-${a.anahtar}`} name="deger" required defaultValue={String(a.deger)}>
                                    <option value="1">Açık</option>
                                    <option value="0">Kapalı</option>
                                  </Secim>
                                </>
                              ) : (
                                <>
                                  <label htmlFor={`deger-${a.anahtar}`} className="text-sm font-medium">Yeni değer ({birimAdi(a.birim)})</label>
                                  <Input id={`deger-${a.anahtar}`} name="deger" type="number" min={a.en_az} max={a.en_cok} step={1} required defaultValue={a.deger} />
                                  <p className="text-xs text-muted-foreground">İzin verilen aralık: {girisAraligi(a)}</p>
                                </>
                              )}
                            </IslemPenceresi>
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </TabloKutusu>
              </section>
            ))
          )}
        </>
      )}

      {gecmisSekmesi && (
      <section aria-labelledby="gecmis-baslik" className="flex flex-col gap-3">
        <div className="flex flex-col gap-1">
          <h2 id="gecmis-baslik" className="text-lg font-semibold">Değişiklik geçmişi</h2>
          <p className="text-sm text-muted-foreground">Son 20 değişiklik gösterilir. Kayıtlar silinemez.</p>
        </div>
        {gecmis.length === 0 ? (
          <BosDurum aciklama="Kayıt bulunmuyor." />
        ) : (
          <TabloKutusu>
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Zaman</TableHead>
                  <TableHead className="w-full">Ayar</TableHead>
                  <TableHead>Değişiklik</TableHead>
                  <TableHead>İşlemi yapan</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {gecmis.map((g) => {
                  const ayar = ayarBilgisi.get(g.anahtar);
                  const birim = ayar?.birim ?? "";
                  return (
                    <TableRow key={g.id}>
                      <TableCell className="tarih-hucre"><Zaman deger={g.degisim_zamani} /></TableCell>
                      <TableCell className="min-w-64 whitespace-normal">
                        {ayar?.ad ?? "—"}
                      </TableCell>
                      <TableCell>
                        {g.eski_deger === null ? (
                          <span className="inline-flex items-center gap-2">
                            <Badge variant="secondary">İlk değer</Badge>
                            <span className="font-semibold tabular-nums">{degerMetni(g.yeni_deger, birim)}</span>
                          </span>
                        ) : (
                          <span className="inline-flex items-center gap-2 tabular-nums">
                            <span className="text-muted-foreground line-through decoration-muted-foreground/50">{degerMetni(g.eski_deger, birim)}</span>
                            <ArrowRightIcon className="size-3.5 text-muted-foreground" aria-label="yerine" />
                            <span className="font-semibold">{degerMetni(g.yeni_deger, birim)}</span>
                          </span>
                        )}
                      </TableCell>
                      <TableCell>
                        {g.guncelleyen ? (
                          g.guncelleyen.ad_soyad
                        ) : (
                          <span className="text-muted-foreground">Sistem</span>
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
