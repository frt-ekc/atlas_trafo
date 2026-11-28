import { cn } from "@/lib/utils";

// T-96: Ay kilidinden önce bütün engeller tek seferde (pdks.ay_kilit_on_kontrol). Fonksiyon yalnızca okur.
// Engeller türüne göre üç grupta gösterilir:
//   zorla_gecilemez  → kırmızı; bu engel varken ay kilitlenemez (zorla da)
//   zorla_gecilebilir → kehribar; zorla kilitte gerekçeyle geçilebilir
//   bilgi            → gri; kilidi engellemez, kilitten sonra ne olacağını söyler
// Her engelin kişi listesi (en çok 50 satır) açılıp kapanır. Sunucuda çizilir; tarayıcıda kod çalışmaz.

export type KilitEngeli = {
  kod: string;
  tur: "zorla_gecilemez" | "zorla_gecilebilir" | "bilgi";
  sayi: number;
  mesaj: string;
  liste: Record<string, string | number | null>[];
};

export type KilitOnKontrolu = {
  donem: string;
  kilitli: boolean;
  kilitlenebilir: boolean;
  zorlamadan_kilitlenebilir: boolean;
  engeller: KilitEngeli[];
};

const GRUPLAR: { tur: KilitEngeli["tur"]; baslik: string; aciklama: string; renk: string }[] = [
  { tur: "zorla_gecilemez", baslik: "Zorla geçilemez", aciklama: "Bu engeller çözülmeden ay kilitlenemez.", renk: "border-l-kotu" },
  { tur: "zorla_gecilebilir", baslik: "Zorla geçilebilir", aciklama: "Sonuçlanmadan kilitlenirse izleyen aya fark satırı olarak aktarılır; zorla kilit gerekçe ister.", renk: "border-l-dikkat" },
  { tur: "bilgi", baslik: "Bilgi", aciklama: "Kilidi engellemez.", renk: "border-l-border" },
];

// Listede gelen itiraz / soru durumlarının ekrandaki adı
const DURUM_ADI: Record<string, string> = {
  acik: "açık",
  inceleniyor: "inceleniyor",
  eskale: "üst amire iletildi",
  ik_karari_bekliyor: "İK kararı bekliyor",
};

const gunMetni = (g: unknown) => (typeof g === "string" && /^\d{4}-\d{2}-\d{2}/.test(g) ? `${g.slice(8, 10)}.${g.slice(5, 7)}` : null);

// Listedeki bir satır: "Ad Soyad (sicil) · gg.aa · ek bilgi"
function satirMetni(o: Record<string, string | number | null>) {
  const kisi = o.ad_soyad ? `${o.ad_soyad}${o.sicil ? ` (${o.sicil})` : ""}` : o.sicil ? String(o.sicil) : null;
  const ek = [
    gunMetni(o.gun ?? o.tarih),
    typeof o.dakika === "number" ? `${o.dakika} dk` : null,
    typeof o.planli_dk === "number" ? `plan ${o.planli_dk} dk` : null,
    typeof o.durum === "string" ? (DURUM_ADI[o.durum] ?? o.durum) : null,
  ].filter(Boolean);
  return [kisi, ...ek].filter(Boolean).join(" · ");
}

export function KilitOnKontrolPaneli({ sonuc }: { sonuc: KilitOnKontrolu }) {
  const ozet = !sonuc.kilitlenebilir
    ? { metin: "Ay şu an kilitlenemez.", renk: "text-kotu" }
    : !sonuc.zorlamadan_kilitlenebilir
      ? { metin: "Ay yalnızca zorla, gerekçeyle kilitlenebilir.", renk: "text-dikkat" }
      : { metin: "Engel yok; ay kilitlenebilir.", renk: "text-iyi" };

  return (
    <section aria-labelledby="on-kontrol-baslik" className="flex flex-col gap-3">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h2 id="on-kontrol-baslik" className="text-base font-semibold">Kilit ön kontrolü</h2>
        <p className={cn("text-sm font-medium", ozet.renk)}>{ozet.metin}</p>
      </div>
      {GRUPLAR.map((g) => {
        const engeller = sonuc.engeller.filter((e) => e.tur === g.tur);
        if (!engeller.length) return null;
        return (
          <div key={g.tur} className={cn("flex flex-col gap-2 rounded-lg border border-l-4 bg-card p-3", g.renk)}>
            <div>
              <h3 className="text-sm font-semibold">{g.baslik}</h3>
              <p className="text-xs text-muted-foreground">{g.aciklama}</p>
            </div>
            <ul className="flex flex-col gap-1.5">
              {engeller.map((e) => (
                <li key={e.kod} className="text-sm">
                  {e.liste.length > 0 ? (
                    <details>
                      <summary className="cursor-pointer marker:text-muted-foreground">{e.mesaj}</summary>
                      <ul className="mt-1.5 ml-4 flex max-h-48 flex-col gap-0.5 overflow-auto text-xs text-muted-foreground">
                        {e.liste.map((o, i) => (
                          <li key={i} className="tabular-nums">{satirMetni(o)}</li>
                        ))}
                        {e.sayi > e.liste.length && <li>… ve {e.sayi - e.liste.length} kayıt daha</li>}
                      </ul>
                    </details>
                  ) : (
                    e.mesaj
                  )}
                </li>
              ))}
            </ul>
          </div>
        );
      })}
    </section>
  );
}
