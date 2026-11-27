import Link from "next/link";
import { TarihSecici } from "@/components/panel/tarih-secici";
import { buttonVariants } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { HizliIslem } from "@/components/panel/hizli-islem";
import { IslemPenceresi } from "@/components/panel/islem-penceresi";
import { Textarea } from "@/components/ui/textarea";
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
import { kartPaylasimKarar, uyariGoruldu, uyarilarGoruldu } from "./actions";
import { TOPLU_SINIR } from "./toplu-sinir";

export const metadata = { title: "Uyarılar" };

type TemelUyari = Omit<Uyari, "ayrinti" | "karar" | "karar_gerekce" | "karar_zamani" | "karar_veren">;
type PaylasimEki = Pick<Uyari, "id" | "ayrinti" | "karar" | "karar_gerekce" | "karar_zamani" | "karar_veren">;
const EKSIZ = { ayrinti: null, karar: null, karar_gerekce: null, karar_zamani: null, karar_veren: null } as const;

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
  // T-81: kart paylaşımı şüphesinde ayrıntı (diğer çalışan, günler) ve İK kararı
  ayrinti: { diger_calisan_id?: number; gunler?: { tarih: string; saat: string; okuyucu: string }[] } | null;
  karar: "paylasim_var" | "yanlis_alarm" | null;
  karar_gerekce: string | null;
  karar_zamani: string | null;
  karar_veren: { ad_soyad: string } | null;
};

// İK'nın incelemesi gereken şüpheler üstte, belirgin gösterilir; kalanı bilgi amaçlıdır.
// Gruplama yalnızca ekrandadır (uyarı türüne göre); veritabanında böyle bir alan yoktur.
// Kart paylaşımı şüphesi (T-81) kararı verilene kadar İK incelemesinde; karar verilince bilgi grubuna geçer.
const KARAR_GEREKLI = new Set(["ariza_suphesi", "gecici_kart_cakisma"]);
const PAYLASIM = "kart_paylasim_suphesi";
// kararDestekli: veritabanında karar sütunları ve fonksiyonu var mı (#101). Yoksa paylaşım eski hâliyle bilgi grubunda.
const incelemeBekliyor = (u: { tur: string; karar: string | null }, kararDestekli: boolean) =>
  KARAR_GEREKLI.has(u.tur) || (kararDestekli && u.tur === PAYLASIM && !u.karar);
const PAYLASIM_KARARI = { paylasim_var: "Paylaşım var", yanlis_alarm: "Yanlış alarm" } as const;

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
    tumSatirlar<TemelUyari>((ilk, son) => {
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

  // T-81: kart paylaşımı şüphesinin ayrıntısı ve kararı ayrı sorguyla okunur. Bu sütunlar #101'in
  // migration'ıyla gelir; veritabanında henüz yoksa sorgu hata verir, sayfa eskisi gibi çalışır,
  // yalnızca karar penceresi gösterilmez (kararDestekli = false).
  const paylasimIdleri = tumUyarilar.filter((u) => u.tur === PAYLASIM).map((u) => u.id);
  const ekler = new Map<number, PaylasimEki>();
  let kararDestekli = paylasimIdleri.length === 0;
  if (paylasimIdleri.length) {
    const { data, error } = await supabase
      .from("uyari")
      .select("id, ayrinti, karar, karar_gerekce, karar_zamani, karar_veren:kullanici!karar_veren_id(ad_soyad)")
      .in("id", paylasimIdleri);
    if (!error) {
      kararDestekli = true;
      for (const e of (data ?? []) as unknown as PaylasimEki[]) ekler.set(e.id, e);
    }
  }
  const zenginUyarilar: Uyari[] = tumUyarilar.map((u) => ({ ...u, ...EKSIZ, ...(ekler.get(u.id) ?? {}) }));

  // Ad / sicil araması ekranda yapılır: ilgili kişinin adı, sicili, okuyucu kodu ve mesaj metni
  // (kart paylaşımında ikinci kişi yalnızca mesajda geçer).
  const uyarilar = kelimeler.length
    ? zenginUyarilar.filter((u) => {
        const metin = [u.calisan?.ad, u.calisan?.soyad, u.calisan?.sicil_no, u.okuyucu?.kod, u.mesaj]
          .filter(Boolean)
          .join(" ")
          .toLocaleLowerCase("tr");
        return kelimeler.every((k) => metin.includes(k));
      })
    : zenginUyarilar;

  const kararGerekli = uyarilar.filter((u) => incelemeBekliyor(u, kararDestekli));
  const bilgi = uyarilar.filter((u) => !incelemeBekliyor(u, kararDestekli));

  // Kart paylaşımında şüpheli çiftin diğer çalışanı (yalnızca ayrıntıda numarası var)
  const digerIdler = [...new Set(uyarilar.map((u) => u.ayrinti?.diger_calisan_id).filter((x): x is number => typeof x === "number"))];
  const digerler = new Map<number, { id: number; sicil_no: string; ad: string; soyad: string }>();
  if (digerIdler.length) {
    const { data } = await supabase.from("calisan").select("id, sicil_no, ad, soyad").in("id", digerIdler);
    for (const c of (data ?? []) as { id: number; sicil_no: string; ad: string; soyad: string }[]) digerler.set(c.id, c);
  }

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
    const karar = incelemeBekliyor(u, kararDestekli);
    // Karar adımı yalnızca veritabanı destekliyorsa; değilse paylaşım uyarısı diğerleri gibi davranır
    const paylasim = u.tur === PAYLASIM && kararDestekli;
    const diger = u.ayrinti?.diger_calisan_id != null ? digerler.get(u.ayrinti.diger_calisan_id) : undefined;
    // Görevler ayrılığı: şüpheli çiftteki çalışanlardan biri İK'nın kendisiyse karar veremez
    const kendiKaydi =
      kullanici.calisanId != null && (u.calisan?.id === kullanici.calisanId || u.ayrinti?.diger_calisan_id === kullanici.calisanId);
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
        secim={secilebilir && !(paylasim && !u.karar) ? <SecimKutusu id={u.id} etiket={`Seç: ${turAdi}${kisiAdi ? `, ${kisiAdi}` : ""}`} /> : undefined}
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
          paylasim && u.karar ? (
            <span className="flex flex-wrap items-center gap-2">
              <DurumRozeti ton={u.karar === "paylasim_var" ? "kotu" : "notr"}>{PAYLASIM_KARARI[u.karar]}</DurumRozeti>
              {u.karar_veren?.ad_soyad ?? "İK"} · <Zaman deger={u.karar_zamani} />
              {u.karar_gerekce && <span className="w-full text-muted-foreground">Gerekçe: {u.karar_gerekce}</span>}
            </span>
          ) : u.goruldu ? (
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
            {(karar || u.tur === PAYLASIM) && u.calisan && calisanSayfasi && (
              <Link href={`/calisanlar/${u.calisan.id}`} className={buttonVariants({ variant: "ghost", size: "sm" })}>
                Çalışan kaydını aç
              </Link>
            )}
            {ik && paylasim && !u.karar && kendiKaydi && (
              <span className="text-xs text-muted-foreground">Kendi kaydınız · başka bir İK kullanıcısı karar verir</span>
            )}
            {ik && paylasim && !u.karar && !kendiKaydi && <PaylasimKararPenceresi uyari={u} diger={diger} />}
            {/* Paylaşım şüphesinde "Görüldü" yok: sonuç bekleniyormuş gibi görünmesin, karar penceresi kullanılır */}
            {ik && !paylasim && !u.goruldu && <HizliIslem dugme="Görüldü olarak işaretle" islem={uyariGoruldu} gizli={{ uyari_id: u.id }} />}
          </>
        }
      >
        {u.mesaj}
        {paylasim && !u.karar && (
          <span className="mt-1 block text-xs text-muted-foreground">
            İK paylaşımın olup olmadığına gerekçesiyle karar verir. Karar gün kayıtlarını değiştirmez; gelmediği anlaşılan
            günler çalışan kaydından elle düzeltilir.
          </span>
        )}
        {u.tur === PAYLASIM && !kararDestekli && (
          <span className="mt-1 block text-xs text-muted-foreground">
            Sistem yalnızca uyarır. Paylaşım varsa karar, İK&apos;nın çalışan kaydında günü elle düzeltmesiyle verilir;
            &ldquo;Görüldü&rdquo; yalnızca uyarının okunduğunu gösterir.
          </span>
        )}
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
              Okuyucu arızası, geçici kart çakışması ve karar bekleyen kart paylaşımı şüphesi kayıtları.
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
            <TarihSecici id="bas" name="bas" defaultValue={bas} className="w-36 sm:w-40" />
          </FiltreAlani>
          <FiltreAlani etiket="Bitiş" htmlFor="bit">
            <TarihSecici id="bit" name="bit" defaultValue={bit} className="w-36 sm:w-40" />
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
        // "Tümünü seç" yalnızca bilgi uyarılarını seçer: karar gerekli uyarı yanlışlıkla topluca kapatılmasın,
        // İK isterse onu tek tek seçer. Sunucu bir seferde en fazla TOPLU_SINIR uyarı işler.
        <TopluSecim
          idler={uyarilar.map((u) => u.id)}
          hepsiIdler={bilgi.slice(0, TOPLU_SINIR).map((u) => u.id)}
          hepsiEtiketi={bilgi.length > TOPLU_SINIR ? `İlk ${TOPLU_SINIR} bilgi uyarısını seç` : "Bilgi uyarılarının tümünü seç"}
          alanAdi="uyari_id"
          dugme="Seçilenleri görüldü olarak işaretle"
          islem={uyarilarGoruldu}
        >
          {liste}
        </TopluSecim>
      ) : (
        liste
      )}
    </div>
  );
}

// T-81: Kart paylaşımı şüphesinde İK kararı. Şüpheli günler, saat ve okuyucu pencerede gösterilir;
// karar ve gerekçe kart_paylasim_karar ile bir kez kaydedilir.
function PaylasimKararPenceresi({ uyari, diger }: { uyari: Uyari; diger?: { sicil_no: string; ad: string; soyad: string } }) {
  const gunler = uyari.ayrinti?.gunler ?? [];
  const kisi = (c?: { sicil_no: string; ad: string; soyad: string } | null) => (c ? `${c.ad} ${c.soyad} (${c.sicil_no})` : "—");
  return (
    <IslemPenceresi
      dugme="Karar ver"
      dugmeTuru="default"
      baslik="Kart paylaşımı şüphesi"
      aciklama={`${kisi(uyari.calisan)} ve ${kisi(diger)}. Kartlar aynı okuyucuda birkaç saniye arayla okutuldu.`}
      onay="Kararı kaydet"
      islem={kartPaylasimKarar}
      gizli={{ uyari_id: uyari.id }}
    >
      {gunler.length > 0 && (
        <div className="max-h-40 overflow-auto rounded-lg border">
          <table className="w-full text-left text-xs">
            <thead className="sticky top-0 bg-muted text-muted-foreground">
              <tr>
                <th className="px-2.5 py-1.5 font-medium">Gün</th>
                <th className="px-2.5 py-1.5 font-medium">Saat</th>
                <th className="px-2.5 py-1.5 font-medium">Okuyucu</th>
              </tr>
            </thead>
            <tbody>
              {gunler.map((g) => (
                <tr key={`${g.tarih}-${g.saat}`} className="border-t">
                  <td className="px-2.5 py-1 tabular-nums">{`${g.tarih.slice(8, 10)}.${g.tarih.slice(5, 7)}.${g.tarih.slice(0, 4)}`}</td>
                  <td className="px-2.5 py-1 tabular-nums">{g.saat}</td>
                  <td className="px-2.5 py-1 font-mono">{g.okuyucu}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      <fieldset className="flex flex-col gap-2">
        <legend className="mb-1 text-sm font-medium">Karar</legend>
        <label className="flex items-center gap-2 text-sm">
          <input type="radio" name="paylasim" value="yok" required /> Yanlış alarm (kartlar ayrı kişilerce okutuldu)
        </label>
        <label className="flex items-center gap-2 text-sm">
          <input type="radio" name="paylasim" value="var" required /> Paylaşım var
        </label>
      </fieldset>
      <div className="flex flex-col gap-1.5">
        <label htmlFor={`gerekce-${uyari.id}`} className="text-sm font-medium">Gerekçe</label>
        <Textarea
          id={`gerekce-${uyari.id}`}
          name="gerekce"
          rows={2}
          required
          minLength={10}
          maxLength={1000}
          placeholder="ör. Kamera kaydında ikisi de girişte görülüyor"
        />
      </div>
      <p className="text-xs text-muted-foreground">
        Karar bir kez verilir ve değiştirilemez. &ldquo;Paylaşım var&rdquo; gün kayıtlarını değiştirmez; gelmediği anlaşılan günler
        çalışan kaydından elle düzeltilir (çalışan aleyhine karar, KVKK m.11).
      </p>
    </IslemPenceresi>
  );
}
