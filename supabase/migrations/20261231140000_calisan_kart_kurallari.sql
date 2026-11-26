-- =====================================================================
-- K7 / K11 · T-68, T-75, T-86: Çalışma tarihleri dışında plan, izin ve kart; ham ya da yanıltıcı mesajlar
--
-- T-68: İşten ayrılmış çalışana 21 Aralık planı, izni ve yeni kart; henüz işe girmemiş çalışana
--       girişten önceki güne plan, izin ve geçici kart verilebiliyordu. Ayrılmış birine kart
--       verilmesi kapıdan geçiş riski.
-- T-75: İşe giriş 1900 ve 2099 kabul ediliyordu; "s11e1" sicili "S11E1" varken ikinci çalışan oldu;
--       kart hataları ham İngilizceydi ("duplicate key …"), kartın kimde olduğu söylenmiyordu.
-- T-86: Olmayan geçici kart / çalışan ham İngilizce hata veriyordu; aynı çalışana ikinci geçici kart
--       verilmek istenince mesaj başka bir kartı anlatıyordu; kart iptal nedeni boş geçilebiliyordu.
--
-- Kurallar (ekran tarafı Gökalp'te; mesajlar buradan gelir, ekran olduğu gibi gösterir):
--   - Plan, izin ve saatlik izin yalnızca işe giriş ile son çalışma günü arasında (pdks.calisan_tarih_denetle).
--   - Asıl kart: çalışan var, işten ayrılmamış (işe başlamadan önce hazırlanabilir); kart numarası
--     büyük harfe çevrilir, boşluk alınır (dosyadaki okutmayla eşleşsin); numara başkasındaysa ya da
--     iptal edilmişse kimde olduğu söylenir.
--   - Geçici kart: kart ve çalışan var; çalışan bugün çalışıyor (işe başlamış, ayrılmamış);
--     çalışanda açık geçici kart varsa hangisi olduğu söylenir.
--   - Kart iptal nedeni zorunlu ve listeden: kayıp, yenilendi, işten çıkış, diğer.
--   - İşe giriş tarihi bugün − 50 yıl ile bugün + 1 yıl arasında; sicil büyük/küçük harfe duyarsız tekil.
-- Kalıcı test: supabase/tests/calisan_kart_kurallari_testi.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Ortak denetim: tarih aralığı çalışma tarihleri içinde mi?
-- ---------------------------------------------------------------------
create function pdks.calisan_tarih_denetle(p_calisan_id bigint, p_bas date, p_bit date)
returns void
language plpgsql
stable
set search_path = pdks
as $$
declare
    v_c   pdks.calisan;
    v_gun date;
begin
    select * into v_c from pdks.calisan where id = p_calisan_id;
    if not found then
        raise exception 'Çalışan bulunamadı.';
    end if;
    v_gun := case when p_bas < v_c.ise_giris_tarihi then p_bas
                  when v_c.isten_cikis_tarihi is not null and p_bit > v_c.isten_cikis_tarihi
                       then greatest(p_bas, v_c.isten_cikis_tarihi + 1) end;
    if v_gun is not null then
        raise exception '%', format('Tarih çalışanın çalışma tarihleri dışında: %s (işe giriş %s%s).',
            to_char(v_gun, 'DD.MM.YYYY'), to_char(v_c.ise_giris_tarihi, 'DD.MM.YYYY'),
            coalesce(', son çalışma günü ' || to_char(v_c.isten_cikis_tarihi, 'DD.MM.YYYY'), ''));
    end if;
end;
$$;
revoke execute on function pdks.calisan_tarih_denetle(bigint, date, date) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 2. Vardiya planı (son hâli 20261205010000; T-68 denetimi)
-- ---------------------------------------------------------------------
create or replace function pdks.vardiya_plani_gir(p_calisan_id bigint, p_tarih date, p_vardiya_id smallint, p_aciklama text default null)
returns bigint
language plpgsql
security definer
set search_path = pdks
as $$
declare
    v_ben     bigint := pdks.yetki_gerekli('amir', 'ik');
    v_geri    boolean := p_tarih < pdks.bugun();
    v_id      bigint;
begin
    perform pdks.calisan_yetkisi(p_calisan_id);
    if pdks.donem_kilitli_mi(p_tarih) then
        raise exception '% günü kilitli bir döneme ait.', p_tarih;
    end if;
    perform pdks.calisan_tarih_denetle(p_calisan_id, p_tarih, p_tarih);   -- T-68
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
$$;

-- ---------------------------------------------------------------------
-- 3. İzin (son hâli 20261225010000; T-68 denetimi)
-- ---------------------------------------------------------------------
create or replace function pdks.izin_gir(p_calisan_id bigint, p_tur text, p_baslangic date, p_bitis date, p_aciklama text default null)
returns bigint
language plpgsql
security definer
set search_path = pdks
as $$
declare
    v_ben    bigint := pdks.yetki_gerekli('ik');
    v_izin   pdks.izin;
    v_id     bigint;
begin
    if p_baslangic is null or p_bitis is null or p_bitis < p_baslangic then
        raise exception 'İzin bitişi, başlangıcından önce olamaz.';
    end if;
    perform pdks.calisan_tarih_denetle(p_calisan_id, p_baslangic, p_bitis);   -- T-68

    perform 1 from pdks.calisan where id = p_calisan_id for no key update;

    select * into v_izin
    from pdks.izin i
    where i.calisan_id = p_calisan_id and i.iptal_zamani is null
      and i.baslangic <= p_bitis and i.bitis >= p_baslangic
    order by i.baslangic, i.id
    limit 1;
    if found then
        raise exception 'Çalışanın % – % tarihlerinde geçerli bir izni vardır. Yeni izin için önce bu izin iptal edilmelidir.',
            to_char(v_izin.baslangic, 'DD.MM.YYYY'), to_char(v_izin.bitis, 'DD.MM.YYYY');
    end if;

    insert into pdks.izin (calisan_id, tur, baslangic, bitis, aciklama, giren_id)
    values (p_calisan_id, p_tur, p_baslangic, p_bitis, p_aciklama, v_ben)
    returning id into v_id;
    perform pdks.izin_gunlere_uygula(v_id, v_ben);
    return v_id;
end;
$$;

-- ---------------------------------------------------------------------
-- 3b. Saatlik izin (son hâli 20261230010000; T-68 denetimi)
-- ---------------------------------------------------------------------
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

    perform pdks.calisan_tarih_denetle(p_calisan_id, p_tarih, p_tarih);   -- T-68
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
-- 4. Asıl kart (son hâli T-82; T-68, T-75)
-- ---------------------------------------------------------------------
create or replace function pdks.kart_tanimla(p_calisan_id bigint, p_kart_no text)
returns bigint
language plpgsql
security definer
set search_path = pdks
as $$
declare
    v_ben   bigint := pdks.yetki_gerekli('ik');
    v_c     pdks.calisan;
    v_no    text := upper(btrim(p_kart_no));
    v_var   record;
    v_id    bigint;
begin
    select * into v_c from pdks.calisan where id = p_calisan_id;
    if not found then
        raise exception 'Çalışan bulunamadı.';
    end if;
    if v_c.isten_cikis_tarihi is not null then
        raise exception 'Çalışan işten ayrılmış (son çalışma günü %); kart tanımlanamaz.',
            to_char(v_c.isten_cikis_tarihi, 'DD.MM.YYYY');
    end if;
    if v_no is null or v_no !~ '^[A-Z0-9-]{1,32}$' then
        raise exception 'Kart numarası boş ya da geçersiz (yalnızca harf, rakam ve "-", en çok 32 karakter).';
    end if;
    if exists (select 1 from pdks.kart where calisan_id = p_calisan_id and durum = 'aktif') then
        raise exception 'Çalışanın aktif kartı var; önce iptal edin.';
    end if;
    select k.durum, k.iptal_zamani, c.ad, c.soyad, c.sicil_no into v_var
    from pdks.kart k join pdks.calisan c on c.id = k.calisan_id
    where k.kart_no = v_no;
    if found then
        if v_var.durum = 'aktif' then
            raise exception '% numaralı kart % % (%) adına kayıtlı.', v_no, v_var.ad, v_var.soyad, v_var.sicil_no;
        end if;
        raise exception '% numaralı kart % % (%) adına kayıtlıydı ve iptal edildi (%); iptal edilen kartın numarası yeniden verilemez.',
            v_no, v_var.ad, v_var.soyad, v_var.sicil_no,
            to_char(v_var.iptal_zamani at time zone 'Europe/Istanbul', 'DD.MM.YYYY');
    end if;
    insert into pdks.kart (kart_no, calisan_id, tanimlayan_id) values (v_no, p_calisan_id, v_ben)
    returning id into v_id;
    return v_id;
end;
$$;

-- ---------------------------------------------------------------------
-- 5. Kart iptali (son hâli 20261119010000; T-86)
-- ---------------------------------------------------------------------
create or replace function pdks.kart_iptal_et(p_kart_id bigint, p_neden text)
returns void
language plpgsql
security definer
set search_path = pdks
as $$
declare
    v_ben  bigint := pdks.yetki_gerekli('ik');
begin
    if p_neden is null or p_neden not in ('kayip', 'yenilendi', 'isten_cikis', 'diger') then
        raise exception 'İptal nedeni seçilmeli: kayıp, yenilendi, işten çıkış ya da diğer.';
    end if;
    update pdks.kart set durum = 'iptal', iptal_nedeni = p_neden, iptal_zamani = now(), iptal_eden_id = v_ben
    where id = p_kart_id and durum = 'aktif';
    if not found then
        raise exception 'Aktif kart bulunamadı.';
    end if;
end;
$$;

-- ---------------------------------------------------------------------
-- 6. Geçici kart verme (son hâli 20261119010000; T-68, T-86)
-- ---------------------------------------------------------------------
create or replace function pdks.gecici_kart_ver(p_gecici_kart_id bigint, p_calisan_id bigint, p_aciklama text default null)
returns bigint
language plpgsql
security definer
set search_path = pdks
as $$
declare
    v_ben    bigint := pdks.yetki_gerekli('guvenlik', 'ik');
    v_c      pdks.calisan;
    v_acik   record;
    v_id     bigint;
begin
    if not exists (select 1 from pdks.gecici_kart where id = p_gecici_kart_id) then
        raise exception 'Geçici kart bulunamadı.';
    end if;
    select * into v_c from pdks.calisan where id = p_calisan_id;
    if not found then
        raise exception 'Çalışan bulunamadı.';
    end if;
    if v_c.isten_cikis_tarihi is not null and v_c.isten_cikis_tarihi < pdks.bugun() then
        raise exception 'Çalışan işten ayrılmış (son çalışma günü %); geçici kart verilemez.',
            to_char(v_c.isten_cikis_tarihi, 'DD.MM.YYYY');
    end if;
    if v_c.ise_giris_tarihi > pdks.bugun() then
        raise exception 'Çalışan henüz işe başlamadı (işe giriş %); geçici kart verilemez.',
            to_char(v_c.ise_giris_tarihi, 'DD.MM.YYYY');
    end if;
    select gk.kart_no, z.verilis_zamani into v_acik
    from pdks.gecici_kart_zimmet z join pdks.gecici_kart gk on gk.id = z.gecici_kart_id
    where z.calisan_id = p_calisan_id and z.iade_zamani is null
    order by z.verilis_zamani desc limit 1;
    if found then
        raise exception 'Bu çalışanda zaten açık bir geçici kart var (%, % verildi); önce iade alın.',
            v_acik.kart_no, to_char(v_acik.verilis_zamani at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI');
    end if;
    insert into pdks.gecici_kart_zimmet (gecici_kart_id, calisan_id, verilis_zamani, veren_id, aciklama)
    values (p_gecici_kart_id, p_calisan_id, clock_timestamp(), v_ben, p_aciklama)
    returning id into v_id;
    return v_id;
end;
$$;

-- ---------------------------------------------------------------------
-- 7. Çalışan ekleme (son hâli 20261130010000; T-75)
-- ---------------------------------------------------------------------
create unique index calisan_sicil_buyuk_harf_tekil on pdks.calisan (upper(sicil_no));

create or replace function pdks.calisan_ekle(p_sicil_no text, p_ad text, p_soyad text,
                                             p_departman_id smallint, p_ise_giris_tarihi date)
returns bigint
language plpgsql
security definer
set search_path = pdks
as $$
declare
    v_eski  pdks.calisan;
    v_id    bigint;
    v_alt   date := (pdks.bugun() - interval '50 years')::date;
    v_ust   date := (pdks.bugun() + interval '1 year')::date;
begin
    perform pdks.yetki_gerekli('ik');

    if coalesce(trim(p_sicil_no), '') = '' or coalesce(trim(p_ad), '') = '' or coalesce(trim(p_soyad), '') = '' then
        raise exception 'Sicil numarası, ad ve soyad boş olamaz.';
    end if;
    if p_ise_giris_tarihi is null then
        raise exception 'İşe giriş tarihi girilmeli.';
    end if;
    -- T-75: makul aralık
    if p_ise_giris_tarihi not between v_alt and v_ust then
        raise exception 'İşe giriş tarihi % ile % arasında olmalı.', to_char(v_alt, 'DD.MM.YYYY'), to_char(v_ust, 'DD.MM.YYYY');
    end if;
    if not exists (select 1 from pdks.departman where id = p_departman_id) then
        raise exception 'Departman bulunamadı.';
    end if;

    -- T-75: sicil büyük/küçük harfe duyarsız
    select * into v_eski from pdks.calisan where upper(sicil_no) = upper(trim(p_sicil_no));
    if found then
        if v_eski.isten_cikis_tarihi is not null or not v_eski.aktif then
            raise exception 'Bu sicil işten ayrılmış bir çalışana ait; yeniden işe giriş desteklenmiyor.';
        end if;
        raise exception 'Bu sicil numarası başka bir çalışanda kayıtlı: % % (%).', v_eski.ad, v_eski.soyad, v_eski.sicil_no;
    end if;

    insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
    values (trim(p_sicil_no), trim(p_ad), trim(p_soyad), p_departman_id, p_ise_giris_tarihi)
    returning id into v_id;
    return v_id;
end;
$$;
