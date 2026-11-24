-- =====================================================================
-- Dosyayı yükleyen ve kendi okutması uyarısı (20261213010000_yukleyen.sql, T-13)
--   * Her yeni yüklemede aktarim.yukleyen_id oturumdaki kullanıcıdır.
--   * Dosyada yükleyenin kendi kartı (asıl ya da okutma anında zimmetli geçici kart)
--     varsa dosya yüklenir ve dosya başına bir uyarı yazılır.
--   * Uyarıyı yükleyen görmez ve "görüldü" yapamaz; diğer İK ve yönetici görür.
--
-- 1. bölüm migration'dan önceki kodda KALIR (yükleyen kaydedilmiyordu).
-- Testin kendi sahte verisi kullanılır; örnek veri yüklü olsun olmasın çalışır.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/yukleyen_testi.sql
-- =====================================================================
\pset tuples_only on
\pset format unaligned
begin;
set local timezone = 'Europe/Istanbul';

create schema test;
create function test.dogrula(p_ad text, p_kosul boolean) returns void language plpgsql as $$
begin
    if p_kosul is not true then raise exception 'KALDI  %', p_ad; end if;
    raise notice 'GEÇTİ  %', p_ad;
end $$;
create function test.hata(p_ad text, p_kalip text, p_sql text) returns void language plpgsql as $$
begin
    begin
        execute p_sql;
    exception when others then
        if sqlerrm not like '%' || p_kalip || '%' then
            raise exception 'KALDI  %: beklenmeyen hata: %', p_ad, sqlerrm;
        end if;
        raise notice 'GEÇTİ  %  (%)', p_ad, sqlerrm;
        return;
    end;
    raise exception 'KALDI  %: hata bekleniyordu ama komut çalıştı', p_ad;
end $$;
create function test.c(p text) returns bigint language sql security definer as $$
    select id from pdks.calisan where sicil_no = p $$;
create function test.k(p text) returns bigint language sql security definer as $$
    select id from pdks.kullanici where eposta = p $$;
create function test.oturum(p_eposta text) returns void language sql security definer as $$
    select set_config('request.jwt.claims',
        json_build_object('sub', (select auth_kullanici_id from pdks.kullanici where eposta = p_eposta),
                          'role', 'authenticated')::text, true) $$;
-- Dosya yükler: "kart zaman yon" satırları, virgülle ayrılmış
create function test.yukle(p_kaynak text, p_ad text, p_gun date, p_satirlar text) returns bigint language sql as $$
    select pdks.dosya_yukle(p_kaynak, p_ad, p_gun,
        (select jsonb_agg(jsonb_build_object('okuyucu', case p_kaynak when 'pdks' then 'YU-PDKS' else 'YU-KAPI' end,
                          'kart_no', split_part(btrim(s), ' ', 1),
                          'zaman', p_gun || 'T' || split_part(btrim(s), ' ', 2) || ':00+03:00',
                          'yon', split_part(btrim(s), ' ', 3)))
         from unnest(string_to_array(p_satirlar, ',')) s)) $$;
-- Testin kendi kontrolleri tablo sahibi olarak okur (RLS'den bağımsız)
create function test.yukleyen(p_id bigint) returns bigint language sql security definer as $$
    select (to_jsonb(a) ->> 'yukleyen_id')::bigint from pdks.aktarim a where id = p_id $$;
create function test.uyari(p_id bigint) returns setof pdks.uyari language sql security definer as $$
    select * from pdks.uyari where tur = 'kendi_okutmasi_yuklendi' and tekillik_anahtari = 'aktarim:' || p_id $$;
create function test.aktarim_id(p_ad text) returns bigint language sql security definer as $$
    select id from pdks.aktarim where dosya_adi = p_ad $$;
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
--   YUI1, YUI2: iki İK · YUY1: yönetici · YUG1: güvenlik · YUW1: çalışan
insert into pdks.departman (ad) values ('YU İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = 'YU İdari'), '2025-01-01'
from unnest(array['YUI1', 'YUI2', 'YUY1', 'YUG1', 'YUW1']) s;
insert into pdks.kullanici (eposta, rol, calisan_id, auth_kullanici_id)
select e, r, test.c(s), u::uuid
from (values ('yu_ik1@ornek.test', 'ik',       'YUI1', '00000000-0000-0000-0000-0000000013b1'),
             ('yu_ik2@ornek.test', 'ik',       'YUI2', '00000000-0000-0000-0000-0000000013b2'),
             ('yu_yon@ornek.test', 'yonetici', 'YUY1', '00000000-0000-0000-0000-0000000013b3'),
             ('yu_guv@ornek.test', 'guvenlik', 'YUG1', '00000000-0000-0000-0000-0000000013b4')) v(e, r, s, u);
insert into pdks.kart (kart_no, calisan_id, verilis_tarihi)
select 'K' || s, test.c(s), '2025-01-01' from unnest(array['YUI1', 'YUI2', 'YUW1']) s;
insert into pdks.okuyucu (kod, ad, sistem) values ('YU-PDKS', 'YU PDKS', 'pdks'), ('YU-KAPI', 'YU kapı', 'kapi');
-- GK-YU1: 10 Eylül 08:00–18:00 arası YUI1'de; 11 Eylül 08:00–18:00 arası YUW1'de
insert into pdks.gecici_kart (kart_no) values ('GK-YU1');
do $$
declare
    r record;
    v_id bigint;
begin
    for r in select * from (values ('YUI1', timestamptz '2026-09-10 08:00+03', timestamptz '2026-09-10 18:00+03'),
                                   ('YUW1', timestamptz '2026-09-11 08:00+03', timestamptz '2026-09-11 18:00+03')) v(s, bas, bit) loop
        insert into pdks.gecici_kart_zimmet (gecici_kart_id, calisan_id, verilis_zamani, veren_id, aciklama)
        values ((select id from pdks.gecici_kart where kart_no = 'GK-YU1'), test.c(r.s), r.bas, test.k('yu_guv@ornek.test'), 'Kartını unuttu')
        returning id into v_id;
        update pdks.gecici_kart_zimmet set iade_zamani = r.bit, iade_alan_id = test.k('yu_guv@ornek.test') where id = v_id;
    end loop;
end $$;

set local role authenticated;
select test.oturum('yu_ik1@ornek.test');

-- 1) Yükleyen kaydedilir (eski kodda KALIR) --------------------------------
select test.yukle('pdks', 'yu_baska.csv', '2026-09-08', 'KYUW1 08:00 giris, KYUI2 08:01 giris') \g /dev/null
select test.dogrula('yeni yüklemede yukleyen_id oturumdaki İK',
    test.yukleyen(test.aktarim_id('yu_baska.csv')) = test.k('yu_ik1@ornek.test'));
select test.dogrula('başka kartlarda (diğer İK''nın kartı dahil) uyarı yok',
    (select count(*) from test.uyari(test.aktarim_id('yu_baska.csv'))) = 0);

-- 2) Kendi asıl kartı --------------------------------------------------------
select test.yukle('pdks', 'yu_kendi.csv', '2026-09-09', 'KYUI1 07:55 giris, KYUW1 07:56 giris, KYUI1 17:05 cikis') \g /dev/null
select test.dogrula('kendi kartı: dosya reddedilmez, 3 okutma yazılır',
    (select satir_sayisi = 3 from pdks.aktarim where dosya_adi = 'yu_kendi.csv'));
select test.dogrula('kendi kartı: dosya başına bir uyarı (kim, hangi dosya, kaç okutma)',
    (select count(*) = 1 and bool_and(calisan_id = test.c('YUI1') and not goruldu
            and mesaj = 'AdYUI1 Örnek (YUI1), kendi kartına ait 2 okutma içeren yu_kendi.csv dosyasını yükledi (09.09.2026).')
     from test.uyari(test.aktarim_id('yu_kendi.csv'))));
select test.yukle('pdks', 'yu_kucuk_harf.csv', '2026-09-09', 'kyui1 12:30 cikis') \g /dev/null
select test.dogrula('kart numarası küçük harfle yazılsa da yakalanır',
    (select count(*) from test.uyari(test.aktarim_id('yu_kucuk_harf.csv'))) = 1);
select test.yukle('kapi', 'yu_kapi.csv', '2026-09-09', 'KYUI1 07:50 giris') \g /dev/null
select test.dogrula('kapı (kanıt) dosyasında da yakalanır ve yükleyen yazılır',
    (select count(*) from test.uyari(test.aktarim_id('yu_kapi.csv'))) = 1
    and test.yukleyen(test.aktarim_id('yu_kapi.csv')) = test.k('yu_ik1@ornek.test'));

-- 3) Geçici kart ------------------------------------------------------------
select test.yukle('pdks', 'yu_gecici.csv', '2026-09-10', 'GK-YU1 08:05 giris, GK-YU1 17:00 cikis') \g /dev/null
select test.dogrula('geçici kart yükleyende zimmetliyken yakalanır',
    (select count(*) = 1 and bool_and(mesaj like '%kartına ait 2 okutma içeren%') from test.uyari(test.aktarim_id('yu_gecici.csv'))));
select test.yukle('pdks', 'yu_gecici_baska.csv', '2026-09-11', 'GK-YU1 08:05 giris') \g /dev/null
select test.dogrula('aynı geçici kart başkasındayken uyarı yok',
    (select count(*) from test.uyari(test.aktarim_id('yu_gecici_baska.csv'))) = 0);
select test.yukle('pdks', 'yu_gecici_iade.csv', '2026-09-10', 'GK-YU1 18:30 cikis') \g /dev/null
select test.dogrula('iade edildikten sonraki okutmada uyarı yok',
    (select count(*) from test.uyari(test.aktarim_id('yu_gecici_iade.csv'))) = 0);

-- 4) Daha önce gelmiş okutma: yeni bir şey yazılmadıysa uyarı da yok -------------
select test.yukle('pdks', 'yu_tekrar.csv', '2026-09-09', 'KYUI1 07:55 giris, KYUW1 09:00 cikis') \g /dev/null
select test.dogrula('kendi okutması zaten kayıtlıysa (yeniden yazılmadı) uyarı yok',
    (select count(*) from test.uyari(test.aktarim_id('yu_tekrar.csv'))) = 0
    and (select satir_sayisi = 1 from pdks.aktarim where dosya_adi = 'yu_tekrar.csv'));

-- 5) Kim görür? --------------------------------------------------------------
select test.dogrula('yükleyen kendi uyarısını görmez',
    (select count(*) from pdks.uyari where tur = 'kendi_okutmasi_yuklendi' and calisan_id = test.c('YUI1')) = 0);
select test.hata('yükleyen kendi uyarısını "görüldü" yapamaz', 'Görevler ayrılığı',
    format('select pdks.uyari_goruldu(%s)', (select id from test.uyari(test.aktarim_id('yu_kendi.csv')))));
select test.oturum('yu_ik2@ornek.test');
select test.dogrula('diğer İK uyarıları görür (4)',
    (select count(*) from pdks.uyari where tur = 'kendi_okutmasi_yuklendi' and calisan_id = test.c('YUI1')) = 4);
select test.yukle('pdks', 'yu_ik2.csv', '2026-09-12', 'KYUI2 08:00 giris') \g /dev/null
select test.dogrula('kural her İK için aynı: ikinci İK kendi uyarısını görmez, birincininkini görür',
    (select array_agg(distinct calisan_id) from pdks.uyari where tur = 'kendi_okutmasi_yuklendi'
     and calisan_id in (test.c('YUI1'), test.c('YUI2'))) = array[test.c('YUI1')]);
select pdks.uyari_goruldu((select id from test.uyari(test.aktarim_id('yu_kendi.csv')))) \g /dev/null
select test.dogrula('diğer İK "görüldü" yapabilir',
    (select goruldu and goren_id = test.k('yu_ik2@ornek.test') from test.uyari(test.aktarim_id('yu_kendi.csv'))));
select test.oturum('yu_yon@ornek.test');
select test.dogrula('yönetici uyarıları ve yükleyeni görür',
    (select count(*) from pdks.uyari where tur = 'kendi_okutmasi_yuklendi' and calisan_id in (test.c('YUI1'), test.c('YUI2'))) = 5
    and (select (to_jsonb(a) ->> 'yukleyen_id')::bigint = test.k('yu_ik1@ornek.test') from pdks.aktarim a where dosya_adi = 'yu_kendi.csv'));
select test.oturum('yu_guv@ornek.test');
select test.dogrula('güvenlik ne uyarıyı ne aktarımı görür',
    (select count(*) from pdks.uyari where tur = 'kendi_okutmasi_yuklendi') = 0 and (select count(*) from pdks.aktarim) = 0);
reset role;

-- 6) Başka uyarılarda kural değişmedi; eski satır boş kalabilir; iz silinemez ----------
insert into pdks.uyari (tur, calisan_id, mesaj) values ('kart_paylasim_suphesi', test.c('YUI1'), 'Örnek uyarı');
set local role authenticated;
select test.oturum('yu_ik1@ornek.test');
select test.dogrula('İK kendisi hakkındaki başka uyarıları eskisi gibi görür',
    (select count(*) from pdks.uyari where tur = 'kart_paylasim_suphesi' and calisan_id = test.c('YUI1')) = 1);
reset role;
insert into pdks.aktarim (kaynak, dosya_adi, dosya_ozeti, veri_tarihi, satir_sayisi)
values ('pdks', 'yu_sql.csv', repeat('e', 64), '2026-09-13', 0);
select test.dogrula('SQL ile yüklenen örnek veri satırında yükleyen boş kalabilir', test.yukleyen(test.aktarim_id('yu_sql.csv')) is null);
select test.hata('yükleyen sonradan değiştirilemez', '',
    $$update pdks.aktarim set yukleyen_id = null where dosya_adi = 'yu_kendi.csv'$$);
select test.dogrula('anon oturum_calisan_id çağıramaz', not has_function_privilege('anon', 'pdks.oturum_calisan_id()', 'execute'));

do $$ begin raise notice 'YÜKLEYEN TESTLERİ GEÇTİ'; end $$;
rollback;
