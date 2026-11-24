-- =====================================================================
-- dosya_yukle testleri (20261128010000_dosya_yukle_duzeltmesi.sql)
-- Dosya özeti, doğru satır sayısı, sunucu denetimi ve eski çağrı biçimi.
-- Fonksiyon uygulamanın rolüyle ("authenticated"), İK adına çağrılır.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Örnek veri yüklü olsa da olmasa da çalışır (kendi okuyucularını ve
-- 2027 tarihli okutmalarını kullanır).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/dosya_yukle_testi.sql
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
-- Hata bekler; mesaj verilen kalıbı içermeli
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
create function test.oturum(p_eposta text) returns void language sql security definer as $$
    select set_config('request.jwt.claims',
        json_build_object('sub', (select auth_kullanici_id from pdks.kullanici where eposta = p_eposta),
                          'role', 'authenticated')::text, true);
$$;
create function test.c(p text) returns bigint language sql security definer as $$
    select id from pdks.calisan where sicil_no = p $$;
-- Testin kendi kontrolleri tablo sahibi olarak okur (RLS'den bağımsız)
create function test.sor(p_sql text) returns text language plpgsql security definer as $$
declare v text;
begin execute p_sql into v; return v; end $$;
-- Bir aktarımın satırları
create function test.aktarim(p_id bigint) returns pdks.aktarim language sql security definer as $$
    select * from pdks.aktarim where id = p_id $$;
-- Sahte SHA-256 özeti (64 onaltılık hane)
create function test.ozet(p text) returns text language sql as $$ select repeat(p, 64) $$;
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) -------------------------------------------
insert into pdks.departman (ad) values ('DY İdari'), ('DY Montaj');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = d), '2025-01-01'
from (values ('DY21', 'DY İdari'), ('DY11', 'DY Montaj')) v(s, d);
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('İK',   'dy_ik@ornek.test',   'ik',   test.c('DY21'), '00000000-0000-0000-0000-0000000000d1'),
    ('Amir', 'dy_amir@ornek.test', 'amir', test.c('DY11'), '00000000-0000-0000-0000-0000000000d2');
insert into pdks.okuyucu (kod, ad, sistem) values
    ('DY-PDKS-1', 'DY PDKS 1', 'pdks'), ('DY-PDKS-2', 'DY PDKS 2', 'pdks'), ('DY-KAPI', 'DY kapı', 'kapi');

create temp table sonuc (ad text primary key, aktarim_id bigint);
grant all on sonuc to authenticated;

set role authenticated;

-- 1) Yetki ----------------------------------------------------------------
select test.dogrula('anon dosya_yukle çağıramaz',
    not has_function_privilege('anon', 'pdks.dosya_yukle(text, text, date, jsonb, text)', 'execute'));
select test.dogrula('eski 4 parametreli tanım kalmadı (tek fonksiyon)',
    test.sor($$select count(*) from pg_proc where proname = 'dosya_yukle'
               and pronamespace = 'pdks'::regnamespace$$)::int = 1);
select test.oturum('dy_amir@ornek.test');
select test.hata('amir dosya yükleyemez', 'yetkiniz yok',
    $$select pdks.dosya_yukle('pdks', 'pdks_20270301.csv', '2027-03-01',
        '[{"okuyucu": "DY-PDKS-1", "kart_no": "DY-K1", "zaman": "2027-03-01T07:50:00+03:00"}]', test.ozet('a'))$$);

select test.oturum('dy_ik@ornek.test');

-- 2) Dosya özeti ve satır sayısı ----------------------------------------------
insert into sonuc values ('ilk', pdks.dosya_yukle('pdks', ' pdks_20270301.csv ', '2027-03-01',
    '[{"okuyucu": "dy-pdks-1", "kart_no": "dy-k1", "zaman": "2027-03-01T07:50:00+03:00", "yon": "giris", "satir_no": 2},
      {"okuyucu": "DY-PDKS-1", "kart_no": "DY-K1", "zaman": "2027-03-01T16:05:00+03:00", "yon": "cikis", "satir_no": 3},
      {"okuyucu": "DY-PDKS-2", "kart_no": "DY-K2", "zaman": "2027-03-01 23:55+03:00",    "yon": "",      "satir_no": 4},
      {"okuyucu": "DY-PDKS-1", "kart_no": "DY-K1", "zaman": "2027-03-01T16:05:00+03:00", "yon": "cikis", "satir_no": 5}]',
    test.ozet('a')));
select test.dogrula('ekranın gönderdiği SHA-256 özeti yazılır (ekrandaki ön kontrol artık eşleşir)',
    (test.aktarim((select aktarim_id from sonuc where ad = 'ilk'))).dosya_ozeti = test.ozet('a'));
select test.dogrula('dosya içi tekrar bir kez yazılır, satır sayısı yazılan okutma kadar (3)',
    (test.aktarim((select aktarim_id from sonuc where ad = 'ilk'))).satir_sayisi = 3
    and test.sor('select count(*) from pdks.ham_okutma where aktarim_id = '
                 || (select aktarim_id from sonuc where ad = 'ilk'))::int = 3);
select test.dogrula('kart no ve okuyucu kodu büyük/küçük harf duyarsız, dosya adı kırpılır, boş yön boş kalır',
    test.sor($$select count(*) from pdks.ham_okutma where kart_no = 'DY-K1'$$)::int = 2
    and (test.aktarim((select aktarim_id from sonuc where ad = 'ilk'))).dosya_adi = 'pdks_20270301.csv'
    and test.sor($$select yon is null from pdks.ham_okutma where kart_no = 'DY-K2'$$)::boolean);
select test.hata('aynı özetle ikinci dosya reddedilir', 'daha önce yüklenmiş',
    $$select pdks.dosya_yukle('pdks', 'kopya.csv', '2027-03-01',
        '[{"okuyucu": "DY-PDKS-1", "kart_no": "DY-K9", "zaman": "2027-03-01T07:50:00+03:00"}]', test.ozet('a'))$$);

insert into sonuc values ('cakisan', pdks.dosya_yukle('pdks', 'pdks_20270302.csv', '2027-03-02',
    '[{"okuyucu": "DY-PDKS-2", "kart_no": "DY-K2", "zaman": "2027-03-01T23:55:00+03:00"},
      {"okuyucu": "DY-PDKS-1", "kart_no": "DY-K3", "zaman": "2027-03-02T07:45:00+03:00", "yon": "giris"}]',
    test.ozet('b')));
select test.dogrula('önceki dosyada gelmiş okutma atlanır ve sayılmaz (1)',
    (test.aktarim((select aktarim_id from sonuc where ad = 'cakisan'))).satir_sayisi = 1);

insert into sonuc values ('hepsi_var', pdks.dosya_yukle('pdks', 'pdks_20270303.csv', '2027-03-03',
    '[{"okuyucu": "DY-PDKS-1", "kart_no": "DY-K3", "zaman": "2027-03-02T07:45:00+03:00", "yon": "giris"}]',
    test.ozet('c')));
select test.dogrula('okutmaların tamamı önceden gelmişse aktarım 0 satırla kaydedilir (gece işi günü tam sayar)',
    (test.aktarim((select aktarim_id from sonuc where ad = 'hepsi_var'))).satir_sayisi = 0
    and test.sor($$select pdks.pdks_verisi_tam_mi('2027-03-03 00:00+03', '2027-03-03 23:59+03')$$)::boolean);

insert into sonuc values ('kapi', pdks.dosya_yukle('kapi', 'kapi_20270301.csv', '2027-03-01',
    '[{"okuyucu": "DY-KAPI", "kart_no": "DY-K1", "zaman": "2027-03-01T07:44:00+03:00", "yon": "giris"}]',
    test.ozet('a')));
select test.dogrula('aynı özet başka kaynakta serbest; kapı dosyası kanıt kaydına yazılır',
    test.sor('select count(*) from pdks.kanit_kaydi where kaynak = ''kapi'' and aktarim_id = '
             || (select aktarim_id from sonuc where ad = 'kapi'))::int = 1);

-- 3) Eski çağrı biçimi (özetsiz) çalışmaya devam eder ---------------------------
insert into sonuc values ('ozetsiz', pdks.dosya_yukle('pdks', 'eski.csv', '2027-03-04',
    '[{"okuyucu": "DY-PDKS-1", "kart_no": "DY-K1", "zaman": "2027-03-04T07:50:00+03:00", "yon": "giris"}]'));
select test.dogrula('özet verilmezse satırların md5 özeti kullanılır',
    (test.aktarim((select aktarim_id from sonuc where ad = 'ozetsiz'))).dosya_ozeti
    = md5('[{"okuyucu": "DY-PDKS-1", "kart_no": "DY-K1", "zaman": "2027-03-04T07:50:00+03:00", "yon": "giris"}]'::jsonb::text));

-- 4) Hatalı girdiler: hiçbiri satır yazmamalı ------------------------------------
create temp table onceki as
select test.sor('select count(*) from pdks.aktarim')::int as aktarim,
       test.sor('select count(*) from pdks.ham_okutma')::int as ham,
       test.sor('select count(*) from pdks.kanit_kaydi')::int as kanit;

select test.hata('kaynağa ait olmayan okuyucu satır numarasıyla bildirilir', 'Okuyucu tanımlı değil ya da bu kaynağa ait değil: DY-PDKS-1 (7. satır)',
    $$select pdks.dosya_yukle('kapi', 'kapi_20270305.csv', '2027-03-05',
        '[{"okuyucu": "DY-KAPI",   "kart_no": "DY-K1", "zaman": "2027-03-05T07:44:00+03:00", "satir_no": 6},
          {"okuyucu": "DY-PDKS-1", "kart_no": "DY-K1", "zaman": "2027-03-05T07:50:00+03:00", "satir_no": 7}]', test.ozet('e'))$$);
select test.hata('boş okuyucu reddedilir', 'Okuyucu tanımlı değil',
    $$select pdks.dosya_yukle('pdks', 'p.csv', '2027-03-05',
        '[{"kart_no": "DY-K1", "zaman": "2027-03-05T07:50:00+03:00"}]', test.ozet('e'))$$);
select test.hata('geçersiz kart numarası reddedilir', '1. satırda kart numarası',
    $$select pdks.dosya_yukle('pdks', 'p.csv', '2027-03-05',
        '[{"okuyucu": "DY-PDKS-1", "kart_no": "DY K1; drop", "zaman": "2027-03-05T07:50:00+03:00"}]', test.ozet('e'))$$);
select test.hata('geçersiz yön reddedilir', 'yön',
    $$select pdks.dosya_yukle('pdks', 'p.csv', '2027-03-05',
        '[{"okuyucu": "DY-PDKS-1", "kart_no": "DY-K1", "zaman": "2027-03-05T07:50:00+03:00", "yon": "yukari"}]', test.ozet('e'))$$);
select test.hata('saat dilimi olmayan zaman reddedilir', 'zaman bilgisi geçersiz',
    $$select pdks.dosya_yukle('pdks', 'p.csv', '2027-03-05',
        '[{"okuyucu": "DY-PDKS-1", "kart_no": "DY-K1", "zaman": "2027-03-05 07:50"}]', test.ozet('e'))$$);
select test.hata('olmayan tarih (31 Şubat) anlaşılır mesajla reddedilir', 'zaman okunamadı',
    $$select pdks.dosya_yukle('pdks', 'p.csv', '2027-03-05',
        '[{"okuyucu": "DY-PDKS-1", "kart_no": "DY-K1", "zaman": "2027-02-31T07:50:00+03:00"}]', test.ozet('e'))$$);
select test.hata('nesne olmayan satır reddedilir', 'satır okunamadı',
    $$select pdks.dosya_yukle('pdks', 'p.csv', '2027-03-05', '["metin"]', test.ozet('e'))$$);
select test.hata('geçersiz dosya özeti reddedilir', 'Dosya doğrulanamadı',
    $$select pdks.dosya_yukle('pdks', 'p.csv', '2027-03-05',
        '[{"okuyucu": "DY-PDKS-1", "kart_no": "DY-K1", "zaman": "2027-03-05T07:50:00+03:00"}]', 'abc')$$);
select test.hata('geçersiz dosya türü reddedilir', 'Dosya türü geçersiz',
    $$select pdks.dosya_yukle('turnike', 'p.csv', '2027-03-05',
        '[{"okuyucu": "DY-PDKS-1", "kart_no": "DY-K1", "zaman": "2027-03-05T07:50:00+03:00"}]', test.ozet('e'))$$);
select test.hata('boş dosya adı reddedilir', 'Dosya adı boş',
    $$select pdks.dosya_yukle('pdks', '  ', '2027-03-05',
        '[{"okuyucu": "DY-PDKS-1", "kart_no": "DY-K1", "zaman": "2027-03-05T07:50:00+03:00"}]', test.ozet('e'))$$);
select test.hata('günü olmayan dosya reddedilir', 'gün boş',
    $$select pdks.dosya_yukle('pdks', 'p.csv', null,
        '[{"okuyucu": "DY-PDKS-1", "kart_no": "DY-K1", "zaman": "2027-03-05T07:50:00+03:00"}]', test.ozet('e'))$$);
select test.hata('boş liste reddedilir', 'Dosyada satır yok',
    $$select pdks.dosya_yukle('pdks', 'p.csv', '2027-03-05', '[]', test.ozet('e'))$$);

select test.dogrula('hatalı denemelerin hiçbiri satır yazmadı',
    (select test.sor('select count(*) from pdks.aktarim')::int = aktarim
            and test.sor('select count(*) from pdks.ham_okutma')::int = ham
            and test.sor('select count(*) from pdks.kanit_kaydi')::int = kanit from onceki));

reset role;
do $$ begin raise notice 'DOSYA YÜKLEME TESTLERİ GEÇTİ'; end $$;
rollback;
