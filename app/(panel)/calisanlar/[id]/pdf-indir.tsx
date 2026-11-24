"use client";

import { sureMetni } from "@/lib/bicim";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import type { Dokum } from "@/lib/dokum";

type ReactPdf = typeof import("@react-pdf/renderer");
type Style = Parameters<ReactPdf["StyleSheet"]["create"]>[0][string];

// Çalışanın aylık kayıt dökümü (PDF). Belge tarayıcıda üretilir; sunucuya bir şey gitmez.
// @react-pdf büyük bir kütüphane; yalnızca düğmeye basılınca yüklenir.
export function PdfIndir({ dokum, hazirlayan }: { dokum: Dokum; hazirlayan: string }) {
  const [durum, setDurum] = useState<"bos" | "hazirlaniyor" | "hata">("bos");

  async function indir() {
    setDurum("hazirlaniyor");
    try {
      const rp = await import("@react-pdf/renderer");
      yaziTipiniKaydet(rp);
      const blob = await rp.pdf(<DokumBelgesi rp={rp} dokum={dokum} hazirlayan={hazirlayan} />).toBlob();
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `dokum_${dokum.calisan.sicil}_${dokum.ay}.pdf`;
      a.click();
      setTimeout(() => URL.revokeObjectURL(url), 10_000);
      setDurum("bos");
    } catch (e) {
      console.error(e);
      setDurum("hata");
    }
  }

  return (
    <div className="flex items-center gap-3">
      {durum === "hata" && <span className="text-sm text-destructive">PDF oluşturulamadı. Lütfen tekrar deneyin.</span>}
      <Button onClick={indir} disabled={durum === "hazirlaniyor"}>
        {durum === "hazirlaniyor" ? "PDF hazırlanıyor…" : "PDF indir"}
      </Button>
    </div>
  );
}

// Varsayılan PDF yazı tipinde ğ, ş, ı, İ yok. Geist (OFL lisanslı) public/fonts'tan yüklenir.
let kayitli = false;
function yaziTipiniKaydet({ Font }: ReactPdf) {
  if (kayitli) return;
  const kok = `${window.location.origin}/fonts/geist`;
  Font.register({
    family: "Geist",
    fonts: [
      { src: `${kok}/Geist-Regular.ttf`, fontWeight: 400 },
      { src: `${kok}/Geist-SemiBold.ttf`, fontWeight: 600 },
    ],
  });
  // Kelimeler İngilizce kurallarıyla bölünmesin
  Font.registerHyphenationCallback((kelime) => [kelime]);
  kayitli = true;
}

const GRI = "#6b7280";
const CIZGI = "#e5e7eb";

function DokumBelgesi({ rp, dokum, hazirlayan }: { rp: ReactPdf; dokum: Dokum; hazirlayan: string }) {
  const { Document, Page, Text, View, Image, StyleSheet } = rp;
  const s = StyleSheet.create({
    sayfa: { fontFamily: "Geist", fontSize: 8.5, padding: 32, paddingBottom: 48, color: "#111827" },
    ust: { flexDirection: "row", justifyContent: "space-between", alignItems: "center", marginBottom: 14 },
    logo: { width: 80 },
    baslik: { fontSize: 14, fontWeight: 600 },
    kucuk: { color: GRI },
    bilgi: { flexDirection: "row", flexWrap: "wrap", borderTop: `1 solid ${CIZGI}`, borderBottom: `1 solid ${CIZGI}`, paddingVertical: 8, marginBottom: 12 },
    bilgiHucre: { width: "33%", marginBottom: 4 },
    tablo: { borderTop: `1 solid ${CIZGI}` },
    satir: { flexDirection: "row", borderBottom: `1 solid ${CIZGI}`, paddingVertical: 3 },
    basSatir: { flexDirection: "row", borderBottom: `1 solid #9ca3af`, paddingVertical: 4, fontWeight: 600 },
    haftaSonu: { color: GRI },
    altBaslik: { fontSize: 11, fontWeight: 600, marginTop: 16, marginBottom: 6 },
    alt: { position: "absolute", bottom: 20, left: 32, right: 32, flexDirection: "row", justifyContent: "space-between", color: GRI, fontSize: 7.5 },
  });
  const gunSutunlari = [
    { b: "Gün", w: "13%" },
    { b: "Plan", w: "17%" },
    { b: "Giriş", w: "9%" },
    { b: "Çıkış", w: "9%" },
    { b: "Çalışma", w: "9%" },
    { b: "Durum", w: "14%" },
    { b: "Not", w: "29%" },
  ];
  const { calisan, ozet } = dokum;

  return (
    <Document title={`PDKS dökümü ${calisan.sicil} ${dokum.ay}`} author="Atlas Trafo PDKS" language="tr">
      <Page size="A4" style={s.sayfa}>
        <View style={s.ust}>
          <View>
            <Text style={s.baslik}>PDKS kayıt dökümü</Text>
            <Text style={s.kucuk}>{dokum.ayMetni}</Text>
          </View>
          {/* eslint-disable-next-line jsx-a11y/alt-text -- react-pdf Image'ında alt yok */}
          <Image style={s.logo} src={`${window.location.origin}/logo/atlas_isaret_lacivert.png`} />
        </View>

        <View style={s.bilgi}>
          <BilgiHucresi rp={rp} st={s} etiket="Ad soyad" deger={calisan.adSoyad} />
          <BilgiHucresi rp={rp} st={s} etiket="Sicil" deger={calisan.sicil} />
          <BilgiHucresi rp={rp} st={s} etiket="Departman" deger={calisan.bolum} />
          <BilgiHucresi rp={rp} st={s} etiket="İşe giriş" deger={calisan.iseGiris} />
          <BilgiHucresi rp={rp} st={s} etiket="Planlı / izinli gün" deger={`${ozet.planliGun} / ${ozet.izinliGun}`} />
          <BilgiHucresi rp={rp} st={s} etiket="Çalışma" deger={`${sureMetni(ozet.calismaDk)} · FM ${sureMetni(ozet.fazlaMesaiDk)}`} />
        </View>

        <View style={s.tablo}>
          <View style={s.basSatir} fixed>
            {gunSutunlari.map((c) => <Text key={c.b} style={{ width: c.w }}>{c.b}</Text>)}
          </View>
          {dokum.gunler.map((g) => {
            const not = [
              g.tatil && `Tatil: ${g.tatil}`,
              g.planNotu,
              g.fazlaMesai && `FM ${g.fazlaMesai}`,
              g.geciciKart && `Geçici kart ${g.geciciKart}`,
              g.gecKalmaDk ? `Geç ${sureMetni(g.gecKalmaDk)}` : null,
              g.erkenCikisDk ? `Erken ${sureMetni(g.erkenCikisDk)}` : null,
            ].filter(Boolean).join(" · ");
            return (
              <View key={g.tarih} style={[s.satir, ...(g.haftaSonu && !g.vardiya ? [s.haftaSonu] : [])]} wrap={false}>
                <Text style={{ width: "13%" }}>{g.gunAdi} {g.tarihMetni}</Text>
                <Text style={{ width: "17%" }}>{g.izin ?? g.vardiya ?? "—"}</Text>
                <Text style={{ width: "9%" }}>{g.giris ?? "—"}{g.girisKaynagi && g.girisKaynagi !== "PDKS" ? ` (${g.girisKaynagi})` : ""}</Text>
                <Text style={{ width: "9%" }}>{g.cikis ?? "—"}{g.cikisKaynagi && g.cikisKaynagi !== "PDKS" ? ` (${g.cikisKaynagi})` : ""}</Text>
                <Text style={{ width: "9%" }}>{g.calismaDk != null ? sureMetni(g.calismaDk) : "—"}</Text>
                <Text style={{ width: "14%" }}>{g.durum ?? "—"}</Text>
                <Text style={{ width: "29%" }}>{not}</Text>
              </View>
            );
          })}
        </View>

        <Text style={s.altBaslik}>Düzeltmeler</Text>
        {dokum.duzeltmeler.length === 0 ? (
          <Text style={s.kucuk}>Kayıt bulunmuyor.</Text>
        ) : (
          <View style={s.tablo}>
            <View style={s.basSatir}>
              {[["Gün", "11%"], ["Alan", "9%"], ["Eski", "14%"], ["Yeni", "14%"], ["Gerekçe", "32%"], ["İşlemi yapan", "20%"]].map(([b, w]) => (
                <Text key={b} style={{ width: w }}>{b}</Text>
              ))}
            </View>
            {dokum.duzeltmeler.map((d, i) => (
              <View key={i} style={s.satir} wrap={false}>
                <Text style={{ width: "11%" }}>{d.gun}</Text>
                <Text style={{ width: "9%" }}>{d.alan}</Text>
                <Text style={{ width: "14%" }}>{d.eski}</Text>
                <Text style={{ width: "14%" }}>{d.yeni}</Text>
                <Text style={{ width: "32%" }}>{d.gerekce}{d.aleyhine ? " (çalışan aleyhine, İK kararı)" : ""}</Text>
                <Text style={{ width: "20%" }}>{d.kaynak} · {d.yapan}{"\n"}{d.zaman}</Text>
              </View>
            ))}
          </View>
        )}

        <Text style={[s.kucuk, { marginTop: 14 }]}>
          Bu belge PDKS kayıtlarından oluşturulmuştur ve ücret bilgisi içermez. Kayıtlara ilişkin itirazlar amire veya İnsan Kaynaklarına iletilebilir.
        </Text>

        <View style={s.alt} fixed>
          <Text>Hazırlayan: {hazirlayan} · {dokum.hazirlanma}</Text>
          <Text render={({ pageNumber, totalPages }) => `${pageNumber} / ${totalPages}`} />
        </View>
      </Page>
    </Document>
  );
}

function BilgiHucresi({
  rp,
  st,
  etiket,
  deger,
}: {
  rp: ReactPdf;
  st: { bilgiHucre: Style; kucuk: Style };
  etiket: string;
  deger: string;
}) {
  const { View, Text } = rp;
  return (
    <View style={st.bilgiHucre}>
      <Text style={st.kucuk}>{etiket}</Text>
      <Text style={{ fontWeight: 600 }}>{deger}</Text>
    </View>
  );
}
