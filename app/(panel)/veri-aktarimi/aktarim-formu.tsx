"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { OzetIzgarasi, OzetKarti } from "@/components/panel/ozet-karti";
import { Secim } from "@/components/panel/secim";
import { KAYNAK_ADI, dosyaOzeti, dosyayiDenetle, type DenetimSonucu, type Kaynak, type Okuyucu } from "@/lib/aktarim/denetim";
import { tarih, tarihSaat } from "@/lib/bicim";
import { tarayiciIstemcisi } from "@/lib/supabase/client";
import { hataMesaji } from "@/lib/supabase/hata";

const EN_BUYUK_DOSYA = 20 * 1024 * 1024; // 20 MB
const ONIZLEME_SATIRI = 10;

type Durum =
  | { tur: "bos" }
  | { tur: "okunuyor" }
  | { tur: "hata"; mesaj: string }
  | { tur: "hazir"; dosyaAdi: string; sonuc: DenetimSonucu; ozet: string; onceki: { aktarim_zamani: string } | null };

// Yükleme sonucu: yazılan okutma sayısı aktarım satırından, ay kilidi dönem tablosundan okunur
type AktarimYaniti = { aktarim_id: number; eklenen: number; zaten_vardi: number; donem_kilitli: boolean };

type Yukleme =
  | { tur: "bekliyor" }
  | { tur: "yukleniyor" }
  | { tur: "hata"; mesaj: string }
  | { tur: "tamam"; yanit: AktarimYaniti };

// Dosya adı "pdks_20261126.csv" gibiyse türü adından tahmin eder
function kaynakTahmini(dosyaAdi: string): Kaynak | null {
  const on = dosyaAdi.toLowerCase().split(/[_\-.\s]/)[0];
  return (["pdks", "kapi", "yemekhane", "servis"] as const).find((k) => k === on) ?? null;
}

// Türkçe Excel CSV'yi çoğu zaman Windows-1254 ile kaydeder; UTF-8 okunamazsa ona düşülür.
function metneCevir(icerik: ArrayBuffer): string {
  const utf8 = new TextDecoder("utf-8").decode(icerik);
  return utf8.includes("�") ? new TextDecoder("windows-1254").decode(icerik) : utf8;
}

export function AktarimFormu({ okuyucular }: { okuyucular: Okuyucu[] }) {
  const [kaynak, setKaynak] = useState<Kaynak>("pdks");
  const [dosya, setDosya] = useState<File | null>(null);
  const [durum, setDurum] = useState<Durum>({ tur: "bos" });
  const [yukleme, setYukleme] = useState<Yukleme>({ tur: "bekliyor" });
  const router = useRouter();

  async function denetle(secilen: File, secilenKaynak: Kaynak) {
    setYukleme({ tur: "bekliyor" });
    if (secilen.size > EN_BUYUK_DOSYA) {
      setDurum({ tur: "hata", mesaj: "Dosya 20 MB'tan büyük. Günlük dosyalar bundan küçük olmalı." });
      return;
    }
    setDurum({ tur: "okunuyor" });
    try {
      const icerik = await secilen.arrayBuffer();
      const [ozet, sonuc] = await Promise.all([
        dosyaOzeti(icerik),
        Promise.resolve(dosyayiDenetle(metneCevir(icerik), secilen.name, secilenKaynak, okuyucular)),
      ]);
      // Aynı dosya daha önce yüklendiyse veritabanı reddeder; kullanıcıya baştan söylenir.
      const { data, error } = await tarayiciIstemcisi()
        .from("aktarim")
        .select("aktarim_zamani")
        .eq("kaynak", secilenKaynak)
        .eq("dosya_ozeti", ozet)
        .maybeSingle();
      if (error) {
        setDurum({ tur: "hata", mesaj: hataMesaji(error) });
        return;
      }
      setDurum({ tur: "hazir", dosyaAdi: secilen.name, sonuc, ozet, onceki: data });
    } catch {
      // Tarayıcının hatası İngilizce ve teknik gelir; kullanıcıya ne yapacağı söylenir
      setDurum({ tur: "hata", mesaj: "Dosya okunamadı. Dosya başka bir programda açıksa kapatın ve yeniden seçin." });
    }
  }

  // Denetlenen satırları veritabanına yazar. Veritabanı denetimi baştan yapar ve
  // her şeyi tek işlemde yazar: hata olursa hiçbir satır yazılmaz.
  async function yukle(hazir: Extract<Durum, { tur: "hazir" }>) {
    if (!hazir.sonuc.veriTarihi) return;
    setYukleme({ tur: "yukleniyor" });
    const supabase = tarayiciIstemcisi();
    const { data: aktarimId, error } = await supabase.rpc("dosya_yukle", {
      p_kaynak: kaynak,
      p_dosya_adi: hazir.dosyaAdi,
      p_veri_tarihi: hazir.sonuc.veriTarihi,
      p_satirlar: hazir.sonuc.satirlar.map((s) => ({
        okuyucu: s.okuyucuKod,
        kart_no: s.kartNo,
        zaman: s.zaman,
        yon: s.yon,
        satir_no: s.satirNo,
      })),
      p_dosya_ozeti: hazir.ozet,
    });
    if (error) {
      setYukleme({ tur: "hata", mesaj: hataMesaji(error) });
      return;
    }

    // Yükleme tamamlandı; aşağıdaki iki okuma yalnızca sonucu anlatmak için
    const [yil, ay] = hazir.sonuc.veriTarihi.split("-").map(Number);
    const [aktarim, donem] = await Promise.all([
      supabase.from("aktarim").select("satir_sayisi").eq("id", aktarimId).maybeSingle(),
      supabase.from("donem").select("durum").eq("yil", yil).eq("ay", ay).maybeSingle(),
    ]);
    const eklenen = aktarim.data?.satir_sayisi ?? hazir.sonuc.satirlar.length;
    setYukleme({
      tur: "tamam",
      yanit: {
        aktarim_id: aktarimId as number,
        eklenen,
        zaten_vardi: Math.max(hazir.sonuc.satirlar.length - eklenen, 0),
        donem_kilitli: donem.data?.durum === "kilitli",
      },
    });
    router.refresh(); // "Son aktarımlar" ve "Gelmeyen dosyalar" yenilensin
  }

  function dosyaSecildi(secilen: File | null) {
    setDosya(secilen);
    if (!secilen) {
      setYukleme({ tur: "bekliyor" });
      return setDurum({ tur: "bos" });
    }
    const tahmin = kaynakTahmini(secilen.name);
    const k = tahmin ?? kaynak;
    if (tahmin) setKaynak(tahmin);
    void denetle(secilen, k);
  }

  function kaynakDegisti(k: Kaynak) {
    setKaynak(k);
    if (dosya) void denetle(dosya, k);
  }

  return (
    <div className="flex flex-col gap-5">
      <div className="flex flex-wrap items-end gap-3">
        <div className="flex flex-col gap-1.5">
          <label htmlFor="kaynak" className="text-sm font-medium">Dosya türü</label>
          <Secim id="kaynak" value={kaynak} onChange={(e) => kaynakDegisti(e.target.value as Kaynak)}>
            {(Object.keys(KAYNAK_ADI) as Kaynak[]).map((k) => (
              <option key={k} value={k}>{KAYNAK_ADI[k]}</option>
            ))}
          </Secim>
        </div>
        <div className="flex min-w-64 flex-1 flex-col gap-1.5 sm:max-w-md">
          <label htmlFor="dosya" className="text-sm font-medium">CSV dosyası</label>
          <Input
            id="dosya"
            type="file"
            accept=".csv,text/csv"
            onChange={(e) => dosyaSecildi(e.target.files?.[0] ?? null)}
          />
        </div>
      </div>

      {durum.tur === "okunuyor" && <p className="text-sm text-muted-foreground" aria-live="polite">Dosya denetleniyor…</p>}

      {durum.tur === "hata" && (
        <Alert variant="destructive">
          <AlertDescription>{durum.mesaj}</AlertDescription>
        </Alert>
      )}

      {durum.tur === "hazir" && <Sonuc durum={durum} kaynak={kaynak} yukleme={yukleme} onYukle={() => void yukle(durum)} />}
    </div>
  );
}

function Sonuc({
  durum,
  kaynak,
  yukleme,
  onYukle,
}: {
  durum: Extract<Durum, { tur: "hazir" }>;
  kaynak: Kaynak;
  yukleme: Yukleme;
  onYukle: () => void;
}) {
  const { sonuc, onceki } = durum;
  const yuklenebilir = sonuc.hatalar.length === 0 && !onceki && sonuc.satirlar.length > 0;

  if (yukleme.tur === "tamam") {
    const { eklenen, zaten_vardi, donem_kilitli } = yukleme.yanit;
    return (
      <div className="flex flex-col gap-3" aria-live="polite">
        <Alert>
          <AlertTitle>Dosya aktarıldı</AlertTitle>
          <AlertDescription>
            {durum.dosyaAdi}: {eklenen.toLocaleString("tr-TR")} okutma kaydedildi
            {zaten_vardi > 0 && `, daha önce başka dosyayla gelmiş ${zaten_vardi.toLocaleString("tr-TR")} okutma atlandı`}. Kayıtlar
            gece işinde işlenecek.
          </AlertDescription>
        </Alert>
        {donem_kilitli && (
          <Alert variant="destructive">
            <AlertTitle>Bu dosyanın ayı kilitli</AlertTitle>
            <AlertDescription>
              Ham kayıtlar alındı. Bu kayıtlardan çıkan düzeltmeler kilitli aya yazılmaz, sonraki aya fark satırı olarak geçer.
            </AlertDescription>
          </Alert>
        )}
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-5" aria-live="polite">
      <OzetIzgarasi>
        <OzetKarti baslik="Dosyadaki satır" deger={sonuc.toplamSatir} aciklama={durum.dosyaAdi} />
        <OzetKarti baslik="Yüklenecek satır" deger={sonuc.satirlar.length} aciklama={KAYNAK_ADI[kaynak]} ton={sonuc.satirlar.length ? "iyi" : "notr"} />
        <OzetKarti
          baslik="Hata"
          deger={sonuc.hatalar.length}
          aciklama={sonuc.hatalar.length ? "Düzeltilmeden yüklenemez" : "Hata yok"}
          ton={sonuc.hatalar.length ? "dikkat" : "iyi"}
        />
        <OzetKarti baslik="Verinin günü" deger={sonuc.veriTarihi ? tarih(sonuc.veriTarihi) : "—"} aciklama="Dosya adından ya da satırlardan" />
      </OzetIzgarasi>

      {onceki && (
        <Alert variant="destructive">
          <AlertTitle>Bu dosya daha önce yüklenmiş</AlertTitle>
          <AlertDescription>
            Aynı içerikteki {KAYNAK_ADI[kaynak]} dosyası {tarihSaat(onceki.aktarim_zamani)} tarihinde aktarılmış. Aynı dosya ikinci
            kez yüklenemez.
          </AlertDescription>
        </Alert>
      )}

      {sonuc.uyarilar.length > 0 && (
        <Alert>
          <AlertTitle>Uyarılar</AlertTitle>
          <AlertDescription>
            <ul className="list-disc pl-5">
              {sonuc.uyarilar.map((u, i) => <li key={i}>{u.mesaj}</li>)}
            </ul>
          </AlertDescription>
        </Alert>
      )}

      {sonuc.hatalar.length > 0 && (
        <section aria-labelledby="hata-baslik" className="flex flex-col gap-2">
          <h3 id="hata-baslik" className="font-semibold">Hatalar</h3>
          <div className="max-h-80 overflow-auto rounded-lg border">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead className="w-20">Satır</TableHead>
                  <TableHead>Sorun</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {sonuc.hatalar.map((h, i) => (
                  <TableRow key={i}>
                    <TableCell className="tabular-nums">{h.satirNo ?? "—"}</TableCell>
                    <TableCell className="whitespace-normal">{h.mesaj}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
          {sonuc.hatalar.length >= 200 && <p className="text-sm text-muted-foreground">İlk 200 hata gösteriliyor.</p>}
        </section>
      )}

      {sonuc.satirlar.length > 0 && (
        <section aria-labelledby="onizleme-baslik" className="flex flex-col gap-2">
          <h3 id="onizleme-baslik" className="font-semibold">Önizleme (ilk {Math.min(ONIZLEME_SATIRI, sonuc.satirlar.length)} satır)</h3>
          <div className="rounded-lg border">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead className="w-20">Satır</TableHead>
                  <TableHead>Okuyucu</TableHead>
                  <TableHead>Kart</TableHead>
                  <TableHead>Zaman</TableHead>
                  <TableHead>Yön</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {sonuc.satirlar.slice(0, ONIZLEME_SATIRI).map((s) => (
                  <TableRow key={s.satirNo}>
                    <TableCell className="tabular-nums">{s.satirNo}</TableCell>
                    <TableCell className="font-mono">{s.okuyucuKod}</TableCell>
                    <TableCell className="font-mono">{s.kartNo}</TableCell>
                    <TableCell className="tarih-hucre">{tarihSaat(s.zaman)}</TableCell>
                    <TableCell>{s.yon === "giris" ? "Giriş" : s.yon === "cikis" ? "Çıkış" : <Badge variant="outline">Yok</Badge>}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        </section>
      )}

      {yukleme.tur === "hata" && (
        <Alert variant="destructive">
          <AlertTitle>Dosya aktarılamadı</AlertTitle>
          <AlertDescription>{yukleme.mesaj} Hiçbir satır kaydedilmedi.</AlertDescription>
        </Alert>
      )}

      <div className="flex flex-col gap-2 rounded-lg border border-dashed p-4">
        <Button disabled={!yuklenebilir || yukleme.tur === "yukleniyor"} onClick={onYukle} className="self-start">
          {yukleme.tur === "yukleniyor"
            ? "Yükleniyor…"
            : yuklenebilir
              ? `${sonuc.satirlar.length.toLocaleString("tr-TR")} satırı yükle`
              : "Yükle"}
        </Button>
        <p className="text-sm text-muted-foreground">
          {yuklenebilir
            ? "Dosya yüklemeye hazır. Kayıtlar tek seferde yazılır; bir hata olursa hiçbiri yazılmaz. Yüklenen kayıt değiştirilemez ve silinemez."
            : onceki
              ? "Bu dosya daha önce aktarıldığı için yüklenemez."
              : "Hatalar giderilmeden dosya yüklenemez."}
        </p>
      </div>
    </div>
  );
}
