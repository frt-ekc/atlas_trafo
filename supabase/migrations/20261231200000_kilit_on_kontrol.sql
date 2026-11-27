-- =====================================================================
-- T-52, T-96, T-54, T-85: Ay kilidi ön kontrolü, düzeltmesiz kabul edilmiş itiraz, izinli günde okutma,
-- kaybolan geçici kart
--
-- T-96: Kilit engelleri tek tek bildiriliyordu: Ekim'i temiz kapatmak 7 deneme sürdü, her denemede
--       yalnızca ilk engel geldi. pdks.ay_kilit_on_kontrol(yıl, ay): bütün engelleri (zorla geçilemez /
--       geçilebilir / bilgi) ve kodsuz kalacak günleri tek seferde döner; hiçbir şeyi değiştirmez.
--       ay_kilitle'nin kurallarının aynısını okur (ay_kilitle'ye dokunulmadı; yalnızca T-52 eklendi).
--       Ekranda kilit düğmesinin yanında gösterilmesi Gökalp'te.
-- T-52: Kabul edilip düzeltmesi yapılmayan itiraz kilitte hiç görünmüyordu. Kilit özetinde ve izinde
--       "düzeltmesiz kabul edilmiş itiraz" sayılır (bilgi; düzeltme kilitten sonra fark olarak yapılabilir).
-- T-54: Önceden izin girilmiş günde kişi kart okuttuysa gün sessizce "izinli" oluyordu (saatler yazılı,
--       çalışma yok, uyarı yok). Gün kaydı izinli / raporlu ve okutmalı yazılınca İK'ya
--       izin_gununde_okutma uyarısı (T-46'daki türle aynı; amire görünmez). Gece işi fonksiyonlarına
--       dokunulmadı (Mehmet'in #105'i gece_isi_uyarilar'ı değiştiriyor): gun_kaydi'nda AFTER INSERT tetikleyici.
-- T-85: Kaybolan geçici kart sistemde "kayıp" yapılamıyordu (doğrudan güncelleme yetkisi yok, fonksiyon yok).
--       pdks.gecici_kart_durum(kart, durum, gerekçe): güvenlik / İK; kim, ne zaman, neden yazılır; kayıp
--       yapılırken açık zimmet kapanır; kayıp kart bulunursa yeniden aktif olur, iptal kesindir. Kayıp
--       bildirilen kart okutulursa İK'ya uyarı (okutma_isareti'nde tetikleyici; gece işine dokunulmadı).
--       Ekranda düğme Gökalp'te.
-- Kalıcı testler: kilit_on_kontrol_testi.sql (T-96, T-52), izinli_gun_okutma_testi.sql (T-54),
--                 gecici_kart_kayip_testi.sql (T-85)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. T-52: ay kilidi (son hâli T-63; yalnızca düzeltmesiz kabul edilmiş itiraz bilgisi)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pdks.ay_kilitle(p_yil smallint, p_ay smallint, p_zorla boolean DEFAULT false, p_gerekce text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pdks', 'pg_temp'
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
    -- T-52: kabul edilmiş ama düzeltmeye bağlanmamış itirazlar (bilgi; kilidi durdurmaz)
    v_kabul        integer;
    v_kabul_liste  jsonb;
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

    -- T-52: kabul edilmiş ama hiçbir düzeltmeye bağlanmamış itirazlar (düzeltme kilitten sonra da
    --       yapılabilir, sonraki aya fark olur; kilit yalnızca söyler)
    select count(*),
           coalesce(jsonb_agg(jsonb_build_object('itiraz_id', i.id, 'sicil', c.sicil_no, 'tarih', g.is_gunu)
                              order by g.is_gunu, c.sicil_no), '[]'::jsonb)
      into v_kabul, v_kabul_liste
    from pdks.itiraz i
    join pdks.gun_kaydi g on g.id = i.gun_kaydi_id
    join pdks.calisan c on c.id = g.calisan_id
    where g.is_gunu between v_bas and v_bit and i.durum = 'kabul'
      and not exists (select 1 from pdks.duzeltme d where d.itiraz_id = i.id);

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
        'duzeltmesiz_kabul_itiraz', v_kabul,
        'kodsuz_gun_listesi', v_kodsuz_liste,
        'mesaj', format('%s/%s kilitlendi.', p_ay, p_yil)
                 || case when v_gecilen <> '' then ' Sonuçlanmadan kilitlenen kayıtlar: ' || v_gecilen || '.' else '' end
                 || case when v_talep > 0 then format(' Karar bekleyen %s fazla mesai talebi kapatıldı.', v_talep) else '' end
                 || case when v_kabul > 0 then format(' Düzeltmesi yapılmamış %s kabul edilmiş itiraz var; düzeltme sonraki aya fark olarak yapılabilir.', v_kabul) else '' end);

    -- T-92: kilidin izi (değiştirilemez; yalnızca İK ve yönetici okur). Zorlamasız kilit de yazılır.
    insert into pdks.donem_kilit_izi (donem_id, zorla, gerekce, ozet, kilitleyen_id)
    values (v_donem, p_zorla, case when p_zorla then v_gerekce end,
            v_sonuc || jsonb_build_object('acik_soru_listesi', v_soru_liste, 'acik_itiraz_listesi', v_itiraz_liste,
                                          'bekleyen_fazla_mesai_listesi', v_fm_liste, 'bekleyen_plan_listesi', v_plan_liste,
                                          'kapatilan_fm_talep_listesi', v_talep_liste,
                                          'duzeltmesiz_kabul_itiraz_listesi', v_kabul_liste),
            v_ben);

    return v_sonuc;
end;
$$;

revoke execute on function pdks.ay_kilitle(smallint, smallint, boolean, text) from public, anon;
grant execute on function pdks.ay_kilitle(smallint, smallint, boolean, text) to authenticated;

-- ---------------------------------------------------------------------
-- 2. T-96: ön kontrol (yalnızca okur). İç fonksiyon yetki denetlemez; ekran dıştakini çağırır (yalnızca İK).
--    Her engel: kod, tur (zorla_gecilemez / zorla_gecilebilir / bilgi), sayi, mesaj, liste (en çok 50).
-- ---------------------------------------------------------------------
create function pdks.ay_kilit_on_kontrol_ic(p_yil smallint, p_ay smallint)
returns jsonb
language plpgsql
stable
set search_path = pdks, pg_temp
as $$
declare
    v_bas     date := make_date(p_yil, p_ay, 1);
    v_bit     date := (make_date(p_yil, p_ay, 1) + interval '1 month - 1 day')::date;
    v_engel   jsonb := '[]'::jsonb;
    v_n       integer;
    v_liste   jsonb;
begin
    if pdks.donem_kilitli_mi(v_bas) then
        return jsonb_build_object('donem', to_char(v_bas, 'YYYY-MM'), 'kilitli', true,
                                  'kilitlenebilir', false, 'zorlamadan_kilitlenebilir', false, 'engeller', '[]'::jsonb);
    end if;

    -- Ay bitmedi (T-89): zorla da geçilemez
    if v_bit >= pdks.bugun() then
        v_engel := v_engel || jsonb_build_object('kod', 'ay_bitmedi', 'tur', 'zorla_gecilemez', 'sayi', 1,
            'mesaj', format('Dönem henüz bitmedi (son gün %s).', to_char(v_bit, 'DD.MM.YYYY')), 'liste', '[]'::jsonb);
    end if;

    -- İşlenmemiş planlı gün: zorla da geçilemez
    select count(*), coalesce(jsonb_agg(x.o order by x.gun, x.sicil) filter (where x.sira <= 50), '[]'::jsonb)
      into v_n, v_liste
    from (select vp.tarih as gun, c.sicil_no as sicil,
                 jsonb_build_object('sicil', c.sicil_no, 'ad_soyad', c.ad || ' ' || c.soyad, 'gun', vp.tarih,
                                    'plan_onayi', vp.ik_onay_durumu) as o,
                 row_number() over (order by vp.tarih, c.sicil_no) as sira
          from pdks.vardiya_plani vp
          join pdks.calisan c on c.id = vp.calisan_id
          where vp.tarih between v_bas and v_bit
            and vp.tarih >= c.ise_giris_tarihi
            and (c.isten_cikis_tarihi is null or vp.tarih <= c.isten_cikis_tarihi)
            and not exists (select 1 from pdks.gun_kaydi g where g.calisan_id = vp.calisan_id and g.is_gunu = vp.tarih)) x;
    if v_n > 0 then
        v_engel := v_engel || jsonb_build_object('kod', 'islenmemis_plan_gunu', 'tur', 'zorla_gecilemez', 'sayi', v_n,
            'mesaj', format('%s planlı gün gece işinden geçmedi; bu günler işlenmeden ay kilitlenemez.', v_n), 'liste', v_liste);
    end if;

    -- Onay bekleyen geriye dönük plan (eski planla işlenmiş gün): zorla geçilebilir
    select count(*), coalesce(jsonb_agg(x.o) filter (where x.sira <= 50), '[]'::jsonb) into v_n, v_liste
    from (select jsonb_build_object('sicil', c.sicil_no, 'ad_soyad', c.ad || ' ' || c.soyad, 'gun', vp.tarih) as o,
                 row_number() over (order by vp.tarih, c.sicil_no) as sira
          from pdks.vardiya_plani vp join pdks.calisan c on c.id = vp.calisan_id
          where vp.tarih between v_bas and v_bit and vp.geriye_donuk and vp.ik_onay_durumu = 'bekliyor'
            and exists (select 1 from pdks.gun_kaydi g where g.calisan_id = vp.calisan_id and g.is_gunu = vp.tarih)) x;
    if v_n > 0 then
        v_engel := v_engel || jsonb_build_object('kod', 'bekleyen_plan_onayi', 'tur', 'zorla_gecilebilir', 'sayi', v_n,
            'mesaj', format('%s geriye dönük vardiya planı İK onayı bekliyor.', v_n), 'liste', v_liste);
    end if;

    -- Onaysız fazla mesai (havuz): zorla geçilebilir
    select count(*), coalesce(jsonb_agg(x.o) filter (where x.sira <= 50), '[]'::jsonb) into v_n, v_liste
    from (select jsonb_build_object('sicil', c.sicil_no, 'ad_soyad', c.ad || ' ' || c.soyad, 'gun', f.is_gunu, 'dakika', f.dakika) as o,
                 row_number() over (order by f.is_gunu, c.sicil_no) as sira
          from pdks.fazla_mesai_inceleme f join pdks.calisan c on c.id = f.calisan_id
          where f.durum = 'inceleme_bekliyor' and f.is_gunu between v_bas and v_bit) x;
    if v_n > 0 then
        v_engel := v_engel || jsonb_build_object('kod', 'onaysiz_fazla_mesai', 'tur', 'zorla_gecilebilir', 'sayi', v_n,
            'mesaj', format('%s onaysız fazla mesai İK kararı bekliyor.', v_n), 'liste', v_liste);
    end if;

    -- Açık soru: zorla geçilebilir
    select count(*), coalesce(jsonb_agg(x.o) filter (where x.sira <= 50), '[]'::jsonb) into v_n, v_liste
    from (select jsonb_build_object('sicil', c.sicil_no, 'ad_soyad', c.ad || ' ' || c.soyad, 'gun', g.is_gunu,
                                    'soru_turu', s.soru_turu, 'durum', s.durum) as o,
                 row_number() over (order by g.is_gunu, c.sicil_no) as sira
          from pdks.amir_sorusu s join pdks.gun_kaydi g on g.id = s.gun_kaydi_id join pdks.calisan c on c.id = g.calisan_id
          where g.is_gunu between v_bas and v_bit and s.durum in ('acik', 'eskale', 'ik_karari_bekliyor')) x;
    if v_n > 0 then
        v_engel := v_engel || jsonb_build_object('kod', 'acik_soru', 'tur', 'zorla_gecilebilir', 'sayi', v_n,
            'mesaj', format('%s amir sorusu cevap ya da İK kararı bekliyor.', v_n), 'liste', v_liste);
    end if;

    -- Açık itiraz: zorla geçilebilir
    select count(*), coalesce(jsonb_agg(x.o) filter (where x.sira <= 50), '[]'::jsonb) into v_n, v_liste
    from (select jsonb_build_object('itiraz_id', i.id, 'sicil', c.sicil_no, 'ad_soyad', c.ad || ' ' || c.soyad, 'gun', g.is_gunu, 'durum', i.durum) as o,
                 row_number() over (order by g.is_gunu, c.sicil_no) as sira
          from pdks.itiraz i join pdks.gun_kaydi g on g.id = i.gun_kaydi_id join pdks.calisan c on c.id = g.calisan_id
          where g.is_gunu between v_bas and v_bit and i.durum in ('acik', 'inceleniyor')) x;
    if v_n > 0 then
        v_engel := v_engel || jsonb_build_object('kod', 'acik_itiraz', 'tur', 'zorla_gecilebilir', 'sayi', v_n,
            'mesaj', format('%s itiraz karar bekliyor.', v_n), 'liste', v_liste);
    end if;

    -- Kodsuz kalacak gün (hesaplanmamış günler hariç: kilit onları önce hesaplar): zorla geçilebilir
    select count(*), coalesce(jsonb_agg(x.o) filter (where x.sira <= 50), '[]'::jsonb) into v_n, v_liste
    from (select jsonb_build_object('sicil', c.sicil_no, 'ad_soyad', c.ad || ' ' || c.soyad, 'gun', g.is_gunu,
                                    'neden', case when exists (select 1 from pdks.amir_sorusu s where s.gun_kaydi_id = g.id
                                                                 and s.durum in ('acik', 'eskale', 'ik_karari_bekliyor'))
                                                  then 'açık soru' else replace(g.durum, '_', ' ') end) as o,
                 row_number() over (order by g.is_gunu, c.sicil_no) as sira
          from pdks.gun_kaydi g join pdks.calisan c on c.id = g.calisan_id
          where g.is_gunu between v_bas and v_bit
            and not (g.durum = 'tamam' and not g.hesap_tamam)
            and not exists (select 1 from pdks.gun_kod_satirlari(g.calisan_id, g.is_gunu, g.durum,
                                                                 g.calisma_dk, g.fm50_dk, g.fm100_dk))) x;
    if v_n > 0 then
        v_engel := v_engel || jsonb_build_object('kod', 'kodsuz_gun', 'tur', 'zorla_gecilebilir', 'sayi', v_n,
            'mesaj', format('%s gün puantaja kodsuz girer (zorla kilitte; açık soru ya da eksik kayıt).', v_n), 'liste', v_liste);
    end if;

    -- Bilgi: hesaplanmamış gün (kilit önce hesaplar; yeni onaysız fazla mesai doğabilir)
    select count(*), coalesce(jsonb_agg(x.o) filter (where x.sira <= 50), '[]'::jsonb) into v_n, v_liste
    from (select jsonb_build_object('sicil', c.sicil_no, 'ad_soyad', c.ad || ' ' || c.soyad, 'gun', g.is_gunu) as o,
                 row_number() over (order by g.is_gunu, c.sicil_no) as sira
          from pdks.gun_kaydi g join pdks.calisan c on c.id = g.calisan_id
          where g.is_gunu between v_bas and v_bit and not g.hesap_tamam
            and not exists (select 1 from pdks.amir_sorusu s where s.gun_kaydi_id = g.id
                            and s.durum in ('acik', 'eskale', 'ik_karari_bekliyor'))) x;
    if v_n > 0 then
        v_engel := v_engel || jsonb_build_object('kod', 'hesaplanmamis_gun', 'tur', 'bilgi', 'sayi', v_n,
            'mesaj', format('%s gün henüz hesaplanmadı; kilit önce hesaplar, yeni onaysız fazla mesai çıkabilir.', v_n), 'liste', v_liste);
    end if;

    -- Bilgi: kilitle kapanacak fazla mesai talepleri (T-63)
    select count(*), coalesce(jsonb_agg(x.o) filter (where x.sira <= 50), '[]'::jsonb) into v_n, v_liste
    from (select jsonb_build_object('sicil', c.sicil_no, 'ad_soyad', c.ad || ' ' || c.soyad, 'gun', p.is_gunu, 'planli_dk', p.planli_dk) as o,
                 row_number() over (order by p.is_gunu, c.sicil_no) as sira
          from pdks.fazla_mesai_plani p join pdks.calisan c on c.id = p.calisan_id
          where p.durum = 'talep' and p.is_gunu between v_bas and v_bit) x;
    if v_n > 0 then
        v_engel := v_engel || jsonb_build_object('kod', 'kapanacak_fm_talebi', 'tur', 'bilgi', 'sayi', v_n,
            'mesaj', format('Karar bekleyen %s fazla mesai talebi kilitle kapanır.', v_n), 'liste', v_liste);
    end if;

    -- Bilgi: kabul edilmiş ama düzeltmesi yapılmamış itiraz (T-52)
    select count(*), coalesce(jsonb_agg(x.o) filter (where x.sira <= 50), '[]'::jsonb) into v_n, v_liste
    from (select jsonb_build_object('itiraz_id', i.id, 'sicil', c.sicil_no, 'ad_soyad', c.ad || ' ' || c.soyad, 'gun', g.is_gunu) as o,
                 row_number() over (order by g.is_gunu, c.sicil_no) as sira
          from pdks.itiraz i join pdks.gun_kaydi g on g.id = i.gun_kaydi_id join pdks.calisan c on c.id = g.calisan_id
          where g.is_gunu between v_bas and v_bit and i.durum = 'kabul'
            and not exists (select 1 from pdks.duzeltme d where d.itiraz_id = i.id)) x;
    if v_n > 0 then
        v_engel := v_engel || jsonb_build_object('kod', 'duzeltmesiz_kabul_itiraz', 'tur', 'bilgi', 'sayi', v_n,
            'mesaj', format('Kabul edilmiş %s itirazın düzeltmesi yapılmadı.', v_n), 'liste', v_liste);
    end if;

    return jsonb_build_object(
        'donem', to_char(v_bas, 'YYYY-MM'),
        'kilitli', false,
        'kilitlenebilir', not exists (select 1 from jsonb_array_elements(v_engel) e where e ->> 'tur' = 'zorla_gecilemez'),
        'zorlamadan_kilitlenebilir', not exists (select 1 from jsonb_array_elements(v_engel) e where e ->> 'tur' <> 'bilgi'),
        'engeller', v_engel);
end;
$$;
revoke execute on function pdks.ay_kilit_on_kontrol_ic(smallint, smallint) from public, anon, authenticated;

create function pdks.ay_kilit_on_kontrol(p_yil smallint, p_ay smallint)
returns jsonb
language plpgsql
stable
security definer
set search_path = pdks, pg_temp
as $$
begin
    perform pdks.yetki_gerekli('ik');
    return pdks.ay_kilit_on_kontrol_ic(p_yil, p_ay);
end;
$$;
comment on function pdks.ay_kilit_on_kontrol(smallint, smallint) is
    'Ay kilidinden önce bütün engelleri tek seferde döner (zorla geçilemez / geçilebilir / bilgi); hiçbir şeyi değiştirmez (T-96).';
revoke execute on function pdks.ay_kilit_on_kontrol(smallint, smallint) from public, anon;
grant execute on function pdks.ay_kilit_on_kontrol(smallint, smallint) to authenticated;

-- ---------------------------------------------------------------------
-- 3. T-54: izinli / raporlu günde okutma uyarısı
-- ---------------------------------------------------------------------
create function pdks.gun_kaydi_izinli_okutma()
returns trigger
language plpgsql
set search_path = pdks, pg_temp
as $$
begin
    perform pdks.uyari_yaz('izin_gununde_okutma', 'gun:' || new.id,
        format('İzinli günde okutma var (%s, %s). Gün izinli sayıldı; çalıştıysa izin iptal edilip gün düzeltilmelidir.',
               to_char(new.is_gunu, 'DD.MM.YYYY'),
               concat_ws('–', to_char(new.giris_zamani at time zone 'Europe/Istanbul', 'HH24:MI'),
                              to_char(new.cikis_zamani at time zone 'Europe/Istanbul', 'HH24:MI'))),
        new.calisan_id);
    return null;
end;
$$;
revoke execute on function pdks.gun_kaydi_izinli_okutma() from public, anon, authenticated;

create trigger gun_kaydi_izinli_okutma
after insert on pdks.gun_kaydi
for each row
when (new.durum in ('izinli', 'raporlu') and (new.giris_zamani is not null or new.cikis_zamani is not null))
execute function pdks.gun_kaydi_izinli_okutma();

-- ---------------------------------------------------------------------
-- 4. T-85: geçici kartın durumu (kayıp / iptal / bulundu)
-- ---------------------------------------------------------------------
alter table pdks.gecici_kart
    add column durum_nedeni        text,
    add column durum_degistiren_id bigint references pdks.kullanici (id),
    add column durum_zamani        timestamptz;

create function pdks.gecici_kart_durum(p_gecici_kart_id bigint, p_durum text, p_gerekce text)
returns void
language plpgsql
security definer
set search_path = pdks, pg_temp
as $$
declare
    v_ben    bigint := pdks.yetki_gerekli('guvenlik', 'ik');
    v_kart   pdks.gecici_kart;
begin
    if p_durum is null or p_durum not in ('kayip', 'iptal', 'aktif') then
        raise exception 'Durum seçilmeli: kayıp, iptal ya da aktif (kayıp kart bulunduysa).';
    end if;
    if p_gerekce is null or length(btrim(p_gerekce)) < 5 then
        raise exception 'Durum değişikliğinin gerekçesi yazılmalı (en az 5 karakter).';
    end if;
    select * into v_kart from pdks.gecici_kart where id = p_gecici_kart_id for update;
    if not found then
        raise exception 'Geçici kart bulunamadı.';
    end if;
    if v_kart.durum = 'iptal' then
        raise exception '% iptal edilmiş; durumu değiştirilemez.', v_kart.kart_no;
    end if;
    if v_kart.durum = p_durum then
        raise exception '% zaten bu durumda.', v_kart.kart_no;
    end if;
    if p_durum = 'aktif' and v_kart.durum <> 'kayip' then
        raise exception 'Yalnızca kayıp kart yeniden aktif yapılabilir (bulundu).';
    end if;

    -- Kart kaybolduysa ya da iptal edildiyse üzerindeki açık zimmet kapanır
    if p_durum in ('kayip', 'iptal') then
        update pdks.gecici_kart_zimmet
        set iade_zamani = clock_timestamp(), iade_alan_id = v_ben,
            aciklama = concat_ws(' · ', nullif(btrim(aciklama), ''),
                                 case p_durum when 'kayip' then 'Kart kayıp bildirildi' else 'Kart iptal edildi' end
                                 || ': ' || btrim(p_gerekce))
        where gecici_kart_id = p_gecici_kart_id and iade_zamani is null;
    end if;

    update pdks.gecici_kart
    set durum = p_durum, durum_nedeni = btrim(p_gerekce), durum_degistiren_id = v_ben, durum_zamani = now()
    where id = p_gecici_kart_id;
end;
$$;
revoke execute on function pdks.gecici_kart_durum(bigint, text, text) from public, anon;
grant execute on function pdks.gecici_kart_durum(bigint, text, text) to authenticated;

-- Kayıp bildirilen geçici kart okutulursa İK'ya uyarı (okutma kimseye yazılmaz: zimmet kapalı)
create function pdks.kayip_gecici_kart_okutma()
returns trigger
language plpgsql
set search_path = pdks, pg_temp
as $$
declare
    v_h  pdks.ham_okutma;
begin
    select h.* into v_h from pdks.ham_okutma h where h.id = new.ham_okutma_id;
    if exists (select 1 from pdks.gecici_kart g where g.kart_no = v_h.kart_no and g.durum = 'kayip') then
        perform pdks.uyari_yaz('gecici_kart_zimmetsiz', 'kayip:' || v_h.id,
            format('Kayıp bildirilen geçici kart %s okutuldu (%s). Okutma kimseye yazılmadı; kart bulunmuş olabilir ya da başkası kullanıyor.',
                   v_h.kart_no, to_char(v_h.okutma_zamani at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI')),
            null, v_h.okuyucu_id);
    end if;
    return null;
end;
$$;
revoke execute on function pdks.kayip_gecici_kart_okutma() from public, anon, authenticated;

create trigger okutma_isareti_kayip_gecici_kart
after insert on pdks.okutma_isareti
for each row
when (new.isaret = 'bilinmeyen_kart')
execute function pdks.kayip_gecici_kart_okutma();
