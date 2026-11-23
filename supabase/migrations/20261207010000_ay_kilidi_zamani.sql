-- =====================================================================
-- K3 · T-89: İleri bir ay kilitlenebiliyordu; kilit açılamadığı için o ay
-- kalıcı olarak kullanılamaz hale geliyordu
--
-- ay_kilitle ayın bitip bitmediğine bakmıyordu: 22.11.2026'da Ocak 2027
-- kilitlenebildi, sonra o aya vardiya planı girilemedi. Ekran (PR #39) bitmemiş
-- ayı kilitlemiyor; ama kural yalnızca ekranda kalmamalı.
--
-- Değişiklik:
--   * ay_kilitle: ayın son günü İstanbul tarihiyle bugünden önce değilse
--     reddedilir ("henüz bitmedi"). Zorla (p_zorla) da geçilemez. Kontrol, gün
--     hesaplama ve diğer engellerden önce, fonksiyonun en başındadır.
--     Fonksiyonun geri kalanı 20261203010000_plan_onayi.sql'deki son sürümle
--     (pg_get_functiondef) birebir aynıdır; yetkiler korunur.
--   * pdks.bugun(): testler için tarih ayarı. Doğrudan veritabanı bağlantısında
--     (session_user = postgres, ör. psql testleri) "set local pdks.test_bugun =
--     'YYYY-MM-DD'" ile bugün değiştirilebilir. Ekrandan gelen istek
--     (PostgREST, session_user = authenticator) ayarı görmez; her zaman gerçek
--     İstanbul tarihi kullanılır. Ayar yoksa ya da boşsa davranış aynıdır.
--     Kasım ve Aralık 2026'yı kilitleyen ay_kilidi_testi ve erp_aktarim_testi
--     bu ayarla tarihten bağımsız çalışır.
-- Kalıcı test: supabase/tests/ay_kilidi_zamani_testi.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. pdks.bugun(): testler için tarih ayarı (yalnızca doğrudan bağlantı)
-- ---------------------------------------------------------------------
create or replace function pdks.bugun()
returns date
language sql
stable
set search_path = pdks
as $$
    select coalesce(
        case when session_user = 'postgres'
             then nullif(current_setting('pdks.test_bugun', true), '')::date
        end,
        (now() at time zone 'Europe/Istanbul')::date);
$$;
comment on function pdks.bugun() is
    'İstanbul saatine göre bugünün tarihi. Oturumun saat dilimi (canlıda UTC) ne olursa olsun aynı sonucu verir; gün gereken yerde current_date yerine bu kullanılır. Testler için: doğrudan veritabanı bağlantısında (session_user = postgres) "set local pdks.test_bugun = ''YYYY-MM-DD''" bugünü değiştirir; ekrandan gelen istek bu ayarı görmez.';

-- ---------------------------------------------------------------------
-- 2. ay_kilitle: ay bitmeden kilit yok (T-89). Eklenen tek blok "0)".
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pdks.ay_kilitle(p_yil smallint, p_ay smallint, p_zorla boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pdks'
AS $function$
declare
    v_ben       bigint := pdks.yetki_gerekli('ik');
    v_bas       date := make_date(p_yil, p_ay, 1);
    v_bit       date := (make_date(p_yil, p_ay, 1) + interval '1 month - 1 day')::date;
    v_donem     bigint := pdks.donem_bul(make_date(p_yil, p_ay, 1));
    v_eksik     record;
    v_plan      integer;
    v_fm        integer;
    v_soru      integer;
    v_itiraz    integer;
    v_kodsuz    integer;
    v_gecilen   text;
begin
    -- 0) Ay bitmeden kilit yok (T-89): son günü İstanbul tarihiyle bugünden önce olmalı.
    --    Kilit açılamadığı için zorla da geçilemez.
    if v_bit >= pdks.bugun() then
        raise exception '%/% dönemi henüz bitmedi (son gün %). Ay, son günü geçtikten sonra kilitlenir.',
            p_ay, p_yil, to_char(v_bit, 'DD.MM.YYYY');
    end if;

    -- 1) Cevaplanmış ya da düzeltilmiş ama henüz hesaplanmamış günler kilitten önce hesaplanır
    perform pdks.gun_hesapla(g.id)
    from pdks.gun_kaydi g
    where g.is_gunu between v_bas and v_bit and not g.hesap_tamam
    order by g.id;

    -- 2) Gece işinden geçmemiş planlı gün: zorla geçilemez
    --    Reddedilmiş ya da İK onayı bekleyen planın işlenmemiş günü de sayılır: İK doğru planı
    --    girmeden ya da bekleyen planı onaylamadan / reddetmeden ay kapanmaz.
    select count(*) as gun, count(distinct vp.calisan_id) as kisi, min(vp.tarih) as ilk,
           count(*) filter (where vp.ik_onay_durumu = 'reddedildi') as reddedilmis,
           count(*) filter (where vp.ik_onay_durumu = 'bekliyor') as bekleyen
      into v_eksik
    from pdks.vardiya_plani vp
    join pdks.calisan c on c.id = vp.calisan_id
    where vp.tarih between v_bas and v_bit
      and vp.tarih >= c.ise_giris_tarihi
      and (c.isten_cikis_tarihi is null or vp.tarih <= c.isten_cikis_tarihi)
      and not exists (select 1 from pdks.gun_kaydi g where g.calisan_id = vp.calisan_id and g.is_gunu = vp.tarih);
    if v_eksik.gun > 0 then
        raise exception '%/% döneminde gece işinden geçmemiş % planlı gün var (% çalışan; ilk gün %)%. Önce o günlerin dosyalarını yükleyip gece işini çalıştırın%. Bu kontrol zorla geçilemez.',
            p_ay, p_yil, v_eksik.gun, v_eksik.kisi, to_char(v_eksik.ilk, 'DD.MM.YYYY'),
            concat(case when v_eksik.reddedilmis > 0 then format('; %s günün geriye dönük planı reddedilmiş', v_eksik.reddedilmis) end,
                   case when v_eksik.bekleyen > 0 then format('; %s günün geriye dönük planı İK onayı bekliyor', v_eksik.bekleyen) end),
            concat(case when v_eksik.reddedilmis > 0 then '; reddedilmiş plan için doğru planı girin' end,
                   case when v_eksik.bekleyen > 0 then '; İK onayı bekleyen planı önce onaylayın ya da reddedin' end);
    end if;

    -- 3) Bekleyen işler (zorla geçilebilir)
    select count(*) into v_plan
    from pdks.vardiya_plani
    where tarih between v_bas and v_bit and geriye_donuk and ik_onay_durumu = 'bekliyor'
      -- yalnızca eski planla işlenmiş gün (işlenmemiş gün yukarıda, zorla geçilemeyen kontrolde)
      and exists (select 1 from pdks.gun_kaydi g where g.calisan_id = vardiya_plani.calisan_id and g.is_gunu = vardiya_plani.tarih);
    select count(*) into v_fm
    from pdks.fazla_mesai_inceleme
    where durum = 'inceleme_bekliyor' and is_gunu between v_bas and v_bit;
    select count(*) into v_soru
    from pdks.gun_kaydi g
    where g.is_gunu between v_bas and v_bit
      and exists (select 1 from pdks.amir_sorusu s
                  where s.gun_kaydi_id = g.id and s.durum in ('acik', 'eskale', 'ik_karari_bekliyor'));
    select count(*) into v_itiraz
    from pdks.itiraz i join pdks.gun_kaydi g on g.id = i.gun_kaydi_id
    where g.is_gunu between v_bas and v_bit and i.durum in ('acik', 'inceleniyor');

    if not p_zorla then
        if v_plan > 0 then
            raise exception '%/% döneminde İK onayı bekleyen % geriye dönük vardiya planı var.', p_ay, p_yil, v_plan;
        end if;
        if v_fm > 0 then
            raise exception '%/% döneminde İK kararı bekleyen % onaysız fazla mesai var.', p_ay, p_yil, v_fm;
        end if;
    end if;
    -- Açık soru / itiraz kontrolü (ve zorla) donem_kilitle'de
    perform pdks.donem_kilitle(v_donem, v_ben, p_zorla);
    perform pdks.puantaj_yaz(v_donem);

    -- 4) Puantaja kodsuz giren gün: gün kaydı var ama puantaj kodu üretilmedi (ör. açık sorulu gün)
    select count(*) into v_kodsuz
    from pdks.gun_kaydi g
    where g.is_gunu between v_bas and v_bit
      and not exists (select 1 from pdks.gun_kod_satirlari(
                          g.calisan_id, g.is_gunu,
                          case when g.durum = 'tamam' and not g.hesap_tamam then 'eksik' else g.durum end,
                          g.calisma_dk, g.fm50_dk, g.fm100_dk));

    v_gecilen := concat_ws(', ',
        case when v_soru   > 0 then v_soru   || ' açık sorulu gün' end,
        case when v_itiraz > 0 then v_itiraz || ' açık itiraz' end,
        case when v_fm     > 0 then v_fm     || ' onaysız fazla mesai' end,
        case when v_plan   > 0 then v_plan   || ' onay bekleyen geriye dönük plan' end);

    return jsonb_build_object(
        'donem', to_char(v_bas, 'YYYY-MM'),
        'zorla', p_zorla,
        'zorla_gecilen', jsonb_build_object(
            'acik_soru_gun', v_soru, 'acik_itiraz', v_itiraz,
            'bekleyen_fazla_mesai', v_fm, 'bekleyen_plan_onayi', v_plan),
        'kodsuz_gun', v_kodsuz,
        'mesaj', format('%s/%s kilitlendi.', p_ay, p_yil)
                 || case when v_gecilen <> '' then ' Zorla geçilenler: ' || v_gecilen || '.' else '' end
                 || case when v_kodsuz > 0 then format(' Puantaja kodsuz giren gün: %s.', v_kodsuz) else '' end);
end;
$function$;
