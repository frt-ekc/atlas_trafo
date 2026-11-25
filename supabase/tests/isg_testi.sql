-- =====================================================================
-- İSG testleri (20261126010000_isg.sql)
--   bölge yetkisi · İSG belgeleri (yok / dolmuş / doluyor) · uyarılar ·
--   yalnızca uyarı (kapı kilitlenmez) · yetkiler
-- Testin kendi sahte verisi (Ekim 2026) kullanılır; örnek veri yüklü olsun
-- olmasın çalışır. Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/isg_testi.sql
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
create function test.d(p text) returns smallint language sql security definer as $$
    select id from pdks.departman where ad = p $$;
create function test.b(p text) returns smallint language sql security definer as $$
    select id from pdks.bolge where kod = p $$;
create function test.uyari(p_tur text, p_sicil text) returns bigint language sql security definer as $$
    select count(*) from pdks.uyari where tur = p_tur and calisan_id = test.c(p_sicil) $$;
create function test.ts(p text) returns timestamptz language sql immutable as $$
    select (p::timestamp) at time zone 'Europe/Istanbul' $$;
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
insert into pdks.departman (ad, yaka) values ('IS Üretim', 'mavi'), ('IS Lab', 'mavi'), ('IS Ofis', 'beyaz');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', test.d(d), '2025-01-01'
from (values ('IS01', 'IS Üretim'), ('IS02', 'IS Üretim'), ('IS03', 'IS Üretim'), ('IS04', 'IS Ofis'),
             ('IS05', 'IS Lab'), ('ISS1', 'IS Ofis'), ('ISS2', 'IS Ofis'), ('ISI1', 'IS Ofis')) v(s, d);
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('IS İSG',   'is_isg@ornek.test',   'isg',  test.c('ISS1'), '00000000-0000-0000-0000-0000000000b1'),
    ('IS İSG 2', 'is_isg2@ornek.test',  'isg',  test.c('ISS2'), '00000000-0000-0000-0000-0000000000b2'),
    ('IS İK',    'is_ik@ornek.test',    'ik',   test.c('ISI1'), '00000000-0000-0000-0000-0000000000b3'),
    ('IS Amir',  'is_amir@ornek.test',  'amir', test.c('IS03'), '00000000-0000-0000-0000-0000000000b4');
update pdks.departman set amir_id = test.k('is_amir@ornek.test') where ad = 'IS Üretim';
insert into pdks.kart (kart_no, calisan_id)
select 'IS-' || s, test.c(s) from unnest(array['IS01', 'IS02', 'IS03', 'IS04', 'IS05']) s;

insert into pdks.bolge (kod, ad) values ('IS-LAB', 'IS Test Laboratuvarı');
insert into pdks.okuyucu (kod, ad, sistem) values ('IS-PDKS', 'IS PDKS', 'pdks'), ('IS-KAPI', 'IS kapı', 'kapi');
insert into pdks.okuyucu (kod, ad, sistem, bolge_id) values ('IS-LABKAPI', 'IS lab kapısı', 'kapi', test.b('IS-LAB'));

-- İSG belgeleri (İSG uzmanı girer)
set local role authenticated;
select test.oturum('is_isg@ornek.test');
select pdks.isg_belge_gir(test.c('IS02'), 'isg_egitimi', '2026-10-02', 'E-IS02');        -- dolmuş
select pdks.isg_belge_gir(test.c('IS02'), 'saglik_muayenesi', '2027-06-30', 'M-IS02');
select pdks.isg_belge_gir(test.c('IS03'), 'isg_egitimi', '2026-10-20', 'E-IS03');        -- 15 gün sonra doluyor
select pdks.isg_belge_gir(test.c('IS03'), 'saglik_muayenesi', '2027-06-30', 'M-IS03');
select pdks.isg_belge_gir(test.c('IS05'), 'isg_egitimi', '2027-06-30');
select pdks.isg_belge_gir(test.c('IS05'), 'saglik_muayenesi', '2027-06-30');
select pdks.bolge_yetkisi_ver(test.b('IS-LAB'), test.d('IS Lab'));
reset role;

-- 5 Ekim okutmaları: herkes kapıdan ve PDKS'den geçer; IS01 ve IS05 lab kapısında okutur
insert into pdks.aktarim (kaynak, dosya_adi, dosya_ozeti, veri_tarihi)
select k, 'is_' || k || '_' || g::date || '.csv', 'is-' || k || '-' || g::date, g::date
from unnest(array['pdks', 'kapi']) k, generate_series(date '2026-10-05', date '2026-10-06', interval '1 day') g;
insert into pdks.ham_okutma (aktarim_id, okuyucu_id, kart_no, okutma_zamani, yon)
select (select id from pdks.aktarim where dosya_ozeti = 'is-pdks-2026-10-05'),
       (select id from pdks.okuyucu where kod = 'IS-PDKS'), 'IS-' || s, test.ts('2026-10-05 07:55'), 'giris'
from unnest(array['IS01', 'IS02', 'IS03', 'IS04', 'IS05']) s;
insert into pdks.kanit_kaydi (aktarim_id, okuyucu_id, kaynak, kart_no, okutma_zamani, yon)
select (select id from pdks.aktarim where dosya_ozeti = 'is-kapi-2026-10-05'),
       (select id from pdks.okuyucu where kod = o), 'kapi', 'IS-' || s, test.ts(z), y
from (values ('IS01', 'IS-LABKAPI', '2026-10-05 10:15', null), ('IS05', 'IS-LABKAPI', '2026-10-05 10:20', null),
             ('IS01', 'IS-KAPI', '2026-10-05 07:50', 'giris')) v(s, o, z, y);

select pdks.gece_isi_calistir('2026-10-05');
select pdks.gece_isi_calistir('2026-10-05');   -- tekrar çalıştırmak uyarıyı çoğaltmamalı

-- 1) İSG belgeleri ve uyarılar ---------------------------------------------------------
select test.dogrula('hiç kaydı olmayan mavi yaka çalışan: eğitim ve muayene için birer "belge yok" uyarısı',
    test.uyari('isg_belgesi_yok', 'IS01') = 2);
select test.dogrula('süresi dolmuş eğitimle okutan: "süresi dolmuş" uyarısı (muayenesi geçerli)',
    test.uyari('isg_belgesi_suresi_dolmus', 'IS02') = 1 and test.uyari('isg_belgesi_yok', 'IS02') = 0
    and exists (select 1 from pdks.uyari where tur = 'isg_belgesi_suresi_dolmus' and calisan_id = test.c('IS02')
                and mesaj like '%İSG eğitimi%02.10.2026%'));
select test.dogrula('30 gün içinde dolacak eğitim: "süresi doluyor" uyarısı',
    test.uyari('isg_belgesi_suresi_doluyor', 'IS03') = 1 and test.uyari('isg_belgesi_suresi_dolmus', 'IS03') = 0);
select test.dogrula('beyaz yaka çalışana İSG belgesi uyarısı çıkmaz',
    test.uyari('isg_belgesi_yok', 'IS04') = 0);
select test.dogrula('belgeleri geçerli çalışana uyarı çıkmaz',
    not exists (select 1 from pdks.uyari where calisan_id = test.c('IS05') and tur like 'isg%'));
select test.dogrula('gece işi tekrar çalışınca İSG uyarıları çoğalmaz',
    (select count(*) = 4 from pdks.uyari where tur like 'isg%'
     and calisan_id in (test.c('IS01'), test.c('IS02'), test.c('IS03'), test.c('IS04'), test.c('IS05'))));

-- Yenilenen belge: en son girilen geçerli sayılır
set local role authenticated;
select test.oturum('is_isg@ornek.test');
select pdks.isg_belge_gir(test.c('IS02'), 'isg_egitimi', '2027-10-01', 'E-IS02-YENI');
reset role;
select test.dogrula('yenilenen belgeden sonra durum "geçerli"',
    (select durum = 'gecerli' and gecerlilik_bitis = '2027-10-01' from pdks.v_isg_durum
     where calisan_id = test.c('IS02') and tur = 'isg_egitimi'));
insert into pdks.ham_okutma (aktarim_id, okuyucu_id, kart_no, okutma_zamani, yon)
values ((select id from pdks.aktarim where dosya_ozeti = 'is-pdks-2026-10-06'),
        (select id from pdks.okuyucu where kod = 'IS-PDKS'), 'IS-IS02', test.ts('2026-10-06 07:55'), 'giris'),
       ((select id from pdks.aktarim where dosya_ozeti = 'is-pdks-2026-10-06'),
        (select id from pdks.okuyucu where kod = 'IS-PDKS'), 'IS-IS05', test.ts('2026-10-06 16:05'), 'cikis');
-- IS05, 6 Ekim: PDKS girişi yok, yalnızca lab kapısı okutması (yönsüz) var
insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id, giren_id)
values (test.c('IS05'), '2026-10-06', (select id from pdks.vardiya_tanim where kod = 'GUNDUZ_8'), test.k('is_ik@ornek.test'));
insert into pdks.kanit_kaydi (aktarim_id, okuyucu_id, kaynak, kart_no, okutma_zamani, yon)
values ((select id from pdks.aktarim where dosya_ozeti = 'is-kapi-2026-10-06'),
        (select id from pdks.okuyucu where kod = 'IS-LABKAPI'), 'kapi', 'IS-IS05', test.ts('2026-10-06 07:40'), null);
select pdks.gece_isi_calistir('2026-10-06');
select test.dogrula('yenilenen belgeyle ertesi gün okutunca yeni "dolmuş" uyarısı çıkmaz',
    test.uyari('isg_belgesi_suresi_dolmus', 'IS02') = 1);

-- 2) Bölge yetkisi ---------------------------------------------------------------------
select test.dogrula('yetkisiz departmandan lab kapısında okutma: uyarı (bölge adı ve saatiyle)',
    (select count(*) = 1 from pdks.uyari where tur = 'yetkisiz_bolge_okutmasi' and calisan_id = test.c('IS01')
     and mesaj like '%IS Test Laboratuvarı%05.10.2026 10:15%'));
select test.dogrula('yetkili departmandan okutmada uyarı yok',
    test.uyari('yetkisiz_bolge_okutmasi', 'IS05') = 0);
select test.dogrula('kapı kilitlenmez: okutmalar kayıtlı, hiçbiri işaretlenmedi',
    (select count(*) = 3 from pdks.kanit_kaydi k join pdks.okuyucu o on o.id = k.okuyucu_id where o.kod = 'IS-LABKAPI')
    and not exists (select 1 from pdks.okutma_isareti i join pdks.ham_okutma h on h.id = i.ham_okutma_id
                    where h.kart_no like 'IS-%'));
select test.dogrula('bölge okutması (yönsüz) giriş saati olarak kullanılmaz: giriş boş, amire "giriş yok" sorusu',
    (select g.giris_zamani is null and g.durum = 'soru_bekliyor'
     from pdks.gun_kaydi g where g.calisan_id = test.c('IS05') and g.is_gunu = '2026-10-06')
    and exists (select 1 from pdks.amir_sorusu q join pdks.gun_kaydi g on g.id = q.gun_kaydi_id
                where g.calisan_id = test.c('IS05') and g.is_gunu = '2026-10-06' and q.soru_turu = 'giris_yok'));

-- 3) Yetkiler ---------------------------------------------------------------------------
set local role authenticated;
select test.oturum('is_isg@ornek.test');
select test.dogrula('İSG uzmanı İSG ve bölge uyarılarını görür, diğer uyarıları görmez',
    (select count(*) >= 5 from pdks.uyari)
    and not exists (select 1 from pdks.uyari where tur not in ('isg_belgesi_yok', 'isg_belgesi_suresi_dolmus',
                    'isg_belgesi_suresi_doluyor', 'yetkisiz_bolge_okutmasi')));
select test.dogrula('İSG uzmanı belgeleri, bölge yetkilerini, okuyucuları ve İSG durumunu görür',
    (select count(*) >= 7 from pdks.isg_belge) and (select count(*) >= 1 from pdks.bolge_yetkisi)
    and (select count(*) >= 3 from pdks.okuyucu) and (select count(*) > 0 from pdks.v_isg_durum));
select test.dogrula('İSG uzmanı gün kaydı ve izin göremez',
    (select count(*) from pdks.gun_kaydi) = 0 and (select count(*) from pdks.izin) = 0);
select test.hata('geçersiz belge türü', 'Geçerli bir belge türü',
    format($$select pdks.isg_belge_gir(%s, 'ehliyet', '2027-01-01')$$, test.c('IS01')));
select test.hata('İSG uzmanı kendi belgesini giremez', 'Görevler ayrılığı',
    format($$select pdks.isg_belge_gir(%s, 'isg_egitimi', '2027-01-01')$$, test.c('ISS1')));
select test.hata('yetkisi olmayan bölge yetkisi kaldırılamaz', 'yetkisi yok',
    format($$select pdks.bolge_yetkisi_kaldir(%s::smallint, %s::smallint)$$, test.b('IS-LAB'), test.d('IS Üretim')));
select pdks.bolge_yetkisi_ver(test.b('IS-LAB'), test.d('IS Üretim'));
select test.dogrula('İSG uzmanı bölge yetkisi verir',
    exists (select 1 from pdks.bolge_yetkisi where bolge_id = test.b('IS-LAB') and departman_id = test.d('IS Üretim')));
select pdks.bolge_yetkisi_kaldir(test.b('IS-LAB'), test.d('IS Üretim'));
select test.dogrula('İSG uzmanı bölge yetkisini kaldırır',
    not exists (select 1 from pdks.bolge_yetkisi where bolge_id = test.b('IS-LAB') and departman_id = test.d('IS Üretim')));
select test.dogrula('yetki izi: verildi ve kaldırıldı, ikisi de kim yaptığıyla (20261127010000_bolge_yetkisi_izi)',
    (select array_agg(islem order by id) = array['verildi', 'kaldirildi']
            and bool_and(yapan_id = test.k('is_isg@ornek.test'))
     from pdks.bolge_yetkisi_gecmisi where bolge_id = test.b('IS-LAB') and departman_id = test.d('IS Üretim')));
select test.dogrula('İSG uzmanı yetki izini görür',
    (select count(*) >= 3 from pdks.bolge_yetkisi_gecmisi where bolge_id = test.b('IS-LAB')));
select test.oturum('is_ik@ornek.test');
select test.hata('İK İSG belgesi giremez', 'yetkiniz yok',
    format($$select pdks.isg_belge_gir(%s, 'isg_egitimi', '2027-01-01')$$, test.c('IS01')));
select test.hata('İK bölge yetkisi veremez', 'yetkiniz yok',
    format($$select pdks.bolge_yetkisi_ver(%s::smallint, %s::smallint)$$, test.b('IS-LAB'), test.d('IS Üretim')));
select test.dogrula('İK İSG durumunu ve uyarıları görür',
    (select count(*) > 0 from pdks.v_isg_durum) and (select count(*) > 0 from pdks.uyari where tur like 'isg%'));
select test.oturum('is_amir@ornek.test');
select test.dogrula('amir İSG belgelerini ve İSG durumunu göremez',
    (select count(*) from pdks.isg_belge) = 0 and (select count(*) from pdks.v_isg_durum) = 0);
reset role;
select test.hata('bölge yetkisi izi silinemez', 'değiştirilemez',
    $$delete from pdks.bolge_yetkisi_gecmisi$$);
select test.hata('İSG belgesi değiştirilemez / silinemez', 'değiştirilemez',
    format($$delete from pdks.isg_belge where calisan_id = %s$$, test.c('IS02')));
select test.hata('İSG belgesini yalnızca İSG uzmanı girer (tablo kuralı)', 'yalnızca İSG uzmanı',
    format($$insert into pdks.isg_belge (calisan_id, tur, gecerlilik_bitis, giren_id) values (%s, 'isg_egitimi', '2027-01-01', %s)$$,
           test.c('IS01'), test.k('is_ik@ornek.test')));
select test.dogrula('belge tablosunda sonuç / teşhis sütunu yok',
    not exists (select 1 from information_schema.columns where table_schema = 'pdks' and table_name = 'isg_belge'
                and column_name ~ '(sonuc|teshis|tani)'));

do $$ begin raise notice 'İSG TESTLERİ GEÇTİ'; end $$;
rollback;
