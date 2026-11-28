-- =====================================================================
-- Amirin aleyhe saati ve karar izleri (T-44, T-35)
--
--   T-44: Amirin girdiği giriş / çıkış saati geç kalma ya da erken çıkış doğuruyorsa düzeltme
--         "çalışan aleyhine" işaretlenir. Ölçü günün kendi hesabıdır (pdks.gun_hesabi): tolerans,
--         esnek mesai ve saatlik izin aynı kuralla sayılır. Amirin yetkisi değişmez (saat beyanı
--         amirdedir); işaret İK'nın aleyhe düzeltmeleri süzebilmesi ve dökümde görünmesi içindir.
--         İK'nın kendi düzeltmesi bu kurala girmez: aleyhe karar zaten İK'nındır (KVKK m.11).
--         Gece işi fonksiyonlarına ve gun_hesabi'ya dokunulmaz; duzeltme'de BEFORE INSERT
--         tetikleyicisi yalnızca gun_hesabi'yı çağırır.
--   T-35: İtirazı incelemeye alan ve zamanı (itiraz.inceleyen_id, inceleme_zamani); arızaya karar
--         veren ve zamanı (ariza.karar_veren_id, karar_zamani). ariza_karar artık giren_id'yi
--         karar verenle ezmez; eski kararlar taşınır.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. T-44: amirin aleyhe saati
-- ---------------------------------------------------------------------
-- Eski kural: aleyhe işaretini yalnızca İK kaynaklı düzeltme taşır (aleyhe = İK kararı).
-- Yeni kural: amirin giriş / çıkış saati de işaretlenebilir (bu bir İK kararı değil, iz).
-- Devamsızlık ve diğer aleyhe kararlar yine yalnızca İK'dadır (duzeltme_hazirla, itiraz_kontrol).
alter table pdks.duzeltme drop constraint duzeltme_check2;
alter table pdks.duzeltme add constraint duzeltme_aleyhe_kaynagi
    check (not calisan_aleyhine or kaynak = 'ik'
           or (kaynak = 'amir' and alan in ('giris_zamani', 'cikis_zamani')));

create function pdks.duzeltme_amir_aleyhe()
returns trigger
language plpgsql
set search_path = pdks, pg_temp
as $$
declare
    v_gun    pdks.gun_kaydi;
    v_saat   timestamptz;
    v_giris  timestamptz;
    v_cikis  timestamptz;
    h        record;
begin
    if new.kaynak <> 'amir' or new.alan not in ('giris_zamani', 'cikis_zamani')
       or new.yeni_deger is null or new.calisan_aleyhine then
        return new;
    end if;
    select * into v_gun from pdks.gun_kaydi where id = new.gun_kaydi_id;
    if v_gun.planli_baslangic is null or v_gun.planli_bitis is null then
        return new;                                   -- plan yoksa geç kalma / erken çıkış da yok
    end if;
    v_saat := new.yeni_deger::timestamptz;
    -- Diğer saat yoksa plandaki saat alınır: yalnızca yazılan saatin etkisi ölçülür
    if new.alan = 'giris_zamani' then
        v_giris := v_saat;
        v_cikis := coalesce(v_gun.cikis_zamani, v_gun.planli_bitis);
    else
        v_giris := coalesce(v_gun.giris_zamani, v_gun.planli_baslangic);
        v_cikis := v_saat;
    end if;
    if v_cikis <= v_giris then
        return new;                                   -- tutarsız saat; duzeltme_uygula / hesap kendi kuralını uygular
    end if;
    select * into h from pdks.gun_hesabi(v_gun.calisan_id, v_gun.is_gunu, v_gun.planli_baslangic, v_gun.planli_bitis,
                                         v_giris, v_cikis, v_gun.vardiya_id);
    if (new.alan = 'giris_zamani' and coalesce(h.gec_kalma_dk, 0) > 0)
       or (new.alan = 'cikis_zamani' and coalesce(h.erken_cikis_dk, 0) > 0) then
        new.calisan_aleyhine := true;
    end if;
    return new;
end;
$$;
comment on function pdks.duzeltme_amir_aleyhe() is
    'T-44: amirin yazdığı saat geç kalma / erken çıkış doğuruyorsa düzeltme çalışan aleyhine işaretlenir (gun_hesabi ile ölçülür).';
create trigger duzeltme_amir_aleyhe before insert on pdks.duzeltme
    for each row execute function pdks.duzeltme_amir_aleyhe();

-- ---------------------------------------------------------------------
-- 2. T-35: itirazı incelemeye alma izi
-- ---------------------------------------------------------------------
alter table pdks.itiraz
    add column inceleyen_id    bigint references pdks.kullanici (id),
    add column inceleme_zamani timestamptz;
comment on column pdks.itiraz.inceleyen_id is 'İtirazı incelemeye alan İK kullanıcısı (T-35)';
comment on column pdks.itiraz.inceleme_zamani is 'İncelemeye alınma zamanı (T-35)';

create or replace function pdks.itiraz_incelemeye_al(p_itiraz_id bigint)
returns void
language plpgsql
security definer
set search_path = pdks, pg_temp
as $$
declare
    v_ben  bigint := pdks.yetki_gerekli('ik');
begin
    if (select calisan_id from pdks.itiraz where id = p_itiraz_id) = pdks.kullanici_calisani(v_ben) then
        raise exception 'Görevler ayrılığı: kendi gününüze ait itirazı inceleyemezsiniz.';
    end if;
    update pdks.itiraz
    set durum = 'inceleniyor', inceleyen_id = v_ben, inceleme_zamani = now()   -- T-35
    where id = p_itiraz_id and durum = 'acik';
    if not found then
        raise exception 'Açık itiraz bulunamadı.';
    end if;
end;
$$;

-- ---------------------------------------------------------------------
-- 3. T-35: arıza kararı izi
-- ---------------------------------------------------------------------
alter table pdks.ariza
    add column karar_veren_id bigint references pdks.kullanici (id),
    add column karar_zamani   timestamptz;
comment on column pdks.ariza.karar_veren_id is 'Arıza şüphesini onaylayan / reddeden İK kullanıcısı (T-35)';
comment on column pdks.ariza.karar_zamani is 'Arıza şüphesi kararının zamanı (T-35)';
comment on column pdks.ariza.giren_id is 'Arızayı elle giren kullanıcı; gece işinin açtığı şüphede boş (T-35)';

-- Eski kararlarda karar veren giren_id'ye yazılmıştı (gece işinin şüphesinde giren yoktur); zamanı bilinmez
update pdks.ariza
set karar_veren_id = giren_id, giren_id = null
where kaynak = 'otomatik_suphe' and durum <> 'suphe' and giren_id is not null;

create or replace function pdks.ariza_karar(p_ariza_id bigint, p_onay boolean)
returns void
language plpgsql
security definer
set search_path = pdks, pg_temp
as $$
declare
    v_ben  bigint := pdks.yetki_gerekli('ik');
begin
    update pdks.ariza
    set durum = case when p_onay then 'onaylandi' else 'reddedildi' end,
        karar_veren_id = v_ben, karar_zamani = now()                          -- T-35
    where id = p_ariza_id and durum = 'suphe';
    if not found then
        raise exception 'Şüphe durumunda arıza bulunamadı.';
    end if;
end;
$$;
