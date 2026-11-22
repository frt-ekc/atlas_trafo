import Link from "next/link";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { BosDurum } from "@/components/panel/bos-durum";
import { HizliIslem } from "@/components/panel/hizli-islem";
import { SuzgecFormu } from "@/components/panel/suzgec-formu";
import { Secim } from "@/components/panel/secim";
import { tekDeger } from "@/lib/arama";
import { tarihSaat } from "@/lib/bicim";
import { UYARI_KONULARI, UYARI_TURU } from "@/lib/etiketler";
import { rolGerekli } from "@/lib/oturum";
import { tumSatirlar } from "@/lib/supabase/sayfali";
import { sunucuIstemcisi } from "@/lib/supabase/server";
import { uyariGoruldu } from "./actions";

export const metadata = { title: "Uyarılar" };

type Uyari = {
  id: number;
  tur: string;
  mesaj: string;
  olusturma_zamani: string;
  goruldu: boolean;
  gorulme_zamani: string | null;
  calisan: { id: number; sicil_no: string; ad: string; soyad: string } | null;
  okuyucu: { kod: string } | null;
  goren: { ad_soyad: string } | null;
};

// Sistem en fazla uyarı ya da şüphe üretir; çalışan aleyhine kararı İK verir.
export default async function UyarilarSayfasi({ searchParams }: PageProps<"/uyarilar">) {
  const kullanici = await rolGerekli(["ik", "yonetici", "isg"]);
  const parametre = await searchParams;
  const tumu = tekDeger(parametre.goster) === "tumu";
  const tur = tekDeger(parametre.tur);
  const gecerliTur = tur in UYARI_TURU ? tur : "";

  const supabase = await sunucuIstemcisi();
  const uyarilar = await tumSatirlar<Uyari>((bas, son) => {
    let q = supabase
      .from("uyari")
      .select(
        "id, tur, mesaj, olusturma_zamani, goruldu, gorulme_zamani, " +
          "calisan:calisan_id(id, sicil_no, ad, soyad), okuyucu:okuyucu_id(kod), goren:kullanici!goren_id(ad_soyad)",
      )
      .order("olusturma_zamani", { ascending: false })
      .order("id")
      .range(bas, son);
    if (!tumu) q = q.eq("goruldu", false);
    if (gecerliTur) q = q.eq("tur", gecerliTur);
    return q;
  });

  // Türlere göre sayı (süzgeç yardımı)
  const turSayisi = new Map<string, number>();
  for (const u of uyarilar) turSayisi.set(u.tur, (turSayisi.get(u.tur) ?? 0) + 1);

  // Özet tablosu: konu başına bir satır; yalnızca uyarısı olan konu ve türler
  const konusuOlanlar = new Set(UYARI_KONULARI.flatMap((k) => k.turler));
  const ozet = [...UYARI_KONULARI, { ad: "Diğer", turler: [...turSayisi.keys()].filter((t) => !konusuOlanlar.has(t)) }]
    .map((k) => {
      const turler = k.turler
        .map((t) => ({ tur: t, sayi: turSayisi.get(t) ?? 0 }))
        .filter((t) => t.sayi > 0)
        .sort((a, b) => b.sayi - a.sayi);
      return { ad: k.ad, turler, toplam: turler.reduce((n, t) => n + t.sayi, 0) };
    })
    .filter((k) => k.toplam > 0)
    .sort((a, b) => b.toplam - a.toplam);
  const adres = (t: string) => {
    const p = new URLSearchParams();
    if (tumu) p.set("goster", "tumu");
    if (t) p.set("tur", t);
    const sorgu = p.toString();
    return sorgu ? `/uyarilar?${sorgu}` : "/uyarilar";
  };

  return (
    <div className="flex flex-col gap-5">
      <div className="flex flex-col gap-1">
        <h1 className="text-2xl font-semibold">Uyarılar</h1>
        <p className="text-sm text-muted-foreground">
          Gece işinin ve veritabanı kurallarının ürettiği uyarılar. Uyarı ceza değildir; çalışan aleyhine karar İK&apos;dadır.
        </p>
      </div>

      <SuzgecFormu className="flex flex-wrap items-end gap-2">
        <div className="flex flex-col gap-1.5">
          <label htmlFor="goster" className="text-sm font-medium">Göster</label>
          <Secim id="goster" name="goster" defaultValue={tumu ? "tumu" : ""}>
            <option value="">Görülmemişler</option>
            <option value="tumu">Tümü</option>
          </Secim>
        </div>
        <div className="flex flex-col gap-1.5">
          <label htmlFor="tur" className="text-sm font-medium">Tür</label>
          <Secim id="tur" name="tur" defaultValue={gecerliTur}>
            <option value="">Tüm türler</option>
            {Object.entries(UYARI_TURU).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
          </Secim>
        </div>
        <Button type="submit" size="sm">Göster</Button>
      </SuzgecFormu>

      <p className="text-sm text-muted-foreground" aria-live="polite">
        {uyarilar.length} uyarı
        {gecerliTur && (
          <>
            {" "}· {UYARI_TURU[gecerliTur]} ·{" "}
            <Link href={adres("")} scroll={false} className="text-foreground underline underline-offset-4">Tüm türleri göster</Link>
          </>
        )}
      </p>

      {!gecerliTur && turSayisi.size > 1 && (
        <div className="overflow-hidden rounded-lg border bg-card">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead className="w-20 sm:w-40">Konu</TableHead>
                <TableHead>Uyarı türü</TableHead>
                <TableHead className="w-14 text-right sm:w-20">Toplam</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {ozet.map((k) => (
                <TableRow key={k.ad}>
                  <TableCell className="font-medium whitespace-normal">{k.ad}</TableCell>
                  <TableCell className="whitespace-normal">
                    {/* Türe tıklayınca aşağıdaki liste o türe süzülür */}
                    <div className="flex flex-wrap gap-1.5">
                      {k.turler.map((t) => (
                        <Link
                          key={t.tur}
                          href={adres(t.tur)}
                          scroll={false}
                          className="inline-flex items-center gap-2 rounded-lg border bg-secondary/60 px-2.5 py-1 text-[0.8125rem] transition-colors hover:border-ring/50 hover:bg-secondary"
                        >
                          {UYARI_TURU[t.tur] ?? t.tur}
                          <span className="font-semibold tabular-nums text-vurgu">{t.sayi}</span>
                        </Link>
                      ))}
                    </div>
                  </TableCell>
                  <TableCell className="text-right text-base font-semibold tabular-nums">{k.toplam}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      )}

      {uyarilar.length === 0 ? (
        <BosDurum>{tumu ? "Hiç uyarı yok." : "Görülmemiş uyarı yok."} Uyarılar gece işi çalıştığında oluşur.</BosDurum>
      ) : (
        <div className="rounded-lg border">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Zaman</TableHead>
                <TableHead>Tür</TableHead>
                <TableHead>İlgili</TableHead>
                <TableHead>Mesaj</TableHead>
                <TableHead>Durum</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {uyarilar.map((u) => (
                <TableRow key={u.id}>
                  <TableCell className="tarih-hucre">{tarihSaat(u.olusturma_zamani)}</TableCell>
                  <TableCell className="min-w-36 font-medium whitespace-normal">{UYARI_TURU[u.tur] ?? u.tur}</TableCell>
                  <TableCell>
                    {u.calisan ? (
                      <Link href={`/calisanlar/${u.calisan.id}`} className="underline-offset-4 hover:underline">
                        {u.calisan.ad} {u.calisan.soyad} <span className="font-mono text-xs text-muted-foreground">({u.calisan.sicil_no})</span>
                      </Link>
                    ) : u.okuyucu ? (
                      <span className="font-mono">{u.okuyucu.kod}</span>
                    ) : (
                      "—"
                    )}
                  </TableCell>
                  <TableCell className="min-w-80 max-w-[32rem] whitespace-normal">{u.mesaj}</TableCell>
                  <TableCell>
                    {u.goruldu ? (
                      <span className="text-sm text-muted-foreground">
                        Görüldü · {u.goren?.ad_soyad ?? "—"}
                        <div className="text-xs">{tarihSaat(u.gorulme_zamani)}</div>
                      </span>
                    ) : kullanici.rol === "ik" ? (
                      <div className="flex items-center gap-2">
                        <Badge>Yeni</Badge>
                        <HizliIslem dugme="Görüldü" islem={uyariGoruldu} gizli={{ uyari_id: u.id }} />
                      </div>
                    ) : (
                      <Badge>Yeni</Badge>
                    )}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      )}

    </div>
  );
}
