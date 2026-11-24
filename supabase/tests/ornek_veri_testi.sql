-- =====================================================================
-- Örnek veri testleri. supabase/seed.sql yüklendikten sonra çalıştırılır.
-- Verinin beklenen büyüklükte olduğunu ve her senaryonun yerinde durduğunu
-- doğrular. Her şey sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/ornek_veri_testi.sql
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
create function test.c(p text) returns bigint language sql as $$ select id from pdks.calisan where sicil_no = p $$;
-- Bir çalışanın bir günde (yerel saat) belirli sistemdeki okutmaları
create function test.okutma(p_sicil text, p_gun date, p_sistem text, p_yon text)
returns setof timestamptz language sql as $$
    select o.okutma_zamani
    from (select kart_no, okutma_zamani, yon, 'pdks' as sistem from pdks.ham_okutma
          union all select kart_no, okutma_zamani, yon, kaynak from pdks.kanit_kaydi) o
    where o.sistem = p_sistem and o.yon is not distinct from p_yon
      and (o.okutma_zamani at time zone 'Europe/Istanbul')::date = p_gun
      and (pdks.okutma_sahibi(o.kart_no, o.okutma_zamani) = test.c(p_sicil)
           or o.kart_no in (select kart_no from pdks.kart where calisan_id = test.c(p_sicil)))
$$;

do $$ begin
    if not exists (select 1 from pdks.calisan where sicil_no = '1001') then
        raise exception 'KALDI  Örnek veri yüklü değil; önce supabase/seed.sql çalıştırılmalı.';
    end if;
end $$;

-- Büyüklük ve bütünlük --------------------------------------------------------
select test.dogrula('76 çalışan, 19 departman (9 mavi, 10 beyaz yaka)',
    (select count(*) from pdks.calisan) = 76 and (select count(*) from pdks.departman) = 19
    and (select count(*) from pdks.departman where yaka = 'mavi') = 9);
select test.dogrula('25 kullanıcı: 2 İK, 19 amir, 1 güvenlik, 1 yönetici, 1 İSG, 1 admin',
    (select count(*) from pdks.kullanici) = 25
    and (select count(*) from pdks.kullanici where rol = 'ik') = 2
    and (select count(*) from pdks.kullanici where rol = 'amir') = 19
    and (select count(*) from pdks.kullanici where rol = 'isg') = 1
    and (select count(*) from pdks.kullanici where rol = 'admin') = 1);
select test.dogrula('her kullanıcı bir çalışana bağlı', not exists (select 1 from pdks.kullanici where calisan_id is null));
select test.dogrula('kullanıcı e-postaları yalnızca örnek alan adında (atlastrafo.example.com)',
    not exists (select 1 from pdks.kullanici where eposta not like '%@atlastrafo.example.com'));
select test.dogrula('her departmanın amiri var', not exists (select 1 from pdks.departman where amir_id is null));
select test.dogrula('her çalışanın tam olarak bir aktif kartı var',
    not exists (select 1 from pdks.calisan c
                where (select count(*) from pdks.kart k where k.calisan_id = c.id and k.durum = 'aktif') <> 1));
select test.dogrula('Kasım hafta içi her gün herkesin vardiya planı var (76 kişi x 21 gün + 2 Pazar: S29, S30)',
    (select count(*) from pdks.vardiya_plani where tarih between '2026-11-01' and '2026-11-30') = 76 * 21 + 2);
select test.dogrula('ileri tarihli geçici kart zimmeti yok (en geç 19 Kasım)',
    not exists (select 1 from pdks.gecici_kart_zimmet where verilis_zamani >= '2026-11-20 00:00+03'));
select test.dogrula('her kaynaktan her gün bir dosya (27 Kasım servis hariç) + 1 Aralık PDKS ve kapı',
    (select count(*) from pdks.aktarim) = 4 * 30 - 1 + 2
    and (select array_agg(kaynak order by kaynak) from pdks.aktarim where veri_tarihi = '2026-12-01') = array['kapi', 'pdks']);
select test.dogrula('1 Aralık dosyalarında yalnızca 30 Kasım gece vardiyalarının sabah okutmaları var (06:30''a kadar)',
    (select max(okutma_zamani) from pdks.ham_okutma where okutma_zamani >= '2026-12-01 00:00+03') < '2026-12-01 06:30+03'
    and (select count(*) from pdks.ham_okutma where okutma_zamani >= '2026-12-01 00:00+03') = 5);
select test.dogrula('7 Aralık (demo günü) yalnızca Montaj''ın 10 kişisi planlı; o gün için okutma yok',
    (select count(*) from pdks.vardiya_plani p join pdks.calisan c on c.id = p.calisan_id
     where p.tarih = '2026-12-07' and c.sicil_no between '1001' and '1010') = 10
    and (select count(*) from pdks.vardiya_plani where tarih > '2026-12-01') = 10
    and not exists (select 1 from pdks.ham_okutma where okutma_zamani >= '2026-12-02 00:00+03')
    and not exists (select 1 from pdks.aktarim where veri_tarihi > '2026-12-01'));
select test.dogrula('yüzlerce PDKS ve kanıt okutması var',
    (select count(*) from pdks.ham_okutma) > 1000 and (select count(*) from pdks.kanit_kaydi) > 2000);
select test.dogrula('Bobinaj grupları haftalık dönüyor (Kemal: V1, V2, V3)',
    (select count(distinct vardiya_id) from pdks.vardiya_plani where calisan_id = test.c('2002')) = 3);
select test.dogrula('resmi tatiller girili (2026)', (select count(*) from pdks.resmi_tatil where extract(year from tarih) = 2026) >= 17);

-- Senaryolar -------------------------------------------------------------------
select test.dogrula('S1  Mehmet 3 Kasım: PDKS girişi yok, kapı girişi 08:00 öncesi',
    not exists (select test.okutma('1002', '2026-11-03', 'pdks', 'giris'))
    and (select min(z) from test.okutma('1002', '2026-11-03', 'kapi', 'giris') z) < '2026-11-03 08:00+03');
select test.dogrula('S2  Ali 4 Kasım: PDKS girişi yok, kapı girişi 08:25',
    not exists (select test.okutma('1003', '2026-11-04', 'pdks', 'giris'))
    and (select min(z) from test.okutma('1003', '2026-11-04', 'kapi', 'giris') z) = '2026-11-04 08:25+03');
select test.dogrula('S3  Veli 5 Kasım: PDKS çıkışı yok, kapı çıkışı 17:12',
    not exists (select test.okutma('1004', '2026-11-05', 'pdks', 'cikis'))
    and (select max(z) from test.okutma('1004', '2026-11-05', 'kapi', 'cikis') z) = '2026-11-05 17:12+03');
select test.dogrula('S4  Mustafa 5 Kasım: çıkışa dair hiçbir okutma yok',
    not exists (select test.okutma('1005', '2026-11-05', s, 'cikis') from unnest(array['pdks', 'kapi', 'servis']) s));
select test.dogrula('S5  Hüseyin 6 Kasım: iki PDKS girişi 40 sn arayla',
    (select count(*) from test.okutma('1006', '2026-11-06', 'pdks', 'giris')) = 2);
select test.dogrula('S6  İbrahim 10 Kasım: geçici kart GK-01 zimmetli ve okutulmuş',
    exists (select 1 from pdks.gecici_kart_zimmet z join pdks.gecici_kart g on g.id = z.gecici_kart_id
            where g.kart_no = 'GK-01' and z.calisan_id = test.c('1007')
              and (z.verilis_zamani at time zone 'Europe/Istanbul')::date = '2026-11-10')
    and exists (select 1 from pdks.ham_okutma where kart_no = 'GK-01'
                and pdks.okutma_sahibi(kart_no, okutma_zamani) = test.c('1007')));
select test.dogrula('S7  Osman Kasım''da 3 kez geçici kart aldı (11, 17, 19 Kasım), hepsi iade edildi',
    (select array_agg((verilis_zamani at time zone 'Europe/Istanbul')::date order by verilis_zamani)
     from pdks.gecici_kart_zimmet where calisan_id = test.c('1008'))
        = array['2026-11-11', '2026-11-17', '2026-11-19']::date[]
    and not exists (select 1 from pdks.gecici_kart_zimmet where calisan_id = test.c('1008') and iade_zamani is null));
select test.dogrula('S8  Emre''nin eski kartı kayıp diye iptal, yeni kartı aktif, eski kart 16 Kasım''da okutuldu',
    (select durum = 'iptal' and iptal_nedeni = 'kayip' from pdks.kart where kart_no = 'K1009')
    and (select durum = 'aktif' from pdks.kart where kart_no = 'K1009B')
    and exists (select 1 from pdks.ham_okutma where kart_no = 'K1009'
                and (okutma_zamani at time zone 'Europe/Istanbul')::date = '2026-11-16'));
select test.dogrula('S9  Burak''ın GK-02 zimmeti iade edilmedi',
    exists (select 1 from pdks.gecici_kart_zimmet z join pdks.gecici_kart g on g.id = z.gecici_kart_id
            where g.kart_no = 'GK-02' and z.calisan_id = test.c('1010') and z.iade_zamani is null));
select test.dogrula('S10 19 Kasım 05:30-09:30 atölye PDKS''inde okutma yok, kapıda var',
    not exists (select 1 from pdks.ham_okutma h join pdks.okuyucu r on r.id = h.okuyucu_id
                where r.kod = 'PDKS-2' and h.okutma_zamani >= '2026-11-19 05:30+03' and h.okutma_zamani < '2026-11-19 09:30+03')
    and exists (select 1 from pdks.kanit_kaydi
                where kaynak = 'kapi' and okutma_zamani >= '2026-11-19 05:30+03' and okutma_zamani < '2026-11-19 09:30+03'));
select test.dogrula('S12 gece vardiyası gece yarısını aşıyor (Cem 16 Kasım girişi, 17 Kasım çıkışı)',
    exists (select test.okutma('2004', '2026-11-16', 'pdks', 'giris'))
    and exists (select test.okutma('2004', '2026-11-17', 'pdks', 'cikis')));
select test.dogrula('S13 Okan''ın 13 Kasım planı geriye dönük ve İK onayı bekliyor',
    (select geriye_donuk and ik_onay_durumu = 'bekliyor' from pdks.vardiya_plani
     where calisan_id = test.c('2005') and tarih = '2026-11-13'));
select test.dogrula('S14 Selin 9 Kasım 08:35''te girdi, 13 Kasım 16:20''de çıktı',
    (select min(z) from test.okutma('3002', '2026-11-09', 'pdks', 'giris') z) = '2026-11-09 08:35+03'
    and (select max(z) from test.okutma('3002', '2026-11-13', 'pdks', 'cikis') z) = '2026-11-13 16:20+03');
select test.dogrula('S15 Gizem''in 20 Kasım fazla mesai planı onaylı (120 dk)',
    (select durum = 'onaylandi' and planli_dk = 120 from pdks.fazla_mesai_plani
     where calisan_id = test.c('3003') and is_gunu = '2026-11-20'));
select test.dogrula('S16 Ece 23 Kasım planı olmadan 19:30''a kalmış',
    not exists (select 1 from pdks.fazla_mesai_plani where calisan_id = test.c('3004'))
    and (select max(z) from test.okutma('3004', '2026-11-23', 'pdks', 'cikis') z) = '2026-11-23 19:30+03');
select test.dogrula('S17 Merve''nin yazılı fazla mesai onayı yok',
    not exists (select 1 from pdks.fazla_mesai_onayi where calisan_id = test.c('3005')));
select test.dogrula('S18 Can raporlu, Deniz yıllık izinli; izin günlerinde okutmaları yok',
    exists (select 1 from pdks.izin where calisan_id = test.c('2007') and tur = 'rapor')
    and exists (select 1 from pdks.izin where calisan_id = test.c('2008') and tur = 'yillik')
    and not exists (select test.okutma('2007', '2026-11-24', 'pdks', 'giris')));
select test.dogrula('S19 Kaan 25 Kasım: planı var, izni ve hiçbir okutması yok',
    exists (select 1 from pdks.vardiya_plani where calisan_id = test.c('2009') and tarih = '2026-11-25')
    and not exists (select test.okutma('2009', '2026-11-25', s, 'giris') from unnest(array['pdks', 'kapi']) s));
select test.dogrula('S20 sistemde olmayan kart (K9999) okutulmuş',
    exists (select 1 from pdks.ham_okutma where kart_no = 'K9999')
    and not exists (select 1 from pdks.kart where kart_no = 'K9999'));
select test.dogrula('S21 27 Kasım servis dosyası yok',
    not exists (select 1 from pdks.aktarim where kaynak = 'servis' and veri_tarihi = '2026-11-27'));
select test.dogrula('S22 Montaj amiri Hasan''ın 26 Kasım girişine dair hiçbir okutma yok, üst amiri tanımlı',
    not exists (select test.okutma('1001', '2026-11-26', s, 'giris') from unnest(array['pdks', 'kapi', 'servis']) s)
    and (select ust_amir_id is not null from pdks.kullanici where calisan_id = test.c('1001')));
select test.dogrula('S25 Uğur''un İSG eğitimi 10 Kasım''da doldu; 12 Kasım 10:15''te YG Lab kapısından geçti',
    (select gecerlilik_bitis = '2026-11-10' from pdks.isg_belge where calisan_id = test.c('5303') and tur = 'isg_egitimi')
    and exists (select 1 from pdks.kanit_kaydi k join pdks.okuyucu r on r.id = k.okuyucu_id
                where r.kod = 'YG-KAPI' and k.kart_no = 'K5303' and k.okutma_zamani = '2026-11-12 10:15+03'));
select test.dogrula('S26 Taner''in sağlık muayenesi 15 Aralık''ta doluyor',
    (select gecerlilik_bitis = '2026-12-15' from pdks.isg_belge where calisan_id = test.c('5302') and tur = 'saglik_muayenesi'));
select test.dogrula('S27 19 Kasım Boyahane kapısı: Selim (Depo) 14:10, Hakan (Boyahane) 09:00',
    (select count(*) from pdks.kanit_kaydi k join pdks.okuyucu r on r.id = k.okuyucu_id
     where r.kod = 'BOYA-KAPI' and (k.kart_no, k.okutma_zamani) in
           (('K5402', '2026-11-19 14:10+03'::timestamptz), ('K5202', '2026-11-19 09:00+03'::timestamptz))) = 2);
select test.dogrula('S29 / S30 Pazar planları: Mehmet 22 Kasım (yazılı onaylı), Erkan 29 Kasım (onaysız)',
    exists (select 1 from pdks.vardiya_plani where calisan_id = test.c('1002') and tarih = '2026-11-22')
    and exists (select 1 from pdks.vardiya_plani where calisan_id = test.c('5102') and tarih = '2026-11-29')
    and exists (select 1 from pdks.fazla_mesai_onayi where calisan_id = test.c('1002'))
    and not exists (select 1 from pdks.fazla_mesai_onayi where calisan_id = test.c('5102')));
select test.dogrula('S32 İrem 18 Kasım: PDKS girişi yok, kapı girişi 09:12',
    not exists (select test.okutma('6202', '2026-11-18', 'pdks', 'giris'))
    and (select min(z) from test.okutma('6202', '2026-11-18', 'kapi', 'giris') z) = '2026-11-18 09:12+03');

-- Hazır kontrol fonksiyonları beklenen uyarıları üretiyor ------------------------
select pdks.kart_paylasim_kontrol('2026-11-30');
select pdks.gecici_kart_kontrol(g::date) from generate_series(date '2026-11-01', date '2026-11-30', interval '1 day') g;
select test.dogrula('S11 Kemal ve Murat için kart paylaşımı şüphesi',
    exists (select 1 from pdks.uyari where tur = 'kart_paylasim_suphesi'));
select test.dogrula('S6  İbrahim''in asıl kartı geçici kart zimmetliyken okutuldu uyarısı',
    exists (select 1 from pdks.uyari where tur = 'gecici_kart_cakisma' and calisan_id = test.c('1007')));
select test.dogrula('S7  Osman için sık kart unutma bilgisi',
    exists (select 1 from pdks.uyari where tur = 'sik_kart_unutma' and calisan_id = test.c('1008')));
select test.dogrula('S9  Burak için iade edilmeyen geçici kart uyarısı',
    exists (select 1 from pdks.uyari where tur = 'gecici_kart_iade_edilmedi' and calisan_id = test.c('1010')));
select test.dogrula('S23 zimmetsiz okutulan geçici kart (yalnızca GK-05)',
    (select count(*) from pdks.uyari where tur = 'gecici_kart_zimmetsiz') = 1
    and exists (select 1 from pdks.uyari where tur = 'gecici_kart_zimmetsiz' and mesaj like '%GK-05%'));

-- Gece işi sonrası (Kasım'ın tamamı işlenir; ekranda görülecek sonuçlar) ----------------
do $$ declare d date; begin
    for d in select g::date from generate_series(date '2026-11-01', date '2026-11-30', interval '1 day') g loop
        perform pdks.gece_isi_calistir(d);
    end loop;
end $$;
create function test.gk(p_sicil text, p_gun date) returns pdks.gun_kaydi language sql as $$
    select * from pdks.gun_kaydi where calisan_id = test.c(p_sicil) and is_gunu = p_gun $$;
create function test.uyari(p_tur text, p_sicil text) returns bigint language sql as $$
    select count(*) from pdks.uyari where tur = p_tur and calisan_id = test.c(p_sicil) $$;

select test.dogrula('gece işi Kasım''ın 30 gününü hatasız işledi',
    (select count(*) from pdks.gece_isi where durum = 'basarili') >= 30
    and not exists (select 1 from pdks.gece_isi where durum = 'hatali'));
select test.dogrula('Kasım''da planı olup gün kaydı olmayan çalışan yok (30 Kasım gece vardiyaları dahil; onay bekleyen plan hariç)',
    not exists (select 1 from pdks.vardiya_plani p
                where p.tarih between '2026-11-01' and '2026-11-30' and p.ik_onay_durumu <> 'bekliyor'
                  and not exists (select 1 from pdks.gun_kaydi g where g.calisan_id = p.calisan_id and g.is_gunu = p.tarih)));
select test.dogrula('S13 Okan 13 Kasım: plan İK onayı beklediği için gün işlenmedi; Kasım''da 1597 gün kaydı',
    (select count(*) from pdks.gun_kaydi g where g.calisan_id = test.c('2005') and g.is_gunu = '2026-11-13') = 0
    and (select count(*) from pdks.gun_kaydi where is_gunu between '2026-11-01' and '2026-11-30') = 1597);
select test.dogrula('açık soru yalnızca bilerek açık bırakılan 4 gün (S2, S4, S19, S22)',
    (select array_agg(c.sicil_no order by c.sicil_no) from pdks.amir_sorusu q
     join pdks.gun_kaydi g on g.id = q.gun_kaydi_id join pdks.calisan c on c.id = g.calisan_id
     where q.durum in ('acik', 'eskale', 'ik_karari_bekliyor')) = array['1001', '1003', '1005', '2009']);
-- T-39: S2 ve S4'te üst amir de cevaplamadı; Kasım sonuna kadar İK'ya geçtiler
select test.dogrula('S2 ve S4 üst amirden İK''ya geçti (ikinci kademe), S19 üst amirde, S22 İK''da',
    (select array_agg(c.sicil_no || ':' || q.durum order by c.sicil_no) from pdks.amir_sorusu q
     join pdks.gun_kaydi g on g.id = q.gun_kaydi_id join pdks.calisan c on c.id = g.calisan_id
     where q.durum in ('acik', 'eskale', 'ik_karari_bekliyor'))
    = array['1001:eskale', '1003:ik_karari_bekliyor', '1005:ik_karari_bekliyor', '2009:eskale']);
select test.dogrula('S24 Ferhat 17 Kasım 00-08: giriş 16 Kasım 23:39, tek iş günü, mola 60, gece 315 dk',
    (select date_trunc('minute', giris_zamani) = '2026-11-16 23:39+03' and (cikis_zamani at time zone 'Europe/Istanbul')::date = '2026-11-17'
            and durum = 'tamam' and mola_dk = 60 and gece_calisma_dk = 315
     from test.gk('5002', '2026-11-17')));
select test.dogrula('S24 Gökhan 2 Kasım 16-24: çıkış gece yarısından sonra (3 Kasım), gün 2 Kasım''a yazılır',
    (select (cikis_zamani at time zone 'Europe/Istanbul')::date = '2026-11-03' and durum = 'tamam'
     from test.gk('5003', '2026-11-02'))
    and (test.gk('5003', '2026-11-03')).cikis_zamani > '2026-11-04 00:00+03');
select test.dogrula('S25 Uğur: süresi dolmuş İSG eğitimi uyarısı bir kez; yetkili olduğu YG Lab için bölge uyarısı yok',
    test.uyari('isg_belgesi_suresi_dolmus', '5303') = 1 and test.uyari('yetkisiz_bolge_okutmasi', '5303') = 0);
select test.dogrula('S26 Taner: sağlık muayenesi "süresi doluyor" uyarısı',
    exists (select 1 from pdks.uyari where tur = 'isg_belgesi_suresi_doluyor' and calisan_id = test.c('5302')
            and mesaj like '%15.12.2026%'));
select test.dogrula('S27 Boyahane kapısı: Selim''e yetkisiz bölge uyarısı, Hakan''a yok',
    test.uyari('yetkisiz_bolge_okutmasi', '5402') = 1 and test.uyari('yetkisiz_bolge_okutmasi', '5202') = 0
    and (select count(*) from pdks.uyari where tur = 'yetkisiz_bolge_okutmasi') = 1);
select test.dogrula('S28 onaysız fazla mesai havuzu: Ece 150, Merve 100 dk (ve S30 Erkan) İK kararı bekliyor',
    (select array_agg(c.sicil_no || ':' || f.tur || ':' || f.dakika order by c.sicil_no)
     from pdks.fazla_mesai_inceleme f join pdks.calisan c on c.id = f.calisan_id
     where f.durum = 'inceleme_bekliyor')
        = array['3004:vardiya_sonrasi:150', '3005:vardiya_sonrasi:100', '5102:tatil_calismasi:485']);
select test.dogrula('S29 Mehmet 22 Kasım Pazar: FM100 480 dk, puantaj kodu FM100',
    (select fm100_dk = 480 and durum = 'tamam' from test.gk('1002', '2026-11-22'))
    and exists (select 1 from pdks.gun_kodlari_hesapla(2026, 11) k
                where k.calisan_id = test.c('1002') and k.tarih = '2026-11-22' and k.kod = 'FM100' and k.dakika = 480));
select test.dogrula('S30 Erkan 29 Kasım Pazar, yazılı onay yok: FM100 0, süre havuzda (tatil çalışması)',
    (select fm100_dk = 0 from test.gk('5102', '2026-11-29'))
    and exists (select 1 from pdks.fazla_mesai_inceleme where calisan_id = test.c('5102')
                and is_gunu = '2026-11-29' and tur = 'tatil_calismasi'));
select test.dogrula('S31 esnek mesai ay sonu: Onur -152 dk, İrem +29 dk',
    (select fark_dk from pdks.v_esnek_mesai where calisan_id = test.c('6002') and yil = 2026 and ay = 11) = -152
    and (select fark_dk from pdks.v_esnek_mesai where calisan_id = test.c('6202') and yil = 2026 and ay = 11) = 29);
select test.dogrula('S32 İrem 18 Kasım: giriş kapı 09:12 + yürüme payı = 09:17, kanıtla yazıldı, amire soru yok',
    (select giris_zamani = '2026-11-18 09:17+03' and giris_kaynagi = 'kanit' and durum = 'tamam'
     from test.gk('6202', '2026-11-18'))
    and not exists (select 1 from pdks.amir_sorusu where gun_kaydi_id = (test.gk('6202', '2026-11-18')).id)
    and exists (select 1 from pdks.duzeltme where gun_kaydi_id = (test.gk('6202', '2026-11-18')).id
                and gerekce like 'Esnek mesai: Kapı kaydı 09:12%'));

do $$ begin raise notice 'ÖRNEK VERİ TESTLERİ GEÇTİ'; end $$;
rollback;
