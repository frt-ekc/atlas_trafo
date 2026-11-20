-- =====================================================================
-- İşe giriş ve işten çıkış testleri (20261130010000_ise_giris_cikis.sql)
--   calisan_ekle · isten_cikis_gir · gece işinin tarihe göre süzmesi
-- Testin kendi sahte verisi (Ekim 2026) kullanılır; örnek veri yüklü olsun
-- olmasın çalışır. Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/ise_giris_cikis_testi.sql
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
-- Hata bekler; mesaj verilen kalıbı içermeli
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
create function test.d(p text) returns smallint language sql security definer as $$
    select id from pdks.departman where ad = p $$;
create function test.gk(p_sicil text, p_gun date) returns pdks.gun_kaydi language sql security definer as $$
    select * from pdks.gun_kaydi where calisan_id = test.c(p_sicil) and is_gunu = p_gun $$;
create function test.ts(p text) returns timestamptz language sql immutable as $$
    select (p::timestamp) at time zone 'Europe/Istanbul' $$;
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
--   IG01: çıkış GEÇ girilir (gece işi 7 Ekim'i işlemiş, soru açılmış)
--   IG02: çıkış gece işinden ÖNCE girilir (13 Ekim son gün); hesabı, izni, FM talebi var
--   IG03: açık geçici kart zimmeti var · IG05: çıkıştan sonra okutması var
--   IG06: ileri tarihli işe giriş (14 Ekim) · IGI1 / IGI2: İK · IG02 aynı zamanda amir
insert into pdks.departman (ad) values ('IG Üretim'), ('IG İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', test.d(d), t::date
from (values ('IG01', 'IG Üretim', '2025-01-01'), ('IG02', 'IG Üretim', '2025-01-01'),
             ('IG03', 'IG Üretim', '2025-01-01'), ('IG05', 'IG Üretim', '2025-01-01'),
             ('IG06', 'IG Üretim', '2026-10-14'),
             ('IGI1', 'IG İdari', '2025-01-01'), ('IGI2', 'IG İdari', '2025-01-01')) v(s, d, t);
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('IG İK 1', 'ig_ik1@ornek.test', 'ik',   test.c('IGI1'), '00000000-0000-0000-0000-0000000000f1'),
    ('IG İK 2', 'ig_ik2@ornek.test', 'ik',   test.c('IGI2'), '00000000-0000-0000-0000-0000000000f2'),
    ('IG Amir', 'ig_amir@ornek.test', 'amir', test.c('IG02'), '00000000-0000-0000-0000-0000000000f3');
update pdks.departman set amir_id = test.k('ig_amir@ornek.test') where ad = 'IG Üretim';
insert into pdks.kart (kart_no, calisan_id)
select 'IG-' || substr(s, 3), test.c(s) from unnest(array['IG01', 'IG02', 'IG03', 'IG05', 'IG06']) s;
insert into pdks.gecici_kart (kart_no) values ('IG-GK1');
insert into pdks.gecici_kart_zimmet (gecici_kart_id, calisan_id, verilis_zamani, veren_id)
values ((select id from pdks.gecici_kart where kart_no = 'IG-GK1'), test.c('IG03'), '2026-10-05 07:30+03', test.k('ig_ik1@ornek.test'));
insert into pdks.okuyucu (kod, ad, sistem) values ('IG-PDKS', 'IG PDKS', 'pdks');

insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id, giren_id)
select test.c(s), g::date, (select id from pdks.vardiya_tanim where kod = 'GUNDUZ_8'), test.k('ig_ik1@ornek.test')
from (values ('IG01', '2026-10-05'), ('IG01', '2026-10-06'), ('IG01', '2026-10-07'), ('IG01', '2026-10-08'),
             ('IG05', '2026-10-05'), ('IG05', '2026-10-06'),
             ('IG02', '2026-10-12'), ('IG02', '2026-10-13'), ('IG02', '2026-10-14'), ('IG02', '2026-10-15'),
             ('IG06', '2026-10-13'), ('IG06', '2026-10-14')) v(s, g);
insert into pdks.aktarim (kaynak, dosya_adi, dosya_ozeti, veri_tarihi)
select 'pdks', 'ig_' || g || '.csv', 'ig-pdks-' || g, g::date
from unnest(array['2026-10-05', '2026-10-06', '2026-10-07', '2026-10-12', '2026-10-13', '2026-10-14']) g;
insert into pdks.ham_okutma (aktarim_id, okuyucu_id, kart_no, okutma_zamani, yon)
select (select id from pdks.aktarim where dosya_ozeti = 'ig-pdks-' || (z::timestamp)::date),
       (select id from pdks.okuyucu where kod = 'IG-PDKS'), k, test.ts(z), y
from (values ('IG-01', '2026-10-05 07:55', 'giris'), ('IG-01', '2026-10-05 16:02', 'cikis'),
             ('IG-01', '2026-10-06 07:56', 'giris'), ('IG-01', '2026-10-06 16:01', 'cikis'),
             -- IG01 7 Ekim'de gelmedi (ayrılmıştı)
             ('IG-05', '2026-10-05 07:57', 'giris'), ('IG-05', '2026-10-05 16:03', 'cikis'),
             ('IG-05', '2026-10-06 07:58', 'giris'), ('IG-05', '2026-10-06 16:04', 'cikis'),
             ('IG-02', '2026-10-12 07:55', 'giris'), ('IG-02', '2026-10-12 16:01', 'cikis'),
             ('IG-02', '2026-10-13 07:54', 'giris'), ('IG-02', '2026-10-13 16:02', 'cikis'),
             ('IG-06', '2026-10-13 07:50', 'giris'), ('IG-06', '2026-10-13 16:00', 'cikis'),  -- işe girişten önce
             ('IG-06', '2026-10-14 07:52', 'giris'), ('IG-06', '2026-10-14 16:03', 'cikis')) v(k, z, y);

-- IG02: çıkıştan sonraya düşen izin, öncesinde kalan izin; FM talepleri (biri öncesi, biri sonrası)
insert into pdks.izin (calisan_id, tur, baslangic, bitis, giren_id)
values (test.c('IG02'), 'yillik', '2026-10-19', '2026-10-21', test.k('ig_ik1@ornek.test')),
       (test.c('IG02'), 'mazeret', '2026-10-09', '2026-10-09', test.k('ig_ik1@ornek.test'));
insert into pdks.fazla_mesai_onayi (calisan_id, yil, imza_tarihi, belge_no, giren_id)
values (test.c('IG02'), 2026, '2026-01-02', 'IG-FMO-1', test.k('ig_ik1@ornek.test'));
insert into pdks.fazla_mesai_plani (calisan_id, is_gunu, planli_dk, gerekce, talep_eden_id)
values (test.c('IG02'), '2026-10-12', 60, 'Sipariş yetişecek', test.k('ig_ik1@ornek.test')),
       (test.c('IG02'), '2026-10-15', 60, 'Sipariş yetişecek', test.k('ig_ik1@ornek.test'));

-- IG01 ve IG05 için gece işi çıkıştan önce çalışır (5–7 Ekim)
select pdks.gece_isi_calistir('2026-10-05');
select pdks.gece_isi_calistir('2026-10-06');
select pdks.gece_isi_calistir('2026-10-07');
select test.dogrula('hazırlık: IG01 7 Ekim gün kaydı açık soruyla bekliyor',
    (select durum = 'soru_bekliyor' from test.gk('IG01', '2026-10-07'))
    and exists (select 1 from pdks.amir_sorusu where gun_kaydi_id = (test.gk('IG01', '2026-10-07')).id and durum = 'acik'));

set local role authenticated;

-- =====================================================================
-- 1) Yetki
-- =====================================================================
select test.dogrula('anon iki fonksiyonu da çağıramaz',
    not has_function_privilege('anon', 'pdks.calisan_ekle(text, text, text, smallint, date)', 'execute')
    and not has_function_privilege('anon', 'pdks.isten_cikis_gir(bigint, date, text)', 'execute'));
select test.oturum('ig_amir@ornek.test');
select test.hata('amir çalışan ekleyemez', 'yetkiniz yok',
    $$select pdks.calisan_ekle('IG90', 'Yeni', 'Kişi', test.d('IG Üretim'), current_date)$$);
select test.hata('amir işten çıkış giremez', 'yetkiniz yok',
    $$select pdks.isten_cikis_gir(test.c('IG01'), '2026-10-06')$$);

-- =====================================================================
-- 2) calisan_ekle
-- =====================================================================
select test.oturum('ig_ik1@ornek.test');
select pdks.calisan_ekle(' IG10 ', ' Yeni ', ' Kişi ', test.d('IG Üretim'), current_date + 3) is not null;
select test.dogrula('İK yeni çalışan ekler; ileri tarihli işe giriş olabilir, boşluklar kırpılır',
    (select sicil_no = 'IG10' and ad = 'Yeni' and soyad = 'Kişi' and aktif and isten_cikis_tarihi is null
                and ise_giris_tarihi = current_date + 3
         from pdks.calisan where id = test.c('IG10')));
select test.hata('çalışan sicili tekrar kullanılamaz', 'başka bir çalışanda kayıtlı',
    $$select pdks.calisan_ekle('IGI2', 'Başka', 'Kişi', test.d('IG Üretim'), current_date)$$);
select test.hata('departman olmalı', 'Departman bulunamadı',
    $$select pdks.calisan_ekle('IG11', 'Yeni', 'Kişi', 32000::smallint, current_date)$$);
select test.hata('ad boş olamaz', 'boş olamaz',
    $$select pdks.calisan_ekle('IG11', '  ', 'Kişi', test.d('IG Üretim'), current_date)$$);
select test.hata('işe giriş tarihi gerekli', 'İşe giriş tarihi',
    $$select pdks.calisan_ekle('IG11', 'Yeni', 'Kişi', test.d('IG Üretim'), null)$$);

-- =====================================================================
-- 3) isten_cikis_gir: reddedilen durumlar
-- =====================================================================
select test.hata('İK kendi çıkışını giremez (görevler ayrılığı)', 'Görevler ayrılığı',
    $$select pdks.isten_cikis_gir(test.c('IGI1'), current_date)$$);
select test.hata('çıkış işe girişten önce olamaz', 'işe giriş tarihinden',
    $$select pdks.isten_cikis_gir(test.c('IG06'), '2026-10-13')$$);
select test.hata('ileri tarihli çıkış yok', 'ileri olamaz',
    $$select pdks.isten_cikis_gir(test.c('IG01'), current_date + 1)$$);
select test.hata('açık geçici kart zimmeti varsa çıkış girilmez; mesaj kartı söyler', 'IG-GK1',
    $$select pdks.isten_cikis_gir(test.c('IG03'), '2026-10-06')$$);
select test.hata('çıkıştan sonra okutması olan gün varsa çıkış tarihi yanlıştır', '06.10.2026',
    $$select pdks.isten_cikis_gir(test.c('IG05'), '2026-10-05')$$);

-- =====================================================================
-- 4) Çıkış geç girildi (IG01: son gün 6 Ekim, gece işi 7 Ekim'i işlemişti)
-- =====================================================================
select test.dogrula('IG01 çıkışı girildi; özet sayıları doğru',
    pdks.isten_cikis_gir(test.c('IG01'), '2026-10-06', 'İstifa')
    = '{"iptal_edilen_kart": 1, "vardiya_yok_yapilan_gun": 1, "silinen_plan": 2, "iptal_edilen_izin": 0,
        "iptal_edilen_fm_talebi": 0, "pasif_yapilan_hesap": 0}'::jsonb);
reset role;
select test.dogrula('IG01: çıkış tarihi yazıldı, kayıt pasif',
    (select isten_cikis_tarihi = '2026-10-06' and not aktif from pdks.calisan where id = test.c('IG01')));
select test.dogrula('IG01: kart "isten_cikis" nedeniyle iptal',
    (select durum = 'iptal' and iptal_nedeni = 'isten_cikis' and iptal_eden_id = test.k('ig_ik1@ornek.test')
     from pdks.kart where kart_no = 'IG-01'));
select test.dogrula('IG01: çıkıştan sonraki 7 Ekim günü "vardiya yok" oldu, düzeltme izi İK ve gerekçe "İşten çıkış"',
    (select durum = 'vardiya_yok' from test.gk('IG01', '2026-10-07'))
    and exists (select 1 from pdks.duzeltme d where d.gun_kaydi_id = (test.gk('IG01', '2026-10-07')).id
                and d.alan = 'durum' and d.yeni_deger = 'vardiya_yok' and d.kaynak = 'ik'
                and d.yapan_id = test.k('ig_ik1@ornek.test') and d.gerekce = 'İşten çıkış (06.10.2026): İstifa'));
select test.dogrula('IG01: 7 Ekim''in açık sorusu kapandı',
    (select durum = 'kapandi' and cevaplayan_id = test.k('ig_ik1@ornek.test') and cevap_aciklama like '%İşten çıkış%'
     from pdks.amir_sorusu where gun_kaydi_id = (test.gk('IG01', '2026-10-07')).id));
select test.dogrula('IG01: çıkıştan önceki günler (5–6 Ekim) olduğu gibi kaldı',
    (select count(*) = 2 from pdks.gun_kaydi where calisan_id = test.c('IG01')
     and is_gunu in ('2026-10-05', '2026-10-06') and durum = 'tamam'));
select test.dogrula('IG01: çıkıştan sonraki planlar (7–8 Ekim) silindi, öncekiler duruyor',
    (select array_agg(tarih order by tarih) = array['2026-10-05', '2026-10-06']::date[]
     from pdks.vardiya_plani where calisan_id = test.c('IG01')));

-- =====================================================================
-- 5) Çıkış gece işinden önce girildi (IG02: son gün 13 Ekim)
-- =====================================================================
set local role authenticated;
select test.oturum('ig_ik2@ornek.test');
select test.dogrula('IG02 çıkışı girildi; hesap pasif, izin ve FM talebi iptal',
    pdks.isten_cikis_gir(test.c('IG02'), '2026-10-13')
    = '{"iptal_edilen_kart": 1, "vardiya_yok_yapilan_gun": 0, "silinen_plan": 2, "iptal_edilen_izin": 1,
        "iptal_edilen_fm_talebi": 1, "pasif_yapilan_hesap": 1}'::jsonb);
select test.hata('çıkış iki kez girilmez', 'zaten girilmiş',
    $$select pdks.isten_cikis_gir(test.c('IG02'), '2026-10-13')$$);
select test.hata('işten ayrılmış çalışanın sicili yeniden kullanılamaz', 'işten ayrılmış bir çalışana ait',
    $$select pdks.calisan_ekle('IG02', 'Yeni', 'Kişi', test.d('IG Üretim'), current_date)$$);
select test.oturum('ig_amir@ornek.test');
select test.hata('pasif hesap artık işlem yapamaz', 'Oturum bulunamadı',
    $$select pdks.isten_cikis_gir(test.c('IG05'), '2026-10-06')$$);
reset role;

select test.dogrula('IG02: çıkıştan sonraya düşen izin (19–21 Ekim) "İşten çıkış" gerekçesiyle iptal',
    (select iptal_zamani is not null and iptal_eden_id = test.k('ig_ik2@ornek.test')
            and iptal_nedeni = 'İşten çıkış (13.10.2026)'
     from pdks.izin where calisan_id = test.c('IG02') and baslangic = '2026-10-19'));
select test.dogrula('IG02: çıkıştan önceki izin (9 Ekim) olduğu gibi kaldı',
    (select iptal_zamani is null from pdks.izin where calisan_id = test.c('IG02') and baslangic = '2026-10-09'));
select test.dogrula('IG02: çıkıştan sonraki FM talebi (15 Ekim) iptal, öncekisi (12 Ekim) bekliyor',
    (select durum = 'iptal' and karar_veren_id = test.k('ig_ik2@ornek.test') and karar_aciklama like 'İşten çıkış%'
     from pdks.fazla_mesai_plani where calisan_id = test.c('IG02') and is_gunu = '2026-10-15')
    and (select durum = 'talep' from pdks.fazla_mesai_plani where calisan_id = test.c('IG02') and is_gunu = '2026-10-12'));
select test.dogrula('IG02: bağlı kullanıcı hesabı pasif',
    (select not aktif from pdks.kullanici where eposta = 'ig_amir@ornek.test'));

-- Gece işi 12–14 Ekim'i çıkıştan SONRA işler
select pdks.gece_isi_calistir('2026-10-12');
select pdks.gece_isi_calistir('2026-10-13');
select pdks.gece_isi_calistir('2026-10-14');
select test.dogrula('IG02: çıkış günü (13 Ekim) kayıt pasif olsa da ertesi sabah işlendi',
    (select durum = 'tamam' and giris_zamani = test.ts('2026-10-13 07:54') from test.gk('IG02', '2026-10-13'))
    and (select durum = 'tamam' from test.gk('IG02', '2026-10-12')));
select test.dogrula('IG02: çıkıştan sonraki gün (14 Ekim) için gün kaydı yok',
    (test.gk('IG02', '2026-10-14')).id is null);
select test.dogrula('IG06: işe girişten önceki plan (13 Ekim) işlenmedi, giriş günü (14 Ekim) işlendi',
    (test.gk('IG06', '2026-10-13')).id is null
    and (select durum = 'tamam' from test.gk('IG06', '2026-10-14')));
select test.dogrula('IG03: reddedilen çıkış denemesi kaydı değiştirmedi',
    (select aktif and isten_cikis_tarihi is null from pdks.calisan where id = test.c('IG03'))
    and (select durum = 'aktif' from pdks.kart where kart_no = 'IG-03'));

do $$ begin raise notice 'İŞE GİRİŞ VE İŞTEN ÇIKIŞ TESTLERİ GEÇTİ'; end $$;
rollback;
