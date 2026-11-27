-- =====================================================================
-- K4 · T-64, T-77, T-78: Fazla mesai kuralları için kararlar (Mehmet, 27.11.2026)
--
-- T-64 · Günlük 11 saat sınırı net çalışmaya uygulanır.
--   İş Kanunu m.63'teki 11 saat çalışma süresidir; m.68'e göre ara dinlenme bu süreye sayılmaz.
--   Önceki ölçü mola dahil brüt süreydi (GÜNDÜZ 540 + 120 = 660). Şimdi brüt süreden mola düşülür:
--   GÜNDÜZ'e 180 dk plan kabul (720 brüt − 60 mola = 660 net), 181 dk ret. Üç yerde aynı ölçü:
--   plan talebi (fm_plan_denetle), havuz onayı (fazla_mesai_inceleme_karar, T-58) ve
--   gece işinin günlük sınır uyarısı (gece_isi_uyarilar).
--
-- T-77 · Eşik altı plansız çalışma kaybolmaz.
--   fm_plansiz_esik_dk (15 dk) yalnızca havuza düşme eşiğidir. Altındaki onaysız süre artık
--   gun_kaydi.esik_alti_dk'ya yazılır, v_puantaj_canli'da ve kilitli puantaj satırında
--   (puantaj_satiri.esik_alti_dk) ay toplamı olarak görünür. Fazla mesaiye eklenmez (İK onayı yok);
--   sistem ücret hesaplamaz, yuvarlama ve ücrete etkisi bordro / ERP tarafındadır.
--   Alanı yalnızca tetikleyici yazar (elle değiştirilemez). Kilitli aya sonradan gelen düzeltmenin
--   eşik altı farkı fark satırına yazılmaz (bilgi alanı; fazla mesai farkları yazılmaya devam eder).
--
-- T-78 · Hafta tatili ve resmî tatil çalışması İK onayına bağlanır.
--   Önceden yazılı onayı olan çalışanın Pazar vardiyası amirin planıyla doğrudan FM100 oluyordu.
--   Şimdi yazılı onay gerekli ama yeterli değil, İK onayı da aranır. İki yolu var:
--     * Önceden: İK o gün için fazla mesai planını onaylamışsa günü onaylamış olur;
--       vardiya + plan FM100 sayılır, planı aşan kısım havuza düşer.
--     * Sonradan: plan yoksa çalışmanın tamamı havuza "tatil_calismasi" olarak düşer;
--       İK onaylayınca FM100 olur ve yıllık sınıra sayılır.
--   Arife öğleden sonrası (T-28) değişmedi: yazılı onaylı çalışan için vardiyanın kendisidir.
--
-- Kalıcı test: supabase/tests/fazla_mesai_kararlari_testi.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- T-77: yeni alanlar
-- ---------------------------------------------------------------------
alter table pdks.gun_kaydi
    add column esik_alti_dk integer not null default 0,
    add constraint gun_kaydi_esik_alti_dk_check check (esik_alti_dk >= 0);
comment on column pdks.gun_kaydi.esik_alti_dk is
    'Havuz eşiğinin (fm_plansiz_esik_dk) altında kalan onaysız çalışma, dakika. Bilgi alanı: fazla mesaiye eklenmez; tetikleyici yazar (T-77).';

alter table pdks.puantaj_satiri
    add column esik_alti_dk integer not null default 0;
comment on column pdks.puantaj_satiri.esik_alti_dk is
    'Ayın eşik altı onaysız çalışma toplamı, dakika (T-77). Normal satırda dolar; fark satırında 0.';

-- Eşik altı süreyi gün hesabıyla aynı anda yazar. Hesap alanlarından biri değişmediyse
-- eski değeri korur: alan elle değiştirilemez.
create function pdks.gun_kaydi_esik_alti()
returns trigger
language plpgsql
set search_path = pdks
as $$
declare
    v_dk integer := 0;
begin
    if tg_op = 'UPDATE'
       and (new.hesap_tamam, new.durum, new.giris_zamani, new.cikis_zamani, new.vardiya_id,
            new.planli_baslangic, new.planli_bitis, new.calisma_dk, new.fm50_dk, new.fm100_dk)
           is not distinct from
           (old.hesap_tamam, old.durum, old.giris_zamani, old.cikis_zamani, old.vardiya_id,
            old.planli_baslangic, old.planli_bitis, old.calisma_dk, old.fm50_dk, old.fm100_dk) then
        new.esik_alti_dk := old.esik_alti_dk;
        return new;
    end if;

    if new.hesap_tamam and new.giris_zamani is not null and new.cikis_zamani is not null
       and (new.durum = 'tamam' or (new.durum = 'vardiya_yok' and new.vardiya_id is null)) then
        select h.onaysiz_fm_dk into v_dk
        from pdks.gun_hesabi(new.calisan_id, new.is_gunu, new.planli_baslangic, new.planli_bitis,
                             new.giris_zamani, new.cikis_zamani, new.vardiya_id) h;
        if coalesce(v_dk, 0) > pdks.ayar_al('fm_plansiz_esik_dk') then
            v_dk := 0;   -- eşiği aşan süre havuza düşer
        end if;
    end if;
    new.esik_alti_dk := coalesce(v_dk, 0);
    return new;
end;
$$;
revoke execute on function pdks.gun_kaydi_esik_alti() from public;

create trigger gun_kaydi_esik_alti
    before insert or update on pdks.gun_kaydi
    for each row execute function pdks.gun_kaydi_esik_alti();

-- T-77: ay toplamı (sona bir sütun eklendi; geri kalanı 20261231070000'daki tanımla aynı)
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
            g_1.esik_alti_dk,
            COALESCE(t.esnek, false) AS esnek,
            (COALESCE(t.esnek, false) AND (g_1.durum <> ALL (ARRAY['izinli'::text, 'raporlu'::text, 'tatil'::text, 'vardiya_yok'::text]))) AS esnek_hedefli,
            (ar.tarih IS NOT NULL) AS arife
           FROM ((pdks.gun_kaydi g_1
             LEFT JOIN pdks.vardiya_tanim t ON ((t.id = g_1.vardiya_id)))
             LEFT JOIN pdks.resmi_tatil ar ON (((ar.tarih = g_1.is_gunu) AND ar.yarim_gun AND (NOT pdks.fm100_gunu_mu(ar.tarih)))))
        ), toplam AS (
         SELECT (EXTRACT(year FROM g.is_gunu))::integer AS yil,
            (EXTRACT(month FROM g.is_gunu))::integer AS ay,
            g.calisan_id,
            count(*) FILTER (WHERE ((g.durum = 'tamam'::text) AND g.hesap_tamam AND (NOT pdks.sayilmayan_tatil_calismasi(g.is_gunu, g.durum, g.calisma_dk)))) AS calisilan_gun,
            COALESCE(sum(g.calisma_dk), (0)::bigint) AS calisma_dk,
            COALESCE(sum(g.gec_kalma_dk), (0)::bigint) AS gec_kalma_dk,
            COALESCE(sum(g.erken_cikis_dk), (0)::bigint) AS erken_cikis_dk,
            count(*) FILTER (WHERE (g.durum = 'devamsiz'::text)) AS devamsiz_gun,
            count(*) FILTER (WHERE (g.durum = 'izinli'::text)) AS izinli_gun,
            count(*) FILTER (WHERE (g.durum = 'raporlu'::text)) AS raporlu_gun,
            count(*) FILTER (WHERE (g.durum = 'tatil'::text)) AS tatil_gun,
            count(*) FILTER (WHERE ((g.durum = ANY (ARRAY['eksik'::text, 'soru_bekliyor'::text, 'devamsiz_suphesi'::text])) OR (NOT g.hesap_tamam))) AS bekleyen_gun,
            COALESCE(sum(g.fazla_mesai_dk), (0)::bigint) AS fazla_mesai_dk,
            COALESCE(sum(g.fm50_dk), (0)::bigint) AS fm50_dk,
            COALESCE(sum(g.fm100_dk), (0)::bigint) AS fm100_dk,
            COALESCE(sum(g.gece_calisma_dk), (0)::bigint) AS gece_calisma_dk,
            COALESCE(sum(g.saatlik_izin_dk), (0)::bigint) AS saatlik_izin_dk,
            COALESCE(sum(g.mola_dk), (0)::bigint) AS mola_dk,
            COALESCE(sum(g.esik_alti_dk), (0)::bigint) AS esik_alti_dk,
            (COALESCE(sum((pdks.ayar_al('esnek_gunluk_hedef_dk'::text) /
                CASE
                    WHEN g.arife THEN 2
                    ELSE 1
                END)) FILTER (WHERE g.esnek_hedefli), (0)::bigint))::integer AS esnek_hedef_dk,
            ((COALESCE(sum((g.calisma_dk -
                CASE
                    WHEN g.arife THEN COALESCE(g.fm100_dk, 0)
                    ELSE 0
                END)) FILTER (WHERE (g.esnek AND (g.durum = 'tamam'::text))), (0)::bigint) - COALESCE(sum((pdks.ayar_al('esnek_gunluk_hedef_dk'::text) /
                CASE
                    WHEN g.arife THEN 2
                    ELSE 1
                END)) FILTER (WHERE g.esnek_hedefli), (0)::bigint)))::integer AS esnek_fark_dk
           FROM g
          GROUP BY ((EXTRACT(year FROM g.is_gunu))::integer), ((EXTRACT(month FROM g.is_gunu))::integer), g.calisan_id
        ), plansiz_izin AS (
         SELECT (EXTRACT(year FROM plansiz_izin_gunleri.gun))::integer AS yil,
            (EXTRACT(month FROM plansiz_izin_gunleri.gun))::integer AS ay,
            plansiz_izin_gunleri.calisan_id,
            count(*) FILTER (WHERE (plansiz_izin_gunleri.tur <> 'rapor'::text)) AS izinli_gun,
            count(*) FILTER (WHERE (plansiz_izin_gunleri.tur = 'rapor'::text)) AS raporlu_gun
           FROM pdks.plansiz_izin_gunleri('-infinity'::date, 'infinity'::date) plansiz_izin_gunleri(calisan_id, gun, tur)
          GROUP BY ((EXTRACT(year FROM plansiz_izin_gunleri.gun))::integer), ((EXTRACT(month FROM plansiz_izin_gunleri.gun))::integer), plansiz_izin_gunleri.calisan_id
        ), satirlar AS (
         SELECT toplam.yil,
            toplam.ay,
            toplam.calisan_id,
            toplam.calisilan_gun,
            toplam.calisma_dk,
            toplam.gec_kalma_dk,
            toplam.erken_cikis_dk,
            toplam.devamsiz_gun,
            toplam.izinli_gun,
            toplam.raporlu_gun,
            toplam.tatil_gun,
            toplam.bekleyen_gun,
            toplam.fazla_mesai_dk,
            toplam.fm50_dk,
            toplam.fm100_dk,
            toplam.gece_calisma_dk,
            toplam.saatlik_izin_dk,
            toplam.mola_dk,
            toplam.esnek_hedef_dk,
            toplam.esnek_fark_dk,
            toplam.esik_alti_dk
           FROM toplam
        UNION ALL
         SELECT plansiz_izin.yil,
            plansiz_izin.ay,
            plansiz_izin.calisan_id,
            0,
            0,
            0,
            0,
            0,
            plansiz_izin.izinli_gun,
            plansiz_izin.raporlu_gun,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0
           FROM plansiz_izin
        )
 SELECT yil,
    ay,
    calisan_id,
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
    (sum(esnek_fark_dk))::integer AS esnek_fark_dk,
    (sum(esik_alti_dk))::bigint AS esik_alti_dk
   FROM satirlar
  GROUP BY yil, ay, calisan_id;

-- T-77: kilitli puantajın normal satırına eşik altı toplam
CREATE OR REPLACE FUNCTION pdks.puantaj_yaz(p_donem_id bigint)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'pdks'
AS $function$
declare
    v_donem  pdks.donem;
    v_say    integer := 0;
    v_n      integer;
begin
    select * into v_donem from pdks.donem where id = p_donem_id;
    if v_donem.durum is distinct from 'kilitli' then
        raise exception 'Puantaj yalnızca kilitlenmiş döneme yazılır.';
    end if;

    insert into pdks.puantaj_satiri (donem_id, calisan_id, satir_turu, calisilan_gun, calisma_dk, gec_kalma_dk,
                                     erken_cikis_dk, devamsiz_gun, izinli_gun, raporlu_gun, tatil_gun, fazla_mesai_dk,
                                     fm50_dk, fm100_dk, gece_calisma_dk, saatlik_izin_dk,
                                     mola_dk, esnek_hedef_dk, esnek_fark_dk, esik_alti_dk)
    select p_donem_id, v.calisan_id, 'normal', v.calisilan_gun, v.calisma_dk, v.gec_kalma_dk,
           v.erken_cikis_dk, v.devamsiz_gun, v.izinli_gun, v.raporlu_gun, v.tatil_gun, v.fazla_mesai_dk,
           v.fm50_dk, v.fm100_dk, v.gece_calisma_dk, v.saatlik_izin_dk,
           v.mola_dk, v.esnek_hedef_dk, v.esnek_fark_dk,
           v.esik_alti_dk   -- T-77: eşik altı plansız çalışma (bilgi; fazla mesaiye eklenmez)
    from pdks.v_puantaj_canli v
    where v.yil = v_donem.yil and v.ay = v_donem.ay;
    get diagnostics v_n = row_count;
    v_say := v_say + v_n;

    insert into pdks.puantaj_kalemi (puantaj_satiri_id, kod, gun, dakika)
    select s.id, k.kod, sum(k.gun), sum(k.dakika)
    from pdks.gun_kodlari_hesapla(v_donem.yil, v_donem.ay) k
    join pdks.puantaj_satiri s
      on s.donem_id = p_donem_id and s.calisan_id = k.calisan_id and s.satir_turu = 'normal'
    group by s.id, k.kod;

    with gunler as (
        select d.gun_kaydi_id,
               array_agg(d.id order by d.id) as bu_donem,
               (select coalesce(array_agg(o.id order by o.id), '{}')
                from pdks.duzeltme o
                where o.gun_kaydi_id = d.gun_kaydi_id and o.fark_satiri and o.hedef_donem_id <> p_donem_id
                  and o.id < max(d.id)) as onceki
        from pdks.duzeltme d
        where d.hedef_donem_id = p_donem_id and d.fark_satiri
        group by d.gun_kaydi_id
    ), gun_durumlari as (
        select g.calisan_id, g.is_gunu,
               pdks.donem_bul(date_trunc('month', g.is_gunu)::date) as kaynak_donem_id,
               o as once, s as sonra
        from gunler x
        join pdks.gun_kaydi g on g.id = x.gun_kaydi_id
        cross join lateral pdks.gun_katkisi(x.gun_kaydi_id, x.onceki) o
        cross join lateral pdks.gun_katkisi(x.gun_kaydi_id, x.onceki || x.bu_donem) s
    ), havuz as (
        select i.*, pdks.donem_bul(date_trunc('month', i.is_gunu)::date) as kaynak_donem_id
        from pdks.fazla_mesai_inceleme i
        where i.hedef_donem_id = p_donem_id and i.fark_satiri and i.durum = 'onaylandi'
    ), farklar as (
        select calisan_id, kaynak_donem_id,
               (sonra).calisilan_gun - (once).calisilan_gun     as calisilan_gun,
               (sonra).calisma_dk - (once).calisma_dk           as calisma_dk,
               (sonra).gec_kalma_dk - (once).gec_kalma_dk       as gec_kalma_dk,
               (sonra).erken_cikis_dk - (once).erken_cikis_dk   as erken_cikis_dk,
               (sonra).devamsiz_gun - (once).devamsiz_gun       as devamsiz_gun,
               (sonra).izinli_gun - (once).izinli_gun           as izinli_gun,
               (sonra).raporlu_gun - (once).raporlu_gun         as raporlu_gun,
               (sonra).tatil_gun - (once).tatil_gun             as tatil_gun,
               (sonra).fazla_mesai_dk - (once).fazla_mesai_dk   as fazla_mesai_dk,
               (sonra).fm50_dk - (once).fm50_dk                 as fm50_dk,
               (sonra).fm100_dk - (once).fm100_dk               as fm100_dk,
               (sonra).gece_calisma_dk - (once).gece_calisma_dk as gece_calisma_dk,
               (sonra).saatlik_izin_dk - (once).saatlik_izin_dk as saatlik_izin_dk,
               (sonra).mola_dk - (once).mola_dk                 as mola_dk,
               (sonra).esnek_hedef_dk - (once).esnek_hedef_dk   as esnek_hedef_dk,
               (sonra).esnek_fark_dk - (once).esnek_fark_dk     as esnek_fark_dk
        from gun_durumlari
        union all
        select calisan_id, kaynak_donem_id, 0, calisma_etki_dk, 0, 0, 0, 0, 0, 0,
               fm50_etki_dk + fm100_etki_dk, fm50_etki_dk, fm100_etki_dk, gece_etki_dk, 0, 0, 0, 0
        from havuz
    ), kod_farklari as (
        select calisan_id, kaynak_donem_id, kod, sum(gun) as gun, sum(dakika) as dakika
        from (
            select d.calisan_id, d.kaynak_donem_id, k.kod, k.gun, k.dakika
            from gun_durumlari d
            cross join lateral pdks.gun_kod_satirlari(d.calisan_id, d.is_gunu, (d.sonra).durum,
                                                      (d.sonra).calisma_dk, (d.sonra).fm50_dk, (d.sonra).fm100_dk) k
            union all
            select d.calisan_id, d.kaynak_donem_id, k.kod, -k.gun, -k.dakika
            from gun_durumlari d
            cross join lateral pdks.gun_kod_satirlari(d.calisan_id, d.is_gunu, (d.once).durum,
                                                      (d.once).calisma_dk, (d.once).fm50_dk, (d.once).fm100_dk) k
            union all
            select calisan_id, kaynak_donem_id, 'FM50', 0, fm50_etki_dk from havuz where fm50_etki_dk <> 0
            union all
            select calisan_id, kaynak_donem_id, 'FM100', 0, fm100_etki_dk from havuz where fm100_etki_dk <> 0
        ) x
        group by calisan_id, kaynak_donem_id, kod
        having sum(gun) <> 0 or sum(dakika) <> 0
    ), yeni as (
        insert into pdks.puantaj_satiri (donem_id, calisan_id, satir_turu, kaynak_donem_id, calisilan_gun, calisma_dk,
                                         gec_kalma_dk, erken_cikis_dk, devamsiz_gun, izinli_gun, raporlu_gun,
                                         tatil_gun, fazla_mesai_dk, fm50_dk, fm100_dk, gece_calisma_dk, saatlik_izin_dk,
                                         mola_dk, esnek_hedef_dk, esnek_fark_dk)
        select p_donem_id, calisan_id, 'fark', kaynak_donem_id,
               sum(calisilan_gun), sum(calisma_dk), sum(gec_kalma_dk), sum(erken_cikis_dk), sum(devamsiz_gun),
               sum(izinli_gun), sum(raporlu_gun), sum(tatil_gun), sum(fazla_mesai_dk),
               sum(fm50_dk), sum(fm100_dk), sum(gece_calisma_dk), sum(saatlik_izin_dk),
               sum(mola_dk), sum(esnek_hedef_dk), sum(esnek_fark_dk)
        from farklar
        group by calisan_id, kaynak_donem_id
        having sum(abs(calisilan_gun)) + sum(abs(calisma_dk)) + sum(abs(gec_kalma_dk)) + sum(abs(erken_cikis_dk))
             + sum(abs(devamsiz_gun)) + sum(abs(izinli_gun)) + sum(abs(raporlu_gun)) + sum(abs(tatil_gun))
             + sum(abs(fazla_mesai_dk)) + sum(abs(gece_calisma_dk)) + sum(abs(saatlik_izin_dk))
             + sum(abs(mola_dk)) + sum(abs(esnek_hedef_dk)) + sum(abs(esnek_fark_dk)) > 0
        returning id, calisan_id, kaynak_donem_id
    ), kalemler as (
        insert into pdks.puantaj_kalemi (puantaj_satiri_id, kod, gun, dakika)
        select y.id, k.kod, k.gun, k.dakika
        from yeni y
        join kod_farklari k on k.calisan_id = y.calisan_id and k.kaynak_donem_id = y.kaynak_donem_id
        returning 1
    )
    select count(*) into v_n from yeni;
    v_say := v_say + v_n;

    return v_say;
end;
$function$

;

-- T-64: plan talebi net çalışmayla denetlenir
CREATE OR REPLACE FUNCTION pdks.fm_plan_denetle(p_calisan_id bigint, p_is_gunu date, p_vardiya_id smallint, p_planli_dk integer, p_plan_id bigint)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'pdks'
AS $function$
declare
    v_gunluk  integer;
    v_toplam  integer;
    v_sinir   integer := pdks.ayar_al('fm_yillik_sinir_dk');
begin
    -- Aynı çalışan için iki onay aynı anda gelirse ikisi de sınırı göremeden geçmesin:
    -- çalışan satırını kilitleyerek işlemleri sıraya sokarız.
    perform 1 from pdks.calisan where id = p_calisan_id for update;

    if not pdks.fm_onay_gecerli_mi(p_calisan_id, p_is_gunu) then
        raise exception 'Çalışanın % günü için geçerli yazılı fazla mesai onayı yok.', p_is_gunu;
    end if;

    if (select gece_yarisini_asar from pdks.vardiya_tanim where id = p_vardiya_id) then
        raise exception 'Gece vardiyası için fazla mesai planlanamaz (İş Kanunu m. 69).';
    end if;

    -- T-64: 11 saat net çalışmadır; ara dinlenme sayılmaz (İş K. m.63, m.68)
    v_gunluk := pdks.vardiya_suresi_dk(p_vardiya_id) + p_planli_dk;
    v_gunluk := v_gunluk - pdks.mola_suresi(v_gunluk);
    if v_gunluk > pdks.ayar_al('gunluk_azami_calisma_dk') then
        raise exception 'Günlük net çalışma süresi (mola hariç) % olur; sınır %.',
            pdks.sure_metni(v_gunluk), pdks.sure_metni(pdks.ayar_al('gunluk_azami_calisma_dk'));
    end if;

    -- Denetlenen plan henüz 'talep' olduğu için toplama girmez
    v_toplam := pdks.fm_yillik_toplam(p_calisan_id, extract(year from p_is_gunu)::integer);

    if v_toplam + p_planli_dk > v_sinir then
        raise exception 'Yıllık fazla mesai sınırı aşılıyor. Kalan süre: %.', pdks.sure_metni(greatest(v_sinir - v_toplam, 0)::integer);
    end if;
    return v_toplam + p_planli_dk;
end;
$function$

;

-- T-64: havuz onayında net çalışma
CREATE OR REPLACE FUNCTION pdks.fazla_mesai_inceleme_karar(p_inceleme_id bigint, p_onay boolean, p_aciklama text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pdks'
AS $function$
declare
    v_ben     bigint := pdks.yetki_gerekli('ik');
    v_kayit   pdks.fazla_mesai_inceleme;
    g         pdks.gun_kaydi;
    v_once    record;
    v_sonra   record;
    v_kilitli boolean;
    v_onaysiz boolean;
    v_toplam  integer;
    v_gunluk  integer;
begin
    select * into v_kayit from pdks.fazla_mesai_inceleme where id = p_inceleme_id for update;
    if not found then
        raise exception 'İnceleme kaydı bulunamadı.';
    end if;
    if v_kayit.durum <> 'inceleme_bekliyor' then
        raise exception 'Bu kayıt zaten karara bağlanmış.';
    end if;
    if p_onay is null then
        raise exception 'Karar (onay / ret) belirtilmeli.';
    end if;

    if not p_onay then
        if p_aciklama is null or length(trim(p_aciklama)) < 5 then
            raise exception 'Ret gerekçesi yazılmalı (en az 5 karakter).';
        end if;
        update pdks.fazla_mesai_inceleme
        set durum = 'reddedildi', karar_veren_id = v_ben, karar_aciklama = trim(p_aciklama)
        where id = p_inceleme_id;
        return;
    end if;

    select * into g from pdks.gun_kaydi where id = v_kayit.gun_kaydi_id;
    -- Aynı çalışanın iki onayı aynı anda gelirse toplamı sırayla görsünler (fm_plan_denetle de kilitler)
    perform 1 from pdks.calisan where id = g.calisan_id for update;
    v_onaysiz := not pdks.fm_onay_gecerli_mi(g.calisan_id, g.is_gunu);
    select * into v_once from pdks.gun_hesabi(g.calisan_id, g.is_gunu, g.planli_baslangic, g.planli_bitis,
                                              g.giris_zamani, g.cikis_zamani);
    if pdks.donem_kilitli_mi(g.is_gunu) and v_kayit.tur = 'tatil_calismasi' then
        -- Yazılı onay kilitten sonra girildiyse gun_hesabi tatil çalışmasını artık "önce"de de sayar;
        -- kilitli puantaja giren, gün kaydındaki eski dakikalardır
        v_once.fm50_dk         := coalesce(g.fm50_dk, 0);
        v_once.fm100_dk        := coalesce(g.fm100_dk, 0);
        v_once.calisma_dk      := coalesce(g.calisma_dk, 0);
        v_once.gece_calisma_dk := coalesce(g.gece_calisma_dk, 0);
    end if;
    update pdks.fazla_mesai_inceleme
    set durum = 'onaylandi', karar_veren_id = v_ben, karar_aciklama = nullif(trim(p_aciklama), ''),
        yazili_onaysiz = v_onaysiz
    where id = p_inceleme_id;
    select * into v_sonra from pdks.gun_hesabi(g.calisan_id, g.is_gunu, g.planli_baslangic, g.planli_bitis,
                                               g.giris_zamani, g.cikis_zamani);

    v_kilitli := pdks.donem_kilitli_mi(g.is_gunu);
    update pdks.fazla_mesai_inceleme
    set fm50_etki_dk    = v_sonra.fm50_dk - v_once.fm50_dk,
        fm100_etki_dk   = v_sonra.fm100_dk - v_once.fm100_dk,
        calisma_etki_dk = v_sonra.calisma_dk - v_once.calisma_dk,
        gece_etki_dk    = v_sonra.gece_calisma_dk - v_once.gece_calisma_dk,
        fark_satiri     = v_kilitli,
        hedef_donem_id  = pdks.hedef_donem(g.is_gunu)
    where id = p_inceleme_id;

    if not v_kilitli then
        perform pdks.gun_hesabini_yenile(g.id);
    end if;

    if v_onaysiz then
        perform pdks.uyari_yaz('yazili_onay_eksik', 'havuz:' || p_inceleme_id,
            format('%s için %s tarihli fazla mesai yazılı onay olmadan yapılmıştır; yazılı onay alınmalıdır.',
                   (select ad || ' ' || soyad from pdks.calisan where id = g.calisan_id), to_char(g.is_gunu, 'DD.MM.YYYY')),
            g.calisan_id);
    end if;

    -- T-58: Günlük sınır da havuzda ret sebebi değildir (iş yapılmıştır): kayıt işaretlenir, İK'ya bildirilir.
    -- Ölçü plan yoluyla aynı: net çalışma (mola hariç, T-64), onaylanan hâliyle.
    v_gunluk := coalesce(v_sonra.calisma_dk, 0);
    if v_gunluk > pdks.ayar_al('gunluk_azami_calisma_dk') then
        update pdks.fazla_mesai_inceleme set gunluk_sinir_asildi = true where id = p_inceleme_id;
        perform pdks.uyari_yaz('fm_gunluk_sinir_asildi', 'havuz:' || p_inceleme_id,
            format('%s için %s tarihli %s net çalışma (mola hariç) onaylandı; günlük sınır %s (İş Kanunu m.63).',
                   (select ad || ' ' || soyad from pdks.calisan where id = g.calisan_id), to_char(g.is_gunu, 'DD.MM.YYYY'),
                   pdks.sure_metni(v_gunluk), pdks.sure_metni(pdks.ayar_al('gunluk_azami_calisma_dk'))),
            g.calisan_id);
    end if;

    -- Yıllık sınır havuzda ret sebebi değildir (iş yapılmıştır): kayıt işaretlenir, İK'ya bildirilir
    v_toplam := pdks.fm_yillik_toplam(g.calisan_id, extract(year from g.is_gunu)::integer);
    if v_toplam > pdks.ayar_al('fm_yillik_sinir_dk') then
        update pdks.fazla_mesai_inceleme set yillik_sinir_asildi = true where id = p_inceleme_id;
        perform pdks.uyari_yaz('fm_yillik_sinir_asildi', 'havuz:' || p_inceleme_id,
            format('%s yılı onaylı fazla mesai süresi %s (sınır %s).',
                   extract(year from g.is_gunu), pdks.sure_metni(v_toplam), pdks.sure_metni(pdks.ayar_al('fm_yillik_sinir_dk'))),
            g.calisan_id);
    end if;
end;
$function$

;

-- T-64: gece işinin günlük sınır uyarısı net çalışmayla
CREATE OR REPLACE FUNCTION pdks.gece_isi_uyarilar(p_gun date)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'pdks'
AS $function$
declare
    v_esik    integer := pdks.ayar_al('fm_plansiz_esik_dk');
    v_gunluk  integer := pdks.ayar_al('gunluk_azami_calisma_dk');
    v_say     integer := 0;
    v_brut    integer;
    v_net     integer;
    r         record;
begin
    for r in
        select g.id, g.calisan_id, g.giris_zamani, g.cikis_zamani, g.planli_baslangic, t.esnek,
               -- Arifede planlı bitiş 13:00'tür; yazılı onaylı çalışanın vardiya içi tatil çalışması plansız sayılmaz
               pdks.dakika(case when pdks.arife_siniri(p_gun) is not null and pdks.fm_onay_gecerli_mi(g.calisan_id, g.is_gunu)
                                then (pdks.vardiya_ham_araligi(g.vardiya_id, g.is_gunu)).p_bit
                                else g.planli_bitis end, g.cikis_zamani) as fazla,
               coalesce(p.planli_dk, 0) as plan,
               pdks.fm_onay_gecerli_mi(g.calisan_id, g.is_gunu) as onay
        from pdks.gun_kaydi g
        join pdks.vardiya_tanim t on t.id = g.vardiya_id
        left join pdks.fazla_mesai_plani p
          on p.calisan_id = g.calisan_id and p.is_gunu = g.is_gunu and p.durum = 'onaylandi'
        where g.is_gunu = p_gun and g.cikis_zamani is not null and g.planli_bitis is not null
    loop
        if not r.esnek and r.fazla - r.plan > v_esik then
            if r.plan = 0 and not r.onay then
                v_say := v_say + pdks.uyari_yaz('fm_onay_yok', 'fm:' || r.id,
                    format('%s tarihinde vardiya sonrası %s çalışıldı; yazılı fazla mesai onayı yok.',
                           to_char(p_gun, 'DD.MM.YYYY'), pdks.sure_metni(r.fazla::integer)), r.calisan_id);
            else
                v_say := v_say + pdks.uyari_yaz('fm_plansiz_calisma', 'fm:' || r.id,
                    format('%s tarihinde vardiya sonrası %s çalışıldı (onaylı plan %s). Aşan süre İK kararı bekliyor.',
                           to_char(p_gun, 'DD.MM.YYYY'), pdks.sure_metni(r.fazla::integer), pdks.sure_metni(r.plan::integer)), r.calisan_id);
            end if;
        end if;

        -- T-64: sınır net çalışmaya uygulanır (brüt süreden mola düşülür)
        v_brut := case when r.giris_zamani is null then 0
                       else pdks.dakika(case when r.esnek then r.giris_zamani else greatest(r.giris_zamani, r.planli_baslangic) end,
                                        r.cikis_zamani)::integer end;
        v_net := v_brut - pdks.mola_suresi(v_brut);
        if v_net > v_gunluk + v_esik then
            v_say := v_say + pdks.uyari_yaz('fm_gunluk_sinir_asildi', 'gunluk:' || r.id,
                format('%s tarihinde %s net çalışıldı (mola hariç; %ssınır %s).', to_char(p_gun, 'DD.MM.YYYY'),
                       pdks.sure_metni(v_net), case when v_gunluk = 660 then 'yasal ' else '' end, pdks.sure_metni(v_gunluk)),
                r.calisan_id);
        end if;
    end loop;

    for r in
        select k from unnest(array['pdks', 'kapi', 'yemekhane', 'servis']) k
        where not exists (select 1 from pdks.aktarim a where a.kaynak = k and a.veri_tarihi = p_gun)
    loop
        v_say := v_say + pdks.uyari_yaz('dosya_gelmedi', r.k || ':' || p_gun,
            format('%s tarihli %s dosyası yüklenmedi.', to_char(p_gun, 'DD.MM.YYYY'),
                   case r.k when 'pdks' then 'PDKS' when 'kapi' then 'kapı turnikesi' else r.k end));
    end loop;

    v_say := v_say + coalesce(pdks.gecici_kart_kontrol(p_gun), 0);
    v_say := v_say + coalesce(pdks.kart_paylasim_kontrol(p_gun), 0);
    v_say := v_say + coalesce(pdks.isg_kontrol(p_gun), 0);
    v_say := v_say + coalesce(pdks.bolge_kontrol(p_gun), 0);

    return v_say;
end;
$function$

;

-- T-78: tatil gününde çalışma İK onayı (plan ya da havuz) kadar sayılır
CREATE OR REPLACE FUNCTION pdks.gun_hesabi(p_calisan_id bigint, p_is_gunu date, p_bas timestamp with time zone, p_bit timestamp with time zone, p_giris timestamp with time zone, p_cikis timestamp with time zone, p_vardiya_id smallint DEFAULT NULL::smallint, OUT gec_kalma_dk integer, OUT erken_cikis_dk integer, OUT calisma_dk integer, OUT fazla_mesai_dk integer, OUT fm50_dk integer, OUT fm100_dk integer, OUT gece_calisma_dk integer, OUT saatlik_izin_dk integer, OUT onaysiz_fm_dk integer, OUT mola_dk integer)
 RETURNS record
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pdks'
AS $function$
declare
    v_izin   tstzmultirange := pdks.saatlik_izin_araligi(p_calisan_id, p_is_gunu);
    v_yuv    integer := pdks.ayar_al('tolerans_yuvarlama_dk');
    v_onay   boolean := pdks.fm_onay_gecerli_mi(p_calisan_id, p_is_gunu);
    v_tatil  boolean := pdks.fm100_gunu_mu(p_is_gunu);
    v_arife  timestamptz := pdks.arife_siniri(p_is_gunu);
    v_vardiya smallint;
    v_ham_bit timestamptz;   -- arifede vardiyanın tanımdaki bitişi (p_bit 13:00'e çekilir)
    v_arife_ici integer;
    v_ek100  integer;
    v_eksik  integer;
    v_esnek  boolean;
    v_plan   integer;
    v_havuz  integer;
    v_bas_is timestamptz;
    v_ici    integer;
    v_sonra  integer;
    v_ek     integer;
    v_brut   integer;
    v_gece   integer;
begin
    gec_kalma_dk := 0; erken_cikis_dk := 0; calisma_dk := 0; fazla_mesai_dk := 0;
    fm50_dk := 0; fm100_dk := 0; gece_calisma_dk := 0; saatlik_izin_dk := 0; onaysiz_fm_dk := 0; mola_dk := 0;
    if p_giris is null or p_cikis is null then
        return;
    end if;

    v_vardiya := coalesce(p_vardiya_id, (select g.vardiya_id from pdks.gun_kaydi g
                                         where g.calisan_id = p_calisan_id and g.is_gunu = p_is_gunu));
    select coalesce(sum(dakika), 0) into v_havuz from pdks.fazla_mesai_inceleme
    where calisan_id = p_calisan_id and is_gunu = p_is_gunu and durum = 'onaylandi';

    if p_bas is null or p_bit is null then
        if v_vardiya is not null then
            return;
        end if;
        -- Plansız gün (T-79): bütün çalışma yalnızca İK'nın havuz onayı kadar sayılır;
        -- hafta tatili / resmi tatilde FM100, diğer günde FM50, arifede 13:00 sonrası FM100
        v_ici  := pdks.dakika_toplami(pdks.aralik(p_giris, p_cikis) - v_izin);
        v_brut := least(v_ici, v_havuz);
        onaysiz_fm_dk := v_ici - v_brut;
        mola_dk := pdks.mola_suresi(v_brut);
        calisma_dk := v_brut - mola_dk;
        if v_tatil then
            fm100_dk := calisma_dk;
        elsif v_arife is not null and v_brut > 0 then
            -- Mola önce 13:00 öncesinden düşer
            v_arife_ici := least(v_brut, pdks.dakika_toplami(pdks.aralik(greatest(p_giris, v_arife), p_cikis) - v_izin));
            fm100_dk := greatest(0, v_arife_ici - greatest(0, mola_dk - (v_brut - v_arife_ici)));
        end if;
        fm50_dk := calisma_dk - fm100_dk;
        fazla_mesai_dk := calisma_dk;
        if v_brut > 0 then
            v_gece := least(v_brut, pdks.dakika_toplami((pdks.aralik(p_giris, p_cikis) - v_izin) * pdks.gece_araligi(p_is_gunu)));
            gece_calisma_dk := greatest(0, v_gece - round(mola_dk::numeric * v_gece / v_brut)::integer);
        end if;
        return;
    end if;

    select t.esnek into v_esnek from pdks.vardiya_tanim t where t.id = v_vardiya;
    if coalesce(v_esnek, false) then
        -- Esnek mesaide vardiya, çalışanın kendi giriş–çıkışıdır
        p_bas := p_giris;
        p_bit := p_cikis;
    end if;

    v_ham_bit := p_bit;
    if v_arife is not null then
        if v_vardiya is not null and not coalesce(v_esnek, false) then
            v_ham_bit := greatest(p_bit, (pdks.vardiya_ham_araligi(v_vardiya, p_is_gunu)).p_bit);
        end if;
        -- Arifede çalışma 13:00'te biter; sonra başlayan vardiyada planlı normal çalışma kalmaz
        p_bit := greatest(p_bas, least(p_bit, v_arife));
    end if;

    select planli_dk into v_plan from pdks.fazla_mesai_plani
    where calisan_id = p_calisan_id and is_gunu = p_is_gunu and durum = 'onaylandi';
    v_plan := case when v_onay then coalesce(v_plan, 0) else 0 end;

    gec_kalma_dk   := pdks.tolerans_uygula(pdks.dakika_toplami(pdks.aralik(p_bas, case when v_arife is not null then least(p_giris, p_bit)
                                                                              else p_giris end) - v_izin),
                                           pdks.ayar_al('gec_kalma_tolerans_dk'), v_yuv);
    erken_cikis_dk := pdks.tolerans_uygula(pdks.dakika_toplami(pdks.aralik(p_cikis, p_bit) - v_izin),
                                           pdks.ayar_al('erken_cikis_tolerans_dk'), v_yuv);
    saatlik_izin_dk := pdks.dakika_toplami(pdks.aralik(p_bas, p_bit) * v_izin);

    v_bas_is := greatest(p_giris, p_bas);
    v_ici    := pdks.dakika_toplami(pdks.aralik(v_bas_is, least(p_cikis, p_bit)) - v_izin);
    v_sonra  := greatest(0, pdks.dakika(v_ham_bit, p_cikis));

    if v_arife is not null then
        -- 13:00'ten vardiya bitişine kadar: yazılı onay varsa FM100, yoksa havuz onayı kadar.
        -- Saat 13:00'ü birkaç dakika geçen çıkış (plansız çalışma eşiği) çalışma sayılmaz.
        v_arife_ici := pdks.dakika_toplami(pdks.aralik(greatest(v_bas_is, v_arife), least(p_cikis, v_ham_bit)) - v_izin);
        if v_ici > 0 and v_arife_ici <= pdks.ayar_al('fm_plansiz_esik_dk') then
            v_arife_ici := 0;
        end if;
        fm100_dk := case when v_onay then v_arife_ici else least(v_arife_ici, v_havuz) end;
        -- Vardiya bitişinden sonrası: onaylı plan + havuz; 13:00 öncesine düşen kısmı (ör. 00-08 vardiyası) FM50
        v_ek := least(v_sonra, v_plan + v_havuz - case when v_onay then 0 else fm100_dk end);
        v_ek100 := least(v_ek, greatest(0, pdks.dakika(greatest(v_arife, v_ham_bit), v_ham_bit + make_interval(mins => v_ek))));
        onaysiz_fm_dk := v_arife_ici - fm100_dk + v_sonra - v_ek;
        fm50_dk := v_ek - v_ek100;
        v_brut := v_ici + fm100_dk + v_ek;
        fm100_dk := fm100_dk + v_ek100;
    elsif not v_tatil then
        v_ek := least(v_sonra, v_plan + v_havuz);
        fm50_dk := v_ek;
        v_brut := v_ici + v_ek;
        onaysiz_fm_dk := greatest(0, v_sonra - v_plan - v_havuz);
    elsif v_plan > 0 then
        -- T-78: İK bu tatil günü için fazla mesai planını onaylamış (plan yalnızca yazılı onayla geçerli):
        -- günü önceden onaylamış olur; vardiya + plan FM100 sayılır, planı aşan kısım havuza düşer
        v_ek := least(v_sonra, v_plan + v_havuz);
        fm100_dk := v_ici + v_ek;
        v_brut := fm100_dk;
        onaysiz_fm_dk := greatest(0, v_sonra - v_plan - v_havuz);
    else
        -- T-78: hafta tatili / resmî tatil çalışması, yazılı onay olsa da İK'nın havuz onayı kadar sayılır;
        -- onaylanmayan süre havuza "tatil_calismasi" olarak düşer
        fm100_dk := least(v_ici + v_sonra, v_havuz);
        v_brut := fm100_dk;
        v_ek := greatest(0, fm100_dk - v_ici);
        onaysiz_fm_dk := greatest(0, v_ici + v_sonra - v_havuz);
    end if;

    -- Brüt çalışmanın gece dilimine düşen kısmı
    v_gece := least(v_brut,
        pdks.dakika_toplami((pdks.aralik(v_bas_is, least(p_cikis, v_ham_bit + make_interval(mins => coalesce(v_ek, 0))))
                             - v_izin) * pdks.gece_araligi(p_is_gunu)));

    -- Mola (m.68)
    mola_dk := pdks.mola_suresi(v_brut);
    calisma_dk := v_brut - mola_dk;
    if v_arife is not null then
        -- Mola önce normal çalışmadan, kalan kısmı fazla mesaiden düşer
        v_eksik := greatest(0, mola_dk - v_ici);
        fm100_dk := greatest(0, fm100_dk - greatest(0, v_eksik - fm50_dk));
        fm50_dk := greatest(0, fm50_dk - v_eksik);
    elsif v_tatil then
        fm100_dk := greatest(0, fm100_dk - mola_dk);
    elsif v_ici < mola_dk then
        fm50_dk := greatest(0, fm50_dk - (mola_dk - v_ici));
    end if;
    fazla_mesai_dk := fm50_dk + fm100_dk;
    gece_calisma_dk := case when v_brut > 0 then greatest(0, v_gece - round(mola_dk::numeric * v_gece / v_brut)::integer)
                            else 0 end;
end;
$function$

;

-- T-78: tatil gününün onaysız kısmı havuza tatil_calismasi olarak düşer
CREATE OR REPLACE FUNCTION pdks.gun_sonrasi_kontroller(p_gun_kaydi_id bigint)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'pdks'
AS $function$
declare
    g       pdks.gun_kaydi;
    h       record;
    v_mevcut pdks.fazla_mesai_inceleme;
    v_tur   text;
    v_say   integer := 0;
    v_toplam integer;
begin
    select * into g from pdks.gun_kaydi where id = p_gun_kaydi_id;
    if not g.hesap_tamam or not (g.durum = 'tamam' or (g.durum = 'vardiya_yok' and g.vardiya_id is null)) then
        return 0;
    end if;
    select * into h from pdks.gun_hesabi(g.calisan_id, g.is_gunu, g.planli_baslangic, g.planli_bitis,
                                         g.giris_zamani, g.cikis_zamani);
    v_tur := case when g.vardiya_id is null   -- plansız gün (T-79)
                    or pdks.fm100_gunu_mu(g.is_gunu)   -- T-78: yazılı onay olsa da
                    or (g.cikis_zamani > pdks.arife_siniri(g.is_gunu)
                        and not pdks.fm_onay_gecerli_mi(g.calisan_id, g.is_gunu))
                  then 'tatil_calismasi' else 'vardiya_sonrasi' end;

    select * into v_mevcut from pdks.fazla_mesai_inceleme where gun_kaydi_id = g.id;
    if h.onaysiz_fm_dk > pdks.ayar_al('fm_plansiz_esik_dk') then
        if v_mevcut.id is null then
            insert into pdks.fazla_mesai_inceleme (gun_kaydi_id, calisan_id, is_gunu, tur, dakika)
            values (g.id, g.calisan_id, g.is_gunu, v_tur, h.onaysiz_fm_dk);
            v_say := v_say + 1;
        elsif v_mevcut.durum = 'inceleme_bekliyor' and (v_mevcut.dakika, v_mevcut.tur) <> (h.onaysiz_fm_dk, v_tur) then
            update pdks.fazla_mesai_inceleme set dakika = h.onaysiz_fm_dk, tur = v_tur where id = v_mevcut.id;
        end if;
    end if;

    -- Havuza düşmeden puantaja giren FM100 (arife öğleden sonrası, tatilde onaylı plan); yıllık sınırı aşarsa İK'ya bildirilir
    -- (havuzdan onaylanan gün kendi uyarısını karar anında yazar)
    if g.fm100_dk > 0 and v_mevcut.durum is distinct from 'onaylandi' then
        v_toplam := pdks.fm_yillik_toplam(g.calisan_id, extract(year from g.is_gunu)::integer);
        if v_toplam > pdks.ayar_al('fm_yillik_sinir_dk') then
            v_say := v_say + pdks.uyari_yaz('fm_yillik_sinir_asildi', 'gun:' || g.id,
                format('%s yılı onaylı fazla mesai süresi %s (sınır %s).',
                       extract(year from g.is_gunu), pdks.sure_metni(v_toplam), pdks.sure_metni(pdks.ayar_al('fm_yillik_sinir_dk'))),
                g.calisan_id);
        end if;
    end if;

    if g.gece_calisma_dk > pdks.ayar_al('gece_calisma_sinir_dk') then
        v_say := v_say + pdks.uyari_yaz('gece_calisma_siniri_asildi', 'gece:' || g.id,
            format('%s tarihinde %s gece çalışması yapıldı (%ssınır %s).',
                   to_char(g.is_gunu, 'DD.MM.YYYY'), pdks.sure_metni(g.gece_calisma_dk),
                   case when pdks.ayar_al('gece_calisma_sinir_dk') = 450 then 'yasal ' else '' end,
                   pdks.sure_metni(pdks.ayar_al('gece_calisma_sinir_dk'))),
            g.calisan_id);
    end if;
    return v_say;
end;
$function$

;
