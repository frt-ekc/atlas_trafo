-- =====================================================================
-- Ekran ve uyarı metinleri: kurumsal, kısa ve tutarlı (docs/metin_envanteri.md)
--
--   * ayar.ad, ayar.kategori, ayar.sira : ekranda teknik anahtar yerine ad, kategori başlığı altında;
--     aciklama resmi metinle güncellenir. Değerler ve aralıklar değişmez.
--   * Uyarı, soru ve düzeltme gerekçesi metinleri: konuşma dili, iç kod ve ham dakika kalktı
--     (pdks.sure_metni: 690 → "11 sa 30 dk"; pdks.soru_cevabi_adi: cevap kodu → Türkçe ad).
--   * Sık görülen ve teknik ad içeren hata mesajları.
--   Fonksiyonlarda yalnızca metin değişir; kural, hesap ve yetkiler son sürümle
--   (pg_get_functiondef) aynıdır. Eski kayıtların metni değişmez.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Ayar adı, kategorisi ve açıklaması
-- ---------------------------------------------------------------------
alter table pdks.ayar
    add column ad text,
    add column kategori text,
    add column sira smallint;

-- Yalnızca metin değişir; "son değişiklik" zamanı oynamasın
alter table pdks.ayar disable trigger ayar_iz;
update pdks.ayar a
set kategori = v.kategori, sira = v.sira, ad = v.ad, aciklama = v.aciklama
from (values
    ('gec_kalma_tolerans_dk', 'Puantaj', 1, 'Geç kalma toleransı',
     'Bu süreye kadar olan geç girişler geç kalma olarak değerlendirilmez.'),
    ('erken_cikis_tolerans_dk', 'Puantaj', 2, 'Erken çıkış toleransı',
     'Bu süreye kadar olan erken çıkışlar erken çıkış olarak değerlendirilmez.'),
    ('tolerans_yuvarlama_dk', 'Puantaj', 3, 'Yuvarlama dilimi',
     'Tolerans aşıldığında geç kalma ve erken çıkış süreleri bu dilime yukarı yuvarlanır. Sıfır değerinde yuvarlama yapılmaz.'),
    ('yurume_payi_dk', 'Puantaj', 4, 'Yürüme süresi',
     'Kapı veya servis kaydına göre belirlenen giriş saatine eklenir.'),
    ('esnek_gunluk_hedef_dk', 'Puantaj', 5, 'Esnek çalışma günlük hedefi',
     'Esnek çalışan personelin planlı her günü için beklenen net çalışma süresi. Aylık hedef bu süre üzerinden hesaplanır.'),
    ('cumartesi_hafta_sonu', 'Puantaj', 6, 'Cumartesi hafta tatili',
     'Açık olduğunda Cumartesi çalışması hafta tatili çalışması (FM100) olarak hesaplanır. Kapalı olduğunda Cumartesi normal iş günüdür.'),
    ('oto_vardiya_esik_dk', 'Puantaj', 7, 'Vardiya eşleştirme süresi',
     'Okutmaların başka bir vardiyanın başlangıç ve bitişine bu süre içinde yakın olması durumunda vardiya önerisi oluşturulur.'),
    ('gunluk_azami_calisma_dk', 'Fazla mesai', 8, 'Günlük çalışma sınırı',
     'Vardiya ve fazla mesai toplamı için günlük yasal üst sınır.'),
    ('fm_yillik_sinir_dk', 'Fazla mesai', 9, 'Yıllık fazla mesai sınırı',
     'Bir takvim yılında onaylanabilecek en fazla fazla mesai süresi.'),
    ('fm_yaklasma_uyari_yuzde', 'Fazla mesai', 10, 'Yıllık sınır uyarı oranı',
     'Yıllık fazla mesai sınırının bu oranına ulaşıldığında İK''ya uyarı gönderilir.'),
    ('fm_plansiz_esik_dk', 'Fazla mesai', 11, 'Plansız fazla mesai toleransı',
     'Vardiya sonrasında bu süreye kadar olan çalışmalar için uyarı oluşturulmaz.'),
    ('gece_calisma_sinir_dk', 'Fazla mesai', 12, 'Gece çalışması sınırı',
     '20.00–06.00 saatleri arasındaki çalışma bu süreyi aştığında İK''ya uyarı gönderilir.'),
    ('mola_kisa_dk', 'Mola', 13, 'Kısa mola süresi',
     'Kısa süreli çalışmalarda çalışma süresinden düşülen ara dinlenmesi.'),
    ('mola_orta_dk', 'Mola', 14, 'Orta mola süresi',
     'Orta süreli çalışmalarda çalışma süresinden düşülen ara dinlenmesi.'),
    ('mola_uzun_dk', 'Mola', 15, 'Uzun mola süresi',
     'Uzun süreli çalışmalarda çalışma süresinden düşülen ara dinlenmesi.'),
    ('mola_kisa_sinir_dk', 'Mola', 16, 'Kısa mola çalışma sınırı',
     'Bu süreye kadar olan çalışmalarda kısa mola süresi uygulanır.'),
    ('mola_orta_sinir_dk', 'Mola', 17, 'Orta mola çalışma sınırı',
     'Bu süreye kadar olan çalışmalarda orta mola süresi, aşan çalışmalarda uzun mola süresi uygulanır.'),
    ('mukerrer_esik_dk', 'Okuyucu ve kart', 18, 'Mükerrer okutma süresi',
     'Aynı kartın bu süre içinde aynı yöndeki okutmaları tek okutma olarak değerlendirilir.'),
    ('ariza_suphe_dk', 'Okuyucu ve kart', 19, 'Okuyucu arıza süresi',
     'Diğer okuyucular çalışırken bu süre boyunca okutma almayan okuyucu için arıza şüphesi oluşturulur.'),
    ('ariza_suphe_kisi', 'Okuyucu ve kart', 20, 'Okuyucu arıza kişi sayısı',
     'Kapı kaydı bulunan ancak PDKS okutması bulunmayan çalışan sayısı bu değere ulaştığında arıza şüphesi oluşturulur.'),
    ('gecici_kart_iade_saat', 'Okuyucu ve kart', 21, 'Geçici kart iade süresi',
     'Bu süre içinde iade edilmeyen geçici kartlar için İK''ya uyarı gönderilir.'),
    ('sik_kart_unutma_esigi', 'Okuyucu ve kart', 22, 'Geçici kart kullanım sınırı',
     'Bir ay içinde bu sayıda geçici kart kullanan çalışan için İK''ya bilgi gönderilir.'),
    ('kart_paylasim_sn', 'Okuyucu ve kart', 23, 'Kart paylaşımı süre aralığı',
     'Aynı okuyucuda bu süre içinde art arda okutulan iki farklı kart, kart paylaşımı incelemesine dahil edilir.'),
    ('kart_paylasim_gun', 'Okuyucu ve kart', 24, 'Kart paylaşımı gün sayısı',
     'Aynı iki kartın bir ay içinde bu sayıda farklı günde art arda okutulması durumunda İK''ya uyarı gönderilir.'),
    ('isg_uyari_gun', 'İSG', 25, 'Belge bitiş uyarı süresi',
     'İSG eğitimi veya sağlık muayenesinin geçerlilik bitişinden bu süre önce uyarı oluşturulur.'),
    ('soru_eskalasyon_gun', 'Soru akışı', 26, 'Soru cevap süresi',
     'Bu süre içinde cevaplanmayan sorular üst amire, ardından İK''ya gönderilir.')
) v(anahtar, kategori, sira, ad, aciklama)
where a.anahtar = v.anahtar;
alter table pdks.ayar enable trigger ayar_iz;

do $$
declare
    v_liste text;
begin
    select string_agg(anahtar, ', ') into v_liste from pdks.ayar where ad is null or kategori is null or sira is null;
    if v_liste is not null then
        raise exception 'Adı ya da kategorisi tanımlanmamış ayar var: %', v_liste;
    end if;
end $$;

alter table pdks.ayar
    alter column ad set not null,
    alter column kategori set not null,
    alter column sira set not null;

comment on column pdks.ayar.ad is 'Ekranda görünen ad.';
comment on column pdks.ayar.kategori is 'Ayarlar ekranındaki grup başlığı.';
comment on column pdks.ayar.sira is 'Ayarlar ekranındaki sıra; kategoriler de bu sıraya göre dizilir.';

-- Vardiya adı (terim: esnek çalışma)
update pdks.vardiya_tanim set ad = 'Esnek çalışma' where kod = 'ESNEK' and ad = 'Esnek mesai';

-- ---------------------------------------------------------------------
-- 2. Metin yardımcıları
-- ---------------------------------------------------------------------
create function pdks.sure_metni(p_dk integer)
returns text
language sql
immutable
as $$
    select case when p_dk is null then null
                when abs(p_dk) < 60 then p_dk || ' dk'
                when p_dk % 60 = 0 then p_dk / 60 || ' sa'
                else p_dk / 60 || ' sa ' || abs(p_dk % 60) || ' dk' end;
$$;
comment on function pdks.sure_metni(integer) is 'Dakikayı metne çevirir: 690 → "11 sa 30 dk".';

create function pdks.ayar_degeri_metni(p_deger integer, p_birim text)
returns text
language sql
immutable
as $$
    select case p_birim when 'evet/hayır' then case p_deger when 1 then 'Açık' else 'Kapalı' end
                        when 'dakika' then p_deger || ' dk'
                        when 'yüzde' then '%' || p_deger
                        else p_deger || ' ' || p_birim end;
$$;

create function pdks.soru_cevabi_adi(p_cevap text)
returns text
language sql
immutable
as $$
    select case p_cevap when 'geldi_saat_dogru' then 'Geldi, önerilen saat doğru'
                        when 'geldi_saat_farkli' then 'Geldi, saat farklı'
                        when 'kart_unuttu' then 'Kartını unuttu'
                        when 'gelmedi' then 'Gelmedi'
                        when 'bilmiyorum' then 'Bilmiyorum'
                        else p_cevap end;
$$;
comment on function pdks.soru_cevabi_adi(text) is 'Soru cevabı kodunun ekrandaki adı (lib/etiketler.ts SORU_CEVABI ile aynı).';

revoke execute on function pdks.sure_metni(integer), pdks.ayar_degeri_metni(integer, text), pdks.soru_cevabi_adi(text) from public, anon;
grant execute on function pdks.sure_metni(integer), pdks.ayar_degeri_metni(integer, text), pdks.soru_cevabi_adi(text) to authenticated;

-- ---------------------------------------------------------------------
-- 3. Metin üreten fonksiyonlar (yalnızca metin değişir)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pdks.ayar_guncelle(p_anahtar text, p_deger text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pdks'
AS $function$
declare
    v_ben    bigint := pdks.yetki_gerekli('admin');
    v_metin  text := btrim(p_deger);
    v_yeni   integer;
    v_ayar   pdks.ayar;
    v_mola   jsonb;
    v_kisi   text;
begin
    -- Mola ayarları birbirine bağlıdır: iki kişi aynı anda değiştirip sırayı bozmasın
    perform 1 from pdks.ayar where anahtar = p_anahtar or (p_anahtar like 'mola\_%' and anahtar like 'mola\_%')
    order by anahtar for update;

    select * into v_ayar from pdks.ayar where anahtar = p_anahtar;
    if not found then
        raise exception 'Ayar bulunamadı.';
    end if;

    if v_metin is null or v_metin !~ '^-?[0-9]+$' then
        raise exception 'Tam sayı girilmelidir.';
    end if;
    -- numeric: integer'a sığmayan sayı da aynı Türkçe mesajı alsın
    if v_metin::numeric not between v_ayar.en_az and v_ayar.en_cok then
        raise exception 'Değer % ile % arasında olmalıdır.', v_ayar.en_az, v_ayar.en_cok;
    end if;
    v_yeni := v_metin::integer;

    if v_yeni = v_ayar.deger then
        return;   -- değişiklik yok: geçmiş ve uyarı yazılmaz
    end if;

    -- Mola sıralaması: kısa < orta < uzun süre, kısa < orta sınır
    if p_anahtar like 'mola\_%' then
        select jsonb_object_agg(anahtar, case when anahtar = p_anahtar then v_yeni else deger end)
          into v_mola
        from pdks.ayar where anahtar like 'mola\_%';
        if not ((v_mola->>'mola_kisa_dk')::int < (v_mola->>'mola_orta_dk')::int
                and (v_mola->>'mola_orta_dk')::int < (v_mola->>'mola_uzun_dk')::int) then
            raise exception 'Mola süreleri kısa, orta ve uzun sırasıyla artmalıdır.';
        end if;
        if not (v_mola->>'mola_kisa_sinir_dk')::int < (v_mola->>'mola_orta_sinir_dk')::int then
            raise exception 'Kısa mola çalışma sınırı, orta mola çalışma sınırından küçük olmalıdır.';
        end if;
    end if;

    update pdks.ayar set deger = v_yeni, guncelleyen_id = v_ben where anahtar = p_anahtar;

    if v_ayar.puantaji_etkiler then
        select ad_soyad into v_kisi from pdks.kullanici where id = v_ben;
        perform pdks.uyari_yaz('puantaj_ayari_degisti',
            'ayar_gecmisi:' || (select max(id) from pdks.ayar_gecmisi where anahtar = p_anahtar),
            format('"%s" ayarı %s değerinden %s değerine güncellendi (%s). Önceden işlenmiş günler yeniden hesaplanmaz.',
                   v_ayar.ad, pdks.ayar_degeri_metni(v_ayar.deger, v_ayar.birim), pdks.ayar_degeri_metni(v_yeni, v_ayar.birim), v_kisi));
    end if;
end;
$function$;

CREATE OR REPLACE FUNCTION pdks.bolge_kontrol(p_gun date)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'pdks'
AS $function$
declare
    v_bas  timestamptz := (p_gun::timestamp at time zone 'Europe/Istanbul');
    v_bit  timestamptz := ((p_gun + 1)::timestamp at time zone 'Europe/Istanbul');
    v_say  integer := 0;
    r      record;
begin
    for r in
        with okutmalar as (
            select 'ham:' || h.id as anahtar, h.okuyucu_id, h.kart_no, h.okutma_zamani
            from pdks.ham_okutma h
            where h.okutma_zamani >= v_bas and h.okutma_zamani < v_bit
            union all
            select 'kanit:' || k.id, k.okuyucu_id, k.kart_no, k.okutma_zamani
            from pdks.kanit_kaydi k
            where k.okutma_zamani >= v_bas and k.okutma_zamani < v_bit
        )
        select o.anahtar, o.okuyucu_id, o.okutma_zamani, c.id as calisan_id, c.sicil_no, b.ad as bolge
        from okutmalar o
        join pdks.okuyucu ok on ok.id = o.okuyucu_id and ok.bolge_id is not null
        join pdks.bolge b on b.id = ok.bolge_id and b.aktif
        join pdks.calisan c on c.id = pdks.okutma_sahibi(o.kart_no, o.okutma_zamani)
        where not exists (select 1 from pdks.bolge_yetkisi y
                          where y.bolge_id = ok.bolge_id and y.departman_id = c.departman_id)
    loop
        v_say := v_say + pdks.uyari_yaz('yetkisiz_bolge_okutmasi', 'bolge:' || r.anahtar,
            format('%s bölgesine yetkisiz giriş kaydedildi (%s).',
                   r.bolge, to_char(r.okutma_zamani at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI')),
            r.calisan_id, r.okuyucu_id);
    end loop;
    return v_say;
end;
$function$;

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
        raise exception '%. satırda zaman bilgisi geçersiz.', v_hatali;
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

CREATE OR REPLACE FUNCTION pdks.fazla_mesai_inceleme_karar(p_inceleme_id bigint, p_onay boolean, p_aciklama text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pdks'
AS $function$
declare
    v_ben     bigint := pdks.yetki_gerekli('ik');
    v_kayit   pdks.fazla_mesai_inceleme;
    g         pdks.gun_kaydi;
    v_once    record;
    v_sonra   record;
    v_kilitli boolean;
    v_toplam  integer;
begin
    select * into v_kayit from pdks.fazla_mesai_inceleme where id = p_inceleme_id for update;
    if not found then
        raise exception 'İnceleme kaydı bulunamadı.';
    end if;
    if v_kayit.durum <> 'inceleme_bekliyor' then
        raise exception 'Bu kayıt zaten karara bağlanmış.';
    end if;
    if p_onay is null then
        raise exception 'Karar (onay / ret) belirtilmeli.';
    end if;

    if not p_onay then
        if p_aciklama is null or length(trim(p_aciklama)) < 5 then
            raise exception 'Ret gerekçesi yazılmalı (en az 5 karakter).';
        end if;
        update pdks.fazla_mesai_inceleme
        set durum = 'reddedildi', karar_veren_id = v_ben, karar_aciklama = trim(p_aciklama)
        where id = p_inceleme_id;
        return;
    end if;

    select * into g from pdks.gun_kaydi where id = v_kayit.gun_kaydi_id;
    select * into v_once from pdks.gun_hesabi(g.calisan_id, g.is_gunu, g.planli_baslangic, g.planli_bitis,
                                              g.giris_zamani, g.cikis_zamani);
    update pdks.fazla_mesai_inceleme
    set durum = 'onaylandi', karar_veren_id = v_ben, karar_aciklama = nullif(trim(p_aciklama), '')
    where id = p_inceleme_id;
    select * into v_sonra from pdks.gun_hesabi(g.calisan_id, g.is_gunu, g.planli_baslangic, g.planli_bitis,
                                               g.giris_zamani, g.cikis_zamani);

    v_kilitli := pdks.donem_kilitli_mi(g.is_gunu);
    update pdks.fazla_mesai_inceleme
    set fm50_etki_dk    = v_sonra.fm50_dk - v_once.fm50_dk,
        fm100_etki_dk   = v_sonra.fm100_dk - v_once.fm100_dk,
        calisma_etki_dk = v_sonra.calisma_dk - v_once.calisma_dk,
        gece_etki_dk    = v_sonra.gece_calisma_dk - v_once.gece_calisma_dk,
        fark_satiri     = v_kilitli,
        hedef_donem_id  = pdks.hedef_donem(g.is_gunu)
    where id = p_inceleme_id;

    if not v_kilitli then
        perform pdks.gun_hesabini_yenile(g.id);
    end if;

    -- Yıllık sınır: onaylı planlar + onaylanan havuz kayıtları
    select coalesce((select sum(planli_dk) from pdks.fazla_mesai_plani
                     where calisan_id = g.calisan_id and durum = 'onaylandi'
                       and extract(year from is_gunu) = extract(year from g.is_gunu)), 0)
         + coalesce((select sum(dakika) from pdks.fazla_mesai_inceleme
                     where calisan_id = g.calisan_id and durum = 'onaylandi'
                       and extract(year from is_gunu) = extract(year from g.is_gunu)), 0)
      into v_toplam;
    if v_toplam > pdks.ayar_al('fm_yillik_sinir_dk') then
        perform pdks.uyari_yaz('fm_yillik_sinir_asildi', 'havuz:' || p_inceleme_id,
            format('%s yılı onaylı fazla mesai süresi %s (sınır %s).',
                   extract(year from g.is_gunu), pdks.sure_metni(v_toplam::integer), pdks.sure_metni(pdks.ayar_al('fm_yillik_sinir_dk'))),
            g.calisan_id);
    end if;
end;
$function$;

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
        karar_aciklama = format('Yazılı onay geri alındı (bildirim %s)', to_char(new.geri_alma_bildirim_tarihi, 'DD.MM.YYYY'))
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
            format('Fazla mesai onayı geri alındı ve %s itibarıyla geçersizdir. %s plan iptal edildi.%s',
                   to_char(new.gecerlilik_bitisi, 'DD.MM.YYYY'), v_say,
                   case when v_kalan > 0 then
                       format(' %s plan geçmiş güne veya kilitli aya ait olduğu için iptal edilmedi; İK incelemesi bekleniyor.', v_kalan)
                   else '' end));
    return null;
end;
$function$;

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
                        format('Yıllık onaylı fazla mesai süresi %s oldu (sınır %s).',
                               pdks.sure_metni(v_toplam::integer), pdks.sure_metni(pdks.ayar_al('fm_yillik_sinir_dk'))));
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

CREATE OR REPLACE FUNCTION pdks.gece_isi_ariza_suphesi(p_gun date)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'pdks'
AS $function$
declare
    v_esik   integer  := pdks.ayar_al('ariza_suphe_kisi');
    v_pay    interval := make_interval(mins => pdks.ayar_al('ariza_suphe_dk'));
    v_ariza  bigint;
    v_say    integer := 0;
    r        record;
begin
    for r in
        with eksik as (
            select g.id, g.calisan_id,
                   pdks.calisan_pdks_okuyucusu(g.calisan_id, p_gun) as okuyucu_id,
                   case when g.giris_zamani is null then (pdks.gun_kaniti(g.id, 'giris')).p_zaman end as kanit_giris,
                   case when g.cikis_zamani is null then
                       (pdks.gun_kaniti(g.id, 'cikis', coalesce(g.giris_zamani, g.planli_baslangic))).p_zaman end as kanit_cikis
            from pdks.gun_kaydi g
            where g.is_gunu = p_gun and g.durum = 'eksik'
        ), zamanlar as (
            select okuyucu_id, calisan_id, z
            from eksik, unnest(array[kanit_giris, kanit_cikis]) z
            where z is not null and okuyucu_id is not null
        )
        select okuyucu_id, min(z) as bas, max(z) as bit, count(distinct calisan_id) as kisi
        from zamanlar
        group by okuyucu_id
        having count(distinct calisan_id) >= v_esik
    loop
        -- Kanıt zamanında okuyucu gerçekten sessiz miydi? Aralıkta okutma varsa şüphe yok.
        continue when exists (select 1 from pdks.ham_okutma h
                              where h.okuyucu_id = r.okuyucu_id and h.okutma_zamani between r.bas and r.bit);

        select id into v_ariza from pdks.ariza a
        where a.okuyucu_id = r.okuyucu_id and a.kaynak = 'otomatik_suphe' and a.durum <> 'reddedildi'
          and tstzrange(a.baslangic - v_pay, coalesce(a.bitis, a.baslangic) + v_pay) && tstzrange(r.bas, r.bit, '[]')
        order by a.id limit 1;

        if v_ariza is null then
            insert into pdks.ariza (okuyucu_id, baslangic, bitis, kaynak, durum, aciklama)
            values (r.okuyucu_id, r.bas, greatest(r.bit, r.bas + interval '1 minute'), 'otomatik_suphe', 'suphe',
                    format('%s çalışanın kapı kaydı bulunmasına rağmen PDKS okutması yok; okuyucudan bu aralıkta okutma alınmadı.', r.kisi))
            returning id into v_ariza;
        else
            update pdks.ariza
            set baslangic = least(baslangic, r.bas),
                bitis     = greatest(coalesce(bitis, baslangic), r.bit, least(baslangic, r.bas) + interval '1 minute')
            where id = v_ariza;
        end if;

        v_say := v_say + pdks.uyari_yaz('ariza_suphesi', 'ariza:' || v_ariza,
            format('%s okuyucusundan %s itibarıyla okutma alınmadı. İK incelemesi bekleniyor.',
                   (select kod from pdks.okuyucu where id = r.okuyucu_id),
                   to_char(r.bas at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI')),
            null, r.okuyucu_id);
    end loop;
    return v_say;
end;
$function$;

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
        if v_hedef is null or pdks.kullanici_calisani(v_hedef) = s.calisan_id then
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

CREATE OR REPLACE FUNCTION pdks.gece_isi_isaretle(p_gun date, p_gece_isi_id bigint)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'pdks'
AS $function$
declare
    v_bas   timestamptz := ((p_gun - 1)::timestamp at time zone 'Europe/Istanbul');
    v_bit   timestamptz := ((p_gun + 2)::timestamp at time zone 'Europe/Istanbul');
    v_esik  interval    := make_interval(mins => pdks.ayar_al('mukerrer_esik_dk'));
    v_say   integer := 0;
    v_n     integer;
    r       record;
begin
    -- Mükerrer: aynı kart, aynı yön, eşik süresi içinde tekrar
    insert into pdks.okutma_isareti (ham_okutma_id, isaret, aciklama, gece_isi_id)
    select x.id, 'mukerrer',
           format('%s sn önce aynı kart aynı yönde okutulmuş', extract(epoch from x.okutma_zamani - x.onceki)::int),
           p_gece_isi_id
    from (select h.id, h.okutma_zamani,
                 lag(h.okutma_zamani) over (partition by h.kart_no, h.yon order by h.okutma_zamani, h.id) as onceki
          from pdks.ham_okutma h
          where h.okutma_zamani >= v_bas - v_esik and h.okutma_zamani < v_bit) x
    where x.onceki is not null
      and x.okutma_zamani - x.onceki <= v_esik
      and x.okutma_zamani >= v_bas
    on conflict (ham_okutma_id, isaret) do nothing;
    get diagnostics v_n = row_count;
    v_say := v_say + v_n;

    -- İptal edilmiş kartla okutma (+ İK'ya uyarı)
    for r in
        select h.id, h.okuyucu_id, h.kart_no, h.okutma_zamani, k.calisan_id
        from pdks.ham_okutma h
        join pdks.kart k on k.kart_no = h.kart_no
        where k.durum = 'iptal' and h.okutma_zamani >= k.iptal_zamani
          and h.okutma_zamani >= v_bas and h.okutma_zamani < v_bit
    loop
        insert into pdks.okutma_isareti (ham_okutma_id, isaret, aciklama, gece_isi_id)
        values (r.id, 'iptal_kart', 'Kart bu okutmadan önce iptal edilmişti', p_gece_isi_id)
        on conflict (ham_okutma_id, isaret) do nothing;
        get diagnostics v_n = row_count;
        v_say := v_say + v_n;
        perform pdks.uyari_yaz('iptal_kart_okutma', 'ham:' || r.id,
            format('%s numaralı iptal edilmiş kart %s tarihinde okutuldu.', r.kart_no,
                   to_char(r.okutma_zamani at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI')),
            r.calisan_id, r.okuyucu_id);
    end loop;

    -- Bilinmeyen kart: okutma anında kimseye ait değil (tanımsız kart ya da zimmetsiz geçici kart)
    insert into pdks.okutma_isareti (ham_okutma_id, isaret, aciklama, gece_isi_id)
    select h.id, 'bilinmeyen_kart', 'Okutma anında bu kart kimseye ait değil', p_gece_isi_id
    from pdks.ham_okutma h
    where h.okutma_zamani >= v_bas and h.okutma_zamani < v_bit
      and pdks.okutma_sahibi(h.kart_no, h.okutma_zamani) is null
    on conflict (ham_okutma_id, isaret) do nothing;
    get diagnostics v_n = row_count;
    v_say := v_say + v_n;

    return v_say;
end;
$function$;

CREATE OR REPLACE FUNCTION pdks.gece_isi_kanitla_duzelt(p_gun date)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'pdks'
AS $function$
declare
    v_yurume  interval := make_interval(mins => pdks.ayar_al('yurume_payi_dk'));
    v_say     integer := 0;
    v_ariza   bigint;
    v_esnek   boolean;
    v_giris   timestamptz;
    g         record;
    k         record;
begin
    for g in
        select * from pdks.gun_kaydi
        where is_gunu = p_gun and durum = 'eksik' and not pdks.donem_kilitli_mi(p_gun)
        order by id
    loop
        select coalesce(t.esnek, false) into v_esnek from pdks.vardiya_tanim t where t.id = g.vardiya_id;

        if g.giris_zamani is null then
            select * into k from pdks.gun_kaniti(g.id, 'giris');
            v_giris := null;
            if k.p_kanit_id is not null then
                if v_esnek then
                    -- Esnek: kanıttaki saat + yürüme payı (çıkıştan sonraya düşmüyorsa)
                    if g.cikis_zamani is null or k.p_zaman + v_yurume < g.cikis_zamani then
                        v_giris := k.p_zaman + v_yurume;
                    end if;
                elsif k.p_zaman + v_yurume <= g.planli_baslangic then
                    v_giris := g.planli_baslangic;
                end if;
            end if;

            if v_giris is not null then
                select a.id into v_ariza from pdks.ariza a
                where a.okuyucu_id = pdks.calisan_pdks_okuyucusu(g.calisan_id, p_gun)
                  and a.durum <> 'reddedildi' and k.p_zaman between a.baslangic and coalesce(a.bitis, 'infinity')
                limit 1;
                perform pdks.duzeltme_uygula(g.id, 'giris_zamani', v_giris::text,
                    case when v_esnek
                         then format('%s kaydı %s; yürüme süresi eklenerek giriş %s olarak kaydedildi',
                                     case k.p_kaynak when 'kapi' then 'Kapı' else 'Servis' end,
                                     to_char(k.p_zaman at time zone 'Europe/Istanbul', 'HH24:MI'),
                                     to_char(v_giris at time zone 'Europe/Istanbul', 'HH24:MI'))
                         else format('%s kaydı %s; giriş vardiya başlangıcı olarak kaydedildi',
                                     case k.p_kaynak when 'kapi' then 'Kapı' else 'Servis' end,
                                     to_char(k.p_zaman at time zone 'Europe/Istanbul', 'HH24:MI')) end,
                    'gece_isi', p_kanit_kaydi_id => k.p_kanit_id, p_ariza_id => v_ariza);
                v_say := v_say + 1;
                g.giris_zamani := v_giris;
            end if;
        end if;

        if g.cikis_zamani is null then
            select * into k from pdks.gun_kaniti(g.id, 'cikis', coalesce(g.giris_zamani, g.planli_baslangic));
            if k.p_kanit_id is not null then
                select a.id into v_ariza from pdks.ariza a
                where a.okuyucu_id = pdks.calisan_pdks_okuyucusu(g.calisan_id, p_gun)
                  and a.durum <> 'reddedildi' and k.p_zaman between a.baslangic and coalesce(a.bitis, 'infinity')
                limit 1;
                perform pdks.duzeltme_uygula(g.id, 'cikis_zamani', k.p_zaman::text,
                    format('%s kaydı %s; çıkış bu saat olarak kaydedildi',
                           case k.p_kaynak when 'kapi' then 'Kapı' else 'Servis' end, to_char(k.p_zaman at time zone 'Europe/Istanbul', 'HH24:MI')),
                    'gece_isi', p_kanit_kaydi_id => k.p_kanit_id, p_ariza_id => v_ariza);
                v_say := v_say + 1;
            end if;
        end if;
    end loop;
    return v_say;
end;
$function$;

CREATE OR REPLACE FUNCTION pdks.gece_isi_sorular(p_gun date)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'pdks'
AS $function$
declare
    v_yurume  interval := make_interval(mins => pdks.ayar_al('yurume_payi_dk'));
    v_son     date     := p_gun + 1 + pdks.ayar_al('soru_eskalasyon_gun');
    v_say     integer  := 0;
    v_n       integer;
    v_gun     text     := to_char(p_gun, 'DD.MM.YYYY');
    g         record;
    k         record;
    o         record;
    v_kanit   boolean;
begin
    for g in
        select gk.*, w.p_bas, w.p_bit
        from pdks.gun_kaydi gk
        cross join lateral pdks.gun_penceresi(gk.id) w
        where gk.is_gunu = p_gun and gk.durum = 'eksik' and not pdks.donem_kilitli_mi(p_gun)
          and pdks.pdks_verisi_tam_mi(w.p_bas, w.p_bit)
        order by gk.id
    loop
        -- Otomatik vardiya tanıma
        select * into o from pdks.vardiya_onerisi(g.id);
        if o.vardiya_id is not null then
            insert into pdks.amir_sorusu (gun_kaydi_id, soru_turu, aciklama, onerilen_zaman, onerilen_cikis,
                                          onerilen_vardiya_id, atanan_id, son_cevap_tarihi)
            values (g.id, 'vardiya_uyusmazligi',
                    format('%s: Okutmalar planlı vardiya (%s) yerine %s vardiyası ile uyumlu (giriş %s, çıkış %s). Onaylandığında vardiya ve saatler güncellenir.',
                           v_gun, (select ad from pdks.vardiya_tanim where id = g.vardiya_id),
                           (select ad from pdks.vardiya_tanim where id = o.vardiya_id),
                           to_char(o.giris at time zone 'Europe/Istanbul', 'DD.MM HH24:MI'),
                           to_char(o.cikis at time zone 'Europe/Istanbul', 'DD.MM HH24:MI')),
                    o.giris, o.cikis, o.vardiya_id, pdks.soru_atanacak(g.calisan_id), v_son)
            on conflict do nothing;
            get diagnostics v_n = row_count;
            v_say := v_say + v_n;
            update pdks.gun_kaydi set durum = 'soru_bekliyor' where id = g.id;
            continue;
        end if;

        if g.giris_zamani is null and g.cikis_zamani is null then
            select exists (select 1 from pdks.kanit_kaydi kk
                           where kk.okutma_zamani between g.p_bas and g.p_bit
                             and pdks.okutma_sahibi(kk.kart_no, kk.okutma_zamani) = g.calisan_id)
              into v_kanit;
            if not v_kanit then
                insert into pdks.amir_sorusu (gun_kaydi_id, soru_turu, aciklama, atanan_id, son_cevap_tarihi)
                values (g.id, 'hic_kayit_yok',
                        format('%s: Vardiya planı bulunmasına rağmen izin veya okutma kaydı yok.', v_gun),
                        pdks.soru_atanacak(g.calisan_id), v_son)
                on conflict do nothing;
                get diagnostics v_n = row_count;
                v_say := v_say + v_n;
                update pdks.gun_kaydi set durum = 'soru_bekliyor' where id = g.id;
                continue;
            end if;
        end if;

        if g.giris_zamani is null then
            select * into k from pdks.gun_kaniti(g.id, 'giris');
            if k.p_kanit_id is not null then
                insert into pdks.amir_sorusu (gun_kaydi_id, soru_turu, aciklama, onerilen_zaman, kanit_kaydi_id,
                                              atanan_id, son_cevap_tarihi)
                values (g.id, 'kanit_vardiya_sonrasi',
                        format('%s: PDKS giriş kaydı yok; %s kaydı %s (vardiya başlangıcından sonra). Giriş saati onaylanmalıdır.',
                               v_gun, case k.p_kaynak when 'kapi' then 'kapı' else 'servis' end, to_char(k.p_zaman at time zone 'Europe/Istanbul', 'HH24:MI')),
                        k.p_zaman + v_yurume, k.p_kanit_id, pdks.soru_atanacak(g.calisan_id), v_son)
                on conflict do nothing;
            else
                insert into pdks.amir_sorusu (gun_kaydi_id, soru_turu, aciklama, atanan_id, son_cevap_tarihi)
                values (g.id, 'giris_yok', format('%s: Giriş okutması ile kapı veya servis kaydı yok.', v_gun),
                        pdks.soru_atanacak(g.calisan_id), v_son)
                on conflict do nothing;
            end if;
            get diagnostics v_n = row_count;
            v_say := v_say + v_n;
        end if;

        if g.cikis_zamani is null then
            insert into pdks.amir_sorusu (gun_kaydi_id, soru_turu, aciklama, atanan_id, son_cevap_tarihi)
            values (g.id, 'cikis_yok', format('%s: Çıkış okutması ile kapı veya servis kaydı yok.', v_gun),
                    pdks.soru_atanacak(g.calisan_id), v_son)
            on conflict do nothing;
            get diagnostics v_n = row_count;
            v_say := v_say + v_n;
        end if;

        update pdks.gun_kaydi set durum = 'soru_bekliyor' where id = g.id;
    end loop;
    return v_say;
end;
$function$;

CREATE OR REPLACE FUNCTION pdks.gece_isi_uyarilar(p_gun date)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'pdks'
AS $function$
declare
    v_esik    integer := pdks.ayar_al('fm_plansiz_esik_dk');
    v_gunluk  integer := pdks.ayar_al('gunluk_azami_calisma_dk');
    v_say     integer := 0;
    r         record;
begin
    for r in
        select g.id, g.calisan_id, g.giris_zamani, g.cikis_zamani, g.planli_baslangic, t.esnek,
               pdks.dakika(g.planli_bitis, g.cikis_zamani) as fazla,
               coalesce(p.planli_dk, 0) as plan,
               pdks.fm_onay_gecerli_mi(g.calisan_id, g.is_gunu) as onay
        from pdks.gun_kaydi g
        join pdks.vardiya_tanim t on t.id = g.vardiya_id
        left join pdks.fazla_mesai_plani p
          on p.calisan_id = g.calisan_id and p.is_gunu = g.is_gunu and p.durum = 'onaylandi'
        where g.is_gunu = p_gun and g.cikis_zamani is not null and g.planli_bitis is not null
    loop
        if not r.esnek and r.fazla - r.plan > v_esik then
            if r.plan = 0 and not r.onay then
                v_say := v_say + pdks.uyari_yaz('fm_onay_yok', 'fm:' || r.id,
                    format('%s tarihinde vardiya sonrası %s çalışıldı; yazılı fazla mesai onayı yok.',
                           to_char(p_gun, 'DD.MM.YYYY'), pdks.sure_metni(r.fazla::integer)), r.calisan_id);
            else
                v_say := v_say + pdks.uyari_yaz('fm_plansiz_calisma', 'fm:' || r.id,
                    format('%s tarihinde vardiya sonrası %s çalışıldı (onaylı plan %s). Aşan süre İK kararı bekliyor.',
                           to_char(p_gun, 'DD.MM.YYYY'), pdks.sure_metni(r.fazla::integer), pdks.sure_metni(r.plan::integer)), r.calisan_id);
            end if;
        end if;

        if r.giris_zamani is not null
           and pdks.dakika(case when r.esnek then r.giris_zamani else greatest(r.giris_zamani, r.planli_baslangic) end,
                           r.cikis_zamani) > v_gunluk + v_esik then
            v_say := v_say + pdks.uyari_yaz('fm_gunluk_sinir_asildi', 'gunluk:' || r.id,
                format('%s tarihinde %s çalışıldı (%ssınır %s).', to_char(p_gun, 'DD.MM.YYYY'),
                       pdks.sure_metni(pdks.dakika(case when r.esnek then r.giris_zamani else greatest(r.giris_zamani, r.planli_baslangic) end,
                                   r.cikis_zamani)::integer), case when v_gunluk = 660 then 'yasal ' else '' end, pdks.sure_metni(v_gunluk)),
                r.calisan_id);
        end if;
    end loop;

    for r in
        select k from unnest(array['pdks', 'kapi', 'yemekhane', 'servis']) k
        where not exists (select 1 from pdks.aktarim a where a.kaynak = k and a.veri_tarihi = p_gun)
    loop
        v_say := v_say + pdks.uyari_yaz('dosya_gelmedi', r.k || ':' || p_gun,
            format('%s tarihli %s dosyası yüklenmedi.', to_char(p_gun, 'DD.MM.YYYY'),
                   case r.k when 'pdks' then 'PDKS' when 'kapi' then 'kapı turnikesi' else r.k end));
    end loop;

    v_say := v_say + coalesce(pdks.gecici_kart_kontrol(p_gun), 0);
    v_say := v_say + coalesce(pdks.kart_paylasim_kontrol(p_gun), 0);
    v_say := v_say + coalesce(pdks.isg_kontrol(p_gun), 0);
    v_say := v_say + coalesce(pdks.bolge_kontrol(p_gun), 0);

    return v_say;
end;
$function$;

CREATE OR REPLACE FUNCTION pdks.gecici_kart_kontrol(p_gun date)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'pdks'
AS $function$
declare
    v_bas    timestamptz := (p_gun::timestamp at time zone 'Europe/Istanbul');
    v_bit    timestamptz := ((p_gun + 1)::timestamp at time zone 'Europe/Istanbul');
    v_say    integer := 0;
    v_n      integer;
    v_esik   integer := pdks.ayar_al('sik_kart_unutma_esigi');
    v_iade_s integer := pdks.ayar_al('gecici_kart_iade_saat');
begin
    -- a) Geçici kart zimmetliyken çalışanın asıl kartı da okutuldu (PDKS ya da kanıt)
    insert into pdks.uyari (tur, calisan_id, okuyucu_id, mesaj, tekillik_anahtari)
    select distinct on (z.id)
           'gecici_kart_cakisma', z.calisan_id, o.okuyucu_id,
           format('%s geçici kartı zimmetli iken asıl kart (%s) %s tarihinde okutuldu.',
                  g.kart_no, k.kart_no, to_char(o.okutma_zamani at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI')),
           'zimmet:' || z.id
    from pdks.gecici_kart_zimmet z
    join pdks.gecici_kart g on g.id = z.gecici_kart_id
    join pdks.kart k on k.calisan_id = z.calisan_id
    join (select okuyucu_id, kart_no, okutma_zamani from pdks.ham_okutma
          union all
          select okuyucu_id, kart_no, okutma_zamani from pdks.kanit_kaydi) o
      on o.kart_no = k.kart_no
     and o.okutma_zamani >= z.verilis_zamani
     and (z.iade_zamani is null or o.okutma_zamani < z.iade_zamani)
    where o.okutma_zamani >= v_bas and o.okutma_zamani < v_bit
    order by z.id, o.okutma_zamani
    on conflict (tur, tekillik_anahtari) where tekillik_anahtari is not null do nothing;
    get diagnostics v_n = row_count; v_say := v_say + v_n;

    -- b) Geçici kart zimmet dışındaki bir saatte okutuldu
    insert into pdks.uyari (tur, okuyucu_id, mesaj, tekillik_anahtari)
    select 'gecici_kart_zimmetsiz', o.okuyucu_id,
           format('Zimmetli olmayan %s geçici kartı %s tarihinde okutuldu.',
                  o.kart_no, to_char(o.okutma_zamani at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI')),
           'okutma:' || o.kaynak || ':' || o.id
    from (select 'pdks' as kaynak, id, okuyucu_id, kart_no, okutma_zamani from pdks.ham_okutma
          union all
          select 'kanit', id, okuyucu_id, kart_no, okutma_zamani from pdks.kanit_kaydi) o
    join pdks.gecici_kart g on g.kart_no = o.kart_no
    where o.okutma_zamani >= v_bas and o.okutma_zamani < v_bit
      and pdks.okutma_sahibi(o.kart_no, o.okutma_zamani) is null
    on conflict (tur, tekillik_anahtari) where tekillik_anahtari is not null do nothing;
    get diagnostics v_n = row_count; v_say := v_say + v_n;

    -- c) Zimmet, ayardaki saatten uzun süredir iade edilmedi (gün sonuna göre)
    insert into pdks.uyari (tur, calisan_id, mesaj, tekillik_anahtari)
    select 'gecici_kart_iade_edilmedi', z.calisan_id,
           format('%s geçici kartı %s tarihinden itibaren iade edilmedi.',
                  g.kart_no, to_char(z.verilis_zamani at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI')),
           'zimmet:' || z.id
    from pdks.gecici_kart_zimmet z
    join pdks.gecici_kart g on g.id = z.gecici_kart_id
    where z.iade_zamani is null
      and z.verilis_zamani < v_bit - make_interval(hours => v_iade_s)
    on conflict (tur, tekillik_anahtari) where tekillik_anahtari is not null do nothing;
    get diagnostics v_n = row_count; v_say := v_say + v_n;

    -- d) Ayda eşik kadar ya da fazla geçici kart alan çalışan (bilgi, ceza değil)
    insert into pdks.uyari (tur, calisan_id, mesaj, tekillik_anahtari)
    select 'sik_kart_unutma', z.calisan_id,
           format('%s döneminde %s kez geçici kart kullanıldı.',
                  to_char(p_gun, 'MM.YYYY'), count(*)),
           'gecici:' || to_char(p_gun, 'YYYY-MM') || ':' || z.calisan_id
    from pdks.gecici_kart_zimmet z
    where z.verilis_zamani >= (date_trunc('month', p_gun)::timestamp at time zone 'Europe/Istanbul')
      and z.verilis_zamani < v_bit
    group by z.calisan_id
    having count(*) >= v_esik
    on conflict (tur, tekillik_anahtari) where tekillik_anahtari is not null do nothing;
    get diagnostics v_n = row_count; v_say := v_say + v_n;

    return v_say;
end;
$function$;

CREATE OR REPLACE FUNCTION pdks.gun_sonrasi_kontroller(p_gun_kaydi_id bigint)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'pdks'
AS $function$
declare
    g       pdks.gun_kaydi;
    h       record;
    v_mevcut pdks.fazla_mesai_inceleme;
    v_tur   text;
    v_say   integer := 0;
begin
    select * into g from pdks.gun_kaydi where id = p_gun_kaydi_id;
    if not g.hesap_tamam or g.durum <> 'tamam' then
        return 0;
    end if;
    select * into h from pdks.gun_hesabi(g.calisan_id, g.is_gunu, g.planli_baslangic, g.planli_bitis,
                                         g.giris_zamani, g.cikis_zamani);
    v_tur := case when pdks.fm100_gunu_mu(g.is_gunu) and not pdks.fm_onay_gecerli_mi(g.calisan_id, g.is_gunu)
                  then 'tatil_calismasi' else 'vardiya_sonrasi' end;

    select * into v_mevcut from pdks.fazla_mesai_inceleme where gun_kaydi_id = g.id;
    if h.onaysiz_fm_dk > pdks.ayar_al('fm_plansiz_esik_dk') then
        if v_mevcut.id is null then
            insert into pdks.fazla_mesai_inceleme (gun_kaydi_id, calisan_id, is_gunu, tur, dakika)
            values (g.id, g.calisan_id, g.is_gunu, v_tur, h.onaysiz_fm_dk);
            v_say := v_say + 1;
        elsif v_mevcut.durum = 'inceleme_bekliyor' and (v_mevcut.dakika, v_mevcut.tur) <> (h.onaysiz_fm_dk, v_tur) then
            update pdks.fazla_mesai_inceleme set dakika = h.onaysiz_fm_dk, tur = v_tur where id = v_mevcut.id;
        end if;
    end if;

    if g.gece_calisma_dk > pdks.ayar_al('gece_calisma_sinir_dk') then
        v_say := v_say + pdks.uyari_yaz('gece_calisma_siniri_asildi', 'gece:' || g.id,
            format('%s tarihinde %s gece çalışması yapıldı (%ssınır %s).',
                   to_char(g.is_gunu, 'DD.MM.YYYY'), pdks.sure_metni(g.gece_calisma_dk),
                   case when pdks.ayar_al('gece_calisma_sinir_dk') = 450 then 'yasal ' else '' end,
                   pdks.sure_metni(pdks.ayar_al('gece_calisma_sinir_dk'))),
            g.calisan_id);
    end if;
    return v_say;
end;
$function$;

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
                           order by b.id desc limit 1) b on true
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
                            where x.calisan_id = c.id order by x.tur, x.id desc) b
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

CREATE OR REPLACE FUNCTION pdks.kart_paylasim_kontrol(p_gun date)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'pdks'
AS $function$
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
               (okutma_zamani at time zone 'Europe/Istanbul')::date as gun
        from sirali
        where calisan_id is not null and onceki_calisan is not null
          and calisan_id <> onceki_calisan
          and okutma_zamani - onceki_zaman <= make_interval(secs => v_sn)
    ),
    supheli as (
        select a, b, count(distinct gun) as gun_sayisi
        from ciftler
        group by a, b
        having count(distinct gun) >= v_gun
    )
    insert into pdks.uyari (tur, calisan_id, mesaj, tekillik_anahtari)
    select 'kart_paylasim_suphesi', s.a,
           format('%s (%s %s) ve %s (%s %s) kartları %s döneminde %s farklı günde %s saniye içinde art arda okutuldu.',
                  c1.sicil_no, c1.ad, c1.soyad, c2.sicil_no, c2.ad, c2.soyad,
                  to_char(p_gun, 'MM.YYYY'), s.gun_sayisi, v_sn),
           'ay:' || to_char(p_gun, 'YYYY-MM') || ':' || s.a || '-' || s.b
    from supheli s
    join pdks.calisan c1 on c1.id = s.a
    join pdks.calisan c2 on c2.id = s.b
    on conflict (tur, tekillik_anahtari) where tekillik_anahtari is not null do nothing;

    get diagnostics v_say = row_count;
    return v_say;
end;
$function$;

CREATE OR REPLACE FUNCTION pdks.soru_cevapla(p_soru_id bigint, p_cevap text, p_giris timestamp with time zone DEFAULT NULL::timestamp with time zone, p_cikis timestamp with time zone DEFAULT NULL::timestamp with time zone, p_aciklama text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pdks'
AS $function$
declare
    v_ben     bigint := pdks.yetki_gerekli('amir');
    v_soru    pdks.amir_sorusu;
    v_gun     pdks.gun_kaydi;
    v_giris   timestamptz;
    v_cikis   timestamptz;
    v_vardiya smallint;
begin
    select * into v_soru from pdks.amir_sorusu where id = p_soru_id for update;
    if not found or v_ben not in (v_soru.atanan_id, coalesce(v_soru.eskale_edilen_id, 0)) then
        raise exception 'Soru bulunamadı ya da size atanmamış.';
    end if;
    if v_soru.durum not in ('acik', 'eskale') then
        raise exception 'Bu soru zaten cevaplanmış.';
    end if;
    if p_cevap not in ('geldi_saat_dogru', 'geldi_saat_farkli', 'kart_unuttu', 'gelmedi', 'bilmiyorum') then
        raise exception 'Geçersiz cevap: %', p_cevap;
    end if;
    select * into v_gun from pdks.gun_kaydi where id = v_soru.gun_kaydi_id;

    if p_cevap = 'geldi_saat_farkli' and p_giris is null and p_cikis is null then
        raise exception 'Saat farklıysa giriş ya da çıkış saatini girin.';
    end if;

    if p_cevap in ('geldi_saat_dogru', 'kart_unuttu') and p_giris is null and p_cikis is null then
        if v_soru.soru_turu = 'vardiya_uyusmazligi' then
            if v_soru.onerilen_vardiya_id is null then
                raise exception 'Bu soru türünde saatleri girin.';
            end if;
            v_vardiya := v_soru.onerilen_vardiya_id;
            v_giris := v_soru.onerilen_zaman;
            v_cikis := v_soru.onerilen_cikis;
        end if;
        if v_soru.soru_turu in ('giris_yok', 'kanit_vardiya_sonrasi', 'ariza_kaniti_yok', 'hic_kayit_yok') then
            v_giris := coalesce(v_soru.onerilen_zaman, v_gun.planli_baslangic);
        end if;
        if v_soru.soru_turu = 'cikis_yok' then
            v_cikis := coalesce(v_soru.onerilen_zaman, v_gun.planli_bitis);
        end if;
        if v_soru.soru_turu = 'hic_kayit_yok' then
            v_cikis := v_gun.planli_bitis;
        end if;
    else
        v_giris := p_giris;
        v_cikis := p_cikis;
    end if;

    update pdks.amir_sorusu
    set cevap = p_cevap, cevap_giris = v_giris, cevap_cikis = v_cikis, cevap_aciklama = p_aciklama,
        cevaplayan_id = v_ben,
        durum = case when p_cevap in ('gelmedi', 'bilmiyorum') then 'ik_karari_bekliyor' else 'cevaplandi' end
    where id = p_soru_id;

    if p_cevap not in ('gelmedi', 'bilmiyorum') then
        if v_vardiya is not null then
            perform pdks.duzeltme_uygula(v_soru.gun_kaydi_id, 'vardiya_id', v_vardiya::text,
                'Amir cevabı: vardiya önerisi onaylandı' || coalesce(' (' || p_aciklama || ')', ''),
                'amir', v_ben, p_soru_id => p_soru_id);
        end if;
        perform pdks.saat_yaz(v_soru.gun_kaydi_id, v_giris, v_cikis,
                              'Amir cevabı: ' || pdks.soru_cevabi_adi(p_cevap) || coalesce(' (' || p_aciklama || ')', ''),
                              'amir', v_ben, p_soru_id => p_soru_id);
    end if;

    -- Değişen gün hemen hesaplanır (kilitli ayda yapılmaz; düzeltme orada fark satırı olur)
    perform pdks.gun_hesapla(v_soru.gun_kaydi_id);
end;
$function$;

CREATE OR REPLACE FUNCTION pdks.fm_plan_denetle(p_calisan_id bigint, p_is_gunu date, p_vardiya_id smallint, p_planli_dk integer, p_plan_id bigint)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'pdks'
AS $function$
declare
    v_gunluk  integer;
    v_toplam  integer;
    v_sinir   integer := pdks.ayar_al('fm_yillik_sinir_dk');
begin
    -- Aynı çalışan için iki onay aynı anda gelirse ikisi de sınırı göremeden geçmesin:
    -- çalışan satırını kilitleyerek işlemleri sıraya sokarız.
    perform 1 from pdks.calisan where id = p_calisan_id for update;

    if not pdks.fm_onay_gecerli_mi(p_calisan_id, p_is_gunu) then
        raise exception 'Çalışanın % günü için geçerli yazılı fazla mesai onayı yok.', p_is_gunu;
    end if;

    if (select gece_yarisini_asar from pdks.vardiya_tanim where id = p_vardiya_id) then
        raise exception 'Gece vardiyası için fazla mesai planlanamaz (İş Kanunu m. 69).';
    end if;

    v_gunluk := pdks.vardiya_suresi_dk(p_vardiya_id) + p_planli_dk;
    if v_gunluk > pdks.ayar_al('gunluk_azami_calisma_dk') then
        raise exception 'Günlük çalışma süresi % olur; sınır %.',
            pdks.sure_metni(v_gunluk), pdks.sure_metni(pdks.ayar_al('gunluk_azami_calisma_dk'));
    end if;

    select coalesce(sum(planli_dk), 0) into v_toplam
    from pdks.fazla_mesai_plani
    where calisan_id = p_calisan_id
      and extract(year from is_gunu) = extract(year from p_is_gunu)
      and durum = 'onaylandi'
      and id is distinct from p_plan_id;

    if v_toplam + p_planli_dk > v_sinir then
        raise exception 'Yıllık fazla mesai sınırı aşılıyor. Kalan süre: %.', pdks.sure_metni(greatest(v_sinir - v_toplam, 0)::integer);
    end if;
    return v_toplam + p_planli_dk;
end;
$function$;

CREATE OR REPLACE FUNCTION pdks.izin_iptal(p_izin_id bigint, p_neden text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pdks'
AS $function$
declare
    v_ben    bigint := pdks.yetki_gerekli('ik');
    v_izin   pdks.izin;
    v_islenen integer;
begin
    select * into v_izin from pdks.izin where id = p_izin_id for update;
    if not found then
        raise exception 'İzin bulunamadı.';
    end if;
    if v_izin.iptal_zamani is not null then
        raise exception 'Bu izin zaten iptal edilmiş.';
    end if;
    if p_neden is null or length(trim(p_neden)) < 5 then
        raise exception 'İptal nedeni yazılmalı (en az 5 karakter).';
    end if;

    select count(*) into v_islenen
    from pdks.gun_kaydi g
    where g.calisan_id = v_izin.calisan_id
      and g.is_gunu between v_izin.baslangic and v_izin.bitis
      and g.durum in ('izinli', 'raporlu');
    if v_islenen > 0 then
        raise exception 'İznin % günü işlenmiştir. Bu günler önce kayıt düzeltme ile güncellenmelidir.', v_islenen;
    end if;

    update pdks.izin
    set iptal_zamani = now(), iptal_eden_id = v_ben, iptal_nedeni = trim(p_neden)
    where id = p_izin_id;
end;
$function$;

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
    if not exists (select 1 from pdks.calisan where id = p_calisan_id and aktif) then
        raise exception 'Çalışan bulunamadı ya da aktif değil.';
    end if;
    insert into pdks.isg_belge (calisan_id, tur, gecerlilik_bitis, belge_no, giren_id)
    values (p_calisan_id, p_tur, p_gecerlilik_bitis, nullif(trim(p_belge_no), ''), v_ben)
    returning id into v_id;
    return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION pdks.ay_kilitle(p_yil smallint, p_ay smallint, p_zorla boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pdks'
AS $function$
declare
    v_ben       bigint := pdks.yetki_gerekli('ik');
    v_bas       date := make_date(p_yil, p_ay, 1);
    v_bit       date := (make_date(p_yil, p_ay, 1) + interval '1 month - 1 day')::date;
    v_donem     bigint := pdks.donem_bul(make_date(p_yil, p_ay, 1));
    v_eksik     record;
    v_plan      integer;
    v_fm        integer;
    v_soru      integer;
    v_itiraz    integer;
    v_kodsuz    integer;
    v_kodsuz_liste jsonb;
    v_kodsuz_metin text;
    v_gecilen   text;
begin
    -- 0) Ay bitmeden kilit yok (T-89): son günü İstanbul tarihiyle bugünden önce olmalı.
    --    Kilit açılamadığı için zorla da geçilemez.
    if v_bit >= pdks.bugun() then
        raise exception '%/% dönemi henüz bitmedi (son gün %). Ay, son günü geçtikten sonra kilitlenir.',
            p_ay, p_yil, to_char(v_bit, 'DD.MM.YYYY');
    end if;

    -- 1) Cevaplanmış ya da düzeltilmiş ama henüz hesaplanmamış günler kilitten önce hesaplanır
    perform pdks.gun_hesapla(g.id)
    from pdks.gun_kaydi g
    where g.is_gunu between v_bas and v_bit and not g.hesap_tamam
    order by g.id;

    -- 2) Gece işinden geçmemiş planlı gün: zorla geçilemez
    --    Reddedilmiş ya da İK onayı bekleyen planın işlenmemiş günü de sayılır: İK doğru planı
    --    girmeden ya da bekleyen planı onaylamadan / reddetmeden ay kapanmaz.
    select count(*) as gun, count(distinct vp.calisan_id) as kisi, min(vp.tarih) as ilk,
           count(*) filter (where vp.ik_onay_durumu = 'reddedildi') as reddedilmis,
           count(*) filter (where vp.ik_onay_durumu = 'bekliyor') as bekleyen
      into v_eksik
    from pdks.vardiya_plani vp
    join pdks.calisan c on c.id = vp.calisan_id
    where vp.tarih between v_bas and v_bit
      and vp.tarih >= c.ise_giris_tarihi
      and (c.isten_cikis_tarihi is null or vp.tarih <= c.isten_cikis_tarihi)
      and not exists (select 1 from pdks.gun_kaydi g where g.calisan_id = vp.calisan_id and g.is_gunu = vp.tarih);
    if v_eksik.gun > 0 then
        raise exception '%/% döneminde işlenmemiş % planlı gün bulunuyor (% çalışan, ilk gün %)%. Kilitlemeden önce bu günler işlenmelidir%.',
            p_ay, p_yil, v_eksik.gun, v_eksik.kisi, to_char(v_eksik.ilk, 'DD.MM.YYYY'),
            concat(case when v_eksik.reddedilmis > 0 then format('; %s günün geriye dönük planı reddedilmiş', v_eksik.reddedilmis) end,
                   case when v_eksik.bekleyen > 0 then format('; %s günün geriye dönük planı İK onayı bekliyor', v_eksik.bekleyen) end),
            concat(case when v_eksik.reddedilmis > 0 then '; reddedilen planın yerine geçerli plan girilmelidir' end,
                   case when v_eksik.bekleyen > 0 then '; İK onayı bekleyen plan onaylanmalı veya reddedilmelidir' end);
    end if;

    -- 3) Bekleyen işler (zorla geçilebilir)
    select count(*) into v_plan
    from pdks.vardiya_plani
    where tarih between v_bas and v_bit and geriye_donuk and ik_onay_durumu = 'bekliyor'
      -- yalnızca eski planla işlenmiş gün (işlenmemiş gün yukarıda, zorla geçilemeyen kontrolde)
      and exists (select 1 from pdks.gun_kaydi g where g.calisan_id = vardiya_plani.calisan_id and g.is_gunu = vardiya_plani.tarih);
    select count(*) into v_fm
    from pdks.fazla_mesai_inceleme
    where durum = 'inceleme_bekliyor' and is_gunu between v_bas and v_bit;
    select count(*) into v_soru
    from pdks.gun_kaydi g
    where g.is_gunu between v_bas and v_bit
      and exists (select 1 from pdks.amir_sorusu s
                  where s.gun_kaydi_id = g.id and s.durum in ('acik', 'eskale', 'ik_karari_bekliyor'));
    select count(*) into v_itiraz
    from pdks.itiraz i join pdks.gun_kaydi g on g.id = i.gun_kaydi_id
    where g.is_gunu between v_bas and v_bit and i.durum in ('acik', 'inceleniyor');

    if not p_zorla then
        if v_plan > 0 then
            raise exception '%/% döneminde İK onayı bekleyen % geriye dönük vardiya planı var.', p_ay, p_yil, v_plan;
        end if;
        if v_fm > 0 then
            raise exception '%/% döneminde İK kararı bekleyen % onaysız fazla mesai var.', p_ay, p_yil, v_fm;
        end if;
    end if;
    -- Açık soru / itiraz kontrolü (ve zorla) donem_kilitle'de
    perform pdks.donem_kilitle(v_donem, v_ben, p_zorla);
    perform pdks.puantaj_yaz(v_donem);

    -- 4) Puantaja kodsuz girecek gün (T-90, T-101): gün kaydı var ama puantaj kodu üretilmiyor
    --    (ör. açık sorulu, tek saatli cevaplı ya da hesaplanmamış gün). Kilit ve puantaj yukarıda
    --    yazıldı; zorlamadan kilitte kodsuz gün varsa hata bütün işlemi (kilit dahil) geri alır.
    select count(*),
           coalesce(jsonb_agg(jsonb_build_object(
                        'sicil', c.sicil_no, 'gun', g.is_gunu, 'durum', g.durum,
                        'neden', case
                            when exists (select 1 from pdks.amir_sorusu s
                                         where s.gun_kaydi_id = g.id
                                           and s.durum in ('acik', 'eskale', 'ik_karari_bekliyor'))
                                then 'açık soru'
                            when g.durum = 'tamam' and not g.hesap_tamam then 'hesap tamamlanmadı'
                            else replace(g.durum, '_', ' ')
                        end)
                    order by c.sicil_no, g.is_gunu), '[]'::jsonb)
      into v_kodsuz, v_kodsuz_liste
    from pdks.gun_kaydi g
    join pdks.calisan c on c.id = g.calisan_id
    where g.is_gunu between v_bas and v_bit
      and not exists (select 1 from pdks.gun_kod_satirlari(
                          g.calisan_id, g.is_gunu,
                          case when g.durum = 'tamam' and not g.hesap_tamam then 'eksik' else g.durum end,
                          g.calisma_dk, g.fm50_dk, g.fm100_dk));

    if v_kodsuz > 0 and not p_zorla then
        select string_agg(format('%s %s (%s)', e ->> 'sicil', to_char((e ->> 'gun')::date, 'DD.MM.YYYY'), e ->> 'neden'),
                          ', ' order by n)
          into v_kodsuz_metin
        from jsonb_array_elements(v_kodsuz_liste) with ordinality as x(e, n)
        where n <= 10;
        -- En çok 10 gün yazılır; kalanı sayılır
        if v_kodsuz > 10 then
            v_kodsuz_metin := v_kodsuz_metin || format(' ve %s gün daha', v_kodsuz - 10);
        end if;
        raise exception '%/% döneminde % gün için puantaj kodu oluşmadı: %. Bu günler kilitlemeden önce sonuçlandırılmalıdır.',
            p_ay, p_yil, v_kodsuz, v_kodsuz_metin;
    end if;

    v_gecilen := concat_ws(', ',
        case when v_soru   > 0 then v_soru   || ' açık sorulu gün' end,
        case when v_itiraz > 0 then v_itiraz || ' açık itiraz' end,
        case when v_fm     > 0 then v_fm     || ' onaysız fazla mesai' end,
        case when v_plan   > 0 then v_plan   || ' onay bekleyen geriye dönük plan' end,
        case when v_kodsuz > 0 then v_kodsuz || ' kodsuz gün' end);

    return jsonb_build_object(
        'donem', to_char(v_bas, 'YYYY-MM'),
        'zorla', p_zorla,
        'zorla_gecilen', jsonb_build_object(
            'acik_soru_gun', v_soru, 'acik_itiraz', v_itiraz,
            'bekleyen_fazla_mesai', v_fm, 'bekleyen_plan_onayi', v_plan),
        'kodsuz_gun', v_kodsuz,
        'kodsuz_gun_listesi', v_kodsuz_liste,
        'mesaj', format('%s/%s kilitlendi.', p_ay, p_yil)
                 || case when v_gecilen <> '' then ' Sonuçlanmadan kilitlenen kayıtlar: ' || v_gecilen || '.' else '' end);
end;
$function$;
