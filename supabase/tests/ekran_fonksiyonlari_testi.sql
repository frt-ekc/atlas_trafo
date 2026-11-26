-- =====================================================================
-- Ekran fonksiyonları (RPC) testleri. Fonksiyonlar uygulamanın rolüyle
-- ("authenticated"), farklı kullanıcılar adına çağrılır.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/ekran_fonksiyonlari_testi.sql
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
-- Hata bekler; mesaj verilen kalıbı içermeli
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
-- Oturumu bir demo kullanıcısı olarak açar
create function test.oturum(p_eposta text) returns void language sql security definer as $$
    select set_config('request.jwt.claims',
        json_build_object('sub', (select auth_kullanici_id from pdks.kullanici where eposta = p_eposta),
                          'role', 'authenticated')::text, true);
$$;
create function test.c(p text) returns bigint language sql security definer as $$
    select id from pdks.calisan where sicil_no = p $$;
create function test.gk(p text) returns bigint language sql security definer as $$
    select id from pdks.gun_kaydi where calisan_id = test.c(p) and is_gunu = '2026-10-13' $$;
create function test.soru(p text) returns bigint language sql security definer as $$
    select id from pdks.amir_sorusu where gun_kaydi_id = test.gk(p) $$;
-- Testin kendi kontrolleri tablo sahibi olarak okur (RLS'den bağımsız)
create function test.sor(p_sql text) returns text language plpgsql security definer as $$
declare v text;
begin execute p_sql into v; return v; end $$;
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) -------------------------------------------
insert into pdks.departman (ad) values ('EF Montaj'), ('EF Bobinaj'), ('EF İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = d), '2025-01-01'
from (values ('EF01', 'EF Montaj'), ('EF02', 'EF Montaj'), ('EF03', 'EF Bobinaj'),
             ('EF11', 'EF Montaj'), ('EF12', 'EF Bobinaj'),
             ('EF21', 'EF İdari'), ('EF22', 'EF İdari'), ('EF31', 'EF İdari')) v(s, d);
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('Amir M', 'ef_amir_m@ornek.test', 'amir',     test.c('EF11'), '00000000-0000-0000-0000-0000000000e1'),
    ('Amir B', 'ef_amir_b@ornek.test', 'amir',     test.c('EF12'), '00000000-0000-0000-0000-0000000000e2'),
    ('İK 1',   'ef_ik1@ornek.test',    'ik',       test.c('EF21'), '00000000-0000-0000-0000-0000000000e3'),
    ('İK 2',   'ef_ik2@ornek.test',    'ik',       test.c('EF22'), '00000000-0000-0000-0000-0000000000e4'),
    ('Güv',    'ef_guv@ornek.test',    'guvenlik', test.c('EF31'), '00000000-0000-0000-0000-0000000000e5');
update pdks.departman set amir_id = (select id from pdks.kullanici where eposta = 'ef_amir_m@ornek.test') where ad = 'EF Montaj';
update pdks.departman set amir_id = (select id from pdks.kullanici where eposta = 'ef_amir_b@ornek.test') where ad = 'EF Bobinaj';

insert into pdks.kart (kart_no, calisan_id) values ('EF-K01', test.c('EF01')), ('EF-K02', test.c('EF02'));
insert into pdks.okuyucu (kod, ad, sistem) values ('EF-PDKS', 'EF PDKS', 'pdks'), ('EF-KAPI', 'EF kapı', 'kapi');
insert into pdks.gecici_kart (kart_no) values ('EF-GK1');
insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id)
select test.c(s), current_date + 7, 1 from unnest(array['EF01', 'EF03']) s;
insert into pdks.fazla_mesai_onayi (calisan_id, yil, imza_tarihi, belge_no, giren_id)
values (test.c('EF01'), extract(year from current_date + 7)::smallint, date_trunc('year', current_date + 7)::date,
        'EF-FMO-1', (select id from pdks.kullanici where eposta = 'ef_ik1@ornek.test'));

-- 13 Ekim: Montaj'da EF01 (giriş yok; çıkış PDKS'ten 17:05), EF02 (hiç kayıt yok); Bobinaj'da EF03 (çıkış yok; giriş PDKS'ten 07:58)
-- (T-41: cevaptan sonra günde iki saat de olmalı; "giriş yok" sorusu çıkışı olan günde açılır)
insert into pdks.gun_kaydi (calisan_id, is_gunu, vardiya_id, planli_baslangic, planli_bitis, durum, giris_zamani, giris_kaynagi, cikis_zamani, cikis_kaynagi)
select test.c(s), '2026-10-13', 1, '2026-10-13 08:00+03', '2026-10-13 17:00+03', 'soru_bekliyor',
       case when s = 'EF03' then '2026-10-13 07:58+03'::timestamptz end, case when s = 'EF03' then 'pdks' end,
       case when s = 'EF01' then '2026-10-13 17:05+03'::timestamptz end, case when s = 'EF01' then 'pdks' end
from unnest(array['EF01', 'EF02', 'EF03']) s;
insert into pdks.amir_sorusu (gun_kaydi_id, soru_turu, aciklama, atanan_id, son_cevap_tarihi)
select test.gk(s), t, 'Örnek soru', (select id from pdks.kullanici where eposta = e), '2026-10-16'
from (values ('EF01', 'giris_yok', 'ef_amir_m@ornek.test'),
             ('EF02', 'hic_kayit_yok', 'ef_amir_m@ornek.test'),
             ('EF03', 'cikis_yok', 'ef_amir_b@ornek.test')) v(s, t, e);
insert into pdks.uyari (tur, calisan_id, mesaj) values ('kart_paylasim_suphesi', test.c('EF01'), 'Örnek uyarı');

set role authenticated;

-- 1) Yetki ----------------------------------------------------------------
select test.dogrula('anon ekran fonksiyonlarını çağıramaz',
    not has_function_privilege('anon', 'pdks.soru_cevapla(bigint, text, timestamptz, timestamptz, text)', 'execute'));
select test.hata('oturumu olmayan işlem yapamaz', 'Oturum bulunamadı',
    $$select pdks.soru_cevapla(test.soru('EF01'), 'geldi_saat_dogru')$$);
select test.oturum('ef_guv@ornek.test');
select test.hata('güvenlik İK işlemi yapamaz', 'yetkiniz yok',
    $$select pdks.uyari_goruldu(test.sor('select id from pdks.uyari limit 1')::bigint)$$);
select test.hata('güvenlik kayıt düzeltemez', 'yetkiniz yok',
    $$select pdks.kayit_duzelt(test.gk('EF01'), 'durum', 'tamam', 'deneme düzeltme')$$);

-- 2) Amir -------------------------------------------------------------------
select test.oturum('ef_amir_b@ornek.test');
select test.hata('amir başkasına atanmış soruyu cevaplayamaz', 'size atanmamış',
    $$select pdks.soru_cevapla(test.soru('EF01'), 'geldi_saat_dogru')$$);

select test.oturum('ef_amir_m@ornek.test');
select test.hata('saat farklıysa saat girilmeli', 'saatini girin',
    $$select pdks.soru_cevapla(test.soru('EF01'), 'geldi_saat_farkli')$$);
select test.hata('geçersiz cevap reddedilir', 'Geçersiz cevap',
    $$select pdks.soru_cevapla(test.soru('EF01'), 'belki')$$);
select pdks.soru_cevapla(test.soru('EF01'), 'geldi_saat_dogru');
select test.dogrula('"geldi, saat doğru": giriş vardiya başı olarak yazıldı, kaynak amir',
    test.sor($$select giris_zamani = '2026-10-13 08:00+03' and giris_kaynagi = 'amir'
               from pdks.gun_kaydi where id = test.gk('EF01')$$)::boolean);
select test.dogrula('düzeltme izi soruya bağlı ve yapan amir',
    test.sor($$select count(*) = 1 from pdks.duzeltme d join pdks.kullanici k on k.id = d.yapan_id
               where d.soru_id = test.soru('EF01') and d.kaynak = 'amir' and k.eposta = 'ef_amir_m@ornek.test'$$)::boolean);
select test.dogrula('soru "cevaplandı" oldu',
    test.sor($$select durum = 'cevaplandi' from pdks.amir_sorusu where id = test.soru('EF01')$$)::boolean);
select test.hata('soru ikinci kez cevaplanamaz', 'zaten cevaplanmış',
    $$select pdks.soru_cevapla(test.soru('EF01'), 'geldi_saat_dogru')$$);

select pdks.soru_cevapla(test.soru('EF02'), 'gelmedi', p_aciklama => 'Haber vermedi');
select test.dogrula('"gelmedi": soru İK kararına geçti, gün kaydı değişmedi',
    test.sor($$select s.durum = 'ik_karari_bekliyor' and g.giris_zamani is null and g.durum = 'soru_bekliyor'
               from pdks.amir_sorusu s join pdks.gun_kaydi g on g.id = s.gun_kaydi_id
               where s.id = test.soru('EF02')$$)::boolean);

select test.dogrula('amir kendi departmanındaki çalışan için itiraz girebilir',
    pdks.itiraz_gir(test.gk('EF01'), 'Çalışan 07:55''te geldiğini söylüyor') is not null);
select test.hata('amir başka departmanın çalışanı için itiraz giremez', 'departmanınızda değil',
    $$select pdks.itiraz_gir(test.gk('EF03'), 'Deneme')$$);
select test.hata('amir başka departmana fazla mesai talep edemez', 'departmanınızda değil',
    $$select pdks.fazla_mesai_talep_et(test.c('EF03'), current_date + 7, 60, 'Sipariş yetişmeli')$$);
select test.dogrula('amir ekibine fazla mesai talep edebilir (vardiya plandan alınır)',
    pdks.fazla_mesai_talep_et(test.c('EF01'), current_date + 7, 60, 'Sipariş yetişmeli') is not null);
select test.dogrula('geçmiş güne girilen vardiya planı İK onayı bekler',
    test.sor(format($$select ik_onay_durumu = 'bekliyor' and geriye_donuk from pdks.vardiya_plani where id = %s$$,
                    pdks.vardiya_plani_gir(test.c('EF02'), current_date - 3, 1::smallint, 'Vardiya değişti')))::boolean);
select test.dogrula('ileri tarihli vardiya planı onay gerektirmez',
    test.sor(format($$select ik_onay_durumu = 'gerekmez' from pdks.vardiya_plani where id = %s$$,
                    pdks.vardiya_plani_gir(test.c('EF02'), current_date + 9, 1::smallint)))::boolean);
select test.hata('amir kendi vardiyasını giremez', 'Görevler ayrılığı',
    $$select pdks.vardiya_plani_gir(test.c('EF11'), current_date + 9, 1::smallint)$$);

-- 3) İK -----------------------------------------------------------------------
select test.oturum('ef_ik1@ornek.test');
select test.hata('İK, amire atanmış soruyu amir yerine cevaplayamaz', 'yetkiniz yok',
    $$select pdks.soru_cevapla(test.soru('EF03'), 'geldi_saat_dogru')$$);
select test.hata('devamsız değilse saat girilmeli', 'saatini girin',
    $$select pdks.soru_ik_karari(test.soru('EF02'), false, 'Geldiği anlaşıldı')$$);
select pdks.soru_ik_karari(test.soru('EF02'), true, 'Haber vermeden gelmedi, belge yok');
select test.dogrula('İK devamsızlık kararı: gün "devamsız", düzeltme çalışan aleyhine işaretli, soru kapandı',
    test.sor($$select g.durum = 'devamsiz' and d.calisan_aleyhine and s.durum = 'kapandi'
               from pdks.gun_kaydi g
               join pdks.duzeltme d on d.gun_kaydi_id = g.id and d.alan = 'durum'
               join pdks.amir_sorusu s on s.gun_kaydi_id = g.id
               where g.id = test.gk('EF02')$$)::boolean);

select pdks.itiraz_incelemeye_al((select id from pdks.itiraz where gun_kaydi_id = test.gk('EF01')));
select pdks.itiraz_karar((select id from pdks.itiraz where gun_kaydi_id = test.gk('EF01')), true, 'Kapı kaydı doğruluyor');
select pdks.kayit_duzelt(test.gk('EF01'), 'giris_zamani', '2026-10-13 07:55+03', 'İtiraz kabul: kapı kaydı 07:55',
                         p_itiraz_id => (select id from pdks.itiraz where gun_kaydi_id = test.gk('EF01')));
select test.dogrula('itiraz kabul edildi ve düzeltme itiraza bağlandı',
    test.sor($$select i.durum = 'kabul' and exists (select 1 from pdks.duzeltme d where d.itiraz_id = i.id)
               from pdks.itiraz i where i.gun_kaydi_id = test.gk('EF01')$$)::boolean);

select pdks.vardiya_plani_gir(test.c('EF03'), current_date - 2, 1::smallint, 'İK girdi');
select test.hata('İK kendi girdiği geçmiş planı onaylayamaz', 'kendi girdiğiniz planı',
    $$select pdks.vardiya_plani_onayla((select id from pdks.vardiya_plani
                                        where calisan_id = test.c('EF03') and tarih = current_date - 2), true)$$);
select test.oturum('ef_ik2@ornek.test');
select pdks.vardiya_plani_onayla((select id from pdks.vardiya_plani
                                  where calisan_id = test.c('EF03') and tarih = current_date - 2), true);
select test.dogrula('başka İK planı onayladı',
    test.sor($$select ik_onay_durumu = 'onaylandi' from pdks.vardiya_plani
               where calisan_id = test.c('EF03') and tarih = current_date - 2$$)::boolean);

select pdks.fazla_mesai_karar((select id from pdks.fazla_mesai_plani where calisan_id = test.c('EF01')), true, 'Uygun');
select test.dogrula('İK fazla mesai talebini onayladı',
    test.sor($$select durum = 'onaylandi' from pdks.fazla_mesai_plani where calisan_id = test.c('EF01')$$)::boolean);
select pdks.uyari_goruldu((select id from pdks.uyari where mesaj = 'Örnek uyarı'));
select test.dogrula('uyarı "görüldü" oldu',
    test.sor($$select goruldu from pdks.uyari where mesaj = 'Örnek uyarı'$$)::boolean);
select test.dogrula('İK izin girebilir',
    pdks.izin_gir(test.c('EF03'), 'yillik', current_date + 20, current_date + 21) is not null);
select test.dogrula('İK yazılı fazla mesai onayı girebilir',
    pdks.fazla_mesai_onayi_gir(test.c('EF03'), 2026::smallint, '2026-01-05', 'EF-FMO-2') is not null);

select pdks.kart_iptal_et((select id from pdks.kart where kart_no = 'EF-K02'), 'kayip');
select test.dogrula('kart iptal edildi, yeni kart tanımlandı',
    pdks.kart_tanimla(test.c('EF02'), 'EF-K02B') is not null
    and test.sor($$select durum = 'iptal' from pdks.kart where kart_no = 'EF-K02'$$)::boolean);
select test.hata('aktif kartı olan çalışana ikinci kart tanımlanamaz', 'aktif kartı var',
    $$select pdks.kart_tanimla(test.c('EF01'), 'EF-K01B')$$);
select test.dogrula('İK arıza girebilir',
    pdks.ariza_gir((select id from pdks.okuyucu where kod = 'EF-PDKS'), '2026-10-13 05:00+03', '2026-10-13 07:00+03') is not null);

-- Dosya yükleme
select test.dogrula('PDKS dosyası yüklendi, okutmalar yazıldı',
    pdks.dosya_yukle('pdks', 'ef_pdks_20261014.csv', '2026-10-14',
        '[{"okuyucu": "EF-PDKS", "kart_no": "EF-K01", "zaman": "2026-10-14T07:51:00+03:00", "yon": "giris"},
          {"okuyucu": "EF-PDKS", "kart_no": "EF-K01", "zaman": "2026-10-14T17:04:00+03:00", "yon": "cikis"}]') is not null
    and test.sor($$select count(*) = 2 from pdks.ham_okutma where kart_no = 'EF-K01'$$)::boolean);
select test.hata('aynı dosya ikinci kez yüklenemez', 'daha önce yüklenmiş',
    $$select pdks.dosya_yukle('pdks', 'tekrar.csv', '2026-10-14',
        '[{"okuyucu": "EF-PDKS", "kart_no": "EF-K01", "zaman": "2026-10-14T07:51:00+03:00", "yon": "giris"},
          {"okuyucu": "EF-PDKS", "kart_no": "EF-K01", "zaman": "2026-10-14T17:04:00+03:00", "yon": "cikis"}]')$$);
select test.hata('kaynağa ait olmayan okuyucu reddedilir', 'Okuyucu tanımlı değil',
    $$select pdks.dosya_yukle('kapi', 'kapi.csv', '2026-10-14',
        '[{"okuyucu": "EF-PDKS", "kart_no": "EF-K01", "zaman": "2026-10-14T07:50:00+03:00", "yon": "giris"}]')$$);
select test.dogrula('kapı dosyası kanıt kaydı olarak yazıldı',
    pdks.dosya_yukle('kapi', 'ef_kapi_20261014.csv', '2026-10-14',
        '[{"okuyucu": "EF-KAPI", "kart_no": "EF-K01", "zaman": "2026-10-14T07:48:00+03:00", "yon": "giris"}]') is not null
    and test.sor($$select count(*) = 1 from pdks.kanit_kaydi where kart_no = 'EF-K01' and kaynak = 'kapi'$$)::boolean);

-- Ay kilidi
select test.hata('açık soru varken ay kilitlenemez', 'açık soru veya itiraz',
    $$select pdks.ay_kilitle(2026::smallint, 10::smallint)$$);

-- 4) Güvenlik -----------------------------------------------------------------
select test.oturum('ef_guv@ornek.test');
select test.hata('güvenlik kendine geçici kart veremez', 'Görevler ayrılığı',
    $$select pdks.gecici_kart_ver((select id from pdks.gecici_kart where kart_no = 'EF-GK1'), test.c('EF31'))$$);
select test.dogrula('güvenlik geçici kart verdi',
    pdks.gecici_kart_ver((select id from pdks.gecici_kart where kart_no = 'EF-GK1'), test.c('EF01'), 'Kartını unuttu') is not null);
select pdks.gecici_kart_iade_al((select id from pdks.gecici_kart_zimmet where calisan_id = test.c('EF01')));
select test.dogrula('güvenlik iadeyi aldı',
    test.sor($$select iade_zamani is not null from pdks.gecici_kart_zimmet where calisan_id = test.c('EF01')$$)::boolean);
select test.hata('iade alınmış zimmet tekrar iade alınamaz', 'Açık zimmet bulunamadı',
    $$select pdks.gecici_kart_iade_al((select id from pdks.gecici_kart_zimmet where calisan_id = test.c('EF01')))$$);

-- 5) Amir cevabından sonra çıkış (Bobinaj amiri) -------------------------------
select test.oturum('ef_amir_b@ornek.test');
select pdks.soru_cevapla(test.soru('EF03'), 'geldi_saat_farkli', p_cikis => '2026-10-13 17:30+03');
select test.dogrula('"saat farklı": amirin girdiği çıkış saati yazıldı',
    test.sor($$select cikis_zamani = '2026-10-13 17:30+03' and cikis_kaynagi = 'amir'
               from pdks.gun_kaydi where id = test.gk('EF03')$$)::boolean);

reset role;
do $$ begin raise notice 'EKRAN FONKSİYONLARI TESTLERİ GEÇTİ'; end $$;
rollback;
