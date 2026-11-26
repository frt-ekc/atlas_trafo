-- =====================================================================
-- K3 · T-92: Zorla kilidin izi yoktu
--
-- Sorun: İK ayı "zorla" kilitleyince açık soru, açık itiraz, onaysız fazla mesai ve bekleyen plan
-- geçiliyor; neyin geçildiği yalnızca o an ekrana dönen özette görünüyordu. donem satırında yalnızca
-- kimin ve ne zaman kilitlediği kalıyordu; zorla olup olmadığı, nedeni ve geçilen kayıtlar hiçbir
-- yerde yoktu. Açık itirazı (KVKK m.11) karara bağlanmadan kapanan ayın izi sürülemiyordu.
--
-- Karar (Yusuf, "birlikte, zorunlu"): zorla kilitte gerekçe zorunlu (en az 10 karakter, baştaki ve
-- sondaki boşluklar sayılmaz). Her kilit (zorla olsun olmasın) pdks.donem_kilit_izi'ne yazılır:
-- zorla mı, gerekçe, kilit anının özeti (ekrana dönen özet + açık sorulu gün, açık itiraz, onaysız
-- fazla mesai ve bekleyen plan listeleri; sicil ve tarih, itiraz metni ve soru açıklaması yok).
--
-- Tasarım notu: raporun önerisi bu bilgileri donem'e sütun olarak eklemekti. donem'i giriş yapmış
-- herkes okuyor (oturum_acan_okur; amir ayın kilitli olup olmadığını görür). Gerekçe ve özet başka
-- departmanların çalışanlarını ve itirazlarını içerdiği için ayrı, yalnızca İK / yönetici okuyan,
-- değiştirilemez bir tabloya yazılır (+1 tablo, 39).
--
-- Ekran (Gökalp): Puantaj sayfasında "Zorla kilitle" işaretlenince gerekçe alanı ve ay_kilitle'ye
-- p_gerekce. Sıra: önce bu migration, sonra ekran. Ekran p_gerekce'yi yalnızca zorla işaretliyse
-- gönderirse sıra ne olursa olsun normal kilit bozulmaz; bu migration'dan sonra ekran güncellenene
-- kadar yalnızca zorla kilit "gerekçe yazılmalıdır" hatası verir.
-- T-92 öncesi kilitlenmiş ayların izi yoktur (o bilgi hiç kaydedilmedi).
-- Kalıcı test: supabase/tests/zorla_kilit_izi_testi.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Kilidin izi
-- ---------------------------------------------------------------------
create table pdks.donem_kilit_izi (
    donem_id       bigint primary key references pdks.donem (id),
    zorla          boolean not null,
    gerekce        text,
    ozet           jsonb not null,
    kilitleyen_id  bigint not null references pdks.kullanici (id),
    kilit_zamani   timestamptz not null default now(),
    constraint donem_kilit_izi_gerekce check (
        (zorla and coalesce(length(trim(gerekce)), 0) >= 10) or (not zorla and gerekce is null))
);
comment on table pdks.donem_kilit_izi is
    'Her ay kilidinin değiştirilemez izi (T-92): zorla mı, gerekçe, kilit anında geçilen kayıtların özeti. Yalnızca İK ve yönetici okur.';
comment on column pdks.donem_kilit_izi.ozet is
    'ay_kilitle''nin döndürdüğü özet + acik_soru_listesi, acik_itiraz_listesi, bekleyen_fazla_mesai_listesi, bekleyen_plan_listesi (sicil, tarih).';

create trigger donem_kilit_izi_degistirilemez before update or delete on pdks.donem_kilit_izi
    for each row execute function pdks.degistirilemez();
create trigger donem_kilit_izi_bosaltilamaz before truncate on pdks.donem_kilit_izi
    for each statement execute function pdks.degistirilemez();

alter table pdks.donem_kilit_izi enable row level security;
create policy ik_yonetici_okur on pdks.donem_kilit_izi for select to authenticated
    using ((select pdks.tum_veriyi_gorur()));
revoke all on pdks.donem_kilit_izi from public, anon, authenticated;
grant select on pdks.donem_kilit_izi to authenticated;

-- ---------------------------------------------------------------------
-- 2. ay_kilitle: gerekçe parametresi, zorla kilitte zorunlu; her kilit ize yazılır
--    (son hâli 20261216010000_ekran_metinleri.sql; yalnızca T-92 ile işaretli kısımlar eklendi)
--    İmza değiştiği için eski fonksiyon kaldırılır. Ekranın bugünkü 3 parametreli çağrısı
--    (p_yil, p_ay, p_zorla) yeni fonksiyona varsayılan p_gerekce ile gider.
-- ---------------------------------------------------------------------
drop function pdks.ay_kilitle(smallint, smallint, boolean);

CREATE FUNCTION pdks.ay_kilitle(p_yil smallint, p_ay smallint, p_zorla boolean DEFAULT false, p_gerekce text DEFAULT NULL::text)
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
        'kodsuz_gun_listesi', v_kodsuz_liste,
        'mesaj', format('%s/%s kilitlendi.', p_ay, p_yil)
                 || case when v_gecilen <> '' then ' Sonuçlanmadan kilitlenen kayıtlar: ' || v_gecilen || '.' else '' end);

    -- T-92: kilidin izi (değiştirilemez; yalnızca İK ve yönetici okur). Zorlamasız kilit de yazılır.
    insert into pdks.donem_kilit_izi (donem_id, zorla, gerekce, ozet, kilitleyen_id)
    values (v_donem, p_zorla, case when p_zorla then v_gerekce end,
            v_sonuc || jsonb_build_object('acik_soru_listesi', v_soru_liste, 'acik_itiraz_listesi', v_itiraz_liste,
                                          'bekleyen_fazla_mesai_listesi', v_fm_liste, 'bekleyen_plan_listesi', v_plan_liste),
            v_ben);

    return v_sonuc;
end;
$$;

revoke execute on function pdks.ay_kilitle(smallint, smallint, boolean, text) from public, anon;
grant execute on function pdks.ay_kilitle(smallint, smallint, boolean, text) to authenticated;
