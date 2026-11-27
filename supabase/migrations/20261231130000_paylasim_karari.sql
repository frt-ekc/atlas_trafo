-- =====================================================================
-- K11 · T-81: Kart paylaşımı şüphesinde karar verilemiyordu
--
-- Sorun: Ali ve Veli'nin kartları Ekim'de 5 farklı günde aynı okuyucuda 5 saniye arayla okutuldu.
-- Sistem "kart paylaşımı şüphesi" uyarısı verdi, ama (a) uyarı hangi gün, saat ve okuyucu olduğunu
-- söylemiyordu, (b) İK'nın elinde yalnızca "görüldü" vardı: "paylaşım var / yanlış alarm" kararını
-- gerekçesiyle kaydedemiyordu, (c) Veli gerçekten gelmediyse günleri "çalıştı" kalıyordu ve İK'nın
-- hangi günleri düzelteceğini bulması için okutmaları tek tek araması gerekiyordu.
--
-- Karar (Yusuf, B seçeneği: kararı uyarının üstünde tut, ayrı tablo yok):
--   1. Uyarı mesajı günleri, saati ve okuyucuyu yazar (en çok 10 gün; kalanı sayılır).
--      uyari.ayrinti (jsonb): diğer çalışan ve gün listesi. Karar verilene kadar yeni günler
--      eklenir (aynı uyarı güncellenir; gece işinin uyarı sayısına yeni uyarı olarak girmez).
--   2. pdks.kart_paylasim_karar(uyari, paylasim_var, gerekce): yalnızca İK; gerekçe ≥ 10 karakter;
--      şüpheli çiftteki iki çalışan da kendi şüphesine karar veremez; karar bir kez verilir,
--      değiştirilemez. Uyarı görüldü sayılır.
--   3. "Paylaşım var" kararı gün kaydına dokunmaz (çalışan aleyhine karar İK'nın elle düzeltmesiyle;
--      KVKK m.11): sonuç, düzeltilecek günleri listeler. Devamsızlık kendiliğinden yazılmaz.
-- Karar penceresi ekranda Gökalp'te (Uyarılar).
-- Kalıcı test: supabase/tests/paylasim_karari_testi.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Uyarıda ayrıntı ve karar alanları
-- ---------------------------------------------------------------------
alter table pdks.uyari
    add column ayrinti        jsonb,
    add column karar          text,
    add column karar_gerekce  text,
    add column karar_veren_id bigint references pdks.kullanici (id),
    add column karar_zamani   timestamptz;

alter table pdks.uyari
    add constraint uyari_karar_turu check (karar is null or (tur = 'kart_paylasim_suphesi' and karar in ('paylasim_var', 'yanlis_alarm'))),
    add constraint uyari_karar_tam check ((karar is null) = (karar_veren_id is null) and (karar is null) = (karar_zamani is null)
                                          and (karar is null or length(btrim(karar_gerekce)) >= 10));

comment on column pdks.uyari.ayrinti is
    'Uyarının ayrıntısı (kart paylaşımında: diger_calisan_id ve gunler [{tarih, saat, okuyucu}]; T-81).';
comment on column pdks.uyari.karar is
    'Kart paylaşımı şüphesinde İK kararı: paylasim_var / yanlis_alarm (T-81). Bir kez verilir.';

-- Görevler ayrılığı: kararı veren de uyarının çalışanı olamaz
drop trigger uyari_gorev_ayriligi on pdks.uyari;
create trigger uyari_gorev_ayriligi
before insert or update on pdks.uyari
for each row execute function pdks.kendi_kaydi_engelle('calisan', 'goren_id', 'karar_veren_id');

-- Karar değiştirilemez
create function pdks.uyari_karar_degismez()
returns trigger
language plpgsql
set search_path = pdks
as $$
begin
    if old.karar is not null
       and (new.karar, new.karar_gerekce, new.karar_veren_id, new.karar_zamani, new.ayrinti, new.mesaj)
           is distinct from (old.karar, old.karar_gerekce, old.karar_veren_id, old.karar_zamani, old.ayrinti, old.mesaj) then
        raise exception 'Kart paylaşımı kararı değiştirilemez.';
    end if;
    return new;
end;
$$;
revoke execute on function pdks.uyari_karar_degismez() from public, anon, authenticated;

create trigger uyari_karar_degismez
before update on pdks.uyari
for each row execute function pdks.uyari_karar_degismez();

-- ---------------------------------------------------------------------
-- 2. Paylaşım kontrolü (son hâli 20261216010000): günler, saat, okuyucu; karar bekleyen uyarı güncellenir
-- ---------------------------------------------------------------------
create or replace function pdks.kart_paylasim_kontrol(p_gun date)
returns integer
language plpgsql
set search_path = pdks
as $$
declare
    v_ay_bas timestamptz := (date_trunc('month', p_gun)::timestamp at time zone 'Europe/Istanbul');
    v_bit    timestamptz := ((p_gun + 1)::timestamp at time zone 'Europe/Istanbul');
    v_sn     integer := pdks.ayar_al('kart_paylasim_sn');
    v_gun    integer := pdks.ayar_al('kart_paylasim_gun');
    v_say    integer;
begin
    with okutma as (
        select h.okuyucu_id, h.kart_no, h.okutma_zamani,
               pdks.okutma_sahibi(h.kart_no, h.okutma_zamani) as calisan_id
        from pdks.ham_okutma h
        join pdks.okuyucu o on o.id = h.okuyucu_id and o.sistem = 'pdks'
        where h.okutma_zamani >= v_ay_bas and h.okutma_zamani < v_bit
          -- mükerrer işaretli okutmalar sayılmaz
          and not exists (select 1 from pdks.okutma_isareti i
                          where i.ham_okutma_id = h.id and i.isaret = 'mukerrer')
    ),
    sirali as (
        select okuyucu_id, okutma_zamani, calisan_id,
               lag(calisan_id)    over w as onceki_calisan,
               lag(okutma_zamani) over w as onceki_zaman
        from okutma
        window w as (partition by okuyucu_id order by okutma_zamani)
    ),
    ciftler as (
        select least(calisan_id, onceki_calisan)    as a,
               greatest(calisan_id, onceki_calisan) as b,
               (okutma_zamani at time zone 'Europe/Istanbul')::date as gun,
               onceki_zaman as zaman, okuyucu_id
        from sirali
        where calisan_id is not null and onceki_calisan is not null
          and calisan_id <> onceki_calisan
          and okutma_zamani - onceki_zaman <= make_interval(secs => v_sn)
    ),
    -- Çift ve gün başına ilk art arda okutma
    gunluk as (
        select distinct on (c.a, c.b, c.gun) c.a, c.b, c.gun, c.zaman, o.kod as okuyucu
        from ciftler c
        join pdks.okuyucu o on o.id = c.okuyucu_id
        order by c.a, c.b, c.gun, c.zaman
    ),
    supheli as (
        select a, b, count(*) as gun_sayisi,
               jsonb_agg(jsonb_build_object('tarih', gun,
                                            'saat', to_char(zaman at time zone 'Europe/Istanbul', 'HH24:MI:SS'),
                                            'okuyucu', okuyucu) order by gun) as gunler,
               string_agg(to_char(gun, 'DD.MM') || ' ' || to_char(zaman at time zone 'Europe/Istanbul', 'HH24:MI')
                          || ' (' || okuyucu || ')', ', ' order by gun) filter (where sira <= 10) as liste
        from (select g.*, row_number() over (partition by g.a, g.b order by g.gun) as sira from gunluk g) x
        group by a, b
        having count(*) >= v_gun
    ),
    yazilan as (
        insert into pdks.uyari (tur, calisan_id, mesaj, tekillik_anahtari, ayrinti)
        select 'kart_paylasim_suphesi', s.a,
               format('%s (%s %s) ve %s (%s %s) kartları %s döneminde %s farklı günde %s saniye içinde art arda okutuldu: %s%s.',
                      c1.sicil_no, c1.ad, c1.soyad, c2.sicil_no, c2.ad, c2.soyad,
                      to_char(p_gun, 'MM.YYYY'), s.gun_sayisi, v_sn, s.liste,
                      case when s.gun_sayisi > 10 then format(' ve %s gün daha', s.gun_sayisi - 10) else '' end),
               'ay:' || to_char(p_gun, 'YYYY-MM') || ':' || s.a || '-' || s.b,
               jsonb_build_object('diger_calisan_id', s.b, 'gunler', s.gunler)
        from supheli s
        join pdks.calisan c1 on c1.id = s.a
        join pdks.calisan c2 on c2.id = s.b
        on conflict (tur, tekillik_anahtari) where tekillik_anahtari is not null
        do update set mesaj = excluded.mesaj, ayrinti = excluded.ayrinti
           -- T-81: karar verilene kadar yeni günler eklenir; karar verilmiş uyarı değişmez
           where pdks.uyari.karar is null and pdks.uyari.ayrinti is distinct from excluded.ayrinti
        returning (xmax = 0) as yeni
    )
    select count(*) filter (where yeni) into v_say from yazilan;

    return v_say;
end;
$$;

-- ---------------------------------------------------------------------
-- 3. İK kararı
-- ---------------------------------------------------------------------
create function pdks.kart_paylasim_karar(p_uyari_id bigint, p_paylasim_var boolean, p_gerekce text)
returns jsonb
language plpgsql
security definer
set search_path = pdks
as $$
declare
    v_ben  bigint := pdks.yetki_gerekli('ik');
    v_u    pdks.uyari;
begin
    select * into v_u from pdks.uyari where id = p_uyari_id for update;
    if not found then
        raise exception 'Uyarı bulunamadı.';
    end if;
    if v_u.tur <> 'kart_paylasim_suphesi' then
        raise exception 'Bu karar yalnızca kart paylaşımı şüphesi uyarısına verilir.';
    end if;
    if v_u.karar is not null then
        raise exception 'Bu uyarıya zaten karar verilmiş.';
    end if;
    if p_paylasim_var is null then
        raise exception 'Karar (paylaşım var / yanlış alarm) seçilmeli.';
    end if;
    if p_gerekce is null or length(btrim(p_gerekce)) < 10 then
        raise exception 'Karar gerekçesi yazılmalı (en az 10 karakter).';
    end if;
    -- Şüpheli çiftteki diğer çalışan da kendi şüphesine karar veremez (uyarının çalışanı tetikleyicide)
    if (v_u.ayrinti ->> 'diger_calisan_id')::bigint = pdks.kullanici_calisani(v_ben) then
        raise exception 'Görevler ayrılığı: kimse kendi kaydında işlem yapamaz (uyari.ayrinti.diger_calisan_id).';
    end if;

    update pdks.uyari
    set karar = case when p_paylasim_var then 'paylasim_var' else 'yanlis_alarm' end,
        karar_gerekce = btrim(p_gerekce), karar_veren_id = v_ben, karar_zamani = now(),
        goruldu = true, goren_id = coalesce(goren_id, v_ben), gorulme_zamani = coalesce(gorulme_zamani, now())
    where id = p_uyari_id;

    return jsonb_build_object(
        'karar', case when p_paylasim_var then 'paylasim_var' else 'yanlis_alarm' end,
        'calisan_id', v_u.calisan_id,
        'diger_calisan_id', (v_u.ayrinti ->> 'diger_calisan_id')::bigint,
        'gunler', coalesce(v_u.ayrinti -> 'gunler', '[]'::jsonb),
        'mesaj', case when p_paylasim_var
                      then 'Karar kaydedildi. Gün kayıtları kendiliğinden değişmez; gelmediği anlaşılan günler çalışan kaydından elle düzeltilmelidir.'
                      else 'Karar kaydedildi (yanlış alarm).' end);
end;
$$;

revoke execute on function pdks.kart_paylasim_karar(bigint, boolean, text) from public, anon;
grant execute on function pdks.kart_paylasim_karar(bigint, boolean, text) to authenticated;
