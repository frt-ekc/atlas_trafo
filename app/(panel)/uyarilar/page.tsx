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
import { UYARI_TURU } from "@/lib/etiketler";
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
        {!gecerliTur && turSayisi.size > 1 &&
          ` · ${[...turSayisi.entries()].sort((a, b) => b[1] - a[1]).map(([t, n]) => `${UYARI_TURU[t] ?? t}: ${n}`).join(", ")}`}
      </p>

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
                  <TableCell className="font-medium">{UYARI_TURU[u.tur] ?? u.tur}</TableCell>
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
