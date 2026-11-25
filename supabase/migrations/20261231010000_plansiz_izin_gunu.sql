-- =====================================================================
-- Planı olmayan izin günü (T-94)
--
-- Sorun: Gece işi yalnızca planı olan güne gün kaydı açar. Amir izindeki kişiye plan girmezse
-- o günün gün kaydı olmaz; puantaj gün kaydı olmayan günü HT (hafta tatili) kodlar ve izinli
-- gün sayısına katmaz. İzin 2 gün, puantaj "1 gün Yİ + 1 gün HT" der.
--
-- Kural: Geçerli (iptal edilmemiş) iznin kapsadığı, gün kaydı olmayan gün izin günüdür, şu
-- günler dışında:
--   - Pazar, tam gün resmi tatil ve (cumartesi_hafta_sonu = 1 ise) Cumartesi: bunlar zaten
--     tatildir, HT / RT kalır (pdks.fm100_gunu_mu ile aynı tanım). Arife (yarım gün) izin günüdür.
--   - Çalışanın işe girişinden önceki ve işten çıkışından sonraki günler.
-- Bu günler planlı izin günüyle aynı kodu alır (Yİ / MZR / ÜCSZ / RPR / Dİ) ve aynı sayıya
-- girer: rapor raporlu güne, diğerleri izinli güne. Gün kaydı açılmaz; yalnızca puantaj
-- hesabı değişir (gece işi ve düzeltme kuralları aynı kalır).
--
-- Kilitli ay (karar: reddet): kilitli ayın planı olmayan bir izin gününe sonradan izin girilmesi
-- ya da o günü kapsayan iznin iptali reddedilir. Sebep: fark satırı (T-48) yalnızca gün kaydı olan
-- günden üretilir; bu günde kilitli satır eski kodunu korur, sonraki aya da fark düşmez, bordro
-- sessizce yanlış kalırdı. Gün kaydı olan günler ve tatil günleri eskisi gibi girilir / iptal edilir.
-- Kalıcı test: supabase/tests/plansiz_izin_gunu_testi.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Kuralın tek yeri: bir tarih aralığındaki planı olmayan izin günleri
--    Çağıranın yetkisiyle çalışır (izin yalnızca İK ve yöneticiye görünür, RLS).
--    Bilerek "set search_path" yok: böyle bir SQL fonksiyonunu PostgreSQL çağıran sorgunun içine
--    açar (inline). Canlı puantaj görünümü bunu tarih sınırı vermeden çağırır; açılınca görünümün
--    yil / ay filtresi fonksiyonun içine iner ve yalnızca o ayın günleri taranır. SET olsaydı
--    fonksiyon her sorguda bütün yılların izin günlerini hesaplardı. Bütün adlar şemayla yazılı
--    (pdks.), fonksiyon security definer değil; sabit search_path'in koruduğu bir şey kalmıyor.
-- ---------------------------------------------------------------------
create function pdks.plansiz_izin_gunleri(p_bas date, p_bit date)
returns table (calisan_id bigint, gun date, tur text)
language sql
stable
as $$
    with ayar as (
        select coalesce(pdks.ayar_al('cumartesi_hafta_sonu'), 0) = 1 as cumartesi_tatil
    )
    select distinct on (i.calisan_id, d.gun) i.calisan_id, d.gun, i.tur
    from pdks.izin i
    cross join ayar
    join pdks.calisan c on c.id = i.calisan_id
    -- Gün "date" sütunu olarak üretilir ("offset 0" alt sorguyu ayrı tutar). Sebep RLS: İK
    -- olarak sorgulanınca PostgreSQL sızıntı yapabilecek işlemi (burada timestamp → date
    -- dönüşümü) index aramasında kullanmaz; "is_gunu = d::date" yazılsaydı gun_kaydi araması
    -- yalnızca calisan_id ile yapılır, kişinin bütün yılı satır satır elenirdi.
    cross join lateral (
        select s::date as gun
        from generate_series(
            greatest(i.baslangic, p_bas, c.ise_giris_tarihi),
            least(i.bitis, p_bit, coalesce(c.isten_cikis_tarihi, 'infinity'::date)),
            interval '1 day') s
        offset 0) d
    where i.iptal_zamani is null
      and i.baslangic <= p_bit and i.bitis >= p_bas
      -- Tatil günü değil: pdks.fm100_gunu_mu ile aynı tanım, ama o fonksiyon gün başına
      -- çağrılmaz (2000 kişide görünümü ~20 kat yavaşlatıyordu).
      and extract(isodow from d.gun) <> 7
      and not (extract(isodow from d.gun) = 6 and ayar.cumartesi_tatil)
      and not exists (select 1 from pdks.resmi_tatil r where r.tarih = d.gun and not r.yarim_gun)
      -- Gün kaydı yok. "not exists" değil, tek satırlık alt sorgu: planlayıcı generate_series'in
      -- izin başına 1000 gün üreteceğini sanıp bütün gun_kaydi'yi tarayabiliyordu. Bu biçim her
      -- gün için tek index araması yapar; (calisan_id, is_gunu) tekil, en fazla bir satır döner.
      and (select g.id from pdks.gun_kaydi g where g.calisan_id = i.calisan_id and g.is_gunu = d.gun) is null
    order by i.calisan_id, d.gun, i.id;
$$;

comment on function pdks.plansiz_izin_gunleri(date, date) is
    'Gün kaydı olmayan izin günleri (T-94): geçerli izin, işe giriş–çıkış arası; Pazar, tam gün resmi tatil ve ayara göre Cumartesi hariç.';

revoke execute on function pdks.plansiz_izin_gunleri(date, date) from public, anon;
grant execute on function pdks.plansiz_izin_gunleri(date, date) to authenticated;

-- ---------------------------------------------------------------------
-- 1b. izin okuma politikası sorgu başına bir kez denetlenir (T-104 kalıbı)
--     Canlı puantaj artık izin tablosunu da okuyor. Bu politika T-104'te çevrilmemişti (o gün
--     sıcak yolda değildi): tum_veriyi_gorur() her izin satırında yeniden çalışıyor, İK'da
--     2000 kişi / 8000 izinle Puantaj sayfasına ~1,3 sn ekliyordu. "(select ...)" içinde sorgu
--     başına bir kez hesaplanır. Kim hangi satırı görür değişmedi.
--     resmi_tatil bilerek çevrilmedi: görünüm onu her gün kaydı için index'le arar, orada
--     "(select ...)" her aramada yeniden hesaplanıp ölçümde daha yavaş çıktı.
-- ---------------------------------------------------------------------
alter policy ik_yonetici_okur on pdks.izin
    using ((select pdks.tum_veriyi_gorur()));

-- ---------------------------------------------------------------------
-- 2. Gün gün kodlar: gün kaydı olmayan izin günü izin kodunu alır, HT değil.
--    Ayda yalnızca planı olmayan izin günü olan çalışan da listeye girer.
-- ---------------------------------------------------------------------
create or replace function pdks.gun_kodlari_hesapla(p_yil integer, p_ay integer)
returns table (calisan_id bigint, tarih date, kod text, gun numeric, dakika integer)
language sql
stable
set search_path = pdks
as $$
    with ay as (
        select make_date(p_yil, p_ay, 1) as bas,
               (make_date(p_yil, p_ay, 1) + interval '1 month - 1 day')::date as bit
    ), pi as (
        select p.* from ay cross join lateral pdks.plansiz_izin_gunleri(ay.bas, ay.bit) p
    ), kisiler as (
        select g.calisan_id from pdks.gun_kaydi g, ay
        where g.is_gunu between ay.bas and ay.bit
        union
        select pi.calisan_id from pi
    )
    select k.calisan_id, d::date, x.kod, x.gun, x.dakika
    from kisiler k
    join pdks.calisan c on c.id = k.calisan_id
    cross join ay
    cross join generate_series(ay.bas, ay.bit, interval '1 day') d
    left join pdks.gun_kaydi g on g.calisan_id = k.calisan_id and g.is_gunu = d::date
    left join pi on pi.calisan_id = k.calisan_id and pi.gun = d::date
    cross join lateral pdks.gun_kod_satirlari(
        k.calisan_id, d::date,
        case when g.id is null and pi.tur = 'rapor' then 'raporlu'       -- T-94: planlı rapor günüyle aynı
             when g.id is null and pi.tur is not null then 'izinli'      -- T-94: kodu izin türünden alır
             when g.durum = 'tamam' and not g.hesap_tamam then 'eksik'
             else g.durum end,
        g.calisma_dk, g.fm50_dk, g.fm100_dk) x
    where d::date >= c.ise_giris_tarihi
      and (c.isten_cikis_tarihi is null or d::date <= c.isten_cikis_tarihi);
$$;

-- ---------------------------------------------------------------------
-- 3. Canlı puantaj: planı olmayan izin günü izinli / raporlu güne eklenir.
--    Gün kaydından gelen toplamlar (toplam) değişmedi; ayda yalnızca planı olmayan izin günü
--    olan çalışan için de satır çıkar. Sütunlar, sırası ve tipleri aynı (sum sonucu numeric
--    olduğu için ::bigint / ::integer ile eski tiplere döner).
--    İki kaynak UNION ALL ile alt alta konup çalışan-ay başına toplanır (FULL JOIN değil):
--    böylece ekranın "yil = ? and ay = ?" filtresi iki kaynağa da iner, yalnızca o ayın gün
--    kayıtları ve izin günleri okunur.
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
    count(*) FILTER (WHERE (durum = 'tamam'::text)) AS calisilan_gun,
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
-- 4. Kilitli ayın planı olmayan izin günü: izin girişi ve iptali reddedilir
--    Kural tablonun üstünde (trigger): izin hangi fonksiyondan girilir ya da iptal edilirse
--    edilsin geçerli. Yeni izin AFTER INSERT ile denetlenir (yeni satır sorguda görünsün);
--    iptal BEFORE UPDATE ile (iptal edilen izin henüz geçerliyken). İkisi de aynı tanımı,
--    pdks.plansiz_izin_gunleri'ni kullanır.
-- ---------------------------------------------------------------------
create function pdks.izin_kilitli_plansiz_gun_engelle()
returns trigger
language plpgsql
set search_path = pdks
as $$
declare
    v_gun date;
begin
    if tg_op = 'UPDATE' and not (old.iptal_zamani is null and new.iptal_zamani is not null) then
        return new;
    end if;

    select p.gun into v_gun
    from pdks.plansiz_izin_gunleri(new.baslangic, new.bitis) p
    join pdks.donem d on d.yil = extract(year from p.gun) and d.ay = extract(month from p.gun)
    where p.calisan_id = new.calisan_id
      and d.durum = 'kilitli'
    order by p.gun
    limit 1;

    if v_gun is not null then
        if tg_op = 'INSERT' then
            raise exception 'İzin girilemez: % tarihinin ayı (%) kilitli ve o gün için vardiya planı yok. Kilitli aya fark satırı yalnızca gün kaydı olan günden üretilebilir; izni bu gün olmadan girin.',
                to_char(v_gun, 'DD.MM.YYYY'), to_char(v_gun, 'MM.YYYY');
        else
            raise exception 'İzin iptal edilemez: % tarihinin ayı (%) kilitli ve o gün için vardiya planı yok. İptal kilitli aya fark satırı olarak yansıyamaz.',
                to_char(v_gun, 'DD.MM.YYYY'), to_char(v_gun, 'MM.YYYY');
        end if;
    end if;
    return new;
end;
$$;

comment on function pdks.izin_kilitli_plansiz_gun_engelle() is
    'T-94: kilitli ayın planı olmayan izin gününe dokunan izin girişini ve iptalini reddeder (fark satırı üretilemez).';

revoke execute on function pdks.izin_kilitli_plansiz_gun_engelle() from public, anon, authenticated;

create trigger izin_kilitli_plansiz_gun after insert on pdks.izin
    for each row execute function pdks.izin_kilitli_plansiz_gun_engelle();
create trigger izin_kilitli_plansiz_gun_iptal before update of iptal_zamani on pdks.izin
    for each row execute function pdks.izin_kilitli_plansiz_gun_engelle();
