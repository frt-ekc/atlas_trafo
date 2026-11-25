import Link from "next/link";
import { buttonVariants } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { HizliIslem } from "@/components/panel/hizli-islem";
import { Secim } from "@/components/panel/secim";
import { BosDurum } from "@/components/liste/bos-durum";
import { DurumRozeti } from "@/components/liste/durum-rozeti";
import { FiltreAlani, FiltreCubugu } from "@/components/liste/filtre-cubugu";
import { ListeKarti } from "@/components/liste/liste-karti";
import { Sekmeler } from "@/components/liste/sekmeler";
import { SecimKutusu, TopluSecim } from "@/components/liste/toplu-secim";
import { Zaman } from "@/components/liste/zaman";
import { aramaTemizle, tekDeger } from "@/lib/arama";
import { UYARI_KONULARI, UYARI_TURU } from "@/lib/etiketler";
import { rolGerekli } from "@/lib/oturum";
import { tumSatirlar } from "@/lib/supabase/sayfali";
import { sunucuIstemcisi } from "@/lib/supabase/server";
import { uyariGoruldu, uyarilarGoruldu } from "./actions";

export const metadata = { title: "Uyarılar" };

type Uyari = {
  id: number;
  tur: string;
  mesaj: string;
  olusturma_zamani: string;
  goruldu: boolean;
  gorulme_zamani: string | null;
  calisan: { id: number; sicil_no: string; ad: string; soyad: string } | null;
  okuyucu: { kod: string } | null;
  goren: { ad_soyad: string } | null;
};

// İK'nın incelemesi gereken şüpheler üstte, belirgin gösterilir; kalanı bilgi amaçlıdır.
// Gruplama yalnızca ekrandadır (uyarı türüne göre); veritabanında böyle bir alan yoktur.
// Kart paylaşımı şüphesi, kural kanıtla güçlendirilene kadar yanlış alarm ürettiği için "Bilgi" grubundadır.
const KARAR_GEREKLI = new Set(["ariza_suphesi", "gecici_kart_cakisma"]);

const TARIH = /^\d{4}-\d{2}-\d{2}$/;

// Sistem en fazla uyarı ya da şüphe üretir; çalışan aleyhine kararı İK verir.
export default async function UyarilarSayfasi({ searchParams }: PageProps<"/uyarilar">) {
  const kullanici = await rolGerekli(["ik", "yonetici", "isg", "amir"]);
  const ik = kullanici.rol === "ik";
  // Çalışan ayrıntısı sayfasını İSG uzmanı açamaz; ona ad bağlantı olarak verilmez
  const calisanSayfasi = kullanici.rol !== "isg";

  const parametre = await searchParams;
  const gorulenler = tekDeger(parametre.goster) === "goruldu";
  const tur = tekDeger(parametre.tur);
  const gecerliTur = tur in UYARI_TURU ? tur : "";
  const bas = TARIH.test(tekDeger(parametre.bas)) ? tekDeger(parametre.bas) : "";
  const bit = TARIH.test(tekDeger(parametre.bit)) ? tekDeger(parametre.bit) : "";
  const araMetni = tekDeger(parametre.ara).slice(0, 100);
  const kelimeler = aramaTemizle(araMetni).map((k) => k.toLocaleLowerCase("tr"));
  const suzgecVar = Boolean(gecerliTur || bas || bit || kelimeler.length);

  const supabase = await sunucuIstemcisi();
  const [tumUyarilar, yeniSayisi, gorulenSayisi] = await Promise.all([
    tumSatirlar<Uyari>((ilk, son) => {
      let q = supabase
        .from("uyari")
        .select(
          "id, tur, mesaj, olusturma_zamani, goruldu, gorulme_zamani, " +
            "calisan:calisan_id(id, sicil_no, ad, soyad), okuyucu:okuyucu_id(kod), goren:kullanici!goren_id(ad_soyad)",
        )
        .eq("goruldu", gorulenler)
        .order(gorulenler ? "gorulme_zamani" : "olusturma_zamani", { ascending: false })
        .order("id")
        .range(ilk, son);
      if (gecerliTur) q = q.eq("tur", gecerliTur);
      // Tarih süzgeci uyarının kayıt zamanına uygulanır (Türkiye saatiyle gün başı / sonu)
      if (bas) q = q.gte("olusturma_zamani", `${bas}T00:00:00+03:00`);
      if (bit) q = q.lt("olusturma_zamani", new Date(Date.parse(`${bit}T00:00:00+03:00`) + 86_400_000).toISOString());
      return q;
    }),
    supabase.from("uyari").select("id", { count: "exact", head: true }).eq("goruldu", false),
    supabase.from("uyari").select("id", { count: "exact", head: true }).eq("goruldu", true),
  ]);

  // Ad / sicil araması ekranda yapılır: ilgili kişinin adı, sicili, okuyucu kodu ve mesaj metni
  // (kart paylaşımında ikinci kişi yalnızca mesajda geçer).
  const uyarilar = kelimeler.length
    ? tumUyarilar.filter((u) => {
        const metin = [u.calisan?.ad, u.calisan?.soyad, u.calisan?.sicil_no, u.okuyucu?.kod, u.mesaj]
          .filter(Boolean)
          .join(" ")
          .toLocaleLowerCase("tr");
        return kelimeler.every((k) => metin.includes(k));
      })
    : tumUyarilar;

  const kararGerekli = uyarilar.filter((u) => KARAR_GEREKLI.has(u.tur));
  const bilgi = uyarilar.filter((u) => !KARAR_GEREKLI.has(u.tur));

  // Sekme ve süzgeç bağlantıları için adres
  const adres = (degisen: Record<string, string>) => {
    const p = new URLSearchParams();
    const tum = { goster: gorulenler ? "goruldu" : "", tur: gecerliTur, bas, bit, ara: araMetni, ...degisen };
    for (const [ad, deger] of Object.entries(tum)) if (deger) p.set(ad, deger);
    const sorgu = p.toString();
    return sorgu ? `/uyarilar?${sorgu}` : "/uyarilar";
  };

  // Türlere göre dağılım (açılır özet): konu başına, yalnızca uyarısı olan türler
  const turSayisi = new Map<string, number>();
  for (const u of uyarilar) turSayisi.set(u.tur, (turSayisi.get(u.tur) ?? 0) + 1);
  const konusuOlanlar = new Set(UYARI_KONULARI.flatMap((k) => k.turler));
  const ozet = [...UYARI_KONULARI, { ad: "Diğer", turler: [...turSayisi.keys()].filter((t) => !konusuOlanlar.has(t)) }]
    .map((k) => ({
      ad: k.ad,
      turler: k.turler
        .map((t) => ({ tur: t, sayi: turSayisi.get(t) ?? 0 }))
        .filter((t) => t.sayi > 0)
        .sort((a, b) => b.sayi - a.sayi),
    }))
    .filter((k) => k.turler.length > 0);

  const secilebilir = ik && !gorulenler;

  const kart = (u: Uyari) => {
    const karar = KARAR_GEREKLI.has(u.tur);
    const turAdi = UYARI_TURU[u.tur] ?? u.tur;
    const kisiAdi = u.calisan ? `${u.calisan.ad} ${u.calisan.soyad}` : u.okuyucu ? `Okuyucu ${u.okuyucu.kod}` : "";
    return (
      <ListeKarti
        key={u.id}
        vurgu={karar ? "karar" : "bilgi"}
        yeni={!u.goruldu}
        soluk={u.goruldu}
        baslik={turAdi}
        zaman={<Zaman deger={u.olusturma_zamani} etiket="Kayıt" />}
        secim={secilebilir ? <SecimKutusu id={u.id} etiket={`Seç: ${turAdi}${kisiAdi ? `, ${kisiAdi}` : ""}`} /> : undefined}
        kisi={
          u.calisan ? (
            calisanSayfasi ? (
              <Link href={`/calisanlar/${u.calisan.id}`} className="font-medium underline-offset-4 hover:underline">
                {u.calisan.ad} {u.calisan.soyad}
                <span className="ml-1.5 font-mono text-xs text-muted-foreground">{u.calisan.sicil_no}</span>
              </Link>
            ) : (
              <span className="font-medium">
                {u.calisan.ad} {u.calisan.soyad}
                <span className="ml-1.5 font-mono text-xs text-muted-foreground">{u.calisan.sicil_no}</span>
              </span>
            )
          ) : u.okuyucu ? (
            <span>
              Okuyucu <span className="font-mono font-medium">{u.okuyucu.kod}</span>
            </span>
          ) : undefined
        }
        alt={
          u.goruldu ? (
            <span className="flex flex-wrap items-center gap-2">
              <DurumRozeti ton="notr">Görüldü</DurumRozeti>
              {u.goren?.ad_soyad ?? "—"} · <Zaman deger={u.gorulme_zamani} />
            </span>
          ) : undefined
        }
        eylemler={
          <>
            {karar && u.tur === "ariza_suphesi" && calisanSayfasi && (
              <Link href="/veri-aktarimi?sekme=ariza" className={buttonVariants({ variant: "ghost", size: "sm" })}>
                Arıza kayıtlarını aç
              </Link>
            )}
            {karar && u.calisan && calisanSayfasi && (
              <Link href={`/calisanlar/${u.calisan.id}`} className={buttonVariants({ variant: "ghost", size: "sm" })}>
                Çalışan kaydını aç
              </Link>
            )}
            {ik && !u.goruldu && <HizliIslem dugme="Görüldü olarak işaretle" islem={uyariGoruldu} gizli={{ uyari_id: u.id }} />}
          </>
        }
      >
        {u.mesaj}
      </ListeKarti>
    );
  };

  const liste = (
    <div className="flex flex-col gap-6">
      {kararGerekli.length > 0 && (
        <section aria-labelledby="karar-baslik" className="flex flex-col gap-3">
          <div className="flex flex-col gap-0.5">
            <h2 id="karar-baslik" className="flex items-center gap-2 text-lg font-semibold">
              İK incelemesi bekleyenler
              <DurumRozeti ton="dikkat">{kararGerekli.length}</DurumRozeti>
            </h2>
            <p className="text-sm text-muted-foreground">
              Okuyucu arızası ve geçici kart çakışması kayıtları.
            </p>
          </div>
          {kararGerekli.map(kart)}
        </section>
      )}
      {bilgi.length > 0 && (
        <section aria-labelledby="bilgi-baslik" className="flex flex-col gap-3">
          <h2 id="bilgi-baslik" className="flex items-center gap-2 text-lg font-semibold">
            Bilgilendirme
            <DurumRozeti ton="notr">{bilgi.length}</DurumRozeti>
          </h2>
          {bilgi.map(kart)}
        </section>
      )}
    </div>
  );

  return (
    <div className="flex flex-col gap-5">
      <div className="flex flex-col gap-1">
        <h1 className="text-2xl font-semibold">Uyarılar</h1>
        <p className="text-sm text-muted-foreground">
          Sistem tarafından oluşturulan uyarılar. Çalışan aleyhine kararlar yalnızca İK tarafından verilir.
        </p>
      </div>

      <Sekmeler
        etiket="Uyarı listesi"
        sekmeler={[
          { ad: "Yeni", adres: adres({ goster: "" }), sayi: yeniSayisi.count ?? undefined, aktif: !gorulenler },
          { ad: "Görülenler", adres: adres({ goster: "goruldu" }), sayi: gorulenSayisi.count ?? undefined, aktif: gorulenler },
        ]}
      />

      <FiltreCubugu temizleAdres={gorulenler ? "/uyarilar?goster=goruldu" : "/uyarilar"} suzgecVar={suzgecVar}>
        {gorulenler && <input type="hidden" name="goster" value="goruldu" />}
        <FiltreAlani etiket="Tür" htmlFor="tur">
          <Secim id="tur" name="tur" defaultValue={gecerliTur} className="max-w-72">
            <option value="">Tüm türler</option>
            <optgroup label="İK incelemesi bekleyenler">
              {[...KARAR_GEREKLI].map((k) => <option key={k} value={k}>{UYARI_TURU[k]}</option>)}
            </optgroup>
            <optgroup label="Bilgilendirme">
              {Object.entries(UYARI_TURU)
                .filter(([k]) => !KARAR_GEREKLI.has(k))
                .map(([k, v]) => <option key={k} value={k}>{v}</option>)}
            </optgroup>
          </Secim>
        </FiltreAlani>
        <div className="flex gap-3">
          <FiltreAlani etiket="Kayıt tarihi, başlangıç" htmlFor="bas">
            <Input id="bas" name="bas" type="date" defaultValue={bas} className="w-40" />
          </FiltreAlani>
          <FiltreAlani etiket="Bitiş" htmlFor="bit">
            <Input id="bit" name="bit" type="date" defaultValue={bit} className="w-40" />
          </FiltreAlani>
        </div>
        <FiltreAlani etiket="Çalışan ara" htmlFor="ara" className="min-w-48 flex-1 sm:max-w-xs">
          <Input id="ara" name="ara" type="search" defaultValue={araMetni} placeholder="Ad, soyad veya sicil" />
        </FiltreAlani>
      </FiltreCubugu>

      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="text-sm text-muted-foreground" aria-live="polite">
          {uyarilar.length} uyarı · {kararGerekli.length} İK incelemesi bekliyor · {bilgi.length} bilgilendirme
        </p>
        {ozet.length > 1 && (
          <details className="group w-full rounded-xl border bg-card/60 open:p-3 sm:w-auto sm:open:w-full">
            <summary className="cursor-pointer list-none rounded-xl px-3 py-1.5 text-sm text-muted-foreground outline-none hover:text-foreground focus-visible:ring-2 focus-visible:ring-ring group-open:mb-2 group-open:px-0 group-open:py-0">
              Türlere göre dağılım
            </summary>
            <dl className="flex flex-col gap-2">
              {ozet.map((k) => (
                <div key={k.ad} className="flex flex-col gap-1.5 sm:flex-row sm:items-baseline sm:gap-3">
                  <dt className="w-36 shrink-0 text-sm font-medium">{k.ad}</dt>
                  <dd className="flex flex-wrap gap-1.5">
                    {k.turler.map((t) => (
                      <Link
                        key={t.tur}
                        href={adres({ tur: t.tur })}
                        scroll={false}
                        className="inline-flex items-center gap-2 rounded-lg border bg-secondary/60 px-2.5 py-1 text-[0.8125rem] outline-none transition-colors hover:border-ring/50 hover:bg-secondary focus-visible:ring-2 focus-visible:ring-ring"
                      >
                        {UYARI_TURU[t.tur] ?? t.tur}
                        <span className="font-semibold tabular-nums text-vurgu">{t.sayi}</span>
                      </Link>
                    ))}
                  </dd>
                </div>
              ))}
            </dl>
          </details>
        )}
      </div>

      {uyarilar.length === 0 ? (
        <BosDurum
          aciklama={
            suzgecVar
              ? "Seçilen filtrelere uygun kayıt bulunmuyor."
              : gorulenler
                ? "Kayıt bulunmuyor."
                : "Kayıt bulunmuyor."
          }
        />
      ) : secilebilir ? (
        <TopluSecim idler={uyarilar.map((u) => u.id)} alanAdi="uyari_id" dugme="Seçilenleri görüldü olarak işaretle" islem={uyarilarGoruldu}>
          {liste}
        </TopluSecim>
      ) : (
        liste
      )}
    </div>
  );
}
