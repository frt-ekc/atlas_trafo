-- =====================================================================
-- Sık sorgulanan yabancı anahtarlara index (T-02)
--
--   72 tek sütunlu yabancı anahtarın sütunu hiçbir indexin başında değil. Çoğu "giren / yapan /
--   karar veren" türünden iz sütunudur, onlarla arama yapılmaz. Yalnızca çalışma sırasında arama
--   yapılan ve 1 yıllık hacimde (2000 çalışan: 1 M ham okutma, 2 M kanıt, 150 bin düzeltme) ölçülen
--   yollara index eklenir. Ölçüm (indexsiz → indexli, geçici kopyalarda):
--     dosya_yukle, aktarım satırları (ham + kanıt, aktarim_id) ...... 160 ms   → 0,5 ms (her dosyada)
--     Sorular ekranı (İK): 200 sorunun düzeltmeleri (soru_id) ....... 3160 ms  → 0,5 ms
--     PDF döküm: çalışanın bir aylık düzeltmeleri (calisan_id) ...... 10 ms    → 0,04 ms
--     Ay kilidi / İtirazlar: itirazın düzeltmesi var mı (itiraz_id) .. 16 ms    → 0,1 ms
--   Düzeltmelerin çoğunda soru / itiraz yoktur; o iki index yalnızca dolu satırları tutar (kısmi).
-- =====================================================================

create index ham_okutma_aktarim on pdks.ham_okutma (aktarim_id);
create index kanit_kaydi_aktarim on pdks.kanit_kaydi (aktarim_id);
create index duzeltme_soru on pdks.duzeltme (soru_id) where soru_id is not null;
create index duzeltme_itiraz on pdks.duzeltme (itiraz_id) where itiraz_id is not null;
create index duzeltme_calisan_gun on pdks.duzeltme (calisan_id, is_gunu);
