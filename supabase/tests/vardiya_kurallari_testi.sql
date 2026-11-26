-- =====================================================================
-- Vardiya kuralları testleri (20261124010000_vardiya_kurallari.sql)
--   yeni vardiyalar · mola (m.68) · esnek mesai · otomatik vardiya tanıma ·
--   vardiya düzeltmesinin planlı saatleri güncellemesi
-- Testin kendi sahte verisi (Ekim 2026) kullanılır; örnek veri yüklü olsun
-- olmasın çalışır. Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/vardiya_kurallari_testi.sql
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
create function test.v(p text) returns smallint language sql security definer as $$
    select id from pdks.vardiya_tanim where kod = p $$;
create function test.gk(p_sicil text, p_gun date) returns pdks.gun_kaydi language sql security definer as $$
    select * from pdks.gun_kaydi where calisan_id = test.c(p_sicil) and is_gunu = p_gun $$;
create function test.soru(p_sicil text, p_gun date, p_tur text) returns pdks.amir_sorusu language sql security definer as $$
    select q.* from pdks.amir_sorusu q where q.gun_kaydi_id = (test.gk(p_sicil, p_gun)).id and q.soru_turu = p_tur $$;
create function test.ts(p text) returns timestamptz language sql immutable as $$
    select (p::timestamp) at time zone 'Europe/Istanbul' $$;
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
insert into pdks.departman (ad) values ('VK Üretim'), ('VK İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = d), '2025-01-01'
from (values ('VK01', 'VK Üretim'), ('VK02', 'VK Üretim'), ('VK03', 'VK Üretim'), ('VK04', 'VK Üretim'),
             ('VK05', 'VK Üretim'), ('VK06', 'VK Üretim'), ('VKA1', 'VK Üretim'), ('VKI1', 'VK İdari')) v(s, d);
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('VK Amir', 'vk_amir@ornek.test', 'amir', test.c('VKA1'), '00000000-0000-0000-0000-0000000000f1'),
    ('VK İK',   'vk_ik@ornek.test',   'ik',   test.c('VKI1'), '00000000-0000-0000-0000-0000000000f2');
update pdks.departman set amir_id = test.k('vk_amir@ornek.test') where ad = 'VK Üretim';
insert into pdks.kart (kart_no, calisan_id)
select 'VK-' || s, test.c(s) from unnest(array['VK01', 'VK02', 'VK03', 'VK04', 'VK05', 'VK06']) s;
insert into pdks.okuyucu (kod, ad, sistem) values ('VK-PDKS', 'VK PDKS', 'pdks');

insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id, giren_id)
select test.c(s), t::date, test.v(v), test.k('vk_ik@ornek.test')
from (values ('VK01', '2026-10-05', 'AKSAM_8'),
             ('VK02', '2026-10-06', 'GECE_8'),
             ('VK03', '2026-10-05', 'BEYAZ'),
             ('VK04', '2026-10-05', 'ESNEK'), ('VK04', '2026-10-06', 'ESNEK'), ('VK04', '2026-10-07', 'ESNEK'),
             ('VK04', '2026-10-08', 'ESNEK'), ('VK04', '2026-10-09', 'ESNEK'),
             ('VK05', '2026-10-07', 'GUNDUZ_8'),
             ('VK06', '2026-10-07', 'GUNDUZ_8')) x(s, t, v);
insert into pdks.izin (calisan_id, tur, baslangic, bitis, giren_id)
values (test.c('VK04'), 'yillik', '2026-10-08', '2026-10-08', test.k('vk_ik@ornek.test'));

insert into pdks.aktarim (kaynak, dosya_adi, dosya_ozeti, veri_tarihi)
select 'pdks', 'vk_' || g::date || '.csv', 'vk-pdks-' || g::date, g::date
from generate_series(date '2026-10-01', date '2026-10-10', interval '1 day') g;

insert into pdks.ham_okutma (aktarim_id, okuyucu_id, kart_no, okutma_zamani, yon)
select (select id from pdks.aktarim where dosya_ozeti = 'vk-pdks-' || (z::timestamp)::date),
       (select id from pdks.okuyucu where kod = 'VK-PDKS'), 'VK-' || s, test.ts(z), y
from (values
    ('VK01', '2026-10-05 15:55', 'giris'), ('VK01', '2026-10-06 00:03', 'cikis'),   -- Akşam 16-24
    ('VK02', '2026-10-05 23:50', 'giris'), ('VK02', '2026-10-06 08:02', 'cikis'),   -- Gece 00-08
    ('VK03', '2026-10-05 08:25', 'giris'), ('VK03', '2026-10-05 18:05', 'cikis'),   -- Beyaz yaka
    ('VK04', '2026-10-05 09:40', 'giris'), ('VK04', '2026-10-05 18:10', 'cikis'),   -- Esnek
    ('VK04', '2026-10-06 07:30', 'giris'), ('VK04', '2026-10-06 15:00', 'cikis'),
    ('VK04', '2026-10-07 10:00', 'giris'), ('VK04', '2026-10-07 21:30', 'cikis'),
    ('VK04', '2026-10-09 08:00', 'giris'), ('VK04', '2026-10-09 15:00', 'cikis'),
    ('VK05', '2026-10-07 15:58', 'giris'), ('VK05', '2026-10-08 00:04', 'cikis'),   -- plan 08-16, çalıştığı 16-24
    ('VK06', '2026-10-07 08:02', 'giris')) v(s, z, y);                               -- çıkış yok

-- VK07 (esnek, ayrı departman): PDKS girişi yok, yalnızca kapı kaydı var (20261129010000_esnek_kanit)
--   6 Ekim: kapı 09:12, PDKS çıkış 17:30   → giriş 09:17 yazılır, soru yok
--   7 Ekim: kapı 18:00, PDKS çıkış 17:00   → kanıt çıkıştan sonra: yazılmaz, amire sorulur
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
values ('VK07', 'AdVK07', 'Örnek', (select id from pdks.departman where ad = 'VK İdari'), '2025-01-01');
insert into pdks.kart (kart_no, calisan_id) values ('VK-VK07', test.c('VK07'));
insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id, giren_id)
select test.c('VK07'), t, test.v('ESNEK'), test.k('vk_ik@ornek.test') from unnest(array['2026-10-06', '2026-10-07']::date[]) t;
insert into pdks.okuyucu (kod, ad, sistem) values ('VK-KAPI', 'VK kapı', 'kapi');
insert into pdks.aktarim (kaynak, dosya_adi, dosya_ozeti, veri_tarihi)
select 'kapi', 'vk_kapi_' || g || '.csv', 'vk-kapi-' || g, g from unnest(array['2026-10-06', '2026-10-07']::date[]) g;
insert into pdks.ham_okutma (aktarim_id, okuyucu_id, kart_no, okutma_zamani, yon)
select (select id from pdks.aktarim where dosya_ozeti = 'vk-pdks-' || (z::timestamp)::date),
       (select id from pdks.okuyucu where kod = 'VK-PDKS'), 'VK-VK07', test.ts(z), 'cikis'
from unnest(array['2026-10-06 17:30', '2026-10-07 17:00']) z;
insert into pdks.kanit_kaydi (aktarim_id, okuyucu_id, kaynak, kart_no, okutma_zamani, yon)
select (select id from pdks.aktarim where dosya_ozeti = 'vk-kapi-' || (z::timestamp)::date),
       (select id from pdks.okuyucu where kod = 'VK-KAPI'), 'kapi', 'VK-VK07', test.ts(z), 'giris'
from unnest(array['2026-10-06 09:12', '2026-10-07 18:00']) z;

do $$
declare d date;
begin
    for d in select g::date from generate_series(date '2026-10-04', date '2026-10-09', interval '1 day') g loop
        perform pdks.gece_isi_calistir(d);
    end loop;
end $$;
select test.dogrula('hazırlık: gece işi hatasız çalıştı',
    not exists (select 1 from pdks.gece_isi where islenen_gun between '2026-10-04' and '2026-10-09' and durum <> 'basarili'));

-- 1) Vardiya tanımları ---------------------------------------------------------
select test.dogrula('yeni vardiyalar tanımlı: 08-16, 16-24, 00-08, 08:30-18:00, esnek',
    (select count(*) = 5 from pdks.vardiya_tanim where kod in ('GUNDUZ_8', 'AKSAM_8', 'GECE_8', 'BEYAZ', 'ESNEK'))
    and (select baslangic = '08:30' and bitis = '18:00' from pdks.vardiya_tanim where kod = 'BEYAZ')
    and (select esnek from pdks.vardiya_tanim where kod = 'ESNEK'));
select test.dogrula('eski vardiyalar duruyor (GUNDUZ, V1, V2, V3)',
    (select count(*) = 4 from pdks.vardiya_tanim where kod in ('GUNDUZ', 'V1', 'V2', 'V3') and aktif));
select test.dogrula('16-24 gece yarısını aşar sayılır, 00-08 aşmaz',
    (select gece_yarisini_asar from pdks.vardiya_tanim where kod = 'AKSAM_8')
    and (select not gece_yarisini_asar from pdks.vardiya_tanim where kod = 'GECE_8'));

-- 2) Mola (m.68) -----------------------------------------------------------------
select test.dogrula('mola sınırları: 4 saate kadar 15, 4–7,5 saat 30, 7,5 saat üstü 60 dk',
    pdks.mola_suresi(0) = 0 and pdks.mola_suresi(200) = 15 and pdks.mola_suresi(240) = 15
    and pdks.mola_suresi(241) = 30 and pdks.mola_suresi(450) = 30 and pdks.mola_suresi(451) = 60);
update pdks.ayar set deger = 45 where anahtar = 'mola_uzun_dk';
select test.dogrula('mola süresi ayardan gelir (uzun mola 45 dk yapılınca)',
    pdks.mola_suresi(480) = 45);
update pdks.ayar set deger = 60 where anahtar = 'mola_uzun_dk';

-- 3) Yeni vardiyalarla gün kaydı ----------------------------------------------------
select test.dogrula('16-24: 00:03 çıkışı aynı iş gününe yazıldı; çalışma 480 − 60 = 420 dk; gece 240 − 30 = 210 dk',
    (select durum = 'tamam' and mola_dk = 60 and calisma_dk = 420 and gece_calisma_dk = 210
            and cikis_zamani = test.ts('2026-10-06 00:03') from test.gk('VK01', '2026-10-05')));
select test.dogrula('00-08: önceki akşam 23:50 girişi vardiyanın başladığı güne (6 Ekim) yazıldı',
    (select durum = 'tamam' and giris_zamani = test.ts('2026-10-05 23:50') and calisma_dk = 420
            and gece_calisma_dk = 315 from test.gk('VK02', '2026-10-06'))
    and (select (test.gk('VK02', '2026-10-05')).id is null));
select test.dogrula('beyaz yaka 08:30-18:00: 08:25 giriş geç değil; çalışma 570 − 60 = 510 dk',
    (select gec_kalma_dk = 0 and erken_cikis_dk = 0 and calisma_dk = 510 from test.gk('VK03', '2026-10-05')));

-- 4) Esnek mesai ---------------------------------------------------------------------
select test.dogrula('esnek: 09:40 giriş geç sayılmaz, 18:10 çıkış fazla mesai değil; 510 − 60 = 450 dk',
    (select gec_kalma_dk = 0 and erken_cikis_dk = 0 and fazla_mesai_dk = 0 and calisma_dk = 450
     from test.gk('VK04', '2026-10-05')));
select test.dogrula('esnek: 15:00 çıkış erken çıkış sayılmaz; 450 − 30 = 420 dk',
    (select erken_cikis_dk = 0 and calisma_dk = 420 from test.gk('VK04', '2026-10-06')));
select test.dogrula('esnek: 21:30 çıkış (19:00 sonrası) tümü çalışma, havuz ve fazla mesai uyarısı yok',
    (select calisma_dk = 630 and fazla_mesai_dk = 0 from test.gk('VK04', '2026-10-07'))
    and not exists (select 1 from pdks.fazla_mesai_inceleme where calisan_id = test.c('VK04'))
    and not exists (select 1 from pdks.uyari where calisan_id = test.c('VK04')
                    and tur in ('fm_plansiz_calisma', 'fm_onay_yok')));
select test.dogrula('esnek ay özeti: 4 hedef gün (izin hariç), hedef 1920, gerçekleşen 1890, fark −30 dk',
    (select hedef_gun = 4 and hedef_dk = 1920 and gerceklesen_dk = 1890 and fark_dk = -30 and bekleyen_gun = 0
     from pdks.v_esnek_mesai where calisan_id = test.c('VK04') and yil = 2026 and ay = 10));
select test.dogrula('canlı puantajda esnek hedef ve fark; esnek olmayanda 0',
    (select esnek_hedef_dk = 1920 and esnek_fark_dk = -30 and mola_dk = 180   -- 60 + 30 + 60 + 30
     from pdks.v_puantaj_canli where calisan_id = test.c('VK04') and yil = 2026 and ay = 10)
    and (select esnek_hedef_dk = 0 and esnek_fark_dk = 0
         from pdks.v_puantaj_canli where calisan_id = test.c('VK03') and yil = 2026 and ay = 10));

-- 4b) Esnek mesaide eksik giriş: kanıt saati doğrudan yazılır ---------------------------
select test.dogrula('esnek, PDKS girişi yok: kapı 09:12 + 5 dk yürüme → giriş 09:17 kanıtla yazıldı',
    (select giris_zamani = test.ts('2026-10-06 09:17') and giris_kaynagi = 'kanit' and durum = 'tamam'
            and gec_kalma_dk = 0 and calisma_dk = 433   -- 09:17–17:30 = 493 dk − 60 dk mola
     from test.gk('VK07', '2026-10-06')));
select test.dogrula('esnek düzeltme izi: kaynak gece işi, dayanak kapı kaydı, gerekçede kapı kaydı ve yürüme süresi',
    exists (select 1 from pdks.duzeltme d where d.gun_kaydi_id = (test.gk('VK07', '2026-10-06')).id
            and d.alan = 'giris_zamani' and d.kaynak = 'gece_isi' and d.kanit_kaydi_id is not null
            and d.gerekce like 'Kapı kaydı 09:12; yürüme süresi eklenerek%'));
select test.dogrula('esnek: amire "kanıt vardiya başından sonra" sorusu açılmadı',
    not exists (select 1 from pdks.amir_sorusu where gun_kaydi_id = (test.gk('VK07', '2026-10-06')).id));
select test.dogrula('esnek: kanıt PDKS çıkışından sonraysa yazılmaz, gün amire / İK''ya sorulur',
    (select giris_zamani is null and durum = 'soru_bekliyor' from test.gk('VK07', '2026-10-07'))
    and exists (select 1 from pdks.amir_sorusu where gun_kaydi_id = (test.gk('VK07', '2026-10-07')).id
                and soru_turu = 'kanit_vardiya_sonrasi'));

-- 5) Otomatik vardiya tanıma -------------------------------------------------------------
select test.dogrula('planı 08-16, okutmaları 16-24: vardiya uyuşmazlığı sorusu, öneri Akşam (16-24)',
    (select q.onerilen_vardiya_id = test.v('AKSAM_8') and q.onerilen_zaman = test.ts('2026-10-07 15:58')
            and q.onerilen_cikis = test.ts('2026-10-08 00:04') and q.atanan_id = test.k('vk_amir@ornek.test')
            and q.durum = 'acik'
     from test.soru('VK05', '2026-10-07', 'vardiya_uyusmazligi') q));
select test.dogrula('öneri kaydı değiştirmedi; başka soru açılmadı',
    (select vardiya_id = test.v('GUNDUZ_8') and durum = 'soru_bekliyor' from test.gk('VK05', '2026-10-07'))
    and (select count(*) = 1 from pdks.amir_sorusu where gun_kaydi_id = (test.gk('VK05', '2026-10-07')).id));
select test.dogrula('başka vardiyaya uymayan eksik gün için normal soru (çıkış yok), öneri yok',
    (select q.onerilen_vardiya_id is null from test.soru('VK06', '2026-10-07', 'cikis_yok') q)
    and (select (test.soru('VK06', '2026-10-07', 'vardiya_uyusmazligi')).id is null));

set local role authenticated;
select test.oturum('vk_amir@ornek.test');
select pdks.soru_cevapla((test.soru('VK05', '2026-10-07', 'vardiya_uyusmazligi')).id, 'geldi_saat_dogru');
reset role;
select pdks.gece_isi_calistir('2026-10-07');

select test.dogrula('amir onayı: vardiya 16-24, planlı saatler ve giriş/çıkış öneriye göre düzeltildi',
    (select vardiya_id = test.v('AKSAM_8') and planli_baslangic = test.ts('2026-10-07 16:00')
            and planli_bitis = test.ts('2026-10-08 00:00') and giris_zamani = test.ts('2026-10-07 15:58')
            and cikis_zamani = test.ts('2026-10-08 00:04') from test.gk('VK05', '2026-10-07')));
select test.dogrula('düzeltme izi: vardiya, giriş, çıkış; kaynak amir, dayanak soru',
    (select count(*) = 3 and bool_and(kaynak = 'amir' and soru_id is not null)
     from pdks.duzeltme where gun_kaydi_id = (test.gk('VK05', '2026-10-07')).id));
select test.dogrula('düzeltilen gün yeni vardiyaya göre hesaplandı: geç 0, çalışma 420 dk',
    (select durum = 'tamam' and hesap_tamam and gec_kalma_dk = 0 and calisma_dk = 420
     from test.gk('VK05', '2026-10-07')));

-- 6) Vardiya düzeltmesi planlı saatleri günceller ----------------------------------------
select pdks.duzeltme_uygula((test.gk('VK03', '2026-10-05')).id, 'vardiya_id', test.v('GUNDUZ_8')::text,
                            'Test: vardiya düzeltmesi', 'ik', test.k('vk_ik@ornek.test'));
select test.dogrula('İK vardiya düzeltmesi: planlı başlangıç / bitiş 08:00–16:00 oldu',
    (select planli_baslangic = test.ts('2026-10-05 08:00') and planli_bitis = test.ts('2026-10-05 16:00')
            and not hesap_tamam from test.gk('VK03', '2026-10-05')));

-- 7) Ay kilidi: mola ve esnek sütunları puantaja yazılır --------------------------------------
set local role authenticated;
select test.oturum('vk_ik@ornek.test');
select pdks.ay_kilitle(2026::smallint, 10::smallint, true, 'Test: zorla kilit gerekçesi');
reset role;
select test.dogrula('kilitli puantaj: esnek hedef 1920, fark −30, mola 180 dk',
    (select s.esnek_hedef_dk = 1920 and s.esnek_fark_dk = -30 and s.mola_dk = 180 and s.calisma_dk = 1890
     from pdks.puantaj_satiri s join pdks.donem d on d.id = s.donem_id
     where s.calisan_id = test.c('VK04') and d.yil = 2026 and d.ay = 10 and s.satir_turu = 'normal'));

-- 8) Yetkiler ------------------------------------------------------------------------------
select test.dogrula('iç fonksiyonlar uygulamaya kapalı; esnek görünümü okunabilir',
    not has_function_privilege('authenticated', 'pdks.vardiya_onerisi(bigint)', 'execute')
    and not has_function_privilege('authenticated', 'pdks.mola_suresi(integer)', 'execute')
    and has_table_privilege('authenticated', 'pdks.v_esnek_mesai', 'select'));
set local role authenticated;
select test.oturum('vk_amir@ornek.test');
select test.dogrula('amir esnek özetinde yalnızca kendi departmanını görür',
    (select count(*) = 1 and bool_and(calisan_id = test.c('VK04')) from pdks.v_esnek_mesai));
reset role;

do $$ begin raise notice 'VARDİYA KURALLARI TESTLERİ GEÇTİ'; end $$;
rollback;
