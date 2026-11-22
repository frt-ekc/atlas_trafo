-- =====================================================================
-- "Bugün" İstanbul'a göre mi? (20261205010000_istanbul_tarihi.sql)
--   T-45: vardiya_plani_gir geriye dönük kararı · T-59: fazla mesai iptali ve
--   yazılı onayın geri alınması · gece_isi_calistir · v_gece_isi_durumu ·
--   v_isg_durum · kart.verilis_tarihi varsayılanı
--
-- T-04: Canlıda ekran (PostgREST) ve pg_cron UTC oturumla çalışır. Bu test aynı
-- işlemleri iki uç saat diliminde yapar: UTC−12 ('Etc/GMT+12') ve UTC+14
-- ('Etc/GMT-14'; POSIX adlarında işaret terstir). Günün her saatinde bu iki
-- dilimden en az birinin tarihi İstanbul'unkinden farklıdır; kod "bugün"ü
-- oturumdan alıyorsa test hangi saatte çalışırsa çalışsın düşer.
--
-- Testin kendi sahte verisi kullanılır; örnek veri yüklü olsun olmasın çalışır.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/istanbul_tarihi_testi.sql
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
create function test.calisir(p_ad text, p_sql text) returns void language plpgsql as $$
begin
    execute p_sql;
    raise notice 'GEÇTİ  %', p_ad;
exception when others then
    raise exception 'KALDI  %: %', p_ad, sqlerrm;
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
-- Testin kendi "İstanbul bugünü"; kodun hesabından bağımsız
create function test.ist_bugun() returns date language sql as $$
    select (now() at time zone 'Europe/Istanbul')::date $$;
create function test.plan(p_sicil text, p_tarih date) returns pdks.vardiya_plani language sql security definer as $$
    select * from pdks.vardiya_plani where calisan_id = test.c(p_sicil) and tarih = p_tarih $$;
create function test.fm(p_sicil text, p_gun date) returns pdks.fazla_mesai_plani language sql security definer as $$
    select * from pdks.fazla_mesai_plani where calisan_id = test.c(p_sicil) and is_gunu = p_gun
    order by id desc limit 1 $$;

-- Oturumun saat dilimini değiştirip işlemi yapan yardımcılar.
-- set_config(..., true) işlem sonuna kadar geçerlidir; her yardımcı İstanbul'a geri döner.
create function test.plan_gir(p_dilim text, p_sicil text, p_tarih date) returns void language plpgsql as $$
begin
    perform set_config('TimeZone', p_dilim, true);
    perform pdks.vardiya_plani_gir(test.c(p_sicil), p_tarih,
                                   (select id from pdks.vardiya_tanim where kod = 'GUNDUZ'));
    perform set_config('TimeZone', 'Europe/Istanbul', true);
end $$;
create function test.fm_iptal(p_dilim text, p_sicil text, p_gun date) returns void language plpgsql as $$
begin
    perform set_config('TimeZone', p_dilim, true);
    -- Talebi amir girdi; iptal eden farklı biri olmalı (fazla_mesai_talep_onay_farkli)
    update pdks.fazla_mesai_plani set durum = 'iptal', karar_veren_id = test.k('tz_ik@ornek.test')
    where id = (test.fm(p_sicil, p_gun)).id;
    perform set_config('TimeZone', 'Europe/Istanbul', true);
end $$;
create function test.gece_isi(p_dilim text, p_gun date) returns void language plpgsql as $$
begin
    perform set_config('TimeZone', p_dilim, true);
    perform pdks.gece_isi_calistir(p_gun);
    perform set_config('TimeZone', 'Europe/Istanbul', true);
end $$;
create function test.gece_gostergesi(p_dilim text) returns date language plpgsql as $$
declare v date;
begin
    perform set_config('TimeZone', p_dilim, true);
    select gun into v from pdks.v_gece_isi_durumu;
    perform set_config('TimeZone', 'Europe/Istanbul', true);
    return v;
end $$;
create function test.isg_durum(p_dilim text, p_sicil text) returns text language plpgsql as $$
declare v text;
begin
    perform set_config('TimeZone', p_dilim, true);
    select durum into v from pdks.v_isg_durum where sicil_no = p_sicil and tur = 'isg_egitimi';
    perform set_config('TimeZone', 'Europe/Istanbul', true);
    return v;
end $$;
create function test.kart_ekle(p_dilim text, p_sicil text) returns date language plpgsql as $$
declare v date;
begin
    perform set_config('TimeZone', p_dilim, true);
    insert into pdks.kart (kart_no, calisan_id) values ('TZ-' || p_sicil, test.c(p_sicil))
    returning verilis_tarihi into v;
    perform set_config('TimeZone', 'Europe/Istanbul', true);
    return v;
end $$;
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
--   TZ01, TZ02: kart · TZ03, TZ04: vardiya planı · TZ05, TZ06: fazla mesai iptali
--   TZ09: yazılı onayın geri alınması · TZ11, TZ12: İSG belgesi
insert into pdks.departman (ad) values ('TZ Üretim'), ('TZ İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = d), '2025-01-01'
from (values ('TZA1', 'TZ Üretim'), ('TZ01', 'TZ Üretim'), ('TZ02', 'TZ Üretim'), ('TZ03', 'TZ Üretim'),
             ('TZ04', 'TZ Üretim'), ('TZ05', 'TZ Üretim'), ('TZ06', 'TZ Üretim'), ('TZ09', 'TZ Üretim'),
             ('TZ11', 'TZ Üretim'), ('TZ12', 'TZ Üretim'), ('TZI1', 'TZ İdari'), ('TZS1', 'TZ İdari')) v(s, d);
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('TZ İK',   'tz_ik@ornek.test',   'ik',   test.c('TZI1'), '00000000-0000-0000-0000-0000000000f1'),
    ('TZ Amir', 'tz_amir@ornek.test', 'amir', test.c('TZA1'), '00000000-0000-0000-0000-0000000000f2'),
    ('TZ İSG',  'tz_isg@ornek.test',  'isg',  test.c('TZS1'), '00000000-0000-0000-0000-0000000000f3');
update pdks.departman set amir_id = test.k('tz_amir@ornek.test') where ad = 'TZ Üretim';

-- Fazla mesai için: yazılı onay (yıl başında imzalı) ve vardiya planları
insert into pdks.fazla_mesai_onayi (calisan_id, yil, imza_tarihi, belge_no, giren_id)
select test.c(s), extract(year from test.ist_bugun()), date_trunc('year', test.ist_bugun())::date,
       'TZ-FMO-' || s, test.k('tz_ik@ornek.test')
from unnest(array['TZ05', 'TZ06', 'TZ09']) s;
insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id)
select test.c(s), test.ist_bugun() + g, (select id from pdks.vardiya_tanim where kod = 'GUNDUZ')
from unnest(array['TZ05', 'TZ06', 'TZ09']) s, unnest(array[-1, 0, 2, 3]) g;
insert into pdks.fazla_mesai_plani (calisan_id, is_gunu, planli_dk, gerekce, talep_eden_id)
select test.c(s), test.ist_bugun() + g, 60, 'Sipariş yetişmeli', test.k('tz_amir@ornek.test')
from (values ('TZ05', -1), ('TZ05', 0), ('TZ06', -1), ('TZ06', 0),
             ('TZ09', -1), ('TZ09', 2), ('TZ09', 3)) v(s, g);
update pdks.fazla_mesai_plani set durum = 'onaylandi', karar_veren_id = test.k('tz_ik@ornek.test')
where calisan_id in (test.c('TZ05'), test.c('TZ06'))
   or (calisan_id = test.c('TZ09') and is_gunu in (test.ist_bugun() - 1, test.ist_bugun() + 2));

-- İSG: TZ11'in belgesi İstanbul'un dünü bitti, TZ12'ninki bugün bitiyor
insert into pdks.isg_belge (calisan_id, tur, gecerlilik_bitis, giren_id) values
    (test.c('TZ11'), 'isg_egitimi', test.ist_bugun() - 1, test.k('tz_isg@ornek.test')),
    (test.c('TZ12'), 'isg_egitimi', test.ist_bugun(),     test.k('tz_isg@ornek.test'));

select 'Test anı: İstanbul ' || to_char(now() at time zone 'Europe/Istanbul', 'YYYY-MM-DD HH24:MI')
    || ' · UTC−12 ' || to_char(now() at time zone 'Etc/GMT+12', 'YYYY-MM-DD HH24:MI')
    || ' · UTC+14 ' || to_char(now() at time zone 'Etc/GMT-14', 'YYYY-MM-DD HH24:MI');

-- 1) T-45: vardiya_plani_gir, "geriye dönük" kararı -------------------------
select test.oturum('tz_amir@ornek.test');
set local role authenticated;
select test.plan_gir('Etc/GMT+12', 'TZ03', test.ist_bugun());
select test.plan_gir('Etc/GMT+12', 'TZ03', test.ist_bugun() - 1);
select test.plan_gir('Etc/GMT-14', 'TZ04', test.ist_bugun());
select test.plan_gir('Etc/GMT-14', 'TZ04', test.ist_bugun() - 1);
reset role;
select test.dogrula('UTC−12 oturum: bugünün planı geriye dönük değil, onay gerekmez',
    (select not geriye_donuk and ik_onay_durumu = 'gerekmez' from test.plan('TZ03', test.ist_bugun())));
select test.dogrula('UTC−12 oturum: dünün planı geriye dönük, İK onayı bekliyor',
    (select geriye_donuk and ik_onay_durumu = 'bekliyor' from test.plan('TZ03', test.ist_bugun() - 1)));
select test.dogrula('UTC+14 oturum: bugünün planı geriye dönük değil, onay gerekmez',
    (select not geriye_donuk and ik_onay_durumu = 'gerekmez' from test.plan('TZ04', test.ist_bugun())));
select test.dogrula('UTC+14 oturum: dünün planı geriye dönük, İK onayı bekliyor',
    (select geriye_donuk and ik_onay_durumu = 'bekliyor' from test.plan('TZ04', test.ist_bugun() - 1)));

-- 2) T-59 (saat kısmı): onaylı planın kişili iptali -------------------------
select test.calisir('UTC−12 oturum: bugünün onaylı planı iptal edilebilir',
    $$select test.fm_iptal('Etc/GMT+12', 'TZ05', test.ist_bugun())$$);
select test.hata('UTC−12 oturum: dünün onaylı planı iptal edilemez', 'Geçmiş bir günün onaylı planı',
    $$select test.fm_iptal('Etc/GMT+12', 'TZ05', test.ist_bugun() - 1)$$);
select test.calisir('UTC+14 oturum: bugünün onaylı planı iptal edilebilir',
    $$select test.fm_iptal('Etc/GMT-14', 'TZ06', test.ist_bugun())$$);
select test.hata('UTC+14 oturum: dünün onaylı planı iptal edilemez', 'Geçmiş bir günün onaylı planı',
    $$select test.fm_iptal('Etc/GMT-14', 'TZ06', test.ist_bugun() - 1)$$);

-- 3) T-59: yazılı onayın geri alınması her zaman kaydedilir ----------------
--   Bildirim 40 gün önce → geçerlilik 10 gün önce bitti. Dünkü onaylı plan
--   (çalışılmış gün) korunur; ileri tarihli onaylı plan ve talep sistemce iptal.
select test.calisir('geçmişte onaylı plan varken yazılı onayın geri alınması kaydedildi',
    $$update pdks.fazla_mesai_onayi
      set geri_alma_bildirim_tarihi = test.ist_bugun() - 41, geri_alma_giren_id = test.k('tz_ik@ornek.test')
      where calisan_id = test.c('TZ09')$$);
select test.dogrula('dünkü onaylı plan olduğu gibi kaldı',
    (select durum = 'onaylandi' from test.fm('TZ09', test.ist_bugun() - 1)));
select test.dogrula('ileri tarihli onaylı plan sistemce (kişisiz) iptal edildi',
    (select durum = 'iptal' and karar_veren_id is null from test.fm('TZ09', test.ist_bugun() + 2)));
select test.dogrula('ileri tarihli talep iptal edildi',
    (select durum = 'iptal' and karar_veren_id is null from test.fm('TZ09', test.ist_bugun() + 3)));
select test.dogrula('İK uyarısı iptal edilen ve korunan planları sayıyor',
    (select mesaj like '%2 plan iptal edildi%' and mesaj like '%1 plan%iptal edilmedi%'
     from pdks.uyari where tur = 'fm_onay_geri_alindi' and calisan_id = test.c('TZ09')));

-- 4) gece_isi_calistir: işlenebilecek en ileri gün İstanbul'un dünü --------
--   Örnek veride ileri tarihli PDKS dosyası varsa bu kontrol anlamsızdır; atlanır.
do $$
begin
    if coalesce((select max(veri_tarihi) from pdks.aktarim where kaynak = 'pdks'), '-infinity'::date)
       >= test.ist_bugun() - 1 then
        raise notice 'ATLANDI  gece işi gün sınırı (yüklü PDKS dosyası İstanbul''un dününe ya da ilerisine ait)';
        return;
    end if;
    perform test.hata('UTC−12 oturum: bugün işlenemez', 'henüz veri yok',
        format('select test.gece_isi(%L, %L)', 'Etc/GMT+12', test.ist_bugun()));
    perform test.hata('UTC+14 oturum: bugün işlenemez', 'henüz veri yok',
        format('select test.gece_isi(%L, %L)', 'Etc/GMT-14', test.ist_bugun()));
    perform test.calisir('UTC−12 oturum: dün işlenebilir',
        format('select test.gece_isi(%L, %L)', 'Etc/GMT+12', test.ist_bugun() - 1));
end $$;

-- 5) v_gece_isi_durumu: "dün" İstanbul'un dünü ------------------------------
select test.dogrula('UTC−12 oturum: gece işi göstergesi İstanbul''un dününü gösteriyor',
    test.gece_gostergesi('Etc/GMT+12') = test.ist_bugun() - 1);
select test.dogrula('UTC+14 oturum: gece işi göstergesi İstanbul''un dününü gösteriyor',
    test.gece_gostergesi('Etc/GMT-14') = test.ist_bugun() - 1);

-- 6) v_isg_durum: dün biten belge dolmuş, bugün biten dolmamış --------------
select test.oturum('tz_ik@ornek.test');
set local role authenticated;
select test.dogrula('UTC−12 oturum: dün biten İSG belgesi "dolmus"',
    test.isg_durum('Etc/GMT+12', 'TZ11') = 'dolmus');
select test.dogrula('UTC+14 oturum: dün biten İSG belgesi "dolmus"',
    test.isg_durum('Etc/GMT-14', 'TZ11') = 'dolmus');
select test.dogrula('UTC−12 oturum: bugün biten İSG belgesi henüz dolmamış',
    test.isg_durum('Etc/GMT+12', 'TZ12') = 'doluyor');
select test.dogrula('UTC+14 oturum: bugün biten İSG belgesi henüz dolmamış',
    test.isg_durum('Etc/GMT-14', 'TZ12') = 'doluyor');
reset role;

-- 7) kart.verilis_tarihi varsayılanı İstanbul'un bugünü --------------------
select test.dogrula('UTC−12 oturum: kartın veriliş tarihi İstanbul''un bugünü',
    test.kart_ekle('Etc/GMT+12', 'TZ01') = test.ist_bugun());
select test.dogrula('UTC+14 oturum: kartın veriliş tarihi İstanbul''un bugünü',
    test.kart_ekle('Etc/GMT-14', 'TZ02') = test.ist_bugun());

select 'İstanbul tarihi testi: hepsi GEÇTİ';
rollback;
