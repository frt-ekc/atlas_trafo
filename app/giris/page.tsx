import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { supabaseAyarlari } from "@/lib/supabase/ayarlar";
import { GirisFormu } from "./giris-formu";

export const metadata = { title: "Giriş" };

// Atlas işareti paletin şeftali rengine boyanır (beyaz PNG maske olarak kullanılır)
function AtlasIsareti({ className }: { className?: string }) {
  return (
    <span
      role="img"
      aria-label="Atlas Trafo"
      className={className}
      style={{
        backgroundColor: "#f4d6b0",
        maskImage: "url(/logo/atlas_isaret_beyaz.png)",
        maskSize: "contain",
        maskRepeat: "no-repeat",
        WebkitMaskImage: "url(/logo/atlas_isaret_beyaz.png)",
        WebkitMaskSize: "contain",
        WebkitMaskRepeat: "no-repeat",
      }}
    />
  );
}

// Sistemin üç adımı: hocanın ve kullanıcının ilk bakışta ne olduğunu anlaması için
const ADIMLAR = [
  { baslik: "Kanıt varsa sistem düzeltir", metin: "Kapı, yemekhane ve servis kaydıyla eksik okutma kendiliğinden tamamlanır." },
  { baslik: "Kanıt yoksa amire sorar", metin: "Amir sabah sorusunu cevaplar; cevapsız soru üst amire gider." },
  { baslik: "Karar İK'dadır", metin: "Çalışan aleyhine her karar gerekçesiyle İK'da verilir ve silinmez." },
];

export default function GirisSayfasi() {
  const ayarlarHazir = supabaseAyarlari() !== null;

  return (
    <main className="flex flex-1 items-stretch gap-4 p-3">
      {/* Sol tanıtım alanı: yalnızca geniş ekranda */}
      <section
        className="hidden flex-1 flex-col justify-between overflow-hidden rounded-2xl p-10 text-[#eadcc8] lg:flex"
        style={{ background: "var(--kenar-zemin)" }}
      >
        <div className="flex flex-col gap-2">
          <AtlasIsareti className="block h-10 w-[159px]" />
          <span className="text-sm text-[#eadcc8]/60">Atlas Trafo · İzmir</span>
        </div>

        <div className="flex max-w-md flex-col gap-8">
          <div className="flex flex-col gap-3">
            <p className="text-xs font-semibold tracking-[0.14em] text-[#f4d6b0] uppercase">PDKS Kayıt Düzeltme</p>
            <h1 className="text-4xl leading-tight font-semibold text-[#f7efe3]">
              Hatalı kart kayıtları, tek bir düzende.
            </h1>
          </div>
          <ol className="flex flex-col gap-5">
            {ADIMLAR.map((a, i) => (
              <li key={a.baslik} className="flex gap-4">
                <span className="grid size-8 shrink-0 place-items-center rounded-full bg-[#f4d6b0]/15 text-sm font-semibold text-[#f4d6b0]">
                  {i + 1}
                </span>
                <div className="flex flex-col gap-0.5">
                  <span className="font-medium text-[#f7efe3]">{a.baslik}</span>
                  <span className="text-sm text-[#eadcc8]/65">{a.metin}</span>
                </div>
              </li>
            ))}
          </ol>
        </div>

        <p className="text-xs text-[#eadcc8]/45">Bilişim Sistemleri Analizi ve Tasarımı · 2026</p>
      </section>

      {/* Giriş formu */}
      <section className="flex flex-1 items-center justify-center px-4 py-10 lg:max-w-xl">
        <div className="flex w-full max-w-sm flex-col gap-8">
          {/* Dar ekranda logo formun üstünde */}
          <div className="flex flex-col items-start gap-3 lg:hidden">
            <span className="rounded-xl p-3" style={{ background: "var(--kenar-zemin)" }}>
              <AtlasIsareti className="block h-7 w-[111px]" />
            </span>
          </div>
          <div className="flex flex-col gap-1.5">
            <h2 className="text-2xl font-semibold">Giriş yap</h2>
            <p className="text-sm text-muted-foreground">Kurum e-postanız ve şifrenizle giriş yapın.</p>
          </div>
          {ayarlarHazir ? (
            <GirisFormu />
          ) : (
            <Alert>
              <AlertTitle>Supabase ayarları eksik</AlertTitle>
              <AlertDescription>
                <code>.env.example</code> dosyasını <code>.env.local</code> olarak kopyalayın, değerleri
                doldurun ve geliştirme sunucusunu yeniden başlatın.
              </AlertDescription>
            </Alert>
          )}
        </div>
      </section>
    </main>
  );
}
