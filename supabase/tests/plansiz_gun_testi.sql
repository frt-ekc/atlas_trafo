-- =====================================================================
-- Plansız gün çalışması testleri (20261224010000_plansiz_gun.sql, T-79)
-- 17 Ekim 2026 Cumartesi, 18 Ekim Pazar. Testin kendi sahte verisi.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/plansiz_gun_testi.sql
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
create function test.uy(p_sicil text) returns text language sql security definer as $$
    select string_agg(mesaj, ' | ' order by id) from pdks.uyari where tur = 'plansiz_gun_calismasi' and calisan_id = test.c(p_sicil) $$;
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
--   Hepsinin 17 Ekim Cumartesi planı yok, aksi yazılmadıkça 08:00–13:00 okuttu:
--   PG01: yazılı onaylı        PG02: yazılı onay yok       PG03: ret edilecek
--   PG04: yalnızca giriş       PG05: 10 dk uğradı          PG06: Cuma 22-06 gecesinin sabah çıkışı (06:05)
--   PG07: Cuma gecesi + Cumartesi 14:00–18:00 yeniden      PG08: Cumartesi 22:00–Pazar 06:00 plansız gece
--   PG09: Pazar 00-08 planlı, Cumartesi 23:50 giriş        PG10: Cumartesi planlı (normal)
--   PG11: 16 Ekim'de ayrıldı   PG12: 18 Ekim'de işe girer  PG13: plan onay bekliyor (geriye dönük)
--   PG14: Pazar 18 Ekim plansız 08–17, yazılı onaylı       PG15: sonradan plan girilecek (GUNDUZ 08-17)
--   PG16: önce havuz, sonra plan     PG17: yıllık sınır    PG18: saat düzeltmesi    PG19: İK'nın kendisi
--   PG20: kilitli ay farkı     PG21: yalnızca çıkış     PG22: hafta içi Perşembe 15 Ekim plansız
--   PG23: 29 Ekim resmi tatil plansız     PG24: 28 Ekim arife plansız 08–17
insert into pdks.departman (ad) values ('PG Üretim'), ('PG Kalite'), ('PG İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = d),
       case when s = 'PG12' then date '2026-10-18' else date '2025-01-01' end
from (select 'PG' || lpad(n::text, 2, '0') as s, 'PG Üretim' as d from generate_series(1, 24) n
      union all select * from (values ('PGI1', 'PG İdari'), ('PGI2', 'PG İdari'), ('PGA1', 'PG Üretim'), ('PGA2', 'PG Kalite')) v) x;
update pdks.calisan set isten_cikis_tarihi = '2026-10-16', aktif = false where sicil_no = 'PG11';
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('x', 'pg_ik1@ornek.test',   'ik',   test.c('PGI1'), '00000000-0000-0000-0000-0000000000c7'),
    ('x', 'pg_ik2@ornek.test',   'ik',   test.c('PGI2'), '00000000-0000-0000-0000-0000000000c8'),
    ('x', 'pg_amir@ornek.test',  'amir', test.c('PGA1'), '00000000-0000-0000-0000-0000000000c9'),
    ('x', 'pg_amir2@ornek.test', 'amir', test.c('PGA2'), '00000000-0000-0000-0000-0000000000ca');
update pdks.departman set amir_id = test.k('pg_amir@ornek.test') where ad = 'PG Üretim';
update pdks.departman set amir_id = test.k('pg_amir2@ornek.test') where ad = 'PG Kalite';
insert into pdks.kart (kart_no, calisan_id) select 'K-' || sicil_no, id from pdks.calisan where sicil_no like 'PG__';
insert into pdks.okuyucu (kod, ad, sistem) values ('PG-PDKS', 'PG PDKS', 'pdks');
insert into pdks.fazla_mesai_onayi (calisan_id, yil, imza_tarihi, belge_no, giren_id)
select test.c(s), 2026, '2026-01-02', 'PG-' || s, test.k('pg_ik1@ornek.test')
from unnest(array['PG01', 'PG14', 'PG15', 'PG16', 'PG17', 'PG18', 'PG20']) s;
insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id, giren_id)
select test.c(s), g::date, (select id from pdks.vardiya_tanim where kod = v), test.k('pg_ik1@ornek.test')
from (values ('PG06', '2026-10-16', 'V3'), ('PG07', '2026-10-16', 'V3'), ('PG09', '2026-10-18', 'GECE_8'),
             ('PG10', '2026-10-17', 'GUNDUZ'), ('PG01', '2026-10-16', 'GUNDUZ'), ('PG13', '2026-10-17', 'GUNDUZ')) x(s, g, v);
update pdks.vardiya_plani set geriye_donuk = true, ik_onay_durumu = 'bekliyor' where calisan_id = test.c('PG13');
insert into pdks.aktarim (kaynak, dosya_adi, dosya_ozeti, veri_tarihi)
select 'pdks', 'pg_' || g || '.csv', 'pg-pdks-' || g, g::date
from unnest(array['2026-10-15', '2026-10-16', '2026-10-17', '2026-10-28', '2026-10-29']) g;
insert into pdks.resmi_tatil (tarih, ad, yarim_gun) values
    ('2026-10-28', 'Cumhuriyet Bayramı arifesi', true), ('2026-10-29', 'Cumhuriyet Bayramı', false)
on conflict (tarih) do nothing;
insert into pdks.ham_okutma (aktarim_id, okuyucu_id, kart_no, okutma_zamani, yon)
select (select id from pdks.aktarim where dosya_ozeti = 'pg-pdks-2026-10-17'),
       (select id from pdks.okuyucu where kod = 'PG-PDKS'), 'K-' || s, test.ts(z), y
from (select s, '2026-10-17 08:00' as z, 'giris' as y
      from unnest(array['PG01','PG02','PG03','PG04','PG10','PG11','PG12','PG13','PG15','PG16','PG17','PG18','PG20','PGI1']) s
      union all
      select s, '2026-10-17 13:00', 'cikis'
      from unnest(array['PG01','PG02','PG03','PG10','PG11','PG12','PG13','PG15','PG16','PG17','PG18','PG20','PG21','PGI1']) s
      union all
      select * from (values ('PG05', '2026-10-17 10:00', 'giris'), ('PG05', '2026-10-17 10:10', 'cikis'),
             ('PG01', '2026-10-16 08:00', 'giris'), ('PG01', '2026-10-16 17:00', 'cikis'),
             ('PG06', '2026-10-16 22:00', 'giris'), ('PG06', '2026-10-17 06:05', 'cikis'),
             ('PG07', '2026-10-16 22:00', 'giris'), ('PG07', '2026-10-17 06:00', 'cikis'),
             ('PG07', '2026-10-17 14:00', 'giris'), ('PG07', '2026-10-17 18:00', 'cikis'),
             ('PG08', '2026-10-17 22:00', 'giris'), ('PG08', '2026-10-18 06:00', 'cikis'),
             ('PG09', '2026-10-17 23:50', 'giris'), ('PG09', '2026-10-18 08:00', 'cikis'),
             ('PG22', '2026-10-15 08:00', 'giris'), ('PG22', '2026-10-15 13:00', 'cikis'),
             ('PG23', '2026-10-29 08:00', 'giris'), ('PG23', '2026-10-29 13:00', 'cikis'),
             ('PG24', '2026-10-28 08:00', 'giris'), ('PG24', '2026-10-28 17:00', 'cikis'),
             ('PG14', '2026-10-18 08:00', 'giris'), ('PG14', '2026-10-18 17:00', 'cikis')) v) x;

-- 1) Gece işi: uyarı ve havuz -----------------------------------------------------
select pdks.gece_isi_calistir('2026-10-15');
select pdks.gece_isi_calistir('2026-10-16');
select pdks.gece_isi_calistir('2026-10-17');
select test.dogrula('gece işi başarılı', (select durum = 'basarili' from pdks.gece_isi order by id desc limit 1));
select test.dogrula('plansız Cumartesi 08:00–13:00: uyarı yazıldı',
    test.uy('PG01') = '17.10.2026 tarihinde vardiya planı olmadan 08:00–13:00 arasında çalışıldı (5 sa). Süre İK kararı bekliyor.');
select test.dogrula('süre havuzda tatil çalışması (300 dk); yazılı onaylı olsa da karar bekler',
    (select tur = 'tatil_calismasi' and dakika = 300 and durum = 'inceleme_bekliyor' from test.hv('PG01', '2026-10-17')));
select test.dogrula('onaya kadar gün "vardiya yok", puantajda HT ve dakika yok',
    (select durum = 'vardiya_yok' and hesap_tamam and vardiya_id is null and fazla_mesai_dk = 0 and calisma_dk = 0
     from test.gk('PG01', '2026-10-17')) and test.kod('PG01', '2026-10-17') = 'HT 1 gün 0 dk');
select test.dogrula('çıkış ertesi sabah olabilir: dosya gelmeden karar verilmez (PG04)',
    (test.gk('PG04', '2026-10-17')).id is null and test.uy('PG04') is null);
insert into pdks.aktarim (kaynak, dosya_adi, dosya_ozeti, veri_tarihi)
values ('pdks', 'pg_18.csv', 'pg-pdks-18', '2026-10-18'), ('pdks', 'pg_19.csv', 'pg-pdks-19', '2026-10-19');
select pdks.gece_isi_calistir('2026-10-17');
select pdks.gece_isi_calistir('2026-10-18');
select pdks.gece_isi_calistir('2026-10-28');
select pdks.gece_isi_calistir('2026-10-29');
select test.dogrula('plansız gece 22:00–06:00 Cumartesi''ye yazılır (480 dk), Pazar''a ayrıca yazılmaz',
    (select dakika = 480 from test.hv('PG08', '2026-10-17')) and test.uy('PG08') like '%22:00–06:00%'
    and (test.gk('PG08', '2026-10-18')).id is null);
select test.dogrula('yeniden çalışınca kayıt ve uyarı çoğalmaz (PG01)',
    (select count(*) = 1 from pdks.uyari where tur = 'plansiz_gun_calismasi' and calisan_id = test.c('PG01'))
    and (select count(*) = 1 from pdks.fazla_mesai_inceleme where calisan_id = test.c('PG01')));
select test.dogrula('yalnızca giriş: uyarı var, havuz ve gün kaydı yok',
    test.uy('PG04') like '%çıkış okutması yok%' and (test.gk('PG04', '2026-10-17')).id is null);
select test.dogrula('yalnızca çıkış: uyarı var, havuz yok',
    test.uy('PG21') like '%giriş okutması yok%' and (test.gk('PG21', '2026-10-17')).id is null);
select test.dogrula('10 dakikalık uğrama: uyarı var, havuz yok',
    test.uy('PG05') like '%süresi kısa%' and (test.hv('PG05', '2026-10-17')).id is null);

-- 2) Plansız sayılmayanlar ---------------------------------------------------------
select test.dogrula('gece vardiyasının sabah çıkışı plansız gün değildir',
    test.uy('PG06') is null and (test.gk('PG06', '2026-10-17')).id is null
    and (select durum = 'tamam' from test.gk('PG06', '2026-10-16')));
select test.dogrula('gece vardiyasından sonra yeniden gelen: yalnızca 14:00–18:00 (240 dk)',
    (select giris_zamani = test.ts('2026-10-17 14:00') from test.gk('PG07', '2026-10-17'))
    and (select dakika = 240 from test.hv('PG07', '2026-10-17')));
select test.dogrula('ertesi günün 00-08 vardiyasına 23:50 girişi plansız gün değildir',
    test.uy('PG09') is null and (select durum = 'tamam' from test.gk('PG09', '2026-10-18')));
select test.dogrula('planlı Cumartesi eskisi gibi', test.uy('PG10') is null and (test.gk('PG10', '2026-10-17')).vardiya_id is not null);
select test.dogrula('işten ayrılmış ve henüz işe girmemiş çalışan işlenmez',
    test.uy('PG11') is null and test.uy('PG12') is null
    and (test.gk('PG11', '2026-10-17')).id is null and (test.gk('PG12', '2026-10-17')).id is null);
select test.dogrula('planı onay bekleyen gün plansız sayılmaz', test.uy('PG13') is null and (test.gk('PG13', '2026-10-17')).id is null);
select test.dogrula('plansız Pazar da havuza düşer (540 dk)',
    (select tur = 'tatil_calismasi' and dakika = 540 from test.hv('PG14', '2026-10-18')) and test.uy('PG14') is not null);

-- 3) Kim görür ----------------------------------------------------------------------
set local role authenticated;
select test.oturum('pg_amir@ornek.test');
select test.dogrula('amir yalnızca bu tür uyarıyı, yalnızca kendi çalışanları için görür',
    (select count(*) > 0 and bool_and(u.tur = 'plansiz_gun_calismasi' and c.sicil_no like 'PG__' and c.sicil_no < 'PGI')
     from pdks.uyari u join pdks.calisan c on c.id = u.calisan_id));
select test.oturum('pg_amir2@ornek.test');
select test.dogrula('başka departmanın amiri görmez', (select count(*) = 0 from pdks.uyari));
select test.oturum('pg_ik2@ornek.test');
select test.dogrula('İK görür', exists (select 1 from pdks.uyari where tur = 'plansiz_gun_calismasi'));

-- 4) Karar: T-56 ve T-57 işaretleri ----------------------------------------------------
select pdks.fazla_mesai_inceleme_karar((test.hv('PG01', '2026-10-17')).id, true);
select pdks.fazla_mesai_inceleme_karar((test.hv('PG02', '2026-10-17')).id, true);
select pdks.fazla_mesai_inceleme_karar((test.hv('PG03', '2026-10-17')).id, false, 'Çalışma yapılmamış');
select pdks.fazla_mesai_inceleme_karar((test.hv('PG08', '2026-10-17')).id, true);
select pdks.fazla_mesai_inceleme_karar((test.hv('PG14', '2026-10-18')).id, true);
select pdks.fazla_mesai_inceleme_karar((test.hv('PG22', '2026-10-15')).id, true);
select pdks.fazla_mesai_inceleme_karar((test.hv('PG23', '2026-10-29')).id, true);
select pdks.fazla_mesai_inceleme_karar((test.hv('PG24', '2026-10-28')).id, true);
reset role;
select test.dogrula('onay: Cumartesi (hafta tatili değil) çalışılmış, FM50 270 (300 − 30 mola), kod FM50 1 gün',
    (select durum = 'tamam' and fm50_dk = 270 and fm100_dk = 0 and calisma_dk = 270 and mola_dk = 30 from test.gk('PG01', '2026-10-17'))
    and test.kod('PG01', '2026-10-17') = 'FM50 1 gün 270 dk' and not (test.hv('PG01', '2026-10-17')).yazili_onaysiz);
select test.dogrula('canlı puantajda çalışılan gün ve dakika',
    (select calisilan_gun = 2 and fm50_dk = 270 from pdks.v_puantaj_canli where calisan_id = test.c('PG01') and ay = 10));
select test.dogrula('yazılı onay yoksa da puantaja girer, işaretlenir (T-56)',
    (select fm50_dk = 270 from test.gk('PG02', '2026-10-17')) and (test.hv('PG02', '2026-10-17')).yazili_onaysiz);
select test.dogrula('ret: gün "vardiya yok" ve HT kalır',
    (select durum = 'vardiya_yok' and fazla_mesai_dk = 0 from test.gk('PG03', '2026-10-17'))
    and test.kod('PG03', '2026-10-17') = 'HT 1 gün 0 dk');
select test.dogrula('plansız Cumartesi gecesi: FM50 420 ve gece çalışması 420',
    (select fm50_dk = 420 and gece_calisma_dk = 420 from test.gk('PG08', '2026-10-17')));
select test.dogrula('hafta içi plansız gün: FM50 270, FM100 yok, kod FM50',
    (select fm50_dk = 270 and fm100_dk = 0 from test.gk('PG22', '2026-10-15')) and test.kod('PG22', '2026-10-15') = 'FM50 1 gün 270 dk');
select test.dogrula('plansız Pazar: FM100 480, FM50 yok, kod FM100',
    (select fm100_dk = 480 and fm50_dk = 0 from test.gk('PG14', '2026-10-18')) and test.kod('PG14', '2026-10-18') = 'FM100 1 gün 480 dk');
select test.dogrula('plansız resmi tatil: FM100 270',
    (select fm100_dk = 270 and fm50_dk = 0 from test.gk('PG23', '2026-10-29')) and test.kod('PG23', '2026-10-29') = 'FM100 1 gün 270 dk');
select test.dogrula('plansız arife: 13:00 öncesi FM50 240, sonrası FM100 240',
    (select fm50_dk = 240 and fm100_dk = 240 and calisma_dk = 480 from test.gk('PG24', '2026-10-28')));
update pdks.ayar set deger = 1 where anahtar = 'cumartesi_hafta_sonu';
select test.dogrula('cumartesi_hafta_sonu açıksa plansız Cumartesi FM100 270',
    (select fm100_dk = 270 and fm50_dk = 0 from pdks.gun_hesabi(test.c('PG01'), '2026-10-17', null, null,
        test.ts('2026-10-17 08:00'), test.ts('2026-10-17 13:00'))));
update pdks.ayar set deger = 0 where anahtar = 'cumartesi_hafta_sonu';
select test.dogrula('yıllık toplamda sayılır (T-57)', pdks.fm_yillik_toplam(test.c('PG01'), 2026) = 300);
update pdks.ayar set deger = 200 where anahtar = 'fm_yillik_sinir_dk';
set local role authenticated;
select test.oturum('pg_ik2@ornek.test');
select pdks.fazla_mesai_inceleme_karar((test.hv('PG17', '2026-10-17')).id, true);
reset role;
update pdks.ayar set deger = 16200 where anahtar = 'fm_yillik_sinir_dk';
select test.dogrula('yıllık sınır aşılınca işaretlenir (T-57)', (test.hv('PG17', '2026-10-17')).yillik_sinir_asildi);
set local role authenticated;
select test.oturum('pg_ik1@ornek.test');
select test.hata('İK kendi plansız gününe karar veremez', 'Görevler ayrılığı',
    format('select pdks.fazla_mesai_inceleme_karar(%s, true)', (test.hv('PGI1', '2026-10-17')).id));

-- 5) Düzeltme ve geriye dönük plan ---------------------------------------------------
select pdks.kayit_duzelt((test.gk('PG18', '2026-10-17')).id, 'cikis_zamani', '2026-10-17 15:00+03', 'Kamera kaydı 15:00');
reset role;
select test.dogrula('karardan önce saat düzeltilirse havuz süresi güncellenir (420 dk)',
    (select dakika = 420 and durum = 'inceleme_bekliyor' from test.hv('PG18', '2026-10-17'))
    and (select durum = 'vardiya_yok' and hesap_tamam from test.gk('PG18', '2026-10-17')));
set local role authenticated;
select test.oturum('pg_amir@ornek.test');
select pdks.vardiya_plani_gir(test.c('PG15'), '2026-10-17', (select id from pdks.vardiya_tanim where kod = 'GUNDUZ'), 'Plan unutulmuş');
select pdks.vardiya_plani_gir(test.c('PG16'), '2026-10-17', (select id from pdks.vardiya_tanim where kod = 'GUNDUZ'), 'Plan unutulmuş');
select test.oturum('pg_ik2@ornek.test');
select pdks.vardiya_plani_onayla((select id from pdks.vardiya_plani where calisan_id = test.c('PG15') and tarih = '2026-10-17'), true);
reset role;
select test.dogrula('geriye dönük plan: gün plana göre hesaplandı, havuz kaydı kapandı',
    (select durum = 'tamam' and hesap_tamam and vardiya_id is not null and calisma_dk = 270 and erken_cikis_dk = 240 and fm100_dk = 0
     from test.gk('PG15', '2026-10-17'))
    and (select durum = 'reddedildi' and karar_aciklama like '%plana göre%' from test.hv('PG15', '2026-10-17')));
set local role authenticated;
select test.oturum('pg_ik2@ornek.test');
select pdks.fazla_mesai_inceleme_karar((test.hv('PG16', '2026-10-17')).id, true);
select test.hata('havuz onaylandıysa geriye dönük plan onaylanmaz', 'havuzdan onaylanmıştır',
    $$select pdks.vardiya_plani_onayla((select id from pdks.vardiya_plani where calisan_id = test.c('PG16') and tarih = '2026-10-17'), true)$$);
reset role;

-- 6) Ay kilidi -----------------------------------------------------------------------
delete from pdks.vardiya_plani where calisan_id in (test.c('PG13'), test.c('PG16'));
set local role authenticated;
select test.oturum('pg_ik2@ornek.test');
select test.hata('kararı bekleyen plansız gün ay kilidini durdurur', 'onaysız fazla mesai',
    $$select pdks.ay_kilitle(2026::smallint, 10::smallint)$$);
select pdks.ay_kilitle(2026::smallint, 10::smallint, true);
select pdks.fazla_mesai_inceleme_karar((test.hv('PG20', '2026-10-17')).id, true);
reset role;
select test.dogrula('kilitten sonra onay: gün değişmez, FM50 270 fark olur',
    (select fark_satiri and fm50_etki_dk = 270 and fm100_etki_dk = 0 and calisma_etki_dk = 270 from test.hv('PG20', '2026-10-17'))
    and (select durum = 'vardiya_yok' from test.gk('PG20', '2026-10-17')));
select test.dogrula('kilitli puantajda onaylı plansız gün FM50, NÇ + FM50 + FM100 = çalışma',
    (select s.fm50_dk = 270 and s.fm100_dk = 0 and s.calisma_dk = (select sum(k.dakika) from pdks.puantaj_kalemi k where k.puantaj_satiri_id = s.id)
     from pdks.puantaj_satiri s join pdks.donem d on d.id = s.donem_id
     where s.calisan_id = test.c('PG02') and d.yil = 2026 and d.ay = 10 and s.satir_turu = 'normal'));
select test.dogrula('gece_isi_plansiz ekrandan çağrılamaz',
    not has_function_privilege('authenticated', 'pdks.gece_isi_plansiz(date, bigint)', 'execute'));

do $$ begin raise notice 'TÜM TESTLER GEÇTİ'; end $$;
rollback;
