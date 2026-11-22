-- =====================================================================
-- T-31: dosya_yukle ekrandan (HTTP) hiç çalışmıyordu.
-- Supabase, HTTP isteklerini taşıyan `authenticator` rolüne `safeupdate`
-- eklentisini yükler; bu eklenti WHERE'siz UPDATE / DELETE'i reddeder
-- ("UPDATE requires a WHERE clause"). Fonksiyondaki geçici tablo güncellemesi
-- WHERE'sizdi; psql'den çalışıyor, ekrandan her geçerli dosyada düşüyordu.
--
-- Değişiklik yalnızca o satır: `where zaman_metni is not null` eklendi.
-- Bir üstteki denetim boş ya da biçimsiz zamanı zaten reddettiği için bu
-- koşul bütün satırları kapsar; davranış aynı kalır.
-- Fonksiyonun geri kalanı 20261128010000_dosya_yukle_duzeltmesi.sql'deki
-- son sürümle (pg_get_functiondef) birebir aynıdır. Yetkiler korunur.
-- =====================================================================

CREATE OR REPLACE FUNCTION pdks.dosya_yukle(p_kaynak text, p_dosya_adi text, p_veri_tarihi date, p_satirlar jsonb, p_dosya_ozeti text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pdks', 'pg_temp'
AS $function$
declare
    v_kullanici  bigint;
    v_aktarim    bigint;
    v_ozet       text;
    v_satir      integer;
    v_yeni       integer;
    v_yazilan    integer;
    v_hatali     integer;
    v_deger      text;
begin
    v_kullanici := pdks.yetki_gerekli('ik');

    -- Dosya bilgileri ---------------------------------------------------
    if p_kaynak is null or p_kaynak not in ('pdks', 'kapi', 'yemekhane', 'servis') then
        raise exception 'Dosya türü geçersiz: %. Beklenen: pdks, kapi, yemekhane, servis.', coalesce(p_kaynak, 'boş');
    end if;
    if nullif(btrim(p_dosya_adi), '') is null or length(p_dosya_adi) > 255 then
        raise exception 'Dosya adı boş ya da 255 karakterden uzun.';
    end if;
    if p_veri_tarihi is null then
        raise exception 'Dosyanın ait olduğu gün boş.';
    end if;
    if p_satirlar is null or jsonb_typeof(p_satirlar) <> 'array' or jsonb_array_length(p_satirlar) = 0 then
        raise exception 'Dosyada satır yok.';
    end if;
    v_satir := jsonb_array_length(p_satirlar);
    if v_satir > 200000 then
        raise exception 'Bir dosyada en fazla 200.000 satır olabilir (gelen: %).', v_satir;
    end if;
    if p_dosya_ozeti is not null and p_dosya_ozeti !~ '^[0-9a-f]{64}$' then
        raise exception 'Dosya özeti geçersiz (64 haneli SHA-256 bekleniyor).';
    end if;

    v_ozet := coalesce(p_dosya_ozeti, md5(p_satirlar::text));
    if exists (select 1 from pdks.aktarim where kaynak = p_kaynak and dosya_ozeti = v_ozet) then
        raise exception 'Bu dosya daha önce yüklenmiş.';
    end if;

    -- Satırları geçici tabloya al; satir_no yoksa dizideki sırası kullanılır
    if to_regclass('pg_temp.dosya_satiri') is not null then
        drop table pg_temp.dosya_satiri;
    end if;
    create temp table dosya_satiri on commit drop as
    select coalesce(case when s.e ->> 'satir_no' ~ '^\d{1,9}$' then (s.e ->> 'satir_no')::integer end,
                    s.sira::integer)                        as satir_no,
           jsonb_typeof(s.e) = 'object'                     as nesne,
           upper(btrim(s.e ->> 'okuyucu'))                  as okuyucu_kod,
           upper(btrim(s.e ->> 'kart_no'))                  as kart_no,
           btrim(s.e ->> 'zaman')                           as zaman_metni,
           nullif(lower(btrim(s.e ->> 'yon')), '')          as yon,
           null::smallint                                   as okuyucu_id,
           null::timestamptz                                as okutma_zamani
    from jsonb_array_elements(p_satirlar) with ordinality as s(e, sira);

    select min(satir_no) into v_hatali from dosya_satiri where not nesne;
    if v_hatali is not null then
        raise exception '%. satır okunamadı.', v_hatali;
    end if;

    -- Okuyucu: tanımlı ve bu kaynağa ait mi? (kod büyük/küçük harf duyarsız)
    update dosya_satiri d
    set okuyucu_id = r.id
    from pdks.okuyucu r
    where upper(r.kod) = d.okuyucu_kod and r.sistem = p_kaynak;

    select satir_no, okuyucu_kod into v_hatali, v_deger
    from dosya_satiri where okuyucu_id is null order by satir_no limit 1;
    if v_hatali is not null then
        raise exception 'Okuyucu tanımlı değil ya da bu kaynağa ait değil: % (%. satır)', coalesce(v_deger, '(boş)'), v_hatali;
    end if;

    select min(satir_no) into v_hatali from dosya_satiri
    where kart_no is null or kart_no !~ '^[A-Z0-9-]{1,32}$';
    if v_hatali is not null then
        raise exception '%. satırda kart numarası boş ya da geçersiz.', v_hatali;
    end if;

    select min(satir_no) into v_hatali from dosya_satiri
    where yon is not null and yon not in ('giris', 'cikis');
    if v_hatali is not null then
        raise exception '%. satırda yön "giris", "cikis" ya da boş olmalı.', v_hatali;
    end if;

    -- Zaman saat dilimiyle gelmeli: dilimsiz zaman sunucunun saat dilimine
    -- göre yorumlanır, Vercel / Supabase UTC'de olduğu için 3 saat kayar.
    select min(satir_no) into v_hatali from dosya_satiri
    where zaman_metni is null
       or zaman_metni !~ '^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}(:?\d{2})?)$';
    if v_hatali is not null then
        raise exception '%. satırda zaman geçersiz; saat dilimiyle gelmeli (ör. 2026-11-13T07:52:00+03:00).', v_hatali;
    end if;

    begin
        update dosya_satiri set okutma_zamani = zaman_metni::timestamptz
        where zaman_metni is not null;
    exception when invalid_datetime_format or datetime_field_overflow then
        raise exception 'Satırlardan birinde zaman okunamadı (ör. 31.02 gibi olmayan bir tarih).';
    end;

    -- Yazılacak okutmalar: dosya içi tekrarlar bir kez, daha önce gelmişler hiç
    if p_kaynak = 'pdks' then
        select count(*) into v_yeni
        from (select distinct okuyucu_id, kart_no, okutma_zamani from dosya_satiri) t
        where not exists (select 1 from pdks.ham_okutma h
                          where (h.okuyucu_id, h.kart_no, h.okutma_zamani) = (t.okuyucu_id, t.kart_no, t.okutma_zamani));
    else
        select count(*) into v_yeni
        from (select distinct okuyucu_id, kart_no, okutma_zamani from dosya_satiri) t
        where not exists (select 1 from pdks.kanit_kaydi k
                          where (k.okuyucu_id, k.kart_no, k.okutma_zamani) = (t.okuyucu_id, t.kart_no, t.okutma_zamani));
    end if;

    -- Yaz ------------------------------------------------------------------
    begin
        insert into pdks.aktarim (kaynak, dosya_adi, dosya_ozeti, veri_tarihi, satir_sayisi)
        values (p_kaynak, btrim(p_dosya_adi), v_ozet, p_veri_tarihi, v_yeni)
        returning id into v_aktarim;
    exception when unique_violation then
        raise exception 'Bu dosya daha önce yüklenmiş.';
    end;

    -- Aynı okutma dosyada birden fazla geçerse ilk satırdaki yön alınır
    if p_kaynak = 'pdks' then
        insert into pdks.ham_okutma (aktarim_id, okuyucu_id, kart_no, okutma_zamani, yon)
        select distinct on (okuyucu_id, kart_no, okutma_zamani)
               v_aktarim, okuyucu_id, kart_no, okutma_zamani, yon
        from dosya_satiri
        order by okuyucu_id, kart_no, okutma_zamani, satir_no
        on conflict (okuyucu_id, kart_no, okutma_zamani) do nothing;
    else
        insert into pdks.kanit_kaydi (aktarim_id, okuyucu_id, kaynak, kart_no, okutma_zamani, yon)
        select distinct on (okuyucu_id, kart_no, okutma_zamani)
               v_aktarim, okuyucu_id, p_kaynak, kart_no, okutma_zamani, yon
        from dosya_satiri
        order by okuyucu_id, kart_no, okutma_zamani, satir_no
        on conflict (okuyucu_id, kart_no, okutma_zamani) do nothing;
    end if;
    get diagnostics v_yazilan = row_count;

    -- Sayım ile yazılan farklıysa aynı anda başka bir aktarım olmuştur;
    -- aktarim satırı silinemediği için her şey geri alınır.
    if v_yazilan <> v_yeni then
        raise exception 'Aynı anda başka bir aktarım yapıldı; lütfen dosyayı yeniden yükleyin.';
    end if;

    drop table pg_temp.dosya_satiri;
    return v_aktarim;
end;
$function$;

-- CREATE OR REPLACE yetkileri ve açıklamayı korur; yine de açıkça yazılır.
revoke execute on function pdks.dosya_yukle(text, text, date, jsonb, text) from public, anon;
grant execute on function pdks.dosya_yukle(text, text, date, jsonb, text) to authenticated;
