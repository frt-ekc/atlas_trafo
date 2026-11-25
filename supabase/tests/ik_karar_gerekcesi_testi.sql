-- =====================================================================
-- İK karar gerekçesi amire gizli (20261215010000_ik_karar_gerekcesi.sql, T-106)
--   * Amir (ve üst amir) soruda kararın sonucunu görür, gerekçeyi hiçbir yoldan okuyamaz:
--     soru, düzeltme görünümü, gün kaydı ve okuyabildiği bütün tablo / görünümler taranır.
--   * Amirin kendi açıklaması ve kendi cevabından gelen düzeltme görünür kalır.
--   * İK ve yönetici gerekçeyi duzeltme satırında görür.
--
-- 1. bölüm migration'dan önceki kodda KALIR.
-- Testin kendi sahte verisi kullanılır; örnek veri yüklü olsun olmasın çalışır.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/ik_karar_gerekcesi_testi.sql
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
create function test.c(p text) returns bigint language sql security definer as $$
    select id from pdks.calisan where sicil_no = p $$;
create function test.k(p text) returns bigint language sql security definer as $$
    select id from pdks.kullanici where eposta = p $$;
create function test.g(p text) returns bigint language sql security definer as $$
    select id from pdks.gun_kaydi where calisan_id = test.c(p) and is_gunu = '2026-08-05' $$;
create function test.s(p text) returns bigint language sql security definer as $$
    select id from pdks.amir_sorusu where gun_kaydi_id = test.g(p) $$;
create function test.oturum(p_eposta text) returns void language sql security definer as $$
    select set_config('request.jwt.claims',
        json_build_object('sub', (select auth_kullanici_id from pdks.kullanici where eposta = p_eposta),
                          'role', 'authenticated')::text, true) $$;
-- Oturumun okuyabildiği bütün pdks tablo ve görünümlerinde metni arar (çağıranın yetkisiyle)
create function test.gecen_yerler(p_metin text) returns text language plpgsql as $$
declare
    r record;
    v_var boolean;
    v_liste text[] := '{}';
begin
    for r in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
             where n.nspname = 'pdks' and c.relkind in ('r', 'v') and has_table_privilege(c.oid, 'select') order by 1 loop
        execute format('select exists (select 1 from pdks.%I t where to_jsonb(t)::text like %L)', r.relname, '%' || p_metin || '%') into v_var;
        if v_var then v_liste := v_liste || r.relname::text; end if;
    end loop;
    return array_to_string(v_liste, ', ');
end $$;
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
--   KG Üretim: amiri KGA1, üst amiri KGU1. KG01 devamsız, KG02 geldi (saat yazılır),
--   KG03 üst amire eskale + geldi, KG04 amirin kendi cevabı (saat farklı)
insert into pdks.departman (ad) values ('KG Üretim'), ('KG İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = d), '2025-01-01'
from (values ('KGA1', 'KG Üretim'), ('KG01', 'KG Üretim'), ('KG02', 'KG Üretim'), ('KG03', 'KG Üretim'), ('KG04', 'KG Üretim'),
             ('KGU1', 'KG İdari'), ('KGI1', 'KG İdari'), ('KGY1', 'KG İdari')) v(s, d);
insert into pdks.kullanici (eposta, rol, calisan_id, auth_kullanici_id)
select e, r, test.c(s), u::uuid
from (values ('kg_ust@ornek.test', 'amir',     'KGU1', '00000000-0000-0000-0000-0000000106b1'),
             ('kg_ik@ornek.test',  'ik',       'KGI1', '00000000-0000-0000-0000-0000000106b2'),
             ('kg_yon@ornek.test', 'yonetici', 'KGY1', '00000000-0000-0000-0000-0000000106b3')) v(e, r, s, u);
insert into pdks.kullanici (eposta, rol, calisan_id, auth_kullanici_id, ust_amir_id)
values ('kg_amir@ornek.test', 'amir', test.c('KGA1'), '00000000-0000-0000-0000-0000000106b4', test.k('kg_ust@ornek.test'));
update pdks.departman set amir_id = test.k('kg_amir@ornek.test') where ad = 'KG Üretim';
insert into pdks.gun_kaydi (calisan_id, is_gunu, vardiya_id, planli_baslangic, planli_bitis, durum)
select test.c(s), '2026-08-05', (select id from pdks.vardiya_tanim where kod = 'GUNDUZ_8'),
       '2026-08-05 08:00+03', '2026-08-05 16:00+03', 'soru_bekliyor'
from unnest(array['KG01', 'KG02', 'KG03', 'KG04']) s;
insert into pdks.amir_sorusu (gun_kaydi_id, soru_turu, aciklama, atanan_id, son_cevap_tarihi)
select test.g(s), 'hic_kayit_yok', 'Hiç okutma yok', test.k('kg_amir@ornek.test'), '2026-08-08'
from unnest(array['KG01', 'KG02', 'KG03', 'KG04']) s;
update pdks.amir_sorusu set durum = 'eskale', eskale_zamani = now(), eskale_edilen_id = test.k('kg_ust@ornek.test') where id = test.s('KG03');

set local role authenticated;
select test.oturum('kg_amir@ornek.test');
select pdks.soru_cevapla(test.s('KG01'), 'gelmedi', p_aciklama => 'AMIRNOTU sabah görmedim') \g /dev/null
select pdks.soru_cevapla(test.s('KG02'), 'bilmiyorum') \g /dev/null
select pdks.soru_cevapla(test.s('KG04'), 'geldi_saat_farkli', '2026-08-05 08:10+03', '2026-08-05 16:00+03', 'AMIRNOTU kart okumadı') \g /dev/null
select test.oturum('kg_ik@ornek.test');
select pdks.soru_ik_karari(test.s('KG01'), true, 'GIZLIKARAR hastane evrakı geçersiz') \g /dev/null
select pdks.soru_ik_karari(test.s('KG02'), false, 'GIZLIKARAR psikiyatri randevusundan döndü', '2026-08-05 09:30+03', '2026-08-05 16:00+03') \g /dev/null
select pdks.soru_ik_karari(test.s('KG03'), false, 'GIZLIKARAR ilaç raporu', '2026-08-05 08:00+03', '2026-08-05 15:00+03') \g /dev/null

-- 1) Gerekçe amire hiçbir yoldan açık değil (eski kodda KALIR) ------------------
select test.oturum('kg_amir@ornek.test');
select test.dogrula('amir: İK gerekçesi soruda yok',
    (select count(*) = 3 and bool_and(coalesce(cevap_aciklama, '') not like '%GIZLIKARAR%')
     from pdks.amir_sorusu where id in (test.s('KG01'), test.s('KG02'), test.s('KG03'))));
select test.dogrula('amir: İK gerekçesi düzeltme görünümünde yok (devamsız ve saat yazılan kararlar)',
    (select count(*) >= 5 and bool_and(gerekce = 'İK tarafından düzeltildi')
     from pdks.v_duzeltme_amir where calisan_id in (test.c('KG01'), test.c('KG02'), test.c('KG03'))));
select test.dogrula('amir: İK gerekçesi gün kaydında yok',
    (select count(*) = 4 and bool_and(to_jsonb(g)::text not like '%GIZLIKARAR%') from pdks.gun_kaydi g where id in
     (test.g('KG01'), test.g('KG02'), test.g('KG03'), test.g('KG04'))));
select test.dogrula('amir: okuyabildiği hiçbir tablo ya da görünümde geçmiyor (bulunan: ' || test.gecen_yerler('GIZLIKARAR') || ')',
    test.gecen_yerler('GIZLIKARAR') = '');
select test.oturum('kg_ust@ornek.test');
select test.dogrula('üst amir: eskale edilen soruyu görür, gerekçe hiçbir yerde geçmiyor',
    (select ik_karari = 'geldi' from pdks.amir_sorusu where id = test.s('KG03')) and test.gecen_yerler('GIZLIKARAR') = '');

-- 2) Amir sonucu ve kendi yazdığını görür ---------------------------------------
select test.oturum('kg_amir@ornek.test');
select test.dogrula('amir kararın sonucunu görür: devamsız / geldi',
    (select array_agg(ik_karari || ':' || durum order by id) from pdks.amir_sorusu where id in (test.s('KG01'), test.s('KG02'), test.s('KG03')))
        = array['devamsiz:kapandi', 'geldi:kapandi', 'geldi:kapandi']);
select test.dogrula('amirin kendi açıklaması ve cevabı değişmedi',
    (select cevap = 'gelmedi' and cevap_aciklama = 'AMIRNOTU sabah görmedim' from pdks.amir_sorusu where id = test.s('KG01'))
    and (select cevap = 'bilmiyorum' and cevap_aciklama is null from pdks.amir_sorusu where id = test.s('KG02')));
select test.dogrula('amirin kendi cevabından gelen düzeltmenin gerekçesi görünür, İK kararı boş',
    (select count(*) = 2 and bool_and(gerekce like '%AMIRNOTU kart okumadı%') from pdks.v_duzeltme_amir where calisan_id = test.c('KG04'))
    and (select ik_karari is null and durum = 'cevaplandi' from pdks.amir_sorusu where id = test.s('KG04')));
select test.dogrula('karar edilen saatler amire görünür',
    (select giris_zamani = '2026-08-05 09:30+03' from pdks.gun_kaydi where id = test.g('KG02')));

-- 3) İK ve yönetici gerekçeyi görür -----------------------------------------------
select test.oturum('kg_ik@ornek.test');
select test.dogrula('İK gerekçeyi sorunun düzeltmesinde görür',
    (select count(distinct soru_id) = 3 and bool_and(gerekce like 'GIZLIKARAR%')
     from pdks.duzeltme where soru_id in (test.s('KG01'), test.s('KG02'), test.s('KG03'))));
select test.dogrula('devamsızlık çalışan aleyhine işaretli kaldı',
    (select calisan_aleyhine and yapan_id = test.k('kg_ik@ornek.test') from pdks.duzeltme where soru_id = test.s('KG01')));
select test.oturum('kg_yon@ornek.test');
select test.dogrula('yönetici gerekçeyi görür', test.gecen_yerler('GIZLIKARAR') = 'duzeltme');
reset role;

select test.dogrula('yetki ve görünüm ayarları korundu',
    has_function_privilege('authenticated', 'pdks.soru_ik_karari(bigint, boolean, text, timestamptz, timestamptz)', 'execute')
    and not has_function_privilege('anon', 'pdks.soru_ik_karari(bigint, boolean, text, timestamptz, timestamptz)', 'execute')
    and not has_table_privilege('anon', 'pdks.v_duzeltme_amir', 'select')
    and (select 'security_barrier=true' = any (reloptions) from pg_class where oid = 'pdks.v_duzeltme_amir'::regclass));

do $$ begin raise notice 'İK KARAR GEREKÇESİ TESTLERİ GEÇTİ'; end $$;
rollback;
