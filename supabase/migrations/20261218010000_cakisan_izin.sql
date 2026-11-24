-- =====================================================================
-- K5 · T-47: Çakışan izinler reddedilmiyordu
--
-- Aynı güne yıllık izin ve rapor girilebiliyor, gece işi günü ilk girilen izne göre
-- yazıyordu (rapor kayboluyordu). Aynı izin iki kez de girilebiliyordu.
--
-- Değişiklik:
--   * izin_gir: çalışanın iptal edilmemiş, tarihi kesişen izni varsa reddeder.
--     Yanlış izin önce iptal edilir (izin_iptal).
--   * saatlik_izin_gir: o gün tam gün izin varsa reddeder.
--   * İki fonksiyon da önce çalışan satırını kilitler: iki İK aynı anda girerse
--     ikincisi bekler ve birincinin iznini görür.
--
-- Ters yön (saatlik izinli güne tam gün izin) bilerek açıktır: vizite saatinden sonra
-- aynı gün için rapor alınabilir ve saatlik izin silinemez.
-- Daha önce girilmiş çakışan izinlere dokunulmaz.
-- Kalıcı test: supabase/tests/cakisan_izin_testi.sql
-- =====================================================================

create or replace function pdks.izin_gir(p_calisan_id bigint, p_tur text, p_baslangic date, p_bitis date,
                                         p_aciklama text default null)
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
    return v_id;
end;
$$;

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
