"""Ekranların kullandığı veri katmanı (Supabase / PostgreSQL).

Ekranlar (sayfalar/) yalnızca bu dosyadaki fonksiyonları çağırır; veritabanının
ayrıntısı burada kalır. Bağlantı bilgisi .env dosyasındaki PDKS_UYGULAMA_DB_URL'den
okunur (uygulamanın kısıtlı kullanıcısı: ham kayıt ve düzeltme izini değiştiremez).

Ekrandaki "kayıt" = gece işinin amire bıraktığı soru (pdks.amir_sorusu) ve ona bağlı
günlük kayıt (pdks.gun_kaydi).

Proje kuralları veritabanında da korunur:
- Ham okutmalara (pdks.ham_okutma) hiç dokunulmaz.
- Saat / durum değişikliği yalnızca pdks.duzeltme_uygula() ile yapılır; iz pdks.duzeltme'ye yazılır.
- Saat değiştirmeyen kararlar (İK'ya gönderme, itiraz) pdks.karar_kaydi'na yazılır.
- Bu iki tablo silinemez ve değiştirilemez. "Devamsız" kararını yalnızca İK verebilir.
"""

from datetime import datetime, time, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

import streamlit as st
from dotenv import dotenv_values
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

TZ = ZoneInfo("Europe/Istanbul")

DURUM_AMIR = "Amir bekliyor"
DURUM_IK = "İK bekliyor"
DURUM_KAPALI = "Kapandı"

ITIRAZ_ACIK = "Açık"
ITIRAZ_SONUC = "Sonuçlandı"

ITIRAZ_KONULARI = [
    "Eksik giriş / çıkış",
    "Yanlış saat",
    "Devamsız sayılma",
    "Fazla mesai eksik",
    "Diğer",
]
BASVURU_SEKILLERI = ["Sözlü", "Dilekçe", "E-posta"]
_BASVURU_DB = {"Sözlü": "sozlu", "Dilekçe": "dilekce", "E-posta": "eposta"}
_BASVURU_EKRAN = {v: k for k, v in _BASVURU_DB.items()}

_SORUN = {
    "giris_yok": "Giriş okutması yok",
    "kanit_vardiya_sonrasi": "Giriş okutması yok (kanıt vardiya başından sonra)",
    "cikis_yok": "Çıkış okutması yok",
    "hic_kayit_yok": "Gün boyu hiç okutma yok",
    "ariza_kaniti_yok": "Okuyucu arızası, kanıt yok",
    "vardiya_uyusmazligi": "Okutmalar başka vardiyaya uyuyor",
}
_SORU_DURUM = {
    "acik": DURUM_AMIR, "eskale": DURUM_AMIR,
    "ik_karari_bekliyor": DURUM_IK,
    "cevaplandi": DURUM_KAPALI, "kapandi": DURUM_KAPALI,
}
_ALAN = {"giris_zamani": "giriş", "cikis_zamani": "çıkış", "vardiya_id": "vardiya", "durum": "durum"}

# Giriş sistemi gelene kadar her ekran veritabanındaki ilk amir / İK hesabını kullanır.
# baslat() bunları ve çalışan listesini veritabanından doldurur.
AMIR = IK = None
CALISANLAR = {}          # sicil_no -> (ad soyad, bölüm)
_KULLANICI_ID = {}       # ekranda görünen ad -> kullanici.id


# --- Bağlantı ----------------------------------------------------------------

def _oturum_ayari(conn):
    conn.autocommit = True
    conn.execute("set timezone to 'Europe/Istanbul'")


@st.cache_resource(show_spinner=False)
def _havuz():
    url = dotenv_values(Path(__file__).resolve().parents[1] / ".env").get("PDKS_UYGULAMA_DB_URL", "")
    if not url or ":SIFRE@" in url:
        return None
    return ConnectionPool(url, min_size=1, max_size=4, configure=_oturum_ayari,
                          kwargs={"row_factory": dict_row, "connect_timeout": 15}, open=True)


def _sorgu(sql, parametre=None):
    with _havuz().connection() as conn:
        return conn.execute(sql, parametre).fetchall()


def baslat():
    """Bağlantıyı kurar, kullanıcıları ve çalışanları yükler. Her sayfanın başında çağrılır."""
    global AMIR, IK
    if _havuz() is None:
        st.error("Veritabanı bağlantısı yok: .env dosyasında PDKS_UYGULAMA_DB_URL doldurulmamış.")
        st.stop()

    kullanicilar = _sorgu("""
        select distinct on (rol) id, ad_soyad, rol from pdks.kullanici
        where aktif and rol in ('amir', 'ik') order by rol, id""")
    _KULLANICI_ID.clear()
    AMIR = IK = None
    for k in kullanicilar:
        ad = f"{k['ad_soyad']} ({'Amir' if k['rol'] == 'amir' else 'İK'})"
        _KULLANICI_ID[ad] = k["id"]
        if k["rol"] == "amir":
            AMIR = ad
        else:
            IK = ad
    if AMIR is None or IK is None:
        st.error("Veritabanında aktif bir amir ve bir İK kullanıcısı yok. "
                 "Deneme verisi için: python scripts/ornek_veri.py")
        st.stop()

    CALISANLAR.clear()
    for c in _sorgu("""
            select c.sicil_no, c.ad || ' ' || c.soyad as ad_soyad, d.ad as bolum
            from pdks.calisan c join pdks.departman d on d.id = c.departman_id
            where c.aktif order by c.sicil_no"""):
        CALISANLAR[c["sicil_no"]] = (c["ad_soyad"], c["bolum"])


# --- Yardımcılar ---------------------------------------------------------------

def _hhmm(z):
    return z.astimezone(TZ).strftime("%H:%M") if z else None


def _metin_zaman(deger):
    """duzeltme.eski_deger / yeni_deger metnini okunur hale getirir."""
    if not deger:
        return "—"
    try:
        return datetime.fromisoformat(deger).astimezone(TZ).strftime("%d.%m %H:%M")
    except ValueError:
        return deger


def _zaman(is_gunu, saat, vardiya_baslangic, gece_vardiyasi):
    """'HH:MM' saatini iş gününe göre tarihe çevirir (gece vardiyasında sabah saatleri ertesi gündür)."""
    t = datetime.strptime(saat, "%H:%M").time()
    gun = is_gunu + timedelta(days=1) if gece_vardiyasi and t < vardiya_baslangic else is_gunu
    return datetime.combine(gun, t, TZ)


_KAYIT_SQL = """
select s.id, s.soru_turu, s.durum as soru_durumu, s.onerilen_zaman,
       c.sicil_no, c.ad || ' ' || c.soyad as ad_soyad, d.ad as bolum,
       g.id as gun_id, g.is_gunu, g.planli_baslangic, g.planli_bitis,
       g.giris_zamani, g.cikis_zamani,
       coalesce(v.baslangic, time '00:00') as vardiya_baslangic,
       coalesce(v.gece_yarisini_asar, false) as gece_vardiyasi,
       ham.giris as ham_giris, ham.cikis as ham_cikis, kanit.metin as kanit,
       (select kk.gerekce from pdks.karar_kaydi kk
        where kk.nesne_turu = 'amir_sorusu' and kk.nesne_id = s.id and kk.islem = 'İK''ya gönderildi'
        order by kk.zaman desc limit 1) as amir_notu
from pdks.amir_sorusu s
join pdks.gun_kaydi g on g.id = s.gun_kaydi_id
join pdks.calisan c on c.id = g.calisan_id
join pdks.departman d on d.id = c.departman_id
left join pdks.vardiya_tanim v on v.id = g.vardiya_id
-- Ham okutmalar: vardiya penceresi içinde, mükerrer işaretliler hariç (ham tabloya dokunulmaz)
left join lateral (
    select min(h.okutma_zamani) filter (where coalesce(h.yon, 'giris') = 'giris') as giris,
           max(h.okutma_zamani) filter (where coalesce(h.yon, 'cikis') = 'cikis') as cikis
    from pdks.ham_okutma h
    join pdks.kart kr on kr.kart_no = h.kart_no and kr.calisan_id = c.id
    where h.okutma_zamani between g.planli_baslangic - make_interval(mins => coalesce(v.pencere_once_dk, 120))
                              and g.planli_bitis + make_interval(mins => coalesce(v.pencere_sonra_dk, 240))
      and not exists (select 1 from pdks.okutma_isareti i
                      where i.ham_okutma_id = h.id and i.isaret = 'mukerrer')
) ham on true
-- Kanıt: aynı penceredeki kapı / yemekhane / servis kayıtları
left join lateral (
    select string_agg(case kk.kaynak when 'kapi' then 'Kapı' when 'yemekhane' then 'Yemekhane' else 'Servis' end
                      || ' ' || to_char(kk.okutma_zamani, 'HH24:MI'), ', ' order by kk.okutma_zamani) as metin
    from pdks.kanit_kaydi kk
    join pdks.kart kr on kr.kart_no = kk.kart_no and kr.calisan_id = c.id
    where kk.okutma_zamani between g.planli_baslangic - make_interval(mins => coalesce(v.pencere_once_dk, 120))
                               and g.planli_bitis + make_interval(mins => coalesce(v.pencere_sonra_dk, 240))
) kanit on true
"""


def _kayit_sozluk(r):
    tur = r["soru_turu"]
    plan_giris, plan_cikis = _hhmm(r["planli_baslangic"]), _hhmm(r["planli_bitis"])
    ham_giris, ham_cikis = _hhmm(r["ham_giris"]), _hhmm(r["ham_cikis"])
    oneri_zaman = _hhmm(r["onerilen_zaman"])
    aleyhine = tur == "hic_kayit_yok"

    if tur in ("giris_yok", "kanit_vardiya_sonrasi"):
        og, oc = oneri_zaman or plan_giris, ham_cikis
        oneri = f"Vardiya başı ({og}) giriş kabul edilsin" if not oneri_zaman else f"Giriş {og} kabul edilsin"
    elif tur == "cikis_yok":
        og, oc = ham_giris, oneri_zaman or plan_cikis
        oneri = f"Vardiya sonu ({oc}) çıkış kabul edilsin" if not oneri_zaman else f"Çıkış {oc} kabul edilsin"
    elif aleyhine:
        og = oc = None
        oneri = "Devamsız sayılsın"
    else:
        og, oc = ham_giris or plan_giris, ham_cikis or plan_cikis
        oneri = f"Vardiya saatleri ({plan_giris}–{plan_cikis}) kabul edilsin"

    durum = _SORU_DURUM[r["soru_durumu"]]
    return {
        "id": r["id"],
        "sicil": r["sicil_no"],
        "ad_soyad": r["ad_soyad"],
        "bolum": r["bolum"],
        "tarih": r["is_gunu"],
        "sorun": _SORUN.get(tur, tur),
        "ham_giris": ham_giris,
        "ham_cikis": ham_cikis,
        "kanit": r["kanit"] or "Kapı / yemekhane kaydı yok",
        "oneri": oneri,
        "onerilen_giris": og,
        "onerilen_cikis": oc,
        "aleyhine": aleyhine,
        "durum": durum,
        "son_giris": _hhmm(r["giris_zamani"]) if durum == DURUM_KAPALI else None,
        "son_cikis": _hhmm(r["cikis_zamani"]) if durum == DURUM_KAPALI else None,
        "amir_notu": r["amir_notu"],
        # Ekranda gösterilmeyen, yazma işlemlerinin kullandığı alanlar
        "_soru_turu": tur,
        "_soru_durumu": r["soru_durumu"],
        "_gun_id": r["gun_id"],
        "_giris": r["giris_zamani"],
        "_cikis": r["cikis_zamani"],
        "_vardiya_baslangic": r["vardiya_baslangic"],
        "_gece": r["gece_vardiyasi"],
    }


# --- Okuma -----------------------------------------------------------------

def kayitlar(durum=None):
    tum = [_kayit_sozluk(r) for r in _sorgu(_KAYIT_SQL + " order by g.is_gunu, s.id")]
    return [k for k in tum if durum is None or k["durum"] == durum]


def kayit(kayit_id):
    return _kayit_sozluk(_sorgu(_KAYIT_SQL + " where s.id = %s", (kayit_id,))[0])


_ITIRAZ_SQL = """
select i.id, i.durum, i.metin, i.konu, i.basvuru_sekli, i.olusturma_zamani, i.karar_aciklama,
       c.sicil_no, c.ad || ' ' || c.soyad as ad_soyad, d.ad as bolum, g.is_gunu,
       ky.ad_soyad as kaydeden,
       (select s.id from pdks.amir_sorusu s where s.gun_kaydi_id = g.id order by s.id desc limit 1) as ilgili_kayit,
       (select kk.yeni_deger from pdks.karar_kaydi kk
        where kk.nesne_turu = 'itiraz' and kk.nesne_id = i.id and kk.islem = 'İtiraz sonuçlandı'
        order by kk.zaman desc limit 1) as sonuc
from pdks.itiraz i
join pdks.calisan c on c.id = i.calisan_id
join pdks.departman d on d.id = c.departman_id
join pdks.gun_kaydi g on g.id = i.gun_kaydi_id
left join pdks.kullanici ky on ky.id = i.kaydeden_id
"""


def _itiraz_sozluk(r):
    return {
        "id": r["id"],
        "sicil": r["sicil_no"],
        "ad_soyad": r["ad_soyad"],
        "bolum": r["bolum"],
        "tarih": r["is_gunu"],
        "konu": r["konu"] or "—",
        "basvuru_sekli": _BASVURU_EKRAN.get(r["basvuru_sekli"], "—"),
        "beyan": r["metin"],
        "ilgili_kayit": r["ilgili_kayit"],
        "kaydeden": r["kaydeden"],
        "kayit_zamani": r["olusturma_zamani"].astimezone(TZ).strftime("%d.%m.%Y %H:%M"),
        "durum": ITIRAZ_ACIK if r["durum"] in ("acik", "inceleniyor") else ITIRAZ_SONUC,
        "sonuc": r["sonuc"] or ({"kabul": "Kabul", "red": "Ret"}.get(r["durum"])),
        "sonuc_aciklama": r["karar_aciklama"],
    }


def itirazlar(durum=None):
    tum = [_itiraz_sozluk(r) for r in _sorgu(_ITIRAZ_SQL + " order by i.id")]
    return [i for i in tum if durum is None or i["durum"] == durum]


def itiraz(itiraz_id):
    return _itiraz_sozluk(_sorgu(_ITIRAZ_SQL + " where i.id = %s", (itiraz_id,))[0])


def denetim_kaydi():
    """Düzeltme izi + karar kaydı, eskiden yeniye. İkisi de veritabanında silinemez."""
    satirlar = _sorgu("""
        select d.yapilma_zamani as zaman, coalesce(k.ad_soyad, 'Gece işi') as kullanici,
               case when d.soru_id is not null then 'Kayıt #' || d.soru_id || ' (' || c.sicil_no || ')'
                    else 'Gün ' || to_char(d.is_gunu, 'DD.MM') || ' (' || c.sicil_no || ')' end as nesne,
               'Düzeltme' as tur, d.alan, d.eski_deger as eski, d.yeni_deger as yeni, d.gerekce
        from pdks.duzeltme d
        join pdks.calisan c on c.id = d.calisan_id
        left join pdks.kullanici k on k.id = d.yapan_id
        union all
        select kk.zaman, k.ad_soyad,
               case kk.nesne_turu when 'amir_sorusu' then 'Kayıt #' else 'İtiraz #' end
                   || kk.nesne_id || coalesce(' (' || c.sicil_no || ')', ''),
               kk.islem, null, kk.eski_deger, kk.yeni_deger, kk.gerekce
        from pdks.karar_kaydi kk
        join pdks.kullanici k on k.id = kk.kullanici_id
        left join pdks.amir_sorusu s on kk.nesne_turu = 'amir_sorusu' and s.id = kk.nesne_id
        left join pdks.itiraz i on kk.nesne_turu = 'itiraz' and i.id = kk.nesne_id
        left join pdks.gun_kaydi g on g.id = coalesce(s.gun_kaydi_id, i.gun_kaydi_id)
        left join pdks.calisan c on c.id = g.calisan_id
        order by 1""")
    return [{
        "zaman": r["zaman"].astimezone(TZ).strftime("%d.%m.%Y %H:%M:%S"),
        "kullanici": r["kullanici"],
        "nesne": r["nesne"],
        "islem": f"Düzeltme: {_ALAN.get(r['alan'], r['alan'])}" if r["alan"] else r["tur"],
        "eski": _metin_zaman(r["eski"]) if r["alan"] else (r["eski"] or "—"),
        "yeni": _metin_zaman(r["yeni"]) if r["alan"] else (r["yeni"] or "—"),
        "gerekce": r["gerekce"],
    } for r in satirlar]


# --- Yazma -----------------------------------------------------------------

def _saat(giris, cikis):
    return f"{giris or '—'} – {cikis or '—'}"


def _karar_yaz(conn, kullanici_id, nesne_turu, nesne_id, islem, eski, yeni, gerekce):
    conn.execute("""insert into pdks.karar_kaydi (kullanici_id, nesne_turu, nesne_id, islem,
                                                  eski_deger, yeni_deger, gerekce)
                    values (%s, %s, %s, %s, %s, %s, %s)""",
                 (kullanici_id, nesne_turu, nesne_id, islem, eski, yeni, gerekce))


def _duzelt(conn, k, alan, yeni, gerekce, kaynak, kullanici_id, aleyhine=False):
    conn.execute("select pdks.duzeltme_uygula(%s, %s, %s, %s, %s, %s, p_soru_id => %s, p_aleyhine => %s)",
                 (k["_gun_id"], alan, yeni, gerekce, kaynak, kullanici_id, k["id"], aleyhine))


def kayit_karar(kayit_id, kullanici, islem, gerekce, yeni_durum, giris=None, cikis=None):
    """Bir kayda (amir sorusuna) karar uygular. Ham okutmalara dokunmaz.

    Saat değişiklikleri pdks.duzeltme_uygula() ile (iz pdks.duzeltme'ye), karar ise
    pdks.karar_kaydi'na yazılır. Hepsi tek işlemde: biri hata verirse hiçbiri kalmaz.
    """
    k = kayit(kayit_id)
    uid = _KULLANICI_ID[kullanici]
    ik_mi = kullanici == IK
    kaynak = "ik" if ik_mi else "amir"
    eski = f"{k['durum']} | {_saat(_hhmm(k['_giris']), _hhmm(k['_cikis']))}"
    iz_gerekcesi = f"{islem}: {gerekce.strip()}"

    with _havuz().connection() as conn, conn.transaction():
        if yeni_durum == DURUM_IK:
            sonuc = conn.execute("""update pdks.amir_sorusu set durum = 'ik_karari_bekliyor'
                                    where id = %s and durum in ('acik', 'eskale')""", (kayit_id,))
            if sonuc.rowcount != 1:
                raise ValueError("Bu kayıt artık amirde değil; sayfayı yenileyin.")
            _karar_yaz(conn, uid, "amir_sorusu", kayit_id, "İK'ya gönderildi", k["durum"], DURUM_IK, gerekce)
            return

        devamsiz = k["aleyhine"] and giris is None and cikis is None and "Öneri" in islem
        if devamsiz:
            if not ik_mi:
                raise ValueError("Çalışan aleyhine kararı yalnızca İK verebilir.")
            _duzelt(conn, k, "durum", "devamsiz", iz_gerekcesi, "ik", uid, aleyhine=True)
            cevap = "gelmedi"
        else:
            yeni_giris = _zaman(k["tarih"], giris, k["_vardiya_baslangic"], k["_gece"]) if giris else None
            yeni_cikis = _zaman(k["tarih"], cikis, k["_vardiya_baslangic"], k["_gece"]) if cikis else None
            degisenler = []
            if yeni_giris and yeni_giris != k["_giris"]:
                degisenler.append(("giris_zamani", yeni_giris))
            if yeni_cikis and yeni_cikis != k["_cikis"]:
                degisenler.append(("cikis_zamani", yeni_cikis))
            # Çıkış > giriş kuralı ara adımda bozulmasın: yeni giriş eski çıkıştan sonraysa önce çıkış
            if len(degisenler) == 2 and k["_cikis"] and yeni_giris >= k["_cikis"]:
                degisenler.reverse()
            for alan, deger in degisenler:
                _duzelt(conn, k, alan, deger.isoformat(), iz_gerekcesi, kaynak, uid)
            if yeni_giris or k["_giris"]:
                if yeni_cikis or k["_cikis"]:
                    conn.execute("update pdks.gun_kaydi set durum = 'tamam' where id = %s and durum <> 'tamam'",
                                 (k["_gun_id"],))
            cevap = ("geldi_saat_farkli" if "düzelt" in islem.lower()
                     else "bilmiyorum" if "Ham kayd" in islem else "geldi_saat_dogru")

        conn.execute("""update pdks.amir_sorusu
                        set cevap = %s, cevap_giris = %s, cevap_cikis = %s, cevap_aciklama = %s,
                            cevaplayan_id = %s, durum = 'kapandi'
                        where id = %s""",
                     (cevap,
                      _zaman(k["tarih"], giris, k["_vardiya_baslangic"], k["_gece"]) if giris else None,
                      _zaman(k["tarih"], cikis, k["_vardiya_baslangic"], k["_gece"]) if cikis else None,
                      gerekce, uid, kayit_id))
        yeni = "Devamsız" if devamsiz else f"{DURUM_KAPALI} | {_saat(giris, cikis)}"
        _karar_yaz(conn, uid, "amir_sorusu", kayit_id, islem, eski, yeni, gerekce)


def itiraz_ekle(kullanici, sicil, tarih, konu, basvuru_sekli, beyan):
    """İK'nın çalışan adına girdiği itirazı kaydeder. O güne ait günlük kayıt olmalı."""
    uid = _KULLANICI_ID[kullanici]
    with _havuz().connection() as conn, conn.transaction():
        gun = conn.execute("""select g.id, g.calisan_id from pdks.gun_kaydi g
                              join pdks.calisan c on c.id = g.calisan_id
                              where c.sicil_no = %s and g.is_gunu = %s""", (sicil, tarih)).fetchone()
        if gun is None:
            raise ValueError(f"{sicil} sicilli çalışanın {tarih:%d.%m.%Y} gününe ait kaydı yok; "
                             "itiraz bir güne bağlanmalı.")
        no = conn.execute("""insert into pdks.itiraz (calisan_id, gun_kaydi_id, metin, konu,
                                                      basvuru_sekli, kaydeden_id)
                             values (%s, %s, %s, %s, %s, %s) returning id""",
                          (gun["calisan_id"], gun["id"], beyan.strip(), konu,
                           _BASVURU_DB[basvuru_sekli], uid)).fetchone()["id"]
        _karar_yaz(conn, uid, "itiraz", no, "İtiraz kaydedildi", None,
                   f"{konu} · {tarih:%d.%m.%Y} · {basvuru_sekli}", beyan.strip())
    return no


def itiraz_sonuclandir(itiraz_id, kullanici, sonuc, aciklama):
    """Kabul / Kısmen kabul / Ret. Ret yalnızca İK; karar sonrası itiraz değiştirilemez."""
    uid = _KULLANICI_ID[kullanici]
    with _havuz().connection() as conn, conn.transaction():
        conn.execute("""update pdks.itiraz set durum = %s, karar_veren_id = %s, karar_aciklama = %s
                        where id = %s""",
                     ("red" if sonuc == "Ret" else "kabul", uid, aciklama.strip(), itiraz_id))
        _karar_yaz(conn, uid, "itiraz", itiraz_id, "İtiraz sonuçlandı", ITIRAZ_ACIK, sonuc, aciklama.strip())


# --- Ekran yardımcıları ----------------------------------------------------

def kayit_etiketi(kayit_id):
    k = kayit(kayit_id)
    return f"#{k['id']} · {k['tarih']:%d.%m} · {k['sicil']} {k['ad_soyad']} · {k['sorun']}"


def calisan_etiketi(sicil):
    ad, bolum = CALISANLAR[sicil]
    return f"{sicil} · {ad} ({bolum})"


def kayit_tablosu(liste):
    return [{
        "No": k["id"],
        "Tarih": k["tarih"].strftime("%d.%m.%Y"),
        "Sicil": k["sicil"],
        "Ad Soyad": k["ad_soyad"],
        "Bölüm": k["bolum"],
        "Sorun": k["sorun"],
        "Ham saat": _saat(k["ham_giris"], k["ham_cikis"]),
        "Öneri": k["oneri"],
        "Aleyhine": "Evet" if k["aleyhine"] else "",
    } for k in liste]


def hata_metni(hata):
    """Veritabanının kural hatasını ekranda gösterilecek tek satıra indirger."""
    return str(hata).splitlines()[0]


def mesaj_birak(metin):
    """Bir sonraki çalıştırmada gösterilecek başarı mesajı bırakır."""
    st.session_state.mesaj = metin


def mesaj_goster():
    # Kutu her çalıştırmada aynı yerde oluşturulur; böylece mesaj çıkınca
    # altındaki sekmeler kaymaz ve kullanıcı bulunduğu sekmede kalır.
    kutu = st.container()
    metin = st.session_state.pop("mesaj", None)
    if metin:
        kutu.success(metin, icon=":material/check_circle:")
