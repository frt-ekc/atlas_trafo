-- =====================================================================
-- K7 / K9 / K12 / K13 · T-69, T-51, T-15, T-16: İtiraz ve fazla mesai kararı kuralları
--
-- T-69: Çalışan 14 Ekim'de ayrıldı; 16 Ekim günü itirazı açıkken gün "vardiya yok" oldu, itiraz açık
--       kaldı, İK kabul etti; o güne yeni itiraz da girilebildi.
-- T-51: Aynı güne amir, İK ve yine amir art arda itiraz girdi: üç ayrı açık itiraz.
-- T-15: İK müdürü kendi günü hakkındaki itirazı "incelemeye" alabildi (karar vermesi engelleniyordu).
-- T-16: "Talep eden onaylayamaz" kuralı ham İngilizce kısıt mesajıyla dönüyordu.
--
-- Düzeltme:
--   - itiraz_gir: gün çalışanın çalışma tarihleri dışındaysa reddedilir (T-69); aynı günde açık ya da
--     incelenen itiraz varsa Türkçe mesajla reddedilir (T-51; kısmi tekil index de var).
--     Not: "vardiya yok" günün kendisi reddedilmez (planı olmayan günde reddedilen çalışmaya itiraz
--     edilebilmeli); yalnızca çalışma tarihi dışı.
--   - isten_cikis_gir: çıkıştan sonraki günlerin açık itirazlarını gerekçeyle kapatır; sonuçta
--     kapatilan_itiraz (T-69).
--   - itiraz_incelemeye_al: İK kendi gününün itirazını incelemeye alamaz (T-15).
--   - fazla_mesai_karar: talebi giren İK kendi talebine karar veremez, Türkçe mesaj (T-16).
-- Ekran tarafı (düğme gizleme) Gökalp'te.
-- Kalıcı test: supabase/tests/itiraz_kurallari_testi.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. İtiraz girişi (son hâli 20261119010000; T-69, T-51)
-- ---------------------------------------------------------------------
create unique index itiraz_gunde_tek_acik on pdks.itiraz (gun_kaydi_id) where durum in ('acik', 'inceleniyor');

create or replace function pdks.itiraz_gir(p_gun_kaydi_id bigint, p_metin text)
returns bigint
language plpgsql
security definer
set search_path = pdks
as $$
declare
    v_ben      bigint := pdks.yetki_gerekli('amir', 'ik');
    v_gun      pdks.gun_kaydi;
    v_acik     bigint;
    v_id       bigint;
begin
    select * into v_gun from pdks.gun_kaydi where id = p_gun_kaydi_id;
    if not found then
        raise exception 'Gün kaydı bulunamadı.';
    end if;
    perform pdks.calisan_yetkisi(v_gun.calisan_id);
    if pdks.kullanici_calisani(v_ben) = v_gun.calisan_id then
        raise exception 'Görevler ayrılığı: kendi itirazınızı giremezsiniz.';
    end if;
    perform pdks.calisan_tarih_denetle(v_gun.calisan_id, v_gun.is_gunu, v_gun.is_gunu);   -- T-69
    select id into v_acik from pdks.itiraz
    where gun_kaydi_id = p_gun_kaydi_id and durum in ('acik', 'inceleniyor')
    order by id limit 1;
    if v_acik is not null then                                                             -- T-51
        raise exception 'Bu güne ait açık bir itiraz var (no %); yeni itiraz için önce onun kararı verilmeli.', v_acik;
    end if;
    insert into pdks.itiraz (calisan_id, gun_kaydi_id, metin)
    values (v_gun.calisan_id, p_gun_kaydi_id, p_metin)
    returning id into v_id;
    return v_id;
end;
$$;

-- ---------------------------------------------------------------------
-- 2. İncelemeye alma (son hâli 20261119010000; T-15)
-- ---------------------------------------------------------------------
create or replace function pdks.itiraz_incelemeye_al(p_itiraz_id bigint)
returns void
language plpgsql
security definer
set search_path = pdks
as $$
declare
    v_ben  bigint := pdks.yetki_gerekli('ik');
begin
    if (select calisan_id from pdks.itiraz where id = p_itiraz_id) = pdks.kullanici_calisani(v_ben) then
        raise exception 'Görevler ayrılığı: kendi gününüze ait itirazı inceleyemezsiniz.';
    end if;
    update pdks.itiraz set durum = 'inceleniyor' where id = p_itiraz_id and durum = 'acik';
    if not found then
        raise exception 'Açık itiraz bulunamadı.';
    end if;
end;
$$;

-- ---------------------------------------------------------------------
-- 3. Fazla mesai talebine karar (son hâli 20261227010000; T-16)
-- ---------------------------------------------------------------------
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
    -- T-16: kısıta (fazla_mesai_talep_onay_farkli) varmadan Türkçe mesaj
    if v_plan.talep_eden_id = v_ben then
        raise exception 'Görevler ayrılığı: kendi girdiğiniz fazla mesai talebine karar veremezsiniz; kararı başka bir İK kullanıcısı verir.';
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

-- ---------------------------------------------------------------------
-- 4. İşten çıkış (son hâli T-67; T-69: çıkış sonrası günlerin açık itirazları kapanır)
-- ---------------------------------------------------------------------
create or replace function pdks.isten_cikis_gir(p_calisan_id bigint, p_cikis_tarihi date, p_aciklama text default null)
returns jsonb
language plpgsql
security definer
set search_path = pdks
as $$
declare
    v_ben      bigint := pdks.yetki_gerekli('ik');
    v_bugun    date := (now() at time zone 'Europe/Istanbul')::date;
    v_c        pdks.calisan;
    v_gerekce  text;
    v_gun      record;
    v_zimmet   record;
    v_okutma   timestamptz;
    v_n        integer;
    v_ozet     jsonb := '{}'::jsonb;
    -- T-67: çıkıştan sonra kilitli aya düşen kayıtlar değişmez; sayılır ve İK'ya bildirilir
    v_kilitli_gun  integer := 0;
    v_kilitli_plan integer;
    v_kilitli_izin integer;
    v_kilitli_ay   text;
    v_uyari        text;
begin
    select * into v_c from pdks.calisan where id = p_calisan_id for update;
    if not found then
        raise exception 'Çalışan bulunamadı.';
    end if;
    if pdks.kullanici_calisani(v_ben) = p_calisan_id then
        raise exception 'Görevler ayrılığı: kimse kendi kaydında işlem yapamaz (calisan.isten_cikis).';
    end if;
    if v_c.isten_cikis_tarihi is not null or not v_c.aktif then
        raise exception 'Bu çalışanın işten çıkışı zaten girilmiş.';
    end if;
    if p_cikis_tarihi is null then
        raise exception 'Çıkış tarihi girilmeli.';
    end if;
    if p_cikis_tarihi < v_c.ise_giris_tarihi then
        raise exception 'Çıkış tarihi işe giriş tarihinden (%) önce olamaz.', to_char(v_c.ise_giris_tarihi, 'DD.MM.YYYY');
    end if;
    if p_cikis_tarihi > v_bugun then
        raise exception 'Çıkış tarihi ileri olamaz; son çalışma günü ya da sonrasında girin.';
    end if;

    -- Açık geçici kart zimmeti: önce kart iade alınmalı
    select gk.kart_no, z.verilis_zamani into v_zimmet
    from pdks.gecici_kart_zimmet z join pdks.gecici_kart gk on gk.id = z.gecici_kart_id
    where z.calisan_id = p_calisan_id and z.iade_zamani is null
    limit 1;
    if found then
        raise exception 'Çalışanda iade edilmemiş geçici kart var (%, % tarihinde verildi); önce iade alın.',
            v_zimmet.kart_no, to_char(v_zimmet.verilis_zamani at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI');
    end if;

    -- Çıkıştan sonra okutması olan gün varsa çıkış tarihi yanlıştır
    select g.is_gunu into v_gun
    from pdks.gun_kaydi g
    where g.calisan_id = p_calisan_id and g.is_gunu > p_cikis_tarihi
      and (g.giris_zamani is not null or g.cikis_zamani is not null)
    order by g.is_gunu
    limit 1;
    if found then
        raise exception 'Çıkış tarihinden sonra çalışılmış gün var (%); çıkış tarihini kontrol edin.',
            to_char(v_gun.is_gunu, 'DD.MM.YYYY');
    end if;

    -- İşlenmemiş ya da plansız günün okutması (ham kayıt)
    v_okutma := pdks.cikistan_sonraki_okutma(p_calisan_id, p_cikis_tarihi);
    if v_okutma is not null then
        raise exception 'Çıkış tarihinden sonra kart okutması var (%); çıkış tarihi kontrol edilmelidir.',
            to_char(v_okutma at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI');
    end if;

    v_gerekce := 'İşten çıkış (' || to_char(p_cikis_tarihi, 'DD.MM.YYYY') || ')'
                 || coalesce(': ' || nullif(trim(p_aciklama), ''), '');

    -- Çalışan kaydı
    update pdks.calisan set isten_cikis_tarihi = p_cikis_tarihi, aktif = false where id = p_calisan_id;

    -- Kartlar (okutma sahibi kart iptalinden etkilenmez; son günün okutmaları yine çalışana yazılır)
    update pdks.kart set durum = 'iptal', iptal_nedeni = 'isten_cikis', iptal_zamani = now(), iptal_eden_id = v_ben
    where calisan_id = p_calisan_id and durum = 'aktif';
    get diagnostics v_n = row_count;
    v_ozet := v_ozet || jsonb_build_object('iptal_edilen_kart', v_n);

    -- Çıkıştan sonra işlenmiş günler (çıkış geç girildiyse): "vardiya yok" olur, açık soruları kapanır
    v_n := 0;
    for v_gun in
        select g.id, g.is_gunu from pdks.gun_kaydi g
        where g.calisan_id = p_calisan_id and g.is_gunu > p_cikis_tarihi and g.durum <> 'vardiya_yok'
        order by g.is_gunu
    loop
        -- T-32: amirin cevabına (cevaplayan, cevap, açıklama) dokunulmaz; kapatan ve nedeni ayrı yazılır.
        -- Nedende yalnızca tarih var: İK'nın açıklaması (ör. istifa) amirin okuyamadığı düzeltme gerekçesinde.
        update pdks.amir_sorusu
        set durum = 'kapandi', kapatan_id = v_ben, kapanis_zamani = now(), onceki_durum = durum,
            kapanis_nedeni = 'İşten çıkış (' || to_char(p_cikis_tarihi, 'DD.MM.YYYY') || ')'
        where gun_kaydi_id = v_gun.id and durum in ('acik', 'eskale', 'ik_karari_bekliyor');
        perform pdks.duzeltme_uygula(v_gun.id, 'durum', 'vardiya_yok', v_gerekce, 'ik', v_ben);
        v_n := v_n + 1;
        -- Kilitli günün kendisi değişmez; düzeltme sonraki aya fark satırı olur
        if pdks.donem_kilitli_mi(v_gun.is_gunu) then
            v_kilitli_gun := v_kilitli_gun + 1;
        end if;
    end loop;
    v_ozet := v_ozet || jsonb_build_object('vardiya_yok_yapilan_gun', v_n);

    -- Çıkıştan sonraki vardiya planları (T-67: kilitli ayınki kalır; kilitli ay kaydı değişmez)
    select count(*) into v_kilitli_plan
    from pdks.vardiya_plani
    where calisan_id = p_calisan_id and tarih > p_cikis_tarihi and pdks.donem_kilitli_mi(tarih);
    delete from pdks.vardiya_plani
    where calisan_id = p_calisan_id and tarih > p_cikis_tarihi and not pdks.donem_kilitli_mi(tarih);
    get diagnostics v_n = row_count;
    v_ozet := v_ozet || jsonb_build_object('silinen_plan', v_n);

    -- Tamamı çıkıştan sonraya düşen izinler (çıkış gününü kapsayan izin olduğu gibi kalır).
    -- T-67: kilitli ayda başlayan izin kalır (kilitli puantaja girmiştir)
    select count(*) into v_kilitli_izin
    from pdks.izin
    where calisan_id = p_calisan_id and baslangic > p_cikis_tarihi and iptal_zamani is null
      and pdks.donem_kilitli_mi(baslangic);
    update pdks.izin set iptal_zamani = now(), iptal_eden_id = v_ben, iptal_nedeni = v_gerekce
    where calisan_id = p_calisan_id and baslangic > p_cikis_tarihi and iptal_zamani is null
      and not pdks.donem_kilitli_mi(baslangic);
    get diagnostics v_n = row_count;
    v_ozet := v_ozet || jsonb_build_object('iptal_edilen_izin', v_n);

    -- T-69: çıkıştan sonraki günlerin açık itirazları kapanır (o gün artık çalışma tarihi dışında)
    update pdks.itiraz i
    set durum = 'red', karar_veren_id = v_ben, karar_zamani = now(),
        karar_aciklama = v_gerekce || ': gün çalışma tarihleri dışında kaldı; itiraz kapatıldı.'
    from pdks.gun_kaydi g
    where g.id = i.gun_kaydi_id and g.calisan_id = p_calisan_id and g.is_gunu > p_cikis_tarihi
      and i.durum in ('acik', 'inceleniyor');
    get diagnostics v_n = row_count;
    v_ozet := v_ozet || jsonb_build_object('kapatilan_itiraz', v_n);

    -- Onay bekleyen fazla mesai talepleri (çıkıştan sonraki günler; kilitli ayda bekleyen talep
    -- kalmaz, kilit kapatır: T-63)
    update pdks.fazla_mesai_plani
    set durum = 'iptal', karar_veren_id = v_ben, karar_aciklama = v_gerekce
    where calisan_id = p_calisan_id and is_gunu > p_cikis_tarihi and durum = 'talep'
      and not pdks.donem_kilitli_mi(is_gunu);
    get diagnostics v_n = row_count;
    v_ozet := v_ozet || jsonb_build_object('iptal_edilen_fm_talebi', v_n);

    -- Bağlı kullanıcı hesabı
    update pdks.kullanici set aktif = false where calisan_id = p_calisan_id and aktif;
    get diagnostics v_n = row_count;
    v_ozet := v_ozet || jsonb_build_object('pasif_yapilan_hesap', v_n);

    -- T-67: çıkış kilitli aya düştüyse İK'ya bildirilir (sonuçta ve kalıcı uyarı olarak)
    v_ozet := v_ozet || jsonb_build_object('kilitli_ayda_kalan_plan', v_kilitli_plan,
                                           'kilitli_ayda_kalan_izin', v_kilitli_izin);
    if v_kilitli_gun + v_kilitli_plan + v_kilitli_izin > 0 then
        select string_agg(to_char(make_date(d.yil, d.ay, 1), 'MM/YYYY'), ', ' order by d.yil, d.ay)
          into v_kilitli_ay
        from pdks.donem d
        where d.durum = 'kilitli' and (make_date(d.yil, d.ay, 1) + interval '1 month')::date > p_cikis_tarihi + 1;
        v_uyari := format('%s %s için işten çıkış (%s) kilitli aya (%s) düşüyor. Kilitli ayın kaydı değişmedi: '
                          || 'çıkıştan sonraki %s vardiya planı ve %s izin kaydı yerinde kaldı; kilitli puantajdaki '
                          || 'izin ve çalışma günleri gerekirse bordroda elle düzeltilmelidir. Çıkıştan sonraki %s gün '
                          || 'kaydının düzeltmesi sonraki aya fark satırı olarak yazıldı.',
                          v_c.ad, v_c.soyad, to_char(p_cikis_tarihi, 'DD.MM.YYYY'), v_kilitli_ay,
                          v_kilitli_plan, v_kilitli_izin, v_kilitli_gun);
        v_ozet := v_ozet || jsonb_build_object('kilitli_ay_uyarisi', v_uyari);
        perform pdks.uyari_yaz('cikis_kilitli_ay', 'cikis:' || p_calisan_id, v_uyari, p_calisan_id);
    end if;

    return v_ozet;
end;
$$;
