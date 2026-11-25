-- =====================================================================
-- K4 · T-61: İşlenmiş güne sonradan onaylanan fazla mesai planı günü yeniden hesaplamıyordu
--
-- Amir planı zamanında ister; İK gece işinden SONRA onaylarsa fazla_mesai_karar yalnızca planın
-- durumunu yazıyordu. Gün eski hesabıyla kalıyor (FM 0), süre havuzda bekliyordu. Sonuç, günün
-- ilgisiz bir sebeple yeniden hesaplanıp hesaplanmamasına bağlıydı; ay kilitlenirse süre hiç
-- gelmeyebilirdi. Havuz da kapanmadığı için İK onu da onaylarsa süre yıllık toplama iki kez giriyordu.
--
-- Değişiklik (fazla_mesai_karar; geriye dönük vardiya planı onayıyla aynı kalıp, T-79):
--   * Onay, gün işlenmişse günü hemen yeniden hesaplar (gun_hesabini_yenile) ve gün sonrası
--     kontrollerini çalıştırır: plan sürenin bir kısmını karşılıyorsa havuzda kalanı bekler.
--   * Plan süreyi karşıladıysa bekleyen havuz kaydı kapanır (karar gerekmez; ay kilidini
--     durdurmaz). vardiya_plani_onayla gibi "reddedildi" + açıklama ile: çalışan aleyhine değildir,
--     süre plan üzerinden puantaja girmiştir.
--   * Kilitli aya düşen güne plan onayı verilmez: gün değiştirilemez; süre havuz kararıyla
--     sonraki aya fark satırı olarak gelir.
--   * Havuzdan zaten onaylanmış güne plan onayı verilmez: süre yıllık toplama iki kez girerdi.
-- Ret davranışı değişmez. Fonksiyonun imzası, yetkisi ve hata mesajları aynı kalır.
-- Kalıcı test: supabase/tests/plan_onayi_hesap_testi.sql
-- =====================================================================

create or replace function pdks.fazla_mesai_karar(p_plan_id bigint, p_onay boolean, p_aciklama text default null)
returns void
language plpgsql
security definer
set search_path = pdks
as $$
declare
    v_ben  bigint := pdks.yetki_gerekli('ik');
    v_plan pdks.fazla_mesai_plani;
    v_gun  pdks.gun_kaydi;
begin
    select * into v_plan from pdks.fazla_mesai_plani where id = p_plan_id and durum = 'talep' for update;
    if not found then
        raise exception 'Karar bekleyen fazla mesai talebi bulunamadı.';
    end if;

    if p_onay then
        if pdks.donem_kilitli_mi(v_plan.is_gunu) then
            raise exception '% günü kilitli aya ait; fazla mesai planı onaylanamaz. Çalışılan süre onaysız fazla mesai listesinden karara bağlanır.',
                to_char(v_plan.is_gunu, 'DD.MM.YYYY');
        end if;
        if exists (select 1 from pdks.fazla_mesai_inceleme
                   where calisan_id = v_plan.calisan_id and is_gunu = v_plan.is_gunu and durum = 'onaylandi') then
            raise exception 'Bu günün fazla mesaisi onaysız fazla mesai listesinden onaylanmıştır; plan ayrıca onaylanamaz (süre iki kez sayılırdı).';
        end if;
    end if;

    update pdks.fazla_mesai_plani
    set durum = case when p_onay then 'onaylandi' else 'reddedildi' end,
        karar_veren_id = v_ben, karar_zamani = now(), karar_aciklama = p_aciklama
    where id = p_plan_id;

    if not p_onay then
        return;
    end if;

    -- Gün işlenmişse onay hemen yansır (işlenmemişse gece işi planı zaten görür)
    select * into v_gun from pdks.gun_kaydi where calisan_id = v_plan.calisan_id and is_gunu = v_plan.is_gunu;
    if found and v_gun.hesap_tamam then
        perform pdks.gun_hesabini_yenile(v_gun.id);
        -- Plan sürenin bir kısmını karşılıyorsa havuz kaydı kalan süreye iner
        perform pdks.gun_sonrasi_kontroller(v_gun.id);
        -- Plan süreyi karşıladıysa bekleyen havuz kaydı kapanır
        update pdks.fazla_mesai_inceleme i
        set durum = 'reddedildi', karar_veren_id = v_ben,
            karar_aciklama = 'Fazla mesai planı onaylandı; süre plan üzerinden puantaja girdi'
        from pdks.gun_kaydi g
        where i.gun_kaydi_id = v_gun.id and g.id = v_gun.id and i.durum = 'inceleme_bekliyor'
          and (select h.onaysiz_fm_dk from pdks.gun_hesabi(g.calisan_id, g.is_gunu, g.planli_baslangic, g.planli_bitis,
                                                           g.giris_zamani, g.cikis_zamani, g.vardiya_id) h)
              <= pdks.ayar_al('fm_plansiz_esik_dk');
    end if;
end;
$$;
