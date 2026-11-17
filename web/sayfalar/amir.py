"""Amir ekranı: gece işinin kanıt bulamadığı kayıtlara sabah karar verilir."""

from datetime import datetime, time

import streamlit as st

import veri

veri.baslat()
KULLANICI = veri.AMIR


def saate_cevir(metin, varsayilan):
    return datetime.strptime(metin, "%H:%M").time() if metin else varsayilan


st.title("Amir ekranı")
st.caption(f"Giriş yapan: {KULLANICI}")
veri.mesaj_goster()

bekleyen = veri.kayitlar(veri.DURUM_AMIR)

m1, m2, m3 = st.columns(3)
m1.metric("Karar bekleyen", len(bekleyen))
m2.metric("İK'ya gönderilen", len(veri.kayitlar(veri.DURUM_IK)))
m3.metric("Kapanan", len(veri.kayitlar(veri.DURUM_KAPALI)))

if not bekleyen:
    st.info("Karar bekleyen kayıt yok.", icon=":material/task_alt:")
    st.stop()

st.subheader("Karar bekleyen kayıtlar")
st.caption("Gece işi bu kayıtlar için kapı veya yemekhane kanıtı bulamadı; öneriyi siz onaylarsınız.")
st.dataframe(veri.kayit_tablosu(bekleyen), hide_index=True, width="stretch")

st.subheader("Karar ver")
secili_id = st.selectbox(
    "Kayıt",
    [k["id"] for k in bekleyen],
    format_func=veri.kayit_etiketi,
)
k = veri.kayit(secili_id)

with st.container(border=True):
    c1, c2, c3 = st.columns(3)
    c1.markdown(f"**Ham kayıt** (değişmez)  \n{k['ham_giris'] or '—'} – {k['ham_cikis'] or '—'}")
    c2.markdown(f"**Kanıt**  \n{k['kanit']}")
    c3.markdown(f"**Sistemin önerisi**  \n{k['oneri']}")

    if k["aleyhine"]:
        st.warning(
            "Bu öneri çalışanın aleyhine. Kuralımız gereği kararı İK verir; "
            "kaydı gerekçenizle İK'ya gönderebilirsiniz.",
            icon=":material/gavel:",
        )
        secenekler = ["İK'ya gönder"]
    else:
        secenekler = ["Öneriyi onayla", "Saati düzelt", "İK'ya gönder"]

    islem = st.radio("Karar", secenekler, horizontal=True, key=f"islem_{secili_id}")

    giris = cikis = None
    if islem == "Saati düzelt":
        s1, s2 = st.columns(2)
        giris = s1.time_input(
            "Giriş", saate_cevir(k["onerilen_giris"] or k["ham_giris"], time(8, 0)),
            step=60, key=f"giris_{secili_id}",
        )
        cikis = s2.time_input(
            "Çıkış", saate_cevir(k["onerilen_cikis"] or k["ham_cikis"], time(16, 0)),
            step=60, key=f"cikis_{secili_id}",
        )

    gerekce = st.text_area(
        "Gerekçe (zorunlu)",
        placeholder="Örn. Çalışan vardiya sonuna kadar hattaydı, ben de oradaydım.",
        key=f"gerekce_{secili_id}",
    )

    if st.button("Kararı kaydet", type="primary"):
        if not gerekce.strip():
            st.error("Gerekçe yazmadan karar kaydedilemez.")
        elif islem == "Saati düzelt" and cikis <= giris:
            st.error("Çıkış saati girişten sonra olmalı.")
        else:
            try:
                if islem == "Öneriyi onayla":
                    veri.kayit_karar(secili_id, KULLANICI, "Öneri onaylandı", gerekce,
                                     veri.DURUM_KAPALI, k["onerilen_giris"], k["onerilen_cikis"])
                elif islem == "Saati düzelt":
                    veri.kayit_karar(secili_id, KULLANICI, "Saat düzeltildi", gerekce,
                                     veri.DURUM_KAPALI, giris.strftime("%H:%M"), cikis.strftime("%H:%M"))
                else:
                    veri.kayit_karar(secili_id, KULLANICI, "İK'ya gönderildi", gerekce, veri.DURUM_IK)
            except Exception as hata:  # veritabanı kuralı reddettiyse hiçbir şey kaydedilmez
                st.error(f"Karar kaydedilemedi: {veri.hata_metni(hata)}")
            else:
                veri.mesaj_birak(f"Kayıt #{secili_id} için karar kaydedildi: {islem}.")
                st.rerun()
