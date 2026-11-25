-- =====================================================================
-- K4 · T-58: Havuz onayında günlük 11 saat sınırı denetlenmiyordu
--
-- İş Kanunu m.63: günlük çalışma 11 saati aşamaz. Plan talebi bunu reddeder
-- (fm_plan_denetle: vardiya süresi + planlı dakika ≤ gunluk_azami_calisma_dk). Havuz onayında
-- hiçbir denetim yoktu: plansız 08:00–20:59 çalışan kişinin günü İK onayıyla 719 dk çalışma,
-- FM50 239 olarak sessizce puantaja giriyordu; kayıtta iz kalmıyordu.
--
-- Karar (B yolu, Yusuf ve Fırat, 25.11.2026): T-56 ve T-57 ile aynı. Havuzdaki fiilen yapılmış
-- çalışma reddedilmez: puantaja girer, kayıt işaretlenir ve İK'ya bildirilir.
--
-- Ölçü plan yoluyla aynıdır: mola dahil (brüt) süre. Onaydan sonraki gün hesabında
-- çalışma + mola dakikası (gun_hesabi) = günün onaylanan brüt çalışması. GUNDUZ vardiyasında
-- 660 dk (19:00 çıkış) sınırdadır, 661 dk aşar; plan yolunda da 120 dk kabul, 121 dk ret.
-- Gece işinin fm_gunluk_sinir_asildi uyarısı ("gunluk:" anahtarı) çalışılan günü bildirir;
-- bu migration'ın uyarısı ("havuz:" anahtarı) İK'nın o günü onayladığını kayda geçirir.
-- Molanın 11 saate dahil olup olmadığı İK ile konuşulacak (T-64); değişirse yalnızca ölçü değişir.
--
-- Değişiklik:
--   * fazla_mesai_inceleme.gunluk_sinir_asildi: karar anının izi (yillik_sinir_asildi gibi).
--   * fazla_mesai_inceleme_karar: onayda brüt süre sınırı aşarsa işaretler ve uyarı yazar.
-- Kalıcı test: supabase/tests/gunluk_sinir_testi.sql
-- =====================================================================

alter table pdks.fazla_mesai_inceleme
    add column gunluk_sinir_asildi boolean not null default false,
    add constraint fazla_mesai_inceleme_gunluk_sinir_check check (not gunluk_sinir_asildi or durum = 'onaylandi');

comment on column pdks.fazla_mesai_inceleme.gunluk_sinir_asildi is
    'Kayıt onaylandığında günün brüt çalışması (mola dahil) günlük sınırı (11 saat) aşıyordu (karar anının izi, T-58).';

-- 20261221010000'daki fonksiyon; yalnızca "T-58" satırları eklendi
create or replace function pdks.fazla_mesai_inceleme_karar(p_inceleme_id bigint, p_onay boolean, p_aciklama text default null)
returns void
language plpgsql
security definer
set search_path = pdks
as $$
declare
    v_ben     bigint := pdks.yetki_gerekli('ik');
    v_kayit   pdks.fazla_mesai_inceleme;
    g         pdks.gun_kaydi;
    v_once    record;
    v_sonra   record;
    v_kilitli boolean;
    v_onaysiz boolean;
    v_toplam  integer;
    v_gunluk  integer;
begin
    select * into v_kayit from pdks.fazla_mesai_inceleme where id = p_inceleme_id for update;
    if not found then
        raise exception 'İnceleme kaydı bulunamadı.';
    end if;
    if v_kayit.durum <> 'inceleme_bekliyor' then
        raise exception 'Bu kayıt zaten karara bağlanmış.';
    end if;
    if p_onay is null then
        raise exception 'Karar (onay / ret) belirtilmeli.';
    end if;

    if not p_onay then
        if p_aciklama is null or length(trim(p_aciklama)) < 5 then
            raise exception 'Ret gerekçesi yazılmalı (en az 5 karakter).';
        end if;
        update pdks.fazla_mesai_inceleme
        set durum = 'reddedildi', karar_veren_id = v_ben, karar_aciklama = trim(p_aciklama)
        where id = p_inceleme_id;
        return;
    end if;

    select * into g from pdks.gun_kaydi where id = v_kayit.gun_kaydi_id;
    -- Aynı çalışanın iki onayı aynı anda gelirse toplamı sırayla görsünler (fm_plan_denetle de kilitler)
    perform 1 from pdks.calisan where id = g.calisan_id for update;
    v_onaysiz := not pdks.fm_onay_gecerli_mi(g.calisan_id, g.is_gunu);
    select * into v_once from pdks.gun_hesabi(g.calisan_id, g.is_gunu, g.planli_baslangic, g.planli_bitis,
                                              g.giris_zamani, g.cikis_zamani);
    if pdks.donem_kilitli_mi(g.is_gunu) and v_kayit.tur = 'tatil_calismasi' then
        -- Yazılı onay kilitten sonra girildiyse gun_hesabi tatil çalışmasını artık "önce"de de sayar;
        -- kilitli puantaja giren, gün kaydındaki eski dakikalardır
        v_once.fm50_dk         := coalesce(g.fm50_dk, 0);
        v_once.fm100_dk        := coalesce(g.fm100_dk, 0);
        v_once.calisma_dk      := coalesce(g.calisma_dk, 0);
        v_once.gece_calisma_dk := coalesce(g.gece_calisma_dk, 0);
    end if;
    update pdks.fazla_mesai_inceleme
    set durum = 'onaylandi', karar_veren_id = v_ben, karar_aciklama = nullif(trim(p_aciklama), ''),
        yazili_onaysiz = v_onaysiz
    where id = p_inceleme_id;
    select * into v_sonra from pdks.gun_hesabi(g.calisan_id, g.is_gunu, g.planli_baslangic, g.planli_bitis,
                                               g.giris_zamani, g.cikis_zamani);

    v_kilitli := pdks.donem_kilitli_mi(g.is_gunu);
    update pdks.fazla_mesai_inceleme
    set fm50_etki_dk    = v_sonra.fm50_dk - v_once.fm50_dk,
        fm100_etki_dk   = v_sonra.fm100_dk - v_once.fm100_dk,
        calisma_etki_dk = v_sonra.calisma_dk - v_once.calisma_dk,
        gece_etki_dk    = v_sonra.gece_calisma_dk - v_once.gece_calisma_dk,
        fark_satiri     = v_kilitli,
        hedef_donem_id  = pdks.hedef_donem(g.is_gunu)
    where id = p_inceleme_id;

    if not v_kilitli then
        perform pdks.gun_hesabini_yenile(g.id);
    end if;

    if v_onaysiz then
        perform pdks.uyari_yaz('yazili_onay_eksik', 'havuz:' || p_inceleme_id,
            format('%s için %s tarihli fazla mesai yazılı onay olmadan yapılmıştır; yazılı onay alınmalıdır.',
                   (select ad || ' ' || soyad from pdks.calisan where id = g.calisan_id), to_char(g.is_gunu, 'DD.MM.YYYY')),
            g.calisan_id);
    end if;

    -- T-58: Günlük sınır da havuzda ret sebebi değildir (iş yapılmıştır): kayıt işaretlenir, İK'ya bildirilir.
    -- Ölçü plan yoluyla aynı: mola dahil süre (çalışma + mola), onaylanan hâliyle.
    v_gunluk := coalesce(v_sonra.calisma_dk, 0) + coalesce(v_sonra.mola_dk, 0);
    if v_gunluk > pdks.ayar_al('gunluk_azami_calisma_dk') then
        update pdks.fazla_mesai_inceleme set gunluk_sinir_asildi = true where id = p_inceleme_id;
        perform pdks.uyari_yaz('fm_gunluk_sinir_asildi', 'havuz:' || p_inceleme_id,
            format('%s için %s tarihli %s çalışma (mola dahil) onaylandı; günlük sınır %s (İş Kanunu m.63).',
                   (select ad || ' ' || soyad from pdks.calisan where id = g.calisan_id), to_char(g.is_gunu, 'DD.MM.YYYY'),
                   pdks.sure_metni(v_gunluk), pdks.sure_metni(pdks.ayar_al('gunluk_azami_calisma_dk'))),
            g.calisan_id);
    end if;

    -- Yıllık sınır havuzda ret sebebi değildir (iş yapılmıştır): kayıt işaretlenir, İK'ya bildirilir
    v_toplam := pdks.fm_yillik_toplam(g.calisan_id, extract(year from g.is_gunu)::integer);
    if v_toplam > pdks.ayar_al('fm_yillik_sinir_dk') then
        update pdks.fazla_mesai_inceleme set yillik_sinir_asildi = true where id = p_inceleme_id;
        perform pdks.uyari_yaz('fm_yillik_sinir_asildi', 'havuz:' || p_inceleme_id,
            format('%s yılı onaylı fazla mesai süresi %s (sınır %s).',
                   extract(year from g.is_gunu), pdks.sure_metni(v_toplam), pdks.sure_metni(pdks.ayar_al('fm_yillik_sinir_dk'))),
            g.calisan_id);
    end if;
end;
$$;
