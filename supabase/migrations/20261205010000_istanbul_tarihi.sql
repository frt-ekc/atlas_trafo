-- =====================================================================
-- K1 · "Bugün" İstanbul'a göre (T-45, T-59, T-04)
--
-- current_date oturumun saat dilimine göre çalışır. Canlıda ekrandan (PostgREST)
-- gelen istekler ve pg_cron UTC oturumla çalışır; İstanbul 00:00–03:00 arasında
-- current_date "dün"ü verir. Bu yüzden ör. amirin dünkü günü için girdiği plan
-- gece 3 saat boyunca İK onayı istemeden geçiyordu (T-45).
--
-- Değişiklik:
--   * pdks.bugun(): İstanbul'a göre bugünün tarihi. Gün gereken her yerde
--     current_date yerine bu kullanılır (tek kural, tek yer).
--   * Şemada current_date geçen altı yerin hepsi buna çevrildi:
--     vardiya_plani_gir, fazla_mesai_plani_kontrol, gece_isi_calistir,
--     v_gece_isi_durumu, v_isg_durum, kart.verilis_tarihi varsayılanı;
--     ayrıca pg_cron'daki gece işi komutu.
--     Fonksiyonların geri kalanı pg_get_functiondef ile alınan son sürümle
--     birebir aynıdır; görünümlerin sütunları ve yetkileri değişmez.
--   * T-59: Yazılı onayın geri alınması, geçmişte onaylı (çalışılmış) bir plan ya da
--     kilitli ayda bir plan varsa tamamen reddediliyordu; çalışanın geri çekilmesi
--     hiç kaydedilemiyordu. Artık geri alma her zaman kaydedilir:
--       - ileri tarihli (bugün dahil) onaylı planlar ve bütün talepler sistemce
--         (kişisiz) iptal edilir;
--       - geçmişteki onaylı planlar ve kilitli aydaki planlar korunur, sayısı
--         İK uyarısına yazılır.
-- Kalıcı test: supabase/tests/istanbul_tarihi_testi.sql (UTC−12 ve UTC+14 oturumla).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. İstanbul'a göre bugün
-- ---------------------------------------------------------------------
create function pdks.bugun()
returns date
language sql
stable
set search_path = pdks
as $$
    select (now() at time zone 'Europe/Istanbul')::date;
$$;
comment on function pdks.bugun() is
    'İstanbul saatine göre bugünün tarihi. Oturumun saat dilimi (canlıda UTC) ne olursa olsun aynı sonucu verir; gün gereken yerde current_date yerine bu kullanılır.';
revoke execute on function pdks.bugun() from public, anon;
grant execute on function pdks.bugun() to authenticated;

-- ---------------------------------------------------------------------
-- 2. vardiya_plani_gir: geriye dönük kararı (T-45). Değişen tek satır: v_geri
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pdks.vardiya_plani_gir(p_calisan_id bigint, p_tarih date, p_vardiya_id smallint, p_aciklama text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pdks'
AS $function$
declare
    v_ben     bigint := pdks.yetki_gerekli('amir', 'ik');
    v_geri    boolean := p_tarih < pdks.bugun();
    v_id      bigint;
begin
    perform pdks.calisan_yetkisi(p_calisan_id);
    if pdks.donem_kilitli_mi(p_tarih) then
        raise exception '% günü kilitli bir döneme ait.', p_tarih;
    end if;
    insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id, giren_id, giris_zamani,
                                    geriye_donuk, ik_onay_durumu, aciklama)
    values (p_calisan_id, p_tarih, p_vardiya_id, v_ben, now(),
            v_geri, case when v_geri then 'bekliyor' else 'gerekmez' end, p_aciklama)
    on conflict (calisan_id, tarih) do update
        set vardiya_id = excluded.vardiya_id, giren_id = excluded.giren_id, giris_zamani = excluded.giris_zamani,
            geriye_donuk = excluded.geriye_donuk, ik_onay_durumu = excluded.ik_onay_durumu,
            aciklama = excluded.aciklama
    returning id into v_id;
    return v_id;
end;
$function$;

-- ---------------------------------------------------------------------
-- 3. fazla_mesai_plani_kontrol: "geçmiş günün onaylı planı" (T-59 saat kısmı).
--    Değişen tek satır: old.is_gunu < pdks.bugun()
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pdks.fazla_mesai_plani_kontrol()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pdks'
AS $function$
declare
    v_toplam  integer;
    v_esik    integer;
begin
    if tg_op = 'DELETE' then
        raise exception 'Fazla mesai planı silinemez; iptal edilir.';
    end if;

    if pdks.donem_kilitli_mi(case when tg_op = 'INSERT' then new.is_gunu else old.is_gunu end) then
        raise exception '% günü kilitli bir döneme ait; fazla mesai planı değişmez.', new.is_gunu;
    end if;

    -- Yeni talep -------------------------------------------------------
    if tg_op = 'INSERT' then
        if new.durum <> 'talep' then
            raise exception 'Yeni plan "talep" olarak girilir; onayı İK verir.';
        end if;
        if pdks.kullanici_rolu(new.talep_eden_id) not in ('amir', 'ik')
           or pdks.kullanici_rolu(new.talep_eden_id) is null then
            raise exception 'Fazla mesaiyi yalnızca amir ya da İK talep eder.';
        end if;
        select vardiya_id into new.vardiya_id
        from pdks.vardiya_plani where calisan_id = new.calisan_id and tarih = new.is_gunu;
        if new.vardiya_id is null then
            raise exception 'Çalışanın % günü için vardiya planı yok.', new.is_gunu;
        end if;
        new.talep_zamani := now();
        new.karar_veren_id := null;
        new.karar_aciklama := null;
        perform pdks.fm_plan_denetle(new.calisan_id, new.is_gunu, new.vardiya_id, new.planli_dk, new.id);
        return new;
    end if;

    -- Güncelleme: yalnızca durum geçişi ------------------------------
    if (new.calisan_id, new.is_gunu, new.vardiya_id, new.planli_dk, new.gerekce,
        new.talep_eden_id, new.talep_zamani)
       is distinct from
       (old.calisan_id, old.is_gunu, old.vardiya_id, old.planli_dk, old.gerekce,
        old.talep_eden_id, old.talep_zamani) then
        raise exception 'Planın içeriği değiştirilemez; iptal edip yeni talep girin.';
    end if;
    if new.durum = old.durum then
        if new is distinct from old then
            raise exception 'Plan kararı değiştirilemez.';
        end if;
        return new;
    end if;
    if old.durum in ('reddedildi', 'iptal') then
        raise exception 'Karara bağlanmış plan değiştirilemez.';
    end if;
    if old.durum = 'onaylandi' and new.durum <> 'iptal' then
        raise exception 'Onaylı plan yalnızca iptal edilebilir.';
    end if;

    if new.durum in ('onaylandi', 'reddedildi') then
        if pdks.kullanici_rolu(new.karar_veren_id) is distinct from 'ik' then
            raise exception 'Fazla mesai planını yalnızca İK onaylar veya reddeder.';
        end if;
        if new.durum = 'onaylandi' then
            v_toplam := pdks.fm_plan_denetle(new.calisan_id, new.is_gunu, new.vardiya_id, new.planli_dk, new.id);
            v_esik := pdks.ayar_al('fm_yillik_sinir_dk') * pdks.ayar_al('fm_yaklasma_uyari_yuzde') / 100;
            -- Eşiği bu onayla geçtiyse bir kez uyar
            if v_toplam >= v_esik and v_toplam - new.planli_dk < v_esik then
                insert into pdks.uyari (tur, calisan_id, mesaj)
                values ('fm_yillik_sinir_yaklasti', new.calisan_id,
                        format('Yıllık onaylı fazla mesai %s / %s dakikaya ulaştı.',
                               v_toplam, pdks.ayar_al('fm_yillik_sinir_dk')));
            end if;
        end if;
    elsif new.durum = 'iptal' then
        if new.karar_veren_id is null then
            -- Kişisiz (sistem) iptal yalnızca yazılı onay o gün için geçersizse olur
            if pdks.fm_onay_gecerli_mi(new.calisan_id, new.is_gunu) then
                raise exception 'İptal eden kullanıcı belirtilmeli.';
            end if;
        else
            if pdks.kullanici_rolu(new.karar_veren_id) not in ('amir', 'ik')
               or pdks.kullanici_rolu(new.karar_veren_id) is null then
                raise exception 'Planı yalnızca amir ya da İK iptal eder.';
            end if;
            if old.durum = 'onaylandi' and old.is_gunu < pdks.bugun() then
                raise exception 'Geçmiş bir günün onaylı planı iptal edilemez.';
            end if;
        end if;
    else
        raise exception 'Geçersiz durum geçişi: % -> %', old.durum, new.durum;
    end if;

    new.karar_zamani := now();
    return new;
end;
$function$;

-- ---------------------------------------------------------------------
-- 4. fazla_mesai_onayi_geri_alindi: geri alma her zaman kaydedilir (T-59)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pdks.fazla_mesai_onayi_geri_alindi()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pdks'
AS $function$
declare
    v_say    integer;
    v_kalan  integer;
begin
    -- Sistem (kişisiz) iptali: karar_veren_id boşaltılır; fazla_mesai_plani_kontrol bunu
    -- "yazılı onay o gün için geçersiz" yolundan geçirir. Geçmişteki onaylı plan
    -- (çalışılmış gün) ve kilitli aydaki plan iptal edilmez; geri alma yine de kaydedilir.
    update pdks.fazla_mesai_plani
    set durum = 'iptal',
        karar_veren_id = null,
        karar_aciklama = format('Yazılı onay geri alındı (bildirim %s)', new.geri_alma_bildirim_tarihi)
    where calisan_id = new.calisan_id
      and extract(year from is_gunu) = new.yil
      and is_gunu >= new.gecerlilik_bitisi
      and (durum = 'talep' or (durum = 'onaylandi' and is_gunu >= pdks.bugun()))
      and not pdks.donem_kilitli_mi(is_gunu);
    get diagnostics v_say = row_count;

    select count(*) into v_kalan
    from pdks.fazla_mesai_plani
    where calisan_id = new.calisan_id
      and extract(year from is_gunu) = new.yil
      and is_gunu >= new.gecerlilik_bitisi
      and durum in ('talep', 'onaylandi');

    insert into pdks.uyari (tur, calisan_id, mesaj)
    values ('fm_onay_geri_alindi', new.calisan_id,
            format('Fazla mesai onayı geri alındı; %s tarihinden itibaren geçersiz. %s plan iptal edildi.%s',
                   new.gecerlilik_bitisi, v_say,
                   case when v_kalan > 0 then
                       format(' %s plan geçmiş bir güne ya da kilitli aya ait olduğu için iptal edilmedi; İK incelemeli.', v_kalan)
                   else '' end));
    return null;
end;
$function$;

-- ---------------------------------------------------------------------
-- 5. gece_isi_calistir: işlenebilecek en ileri gün İstanbul'un dünü.
--    Değişen tek satır: pdks.bugun() - 1
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pdks.gece_isi_calistir(p_gun date)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pdks'
AS $function$
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
$function$;

-- ---------------------------------------------------------------------
-- 6. Görünümler (sütunlar, security_invoker ve yetkiler aynı kalır)
-- ---------------------------------------------------------------------
create or replace view pdks.v_gece_isi_durumu
with (security_invoker = true)
as
select pdks.bugun() - 1 as gun,
       exists (select 1 from pdks.gece_isi
               where islenen_gun = pdks.bugun() - 1 and durum = 'basarili') as calisti;

create or replace view pdks.v_isg_durum
with (security_invoker = true)
as
select c.id as calisan_id, c.sicil_no, d.id as departman_id, d.yaka, t.tur,
       b.id as belge_id, b.gecerlilik_bitis,
       case when b.id is null then 'yok'
            when b.gecerlilik_bitis < pdks.bugun() then 'dolmus'
            when b.gecerlilik_bitis < pdks.bugun() + pdks.ayar_al('isg_uyari_gun') then 'doluyor'
            else 'gecerli' end as durum
from pdks.calisan c
join pdks.departman d on d.id = c.departman_id
cross join (values ('isg_egitimi'), ('saglik_muayenesi')) t(tur)
left join lateral (select * from pdks.isg_belge b
                   where b.calisan_id = c.id and b.tur = t.tur
                   order by b.id desc limit 1) b on true
where c.aktif
  -- Belgeyi göremeyen rol (amir, admin) herkesi "yok" görmesin
  and (pdks.tum_veriyi_gorur() or pdks.oturum_rolu() = 'isg');

-- ---------------------------------------------------------------------
-- 7. Kartın veriliş tarihi varsayılanı
-- ---------------------------------------------------------------------
alter table pdks.kart alter column verilis_tarihi set default pdks.bugun();

-- ---------------------------------------------------------------------
-- 8. Zamanlanmış gece işi (pg_cron, 20261120010000_gece_isi.sql §14)
--    Saat aynı: 06:30 Türkiye = 03:30 UTC; o saatte UTC ve İstanbul tarihi zaten
--    aynı. Yine de komut da pdks.bugun()'ü kullansın: zamanlama değişirse gün kaymaz.
--    Aynı adla schedule mevcut görevi günceller.
-- ---------------------------------------------------------------------
select cron.schedule(
    'pdks-gece-isi',
    '30 3 * * *',
    $cron$select pdks.gece_isi_calistir(pdks.bugun() - 2); select pdks.gece_isi_calistir(pdks.bugun() - 1);$cron$
);
