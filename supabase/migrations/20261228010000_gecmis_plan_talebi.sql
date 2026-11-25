-- =====================================================================
-- K4 · T-76: Geçmiş, çalışılmış bir güne "planlı" fazla mesai talebi girilebiliyordu
--
-- "Planlı fazla mesai" çalışmadan önce verilen karardır; habersiz kalınan süre ise havuza düşer
-- ve İK ayrıca inceler (neden kalındı, kim izin verdi). fazla_mesai_talep_et tarih denetlemiyordu:
-- amir iş bittikten sonra geçmiş güne talep girip plansız çalışmayı planlıymış gibi gösterebiliyordu.
-- T-61'den sonra bu daha önemli: plan onayı havuzdaki karşılığı kapattığı için geriye dönük talep
-- İK'nın havuz incelemesini tamamen atlatırdı. (Geçmiş günün onaylı planını iptal etmek zaten yasaktı.)
--
-- Karar (Yusuf, Fırat; 25.11.2026): talep, girildiği gün (İstanbul, pdks.bugun) bugün ya da sonrası
-- için olmalıdır. "Bugün 2 saat daha kal" serbesttir. Amir planı girmeyi unuttuysa çalışılan süre
-- kaybolmaz: gece işi onu havuza koyar, İK oradan onaylar (amirin açıklaması karar açıklamasına yazılır).
-- Denetim talep anındadır, onay anında değil: zamanında girilmiş talep gün geçtikten sonra da
-- onaylanabilir (T-61).
--
-- Ekran rolü fazla_mesai_plani tablosuna yalnızca SELECT yetkisiyle erişir; yeni plan yalnızca bu
-- fonksiyonla girilir. Örnek veri ve testlerin doğrudan eklediği planlar etkilenmez.
-- Kalıcı test: supabase/tests/gecmis_plan_talebi_testi.sql
-- =====================================================================

create or replace function pdks.fazla_mesai_talep_et(p_calisan_id bigint, p_is_gunu date, p_planli_dk integer, p_gerekce text)
returns bigint
language plpgsql
security definer
set search_path = pdks
as $$
declare
    v_ben  bigint := pdks.yetki_gerekli('amir', 'ik');
    v_id   bigint;
begin
    perform pdks.calisan_yetkisi(p_calisan_id);
    -- T-76: plan çalışmadan önce yapılır; geçmiş günün süresi havuzdan (İK incelemesi) gelir
    if p_is_gunu < pdks.bugun() then
        raise exception 'Geçmiş bir güne fazla mesai planı girilemez (%). Çalışılan süre onaysız fazla mesai listesinden İK kararına bağlanır.',
            to_char(p_is_gunu, 'DD.MM.YYYY');
    end if;
    insert into pdks.fazla_mesai_plani (calisan_id, is_gunu, vardiya_id, planli_dk, gerekce, talep_eden_id)
    values (p_calisan_id, p_is_gunu,
            (select vardiya_id from pdks.vardiya_plani where calisan_id = p_calisan_id and tarih = p_is_gunu),
            p_planli_dk, p_gerekce, v_ben)
    returning id into v_id;
    return v_id;
end;
$$;
