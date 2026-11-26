-- =====================================================================
-- K8 · T-17, T-18 (+ T-21): Dosyanın günü ve satır tarihleri denetlenmiyordu
--
-- T-17: İK 10 Aralık'ın dosyasını yanlışlıkla "7 Aralık" diye yükledi. Satır tarihleri dosyanın
--       günüyle karşılaştırılmadığı için sistem 7 Aralık'ın verisi geldi sandı; gece işi o gün
--       kimsenin okutması olmadığını görüp 10 çalışan için amire "hiç gelmedi" sorusu açtı. Dosya
--       silinemediği için o gün bir daha "veri yok" sayılamıyordu. Kilitli aya da dosya yüklenebiliyordu.
-- T-18: 2030 tarihli tek satırlık dosya gece işinin 2029'a kadar çalıştırılmasını mümkün kıldı;
--       eskale o günü "bugün" sayıp süresi dolmamış 10 soruyu üst amire taşıdı, sahte "dosya gelmedi"
--       uyarıları yazıldı.
-- T-21: hata mesajı 1000 karakterlik okuyucu kodunu kısaltmadan geri yansıtıyordu.
--
-- Düzeltme (K8 kararı):
--   dosya_yukle: dosyanın günü bugünden ileri olamaz; kilitli aya dosya yüklenemez; her satırın
--   (İstanbul) tarihi dosyanın günü ya da ertesi gün olmalı (önceki dosyada gelmiş okutmanın tekrarı
--   hariç: yazılmadan atlanır), bugünden ileri olamaz. İlk aykırı satır numarası ve tarihiyle reddedilir. Mesajdaki okuyucu kodu 40 karakterde kısaltılır.
--   gece_isi_calistir: bugünden ileri bir gün hiçbir zaman işlenmez (eskale de bu günü kullanır).
-- Kalıcı test: supabase/tests/dosya_tarihi_testi.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Dosya yükleme (son hâli 20261216010000)
-- ---------------------------------------------------------------------
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
    v_calisan    bigint;
    v_kendi      integer;
    v_tarih      date;
begin
    v_kullanici := pdks.yetki_gerekli('ik');

    -- Dosya bilgileri ---------------------------------------------------
    if p_kaynak is null or p_kaynak not in ('pdks', 'kapi', 'yemekhane', 'servis') then
        raise exception 'Dosya türü geçersiz.';
    end if;
    if nullif(btrim(p_dosya_adi), '') is null or length(p_dosya_adi) > 255 then
        raise exception 'Dosya adı boş ya da 255 karakterden uzun.';
    end if;
    if p_veri_tarihi is null then
        raise exception 'Dosyanın ait olduğu gün boş.';
    end if;
    -- T-18: ileri tarihli dosya gece işinin takvimini ileri alıyordu
    if p_veri_tarihi > pdks.bugun() then
        raise exception 'Dosyanın günü (%) bugünden ileri olamaz.', to_char(p_veri_tarihi, 'DD.MM.YYYY');
    end if;
    -- T-17: kilitli ayın verisi değişmez
    if pdks.donem_kilitli_mi(p_veri_tarihi) then
        raise exception '% kilitli bir aya ait; bu güne dosya yüklenemez.', to_char(p_veri_tarihi, 'DD.MM.YYYY');
    end if;
    if p_satirlar is null or jsonb_typeof(p_satirlar) <> 'array' or jsonb_array_length(p_satirlar) = 0 then
        raise exception 'Dosyada satır yok.';
    end if;
    v_satir := jsonb_array_length(p_satirlar);
    if v_satir > 200000 then
        raise exception 'Bir dosyada en fazla 200.000 satır olabilir (gelen: %).', v_satir;
    end if;
    if p_dosya_ozeti is not null and p_dosya_ozeti !~ '^[0-9a-f]{64}$' then
        raise exception 'Dosya doğrulanamadı. Dosya yeniden yüklenmelidir.';
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
        -- T-21: girdi mesajda kısaltılır
        raise exception 'Okuyucu tanımlı değil ya da bu kaynağa ait değil: % (%. satır)',
            coalesce(case when length(v_deger) > 40 then left(v_deger, 40) || '…' else v_deger end, '(boş)'), v_hatali;
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
        raise exception '%. satırda zaman bilgisi geçersiz.', v_hatali;
    end if;

    begin
        update dosya_satiri set okutma_zamani = zaman_metni::timestamptz
        where zaman_metni is not null;
    exception when invalid_datetime_format or datetime_field_overflow then
        raise exception 'Satırlardan birinde zaman okunamadı (ör. 31.02 gibi olmayan bir tarih).';
    end;

    -- T-17: satırlar dosyanın gününe ya da ertesi güne düşmeli (gece vardiyasının çıkışı ertesi sabah);
    -- yanlış günün dosyası o günü "hiç kayıt yok" yapıyordu. T-18: ileri tarihli satır da kabul edilmez.
    -- Önceki dosyada zaten gelmiş okutmanın tekrarı (çakışan dışa aktarım) yazılmadan atlandığı için
    -- günü yanıltmaz; o satır bu kurala takılmaz.
    select d.satir_no, (d.okutma_zamani at time zone 'Europe/Istanbul')::date into v_hatali, v_tarih
    from dosya_satiri d
    where (d.okutma_zamani at time zone 'Europe/Istanbul')::date not in (p_veri_tarihi, p_veri_tarihi + 1)
      and not exists (select 1 from pdks.ham_okutma h
                      where p_kaynak = 'pdks'
                        and (h.okuyucu_id, h.kart_no, h.okutma_zamani) = (d.okuyucu_id, d.kart_no, d.okutma_zamani))
      and not exists (select 1 from pdks.kanit_kaydi k
                      where p_kaynak <> 'pdks'
                        and (k.okuyucu_id, k.kart_no, k.okutma_zamani) = (d.okuyucu_id, d.kart_no, d.okutma_zamani))
    order by d.satir_no limit 1;
    if v_hatali is not null then
        raise exception '%. satırın tarihi (%) dosyanın günü (%) ya da ertesi gün değil. Doğru dosyayı ve günü seçin.',
            v_hatali, to_char(v_tarih, 'DD.MM.YYYY'), to_char(p_veri_tarihi, 'DD.MM.YYYY');
    end if;
    select satir_no, (okutma_zamani at time zone 'Europe/Istanbul')::date into v_hatali, v_tarih
    from dosya_satiri
    where (okutma_zamani at time zone 'Europe/Istanbul')::date > pdks.bugun()
    order by satir_no limit 1;
    if v_hatali is not null then
        raise exception '%. satırın tarihi (%) bugünden ileri.', v_hatali, to_char(v_tarih, 'DD.MM.YYYY');
    end if;

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
        insert into pdks.aktarim (kaynak, dosya_adi, dosya_ozeti, veri_tarihi, satir_sayisi, yukleyen_id)
        values (p_kaynak, btrim(p_dosya_adi), v_ozet, p_veri_tarihi, v_yeni, v_kullanici)
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

    -- T-13: yazılan okutmalar arasında yükleyenin kendi kartı varsa (asıl kartı ya da okutma anında
    -- zimmetli geçici kartı) dosya reddedilmez; dosya başına bir uyarı yazılır. Önce kendi kart
    -- numaralarıyla süzülür ki büyük dosyada okutma_sahibi her satır için çalışmasın.
    v_calisan := pdks.kullanici_calisani(v_kullanici);
    select count(*) into v_kendi
    from (select kart_no, okutma_zamani from pdks.ham_okutma where aktarim_id = v_aktarim
          union all
          select kart_no, okutma_zamani from pdks.kanit_kaydi where aktarim_id = v_aktarim) o
    where o.kart_no in (select k.kart_no from pdks.kart k where k.calisan_id = v_calisan
                        union
                        select g.kart_no from pdks.gecici_kart g
                        join pdks.gecici_kart_zimmet z on z.gecici_kart_id = g.id
                        where z.calisan_id = v_calisan)
      and pdks.okutma_sahibi(o.kart_no, o.okutma_zamani) = v_calisan;
    if v_kendi > 0 then
        perform pdks.uyari_yaz('kendi_okutmasi_yuklendi', 'aktarim:' || v_aktarim,
            format('%s (%s), kendi kartına ait %s okutma içeren %s dosyasını yükledi (%s).',
                   (select ad || ' ' || soyad from pdks.calisan where id = v_calisan),
                   (select sicil_no from pdks.calisan where id = v_calisan),
                   v_kendi, btrim(p_dosya_adi), to_char(p_veri_tarihi, 'DD.MM.YYYY')),
            v_calisan);
    end if;

    drop table pg_temp.dosya_satiri;
    return v_aktarim;
end;
$function$;

-- ---------------------------------------------------------------------
-- 2. Gece işi (son hâli 20261224010000; yalnızca gün sınırı değişti)
-- ---------------------------------------------------------------------
create or replace function pdks.gece_isi_calistir(p_gun date)
returns bigint
language plpgsql
security definer
set search_path = pdks
as $$
declare
    v_id    bigint;
    v_ozet  jsonb;
begin
    -- Dün her zaman işlenebilir; bugün ancak PDKS dosyası yüklendiyse (ör. demo verisi).
    -- T-18: bugünden ileri bir gün hiçbir zaman (ileri tarihli dosya takvimi ileri alıyordu; eskale
    -- o günü "bugün" sayıp soruları süresinden önce taşıyordu). Eksik veriyle yarım iş yapılmasını
    -- pdks_verisi_tam_mi() önler.
    if p_gun is null or p_gun > pdks.bugun()
       or p_gun > greatest(pdks.bugun() - 1,
                           (select max(veri_tarihi) from pdks.aktarim where kaynak = 'pdks')) then
        raise exception 'Bu gün için henüz veri yok: %', p_gun;
    end if;

    -- Aynı anda iki gece işi çalışmasın
    perform pg_advisory_xact_lock(hashtext('pdks.gece_isi'));

    insert into pdks.gece_isi (islenen_gun) values (p_gun) returning id into v_id;

    begin
        v_ozet := jsonb_build_object('isaret',    pdks.gece_isi_isaretle(p_gun, v_id));
        v_ozet := v_ozet || jsonb_build_object('gun_kaydi', pdks.gece_isi_gun_kayitlari(p_gun, v_id));
        v_ozet := v_ozet || jsonb_build_object('plansiz',   pdks.gece_isi_plansiz(p_gun, v_id));
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
$$;
