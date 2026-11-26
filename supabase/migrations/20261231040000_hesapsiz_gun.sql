-- =====================================================================
-- K3 · T-91: Puantaj satırı ile gün kodları "tamam ama hesaplanmamış" günü farklı sayıyordu
--
-- Sorun: Durumu "tamam" ama hesabı yapılmamış gün (hesap_tamam = false; ör. açık soru varken İK
-- saatleri yazdı) canlı puantajda ve yönetici panelinde hem "çalışılan" hem "bekleyen" sayılıyordu.
-- Kod listesi (gun_kodlari_hesapla → kalem, ERP) aynı günü "eksik" sayıp kodlamıyordu. Zorla kilitte
-- satır "çalışılan 3", kalemler "NÇ 2 gün" yazıyordu; sistem kendi kendisiyle çelişiyordu.
--
-- Karar (Yusuf): hesabı tamamlanmamış gün her yerde "bekliyor" sayılır, çalışılan sayılmaz. Gün
-- hesaplanınca kendiliğinden çalışılan olur. Değişen tek şey calisilan_gun'ün koşulu
-- ("durum = 'tamam'" → "durum = 'tamam' and hesap_tamam"); sütunlar, sırası ve tipleri aynı.
-- Normal kilit bu günü zaten engelliyor (T-90, "hesap tamamlanmadı"); fark zorla kilitte ve
-- ekrandaki sayılarda görülüyordu.
-- Kalıcı test: supabase/tests/hesapsiz_gun_testi.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Canlı puantaj (son hâli T-94; yalnızca calisilan_gun değişti)
-- ---------------------------------------------------------------------
create or replace view pdks.v_puantaj_canli with (security_invoker = true) as
WITH g AS (
         SELECT g_1.id,
            g_1.calisan_id,
            g_1.is_gunu,
            g_1.vardiya_id,
            g_1.planli_baslangic,
            g_1.planli_bitis,
            g_1.giris_zamani,
            g_1.cikis_zamani,
            g_1.giris_kaynagi,
            g_1.cikis_kaynagi,
            g_1.durum,
            g_1.gec_kalma_dk,
            g_1.erken_cikis_dk,
            g_1.calisma_dk,
            g_1.hesap_tamam,
            g_1.gece_isi_id,
            g_1.guncelleme_zamani,
            g_1.fazla_mesai_dk,
            g_1.fm50_dk,
            g_1.fm100_dk,
            g_1.gece_calisma_dk,
            g_1.saatlik_izin_dk,
            g_1.mola_dk,
            COALESCE(t.esnek, false) AS esnek,
            (COALESCE(t.esnek, false) AND (g_1.durum <> ALL (ARRAY['izinli'::text, 'raporlu'::text, 'tatil'::text, 'vardiya_yok'::text]))) AS esnek_hedefli,
            (ar.tarih IS NOT NULL) AS arife
           FROM pdks.gun_kaydi g_1
             LEFT JOIN pdks.vardiya_tanim t ON t.id = g_1.vardiya_id
             LEFT JOIN pdks.resmi_tatil ar ON ar.tarih = g_1.is_gunu AND ar.yarim_gun AND NOT pdks.fm100_gunu_mu(ar.tarih)
        ), toplam AS (
 SELECT (EXTRACT(year FROM is_gunu))::integer AS yil,
    (EXTRACT(month FROM is_gunu))::integer AS ay,
    calisan_id,
    -- T-91: hesabı tamamlanmamış gün çalışılan sayılmaz (bekleyen_gun'de); kod listesiyle aynı kural
    count(*) FILTER (WHERE ((durum = 'tamam'::text) AND hesap_tamam)) AS calisilan_gun,
    COALESCE(sum(calisma_dk), (0)::bigint) AS calisma_dk,
    COALESCE(sum(gec_kalma_dk), (0)::bigint) AS gec_kalma_dk,
    COALESCE(sum(erken_cikis_dk), (0)::bigint) AS erken_cikis_dk,
    count(*) FILTER (WHERE (durum = 'devamsiz'::text)) AS devamsiz_gun,
    count(*) FILTER (WHERE (durum = 'izinli'::text)) AS izinli_gun,
    count(*) FILTER (WHERE (durum = 'raporlu'::text)) AS raporlu_gun,
    count(*) FILTER (WHERE (durum = 'tatil'::text)) AS tatil_gun,
    count(*) FILTER (WHERE ((durum = ANY (ARRAY['eksik'::text, 'soru_bekliyor'::text, 'devamsiz_suphesi'::text])) OR (NOT hesap_tamam))) AS bekleyen_gun,
    COALESCE(sum(fazla_mesai_dk), (0)::bigint) AS fazla_mesai_dk,
    COALESCE(sum(fm50_dk), (0)::bigint) AS fm50_dk,
    COALESCE(sum(fm100_dk), (0)::bigint) AS fm100_dk,
    COALESCE(sum(gece_calisma_dk), (0)::bigint) AS gece_calisma_dk,
    COALESCE(sum(saatlik_izin_dk), (0)::bigint) AS saatlik_izin_dk,
    COALESCE(sum(mola_dk), (0)::bigint) AS mola_dk,
    (coalesce(sum(pdks.ayar_al('esnek_gunluk_hedef_dk') / case when arife then 2 else 1 end) filter (where esnek_hedefli), 0))::integer AS esnek_hedef_dk,
    ((coalesce(sum(calisma_dk - case when arife then coalesce(fm100_dk, 0) else 0 end) filter (where esnek and durum = 'tamam'), 0) - coalesce(sum(pdks.ayar_al('esnek_gunluk_hedef_dk') / case when arife then 2 else 1 end) filter (where esnek_hedefli), 0)))::integer AS esnek_fark_dk
   FROM g
  GROUP BY ((EXTRACT(year FROM is_gunu))::integer), ((EXTRACT(month FROM is_gunu))::integer), calisan_id
        ), plansiz_izin AS (
 SELECT (EXTRACT(year FROM gun))::integer AS yil,
    (EXTRACT(month FROM gun))::integer AS ay,
    calisan_id,
    count(*) FILTER (WHERE tur <> 'rapor'::text) AS izinli_gun,
    count(*) FILTER (WHERE tur = 'rapor'::text) AS raporlu_gun
   FROM pdks.plansiz_izin_gunleri('-infinity'::date, 'infinity'::date)
  GROUP BY 1, 2, 3
        ), satirlar AS (
 SELECT yil, ay, calisan_id, calisilan_gun, calisma_dk, gec_kalma_dk, erken_cikis_dk, devamsiz_gun,
    izinli_gun, raporlu_gun, tatil_gun, bekleyen_gun, fazla_mesai_dk, fm50_dk, fm100_dk,
    gece_calisma_dk, saatlik_izin_dk, mola_dk, esnek_hedef_dk, esnek_fark_dk
   FROM toplam
UNION ALL
 SELECT yil, ay, calisan_id, 0, 0, 0, 0, 0, izinli_gun, raporlu_gun, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
   FROM plansiz_izin
        )
 SELECT yil, ay, calisan_id,
    (sum(calisilan_gun))::bigint AS calisilan_gun,
    (sum(calisma_dk))::bigint AS calisma_dk,
    (sum(gec_kalma_dk))::bigint AS gec_kalma_dk,
    (sum(erken_cikis_dk))::bigint AS erken_cikis_dk,
    (sum(devamsiz_gun))::bigint AS devamsiz_gun,
    (sum(izinli_gun))::bigint AS izinli_gun,
    (sum(raporlu_gun))::bigint AS raporlu_gun,
    (sum(tatil_gun))::bigint AS tatil_gun,
    (sum(bekleyen_gun))::bigint AS bekleyen_gun,
    (sum(fazla_mesai_dk))::bigint AS fazla_mesai_dk,
    (sum(fm50_dk))::bigint AS fm50_dk,
    (sum(fm100_dk))::bigint AS fm100_dk,
    (sum(gece_calisma_dk))::bigint AS gece_calisma_dk,
    (sum(saatlik_izin_dk))::bigint AS saatlik_izin_dk,
    (sum(mola_dk))::bigint AS mola_dk,
    (sum(esnek_hedef_dk))::integer AS esnek_hedef_dk,
    (sum(esnek_fark_dk))::integer AS esnek_fark_dk
   FROM satirlar
  GROUP BY yil, ay, calisan_id;

-- ---------------------------------------------------------------------
-- 2. Yönetici paneli: departman özeti (yalnızca calisilan_gun değişti)
-- ---------------------------------------------------------------------
create or replace view pdks.v_departman_ozet with (security_invoker = true) as
 WITH gunler AS (
         SELECT (EXTRACT(year FROM g_1.is_gunu))::integer AS yil,
            (EXTRACT(month FROM g_1.is_gunu))::integer AS ay,
            c.departman_id,
            g_1.id,
            g_1.calisan_id,
            g_1.is_gunu,
            g_1.vardiya_id,
            g_1.planli_baslangic,
            g_1.planli_bitis,
            g_1.giris_zamani,
            g_1.cikis_zamani,
            g_1.giris_kaynagi,
            g_1.cikis_kaynagi,
            g_1.durum,
            g_1.gec_kalma_dk,
            g_1.erken_cikis_dk,
            g_1.calisma_dk,
            g_1.hesap_tamam,
            g_1.gece_isi_id,
            g_1.guncelleme_zamani,
            g_1.fazla_mesai_dk
           FROM (pdks.gun_kaydi g_1
             JOIN pdks.calisan c ON ((c.id = g_1.calisan_id)))
        )
 SELECT g.yil,
    g.ay,
    d.id AS departman_id,
    d.ad AS departman,
    count(DISTINCT g.calisan_id) AS calisan_sayisi,
    -- T-91: hesabı tamamlanmamış gün çalışılan sayılmaz (bekleyen_gun'de)
    count(*) FILTER (WHERE ((g.durum = 'tamam'::text) AND g.hesap_tamam)) AS calisilan_gun,
    count(*) FILTER (WHERE (g.durum = 'devamsiz'::text)) AS devamsiz_gun,
    count(*) FILTER (WHERE (g.gec_kalma_dk > 0)) AS gec_kalinan_gun,
    COALESCE(sum(g.gec_kalma_dk), (0)::bigint) AS gec_kalma_dk,
    COALESCE(sum(g.erken_cikis_dk), (0)::bigint) AS erken_cikis_dk,
    COALESCE(sum(g.fazla_mesai_dk), (0)::bigint) AS fazla_mesai_dk,
    count(*) FILTER (WHERE ((g.durum = ANY (ARRAY['eksik'::text, 'soru_bekliyor'::text, 'devamsiz_suphesi'::text])) OR (NOT g.hesap_tamam))) AS bekleyen_gun,
    ( SELECT count(*) AS count
           FROM ((pdks.amir_sorusu q
             JOIN pdks.gun_kaydi g2 ON ((g2.id = q.gun_kaydi_id)))
             JOIN pdks.calisan c2 ON ((c2.id = g2.calisan_id)))
          WHERE ((c2.departman_id = d.id) AND (EXTRACT(year FROM g2.is_gunu) = (g.yil)::numeric) AND (EXTRACT(month FROM g2.is_gunu) = (g.ay)::numeric) AND (q.durum = ANY (ARRAY['acik'::text, 'eskale'::text, 'ik_karari_bekliyor'::text])))) AS acik_soru,
    ( SELECT count(*) AS count
           FROM ((pdks.itiraz i
             JOIN pdks.gun_kaydi g2 ON ((g2.id = i.gun_kaydi_id)))
             JOIN pdks.calisan c2 ON ((c2.id = g2.calisan_id)))
          WHERE ((c2.departman_id = d.id) AND (EXTRACT(year FROM g2.is_gunu) = (g.yil)::numeric) AND (EXTRACT(month FROM g2.is_gunu) = (g.ay)::numeric) AND (i.durum = ANY (ARRAY['acik'::text, 'inceleniyor'::text])))) AS acik_itiraz
   FROM (gunler g
     JOIN pdks.departman d ON ((d.id = g.departman_id)))
  GROUP BY g.yil, g.ay, d.id, d.ad;
