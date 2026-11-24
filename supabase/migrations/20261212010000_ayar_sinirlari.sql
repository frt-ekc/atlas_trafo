-- =====================================================================
-- K6 · T-74: Ayarlarda yalnızca "0'dan küçük olamaz" kontrolü vardı; yasal sınırlar
-- ve puantaj kuralları tek çağrıyla anlamsız değerlere çekilebiliyordu
--
-- Değişiklik:
--   * ayar.en_az / en_cok : her ayarın izin verilen aralığı. Yasal sınırlarda en_cok yasa
--     değeridir (m.63: 660, m.41: 16200, m.69: 450); molalarda en_az m.68'in en az süresidir.
--     Aralık ekrandan değişmez; değiştirmek yeni migration ister.
--   * ayar.puantaji_etkiler : değişince İK'ya uyarı yazılır (puantaj_ayari_degisti).
--   * ayar_guncelle(text, text): değeri metin alır; ondalık / metin / boş değer, PostgreSQL'in
--     İngilizce hatası yerine Türkçe mesajla reddedilir. Aralık ve mola sıralaması denetlenir.
--     Eski (text, integer) sürümü kaldırılır: iki sürüm birlikte kalırsa PostgREST hangisini
--     çağıracağını bilemez.
--
-- Aralık, kullanıcının tek yazma yolu olan ayar_guncelle'de denetlenir. Veritabanı sahibinin
-- doğrudan UPDATE'i bu kapsamda değildir (testler bilerek uç değer yazar).
-- Ayarların bugünkü değerleri değişmez.
-- Kalıcı test: supabase/tests/ayar_sinirlari_testi.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Aralık sütunları
-- ---------------------------------------------------------------------
alter table pdks.ayar
    add column en_az integer,
    add column en_cok integer,
    add column puantaji_etkiler boolean not null default false;

-- Yalnızca aralık doldurulur; ayarın "son değişiklik" zamanı oynamasın
alter table pdks.ayar disable trigger ayar_iz;

update pdks.ayar a
set en_az = v.en_az, en_cok = v.en_cok, puantaji_etkiler = v.puantaj
from (values
    -- Yasal sınırlar (üst sınır yasa değeri)
    ('gunluk_azami_calisma_dk', 480,   660, true),   -- m.63: 11 saat
    ('fm_yillik_sinir_dk',        0, 16200, true),   -- m.41: 270 saat
    ('gece_calisma_sinir_dk',    60,   450, false),  -- m.69: 7,5 saat (yalnızca uyarı)
    -- Mola (m.68: en az 15 / 30 / 60 dk; sınırlar 4 ve 7,5 saat)
    ('mola_kisa_dk',             15,    60, true),
    ('mola_orta_dk',             30,    90, true),
    ('mola_uzun_dk',             60,   120, true),
    ('mola_kisa_sinir_dk',       60,   240, true),
    ('mola_orta_sinir_dk',      120,   450, true),
    -- Puantaj toleransları ve hedefleri
    ('gec_kalma_tolerans_dk',     0,    60, true),
    ('erken_cikis_tolerans_dk',   0,    60, true),
    ('tolerans_yuvarlama_dk',     0,    60, true),
    ('yurume_payi_dk',            0,    30, true),
    ('mukerrer_esik_dk',          1,    30, true),
    ('fm_plansiz_esik_dk',        0,    60, true),
    ('esnek_gunluk_hedef_dk',   240,   660, true),
    -- Bayrak ve yüzde
    ('cumartesi_hafta_sonu',      0,     1, true),
    ('fm_yaklasma_uyari_yuzde',   1,   100, false),
    -- Uyarı ve soru eşikleri
    ('ariza_suphe_dk',           15,   480, false),
    ('ariza_suphe_kisi',          1,    50, false),
    ('gecici_kart_iade_saat',     1,    72, false),
    ('isg_uyari_gun',             1,   180, false),
    ('kart_paylasim_gun',         1,    31, false),
    ('kart_paylasim_sn',          1,    60, false),
    ('oto_vardiya_esik_dk',       1,   120, false),
    ('sik_kart_unutma_esigi',     1,    31, false),
    ('soru_eskalasyon_gun',       1,    15, false)
) v(anahtar, en_az, en_cok, puantaj)
where a.anahtar = v.anahtar;

alter table pdks.ayar enable trigger ayar_iz;

do $$
declare
    v_liste text;
begin
    -- Aralığı yazılmamış ayar kalmasın (sütunlar aşağıda not null olur)
    select string_agg(anahtar, ', ') into v_liste from pdks.ayar where en_az is null or en_cok is null;
    if v_liste is not null then
        raise exception 'Aralığı tanımlanmamış ayar var: %', v_liste;
    end if;
    -- Bugünkü değeri aralık dışında olan ayar kendiliğinden değiştirilmez, yalnızca haber verilir
    select string_agg(anahtar || ' = ' || deger, ', ') into v_liste from pdks.ayar where deger not between en_az and en_cok;
    if v_liste is not null then
        raise warning 'Değeri aralık dışında olan ayar var, ekrandan düzeltilmeli: %', v_liste;
    end if;
end $$;

alter table pdks.ayar
    alter column en_az set not null,
    alter column en_cok set not null,
    add constraint ayar_aralik_check check (en_az <= en_cok);

comment on column pdks.ayar.en_az is 'İzin verilen en küçük değer; ayar_guncelle denetler (T-74).';
comment on column pdks.ayar.en_cok is 'İzin verilen en büyük değer; yasal sınırlarda yasa değeri (T-74).';
comment on column pdks.ayar.puantaji_etkiler is 'true ise değer değişince İK''ya puantaj_ayari_degisti uyarısı yazılır (T-74).';

-- ---------------------------------------------------------------------
-- 2. Uyarı türü (kısıtın güncel listesi korunarak eklenir)
-- ---------------------------------------------------------------------
do $$
declare
    v_tanim    text;
    v_degerler text[];
begin
    select pg_get_constraintdef(oid) into v_tanim
    from pg_constraint where conrelid = 'pdks.uyari'::regclass and conname = 'uyari_tur_check';
    select array_agg(d) into v_degerler
    from (select m[1] as d from regexp_matches(v_tanim, '''([a-z_]+)''', 'g') as r(m)
          union
          select 'puantaj_ayari_degisti') x;
    if array_length(v_degerler, 1) < 20 then
        raise exception 'uyari_tur_check kısıtı okunamadı: %', v_tanim;
    end if;
    alter table pdks.uyari drop constraint uyari_tur_check;
    execute format('alter table pdks.uyari add constraint uyari_tur_check check (tur in (%s))',
                   (select string_agg(quote_literal(d), ', ' order by d) from unnest(v_degerler) d));
end;
$$;

-- ---------------------------------------------------------------------
-- 3. ayar_guncelle
-- ---------------------------------------------------------------------
drop function pdks.ayar_guncelle(text, integer);

create function pdks.ayar_guncelle(p_anahtar text, p_deger text)
returns void
language plpgsql
security definer
set search_path = pdks
as $$
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
        raise exception 'Ayar bulunamadı: %', p_anahtar;
    end if;

    if v_metin is null or v_metin !~ '^-?[0-9]+$' then
        raise exception '% için tam sayı girin (ondalık ya da metin olmaz).', p_anahtar;
    end if;
    -- numeric: integer'a sığmayan sayı da aynı Türkçe mesajı alsın
    if v_metin::numeric not between v_ayar.en_az and v_ayar.en_cok then
        raise exception '% için değer % ile % arasında olmalı.', p_anahtar, v_ayar.en_az, v_ayar.en_cok;
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
            raise exception 'Mola süreleri sıralı olmalı: kısa (%) < orta (%) < uzun (%) dakika.',
                v_mola->>'mola_kisa_dk', v_mola->>'mola_orta_dk', v_mola->>'mola_uzun_dk';
        end if;
        if not (v_mola->>'mola_kisa_sinir_dk')::int < (v_mola->>'mola_orta_sinir_dk')::int then
            raise exception 'Mola sınırları sıralı olmalı: kısa sınır (%) < orta sınır (%) dakika.',
                v_mola->>'mola_kisa_sinir_dk', v_mola->>'mola_orta_sinir_dk';
        end if;
    end if;

    update pdks.ayar set deger = v_yeni, guncelleyen_id = v_ben where anahtar = p_anahtar;

    if v_ayar.puantaji_etkiler then
        select ad_soyad into v_kisi from pdks.kullanici where id = v_ben;
        perform pdks.uyari_yaz('puantaj_ayari_degisti',
            'ayar_gecmisi:' || (select max(id) from pdks.ayar_gecmisi where anahtar = p_anahtar),
            format('%s ayarı %s değerinden %s değerine çekildi (%s; değiştiren: %s). Bundan sonra hesaplanan günleri etkiler; işlenmiş günler kendiliğinden yeniden hesaplanmaz.',
                   p_anahtar, v_ayar.deger, v_yeni, v_ayar.birim, v_kisi));
    end if;
end;
$$;

comment on function pdks.ayar_guncelle(text, text) is
    'Admin ayar değerini değiştirir. Tam sayı, en_az–en_cok aralığı ve mola sıralaması denetlenir; puantajı etkileyen ayarda İK''ya uyarı yazılır (T-74).';

revoke execute on function pdks.ayar_guncelle(text, text) from public, anon;
grant execute on function pdks.ayar_guncelle(text, text) to authenticated;
