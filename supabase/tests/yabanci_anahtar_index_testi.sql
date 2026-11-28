-- =====================================================================
-- Sık sorgulanan yabancı anahtarlara index (20261231220000_yabanci_anahtar_index.sql, T-02)
--   Ölçülen yolların sorgusu (aynı süzme koşuluyla) index ile çalışabilmeli. Küçük örnek veride
--   planlayıcı tablo taramasını seçebilir; bu yüzden tarama kapatılıp planda index aranır.
-- Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/yabanci_anahtar_index_testi.sql
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
-- Sorgunun planında verilen index kullanılıyor mu? (tablo taraması kapalı)
create function test.index_kullanir(p_sorgu text, p_index text) returns boolean language plpgsql as $$
declare v_plan text := '';
        r      record;
begin
    set local enable_seqscan = off;
    for r in execute 'explain ' || p_sorgu loop
        v_plan := v_plan || r."QUERY PLAN" || E'\n';
    end loop;
    reset enable_seqscan;
    return position(p_index in v_plan) > 0;
end $$;

select test.dogrula('dosya_yukle: ham okutma aktarim_id ile index kullanır',
    test.index_kullanir('select kart_no, okutma_zamani from pdks.ham_okutma where aktarim_id = 1', 'ham_okutma_aktarim'));
select test.dogrula('dosya_yukle: kanıt kaydı aktarim_id ile index kullanır',
    test.index_kullanir('select kart_no, okutma_zamani from pdks.kanit_kaydi where aktarim_id = 1', 'kanit_kaydi_aktarim'));
select test.dogrula('Sorular ekranı: sorunun düzeltmeleri soru_id ile (kısmi) index kullanır',
    test.index_kullanir('select gerekce, kaynak from pdks.duzeltme where soru_id = 1', 'duzeltme_soru'));
select test.dogrula('İtirazlar / ay kilidi: itirazın düzeltmesi itiraz_id ile (kısmi) index kullanır',
    test.index_kullanir('select 1 from pdks.duzeltme where itiraz_id = 1', 'duzeltme_itiraz'));
select test.dogrula('İtirazlar ekranı: itiraza bağlı düzeltmeler (itiraz_id dolu) kısmi index kullanır',
    test.index_kullanir('select itiraz_id from pdks.duzeltme where itiraz_id is not null', 'duzeltme_itiraz'));
select test.dogrula('PDF döküm: çalışanın aylık düzeltmeleri index kullanır',
    test.index_kullanir($q$select * from pdks.duzeltme where calisan_id = 1 and is_gunu between '2026-10-01' and '2026-10-31'$q$,
                        'duzeltme_calisan_gun'));

\echo 'TÜM TESTLER GEÇTİ'
rollback;
