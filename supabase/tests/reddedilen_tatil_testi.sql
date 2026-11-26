-- =====================================================================
-- Reddedilen (ya da karar bekleyen) tatil çalışmasının kodu testleri (20261231070000_reddedilen_tatil.sql, T-102)
-- Testin kendi sahte verisi (Ekim 2026); örnek veri yüklü olsun olmasın çalışır.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/reddedilen_tatil_testi.sql
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
create function test.gk(p_sicil text, p_gun date) returns pdks.gun_kaydi language sql security definer as $$
    select * from pdks.gun_kaydi where calisan_id = test.c(p_sicil) and is_gunu = p_gun $$;
create function test.hv(p_sicil text, p_gun date) returns pdks.fazla_mesai_inceleme language sql security definer as $$
    select * from pdks.fazla_mesai_inceleme where calisan_id = test.c(p_sicil) and is_gunu = p_gun $$;
create function test.kod(p_sicil text, p_gun date) returns text language sql security definer as $$
    select string_agg(k.kod || ' ' || k.gun || ' gün ' || k.dakika || ' dk', ', ' order by k.gun desc, k.kod)
    from pdks.gun_kodlari_hesapla(extract(year from p_gun)::int, extract(month from p_gun)::int) k
    where k.calisan_id = test.c(p_sicil) and k.tarih = p_gun $$;
create function test.katki(p_sicil text, p_gun date) returns numeric language sql security definer as $$
    select (pdks.gun_katkisi((test.gk(p_sicil, p_gun)).id, null)).calisilan_gun $$;
create function test.canli(p_sicil text) returns bigint language sql security definer as $$
    select calisilan_gun from pdks.v_puantaj_canli where calisan_id = test.c(p_sicil) and yil = 2026 and ay = 10 $$;
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
-- Hiçbirinin yazılı fazla mesai onayı yok; tatil günündeki çalışma bu yüzden havuza düşer.
--   TR01: Pazar 18 Ekim 08–17, havuz reddedilir        TR02: Pazar 18 Ekim 08–17, havuz onaylanır
--   TR03: Pazar 18 Ekim 08–17, önce bekler sonra onay  TR04: 29 Ekim (tam gün bayram) 08–17, ret
--   TR05: Çarşamba 14 Ekim 08–17 (normal iş günü)      TR06: Pazar 18 Ekim 08–17, kilitte hâlâ bekliyor
insert into pdks.departman (ad) values ('TR Üretim'), ('TR İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = case when s like 'TRI%' then 'TR İdari' else 'TR Üretim' end), '2025-01-01'
from unnest(array['TR01','TR02','TR03','TR04','TR05','TR06','TRI1']) s;
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('TR İK', 'tr_ik@ornek.test', 'ik', test.c('TRI1'), '00000000-0000-0000-0000-0000000001a2');
insert into pdks.kart (kart_no, calisan_id)
select 'TR-' || s, test.c(s) from unnest(array['TR01','TR02','TR03','TR04','TR05','TR06']) s;
insert into pdks.okuyucu (kod, ad, sistem) values ('TR-PDKS', 'TR PDKS', 'pdks');
insert into pdks.resmi_tatil (tarih, ad, yarim_gun) values
    ('2026-10-28', 'Cumhuriyet Bayramı arifesi', true), ('2026-10-29', 'Cumhuriyet Bayramı', false)
on conflict (tarih) do nothing;

create temp table tr_gun on commit drop as
select * from (values ('TR01', date '2026-10-18'), ('TR02', date '2026-10-18'), ('TR03', date '2026-10-18'),
                      ('TR04', date '2026-10-29'), ('TR05', date '2026-10-14'), ('TR06', date '2026-10-18')) v(s, g);
insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id, giren_id)
select test.c(s), g, (select id from pdks.vardiya_tanim where kod = 'GUNDUZ'), test.k('tr_ik@ornek.test') from tr_gun;
insert into pdks.aktarim (kaynak, dosya_adi, dosya_ozeti, veri_tarihi)
select distinct 'pdks', 'tr_' || g || '.csv', 'tr-pdks-' || g, g from tr_gun;
insert into pdks.ham_okutma (aktarim_id, okuyucu_id, kart_no, okutma_zamani, yon)
select (select id from pdks.aktarim where dosya_ozeti = 'tr-pdks-' || g),
       (select id from pdks.okuyucu where kod = 'TR-PDKS'), 'TR-' || s, test.ts(g || ' ' || x.saat), x.yon
from tr_gun cross join lateral (values ('08:00', 'giris'), ('17:00', 'cikis')) x(saat, yon);
select pdks.gece_isi_calistir('2026-10-14');
select pdks.gece_isi_calistir('2026-10-18');
select pdks.gece_isi_calistir('2026-10-29');
select test.dogrula('hazırlık: tatil günlerindeki çalışmalar havuzda karar bekliyor, gün "tamam" ve 0 dk',
    (select count(*) = 5 from tr_gun t
     where t.s <> 'TR05'
       and (test.hv(t.s, t.g)).tur = 'tatil_calismasi' and (test.hv(t.s, t.g)).durum = 'inceleme_bekliyor'
       and (test.gk(t.s, t.g)).durum = 'tamam' and (test.gk(t.s, t.g)).hesap_tamam
       and coalesce((test.gk(t.s, t.g)).calisma_dk, 0) = 0));

-- 1) Karar beklerken: gün hiç çalışılmamış tatil gibi görünür -----------------------
select test.dogrula('karar bekleyen Pazar: kod HT 1 gün, çalışılan gün sayılmaz',
    test.kod('TR03', '2026-10-18') = 'HT 1 gün 0 dk' and test.katki('TR03', '2026-10-18') = 0
    and test.canli('TR03') = 0);

-- 2) Kararlar --------------------------------------------------------------------------
set local role authenticated;
select test.oturum('tr_ik@ornek.test');
select pdks.fazla_mesai_inceleme_karar((test.hv('TR01', '2026-10-18')).id, false, 'Çağrılmadı, ödenmez');
select pdks.fazla_mesai_inceleme_karar((test.hv('TR02', '2026-10-18')).id, true, 'Bakım işi için çağrıldı');
select pdks.fazla_mesai_inceleme_karar((test.hv('TR03', '2026-10-18')).id, true, 'Sevkiyat için çağrıldı');
select pdks.fazla_mesai_inceleme_karar((test.hv('TR04', '2026-10-29')).id, false, 'Bayramda çalışma istenmedi');
reset role;

select test.dogrula('reddedilen Pazar: kod HT 1 gün 0 dk (FM100 değil)',
    test.kod('TR01', '2026-10-18') = 'HT 1 gün 0 dk');
select test.dogrula('reddedilen Pazar: gün katkısında ve canlı puantajda çalışılan gün 0',
    test.katki('TR01', '2026-10-18') = 0 and test.canli('TR01') = 0);
select test.dogrula('reddedilen bayram: kod RT 1 gün 0 dk, çalışılan gün 0',
    test.kod('TR04', '2026-10-29') = 'RT 1 gün 0 dk' and test.katki('TR04', '2026-10-29') = 0 and test.canli('TR04') = 0);
select test.dogrula('onaylanan Pazar değişmez: FM100 1 gün 480 dk, çalışılan gün 1',
    test.kod('TR02', '2026-10-18') = 'FM100 1 gün 480 dk' and test.katki('TR02', '2026-10-18') = 1 and test.canli('TR02') = 1);
select test.dogrula('bekledikten sonra onaylanan Pazar: FM100 1 gün 480 dk, çalışılan gün 1',
    test.kod('TR03', '2026-10-18') = 'FM100 1 gün 480 dk' and test.katki('TR03', '2026-10-18') = 1 and test.canli('TR03') = 1);
select test.dogrula('normal iş günü değişmez: NÇ 1 gün 480 dk, çalışılan gün 1',
    test.kod('TR05', '2026-10-14') = 'NÇ 1 gün 480 dk' and test.katki('TR05', '2026-10-14') = 1 and test.canli('TR05') = 1);
select test.dogrula('yönetici paneli de aynı sayar: TR Üretim çalışılan gün 3 (TR02, TR03, TR05)',
    (select calisilan_gun = 3 from pdks.v_departman_ozet
     where departman = 'TR Üretim' and yil = 2026 and ay = 10));

-- 3) Ay kilidi: kilitli puantaj aynı kodu ve aynı gün sayısını yazar -------------------
set local role authenticated;
select test.oturum('tr_ik@ornek.test');
select pdks.ay_kilitle(2026::smallint, 10::smallint, true, 'Test: zorla kilit gerekçesi');
reset role;
-- Kalemler kod başına ayın toplamıdır: ayın kayıtsız günleri de HT, 29 Ekim RT. Bu üç kişi ayda hiç
-- çalışmış sayılmaz: kalemleri yalnızca HT 30 + RT 1 (eski kod: FM100 1 gün / 0 dk, HT 29, RT 1).
select test.dogrula('kilitli puantaj: reddedilen ve bekleyen Pazar ile reddedilen bayram FM100 değil HT / RT, satırda çalışılan gün 0',
    (select bool_and(s.calisilan_gun = 0)
            and bool_and((select string_agg(k.kod || ' ' || k.gun || ' ' || k.dakika, ', ' order by k.kod)
                          from pdks.puantaj_kalemi k where k.puantaj_satiri_id = s.id) = 'HT 30.0 0, RT 1.0 0')
            and count(*) = 3
     from pdks.puantaj_satiri s join pdks.donem d on d.id = s.donem_id
     where s.calisan_id in (test.c('TR01'), test.c('TR04'), test.c('TR06'))
       and d.yil = 2026 and d.ay = 10 and s.satir_turu = 'normal'));
select test.dogrula('kilitli puantaj: satırdaki çalışılan gün = NÇ + FM50 + FM100 kalemlerinin günü (TR01–TR06)',
    (select bool_and(s.calisilan_gun = coalesce((select sum(k.gun) from pdks.puantaj_kalemi k
                                                 where k.puantaj_satiri_id = s.id and k.kod in ('NÇ', 'FM50', 'FM100')), 0))
            and count(*) = 6
     from pdks.puantaj_satiri s join pdks.donem d on d.id = s.donem_id
     where s.calisan_id in (select test.c(t.s) from tr_gun t) and d.yil = 2026 and d.ay = 10 and s.satir_turu = 'normal'));

-- 4) Kilitten sonra onay: kilitli ay değişmez, dakika fark olarak gelir (T-79'daki plansız günle aynı)
set local role authenticated;
select test.oturum('tr_ik@ornek.test');
select pdks.fazla_mesai_inceleme_karar((test.hv('TR06', '2026-10-18')).id, true, 'Geç bildirildi, çağrılmıştı');
reset role;
select test.dogrula('kilitten sonra onay: FM100 480 dk fark satırına gider, kilitli kalem HT kalır',
    (select fark_satiri and fm100_etki_dk = 480 from test.hv('TR06', '2026-10-18'))
    and (select string_agg(k.kod || ' ' || k.gun, ', ' order by k.kod) = 'HT 30.0, RT 1.0'
         from pdks.puantaj_kalemi k join pdks.puantaj_satiri s on s.id = k.puantaj_satiri_id
         join pdks.donem d on d.id = s.donem_id
         where s.calisan_id = test.c('TR06') and d.yil = 2026 and d.ay = 10 and s.satir_turu = 'normal'));

do $$ begin raise notice 'TÜM TESTLER GEÇTİ'; end $$;
rollback;
