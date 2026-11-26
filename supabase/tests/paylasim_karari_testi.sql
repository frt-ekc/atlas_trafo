-- =====================================================================
-- Kart paylaşımı şüphesinde İK kararı testleri (20261231130000_paylasim_karari.sql, T-81)
-- Testin kendi sahte verisi (Ekim 2026); örnek veri yüklü olsun olmasın çalışır.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/paylasim_karari_testi.sql
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
create function test.oturum(p_eposta text) returns void language sql security definer as $$
    select set_config('request.jwt.claims',
        json_build_object('sub', (select auth_kullanici_id from pdks.kullanici where eposta = p_eposta),
                          'role', 'authenticated')::text, true);
$$;
create function test.c(p text) returns bigint language sql security definer as $$
    select id from pdks.calisan where sicil_no = p $$;
create function test.k(p text) returns bigint language sql security definer as $$
    select id from pdks.kullanici where eposta = p $$;
create function test.ts(p text) returns timestamptz language sql immutable as $$
    select (p::timestamp) at time zone 'Europe/Istanbul' $$;
create function test.plan(p_sicil text, p_gun date) returns pdks.fazla_mesai_plani language sql security definer as $$
    select * from pdks.fazla_mesai_plani where calisan_id = test.c(p_sicil) and is_gunu = p_gun $$;
create function test.hv(p_sicil text, p_gun date) returns pdks.fazla_mesai_inceleme language sql security definer as $$
    select * from pdks.fazla_mesai_inceleme where calisan_id = test.c(p_sicil) and is_gunu = p_gun $$;
create function test.kilit(p_yil int, p_ay int) returns jsonb language sql security definer as $$
    select z.ozet from pdks.donem_kilit_izi z join pdks.donem d on d.id = z.donem_id
    where d.yil = p_yil and d.ay = p_ay order by z.kilit_zamani desc limit 1 $$;
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

create function test.uy(p_sicil text) returns pdks.uyari language sql security definer as $$
    select * from pdks.uyari where tur = 'kart_paylasim_suphesi' and calisan_id = test.c(p_sicil) $$;
create temp table kp_sonuc (ad text primary key, sonuc jsonb);
grant all on kp_sonuc to authenticated;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
--   KP01 – KP02: kartları 12–16 Ekim'de her sabah aynı okuyucuda 4 sn arayla okutuldu (paylaşım şüphesi)
--   KP03 – KP04: aynı şekilde 12–16 Ekim; sonra 19–20 Ekim'de de (karar verilmeden yeni günler eklenir)
--   KP02 aynı zamanda İK kullanıcısıdır (kendi şüphesine karar veremez). KPI1: kararı veren İK. KPA1: amir.
insert into pdks.departman (ad) values ('KP Üretim'), ('KP İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = case when s in ('KP02','KPI1') then 'KP İdari' else 'KP Üretim' end), '2025-01-01'
from unnest(array['KP01','KP02','KP03','KP04','KPI1','KPA1']) s;
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('x', 'kp_ik@ornek.test',   'ik',   test.c('KPI1'), '00000000-0000-0000-0000-000000000ea1'),
    ('x', 'kp_ik2@ornek.test',  'ik',   test.c('KP02'), '00000000-0000-0000-0000-000000000ea2'),
    ('x', 'kp_amir@ornek.test', 'amir', test.c('KPA1'), '00000000-0000-0000-0000-000000000ea3');
insert into pdks.kart (kart_no, calisan_id) select 'KP-' || s, test.c(s) from unnest(array['KP01','KP02','KP03','KP04']) s;
insert into pdks.okuyucu (kod, ad, sistem) values ('KP-GIRIS', 'KP giriş', 'pdks');
insert into pdks.aktarim (kaynak, dosya_adi, dosya_ozeti, veri_tarihi) values ('pdks', 'kp.csv', 'kp-ozet', '2026-10-12');
insert into pdks.ham_okutma (aktarim_id, okuyucu_id, kart_no, okutma_zamani, yon)
select (select id from pdks.aktarim where dosya_ozeti = 'kp-ozet'), (select id from pdks.okuyucu where kod = 'KP-GIRIS'),
       'KP-' || x.s, test.ts(g::date || ' ' || x.saat), 'giris'
from generate_series('2026-10-12'::date, '2026-10-16', interval '1 day') g,
     (values ('KP01', '07:58:00'), ('KP02', '07:58:04'), ('KP03', '07:40:00'), ('KP04', '07:40:04')) x(s, saat);

-- 1) Uyarı günleri, saatleri ve okuyucuyu söyler; ayrıntı saklanır -----------------------------
select pdks.kart_paylasim_kontrol('2026-10-16');
select test.dogrula('uyarı mesajı günleri, saati ve okuyucuyu yazıyor',
    (test.uy('KP01')).mesaj like '%5 farklı günde%' and (test.uy('KP01')).mesaj like '%12.10 07:58 (KP-GIRIS)%'
    and (test.uy('KP01')).mesaj like '%16.10 07:58 (KP-GIRIS)%');
select test.dogrula('ayrıntıda diğer çalışan ve 5 gün var',
    ((test.uy('KP01')).ayrinti ->> 'diger_calisan_id')::bigint = test.c('KP02')
    and jsonb_array_length((test.uy('KP01')).ayrinti -> 'gunler') = 5);

-- 2) Karar verilmeden yeni günler gelirse uyarı güncellenir, yeni uyarı açılmaz ---------------
insert into pdks.ham_okutma (aktarim_id, okuyucu_id, kart_no, okutma_zamani, yon)
select (select id from pdks.aktarim where dosya_ozeti = 'kp-ozet'), (select id from pdks.okuyucu where kod = 'KP-GIRIS'),
       'KP-' || x.s, test.ts(g || ' ' || x.saat), 'giris'
from unnest(array['2026-10-19', '2026-10-20']) g, (values ('KP03', '07:40:00'), ('KP04', '07:40:04')) x(s, saat);
select test.dogrula('yeniden çalışınca yeni uyarı sayılmaz (0)', pdks.kart_paylasim_kontrol('2026-10-20') = 0);
select test.dogrula('karar bekleyen uyarı 7 güne güncellendi; tek uyarı',
    (test.uy('KP03')).mesaj like '%7 farklı günde%' and jsonb_array_length((test.uy('KP03')).ayrinti -> 'gunler') = 7
    and (select count(*) = 1 from pdks.uyari where tur = 'kart_paylasim_suphesi' and calisan_id = test.c('KP03')));

-- 3) Kararı yalnızca İK verir; gerekçe zorunlu; ilgili iki çalışan da karar veremez -------------
select pdks.uyari_yaz('dosya_gelmedi', 'kp-test', 'Test uyarısı');
set local role authenticated;
select test.oturum('kp_amir@ornek.test');
select test.hata('amir karar veremez', 'yetkiniz yok',
    $$select pdks.kart_paylasim_karar((test.uy('KP01')).id, true, 'Kamerada görüldü, Ad KP01 okuttu')$$);
select test.oturum('kp_ik2@ornek.test');
select test.hata('şüpheli çiftteki İK (KP02) karar veremez', 'Görevler ayrılığı',
    $$select pdks.kart_paylasim_karar((test.uy('KP01')).id, false, 'Yanlış alarm, sırada arka arkaya geldik')$$);
select test.oturum('kp_ik@ornek.test');
select test.hata('gerekçesiz karar verilmez', 'gerekçe',
    $$select pdks.kart_paylasim_karar((test.uy('KP01')).id, true, 'kısa')$$);
select test.hata('başka türdeki uyarıya paylaşım kararı verilmez', 'yalnızca kart paylaşımı',
    $$select pdks.kart_paylasim_karar((select max(id) from pdks.uyari where tekillik_anahtari = 'kp-test'),
                                       true, 'Gerekçe yazıldı burada')$$);

-- 4) "Paylaşım var" kararı: kaydedilir, günler listelenir, gün kaydı kendiliğinden değişmez -----
insert into kp_sonuc select 'var', pdks.kart_paylasim_karar((test.uy('KP01')).id, true, 'Kamera kaydı: KP01 iki kartı birlikte okuttu');
insert into kp_sonuc select 'yok', pdks.kart_paylasim_karar((test.uy('KP03')).id, false, 'Aynı serviste geliyorlar, sırayla okuttular');
reset role;
select test.dogrula('karar, gerekçe, veren ve zaman kaydedildi; uyarı görüldü sayıldı',
    (select karar = 'paylasim_var' and karar_gerekce like 'Kamera kaydı%' and karar_veren_id = test.k('kp_ik@ornek.test')
            and karar_zamani is not null and goruldu and goren_id = test.k('kp_ik@ornek.test')
     from test.uy('KP01')));
select test.dogrula('"var" sonucu düzeltilecek günleri listeler ve devamsızlığın yazılmadığını söyler',
    (select jsonb_array_length(sonuc -> 'gunler') = 5 and sonuc ->> 'mesaj' like '%elle%'
     from kp_sonuc where ad = 'var'));
select test.dogrula('karar gün kaydı ya da düzeltme yazmadı (çalışan aleyhine karar İK''nın elle düzeltmesiyle)',
    not exists (select 1 from pdks.duzeltme where calisan_id in (test.c('KP01'), test.c('KP02'))));
select test.dogrula('"yok" kararı (yanlış alarm) kaydedildi',
    (test.uy('KP03')).karar = 'yanlis_alarm');

-- 5) Karar bir kez verilir, değiştirilemez; karar verilmiş uyarı yeni günlerle güncellenmez -----
set local role authenticated;
select test.oturum('kp_ik@ornek.test');
select test.hata('ikinci karar verilmez', 'zaten karar verilmiş',
    $$select pdks.kart_paylasim_karar((test.uy('KP01')).id, false, 'Fikir değiştirdim, yanlış alarm')$$);
reset role;
select test.hata('karar doğrudan da değiştirilemez', 'Kart paylaşımı kararı değiştirilemez',
    $$update pdks.uyari set karar = 'yanlis_alarm' where id = (test.uy('KP01')).id$$);
insert into pdks.ham_okutma (aktarim_id, okuyucu_id, kart_no, okutma_zamani, yon)
select (select id from pdks.aktarim where dosya_ozeti = 'kp-ozet'), (select id from pdks.okuyucu where kod = 'KP-GIRIS'),
       'KP-' || x.s, test.ts('2026-10-21 ' || x.saat), 'giris'
from (values ('KP01', '07:58:00'), ('KP02', '07:58:04')) x(s, saat);
select pdks.kart_paylasim_kontrol('2026-10-21');
select test.dogrula('karar verilmiş uyarının mesajı ve günleri değişmedi (5 gün)',
    jsonb_array_length((test.uy('KP01')).ayrinti -> 'gunler') = 5 and (test.uy('KP01')).mesaj like '%5 farklı günde%');

do $$ begin raise notice 'TÜM TESTLER GEÇTİ'; end $$;
rollback;
