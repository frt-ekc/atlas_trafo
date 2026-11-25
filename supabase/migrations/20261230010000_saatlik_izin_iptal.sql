-- =====================================================================
-- K5 · T-50: Yanlış girilen saatlik izin geri alınamıyordu
--
-- saatlik_izin tablosunda UPDATE ve DELETE tamamen yasaktı, iptal yolu yoktu. İK yanlış kişiye ya da
-- yanlış saate izin girerse kayıt sonsuza kadar geçerli kalıyor, gün her hesaplandığında o saatler
-- "izinli" sayılıyordu (ör. 2 saat erken çıkan çalışanın erken çıkışı 0 görünüyordu).
--
-- Karar (Yusuf, 25.11.2026; Fırat onayladı): tam gün izindeki (izin_iptal) yolun aynısı.
--   * Kayıt silinmez; iptal_zamani / iptal_eden_id / iptal_nedeni yazılır (iz kalır).
--   * saatlik_izin_iptal(p_id, p_neden): yalnızca İK; kendi iznini iptal edemez (görevler ayrılığı);
--     neden en az 5 karakter; kilitli aydaki izin iptal edilemez (girişte de kilitli ay reddediliyor).
--   * İptal edilen izin hesaba girmez (saatlik_izin_araligi), çakışma sayılmaz (saatlik_izin_gir),
--     amirin görünümünde çıkmaz (v_saatlik_izin_amir).
--   * Gün işlenmişse hemen yeniden hesaplanır (saatlik_izin_gir ile aynı).
--   * Tablo yine silinemez; UPDATE yalnızca bir kez "iptal" için (diğer alanlar ve geri alma yasak).
-- Kalıcı test: supabase/tests/saatlik_izin_iptal_testi.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. İptal sütunları
-- ---------------------------------------------------------------------
alter table pdks.saatlik_izin
    add column iptal_zamani  timestamptz,
    add column iptal_eden_id bigint references pdks.kullanici (id),
    add column iptal_nedeni  text,
    add constraint saatlik_izin_iptal_tam check (
        (iptal_zamani is null and iptal_eden_id is null and iptal_nedeni is null)
        or (iptal_zamani is not null and iptal_eden_id is not null and iptal_nedeni is not null));
comment on table pdks.saatlik_izin is
    'Gün içinde saat aralıklı izin (vizite dahil). Yalnızca İK girer; silinmez, değiştirilmez. Yanlış izin iptal edilir (T-50).';

-- ---------------------------------------------------------------------
-- 2. Değişmezlik: silme yine yasak; UPDATE yalnızca iptal
-- ---------------------------------------------------------------------
drop trigger saatlik_izin_degistirilemez on pdks.saatlik_izin;
create trigger saatlik_izin_degistirilemez before delete on pdks.saatlik_izin
    for each row execute function pdks.degistirilemez();

create function pdks.saatlik_izin_yalniz_iptal()
returns trigger
language plpgsql
set search_path = pdks
as $$
begin
    -- İzin alanları aynı kalmalı, iptal bir kez yazılır, geri alınmaz
    if old.iptal_zamani is not null or new.iptal_zamani is null
       or (new.id, new.calisan_id, new.tarih, new.baslangic, new.bitis, new.tur, new.aciklama, new.giren_id, new.giris_zamani)
          is distinct from
          (old.id, old.calisan_id, old.tarih, old.baslangic, old.bitis, old.tur, old.aciklama, old.giren_id, old.giris_zamani) then
        raise exception 'saatlik_izin tablosu değiştirilemez ve silinemez (yalnızca iptal edilir).'
            using errcode = 'insufficient_privilege';
    end if;
    return new;
end;
$$;
create trigger saatlik_izin_yalniz_iptal before update on pdks.saatlik_izin
    for each row execute function pdks.saatlik_izin_yalniz_iptal();
revoke execute on function pdks.saatlik_izin_yalniz_iptal() from public, anon, authenticated;

-- Görevler ayrılığı iptale de uygulanır (izin tablosundaki gibi)
drop trigger saatlik_izin_gorev_ayriligi on pdks.saatlik_izin;
create trigger saatlik_izin_gorev_ayriligi before insert or update on pdks.saatlik_izin
    for each row execute function pdks.kendi_kaydi_engelle('calisan', 'giren_id', 'iptal_eden_id');

-- ---------------------------------------------------------------------
-- 3. İptal edilen izin hesaba, çakışmaya ve amir görünümüne girmez
-- ---------------------------------------------------------------------
create or replace function pdks.saatlik_izin_araligi(p_calisan_id bigint, p_is_gunu date)
returns tstzmultirange
language sql
stable
set search_path = pdks
as $$
    select coalesce(range_agg(tstzrange(baslangic, bitis)), '{}'::tstzmultirange)
    from pdks.saatlik_izin
    where calisan_id = p_calisan_id and tarih = p_is_gunu
      and iptal_zamani is null;   -- T-50
$$;

create or replace view pdks.v_saatlik_izin_amir as
select id, calisan_id, tarih, baslangic, bitis, 'saatlik_izin'::text as tur
from pdks.saatlik_izin
where iptal_zamani is null   -- T-50
  and (pdks.tum_veriyi_gorur() or pdks.amirin_calisani_mi(calisan_id));

-- (20261218010000'daki fonksiyon; yalnızca çakışma denetimi değişti, "T-50" satırı)
create or replace function pdks.saatlik_izin_gir(p_calisan_id bigint, p_tarih date, p_baslangic timestamptz,
                                                 p_bitis timestamptz, p_tur text, p_aciklama text default null)
returns bigint
language plpgsql
security definer
set search_path = pdks
as $$
declare
    v_ben  bigint := pdks.yetki_gerekli('ik');
    v_id   bigint;
    v_gun  bigint;
begin
    if p_baslangic is null or p_bitis is null or p_bitis <= p_baslangic then
        raise exception 'İzin bitişi başlangıçtan sonra olmalı.';
    end if;

    perform 1 from pdks.calisan where id = p_calisan_id for no key update;

    if exists (select 1 from pdks.izin
               where calisan_id = p_calisan_id and iptal_zamani is null
                 and p_tarih between baslangic and bitis) then
        raise exception 'Çalışan % günü tam gün izinlidir; saatlik izin girilemez.', to_char(p_tarih, 'DD.MM.YYYY');
    end if;
    if exists (select 1 from pdks.saatlik_izin
               where calisan_id = p_calisan_id and tarih = p_tarih
                 and iptal_zamani is null   -- T-50: iptal edilen izin çakışma sayılmaz
                 and tstzrange(baslangic, bitis) && tstzrange(p_baslangic, p_bitis)) then
        raise exception 'Bu saat aralığında başka bir saatlik izin var.';
    end if;

    insert into pdks.saatlik_izin (calisan_id, tarih, baslangic, bitis, tur, aciklama, giren_id)
    values (p_calisan_id, p_tarih, p_baslangic, p_bitis, p_tur, nullif(trim(p_aciklama), ''), v_ben)
    returning id into v_id;

    select id into v_gun from pdks.gun_kaydi where calisan_id = p_calisan_id and is_gunu = p_tarih;
    if v_gun is not null then
        perform pdks.gun_hesabini_yenile(v_gun);
        perform pdks.gun_sonrasi_kontroller(v_gun);
    end if;
    return v_id;
end;
$$;

-- ---------------------------------------------------------------------
-- 4. İptal
-- ---------------------------------------------------------------------
create function pdks.saatlik_izin_iptal(p_id bigint, p_neden text)
returns void
language plpgsql
security definer
set search_path = pdks
as $$
declare
    v_ben   bigint := pdks.yetki_gerekli('ik');
    v_izin  pdks.saatlik_izin;
    v_gun   bigint;
begin
    select * into v_izin from pdks.saatlik_izin where id = p_id for update;
    if not found then
        raise exception 'Saatlik izin bulunamadı.';
    end if;
    if v_izin.iptal_zamani is not null then
        raise exception 'Bu saatlik izin zaten iptal edilmiş.';
    end if;
    if p_neden is null or length(trim(p_neden)) < 5 then
        raise exception 'İptal nedeni yazılmalı (en az 5 karakter).';
    end if;
    if pdks.donem_kilitli_mi(v_izin.tarih) then
        raise exception '% günü kilitli bir döneme ait; saatlik izin iptal edilemez.', to_char(v_izin.tarih, 'DD.MM.YYYY');
    end if;

    perform 1 from pdks.calisan where id = v_izin.calisan_id for no key update;

    -- Görevler ayrılığı (kendi izni) saatlik_izin_gorev_ayriligi trigger'ında denetlenir
    update pdks.saatlik_izin
    set iptal_zamani = now(), iptal_eden_id = v_ben, iptal_nedeni = trim(p_neden)
    where id = p_id;

    -- Gün işlenmişse izin olmadan yeniden hesaplanır
    select id into v_gun from pdks.gun_kaydi where calisan_id = v_izin.calisan_id and is_gunu = v_izin.tarih;
    if v_gun is not null then
        perform pdks.gun_hesabini_yenile(v_gun);
        perform pdks.gun_sonrasi_kontroller(v_gun);
    end if;
end;
$$;
revoke execute on function pdks.saatlik_izin_iptal(bigint, text) from public, anon;
grant execute on function pdks.saatlik_izin_iptal(bigint, text) to authenticated;
