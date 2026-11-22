import Link from "next/link";
import { Badge } from "@/components/ui/badge";
import { Button, buttonVariants } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Alan, IslemPenceresi } from "@/components/panel/islem-penceresi";
import { SuzgecFormu } from "@/components/panel/suzgec-formu";
import { Secim } from "@/components/panel/secim";
import { aramaTemizle, tekDeger } from "@/lib/arama";
import { tarih } from "@/lib/bicim";
import { bolumNumarasi, gorunurBolumler } from "@/lib/bolumler";
import { bugun } from "@/lib/hafta";
import { rolGerekli } from "@/lib/oturum";
import { sunucuIstemcisi } from "@/lib/supabase/server";
import { calisanEkle } from "./actions";

export const metadata = { title: "Çalışanlar" };

type CalisanSatiri = {
  id: number;
  sicil_no: string;
  ad: string;
  soyad: string;
  ise_giris_tarihi: string;
  isten_cikis_tarihi: string | null;
  aktif: boolean;
  departman: { ad: string } | null;
};

export default async function CalisanlarSayfasi({ searchParams }: PageProps<"/calisanlar">) {
  const kullanici = await rolGerekli(["amir", "ik", "guvenlik", "yonetici", "isg", "admin"]);
  const parametre = await searchParams;

  // Süzgeçler adresten okunur (?ara=...&departman=...&durum=...).
  // Böylece süzülmüş liste yer imine eklenebilir, geri tuşu da çalışır.
  const araMetni = tekDeger(parametre.ara);
  const kelimeler = aramaTemizle(araMetni);
  const departmanId = bolumNumarasi(tekDeger(parametre.departman));
  const tumu = tekDeger(parametre.durum) === "tumu";

  const supabase = await sunucuIstemcisi();

  // Hangi satırların döneceğine RLS karar verir: amir yalnızca kendi bölümlerini görür.
  let sorgu = supabase
    .from("calisan")
    .select("id, sicil_no, ad, soyad, ise_giris_tarihi, isten_cikis_tarihi, aktif, departman:departman_id(ad)")
    .order("sicil_no");

  if (departmanId) sorgu = sorgu.eq("departman_id", departmanId);
  if (!tumu) sorgu = sorgu.eq("aktif", true);
  // Her kelime sicil, ad ya da soyaddan birinde geçmeli ("elif şen" iki kelime de eşleşmeli).
  for (const k of kelimeler) {
    sorgu = sorgu.or(`sicil_no.ilike.*${k}*,ad.ilike.*${k}*,soyad.ilike.*${k}*`);
  }

  const [calisanSonucu, departmanlar] = await Promise.all([sorgu, gorunurBolumler(supabase, kullanici.rol)]);

  if (calisanSonucu.error) throw new Error(`Çalışanlar okunamadı: ${calisanSonucu.error.message}`);

  const calisanlar = (calisanSonucu.data ?? []) as unknown as CalisanSatiri[];
  const suzgecVar = Boolean(araMetni || departmanId || tumu);
  const bugunTarih = bugun();

  return (
    <div className="flex flex-col gap-5">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div className="flex flex-col gap-1">
          <h1 className="text-2xl font-semibold">Çalışanlar</h1>
          <p className="text-sm text-muted-foreground">
            {kullanici.rol === "amir"
              ? "Yalnızca sorumlu olduğunuz bölümlerin çalışanları listelenir."
              : "Fabrikadaki çalışanlar."}
          </p>
        </div>
        {kullanici.rol === "ik" && (
          <IslemPenceresi
            dugme="Çalışan ekle"
            dugmeTuru="default"
            baslik="Yeni çalışan"
            aciklama="İşe giriş ileri tarihli olabilir; o güne kadar gece işi gün kaydı açmaz. Kart ve vardiya planı ayrıca girilir. Departman sonradan değiştirilemez."
            onay="Ekle"
            islem={calisanEkle}
          >
            <div className="grid grid-cols-2 gap-3">
              <Alan etiket="Sicil no" htmlFor="sicil_no">
                <Input id="sicil_no" name="sicil_no" required maxLength={20} autoComplete="off" className="font-mono uppercase" />
              </Alan>
              <Alan etiket="İşe giriş" htmlFor="ise_giris_tarihi">
                <Input id="ise_giris_tarihi" name="ise_giris_tarihi" type="date" required defaultValue={bugunTarih} />
              </Alan>
              <Alan etiket="Ad" htmlFor="ad">
                <Input id="ad" name="ad" required maxLength={50} />
              </Alan>
              <Alan etiket="Soyad" htmlFor="soyad">
                <Input id="soyad" name="soyad" required maxLength={50} />
              </Alan>
            </div>
            <Alan etiket="Departman" htmlFor="departman_id">
              <Secim id="departman_id" name="departman_id" required defaultValue="" className="h-9">
                <option value="" disabled>Seçin</option>
                {departmanlar.map((d) => (
                  <option key={d.id} value={d.id}>{d.ad}</option>
                ))}
              </Secim>
            </Alan>
          </IslemPenceresi>
        )}
      </div>

      <SuzgecFormu className="flex flex-wrap items-end gap-3">
        <div className="flex min-w-48 flex-1 flex-col gap-1.5 sm:max-w-xs">
          <label htmlFor="ara" className="text-sm font-medium">Ara</label>
          <Input id="ara" name="ara" defaultValue={araMetni} placeholder="Sicil, ad ya da soyad" />
        </div>
        <div className="flex flex-col gap-1.5">
          <label htmlFor="departman" className="text-sm font-medium">Bölüm</label>
          <Secim id="departman" name="departman" defaultValue={departmanId ?? ""}>
            <option value="">Tümü</option>
            {departmanlar.map((d) => (
              <option key={d.id} value={d.id}>{d.ad}</option>
            ))}
          </Secim>
        </div>
        <div className="flex flex-col gap-1.5">
          <label htmlFor="durum" className="text-sm font-medium">Durum</label>
          <Secim id="durum" name="durum" defaultValue={tumu ? "tumu" : ""}>
            <option value="">Çalışanlar</option>
            <option value="tumu">Ayrılanlar dahil</option>
          </Secim>
        </div>
        <Button type="submit">Süz</Button>
        {suzgecVar && (
          <Link href="/calisanlar" className={buttonVariants({ variant: "ghost" })}>Temizle</Link>
        )}
      </SuzgecFormu>

      <p className="text-sm text-muted-foreground" aria-live="polite">{calisanlar.length} kişi</p>

      {calisanlar.length === 0 ? (
        <div className="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
          {suzgecVar ? "Süzgece uyan çalışan yok." : "Görebileceğiniz çalışan kaydı yok."}
        </div>
      ) : (
        <div className="rounded-lg border">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead className="w-24">Sicil</TableHead>
                <TableHead>Ad soyad</TableHead>
                <TableHead>Bölüm</TableHead>
                <TableHead>İşe giriş</TableHead>
                <TableHead>Durum</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {calisanlar.map((c) => (
                <TableRow key={c.id}>
                  <TableCell className="font-mono tabular-nums">{c.sicil_no}</TableCell>
                  <TableCell className="font-medium">
                    {!["amir", "ik", "yonetici"].includes(kullanici.rol) ? (
                      `${c.ad} ${c.soyad}`
                    ) : (
                      <Link href={`/calisanlar/${c.id}`} className="underline-offset-4 hover:underline">{c.ad} {c.soyad}</Link>
                    )}
                  </TableCell>
                  <TableCell>{c.departman?.ad ?? "—"}</TableCell>
                  <TableCell className="tarih-hucre">{tarih(c.ise_giris_tarihi)}</TableCell>
                  <TableCell>
                    {c.aktif && c.ise_giris_tarihi > bugunTarih ? (
                      <Badge variant="default">Başlayacak · {tarih(c.ise_giris_tarihi)}</Badge>
                    ) : c.aktif ? (
                      <Badge variant="secondary">Çalışıyor</Badge>
                    ) : (
                      <Badge variant="outline">Ayrıldı{c.isten_cikis_tarihi ? ` · ${tarih(c.isten_cikis_tarihi)}` : ""}</Badge>
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
