-- =====================================================================
-- T-29, T-95, T-60: Puantajı etkileyen kalan Düşük bulgular
--
-- T-29: Çıkışta kartını iki kez okutan kişinin İLK okutması çıkış sayılıyordu (16:53 ve 16:56 okutan
--       16:53'le 7 dk erken çıkış alıyordu; 16:56 tutulsa tolerans içinde 0). Zincirleme okutmada kayıp
--       3 dk'yı aşabiliyordu. Girişte ilkini tutmak doğru ve çalışan lehine; çıkışta sonuncusu tutulmalı.
-- T-95: Fark satırı yalnızca sayısal alanlardan biri değişince yazılıyordu. Yalnızca gün kodu değişince
--       (kilitli ayda kodsuz kalan gün sonradan "vardiya yok" olunca: kodsuz → HT) ne satır ne kalem
--       yazılıyordu; gün bordroya hiç ulaşmıyordu (T-67'deki Ahmet örneği: 16–18 Eylül).
-- T-60: Yazılı fazla mesai onayı "çalışan + yıl" tekildi; onayını geri alan çalışan aynı yıl yeniden imza
--       veremiyordu (ham İngilizce "duplicate key"). Kural: yılda en çok bir GEÇERLİ (geri alınmamış) onay;
--       geri alınmış onay kayıt olarak kalır. fm_onay_gecerli_mi zaten tarih aralığına bakıyor.
-- T-03: 52 security definer fonksiyonun search_path'inde pg_temp yoktu; PostgreSQL yazılmayan pg_temp'i
--       tablo ararken EN BAŞA koyar (TEMP yetkisi olan kullanıcı aynı adla geçici tablo açabilir). Bugün
--       istismar yolu yok (bütün tablolar pdks. önekli), ama mandal eksikti: hepsine pg_temp sona eklenir.
-- T-08: pdks'te yeni fonksiyon PUBLIC'e açık doğuyordu (her migration elle revoke ediyordu). Varsayılan
--       yetki: yeni fonksiyon kapalı doğar.
-- Kalıcı testler: supabase/tests/mukerrer_cikis_testi.sql (T-29), kod_farki_testi.sql (T-95),
--                 yazili_onay_yenileme_testi.sql (T-60), sema_temizligi_testi.sql (T-03, T-08)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. T-29: gece işinin işaretleme adımı (son hâli 20261216010000; yalnızca mükerrer kuralı)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pdks.gece_isi_isaretle(p_gun date, p_gece_isi_id bigint)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'pdks'
AS $function$
declare
    v_bas   timestamptz := ((p_gun - 1)::timestamp at time zone 'Europe/Istanbul');
    v_bit   timestamptz := ((p_gun + 2)::timestamp at time zone 'Europe/Istanbul');
    v_esik  interval    := make_interval(mins => pdks.ayar_al('mukerrer_esik_dk'));
    v_say   integer := 0;
    v_n     integer;
    r       record;
begin
    -- Mükerrer: aynı kart, aynı yön, eşik süresi içinde tekrar.
    -- Giriş (ve yönü belirsiz okutma): ilk okutma tutulur, sonrakiler mükerrer.
    -- T-29: Çıkış: son okutma tutulur (kişi binadan son okutmada çıkmıştır), öncekiler mükerrer.
    --       Eski kuralla (ilkini tutup sonrakini işaretleyen) işaretlenmiş bir çifte dokunulmaz: işaretler
    --       silinemediği için öbürü de işaretlenirse iki çıkış birden düşerdi (gece işi penceresi örtüşür).
    insert into pdks.okutma_isareti (ham_okutma_id, isaret, aciklama, gece_isi_id)
    select x.id, 'mukerrer',
           case when x.yon = 'cikis'
                then format('%s sn sonra aynı kart yeniden çıkış okuttu; çıkışta son okutma tutulur',
                            extract(epoch from x.sonraki - x.okutma_zamani)::int)
                else format('%s sn önce aynı kart aynı yönde okutulmuş', extract(epoch from x.okutma_zamani - x.onceki)::int)
           end,
           p_gece_isi_id
    from (select h.id, h.okutma_zamani, h.yon, h.kart_no,
                 lag(h.okutma_zamani)  over w as onceki,
                 lead(h.okutma_zamani) over w as sonraki
          from pdks.ham_okutma h
          where h.okutma_zamani >= v_bas - v_esik and h.okutma_zamani < v_bit + v_esik
          window w as (partition by h.kart_no, h.yon order by h.okutma_zamani, h.id)) x
    where x.okutma_zamani >= v_bas and x.okutma_zamani < v_bit
      and case when x.yon = 'cikis'
               then x.sonraki is not null and x.sonraki - x.okutma_zamani <= v_esik
                    and not exists (select 1 from pdks.okutma_isareti i
                                    join pdks.ham_okutma h2 on h2.id = i.ham_okutma_id
                                    where i.isaret = 'mukerrer' and h2.kart_no = x.kart_no and h2.yon = 'cikis'
                                      and h2.id <> x.id
                                      and h2.okutma_zamani between x.okutma_zamani - v_esik and x.okutma_zamani + v_esik)
               else x.onceki is not null and x.okutma_zamani - x.onceki <= v_esik
          end
    on conflict (ham_okutma_id, isaret) do nothing;
    get diagnostics v_n = row_count;
    v_say := v_say + v_n;

    -- İptal edilmiş kartla okutma (+ İK'ya uyarı)
    for r in
        select h.id, h.okuyucu_id, h.kart_no, h.okutma_zamani, k.calisan_id
        from pdks.ham_okutma h
        join pdks.kart k on k.kart_no = h.kart_no
        where k.durum = 'iptal' and h.okutma_zamani >= k.iptal_zamani
          and h.okutma_zamani >= v_bas and h.okutma_zamani < v_bit
    loop
        insert into pdks.okutma_isareti (ham_okutma_id, isaret, aciklama, gece_isi_id)
        values (r.id, 'iptal_kart', 'Kart bu okutmadan önce iptal edilmişti', p_gece_isi_id)
        on conflict (ham_okutma_id, isaret) do nothing;
        get diagnostics v_n = row_count;
        v_say := v_say + v_n;
        perform pdks.uyari_yaz('iptal_kart_okutma', 'ham:' || r.id,
            format('%s numaralı iptal edilmiş kart %s tarihinde okutuldu.', r.kart_no,
                   to_char(r.okutma_zamani at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI')),
            r.calisan_id, r.okuyucu_id);
    end loop;

    -- Bilinmeyen kart: okutma anında kimseye ait değil (tanımsız kart ya da zimmetsiz geçici kart)
    insert into pdks.okutma_isareti (ham_okutma_id, isaret, aciklama, gece_isi_id)
    select h.id, 'bilinmeyen_kart', 'Okutma anında bu kart kimseye ait değil', p_gece_isi_id
    from pdks.ham_okutma h
    where h.okutma_zamani >= v_bas and h.okutma_zamani < v_bit
      and pdks.okutma_sahibi(h.kart_no, h.okutma_zamani) is null
    on conflict (ham_okutma_id, isaret) do nothing;
    get diagnostics v_n = row_count;
    v_say := v_say + v_n;

    return v_say;
end;
$function$;

-- ---------------------------------------------------------------------
-- 2. T-95: puantaj yazımı (son hâli 20261124010000; yalnızca fark satırı koşulu)
-- ---------------------------------------------------------------------
create or replace function pdks.puantaj_yaz(p_donem_id bigint)
returns integer
language plpgsql
set search_path = pdks
as $$
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
                                     mola_dk, esnek_hedef_dk, esnek_fark_dk)
    select p_donem_id, v.calisan_id, 'normal', v.calisilan_gun, v.calisma_dk, v.gec_kalma_dk,
           v.erken_cikis_dk, v.devamsiz_gun, v.izinli_gun, v.raporlu_gun, v.tatil_gun, v.fazla_mesai_dk,
           v.fm50_dk, v.fm100_dk, v.gece_calisma_dk, v.saatlik_izin_dk,
           v.mola_dk, v.esnek_hedef_dk, v.esnek_fark_dk
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
            -- T-95: yalnızca gün kodu değiştiyse de (ör. kodsuz → HT) fark satırı ve kalemi yazılır
            or exists (select 1 from kod_farklari k
                       where k.calisan_id = farklar.calisan_id and k.kaynak_donem_id = farklar.kaynak_donem_id)
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
$$;

-- ---------------------------------------------------------------------
-- 3. T-60: yılda tek geçerli yazılı onay
-- ---------------------------------------------------------------------
alter table pdks.fazla_mesai_onayi drop constraint fazla_mesai_onayi_calisan_id_yil_key;
create unique index fazla_mesai_onayi_yil_tek_gecerli on pdks.fazla_mesai_onayi (calisan_id, yil)
    where geri_alma_bildirim_tarihi is null;

create or replace function pdks.fazla_mesai_onayi_gir(p_calisan_id bigint, p_yil smallint, p_imza_tarihi date, p_belge_no text)
returns bigint
language plpgsql
security definer
set search_path = pdks
as $$
declare
    v_ben    bigint := pdks.yetki_gerekli('ik');
    v_eski   pdks.fazla_mesai_onayi;
    v_id     bigint;
begin
    select * into v_eski from pdks.fazla_mesai_onayi
    where calisan_id = p_calisan_id and yil = p_yil and geri_alma_bildirim_tarihi is null;
    if found then
        raise exception 'Çalışanın % yılı için geçerli bir yazılı onayı var (belge %, imza %). Yeni onay için önce bu onayın geri alındığı girilmelidir.',
            p_yil, v_eski.belge_no, to_char(v_eski.imza_tarihi, 'DD.MM.YYYY');
    end if;
    insert into pdks.fazla_mesai_onayi (calisan_id, yil, imza_tarihi, belge_no, giren_id)
    values (p_calisan_id, p_yil, p_imza_tarihi, p_belge_no, v_ben)
    returning id into v_id;
    return v_id;
end;
$$;

-- ---------------------------------------------------------------------
-- 4. T-03: security definer fonksiyonlarda pg_temp en sonda (var olan search_path korunur)
--    Not: bundan sonra security definer fonksiyon "set search_path = pdks, pg_temp" ile yazılmalı;
--    sema_temizligi_testi bunu denetler.
-- ---------------------------------------------------------------------
do $$
declare
    r record;
begin
    for r in
        select p.oid::regprocedure as fn,
               coalesce((select substr(c, length('search_path=') + 1) from unnest(p.proconfig) c
                         where c like 'search_path=%'), 'pdks') as yol
        from pg_proc p
        where p.pronamespace = 'pdks'::regnamespace and p.prosecdef
          and not exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%pg_temp%')
    loop
        execute format('alter function %s set search_path = %s, pg_temp', r.fn, r.yol);
    end loop;
end $$;

-- ---------------------------------------------------------------------
-- 5. T-08: pdks'te yeni fonksiyon herkese kapalı doğar
-- ---------------------------------------------------------------------
-- Şema bazında ("in schema pdks") varsayılan yetki yalnızca yetki EKLEYEBİLİR; PUBLIC'in yerleşik EXECUTE'unu
-- kaldırmak için rol düzeyinde verilir. postgres'in fonksiyonları yalnızca pdks'te; public / storage şemalarında
-- Supabase'in anon / authenticated / service_role'e açık varsayılan yetkileri ayrıca tanımlı, etkilenmez.
alter default privileges for role postgres revoke execute on functions from public;
