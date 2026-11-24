-- =====================================================================
-- K9 · T-12 (seçenek a): Rapor gerekçesi (sağlık bilgisi, KVKK m.6) amire açıktı
--
-- Amir, duzeltme tablosunu doğrudan okuyordu: İK bir günü "raporlu" yapınca yeni değer ve
-- serbest metin gerekçe (tanı yazıldıysa tanı) amire görünüyordu.
--
-- Değişiklik:
--   * duzeltme.amir_okur politikası kaldırılır; tabloyu yalnızca İK ve yönetici okur.
--   * v_duzeltme_amir: amir yalnızca kendi çalışanlarının düzeltmelerini görür.
--       - durum düzeltmesinde ya da izne dayanan düzeltmede gerekçe "İK tarafından düzeltildi",
--       - durum düzeltmesinin eski / yeni değerinde "raporlu" → "izinli",
--       - izin_id, itiraz_id gibi bağlar görünümde yoktur (izin bağı da bilgi verir).
--     Görünüm security_invoker DEĞİLDİR (amir tabloyu okuyamaz); kimin neyi göreceği içindeki
--     koşuldur. security_barrier: kullanıcı süzgeci bu koşuldan önce çalışmaz.
--
-- Bilinçli sınırlılık (karar verildi): gun_kaydi.durum ve v_puantaj_canli.raporlu_gun amire
-- API'den açıktır, ekranda "İzinli" görünür (docs/veritabani.md, Bilinçli tercihler).
-- Kalıcı test: supabase/tests/rapor_gizliligi_testi.sql
-- =====================================================================

drop policy amir_okur on pdks.duzeltme;

create view pdks.v_duzeltme_amir
with (security_barrier = true) as
select d.id,
       d.gun_kaydi_id,
       d.calisan_id,
       d.is_gunu,
       d.alan,
       case when d.alan = 'durum' and d.eski_deger = 'raporlu' then 'izinli' else d.eski_deger end as eski_deger,
       case when d.alan = 'durum' and d.yeni_deger = 'raporlu' then 'izinli' else d.yeni_deger end as yeni_deger,
       case when d.alan = 'durum' or d.izin_id is not null then 'İK tarafından düzeltildi' else d.gerekce end as gerekce,
       d.kaynak,
       d.yapan_id,
       d.calisan_aleyhine,
       d.yapilma_zamani
from pdks.duzeltme d
-- (select …): oturum sorgu başına bir kez denetlenir (T-104); oturum_calisanlari, amirin çalışanlarıdır
where (select pdks.tum_veriyi_gorur())
   or d.calisan_id = any ((select pdks.oturum_calisanlari())::bigint[]);

comment on view pdks.v_duzeltme_amir is
    'Amirin düzeltme listesi: kendi çalışanları; durum ve izin düzeltmelerinde gerekçe gizli, "raporlu" yerine "izinli" (T-12).';

revoke all on pdks.v_duzeltme_amir from public, anon, authenticated;
grant select on pdks.v_duzeltme_amir to authenticated;
