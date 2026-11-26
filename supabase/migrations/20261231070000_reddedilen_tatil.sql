-- =====================================================================
-- K4 · T-102: Reddedilen tatil çalışması puantajda "FM100 1 gün / 0 dk" kodlanıyordu
--
-- Sorun: Yazılı fazla mesai onayı olmayan çalışan Pazar (ya da tam gün resmi tatil) planlıydı ve
-- 08–17 çalıştı. Çalışma havuza düştü, İK reddetti. Gün "tamam" kaldığı için kod listesi bu güne
-- "FM100 1 gün / 0 dk" yazdı, puantaj satırı da günü çalışılan gün saydı. Onaylanan (FM100 1 / 480)
-- ile reddedilen arasındaki tek fark dakikaydı; gün sayısına bakan bordro bu günü tatil mesaisi
-- olarak öder. Karar bekleyen gün (zorla kilitte) de aynı görünüyordu.
--
-- Karar (Yusuf, A seçeneği): tatil gününde "tamam" görünen ama sayılan çalışması 0 dakika olan gün,
-- çalışılmamış tatil gibi kodlanır: tam gün resmi tatilse RT, değilse HT (1 gün / 0 dk) ve çalışılan
-- gün sayılmaz. Planı olmayan günde (T-79) reddedilen çalışma zaten böyle ("vardiya yok" → HT).
-- Kural havuzun durumuna değil günün dakikasına bakar: İK onaylayınca gün yeniden hesaplanır,
-- dakika gelir ve kod kendiliğinden FM100 olur.
-- Bilinçli bedel (T-79 ile aynı): kilitten sonra onaylanırsa kilitli ayda HT kalır; dakika sonraki
-- aya fark satırı olarak gelir (FM100 0 gün / 480 dk), gün sayısı değişmez.
-- Tek kural: pdks.sayilmayan_tatil_calismasi; kod listesi, gün katkısı (kilit ve fark), canlı
-- puantaj ve yönetici paneli aynı fonksiyonu çağırır.
-- Kalıcı test: supabase/tests/reddedilen_tatil_testi.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Tek kural
--    SET'siz SQL fonksiyonu: görünümlerin içine açılır (inline). fm100_gunu_mu yalnızca ilk iki
--    koşul doğruysa (tamam ve 0 dk; seyrek) çağrılır.
-- ---------------------------------------------------------------------
create function pdks.sayilmayan_tatil_calismasi(p_gun date, p_durum text, p_calisma_dk integer)
returns boolean
language sql
stable
as $$
    select p_durum = 'tamam' and coalesce(p_calisma_dk, 0) = 0 and pdks.fm100_gunu_mu(p_gun);
$$;

comment on function pdks.sayilmayan_tatil_calismasi(date, text, integer) is
    'Tatil gününde (fm100_gunu_mu) "tamam" görünen ama sayılan çalışması 0 dk olan gün (havuzda reddedilen ya da karar bekleyen tatil çalışması). Bu gün HT/RT kodlanır, çalışılan gün sayılmaz (T-102).';
-- Görünümler çağıranın yetkisiyle çalıştığı için gerekir (yalnızca takvimi okur)
revoke execute on function pdks.sayilmayan_tatil_calismasi(date, text, integer) from public, anon;
grant execute on function pdks.sayilmayan_tatil_calismasi(date, text, integer) to authenticated;

-- ---------------------------------------------------------------------
-- 2. Gün kodları (son hâli T-79): sayılmayan tatil çalışması "vardiya yok" günüyle aynı kodlanır
-- ---------------------------------------------------------------------
create or replace function pdks.gun_kod_satirlari(p_calisan_id bigint, p_gun date, p_durum text, p_calisma_dk integer, p_fm50_dk integer, p_fm100_dk integer)
returns TABLE(kod text, gun numeric, dakika integer)
language plpgsql
stable
set search_path = pdks
as $$
declare
    v_izin text;
begin
    if p_durum is null or p_durum = 'vardiya_yok'
       -- T-102: reddedilen ya da karar bekleyen tatil çalışması (0 dk) FM100 değil, HT / RT'dir
       or pdks.sayilmayan_tatil_calismasi(p_gun, p_durum, p_calisma_dk) then
        return query select case when exists (select 1 from pdks.resmi_tatil r where r.tarih = p_gun and not r.yarim_gun)
                                 then 'RT' else 'HT' end, 1::numeric, 0;
    elsif p_durum = 'tatil' then
        return query select 'RT'::text, 1::numeric, 0;
    elsif p_durum = 'raporlu' then
        return query select 'RPR'::text, 1::numeric, 0;
    elsif p_durum = 'devamsiz' then
        return query select 'DVMSZ'::text, 1::numeric, 0;
    elsif p_durum = 'izinli' then
        select i.tur into v_izin from pdks.izin i
        where i.calisan_id = p_calisan_id and p_gun between i.baslangic and i.bitis and i.iptal_zamani is null
        order by i.id limit 1;
        return query select case v_izin when 'yillik' then 'Yİ' when 'mazeret' then 'MZR'
                                        when 'ucretsiz' then 'ÜCSZ' when 'rapor' then 'RPR' else 'Dİ' end,
                            1::numeric, 0;
    elsif p_durum = 'tamam' then
        if pdks.fm100_gunu_mu(p_gun) then
            return query select 'FM100'::text, 1::numeric, coalesce(p_fm100_dk, 0);
        elsif coalesce(p_fm50_dk, 0) > 0 and coalesce(p_fm100_dk, 0) = 0
              and exists (select 1 from pdks.gun_kaydi g
                          where g.calisan_id = p_calisan_id and g.is_gunu = p_gun and g.vardiya_id is null) then
            -- Onaylanan plansız gün (T-79), tatil değil: gün FM50 günüdür
            return query select 'FM50'::text, 1::numeric, p_fm50_dk;
        elsif coalesce(p_fm100_dk, 0) > 0
              and coalesce(p_calisma_dk, 0) = coalesce(p_fm50_dk, 0) + p_fm100_dk then
            -- Arifede 13:00'ten sonraki vardiya ya da tatildeki plansız gün (T-79): gün FM100 günüdür
            return query select 'FM100'::text, 1::numeric, p_fm100_dk;
            if coalesce(p_fm50_dk, 0) <> 0 then
                return query select 'FM50'::text, 0::numeric, p_fm50_dk;
            end if;
        else
            -- Arifede FM100, normal çalışmayla aynı gündedir
            return query select 'NÇ'::text, 1::numeric,
                                coalesce(p_calisma_dk, 0) - coalesce(p_fm50_dk, 0) - coalesce(p_fm100_dk, 0);
            if coalesce(p_fm100_dk, 0) <> 0 then
                return query select 'FM100'::text, 0::numeric, p_fm100_dk;
            end if;
            if coalesce(p_fm50_dk, 0) <> 0 then
                return query select 'FM50'::text, 0::numeric, p_fm50_dk;
            end if;
        end if;
    end if;
end;
$$;


-- ---------------------------------------------------------------------
-- 3. Gün katkısı (son hâli T-79; kilitli puantaj ve fark satırı bunu kullanır):
--    sayılmayan tatil çalışması çalışılan gün değildir
-- ---------------------------------------------------------------------
create or replace function pdks.gun_katkisi(p_gun_kaydi_id bigint, p_duzeltmeler bigint[], out calisilan_gun numeric, out calisma_dk integer, out gec_kalma_dk integer, out erken_cikis_dk integer, out devamsiz_gun numeric, out izinli_gun numeric, out raporlu_gun numeric, out tatil_gun numeric, out fazla_mesai_dk integer, out fm50_dk integer, out fm100_dk integer, out gece_calisma_dk integer, out saatlik_izin_dk integer, out durum text, out mola_dk integer, out esnek_hedef_dk integer, out esnek_fark_dk integer)
returns record
language plpgsql
stable
set search_path = pdks
as $$
declare
    g        pdks.gun_kaydi;
    d        record;
    v_durum_duzeltildi boolean := false;
    v_ara    record;
    v_esnek  boolean;
    h        record;
begin
    select * into g from pdks.gun_kaydi where id = p_gun_kaydi_id;

    for d in select * from pdks.duzeltme where id = any (coalesce(p_duzeltmeler, '{}')) order by id loop
        case d.alan
            when 'giris_zamani' then g.giris_zamani := d.yeni_deger::timestamptz;
            when 'cikis_zamani' then g.cikis_zamani := d.yeni_deger::timestamptz;
            when 'durum'        then g.durum := d.yeni_deger; v_durum_duzeltildi := true;
            when 'vardiya_id'   then
                g.vardiya_id := d.yeni_deger::smallint;
                select * into v_ara from pdks.vardiya_araligi(g.vardiya_id, g.is_gunu);
                g.planli_baslangic := v_ara.p_bas;
                g.planli_bitis := v_ara.p_bit;
        end case;
    end loop;

    if not v_durum_duzeltildi and coalesce(array_length(p_duzeltmeler, 1), 0) > 0
       and g.durum in ('eksik', 'soru_bekliyor', 'devamsiz_suphesi')
       and g.giris_zamani is not null and g.cikis_zamani is not null then
        g.durum := 'tamam';
    end if;

    durum         := g.durum;
    calisilan_gun := case when g.durum = 'tamam'    then 1 else 0 end;
    devamsiz_gun  := case when g.durum = 'devamsiz' then 1 else 0 end;
    izinli_gun    := case when g.durum = 'izinli'   then 1 else 0 end;
    raporlu_gun   := case when g.durum = 'raporlu'  then 1 else 0 end;
    tatil_gun     := case when g.durum = 'tatil'    then 1 else 0 end;

    if g.durum = 'tamam' and g.giris_zamani is not null and g.cikis_zamani is not null
       and (g.planli_baslangic is not null or g.vardiya_id is null) then
        select * into h from pdks.gun_hesabi(g.calisan_id, g.is_gunu, g.planli_baslangic, g.planli_bitis,
                                              g.giris_zamani, g.cikis_zamani, g.vardiya_id);
        calisma_dk := h.calisma_dk; gec_kalma_dk := h.gec_kalma_dk;
        erken_cikis_dk := h.erken_cikis_dk; fazla_mesai_dk := h.fazla_mesai_dk;
        fm50_dk := h.fm50_dk; fm100_dk := h.fm100_dk;
        gece_calisma_dk := h.gece_calisma_dk; saatlik_izin_dk := h.saatlik_izin_dk; mola_dk := h.mola_dk;
    else
        calisma_dk := 0; gec_kalma_dk := 0; erken_cikis_dk := 0; fazla_mesai_dk := 0;
        fm50_dk := 0; fm100_dk := 0; gece_calisma_dk := 0; saatlik_izin_dk := 0; mola_dk := 0;
    end if;

    -- T-102: reddedilen ya da karar bekleyen tatil çalışması (0 dk) çalışılan gün değildir (kod HT / RT)
    if pdks.sayilmayan_tatil_calismasi(g.is_gunu, g.durum, calisma_dk) then
        calisilan_gun := 0;
    end if;

    select t.esnek into v_esnek from pdks.vardiya_tanim t where t.id = g.vardiya_id;
    if coalesce(v_esnek, false) and g.durum not in ('izinli', 'raporlu', 'tatil', 'vardiya_yok') then
        esnek_hedef_dk := pdks.ayar_al('esnek_gunluk_hedef_dk')
                          / case when pdks.arife_siniri(g.is_gunu) is not null then 2 else 1 end;
    else
        esnek_hedef_dk := 0;
    end if;
    esnek_fark_dk := case when coalesce(v_esnek, false)
                           then calisma_dk - case when pdks.arife_siniri(g.is_gunu) is not null then fm100_dk else 0 end
                           else 0 end - esnek_hedef_dk;
end;
$$;


-- ---------------------------------------------------------------------
-- 4. Canlı puantaj (son hâli T-91; yalnızca calisilan_gun değişti)
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
    -- T-102: reddedilen ya da karar bekleyen tatil çalışması (0 dk) da sayılmaz (kod HT / RT)
    count(*) FILTER (WHERE ((durum = 'tamam'::text) AND hesap_tamam
                            AND NOT pdks.sayilmayan_tatil_calismasi(is_gunu, durum, calisma_dk))) AS calisilan_gun,
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
-- 5. Yönetici paneli: departman özeti (son hâli T-91; yalnızca calisilan_gun değişti)
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
    -- T-102: reddedilen ya da karar bekleyen tatil çalışması (0 dk) da sayılmaz (kod HT / RT)
    count(*) FILTER (WHERE ((g.durum = 'tamam'::text) AND g.hesap_tamam
                            AND NOT pdks.sayilmayan_tatil_calismasi(g.is_gunu, g.durum, g.calisma_dk))) AS calisilan_gun,
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
