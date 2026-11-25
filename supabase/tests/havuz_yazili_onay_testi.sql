-- =====================================================================
-- Yazılı onaysız fazla mesainin havuzdan onaylanması testleri (20261220010000_havuz_yazili_onay.sql, T-56)
-- Testin kendi sahte verisi (Ekim 2026); örnek veri yüklü olsun olmasın çalışır.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/havuz_yazili_onay_testi.sql
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
create function test.izin(p_sicil text) returns bigint language sql security definer as $$
    select id from pdks.izin where calisan_id = test.c(p_sicil) order by id desc limit 1 $$;
create function test.ts(p text) returns timestamptz language sql immutable as $$
    select (p::timestamp) at time zone 'Europe/Istanbul' $$;
create function test.gk(p_sicil text, p_gun date) returns pdks.gun_kaydi language sql security definer as $$
    select * from pdks.gun_kaydi where calisan_id = test.c(p_sicil) and is_gunu = p_gun $$;
create function test.hv(p_sicil text, p_gun date) returns pdks.fazla_mesai_inceleme language sql security definer as $$
    select * from pdks.fazla_mesai_inceleme where calisan_id = test.c(p_sicil) and is_gunu = p_gun $$;
create function test.uyari(p_sicil text) returns text language sql security definer as $$
    select string_agg(mesaj, ' | ') from pdks.uyari where tur = 'yazili_onay_eksik' and calisan_id = test.c(p_sicil) $$;
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
--   HY01: onay yok, Çarşamba 14 Ekim 08–19     HY02: onay yok, Pazar 18 Ekim 08–17
--   HY03: onay var, 14 Ekim 08–19              HY04: imza 15 Ekim, 14 ve 16 Ekim 08–19
--   HY05: onay yok, Pazar 18 Ekim 08–17; belge kilitten sonra girilir
--   HY06: onay yok, 14 Ekim 08–19 (ret)
insert into pdks.departman (ad) values ('HY Üretim'), ('HY İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = case when s like 'HYI%' then 'HY İdari' else 'HY Üretim' end), '2025-01-01'
from unnest(array['HY01','HY02','HY03','HY04','HY05','HY06','HY07','HYI1']) s;
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('HY İK', 'hy_ik@ornek.test', 'ik', test.c('HYI1'), '00000000-0000-0000-0000-0000000000a1');
insert into pdks.kart (kart_no, calisan_id)
select 'HY-' || s, test.c(s) from unnest(array['HY01','HY02','HY03','HY04','HY05','HY06','HY07']) s;
insert into pdks.okuyucu (kod, ad, sistem) values ('HY-PDKS', 'HY PDKS', 'pdks');
insert into pdks.fazla_mesai_onayi (calisan_id, yil, imza_tarihi, belge_no, giren_id)
values (test.c('HY03'), 2026, '2026-01-02', 'HY-FMO-3', test.k('hy_ik@ornek.test')),
       (test.c('HY04'), 2026, '2026-10-15', 'HY-FMO-4', test.k('hy_ik@ornek.test'));

create temp table hy_gun on commit drop as
select * from (values ('HY01', date '2026-10-14', '19:00'), ('HY02', date '2026-10-18', '17:00'),
                      ('HY03', date '2026-10-14', '19:00'), ('HY04', date '2026-10-14', '19:00'),
                      ('HY04', date '2026-10-16', '19:00'), ('HY05', date '2026-10-18', '17:00'),
                      ('HY06', date '2026-10-14', '19:00'), ('HY07', date '2026-10-18', '17:00')) v(s, g, bit);
insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id, giren_id)
select test.c(s), g, (select id from pdks.vardiya_tanim where kod = 'GUNDUZ'), test.k('hy_ik@ornek.test') from hy_gun;
insert into pdks.aktarim (kaynak, dosya_adi, dosya_ozeti, veri_tarihi)
select distinct 'pdks', 'hy_' || g || '.csv', 'hy-pdks-' || g, g from hy_gun;
insert into pdks.ham_okutma (aktarim_id, okuyucu_id, kart_no, okutma_zamani, yon)
select (select id from pdks.aktarim where dosya_ozeti = 'hy-pdks-' || g),
       (select id from pdks.okuyucu where kod = 'HY-PDKS'), 'HY-' || s, test.ts(g || ' ' || x.saat), x.yon
from hy_gun cross join lateral (values ('08:00', 'giris'), (bit, 'cikis')) x(saat, yon);
select pdks.gece_isi_calistir('2026-10-14');
select pdks.gece_isi_calistir('2026-10-16');
select pdks.gece_isi_calistir('2026-10-18');
select test.dogrula('hazırlık: 120 dk vardiya sonrası ve 540 dk tatil çalışması havuzda',
    (select dakika = 120 and tur = 'vardiya_sonrasi' and durum = 'inceleme_bekliyor' from test.hv('HY01', '2026-10-14'))
    and (select dakika = 540 and tur = 'tatil_calismasi' and durum = 'inceleme_bekliyor' from test.hv('HY02', '2026-10-18'))
    and (select dakika = 120 from test.hv('HY04', '2026-10-16')));

-- 1) Yazılı onay yok: onaylanır, dakika sayılır, işaret ve uyarı oluşur ---------
select test.dogrula('karardan önce işaret ve uyarı yok',
    (select not yazili_onaysiz from test.hv('HY01', '2026-10-14')) and test.uyari('HY01') is null);
set local role authenticated;
select test.oturum('hy_ik@ornek.test');
select pdks.fazla_mesai_inceleme_karar((test.hv('HY01', '2026-10-14')).id, true);
select pdks.fazla_mesai_inceleme_karar((test.hv('HY02', '2026-10-18')).id, true, 'Bakım işi için çağrıldı');
select pdks.fazla_mesai_inceleme_karar((test.hv('HY04', '2026-10-14')).id, true);
reset role;
select test.dogrula('hafta içi: yazılı onay olmadan onaylanan süre puantaja girer (FM50 120)',
    (select fm50_dk = 120 and fazla_mesai_dk = 120 and calisma_dk = 600 from test.gk('HY01', '2026-10-14'))
    and (select durum = 'onaylandi' and fm50_etki_dk = 120 from test.hv('HY01', '2026-10-14')));
select test.dogrula('Pazar: yazılı onay olmadan onaylanan çalışma puantaja girer (FM100 480)',
    (select fm100_dk = 480 and calisma_dk = 480 from test.gk('HY02', '2026-10-18')));
select test.dogrula('kayıtlar "yazılı onaysız" işaretlendi',
    (test.hv('HY01', '2026-10-14')).yazili_onaysiz and (test.hv('HY02', '2026-10-18')).yazili_onaysiz);
select test.dogrula('imza tarihinden önceki gün de yazılı onaysız sayılır',
    (test.hv('HY04', '2026-10-14')).yazili_onaysiz and test.uyari('HY04') like '%14.10.2026%');
select test.dogrula('uyarı metni çalışanı ve günü söyler',
    test.uyari('HY01') = 'AdHY01 Örnek için 14.10.2026 tarihli fazla mesai yazılı onay olmadan yapılmıştır; yazılı onay alınmalıdır.');

-- 2) Yazılı onay var: eskisi gibi, işaret ve uyarı yok --------------------------
set local role authenticated;
select pdks.fazla_mesai_inceleme_karar((test.hv('HY03', '2026-10-14')).id, true);
select pdks.fazla_mesai_inceleme_karar((test.hv('HY04', '2026-10-16')).id, true);
reset role;
select test.dogrula('yazılı onaylı kayıt: FM50 120, işaret yok, uyarı yok',
    (select fm50_dk = 120 from test.gk('HY03', '2026-10-14'))
    and not (test.hv('HY03', '2026-10-14')).yazili_onaysiz and test.uyari('HY03') is null);
select test.dogrula('imza tarihinden sonraki gün: işaret yok, yeni uyarı yok',
    not (test.hv('HY04', '2026-10-16')).yazili_onaysiz and test.uyari('HY04') not like '%16.10.2026%');

-- 3) İşaret karar anının izidir --------------------------------------------------
set local role authenticated;
select pdks.fazla_mesai_onayi_gir(test.c('HY01'), 2026::smallint, '2026-01-05', 'HY-FMO-1');
select pdks.fazla_mesai_inceleme_karar((test.hv('HY06', '2026-10-14')).id, false, 'Çalışma yapılmamış');
reset role;
select test.dogrula('belge sonradan girilse de işaret ve uyarı kalır',
    (test.hv('HY01', '2026-10-14')).yazili_onaysiz and test.uyari('HY01') is not null);
select test.dogrula('ret kararında işaret ve uyarı olmaz',
    (select durum = 'reddedildi' and not yazili_onaysiz from test.hv('HY06', '2026-10-14')) and test.uyari('HY06') is null);
select test.hata('reddedilmiş kayda işaret konamaz', 'yazili_onaysiz_check',
    format('update pdks.fazla_mesai_inceleme set yazili_onaysiz = true where id = %s', (test.hv('HY06', '2026-10-14')).id));
select pdks.gun_hesabini_yenile((test.gk('HY02', '2026-10-18')).id);
select test.dogrula('yeniden hesapta yazılı onaysız dakika yine sayılır (HY02)',
    (select fm100_dk = 480 from test.gk('HY02', '2026-10-18')));

-- 4) Kilitli ay -------------------------------------------------------------------
--   HY05: belge kilitten sonra girilir · HY07: belge hiç girilmez
set local role authenticated;
select test.oturum('hy_ik@ornek.test');
select pdks.ay_kilitle(2026::smallint, 10::smallint, true);
select pdks.fazla_mesai_onayi_gir(test.c('HY05'), 2026::smallint, '2026-01-05', 'HY-FMO-5');
select pdks.fazla_mesai_inceleme_karar((test.hv('HY05', '2026-10-18')).id, true);
select pdks.fazla_mesai_inceleme_karar((test.hv('HY07', '2026-10-18')).id, true);
reset role;
select test.dogrula('kilitli ayda belge sonradan gelirse FM100 480 dk fark olur; kilitli gün değişmez',
    (select fark_satiri and fm100_etki_dk = 480 and calisma_etki_dk = 480 and not yazili_onaysiz from test.hv('HY05', '2026-10-18'))
    and (select fm100_dk = 0 from test.gk('HY05', '2026-10-18')));
select test.dogrula('kilitli ayda yazılı onaysız kayıt da fark olur, işaret ve uyarı oluşur',
    (select fark_satiri and fm100_etki_dk = 480 and yazili_onaysiz from test.hv('HY07', '2026-10-18'))
    and test.uyari('HY07') is not null);

do $$ begin raise notice 'TÜM TESTLER GEÇTİ'; end $$;
rollback;
