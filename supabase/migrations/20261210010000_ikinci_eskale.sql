-- =====================================================================
-- K2 · T-39: Üst amir de cevaplamazsa soru hiçbir zaman İK'ya gitmiyordu; İK ne
-- soruyu kapatabiliyor ne günü hesaplatabiliyordu
--
-- Eskiden gece_isi_eskale yalnızca "acik" soruları üst amire taşıyordu. Üst amir de
-- cevaplamazsa soru "eskale" durumunda sonsuza kadar kalıyordu; soru_ik_karari onu
-- kabul etmiyordu ("İK kararı bekleyen soru bulunamadı."), gün hesaplanmıyor ve ay
-- sonunda puantaja kodsuz giriyordu (T-90).
--
-- Değişiklik:
--   * amir_sorusu.ik_eskale_zamani: sorunun İK'ya geçtiği an (ikinci kademe).
--   * gece_isi_eskale: amir → üst amir → İK.
--       - İkinci kademe: "eskale" durumundaki soru, son cevap tarihinden
--         soru_eskalasyon_gun gün sonra da cevaplanmadıysa ve üst amir İK değilse
--         "ik_karari_bekliyor" olur. Üst amirin adı (eskale_edilen_id) silinmez.
--         İK'ya uyarı yazılır (soru_eskale, anahtar soru_ik:<id>).
--       - Birinci kademe eskisi gibi. İkinci kademe önce çalışır: bir gecede soru
--         en çok bir kademe ilerler.
--   * soru_ik_karari: İK her açık soruya (acik / eskale / ik_karari_bekliyor) karar
--     verebilir; son karar İK'dadır. Görevler ayrılığı tetikleyicisi korunur.
--   Fonksiyonların geri kalanı son sürümle (pg_get_functiondef) birebir aynıdır.
-- Kalıcı test: supabase/tests/soru_eskale_testi.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Sorunun İK'ya geçtiği an
-- ---------------------------------------------------------------------
alter table pdks.amir_sorusu add column ik_eskale_zamani timestamptz;
comment on column pdks.amir_sorusu.ik_eskale_zamani is
    'Üst amir de süresinde cevaplamayınca sorunun İK''ya geçtiği an (ikinci kademe eskalasyon, T-39).';

-- ---------------------------------------------------------------------
-- 2. gece_isi_eskale: amir → üst amir → İK
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pdks.gece_isi_eskale(p_gun date)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'pdks'
AS $function$
declare
    v_say  integer := 0;
    v_hedef bigint;
    v_sure  integer := pdks.ayar_al('soru_eskalasyon_gun');
    s      record;
begin
    -- İkinci kademe (T-39): üst amire gitmiş soru, onun süresi de dolduysa İK'ya geçer.
    -- Birinci kademeden önce çalışır: bir gecede soru en çok bir kademe ilerler.
    for s in
        select q.id, g.calisan_id, g.is_gunu
        from pdks.amir_sorusu q
        join pdks.gun_kaydi g on g.id = q.gun_kaydi_id
        where q.durum = 'eskale'
          and q.son_cevap_tarihi + v_sure <= p_gun
          and pdks.kullanici_rolu(q.eskale_edilen_id) is distinct from 'ik'
        order by q.id
    loop
        update pdks.amir_sorusu
        set durum = 'ik_karari_bekliyor', ik_eskale_zamani = now()
        where id = s.id;
        v_say := v_say + 1;
        perform pdks.uyari_yaz('soru_eskale', 'soru_ik:' || s.id,
            format('%s tarihli soruyu üst amir de süresinde cevaplamadı; İK kararı bekliyor.', to_char(s.is_gunu, 'DD.MM.YYYY')),
            s.calisan_id);
    end loop;

    -- Birinci kademe: amir süresinde cevaplamadıysa üst amire (üst amiri yoksa ya da üst
    -- amir çalışanın kendisiyse İK'ya)
    for s in
        select q.id, q.atanan_id, g.calisan_id, g.is_gunu
        from pdks.amir_sorusu q
        join pdks.gun_kaydi g on g.id = q.gun_kaydi_id
        where q.durum = 'acik' and q.son_cevap_tarihi <= p_gun
        order by q.id
    loop
        select ust_amir_id into v_hedef from pdks.kullanici where id = s.atanan_id;
        if v_hedef is null or pdks.kullanici_calisani(v_hedef) = s.calisan_id then
            v_hedef := pdks.ik_sorumlusu(s.calisan_id);
        end if;
        update pdks.amir_sorusu
        set durum = 'eskale', eskale_zamani = now(), eskale_edilen_id = v_hedef
        where id = s.id;
        v_say := v_say + 1;
        perform pdks.uyari_yaz('soru_eskale', 'soru:' || s.id,
            format('%s tarihli soru süresinde cevaplanmadı; üst amire / İK''ya gitti.', to_char(s.is_gunu, 'DD.MM.YYYY')),
            s.calisan_id);
    end loop;
    return v_say;
end;
$function$;

-- ---------------------------------------------------------------------
-- 3. soru_ik_karari: İK her açık soruya karar verebilir. Değişen tek koşul.
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
        cevap_aciklama = concat_ws(' | ', cevap_aciklama, 'İK: ' || p_gerekce)
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
