import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { HizliIslem } from "@/components/panel/hizli-islem";
import { Alan, IslemPenceresi } from "@/components/panel/islem-penceresi";
import { Secim } from "@/components/panel/secim";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { BosDurum } from "@/components/liste/bos-durum";
import { DurumRozeti } from "@/components/liste/durum-rozeti";
import { IslemMenusu } from "@/components/liste/islem-menusu";
import { ListeKarti } from "@/components/liste/liste-karti";
import { Sekmeler } from "@/components/liste/sekmeler";
import { TabloKutusu } from "@/components/liste/tablo-kutusu";
import { Zaman } from "@/components/liste/zaman";
import { tekDeger } from "@/lib/arama";
import { KAYNAK_ADI, type Kaynak, type Okuyucu } from "@/lib/aktarim/denetim";
import { tarih, tarihSaat } from "@/lib/bicim";
import { bugun, gunEkle } from "@/lib/hafta";
import { rolGerekli } from "@/lib/oturum";
import { tumSatirlar } from "@/lib/supabase/sayfali";
import { sunucuIstemcisi } from "@/lib/supabase/server";
import { arizaGir, arizaKarari, geceIsiTetikle } from "./actions";
import { AktarimFormu } from "./aktarim-formu";

export const metadata = { title: "Veri aktarımı" };

type Aktarim = { id: number; kaynak: Kaynak; dosya_adi: string; veri_tarihi: string; satir_sayisi: number; aktarim_zamani: string };

const KAYNAKLAR = Object.keys(KAYNAK_ADI) as Kaynak[];
const SON_AKTARIM_SAYISI = 20;
const SON_GECE_ISI_SAYISI = 10;

type Ariza = {
  id: number;
  baslangic: string;
  bitis: string | null;
  kaynak: "manuel" | "otomatik_suphe";
  durum: "suphe" | "onaylandi" | "reddedildi";
  aciklama: string | null;
  okuyucu: { kod: string; ad: string } | null;
};

const ARIZA_DURUMU: Record<Ariza["durum"], { ad: string; tur: "default" | "secondary" | "outline" }> = {
  suphe: { ad: "Şüphe · İK kararı bekliyor", tur: "default" },
  onaylandi: { ad: "Arıza", tur: "secondary" },
  reddedildi: { ad: "Reddedildi", tur: "outline" },
};

type GeceIsi = {
  id: number;
  islenen_gun: string;
  durum: "calisiyor" | "basarili" | "hatali";
  baslangic: string;
  bitis: string | null;
  ozet: Record<string, unknown> | null;
  hata_mesaji: string | null;
};

const GECE_ISI_DURUMU: Record<GeceIsi["durum"], { ad: string; tur: "default" | "secondary" | "destructive" }> = {
  calisiyor: { ad: "Çalışıyor", tur: "default" },
  basarili: { ad: "Başarılı", tur: "secondary" },
  hatali: { ad: "Hatalı", tur: "destructive" },
};

// Özetteki sayılardan kısa bir metin: "31 gün kaydı · 2 soru · 1 uyarı"
function ozetMetni(ozet: GeceIsi["ozet"]): string {
  if (!ozet) return "—";
  const adlar: [string, string][] = [
    ["gun_kaydi", "gün kaydı"],
    ["duzeltme", "düzeltme"],
    ["soru", "soru"],
    ["eskale", "eskale"],
    ["uyari", "uyarı"],
  ];
  const parcalar = adlar.filter(([k]) => typeof ozet[k] === "number" && ozet[k]).map(([k, ad]) => `${ozet[k]} ${ad}`);
  return parcalar.join(" · ") || "Değişiklik yok";
}

export default async function VeriAktarimiSayfasi({ searchParams }: PageProps<"/veri-aktarimi">) {
  const kullanici = await rolGerekli(["ik", "yonetici"]);
  // Uzun sayfa üç sekmeye bölünür (?sekme=ariza | okuyucu); varsayılan aktarımlar
  const istenenSekme = tekDeger((await searchParams).sekme);
  const sekme = istenenSekme === "ariza" || istenenSekme === "okuyucu" ? istenenSekme : "aktarim";
  const supabase = await sunucuIstemcisi();

  const bugunTarih = bugun();
  const ayBasi = `${bugunTarih.slice(0, 7)}-01`;
  // Ayın 1'ine 31 gün eklemek her zaman sonraki aya düşer
  const sonrakiAyBasi = `${gunEkle(ayBasi, 31).slice(0, 7)}-01`;
  const ayAdi = new Intl.DateTimeFormat("tr-TR", { month: "long", year: "numeric", timeZone: "UTC" }).format(
    new Date(`${ayBasi}T00:00:00Z`),
  );

  const [okuyucuSonucu, buAy, sonlar, geceIsiSonucu, arizaSonucu] = await Promise.all([
    supabase.from("okuyucu").select("id, kod, ad, sistem, aktif").order("kod"),
    tumSatirlar<Aktarim>((bas, son) =>
      supabase
        .from("aktarim")
        .select("id, kaynak, dosya_adi, veri_tarihi, satir_sayisi, aktarim_zamani")
        .gte("veri_tarihi", ayBasi)
        .lt("veri_tarihi", sonrakiAyBasi)
        .order("id")
        .range(bas, son),
    ),
    supabase
      .from("aktarim")
      .select("id, kaynak, dosya_adi, veri_tarihi, satir_sayisi, aktarim_zamani")
      .order("veri_tarihi", { ascending: false })
      .order("kaynak")
      .limit(SON_AKTARIM_SAYISI),
    supabase
      .from("gece_isi")
      .select("id, islenen_gun, durum, baslangic, bitis, ozet, hata_mesaji")
      // Demo düğmesiyle çalışan günlerin başlangıç zamanı aynı olabilir; kayıt sırası esas alınır
      .order("id", { ascending: false })
      .limit(SON_GECE_ISI_SAYISI),
    supabase
      .from("ariza")
      .select("id, baslangic, bitis, kaynak, durum, aciklama, okuyucu:okuyucu_id(kod, ad)")
      .order("baslangic", { ascending: false })
      .limit(20),
  ]);
  if (okuyucuSonucu.error) throw new Error(`Okuyucular okunamadı: ${okuyucuSonucu.error.message}`);
  if (sonlar.error) throw new Error(`Aktarımlar okunamadı: ${sonlar.error.message}`);

  const okuyucular = (okuyucuSonucu.data ?? []) as Okuyucu[];
  const sonAktarimlar = (sonlar.data ?? []) as Aktarim[];
  const geceIsleri = (geceIsiSonucu.data ?? []) as GeceIsi[];
  const arizalar = (arizaSonucu.data ?? []) as unknown as Ariza[];
  const ik = kullanici.rol === "ik";
  const dun = gunEkle(bugunTarih, -1);
  // Arıza şüpheleri İK kararı bekler: Uyarılar'daki "Karar gerekli" kartı düzeninde üstte gösterilir
  const supheler = arizalar.filter((a) => a.durum === "suphe");
  const kararliArizalar = arizalar.filter((a) => a.durum !== "suphe");

  // Bu ay gelmeyen dosyalar: ayın ilk gününden, gelen en son dosyanın gününe kadar her gün
  // her kaynaktan bir dosya beklenir. (Gece işi de eksik dosya için "dosya_gelmedi" uyarısı üretir.)
  const gelen = new Set(buAy.map((a) => `${a.kaynak}|${a.veri_tarihi}`));
  const sonGun = buAy.reduce((enSon, a) => (a.veri_tarihi > enSon ? a.veri_tarihi : enSon), "");
  const eksikler: { gun: string; kaynak: Kaynak }[] = [];
  for (let g = ayBasi; sonGun && g <= sonGun; g = gunEkle(g, 1)) {
    for (const k of KAYNAKLAR) if (!gelen.has(`${k}|${g}`)) eksikler.push({ gun: g, kaynak: k });
  }

  return (
    <div className="flex flex-col gap-5">
      <div className="flex flex-col gap-1">
        <h1 className="text-2xl font-semibold">Veri aktarımı</h1>
        <p className="text-sm text-muted-foreground">
          PDKS, kapı, yemekhane ve servis sistemlerinin günlük dosyaları buradan alınır. Ham kayıtlar bir kez yazılır;
          değiştirilemez ve silinemez.
        </p>
      </div>

      <Sekmeler
        etiket="Veri aktarımı bölümleri"
        sekmeler={[
          { ad: "Aktarımlar", adres: "/veri-aktarimi", sayi: eksikler.length || undefined, sayiAciklama: "eksik dosya", aktif: sekme === "aktarim" },
          { ad: "Okuyucu arızaları", adres: "/veri-aktarimi?sekme=ariza", sayi: supheler.length || undefined, sayiAciklama: "karar bekliyor", aktif: sekme === "ariza" },
          { ad: "Okuyucular", adres: "/veri-aktarimi?sekme=okuyucu", aktif: sekme === "okuyucu" },
        ]}
      />

      {sekme === "aktarim" && (
        <div className="flex flex-col gap-8">
      {kullanici.rol === "ik" && (
        <section aria-labelledby="yukle-baslik" className="flex flex-col gap-3">
          <div className="flex flex-col gap-1">
            <h2 id="yukle-baslik" className="text-lg font-semibold">Dosya yükle</h2>
            <p className="text-sm text-muted-foreground">
              Biçim: başlık satırı <code className="font-mono">okuyucu;kart_no;zaman;yon</code>, zaman Türkiye saatiyle
              (<code className="font-mono">2026-11-26 08:01</code>). Dosya adına günü yazın:{" "}
              <code className="font-mono">pdks_20261126.csv</code>.{" "}
              <a href="/ornek/pdks_20261201.csv" download className="text-primary underline-offset-4 hover:underline">
                Örnek dosyayı indir
              </a>
            </p>
          </div>
          <AktarimFormu okuyucular={okuyucular} />
        </section>
      )}

      <section aria-labelledby="gece-baslik" className="flex flex-col gap-3">
        <div className="flex flex-wrap items-end justify-between gap-3">
          <div className="flex flex-col gap-1">
            <h2 id="gece-baslik" className="text-lg font-semibold">Gece işi</h2>
            <p className="text-sm text-muted-foreground">
              Her gece kendiliğinden çalışır: okutmaları işaretler, günlük kayıtları kurar, kanıt varsa düzeltir, yoksa amire sorar,
              uyarıları yazar. Demoda aşağıdaki düğmeyle de çalıştırılır.
            </p>
          </div>
          {kullanici.rol === "ik" && (
            <IslemPenceresi
              dugme="Gece işini çalıştır"
              dugmeTuru="default"
              baslik="Gece işini çalıştır"
              aciklama="Seçilen günler sırayla işlenir (en fazla 62 gün). Tekrar çalıştırmak güvenlidir: var olan kayıtlar bozulmaz, yalnızca eksikler eklenir. Verisi yüklenmemiş gün işlenmez."
              onay="Çalıştır"
              islem={geceIsiTetikle}
            >
              <div className="grid grid-cols-2 gap-3">
                <Alan etiket="Başlangıç" htmlFor="baslangic">
                  <Input id="baslangic" name="baslangic" type="date" required defaultValue={ayBasi <= dun ? ayBasi : dun} />
                </Alan>
                <Alan etiket="Bitiş" htmlFor="bitis">
                  <Input id="bitis" name="bitis" type="date" required defaultValue={dun} />
                </Alan>
              </div>
            </IslemPenceresi>
          )}
        </div>
        {geceIsleri.length === 0 ? (
          <BosDurum aciklama="Gece işi henüz hiç çalışmadı." />
        ) : (
          <TabloKutusu>
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>İşlenen gün</TableHead>
                  <TableHead>Çalışma zamanı</TableHead>
                  <TableHead>Durum</TableHead>
                  <TableHead className="w-full">Sonuç</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {geceIsleri.map((g) => (
                  <TableRow key={g.id}>
                    <TableCell className="tarih-hucre">{tarih(g.islenen_gun)}</TableCell>
                    <TableCell className="tarih-hucre">{tarihSaat(g.baslangic)}</TableCell>
                    <TableCell><Badge variant={GECE_ISI_DURUMU[g.durum].tur}>{GECE_ISI_DURUMU[g.durum].ad}</Badge></TableCell>
                    <TableCell className="min-w-64 whitespace-normal text-sm">
                      {g.durum === "hatali" ? <span className="text-destructive">{g.hata_mesaji ?? "—"}</span> : ozetMetni(g.ozet)}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </TabloKutusu>
        )}
      </section>

      <section aria-labelledby="eksik-baslik" className="flex flex-col gap-3">
        <div className="flex flex-col gap-1">
          <h2 id="eksik-baslik" className="text-lg font-semibold">Gelmeyen dosyalar · {ayAdi}</h2>
          <p className="text-sm text-muted-foreground">
            {sonGun ? `${tarih(ayBasi)} – ${tarih(sonGun)} arasında her gün her sistemden bir dosya beklenir.` : "Bu ay henüz dosya gelmedi."}
          </p>
        </div>
        {sonGun && eksikler.length === 0 ? (
          <BosDurum baslik="Eksik dosya yok" aciklama="Bu ay beklenen bütün dosyalar geldi." />
        ) : (
          <ul className="flex flex-wrap gap-2">
            {eksikler.map((e) => (
              <li key={`${e.kaynak}|${e.gun}`}>
                <Badge variant="destructive">{tarih(e.gun)} · {KAYNAK_ADI[e.kaynak]}</Badge>
              </li>
            ))}
          </ul>
        )}
      </section>

      <section aria-labelledby="son-baslik" className="flex flex-col gap-3">
        <h2 id="son-baslik" className="text-lg font-semibold">Son aktarımlar</h2>
        {sonAktarimlar.length === 0 ? (
          <BosDurum aciklama="Henüz dosya aktarılmadı." />
        ) : (
          <TabloKutusu>
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Verinin günü</TableHead>
                  <TableHead>Tür</TableHead>
                  <TableHead className="w-full">Dosya</TableHead>
                  <TableHead className="text-right">Satır</TableHead>
                  <TableHead>Aktarım zamanı</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {sonAktarimlar.map((a) => (
                  <TableRow key={a.id}>
                    <TableCell className="tarih-hucre">{tarih(a.veri_tarihi)}</TableCell>
                    <TableCell>{KAYNAK_ADI[a.kaynak]}</TableCell>
                    <TableCell className="font-mono text-xs">{a.dosya_adi}</TableCell>
                    <TableCell className="text-right tabular-nums">{a.satir_sayisi.toLocaleString("tr-TR")}</TableCell>
                    <TableCell className="tarih-hucre">{tarihSaat(a.aktarim_zamani)}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </TabloKutusu>
        )}
      </section>

        </div>
      )}

      {sekme === "ariza" && (
      <section aria-labelledby="ariza-baslik" className="flex flex-col gap-4">
        <div className="flex flex-wrap items-end justify-between gap-3">
          <div className="flex flex-col gap-1">
            <h2 id="ariza-baslik" className="text-lg font-semibold">Okuyucu arızaları</h2>
            <p className="text-sm text-muted-foreground">
              Arıza süresince okutması eksik çalışan devamsız sayılmaz: gece işi kanıt arar, yoksa amire sorar. Hiç okutma gelmeyen
              okuyucu için gece işi “arıza şüphesi” açar; kararı İK verir.
            </p>
          </div>
          {ik && (
            <IslemPenceresi
              dugme="Arıza gir"
              baslik="Okuyucu arızası"
              aciklama="Bitişi bilinmiyorsa boş bırakın; arıza sürüyor sayılır."
              onay="Kaydet"
              islem={arizaGir}
            >
              <Alan etiket="Okuyucu" htmlFor="okuyucu_id">
                <Secim id="okuyucu_id" name="okuyucu_id" required defaultValue="" className="h-9">
                  <option value="" disabled>Seçin</option>
                  {okuyucular.filter((o) => o.aktif).map((o) => (
                    <option key={o.id} value={o.id}>{o.kod} · {o.ad}</option>
                  ))}
                </Secim>
              </Alan>
              <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                <Alan etiket="Başlangıç" htmlFor="ariza-bas">
                  <Input id="ariza-bas" name="baslangic" type="datetime-local" required />
                </Alan>
                <Alan etiket="Bitiş (isteğe bağlı)" htmlFor="ariza-bit">
                  <Input id="ariza-bit" name="bitis" type="datetime-local" />
                </Alan>
              </div>
              <Alan etiket="Açıklama (isteğe bağlı)" htmlFor="ariza-aciklama">
                <Textarea id="ariza-aciklama" name="aciklama" rows={2} maxLength={500} placeholder="ör. Turnike kart okuyucusu yanıt vermiyor" />
              </Alan>
            </IslemPenceresi>
          )}
        </div>

        {supheler.length > 0 && (
          <div className="flex flex-col gap-3">
            <h3 className="flex items-center gap-2 text-base font-semibold">
              Karar gerekli
              <DurumRozeti ton="dikkat">{supheler.length}</DurumRozeti>
            </h3>
            {supheler.map((a) => (
              <ListeKarti
                key={a.id}
                vurgu="karar"
                baslik="Okuyucu arıza şüphesi"
                kisi={
                  a.okuyucu ? (
                    <span>
                      Okuyucu <span className="font-mono font-medium">{a.okuyucu.kod}</span>
                      <span className="text-muted-foreground"> · {a.okuyucu.ad}</span>
                    </span>
                  ) : undefined
                }
                // Olayın zamanı (arızanın başladığı an) öne çıkar
                zaman={
                  <>
                    <Zaman deger={a.baslangic} etiket="Başlangıç" />
                    {a.bitis ? <> · <Zaman deger={a.bitis} etiket="Bitiş" /></> : " · sürüyor"}
                  </>
                }
                alt={a.kaynak === "manuel" ? "İK girdi" : "Gece işi buldu"}
                eylemler={
                  ik ? (
                    <>
                      <HizliIslem dugme="Arıza" dugmeTuru="default" islem={arizaKarari} gizli={{ ariza_id: a.id, karar: "onay" }} />
                      <IslemMenusu>
                        {/* Geri alınamaz: tek tıkla değil, onay penceresiyle (aynı işlem, aynı RPC) */}
                        <IslemPenceresi
                          dugme="Arıza değil"
                          baslik="Arıza şüphesini reddet"
                          aciklama="Okuyucu arızası reddedilecek; eksik okutmalar normal soru akışına girecek."
                          onay="Arıza değil"
                          onayTuru="destructive"
                          islem={arizaKarari}
                          gizli={{ ariza_id: a.id, karar: "ret" }}
                        />
                      </IslemMenusu>
                    </>
                  ) : undefined
                }
              >
                {a.aciklama ?? "Açıklama yok."}
              </ListeKarti>
            ))}
          </div>
        )}

        <div className="flex flex-col gap-3">
          {supheler.length > 0 && <h3 className="text-base font-semibold">Kararı verilmiş arızalar</h3>}
          {kararliArizalar.length === 0 ? (
            <BosDurum aciklama={supheler.length > 0 ? "Kararı verilmiş arıza kaydı yok." : "Kayıtlı arıza yok."} />
          ) : (
            <TabloKutusu>
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Başlangıç</TableHead>
                    <TableHead>Bitiş</TableHead>
                    <TableHead>Okuyucu</TableHead>
                    <TableHead className="w-full">Açıklama</TableHead>
                    <TableHead>Durum</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {kararliArizalar.map((a) => (
                    <TableRow key={a.id}>
                      <TableCell className="tarih-hucre">{tarihSaat(a.baslangic)}</TableCell>
                      <TableCell className="tabular-nums">{a.bitis ? tarihSaat(a.bitis) : "Sürüyor"}</TableCell>
                      <TableCell className="font-mono">{a.okuyucu?.kod ?? "—"}</TableCell>
                      <TableCell className="min-w-56 whitespace-normal text-sm">{a.aciklama ?? "—"}</TableCell>
                      <TableCell>
                        <Badge variant={ARIZA_DURUMU[a.durum].tur}>{ARIZA_DURUMU[a.durum].ad}</Badge>
                        <div className="mt-1 text-xs text-muted-foreground">{a.kaynak === "manuel" ? "İK girdi" : "Gece işi buldu"}</div>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </TabloKutusu>
          )}
        </div>
      </section>
      )}

      {sekme === "okuyucu" && (
      <section aria-labelledby="okuyucu-baslik" className="flex flex-col gap-3">
        <div className="flex flex-col gap-1">
          <h2 id="okuyucu-baslik" className="text-lg font-semibold">Okuyucular</h2>
          <p className="text-sm text-muted-foreground">{okuyucular.length} okuyucu · {okuyucular.filter((o) => !o.aktif).length} pasif</p>
        </div>
        <TabloKutusu>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Kod</TableHead>
                <TableHead className="w-full">Ad</TableHead>
                <TableHead>Sistem</TableHead>
                <TableHead>Durum</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {okuyucular.map((o) => (
                <TableRow key={o.id}>
                  <TableCell className="font-mono">{o.kod}</TableCell>
                  <TableCell>{o.ad}</TableCell>
                  <TableCell>{KAYNAK_ADI[o.sistem]}</TableCell>
                  <TableCell>{o.aktif ? "Aktif" : <DurumRozeti ton="notr">Pasif</DurumRozeti>}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </TabloKutusu>
      </section>
      )}
    </div>
  );
}
