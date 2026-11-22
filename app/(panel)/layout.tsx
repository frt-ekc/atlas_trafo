import { LogOutIcon, SearchIcon } from "lucide-react";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { cikisYap } from "@/app/giris/actions";
import { Konum } from "@/components/panel/konum";
import { MenuBaglantisi } from "@/components/panel/menu-baglantisi";
import { MobilMenu } from "@/components/panel/mobil-menu";
import { TemaDugmesi } from "@/components/panel/tema-dugmesi";
import { MENU, gruplanmisMenu } from "@/lib/menu";
import { ROL_ADI, oturumKullanicisi, type OturumKullanicisi } from "@/lib/oturum";
import { sunucuIstemcisi } from "@/lib/supabase/server";
import { temaOku } from "@/lib/tema";

// Menüdeki rozetler: bekleyen iş sayıları. Her sayı RLS'e göre kullanıcının görebildiğidir
// (amir yalnızca kendi sorularını sayar). Menüde olmayan sayfanın sayısı sorulmaz.
async function bekleyenSayilar(kullanici: OturumKullanicisi): Promise<Record<string, number>> {
  const yollar = new Set(MENU[kullanici.rol].map((o) => o.yol));
  const supabase = await sunucuIstemcisi();
  const SAYIM = { count: "exact", head: true } as const;
  const sorgular: [string, PromiseLike<{ count: number | null }>][] = [];
  if (yollar.has("/uyarilar")) sorgular.push(["/uyarilar", supabase.from("uyari").select("id", SAYIM).eq("goruldu", false)]);
  if (yollar.has("/sorular")) {
    // Amir cevaplayacağı soruları, İK ve yönetici kapanmamış bütün soruları sayar
    const durumlar = kullanici.rol === "amir" ? ["acik", "eskale"] : ["acik", "eskale", "ik_karari_bekliyor"];
    sorgular.push(["/sorular", supabase.from("amir_sorusu").select("id", SAYIM).in("durum", durumlar)]);
  }
  if (yollar.has("/itirazlar")) sorgular.push(["/itirazlar", supabase.from("itiraz").select("id", SAYIM).in("durum", ["acik", "inceleniyor"])]);
  const sonuclar = await Promise.all(sorgular.map(([, s]) => s));
  return Object.fromEntries(sorgular.map(([yol], i) => [yol, sonuclar[i].count ?? 0]));
}

// (panel) klasörü bir "route group": adresi değiştirmez, yalnızca giriş
// gerektiren sayfaları bu ortak düzenin (kenar çubuğu + üst bar) altında toplar.
export default async function PanelDuzeni({ children }: LayoutProps<"/">) {
  const kullanici = await oturumKullanicisi();

  if (!kullanici) {
    return (
      <main className="flex flex-1 items-center justify-center px-4">
        <div className="flex w-full max-w-md flex-col gap-4">
          <Alert>
            <AlertTitle>Hesabınız sisteme bağlı değil</AlertTitle>
            <AlertDescription>
              Giriş yaptınız, ancak hesabınız bir PDKS kullanıcısına bağlı değil ya da pasif. İK ile görüşün.
            </AlertDescription>
          </Alert>
          <form action={cikisYap}>
            <Button type="submit" variant="outline">Çıkış yap</Button>
          </form>
        </div>
      </main>
    );
  }

  const [sayilar, tema] = await Promise.all([bekleyenSayilar(kullanici), temaOku()]);
  const aramaVar = MENU[kullanici.rol].some((o) => o.yol === "/calisanlar");

  // Masaüstünde solda sabit durur; telefonda MobilMenu içinde açılır
  const kenarCubugu = (
    <div
      className="flex h-full flex-col overflow-hidden rounded-2xl text-sidebar-foreground shadow-xl shadow-black/10"
      style={{ background: "var(--kenar-zemin)" }}
    >
      <div className="flex flex-col gap-1 px-6 pt-6 pb-5">
        {/* Atlas işareti, paletin şeftali rengine boyanır (beyaz PNG maske olarak kullanılır) */}
        <span
          role="img"
          aria-label="Atlas Trafo"
          className="block h-8 w-[127px] bg-sidebar-primary"
          style={{
            maskImage: "url(/logo/atlas_isaret_beyaz.png)",
            maskSize: "contain",
            maskRepeat: "no-repeat",
            WebkitMaskImage: "url(/logo/atlas_isaret_beyaz.png)",
            WebkitMaskSize: "contain",
            WebkitMaskRepeat: "no-repeat",
          }}
        />
        <span className="text-sm text-sidebar-foreground/70">PDKS Kayıt Düzeltme</span>
      </div>

      <nav aria-label="Ana menü" className="flex flex-1 flex-col gap-5 overflow-y-auto px-3 pb-4 [scrollbar-color:rgb(234_220_200/0.25)_transparent] [scrollbar-width:thin]">
        {gruplanmisMenu(kullanici.rol).map(({ grup, ogeler }) => (
          <div key={grup} className="flex flex-col gap-0.5">
            <div className="px-3 pb-1.5 text-[11px] font-semibold tracking-[0.12em] text-sidebar-foreground/70 uppercase">
              {grup}
            </div>
            {ogeler.map((oge) => (
              <MenuBaglantisi key={oge.yol} yol={oge.yol} baslik={oge.baslik} simge={oge.simge} sayi={sayilar[oge.yol]} />
            ))}
          </div>
        ))}
      </nav>

      <div className="flex items-center gap-3 border-t border-sidebar-border px-4 py-3">
        <div className="grid size-9 shrink-0 place-items-center rounded-full bg-sidebar-primary/15 text-sm font-semibold text-sidebar-primary">
          {kullanici.adSoyad
            .split(" ")
            .map((p) => p[0])
            .slice(0, 2)
            .join("")}
        </div>
        <div className="min-w-0 flex-1 leading-tight">
          <div className="truncate text-sm font-medium">{kullanici.adSoyad}</div>
          <div className="truncate text-xs text-sidebar-foreground/70">{ROL_ADI[kullanici.rol]}</div>
        </div>
        <form action={cikisYap}>
          <button
            type="submit"
            className="grid size-8 place-items-center rounded-full text-sidebar-foreground/70 transition-colors hover:bg-sidebar-foreground/10 hover:text-sidebar-foreground"
            aria-label="Çıkış yap"
            title="Çıkış yap"
          >
            <LogOutIcon className="size-4" />
          </button>
        </form>
      </div>
    </div>
  );

  return (
    <div className="flex min-h-svh flex-1 gap-4 p-3">
      <aside className="sticky top-3 hidden h-[calc(100svh-1.5rem)] w-64 shrink-0 md:block">{kenarCubugu}</aside>

      <div className="flex min-w-0 flex-1 flex-col gap-4">
        <header
          className="relative z-30 flex items-center gap-3 rounded-2xl border px-3 py-2 backdrop-blur-md md:px-5"
          style={{ background: "var(--ust-bar)" }}
        >
          <MobilMenu>{kenarCubugu}</MobilMenu>
          <div className="min-w-0 flex-1">
            <Konum sayfalar={MENU[kullanici.rol].map(({ yol, baslik }) => ({ yol, baslik }))} />
          </div>
          {aramaVar && (
            <form action="/calisanlar" role="search" className="relative hidden lg:block">
              <SearchIcon className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground" aria-hidden />
              <input
                type="search"
                name="ara"
                placeholder="Çalışan ara (sicil, ad)…"
                aria-label="Çalışan ara"
                className="h-9 w-64 rounded-full border bg-card/60 pr-4 pl-9 text-sm outline-none placeholder:text-muted-foreground focus-visible:ring-2 focus-visible:ring-ring"
              />
            </form>
          )}
          <TemaDugmesi tema={tema} />
        </header>

        <main className="flex-1 px-1 pb-6 md:px-3">{children}</main>
      </div>
    </div>
  );
}
