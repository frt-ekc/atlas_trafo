-- =====================================================================
-- Canlıda hangi migration'lar uygulanmış? (YALNIZCA OKUR; hiçbir şeyi değiştirmez)
-- Supabase > SQL Editor'da çalıştırılır.
--
--   kayitli : Supabase CLI kayıt tablosunda var mı (db push ile uygulandıysa evet)
--   nesne   : migration'ın oluşturduğu tablo / sütun / fonksiyon veritabanında var mı
--             (SQL Editor'dan elle çalıştırıldıysa kayitli = hayır ama nesne = evet olabilir)
--
-- BAKIM: supabase/migrations/ altına yeni bir dosya eklendiğinde aşağıdaki listeye de bir satır
-- eklenir. Eklenmezse yeni migration bu sorguda hiç görünmez.
-- =====================================================================
with beklenen(surum, ad, nesne) as (values
    ('20261114000100', 'tablolar',                       to_regclass('pdks.gun_kaydi') is not null),
    ('20261114000200', 'kurallar',                       exists (select 1 from pg_proc where pronamespace = 'pdks'::regnamespace and proname = 'duzeltme_uygula')),
    ('20261114000300', 'roller_ve_yetkiler',             null::boolean),   -- rolleri sonraki migration kaldırır; nesneyle anlaşılmaz
    ('20261114000400', 'varsayilan_ayarlar',             exists (select 1 from pdks.ayar where anahtar = 'yurume_payi_dk')),
    ('20261115000500', 'fazla_mesai',                    to_regclass('pdks.fazla_mesai_plani') is not null),
    ('20261117010000', 'kiosk_kaldir',                   not exists (select 1 from information_schema.columns where table_schema = 'pdks' and table_name = 'calisan' and column_name = 'pin_ozeti')),
    ('20261117020000', 'gecici_kart',                    to_regclass('pdks.gecici_kart') is not null),
    ('20261117030000', 'kart_paylasimi',                 exists (select 1 from pg_proc where pronamespace = 'pdks'::regnamespace and proname = 'kart_paylasim_kontrol')),
    ('20261118010000', 'sema_temizligi',                 null::boolean),   -- yalnızca açıklama düzenler
    ('20261118020000', 'gorevler_ayriligi',              exists (select 1 from information_schema.columns where table_schema = 'pdks' and table_name = 'kullanici' and column_name = 'calisan_id')),
    ('20261118030000', 'giris_ve_yetki',                 exists (select 1 from pg_proc where pronamespace = 'pdks'::regnamespace and proname = 'oturum_kullanici_id')),
    ('20261118040000', 'ayar_al_yetkisi',                exists (select 1 from pg_proc where pronamespace = 'pdks'::regnamespace and proname = 'ayar_al' and prosecdef)),
    ('20261119010000', 'ekran_fonksiyonlari',            exists (select 1 from pg_proc where pronamespace = 'pdks'::regnamespace and proname = 'yetki_gerekli')),
    ('20261120010000', 'gece_isi',                       exists (select 1 from pg_proc where pronamespace = 'pdks'::regnamespace and proname = 'gece_isi_calistir')),
    ('20261121010000', 'puantaj',                        exists (select 1 from pg_proc where pronamespace = 'pdks'::regnamespace and proname = 'puantaj_yaz')),
    ('20261122010000', 'izin_iptal_ve_departman_ozeti',  to_regclass('pdks.v_departman_ozet') is not null),
    ('20261123010000', 'puantaj_kurallari',              to_regclass('pdks.fazla_mesai_inceleme') is not null),
    ('20261124010000', 'vardiya_kurallari',              exists (select 1 from information_schema.columns where table_schema = 'pdks' and table_name = 'vardiya_tanim' and column_name = 'esnek')),
    ('20261125010000', 'organizasyon_ve_roller',         exists (select 1 from information_schema.columns where table_schema = 'pdks' and table_name = 'departman' and column_name = 'yaka')),
    ('20261126010000', 'isg',                            to_regclass('pdks.isg_belge') is not null),
    ('20261127010000', 'bolge_yetkisi_izi',              to_regclass('pdks.bolge_yetkisi_gecmisi') is not null),
    ('20261127020000', 'erp_aktarim',                    to_regclass('pdks.v_puantaj_aktarim') is not null),
    ('20261128010000', 'dosya_yukle_duzeltmesi',         exists (select 1 from pg_proc where pronamespace = 'pdks'::regnamespace and proname = 'dosya_yukle'
                                                                 and pg_get_function_identity_arguments(oid) like '%p_dosya_ozeti%')),
    ('20261129010000', 'esnek_kanit',                    exists (select 1 from pg_proc where pronamespace = 'pdks'::regnamespace and proname = 'gece_isi_kanitla_duzelt'
                                                                 and prosrc like '%v\_esnek%')),
    ('20261129020000', 'zimmet_cakisma_mesaji',          exists (select 1 from pg_proc where pronamespace = 'pdks'::regnamespace and proname = 'yonelme_eki')),
    ('20261130010000', 'ise_giris_cikis',                exists (select 1 from pg_proc where pronamespace = 'pdks'::regnamespace and proname = 'isten_cikis_gir')),
    ('20261201010000', 'ay_kilidi_ve_aninda_hesap',      exists (select 1 from pg_proc where pronamespace = 'pdks'::regnamespace and proname = 'gun_hesapla')),
    ('20261201020000', 'kilit_ozeti',                    exists (select 1 from pg_proc where pronamespace = 'pdks'::regnamespace and proname = 'ay_kilitle'
                                                                 and prorettype = 'jsonb'::regtype)),
    ('20261202010000', 'durum_duzeltmesi',               exists (select 1 from pg_proc where pronamespace = 'pdks'::regnamespace and proname = 'duzeltme_uygula'
                                                                 and prosrc like '%''vardiya_yok'') then%')),
    ('20261203010000', 'plan_onayi',                     exists (select 1 from pg_proc where pronamespace = 'pdks'::regnamespace and proname = 'gece_isi_gun_kayitlari'
                                                                 and prosrc like '%ik_onay_durumu%')),
    ('20261204010000', 'dosya_yukle_where',              exists (select 1 from pg_proc where pronamespace = 'pdks'::regnamespace and proname = 'dosya_yukle'
                                                                 and prosrc like '%where zaman_metni is not null%')),
    ('20261205010000', 'istanbul_tarihi',                exists (select 1 from pg_proc where pronamespace = 'pdks'::regnamespace and proname = 'bugun')),
    ('20261206010000', 'rls_hizi',                       exists (select 1 from pg_proc where pronamespace = 'pdks'::regnamespace and proname = 'oturum_calisanlari')),
    ('20261207010000', 'ay_kilidi_zamani',               exists (select 1 from pg_proc where pronamespace = 'pdks'::regnamespace and proname = 'ay_kilitle'
                                                                 and prosrc like '%henüz bitmedi%')),
    ('20261208010000', 'kullanici_cift_kayit',           exists (select 1 from pg_proc where pronamespace = 'pdks'::regnamespace and proname = 'kullanici_izinli_mi')),
    ('20261209010000', 'kodsuz_gun',                     exists (select 1 from pg_proc where pronamespace = 'pdks'::regnamespace and proname = 'ay_kilitle'
                                                                 and prosrc like '%kodsuz_gun_listesi%')),
    ('20261210010000', 'ikinci_eskale',                  exists (select 1 from information_schema.columns where table_schema = 'pdks'
                                                                 and table_name = 'amir_sorusu' and column_name = 'ik_eskale_zamani')),
    ('20261211010000', 'cikmis_hesap',                   exists (select 1 from pg_proc where pronamespace = 'pdks'::regnamespace and proname = 'kullanici_guncelle'
                                                                 and prosrc like '%hesabı yeniden açılamaz%')),
    ('20261212010000', 'ayar_sinirlari',                 exists (select 1 from information_schema.columns where table_schema = 'pdks'
                                                                 and table_name = 'ayar' and column_name = 'en_cok')),
    ('20261213010000', 'yukleyen',                       exists (select 1 from information_schema.columns where table_schema = 'pdks'
                                                                 and table_name = 'aktarim' and column_name = 'yukleyen_id')),
    ('20261214010000', 'rapor_gizliligi',                to_regclass('pdks.v_duzeltme_amir') is not null),
    ('20261215010000', 'ik_karar_gerekcesi',             exists (select 1 from information_schema.columns where table_schema = 'pdks'
                                                                 and table_name = 'amir_sorusu' and column_name = 'ik_karari')),
    ('20261216010000', 'ekran_metinleri',                exists (select 1 from information_schema.columns where table_schema = 'pdks'
                                                                 and table_name = 'ayar' and column_name = 'kategori')),
    ('20261217010000', 'oturum_yardimcilari',            exists (select 1 from pg_proc where pronamespace = 'pdks'::regnamespace and proname = 'oturum_calisanlari'
                                                                 and prosrc like '%(select pdks.oturum_departmanlari())%')),
    ('20261218010000', 'cakisan_izin',                   exists (select 1 from pg_proc where pronamespace = 'pdks'::regnamespace and proname = 'izin_gir'
                                                                 and prosrc like '%geçerli bir izni vardır%')),
    ('20261219010000', 'cikis_okutma',                   exists (select 1 from pg_proc where pronamespace = 'pdks'::regnamespace and proname = 'cikistan_sonraki_okutma')),
    ('20261220010000', 'havuz_yazili_onay',              exists (select 1 from information_schema.columns where table_schema = 'pdks'
                                                                 and table_name = 'fazla_mesai_inceleme' and column_name = 'yazili_onaysiz')),
    ('20261221010000', 'yillik_fazla_mesai',             exists (select 1 from pg_proc where pronamespace = 'pdks'::regnamespace and proname = 'fm_yillik_toplam')),
    ('20261222010000', 'arife',                          exists (select 1 from pg_proc where pronamespace = 'pdks'::regnamespace and proname = 'arife_siniri')),
    ('20261223010000', 'rol_onayi',                      to_regclass('pdks.rol_onerisi') is not null),
    ('20261224010000', 'plansiz_gun',                    exists (select 1 from pg_proc where pronamespace = 'pdks'::regnamespace and proname = 'gece_isi_plansiz')),
    ('20261225010000', 'gecmis_izin',                    exists (select 1 from information_schema.columns where table_schema = 'pdks'
                                                                 and table_name = 'amir_sorusu' and column_name = 'kapatan_izin_id')),
    ('20261226010000', 'gunluk_sinir',                   exists (select 1 from information_schema.columns where table_schema = 'pdks'
                                                                 and table_name = 'fazla_mesai_inceleme' and column_name = 'gunluk_sinir_asildi')),
    ('20261227010000', 'plan_onayi_hesap',               exists (select 1 from pg_proc where pronamespace = 'pdks'::regnamespace and proname = 'fazla_mesai_karar'
                                                                 and prosrc like '%gun_hesabini_yenile%')),
    ('20261228010000', 'gecmis_plan_talebi',             exists (select 1 from pg_proc where pronamespace = 'pdks'::regnamespace and proname = 'fazla_mesai_talep_et'
                                                                 and prosrc like '%Geçmiş bir güne fazla mesai planı girilemez%')),
    ('20261229010000', 'plan_gecmisi',                   to_regclass('pdks.vardiya_plani_gecmisi') is not null),
    ('20261230010000', 'saatlik_izin_iptal',             to_regprocedure('pdks.saatlik_izin_iptal(bigint, text)') is not null),
    ('20261231010000', 'plansiz_izin_gunu',              to_regprocedure('pdks.plansiz_izin_gunleri(date, date)') is not null),
    ('20261231020000', 'ik_karari_cevaplayan',           exists (select 1 from information_schema.columns where table_schema = 'pdks'
                                                                 and table_name = 'amir_sorusu' and column_name = 'ik_karar_veren_id')),
    ('20261231030000', 'eksik_saat_reddi',               to_regprocedure('pdks.cevap_saatleri_denetle(bigint, timestamptz, timestamptz, text)') is not null),
    -- T-102 calisilan_gun koşuluna bir şart ekledi; T-91 izi iki hâlde de aranır
    ('20261231040000', 'hesapsiz_gun',                   pg_get_viewdef('pdks.v_puantaj_canli'::regclass)
                                                         ~ 'hesap_tamam(\)\)| AND \(NOT pdks\.sayilmayan_tatil_calismasi\([^)]*\)\)\)\)) AS calisilan_gun'),
    ('20261231050000', 'zorla_kilit_izi',                to_regclass('pdks.donem_kilit_izi') is not null),
    ('20261231060000', 'kilitli_vardiya',                exists (select 1 from pg_trigger where tgname = 'duzeltme_kilitli_vardiya')),
    ('20261231070000', 'reddedilen_tatil',               pg_get_viewdef('pdks.v_departman_ozet'::regclass) like '%sayilmayan_tatil_calismasi%'),
    ('20261231080000', 'kilitte_fm_talebi',              pg_get_functiondef('pdks.ay_kilitle(smallint, smallint, boolean, text)'::regprocedure) like '%kapatilan_fm_talebi%'),
    ('20261231090000', 'kilitli_ay_cikis',               exists (select 1 from pg_trigger where tgname = 'vardiya_plani_kilitli_silme')),
    ('20261231100000', 'gecersiz_amir',                  exists (select 1 from pg_trigger where tgname = 'kullanici_amir_gecersiz')),
    ('20261231110000', 'kart_tanimlayan',                exists (select 1 from information_schema.columns where table_schema = 'pdks'
                                                                 and table_name = 'kart' and column_name = 'tanimlayan_id')),
    ('20261231120000', 'dosya_tarihi',                   pg_get_functiondef('pdks.dosya_yukle(text, text, date, jsonb, text)'::regprocedure) like '%ertesi gün değil%'),
    ('20261231130000', 'paylasim_karari',                to_regprocedure('pdks.kart_paylasim_karar(bigint, boolean, text)') is not null),
    ('20261231170000', 'fazla_mesai_kararlari',          exists (select 1 from pg_trigger where tgname = 'gun_kaydi_esik_alti'))
), kayit as (
    -- CLI hiç kullanılmadıysa kayıt tablosu yoktur; o zaman hepsi "hayır" görünür
    select (xpath('/row/v/text()', x))[1]::text as surum
    from query_to_xml(
        case when to_regclass('supabase_migrations.schema_migrations') is not null
             then 'select version as v from supabase_migrations.schema_migrations'
             else 'select null::text as v where false' end,
        false, false, '') as t(xml_doc),
         unnest(xpath('/table/row', xml_doc)) as x
)
select b.surum, b.ad,
       case when exists (select 1 from kayit k where k.surum = b.surum) then 'evet' else 'hayır' end as kayitli,
       case b.nesne when true then 'evet' when false then 'hayır' else '—' end as nesne
from beklenen b
order by b.surum;
