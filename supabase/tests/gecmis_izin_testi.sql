-- =====================================================================
-- Geçmiş güne izin ve İK düzeltmesinin soruyu kapatması (20261225010000_gecmis_izin.sql, T-46 + T-40)
-- 12–16 Ekim 2026 hafta içi. Testin kendi sahte verisi.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/gecmis_izin_testi.sql
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
create function test.soru(p_sicil text, p_gun date, p_tur text default null) returns pdks.amir_sorusu language sql security definer as $$
    select q.* from pdks.amir_sorusu q join pdks.gun_kaydi g on g.id = q.gun_kaydi_id
    where g.calisan_id = test.c(p_sicil) and g.is_gunu = p_gun and (p_tur is null or q.soru_turu = p_tur) order by q.id desc limit 1 $$;
create function test.uy(p_sicil text) returns text language sql security definer as $$
    select string_agg(mesaj, ' | ' order by id) from pdks.uyari where tur = 'izin_gununde_okutma' and calisan_id = test.c(p_sicil) $$;
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
--   12–14 Ekim GUNDUZ planlı; aksi yazılmadıkça 13 Ekim'de hiç okutma yok (amire soru)
--   GI01: rapor, iptal      GI02: yıllık, iptal yok     GI03: 13'ünde 08–17 okutma   GI04: yalnızca giriş
--   GI05: amir "gelmedi", sonra rapor      GI06: devamsız, sonra rapor, iptal
--   GI07: izinden sonra İK başka karar     GI08: kilitli ay     GI09: KS2 (İK girişi düzeltir)
--   GI10: DV1 (İK devamsız)                GI11: hiç kayıt yok, İK yalnızca girişi düzeltir
--   GI12: okutmalı güne izin, soru açık    GI13: izinsiz devamsız     GI14: gece işinden geçen izin
insert into pdks.departman (ad) values ('GI Üretim'), ('GI İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = case when s ~ 'GI[IA]' then 'GI İdari' else 'GI Üretim' end), '2025-01-01'
from (select 'GI' || lpad(n::text, 2, '0') as s from generate_series(1, 14) n union all select unnest(array['GII1', 'GII2', 'GIA1'])) x;
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('x', 'gi_ik1@ornek.test',  'ik',   test.c('GII1'), '00000000-0000-0000-0000-0000000000d7'),
    ('x', 'gi_ik2@ornek.test',  'ik',   test.c('GII2'), '00000000-0000-0000-0000-0000000000d8'),
    ('x', 'gi_amir@ornek.test', 'amir', test.c('GIA1'), '00000000-0000-0000-0000-0000000000d9');
update pdks.departman set amir_id = test.k('gi_amir@ornek.test') where ad like 'GI %';
insert into pdks.kart (kart_no, calisan_id) select 'K-' || sicil_no, id from pdks.calisan where sicil_no like 'GI__';
insert into pdks.okuyucu (kod, ad, sistem) values ('GI-PDKS', 'GI PDKS', 'pdks');
insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id, giren_id)
select c.id, g::date, (select id from pdks.vardiya_tanim where kod = 'GUNDUZ'), test.k('gi_ik1@ornek.test')
from pdks.calisan c cross join generate_series(date '2026-10-12', date '2026-10-14', '1 day') g
where c.sicil_no like 'GI__' and c.sicil_no !~ 'GI[IA]';
insert into pdks.aktarim (kaynak, dosya_adi, dosya_ozeti, veri_tarihi)
select 'pdks', 'gi_' || g || '.csv', 'gi-pdks-' || g, g::date
from unnest(array['2026-10-12', '2026-10-13', '2026-10-14', '2026-10-15']) g;
insert into pdks.ham_okutma (aktarim_id, okuyucu_id, kart_no, okutma_zamani, yon)
select (select id from pdks.aktarim where dosya_ozeti = 'gi-pdks-2026-10-13'),
       (select id from pdks.okuyucu where kod = 'GI-PDKS'), 'K-' || s, test.ts(z), y
from (values ('GI03', '2026-10-13 08:00', 'giris'), ('GI03', '2026-10-13 17:00', 'cikis'),
             ('GI04', '2026-10-13 08:00', 'giris'), ('GI12', '2026-10-13 08:00', 'giris'),
             ('GI09', '2026-10-13 17:00', 'cikis')) v(s, z, y);
insert into pdks.ham_okutma (aktarim_id, okuyucu_id, kart_no, okutma_zamani, yon)
select (select id from pdks.aktarim where dosya_ozeti = 'gi-pdks-' || g::date),
       (select id from pdks.okuyucu where kod = 'GI-PDKS'), 'K-' || c.sicil_no, test.ts(g::date || ' ' || x.s), x.y
from pdks.calisan c cross join unnest(array['2026-10-12', '2026-10-14']) g
cross join (values ('08:00', 'giris'), ('17:00', 'cikis')) x(s, y)
where c.sicil_no like 'GI__' and c.sicil_no !~ 'GI[IA]' and c.sicil_no <> 'GI14';
insert into pdks.izin (calisan_id, tur, baslangic, bitis, giren_id)
values (test.c('GI14'), 'yillik', '2026-10-12', '2026-10-14', test.k('gi_ik1@ornek.test'));
select pdks.gece_isi_calistir(g::date) from generate_series(date '2026-10-12', date '2026-10-14', '1 day') g;
select test.dogrula('hazırlık: 13 Ekim''de okutması olmayana soru açıldı, gün bekliyor',
    (test.soru('GI01', '2026-10-13')).durum = 'acik' and (test.gk('GI01', '2026-10-13')).durum = 'soru_bekliyor');

-- 1) Geçmiş güne izin -----------------------------------------------------------------
set local role authenticated;
select test.oturum('gi_ik1@ornek.test');
select pdks.izin_gir(test.c('GI01'), 'rapor', '2026-10-13', '2026-10-13', 'Doktor raporu');
select pdks.izin_gir(test.c('GI02'), 'yillik', '2026-10-13', '2026-10-13');
reset role;
select test.dogrula('rapor: gün raporlu, hesap kapandı; düzeltme izi izne bağlı',
    (select durum = 'raporlu' and hesap_tamam from test.gk('GI01', '2026-10-13'))
    and exists (select 1 from pdks.duzeltme d where d.gun_kaydi_id = (test.gk('GI01', '2026-10-13')).id and d.alan = 'durum'
                and d.eski_deger = 'soru_bekliyor' and d.yeni_deger = 'raporlu' and d.izin_id = test.izin('GI01')
                and d.kaynak = 'ik' and d.yapan_id = test.k('gi_ik1@ornek.test') and not d.calisan_aleyhine));
select test.dogrula('açık soru "İzin girildi" nedeniyle kapandı (kim, ne zaman)',
    (select durum = 'kapandi' and kapanis_nedeni = 'İzin girildi' and kapatan_id = test.k('gi_ik1@ornek.test')
            and kapanis_zamani is not null and onceki_durum = 'acik' and kapatan_izin_id = test.izin('GI01')
     from test.soru('GI01', '2026-10-13')));
select test.dogrula('yıllık izin: gün izinli; puantaj kodları RPR ve Yİ',
    (test.gk('GI02', '2026-10-13')).durum = 'izinli' and test.kod('GI02', '2026-10-13') = 'Yİ 1 gün 0 dk'
    and test.kod('GI01', '2026-10-13') = 'RPR 1 gün 0 dk');
set local role authenticated;
select test.oturum('gi_amir@ornek.test');
select test.hata('amir kapanan soruya cevap veremez', 'zaten cevaplanmış',
    $$select pdks.soru_cevapla((test.soru('GI01', '2026-10-13')).id, 'gelmedi')$$);
select test.dogrula('amir soruda izin türünü görmez',
    (select kapanis_nedeni = 'İzin girildi' from pdks.amir_sorusu where id = (test.soru('GI01', '2026-10-13')).id)
    and not exists (select 1 from pdks.v_duzeltme_amir where calisan_id = test.c('GI01') and (yeni_deger = 'raporlu' or gerekce like '%İzin girildi%')));

-- 2) Okutma olan gün ---------------------------------------------------------------------
select test.oturum('gi_ik1@ornek.test');
select pdks.izin_gir(test.c('GI03'), 'yillik', '2026-10-12', '2026-10-14');
select pdks.izin_gir(test.c('GI04'), 'rapor', '2026-10-13', '2026-10-13');
select pdks.izin_gir(test.c('GI12'), 'rapor', '2026-10-13', '2026-10-13');
reset role;
select test.dogrula('okutması olan günler izinli yapılmadı, her gün için uyarı',
    (select count(*) = 3 from pdks.gun_kaydi where calisan_id = test.c('GI03') and durum = 'tamam')
    and test.uy('GI03') like 'İzin girilen günde okutma var (12.10.2026)%13.10.2026%14.10.2026%'
    and not exists (select 1 from pdks.duzeltme where calisan_id = test.c('GI03')));
select test.dogrula('yalnızca girişi olan gün de izinli yapılmadı; soru açık kaldı',
    (test.gk('GI04', '2026-10-13')).durum = 'soru_bekliyor' and (test.soru('GI04', '2026-10-13')).durum = 'acik'
    and test.uy('GI04') is not null);

-- 3) Devamsız kararı ----------------------------------------------------------------------
set local role authenticated;
select test.oturum('gi_ik2@ornek.test');
select test.hata('izin varken soru devamsız olarak kapatılamaz', '13.10.2026 günü için geçerli bir izni vardır; devamsız kararı verilemez',
    $$select pdks.soru_ik_karari((test.soru('GI12', '2026-10-13')).id, true, 'Gelmedi')$$);
select test.hata('izin varken kayıt düzeltme de devamsız yapamaz', 'devamsız kararı verilemez',
    $$select pdks.kayit_duzelt((test.gk('GI02', '2026-10-13')).id, 'durum', 'devamsiz', 'Haber vermedi')$$);
select pdks.soru_ik_karari((test.soru('GI13', '2026-10-13')).id, true, 'Haber vermeden gelmedi');
select test.dogrula('izni olmayan için devamsız kararı verilir', (test.gk('GI13', '2026-10-13')).durum = 'devamsiz');
select test.oturum('gi_amir@ornek.test');
select pdks.soru_cevapla((test.soru('GI05', '2026-10-13')).id, 'gelmedi', p_aciklama => 'Haber alınamadı');
select test.oturum('gi_ik1@ornek.test');
select pdks.izin_gir(test.c('GI05'), 'rapor', '2026-10-13', '2026-10-13');
reset role;
select test.dogrula('amir "gelmedi" demişse: gün raporlu, soru kapandı; amirin cevabı ve adı silinmedi',
    (test.gk('GI05', '2026-10-13')).durum = 'raporlu'
    and (select durum = 'kapandi' and onceki_durum = 'ik_karari_bekliyor' and cevap = 'gelmedi'
                and cevaplayan_id = test.k('gi_amir@ornek.test') and kapatan_id = test.k('gi_ik1@ornek.test')
         from test.soru('GI05', '2026-10-13')));

-- 4) İzin iptali ----------------------------------------------------------------------------
set local role authenticated;
select test.oturum('gi_ik2@ornek.test');
select pdks.izin_iptal(test.izin('GI01'), 'Yanlış kişiye girildi');
select pdks.izin_iptal(test.izin('GI05'), 'Rapor geçersiz');
reset role;
select test.dogrula('iptal: gün önceki haline döndü, düzeltme izi izne bağlı',
    (select durum = 'soru_bekliyor' and not hesap_tamam from test.gk('GI01', '2026-10-13'))
    and (select count(*) = 2 from pdks.duzeltme where gun_kaydi_id = (test.gk('GI01', '2026-10-13')).id and izin_id = test.izin('GI01')));
select test.dogrula('iptal: soru eski durumuyla açıldı, cevap süresi bugünden başlar',
    (select durum = 'acik' and kapanis_nedeni is null and kapatan_izin_id is null and son_cevap_tarihi > pdks.bugun()
     from test.soru('GI01', '2026-10-13'))
    and (select durum = 'ik_karari_bekliyor' and cevap = 'gelmedi' from test.soru('GI05', '2026-10-13')));
set local role authenticated;
select test.oturum('gi_ik1@ornek.test');
select pdks.soru_ik_karari((test.soru('GI06', '2026-10-13')).id, true, 'Haber vermeden gelmedi');
select pdks.izin_gir(test.c('GI06'), 'rapor', '2026-10-13', '2026-10-13');
select test.dogrula('devamsız güne sonradan rapor: gün raporlu', (test.gk('GI06', '2026-10-13')).durum = 'raporlu');
select pdks.izin_iptal(test.izin('GI06'), 'Rapor geçersiz çıktı');
select test.dogrula('iptal: devamsız gün devamsıza döner', (test.gk('GI06', '2026-10-13')).durum = 'devamsiz');
select pdks.izin_gir(test.c('GI07'), 'yillik', '2026-10-13', '2026-10-13');
select pdks.kayit_duzelt((test.gk('GI07', '2026-10-13')).id, 'durum', 'vardiya_yok', 'O gün vardiyası kaldırılmıştı');
select pdks.izin_iptal(test.izin('GI07'), 'İzin gerekmiyor');
select test.dogrula('izinden sonra başka karar verilmiş güne iptalde dokunulmaz, sorusu kapalı kalır',
    (test.gk('GI07', '2026-10-13')).durum = 'vardiya_yok' and (test.soru('GI07', '2026-10-13')).durum = 'kapandi');
select test.hata('gece işinden izinli geçen günü olan izin yine iptal edilemez', 'günü işlenmiş',
    $$select pdks.izin_iptal(test.izin('GI14'), 'Vazgeçildi')$$);
select pdks.izin_gir(test.c('GI01'), 'yillik', '2026-10-13', '2026-10-13');
select test.dogrula('iptalden sonra yeniden izin girilir',
    (test.gk('GI01', '2026-10-13')).durum = 'izinli' and (test.soru('GI01', '2026-10-13')).durum = 'kapandi');

-- 5) İK düzeltmesi soruyu kapatır (T-40) --------------------------------------------------------
select pdks.kayit_duzelt((test.gk('GI09', '2026-10-13')).id, 'giris_zamani', '2026-10-13 07:50+03', 'Kamera kaydı 07:50');
select test.dogrula('KS2: soru kapandı, gün hemen hesaplandı, İK saati duruyor',
    (select durum = 'kapandi' and kapanis_nedeni = 'İK kayıt düzeltmesi' from test.soru('GI09', '2026-10-13'))
    and (select durum = 'tamam' and hesap_tamam and giris_zamani = test.ts('2026-10-13 07:50') and calisma_dk = 480 from test.gk('GI09', '2026-10-13')));
select pdks.kayit_duzelt((test.gk('GI10', '2026-10-13')).id, 'durum', 'devamsiz', 'Haber vermeden gelmedi');
select test.oturum('gi_amir@ornek.test');
select test.hata('DV1: İK devamsız dedikten sonra amir cevap veremez', 'zaten cevaplanmış',
    $$select pdks.soru_cevapla((test.soru('GI10', '2026-10-13')).id, 'geldi_saat_dogru')$$);
reset role;
select test.dogrula('DV1: devamsız güne saat yazılmadı, hesap kapalı',
    (select durum = 'devamsiz' and giris_zamani is null and hesap_tamam from test.gk('GI10', '2026-10-13')));
-- Eski veri: devamsız günde soru açık kalmış olabilir
update pdks.amir_sorusu set durum = 'acik', onceki_durum = null, kapanis_nedeni = null, kapatan_id = null, kapanis_zamani = null
where id = (test.soru('GI10', '2026-10-13')).id;
set local role authenticated;
select test.oturum('gi_amir@ornek.test');
select test.hata('sonuçlanmış günde açık kalmış soruya da cevap verilemez', 'İK tarafından sonuçlandırılmıştır',
    $$select pdks.soru_cevapla((test.soru('GI10', '2026-10-13')).id, 'geldi_saat_dogru')$$);
select test.oturum('gi_ik1@ornek.test');
select pdks.kayit_duzelt((test.gk('GI11', '2026-10-13')).id, 'giris_zamani', '2026-10-13 07:45+03', 'Kamera kaydı');
select test.dogrula('yalnızca giriş düzeltildi, çıkış yok: soru açık kalır (gün askıda kalmaz)',
    (test.soru('GI11', '2026-10-13')).durum = 'acik');
select test.oturum('gi_amir@ornek.test');
select pdks.soru_cevapla((test.soru('GI11', '2026-10-13')).id, 'geldi_saat_dogru');
reset role;
select test.dogrula('amirin cevabı İK''nın girişini ezmez, çıkışı tamamlar',
    (select giris_zamani = test.ts('2026-10-13 07:45') and cikis_zamani = test.ts('2026-10-13 17:00') and hesap_tamam
     from test.gk('GI11', '2026-10-13')));

-- 6) Kilitli ay -----------------------------------------------------------------------------------
set local role authenticated;
select test.oturum('gi_ik1@ornek.test');
select pdks.ay_kilitle(2026::smallint, 10::smallint, true);
select pdks.izin_gir(test.c('GI08'), 'rapor', '2026-10-13', '2026-10-13');
reset role;
select test.dogrula('kilitli ay: gün değişmedi, düzeltme sonraki aya fark satırı; soru kapandı',
    (test.gk('GI08', '2026-10-13')).durum = 'soru_bekliyor'
    and (select d.fark_satiri and d.yeni_deger = 'raporlu' and (n.yil, n.ay) = (2026, 11) from pdks.duzeltme d join pdks.donem n on n.id = d.hedef_donem_id
         where d.izin_id = test.izin('GI08') order by d.id limit 1)
    and (test.soru('GI08', '2026-10-13')).durum = 'kapandi');
set local role authenticated;
select test.oturum('gi_ik1@ornek.test');
select pdks.izin_iptal(test.izin('GI08'), 'Rapor geçersiz');
reset role;
select test.dogrula('kilitli ayda iptal: ters fark satırı, soru yeniden açık',
    (select count(*) = 2 and bool_and(fark_satiri) and (array_agg(yeni_deger order by id desc))[1] = 'soru_bekliyor'
     from pdks.duzeltme where izin_id = test.izin('GI08'))
    and (test.soru('GI08', '2026-10-13')).durum = 'acik');
select test.dogrula('kilitli ayda izin ve iptalin net farkı sıfır',
    (select (pdks.gun_katkisi(g.id, array_agg(d.id))).raporlu_gun = 0 and (pdks.gun_katkisi(g.id, array_agg(d.id))).calisma_dk = 0
     from pdks.gun_kaydi g join pdks.duzeltme d on d.gun_kaydi_id = g.id
     where g.calisan_id = test.c('GI08') and g.is_gunu = '2026-10-13' group by g.id));

-- 7) Yetkiler -------------------------------------------------------------------------------------
select test.dogrula('yardımcılar ekrandan çağrılamaz',
    not has_function_privilege('authenticated', 'pdks.izin_gunlere_uygula(bigint, bigint)', 'execute')
    and not has_function_privilege('authenticated', 'pdks.izin_gunlerden_geri_al(bigint, bigint, text)', 'execute')
    and not has_function_privilege('authenticated', 'pdks.soru_kapat(bigint, bigint, text, bigint, text[])', 'execute'));

do $$ begin raise notice 'TÜM TESTLER GEÇTİ'; end $$;
rollback;
