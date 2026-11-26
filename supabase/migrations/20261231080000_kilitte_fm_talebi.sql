-- =====================================================================
-- K4 · T-63: Kilitli ayda karar bekleyen fazla mesai talebi askıda kalıyordu; kilit bunu söylemiyordu
--
-- Sorun: Amir 13 Ekim'de "yarın 2 saat kalsın" talebini girer, İK karar vermez, ay kilitlenir.
-- Kilit talepleri saymıyordu (yalnızca havuzu); kilitten sonra talep ne onaylanabiliyor ne
-- reddedilebiliyordu (fazla_mesai_plani_kontrol kilitli ayda her değişikliği reddeder). Talep İK
-- ekranında sonsuza kadar "karar bekliyor" kalıyordu.
--
-- Karar (Yusuf, A seçeneği): kilit, o ayın karar bekleyen taleplerini kendisi kapatır ("iptal",
-- kişisiz, açıklama "Dönem kilitlendi ..."), kilit mesajına ve kilit izine yazar. Kilidi durdurmaz:
-- gün geçtikten sonra talebin tek başına puantaja etkisi yoktur; çalışılan süre varsa havuza
-- (fazla_mesai_inceleme) düşmüştür, o kilidi zaten durdurur ve kilitten sonra da karara bağlanıp
-- fark satırı olur. Kilit başarısız olursa (hata) kapatma da geri alınır.
-- Kişisiz iptal yalnızca ay_kilitle içinden yapılabilir: işlem süresince açılan pdks.kilit_kapanisi
-- ayarı. Ekran kullanıcısı tabloyu doğrudan değiştiremez (yalnızca SELECT yetkisi var).
-- Kalıcı test: supabase/tests/kilitte_fm_talebi_testi.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Fazla mesai planı tetikleyicisi (son hâli 20261216010000; yalnızca kişisiz iptal koşulu değişti)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pdks.fazla_mesai_plani_kontrol()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pdks'
AS $function$
declare
    v_toplam  integer;
    v_esik    integer;
begin
    if tg_op = 'DELETE' then
        raise exception 'Fazla mesai planı silinemez; iptal edilir.';
    end if;

    if pdks.donem_kilitli_mi(case when tg_op = 'INSERT' then new.is_gunu else old.is_gunu end) then
        raise exception '% günü kilitli bir döneme ait; fazla mesai planı değişmez.', new.is_gunu;
    end if;

    -- Yeni talep -------------------------------------------------------
    if tg_op = 'INSERT' then
        if new.durum <> 'talep' then
            raise exception 'Yeni plan "talep" olarak girilir; onayı İK verir.';
        end if;
        if pdks.kullanici_rolu(new.talep_eden_id) not in ('amir', 'ik')
           or pdks.kullanici_rolu(new.talep_eden_id) is null then
            raise exception 'Fazla mesaiyi yalnızca amir ya da İK talep eder.';
        end if;
        select vardiya_id into new.vardiya_id
        from pdks.vardiya_plani where calisan_id = new.calisan_id and tarih = new.is_gunu;
        if new.vardiya_id is null then
            raise exception 'Çalışanın % günü için vardiya planı yok.', new.is_gunu;
        end if;
        new.talep_zamani := now();
        new.karar_veren_id := null;
        new.karar_aciklama := null;
        perform pdks.fm_plan_denetle(new.calisan_id, new.is_gunu, new.vardiya_id, new.planli_dk, new.id);
        return new;
    end if;

    -- Güncelleme: yalnızca durum geçişi ------------------------------
    if (new.calisan_id, new.is_gunu, new.vardiya_id, new.planli_dk, new.gerekce,
        new.talep_eden_id, new.talep_zamani)
       is distinct from
       (old.calisan_id, old.is_gunu, old.vardiya_id, old.planli_dk, old.gerekce,
        old.talep_eden_id, old.talep_zamani) then
        raise exception 'Planın içeriği değiştirilemez; iptal edip yeni talep girin.';
    end if;
    if new.durum = old.durum then
        if new is distinct from old then
            raise exception 'Plan kararı değiştirilemez.';
        end if;
        return new;
    end if;
    if old.durum in ('reddedildi', 'iptal') then
        raise exception 'Karara bağlanmış plan değiştirilemez.';
    end if;
    if old.durum = 'onaylandi' and new.durum <> 'iptal' then
        raise exception 'Onaylı plan yalnızca iptal edilebilir.';
    end if;

    if new.durum in ('onaylandi', 'reddedildi') then
        if pdks.kullanici_rolu(new.karar_veren_id) is distinct from 'ik' then
            raise exception 'Fazla mesai planını yalnızca İK onaylar veya reddeder.';
        end if;
        if new.durum = 'onaylandi' then
            v_toplam := pdks.fm_plan_denetle(new.calisan_id, new.is_gunu, new.vardiya_id, new.planli_dk, new.id);
            v_esik := pdks.ayar_al('fm_yillik_sinir_dk') * pdks.ayar_al('fm_yaklasma_uyari_yuzde') / 100;
            -- Eşiği bu onayla geçtiyse bir kez uyar
            if v_toplam >= v_esik and v_toplam - new.planli_dk < v_esik then
                insert into pdks.uyari (tur, calisan_id, mesaj)
                values ('fm_yillik_sinir_yaklasti', new.calisan_id,
                        format('Yıllık onaylı fazla mesai süresi %s oldu (sınır %s).',
                               pdks.sure_metni(v_toplam::integer), pdks.sure_metni(pdks.ayar_al('fm_yillik_sinir_dk'))));
            end if;
        end if;
    elsif new.durum = 'iptal' then
        if new.karar_veren_id is null then
            -- Kişisiz (sistem) iptal yalnızca yazılı onay o gün için geçersizse olur
            -- ya da ay kilidi bekleyen talebi kapatırken (T-63; ayar yalnızca ay_kilitle içinde açılır)
            if pdks.fm_onay_gecerli_mi(new.calisan_id, new.is_gunu)
               and not (old.durum = 'talep'
                        and coalesce(current_setting('pdks.kilit_kapanisi', true), '') = 'evet') then
                raise exception 'İptal eden kullanıcı belirtilmeli.';
            end if;
        else
            if pdks.kullanici_rolu(new.karar_veren_id) not in ('amir', 'ik')
               or pdks.kullanici_rolu(new.karar_veren_id) is null then
                raise exception 'Planı yalnızca amir ya da İK iptal eder.';
            end if;
            if old.durum = 'onaylandi' and old.is_gunu < pdks.bugun() then
                raise exception 'Geçmiş bir günün onaylı planı iptal edilemez.';
            end if;
        end if;
    else
        raise exception 'Geçersiz durum geçişi: % -> %', old.durum, new.durum;
    end if;

    new.karar_zamani := now();
    return new;
end;
$function$;

-- ---------------------------------------------------------------------
-- 2. Ay kilidi (son hâli T-92): bekleyen talepler kapanır; sonuçta ve izde görünür
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pdks.ay_kilitle(p_yil smallint, p_ay smallint, p_zorla boolean DEFAULT false, p_gerekce text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pdks'
AS $$
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
    v_kodsuz_liste jsonb;
    v_kodsuz_metin text;
    v_gecilen   text;
    -- T-92: zorla kilidin gerekçesi ve kilit anının özeti (donem_kilit_izi)
    v_gerekce   text := nullif(trim(p_gerekce), '');
    v_soru_liste   jsonb;
    v_itiraz_liste jsonb;
    v_fm_liste     jsonb;
    v_plan_liste   jsonb;
    -- T-63: kilitle kapatılan, karar bekleyen fazla mesai talepleri
    v_talep        integer;
    v_talep_liste  jsonb;
    v_sonuc     jsonb;
begin
    -- 0) Ay bitmeden kilit yok (T-89): son günü İstanbul tarihiyle bugünden önce olmalı.
    --    Kilit açılamadığı için zorla da geçilemez.
    if v_bit >= pdks.bugun() then
        raise exception '%/% dönemi henüz bitmedi (son gün %). Ay, son günü geçtikten sonra kilitlenir.',
            p_ay, p_yil, to_char(v_bit, 'DD.MM.YYYY');
    end if;

    -- T-92: zorla kilit gerekçesiz olmaz (açık itiraz ve soruları da geçebildiği için izli olmalı)
    if p_zorla and coalesce(length(v_gerekce), 0) < 10 then
        raise exception 'Zorla kilitte gerekçe yazılmalıdır (en az 10 karakter).';
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
        raise exception '%/% döneminde işlenmemiş % planlı gün bulunuyor (% çalışan, ilk gün %)%. Kilitlemeden önce bu günler işlenmelidir%.',
            p_ay, p_yil, v_eksik.gun, v_eksik.kisi, to_char(v_eksik.ilk, 'DD.MM.YYYY'),
            concat(case when v_eksik.reddedilmis > 0 then format('; %s günün geriye dönük planı reddedilmiş', v_eksik.reddedilmis) end,
                   case when v_eksik.bekleyen > 0 then format('; %s günün geriye dönük planı İK onayı bekliyor', v_eksik.bekleyen) end),
            concat(case when v_eksik.reddedilmis > 0 then '; reddedilen planın yerine geçerli plan girilmelidir' end,
                   case when v_eksik.bekleyen > 0 then '; İK onayı bekleyen plan onaylanmalı veya reddedilmelidir' end);
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
    -- T-92: kilit anında açık olanların listesi (iz için; itiraz metni ve soru açıklaması yazılmaz)
    select coalesce(jsonb_agg(jsonb_build_object('sicil', c.sicil_no, 'tarih', g.is_gunu,
                                                 'soru_turu', s.soru_turu, 'durum', s.durum)
                              order by g.is_gunu, c.sicil_no), '[]'::jsonb)
      into v_soru_liste
    from pdks.amir_sorusu s
    join pdks.gun_kaydi g on g.id = s.gun_kaydi_id
    join pdks.calisan c on c.id = g.calisan_id
    where g.is_gunu between v_bas and v_bit and s.durum in ('acik', 'eskale', 'ik_karari_bekliyor');
    select coalesce(jsonb_agg(jsonb_build_object('itiraz_id', i.id, 'sicil', c.sicil_no, 'tarih', g.is_gunu, 'durum', i.durum)
                              order by g.is_gunu, c.sicil_no), '[]'::jsonb)
      into v_itiraz_liste
    from pdks.itiraz i
    join pdks.gun_kaydi g on g.id = i.gun_kaydi_id
    join pdks.calisan c on c.id = g.calisan_id
    where g.is_gunu between v_bas and v_bit and i.durum in ('acik', 'inceleniyor');
    select coalesce(jsonb_agg(jsonb_build_object('sicil', c.sicil_no, 'tarih', f.is_gunu) order by f.is_gunu, c.sicil_no), '[]'::jsonb)
      into v_fm_liste
    from pdks.fazla_mesai_inceleme f
    join pdks.calisan c on c.id = f.calisan_id
    where f.durum = 'inceleme_bekliyor' and f.is_gunu between v_bas and v_bit;
    select coalesce(jsonb_agg(jsonb_build_object('sicil', c.sicil_no, 'tarih', vp.tarih) order by vp.tarih, c.sicil_no), '[]'::jsonb)
      into v_plan_liste
    from pdks.vardiya_plani vp
    join pdks.calisan c on c.id = vp.calisan_id
    where vp.tarih between v_bas and v_bit and vp.geriye_donuk and vp.ik_onay_durumu = 'bekliyor'
      and exists (select 1 from pdks.gun_kaydi g where g.calisan_id = vp.calisan_id and g.is_gunu = vp.tarih);

    -- T-63: ayın karar bekleyen fazla mesai talepleri kilitle kapanır (kilidi durdurmaz). Kilit
    --       sonradan hata verirse bu da geri alınır. Tetikleyici kilitli ayda değişikliği reddettiği
    --       için kapatma donem_kilitle'den önce yapılır.
    select count(*),
           coalesce(jsonb_agg(jsonb_build_object('sicil', c.sicil_no, 'tarih', p.is_gunu, 'planli_dk', p.planli_dk)
                              order by p.is_gunu, c.sicil_no), '[]'::jsonb)
      into v_talep, v_talep_liste
    from pdks.fazla_mesai_plani p
    join pdks.calisan c on c.id = p.calisan_id
    where p.durum = 'talep' and p.is_gunu between v_bas and v_bit;
    if v_talep > 0 then
        perform set_config('pdks.kilit_kapanisi', 'evet', true);
        update pdks.fazla_mesai_plani
        set durum = 'iptal', karar_veren_id = null,
            karar_aciklama = 'Dönem kilitlendi; karar verilmemiş talep kapatıldı. Çalışılan süre varsa onaysız fazla mesai listesinden karara bağlanır.'
        where durum = 'talep' and is_gunu between v_bas and v_bit;
        perform set_config('pdks.kilit_kapanisi', '', true);
    end if;

    -- Açık soru / itiraz kontrolü (ve zorla) donem_kilitle'de
    perform pdks.donem_kilitle(v_donem, v_ben, p_zorla);
    perform pdks.puantaj_yaz(v_donem);

    -- 4) Puantaja kodsuz girecek gün (T-90, T-101): gün kaydı var ama puantaj kodu üretilmiyor
    --    (ör. açık sorulu, tek saatli cevaplı ya da hesaplanmamış gün). Kilit ve puantaj yukarıda
    --    yazıldı; zorlamadan kilitte kodsuz gün varsa hata bütün işlemi (kilit dahil) geri alır.
    select count(*),
           coalesce(jsonb_agg(jsonb_build_object(
                        'sicil', c.sicil_no, 'gun', g.is_gunu, 'durum', g.durum,
                        'neden', case
                            when exists (select 1 from pdks.amir_sorusu s
                                         where s.gun_kaydi_id = g.id
                                           and s.durum in ('acik', 'eskale', 'ik_karari_bekliyor'))
                                then 'açık soru'
                            when g.durum = 'tamam' and not g.hesap_tamam then 'hesap tamamlanmadı'
                            else replace(g.durum, '_', ' ')
                        end)
                    order by c.sicil_no, g.is_gunu), '[]'::jsonb)
      into v_kodsuz, v_kodsuz_liste
    from pdks.gun_kaydi g
    join pdks.calisan c on c.id = g.calisan_id
    where g.is_gunu between v_bas and v_bit
      and not exists (select 1 from pdks.gun_kod_satirlari(
                          g.calisan_id, g.is_gunu,
                          case when g.durum = 'tamam' and not g.hesap_tamam then 'eksik' else g.durum end,
                          g.calisma_dk, g.fm50_dk, g.fm100_dk));

    if v_kodsuz > 0 and not p_zorla then
        select string_agg(format('%s %s (%s)', e ->> 'sicil', to_char((e ->> 'gun')::date, 'DD.MM.YYYY'), e ->> 'neden'),
                          ', ' order by n)
          into v_kodsuz_metin
        from jsonb_array_elements(v_kodsuz_liste) with ordinality as x(e, n)
        where n <= 10;
        -- En çok 10 gün yazılır; kalanı sayılır
        if v_kodsuz > 10 then
            v_kodsuz_metin := v_kodsuz_metin || format(' ve %s gün daha', v_kodsuz - 10);
        end if;
        raise exception '%/% döneminde % gün için puantaj kodu oluşmadı: %. Bu günler kilitlemeden önce sonuçlandırılmalıdır.',
            p_ay, p_yil, v_kodsuz, v_kodsuz_metin;
    end if;

    v_gecilen := concat_ws(', ',
        case when v_soru   > 0 then v_soru   || ' açık sorulu gün' end,
        case when v_itiraz > 0 then v_itiraz || ' açık itiraz' end,
        case when v_fm     > 0 then v_fm     || ' onaysız fazla mesai' end,
        case when v_plan   > 0 then v_plan   || ' onay bekleyen geriye dönük plan' end,
        case when v_kodsuz > 0 then v_kodsuz || ' kodsuz gün' end);

    v_sonuc := jsonb_build_object(
        'donem', to_char(v_bas, 'YYYY-MM'),
        'zorla', p_zorla,
        'zorla_gerekce', case when p_zorla then v_gerekce end,
        'zorla_gecilen', jsonb_build_object(
            'acik_soru_gun', v_soru, 'acik_itiraz', v_itiraz,
            'bekleyen_fazla_mesai', v_fm, 'bekleyen_plan_onayi', v_plan),
        'kodsuz_gun', v_kodsuz,
        'kapatilan_fm_talebi', v_talep,
        'kodsuz_gun_listesi', v_kodsuz_liste,
        'mesaj', format('%s/%s kilitlendi.', p_ay, p_yil)
                 || case when v_gecilen <> '' then ' Sonuçlanmadan kilitlenen kayıtlar: ' || v_gecilen || '.' else '' end
                 || case when v_talep > 0 then format(' Karar bekleyen %s fazla mesai talebi kapatıldı.', v_talep) else '' end);

    -- T-92: kilidin izi (değiştirilemez; yalnızca İK ve yönetici okur). Zorlamasız kilit de yazılır.
    insert into pdks.donem_kilit_izi (donem_id, zorla, gerekce, ozet, kilitleyen_id)
    values (v_donem, p_zorla, case when p_zorla then v_gerekce end,
            v_sonuc || jsonb_build_object('acik_soru_listesi', v_soru_liste, 'acik_itiraz_listesi', v_itiraz_liste,
                                          'bekleyen_fazla_mesai_listesi', v_fm_liste, 'bekleyen_plan_listesi', v_plan_liste,
                                          'kapatilan_fm_talep_listesi', v_talep_liste),
            v_ben);

    return v_sonuc;
end;
$$;

revoke execute on function pdks.ay_kilitle(smallint, smallint, boolean, text) from public, anon;
grant execute on function pdks.ay_kilitle(smallint, smallint, boolean, text) to authenticated;
