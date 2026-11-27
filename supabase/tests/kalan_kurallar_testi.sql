-- =====================================================================
-- Kalan kurallar testleri (20261231180000_kalan_kurallar.sql, T-07, T-34, T-84)
-- Testin kendi sahte verisi (Kasım 2026); örnek veri yüklü olsun olmasın çalışır.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/kalan_kurallar_testi.sql
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
create function test.ts(p text) returns timestamptz language sql immutable as $$
    select (p::timestamp) at time zone 'Europe/Istanbul' $$;
create function test.plan(p_sicil text, p_gun date) returns pdks.fazla_mesai_plani language sql security definer as $$
    select * from pdks.fazla_mesai_plani where calisan_id = test.c(p_sicil) and is_gunu = p_gun $$;
create function test.hv(p_sicil text, p_gun date) returns pdks.fazla_mesai_inceleme language sql security definer as $$
    select * from pdks.fazla_mesai_inceleme where calisan_id = test.c(p_sicil) and is_gunu = p_gun $$;
create function test.kilit(p_yil int, p_ay int) returns jsonb language sql security definer as $$
    select z.ozet from pdks.donem_kilit_izi z join pdks.donem d on d.id = z.donem_id
    where d.yil = p_yil and d.ay = p_ay order by z.kilit_zamani desc limit 1 $$;
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

create function test.gk(p_sicil text, p_gun date) returns pdks.gun_kaydi language sql security definer as $$
    select * from pdks.gun_kaydi where calisan_id = test.c(p_sicil) and is_gunu = p_gun $$;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
--   KL01: 5 Kasım ve 6 Kasım günleri var · KL02: 6 Kasım günü var · KLI1, KLI2: İK · KLG1: güvenlik
insert into pdks.departman (ad) values ('KL Üretim'), ('KL İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = case when s like 'KL0%' then 'KL Üretim' else 'KL İdari' end), '2025-01-01'
from unnest(array['KL01','KL02','KLI1','KLI2','KLG1']) s;
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('x', 'kl_ik1@ornek.test', 'ik',       test.c('KLI1'), '00000000-0000-0000-0000-000000000fd1'),
    ('x', 'kl_ik2@ornek.test', 'ik',       test.c('KLI2'), '00000000-0000-0000-0000-000000000fd2'),
    ('x', 'kl_gv@ornek.test',  'guvenlik', test.c('KLG1'), '00000000-0000-0000-0000-000000000fd3');
insert into pdks.gun_kaydi (calisan_id, is_gunu, durum, giris_zamani, cikis_zamani, hesap_tamam, calisma_dk)
values (test.c('KL01'), '2026-11-05', 'tamam', test.ts('2026-11-05 08:35'), test.ts('2026-11-05 17:00'), true, 445),
       (test.c('KL01'), '2026-11-06', 'tamam', test.ts('2026-11-06 08:40'), test.ts('2026-11-06 17:00'), true, 440),
       (test.c('KL02'), '2026-11-06', 'tamam', test.ts('2026-11-06 08:30'), test.ts('2026-11-06 17:00'), true, 450);
insert into pdks.gecici_kart (kart_no) values ('KL-GK1'), ('KL-GK2');

-- 1) T-07: v_izin_amir'in açıklaması var --------------------------------------------------------
select test.dogrula('v_izin_amir açıklaması: amirin izin görünümü, tür gizli, neden RLS dışı',
    obj_description('pdks.v_izin_amir'::regclass) like '%izin türü gizlidir%');

-- 2) T-34: düzeltmeye yalnızca aynı günün, reddedilmemiş itirazı bağlanır --------------------------
set local role authenticated;
select test.oturum('kl_ik1@ornek.test');
select pdks.itiraz_gir((test.gk('KL02', '2026-11-06')).id, 'KL02: servis geç geldi');
select pdks.itiraz_gir((test.gk('KL01', '2026-11-06')).id, 'KL01: kart unuttum, 08:00''de geldim');
select test.oturum('kl_ik2@ornek.test');
select test.hata('başka çalışanın itirazı bağlanamaz', 'bu güne ait değil',
    $$select pdks.kayit_duzelt((test.gk('KL01', '2026-11-05')).id, 'giris_zamani', '2026-11-05 08:00+03', 'İtiraz kabulü',
                               p_itiraz_id => (select id from pdks.itiraz where calisan_id = test.c('KL02')))$$);
select test.hata('aynı çalışanın başka günündeki itirazı bağlanamaz', 'bu güne ait değil',
    $$select pdks.kayit_duzelt((test.gk('KL01', '2026-11-05')).id, 'giris_zamani', '2026-11-05 08:00+03', 'İtiraz kabulü',
                               p_itiraz_id => (select id from pdks.itiraz where gun_kaydi_id = (test.gk('KL01', '2026-11-06')).id))$$);
select pdks.itiraz_karar((select id from pdks.itiraz where calisan_id = test.c('KL02')), false, 'Servis kaydı geç gelişi doğrulamıyor');
select test.hata('reddedilmiş itiraz bağlanamaz', 'reddedilmiş',
    $$select pdks.kayit_duzelt((test.gk('KL02', '2026-11-06')).id, 'giris_zamani', '2026-11-06 08:00+03', 'Düzeltme',
                               p_itiraz_id => (select id from pdks.itiraz where calisan_id = test.c('KL02')))$$);
select pdks.itiraz_karar((select id from pdks.itiraz where gun_kaydi_id = (test.gk('KL01', '2026-11-06')).id), true, 'Kapı kaydı 07:58');
select pdks.kayit_duzelt((test.gk('KL01', '2026-11-06')).id, 'giris_zamani', '2026-11-06 08:00+03', 'İtiraz kabulü',
                         p_itiraz_id => (select id from pdks.itiraz where gun_kaydi_id = (test.gk('KL01', '2026-11-06')).id));
reset role;
select test.dogrula('bağlanan düzeltme yazıldı (KL01, 6 Kasım)',
    exists (select 1 from pdks.duzeltme d join pdks.itiraz i on i.id = d.itiraz_id
            where d.gun_kaydi_id = (test.gk('KL01', '2026-11-06')).id and i.gun_kaydi_id = d.gun_kaydi_id));

-- 3) T-84: ileri tarihli zimmet ve iade reddedilir ------------------------------------------------
select test.hata('ileri tarihli veriliş reddedilir (Türkçe, çakışma mesajı değil)', 'Zimmetin veriliş zamanı ileri olamaz',
    $$insert into pdks.gecici_kart_zimmet (gecici_kart_id, calisan_id, verilis_zamani, veren_id)
      values ((select id from pdks.gecici_kart where kart_no = 'KL-GK1'), test.c('KL01'), now() + interval '30 days',
              test.k('kl_gv@ornek.test'))$$);
insert into pdks.gecici_kart_zimmet (gecici_kart_id, calisan_id, verilis_zamani, veren_id)
values ((select id from pdks.gecici_kart where kart_no = 'KL-GK1'), test.c('KL01'), now() - interval '2 hours', test.k('kl_gv@ornek.test'));
select test.hata('ileri tarihli iade reddedilir', 'İade zamanı ileri olamaz',
    $$update pdks.gecici_kart_zimmet set iade_zamani = now() + interval '30 days', iade_alan_id = test.k('kl_gv@ornek.test')
      where calisan_id = test.c('KL01') and iade_zamani is null$$);
select test.hata('verilişten önceki iade reddedilir (Türkçe, ham aralık hatası değil)', 'İade zamanı veriliş zamanından önce olamaz',
    $$update pdks.gecici_kart_zimmet set iade_zamani = now() - interval '3 hours', iade_alan_id = test.k('kl_gv@ornek.test')
      where calisan_id = test.c('KL01') and iade_zamani is null$$);
update pdks.gecici_kart_zimmet set iade_zamani = now(), iade_alan_id = test.k('kl_gv@ornek.test')
where calisan_id = test.c('KL01') and iade_zamani is null;
select test.dogrula('şimdiki zamanla iade kabul edilir',
    (select iade_zamani is not null from pdks.gecici_kart_zimmet where calisan_id = test.c('KL01')));

do $$ begin raise notice 'TÜM TESTLER GEÇTİ'; end $$;
rollback;
