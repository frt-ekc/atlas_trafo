-- =====================================================================
-- Puantaj testleri (20261121010000_puantaj.sql)
-- Testin kendi sahte verisi (Ekim 2026) kullanılır; örnek veri yüklü olsun
-- olmasın çalışır. Her şey tek işlemde çalışır ve sonda geri alınır (ROLLBACK).
-- Çalıştırma: psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/puantaj_testi.sql
-- =====================================================================
\pset tuples_only on
\pset format unaligned
begin;
-- Bu test Kasım / Aralık 2026'yı kilitler; ay bitmeden kilit olmadığı için (T-89) bugün 15.01.2027 kabul edilir
set local pdks.test_bugun = '2027-01-15';
set local timezone = 'Europe/Istanbul';

create schema test;
create function test.dogrula(p_ad text, p_kosul boolean) returns void language plpgsql as $$
begin
    if p_kosul is not true then raise exception 'KALDI  %', p_ad; end if;
    raise notice 'GEÇTİ  %', p_ad;
end $$;
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
create function test.gk(p_sicil text, p_gun date) returns pdks.gun_kaydi language sql security definer as $$
    select * from pdks.gun_kaydi where calisan_id = test.c(p_sicil) and is_gunu = p_gun $$;
create function test.ps(p_sicil text, p_yil int, p_ay int, p_tur text) returns pdks.puantaj_satiri
language sql security definer as $$
    select s.* from pdks.puantaj_satiri s join pdks.donem d on d.id = s.donem_id
    where s.calisan_id = test.c(p_sicil) and d.yil = p_yil and d.ay = p_ay and s.satir_turu = p_tur $$;
create function test.ts(p text) returns timestamptz language sql immutable as $$
    select (p::timestamp) at time zone 'Europe/Istanbul' $$;
grant usage on schema test to authenticated;
grant execute on all functions in schema test to authenticated;

-- Test verisi (yalnızca sahte) ---------------------------------------------
insert into pdks.departman (ad) values ('PT Üretim'), ('PT İdari');
insert into pdks.calisan (sicil_no, ad, soyad, departman_id, ise_giris_tarihi)
select s, 'Ad' || s, 'Örnek', (select id from pdks.departman where ad = d), '2025-01-01'
from (values ('PT01', 'PT Üretim'), ('PT02', 'PT Üretim'), ('PTA1', 'PT Üretim'), ('PTI1', 'PT İdari')) v(s, d);
insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, auth_kullanici_id) values
    ('PT Amir', 'pt_amir@ornek.test', 'amir', test.c('PTA1'), '00000000-0000-0000-0000-0000000000d1'),
    ('PT İK',   'pt_ik@ornek.test',   'ik',   test.c('PTI1'), '00000000-0000-0000-0000-0000000000d2');
update pdks.departman set amir_id = test.k('pt_amir@ornek.test') where ad = 'PT Üretim';
insert into pdks.kart (kart_no, calisan_id) values ('PT-01', test.c('PT01')), ('PT-02', test.c('PT02'));
insert into pdks.okuyucu (kod, ad, sistem) values ('PT-PDKS', 'PT PDKS', 'pdks');

-- PT01 ve PT02, 5 ve 6 Ekim gündüz vardiyasında
insert into pdks.vardiya_plani (calisan_id, tarih, vardiya_id, giren_id)
select test.c(s), g, (select id from pdks.vardiya_tanim where kod = 'GUNDUZ'), test.k('pt_ik@ornek.test')
from unnest(array['PT01', 'PT02']) s, unnest(array['2026-10-05', '2026-10-06']::date[]) g;

insert into pdks.aktarim (kaynak, dosya_adi, dosya_ozeti, veri_tarihi)
select 'pdks', 'pt_' || g || '.csv', 'pt-pdks-' || g, g
from unnest(array['2026-10-05', '2026-10-06']::date[]) g;

-- PT01: iki gün normal. PT02: 5 Ekim 20 dk geç; 6 Ekim giriş yok, çıkış 17:00
insert into pdks.ham_okutma (aktarim_id, okuyucu_id, kart_no, okutma_zamani, yon)
select (select id from pdks.aktarim where dosya_ozeti = 'pt-pdks-' || (z::timestamp)::date),
       (select id from pdks.okuyucu where kod = 'PT-PDKS'), k, test.ts(z), y
from (values ('PT-01', '2026-10-05 07:55:00', 'giris'), ('PT-01', '2026-10-05 17:02:00', 'cikis'),
             ('PT-01', '2026-10-06 07:56:00', 'giris'), ('PT-01', '2026-10-06 17:01:00', 'cikis'),
             ('PT-02', '2026-10-05 08:20:00', 'giris'), ('PT-02', '2026-10-05 17:03:00', 'cikis'),
                                                        ('PT-02', '2026-10-06 17:00:00', 'cikis')) v(k, z, y);

select pdks.gece_isi_calistir('2026-10-05');
select pdks.gece_isi_calistir('2026-10-06');

select test.dogrula('hazırlık: PT02 6 Ekim girişi eksik, amire soru açık',
    (select durum = 'soru_bekliyor' and giris_zamani is null from test.gk('PT02', '2026-10-06')));

-- Kilitten önceki canlı puantaj (karşılaştırma için)
create temp table canli as
select v.* from pdks.v_puantaj_canli v
where v.yil = 2026 and v.ay = 10 and v.calisan_id in (test.c('PT01'), test.c('PT02'));

-- 1) Yetki ve kilit kuralı -------------------------------------------------
set local role authenticated;
select test.oturum('pt_amir@ornek.test');
select test.hata('amir ayı kilitleyemez', 'yetkiniz yok', $$select pdks.ay_kilitle(2026::smallint, 10::smallint)$$);
select test.hata('uygulama puantajı doğrudan yazamaz', 'permission denied',
    $$select pdks.puantaj_yaz(1)$$);
select test.oturum('pt_ik@ornek.test');
select test.hata('açık soru varken ay kilitlenmez', 'açık soru',
    $$select pdks.ay_kilitle(2026::smallint, 10::smallint)$$);
select pdks.ay_kilitle(2026::smallint, 10::smallint, true, 'Test: zorla kilit gerekçesi');
reset role;

-- 2) Normal satırlar ---------------------------------------------------------
select test.dogrula('Ekim kilitlendi',
    (select durum = 'kilitli' from pdks.donem where yil = 2026 and ay = 10));
select test.dogrula('normal satırlar kilit öncesi canlı puantajla birebir aynı',
    (select count(*) = 2 from canli c
     join pdks.puantaj_satiri s on s.calisan_id = c.calisan_id and s.satir_turu = 'normal'
     join pdks.donem d on d.id = s.donem_id and d.yil = 2026 and d.ay = 10
     where s.calisilan_gun = c.calisilan_gun and s.calisma_dk = c.calisma_dk
       and s.gec_kalma_dk = c.gec_kalma_dk and s.erken_cikis_dk = c.erken_cikis_dk
       and s.fazla_mesai_dk = c.fazla_mesai_dk and s.devamsiz_gun = c.devamsiz_gun));
select test.dogrula('PT01: 2 gün, 960 dk çalışma (2 × (540 − 60 dk mola))',
    (select calisilan_gun = 2 and calisma_dk = 960 and gec_kalma_dk = 0 from test.ps('PT01', 2026, 10, 'normal')));
select test.dogrula('PT02: 1 gün (6 Ekim eksik sayılmadı), 20 dk geç',
    (select calisilan_gun = 1 and calisma_dk = 460 and gec_kalma_dk = 20 from test.ps('PT02', 2026, 10, 'normal')));
select test.hata('puantaj satırı silinemez', 'değiştirilemez',
    $$delete from pdks.puantaj_satiri where calisan_id = test.c('PT01')$$);
select test.hata('kilit ikinci kez yapılamaz / geri açılamaz', 'kilitli',
    $$update pdks.donem set durum = 'acik' where yil = 2026 and ay = 10$$);

-- 3) Kilitten sonra gelen düzeltme: gün değişmez, fark Kasım'a düşer -------------
set local role authenticated;
select test.oturum('pt_ik@ornek.test');
select pdks.kayit_duzelt((test.gk('PT02', '2026-10-06')).id, 'giris_zamani', '2026-10-06 08:00+03',
                         'Kilit sonrası belge geldi: 08:00 girişi');
reset role;

select test.dogrula('kilitli günün kaydı değişmedi',
    (select giris_zamani is null from test.gk('PT02', '2026-10-06')));
select test.dogrula('düzeltme Kasım''a fark olarak yönlendirildi',
    (select d.fark_satiri and dn.yil = 2026 and dn.ay = 11
     from pdks.duzeltme d join pdks.donem dn on dn.id = d.hedef_donem_id
     where d.gun_kaydi_id = (test.gk('PT02', '2026-10-06')).id and d.alan = 'giris_zamani'));

-- Kasım kilitlenince fark satırı yazılır (örnek veri yüklüyse Kasım'da soru olabilir: zorla)
-- Örnek veri yüklüyse onun Kasım planları bu testte gece işinden geçmez; ay kilidi (20261201010000)
-- işlenmemiş planlı günü zorla bile kabul etmez. Test yalnızca kendi verisine bakar (ROLLBACK geri alır).
delete from pdks.vardiya_plani where tarih between '2026-11-01' and '2026-11-30';
set local role authenticated;
select test.oturum('pt_ik@ornek.test');
select pdks.ay_kilitle(2026::smallint, 11::smallint, true, 'Test: zorla kilit gerekçesi');
reset role;

select test.dogrula('Kasım puantajında PT02 için Ekim kaynaklı fark: +1 gün, +480 dk (mola düşülmüş)',
    (select s.calisilan_gun = 1 and s.calisma_dk = 480 and s.gec_kalma_dk = 0 and s.devamsiz_gun = 0
            and dk.yil = 2026 and dk.ay = 10
     from test.ps('PT02', 2026, 11, 'fark') s join pdks.donem dk on dk.id = s.kaynak_donem_id));
select test.dogrula('düzeltmesi olmayan PT01 için fark satırı yok',
    (select (test.ps('PT01', 2026, 11, 'fark')).id is null));
select test.dogrula('Ekim''in normal satırı değişmeden kaldı',
    (select calisilan_gun = 1 and calisma_dk = 460 from test.ps('PT02', 2026, 10, 'normal')));

-- 4) Gece işi aynı hesap kuralını kullanıyor (gun_hesabi) ----------------------
select test.dogrula('gün kaydındaki dakikalar gun_hesabi ile aynı',
    (select bool_and(x.calisma_dk = g.calisma_dk and x.gec_kalma_dk = g.gec_kalma_dk
                     and x.erken_cikis_dk = g.erken_cikis_dk and x.fazla_mesai_dk = g.fazla_mesai_dk)
     from pdks.gun_kaydi g
     cross join lateral pdks.gun_hesabi(g.calisan_id, g.is_gunu, g.planli_baslangic, g.planli_bitis,
                                        g.giris_zamani, g.cikis_zamani) x
     where g.calisan_id in (test.c('PT01'), test.c('PT02')) and g.hesap_tamam));

do $$ begin raise notice 'TÜM TESTLER GEÇTİ'; end $$;
rollback;
