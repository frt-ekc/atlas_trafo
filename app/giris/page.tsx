import Image from "next/image";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import fabrika from "@/public/gorsel/atlas_fabrika.jpg";
import { supabaseAyarlari } from "@/lib/supabase/ayarlar";
import { GirisFormu } from "./giris-formu";

export const metadata = { title: "Giriş" };

// Atlas işareti temanın vurgu rengine boyanır (beyaz PNG maske olarak kullanılır)
function AtlasIsareti({ className }: { className?: string }) {
  return (
    <span
      role="img"
      aria-label="Atlas Trafo"
      className={className}
      style={{
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

export default function GirisSayfasi() {
  const ayarlarHazir = supabaseAyarlari() !== null;

  return (
    <main className="relative isolate flex min-h-svh flex-1 items-center justify-center bg-[#0a1c20] px-4 py-6">
      {/* Arka plan: bulanık fabrika fotoğrafı, pencereye sabit (form kaysa da yerinde kalır).
          Her yandan 8 px taşar ki bulanıklık kenarlarda soluk çerçeve bırakmasın; ayrıca büyütülmez.
          Pencere fotoğraftan yayvansa alttaki asfalttan kırpılır, binanın tepesi ve tabelalar tam kalır. */}
      <div className="fixed -inset-2 -z-20" aria-hidden>
        <Image
          src={fabrika}
          alt=""
          fill
          priority
          unoptimized // 185 KB'lık dosya olduğu gibi gider; büyük ekran için kopya üretmek ilk açılışı geciktiriyordu
          placeholder="blur" // fotoğraf gelene kadar küçük bulanık ön izlemesi görünür
          className="object-cover object-[34%_top] blur-[3px] lg:object-top"
        />
      </div>
      {/* Hafif petrol tonu ve köşelere doğru koyulaşma: göz ortadaki karta gider */}
      <div
        className="fixed inset-0 -z-10"
        style={{
          background:
            "radial-gradient(ellipse at center, rgb(10 28 32 / 0.18) 0%, rgb(10 28 32 / 0.62) 100%), linear-gradient(rgb(15 61 62 / 0.2), rgb(15 61 62 / 0.2))",
        }}
        aria-hidden
      />

      <section className="flex w-full max-w-[19rem] flex-col gap-5 rounded-2xl border border-white/15 bg-card/90 p-6 shadow-2xl shadow-black/50 backdrop-blur-xl dark:bg-card/75">
        <div className="flex flex-col items-center gap-3.5 text-center">
          <AtlasIsareti className="block h-7 w-[111px] bg-vurgu" />
          <div className="flex flex-col gap-1">
            <h1 className="text-lg font-semibold">PDKS Kayıt Düzeltme</h1>
            <p className="text-[0.8125rem] text-muted-foreground">Kurumsal e-posta adresi ve şifre ile giriş yapılır.</p>
          </div>
        </div>
        {ayarlarHazir ? (
          <GirisFormu />
        ) : (
          <Alert>
            <AlertTitle>Sistem yapılandırması eksik</AlertTitle>
            <AlertDescription>
              Sistem yöneticisi ile iletişime geçilmelidir.
            </AlertDescription>
          </Alert>
        )}
      </section>
    </main>
  );
}
