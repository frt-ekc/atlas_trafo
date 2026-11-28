-- =====================================================================
-- İSG belgesi sırası ve tarih aralığı testleri (20261231150000_isg_belge_sirasi.sql, T-87)
-- Testin kendi sahte verisi (Kasım 2026); örnek veri yüklü olsun olmasın çalışır.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/isg_belge_sirasi_testi.sql
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

create function test.durum(p_sicil text, p_tur text) returns text language sql security definer as $$
    select durum || ' ' || coalesce(to_char(gecerlilik_bitis, 'YYYY-MM-DD'), '-') || ' ' || izleniyor
    from pdks.v_isg_durum where sicil_no = p_sicil and tur = p_tur $$;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
-- Bugün 20 Kasım 2026. IS01 (mavi yaka): 2027'ye kadar geçerli eğitim belgesi var; sonra eski tarihli
-- (01.01.2026) bir belge girilir. IS02 (beyaz yaka): izlenmez.
insert into pdks.departman (ad, yaka) values ('IS Üretim', 'mavi'), ('IS İdari', 'beyaz');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = case when s = 'IS01' then 'IS Üretim' else 'IS İdari' end), '2025-01-01'
from unnest(array['IS01','IS02','ISU1']) s;
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('x', 'is_isg@ornek.test', 'isg', test.c('ISU1'), '00000000-0000-0000-0000-000000000fb1');
insert into pdks.kart (kart_no, calisan_id) values ('IS-K1', test.c('IS01'));
insert into pdks.okuyucu (kod, ad, sistem) values ('IS-PDKS', 'IS PDKS', 'pdks');
set local pdks.test_bugun = '2026-11-20';
set local role authenticated;
select test.oturum('is_isg@ornek.test');
select pdks.isg_belge_gir(test.c('IS01'), 'isg_egitimi', '2027-06-30', 'IS-E1');
select pdks.isg_belge_gir(test.c('IS01'), 'saglik_muayenesi', '2027-06-30', 'IS-S1');

-- 1) Eski tarihli belge girilince geçerli belge yine en geç biten belgedir ------------------------
select pdks.isg_belge_gir(test.c('IS01'), 'isg_egitimi', '2026-01-01', 'IS-E0 (eski sertifika)');
select test.dogrula('İSG durumu: eski belge girildikten sonra da geçerli (bitiş 2027-06-30)',
    test.durum('IS01', 'isg_egitimi') = 'gecerli 2027-06-30 true');
reset role;
insert into pdks.aktarim (kaynak, dosya_adi, dosya_ozeti, veri_tarihi) values ('pdks', 'is.csv', 'is-ozet', '2026-11-19');
insert into pdks.ham_okutma (aktarim_id, okuyucu_id, kart_no, okutma_zamani, yon)
values ((select id from pdks.aktarim where dosya_ozeti = 'is-ozet'), (select id from pdks.okuyucu where kod = 'IS-PDKS'),
        'IS-K1', test.ts('2026-11-19 07:55'), 'giris');
select pdks.isg_kontrol('2026-11-19');
select test.dogrula('gece işi de geçerli belgeyi görür: "süresi dolmuş" uyarısı yazılmadı',
    not exists (select 1 from pdks.uyari where tur in ('isg_belgesi_suresi_dolmus', 'isg_belgesi_yok') and calisan_id = test.c('IS01')));

-- 2) Bitiş tarihi makul aralıkta ----------------------------------------------------------------
set local role authenticated;
select test.oturum('is_isg@ornek.test');
select test.hata('bitiş 2999 olamaz', 'Geçerlilik bitişi 20.11.2016 ile 20.11.2036 arasında olmalı',
    $$select pdks.isg_belge_gir(test.c('IS01'), 'isg_egitimi', '2999-12-31')$$);
select test.hata('bitiş 1900 olamaz', 'Geçerlilik bitişi',
    $$select pdks.isg_belge_gir(test.c('IS01'), 'isg_egitimi', '1900-01-01')$$);

-- 3) Görünüm hangi yakanın izlendiğini söyler ---------------------------------------------------
select test.dogrula('beyaz yaka izlenmez (izleniyor = false), mavi yaka izlenir',
    test.durum('IS02', 'isg_egitimi') = 'yok - false' and test.durum('IS01', 'saglik_muayenesi') like '% true');
reset role;

do $$ begin raise notice 'TÜM TESTLER GEÇTİ'; end $$;
rollback;
