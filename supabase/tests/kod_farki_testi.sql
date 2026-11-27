-- =====================================================================
-- Yalnızca kodu değişen fark testleri (20261231190000_puantaj_kalanlari.sql, T-95)
-- Testin kendi sahte verisi (Eylül–Ekim 2026); örnek veri yüklü olsun olmasın çalışır.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/kod_farki_testi.sql
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

grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
--   KF01 (Ahmet): 14–18 Eylül GÜNDÜZ; 14, 15 Eylül çalıştı, 16–18 gelmedi. Eylül zorla kilitlenir
--         (16–18 kodsuz girer), çıkış 15.09 girilir → 16–18 "vardiya yok" düzeltmesi Ekim'e fark olur.
--   Ekim kilitlenince fark satırı ve HT 3 gün kalemi yazılmalı (yalnızca kod değişti, sayılar 0).
insert into pdks.departman (ad) values ('KF Üretim'), ('KF İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = case when s like 'KFI%' then 'KF İdari' else 'KF Üretim' end), '2025-01-01'
from unnest(array['KF01','KFI1']) s;
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('x', 'kf_ik@ornek.test', 'ik', test.c('KFI1'), '00000000-0000-0000-0000-000000000ff1');
insert into pdks.kart (kart_no, calisan_id) values ('KF-KF01', test.c('KF01'));
insert into pdks.okuyucu (kod, ad, sistem) values ('KF-PDKS', 'KF PDKS', 'pdks');
insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id, giren_id)
select test.c('KF01'), d::date, (select id from pdks.vardiya_tanim where kod = 'GUNDUZ'), test.k('kf_ik@ornek.test')
from generate_series('2026-09-14'::date, '2026-09-18', interval '1 day') d;
insert into pdks.aktarim (kaynak, dosya_adi, dosya_ozeti, veri_tarihi)
select 'pdks', 'kf_' || d::date || '.csv', 'kf-' || d::date, d::date from generate_series('2026-09-14'::date, '2026-09-18', interval '1 day') d;
insert into pdks.ham_okutma (aktarim_id, okuyucu_id, kart_no, okutma_zamani, yon)
select (select id from pdks.aktarim where dosya_ozeti = 'kf-' || g), (select id from pdks.okuyucu where kod = 'KF-PDKS'), 'KF-KF01', test.ts(g || ' ' || x.s), x.y
from unnest(array['2026-09-14', '2026-09-15']) g, (values ('08:00', 'giris'), ('17:00', 'cikis')) x(s, y);
set local pdks.test_bugun = '2026-11-15';
select pdks.gece_isi_calistir(d::date) from generate_series('2026-09-14'::date, '2026-09-18', interval '1 day') d;
set local role authenticated;
select test.oturum('kf_ik@ornek.test');
select pdks.ay_kilitle(2026::smallint, 9::smallint, true, 'Test: zorla kilit gerekçesi');
select pdks.isten_cikis_gir(test.c('KF01'), '2026-09-15', 'Haber vermeden bıraktı');
select pdks.ay_kilitle(2026::smallint, 10::smallint, true, 'Test: zorla kilit gerekçesi');
reset role;

select test.dogrula('Eylül kilitli puantajında 16–18 kodsuz (hazırlık)',
    (select coalesce(sum(k.gun), 0) = 2 from pdks.puantaj_kalemi k join pdks.puantaj_satiri s on s.id = k.puantaj_satiri_id
     join pdks.donem d on d.id = s.donem_id
     where s.calisan_id = test.c('KF01') and d.yil = 2026 and d.ay = 9 and s.satir_turu = 'normal' and k.kod = 'NÇ'));
select test.dogrula('Ekim kilidinde Eylül kaynaklı fark satırı yazıldı (sayılar 0, yalnızca kod değişti)',
    exists (select 1 from pdks.puantaj_satiri s join pdks.donem d on d.id = s.donem_id
            join pdks.donem k on k.id = s.kaynak_donem_id
            where s.calisan_id = test.c('KF01') and d.yil = 2026 and d.ay = 10 and s.satir_turu = 'fark'
              and k.ay = 9 and s.calisilan_gun = 0 and s.calisma_dk = 0));
select test.dogrula('fark satırının kalemi: HT 3 gün (16–18 Eylül artık kodsuz değil)',
    (select string_agg(k.kod || ' ' || k.gun, ', ') = 'HT 3.0'
     from pdks.puantaj_kalemi k join pdks.puantaj_satiri s on s.id = k.puantaj_satiri_id
     join pdks.donem d on d.id = s.donem_id
     where s.calisan_id = test.c('KF01') and d.yil = 2026 and d.ay = 10 and s.satir_turu = 'fark'));
select test.dogrula('ERP aktarımında da görünüyor (Ekim fark, HT 3)',
    exists (select 1 from pdks.v_puantaj_aktarim where sicil = 'KF01' and donem = '2026-10' and satir_turu = 'fark' and kod = 'HT' and gun = 3));

do $$ begin raise notice 'TÜM TESTLER GEÇTİ'; end $$;
rollback;
