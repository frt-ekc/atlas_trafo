-- =====================================================================
-- RLS hızı (20261206010000_rls_hizi.sql, T-104)
--   Departmanlar sayfasının 6 tablosu: gun_kaydi · calisan · amir_sorusu · itiraz ·
--   departman · vardiya_tanim; amirde yavaş çıkan 3 tablo: vardiya_plani ·
--   kanit_kaydi · ham_okutma
--
-- 1) Yapı: bu tabloların politikaları oturum fonksiyonlarını satır başına değil,
--    sorgu başına bir kez çalıştırır ("(select pdks.f())" kalıbı → InitPlan).
-- 2) Eşdeğerlik: her rolde görünen satırlar, eski politikaların ifadesiyle
--    hesaplanan satırlarla birebir aynıdır (yetki değişmedi, yalnızca hız).
-- 3) Hız: örnek veri yüklüyse Kasım gece işinden geçirilir; Montaj amirinin
--    v_departman_ozet, v_esnek_mesai, vardiya_plani, kanit_kaydi ve ham_okutma
--    okumaları 150 ms'nin, "Hasan'ın çalışanları" (oturum_calisanlari) 30 ms'nin
--    altında kalır. Örnek veri yoksa bu bölüm atlanır.
--    T-108: sınırlar ölçülen değere yakın tutulur (eskiden 500 ms; 50 ms'lik okuma
--    10 kat yavaşlayınca test bunu yakalayamadı).
-- 4) Yardımcılar (T-108): oturum_rolu, oturum_calisan_id, oturum_departmanlari,
--    oturum_calisanlari ve amirin_calisani_mi da oturumu kendi içlerinde satır başına
--    değil bir kez sorar ("(select pdks.f())").
--
-- Testin kendi sahte verisi kullanılır; örnek veri yüklü olsun olmasın çalışır.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/rls_hizi_testi.sql
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
create function test.oturum(p_eposta text) returns void language sql security definer as $$
    select set_config('request.jwt.claims',
        json_build_object('sub', (select auth_kullanici_id from pdks.kullanici where eposta = p_eposta),
                          'role', 'authenticated')::text, true);
$$;
create function test.c(p text) returns bigint language sql security definer as $$
    select id from pdks.calisan where sicil_no = p $$;
create function test.k(p text) returns bigint language sql security definer as $$
    select id from pdks.kullanici where eposta = p $$;
-- Bu testin kapsadığı tablolar
create function test.tablolar() returns text[] language sql immutable as $$
    select array['gun_kaydi', 'calisan', 'amir_sorusu', 'itiraz', 'departman', 'vardiya_tanim',
                 'vardiya_plani', 'kanit_kaydi', 'ham_okutma'] $$;

-- Oturumun gördüğü satırlar (RLS ile; authenticated rolüyle çağrılır)
create function test.gorunen(p_tablo text) returns bigint[] language plpgsql as $$
declare v bigint[];
begin
    execute format('select coalesce(array_agg(id::bigint order by id), ''{}'') from pdks.%I', p_tablo) into v;
    return v;
end $$;
-- Eski (20261205010000 sonrası, bu migration öncesi) politikaların ifadesiyle beklenen satırlar.
-- security definer: RLS'siz okur; oturum fonksiyonları aynı JWT'yi görür.
create function test.beklenen(p_tablo text) returns bigint[] language plpgsql security definer set search_path = pdks as $$
declare v bigint[];
begin
    case p_tablo
    when 'gun_kaydi' then
        select coalesce(array_agg(id order by id), '{}') into v from pdks.gun_kaydi
        where pdks.tum_veriyi_gorur() or pdks.amirin_calisani_mi(calisan_id);
    when 'itiraz' then
        select coalesce(array_agg(id order by id), '{}') into v from pdks.itiraz
        where pdks.tum_veriyi_gorur() or pdks.amirin_calisani_mi(calisan_id);
    when 'vardiya_plani' then
        select coalesce(array_agg(id order by id), '{}') into v from pdks.vardiya_plani
        where pdks.tum_veriyi_gorur() or pdks.amirin_calisani_mi(calisan_id);
    when 'calisan' then
        select coalesce(array_agg(id order by id), '{}') into v from pdks.calisan
        where pdks.oturum_rolu() in ('admin', 'isg', 'guvenlik') or pdks.tum_veriyi_gorur()
           or departman_id = any (pdks.oturum_departmanlari());
    when 'amir_sorusu' then
        select coalesce(array_agg(id order by id), '{}') into v from pdks.amir_sorusu
        where pdks.tum_veriyi_gorur()
           or (pdks.oturum_rolu() = 'amir'
               and (pdks.oturum_kullanici_id() = atanan_id or pdks.oturum_kullanici_id() = eskale_edilen_id));
    when 'departman' then
        select coalesce(array_agg(id::bigint order by id), '{}') into v from pdks.departman
        where pdks.tum_veriyi_gorur() or pdks.oturum_kullanici_id() is not null;
    when 'vardiya_tanim' then
        select coalesce(array_agg(id::bigint order by id), '{}') into v from pdks.vardiya_tanim
        where pdks.tum_veriyi_gorur() or pdks.oturum_kullanici_id() is not null;
    when 'kanit_kaydi' then
        select coalesce(array_agg(id order by id), '{}') into v from pdks.kanit_kaydi
        where pdks.tum_veriyi_gorur();
    when 'ham_okutma' then
        select coalesce(array_agg(id order by id), '{}') into v from pdks.ham_okutma
        where pdks.tum_veriyi_gorur();
    end case;
    return v;
end $$;
-- Bir oturum için bütün tabloları karşılaştırır; farklı olanları adıyla döner
create function test.farklar() returns text language plpgsql as $$
declare t text; f text := '';
begin
    foreach t in array test.tablolar() loop
        if test.gorunen(t) is distinct from test.beklenen(t) then
            f := f || t || ' (görünen ' || cardinality(test.gorunen(t)) || ', beklenen '
                   || cardinality(test.beklenen(t)) || ') ';
        end if;
    end loop;
    return f;
end $$;
-- Bir okumanın süresi (ms); çağıranın rolü ve oturumuyla çalışır
create function test.sure(p_sql text) returns numeric language plpgsql as $$
declare b timestamptz := clock_timestamp();
begin
    execute p_sql;
    return round(extract(epoch from clock_timestamp() - b) * 1000);
end $$;
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
--   HZ A: amiri hz_amir · HZ B: amiri hz_amir2, vekili hz_amir · HZ C: amiri hz_amir2
--   Kullanıcılar HZ İdari'de çalışan kayıtlarına bağlı.
insert into pdks.departman (ad) values ('HZ A'), ('HZ B'), ('HZ C'), ('HZ İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = d), '2025-01-01'
from (values ('HZ01', 'HZ A'), ('HZ02', 'HZ A'), ('HZ03', 'HZ B'), ('HZ04', 'HZ C'),
             ('HZM1', 'HZ İdari'), ('HZM2', 'HZ İdari'), ('HZI1', 'HZ İdari'), ('HZY1', 'HZ İdari'),
             ('HZS1', 'HZ İdari'), ('HZG1', 'HZ İdari'), ('HZD1', 'HZ İdari')) v(s, d);
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('HZ Amir 1',   'hz_amir@ornek.test',  'amir',     test.c('HZM1'), '00000000-0000-0000-0000-0000000010a1'),
    ('HZ Amir 2',   'hz_amir2@ornek.test', 'amir',     test.c('HZM2'), '00000000-0000-0000-0000-0000000010a2'),
    ('HZ İK',       'hz_ik@ornek.test',    'ik',       test.c('HZI1'), '00000000-0000-0000-0000-0000000010a3'),
    ('HZ Yönetici', 'hz_yon@ornek.test',   'yonetici', test.c('HZY1'), '00000000-0000-0000-0000-0000000010a4'),
    ('HZ İSG',      'hz_isg@ornek.test',   'isg',      test.c('HZS1'), '00000000-0000-0000-0000-0000000010a5'),
    ('HZ Güvenlik', 'hz_guv@ornek.test',   'guvenlik', test.c('HZG1'), '00000000-0000-0000-0000-0000000010a6'),
    ('HZ Admin',    'hz_admin@ornek.test', 'admin',    test.c('HZD1'), '00000000-0000-0000-0000-0000000010a7');
update pdks.departman set amir_id = test.k('hz_amir@ornek.test') where ad = 'HZ A';
update pdks.departman set amir_id = test.k('hz_amir2@ornek.test'), vekil_amir_id = test.k('hz_amir@ornek.test') where ad = 'HZ B';
update pdks.departman set amir_id = test.k('hz_amir2@ornek.test') where ad = 'HZ C';

insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id)
select test.c(s), '2026-10-14', 1 from unnest(array['HZ01', 'HZ02', 'HZ03', 'HZ04']) s;
insert into pdks.gun_kaydi (calisan_id, is_gunu, vardiya_id, durum)
select test.c(s), '2026-10-14', 1, 'eksik' from unnest(array['HZ01', 'HZ02', 'HZ03', 'HZ04']) s;
insert into pdks.amir_sorusu (gun_kaydi_id, soru_turu, aciklama, atanan_id, eskale_edilen_id, son_cevap_tarihi)
select g.id, 'giris_yok', 'Örnek soru', test.k(a), test.k(e), '2026-10-17'
from (values ('HZ01', 'hz_amir@ornek.test',  null),
             ('HZ03', 'hz_amir2@ornek.test', 'hz_amir@ornek.test'),
             ('HZ04', 'hz_amir2@ornek.test', null)) v(s, a, e)
join pdks.gun_kaydi g on g.calisan_id = test.c(v.s) and g.is_gunu = '2026-10-14';
insert into pdks.itiraz (calisan_id, gun_kaydi_id, metin)
select g.calisan_id, g.id, 'O gün işteydim'
from pdks.gun_kaydi g where g.calisan_id in (test.c('HZ01'), test.c('HZ04')) and g.is_gunu = '2026-10-14';

-- 1) Yapı: satır başına oturum denetimi yok ---------------------------------
select test.dogrula(t || ': okuma politikaları oturumu sorgu başına bir kez denetliyor',
    (select bool_and(regexp_count(qual, 'pdks\.(oturum_[a-z_]+|tum_veriyi_gorur|amirin_calisani_mi)\(') > 0
                 and regexp_count(qual, 'pdks\.(oturum_[a-z_]+|tum_veriyi_gorur|amirin_calisani_mi)\(')
                   = regexp_count(qual, 'SELECT pdks\.(oturum_[a-z_]+|tum_veriyi_gorur)\('))
     from pg_policies where schemaname = 'pdks' and tablename = t))
from unnest(test.tablolar()) t;

-- 1b) Yapı (T-108): yardımcı fonksiyonların içinde de satır başına oturum sorusu yok
select test.dogrula(f || ': oturumu kendi içinde de bir kez soruyor',
    (select regexp_count(prosrc, 'pdks\.(oturum_[a-z_]+|tum_veriyi_gorur)\(') > 0
            and regexp_count(prosrc, 'pdks\.(oturum_[a-z_]+|tum_veriyi_gorur)\(')
              = regexp_count(prosrc, '\(select pdks\.(oturum_[a-z_]+|tum_veriyi_gorur)\(')
     from pg_proc where pronamespace = 'pdks'::regnamespace and proname = f))
from unnest(array['oturum_rolu', 'oturum_calisan_id', 'oturum_departmanlari', 'oturum_calisanlari',
                  'amirin_calisani_mi']) f;

-- 2) Eşdeğerlik: her rol eskisiyle aynı satırları görüyor --------------------
set local role authenticated;
select test.oturum('hz_amir@ornek.test');
select test.dogrula('amir: kendi ve vekil olduğu departmanın gün kayıtlarını görüyor, başkasınınkini görmüyor',
    (select array_agg(c.sicil_no order by c.sicil_no) from pdks.gun_kaydi g join pdks.calisan c on c.id = g.calisan_id)
    = array['HZ01', 'HZ02', 'HZ03']);
select test.dogrula('amir: vardiya planlarını yalnızca kendi ve vekil olduğu departmandan görüyor',
    (select array_agg(c.sicil_no order by c.sicil_no) from pdks.vardiya_plani p join pdks.calisan c on c.id = p.calisan_id)
    = array['HZ01', 'HZ02', 'HZ03']);
select test.dogrula('amir: soruları yalnızca kendine atanan ya da eskale edilen',
    (select count(*) = 2 from pdks.amir_sorusu));
select test.dogrula('amir: itirazları yalnızca kendi departmanından',
    (select count(*) = 1 from pdks.itiraz));
select test.dogrula('amir: ham okutma ve kanıt kaydı görmüyor',
    (select count(*) = 0 from pdks.ham_okutma) and (select count(*) = 0 from pdks.kanit_kaydi));
do $$
declare o text; f text;
begin
    foreach o in array array['hz_amir@ornek.test', 'hz_amir2@ornek.test', 'hz_ik@ornek.test', 'hz_yon@ornek.test',
                             'hz_isg@ornek.test', 'hz_guv@ornek.test', 'hz_admin@ornek.test'] loop
        perform test.oturum(o);
        f := test.farklar();
        perform test.dogrula(o || ': 9 tabloda görünen satırlar eski kuralla aynı ' || f, f = '');
    end loop;
    -- Hesabı bir kullanıcıya bağlı olmayan oturum
    perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000010ff","role":"authenticated"}', true);
    f := test.farklar();
    perform test.dogrula('bağlı olmayan oturum: eski kuralla aynı, hiçbir çalışanı görmüyor ' || f,
                         f = '' and cardinality(test.gorunen('calisan')) = 0);
end $$;
reset role;

-- 3) Hız: Montaj amiri, Kasım (örnek veriyle) --------------------------------
do $$
declare
    v_amir   bigint := (select amir_id from pdks.departman where ad = 'Aktif Kısım ve Montaj');
    v_gun    date;
    r        record;
    v_ms     numeric;
begin
    if v_amir is null then
        raise notice 'ATLANDI  hız (örnek veri yüklü değil)';
        return;
    end if;
    if not exists (select 1 from pdks.gun_kaydi where is_gunu between '2026-11-01' and '2026-11-30') then
        for v_gun in select generate_series('2026-11-01'::date, '2026-11-30'::date, '1 day')::date loop
            perform pdks.gece_isi_calistir(v_gun);
        end loop;
    end if;
    update pdks.kullanici set auth_kullanici_id = '00000000-0000-0000-0000-0000000010b1' where id = v_amir;
    perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000010b1","role":"authenticated"}', true);
    set local role authenticated;

    perform test.dogrula('Montaj amiri (' || (select count(*) from pdks.gun_kaydi) || ' gün kaydı görüyor): 9 tabloda görünen satırlar eski kuralla aynı '
                         || test.farklar(), test.farklar() = '');

    -- T-108: listeyi hazırlayan yardımcı tek başına
    v_ms := test.sure('select pdks.oturum_calisanlari()');
    perform test.dogrula(format('Montaj amiri: "çalışanlarım" listesi (oturum_calisanlari) %s ms (< 30)', v_ms), v_ms < 30);

    for r in select * from (values
        ('departman özeti (Departmanlar)', 'select count(*) from pdks.v_departman_ozet where yil = 2026 and ay = 11'),
        ('esnek mesai özeti (Departmanlar)', 'select count(*) from pdks.v_esnek_mesai where yil = 2026 and ay = 11'),
        ('vardiya planları (Vardiya planı)', 'select count(*) from pdks.vardiya_plani'),
        ('kanıt kayıtları', 'select count(*) from pdks.kanit_kaydi'),
        ('ham okutmalar', 'select count(*) from pdks.ham_okutma')) v(ad, sorgu)
    loop
        v_ms := test.sure(r.sorgu);
        perform test.dogrula(format('Montaj amiri: %s %s ms (< 150)', r.ad, v_ms), v_ms < 150);
    end loop;
    reset role;
end $$;

select 'RLS hızı testi: hepsi GEÇTİ';
rollback;
