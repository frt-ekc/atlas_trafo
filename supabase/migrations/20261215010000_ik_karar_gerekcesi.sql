-- =====================================================================
-- K9 · T-106: İK'nın soru kararındaki gerekçesi amire açıktı (T-12 ile aynı kök)
--
-- soru_ik_karari gerekçeyi amir_sorusu.cevap_aciklama'ya ekliyordu ("İK: …"); soruyu amir (ve
-- üst amir) okuyabiliyor. "Geldi" kararında gerekçe ayrıca saat düzeltmesine yazılıyor ve
-- v_duzeltme_amir'de (T-12) görünüyordu.
--
-- Değişiklik:
--   * amir_sorusu.ik_karari : kararın sonucu ('devamsiz' / 'geldi'). Amir yalnızca bunu görür.
--   * soru_ik_karari : gerekçeyi soruya yazmaz; gerekçe yalnızca soru_id'li duzeltme satırındadır
--     (İK ve yönetici okur). cevap_aciklama amirin kendi açıklaması olarak kalır.
--   * v_duzeltme_amir : İK'nın soru kararından gelen düzeltmede de gerekçe gizli. Amirin kendi
--     cevabından gelen düzeltme (kaynak = 'amir') olduğu gibi görünür.
--   * Eski kayıtlar : soruya eklenmiş İK gerekçesi silinir (aynısı duzeltme'de duruyor, bilgi
--     kaybolmaz), ik_karari doldurulur.
--   soru_ik_karari'nin geri kalanı son sürümle (pg_get_functiondef) aynıdır; yetkiler korunur.
--
-- Kapsam dışı: isten_cikis_gir'in soruya yazdığı açıklama; itiraz ve fazla mesai karar açıklamaları.
-- Kalıcı test: supabase/tests/ik_karar_gerekcesi_testi.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Kararın sonucu
-- ---------------------------------------------------------------------
alter table pdks.amir_sorusu
    add column ik_karari text check (ik_karari in ('devamsiz', 'geldi'));
comment on column pdks.amir_sorusu.ik_karari is
    'İK''nın soru kararının sonucu (soru_ik_karari). Gerekçe burada değil, soru_id''li duzeltme satırındadır (T-106).';

-- ---------------------------------------------------------------------
-- 2. Eski kayıtlar: gerekçe yalnızca birebir aynısı duzeltme'de varsa sorudan çıkarılır
-- ---------------------------------------------------------------------
update pdks.amir_sorusu s
set ik_karari = case when d.alan = 'durum' and d.yeni_deger = 'devamsiz' then 'devamsiz' else 'geldi' end,
    cevap_aciklama = nullif(regexp_replace(
        left(s.cevap_aciklama, length(s.cevap_aciklama) - length('İK: ' || d.gerekce)), ' \| $', ''), '')
from (select distinct on (soru_id) soru_id, alan, yeni_deger, gerekce
      from pdks.duzeltme where kaynak = 'ik' and soru_id is not null order by soru_id, id) d
where d.soru_id = s.id and s.durum = 'kapandi'
  and right(s.cevap_aciklama, length('İK: ' || d.gerekce)) = 'İK: ' || d.gerekce;

-- ---------------------------------------------------------------------
-- 3. soru_ik_karari
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pdks.soru_ik_karari(p_soru_id bigint, p_devamsiz boolean, p_gerekce text, p_giris timestamp with time zone DEFAULT NULL::timestamp with time zone, p_cikis timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pdks'
AS $function$
declare
    v_ben   bigint := pdks.yetki_gerekli('ik');
    v_soru  pdks.amir_sorusu;
begin
    select * into v_soru from pdks.amir_sorusu where id = p_soru_id for update;
    -- Son karar İK'dadır (T-39): soru amirde, üst amirde ya da İK'da beklerken İK karar verebilir
    if not found or v_soru.durum not in ('acik', 'eskale', 'ik_karari_bekliyor') then
        raise exception 'İK kararı bekleyen soru bulunamadı.';
    end if;
    if not p_devamsiz and p_giris is null and p_cikis is null then
        raise exception 'Devamsız değilse giriş ya da çıkış saatini girin.';
    end if;

    update pdks.amir_sorusu
    set durum = 'kapandi', cevaplayan_id = v_ben,
        -- Yalnızca sonuç: gerekçe, amirin okuyamadığı duzeltme satırındadır (T-106)
        ik_karari = case when p_devamsiz then 'devamsiz' else 'geldi' end
    where id = p_soru_id;

    if p_devamsiz then
        perform pdks.duzeltme_uygula(v_soru.gun_kaydi_id, 'durum', 'devamsiz', p_gerekce, 'ik', v_ben,
                                     p_soru_id => p_soru_id, p_aleyhine => true);
    else
        perform pdks.saat_yaz(v_soru.gun_kaydi_id, p_giris, p_cikis, p_gerekce, 'ik', v_ben, p_soru_id => p_soru_id);
    end if;

    -- Değişen gün hemen hesaplanır (kilitli ayda yapılmaz; düzeltme orada fark satırı olur)
    perform pdks.gun_hesapla(v_soru.gun_kaydi_id);
end;
$function$;


-- ---------------------------------------------------------------------
-- 4. v_duzeltme_amir (T-12; yalnızca gerekçe koşulu genişledi)
-- ---------------------------------------------------------------------
create or replace view pdks.v_duzeltme_amir
with (security_barrier = true) as
select d.id,
       d.gun_kaydi_id,
       d.calisan_id,
       d.is_gunu,
       d.alan,
       case when d.alan = 'durum' and d.eski_deger = 'raporlu' then 'izinli' else d.eski_deger end as eski_deger,
       case when d.alan = 'durum' and d.yeni_deger = 'raporlu' then 'izinli' else d.yeni_deger end as yeni_deger,
       case when d.alan = 'durum' or d.izin_id is not null
                 or (d.kaynak = 'ik' and d.soru_id is not null)   -- İK'nın soru kararı (T-106)
            then 'İK tarafından düzeltildi' else d.gerekce end as gerekce,
       d.kaynak,
       d.yapan_id,
       d.calisan_aleyhine,
       d.yapilma_zamani
from pdks.duzeltme d
where (select pdks.tum_veriyi_gorur())
   or d.calisan_id = any ((select pdks.oturum_calisanlari())::bigint[]);

comment on view pdks.v_duzeltme_amir is
    'Amirin düzeltme listesi: kendi çalışanları; durum, izin ve İK soru kararı düzeltmelerinde gerekçe gizli, "raporlu" yerine "izinli" (T-12, T-106).';
