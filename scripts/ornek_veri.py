"""Boş bir veritabanına küçük bir deneme verisi ekler (sentetik, gerçek kişi değildir).

İçerik: 1 amir, 1 İK, 5 departman, 8 çalışan ve son 4 günün PDKS / kapı / yemekhane
okutmaları. Gece işinin sonucunu da taklit eder: sorunsuz günler "tamam", kanıt
bulunamayan günler amire soru olarak düşer (amir ekranında 6 kayıt görünür).

Kullanım (repo kökünden):  python scripts/ornek_veri.py
Bağlantı: .env içindeki PDKS_ADMIN_DB_URL. Veritabanında çalışan varsa hiçbir şey yapmaz.
Hepsi tek işlemde yazılır; bir hata olursa hiçbir şey kalmaz.
"""

import hashlib
import sys
from datetime import date, datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

import psycopg
from dotenv import dotenv_values

TZ = ZoneInfo("Europe/Istanbul")
BUGUN = date.today()
GUNLER = [BUGUN - timedelta(days=n) for n in range(4, 0, -1)]   # 4 gün önce .. dün

CALISANLAR = [  # sicil, ad, soyad, bölüm
    ("1043", "Ali", "Kaya", "Sargı"),
    ("1057", "Zeynep", "Arslan", "Sargı"),
    ("1088", "Hasan", "Çelik", "Montaj"),
    ("1102", "Elif", "Şahin", "Montaj"),
    ("1121", "Murat", "Öztürk", "Test"),
    ("1135", "Fatma", "Aydın", "Kalite"),
    ("1149", "Emre", "Koç", "Sargı"),
    ("1163", "Seda", "Yıldız", "Depo"),
]

# Sorunlu günler: (sicil, kaç gün önce) -> okutmalar ve gece işinin açacağı soru.
# pdks: [(saat, yön)], kanit: [(kaynak, saat, yön)], soru: soru türü (yoksa gün "tamam")
SORUNLU = {
    ("1043", 1): dict(pdks=[("07:56", "giris")], kanit=[("kapi", "07:51", "giris")], soru="cikis_yok",
                      aciklama="Çıkış okutması yok; kapı ve yemekhane kaydında çıkış bulunamadı."),
    ("1057", 1): dict(pdks=[("17:04", "cikis")], kanit=[("yemekhane", "12:01", None)], soru="kanit_vardiya_sonrasi",
                      aciklama="Giriş okutması yok; tek kanıt yemekhane 12:01 (vardiya başından sonra)."),
    ("1088", 1): dict(pdks=[], kanit=[], soru="hic_kayit_yok",
                      aciklama="Gün boyu hiç okutma ve kanıt yok."),
    ("1102", 2): dict(pdks=[("07:49", "giris"), ("07:52", "giris")], kanit=[], soru="cikis_yok", mukerrer="07:52",
                      aciklama="Aynı yönde çift okutma (07:52 mükerrer işaretlendi); çıkış okutması yok."),
    ("1121", 2): dict(pdks=[("17:02", "cikis")], kanit=[], soru="giris_yok",
                      aciklama="Giriş okutması yok; kapı ve yemekhane kaydı da yok."),
    ("1149", 3): dict(pdks=[("08:02", "giris")], kanit=[("yemekhane", "12:15", None)], soru="cikis_yok",
                      aciklama="Çıkış okutması yok; yemekhane 12:15, çıkış kanıtı yok."),
    ("1163", 4): dict(pdks=[("08:47", "giris"), ("17:01", "cikis")], kanit=[("kapi", "08:45", "giris")], soru=None),
}


def zaman(gun, saat):
    return datetime.combine(gun, datetime.strptime(saat, "%H:%M").time(), TZ)


def tek(cur, sql, parametre):
    return cur.execute(sql, parametre).fetchone()[0]


def main():
    proje = Path(__file__).resolve().parents[1]
    url = dotenv_values(proje / ".env").get("PDKS_ADMIN_DB_URL", "")
    if not url or "SIFRE" in url:
        sys.exit("HATA: .env içinde PDKS_ADMIN_DB_URL doldurulmamış.")

    with psycopg.connect(url) as conn, conn.cursor() as cur:
        cur.execute("set timezone to 'Europe/Istanbul'")
        if tek(cur, "select count(*) from pdks.calisan", None):
            sys.exit("DURDU: veritabanında zaten çalışan var; deneme verisi eklenmedi.")

        amir = tek(cur, """insert into pdks.kullanici (ad_soyad, eposta, rol)
                           values ('Mehmet Yılmaz', 'amir@ornek.test', 'amir') returning id""", None)
        tek(cur, """insert into pdks.kullanici (ad_soyad, eposta, rol)
                    values ('Ayşe Demir', 'ik@ornek.test', 'ik') returning id""", None)

        bolum = {}
        for ad in ("Sargı", "Montaj", "Test", "Kalite", "Depo"):
            bolum[ad] = tek(cur, "insert into pdks.departman (ad, amir_id) values (%s, %s) returning id", (ad, amir))

        calisan = {}
        for sicil, ad, soyad, b in CALISANLAR:
            calisan[sicil] = tek(cur, """insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
                                         values (%s, %s, %s, %s, '2024-01-01') returning id""",
                                 (sicil, ad, soyad, bolum[b]))
            cur.execute("insert into pdks.kart (kart_no, calisan_id) values (%s, %s)", (f"K{sicil}", calisan[sicil]))

        okuyucu = {}
        for kod, ad, sistem in (("PDKS-A", "A kapısı PDKS okuyucu", "pdks"),
                                ("KAPI-1", "Tesis ana kapı turnikesi", "kapi"),
                                ("YEMEK-1", "Yemekhane kart okuyucu", "yemekhane")):
            okuyucu[sistem] = tek(cur, "insert into pdks.okuyucu (kod, ad, sistem) values (%s, %s, %s) returning id",
                                  (kod, ad, sistem))

        vardiya, v_bas, v_bit = cur.execute(
            "select id, baslangic, bitis from pdks.vardiya_tanim where kod = 'GUNDUZ'").fetchone()
        soru_sayisi = 0

        for gun in GUNLER:
            once = (BUGUN - gun).days
            aktarim = {}
            for kaynak in ("pdks", "kapi", "yemekhane"):
                ozet = hashlib.sha256(f"ornek-veri-{kaynak}-{gun}".encode()).hexdigest()
                aktarim[kaynak] = tek(cur, """insert into pdks.aktarim (kaynak, dosya_adi, dosya_ozeti, veri_tarihi)
                                              values (%s, %s, %s, %s) returning id""",
                                      (kaynak, f"{kaynak}_{gun:%Y%m%d}.csv", ozet, gun))
            gece = tek(cur, """insert into pdks.gece_isi (islenen_gun, bitis, durum)
                               values (%s, now(), 'basarili') returning id""", (gun,))

            for sira, (sicil, *_rest) in enumerate(CALISANLAR):
                cid, kart = calisan[sicil], f"K{sicil}"
                cur.execute("insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id) values (%s, %s, %s)",
                            (cid, gun, vardiya))
                durum = SORUNLU.get((sicil, once))
                if durum is None:   # sorunsuz gün: birkaç dakika oynayan normal okutmalar
                    d = (sira * 3 + once) % 7
                    durum = dict(pdks=[(f"07:{50 + d:02d}", "giris"), (f"17:{d:02d}", "cikis")],
                                 kanit=[("kapi", f"07:{44 + d:02d}", "giris"), ("yemekhane", f"12:{10 + d:02d}", None)],
                                 soru=None)

                ham = {}
                for saat, yon in durum["pdks"]:
                    ham[saat] = tek(cur, """insert into pdks.ham_okutma (aktarim_id, okuyucu_id, kart_no, okutma_zamani, yon)
                                            values (%s, %s, %s, %s, %s) returning id""",
                                    (aktarim["pdks"], okuyucu["pdks"], kart, zaman(gun, saat), yon))
                for kaynak, saat, yon in durum["kanit"]:
                    cur.execute("""insert into pdks.kanit_kaydi (aktarim_id, okuyucu_id, kaynak, kart_no, okutma_zamani, yon)
                                   values (%s, %s, %s, %s, %s, %s)""",
                                (aktarim[kaynak], okuyucu[kaynak], kaynak, kart, zaman(gun, saat), yon))
                if durum.get("mukerrer"):
                    cur.execute("""insert into pdks.okutma_isareti (ham_okutma_id, isaret, aciklama, gece_isi_id)
                                   values (%s, 'mukerrer', 'Eşik içinde aynı yönlü ikinci okutma', %s)""",
                                (ham[durum["mukerrer"]], gece))

                girisler = [zaman(gun, s) for s, y in durum["pdks"] if y == "giris"]
                cikislar = [zaman(gun, s) for s, y in durum["pdks"] if y == "cikis"]
                giris = min(girisler) if girisler else None
                cikis = max(cikislar) if cikislar else None
                plan_bas, plan_bit = datetime.combine(gun, v_bas, TZ), datetime.combine(gun, v_bit, TZ)

                if durum["soru"] is None:
                    gec = max(0, int((giris - plan_bas).total_seconds() // 60) - 5)
                    erken = max(0, int((plan_bit - cikis).total_seconds() // 60) - 5)
                    sonuc = dict(durum="tamam", calisma=int((cikis - giris).total_seconds() // 60),
                                 gec=gec, erken=erken, hesap=True)
                else:
                    sonuc = dict(durum="devamsiz_suphesi" if durum["soru"] == "hic_kayit_yok" else "soru_bekliyor",
                                 calisma=None, gec=None, erken=None, hesap=False)

                gun_id = tek(cur, """
                    insert into pdks.gun_kaydi (calisan_id, is_gunu, vardiya_id, planli_baslangic, planli_bitis,
                                                giris_zamani, cikis_zamani, giris_kaynagi, cikis_kaynagi, durum,
                                                gec_kalma_dk, erken_cikis_dk, calisma_dk, hesap_tamam, gece_isi_id)
                    values (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s) returning id""",
                    (cid, gun, vardiya, plan_bas, plan_bit, giris, cikis,
                     "pdks" if giris else None, "pdks" if cikis else None, sonuc["durum"],
                     sonuc["gec"], sonuc["erken"], sonuc["calisma"], sonuc["hesap"], gece))

                if durum["soru"]:
                    cur.execute("""insert into pdks.amir_sorusu (gun_kaydi_id, soru_turu, aciklama, atanan_id, son_cevap_tarihi)
                                   values (%s, %s, %s, %s, %s)""",
                                (gun_id, durum["soru"], durum["aciklama"], amir, BUGUN + timedelta(days=3)))
                    soru_sayisi += 1

        conn.commit()
    print(f"Deneme verisi eklendi: {len(CALISANLAR)} çalışan, {len(GUNLER)} gün, amire {soru_sayisi} soru.")


if __name__ == "__main__":
    main()
