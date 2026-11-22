import { Input } from "@/components/ui/input";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { CalisanListesi, type ListeCalisani } from "@/components/panel/calisan-listesi";
import { Alan, IslemPenceresi } from "@/components/panel/islem-penceresi";
import { OzetIzgarasi, OzetKarti } from "@/components/panel/ozet-karti";
import { Secim } from "@/components/panel/secim";
import { CheckIcon } from "lucide-react";
import { aramaSuzgeci } from "@/components/liste/arama";
import { BosDurum } from "@/components/liste/bos-durum";
import { DurumRozeti } from "@/components/liste/durum-rozeti";
import { FiltreAlani, FiltreCubugu } from "@/components/liste/filtre-cubugu";
import { Sekmeler } from "@/components/liste/sekmeler";
import { TabloKutusu } from "@/components/liste/tablo-kutusu";
import { Zaman } from "@/components/liste/zaman";
import { tekDeger } from "@/lib/arama";
import { tarih } from "@/lib/bicim";
import type { Ton } from "@/lib/etiketler";
import { rolGerekli } from "@/lib/oturum";
import { tumSatirlar } from "@/lib/supabase/sayfali";
import { sunucuIstemcisi } from "@/lib/supabase/server";
import { bolgeYetkisi, isgBelgeGir } from "./actions";

export const metadata = { title: "İSG" };

type Durum = "yok" | "dolmus" | "doluyor" | "gecerli";
type IsgSatiri = { calisan_id: number; sicil_no: string; departman_id: number; yaka: string; tur: string; gecerlilik_bitis: string | null; durum: Durum };
type Calisan = { id: number; ad: string; soyad: string };
type Departman = { id: number; ad: string; yaka: string };
type Bolge = { id: number; kod: string; ad: string };
type Yetki = { bolge_id: number; departman_id: number; verilis_zamani: string };
type Gecmis = { id: number; bolge_id: number; departman_id: number; islem: "verildi" | "kaldirildi"; zaman: string; yapan: { ad_soyad: string } | null };

const TUR_ADI: Record<string, string> = { isg_egitimi: "İSG eğitimi", saglik_muayenesi: "Sağlık muayenesi" };
const DURUM: Record<Durum, { ad: string; ton: Ton }> = {
  yok: { ad: "Kayıt yok", ton: "kotu" },
  dolmus: { ad: "Süresi dolmuş", ton: "kotu" },
  doluyor: { ad: "Süresi doluyor", ton: "dikkat" },
  gecerli: { ad: "Geçerli", ton: "iyi" },
};

// İSG: eğitim / sağlık muayenesi geçerliliği ve bölge giriş yetkileri. Kapı kilitlenmez; sistem yalnızca uyarır.
// İSG uzmanı yazar; İK ve yönetici okur.
export default async function IsgSayfasi({ searchParams }: PageProps<"/isg">) {
  const kullanici = await rolGerekli(["isg", "ik", "yonetici"]);
  const isg = kullanici.rol === "isg";
  const parametre = await searchParams;
  const goster = tekDeger(parametre.goster) === "tumu" ? "tumu" : "eksik";
  const bolgeSekmesi = tekDeger(parametre.sekme) === "bolge";
  const araMetni = tekDeger(parametre.ara).slice(0, 100);
  const uyar = aramaSuzgeci(araMetni);

  const supabase = await sunucuIstemcisi();
  const [durumlar, calisanlar, departmanSonucu, bolgeSonucu, yetkiSonucu, gecmisSonucu, liste] = await Promise.all([
    tumSatirlar<IsgSatiri>((bas, son) =>
      supabase.from("v_isg_durum").select("calisan_id, sicil_no, departman_id, yaka, tur, gecerlilik_bitis, durum").order("sicil_no").order("tur").range(bas, son),
    ),
    tumSatirlar<Calisan>((bas, son) => supabase.from("calisan").select("id, ad, soyad").eq("aktif", true).order("id").range(bas, son)),
    supabase.from("departman").select("id, ad, yaka").order("id"),
    supabase.from("bolge").select("id, kod, ad").eq("aktif", true).order("id"),
    supabase.from("bolge_yetkisi").select("bolge_id, departman_id, verilis_zamani"),
    supabase.from("bolge_yetkisi_gecmisi").select("id, bolge_id, departman_id, islem, zaman, yapan:kullanici!yapan_id(ad_soyad)").order("id", { ascending: false }).limit(15),
    isg
      ? tumSatirlar<ListeCalisani>((bas, son) => supabase.from("calisan").select("sicil_no, ad, soyad").eq("aktif", true).order("sicil_no").range(bas, son))
      : Promise.resolve([] as ListeCalisani[]),
  ]);

  const departmanlar = (departmanSonucu.data ?? []) as Departman[];
  const bolgeler = (bolgeSonucu.data ?? []) as Bolge[];
  const yetkiler = (yetkiSonucu.data ?? []) as Yetki[];
  const gecmis = (gecmisSonucu.data ?? []) as unknown as Gecmis[];
  const adById = new Map(calisanlar.map((c) => [c.id, `${c.ad} ${c.soyad}`]));
  const departmanAdi = new Map(departmanlar.map((d) => [d.id, d.ad]));
  const bolgeAdi = new Map(bolgeler.map((b) => [b.id, b.ad]));
  const yetkiVar = new Map(yetkiler.map((y) => [`${y.bolge_id}|${y.departman_id}`, y]));

  // Belge zorunluluğu mavi yakada (sahada çalışan); beyaz yaka da listelenir ama uyarı üretmez
  const mavi = durumlar.filter((d) => d.yaka === "mavi");
  const say = (durum: Durum) => mavi.filter((d) => d.durum === durum).length;
  const eksikler = durumlar.filter((d) => d.yaka === "mavi" && d.durum !== "gecerli");
  // Ad / sicil araması ekranda yapılır
  const gosterilen = (goster === "tumu" ? durumlar : eksikler).filter((d) => uyar(adById.get(d.calisan_id), d.sicil_no));

  return (
    <div className="flex flex-col gap-5">
      <div className="flex flex-col gap-1">
        <h1 className="text-2xl font-semibold">İSG</h1>
        <p className="text-sm text-muted-foreground">
          İSG eğitimi ve periyodik sağlık muayenesinin yalnızca geçerlilik tarihi tutulur; sonuç ya da teşhis tutulmaz. Kapı
          kilitlenmez: belgesi olmayan ya da yetkisiz bölgeye giren çalışan için uyarı üretilir.
        </p>
      </div>

      <OzetIzgarasi>
        <OzetKarti baslik="Kayıt yok" deger={say("yok")} aciklama="Mavi yaka, belge türü başına" ton={say("yok") ? "dikkat" : "iyi"} />
        <OzetKarti baslik="Süresi dolmuş" deger={say("dolmus")} ton={say("dolmus") ? "dikkat" : "iyi"} />
        <OzetKarti baslik="Süresi doluyor" deger={say("doluyor")} aciklama="Uyarı süresi içinde" ton={say("doluyor") ? "dikkat" : "notr"} />
        <OzetKarti baslik="Geçerli" deger={say("gecerli")} ton="iyi" />
      </OzetIzgarasi>

      <Sekmeler
        etiket="İSG bölümleri"
        sekmeler={[
          { ad: "Belgeler", adres: "/isg", sayi: eksikler.length || undefined, sayiAciklama: "eksik ya da dolan belge", aktif: !bolgeSekmesi },
          { ad: "Bölge yetkileri", adres: "/isg?sekme=bolge", aktif: bolgeSekmesi },
        ]}
      />

      {!bolgeSekmesi && (
        <section aria-labelledby="belge-baslik" className="flex flex-col gap-3">
          <div className="flex flex-wrap items-end justify-between gap-3">
            <div className="flex flex-col gap-1">
              <h2 id="belge-baslik" className="text-lg font-semibold">Belgeler</h2>
              <p className="text-sm text-muted-foreground">{gosterilen.length} satır</p>
            </div>
            {isg && (
              <div>
                <IslemPenceresi
                  dugme="Belge gir"
                  dugmeTuru="default"
                  baslik="İSG belgesi"
                  aciklama="Yenileme yeni kayıttır; en son girilen geçerli sayılır. Kendi belgenizi giremezsiniz."
                  onay="Kaydet"
                  islem={isgBelgeGir}
                >
                  <Alan etiket="Çalışanın sicil numarası" htmlFor="sicil" ipucu="Yazmaya başlayınca liste açılır.">
                    <Input id="sicil" name="sicil" list="isg-calisanlar" required autoComplete="off" inputMode="numeric" />
                  </Alan>
                  <Alan etiket="Tür" htmlFor="tur">
                    <Secim id="tur" name="tur" required defaultValue="" className="h-9">
                      <option value="" disabled>Seçin</option>
                      <option value="isg_egitimi">İSG eğitimi</option>
                      <option value="saglik_muayenesi">Sağlık muayenesi</option>
                    </Secim>
                  </Alan>
                  <div className="grid grid-cols-2 gap-3">
                    <Alan etiket="Geçerlilik bitişi" htmlFor="gecerlilik_bitis">
                      <Input id="gecerlilik_bitis" name="gecerlilik_bitis" type="date" required />
                    </Alan>
                    <Alan etiket="Belge no (isteğe bağlı)" htmlFor="belge_no">
                      <Input id="belge_no" name="belge_no" maxLength={50} />
                    </Alan>
                  </div>
                </IslemPenceresi>
                <CalisanListesi id="isg-calisanlar" calisanlar={liste} />
              </div>
            )}
          </div>
          <FiltreCubugu temizleAdres="/isg" suzgecVar={goster === "tumu" || Boolean(araMetni)}>
            <FiltreAlani etiket="Göster" htmlFor="goster">
              <Secim id="goster" name="goster" defaultValue={goster}>
                <option value="eksik">Eksik / dolan (mavi yaka)</option>
                <option value="tumu">Tümü</option>
              </Secim>
            </FiltreAlani>
            <FiltreAlani etiket="Çalışan ara" htmlFor="ara" className="min-w-48 flex-1 sm:max-w-xs">
              <Input id="ara" name="ara" type="search" defaultValue={araMetni} placeholder="Ad, soyad ya da sicil" />
            </FiltreAlani>
          </FiltreCubugu>
          {gosterilen.length === 0 ? (
            <BosDurum
              aciklama={
                araMetni ? "Aramaya uyan belge kaydı yok." : goster === "eksik" ? "Mavi yakada eksik ya da süresi dolan belge yok." : "Belge kaydı yok."
              }
            />
          ) : (
            <TabloKutusu>
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Çalışan</TableHead>
                    <TableHead className="w-full">Departman</TableHead>
                    <TableHead>Belge</TableHead>
                    <TableHead>Geçerlilik</TableHead>
                    <TableHead>Durum</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {gosterilen.map((d) => (
                    <TableRow key={`${d.calisan_id}-${d.tur}`}>
                      <TableCell>
                        {adById.get(d.calisan_id) ?? "—"} <span className="font-mono text-xs text-muted-foreground">{d.sicil_no}</span>
                      </TableCell>
                      <TableCell className="whitespace-normal text-sm">
                        {departmanAdi.get(d.departman_id) ?? "—"}
                        <span className="ml-1 text-xs text-muted-foreground">({d.yaka} yaka)</span>
                      </TableCell>
                      <TableCell>{TUR_ADI[d.tur] ?? d.tur}</TableCell>
                      <TableCell className="tabular-nums">{d.gecerlilik_bitis ? tarih(d.gecerlilik_bitis) : "—"}</TableCell>
                      <TableCell><DurumRozeti ton={DURUM[d.durum].ton}>{DURUM[d.durum].ad}</DurumRozeti></TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </TabloKutusu>
          )}
        </section>
      )}

      {bolgeSekmesi && (
        <section aria-labelledby="bolge-baslik" className="flex flex-col gap-3">
          <div className="flex flex-col gap-1">
            <h2 id="bolge-baslik" className="text-lg font-semibold">Bölge giriş yetkileri</h2>
            <p className="text-sm text-muted-foreground">
              Yetkisiz departmandan biri bölge kapısında okutursa İK ve İSG&apos;ye uyarı düşer. Verme ve kaldırma kim / ne zaman
              bilgisiyle saklanır. ✓ yetkili, — yetkisiz.
            </p>
          </div>
          {bolgeler.length === 0 ? (
            <BosDurum aciklama="Tanımlı bölge yok." />
          ) : (
            <TabloKutusu>
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Departman</TableHead>
                    {bolgeler.map((b) => (
                      <TableHead key={b.id} className="whitespace-normal">{b.ad}</TableHead>
                    ))}
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {departmanlar.map((d) => (
                    <TableRow key={d.id}>
                      <TableCell className="text-sm">{d.ad}</TableCell>
                      {bolgeler.map((b) => {
                        const var_ = yetkiVar.has(`${b.id}|${d.id}`);
                        return (
                          <TableCell key={b.id}>
                            <div className="flex items-center gap-2">
                              {/* Her hücrede "Yetkili" rozeti yerine işaret; anlamı ekran okuyucuya yazıyla söylenir */}
                              {var_ ? (
                                <span className="inline-flex items-center gap-1 font-medium text-iyi" title="Yetkili">
                                  <CheckIcon className="size-4" aria-hidden />
                                  <span className="sr-only">Yetkili</span>
                                </span>
                              ) : (
                                <span className="text-muted-foreground" title="Yetkisiz">
                                  <span aria-hidden>—</span>
                                  <span className="sr-only">Yetkisiz</span>
                                </span>
                              )}
                              {isg && (
                                // Güvenlik yetkisi: satırlar birbirine yakın olduğu için tek tıkla değil, onay penceresiyle
                                <IslemPenceresi
                                  dugme={var_ ? "Kaldır" : "Ver"}
                                  dugmeTuru="ghost"
                                  baslik={var_ ? "Bölge yetkisini kaldır" : "Bölge yetkisi ver"}
                                  aciklama={
                                    var_
                                      ? `${d.ad} departmanının ${b.ad} yetkisi kaldırılacak. Bu bölgede okutan çalışanları için uyarı düşer.`
                                      : `${d.ad} departmanına ${b.ad} yetkisi verilecek. Bu bölgede okutan çalışanları için uyarı düşmez.`
                                  }
                                  onay={var_ ? "Yetkiyi kaldır" : "Yetki ver"}
                                  onayTuru={var_ ? "destructive" : "default"}
                                  islem={bolgeYetkisi}
                                  gizli={{ bolge_id: b.id, departman_id: d.id, islem: var_ ? "kaldir" : "ver" }}
                                />
                              )}
                            </div>
                          </TableCell>
                        );
                      })}
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </TabloKutusu>
          )}

          {gecmis.length > 0 && (
            <div className="flex flex-col gap-2">
              <h3 className="text-sm font-semibold">Son değişiklikler</h3>
              <ul className="flex flex-col gap-1 text-sm text-muted-foreground">
                {gecmis.map((g) => (
                  <li key={g.id}>
                    <Zaman deger={g.zaman} /> · {departmanAdi.get(g.departman_id) ?? "—"} →{" "}
                    {bolgeAdi.get(g.bolge_id) ?? "—"}: {g.islem === "verildi" ? "verildi" : "kaldırıldı"} ({g.yapan?.ad_soyad ?? "sistem"})
                  </li>
                ))}
              </ul>
            </div>
          )}
        </section>
      )}
    </div>
  );
}
