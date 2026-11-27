-- =====================================================================
-- Yazılı onayın yeniden verilmesi testleri (20261231190000_puantaj_kalanlari.sql, T-60)
-- Testin kendi sahte verisi (2026); örnek veri yüklü olsun olmasın çalışır.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/yazili_onay_yenileme_testi.sql
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
--   YO01: 2 Ocak 2026'da yazılı onay verdi; 19 Ekim'de geri aldı (onay 18 Kasım'da geçersiz olur).
--         Aralık'ta sipariş yoğunluğunda yeniden imza verir (1 Aralık).
insert into pdks.departman (ad) values ('YO Üretim'), ('YO İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = case when s like 'YOI%' then 'YO İdari' else 'YO Üretim' end), '2025-01-01'
from unnest(array['YO01','YOI1']) s;
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('x', 'yo_ik@ornek.test', 'ik', test.c('YOI1'), '00000000-0000-0000-0000-000000000f01');
set local role authenticated;
select test.oturum('yo_ik@ornek.test');
select pdks.fazla_mesai_onayi_gir(test.c('YO01'), 2026::smallint, '2026-01-02', 'YO-FMO-1');
select test.hata('geçerli onay varken aynı yıla ikinci onay girilmez (Türkçe)', 'geçerli bir yazılı onayı var',
    $$select pdks.fazla_mesai_onayi_gir(test.c('YO01'), 2026::smallint, '2026-03-01', 'YO-FMO-1B')$$);
select pdks.fazla_mesai_onayi_geri_al((select id from pdks.fazla_mesai_onayi where belge_no = 'YO-FMO-1'), '2026-10-19');

-- 1) Geri alınan onaydan sonra aynı yıl yeniden onay girilir ---------------------------------------
select test.dogrula('onayını geri alan çalışan aynı yıl yeniden yazılı onay verebilir',
    pdks.fazla_mesai_onayi_gir(test.c('YO01'), 2026::smallint, '2026-12-01', 'YO-FMO-2') is not null);
reset role;
select test.dogrula('onay tarihleri: 18 Kasım geçersiz, 25 Kasım geçersiz, 1 Aralık''tan itibaren yeniden geçerli',
    pdks.fm_onay_gecerli_mi(test.c('YO01'), '2026-11-10') and not pdks.fm_onay_gecerli_mi(test.c('YO01'), '2026-11-25')
    and pdks.fm_onay_gecerli_mi(test.c('YO01'), '2026-12-05'));
select test.dogrula('yılda en çok bir geçerli (geri alınmamış) onay: veritabanı da engeller',
    (select count(*) = 1 from pdks.fazla_mesai_onayi where calisan_id = test.c('YO01') and yil = 2026 and geri_alma_bildirim_tarihi is null));
select test.hata('doğrudan ikinci geçerli onay da yazılamaz', 'fazla_mesai_onayi_yil_tek_gecerli',
    $$insert into pdks.fazla_mesai_onayi (calisan_id, yil, imza_tarihi, belge_no, giren_id)
      values (test.c('YO01'), 2026, '2026-12-02', 'YO-FMO-3', test.k('yo_ik@ornek.test'))$$);

do $$ begin raise notice 'TÜM TESTLER GEÇTİ'; end $$;
rollback;
