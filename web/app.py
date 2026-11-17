"""Atlas Trafo PDKS — amir ve İK ekranları.

Çalıştırmak için (repo kökünden):  streamlit run web/app.py
"""

import streamlit as st

import veri

st.set_page_config(page_title="Atlas Trafo PDKS", page_icon=":material/schedule:", layout="wide")
veri.baslat()

sayfa = st.navigation([
    st.Page("sayfalar/amir.py", title="Amir", icon=":material/fact_check:", default=True),
    st.Page("sayfalar/ik.py", title="İK", icon=":material/badge:"),
])

st.sidebar.caption(
    "Supabase veritabanına bağlı. Giriş sistemi henüz yok; ekranlar veritabanındaki "
    "ilk amir ve İK hesabıyla çalışır."
)

sayfa.run()
