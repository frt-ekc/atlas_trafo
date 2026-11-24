"use client";

import { useState } from "react";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Secim } from "@/components/panel/secim";
import { ITIRAZ_DURUMU } from "@/lib/etiketler";

// İK'nın gün kaydında değiştirebileceği alanlar ve "durum" için seçenekler.
// gun_kaydi doğrudan değişmez: kayit_duzelt → duzeltme_uygula eski / yeni değeri ve gerekçeyi saklar.
const DURUMLAR: Record<string, string> = {
  tamam: "Çalıştı",
  devamsiz: "Devamsız",
  izinli: "İzinli",
  raporlu: "Raporlu",
  tatil: "Tatil",
  vardiya_yok: "Vardiya planı yok",
};

export type DuzeltmeItirazi = { id: number; metin: string; durum: string };

export function DuzeltmeAlanlari({
  girisVarsayilan,
  cikisVarsayilan,
  itirazlar,
}: {
  girisVarsayilan: string;
  cikisVarsayilan: string;
  itirazlar: DuzeltmeItirazi[]; // o güne girilmiş, reddedilmemiş itirazlar (düzeltme bir itiraza bağlanabilir)
}) {
  const [alan, setAlan] = useState("giris_zamani");
  // Kendiliğinden yalnızca kabul edilmiş tek itiraz seçilir; kararı verilmemiş itirazı İK bilerek seçer
  const kabulEdilenler = itirazlar.filter((i) => i.durum === "kabul");
  const varsayilanItiraz = kabulEdilenler.length === 1 ? String(kabulEdilenler[0].id) : "";

  return (
    <>
      <div className="flex flex-col gap-1.5">
        <label htmlFor="alan" className="text-sm font-medium">Düzeltilecek alan</label>
        <Secim id="alan" name="alan" value={alan} onChange={(e) => setAlan(e.target.value)} className="h-9">
          <option value="giris_zamani">Giriş saati</option>
          <option value="cikis_zamani">Çıkış saati</option>
          <option value="durum">Gün durumu</option>
        </Secim>
      </div>

      <div className="flex flex-col gap-1.5">
        <label htmlFor="yeni_deger" className="text-sm font-medium">Yeni değer</label>
        {alan === "durum" ? (
          <Secim key="durum" id="yeni_deger" name="yeni_deger" required defaultValue="" className="h-9">
            <option value="" disabled>Seçin</option>
            {Object.entries(DURUMLAR).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
          </Secim>
        ) : (
          <Input
            key={alan}
            id="yeni_deger"
            name="yeni_deger"
            type="datetime-local"
            required
            defaultValue={alan === "giris_zamani" ? girisVarsayilan : cikisVarsayilan}
          />
        )}
      </div>

      {itirazlar.length > 0 && (
        <div className="flex flex-col gap-1.5">
          <label htmlFor="itiraz_id" className="text-sm font-medium">Bağlı itiraz (isteğe bağlı)</label>
          <Secim id="itiraz_id" name="itiraz_id" defaultValue={varsayilanItiraz} className="h-9">
            <option value="">Bağlı itiraz yok</option>
            {itirazlar.map((i) => (
              <option key={i.id} value={i.id}>No {i.id} · {ITIRAZ_DURUMU[i.durum]?.ad ?? i.durum}: {i.metin.slice(0, 50)}</option>
            ))}
          </Secim>
        </div>
      )}

      <div className="flex flex-col gap-1.5">
        <label htmlFor="gerekce" className="text-sm font-medium">Gerekçe</label>
        <Textarea id="gerekce" name="gerekce" rows={2} required minLength={5} maxLength={1000} placeholder="ör. İtiraz kabul edildi, servis kaydı 07:40" />
      </div>
      <p className="text-xs text-muted-foreground">
        Okutma kaydı değiştirilmez. Düzeltme; tarih, kullanıcı ve gerekçe bilgisiyle kalıcı olarak saklanır. &quot;Devamsız&quot; kararı çalışan aleyhine kaydedilir. Kilitli aya ait düzeltmeler izleyen aya fark satırı olarak aktarılır.
      </p>
    </>
  );
}
