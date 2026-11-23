-- =====================================================================
-- K16 · T-104: Departmanlar sayfası amirde 8 saniyede zaman aşımına düşüyordu
--
-- Sebep: RLS politikaları oturum fonksiyonlarını (oturum_kullanici_id, oturum_rolu,
-- oturum_departmanlari, tum_veriyi_gorur, amirin_calisani_mi) SATIR BAŞINA
-- çalıştırıyordu. Her çağrı kendi içinde birkaç sorgu daha yapıyor; Kasım'ın
-- 1597 gün kaydında bu binlerce tekrar demek. Aynı sorgu RLS'siz 3–15 ms,
-- amirde 0,5–1,4 sn (yerel ölçüm; Fırat'ın ölçümünde 1,1–4,4 sn).
--
-- Düzeltme (Supabase'in önerdiği kalıp): fonksiyon "(select pdks.f())" içine
-- alınır. Satıra bağlı olmayan bu alt sorguyu PostgreSQL sorgu başına BİR KEZ
-- hesaplar (InitPlan) ve sonucu bütün satırlarda kullanır.
-- amirin_calisani_mi(calisan_id) satıra bağlı olduğu için bu kalıba girmez;
-- yerine "amirin çalışanlarının listesi" bir kez alınır: pdks.oturum_calisanlari().
--
-- Kapsam: 9 tablonun 20 okuma politikası.
--   * Departmanlar sayfasının okuduğu 6 tablo: gun_kaydi, calisan, amir_sorusu,
--     itiraz, departman, vardiya_tanim.
--   * Amir olarak bütün tablolar tek tek ölçülünce örnek veriyle bugün yavaş çıkan 3 tablo:
--     vardiya_plani 5,2 sn (Vardiya planı sayfası amirde 4,8 sn), kanit_kaydi 5,1 sn,
--     ham_okutma 2,8 sn. Kalan 26 tablo amirde 0,2 sn'nin altında.
-- Kalan 46 politika ayrı bir işte aynı kalıba çevrilecek.
-- Kim hangi satırı görür DEĞİŞMEZ; her politikanın anlamı eskisiyle aynıdır.
-- Kalıcı test: supabase/tests/rls_hizi_testi.sql (yapı, rol bazında eşdeğerlik, hız).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Amirin (ve vekil olduğu departmanların) çalışanları
--    amirin_calisani_mi(p) ile aynı kural: calisan.departman_id ∈ oturum_departmanlari()
-- ---------------------------------------------------------------------
create function pdks.oturum_calisanlari()
returns bigint[]
language sql
stable
security definer
set search_path = pdks
as $$
    select coalesce(array_agg(id), '{}')
    from pdks.calisan
    where departman_id = any (pdks.oturum_departmanlari());
$$;
comment on function pdks.oturum_calisanlari() is
    'Oturumdaki amirin (vekil olduğu departmanlar dahil) çalışanları. RLS politikalarında "(select pdks.oturum_calisanlari())" olarak sorgu başına bir kez çalışır.';
revoke execute on function pdks.oturum_calisanlari() from public, anon;
grant execute on function pdks.oturum_calisanlari() to authenticated;

-- ---------------------------------------------------------------------
-- 2. Politikalar: aynı kural, "(select ...)" kalıbı
--    Diziyle karşılaştırmada "::tip[]" gerekir; yoksa PostgreSQL
--    "= any ((select ...))" yazımını alt sorgu satırlarıyla karşılaştırma sanır.
-- ---------------------------------------------------------------------

-- gun_kaydi
alter policy ik_yonetici_okur on pdks.gun_kaydi
    using ((select pdks.tum_veriyi_gorur()));
alter policy amir_okur on pdks.gun_kaydi
    using (calisan_id = any ((select pdks.oturum_calisanlari())::bigint[]));

-- itiraz
alter policy ik_yonetici_okur on pdks.itiraz
    using ((select pdks.tum_veriyi_gorur()));
alter policy amir_okur on pdks.itiraz
    using (calisan_id = any ((select pdks.oturum_calisanlari())::bigint[]));

-- calisan
alter policy ik_yonetici_okur on pdks.calisan
    using ((select pdks.tum_veriyi_gorur()));
alter policy amir_okur on pdks.calisan
    using (departman_id = any ((select pdks.oturum_departmanlari())::smallint[]));
alter policy admin_okur on pdks.calisan
    using ((select pdks.oturum_rolu()) = 'admin');
alter policy isg_okur on pdks.calisan
    using ((select pdks.oturum_rolu()) = 'isg');
alter policy guvenlik_okur on pdks.calisan
    using ((select pdks.oturum_rolu()) = 'guvenlik');

-- amir_sorusu
alter policy ik_yonetici_okur on pdks.amir_sorusu
    using ((select pdks.tum_veriyi_gorur()));
alter policy amir_okur on pdks.amir_sorusu
    using ((select pdks.oturum_rolu()) = 'amir'
           and ((select pdks.oturum_kullanici_id()) = atanan_id
                or (select pdks.oturum_kullanici_id()) = eskale_edilen_id));

-- departman
alter policy ik_yonetici_okur on pdks.departman
    using ((select pdks.tum_veriyi_gorur()));
alter policy oturum_acan_okur on pdks.departman
    using ((select pdks.oturum_kullanici_id()) is not null);

-- vardiya_tanim
alter policy ik_yonetici_okur on pdks.vardiya_tanim
    using ((select pdks.tum_veriyi_gorur()));
alter policy oturum_acan_okur on pdks.vardiya_tanim
    using ((select pdks.oturum_kullanici_id()) is not null);

-- vardiya_plani (Vardiya planı sayfası)
alter policy ik_yonetici_okur on pdks.vardiya_plani
    using ((select pdks.tum_veriyi_gorur()));
alter policy amir_okur on pdks.vardiya_plani
    using (calisan_id = any ((select pdks.oturum_calisanlari())::bigint[]));

-- kanit_kaydi, ham_okutma: yalnızca İK ve yönetici okur. Amir hiçbir satır görmez,
-- ama eski kalıpta veritabanı bunu her satır için ayrı ayrı soruyordu.
alter policy ik_yonetici_okur on pdks.kanit_kaydi
    using ((select pdks.tum_veriyi_gorur()));
alter policy ik_yonetici_okur on pdks.ham_okutma
    using ((select pdks.tum_veriyi_gorur()));
