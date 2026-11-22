-- =====================================================================
-- Ay kilidi: onay bekleyen geriye dönük plan ve kilit özeti
--
--   1. İK onayı bekleyen geriye dönük vardiya planı kilidi durdurmuyordu. Artık diğer
--      bekleyen işler gibi: zorlamadan kilit reddedilir, zorla geçilebilir.
--   2. ay_kilitle sonuç döner (jsonb): zorla geçilen kalemlerin sayısı ve "puantaja kodsuz
--      giren gün sayısı" (zorla kilitlenen açık sorulu gün puantajda hiçbir kod almaz:
--      ne NÇ ne HT). Ekran bunu kilitten sonra gösterir.
-- Dönüş tipi değiştiği için fonksiyon silinip yeniden oluşturulur; yetkiler yeniden verilir.
-- Kilidin geri kalanı 20261201010000 ile aynı.
-- =====================================================================

drop function pdks.ay_kilitle(smallint, smallint, boolean);

create function pdks.ay_kilitle(p_yil smallint, p_ay smallint, p_zorla boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = pdks
as $$
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
    -- 1) Cevaplanmış ya da düzeltilmiş ama henüz hesaplanmamış günler kilitten önce hesaplanır
    perform pdks.gun_hesapla(g.id)
    from pdks.gun_kaydi g
    where g.is_gunu between v_bas and v_bit and not g.hesap_tamam
    order by g.id;

    -- 2) Gece işinden geçmemiş planlı gün: zorla geçilemez
    select count(*) as gun, count(distinct vp.calisan_id) as kisi, min(vp.tarih) as ilk
      into v_eksik
    from pdks.vardiya_plani vp
    join pdks.calisan c on c.id = vp.calisan_id
    where vp.tarih between v_bas and v_bit
      and vp.tarih >= c.ise_giris_tarihi
      and (c.isten_cikis_tarihi is null or vp.tarih <= c.isten_cikis_tarihi)
      and not exists (select 1 from pdks.gun_kaydi g where g.calisan_id = vp.calisan_id and g.is_gunu = vp.tarih);
    if v_eksik.gun > 0 then
        raise exception '%/% döneminde gece işinden geçmemiş % planlı gün var (% çalışan; ilk gün %). Önce o günlerin dosyalarını yükleyip gece işini çalıştırın. Bu kontrol zorla geçilemez.',
            p_ay, p_yil, v_eksik.gun, v_eksik.kisi, to_char(v_eksik.ilk, 'DD.MM.YYYY');
    end if;

    -- 3) Bekleyen işler (zorla geçilebilir)
    select count(*) into v_plan
    from pdks.vardiya_plani
    where tarih between v_bas and v_bit and geriye_donuk and ik_onay_durumu = 'bekliyor';
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
$$;

revoke execute on function pdks.ay_kilitle(smallint, smallint, boolean) from public, anon;
grant execute on function pdks.ay_kilitle(smallint, smallint, boolean) to authenticated;
