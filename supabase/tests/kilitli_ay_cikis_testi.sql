-- =====================================================================
-- Kilitli aya düşen işten çıkış testleri (20261231090000_kilitli_ay_cikis.sql, T-67)
-- Testin kendi sahte verisi (Eylül–Ekim 2026); örnek veri yüklü olsun olmasın çalışır.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/kilitli_ay_cikis_testi.sql
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

create function test.uyari(p_sicil text) returns text language sql security definer as $$
    select string_agg(mesaj, ' | ' order by id) from pdks.uyari where tur = 'cikis_kilitli_ay' and calisan_id = test.c(p_sicil) $$;
create function test.planlar(p_sicil text) returns text language sql security definer as $$
    select string_agg(to_char(tarih, 'DD.MM'), ',' order by tarih) from pdks.vardiya_plani where calisan_id = test.c(p_sicil) $$;
create temp table ck_sonuc (s text, sonuc jsonb) on commit drop;
grant all on ck_sonuc to authenticated;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
--   CK01 (Ahmet): 14–18 Eylül GÜNDÜZ planlı; 14, 15 Eylül çalıştı, 16–18 gelmedi (haber vermeden bıraktı).
--         21–22 Eylül yıllık izni (planı yok), 1–2 Ekim planı ve 12–13 Ekim izni var. Eylül kilitlenir,
--         çıkış Ekim'de 15.09 olarak girilir.
--   CK02: çıkış açık aya düşer (5 Ekim); 6–7 Ekim planı, 12 Ekim izni → eskisi gibi silinir / iptal, uyarı yok
insert into pdks.departman (ad) values ('CK Üretim'), ('CK İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = case when s like 'CKI%' then 'CK İdari' else 'CK Üretim' end), '2025-01-01'
from unnest(array['CK01','CK02','CKI1']) s;
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('CK İK', 'ck_ik@ornek.test', 'ik', test.c('CKI1'), '00000000-0000-0000-0000-0000000009a1');
insert into pdks.kart (kart_no, calisan_id) values ('CK-CK01', test.c('CK01')), ('CK-CK02', test.c('CK02'));
insert into pdks.okuyucu (kod, ad, sistem) values ('CK-PDKS', 'CK PDKS', 'pdks');
insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id, giren_id)
select test.c(s), d::date, (select id from pdks.vardiya_tanim where kod = 'GUNDUZ'), test.k('ck_ik@ornek.test')
from (select 'CK01' s, d from generate_series('2026-09-14'::date, '2026-09-18', interval '1 day') d
      union all select 'CK01', d from generate_series('2026-10-01'::date, '2026-10-02', interval '1 day') d
      union all select 'CK02', d from generate_series('2026-10-06'::date, '2026-10-07', interval '1 day') d) x;
insert into pdks.izin (calisan_id, tur, baslangic, bitis, giren_id) values
    (test.c('CK01'), 'yillik', '2026-09-21', '2026-09-22', test.k('ck_ik@ornek.test')),
    (test.c('CK01'), 'yillik', '2026-10-12', '2026-10-13', test.k('ck_ik@ornek.test')),
    (test.c('CK02'), 'yillik', '2026-10-12', '2026-10-12', test.k('ck_ik@ornek.test'));
insert into pdks.aktarim (kaynak, dosya_adi, dosya_ozeti, veri_tarihi)
select 'pdks', 'ck_' || d::date || '.csv', 'ck-' || d::date, d::date from generate_series('2026-09-14'::date, '2026-09-18', interval '1 day') d;
insert into pdks.ham_okutma (aktarim_id, okuyucu_id, kart_no, okutma_zamani, yon)
select (select id from pdks.aktarim where dosya_ozeti = 'ck-' || g), (select id from pdks.okuyucu where kod = 'CK-PDKS'), 'CK-CK01', test.ts(g || ' ' || x.s), x.y
from unnest(array['2026-09-14', '2026-09-15']) g, (values ('08:00', 'giris'), ('17:00', 'cikis')) x(s, y);
set local pdks.test_bugun = '2026-10-15';
select pdks.gece_isi_calistir(d::date) from generate_series('2026-09-14'::date, '2026-09-18', interval '1 day') d;
set local role authenticated;
select test.oturum('ck_ik@ornek.test');
select pdks.ay_kilitle(2026::smallint, 9::smallint, true, 'Test: zorla kilit gerekçesi');
reset role;
select test.dogrula('hazırlık: Eylül kilitli; 16–18 Eylül soru bekliyor, planları duruyor',
    pdks.donem_kilitli_mi('2026-09-16') and test.planlar('CK01') = '14.09,15.09,16.09,17.09,18.09,01.10,02.10'
    and (select count(*) = 3 from pdks.gun_kaydi where calisan_id = test.c('CK01') and durum = 'soru_bekliyor'));

-- 1) Çıkış kilitli aya düşer: kilitli ayın planı ve izni değişmez, açık ayınki eskisi gibi ---------
set local role authenticated;
select test.oturum('ck_ik@ornek.test');
insert into ck_sonuc select 'CK01', pdks.isten_cikis_gir(test.c('CK01'), '2026-09-15', 'Haber vermeden bıraktı');
reset role;
select test.dogrula('kilitli Eylül''ün 16–18 planları silinmedi; açık Ekim''in 1–2 planları silindi',
    test.planlar('CK01') = '14.09,15.09,16.09,17.09,18.09');
select test.dogrula('kilitli Eylül''deki 21–22 izni iptal edilmedi; Ekim''deki 12–13 izni iptal edildi',
    (select iptal_zamani is null from pdks.izin where calisan_id = test.c('CK01') and baslangic = '2026-09-21')
    and (select iptal_zamani is not null from pdks.izin where calisan_id = test.c('CK01') and baslangic = '2026-10-12'));
select test.dogrula('kilitli günler değişmedi, "vardiya yok" düzeltmesi Ekim''e fark satırı olarak yazıldı (3 gün)',
    (select count(*) = 3 from pdks.gun_kaydi where calisan_id = test.c('CK01') and durum = 'soru_bekliyor')
    and (select count(*) = 3 and bool_and(d.fark_satiri) and bool_and(p.yil = 2026 and p.ay = 10)
         from pdks.duzeltme d join pdks.donem p on p.id = d.hedef_donem_id
         where d.calisan_id = test.c('CK01') and d.alan = 'durum' and d.yeni_deger = 'vardiya_yok'));
select test.dogrula('çıkış sonucu: 2 plan silindi, 1 izin iptal, kilitli ayda 3 plan ve 1 izin kaldı',
    (select (sonuc ->> 'silinen_plan')::int = 2 and (sonuc ->> 'iptal_edilen_izin')::int = 1
            and (sonuc ->> 'kilitli_ayda_kalan_plan')::int = 3 and (sonuc ->> 'kilitli_ayda_kalan_izin')::int = 1
            and sonuc ->> 'kilitli_ay_uyarisi' like '%09/2026%'
     from ck_sonuc where s = 'CK01'));
select test.dogrula('İK''ya "çıkış kilitli aya düşüyor" uyarısı yazıldı (ay, plan ve izin sayısı, elle düzeltme)',
    test.uyari('CK01') like '%15.09.2026%' and test.uyari('CK01') like '%09/2026%'
    and test.uyari('CK01') like '%3 vardiya planı%' and test.uyari('CK01') like '%1 izin%'
    and test.uyari('CK01') like '%bordroda elle%');

-- 2) Çıkış açık aya düşer: eskisi gibi, uyarı yok --------------------------------------------
set local role authenticated;
select test.oturum('ck_ik@ornek.test');
insert into ck_sonuc select 'CK02', pdks.isten_cikis_gir(test.c('CK02'), '2026-10-05', 'İstifa');
reset role;
select test.dogrula('açık ayda çıkış: planlar silindi, izin iptal, kilitli ay sayıları 0, uyarı yok',
    test.planlar('CK02') is null
    and (select iptal_zamani is not null from pdks.izin where calisan_id = test.c('CK02'))
    and (select (sonuc ->> 'silinen_plan')::int = 2 and (sonuc ->> 'kilitli_ayda_kalan_plan')::int = 0
                and (sonuc ->> 'kilitli_ayda_kalan_izin')::int = 0 and sonuc ->> 'kilitli_ay_uyarisi' is null
         from ck_sonuc where s = 'CK02')
    and test.uyari('CK02') is null);

-- 3) Kilitli ayın vardiya planı hiçbir yoldan silinemez -----------------------------------------
select test.hata('kilitli ayın planı doğrudan da silinemez', 'Kilitli ayın vardiya planı silinemez',
    $$delete from pdks.vardiya_plani where calisan_id = test.c('CK01') and tarih = '2026-09-16'$$);
select test.dogrula('ekran kullanıcısı vardiya planını doğrudan silemez (yalnızca fonksiyonlarla)',
    not has_table_privilege('authenticated', 'pdks.vardiya_plani', 'delete'));

do $$ begin raise notice 'TÜM TESTLER GEÇTİ'; end $$;
rollback;
