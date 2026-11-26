"use client";

import { useState } from "react";
import { Textarea } from "@/components/ui/textarea";

// "Bekleyen kayıtlarla birlikte kilitle" kutusu ve zorla kilidin gerekçesi (T-92).
// Gerekçe yalnızca kutu işaretliyken görünür ve zorunludur (en az 10 karakter); veritabanı
// (ay_kilitle) gerekçeyi kilidin değiştirilemez izine (donem_kilit_izi) yazar.
export const GEREKCE_EN_AZ = 10;

export function ZorlaKilitAlanlari() {
  const [zorla, setZorla] = useState(false);
  return (
    <>
      <label className="flex items-center gap-2">
        <input type="checkbox" name="zorla" value="evet" checked={zorla} onChange={(e) => setZorla(e.target.checked)} />
        Bekleyen kayıtlarla birlikte kilitle
      </label>
      {zorla && (
        <div className="flex flex-col gap-1.5">
          <label htmlFor="gerekce" className="font-medium">
            Zorla kilit gerekçesi
          </label>
          <Textarea
            id="gerekce"
            name="gerekce"
            rows={2}
            required
            minLength={GEREKCE_EN_AZ}
            maxLength={1000}
            className="bg-card"
            placeholder="ör. Bordro kesim tarihi; açık itirazlar Aralık'ta fark satırıyla sonuçlandırılacak"
          />
          <p className="text-xs text-muted-foreground">
            En az {GEREKCE_EN_AZ} karakter. Gerekçe ve kilit anında açık olan kayıtların listesi değiştirilemez şekilde saklanır.
          </p>
        </div>
      )}
    </>
  );
}
