-- =====================================================================
-- Geriye dönük vardiya planının onayı ve reddi
--
-- Önceden gece işi İK onayı bekleyen planı hemen kullanıyordu; ret hiçbir şeyi geri almıyordu.
-- Onay da zaten işlenmiş günü değiştirmiyordu (plan değişikliği gün kaydına yansımaz).
-- Artık:
--   * Gece işi onay bekleyen ya da reddedilmiş planı kullanmaz; o gün onaya kadar işlenmez.
--   * Onay: gün işlenmişse vardiya düzeltmesi yazılır ve gün hemen hesaplanır (kilitli ayda
--     düzeltme fark satırı olur, gün değişmez); gün işlenmemişse o gün gece işinden geçer.
--   * Ret: hiçbir şey değişmez. Gün işlenmemişse ay kilidi onu zorla geçilemeyen
--     "işlenmemiş planlı gün" sayar ve mesajda reddedilmiş plan olduğunu söyler.
--   * Onay bekleyen planın günü hiç işlenmemişse o da zorla geçilemeyen "işlenmemiş planlı gün"
--     sayılır (önce onaylanmalı ya da reddedilmeli). Gün eski planla işlenmişse onay bekleyen plan
--     zorla geçilebilen "bekleyen plan" sayısında kalır.
--   * Görevler ayrılığı: kimse kendi çalışan kaydına ait planı onaylayamaz ya da reddedemez.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Gece işi: onay bekleyen / reddedilmiş plan kullanılmaz (yalnızca bir koşul eklendi)
-- ---------------------------------------------------------------------
create or replace function pdks.gece_isi_gun_kayitlari(p_gun date, p_gece_isi_id bigint)
returns integer
language plpgsql
set search_path = pdks
as $$
declare
    v_n integer;
begin
    with plan as (
        select vp.calisan_id, vp.vardiya_id, vt.pencere_once_dk, vt.pencere_sonra_dk,
               (p_gun + vt.baslangic) at time zone 'Europe/Istanbul' as bas,
               (p_gun + case when vt.gece_yarisini_asar then 1 else 0 end + vt.bitis) at time zone 'Europe/Istanbul' as bit
        from pdks.vardiya_plani vp
        join pdks.vardiya_tanim vt on vt.id = vp.vardiya_id
        -- O gün işte miydi? (aktif alanı çıkış girilince hemen false olur; tarih son günü de kapsar)
        join pdks.calisan c on c.id = vp.calisan_id
                           and p_gun >= c.ise_giris_tarihi
                           and (c.isten_cikis_tarihi is null or p_gun <= c.isten_cikis_tarihi)
        where vp.tarih = p_gun
          -- İK onayı bekleyen ya da reddedilmiş geriye dönük plan hesapta kullanılmaz
          and vp.ik_onay_durumu in ('gerekmez', 'onaylandi')
          and not exists (select 1 from pdks.gun_kaydi g where g.calisan_id = vp.calisan_id and g.is_gunu = p_gun)
    ), tam as (
        select p.* from plan p
        where pdks.pdks_verisi_tam_mi(p.bas - make_interval(mins => p.pencere_once_dk),
                                      p.bit + make_interval(mins => p.pencere_sonra_dk))
    ), okut as (
        select p.calisan_id,
               min(h.okutma_zamani) filter (where h.yon is distinct from 'cikis') as giris,
               max(h.okutma_zamani) filter (where h.yon is distinct from 'giris') as cikis
        from tam p
        join pdks.ham_okutma h
          on h.okutma_zamani between p.bas - make_interval(mins => p.pencere_once_dk)
                                 and p.bit + make_interval(mins => p.pencere_sonra_dk)
        where pdks.okutma_sahibi(h.kart_no, h.okutma_zamani) = p.calisan_id
          and not pdks.okutma_gecersiz_mi(h.id)
        group by p.calisan_id
    ), durumlu as (
        select t.calisan_id, t.vardiya_id, t.bas, t.bit, o.giris,
               case when o.giris is null or o.cikis > o.giris then o.cikis end as cikis,
               (select i.tur from pdks.izin i
                where i.calisan_id = t.calisan_id and p_gun between i.baslangic and i.bitis
                  and i.iptal_zamani is null
                order by i.id limit 1) as izin_turu,
               -- Resmi tatil yalnızca hiç okutma yoksa "tatil"dir; okutma varsa çalışılmış gün işlenir
               exists (select 1 from pdks.resmi_tatil r where r.tarih = p_gun and not r.yarim_gun)
                   and o.giris is null and o.cikis is null as tatil
        from tam t
        left join okut o on o.calisan_id = t.calisan_id
    )
    insert into pdks.gun_kaydi (calisan_id, is_gunu, vardiya_id, planli_baslangic, planli_bitis,
                                giris_zamani, cikis_zamani, giris_kaynagi, cikis_kaynagi,
                                durum, hesap_tamam, gece_isi_id)
    select d.calisan_id, p_gun, d.vardiya_id, d.bas, d.bit,
           d.giris, d.cikis,
           case when d.giris is not null then 'pdks' end,
           case when d.cikis is not null then 'pdks' end,
           case when d.izin_turu = 'rapor' then 'raporlu'
                when d.izin_turu is not null then 'izinli'
                when d.tatil then 'tatil'
                when d.giris is not null and d.cikis is not null then 'tamam'
                else 'eksik' end,
           (d.izin_turu is not null or d.tatil),
           p_gece_isi_id
    from durumlu d;
    get diagnostics v_n = row_count;
    return v_n;
end;
$$;

-- ---------------------------------------------------------------------
-- 2. Plan onayı: günü düzeltir ya da işletir; ret hiçbir şeyi değiştirmez
-- ---------------------------------------------------------------------
create or replace function pdks.vardiya_plani_onayla(p_plan_id bigint, p_onay boolean)
returns void
language plpgsql
security definer
set search_path = pdks
as $$
declare
    v_ben  bigint := pdks.yetki_gerekli('ik');
    v_plan pdks.vardiya_plani;
    v_gun  pdks.gun_kaydi;
begin
    select * into v_plan from pdks.vardiya_plani where id = p_plan_id for update;
    if not found or v_plan.ik_onay_durumu <> 'bekliyor' then
        raise exception 'Onay bekleyen plan bulunamadı.';
    end if;
    if v_plan.giren_id = v_ben then
        raise exception 'Görevler ayrılığı: kendi girdiğiniz planı onaylayamazsınız.';
    end if;
    -- kendi_kaydi_engelle ile aynı kural (planda onaylayan sütunu olmadığı için burada denetlenir)
    if pdks.kullanici_calisani(v_ben) = v_plan.calisan_id then
        raise exception 'Görevler ayrılığı: kimse kendi kaydında işlem yapamaz (vardiya_plani.onay).';
    end if;
    update pdks.vardiya_plani set ik_onay_durumu = case when p_onay then 'onaylandi' else 'reddedildi' end
    where id = p_plan_id;

    -- Ret: hiçbir şey değişmez (gün işlendiyse eski plana göre kalır; işlenmediyse ay kilidi bunu gösterir)
    if not p_onay then
        return;
    end if;

    select * into v_gun from pdks.gun_kaydi where calisan_id = v_plan.calisan_id and is_gunu = v_plan.tarih;
    if found then
        -- Gün işlenmiş: vardiya düzeltmesi (kilitli ayda fark satırı olur) ve hemen hesap
        if v_gun.vardiya_id is distinct from v_plan.vardiya_id then
            perform pdks.duzeltme_uygula(v_gun.id, 'vardiya_id', v_plan.vardiya_id::text,
                'Geriye dönük vardiya planı onaylandı' || coalesce(' (' || v_plan.aciklama || ')', ''),
                'ik', v_ben);
        end if;
        perform pdks.gun_hesapla(v_gun.id);
    elsif not pdks.donem_kilitli_mi(v_plan.tarih)
          and exists (select 1 from pdks.aktarim where kaynak = 'pdks' and veri_tarihi = v_plan.tarih) then
        -- Gün onay beklediği için işlenmemiş: o gün gece işinden yeniden geçer (var olan kayıtlar bozulmaz)
        perform pdks.gece_isi_calistir(v_plan.tarih);
    end if;
end;
$$;

-- ---------------------------------------------------------------------
-- 3. Ay kilidi: reddedilmiş ya da onay bekleyen planın işlenmemiş günü zorla geçilemez;
--    eski planla işlenmiş gündeki onay bekleyen plan "bekleyen plan" olarak zorla geçilebilir
--    (yalnızca işlenmemiş gün kontrolü ve bekleyen plan sayımı değişti)
-- ---------------------------------------------------------------------
create or replace function pdks.ay_kilitle(p_yil smallint, p_ay smallint, p_zorla boolean default false)
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
$$;
