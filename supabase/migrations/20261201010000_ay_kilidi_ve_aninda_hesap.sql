-- =====================================================================
-- Ay kilidi düzeltmeleri ve günün hemen hesaplanması
--
-- Örnek Kasım verisiyle yerelde ay sonu denenince çıkan sorunlar:
--   1. Cevaplanmış ama henüz hesaplanmamış günler (hesap_tamam = false) olduğu gibi
--      kilitleniyordu; gece işi kilitli ayı atladığı için bu günler hiç çalışılmamış
--      sayılıyordu. → ay_kilitle kilitten önce o ayın hesabı bekleyen günlerini hesaplar.
--   2. Gün kaydı hiç açılmamış planlı gün (veri eksik) puantajda hafta tatili (HT)
--      sayılıyordu. → Kilit, gece işinden geçmemiş planlı gün varken reddeder; bu
--      kontrol zorla geçilemez (kilitten sonra o güne gün kaydı açılamaz, fark satırı da olmaz).
--   3. Üst amiri olmayan amirin sorusu İK'ya eskale olunca (ya da doğrudan İK'ya atanınca)
--      İK kapatamıyordu. → soru_ik_karari bu soruları da kabul eder.
--   4. soru_cevapla, soru_ik_karari ve kayit_duzelt değiştirdikleri günü hemen hesaplar;
--      bir sonraki gece işini beklemez. Kilitli ayda hesap yapılmaz.
-- Gün hesabı tek yerde: pdks.gun_hesapla(gün). Gece işinin hesap adımı da onu kullanır.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Tek günün hesabı (gece işinin hesap adımının tek gün hâli)
--    Giriş ve çıkış belli, açık sorusu olmayan, kilitli aya ait olmayan ve hesabı
--    bekleyen günü hesaplar; hesapladıysa true döner.
-- ---------------------------------------------------------------------
create function pdks.gun_hesapla(p_gun_kaydi_id bigint)
returns boolean
language plpgsql
set search_path = pdks
as $$
declare
    v_n integer;
begin
    with h as (
        select g.id, x.*
        from pdks.gun_kaydi g
        cross join lateral pdks.gun_hesabi(g.calisan_id, g.is_gunu, g.planli_baslangic, g.planli_bitis,
                                           g.giris_zamani, g.cikis_zamani, g.vardiya_id) x
        where g.id = p_gun_kaydi_id
          and not g.hesap_tamam
          and g.giris_zamani is not null and g.cikis_zamani is not null
          and g.planli_baslangic is not null
          and g.durum in ('eksik', 'tamam', 'soru_bekliyor')
          and not pdks.donem_kilitli_mi(g.is_gunu)
          and not exists (select 1 from pdks.amir_sorusu q
                          where q.gun_kaydi_id = g.id and q.durum in ('acik', 'eskale', 'ik_karari_bekliyor'))
    )
    update pdks.gun_kaydi g
    set gec_kalma_dk    = h.gec_kalma_dk,
        erken_cikis_dk  = h.erken_cikis_dk,
        fazla_mesai_dk  = h.fazla_mesai_dk,
        fm50_dk         = h.fm50_dk,
        fm100_dk        = h.fm100_dk,
        calisma_dk      = h.calisma_dk,
        gece_calisma_dk = h.gece_calisma_dk,
        saatlik_izin_dk = h.saatlik_izin_dk,
        mola_dk         = h.mola_dk,
        durum           = 'tamam',
        hesap_tamam     = true
    from h
    where g.id = h.id;
    get diagnostics v_n = row_count;
    if v_n = 0 then
        return false;
    end if;
    perform pdks.gun_sonrasi_kontroller(p_gun_kaydi_id);
    return true;
end;
$$;

-- Gece işinin hesap adımı: hesabı bekleyen her gün için gun_hesapla (davranış aynı)
create or replace function pdks.gece_isi_hesapla()
returns integer
language plpgsql
set search_path = pdks
as $$
declare
    v_say integer := 0;
    v_id  bigint;
begin
    for v_id in
        select g.id from pdks.gun_kaydi g
        where not g.hesap_tamam and g.giris_zamani is not null and g.cikis_zamani is not null
        order by g.id
    loop
        if pdks.gun_hesapla(v_id) then
            v_say := v_say + 1;
        end if;
    end loop;
    return v_say;
end;
$$;

-- ---------------------------------------------------------------------
-- 2. Amir cevabı: gün hemen hesaplanır (yalnızca sondaki satır eklendi)
-- ---------------------------------------------------------------------
create or replace function pdks.soru_cevapla(p_soru_id bigint, p_cevap text,
                                             p_giris timestamptz default null, p_cikis timestamptz default null,
                                             p_aciklama text default null)
returns void
language plpgsql
security definer
set search_path = pdks
as $$
declare
    v_ben     bigint := pdks.yetki_gerekli('amir');
    v_soru    pdks.amir_sorusu;
    v_gun     pdks.gun_kaydi;
    v_giris   timestamptz;
    v_cikis   timestamptz;
    v_vardiya smallint;
begin
    select * into v_soru from pdks.amir_sorusu where id = p_soru_id for update;
    if not found or v_ben not in (v_soru.atanan_id, coalesce(v_soru.eskale_edilen_id, 0)) then
        raise exception 'Soru bulunamadı ya da size atanmamış.';
    end if;
    if v_soru.durum not in ('acik', 'eskale') then
        raise exception 'Bu soru zaten cevaplanmış.';
    end if;
    if p_cevap not in ('geldi_saat_dogru', 'geldi_saat_farkli', 'kart_unuttu', 'gelmedi', 'bilmiyorum') then
        raise exception 'Geçersiz cevap: %', p_cevap;
    end if;
    select * into v_gun from pdks.gun_kaydi where id = v_soru.gun_kaydi_id;

    if p_cevap = 'geldi_saat_farkli' and p_giris is null and p_cikis is null then
        raise exception 'Saat farklıysa giriş ya da çıkış saatini girin.';
    end if;

    if p_cevap in ('geldi_saat_dogru', 'kart_unuttu') and p_giris is null and p_cikis is null then
        if v_soru.soru_turu = 'vardiya_uyusmazligi' then
            if v_soru.onerilen_vardiya_id is null then
                raise exception 'Bu soru türünde saatleri girin.';
            end if;
            v_vardiya := v_soru.onerilen_vardiya_id;
            v_giris := v_soru.onerilen_zaman;
            v_cikis := v_soru.onerilen_cikis;
        end if;
        if v_soru.soru_turu in ('giris_yok', 'kanit_vardiya_sonrasi', 'ariza_kaniti_yok', 'hic_kayit_yok') then
            v_giris := coalesce(v_soru.onerilen_zaman, v_gun.planli_baslangic);
        end if;
        if v_soru.soru_turu = 'cikis_yok' then
            v_cikis := coalesce(v_soru.onerilen_zaman, v_gun.planli_bitis);
        end if;
        if v_soru.soru_turu = 'hic_kayit_yok' then
            v_cikis := v_gun.planli_bitis;
        end if;
    else
        v_giris := p_giris;
        v_cikis := p_cikis;
    end if;

    update pdks.amir_sorusu
    set cevap = p_cevap, cevap_giris = v_giris, cevap_cikis = v_cikis, cevap_aciklama = p_aciklama,
        cevaplayan_id = v_ben,
        durum = case when p_cevap in ('gelmedi', 'bilmiyorum') then 'ik_karari_bekliyor' else 'cevaplandi' end
    where id = p_soru_id;

    if p_cevap not in ('gelmedi', 'bilmiyorum') then
        if v_vardiya is not null then
            perform pdks.duzeltme_uygula(v_soru.gun_kaydi_id, 'vardiya_id', v_vardiya::text,
                'Amir cevabı: vardiya önerisi onaylandı' || coalesce(' (' || p_aciklama || ')', ''),
                'amir', v_ben, p_soru_id => p_soru_id);
        end if;
        perform pdks.saat_yaz(v_soru.gun_kaydi_id, v_giris, v_cikis,
                              'Amir cevabı: ' || p_cevap || coalesce(' (' || p_aciklama || ')', ''),
                              'amir', v_ben, p_soru_id => p_soru_id);
    end if;

    -- Değişen gün hemen hesaplanır (kilitli ayda yapılmaz; düzeltme orada fark satırı olur)
    perform pdks.gun_hesapla(v_soru.gun_kaydi_id);
end;
$$;

-- ---------------------------------------------------------------------
-- 3. İK kararı: İK'ya eskale edilmiş / atanmış soru da kabul edilir; gün hemen hesaplanır
--    Görevler ayrılığı tetikleyicileri (amir_sorusu, duzeltme) aynen geçerli.
-- ---------------------------------------------------------------------
create or replace function pdks.soru_ik_karari(p_soru_id bigint, p_devamsiz boolean, p_gerekce text,
                                    p_giris timestamptz default null, p_cikis timestamptz default null)
returns void
language plpgsql
security definer
set search_path = pdks
as $$
declare
    v_ben   bigint := pdks.yetki_gerekli('ik');
    v_soru  pdks.amir_sorusu;
begin
    select * into v_soru from pdks.amir_sorusu where id = p_soru_id for update;
    -- Amirin "gelmedi / bilmiyorum" dediği soru ya da şu an İK'da duran soru: üst amiri olmayan
    -- amirin sorusu İK'ya eskale edildiyse ya da soru doğrudan İK'ya atandıysa (soru_cevapla amir ister)
    if not found or not (v_soru.durum = 'ik_karari_bekliyor'
                         or (v_soru.durum in ('acik', 'eskale')
                             and pdks.kullanici_rolu(coalesce(v_soru.eskale_edilen_id, v_soru.atanan_id)) = 'ik')) then
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
$$;

-- ---------------------------------------------------------------------
-- 4. İK kayıt düzeltmesi: gün hemen hesaplanır
-- ---------------------------------------------------------------------
create or replace function pdks.kayit_duzelt(p_gun_kaydi_id bigint, p_alan text, p_yeni_deger text, p_gerekce text,
                                             p_itiraz_id bigint default null, p_izin_id bigint default null)
returns bigint
language plpgsql
security definer
set search_path = pdks
as $$
declare
    v_ben  bigint := pdks.yetki_gerekli('ik');
    v_id   bigint;
begin
    v_id := pdks.duzeltme_uygula(p_gun_kaydi_id, p_alan, p_yeni_deger, p_gerekce, 'ik', v_ben,
                                 p_izin_id => p_izin_id, p_itiraz_id => p_itiraz_id,
                                 p_aleyhine => (p_alan = 'durum' and p_yeni_deger = 'devamsiz'));
    -- Değişen gün hemen hesaplanır (kilitli ayda yapılmaz; düzeltme orada fark satırı olur)
    perform pdks.gun_hesapla(p_gun_kaydi_id);
    return v_id;
end;
$$;

-- ---------------------------------------------------------------------
-- 5. Ay kilidi: önce hesap, sonra eksik gün kontrolü, sonra eski kontroller
-- ---------------------------------------------------------------------
create or replace function pdks.ay_kilitle(p_yil smallint, p_ay smallint, p_zorla boolean default false)
returns void
language plpgsql
security definer
set search_path = pdks
as $$
declare
    v_ben      bigint := pdks.yetki_gerekli('ik');
    v_bas      date := make_date(p_yil, p_ay, 1);
    v_bit      date := (make_date(p_yil, p_ay, 1) + interval '1 month - 1 day')::date;
    v_donem    bigint := pdks.donem_bul(make_date(p_yil, p_ay, 1));
    v_bekleyen integer;
    v_eksik    record;
begin
    -- 1) Cevaplanmış ya da düzeltilmiş ama henüz hesaplanmamış günler kilitten önce hesaplanır
    perform pdks.gun_hesapla(g.id)
    from pdks.gun_kaydi g
    where g.is_gunu between v_bas and v_bit and not g.hesap_tamam
    order by g.id;

    -- 2) Gece işinden geçmemiş planlı gün (o gün işteyken planı olup gün kaydı açılmamış).
    --    Zorla geçilemez: kilitten sonra bu güne gün kaydı açılamaz, puantajda hafta tatili görünürdü.
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

    -- 3) Eski kontroller: İK kararı bekleyen onaysız fazla mesai; açık soru / itiraz (zorla geçilebilir)
    select count(*) into v_bekleyen
    from pdks.fazla_mesai_inceleme
    where durum = 'inceleme_bekliyor' and is_gunu between v_bas and v_bit;
    if v_bekleyen > 0 and not p_zorla then
        raise exception '%/% döneminde İK kararı bekleyen % onaysız fazla mesai var.', p_ay, p_yil, v_bekleyen;
    end if;
    perform pdks.donem_kilitle(v_donem, v_ben, p_zorla);
    perform pdks.puantaj_yaz(v_donem);
end;
$$;

revoke execute on function pdks.gun_hesapla(bigint) from public, anon, authenticated;
