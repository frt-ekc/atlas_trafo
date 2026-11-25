-- =====================================================================
-- K4 · T-57: Yıllık 270 saat sınırı yalnızca planları sayıyordu
--
-- Karar: 270 saate onaylı plan, onaylı havuz ve tatil çalışması (FM100) sayılır.
-- Sınır, ileriye dönük plan talebinde ret sebebidir. Havuzdaki fiilen yapılmış çalışma
-- reddedilmez: puantaja girer, yillik_sinir_asildi işaretlenir ve İK'ya bildirilir.
--
-- Değişiklik:
--   * v_fm_yillik_gun + fm_yillik_toplam(calisan, yil): tek hesap.
--   * v_fazla_mesai_yillik (T-62): aynı hesabı gösterir; ekran bunu okur.
--   * fm_plan_denetle: bu toplamla reddeder (talepte ve onayda).
--   * fazla_mesai_inceleme.yillik_sinir_asildi: karar anının izi (T-56'daki yazili_onaysiz gibi;
--     sınır ya da toplam sonradan değişse de kalır). fazla_mesai_inceleme_karar koyar.
--   * gun_sonrasi_kontroller: yazılı onaylı tatil çalışması sınırı aşarsa uyarı.
-- Kalıcı test: supabase/tests/yillik_fazla_mesai_testi.sql
-- =====================================================================

alter table pdks.fazla_mesai_inceleme
    add column yillik_sinir_asildi boolean not null default false,
    add constraint fazla_mesai_inceleme_yillik_sinir_check check (not yillik_sinir_asildi or durum = 'onaylandi');

comment on column pdks.fazla_mesai_inceleme.yillik_sinir_asildi is
    'Kayıt onaylandığında çalışanın yıllık fazla mesai toplamı sınırı aşıyordu (karar anının izi).';

-- Gün gün fazla mesai; aynı süre iki kez sayılmaz (sinir_dk):
--   * normal gün: onaylı plan + onaylı havuz
--   * Pazar / tatil: gün işlendiyse o günün FM100 dakikası (plan ve açık ayın havuz onayı bunun
--     içindedir) + kilitli aya gelen havuz onayının FM100 farkı; işlenmediyse onaylı plan
-- Çağıranın yetkisiyle çalışır: İK ve yönetici herkesi, amir kendi çalışanlarını görür.
-- union all + group by: çalışan / tarih süzgeci alt tablolara iner (full join'de inmezdi).
create view pdks.v_fm_yillik_gun with (security_invoker = true) as
with gun as (
    select calisan_id, is_gunu, sum(plan)::integer as plan_dk, sum(havuz)::integer as havuz_dk,
           sum(fm100)::integer as fm100_dk, sum(gerceklesen)::integer as gerceklesen_dk
    from (
        select calisan_id, is_gunu, planli_dk as plan, 0 as havuz, 0 as fm100, 0 as gerceklesen
        from pdks.fazla_mesai_plani where durum = 'onaylandi'
        union all
        select calisan_id, is_gunu, 0, dakika,
               case when fark_satiri then fm100_etki_dk else 0 end,
               case when fark_satiri then fm50_etki_dk + fm100_etki_dk else 0 end
        from pdks.fazla_mesai_inceleme where durum = 'onaylandi'
        union all
        select calisan_id, is_gunu, 0, 0, coalesce(fm100_dk, 0), fazla_mesai_dk
        from pdks.gun_kaydi where fazla_mesai_dk > 0
    ) x
    group by calisan_id, is_gunu
)
select calisan_id, is_gunu, plan_dk, havuz_dk, fm100_dk, gerceklesen_dk,
       case when pdks.fm100_gunu_mu(is_gunu) then greatest(fm100_dk, plan_dk)
            else plan_dk + havuz_dk end as sinir_dk
from gun;

comment on view pdks.v_fm_yillik_gun is
    'Gün gün fazla mesai; sinir_dk yıllık 270 saate sayılan dakikadır (fm_yillik_toplam ve v_fazla_mesai_yillik bunu toplar).';
grant select on pdks.v_fm_yillik_gun to authenticated;
-- Görünüm çağıranın yetkisiyle çalıştığı için gerekir (yalnızca takvimi okur)
grant execute on function pdks.fm100_gunu_mu(date) to authenticated;

create function pdks.fm_yillik_toplam(p_calisan_id bigint, p_yil integer)
returns integer
language sql
stable
set search_path = pdks
as $$
    select coalesce(sum(sinir_dk), 0)::integer
    from pdks.v_fm_yillik_gun
    where calisan_id = p_calisan_id
      and is_gunu between make_date(p_yil, 1, 1) and make_date(p_yil, 12, 31);
$$;

-- T-62: yıllık görünüm de aynı günleri toplar (ilk beş sütun eski adlarıyla)
create or replace view pdks.v_fazla_mesai_yillik with (security_invoker = true) as
select g.calisan_id, extract(year from g.is_gunu)::integer as yil,
       sum(g.plan_dk)::integer as onayli_plan_dk,
       sum(g.gerceklesen_dk)::integer as gerceklesen_dk,
       pdks.ayar_al('fm_yillik_sinir_dk') - sum(g.sinir_dk)::integer as kalan_dk,
       sum(g.havuz_dk)::integer as onayli_havuz_dk,
       sum(g.sinir_dk)::integer as toplam_dk,
       pdks.ayar_al('fm_yillik_sinir_dk') as sinir_dk,
       c.sicil_no, c.ad, c.soyad
from pdks.v_fm_yillik_gun g
join pdks.calisan c on c.id = g.calisan_id
group by g.calisan_id, extract(year from g.is_gunu)::integer, c.sicil_no, c.ad, c.soyad;

comment on function pdks.fm_yillik_toplam(bigint, integer) is
    'Çalışanın yıllık fazla mesai toplamı (dk): onaylı plan + onaylı havuz + tatil çalışması. 270 saat sınırı bununla denetlenir.';

revoke execute on function pdks.fm_yillik_toplam(bigint, integer) from public, anon, authenticated;

create or replace function pdks.fm_plan_denetle(p_calisan_id bigint, p_is_gunu date, p_vardiya_id smallint, p_planli_dk integer, p_plan_id bigint)
returns integer
language plpgsql
set search_path = pdks
as $$
declare
    v_gunluk  integer;
    v_toplam  integer;
    v_sinir   integer := pdks.ayar_al('fm_yillik_sinir_dk');
begin
    -- Aynı çalışan için iki onay aynı anda gelirse ikisi de sınırı göremeden geçmesin:
    -- çalışan satırını kilitleyerek işlemleri sıraya sokarız.
    perform 1 from pdks.calisan where id = p_calisan_id for update;

    if not pdks.fm_onay_gecerli_mi(p_calisan_id, p_is_gunu) then
        raise exception 'Çalışanın % günü için geçerli yazılı fazla mesai onayı yok.', p_is_gunu;
    end if;

    if (select gece_yarisini_asar from pdks.vardiya_tanim where id = p_vardiya_id) then
        raise exception 'Gece vardiyası için fazla mesai planlanamaz (İş Kanunu m. 69).';
    end if;

    v_gunluk := pdks.vardiya_suresi_dk(p_vardiya_id) + p_planli_dk;
    if v_gunluk > pdks.ayar_al('gunluk_azami_calisma_dk') then
        raise exception 'Günlük çalışma süresi % olur; sınır %.',
            pdks.sure_metni(v_gunluk), pdks.sure_metni(pdks.ayar_al('gunluk_azami_calisma_dk'));
    end if;

    -- Denetlenen plan henüz 'talep' olduğu için toplama girmez
    v_toplam := pdks.fm_yillik_toplam(p_calisan_id, extract(year from p_is_gunu)::integer);

    if v_toplam + p_planli_dk > v_sinir then
        raise exception 'Yıllık fazla mesai sınırı aşılıyor. Kalan süre: %.', pdks.sure_metni(greatest(v_sinir - v_toplam, 0)::integer);
    end if;
    return v_toplam + p_planli_dk;
end;
$$;

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
    if not g.hesap_tamam or g.durum <> 'tamam' then
        return 0;
    end if;
    select * into h from pdks.gun_hesabi(g.calisan_id, g.is_gunu, g.planli_baslangic, g.planli_bitis,
                                         g.giris_zamani, g.cikis_zamani);
    v_tur := case when pdks.fm100_gunu_mu(g.is_gunu) and not pdks.fm_onay_gecerli_mi(g.calisan_id, g.is_gunu)
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
