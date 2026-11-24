-- =====================================================================
-- T-108 (T-104'ün devamı): Oturum yardımcıları oturumu kendi içlerinde satır başına
-- soruyordu; amirin "çalışanlarım" listesi yarım saniye sürüyordu
--
-- T-104'te RLS politikaları "(select pdks.f())" kalıbına çevrildi: oturum sorgu
-- başına bir kez sorulur. Ama politikaların çağırdığı yardımcı fonksiyonların İÇİ
-- aynı kalıba çevrilmemişti:
--   * oturum_departmanlari: departman tablosunun HER satırı için oturum_rolu() ve
--     oturum_kullanici_id() yeniden hesaplanıyordu.
--   * oturum_calisanlari: çalışan tablosunun HER satırı için oturum_departmanlari()
--     yeniden hesaplanıyordu (tekrarın içinde tekrar).
--   * amirin_calisani_mi, oturum_rolu, oturum_calisan_id: aynı kalıbın küçük örnekleri.
-- T-71 oturum_kullanici_id'ye "çalışan aktif mi" şartını ekleyince her soru biraz
-- uzadı ve tekrar görünür oldu. Ölçüm (yerel, Montaj amiri, 5 ölçüm ortalaması):
--   oturum_departmanlari 3,5 ms · oturum_calisanlari 262,6 ms (79 çalışan × 3,5 ms)
--   · Vardiya planı okuması 286,5 ms (T-104'ten hemen sonra ~50 ms idi).
-- Süre çalışan sayısıyla doğru orantılı: 2000 çalışanda saniyeler sürer ve T-104'teki
-- zaman aşımı geri gelir. T-12 ve T-106'nın yeni politikaları da oturum_calisanlari'ni
-- kullanıyor.
--
-- Değişiklik: beş yardımcının içinde oturum fonksiyonları "(select pdks.f())" ile
-- çağrılır; PostgreSQL bunu sorgu başına bir kez hesaplar (InitPlan).
-- Kim neyi görür DEĞİŞMEZ: her fonksiyonun sonucu eskisiyle aynıdır (rls_hizi_testi
-- 8 oturumda 9 tabloyu eski politika ifadesiyle karşılaştırır). Fonksiyonların imzası,
-- özellikleri (STABLE, SECURITY DEFINER, search_path) ve yetkileri aynı kalır.
-- Kalıcı test: supabase/tests/rls_hizi_testi.sql (yapı 1b, hız sınırları 30 / 150 ms)
-- =====================================================================

CREATE OR REPLACE FUNCTION pdks.oturum_rolu()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pdks'
AS $function$
    select rol from pdks.kullanici where id = (select pdks.oturum_kullanici_id());
$function$;

CREATE OR REPLACE FUNCTION pdks.oturum_calisan_id()
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pdks'
AS $function$
    select calisan_id from pdks.kullanici where id = (select pdks.oturum_kullanici_id());
$function$;

-- Oturumdaki amirin (vekil olduğu departmanlar dahil) departmanları
CREATE OR REPLACE FUNCTION pdks.oturum_departmanlari()
 RETURNS smallint[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pdks'
AS $function$
    select coalesce(array_agg(id), '{}')
    from pdks.departman
    where (select pdks.oturum_rolu()) = 'amir'
      and (select pdks.oturum_kullanici_id()) in (amir_id, vekil_amir_id);
$function$;

-- Oturumdaki amirin çalışanları (T-104)
CREATE OR REPLACE FUNCTION pdks.oturum_calisanlari()
 RETURNS bigint[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pdks'
AS $function$
    select coalesce(array_agg(id), '{}')
    from pdks.calisan
    where departman_id = any ((select pdks.oturum_departmanlari())::smallint[]);
$function$;

CREATE OR REPLACE FUNCTION pdks.amirin_calisani_mi(p_calisan_id bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pdks'
AS $function$
    select exists (
        select 1 from pdks.calisan
        where id = p_calisan_id
          and departman_id = any ((select pdks.oturum_departmanlari())::smallint[])
    );
$function$;
