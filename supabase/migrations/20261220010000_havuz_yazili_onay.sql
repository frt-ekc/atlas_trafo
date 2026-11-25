-- =====================================================================
-- K4 · T-56: Yazılı onayı olmayan çalışanın havuz onayı iz bırakmıyordu
--
-- Karar: Yazılı onay (İş Kanunu m.41) işveren yükümlülüğüdür. Fiilen yapılan çalışma puantaja
-- girer; eksiklik işaretlenir ve İK'ya bildirilir. Bu yüzden gun_hesabi ve
-- gun_kaydi_fazla_mesai_kontrol değişmez: onaylanan havuz dakikasını zaten yazılı onaydan
-- bağımsız sayarlar. (Plan talebinde yazılı onay şartı sürer.)
--
-- Değişiklik:
--   * fazla_mesai_inceleme.yazili_onaysiz: kayıt, o gün geçerli yazılı onay yokken onaylandı.
--     Ayrı sütun: karar anının izidir. Onaydan sonra belge girilirse canlı hesap (fm_onay_gecerli_mi)
--     "var" der ve iz kaybolur; karar_aciklama ise İK'nın serbest metnidir.
--   * fazla_mesai_inceleme_karar: bu durumda işareti koyar ve yazili_onay_eksik uyarısı yazar.
--   * Kilitli ayın tatil çalışması: imzalı belge kilitten sonra girilip kayıt onaylanırsa
--     fark, kilitli puantajdaki dakikalara göre hesaplanır (yoksa fark 0 çıkardı).
-- Kalıcı test: supabase/tests/havuz_yazili_onay_testi.sql
-- =====================================================================

alter table pdks.fazla_mesai_inceleme
    add column yazili_onaysiz boolean not null default false,
    add constraint fazla_mesai_inceleme_yazili_onaysiz_check check (not yazili_onaysiz or durum = 'onaylandi');

comment on column pdks.fazla_mesai_inceleme.yazili_onaysiz is
    'Kayıt, çalışanın o gün için geçerli yazılı fazla mesai onayı yokken onaylandı (karar anının izi).';

alter table pdks.uyari drop constraint uyari_tur_check;
alter table pdks.uyari add constraint uyari_tur_check check (tur in (
    'ariza_suphesi', 'dosya_gelmedi', 'fm_gunluk_sinir_asildi',
    'fm_onay_geri_alindi', 'fm_onay_yok', 'fm_plansiz_calisma',
    'fm_yillik_sinir_asildi', 'fm_yillik_sinir_yaklasti', 'gece_calisma_siniri_asildi',
    'gece_isi_calismadi', 'gecici_kart_cakisma', 'gecici_kart_iade_edilmedi',
    'gecici_kart_zimmetsiz', 'geriye_donuk_vardiya', 'iptal_kart_okutma',
    'isg_belgesi_suresi_dolmus', 'isg_belgesi_suresi_doluyor', 'isg_belgesi_yok',
    'kart_paylasim_suphesi', 'kendi_okutmasi_yuklendi', 'puantaj_ayari_degisti',
    'sik_kart_unutma', 'soru_eskale', 'yazili_onay_eksik',
    'yetkisiz_bolge_okutmasi'
));

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

    -- Yıllık sınır: onaylı planlar + onaylanan havuz kayıtları
    select coalesce((select sum(planli_dk) from pdks.fazla_mesai_plani
                     where calisan_id = g.calisan_id and durum = 'onaylandi'
                       and extract(year from is_gunu) = extract(year from g.is_gunu)), 0)
         + coalesce((select sum(dakika) from pdks.fazla_mesai_inceleme
                     where calisan_id = g.calisan_id and durum = 'onaylandi'
                       and extract(year from is_gunu) = extract(year from g.is_gunu)), 0)
      into v_toplam;
    if v_toplam > pdks.ayar_al('fm_yillik_sinir_dk') then
        perform pdks.uyari_yaz('fm_yillik_sinir_asildi', 'havuz:' || p_inceleme_id,
            format('%s yılı onaylı fazla mesai süresi %s (sınır %s).',
                   extract(year from g.is_gunu), pdks.sure_metni(v_toplam::integer), pdks.sure_metni(pdks.ayar_al('fm_yillik_sinir_dk'))),
            g.calisan_id);
    end if;
end;
$$;
