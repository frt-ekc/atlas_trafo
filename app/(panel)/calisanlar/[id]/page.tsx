import Link from "next/link";
import { notFound } from "next/navigation";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { buttonVariants } from "@/components/ui/button";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Secim } from "@/components/panel/secim";
import { IslemPenceresi } from "@/components/panel/islem-penceresi";
import { OzetIzgarasi, OzetKarti } from "@/components/panel/ozet-karti";
import { DurumEtiketi } from "@/components/panel/durum-etiketi";
import { VardiyaEtiketi } from "@/components/panel/vardiya-etiketi";
import { BosDurum } from "@/components/liste/bos-durum";
import { DurumIslem } from "@/components/liste/durum-islem";
import { IslemMenusu } from "@/components/liste/islem-menusu";
import { Sekmeler } from "@/components/liste/sekmeler";
import { TabloKutusu } from "@/components/liste/tablo-kutusu";
import { tekDeger } from "@/lib/arama";
import { sureMetni, yerelZamanGirdisi } from "@/lib/bicim";
import { aylikDokum } from "@/lib/dokum";
import { bugun } from "@/lib/hafta";
import { rolGerekli } from "@/lib/oturum";
import { ayAdi, ayKaydir } from "@/lib/puantaj";
import { sunucuIstemcisi } from "@/lib/supabase/server";
import { cn } from "@/lib/utils";
import { istenCikis, itirazGir, kartIptalEt, kartTanimla, kayitDuzelt } from "./actions";
import { DuzeltmeAlanlari, type DuzeltmeItirazi } from "./duzeltme-alanlari";
import { PdfIndir } from "./pdf-indir";

export const metadata = { title: "Çalışan" };

export default async function CalisanSayfasi({ params, searchParams }: PageProps<"/calisanlar/[id]">) {
  const kullanici = await rolGerekli(["amir", "ik", "yonetici"]);
  const [{ id }, parametre] = await Promise.all([params, searchParams]);

  const calisanId = Number.parseInt(id, 10);
  if (!calisanId) notFound();
  const istenen = tekDeger(parametre.ay);
  const ay = /^\d{4}-(0[1-9]|1[0-2])$/.test(istenen) ? istenen : bugun().slice(0, 7);

  const supabase = await sunucuIstemcisi();
  // Amir başka bölümün çalışanını açmaya çalışırsa RLS satırı döndürmez → 404
  const dokum = await aylikDokum(supabase, calisanId, ay, kullanici.rol);
  if (!dokum) notFound();

  const { calisan, gunler, duzeltmeler, ozet } = dokum;
  const bugunTarih = bugun();
  // Günler ve düzeltmeler ayrı sekmelerde (?sekme=duzeltme)
  const duzeltmeSekmesi = tekDeger(parametre.sekme) === "duzeltme";
  const adres = (a: string) => `/calisanlar/${calisanId}?ay=${a}${duzeltmeSekmesi ? "&sekme=duzeltme" : ""}`;
  // İtirazı amir ve İK girer; yönetici yalnızca okur. Kimse kendi kaydına itiraz giremez
  // (veritabanı da reddeder; düğme hiç gösterilmez).
  const itirazGirebilir = (kullanici.rol === "amir" || kullanici.rol === "ik") && kullanici.calisanId !== calisanId;
  // Kaydı yalnızca İK düzeltir; kendi kaydını düzeltemez (veritabanı da reddeder)
  const duzeltebilir = kullanici.rol === "ik" && kullanici.calisanId !== calisanId;
  const islemSutunu = itirazGirebilir || duzeltebilir;

  // Kart işlemleri yalnızca İK (asıl kartın no'su ve id'si)
  const aktifKart = duzeltebilir
    ? ((await supabase.from("kart").select("id, kart_no").eq("calisan_id", calisanId).eq("durum", "aktif").maybeSingle()).data as
        | { id: number; kart_no: string }
        | null)
    : null;

  // Düzeltme bir itiraza bağlanabilsin diye bu ayın itirazları (gün kaydına göre).
  // Reddedilmiş itiraz listelenmez: düzeltme reddedilmiş bir itiraza dayanamaz (T-34).
  const itirazByGun = new Map<number, DuzeltmeItirazi[]>();
  if (duzeltebilir) {
    const ids = dokum.gunler.map((g) => g.gunKaydiId).filter((x): x is number => x !== null);
    if (ids.length) {
      const { data } = await supabase
        .from("itiraz")
        .select("id, metin, durum, gun_kaydi_id")
        .in("gun_kaydi_id", ids)
        .in("durum", ["acik", "inceleniyor", "kabul"])
        .order("id");
      for (const i of (data ?? []) as (DuzeltmeItirazi & { gun_kaydi_id: number })[]) {
        const liste = itirazByGun.get(i.gun_kaydi_id) ?? [];
        liste.push({ id: i.id, metin: i.metin, durum: i.durum });
        itirazByGun.set(i.gun_kaydi_id, liste);
      }
    }
  }

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-col gap-2">
        <Link href="/calisanlar" className="self-start text-sm text-muted-foreground hover:text-foreground">← Çalışanlar</Link>
        <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
          <h1 className="text-2xl font-semibold">{calisan.adSoyad}</h1>
          {!calisan.aktif && <Badge variant="outline">Ayrıldı{calisan.cikis ? ` · ${calisan.cikis}` : ""}</Badge>}
          {calisan.aktif && calisan.iseGirisTarihi > bugunTarih && <Badge>Başlayacak · {calisan.iseGiris}</Badge>}
        </div>
        <p className="text-sm text-muted-foreground">
          Sicil <span className="font-mono">{calisan.sicil}</span> · {calisan.bolum} · İşe giriş {calisan.iseGiris}
          {calisan.cikis && <> · Son çalışma günü {calisan.cikis}</>}
          {calisan.kart && <> · Kart <span className="font-mono">{calisan.kart}</span></>}
        </p>
      </div>

      <div className="flex flex-wrap items-center justify-between gap-3">
        <nav aria-label="Ay" className="flex flex-wrap items-center gap-2">
          <Link href={adres(ayKaydir(ay, -1))} className={buttonVariants({ variant: "outline", size: "sm" })}>←</Link>
          <span className="min-w-28 text-center font-semibold">{ayAdi(ay)}</span>
          <Link href={adres(ayKaydir(ay, 1))} className={buttonVariants({ variant: "outline", size: "sm" })}>→</Link>
        </nav>
        <div className="flex flex-wrap gap-2">
          {duzeltebilir && calisan.aktif && !aktifKart && (
            <IslemPenceresi
              dugme="Kart tanımla"
              baslik={`${calisan.adSoyad} · yeni kart`}
              aciklama="Kartın üzerindeki numara girilmelidir. Her kart numarası yalnızca bir kez kullanılabilir."
              onay="Kartı tanımla"
              islem={kartTanimla}
              gizli={{ calisan_id: calisanId }}
            >
              <label htmlFor="kart_no" className="text-sm font-medium">Kart numarası</label>
              <Input id="kart_no" name="kart_no" required maxLength={32} autoComplete="off" className="font-mono uppercase" placeholder="ör. K1031" />
            </IslemPenceresi>
          )}
          {duzeltebilir && aktifKart && (
            <IslemPenceresi
              dugme="Kartı iptal et"
              dugmeTuru="ghost"
              baslik={`${aktifKart.kart_no} kartını iptal et`}
              aciklama="İptal edilen kart geçersiz olur ve okutulduğunda İK'ya uyarı iletilir. Yeni kart, iptal işleminden sonra tanımlanabilir."
              onay="İptal et"
              onayTuru="destructive"
              islem={kartIptalEt}
              gizli={{ kart_id: aktifKart.id }}
            >
              <label htmlFor="neden" className="text-sm font-medium">Neden</label>
              <Secim id="neden" name="neden" required defaultValue="" className="h-9">
                <option value="" disabled>Seçin</option>
                <option value="kayip">Kayıp</option>
                <option value="yenilendi">Yenilendi</option>
                <option value="isten_cikis">İşten çıkış</option>
                <option value="diger">Diğer</option>
              </Secim>
            </IslemPenceresi>
          )}
          {duzeltebilir && calisan.aktif && (
            <IslemPenceresi
              dugme="İşten çıkış"
              dugmeTuru="ghost"
              baslik={`${calisan.adSoyad} · işten çıkış`}
              aciklama="Çalışanın kartı iptal edilir, sonraki vardiya planları silinir, sonraki izinleri ve bekleyen fazla mesai talepleri iptal edilir, kullanıcı hesabı pasife alınır. Son çalışma günü ileri tarihli olamaz. Bu işlem geri alınamaz."
              onay="Çıkışı kaydet"
              onayTuru="destructive"
              islem={istenCikis}
              gizli={{ calisan_id: calisanId, ad_soyad: calisan.adSoyad }}
            >
              <label htmlFor="cikis_tarihi" className="text-sm font-medium">Son çalışma günü</label>
              <Input id="cikis_tarihi" name="cikis_tarihi" type="date" required max={bugunTarih} defaultValue={bugunTarih} />
              <label htmlFor="cikis_aciklama" className="text-sm font-medium">Açıklama (isteğe bağlı)</label>
              <Textarea id="cikis_aciklama" name="aciklama" rows={2} maxLength={500} placeholder="ör. İstifa" />
            </IslemPenceresi>
          )}
          {kullanici.rol === "ik" && <PdfIndir dokum={dokum} hazirlayan={kullanici.adSoyad} />}
        </div>
      </div>

      <OzetIzgarasi>
        <OzetKarti baslik="Planlı gün" deger={ozet.planliGun} aciklama="İzinli günler hariç" />
        <OzetKarti baslik="İzinli gün" deger={ozet.izinliGun} />
        <OzetKarti baslik="Çalışma" deger={sureMetni(ozet.calismaDk)} aciklama={`Fazla mesai ${sureMetni(ozet.fazlaMesaiDk)}`} />
        <OzetKarti baslik="Düzeltme" deger={duzeltmeler.length} aciklama="Seçili ay" />
      </OzetIzgarasi>

      {ozet.gunKaydi === 0 && (
        <Alert>
          <AlertTitle>Kayıt bulunmuyor</AlertTitle>
          <AlertDescription>Giriş ve çıkış saatleri gece işleminden sonra görüntülenir.</AlertDescription>
        </Alert>
      )}

      <Sekmeler
        etiket="Çalışan kayıtları"
        sekmeler={[
          { ad: "Günler", adres: `/calisanlar/${calisanId}?ay=${ay}`, aktif: !duzeltmeSekmesi },
          { ad: "Düzeltmeler", adres: `/calisanlar/${calisanId}?ay=${ay}&sekme=duzeltme`, sayi: duzeltmeler.length, aktif: duzeltmeSekmesi },
        ]}
      />

      {!duzeltmeSekmesi && (
      <TabloKutusu>
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Gün</TableHead>
              <TableHead>Plan</TableHead>
              <TableHead>Giriş</TableHead>
              <TableHead>Çıkış</TableHead>
              <TableHead className="text-right">Çalışma</TableHead>
              <TableHead className="w-full">Not</TableHead>
              <TableHead>Durum</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {gunler.map((g) => {
              const notlar = [
                g.tatil && `Resmi tatil: ${g.tatil}`,
                g.planNotu,
                g.fazlaMesai && `Fazla mesai ${g.fazlaMesai}`,
                g.geciciKart && `Geçici kart ${g.geciciKart}`,
                g.gecKalmaDk ? `Geç kalma ${sureMetni(g.gecKalmaDk)}` : null,
                g.erkenCikisDk ? `Erken çıkış ${sureMetni(g.erkenCikisDk)}` : null,
              ].filter(Boolean);
              return (
                <TableRow key={g.tarih} className={cn(g.haftaSonu && "bg-muted/40", g.haftaSonu && !g.vardiya && "text-muted-foreground", g.tarih === bugunTarih && "bg-primary/5")}>
                  <TableCell className="tabular-nums whitespace-nowrap">
                    <span className="inline-block w-8">{g.gunAdi}</span> {g.tarihMetni}
                  </TableCell>
                  <TableCell>
                    {g.izin ? <Badge variant="outline">{g.izin}</Badge> : g.vardiyaKod ? <VardiyaEtiketi kod={g.vardiyaKod} /> : "—"}
                  </TableCell>
                  <TableCell className="tabular-nums">
                    {g.giris ?? "—"}
                    {g.girisKaynagi && g.girisKaynagi !== "PDKS" && <span className="ml-1 text-xs text-muted-foreground">({g.girisKaynagi})</span>}
                  </TableCell>
                  <TableCell className="tabular-nums">
                    {g.cikis ?? "—"}
                    {g.cikisKaynagi && g.cikisKaynagi !== "PDKS" && <span className="ml-1 text-xs text-muted-foreground">({g.cikisKaynagi})</span>}
                  </TableCell>
                  <TableCell className="text-right tabular-nums">{g.calismaDk != null ? sureMetni(g.calismaDk) : "—"}</TableCell>
                  <TableCell className="min-w-56 whitespace-normal text-sm text-muted-foreground">{notlar.join(" · ") || ""}</TableCell>
                  <TableCell>
                    {/* Durum ve işlemler tek dar sütunda: İK için ana işlem Düzelt, İtiraz menüde; amir için İtiraz görünür */}
                    <DurumIslem yatay durum={<DurumEtiketi kod={g.durumKodu}>{g.durum}</DurumEtiketi>}>
                      {islemSutunu && g.gunKaydiId && (
                        <>
                          {duzeltebilir && (
                            <IslemPenceresi
                              dugme="Düzelt"
                              dugmeTuru="outline"
                              baslik={`${calisan.adSoyad} · ${g.tarihMetni} kaydını düzelt`}
                              aciklama={`Mevcut kayıt: giriş ${g.giris ?? "—"}, çıkış ${g.cikis ?? "—"}, ${g.durum ?? "—"}.`}
                              onay="Düzeltmeyi kaydet"
                              islem={kayitDuzelt}
                              gizli={{ gun_kaydi_id: g.gunKaydiId }}
                            >
                              <DuzeltmeAlanlari
                                girisVarsayilan={yerelZamanGirdisi(g.girisZamani ?? g.planliBaslangic)}
                                cikisVarsayilan={yerelZamanGirdisi(g.cikisZamani ?? g.planliBitis)}
                                itirazlar={itirazByGun.get(g.gunKaydiId) ?? []}
                              />
                            </IslemPenceresi>
                          )}
                          {/* İK'da İtiraz yan düğmedir, amirde tek işlemdir; görünümü IslemMenusu belirler */}
                          <IslemMenusu>
                            {itirazGirebilir && (
                              <IslemPenceresi
                                dugme="İtiraz ekle"
                                baslik={`${calisan.adSoyad} · ${g.tarihMetni} itirazı`}
                                aciklama={`Mevcut kayıt: giriş ${g.giris ?? "—"}, çıkış ${g.cikis ?? "—"}, ${g.durum ?? "—"}. İtiraz kararı İK tarafından verilir.`}
                                onay="İtirazı kaydet"
                                islem={itirazGir}
                                gizli={{ gun_kaydi_id: g.gunKaydiId }}
                              >
                                <label htmlFor="metin" className="text-sm font-medium">İtiraz</label>
                                <Textarea id="metin" name="metin" rows={3} required minLength={5} maxLength={1000} placeholder="ör. Giriş okutması kaydedilmedi" />
                              </IslemPenceresi>
                            )}
                          </IslemMenusu>
                        </>
                      )}
                    </DurumIslem>
                  </TableCell>
                </TableRow>
              );
            })}
          </TableBody>
        </Table>
      </TabloKutusu>
      )}

      {duzeltmeSekmesi && (
      <section aria-labelledby="duzeltme-baslik" className="flex flex-col gap-3">
        <div className="flex flex-col gap-1">
          <h2 id="duzeltme-baslik" className="text-lg font-semibold">Düzeltmeler</h2>
          <p className="text-sm text-muted-foreground">Okutma kaydı değiştirilmez; tüm düzeltmeler gerekçesiyle birlikte saklanır.</p>
        </div>
        {duzeltmeler.length === 0 ? (
          <BosDurum aciklama="Kayıt bulunmuyor." />
        ) : (
          <TabloKutusu>
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Gün</TableHead>
                  <TableHead>Alan</TableHead>
                  <TableHead>Eski</TableHead>
                  <TableHead>Yeni</TableHead>
                  <TableHead className="w-full">Gerekçe</TableHead>
                  <TableHead>İşlemi yapan</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {duzeltmeler.map((d, i) => (
                  <TableRow key={i}>
                    <TableCell className="tabular-nums">{d.gun}</TableCell>
                    <TableCell>{d.alan}{d.aleyhine && <Badge variant="destructive" className="ml-2">Çalışan aleyhine</Badge>}</TableCell>
                    <TableCell className="tabular-nums">{d.eski}</TableCell>
                    <TableCell className="tabular-nums">{d.yeni}</TableCell>
                    <TableCell className="min-w-56 whitespace-normal">{d.gerekce}</TableCell>
                    <TableCell className="text-muted-foreground">{d.kaynak} · {d.yapan}<div className="text-xs">{d.zaman}</div></TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </TabloKutusu>
        )}
      </section>
      )}
    </div>
  );
}
