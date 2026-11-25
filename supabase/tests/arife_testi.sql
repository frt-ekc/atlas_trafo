-- =====================================================================
-- Arife testleri (20261222010000_arife.sql, T-28)
-- 28 Ekim 2026 Çarşamba arife, 29 Ekim tam tatil. Testin kendi sahte verisi.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/arife_testi.sql
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
create function test.kod(p_sicil text, p_gun date) returns text language sql security definer as $$
    select string_agg(k.kod || ' ' || k.gun || ' gün ' || k.dakika || ' dk', ', ' order by k.gun desc, k.kod)
    from pdks.gun_kodlari_hesapla(extract(year from p_gun)::int, extract(month from p_gun)::int) k
    where k.calisan_id = test.c(p_sicil) and k.tarih = p_gun $$;
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
--   Hepsi 28 Ekim arife, aksi yazılmadıkça yazılı onaylı:
--   AR01: 08-17 vardiyası, 13:02'de çıktı      AR02: 08-17, 17:00'de çıktı      AR03: AR02 gibi, yazılı onay yok
--   AR04: 08-17, 12:00'de çıktı                AR05: 08-17, plan 120, 19:00     AR06: 14-22 çalıştı
--   AR07: 14-22, gelmedi                       AR08: 22-06 gecesi çalıştı       AR09: 27 Ekim 22-06 (arife sabahı biter)
--   AR10: 22-06, yazılı onay yok               AR11: 22-06, gelmedi             AR12: 08-17, gelmedi
--   AR13: 00-08, 10:00'a kadar (havuz)         AR14: esnek 08-13                AR15: esnek 08-17
--   AR16: 08-17, çıkış okutması yok            AR17: 08-17, 14:00'te geldi      AR18: 06-14, 14:00
insert into pdks.departman (ad) values ('AR Üretim'), ('AR İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = case when s in ('ARI1', 'ARA1') then 'AR İdari' else 'AR Üretim' end), '2025-01-01'
from (select 'AR' || lpad(n::text, 2, '0') as s from generate_series(1, 18) n union all select unnest(array['ARI1', 'ARA1'])) x;
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('AR İK', 'ar_ik@ornek.test', 'ik', test.c('ARI1'), '00000000-0000-0000-0000-0000000000c5'),
    ('AR Amir', 'ar_amir@ornek.test', 'amir', test.c('ARA1'), '00000000-0000-0000-0000-0000000000c6');
update pdks.departman set amir_id = test.k('ar_amir@ornek.test') where ad = 'AR Üretim';
insert into pdks.kart (kart_no, calisan_id) select 'K-' || sicil_no, id from pdks.calisan where sicil_no like 'AR__' and sicil_no < 'ARA';
insert into pdks.okuyucu (kod, ad, sistem) values ('AR-PDKS', 'AR PDKS', 'pdks');
insert into pdks.resmi_tatil (tarih, ad, yarim_gun) values
    ('2026-10-28', 'Cumhuriyet Bayramı arifesi', true), ('2026-10-29', 'Cumhuriyet Bayramı', false)
on conflict (tarih) do nothing;
insert into pdks.fazla_mesai_onayi (calisan_id, yil, imza_tarihi, belge_no, giren_id)
select id, 2026, '2026-01-02', 'AR-' || sicil_no, test.k('ar_ik@ornek.test')
from pdks.calisan where sicil_no like 'AR__' and sicil_no < 'ARA' and sicil_no not in ('AR03', 'AR10');
insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id, giren_id)
select test.c(s), g::date, (select id from pdks.vardiya_tanim where kod = v), test.k('ar_ik@ornek.test')
from (values ('AR01', '2026-10-28', 'GUNDUZ'), ('AR02', '2026-10-28', 'GUNDUZ'), ('AR03', '2026-10-28', 'GUNDUZ'),
             ('AR04', '2026-10-28', 'GUNDUZ'), ('AR05', '2026-10-28', 'GUNDUZ'), ('AR06', '2026-10-28', 'V2'),
             ('AR07', '2026-10-28', 'V2'), ('AR08', '2026-10-28', 'V3'), ('AR09', '2026-10-27', 'V3'),
             ('AR10', '2026-10-28', 'V3'), ('AR11', '2026-10-28', 'V3'), ('AR12', '2026-10-28', 'GUNDUZ'),
             ('AR13', '2026-10-28', 'GECE_8'), ('AR14', '2026-10-28', 'ESNEK'), ('AR15', '2026-10-28', 'ESNEK'),
             ('AR16', '2026-10-28', 'GUNDUZ'), ('AR17', '2026-10-28', 'GUNDUZ'), ('AR18', '2026-10-28', 'V1')) x(s, g, v);
insert into pdks.fazla_mesai_plani (calisan_id, is_gunu, planli_dk, gerekce, talep_eden_id)
values (test.c('AR05'), '2026-10-28', 120, 'Sipariş yetişmeli', test.k('ar_amir@ornek.test'));
update pdks.fazla_mesai_plani set durum = 'onaylandi', karar_veren_id = test.k('ar_ik@ornek.test') where calisan_id = test.c('AR05');
insert into pdks.aktarim (kaynak, dosya_adi, dosya_ozeti, veri_tarihi)
select 'pdks', 'ar_' || g || '.csv', 'ar-pdks-' || g, g::date from unnest(array['2026-10-27', '2026-10-28', '2026-10-29']) g;
insert into pdks.ham_okutma (aktarim_id, okuyucu_id, kart_no, okutma_zamani, yon)
select (select id from pdks.aktarim where dosya_ozeti = 'ar-pdks-2026-10-28'),
       (select id from pdks.okuyucu where kod = 'AR-PDKS'), 'K-' || s, test.ts(z), y
from (values ('AR01', '2026-10-28 08:00', 'giris'), ('AR01', '2026-10-28 13:02', 'cikis'),
             ('AR02', '2026-10-28 08:00', 'giris'), ('AR02', '2026-10-28 17:00', 'cikis'),
             ('AR03', '2026-10-28 08:00', 'giris'), ('AR03', '2026-10-28 17:00', 'cikis'),
             ('AR04', '2026-10-28 08:00', 'giris'), ('AR04', '2026-10-28 12:00', 'cikis'),
             ('AR05', '2026-10-28 08:00', 'giris'), ('AR05', '2026-10-28 19:00', 'cikis'),
             ('AR06', '2026-10-28 14:00', 'giris'), ('AR06', '2026-10-28 22:00', 'cikis'),
             ('AR08', '2026-10-28 22:00', 'giris'), ('AR08', '2026-10-29 06:00', 'cikis'),
             ('AR09', '2026-10-27 22:00', 'giris'), ('AR09', '2026-10-28 06:00', 'cikis'),
             ('AR10', '2026-10-28 22:00', 'giris'), ('AR10', '2026-10-29 06:00', 'cikis'),
             ('AR13', '2026-10-28 00:00', 'giris'), ('AR13', '2026-10-28 10:00', 'cikis'),
             ('AR14', '2026-10-28 08:00', 'giris'), ('AR14', '2026-10-28 13:00', 'cikis'),
             ('AR15', '2026-10-28 08:00', 'giris'), ('AR15', '2026-10-28 17:00', 'cikis'),
             ('AR16', '2026-10-28 08:00', 'giris'),
             ('AR17', '2026-10-28 14:00', 'giris'), ('AR17', '2026-10-28 17:00', 'cikis'),
             ('AR18', '2026-10-28 06:00', 'giris'), ('AR18', '2026-10-28 14:00', 'cikis')) v(s, z, y);
select pdks.gece_isi_calistir('2026-10-27');
select pdks.gece_isi_calistir('2026-10-28');

-- 1) Erken çıkış ve 13:00 sonrası ------------------------------------------------
select test.dogrula('13:00''te (13:02) çıkana erken çıkış ve fazla mesai yok; çalışma 270',
    (select erken_cikis_dk = 0 and fazla_mesai_dk = 0 and calisma_dk = 270 and mola_dk = 30 from test.gk('AR01', '2026-10-28')));
select test.dogrula('12:00''de çıkana yalnızca 13:00''e kadarki 60 dk erken çıkış',
    (select erken_cikis_dk = 60 and calisma_dk = 225 from test.gk('AR04', '2026-10-28')));
select test.dogrula('17:00''ye kadar çalışana (yazılı onaylı) 13:00 sonrası FM100 240, toplam 480',
    (select fm100_dk = 240 and fm50_dk = 0 and calisma_dk = 480 and erken_cikis_dk = 0 from test.gk('AR02', '2026-10-28'))
    and (test.hv('AR02', '2026-10-28')).id is null);
select test.dogrula('vardiya sonrası plan 120 dk da FM100 (toplam 360)',
    (select fm100_dk = 360 and fm50_dk = 0 and calisma_dk = 600 from test.gk('AR05', '2026-10-28')));
select test.dogrula('06-14 vardiyası: 13:00-14:00 FM100 60',
    (select fm100_dk = 60 and calisma_dk = 420 and erken_cikis_dk = 0 from test.gk('AR18', '2026-10-28')));
select test.dogrula('14:00''te gelen: geç kalma en çok 13:00''e kadar (300), çalışması FM100',
    (select gec_kalma_dk = 300 and fm100_dk = 165 and calisma_dk = 165 from test.gk('AR17', '2026-10-28')));
select test.dogrula('planlı bitiş 13:00 yazıldı; 17:00 çıkışı yine bulundu',
    (select planli_bitis = test.ts('2026-10-28 13:00') and cikis_zamani = test.ts('2026-10-28 17:00') from test.gk('AR02', '2026-10-28')));
select test.dogrula('yazılı onaylı tatil çalışmasına "plansız" uyarısı yok (AR02)',
    not exists (select 1 from pdks.uyari where calisan_id = test.c('AR02') and tur in ('fm_plansiz_calisma', 'fm_onay_yok')));

-- 2) Yazılı onay yok (T-56) -------------------------------------------------------
select test.dogrula('yazılı onaysız: 13:00 sonrası 240 dk havuzda tatil çalışması, puantajda yok',
    (select fm100_dk = 0 and calisma_dk = 270 and erken_cikis_dk = 0 from test.gk('AR03', '2026-10-28'))
    and (select tur = 'tatil_calismasi' and dakika = 240 and durum = 'inceleme_bekliyor' from test.hv('AR03', '2026-10-28')));
set local role authenticated;
select test.oturum('ar_ik@ornek.test');
select pdks.fazla_mesai_inceleme_karar((test.hv('AR03', '2026-10-28')).id, true);
reset role;
select test.dogrula('İK onaylayınca FM100 240; kayıt yazılı onaysız işaretli',
    (select fm100_dk = 240 and calisma_dk = 480 from test.gk('AR03', '2026-10-28'))
    and (test.hv('AR03', '2026-10-28')).yazili_onaysiz);

-- 3) Gece vardiyası ve 13:00'ten sonra başlayan vardiya -----------------------------
select test.dogrula('14-22 çalışan: tamamı FM100 (480 − 60 mola), erken çıkış / geç kalma yok',
    (select fm100_dk = 420 and calisma_dk = 420 and gec_kalma_dk = 0 and erken_cikis_dk = 0 from test.gk('AR06', '2026-10-28')));
select test.dogrula('arife gecesi 22-06: is_gunu arife, tamamı FM100; gece çalışması yazılır',
    (select fm100_dk = 420 and calisma_dk = 420 and gece_calisma_dk = 420 and planli_bitis = test.ts('2026-10-29 06:00')
     from test.gk('AR08', '2026-10-28')));
select test.dogrula('27 Ekim gecesi (arife sabahı 06:00''da biter): normal gece vardiyası, FM100 yok',
    (select fm100_dk = 0 and calisma_dk = 420 and erken_cikis_dk = 0 from test.gk('AR09', '2026-10-27')));
select test.dogrula('yazılı onaysız arife gecesi: 480 dk havuzda tatil çalışması',
    (select fm100_dk = 0 and calisma_dk = 0 from test.gk('AR10', '2026-10-28'))
    and (select tur = 'tatil_calismasi' and dakika = 480 from test.hv('AR10', '2026-10-28')));
select test.dogrula('14-22 ya da 22-06 vardiyasına gelmeyen: gün tatil, soru yok',
    (select durum = 'tatil' and hesap_tamam from test.gk('AR07', '2026-10-28'))
    and (select durum = 'tatil' and hesap_tamam from test.gk('AR11', '2026-10-28')));
select test.dogrula('08-17 vardiyasına hiç gelmeyen: öğleden önce iş günü, soru açılır',
    (select durum = 'soru_bekliyor' from test.gk('AR12', '2026-10-28')));
select test.dogrula('00-08 vardiyası: 13:00''ten önceki vardiya sonrası 120 dk havuzda, normal fazla mesai',
    (select erken_cikis_dk = 0 and calisma_dk = 420 and fm100_dk = 0 from test.gk('AR13', '2026-10-28'))
    and (select tur = 'vardiya_sonrasi' and dakika = 120 from test.hv('AR13', '2026-10-28')));
set local role authenticated;
select pdks.fazla_mesai_inceleme_karar((test.hv('AR13', '2026-10-28')).id, true);
reset role;
select test.dogrula('onaylanınca FM50 120 (13:00''ten önce)',
    (select fm50_dk = 120 and fm100_dk = 0 from test.gk('AR13', '2026-10-28')));

-- 4) Soru, kod, esnek mesai, yıllık toplam -------------------------------------------
select test.oturum('ar_amir@ornek.test');
set local role authenticated;
select pdks.soru_cevapla((select q.id from pdks.amir_sorusu q where q.gun_kaydi_id = (test.gk('AR16', '2026-10-28')).id), 'geldi_saat_dogru');
reset role;
select test.dogrula('çıkış okutması yoksa amir "saat doğru" deyince çıkış 13:00 yazılır, FM100 oluşmaz',
    (select cikis_zamani = test.ts('2026-10-28 13:00') and fm100_dk = 0 and calisma_dk = 270 from test.gk('AR16', '2026-10-28')));
select test.dogrula('puantaj kodu: NÇ 240 + FM100 240 aynı günde',
    test.kod('AR02', '2026-10-28') = 'NÇ 1 gün 240 dk, FM100 0 gün 240 dk');
select test.dogrula('puantaj kodu: 13:00''te çıkan NÇ 270; arife gecesi FM100 1 gün; gelmeyen RT',
    test.kod('AR01', '2026-10-28') = 'NÇ 1 gün 270 dk' and test.kod('AR08', '2026-10-28') = 'FM100 1 gün 420 dk'
    and test.kod('AR07', '2026-10-28') = 'RT 1 gün 0 dk');
select test.dogrula('esnek: arife hedefi 240; 08-13 fark +30, 08-17 (FM100 240 ayrı) fark 0',
    (select hedef_dk = 240 and fark_dk = 30 from pdks.v_esnek_mesai where calisan_id = test.c('AR14') and ay = 10)
    and (select hedef_dk = 240 and fark_dk = 0 from pdks.v_esnek_mesai where calisan_id = test.c('AR15') and ay = 10)
    and (select fm100_dk = 240 from test.gk('AR15', '2026-10-28')));
select test.dogrula('esnek: canlı puantaj ve fark hesabı (gun_katkisi) aynı sonucu verir',
    (select esnek_hedef_dk = 240 and esnek_fark_dk = 0 from pdks.v_puantaj_canli where calisan_id = test.c('AR15') and ay = 10)
    and (select esnek_hedef_dk = 240 and esnek_fark_dk = 0 from pdks.gun_katkisi((test.gk('AR15', '2026-10-28')).id, '{}')));
select test.dogrula('yıllık toplam: arife FM100 sayılır, plan iki kez sayılmaz (240 / 360)',
    pdks.fm_yillik_toplam(test.c('AR02'), 2026) = 240 and pdks.fm_yillik_toplam(test.c('AR05'), 2026) = 360);
select test.dogrula('yıllık toplam: havuzdan onaylanan arife (AR03 240, AR13 120)',
    pdks.fm_yillik_toplam(test.c('AR03'), 2026) = 240 and pdks.fm_yillik_toplam(test.c('AR13'), 2026) = 120);

-- 5) Takvim -----------------------------------------------------------------------
select test.dogrula('2026 ve 2027 arifeleri takvimde, hepsi yarım gün',
    (select count(*) = 6 from pdks.resmi_tatil where yarim_gun and tarih in
        ('2026-03-19', '2026-05-26', '2026-10-28', '2027-03-08', '2027-05-15', '2027-10-28')));
select test.dogrula('arife sınırı: arifede 13:00 (İstanbul), diğer günde yok',
    pdks.arife_siniri('2026-10-28') = test.ts('2026-10-28 13:00')
    and pdks.arife_siniri('2026-10-27') is null and pdks.arife_siniri('2026-10-29') is null);
insert into pdks.resmi_tatil (tarih, ad, yarim_gun) values ('2026-10-25', 'Deneme arifesi (Pazar)', true);
select test.dogrula('Pazara gelen arife tam tatil kuralıyla sayılır', pdks.arife_siniri('2026-10-25') is null);

do $$ begin raise notice 'TÜM TESTLER GEÇTİ'; end $$;
rollback;
