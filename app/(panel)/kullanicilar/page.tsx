import { Input } from "@/components/ui/input";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { CalisanListesi, type ListeCalisani } from "@/components/panel/calisan-listesi";
import { Alan, IslemPenceresi } from "@/components/panel/islem-penceresi";
import { Secim } from "@/components/panel/secim";
import { aramaSuzgeci } from "@/components/liste/arama";
import { BosDurum } from "@/components/liste/bos-durum";
import { DurumIslem } from "@/components/liste/durum-islem";
import { DurumRozeti } from "@/components/liste/durum-rozeti";
import { FiltreAlani, FiltreCubugu } from "@/components/liste/filtre-cubugu";
import { IslemMenusu } from "@/components/liste/islem-menusu";
import { TabloKutusu } from "@/components/liste/tablo-kutusu";
import { tekDeger } from "@/lib/arama";
import { ROL_ADI, rolGerekli, type Rol } from "@/lib/oturum";
import { tumSatirlar } from "@/lib/supabase/sayfali";
import { sunucuIstemcisi } from "@/lib/supabase/server";
import { kullaniciEkle, kullaniciGuncelle } from "./actions";

export const metadata = { title: "Kullanıcılar" };

type Kullanici = {
  id: number;
  ad_soyad: string;
  eposta: string;
  rol: Rol;
  aktif: boolean;
  ust_amir_id: number | null;
  auth_kullanici_id: string | null;
  calisan: { sicil_no: string } | null;
};

// Sistem yöneticisi: kimin hangi rolle gireceğini yönetir. Çalışan kayıtları üzerinde karar veremez;
// kendi hesabını değiştiremez (görevler ayrılığı).
export default async function KullanicilarSayfasi({ searchParams }: PageProps<"/kullanicilar">) {
  const kullanici = await rolGerekli(["admin"]);
  const parametre = await searchParams;
  const rolSuzgeci = tekDeger(parametre.rol);
  const durumSuzgeci = tekDeger(parametre.durum);
  const araMetni = tekDeger(parametre.ara).slice(0, 100);
  const uyar = aramaSuzgeci(araMetni);
  const supabase = await sunucuIstemcisi();

  const [kullanicilar, calisanlar] = await Promise.all([
    tumSatirlar<Kullanici>((bas, son) =>
      supabase
        .from("kullanici")
        .select("id, ad_soyad, eposta, rol, aktif, ust_amir_id, auth_kullanici_id, calisan:calisan_id(sicil_no)")
        .order("rol")
        .order("ad_soyad")
        .range(bas, son),
    ),
    tumSatirlar<ListeCalisani>((bas, son) =>
      supabase.from("calisan").select("sicil_no, ad, soyad").eq("aktif", true).order("sicil_no").range(bas, son),
    ),
  ]);

  const adById = new Map(kullanicilar.map((k) => [k.id, k.ad_soyad]));
  const amirler = kullanicilar.filter((k) => k.aktif && (k.rol === "amir" || k.rol === "yonetici"));
  const roller = Object.entries(ROL_ADI) as [Rol, string][];
  // Rol, durum ve ad / e-posta / sicil süzgeci ekranda uygulanır
  const gosterilen = kullanicilar.filter(
    (k) =>
      (!rolSuzgeci || k.rol === rolSuzgeci) &&
      (!durumSuzgeci ||
        (durumSuzgeci === "aktif" && k.aktif) ||
        (durumSuzgeci === "pasif" && !k.aktif) ||
        (durumSuzgeci === "hesapsiz" && !k.auth_kullanici_id)) &&
      uyar(k.ad_soyad, k.eposta, k.calisan?.sicil_no),
  );
  const suzgecVar = Boolean(rolSuzgeci || durumSuzgeci || araMetni);

  return (
    <div className="flex flex-col gap-5">
      <div className="flex flex-col gap-1">
        <h1 className="text-2xl font-semibold">Kullanıcılar</h1>
        <p className="text-sm text-muted-foreground">
          Her kullanıcı bir çalışan kaydına bağlıdır. Giriş hesabı aynı e-posta adresiyle oluşturulduğunda kullanıcıya otomatik olarak bağlanır. Kullanıcılar silinmez, pasife alınır.
        </p>
      </div>

      <div className="flex flex-wrap items-center justify-between gap-3">
        <p className="text-sm text-muted-foreground">
          {kullanicilar.length} kullanıcı · {kullanicilar.filter((k) => !k.auth_kullanici_id).length} giriş hesabı bekliyor
        </p>
        <IslemPenceresi
          dugme="Kullanıcı ekle"
          dugmeTuru="default"
          baslik="Yeni kullanıcı"
          aciklama="Her çalışan ve e-posta adresi için yalnızca bir kullanıcı tanımlanabilir. Kullanıcı kendisine hesap tanımlayamaz."
          onay="Ekle"
          islem={kullaniciEkle}
        >
          <Alan
            etiket="Çalışanın sicil numarası"
            htmlFor="sicil"
            ipucu="Ad soyad bilgisi çalışan kaydından alınır."
          >
            <Input id="sicil" name="sicil" list="k-calisanlar" required autoComplete="off" inputMode="numeric" />
          </Alan>
          <Alan etiket="E-posta" htmlFor="eposta">
            <Input id="eposta" name="eposta" type="email" required maxLength={200} />
          </Alan>
          <div className="grid grid-cols-2 gap-3">
            <Alan etiket="Rol" htmlFor="rol">
              <Secim id="rol" name="rol" required defaultValue="" className="h-9">
                <option value="" disabled>Seçin</option>
                {roller.map(([k, v]) => <option key={k} value={k}>{v}</option>)}
              </Secim>
            </Alan>
            <Alan etiket="Üst amir (isteğe bağlı)" htmlFor="ust_amir_id">
              <Secim id="ust_amir_id" name="ust_amir_id" defaultValue="" className="h-9">
                <option value="">Yok</option>
                {amirler.map((a) => <option key={a.id} value={a.id}>{a.ad_soyad}</option>)}
              </Secim>
            </Alan>
          </div>
        </IslemPenceresi>
        <CalisanListesi id="k-calisanlar" calisanlar={calisanlar} />
      </div>

      <FiltreCubugu temizleAdres="/kullanicilar" suzgecVar={suzgecVar}>
        <FiltreAlani etiket="Rol" htmlFor="rol-suzgec">
          <Secim id="rol-suzgec" name="rol" defaultValue={rolSuzgeci}>
            <option value="">Tüm roller</option>
            {roller.map(([k, v]) => <option key={k} value={k}>{v}</option>)}
          </Secim>
        </FiltreAlani>
        <FiltreAlani etiket="Durum" htmlFor="durum">
          <Secim id="durum" name="durum" defaultValue={durumSuzgeci}>
            <option value="">Tümü</option>
            <option value="aktif">Aktif</option>
            <option value="pasif">Pasif</option>
            <option value="hesapsiz">Giriş hesabı bekleyenler</option>
          </Secim>
        </FiltreAlani>
        <FiltreAlani etiket="Ara" htmlFor="ara" className="min-w-48 flex-1 sm:max-w-xs">
          <Input id="ara" name="ara" type="search" defaultValue={araMetni} placeholder="Ad, e-posta veya sicil" />
        </FiltreAlani>
      </FiltreCubugu>

      {gosterilen.length === 0 ? (
        <BosDurum aciklama={suzgecVar ? "Seçilen filtrelere uygun kayıt bulunmuyor." : "Kayıt bulunmuyor."} />
      ) : (
      <TabloKutusu>
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Ad soyad</TableHead>
              <TableHead>E-posta</TableHead>
              <TableHead>Rol</TableHead>
              <TableHead>Üst amir</TableHead>
              <TableHead>Durum</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {gosterilen.map((k) => (
              <TableRow key={k.id} className={k.aktif ? undefined : "text-muted-foreground"}>
                <TableCell>
                  {k.ad_soyad}
                  {k.calisan && <span className="ml-1.5 font-mono text-xs text-muted-foreground">{k.calisan.sicil_no}</span>}
                </TableCell>
                <TableCell className="text-sm break-all">{k.eposta}</TableCell>
                <TableCell>{ROL_ADI[k.rol] ?? k.rol}</TableCell>
                <TableCell className="text-sm">{k.ust_amir_id ? (adById.get(k.ust_amir_id) ?? "—") : "—"}</TableCell>
                <TableCell>
                  <DurumIslem
                    yatay
                    durum={
                      <span className="flex items-center gap-1.5 whitespace-nowrap">
                        {k.aktif ? <span className="text-sm">Aktif</span> : <DurumRozeti ton="notr">Pasif</DurumRozeti>}
                        {!k.auth_kullanici_id && <span className="text-xs text-muted-foreground">· giriş hesabı yok</span>}
                      </span>
                    }
                  >
                    {k.id !== kullanici.id && (
                      <IslemMenusu>
                        <IslemPenceresi
                          dugme="Düzenle"
                          dugmeTuru="ghost"
                          baslik={k.ad_soyad}
                          aciklama="Rol değişikliği bir sonraki girişte geçerli olur. Pasif kullanıcılar sisteme giriş yapamaz."
                          onay="Kaydet"
                          islem={kullaniciGuncelle}
                          gizli={{ kullanici_id: k.id }}
                        >
                          <div className="grid grid-cols-2 gap-3">
                            <Alan etiket="Rol" htmlFor={`rol-${k.id}`}>
                              <Secim id={`rol-${k.id}`} name="rol" defaultValue={k.rol} className="h-9">
                                {roller.map(([r, ad]) => <option key={r} value={r}>{ad}</option>)}
                              </Secim>
                            </Alan>
                            <Alan etiket="Üst amir" htmlFor={`ust-${k.id}`} ipucu="Üst amir kaldırılamaz, değiştirilebilir.">
                              <Secim id={`ust-${k.id}`} name="ust_amir_id" defaultValue={k.ust_amir_id ?? ""} className="h-9">
                                <option value="">Değişiklik yok</option>
                                {amirler.filter((a) => a.id !== k.id).map((a) => <option key={a.id} value={a.id}>{a.ad_soyad}</option>)}
                              </Secim>
                            </Alan>
                          </div>
                          <label className="flex items-center gap-2 text-sm">
                            <input type="checkbox" name="aktif" value="evet" defaultChecked={k.aktif} />
                            Aktif
                          </label>
                        </IslemPenceresi>
                      </IslemMenusu>
                    )}
                  </DurumIslem>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </TabloKutusu>
      )}
    </div>
  );
}
