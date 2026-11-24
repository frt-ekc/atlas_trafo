import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { GrafikKarti, ParcaliCubuk } from "@/components/panel/grafik";
import { OzetIzgarasi, OzetKarti } from "@/components/panel/ozet-karti";
import { VardiyaEtiketi } from "@/components/panel/vardiya-etiketi";
import { geciciKartIadeSaati } from "@/lib/ayar";
import { tarih, tarihSaat, uzunTarih } from "@/lib/bicim";
import { bugun } from "@/lib/hafta";
import { ROL_ADI, oturumKullanicisi } from "@/lib/oturum";
import { tumSatirlar } from "@/lib/supabase/sayfali";
import { sunucuIstemcisi } from "@/lib/supabase/server";

type Istemci = Awaited<ReturnType<typeof sunucuIstemcisi>>;
type SayimYaniti = { count: number | null; error: { message: string } | null };

// Satırları indirmeden yalnızca sayısını alır (count + head). 2000 kişide de hızlıdır.
// Hangi satırların sayılacağına yine RLS karar verir.
async function say(sorgu: PromiseLike<SayimYaniti>, ne: string): Promise<number> {
  const { count, error } = await sorgu;
  if (error) throw new Error(`${ne} sayılamadı: ${error.message}`);
  return count ?? 0;
}

const SAYIM = { count: "exact", head: true } as const;

export default async function AnaSayfa() {
  // Layout zaten kontrol etti; cache() sayesinde veritabanına tekrar gidilmez.
  const kullanici = await oturumKullanicisi();
  if (!kullanici) return null;

  const supabase = await sunucuIstemcisi();
  const bugunTarih = bugun();

  return (
    <div className="flex max-w-6xl flex-col gap-8">
      <div className="flex flex-col gap-1">
        <h1 className="text-2xl font-semibold">Hoş geldiniz, {kullanici.adSoyad}</h1>
        <p className="text-sm text-muted-foreground">
          {uzunTarih(bugunTarih)} · {ROL_ADI[kullanici.rol]}
        </p>
      </div>

      {(kullanici.rol === "ik" || kullanici.rol === "yonetici") && (
        <IkOzeti supabase={supabase} bugunTarih={bugunTarih} saltOkur={kullanici.rol === "yonetici"} />
      )}
      {kullanici.rol === "amir" && <AmirOzeti supabase={supabase} bugunTarih={bugunTarih} />}
      {kullanici.rol === "guvenlik" && <GuvenlikOzeti supabase={supabase} />}
      {kullanici.rol === "isg" && <IsgOzeti supabase={supabase} />}
      {kullanici.rol === "admin" && <AdminOzeti supabase={supabase} />}
    </div>
  );
}

// ---------------------------------------------------------------------
// İK ve yönetici: fabrika geneli. Yönetici aynı sayıları görür ama karar vermez.
// ---------------------------------------------------------------------
async function IkOzeti({ supabase, bugunTarih, saltOkur }: { supabase: Istemci; bugunTarih: string; saltOkur: boolean }) {
  const [
    ikKarariBekleyenSoru,
    acikSoru,
    acikItiraz,
    gorulmemisUyari,
    vardiyaOnayi,
    fmTalebi,
    acikZimmet,
    bugunIzinli,
    ilkBekleyenPlan,
    sonGeceIsi,
  ] = await Promise.all([
    say(supabase.from("amir_sorusu").select("id", SAYIM).eq("durum", "ik_karari_bekliyor"), "Sorular"),
    say(supabase.from("amir_sorusu").select("id", SAYIM).in("durum", ["acik", "eskale"]), "Sorular"),
    say(supabase.from("itiraz").select("id", SAYIM).in("durum", ["acik", "inceleniyor"]), "İtirazlar"),
    say(supabase.from("uyari").select("id", SAYIM).eq("goruldu", false), "Uyarılar"),
    say(supabase.from("vardiya_plani").select("id", SAYIM).eq("ik_onay_durumu", "bekliyor"), "Vardiya onayları"),
    say(supabase.from("fazla_mesai_plani").select("id", SAYIM).eq("durum", "talep"), "Fazla mesai talepleri"),
    say(supabase.from("gecici_kart_zimmet").select("id", SAYIM).is("iade_zamani", null), "Zimmetler"),
    say(
      supabase
        .from("izin")
        .select("id", SAYIM)
        .is("iptal_zamani", null) // iptal edilen izin silinmez, yalnızca işaretlenir
        .lte("baslangic", bugunTarih)
        .gte("bitis", bugunTarih),
      "İzinler",
    ),
    supabase.from("vardiya_plani").select("tarih").eq("ik_onay_durumu", "bekliyor").order("tarih").limit(1).maybeSingle(),
    supabase.from("gece_isi").select("islenen_gun, durum, bitis").order("baslangic", { ascending: false }).limit(1).maybeSingle(),
  ]);

  const geceIsi = sonGeceIsi.data as { islenen_gun: string; durum: string; bitis: string | null } | null;
  const ilkPlanTarihi = (ilkBekleyenPlan.data as { tarih: string } | null)?.tarih;
  const geceIsiYok = !geceIsi;
  const bekliyorMetni = saltOkur ? "İK kararı bekliyor" : "Karar bekliyor";

  return (
    <>
      {geceIsiYok && (
        <Alert>
          <AlertTitle>Gece işlemi henüz çalıştırılmadı</AlertTitle>
          <AlertDescription>
            Gün kayıtları, sorular ve uyarılar gece işleminden sonra görüntülenir.
          </AlertDescription>
        </Alert>
      )}

      <section aria-labelledby="bekleyen-baslik" className="flex flex-col gap-3">
        <h2 id="bekleyen-baslik" className="text-lg font-semibold">Bekleyen işlemler</h2>
        <OzetIzgarasi>
          <OzetKarti
            baslik="Geriye dönük vardiya değişikliği"
            deger={vardiyaOnayi}
            aciklama={vardiyaOnayi ? bekliyorMetni : "Bekleyen kayıt bulunmuyor"}
            href={ilkPlanTarihi ? `/vardiya-plani?hafta=${ilkPlanTarihi}` : "/vardiya-plani"}
            ton={vardiyaOnayi ? "dikkat" : "notr"}
          />
          <OzetKarti
            baslik="Fazla mesai talebi"
            deger={fmTalebi}
            aciklama={fmTalebi ? bekliyorMetni : "Bekleyen kayıt bulunmuyor"}
            href="/fazla-mesai?durum=talep"
            ton={fmTalebi ? "dikkat" : "notr"}
          />
          <OzetKarti
            baslik="İK kararı bekleyen soru"
            deger={ikKarariBekleyenSoru}
            aciklama="Karar bekliyor"
            href="/sorular?durum=ik"
            ton={ikKarariBekleyenSoru ? "dikkat" : "notr"}
          />
          <OzetKarti
            baslik="Açık itiraz"
            deger={acikItiraz}
            aciklama={acikItiraz ? "Karar bekliyor" : "Açık itiraz bulunmuyor"}
            href="/itirazlar"
            ton={acikItiraz ? "dikkat" : "notr"}
          />
        </OzetIzgarasi>
      </section>

      <section aria-labelledby="durum-baslik" className="flex flex-col gap-3">
        <h2 id="durum-baslik" className="text-lg font-semibold">Bugün</h2>
        <OzetIzgarasi>
          <OzetKarti baslik="İzinli çalışan" deger={bugunIzinli} aciklama={tarih(bugunTarih)} href={`/vardiya-plani?hafta=${bugunTarih}`} />
          <OzetKarti
            baslik="Zimmetli geçici kart"
            deger={acikZimmet}
            aciklama={acikZimmet ? "İade bekleniyor" : "Zimmetli kart bulunmuyor"}
            href="/gecici-kartlar"
          />
          <OzetKarti
            baslik="Cevap bekleyen soru"
            deger={acikSoru}
            aciklama="Amir cevabı bekleniyor"
            href="/sorular?durum=bekleyen"
          />
          <OzetKarti
            baslik="Yeni uyarı"
            deger={gorulmemisUyari}
            aciklama="Henüz görüldü olarak işaretlenmedi"
            href="/uyarilar"
            ton={gorulmemisUyari ? "dikkat" : "notr"}
          />
        </OzetIzgarasi>
        {geceIsi && (
          <p className="text-sm text-muted-foreground">
            Son gece işlemi: {tarih(geceIsi.islenen_gun)} günü ·{" "}
            {geceIsi.durum === "basarili"
              ? `başarılı (${tarihSaat(geceIsi.bitis)})`
              : geceIsi.durum === "calisiyor"
                ? "çalışıyor"
                : "işlem tamamlanamadı"}
          </p>
        )}
      </section>

      <DuzeltmeGrafigi supabase={supabase} bugunTarih={bugunTarih} />
    </>
  );
}

// Son 30 günde hatalı / eksik kayıtların kimin eliyle düzeldiği. Sistemin asıl işi bu:
// kanıt varsa kendisi düzeltir, yoksa amire sorar; çalışan aleyhine karar İK'dadır.
async function DuzeltmeGrafigi({ supabase, bugunTarih }: { supabase: Istemci; bugunTarih: string }) {
  const d = new Date(`${bugunTarih}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() - 29);
  const baslangic = d.toISOString().slice(0, 10);

  const duzeltme = (kaynak: string) =>
    say(
      supabase.from("duzeltme").select("id, gun:gun_kaydi_id!inner(is_gunu)", SAYIM).eq("kaynak", kaynak).gte("gun.is_gunu", baslangic),
      "Düzeltmeler",
    );
  const [sistem, amir, ik, bekleyen] = await Promise.all([
    duzeltme("gece_isi"),
    duzeltme("amir"),
    duzeltme("ik"),
    say(
      supabase
        .from("amir_sorusu")
        .select("id, gun:gun_kaydi_id!inner(is_gunu)", SAYIM)
        .in("durum", ["acik", "eskale", "ik_karari_bekliyor"])
        .gte("gun.is_gunu", baslangic),
      "Sorular",
    ),
  ]);
  if (sistem + amir + ik + bekleyen === 0) return null;

  const otomatikOran = Math.round((sistem / (sistem + amir + ik + bekleyen)) * 100);

  return (
    <GrafikKarti
      baslik="Kayıt düzeltme dağılımı"
      aciklama={
        <>
          Son 30 gün ({tarih(baslangic)} – {tarih(bugunTarih)}). Sistem tarafından otomatik düzeltilen kayıt oranı: <strong className="text-foreground">%{otomatikOran}</strong>
        </>
      }
    >
      <ParcaliCubuk
        birim="kayıt"
        dilimler={[
          { etiket: "Otomatik düzeltme", deger: sistem, renk: "var(--grafik-sistem)" },
          { etiket: "Amir cevabı ile düzeltme", deger: amir, renk: "var(--grafik-amir)" },
          { etiket: "İK düzeltmesi", deger: ik, renk: "var(--grafik-ik)" },
          { etiket: "Cevap bekliyor", deger: bekleyen, renk: "color-mix(in srgb, var(--grafik-bekliyor) 25%, transparent)", desenli: true, href: "/sorular?durum=tumu" },
        ]}
      />
    </GrafikKarti>
  );
}

// ---------------------------------------------------------------------
// Amir: kendi bölümleri (RLS süzer)
// ---------------------------------------------------------------------
type BugunPlan = { calisan_id: number; vardiya: { kod: string; baslangic: string } | null };

async function AmirOzeti({ supabase, bugunTarih }: { supabase: Istemci; bugunTarih: string }) {
  const [bekleyenSoru, acikItiraz, fmTalebi, planlar, izinliler] = await Promise.all([
    say(supabase.from("amir_sorusu").select("id", SAYIM).in("durum", ["acik", "eskale"]), "Sorular"),
    say(supabase.from("itiraz").select("id", SAYIM).in("durum", ["acik", "inceleniyor"]), "İtirazlar"),
    say(supabase.from("fazla_mesai_plani").select("id", SAYIM).eq("durum", "talep"), "Fazla mesai talepleri"),
    tumSatirlar<BugunPlan>((bas, son) =>
      supabase
        .from("vardiya_plani")
        .select("calisan_id, vardiya:vardiya_id(kod, baslangic)")
        .eq("tarih", bugunTarih)
        .order("id")
        .range(bas, son),
    ),
    tumSatirlar<{ calisan_id: number }>((bas, son) =>
      supabase
        .from("v_izin_amir")
        .select("calisan_id")
        .lte("baslangic", bugunTarih)
        .gte("bitis", bugunTarih)
        .order("id")
        .range(bas, son),
    ),
  ]);

  // Bugün izinli olanlar çalışan sayısından düşülür
  const izinliIdler = new Set(izinliler.map((i) => i.calisan_id));
  const vardiyaSayilari = new Map<string, { baslangic: string; sayi: number }>();
  for (const p of planlar) {
    if (!p.vardiya || izinliIdler.has(p.calisan_id)) continue;
    const s = vardiyaSayilari.get(p.vardiya.kod) ?? { baslangic: p.vardiya.baslangic, sayi: 0 };
    s.sayi += 1;
    vardiyaSayilari.set(p.vardiya.kod, s);
  }
  const vardiyalar = [...vardiyaSayilari.entries()].sort((a, b) => a[1].baslangic.localeCompare(b[1].baslangic));
  const calisacak = vardiyalar.reduce((t, [, s]) => t + s.sayi, 0);

  return (
    <>
      <section aria-labelledby="bekleyen-baslik" className="flex flex-col gap-3">
        <h2 id="bekleyen-baslik" className="text-lg font-semibold">Bekleyen işlemler</h2>
        <OzetIzgarasi>
          <OzetKarti
            baslik="Cevap bekleyen soru"
            deger={bekleyenSoru}
            aciklama={bekleyenSoru ? "Süresinde cevaplanmayan sorular üst amire iletilir" : "Bekleyen soru bulunmuyor"}
            ton={bekleyenSoru ? "dikkat" : "notr"}
            href="/sorular"
          />
          <OzetKarti
            baslik="Fazla mesai talebi"
            deger={fmTalebi}
            aciklama={fmTalebi ? "İK kararı bekliyor" : "Bekleyen talep bulunmuyor"}
            href="/fazla-mesai?durum=talep"
          />
          <OzetKarti baslik="Açık itiraz" deger={acikItiraz} aciklama="Sorumlu olunan departmanlar" href="/itirazlar" />
        </OzetIzgarasi>
      </section>

      <section aria-labelledby="ekip-baslik" className="flex flex-col gap-3">
        <h2 id="ekip-baslik" className="text-lg font-semibold">Bugünkü ekip durumu</h2>
        <OzetIzgarasi>
          <OzetKarti
            baslik="Planlı çalışan"
            deger={calisacak}
            aciklama={
              vardiyalar.length ? (
                <span className="flex flex-wrap gap-1.5 pt-1">
                  {vardiyalar.map(([kod, s]) => (
                    <span key={kod} className="inline-flex items-center gap-1">
                      <VardiyaEtiketi kod={kod} /> <span className="tabular-nums">{s.sayi}</span>
                    </span>
                  ))}
                </span>
              ) : (
                "Bugün için vardiya planı bulunmuyor"
              )
            }
            href={`/vardiya-plani?hafta=${bugunTarih}`}
          />
          <OzetKarti baslik="İzinli" deger={izinliIdler.size} aciklama={tarih(bugunTarih)} href={`/vardiya-plani?hafta=${bugunTarih}`} />
        </OzetIzgarasi>
      </section>
    </>
  );
}

// ---------------------------------------------------------------------
// Güvenlik: geçici kartlar
// ---------------------------------------------------------------------
// Şimdiki zamana bakan hesap bileşenin dışında durur (bileşenler saf olmalı).
function gecikenIadeSayisi(zimmetler: { verilis_zamani: string }[], iadeSaati: number): number {
  const simdi = Date.now();
  return zimmetler.filter((z) => simdi - new Date(z.verilis_zamani).getTime() > iadeSaati * 3600_000).length;
}

async function GuvenlikOzeti({ supabase }: { supabase: Istemci }) {
  const [kartSonucu, zimmetSonucu, iadeSaati] = await Promise.all([
    supabase.from("gecici_kart").select("id, durum"),
    supabase.from("gecici_kart_zimmet").select("gecici_kart_id, verilis_zamani").is("iade_zamani", null),
    geciciKartIadeSaati(supabase),
  ]);
  if (kartSonucu.error) throw new Error(`Geçici kartlar okunamadı: ${kartSonucu.error.message}`);
  if (zimmetSonucu.error) throw new Error(`Zimmetler okunamadı: ${zimmetSonucu.error.message}`);

  const kartlar = kartSonucu.data ?? [];
  const zimmetler = zimmetSonucu.data ?? [];
  const zimmetliIdler = new Set(zimmetler.map((z) => z.gecici_kart_id));
  const bosta = kartlar.filter((k) => k.durum === "aktif" && !zimmetliIdler.has(k.id)).length;
  const geciken = gecikenIadeSayisi(zimmetler, iadeSaati);

  return (
    <section aria-labelledby="kart-baslik" className="flex flex-col gap-3">
      <h2 id="kart-baslik" className="text-lg font-semibold">Geçici kartlar</h2>
      <OzetIzgarasi>
        <OzetKarti baslik="Kullanılabilir kart" deger={bosta} aciklama={`${kartlar.length} karttan`} href="/gecici-kartlar" ton={bosta ? "iyi" : "dikkat"} />
        <OzetKarti baslik="Zimmetli kart" deger={zimmetler.length} aciklama="İade bekleniyor" href="/gecici-kartlar" />
        <OzetKarti
          baslik="Geciken iade"
          deger={geciken}
          aciklama={`${iadeSaati} saatten uzun süredir zimmetli`}
          href="/gecici-kartlar"
          ton={geciken ? "dikkat" : "notr"}
        />
      </OzetIzgarasi>
    </section>
  );
}

// ---------------------------------------------------------------------
// İSG uzmanı: mavi yakanın belge durumu ve bölge uyarıları
// ---------------------------------------------------------------------
async function IsgOzeti({ supabase }: { supabase: Istemci }) {
  const durumSay = (durum: string) =>
    say(supabase.from("v_isg_durum").select("calisan_id", SAYIM).eq("yaka", "mavi").eq("durum", durum), "İSG belgeleri");
  const [yok, dolmus, doluyor, uyari] = await Promise.all([
    durumSay("yok"),
    durumSay("dolmus"),
    durumSay("doluyor"),
    // İSG uzmanı uyari tablosunda yalnızca İSG ve bölge uyarılarını görür (RLS)
    say(supabase.from("uyari").select("id", SAYIM).eq("goruldu", false), "Uyarılar"),
  ]);

  return (
    <section aria-labelledby="isg-baslik" className="flex flex-col gap-3">
      <h2 id="isg-baslik" className="text-lg font-semibold">İSG</h2>
      <OzetIzgarasi>
        <OzetKarti baslik="Belgesi olmayan" deger={yok} aciklama="Mavi yaka, belge türü bazında" href="/isg" ton={yok ? "dikkat" : "iyi"} />
        <OzetKarti baslik="Süresi dolmuş" deger={dolmus} href="/isg" ton={dolmus ? "dikkat" : "iyi"} />
        <OzetKarti baslik="Süresi doluyor" deger={doluyor} aciklama="Uyarı süresi içinde" href="/isg" ton={doluyor ? "dikkat" : "notr"} />
        <OzetKarti baslik="Yeni uyarı" deger={uyari} aciklama="İSG ve yetkisiz bölge" href="/uyarilar" ton={uyari ? "dikkat" : "notr"} />
      </OzetIzgarasi>
    </section>
  );
}

// ---------------------------------------------------------------------
// Sistem yöneticisi: kullanıcılar ve gece işinin durumu. Çalışan kayıtlarını görmez.
// ---------------------------------------------------------------------
async function AdminOzeti({ supabase }: { supabase: Istemci }) {
  const [aktif, hesapsiz, sonGeceIsi] = await Promise.all([
    say(supabase.from("kullanici").select("id", SAYIM).eq("aktif", true), "Kullanıcılar"),
    say(supabase.from("kullanici").select("id", SAYIM).eq("aktif", true).is("auth_kullanici_id", null), "Kullanıcılar"),
    supabase.from("gece_isi").select("islenen_gun, durum, hata_mesaji").order("id", { ascending: false }).limit(1).maybeSingle(),
  ]);
  const gece = sonGeceIsi.data as { islenen_gun: string; durum: string; hata_mesaji: string | null } | null;

  return (
    <section aria-labelledby="admin-baslik" className="flex flex-col gap-3">
      <h2 id="admin-baslik" className="text-lg font-semibold">Sistem</h2>
      <OzetIzgarasi>
        <OzetKarti baslik="Aktif kullanıcı" deger={aktif} href="/kullanicilar" />
        <OzetKarti baslik="Giriş hesabı bekleyen" deger={hesapsiz} aciklama="Giriş hesabı oluşturulmalıdır" href="/kullanicilar" ton={hesapsiz ? "dikkat" : "iyi"} />
        <OzetKarti
          baslik="Son gece işlemi"
          deger={gece ? (gece.durum === "basarili" ? "Başarılı" : gece.durum === "hatali" ? "Hatalı" : "Çalışıyor") : "—"}
          aciklama={gece ? `${tarih(gece.islenen_gun)} günü${gece.hata_mesaji ? ` · ${gece.hata_mesaji}` : ""}` : "Kayıt bulunmuyor"}
          ton={gece?.durum === "hatali" ? "dikkat" : gece ? "iyi" : "notr"}
        />
      </OzetIzgarasi>
    </section>
  );
}
