"""İK ekranı: amirden gelen kayıtlar, çalışan itirazları ve denetim kaydı."""

from datetime import date, datetime, time, timedelta

import streamlit as st

import veri

veri.baslat()
KULLANICI = veri.IK


def saate_cevir(metin, varsayilan):
    return datetime.strptime(metin, "%H:%M").time() if metin else varsayilan


st.title("İK ekranı")
st.caption(f"Giriş yapan: {KULLANICI}")
veri.mesaj_goster()

gelen = veri.kayitlar(veri.DURUM_IK)
acik_itirazlar = veri.itirazlar(veri.ITIRAZ_ACIK)

m1, m2, m3 = st.columns(3)
m1.metric("Amirden gelen kayıt", len(gelen))
m2.metric("Açık itiraz", len(acik_itirazlar))
m3.metric("Denetim kaydı satırı", len(veri.denetim_kaydi()))

sekme_gelen, sekme_itiraz_gir, sekme_itirazlar, sekme_denetim = st.tabs(
    ["Amirden gelenler", "İtiraz kaydı gir", "İtirazlar", "Denetim kaydı"]
)

# --- Amirden gelen kayıtlar ------------------------------------------------
with sekme_gelen:
    if not gelen:
        st.info("Amirden gelen kayıt yok.", icon=":material/task_alt:")
    else:
        st.dataframe(veri.kayit_tablosu(gelen), hide_index=True, width="stretch")

        secili_id = st.selectbox("Kayıt", [k["id"] for k in gelen],
                                 format_func=veri.kayit_etiketi, key="ik_kayit")
        k = veri.kayit(secili_id)
        with st.container(border=True):
            c1, c2, c3 = st.columns(3)
            c1.markdown(f"**Ham kayıt** (değişmez)  \n{k['ham_giris'] or '—'} – {k['ham_cikis'] or '—'}")
            c2.markdown(f"**Sistemin önerisi**  \n{k['oneri']}")
            c3.markdown(f"**Amirin notu**  \n{k['amir_notu']}")

            islem = st.radio("Karar", ["Öneriyi uygula", "Saati düzelt", "Ham kaydı geçerli say"],
                             horizontal=True, key=f"ik_islem_{secili_id}")
            giris = cikis = None
            if islem == "Saati düzelt":
                s1, s2 = st.columns(2)
                giris = s1.time_input("Giriş", saate_cevir(k["onerilen_giris"] or k["ham_giris"], time(8, 0)),
                                      step=60, key=f"ik_giris_{secili_id}")
                cikis = s2.time_input("Çıkış", saate_cevir(k["onerilen_cikis"] or k["ham_cikis"], time(16, 0)),
                                      step=60, key=f"ik_cikis_{secili_id}")
            gerekce = st.text_area("Gerekçe (zorunlu)", key=f"ik_gerekce_{secili_id}")

            if st.button("Kararı kaydet", type="primary", key="ik_kayit_kaydet"):
                if not gerekce.strip():
                    st.error("Gerekçe yazmadan karar kaydedilemez.")
                elif islem == "Saati düzelt" and cikis <= giris:
                    st.error("Çıkış saati girişten sonra olmalı.")
                else:
                    if islem == "Öneriyi uygula":
                        g, c = k["onerilen_giris"], k["onerilen_cikis"]
                    elif islem == "Saati düzelt":
                        g, c = giris.strftime("%H:%M"), cikis.strftime("%H:%M")
                    else:
                        g, c = k["ham_giris"], k["ham_cikis"]
                    try:
                        veri.kayit_karar(secili_id, KULLANICI, f"İK kararı: {islem}", gerekce,
                                         veri.DURUM_KAPALI, g, c)
                    except Exception as hata:
                        st.error(f"Karar kaydedilemedi: {veri.hata_metni(hata)}")
                    else:
                        veri.mesaj_birak(f"Kayıt #{secili_id} kapatıldı: {islem}.")
                        st.rerun()

# --- İtiraz kaydı gir ------------------------------------------------------
with sekme_itiraz_gir:
    st.caption("Çalışanın sözlü, dilekçe ya da e-posta ile ilettiği itirazı buraya kaydedin.")
    with st.form("itiraz_formu", clear_on_submit=True):
        sicil = st.selectbox("Çalışan", list(veri.CALISANLAR), format_func=veri.calisan_etiketi)
        f1, f2, f3 = st.columns(3)
        tarih = f1.date_input("İtiraz edilen gün", value=date.today() - timedelta(days=1),
                              max_value=date.today(), format="DD.MM.YYYY")
        konu = f2.selectbox("Konu", veri.ITIRAZ_KONULARI)
        basvuru = f3.radio("Başvuru şekli", veri.BASVURU_SEKILLERI, horizontal=True)
        beyan = st.text_area("Çalışanın beyanı (zorunlu)",
                             placeholder="Örn. 12 Kasım'da 16:00'ya kadar çalıştım, çıkışta kart okuyucu arızalıydı.")
        gonder = st.form_submit_button("İtirazı kaydet", type="primary")

    if gonder:
        if not beyan.strip():
            st.error("Çalışanın beyanı boş bırakılamaz.")
        else:
            try:
                no = veri.itiraz_ekle(KULLANICI, sicil, tarih, konu, basvuru, beyan)
            except Exception as hata:
                st.error(f"İtiraz kaydedilemedi: {veri.hata_metni(hata)}")
            else:
                ilgili = veri.itiraz(no)["ilgili_kayit"]
                ek = f" O güne ait kayıt #{ilgili} ile ilişkilendirildi." if ilgili else ""
                veri.mesaj_birak(f"İtiraz #{no} kaydedildi.{ek}")
                st.rerun()

# --- İtirazlar --------------------------------------------------------------
with sekme_itirazlar:
    tum = veri.itirazlar()
    if not tum:
        st.info("Henüz itiraz kaydı yok. «İtiraz kaydı gir» sekmesinden ekleyebilirsiniz.",
                icon=":material/inbox:")
    else:
        st.dataframe([{
            "No": i["id"],
            "Durum": i["durum"],
            "Sicil": i["sicil"],
            "Ad Soyad": i["ad_soyad"],
            "Gün": i["tarih"].strftime("%d.%m.%Y"),
            "Konu": i["konu"],
            "Başvuru": i["basvuru_sekli"],
            "İlgili kayıt": f"#{i['ilgili_kayit']}" if i["ilgili_kayit"] else "",
            "Sonuç": i["sonuc"] or "",
        } for i in tum], hide_index=True, width="stretch")

        if not acik_itirazlar:
            st.info("Açık itiraz yok.", icon=":material/task_alt:")
        else:
            st.subheader("İtirazı sonuçlandır")
            itiraz_id = st.selectbox(
                "İtiraz", [i["id"] for i in acik_itirazlar],
                format_func=lambda n: (lambda i: f"#{i['id']} · {i['sicil']} {i['ad_soyad']} · "
                                                 f"{i['tarih']:%d.%m} · {i['konu']}")(veri.itiraz(n)),
            )
            i = veri.itiraz(itiraz_id)
            with st.container(border=True):
                st.markdown(f"**Çalışanın beyanı**  \n{i['beyan']}")
                if i["ilgili_kayit"]:
                    ilgili = veri.kayit(i["ilgili_kayit"])
                    st.markdown(f"**İlgili kayıt #{ilgili['id']}:** {ilgili['sorun']} · "
                                f"ham {ilgili['ham_giris'] or '—'} – {ilgili['ham_cikis'] or '—'} · "
                                f"durum: {ilgili['durum']}")
                sonuc = st.radio("Sonuç", ["Kabul", "Kısmen kabul", "Ret"], horizontal=True,
                                 key=f"sonuc_{itiraz_id}")
                aciklama = st.text_area("Açıklama (zorunlu)", key=f"aciklama_{itiraz_id}")
                if st.button("Sonucu kaydet", type="primary", key="itiraz_sonuc_kaydet"):
                    if not aciklama.strip():
                        st.error("Açıklama yazmadan sonuç kaydedilemez.")
                    else:
                        try:
                            veri.itiraz_sonuclandir(itiraz_id, KULLANICI, sonuc, aciklama)
                        except Exception as hata:
                            st.error(f"Sonuç kaydedilemedi: {veri.hata_metni(hata)}")
                        else:
                            veri.mesaj_birak(f"İtiraz #{itiraz_id} sonuçlandı: {sonuc}.")
                            st.rerun()

# --- Denetim kaydı ---------------------------------------------------------
with sekme_denetim:
    st.caption("Her karar burada kim / ne zaman / eski / yeni / gerekçe ile tutulur. Bu kayıt silinemez.")
    satirlar = veri.denetim_kaydi()
    if not satirlar:
        st.info("Henüz denetim kaydı yok.", icon=":material/history:")
    else:
        st.dataframe([{
            "Zaman": d["zaman"],
            "Kullanıcı": d["kullanici"],
            "Nesne": d["nesne"],
            "İşlem": d["islem"],
            "Eski": d["eski"],
            "Yeni": d["yeni"],
            "Gerekçe": d["gerekce"],
        } for d in reversed(satirlar)], hide_index=True, width="stretch")
