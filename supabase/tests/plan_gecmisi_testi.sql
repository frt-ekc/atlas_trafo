-- =====================================================================
-- Vardiya planı geçmişi testleri (20261229010000_plan_gecmisi.sql, T-49)
--   Plan her değiştiğinde ya da silindiğinde eski hâli vardiya_plani_gecmisi'ne yazılır.
--   İK geriye dönük değişikliği reddedince son geçerli plan geri gelir; gün işlenmemişse işlenir.
-- Testin kendi sahte verisi (Ekim 2026) kullanılır; örnek veri yüklü olsun olmasın çalışır.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/plan_gecmisi_testi.sql
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
create function test.plan(p_sicil text, p_gun date) returns pdks.vardiya_plani language sql security definer as $$
    select * from pdks.vardiya_plani where calisan_id = test.c(p_sicil) and tarih = p_gun $$;
-- Planın vardiya kodu ve onay durumu: 'GUNDUZ/gerekmez' gibi
create function test.pd(p_sicil text, p_gun date) returns text language sql security definer as $$
    select v.kod || '/' || p.ik_onay_durumu from pdks.vardiya_plani p join pdks.vardiya_tanim v on v.id = p.vardiya_id
    where p.calisan_id = test.c(p_sicil) and p.tarih = p_gun $$;
create function test.gk(p_sicil text, p_gun date) returns pdks.gun_kaydi language sql security definer as $$
    select * from pdks.gun_kaydi where calisan_id = test.c(p_sicil) and is_gunu = p_gun $$;
-- Geçmiş satırları, eskiden yeniye: 'GUNDUZ/gerekmez/degisti' gibi
create function test.gecmis(p_sicil text, p_gun date) returns text[] language sql security definer as $$
    select array_agg(v.kod || '/' || g.ik_onay_durumu || '/' || g.islem order by g.id)
    from pdks.vardiya_plani_gecmisi g join pdks.vardiya_tanim v on v.id = g.vardiya_id
    where g.calisan_id = test.c(p_sicil) and g.tarih = p_gun $$;
create function test.gir(p_sicil text, p_gun date, p_kod text) returns bigint language sql as $$
    select pdks.vardiya_plani_gir(test.c(p_sicil), p_gun, test.v(p_kod), 'Amir değiştirdi') $$;
create function test.karar(p_sicil text, p_gun date, p_onay boolean) returns void language sql as $$
    select pdks.vardiya_plani_onayla((test.plan(p_sicil, p_gun)).id, p_onay) $$;
create function test.ts(p text) returns timestamptz language sql immutable as $$
    select (p::timestamp) at time zone 'Europe/Istanbul' $$;
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
--   VP01: 19 Ekim GÜNDÜZ; amir AKŞAM yapar, dosya gelir (gün onay beklediği için işlenmez), İK reddeder
--   VP02: 16 Ekim GÜNDÜZ'le işlenmiş; amir SABAH yapar, İK reddeder
--   VP03: 15 Ekim GÜNDÜZ; amir önce SABAH, sonra AKŞAM yapar; İK reddeder
--   VP04: 14 Ekim'de planı yok; amir AKŞAM girer, İK reddeder
--   VP05: 19 Ekim GÜNDÜZ; amir AKŞAM yapar, İK onaylar
insert into pdks.departman (ad) values ('VP Üretim'), ('VP İdari'), ('VP Depo');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = d), '2025-01-01'
from (values ('VP01', 'VP Üretim'), ('VP02', 'VP Üretim'), ('VP03', 'VP Üretim'), ('VP04', 'VP Üretim'),
             ('VP05', 'VP Üretim'), ('VPA1', 'VP Üretim'), ('VPI1', 'VP İdari'), ('VPD1', 'VP Depo')) v(s, d);
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('VP Amir',      'vp_amir@ornek.test',  'amir', test.c('VPA1'), '00000000-0000-0000-0000-00000000bb01'),
    ('VP İK',        'vp_ik@ornek.test',    'ik',   test.c('VPI1'), '00000000-0000-0000-0000-00000000bb02'),
    ('VP Depo Amir', 'vp_amir2@ornek.test', 'amir', test.c('VPD1'), '00000000-0000-0000-0000-00000000bb03');
update pdks.departman set amir_id = test.k('vp_amir@ornek.test') where ad = 'VP Üretim';
update pdks.departman set amir_id = test.k('vp_amir2@ornek.test') where ad = 'VP Depo';
insert into pdks.kart (kart_no, calisan_id) values ('VP-01', test.c('VP01')), ('VP-02', test.c('VP02'));
insert into pdks.okuyucu (kod, ad, sistem) values ('VP-PDKS', 'VP PDKS', 'pdks');

insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id, giren_id)
select test.c(s), t::date, test.v('GUNDUZ'), test.k('vp_ik@ornek.test')
from (values ('VP01', '2026-10-19'), ('VP02', '2026-10-16'), ('VP03', '2026-10-15'), ('VP05', '2026-10-19')) x(s, t);

insert into pdks.aktarim (kaynak, dosya_adi, dosya_ozeti, veri_tarihi)
select 'pdks', 'vp_' || d || '.csv', 'vp-pdks-' || d, d::date from unnest(array['2026-10-16', '2026-10-19']) d;
insert into pdks.ham_okutma (aktarim_id, okuyucu_id, kart_no, okutma_zamani, yon)
select (select id from pdks.aktarim where dosya_ozeti = 'vp-pdks-' || (z::timestamp)::date),
       (select id from pdks.okuyucu where kod = 'VP-PDKS'), k, test.ts(z), y
from (values ('VP-02', '2026-10-16 08:00', 'giris'), ('VP-02', '2026-10-16 17:00', 'cikis'),
             ('VP-01', '2026-10-19 08:00', 'giris'), ('VP-01', '2026-10-19 17:00', 'cikis')) v(k, z, y);

-- 17 Ekim: 16 Ekim işlendi (VP02 GÜNDÜZ)
set local pdks.test_bugun = '2026-10-17';
select pdks.gece_isi_calistir('2026-10-16');
select test.dogrula('hazırlık: VP02''nin 16 Ekim günü GÜNDÜZ''le işlendi',
    (test.gk('VP02', '2026-10-16')).vardiya_id = test.v('GUNDUZ') and (test.gk('VP02', '2026-10-16')).calisma_dk = 480);
select test.dogrula('hazırlık: henüz geçmiş yok (doğrudan eklenen plan iz bırakmaz)',
    test.gecmis('VP01', '2026-10-19') is null);

-- 20 Ekim: amir geriye dönük değişiklikler girer
set local pdks.test_bugun = '2026-10-20';
set local role authenticated;
select test.oturum('vp_amir@ornek.test');
select test.gir('VP01', '2026-10-19', 'V2');
select test.gir('VP02', '2026-10-16', 'V1');
select test.gir('VP03', '2026-10-15', 'V1');
select test.gir('VP03', '2026-10-15', 'V2');
select test.gir('VP04', '2026-10-14', 'V2');
select test.gir('VP05', '2026-10-19', 'V2');
reset role;
select test.dogrula('değişiklikler İK onayı bekliyor; eski plan geçmişe yazıldı',
    test.pd('VP01', '2026-10-19') = 'V2/bekliyor'
    and test.gecmis('VP01', '2026-10-19') = array['GUNDUZ/gerekmez/degisti']);

-- 19 Ekim dosyası geldi; VP01'in günü plan onay beklediği için işlenmez
select pdks.gece_isi_calistir('2026-10-19');
select test.dogrula('hazırlık: VP01''in 19 Ekim günü onay beklediği için işlenmedi',
    (test.gk('VP01', '2026-10-19')).id is null);

-- 1) Ret eski planı geri getirir, gün işlenir (raporun VP5'i) ---------------------
set local role authenticated;
select test.oturum('vp_ik@ornek.test');
select test.karar('VP01', '2026-10-19', false);
reset role;
select test.dogrula('T-49: İK reddedince GÜNDÜZ planı geri geldi',
    test.pd('VP01', '2026-10-19') = 'GUNDUZ/gerekmez' and not (test.plan('VP01', '2026-10-19')).geriye_donuk);
select test.dogrula('T-49: gün hemen GÜNDÜZ''e göre işlendi (çalışma 480)',
    (test.gk('VP01', '2026-10-19')).vardiya_id = test.v('GUNDUZ') and (test.gk('VP01', '2026-10-19')).calisma_dk = 480);
select test.dogrula('geçmiş, reddedilen değişikliği de saklıyor (kim neyi değiştirdi)',
    test.gecmis('VP01', '2026-10-19') = array['GUNDUZ/gerekmez/degisti', 'V2/bekliyor/degisti', 'V2/reddedildi/degisti']);

-- 2) İşlenmiş günde ret: plan satırı gerçekte uygulanan planı gösterir (raporun VP4'ü) --
set local role authenticated;
select test.oturum('vp_ik@ornek.test');
select test.karar('VP02', '2026-10-16', false);
reset role;
select test.dogrula('T-49: işlenmiş günde ret sonrası plan yine GÜNDÜZ, gün değişmedi',
    test.pd('VP02', '2026-10-16') = 'GUNDUZ/gerekmez' and (test.gk('VP02', '2026-10-16')).vardiya_id = test.v('GUNDUZ'));

-- 3) İki kez değiştirilen plan: son GEÇERLİ plan geri gelir -----------------------------
set local role authenticated;
select test.oturum('vp_ik@ornek.test');
select test.karar('VP03', '2026-10-15', false);
reset role;
select test.dogrula('SABAH sonra AKŞAM girilmişti; ret GÜNDÜZ''e döndü (onaylanmamış SABAH''a değil)',
    test.pd('VP03', '2026-10-15') = 'GUNDUZ/gerekmez');

-- 4) Önceden plan yoksa geri getirilecek bir şey yok --------------------------------
set local role authenticated;
select test.oturum('vp_ik@ornek.test');
select test.karar('VP04', '2026-10-14', false);
reset role;
select test.dogrula('önceden planı olmayan günde ret eskisi gibi: plan "reddedildi" kalır',
    test.pd('VP04', '2026-10-14') = 'V2/reddedildi');

-- 5) Onay eskisi gibi çalışır ----------------------------------------------------------
set local role authenticated;
select test.oturum('vp_ik@ornek.test');
select test.karar('VP05', '2026-10-19', true);
reset role;
select test.dogrula('onaylanan değişiklik geçerli; eski GÜNDÜZ geçmişte duruyor',
    test.pd('VP05', '2026-10-19') = 'V2/onaylandi'
    and test.gecmis('VP05', '2026-10-19') = array['GUNDUZ/gerekmez/degisti', 'V2/bekliyor/degisti']);

-- 6) Geçmiş silinmez, değiştirilmez; silinen planın da izi kalır ----------------------------
select test.hata('geçmiş satırı değiştirilemez', 'değiştirilemez',
    format('update pdks.vardiya_plani_gecmisi set vardiya_id = %s where calisan_id = %s', test.v('V3'), test.c('VP01')));
select test.hata('geçmiş satırı silinemez', 'değiştirilemez',
    format('delete from pdks.vardiya_plani_gecmisi where calisan_id = %s', test.c('VP01')));
delete from pdks.vardiya_plani where calisan_id = test.c('VP03') and tarih = '2026-10-15';
select test.dogrula('silinen planın son hâli geçmişe "silindi" olarak yazıldı',
    (test.gecmis('VP03', '2026-10-15'))[array_length(test.gecmis('VP03', '2026-10-15'), 1)] = 'GUNDUZ/gerekmez/silindi');

-- 7) Kim görür -----------------------------------------------------------------------
set local role authenticated;
select test.oturum('vp_amir@ornek.test');
select test.dogrula('amir kendi bölümünün plan geçmişini görür',
    (select count(*) > 0 from pdks.vardiya_plani_gecmisi where calisan_id = test.c('VP01')));
select test.oturum('vp_amir2@ornek.test');
select test.dogrula('başka bölümün amiri göremez',
    (select count(*) = 0 from pdks.vardiya_plani_gecmisi where calisan_id = test.c('VP01')));
select test.oturum('vp_ik@ornek.test');
select test.dogrula('İK görür', (select count(*) > 0 from pdks.vardiya_plani_gecmisi where calisan_id = test.c('VP01')));
select test.hata('ekrandan geçmişe kayıt eklenemez', 'permission denied',
    format('insert into pdks.vardiya_plani_gecmisi (plan_id, calisan_id, tarih, vardiya_id, geriye_donuk, ik_onay_durumu, giris_zamani, islem) values (1, %s, %L, %s, false, %L, now(), %L)',
           test.c('VP01'), '2026-10-19', test.v('V3'), 'gerekmez', 'degisti'));
reset role;

rollback;
