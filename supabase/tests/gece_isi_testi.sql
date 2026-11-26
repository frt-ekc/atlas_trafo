-- =====================================================================
-- Gece işi testleri (20261120010000_gece_isi.sql)
--   A) Testin kendi sahte verisiyle (Ekim 2026) mekanik: her zaman çalışır.
--   B) Örnek veri (seed.sql) yüklüyse Kasım'ın tamamı işlenir ve
--      docs/ornek_veri.md'deki S1–S23 tek tek kontrol edilir; yoksa atlanır.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/gece_isi_testi.sql
-- =====================================================================
\pset tuples_only on
\pset format unaligned
begin;
set local timezone = 'Europe/Istanbul';
-- T-18: gece işi bugünden ileri bir günü işlemez; örnek veri Kasım'ın tamamını kapsar, demo günü esas alınır
set local pdks.test_bugun = '2026-12-07';

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
create function test.gk(p_sicil text, p_gun date) returns pdks.gun_kaydi language sql security definer as $$
    select * from pdks.gun_kaydi where calisan_id = test.c(p_sicil) and is_gunu = p_gun $$;
create function test.soru(p_sicil text, p_gun date, p_tur text) returns pdks.amir_sorusu language sql security definer as $$
    select q.* from pdks.amir_sorusu q join pdks.gun_kaydi g on g.id = q.gun_kaydi_id
    where g.calisan_id = test.c(p_sicil) and g.is_gunu = p_gun and q.soru_turu = p_tur $$;
create function test.ts(p text) returns timestamptz language sql immutable as $$
    select (p::timestamp) at time zone 'Europe/Istanbul' $$;
-- Gece işini çalıştırır, sonra (ayrı bir adımda) sonucunu okur
create function test.calistir(p_gun date) returns text language plpgsql as $$
declare v_id bigint;
begin
    v_id := pdks.gece_isi_calistir(p_gun);
    return (select durum || coalesce(': ' || hata_mesaji, '') from pdks.gece_isi where id = v_id);
end $$;
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

-- =====================================================================
-- A) Mekanik: testin kendi verisi, 6 Ekim 2026 (Salı)
-- =====================================================================
insert into pdks.departman (ad) values ('GT Üretim'), ('GT Yönetim');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = d), '2025-01-01'
from (values ('GT01', 'GT Üretim'), ('GT02', 'GT Üretim'), ('GT03', 'GT Üretim'), ('GT04', 'GT Üretim'),
             ('GT05', 'GT Üretim'), ('GT06', 'GT Üretim'), ('GT07', 'GT Üretim'),
             ('GTA1', 'GT Üretim'), ('GTU1', 'GT Yönetim'), ('GTI1', 'GT Yönetim')) v(s, d);

-- GTU1: üst amir (kendisinin üst amiri yok); GTA1: GT Üretim amiri, üst amiri GTU1
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('GT Üst',  'gt_ust@ornek.test',  'amir', test.c('GTU1'), '00000000-0000-0000-0000-0000000000f1'),
    ('GT İK',   'gt_ik@ornek.test',   'ik',   test.c('GTI1'), '00000000-0000-0000-0000-0000000000f3');
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, ust_amir_id, auth_kullanici_id) values
    ('GT Amir', 'gt_amir@ornek.test', 'amir', test.c('GTA1'), test.k('gt_ust@ornek.test'), '00000000-0000-0000-0000-0000000000f2');
update pdks.departman set amir_id = test.k('gt_amir@ornek.test') where ad = 'GT Üretim';
update pdks.departman set amir_id = test.k('gt_ust@ornek.test')  where ad = 'GT Yönetim';

insert into pdks.kart (kart_no, calisan_id)
select 'GT-' || sicil_no, id from pdks.calisan where sicil_no like 'GT%';
insert into pdks.okuyucu (kod, ad, sistem) values ('GT-PDKS', 'GT PDKS', 'pdks'), ('GT-KAPI', 'GT kapı', 'kapi');

-- Herkes (İK hariç) 6 Ekim gündüz vardiyasında
insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id, giren_id)
select id, '2026-10-06', (select id from pdks.vardiya_tanim where kod = 'GUNDUZ'), test.k('gt_ik@ornek.test')
from pdks.calisan where sicil_no like 'GT%' and sicil_no <> 'GTI1';

-- 6 Ekim için yalnızca PDKS ve kapı dosyası (yemekhane ve servis gelmedi)
insert into pdks.aktarim (kaynak, dosya_adi, dosya_ozeti, veri_tarihi)
values ('pdks', 'gt_pdks.csv', 'gt-pdks-20261006', '2026-10-06'),
       ('kapi', 'gt_kapi.csv', 'gt-kapi-20261006', '2026-10-06');

insert into pdks.ham_okutma (aktarim_id, okuyucu_id, kart_no, okutma_zamani, yon)
select (select id from pdks.aktarim where dosya_ozeti = 'gt-pdks-20261006'),
       (select id from pdks.okuyucu where kod = 'GT-PDKS'), k, test.ts(z), y
from (values
    ('GT-GT01', '2026-10-06 07:50:00', 'giris'), ('GT-GT01', '2026-10-06 17:03:00', 'cikis'),  -- normal
                                                 ('GT-GT02', '2026-10-06 17:04:00', 'cikis'),  -- giriş yok, kapı 07:40
                                                 ('GT-GT03', '2026-10-06 17:05:00', 'cikis'),  -- giriş yok, kapı 08:30
                                                                                               -- GT04: hiç kayıt yok
    ('GT-GT05', '2026-10-06 07:52:00', 'giris'), ('GT-GT05', '2026-10-06 07:52:30', 'giris'),  -- mükerrer
    ('GT-GT05', '2026-10-06 17:06:00', 'cikis'),
    ('GT-GT06', '2026-10-06 08:20:00', 'giris'), ('GT-GT06', '2026-10-06 17:07:00', 'cikis'),  -- 20 dk geç
    ('GT-GT07', '2026-10-06 07:54:00', 'giris'), ('GT-GT07', '2026-10-06 18:00:00', 'cikis')   -- 60 dk fazla, onay yok
) v(k, z, y);

insert into pdks.kanit_kaydi (aktarim_id, okuyucu_id, kaynak, kart_no, okutma_zamani, yon)
select (select id from pdks.aktarim where dosya_ozeti = 'gt-kapi-20261006'),
       (select id from pdks.okuyucu where kod = 'GT-KAPI'), 'kapi', k, test.ts(z), 'giris'
from (values ('GT-GT02', '2026-10-06 07:40:00'), ('GT-GT03', '2026-10-06 08:30:00')) v(k, z);

-- 1) Çalıştırma --------------------------------------------------------
select test.dogrula('6 Ekim gece işi başarılı',
    test.calistir('2026-10-06') = 'basarili');
select test.dogrula('planı olan 9 kişiye gün kaydı açıldı',
    (select count(*) = 9 from pdks.gun_kaydi g join pdks.calisan c on c.id = g.calisan_id
     where c.sicil_no like 'GT%' and g.is_gunu = '2026-10-06'));

-- 2) Hesap -------------------------------------------------------------
select test.dogrula('normal gün: tamam, geç/erken 0, çalışma 480 dk (540 − 60 dk mola)',
    (select durum = 'tamam' and hesap_tamam and gec_kalma_dk = 0 and erken_cikis_dk = 0 and calisma_dk = 480
            and fazla_mesai_dk = 0
     from test.gk('GT01', '2026-10-06')));
select test.dogrula('20 dk geç kalma hesaplandı (çalışma 520 − 60 dk mola)',
    (select gec_kalma_dk = 20 and calisma_dk = 460 from test.gk('GT06', '2026-10-06')));

-- 3) Kanıtla düzeltme ----------------------------------------------------
select test.dogrula('kapı 07:40 + yürüme payı < 08:00: giriş 08:00 yazıldı (kaynak kanıt)',
    (select giris_zamani = test.ts('2026-10-06 08:00') and giris_kaynagi = 'kanit' from test.gk('GT02', '2026-10-06')));
select test.dogrula('düzeltme izi: kaynak gece_isi, dayanak kapı kaydı',
    exists (select 1 from pdks.duzeltme d
            where d.gun_kaydi_id = (test.gk('GT02', '2026-10-06')).id and d.kaynak = 'gece_isi'
              and d.alan = 'giris_zamani' and d.kanit_kaydi_id is not null));

-- 4) Sorular ve kime gittiği --------------------------------------------
select test.dogrula('kapı 08:30: düzeltme yok, amire "kanıt vardiya sonrası" sorusu (öneri 08:35)',
    (select q.onerilen_zaman = test.ts('2026-10-06 08:35') and q.atanan_id = test.k('gt_amir@ornek.test')
     from test.soru('GT03', '2026-10-06', 'kanit_vardiya_sonrasi') q)
    and (select durum = 'soru_bekliyor' and giris_zamani is null from test.gk('GT03', '2026-10-06')));
select test.dogrula('hiç kayıt yok: "hic_kayit_yok" sorusu amire, son cevap 4 gün sonra',
    (select q.atanan_id = test.k('gt_amir@ornek.test') and q.son_cevap_tarihi = '2026-10-10'
     from test.soru('GT04', '2026-10-06', 'hic_kayit_yok') q));
select test.dogrula('amirin kendi sorusu üst amirine gider',
    (select q.atanan_id = test.k('gt_ust@ornek.test') from test.soru('GTA1', '2026-10-06', 'hic_kayit_yok') q));
select test.dogrula('üst amiri olmayan amirin kendi sorusu İK''ya gider',
    (select pdks.kullanici_rolu(q.atanan_id) = 'ik' from test.soru('GTU1', '2026-10-06', 'hic_kayit_yok') q));

-- 5) İşaretleme ----------------------------------------------------------
select test.dogrula('30 sn sonraki ikinci giriş mükerrer işaretlendi; giriş ilk okutma',
    (select count(*) = 1 from pdks.okutma_isareti i join pdks.ham_okutma h on h.id = i.ham_okutma_id
     where h.kart_no = 'GT-GT05' and i.isaret = 'mukerrer' and h.okutma_zamani = test.ts('2026-10-06 07:52:30'))
    and (select giris_zamani = test.ts('2026-10-06 07:52') from test.gk('GT05', '2026-10-06')));

-- 6) Uyarılar ------------------------------------------------------------
select test.dogrula('yazılı onayı olmadan 60 dk kalan için fm_onay_yok uyarısı',
    exists (select 1 from pdks.uyari where tur = 'fm_onay_yok' and calisan_id = test.c('GT07')));
select test.dogrula('fazla mesai puantaja yazılmadı (plan yok)',
    (select fazla_mesai_dk = 0 and calisma_dk = 480 from test.gk('GT07', '2026-10-06')));
select test.dogrula('yemekhane ve servis dosyası gelmedi uyarısı',
    (select count(*) = 2 from pdks.uyari where tur = 'dosya_gelmedi'
     and tekillik_anahtari in ('yemekhane:2026-10-06', 'servis:2026-10-06')));

-- 7) Tekrar çalıştırmak hiçbir şeyi çoğaltmaz ------------------------------
create temp table sayim_once as
select (select count(*) from pdks.gun_kaydi) gk, (select count(*) from pdks.duzeltme) dz,
       (select count(*) from pdks.amir_sorusu) sr, (select count(*) from pdks.uyari) uy,
       (select count(*) from pdks.okutma_isareti) oi;
select test.dogrula('aynı gün ikinci kez çalıştı, başarılı',
    test.calistir('2026-10-06') = 'basarili');
select test.dogrula('ikinci çalıştırma kayıt, düzeltme, soru, uyarı, işaret çoğaltmadı',
    (select (select count(*) from pdks.gun_kaydi) = gk and (select count(*) from pdks.duzeltme) = dz
        and (select count(*) from pdks.amir_sorusu) = sr and (select count(*) from pdks.uyari) = uy
        and (select count(*) from pdks.okutma_isareti) = oi from sayim_once));

-- 8) Eskalasyon: son cevap günü (10 Ekim) geçince ---------------------------
select pdks.gece_isi_calistir('2026-10-10');
select test.dogrula('süresi dolan soru üst amire eskale edildi',
    (select q.durum = 'eskale' and q.eskale_edilen_id = test.k('gt_ust@ornek.test')
     from test.soru('GT04', '2026-10-06', 'hic_kayit_yok') q));
select test.dogrula('üst amirin sorusu eskale olunca İK''ya gitti',
    (select q.durum = 'eskale' and pdks.kullanici_rolu(q.eskale_edilen_id) = 'ik'
     from test.soru('GTA1', '2026-10-06', 'hic_kayit_yok') q));
select test.dogrula('eskalasyon İK''ya uyarı olarak düştü',
    exists (select 1 from pdks.uyari where tur = 'soru_eskale' and calisan_id = test.c('GT04')));

-- 9) Sınırlar ve yetki -----------------------------------------------------
select test.hata('verisi olmayan ileri bir gün işlenmez', 'henüz veri yok',
    $$select pdks.gece_isi_calistir('2099-01-01')$$);

set local role authenticated;
select test.oturum('gt_amir@ornek.test');
select test.hata('amir gece işini tetikleyemez', 'yetkiniz yok',
    $$select * from pdks.gece_isi_tetikle('2026-10-07')$$);
select test.hata('uygulama iç fonksiyonu doğrudan çağıramaz', 'permission denied',
    $$select pdks.gece_isi_calistir('2026-10-07')$$);
select test.oturum('gt_ik@ornek.test');
select test.dogrula('İK demo düğmesiyle bir günü işletebilir',
    (select count(*) = 1 and bool_and(durum = 'basarili') from pdks.gece_isi_tetikle('2026-10-07')));
reset role;

-- =====================================================================
-- B) Örnek veri: Kasım 2026, S1–S23 (docs/ornek_veri.md)
-- =====================================================================
do $$
declare
    d       date;
    v_hata  integer;
    k1      record;
begin
    if not exists (select 1 from pdks.calisan where sicil_no = '1001') then
        raise notice 'ATLANDI  örnek veri yüklü değil; S1–S23 kontrol edilmedi';
        return;
    end if;

    for d in select g::date from generate_series(date '2026-11-01', date '2026-11-30', interval '1 day') g loop
        perform pdks.gece_isi_calistir(d);
    end loop;
    select count(*) into v_hata from pdks.gece_isi where islenen_gun between '2026-11-01' and '2026-11-30' and durum <> 'basarili';
    perform test.dogrula('Kasım: 30 günün hepsi başarılı', v_hata = 0);

    perform test.dogrula('S1 giriş kapı kaydıyla 08:00 yazıldı',
        (select giris_zamani = test.ts('2026-11-03 08:00') and giris_kaynagi = 'kanit' from test.gk('1002', '2026-11-03')));
    perform test.dogrula('S2 kanıt 08:25: amire soru, öneri 08:30',
        (select onerilen_zaman = test.ts('2026-11-04 08:30') from test.soru('1003', '2026-11-04', 'kanit_vardiya_sonrasi')));
    perform test.dogrula('S3 çıkış kapıdaki 17:12 olarak yazıldı',
        (select cikis_zamani = test.ts('2026-11-05 17:12') and cikis_kaynagi = 'kanit' from test.gk('1004', '2026-11-05')));
    perform test.dogrula('S4 çıkış kanıtı yok: amire soru',
        (select (test.soru('1005', '2026-11-05', 'cikis_yok')).id is not null));
    perform test.dogrula('S5 ikinci giriş mükerrer',
        exists (select 1 from pdks.okutma_isareti i join pdks.ham_okutma h on h.id = i.ham_okutma_id
                where i.isaret = 'mukerrer' and h.kart_no = 'K1006'
                  and (h.okutma_zamani at time zone 'Europe/Istanbul')::date = '2026-11-06'));
    perform test.dogrula('S6 geçici kart okutmaları İbrahim''e yazıldı; çakışma uyarısı',
        (select giris_zamani is not null and cikis_zamani is not null from test.gk('1007', '2026-11-10'))
        and exists (select 1 from pdks.uyari where tur = 'gecici_kart_cakisma' and calisan_id = test.c('1007')));
    perform test.dogrula('S7 ayda 3 geçici kart: sık kart unutma bilgisi',
        exists (select 1 from pdks.uyari where tur = 'sik_kart_unutma' and calisan_id = test.c('1008')));
    perform test.dogrula('S8 iptal kart okutması işaretlendi ve uyarıldı',
        exists (select 1 from pdks.okutma_isareti i join pdks.ham_okutma h on h.id = i.ham_okutma_id
                where i.isaret = 'iptal_kart' and h.kart_no = 'K1009')
        and exists (select 1 from pdks.uyari where tur = 'iptal_kart_okutma' and calisan_id = test.c('1009')));
    perform test.dogrula('S9 iade edilmeyen geçici kart ve çakışma uyarısı',
        exists (select 1 from pdks.uyari where tur = 'gecici_kart_iade_edilmedi' and calisan_id = test.c('1010'))
        and exists (select 1 from pdks.uyari where tur = 'gecici_kart_cakisma' and calisan_id = test.c('1010')));
    perform test.dogrula('S10 atölye PDKS arıza şüphesi; girişler kapı kaydıyla, arızaya bağlı düzeltildi',
        exists (select 1 from pdks.ariza a join pdks.okuyucu o on o.id = a.okuyucu_id
                where o.kod = 'PDKS-2' and a.kaynak = 'otomatik_suphe'
                  and test.ts('2026-11-19 06:00') between a.baslangic and a.bitis)
        and (select count(*) >= 4 from pdks.duzeltme
             where is_gunu = '2026-11-19' and alan = 'giris_zamani' and ariza_id is not null)
        and exists (select 1 from pdks.uyari where tur = 'ariza_suphesi'));
    perform test.dogrula('S11 kart paylaşımı şüphesi (karar İK''da)',
        exists (select 1 from pdks.uyari where tur = 'kart_paylasim_suphesi'
                and calisan_id in (test.c('2002'), test.c('2003'))));
    perform test.dogrula('S12 gece vardiyası tek iş günü: 16 Kas girişi, 17 Kas çıkışı',
        (select durum = 'tamam' and (giris_zamani at time zone 'Europe/Istanbul')::date = '2026-11-16'
                and (cikis_zamani at time zone 'Europe/Istanbul')::date = '2026-11-17'
         from test.gk('2004', '2026-11-16')));
    perform test.dogrula('S13 İK onayı bekleyen plan (V2) kullanılmadı: gün onaya kadar işlenmedi (20261203010000)',
        (test.gk('2005', '2026-11-13')).id is null
        and (select ik_onay_durumu = 'bekliyor' from pdks.vardiya_plani
             where calisan_id = test.c('2005') and tarih = '2026-11-13'));
    perform test.dogrula('S14 geç kalma 35 dk, erken çıkış 40 dk',
        (select gec_kalma_dk = 35 from test.gk('3002', '2026-11-09'))
        and (select erken_cikis_dk = 40 from test.gk('3002', '2026-11-13')));
    perform test.dogrula('S15 onaylı 120 dk fazla mesai puantaja yazıldı',
        (select fazla_mesai_dk = 120 from test.gk('3003', '2026-11-20')));
    perform test.dogrula('S16 plansız fazla mesai uyarısı; puantaja yazılmadı',
        exists (select 1 from pdks.uyari where tur = 'fm_plansiz_calisma' and calisan_id = test.c('3004'))
        and (select fazla_mesai_dk = 0 from test.gk('3004', '2026-11-23')));
    perform test.dogrula('S17 yazılı onay yokken fazla kalma uyarısı',
        exists (select 1 from pdks.uyari where tur = 'fm_onay_yok' and calisan_id = test.c('3005')));
    perform test.dogrula('S18 rapor ve yıllık izin günleri',
        (select count(*) = 3 from pdks.gun_kaydi where calisan_id = test.c('2007') and durum = 'raporlu')
        and (select count(*) = 2 from pdks.gun_kaydi where calisan_id = test.c('2008') and durum = 'izinli')
        and (select durum = 'izinli' from test.gk('4005', '2026-11-16')));
    perform test.dogrula('S19 hiç kayıt yok: amire soru, devamsızlık kararı yok',
        (select (test.soru('2009', '2026-11-25', 'hic_kayit_yok')).id is not null)
        and (select durum <> 'devamsiz' from test.gk('2009', '2026-11-25')));
    perform test.dogrula('S20 sistemde olmayan kart işaretlendi',
        exists (select 1 from pdks.okutma_isareti i join pdks.ham_okutma h on h.id = i.ham_okutma_id
                where i.isaret = 'bilinmeyen_kart' and h.kart_no = 'K9999'));
    perform test.dogrula('S21 servis dosyası gelmedi uyarısı',
        exists (select 1 from pdks.uyari where tur = 'dosya_gelmedi' and tekillik_anahtari = 'servis:2026-11-27'));
    perform test.dogrula('S22 amirin kendi sorusu üst amiri Levent''e gitti',
        (select atanan_id = test.k('levent.sari@atlastrafo.example.com') from test.soru('1001', '2026-11-26', 'giris_yok')));
    perform test.dogrula('S23 zimmetsiz geçici kart uyarısı',
        exists (select 1 from pdks.uyari where tur = 'gecici_kart_zimmetsiz'));
    perform test.dogrula('sistem hiçbir günü devamsız yapmadı (karar İK''da)',
        not exists (select 1 from pdks.gun_kaydi where durum = 'devamsiz'));

    -- Kasım'ı ikinci kez işlemek hiçbir şeyi çoğaltmaz
    select (select count(*) from pdks.gun_kaydi) gk, (select count(*) from pdks.duzeltme) dz,
           (select count(*) from pdks.amir_sorusu) sr, (select count(*) from pdks.uyari) uy,
           (select count(*) from pdks.ariza) ar into k1;
    for d in select g::date from generate_series(date '2026-11-01', date '2026-11-30', interval '1 day') g loop
        perform pdks.gece_isi_calistir(d);
    end loop;
    perform test.dogrula('Kasım ikinci kez işlendi: hiçbir şey çoğalmadı',
        (select count(*) from pdks.gun_kaydi) = k1.gk and (select count(*) from pdks.duzeltme) = k1.dz
        and (select count(*) from pdks.amir_sorusu) = k1.sr and (select count(*) from pdks.uyari) = k1.uy
        and (select count(*) from pdks.ariza) = k1.ar);
end $$;

do $$ begin raise notice 'TÜM TESTLER GEÇTİ'; end $$;
rollback;
