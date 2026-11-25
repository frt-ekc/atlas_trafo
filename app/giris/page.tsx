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
    <main className="relative isolate flex min-h-svh flex-1 flex-col items-center justify-center gap-6 bg-[#1f2357] px-4 py-8">
      {/* Arka plan: fabrika fotoğrafı, pencereye sabit. Bulanıklık yalnızca geniş ekranda: telefonda büyük bir
          görüntüyü bulanıklaştırmak kaydırmayı ve açılışı yavaşlatıyordu; orada koyu örtü yeterli. */}
      <div className="fixed inset-0 -z-20 md:-inset-2" aria-hidden>
        <Image
          src={fabrika}
          alt=""
          fill
          priority
          unoptimized // 185 KB'lık dosya olduğu gibi gider; büyük ekran için kopya üretmek ilk açılışı geciktiriyordu
          placeholder="blur" // fotoğraf gelene kadar küçük bulanık ön izlemesi görünür
          sizes="100vw"
          className="object-cover object-[34%_top] md:blur-[3px] lg:object-top"
        />
      </div>
      {/* Logonun lacivertiyle örtü: üstte gök mavisi ışıma, kenarlara doğru koyulaşma. Göz ortadaki karta gider. */}
      <div
        className="fixed inset-0 -z-10"
        style={{
          background:
            "radial-gradient(900px 520px at 50% -10%, rgb(106 155 252 / 0.35), transparent 70%), radial-gradient(ellipse at center, rgb(31 35 87 / 0.35) 0%, rgb(20 23 62 / 0.82) 100%), linear-gradient(rgb(44 49 120 / 0.35), rgb(44 49 120 / 0.35))",
        }}
        aria-hidden
      />

      <section className="flex w-full max-w-sm flex-col gap-6 rounded-2xl border border-white/20 bg-card/95 p-7 shadow-2xl shadow-[#0b0e28]/60 md:bg-card/85 md:backdrop-blur-xl sm:p-8">
        <div className="flex flex-col items-center gap-4 text-center">
          {/* Orijinal logo: açık temada logonun laciverti, koyu temada beyazı */}
          <AtlasIsareti className="block h-8 w-[127px] bg-[#2c3178] dark:bg-white" />
          <div className="flex flex-col gap-1.5">
            <h1 className="text-xl font-semibold">PDKS Kayıt Düzeltme</h1>
            <p className="text-sm text-muted-foreground">Kurumsal e-posta adresi ve şifre ile giriş yapılır.</p>
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
      <p className="text-xs text-white/70">Atlas Trafo · Personel Devam Kontrol Sistemi</p>
    </main>
  );
}
