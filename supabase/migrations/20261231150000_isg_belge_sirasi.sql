-- =====================================================================
-- K10 · T-87: İSG belgesinde "son girilen kayıt" geçerli sayılıyordu; tarih aralığı yoktu
--
-- Sorun: Çalışanın 2027'ye kadar geçerli İSG eğitimi varken İSG uzmanı eski bir sertifikayı
-- (bitiş 01.01.2026) sisteme girdi. Geçerli belge "en son girilen" sayıldığı için çalışan "süresi
-- dolmuş" listesine düştü; belge silinemediği için tek çare geçerli belgeyi yeniden girmekti. Bitiş
-- 1900 ve 2999 kabul ediliyordu (2999 yazılan çalışan hiç uyarı listesine girmez). Beyaz yaka
-- izlenmediği hâlde ekranda "yok" görünüyordu.
--
-- Düzeltme (rapor önerisi):
--   - Geçerli belge, en geç biten belgedir (isg_kontrol ve v_isg_durum: gecerlilik_bitis desc, id desc).
--   - isg_belge_gir: bitiş bugün − 10 yıl ile bugün + 10 yıl arasında. Eski tarihli belge girilebilir
--     (geçmiş kayıt) ama artık geçerli belgeyi gölgelemez.
--   - v_isg_durum'a "izleniyor" sütunu (mavi yaka; uyarı yalnızca bunlar için üretilir).
-- Ekran tarafı (tarih sınırı) Gökalp'te.
-- Kalıcı test: supabase/tests/isg_belge_sirasi_testi.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Gece işindeki İSG kontrolü (son hâli 20261216010000; yalnızca sıralama)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pdks.isg_kontrol(p_gun date)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'pdks'
AS $function$
declare
    v_bas  timestamptz := (p_gun::timestamp at time zone 'Europe/Istanbul');
    v_bit  timestamptz := ((p_gun + 1)::timestamp at time zone 'Europe/Istanbul');
    v_say  integer := 0;
    v_ad   text;
    r      record;
begin
    for r in
        with okutan as (
            select distinct pdks.okutma_sahibi(h.kart_no, h.okutma_zamani) as calisan_id
            from pdks.ham_okutma h
            where h.okutma_zamani >= v_bas and h.okutma_zamani < v_bit and not pdks.okutma_gecersiz_mi(h.id)
            union
            select distinct pdks.okutma_sahibi(k.kart_no, k.okutma_zamani)
            from pdks.kanit_kaydi k
            where k.okutma_zamani >= v_bas and k.okutma_zamani < v_bit
        )
        select c.id as calisan_id, c.sicil_no, t.tur, b.id as belge_id, b.gecerlilik_bitis
        from okutan o
        join pdks.calisan c on c.id = o.calisan_id
        join pdks.departman d on d.id = c.departman_id and d.yaka = 'mavi'
        cross join (values ('isg_egitimi'), ('saglik_muayenesi')) t(tur)
        left join lateral (select * from pdks.isg_belge b
                           where b.calisan_id = c.id and b.tur = t.tur
                           -- T-87: geçerli belge en geç biten belgedir (son girilen değil)
                           order by b.gecerlilik_bitis desc, b.id desc limit 1) b on true
        where b.id is null or b.gecerlilik_bitis < p_gun
    loop
        v_ad := case r.tur when 'isg_egitimi' then 'İSG eğitimi' else 'Periyodik sağlık muayenesi' end;
        if r.belge_id is null then
            v_say := v_say + pdks.uyari_yaz('isg_belgesi_yok', 'isg_yok:' || r.calisan_id || ':' || r.tur,
                format('%s kaydı bulunmuyor; %s tarihinde okutma yapıldı.',
                       v_ad, to_char(p_gun, 'DD.MM.YYYY')), r.calisan_id);
        else
            v_say := v_say + pdks.uyari_yaz('isg_belgesi_suresi_dolmus', 'isg_dolmus:' || r.belge_id,
                format('%s geçerliliği %s tarihinde sona erdi; %s tarihinde okutma yapıldı.',
                       v_ad, to_char(r.gecerlilik_bitis, 'DD.MM.YYYY'), to_char(p_gun, 'DD.MM.YYYY')),
                r.calisan_id);
        end if;
    end loop;

    -- Süresi yakında dolacaklar (okutma gerekmez)
    for r in
        select c.id as calisan_id, c.sicil_no, b.tur, b.id as belge_id, b.gecerlilik_bitis
        from pdks.calisan c
        join pdks.departman d on d.id = c.departman_id and d.yaka = 'mavi'
        cross join lateral (select distinct on (x.tur) x.* from pdks.isg_belge x
                            where x.calisan_id = c.id order by x.tur, x.gecerlilik_bitis desc, x.id desc) b
        where c.aktif
          and b.gecerlilik_bitis >= p_gun and b.gecerlilik_bitis < p_gun + pdks.ayar_al('isg_uyari_gun')
    loop
        v_say := v_say + pdks.uyari_yaz('isg_belgesi_suresi_doluyor', 'isg_doluyor:' || r.belge_id,
            format('%s geçerliliği %s tarihinde sona erecek.',
                   case r.tur when 'isg_egitimi' then 'İSG eğitimi' else 'Periyodik sağlık muayenesi' end,
                   to_char(r.gecerlilik_bitis, 'DD.MM.YYYY')),
            r.calisan_id);
    end loop;
    return v_say;
end;
$function$;

-- ---------------------------------------------------------------------
-- 2. Belge girişi (son hâli 20261216010000; tarih aralığı)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pdks.isg_belge_gir(p_calisan_id bigint, p_tur text, p_gecerlilik_bitis date, p_belge_no text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pdks'
AS $function$
declare
    v_ben  bigint := pdks.yetki_gerekli('isg');
    v_id   bigint;
begin
    if p_tur not in ('isg_egitimi', 'saglik_muayenesi') then
        raise exception 'Geçerli bir belge türü seçilmelidir.';
    end if;
    if p_gecerlilik_bitis is null then
        raise exception 'Geçerlilik bitiş tarihi girilmeli.';
    end if;
    -- T-87: makul aralık (bugün ± 10 yıl)
    if p_gecerlilik_bitis not between (pdks.bugun() - interval '10 years')::date and (pdks.bugun() + interval '10 years')::date then
        raise exception 'Geçerlilik bitişi % ile % arasında olmalı.',
            to_char(pdks.bugun() - interval '10 years', 'DD.MM.YYYY'), to_char(pdks.bugun() + interval '10 years', 'DD.MM.YYYY');
    end if;
    if not exists (select 1 from pdks.calisan where id = p_calisan_id and aktif) then
        raise exception 'Çalışan bulunamadı ya da aktif değil.';
    end if;
    insert into pdks.isg_belge (calisan_id, tur, gecerlilik_bitis, belge_no, giren_id)
    values (p_calisan_id, p_tur, p_gecerlilik_bitis, nullif(trim(p_belge_no), ''), v_ben)
    returning id into v_id;
    return v_id;
end;
$function$;

-- ---------------------------------------------------------------------
-- 3. İSG durum görünümü (son hâli 20261205010000; sıralama + izleniyor sütunu sonda)
-- ---------------------------------------------------------------------
create or replace view pdks.v_isg_durum
with (security_invoker = true)
as
select c.id as calisan_id, c.sicil_no, d.id as departman_id, d.yaka, t.tur,
       b.id as belge_id, b.gecerlilik_bitis,
       case when b.id is null then 'yok'
            when b.gecerlilik_bitis < pdks.bugun() then 'dolmus'
            when b.gecerlilik_bitis < pdks.bugun() + pdks.ayar_al('isg_uyari_gun') then 'doluyor'
            else 'gecerli' end as durum,
       d.yaka = 'mavi' as izleniyor
from pdks.calisan c
join pdks.departman d on d.id = c.departman_id
cross join (values ('isg_egitimi'), ('saglik_muayenesi')) t(tur)
left join lateral (select * from pdks.isg_belge b
                   where b.calisan_id = c.id and b.tur = t.tur
                   order by b.gecerlilik_bitis desc, b.id desc limit 1) b on true
where c.aktif
  -- Belgeyi göremeyen rol (amir, admin) herkesi "yok" görmesin
  and (pdks.tum_veriyi_gorur() or pdks.oturum_rolu() = 'isg');
