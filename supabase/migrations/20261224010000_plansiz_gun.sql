-- =====================================================================
-- K4 · T-79: Planı olmayan günde (ör. Cumartesi) yapılan çalışma hiçbir yere yazılmıyordu
--
-- Karar: Planı hiç olmayan günde, işte olduğu tarihler içindeki çalışanın geçerli PDKS okutması
-- varsa gece işi İK'ya ve amire plansiz_gun_calismasi uyarısı yazar, süreyi havuza
-- tatil_calismasi olarak düşürür; karar İK'dadır (T-56 ve T-57 işaretleri geçerlidir).
--
-- Değişiklik:
--   * gece_isi_plansiz: planı (bekleyen / reddedilmiş dahil) olmayan günün okutmalarını bulur,
--     gün kaydını vardiyasız ve "vardiya_yok" olarak açar.
--   * gun_hesabi: vardiyasız günde çalışma yalnızca havuz onayı kadar sayılır: hafta tatili (Pazar,
--     cumartesi_hafta_sonu açıkken Cumartesi) ve resmi tatilde FM100, diğer günde FM50
--     (arifede 13:00 sonrası FM100).
--     Onaylanınca gün "tamam" olur; onaylanmazsa HT / RT kalır.
--   * vardiya_plani_onayla: plansız güne geriye dönük plan onaylanırsa gün plana göre hesaplanır,
--     havuzda süre kalmadıysa kayıt kapanır. Havuz önce onaylandıysa plan onaylanmaz.
--   * Amir yalnızca bu tür uyarıyı, yalnızca kendi çalışanları için okur.
-- Planlı Pazar / tatil günlerinin kuralı değişmez. Daha önce işlenmiş günler, gece işi o gün için
-- yeniden çalıştırılırsa işlenir.
-- Kalıcı test: supabase/tests/plansiz_gun_testi.sql
-- =====================================================================

alter table pdks.uyari drop constraint uyari_tur_check;
alter table pdks.uyari add constraint uyari_tur_check check (tur in (
    'ariza_suphesi', 'dosya_gelmedi', 'fm_gunluk_sinir_asildi',
    'fm_onay_geri_alindi', 'fm_onay_yok', 'fm_plansiz_calisma',
    'fm_yillik_sinir_asildi', 'fm_yillik_sinir_yaklasti', 'gece_calisma_siniri_asildi',
    'gece_isi_calismadi', 'gecici_kart_cakisma', 'gecici_kart_iade_edilmedi',
    'gecici_kart_zimmetsiz', 'geriye_donuk_vardiya', 'iptal_kart_okutma',
    'isg_belgesi_suresi_dolmus', 'isg_belgesi_suresi_doluyor', 'isg_belgesi_yok',
    'kart_paylasim_suphesi', 'kendi_okutmasi_yuklendi', 'plansiz_gun_calismasi',
    'puantaj_ayari_degisti', 'sik_kart_unutma', 'soru_eskale',
    'yazili_onay_eksik', 'yetkisiz_bolge_okutmasi'
));

create policy amir_okur on pdks.uyari for select to authenticated
    using (tur = 'plansiz_gun_calismasi' and (select pdks.oturum_rolu()) = 'amir'
           and calisan_id = any ((select pdks.oturum_calisanlari())::bigint[]));

-- ---------------------------------------------------------------------
-- 1. Günün hesabı, havuz, puantaj kodu
-- ---------------------------------------------------------------------
create or replace function pdks.gun_hesabi(p_calisan_id bigint, p_is_gunu date, p_bas timestamptz, p_bit timestamptz, p_giris timestamptz, p_cikis timestamptz, p_vardiya_id smallint default null, out gec_kalma_dk integer, out erken_cikis_dk integer, out calisma_dk integer, out fazla_mesai_dk integer, out fm50_dk integer, out fm100_dk integer, out gece_calisma_dk integer, out saatlik_izin_dk integer, out onaysiz_fm_dk integer, out mola_dk integer)
returns record
language plpgsql
stable
set search_path = pdks
as $$
declare
    v_izin   tstzmultirange := pdks.saatlik_izin_araligi(p_calisan_id, p_is_gunu);
    v_yuv    integer := pdks.ayar_al('tolerans_yuvarlama_dk');
    v_onay   boolean := pdks.fm_onay_gecerli_mi(p_calisan_id, p_is_gunu);
    v_tatil  boolean := pdks.fm100_gunu_mu(p_is_gunu);
    v_arife  timestamptz := pdks.arife_siniri(p_is_gunu);
    v_vardiya smallint;
    v_ham_bit timestamptz;   -- arifede vardiyanın tanımdaki bitişi (p_bit 13:00'e çekilir)
    v_arife_ici integer;
    v_ek100  integer;
    v_eksik  integer;
    v_esnek  boolean;
    v_plan   integer;
    v_havuz  integer;
    v_bas_is timestamptz;
    v_ici    integer;
    v_sonra  integer;
    v_ek     integer;
    v_brut   integer;
    v_gece   integer;
begin
    gec_kalma_dk := 0; erken_cikis_dk := 0; calisma_dk := 0; fazla_mesai_dk := 0;
    fm50_dk := 0; fm100_dk := 0; gece_calisma_dk := 0; saatlik_izin_dk := 0; onaysiz_fm_dk := 0; mola_dk := 0;
    if p_giris is null or p_cikis is null then
        return;
    end if;

    v_vardiya := coalesce(p_vardiya_id, (select g.vardiya_id from pdks.gun_kaydi g
                                         where g.calisan_id = p_calisan_id and g.is_gunu = p_is_gunu));
    select coalesce(sum(dakika), 0) into v_havuz from pdks.fazla_mesai_inceleme
    where calisan_id = p_calisan_id and is_gunu = p_is_gunu and durum = 'onaylandi';

    if p_bas is null or p_bit is null then
        if v_vardiya is not null then
            return;
        end if;
        -- Plansız gün (T-79): bütün çalışma yalnızca İK'nın havuz onayı kadar sayılır;
        -- hafta tatili / resmi tatilde FM100, diğer günde FM50, arifede 13:00 sonrası FM100
        v_ici  := pdks.dakika_toplami(pdks.aralik(p_giris, p_cikis) - v_izin);
        v_brut := least(v_ici, v_havuz);
        onaysiz_fm_dk := v_ici - v_brut;
        mola_dk := pdks.mola_suresi(v_brut);
        calisma_dk := v_brut - mola_dk;
        if v_tatil then
            fm100_dk := calisma_dk;
        elsif v_arife is not null and v_brut > 0 then
            -- Mola önce 13:00 öncesinden düşer
            v_arife_ici := least(v_brut, pdks.dakika_toplami(pdks.aralik(greatest(p_giris, v_arife), p_cikis) - v_izin));
            fm100_dk := greatest(0, v_arife_ici - greatest(0, mola_dk - (v_brut - v_arife_ici)));
        end if;
        fm50_dk := calisma_dk - fm100_dk;
        fazla_mesai_dk := calisma_dk;
        if v_brut > 0 then
            v_gece := least(v_brut, pdks.dakika_toplami((pdks.aralik(p_giris, p_cikis) - v_izin) * pdks.gece_araligi(p_is_gunu)));
            gece_calisma_dk := greatest(0, v_gece - round(mola_dk::numeric * v_gece / v_brut)::integer);
        end if;
        return;
    end if;

    select t.esnek into v_esnek from pdks.vardiya_tanim t where t.id = v_vardiya;
    if coalesce(v_esnek, false) then
        -- Esnek mesaide vardiya, çalışanın kendi giriş–çıkışıdır
        p_bas := p_giris;
        p_bit := p_cikis;
    end if;

    v_ham_bit := p_bit;
    if v_arife is not null then
        if v_vardiya is not null and not coalesce(v_esnek, false) then
            v_ham_bit := greatest(p_bit, (pdks.vardiya_ham_araligi(v_vardiya, p_is_gunu)).p_bit);
        end if;
        -- Arifede çalışma 13:00'te biter; sonra başlayan vardiyada planlı normal çalışma kalmaz
        p_bit := greatest(p_bas, least(p_bit, v_arife));
    end if;

    select planli_dk into v_plan from pdks.fazla_mesai_plani
    where calisan_id = p_calisan_id and is_gunu = p_is_gunu and durum = 'onaylandi';
    v_plan := case when v_onay then coalesce(v_plan, 0) else 0 end;

    gec_kalma_dk   := pdks.tolerans_uygula(pdks.dakika_toplami(pdks.aralik(p_bas, case when v_arife is not null then least(p_giris, p_bit)
                                                                              else p_giris end) - v_izin),
                                           pdks.ayar_al('gec_kalma_tolerans_dk'), v_yuv);
    erken_cikis_dk := pdks.tolerans_uygula(pdks.dakika_toplami(pdks.aralik(p_cikis, p_bit) - v_izin),
                                           pdks.ayar_al('erken_cikis_tolerans_dk'), v_yuv);
    saatlik_izin_dk := pdks.dakika_toplami(pdks.aralik(p_bas, p_bit) * v_izin);

    v_bas_is := greatest(p_giris, p_bas);
    v_ici    := pdks.dakika_toplami(pdks.aralik(v_bas_is, least(p_cikis, p_bit)) - v_izin);
    v_sonra  := greatest(0, pdks.dakika(v_ham_bit, p_cikis));

    if v_arife is not null then
        -- 13:00'ten vardiya bitişine kadar: yazılı onay varsa FM100, yoksa havuz onayı kadar.
        -- Saat 13:00'ü birkaç dakika geçen çıkış (plansız çalışma eşiği) çalışma sayılmaz.
        v_arife_ici := pdks.dakika_toplami(pdks.aralik(greatest(v_bas_is, v_arife), least(p_cikis, v_ham_bit)) - v_izin);
        if v_ici > 0 and v_arife_ici <= pdks.ayar_al('fm_plansiz_esik_dk') then
            v_arife_ici := 0;
        end if;
        fm100_dk := case when v_onay then v_arife_ici else least(v_arife_ici, v_havuz) end;
        -- Vardiya bitişinden sonrası: onaylı plan + havuz; 13:00 öncesine düşen kısmı (ör. 00-08 vardiyası) FM50
        v_ek := least(v_sonra, v_plan + v_havuz - case when v_onay then 0 else fm100_dk end);
        v_ek100 := least(v_ek, greatest(0, pdks.dakika(greatest(v_arife, v_ham_bit), v_ham_bit + make_interval(mins => v_ek))));
        onaysiz_fm_dk := v_arife_ici - fm100_dk + v_sonra - v_ek;
        fm50_dk := v_ek - v_ek100;
        v_brut := v_ici + fm100_dk + v_ek;
        fm100_dk := fm100_dk + v_ek100;
    elsif not v_tatil then
        v_ek := least(v_sonra, v_plan + v_havuz);
        fm50_dk := v_ek;
        v_brut := v_ici + v_ek;
        onaysiz_fm_dk := greatest(0, v_sonra - v_plan - v_havuz);
    elsif v_onay then
        v_ek := least(v_sonra, v_plan + v_havuz);
        fm100_dk := v_ici + v_ek;
        v_brut := fm100_dk;
        onaysiz_fm_dk := greatest(0, v_sonra - v_plan - v_havuz);
    else
        fm100_dk := least(v_ici + v_sonra, v_havuz);
        v_brut := fm100_dk;
        v_ek := greatest(0, fm100_dk - v_ici);
        onaysiz_fm_dk := greatest(0, v_ici + v_sonra - v_havuz);
    end if;

    -- Brüt çalışmanın gece dilimine düşen kısmı
    v_gece := least(v_brut,
        pdks.dakika_toplami((pdks.aralik(v_bas_is, least(p_cikis, v_ham_bit + make_interval(mins => coalesce(v_ek, 0))))
                             - v_izin) * pdks.gece_araligi(p_is_gunu)));

    -- Mola (m.68)
    mola_dk := pdks.mola_suresi(v_brut);
    calisma_dk := v_brut - mola_dk;
    if v_arife is not null then
        -- Mola önce normal çalışmadan, kalan kısmı fazla mesaiden düşer
        v_eksik := greatest(0, mola_dk - v_ici);
        fm100_dk := greatest(0, fm100_dk - greatest(0, v_eksik - fm50_dk));
        fm50_dk := greatest(0, fm50_dk - v_eksik);
    elsif v_tatil then
        fm100_dk := greatest(0, fm100_dk - mola_dk);
    elsif v_ici < mola_dk then
        fm50_dk := greatest(0, fm50_dk - (mola_dk - v_ici));
    end if;
    fazla_mesai_dk := fm50_dk + fm100_dk;
    gece_calisma_dk := case when v_brut > 0 then greatest(0, v_gece - round(mola_dk::numeric * v_gece / v_brut)::integer)
                            else 0 end;
end;
$$;

create or replace function pdks.gun_hesapla(p_gun_kaydi_id bigint)
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
          -- Plansız gün (T-79): vardiyası yoktur, onaya kadar "vardiya_yok" durur
          and (g.planli_baslangic is not null or g.vardiya_id is null)
          and (g.durum in ('eksik', 'tamam', 'soru_bekliyor') or (g.durum = 'vardiya_yok' and g.vardiya_id is null))
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
        durum           = case when g.vardiya_id is null and h.calisma_dk = 0 then 'vardiya_yok' else 'tamam' end,
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

create or replace function pdks.gun_hesabini_yenile(p_gun_kaydi_id bigint)
returns void
language plpgsql
set search_path = pdks
as $$
begin
    -- Plansız gün (T-79) havuzdan onaylanınca çalışılmış gün olur
    update pdks.gun_kaydi g set durum = 'tamam'
    where g.id = p_gun_kaydi_id and g.hesap_tamam and g.durum = 'vardiya_yok' and g.vardiya_id is null
      and not pdks.donem_kilitli_mi(g.is_gunu)
      and exists (select 1 from pdks.fazla_mesai_inceleme i where i.gun_kaydi_id = g.id and i.durum = 'onaylandi');

    update pdks.gun_kaydi g
    set (gec_kalma_dk, erken_cikis_dk, calisma_dk, fazla_mesai_dk, fm50_dk, fm100_dk,
         gece_calisma_dk, saatlik_izin_dk, mola_dk) =
        (select h.gec_kalma_dk, h.erken_cikis_dk, h.calisma_dk, h.fazla_mesai_dk, h.fm50_dk, h.fm100_dk,
                h.gece_calisma_dk, h.saatlik_izin_dk, h.mola_dk
         from pdks.gun_hesabi(g.calisan_id, g.is_gunu, g.planli_baslangic, g.planli_bitis,
                              g.giris_zamani, g.cikis_zamani, g.vardiya_id) h)
    where g.id = p_gun_kaydi_id and g.hesap_tamam
      and (g.durum = 'tamam' or (g.durum = 'vardiya_yok' and g.vardiya_id is null))
      and not pdks.donem_kilitli_mi(g.is_gunu);
end;
$$;

create or replace function pdks.gun_sonrasi_kontroller(p_gun_kaydi_id bigint)
returns integer
language plpgsql
set search_path = pdks
as $$
declare
    g       pdks.gun_kaydi;
    h       record;
    v_mevcut pdks.fazla_mesai_inceleme;
    v_tur   text;
    v_say   integer := 0;
    v_toplam integer;
begin
    select * into g from pdks.gun_kaydi where id = p_gun_kaydi_id;
    if not g.hesap_tamam or not (g.durum = 'tamam' or (g.durum = 'vardiya_yok' and g.vardiya_id is null)) then
        return 0;
    end if;
    select * into h from pdks.gun_hesabi(g.calisan_id, g.is_gunu, g.planli_baslangic, g.planli_bitis,
                                         g.giris_zamani, g.cikis_zamani);
    v_tur := case when g.vardiya_id is null   -- plansız gün (T-79)
                    or ((pdks.fm100_gunu_mu(g.is_gunu) or g.cikis_zamani > pdks.arife_siniri(g.is_gunu))
                        and not pdks.fm_onay_gecerli_mi(g.calisan_id, g.is_gunu))
                  then 'tatil_calismasi' else 'vardiya_sonrasi' end;

    select * into v_mevcut from pdks.fazla_mesai_inceleme where gun_kaydi_id = g.id;
    if h.onaysiz_fm_dk > pdks.ayar_al('fm_plansiz_esik_dk') then
        if v_mevcut.id is null then
            insert into pdks.fazla_mesai_inceleme (gun_kaydi_id, calisan_id, is_gunu, tur, dakika)
            values (g.id, g.calisan_id, g.is_gunu, v_tur, h.onaysiz_fm_dk);
            v_say := v_say + 1;
        elsif v_mevcut.durum = 'inceleme_bekliyor' and (v_mevcut.dakika, v_mevcut.tur) <> (h.onaysiz_fm_dk, v_tur) then
            update pdks.fazla_mesai_inceleme set dakika = h.onaysiz_fm_dk, tur = v_tur where id = v_mevcut.id;
        end if;
    end if;

    -- Yazılı onaylı tatil çalışması havuza düşmeden puantaja girer; yıllık sınırı aşarsa İK'ya bildirilir
    -- (havuzdan onaylanan gün kendi uyarısını karar anında yazar)
    if g.fm100_dk > 0 and v_mevcut.durum is distinct from 'onaylandi' then
        v_toplam := pdks.fm_yillik_toplam(g.calisan_id, extract(year from g.is_gunu)::integer);
        if v_toplam > pdks.ayar_al('fm_yillik_sinir_dk') then
            v_say := v_say + pdks.uyari_yaz('fm_yillik_sinir_asildi', 'gun:' || g.id,
                format('%s yılı onaylı fazla mesai süresi %s (sınır %s).',
                       extract(year from g.is_gunu), pdks.sure_metni(v_toplam), pdks.sure_metni(pdks.ayar_al('fm_yillik_sinir_dk'))),
                g.calisan_id);
        end if;
    end if;

    if g.gece_calisma_dk > pdks.ayar_al('gece_calisma_sinir_dk') then
        v_say := v_say + pdks.uyari_yaz('gece_calisma_siniri_asildi', 'gece:' || g.id,
            format('%s tarihinde %s gece çalışması yapıldı (%ssınır %s).',
                   to_char(g.is_gunu, 'DD.MM.YYYY'), pdks.sure_metni(g.gece_calisma_dk),
                   case when pdks.ayar_al('gece_calisma_sinir_dk') = 450 then 'yasal ' else '' end,
                   pdks.sure_metni(pdks.ayar_al('gece_calisma_sinir_dk'))),
            g.calisan_id);
    end if;
    return v_say;
end;
$$;

create or replace function pdks.gun_kod_satirlari(p_calisan_id bigint, p_gun date, p_durum text, p_calisma_dk integer, p_fm50_dk integer, p_fm100_dk integer)
returns TABLE(kod text, gun numeric, dakika integer)
language plpgsql
stable
set search_path = pdks
as $$
declare
    v_izin text;
begin
    if p_durum is null or p_durum = 'vardiya_yok' then
        return query select case when exists (select 1 from pdks.resmi_tatil r where r.tarih = p_gun and not r.yarim_gun)
                                 then 'RT' else 'HT' end, 1::numeric, 0;
    elsif p_durum = 'tatil' then
        return query select 'RT'::text, 1::numeric, 0;
    elsif p_durum = 'raporlu' then
        return query select 'RPR'::text, 1::numeric, 0;
    elsif p_durum = 'devamsiz' then
        return query select 'DVMSZ'::text, 1::numeric, 0;
    elsif p_durum = 'izinli' then
        select i.tur into v_izin from pdks.izin i
        where i.calisan_id = p_calisan_id and p_gun between i.baslangic and i.bitis and i.iptal_zamani is null
        order by i.id limit 1;
        return query select case v_izin when 'yillik' then 'Yİ' when 'mazeret' then 'MZR'
                                        when 'ucretsiz' then 'ÜCSZ' when 'rapor' then 'RPR' else 'Dİ' end,
                            1::numeric, 0;
    elsif p_durum = 'tamam' then
        if pdks.fm100_gunu_mu(p_gun) then
            return query select 'FM100'::text, 1::numeric, coalesce(p_fm100_dk, 0);
        elsif coalesce(p_fm50_dk, 0) > 0 and coalesce(p_fm100_dk, 0) = 0
              and exists (select 1 from pdks.gun_kaydi g
                          where g.calisan_id = p_calisan_id and g.is_gunu = p_gun and g.vardiya_id is null) then
            -- Onaylanan plansız gün (T-79), tatil değil: gün FM50 günüdür
            return query select 'FM50'::text, 1::numeric, p_fm50_dk;
        elsif coalesce(p_fm100_dk, 0) > 0
              and coalesce(p_calisma_dk, 0) = coalesce(p_fm50_dk, 0) + p_fm100_dk then
            -- Arifede 13:00'ten sonraki vardiya ya da tatildeki plansız gün (T-79): gün FM100 günüdür
            return query select 'FM100'::text, 1::numeric, p_fm100_dk;
            if coalesce(p_fm50_dk, 0) <> 0 then
                return query select 'FM50'::text, 0::numeric, p_fm50_dk;
            end if;
        else
            -- Arifede FM100, normal çalışmayla aynı gündedir
            return query select 'NÇ'::text, 1::numeric,
                                coalesce(p_calisma_dk, 0) - coalesce(p_fm50_dk, 0) - coalesce(p_fm100_dk, 0);
            if coalesce(p_fm100_dk, 0) <> 0 then
                return query select 'FM100'::text, 0::numeric, p_fm100_dk;
            end if;
            if coalesce(p_fm50_dk, 0) <> 0 then
                return query select 'FM50'::text, 0::numeric, p_fm50_dk;
            end if;
        end if;
    end if;
end;
$$;

create or replace function pdks.gun_katkisi(p_gun_kaydi_id bigint, p_duzeltmeler bigint[], out calisilan_gun numeric, out calisma_dk integer, out gec_kalma_dk integer, out erken_cikis_dk integer, out devamsiz_gun numeric, out izinli_gun numeric, out raporlu_gun numeric, out tatil_gun numeric, out fazla_mesai_dk integer, out fm50_dk integer, out fm100_dk integer, out gece_calisma_dk integer, out saatlik_izin_dk integer, out durum text, out mola_dk integer, out esnek_hedef_dk integer, out esnek_fark_dk integer)
returns record
language plpgsql
stable
set search_path = pdks
as $$
declare
    g        pdks.gun_kaydi;
    d        record;
    v_durum_duzeltildi boolean := false;
    v_ara    record;
    v_esnek  boolean;
    h        record;
begin
    select * into g from pdks.gun_kaydi where id = p_gun_kaydi_id;

    for d in select * from pdks.duzeltme where id = any (coalesce(p_duzeltmeler, '{}')) order by id loop
        case d.alan
            when 'giris_zamani' then g.giris_zamani := d.yeni_deger::timestamptz;
            when 'cikis_zamani' then g.cikis_zamani := d.yeni_deger::timestamptz;
            when 'durum'        then g.durum := d.yeni_deger; v_durum_duzeltildi := true;
            when 'vardiya_id'   then
                g.vardiya_id := d.yeni_deger::smallint;
                select * into v_ara from pdks.vardiya_araligi(g.vardiya_id, g.is_gunu);
                g.planli_baslangic := v_ara.p_bas;
                g.planli_bitis := v_ara.p_bit;
        end case;
    end loop;

    if not v_durum_duzeltildi and coalesce(array_length(p_duzeltmeler, 1), 0) > 0
       and g.durum in ('eksik', 'soru_bekliyor', 'devamsiz_suphesi')
       and g.giris_zamani is not null and g.cikis_zamani is not null then
        g.durum := 'tamam';
    end if;

    durum         := g.durum;
    calisilan_gun := case when g.durum = 'tamam'    then 1 else 0 end;
    devamsiz_gun  := case when g.durum = 'devamsiz' then 1 else 0 end;
    izinli_gun    := case when g.durum = 'izinli'   then 1 else 0 end;
    raporlu_gun   := case when g.durum = 'raporlu'  then 1 else 0 end;
    tatil_gun     := case when g.durum = 'tatil'    then 1 else 0 end;

    if g.durum = 'tamam' and g.giris_zamani is not null and g.cikis_zamani is not null
       and (g.planli_baslangic is not null or g.vardiya_id is null) then
        select * into h from pdks.gun_hesabi(g.calisan_id, g.is_gunu, g.planli_baslangic, g.planli_bitis,
                                              g.giris_zamani, g.cikis_zamani, g.vardiya_id);
        calisma_dk := h.calisma_dk; gec_kalma_dk := h.gec_kalma_dk;
        erken_cikis_dk := h.erken_cikis_dk; fazla_mesai_dk := h.fazla_mesai_dk;
        fm50_dk := h.fm50_dk; fm100_dk := h.fm100_dk;
        gece_calisma_dk := h.gece_calisma_dk; saatlik_izin_dk := h.saatlik_izin_dk; mola_dk := h.mola_dk;
    else
        calisma_dk := 0; gec_kalma_dk := 0; erken_cikis_dk := 0; fazla_mesai_dk := 0;
        fm50_dk := 0; fm100_dk := 0; gece_calisma_dk := 0; saatlik_izin_dk := 0; mola_dk := 0;
    end if;

    select t.esnek into v_esnek from pdks.vardiya_tanim t where t.id = g.vardiya_id;
    if coalesce(v_esnek, false) and g.durum not in ('izinli', 'raporlu', 'tatil', 'vardiya_yok') then
        esnek_hedef_dk := pdks.ayar_al('esnek_gunluk_hedef_dk')
                          / case when pdks.arife_siniri(g.is_gunu) is not null then 2 else 1 end;
    else
        esnek_hedef_dk := 0;
    end if;
    esnek_fark_dk := case when coalesce(v_esnek, false)
                           then calisma_dk - case when pdks.arife_siniri(g.is_gunu) is not null then fm100_dk else 0 end
                           else 0 end - esnek_hedef_dk;
end;
$$;

-- ---------------------------------------------------------------------
-- 2. Gece işi adımı
-- ---------------------------------------------------------------------
create function pdks.gece_isi_plansiz(p_gun date, p_gece_isi_id bigint)
returns integer
language plpgsql
set search_path = pdks
as $$
declare
    v_bas     timestamptz := p_gun::timestamp at time zone 'Europe/Istanbul';
    v_bit     timestamptz := (p_gun + 1)::timestamp at time zone 'Europe/Istanbul';
    v_giris   timestamptz;
    v_cikis   timestamptz;
    v_kesim   timestamptz;
    v_ertesi  timestamptz;
    v_tek     timestamptz;
    v_kom     tstzmultirange;   -- komşu günlerin vardiya pencereleri
    v_kom_gir tstzmultirange;   -- giriş okutması için (önceki vardiyanın bitişinden sonraki giriş yeni çalışmadır)
    v_gun     bigint;
    v_say     integer := 0;
    r         record;
begin
    for r in
        select distinct c.id
        from (select distinct pdks.okutma_sahibi(h.kart_no, h.okutma_zamani) as calisan_id
              from pdks.ham_okutma h
              where h.okutma_zamani >= v_bas and h.okutma_zamani < v_bit
                and not pdks.okutma_gecersiz_mi(h.id)) o
        join pdks.calisan c on c.id = o.calisan_id
        where p_gun >= c.ise_giris_tarihi
          and (c.isten_cikis_tarihi is null or p_gun <= c.isten_cikis_tarihi)
          and not exists (select 1 from pdks.vardiya_plani vp where vp.calisan_id = c.id and vp.tarih = p_gun)
          and not exists (select 1 from pdks.gun_kaydi g where g.calisan_id = c.id and g.is_gunu = p_gun)
        order by c.id
    loop
        -- Komşu günlerin okutmaları bu günün değildir (ör. önceki gece vardiyasının sabah çıkışı)
        select coalesce(range_agg(tstzrange(x.bas, x.bit, '[]')), '{}'::tstzmultirange),
               coalesce(range_agg(tstzrange(x.bas, x.giris_bit, '[]')), '{}'::tstzmultirange),
               min(x.bas) filter (where x.sonraki)
          into v_kom, v_kom_gir, v_ertesi
        from (
            select a.p_bas - make_interval(mins => t.pencere_once_dk) as bas,
                   a.p_bit + make_interval(mins => t.pencere_sonra_dk) as bit,
                   case when vp.tarih < p_gun then a.p_bit
                        else a.p_bit + make_interval(mins => t.pencere_sonra_dk) end as giris_bit,
                   vp.tarih > p_gun as sonraki
            from pdks.vardiya_plani vp
            join pdks.vardiya_tanim t on t.id = vp.vardiya_id
            cross join lateral pdks.vardiya_ham_araligi(vp.vardiya_id, vp.tarih) a
            where vp.calisan_id = r.id and vp.tarih in (p_gun - 1, p_gun + 1) and vp.ik_onay_durumu <> 'reddedildi'
            union all
            -- Önceki günün plansız çalışması gece yarısını aştıysa
            select g.giris_zamani, g.cikis_zamani, g.cikis_zamani, false
            from pdks.gun_kaydi g
            where g.calisan_id = r.id and g.is_gunu = p_gun - 1 and g.vardiya_id is null
              and g.giris_zamani is not null and g.cikis_zamani is not null
        ) x;

        select min(h.okutma_zamani) filter (where h.yon is distinct from 'cikis'
                    and not h.okutma_zamani <@ case when h.yon = 'giris' then v_kom_gir else v_kom end),
               min(h.okutma_zamani) filter (where not h.okutma_zamani <@ v_kom)
          into v_giris, v_tek
        from pdks.ham_okutma h
        where h.okutma_zamani >= v_bas and h.okutma_zamani < v_bit
          and pdks.okutma_sahibi(h.kart_no, h.okutma_zamani) = r.id
          and not pdks.okutma_gecersiz_mi(h.id);
        continue when v_giris is null and v_tek is null;

        -- Çıkış: ertesi gün 12:00'ye, ertesi günün ilk girişine ya da vardiya penceresine kadar
        v_cikis := null;
        if v_giris is not null then
            select least(v_bit + interval '12 hours',
                         case when v_ertesi > v_giris then v_ertesi end,
                         min(h.okutma_zamani))
              into v_kesim
            from pdks.ham_okutma h
            where h.okutma_zamani >= v_bit and h.okutma_zamani < v_bit + interval '12 hours' and h.yon = 'giris'
              and pdks.okutma_sahibi(h.kart_no, h.okutma_zamani) = r.id
              and not pdks.okutma_gecersiz_mi(h.id);
            select max(h.okutma_zamani) into v_cikis
            from pdks.ham_okutma h
            where h.okutma_zamani > v_giris and h.okutma_zamani < v_kesim and h.yon is distinct from 'giris'
              and pdks.okutma_sahibi(h.kart_no, h.okutma_zamani) = r.id
              and not pdks.okutma_gecersiz_mi(h.id);
            -- Çıkış ertesi sabah olabilir: o dosya gelmeden karar verilmez (gece işi günü ertesi gece yeniden işler)
            continue when v_cikis is null and not pdks.pdks_verisi_tam_mi(v_bit, v_bit);
        end if;

        if v_cikis is null or pdks.dakika(v_giris, v_cikis) <= pdks.ayar_al('fm_plansiz_esik_dk')
           or pdks.donem_kilitli_mi(p_gun) then
            v_say := v_say + pdks.uyari_yaz('plansiz_gun_calismasi', r.id || ':' || p_gun,
                format('%s tarihinde vardiya planı olmadan kart okutuldu (%s). Süre havuza eklenmedi: %s.',
                       to_char(p_gun, 'DD.MM.YYYY'),
                       to_char(coalesce(v_giris, v_tek) at time zone 'Europe/Istanbul', 'HH24:MI')
                           || coalesce('–' || to_char(v_cikis at time zone 'Europe/Istanbul', 'HH24:MI'), ''),
                       case when v_giris is null then 'giriş okutması yok'
                            when v_cikis is null then 'çıkış okutması yok'
                            when pdks.donem_kilitli_mi(p_gun) then 'ay kilitli'
                            else 'çalışma süresi kısa' end),
                r.id);
            continue;
        end if;

        insert into pdks.gun_kaydi (calisan_id, is_gunu, giris_zamani, cikis_zamani, giris_kaynagi, cikis_kaynagi,
                                    durum, hesap_tamam, gece_isi_id)
        values (r.id, p_gun, v_giris, v_cikis, 'pdks', 'pdks', 'vardiya_yok', false, p_gece_isi_id)
        returning id into v_gun;
        perform pdks.gun_hesapla(v_gun);   -- havuz kaydını gun_sonrasi_kontroller açar
        v_say := v_say + pdks.uyari_yaz('plansiz_gun_calismasi', r.id || ':' || p_gun,
            format('%s tarihinde vardiya planı olmadan %s–%s arasında çalışıldı (%s). Süre İK kararı bekliyor.',
                   to_char(p_gun, 'DD.MM.YYYY'),
                   to_char(v_giris at time zone 'Europe/Istanbul', 'HH24:MI'),
                   to_char(v_cikis at time zone 'Europe/Istanbul', 'HH24:MI'),
                   pdks.sure_metni(pdks.dakika(v_giris, v_cikis)::integer)),
            r.id);
    end loop;
    return v_say;
end;
$$;

revoke execute on function pdks.gece_isi_plansiz(date, bigint) from public, anon, authenticated;

create or replace function pdks.gece_isi_calistir(p_gun date)
returns bigint
language plpgsql
security definer
set search_path = pdks
as $$
declare
    v_id    bigint;
    v_ozet  jsonb;
begin
    -- Dün her zaman işlenebilir; daha ileri bir gün ancak PDKS dosyası yüklendiyse
    -- (ör. demo verisi). Eksik veriyle yarım iş yapılmasını pdks_verisi_tam_mi() önler.
    if p_gun is null or p_gun > greatest(pdks.bugun() - 1,
            (select max(veri_tarihi) from pdks.aktarim where kaynak = 'pdks')) then
        raise exception 'Bu gün için henüz veri yok: %', p_gun;
    end if;

    -- Aynı anda iki gece işi çalışmasın
    perform pg_advisory_xact_lock(hashtext('pdks.gece_isi'));

    insert into pdks.gece_isi (islenen_gun) values (p_gun) returning id into v_id;

    begin
        v_ozet := jsonb_build_object('isaret',    pdks.gece_isi_isaretle(p_gun, v_id));
        v_ozet := v_ozet || jsonb_build_object('gun_kaydi', pdks.gece_isi_gun_kayitlari(p_gun, v_id));
        v_ozet := v_ozet || jsonb_build_object('plansiz',   pdks.gece_isi_plansiz(p_gun, v_id));
        v_ozet := v_ozet || jsonb_build_object('ariza',     pdks.gece_isi_ariza_suphesi(p_gun));
        v_ozet := v_ozet || jsonb_build_object('duzeltme',  pdks.gece_isi_kanitla_duzelt(p_gun));
        v_ozet := v_ozet || jsonb_build_object('soru',      pdks.gece_isi_sorular(p_gun));
        v_ozet := v_ozet || jsonb_build_object('eskale',    pdks.gece_isi_eskale(p_gun));
        v_ozet := v_ozet || jsonb_build_object('hesap',     pdks.gece_isi_hesapla());
        v_ozet := v_ozet || jsonb_build_object('uyari',     pdks.gece_isi_uyarilar(p_gun));

        update pdks.gece_isi set durum = 'basarili', bitis = clock_timestamp(), ozet = v_ozet where id = v_id;
    exception when others then
        -- Bu bloktaki tüm değişiklikler geri alınır; yalnızca hata kaydı kalır
        update pdks.gece_isi set durum = 'hatali', bitis = clock_timestamp(), hata_mesaji = sqlerrm where id = v_id;
    end;
    return v_id;
end;
$$;

-- ---------------------------------------------------------------------
-- 3. Geriye dönük plan
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
    -- Plansız gün olarak havuzdan onaylanmış çalışma ayrıca plana göre sayılamaz (T-79)
    if p_onay and exists (select 1 from pdks.fazla_mesai_inceleme i join pdks.gun_kaydi g on g.id = i.gun_kaydi_id
                          where g.calisan_id = v_plan.calisan_id and g.is_gunu = v_plan.tarih
                            and g.vardiya_id is null and i.durum = 'onaylandi') then
        raise exception 'Bu günün plansız çalışması havuzdan onaylanmıştır; geriye dönük plan onaylanamaz.';
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
        if v_gun.vardiya_id is null and v_gun.durum = 'vardiya_yok' and v_gun.giris_zamani is not null then
            -- Plansız gün artık planlıdır: plana göre hesaplanır
            perform pdks.duzeltme_uygula(v_gun.id, 'durum', 'tamam', 'Geriye dönük vardiya planı onaylandı', 'ik', v_ben);
        end if;
        perform pdks.gun_hesapla(v_gun.id);
        if v_gun.vardiya_id is null then
            -- Plana göre havuzda süre kalmadıysa bekleyen kayıt kapanır (kalan varsa gun_hesapla güncelledi)
            update pdks.fazla_mesai_inceleme i
            set durum = 'reddedildi', karar_veren_id = v_ben,
                karar_aciklama = 'Geriye dönük vardiya planı onaylandı; süre plana göre hesaplandı'
            from pdks.gun_kaydi g
            where i.gun_kaydi_id = v_gun.id and g.id = v_gun.id and i.durum = 'inceleme_bekliyor'
              and (pdks.donem_kilitli_mi(g.is_gunu)
                   or (select h.onaysiz_fm_dk from pdks.gun_hesabi(g.calisan_id, g.is_gunu, g.planli_baslangic, g.planli_bitis,
                                                                   g.giris_zamani, g.cikis_zamani, g.vardiya_id) h)
                      <= pdks.ayar_al('fm_plansiz_esik_dk'));
        end if;
    elsif not pdks.donem_kilitli_mi(v_plan.tarih)
          and exists (select 1 from pdks.aktarim where kaynak = 'pdks' and veri_tarihi = v_plan.tarih) then
        -- Gün onay beklediği için işlenmemiş: o gün gece işinden yeniden geçer (var olan kayıtlar bozulmaz)
        perform pdks.gece_isi_calistir(v_plan.tarih);
    end if;
end;
$$;
