-- =====================================================================
-- K7 · T-70: Departman amirinin hesabı pasif olunca ya da rolü değişince yeni sorular ona açılıyordu
--
-- Sorun: Montaj amirinin hesabı pasif yapıldı (emekli oldu) ya da rolü "guvenlik" oldu. Departman
-- amiri olarak o kaldı; gece işi "kart okutmamış, geldi mi?" sorularını ona açmaya devam etti. Pasif
-- kullanıcı giriş yapamıyor, rolü değişen "yetkiniz yok" alıyor. Sorular 3 gün kimse görmeden
-- bekledi; o sırada çalışanın günü "soru bekliyor" kaldı. Eskale de pasif üst amire gidebiliyordu.
--
-- Düzeltme (rapor önerisi; T-43 sınırlılığına dokunmaz: izindeki amirin önceden açılmış sorusu yine
-- onda kalır):
--   1. pdks.soru_alabilir_mi: hesap aktif, rol "amir", çalışanı işten çıkmamış.
--   2. Soru açılırken (soru_atanacak) sıra: amir (izinde değilse) → vekil → amir (izinde, vekil yok)
--      → amirin üst amiri → İK. Her adımda kişi soru alabilmeli.
--   3. Eskale: üst amir soru alamıyorsa İK'ya.
--   4. Amir soru alamaz hâle gelince (kullanici.aktif / rol değişikliği; hangi yoldan olursa olsun:
--      kullanici_guncelle, rol onayı, isten_cikis_gir) tetikleyici açık sorularını yukarıdaki sıraya
--      göre devreder ve amiri ya da vekili olduğu her departman için İK'ya "amirsiz_departman"
--      uyarısı yazar ("yeni amir atanmalı; sorular şimdilik X'e gidiyor").
--   5. Kurulumda: soru alamayan kişide bekleyen açık sorular bir kez devredilir.
-- İşlem reddedilmez: amir emekli olduğunda çıkış ya da hesap kapatma beklemeden yapılabilmeli.
-- Kalıcı test: supabase/tests/gecersiz_amir_testi.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Yeni uyarı türü
-- ---------------------------------------------------------------------
alter table pdks.uyari drop constraint uyari_tur_check;
alter table pdks.uyari add constraint uyari_tur_check check (tur in (
    'amirsiz_departman', 'ariza_suphesi', 'cikis_kilitli_ay', 'dosya_gelmedi', 'fm_gunluk_sinir_asildi',
    'fm_onay_geri_alindi', 'fm_onay_yok', 'fm_plansiz_calisma', 'fm_yillik_sinir_asildi', 'fm_yillik_sinir_yaklasti',
    'gece_calisma_siniri_asildi', 'gece_isi_calismadi', 'gecici_kart_cakisma', 'gecici_kart_iade_edilmedi',
    'gecici_kart_zimmetsiz', 'geriye_donuk_vardiya', 'iptal_kart_okutma', 'isg_belgesi_suresi_dolmus',
    'isg_belgesi_suresi_doluyor', 'isg_belgesi_yok', 'izin_gununde_okutma', 'kart_paylasim_suphesi',
    'kendi_okutmasi_yuklendi', 'plansiz_gun_calismasi', 'puantaj_ayari_degisti', 'sik_kart_unutma',
    'soru_eskale', 'yazili_onay_eksik', 'yetkisiz_bolge_okutmasi'));

-- ---------------------------------------------------------------------
-- 2. Soru alabilir mi, departmanın soru hedefi, çalışanın soru hedefi
--    soru_alabilir_mi SET'siz SQL fonksiyonu (adlar pdks. ile yazılı): çağıran sorgunun içine açılır.
-- ---------------------------------------------------------------------
create function pdks.soru_alabilir_mi(p_kullanici_id bigint)
returns boolean
language sql
stable
as $$
    select exists (
        select 1 from pdks.kullanici k
        left join pdks.calisan c on c.id = k.calisan_id
        where k.id = p_kullanici_id and k.aktif and k.rol = 'amir'
          and (c.id is null or c.isten_cikis_tarihi is null));
$$;
comment on function pdks.soru_alabilir_mi(bigint) is
    'Kullanıcı amir sorusu alıp cevaplayabilir mi: hesap aktif, rol amir, çalışanı işten çıkmamış (T-70).';

-- İK'ya düşmeden önceki son kişi; yoksa null. PL/pgSQL: planı önbellekte tutulur (gece işinde
-- soru başına çağrılır; SQL sürümü 2000 çağrıda ~10 kat yavaştı)
create function pdks.departman_soru_hedefi(p_departman_id bigint)
returns bigint
language plpgsql
stable
set search_path = pdks
as $$
declare
    d record;
begin
    select dp.amir_id, dp.vekil_amir_id, a.ust_amir_id into d
    from pdks.departman dp
    left join pdks.kullanici a on a.id = dp.amir_id
    where dp.id = p_departman_id;
    if pdks.soru_alabilir_mi(d.amir_id) and not pdks.kullanici_izinli_mi(d.amir_id) then
        return d.amir_id;
    end if;
    if pdks.soru_alabilir_mi(d.vekil_amir_id) then
        return d.vekil_amir_id;
    end if;
    if pdks.soru_alabilir_mi(d.amir_id) then        -- amir izinde, vekili yok: eskisi gibi amirde
        return d.amir_id;
    end if;
    if pdks.soru_alabilir_mi(d.ust_amir_id) then
        return d.ust_amir_id;
    end if;
    return null;
end;
$$;

-- Çalışanın sorusu kime açılır; departmanda soru alabilen yoksa İK (çalışanın kendisi değil)
create or replace function pdks.soru_atanacak(p_calisan_id bigint)
returns bigint
language sql
stable
set search_path = pdks
as $$
    select coalesce(
        (select pdks.departman_soru_hedefi(c.departman_id) from pdks.calisan c where c.id = p_calisan_id),
        pdks.ik_sorumlusu(p_calisan_id));
$$;

revoke execute on function pdks.soru_alabilir_mi(bigint) from public, anon;
revoke execute on function pdks.departman_soru_hedefi(bigint) from public, anon;
grant execute on function pdks.soru_alabilir_mi(bigint) to authenticated;
grant execute on function pdks.departman_soru_hedefi(bigint) to authenticated;

-- ---------------------------------------------------------------------
-- 3. Soru alamayan kişinin açık sorularını devret
--    Açık soru: yeni hedef (soru_atanacak; çalışanın kendisi çıkarsa İK). Eskale soru: İK.
--    Dönen: devredilen soru sayısı.
-- ---------------------------------------------------------------------
create function pdks.amir_sorularini_devret(p_kullanici_id bigint)
returns integer
language plpgsql
set search_path = pdks
as $$
declare
    v_say   integer := 0;
    v_hedef bigint;
    s       record;
begin
    for s in
        select q.id, q.durum, g.calisan_id
        from pdks.amir_sorusu q
        join pdks.gun_kaydi g on g.id = q.gun_kaydi_id
        where (q.durum = 'acik' and q.atanan_id = p_kullanici_id)
           or (q.durum = 'eskale' and q.eskale_edilen_id = p_kullanici_id)
        order by q.id
    loop
        if s.durum = 'acik' then
            v_hedef := pdks.soru_atanacak(s.calisan_id);
            if v_hedef is null or pdks.kullanici_calisani(v_hedef) = s.calisan_id then
                v_hedef := pdks.ik_sorumlusu(s.calisan_id);
            end if;
            continue when v_hedef is null or v_hedef = p_kullanici_id;
            update pdks.amir_sorusu set atanan_id = v_hedef where id = s.id;
        else
            v_hedef := pdks.ik_sorumlusu(s.calisan_id);
            continue when v_hedef is null;
            update pdks.amir_sorusu set eskale_edilen_id = v_hedef where id = s.id;
        end if;
        v_say := v_say + 1;
    end loop;
    return v_say;
end;
$$;
revoke execute on function pdks.amir_sorularini_devret(bigint) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 4. Amir soru alamaz hâle gelince: devret ve İK'ya uyar
-- ---------------------------------------------------------------------
create function pdks.kullanici_amir_gecersiz()
returns trigger
language plpgsql
set search_path = pdks
as $$
declare
    v_neden text;
    v_hedef bigint;
    v_devir jsonb;
    d       record;
begin
    if pdks.soru_alabilir_mi(new.id) then
        return new;
    end if;
    -- Devredilecek açık soruların departman başına sayısı (uyarı metni için)
    select coalesce(jsonb_object_agg(x.departman_id::text, x.n), '{}'::jsonb) into v_devir
    from (select c.departman_id, count(*) as n
          from pdks.amir_sorusu q
          join pdks.gun_kaydi g on g.id = q.gun_kaydi_id
          join pdks.calisan c on c.id = g.calisan_id
          where (q.durum = 'acik' and q.atanan_id = new.id) or (q.durum = 'eskale' and q.eskale_edilen_id = new.id)
          group by c.departman_id) x;
    perform pdks.amir_sorularini_devret(new.id);
    v_neden := case when not new.aktif then 'hesabı pasif'
                    else 'rolü ' || case new.rol when 'guvenlik' then 'güvenlik' when 'ik' then 'İK'
                                                 when 'yonetici' then 'yönetici' when 'isg' then 'İSG uzmanı'
                                                 when 'admin' then 'sistem yöneticisi' else new.rol end
               end;
    for d in
        select dp.id, dp.ad, case when dp.amir_id = new.id then 'amiri' else 'vekil amiri' end as gorev
        from pdks.departman dp
        where dp.amir_id = new.id or dp.vekil_amir_id = new.id
        order by dp.ad
    loop
        v_hedef := pdks.departman_soru_hedefi(d.id);
        perform pdks.uyari_yaz('amirsiz_departman',
            'amirsiz:' || d.id || ':' || new.id || ':' || extract(epoch from now())::bigint,
            format('%s departmanının %s %s artık soru cevaplayamıyor (%s). Departmana yeni %s atanmalıdır. '
                   || 'Sorular şimdilik şu kişiye açılıyor: %s. Bu departmandan %s açık soru devredildi.',
                   d.ad, d.gorev, new.ad_soyad, v_neden,
                   case when d.gorev = 'amiri' then 'amir' else 'vekil amir' end,
                   coalesce((select ad_soyad from pdks.kullanici where id = v_hedef), 'İK'),
                   coalesce((v_devir ->> d.id::text)::integer, 0)));
    end loop;
    return new;
end;
$$;
revoke execute on function pdks.kullanici_amir_gecersiz() from public, anon, authenticated;

create trigger kullanici_amir_gecersiz
after update of aktif, rol on pdks.kullanici
for each row
when (old.aktif and old.rol = 'amir' and (not new.aktif or new.rol <> 'amir'))
execute function pdks.kullanici_amir_gecersiz();

-- ---------------------------------------------------------------------
-- 5. Eskale (son hâli 20261216010000; yalnızca üst amir koşulu değişti)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pdks.gece_isi_eskale(p_gun date)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'pdks'
AS $function$
declare
    v_say  integer := 0;
    v_hedef bigint;
    v_sure  integer := pdks.ayar_al('soru_eskalasyon_gun');
    s      record;
begin
    -- İkinci kademe (T-39): üst amire gitmiş soru, onun süresi de dolduysa İK'ya geçer.
    -- Birinci kademeden önce çalışır: bir gecede soru en çok bir kademe ilerler.
    for s in
        select q.id, g.calisan_id, g.is_gunu
        from pdks.amir_sorusu q
        join pdks.gun_kaydi g on g.id = q.gun_kaydi_id
        where q.durum = 'eskale'
          and q.son_cevap_tarihi + v_sure <= p_gun
          and pdks.kullanici_rolu(q.eskale_edilen_id) is distinct from 'ik'
        order by q.id
    loop
        update pdks.amir_sorusu
        set durum = 'ik_karari_bekliyor', ik_eskale_zamani = now()
        where id = s.id;
        v_say := v_say + 1;
        perform pdks.uyari_yaz('soru_eskale', 'soru_ik:' || s.id,
            format('%s tarihli soru üst amir tarafından süresinde cevaplanmadı ve İK''ya iletildi.', to_char(s.is_gunu, 'DD.MM.YYYY')),
            s.calisan_id);
    end loop;

    -- Birinci kademe: amir süresinde cevaplamadıysa üst amire (üst amiri yoksa ya da üst
    -- amir çalışanın kendisiyse İK'ya)
    for s in
        select q.id, q.atanan_id, g.calisan_id, g.is_gunu
        from pdks.amir_sorusu q
        join pdks.gun_kaydi g on g.id = q.gun_kaydi_id
        where q.durum = 'acik' and q.son_cevap_tarihi <= p_gun
        order by q.id
    loop
        select ust_amir_id into v_hedef from pdks.kullanici where id = s.atanan_id;
        -- T-70: üst amir soru cevaplayamıyorsa (hesap pasif, rol amir değil) İK'ya
        if v_hedef is null or pdks.kullanici_calisani(v_hedef) = s.calisan_id
           or not pdks.soru_alabilir_mi(v_hedef) then
            v_hedef := pdks.ik_sorumlusu(s.calisan_id);
        end if;
        update pdks.amir_sorusu
        set durum = 'eskale', eskale_zamani = now(), eskale_edilen_id = v_hedef
        where id = s.id;
        v_say := v_say + 1;
        perform pdks.uyari_yaz('soru_eskale', 'soru:' || s.id,
            format('%s tarihli soru süresinde cevaplanmadı ve bir üst kademeye iletildi.', to_char(s.is_gunu, 'DD.MM.YYYY')),
            s.calisan_id);
    end loop;
    return v_say;
end;
$function$;

-- ---------------------------------------------------------------------
-- 6. Kurulumda bir kez: soru alamayan kişide bekleyen açık sorular devredilir
-- ---------------------------------------------------------------------
do $$
declare
    k record;
begin
    for k in
        select distinct x.kid
        from (select atanan_id as kid from pdks.amir_sorusu where durum = 'acik'
              union all
              select eskale_edilen_id from pdks.amir_sorusu where durum = 'eskale') x
        where x.kid is not null and pdks.kullanici_rolu(x.kid) <> 'ik' and not pdks.soru_alabilir_mi(x.kid)
    loop
        perform pdks.amir_sorularini_devret(k.kid);
    end loop;
end $$;
