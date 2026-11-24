-- =====================================================================
-- Kodsuz gün kilidi durdurur (20261209010000_kodsuz_gun.sql, T-90, T-101)
--   * Puantaja kodsuz girecek gün varsa zorlamadan kilit reddedilir; hata
--     günleri adıyla söyler (sicil, gün, neden). En çok 10 gün yazılır.
--   * Zorla kilit kabul edilir; kodsuz günler "Zorla geçilenler"e ve özetin
--     kodsuz_gun_listesi alanına yazılır.
--   * Kodsuz gün yoksa kilit eskisi gibi; liste boş.
-- Tarih sabit: bugün 15.01.2027 kabul edilir (pdks.test_bugun).
--
-- Testin kendi sahte verisi kullanılır (Ağustos – Ekim 2026; örnek veride bu
-- aylara ait kayıt yok). Her şey tek işlemde çalışır ve sonda geri alınır.
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/kodsuz_gun_testi.sql
-- =====================================================================
\pset tuples_only on
\pset format unaligned
begin;
set local timezone = 'Europe/Istanbul';
set local pdks.test_bugun = '2027-01-15';

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
create function test.kilit(p_yil int, p_ay int, p_zorla boolean) returns jsonb language sql as $$
    select pdks.ay_kilitle(p_yil::smallint, p_ay::smallint, p_zorla) $$;
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
--   KG01: 9 Ekim "eksik" (ör. amir yalnızca giriş saatini girdi, soru kapandı)
--   KG02: Ağustos'ta 11 gün "eksik" (listenin 10 günle sınırlandığını görmek için)
--   KG03: Eylül'de tamamlanmış, hesaplanmış bir gün (kodsuz gün yok)
insert into pdks.departman (ad) values ('KG Üretim'), ('KG İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = d), '2025-01-01'
from (values ('KG01', 'KG Üretim'), ('KG02', 'KG Üretim'), ('KG03', 'KG Üretim'), ('KGI1', 'KG İdari')) v(s, d);
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id)
values ('KG İK', 'kg_ik@ornek.test', 'ik', test.c('KGI1'), '00000000-0000-0000-0000-0000000090b1');
insert into pdks.gun_kaydi (calisan_id, is_gunu, vardiya_id, durum, giris_zamani)
values (test.c('KG01'), '2026-10-09', 1, 'eksik', '2026-10-09 07:58+03');
insert into pdks.gun_kaydi (calisan_id, is_gunu, vardiya_id, durum, giris_zamani)
select test.c('KG02'), g::date, 1, 'eksik', (g::date || ' 07:55+03')::timestamptz
from generate_series('2026-08-03'::date, '2026-08-13'::date, '1 day') g;
insert into pdks.gun_kaydi (calisan_id, is_gunu, vardiya_id, durum, planli_baslangic, planli_bitis,
                            giris_zamani, cikis_zamani)
values (test.c('KG03'), '2026-09-15', 1, 'tamam', '2026-09-15 08:00+03', '2026-09-15 17:00+03',
        '2026-09-15 07:55+03', '2026-09-15 17:05+03');
select pdks.gun_hesapla(id) from pdks.gun_kaydi where calisan_id = test.c('KG03') \g /dev/null

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000090b1","role":"authenticated"}', true) \g /dev/null
set local role authenticated;

-- 1) Zorlamadan: kodsuz gün kilidi durdurur, günleri adıyla söyler -----------
select test.hata('Ekim: 1 kodsuz gün varken zorlamadan kilit reddedilir',
    '10/2026 döneminde 1 gün puantaja kodsuz girecek: KG01 09.10.2026 (eksik)',
    'select test.kilit(2026, 10, false)');
select test.dogrula('Ekim kilitlenmedi',
    not exists (select 1 from pdks.donem where yil = 2026 and ay = 10 and durum = 'kilitli'));
select test.hata('Ağustos: 11 kodsuz gün; hata ilk 10 günü yazar, kalanını sayar',
    '8/2026 döneminde 11 gün puantaja kodsuz girecek: KG02 03.08.2026 (eksik)',
    'select test.kilit(2026, 8, false)');
select test.hata('Ağustos: "ve 1 gün daha" ile biter (en çok 10 gün listelenir)',
    'KG02 12.08.2026 (eksik) ve 1 gün daha',
    'select test.kilit(2026, 8, false)');

-- 2) Zorla: kilit olur, kodsuz günler özete yazılır --------------------------
create temp table ozet as select test.kilit(2026, 10, true) as r;
select test.dogrula('Ekim zorla kilitlendi',
    exists (select 1 from pdks.donem where yil = 2026 and ay = 10 and durum = 'kilitli'));
select test.dogrula('özet: kodsuz_gun 1, liste KG01 9 Ekim (eksik)',
    (select r -> 'kodsuz_gun' = '1'
        and r -> 'kodsuz_gun_listesi' = '[{"sicil": "KG01", "gun": "2026-10-09", "durum": "eksik", "neden": "eksik"}]'::jsonb
     from ozet));
select test.dogrula('özet mesajı: kodsuz gün "Zorla geçilenler" arasında',
    (select r ->> 'mesaj' = '10/2026 kilitlendi. Zorla geçilenler: 1 kodsuz gün.' from ozet));

-- 3) Kodsuz gün yok: kilit eskisi gibi -------------------------------------
create temp table ozet_eylul as select test.kilit(2026, 9, false) as r;
select test.dogrula('Eylül: kodsuz gün yok, zorlamadan kilitlendi, liste boş',
    (select r -> 'kodsuz_gun' = '0' and r -> 'kodsuz_gun_listesi' = '[]'::jsonb
        and r ->> 'mesaj' = '9/2026 kilitlendi.' from ozet_eylul));
reset role;

select 'Kodsuz gün testi: hepsi GEÇTİ';
rollback;
