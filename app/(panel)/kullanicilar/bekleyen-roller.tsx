import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { IslemPenceresi } from "@/components/panel/islem-penceresi";
import { KararAlanlari } from "@/components/panel/karar-alanlari";
import { BosDurum } from "@/components/liste/bos-durum";
import { DurumIslem } from "@/components/liste/durum-islem";
import { TabloKutusu } from "@/components/liste/tablo-kutusu";
import { Zaman } from "@/components/liste/zaman";
import { ROL_ADI, type Rol } from "@/lib/oturum";
import { rolOnerisiKarari } from "./actions";

export type RolOnerisi = {
  id: number;
  kullanici_id: number;
  oneren_id: number;
  eski_rol: Rol;
  yeni_rol: Rol;
  yeni_hesap: boolean;
  aktif_yap: boolean;
  oneri_zamani: string;
  kullanici: { ad_soyad: string; eposta: string } | null;
  calisan: { sicil_no: string; ad: string; soyad: string } | null;
  oneren: { ad_soyad: string } | null;
};

// İK karar verir; sistem yöneticisi yalnızca görür. Öneren ve hesabın sahibi karar veremez (veritabanı denetler).
export function BekleyenRoller({ oneriler, kararVerebilir, benId }: { oneriler: RolOnerisi[]; kararVerebilir: boolean; benId: number }) {
  return (
    <section aria-labelledby="bekleyen-roller" className="flex flex-col gap-3">
      <div className="flex flex-col gap-1">
        <h2 id="bekleyen-roller" className="text-lg font-semibold">Onay bekleyen rol değişiklikleri</h2>
        <p className="text-sm text-muted-foreground">
          İnsan Kaynakları ve sistem yöneticisi rolleri İK onayından sonra geçerli olur. Onaya kadar hesap mevcut rolüyle, yeni hesap pasif olarak kalır.
        </p>
      </div>
      {oneriler.length === 0 ? (
        <BosDurum aciklama="Kayıt bulunmuyor." />
      ) : (
        <TabloKutusu>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Çalışan</TableHead>
                <TableHead>E-posta</TableHead>
                <TableHead>Değişiklik</TableHead>
                <TableHead>Öneren</TableHead>
                <TableHead>Durum</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {oneriler.map((o) => {
                const ad = o.calisan ? `${o.calisan.ad} ${o.calisan.soyad}` : (o.kullanici?.ad_soyad ?? "—");
                const degisiklik = o.yeni_hesap
                  ? `Yeni hesap: ${ROL_ADI[o.yeni_rol]}`
                  : o.eski_rol === o.yeni_rol
                    ? `Hesabın açılması: ${ROL_ADI[o.yeni_rol]}`
                    : `${ROL_ADI[o.eski_rol]} → ${ROL_ADI[o.yeni_rol]}${o.aktif_yap ? " (hesap açılır)" : ""}`;
                return (
                  <TableRow key={o.id}>
                    <TableCell>
                      {ad}
                      {o.calisan && <span className="ml-1.5 font-mono text-xs text-muted-foreground">{o.calisan.sicil_no}</span>}
                    </TableCell>
                    <TableCell className="text-sm break-all">{o.kullanici?.eposta ?? "—"}</TableCell>
                    <TableCell className="whitespace-normal">{degisiklik}</TableCell>
                    <TableCell className="text-muted-foreground">
                      <div>{o.oneren?.ad_soyad ?? "—"}</div>
                      <div className="text-xs"><Zaman deger={o.oneri_zamani} /></div>
                    </TableCell>
                    <TableCell>
                      <DurumIslem durum={<span className="text-sm">İK onayı bekliyor</span>}>
                        {kararVerebilir && o.kullanici_id !== benId && o.oneren_id !== benId && (
                          <IslemPenceresi
                            dugme="Karar ver"
                            dugmeTuru="default"
                            baslik={`${ad} · ${degisiklik}`}
                            aciklama="Onaydan önce hesabın bağlı olduğu çalışan ve e-posta adresi doğrulanmalıdır. Onaylanan rol, kullanıcının bir sonraki girişinde geçerli olur."
                            onay="Kararı kaydet"
                            islem={rolOnerisiKarari}
                            gizli={{ oneri_id: o.id }}
                          >
                            <KararAlanlari />
                          </IslemPenceresi>
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
    </section>
  );
}
