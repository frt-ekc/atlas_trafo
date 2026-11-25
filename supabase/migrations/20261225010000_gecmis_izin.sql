-- =====================================================================
-- K5 / K2 · T-46 + T-40: İşlenmiş güne girilen izin günü değiştirmiyor, soru açık kalıyordu;
-- İK'nın kayıt düzeltmesi açık soruyu kapatmıyor, sonraki amir cevabı onu eziyordu
--
-- Karar:
--   * izin_gir: iznin işlenmiş günleri duzeltme_uygula ile izinli / raporlu olur (izin_id ile),
--     o günlerin açık soruları "İzin girildi" nedeniyle kapanır. Kilitli ayda gün değişmez,
--     düzeltme sonraki açık aya fark satırı olur.
--   * O gün okutma ya da saat kaydı varsa gün izinli yapılmaz, soru açık kalır;
--     İK'ya izin_gununde_okutma uyarısı yazılır.
--   * izin_iptal: bu düzeltmeler geri alınır, kapanan sorular eski durumuyla açılır.
--     Sonradan başka bir durum düzeltmesi yapılmış güne dokunulmaz.
--   * Geçerli izin varken devamsız kararı verilemez (soru_ik_karari ve kayit_duzelt).
--   * kayit_duzelt açık soruyu kapatır. Yalnızca bir saat düzeltildi ve gün hâlâ eksikse yalnızca
--     o saatin sorusu kapanır; diğeri açık kalır (gün sorusuz askıda kalmasın).
--   * soru_cevapla: İK'nın sonuçlandırdığı güne cevap verilemez, İK'nın düzelttiği saat ezilmez.
-- Kalıcı test: supabase/tests/gecmis_izin_testi.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Sorunun kapanış izi ve yeni uyarı türü
-- ---------------------------------------------------------------------
alter table pdks.amir_sorusu
    add column kapanis_nedeni  text,
    add column kapatan_id      bigint references pdks.kullanici (id),
    add column kapanis_zamani  timestamptz,
    add column kapatan_izin_id bigint references pdks.izin (id),
    add column onceki_durum    text check (onceki_durum in ('acik', 'eskale', 'ik_karari_bekliyor')),
    add constraint amir_sorusu_kapanis_tam check (
        (kapanis_nedeni is null) = (kapatan_id is null)
        and (kapanis_nedeni is null) = (kapanis_zamani is null)
        and (kapanis_nedeni is null) = (onceki_durum is null)
        and (kapatan_izin_id is null or kapanis_nedeni is not null)
        and (kapanis_nedeni is null or durum = 'kapandi'));
comment on column pdks.amir_sorusu.kapanis_nedeni is
    'Cevapla değil başka bir işlemle kapandıysa nedeni (İzin girildi, İK kayıt düzeltmesi). İzin türü yazılmaz.';
comment on column pdks.amir_sorusu.onceki_durum is 'Kapanmadan önceki durum; izin iptal edilirse soru bu duruma döner.';

drop trigger amir_sorusu_gorev_ayriligi on pdks.amir_sorusu;
create trigger amir_sorusu_gorev_ayriligi before insert or update on pdks.amir_sorusu
    for each row execute function pdks.kendi_kaydi_engelle('gun_kaydi', 'atanan_id', 'eskale_edilen_id', 'cevaplayan_id', 'kapatan_id');

create or replace function pdks.amir_sorusu_kontrol()
returns trigger
language plpgsql
set search_path = pdks
as $$
begin
    if new.cevap is not null and old.cevap is null then
        new.cevap_zamani := now();
        if new.cevap = 'gelmedi' and pdks.kullanici_rolu(new.cevaplayan_id) is distinct from 'ik' then
            new.durum := 'ik_karari_bekliyor';
        end if;
    end if;
    if new.durum = 'kapandi' and old.durum = 'ik_karari_bekliyor'
       and pdks.kullanici_rolu(coalesce(new.kapatan_id, new.cevaplayan_id)) is distinct from 'ik' then
        raise exception 'Bu soruyu yalnızca İK kapatabilir.';
    end if;
    return new;
end;
$$;

alter table pdks.uyari drop constraint uyari_tur_check;
alter table pdks.uyari add constraint uyari_tur_check check (tur in (
    'ariza_suphesi', 'dosya_gelmedi', 'fm_gunluk_sinir_asildi',
    'fm_onay_geri_alindi', 'fm_onay_yok', 'fm_plansiz_calisma',
    'fm_yillik_sinir_asildi', 'fm_yillik_sinir_yaklasti', 'gece_calisma_siniri_asildi',
    'gece_isi_calismadi', 'gecici_kart_cakisma', 'gecici_kart_iade_edilmedi',
    'gecici_kart_zimmetsiz', 'geriye_donuk_vardiya', 'iptal_kart_okutma',
    'isg_belgesi_suresi_dolmus', 'isg_belgesi_suresi_doluyor', 'isg_belgesi_yok',
    'izin_gununde_okutma', 'kart_paylasim_suphesi', 'kendi_okutmasi_yuklendi',
    'plansiz_gun_calismasi', 'puantaj_ayari_degisti', 'sik_kart_unutma',
    'soru_eskale', 'yazili_onay_eksik', 'yetkisiz_bolge_okutmasi'
));

-- ---------------------------------------------------------------------
-- 2. Yardımcılar
-- ---------------------------------------------------------------------

-- O günün açık sorularını kapatır; p_turler verilirse yalnızca o türleri
create function pdks.soru_kapat(p_gun_kaydi_id bigint, p_kapatan_id bigint, p_neden text,
                                p_izin_id bigint default null, p_turler text[] default null)
returns integer
language plpgsql
set search_path = pdks
as $$
declare
    v_n integer;
begin
    update pdks.amir_sorusu
    set onceki_durum = durum, durum = 'kapandi', kapanis_nedeni = p_neden, kapatan_id = p_kapatan_id,
        kapanis_zamani = now(), kapatan_izin_id = p_izin_id
    where gun_kaydi_id = p_gun_kaydi_id and durum in ('acik', 'eskale', 'ik_karari_bekliyor')
      and (p_turler is null or soru_turu = any (p_turler));
    get diagnostics v_n = row_count;
    return v_n;
end;
$$;

-- İzin girilirken yazılan, sonradan başka durum düzeltmesiyle değişmemiş düzeltmeler
-- (izin ve düzeltmesi aynı işlemde yazılır; elle bağlanan düzeltmeler bu yolla ayrılır)
create function pdks.izin_duzeltmeleri(p_izin_id bigint)
returns setof pdks.duzeltme
language sql
stable
set search_path = pdks
as $$
    select d.*
    from pdks.duzeltme d
    join pdks.izin i on i.id = d.izin_id
    where d.izin_id = p_izin_id and d.alan = 'durum' and d.yapilma_zamani = i.giris_zamani
      and d.yeni_deger in ('izinli', 'raporlu')
      and not exists (select 1 from pdks.duzeltme s
                      where s.gun_kaydi_id = d.gun_kaydi_id and s.alan = 'durum' and s.id > d.id);
$$;

create function pdks.izin_gunlere_uygula(p_izin_id bigint, p_yapan_id bigint)
returns void
language plpgsql
set search_path = pdks
as $$
declare
    v_izin   pdks.izin;
    v_hedef  text;
    v_durum  text;
    g        record;
begin
    select * into v_izin from pdks.izin where id = p_izin_id;
    v_hedef := case when v_izin.tur = 'rapor' then 'raporlu' else 'izinli' end;

    for g in
        select gk.*, w.p_bas, w.p_bit
        from pdks.gun_kaydi gk
        left join lateral pdks.gun_penceresi(gk.id) w on true
        where gk.calisan_id = v_izin.calisan_id and gk.is_gunu between v_izin.baslangic and v_izin.bitis
        order by gk.is_gunu
    loop
        -- Kilitli günde kayıt değişmez; geçerli durum son fark düzeltmesindedir
        v_durum := coalesce((select d.yeni_deger from pdks.duzeltme d
                             where d.gun_kaydi_id = g.id and d.alan = 'durum' and d.fark_satiri
                             order by d.id desc limit 1), g.durum);

        if g.giris_zamani is not null or g.cikis_zamani is not null
           or exists (select 1 from pdks.amir_sorusu q
                      where q.gun_kaydi_id = g.id and q.soru_turu = 'vardiya_uyusmazligi')
           or exists (select 1 from pdks.ham_okutma h
                      where h.okutma_zamani between g.p_bas and g.p_bit
                        and pdks.okutma_sahibi(h.kart_no, h.okutma_zamani) = g.calisan_id
                        and not pdks.okutma_gecersiz_mi(h.id)) then
            perform pdks.uyari_yaz('izin_gununde_okutma', p_izin_id || ':' || g.is_gunu,
                format('İzin girilen günde okutma var (%s). Gün izinli yapılmadı; kayıt incelenmelidir.',
                       to_char(g.is_gunu, 'DD.MM.YYYY')),
                g.calisan_id);
            continue;
        end if;
        -- Tatil ve vardiyasız gün izinle değişmez
        continue when v_durum in ('tatil', 'vardiya_yok');

        if v_durum <> v_hedef then
            perform pdks.duzeltme_uygula(g.id, 'durum', v_hedef,
                format('İzin girildi (%s – %s)', to_char(v_izin.baslangic, 'DD.MM.YYYY'), to_char(v_izin.bitis, 'DD.MM.YYYY')),
                'ik', p_yapan_id, p_izin_id => p_izin_id);
        end if;
        perform pdks.soru_kapat(g.id, p_yapan_id, 'İzin girildi', p_izin_id);
    end loop;
end;
$$;

create function pdks.izin_gunlerden_geri_al(p_izin_id bigint, p_yapan_id bigint, p_neden text)
returns void
language plpgsql
set search_path = pdks
as $$
declare
    v_eski text;
    d      pdks.duzeltme;
begin
    for d in select * from pdks.izin_duzeltmeleri(p_izin_id) order by id loop
        v_eski := d.eski_deger;
        if d.fark_satiri then
            v_eski := coalesce((select o.yeni_deger from pdks.duzeltme o
                                where o.gun_kaydi_id = d.gun_kaydi_id and o.alan = 'durum' and o.fark_satiri and o.id < d.id
                                order by o.id desc limit 1), d.eski_deger);
        end if;
        perform pdks.duzeltme_uygula(d.gun_kaydi_id, 'durum', v_eski, 'İzin iptal edildi: ' || p_neden,
                                     'ik', p_yapan_id, p_izin_id => p_izin_id);
    end loop;

    -- İzinle kapanan sorular eski durumuyla açılır; cevap süresi bugünden başlar.
    -- Gün sonradan başka türlü sonuçlandıysa soru kapalı kalır.
    update pdks.amir_sorusu q
    set durum = q.onceki_durum, onceki_durum = null, kapanis_nedeni = null, kapatan_id = null,
        kapanis_zamani = null, kapatan_izin_id = null,
        son_cevap_tarihi = greatest(q.son_cevap_tarihi, pdks.bugun() + pdks.ayar_al('soru_eskalasyon_gun'))
    where q.kapatan_izin_id = p_izin_id
      and coalesce((select s.yeni_deger from pdks.duzeltme s
                    where s.gun_kaydi_id = q.gun_kaydi_id and s.alan = 'durum'
                    order by s.id desc limit 1),
                   (select g.durum from pdks.gun_kaydi g where g.id = q.gun_kaydi_id))
          in ('soru_bekliyor', 'eksik', 'devamsiz_suphesi');
end;
$$;

-- Geçerli izin varken gün devamsız yapılamaz
create function pdks.devamsiz_izin_denetle(p_gun_kaydi_id bigint)
returns void
language plpgsql
stable
set search_path = pdks
as $$
declare
    v_gun date;
begin
    select g.is_gunu into v_gun
    from pdks.gun_kaydi g
    join pdks.izin i on i.calisan_id = g.calisan_id and i.iptal_zamani is null
                    and g.is_gunu between i.baslangic and i.bitis
    where g.id = p_gun_kaydi_id
    limit 1;
    if found then
        raise exception 'Çalışanın % günü için geçerli bir izni vardır; devamsız kararı verilemez.', to_char(v_gun, 'DD.MM.YYYY');
    end if;
end;
$$;

-- kayit_duzelt'ten sonra: düzeltmenin sonuçlandırdığı sorular kapanır (T-40)
create function pdks.duzeltme_sorulari_kapat(p_gun_kaydi_id bigint, p_alan text, p_yeni_deger text, p_kapatan_id bigint)
returns void
language plpgsql
set search_path = pdks
as $$
declare
    g pdks.gun_kaydi;
begin
    select * into g from pdks.gun_kaydi where id = p_gun_kaydi_id;
    -- Kilitli günde kayıt değişmez; düzeltilen saat var sayılır
    if (p_alan = 'durum' and p_yeni_deger in ('devamsiz', 'izinli', 'raporlu', 'tatil', 'vardiya_yok'))
       or ((g.giris_zamani is not null or p_alan = 'giris_zamani')
           and (g.cikis_zamani is not null or p_alan = 'cikis_zamani')) then
        perform pdks.soru_kapat(p_gun_kaydi_id, p_kapatan_id, 'İK kayıt düzeltmesi');
    elsif p_alan = 'giris_zamani' then
        perform pdks.soru_kapat(p_gun_kaydi_id, p_kapatan_id, 'İK kayıt düzeltmesi',
                                p_turler => array['giris_yok', 'kanit_vardiya_sonrasi', 'ariza_kaniti_yok']);
    elsif p_alan = 'cikis_zamani' then
        perform pdks.soru_kapat(p_gun_kaydi_id, p_kapatan_id, 'İK kayıt düzeltmesi', p_turler => array['cikis_yok']);
    end if;
end;
$$;

revoke execute on function pdks.soru_kapat(bigint, bigint, text, bigint, text[]), pdks.izin_duzeltmeleri(bigint),
    pdks.izin_gunlere_uygula(bigint, bigint), pdks.izin_gunlerden_geri_al(bigint, bigint, text),
    pdks.devamsiz_izin_denetle(bigint), pdks.duzeltme_sorulari_kapat(bigint, text, text, bigint)
from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 3. Ekran fonksiyonları
-- ---------------------------------------------------------------------
create or replace function pdks.izin_gir(p_calisan_id bigint, p_tur text, p_baslangic date, p_bitis date, p_aciklama text default null)
returns bigint
language plpgsql
security definer
set search_path = pdks
as $$
declare
    v_ben    bigint := pdks.yetki_gerekli('ik');
    v_izin   pdks.izin;
    v_id     bigint;
begin
    if p_baslangic is null or p_bitis is null or p_bitis < p_baslangic then
        raise exception 'İzin bitişi, başlangıcından önce olamaz.';
    end if;

    perform 1 from pdks.calisan where id = p_calisan_id for no key update;

    select * into v_izin
    from pdks.izin i
    where i.calisan_id = p_calisan_id and i.iptal_zamani is null
      and i.baslangic <= p_bitis and i.bitis >= p_baslangic
    order by i.baslangic, i.id
    limit 1;
    if found then
        raise exception 'Çalışanın % – % tarihlerinde geçerli bir izni vardır. Yeni izin için önce bu izin iptal edilmelidir.',
            to_char(v_izin.baslangic, 'DD.MM.YYYY'), to_char(v_izin.bitis, 'DD.MM.YYYY');
    end if;

    insert into pdks.izin (calisan_id, tur, baslangic, bitis, aciklama, giren_id)
    values (p_calisan_id, p_tur, p_baslangic, p_bitis, p_aciklama, v_ben)
    returning id into v_id;
    perform pdks.izin_gunlere_uygula(v_id, v_ben);
    return v_id;
end;
$$;

create or replace function pdks.izin_iptal(p_izin_id bigint, p_neden text)
returns void
language plpgsql
security definer
set search_path = pdks
as $$
declare
    v_ben    bigint := pdks.yetki_gerekli('ik');
    v_izin   pdks.izin;
    v_islenen integer;
begin
    select * into v_izin from pdks.izin where id = p_izin_id for update;
    if not found then
        raise exception 'İzin bulunamadı.';
    end if;
    if v_izin.iptal_zamani is not null then
        raise exception 'Bu izin zaten iptal edilmiş.';
    end if;
    if p_neden is null or length(trim(p_neden)) < 5 then
        raise exception 'İptal nedeni yazılmalı (en az 5 karakter).';
    end if;

    -- Bu iznin düzeltmeyle değiştirmediği izinli gün (gece işi ya da elle düzeltme) kendiliğinden dönmez
    select count(*) into v_islenen
    from pdks.gun_kaydi g
    where g.calisan_id = v_izin.calisan_id
      and g.is_gunu between v_izin.baslangic and v_izin.bitis
      and g.durum in ('izinli', 'raporlu')
      and not exists (select 1 from pdks.izin_duzeltmeleri(v_izin.id) d where d.gun_kaydi_id = g.id);
    if v_islenen > 0 then
        raise exception 'İznin % günü işlenmiştir. Bu günler önce kayıt düzeltme ile güncellenmelidir.', v_islenen;
    end if;

    perform 1 from pdks.calisan where id = v_izin.calisan_id for no key update;
    perform pdks.izin_gunlerden_geri_al(v_izin.id, v_ben, trim(p_neden));

    update pdks.izin
    set iptal_zamani = now(), iptal_eden_id = v_ben, iptal_nedeni = trim(p_neden)
    where id = p_izin_id;
end;
$$;

create or replace function pdks.soru_ik_karari(p_soru_id bigint, p_devamsiz boolean, p_gerekce text, p_giris timestamptz default null, p_cikis timestamptz default null)
returns void
language plpgsql
security definer
set search_path = pdks
as $$
declare
    v_ben   bigint := pdks.yetki_gerekli('ik');
    v_soru  pdks.amir_sorusu;
begin
    select * into v_soru from pdks.amir_sorusu where id = p_soru_id for update;
    -- Son karar İK'dadır (T-39): soru amirde, üst amirde ya da İK'da beklerken İK karar verebilir
    if not found or v_soru.durum not in ('acik', 'eskale', 'ik_karari_bekliyor') then
        raise exception 'İK kararı bekleyen soru bulunamadı.';
    end if;
    if not p_devamsiz and p_giris is null and p_cikis is null then
        raise exception 'Devamsız değilse giriş ya da çıkış saatini girin.';
    end if;

    if p_devamsiz then
        perform pdks.devamsiz_izin_denetle(v_soru.gun_kaydi_id);
    end if;

    update pdks.amir_sorusu
    set durum = 'kapandi', cevaplayan_id = v_ben,
        -- Yalnızca sonuç: gerekçe, amirin okuyamadığı duzeltme satırındadır (T-106)
        ik_karari = case when p_devamsiz then 'devamsiz' else 'geldi' end
    where id = p_soru_id;

    if p_devamsiz then
        perform pdks.duzeltme_uygula(v_soru.gun_kaydi_id, 'durum', 'devamsiz', p_gerekce, 'ik', v_ben,
                                     p_soru_id => p_soru_id, p_aleyhine => true);
    else
        perform pdks.saat_yaz(v_soru.gun_kaydi_id, p_giris, p_cikis, p_gerekce, 'ik', v_ben, p_soru_id => p_soru_id);
    end if;

    -- Değişen gün hemen hesaplanır (kilitli ayda yapılmaz; düzeltme orada fark satırı olur)
    perform pdks.gun_hesapla(v_soru.gun_kaydi_id);
end;
$$;

create or replace function pdks.kayit_duzelt(p_gun_kaydi_id bigint, p_alan text, p_yeni_deger text, p_gerekce text, p_itiraz_id bigint default null, p_izin_id bigint default null)
returns bigint
language plpgsql
security definer
set search_path = pdks
as $$
declare
    v_ben  bigint := pdks.yetki_gerekli('ik');
    v_id   bigint;
begin
    if p_alan = 'durum' and p_yeni_deger = 'devamsiz' then
        perform pdks.devamsiz_izin_denetle(p_gun_kaydi_id);
    end if;
    v_id := pdks.duzeltme_uygula(p_gun_kaydi_id, p_alan, p_yeni_deger, p_gerekce, 'ik', v_ben,
                                 p_izin_id => p_izin_id, p_itiraz_id => p_itiraz_id,
                                 p_aleyhine => (p_alan = 'durum' and p_yeni_deger = 'devamsiz'));
    -- İK'nın düzeltmesi o günün sorusunu sonuçlandırır (T-40)
    perform pdks.duzeltme_sorulari_kapat(p_gun_kaydi_id, p_alan, p_yeni_deger, v_ben);
    -- Değişen gün hemen hesaplanır (kilitli ayda yapılmaz; düzeltme orada fark satırı olur)
    perform pdks.gun_hesapla(p_gun_kaydi_id);
    return v_id;
end;
$$;

create or replace function pdks.soru_cevapla(p_soru_id bigint, p_cevap text, p_giris timestamptz default null, p_cikis timestamptz default null, p_aciklama text default null)
returns void
language plpgsql
security definer
set search_path = pdks
as $$
declare
    v_ben     bigint := pdks.yetki_gerekli('amir');
    v_soru    pdks.amir_sorusu;
    v_gun     pdks.gun_kaydi;
    v_giris   timestamptz;
    v_cikis   timestamptz;
    v_vardiya smallint;
begin
    select * into v_soru from pdks.amir_sorusu where id = p_soru_id for update;
    if not found or v_ben not in (v_soru.atanan_id, coalesce(v_soru.eskale_edilen_id, 0)) then
        raise exception 'Soru bulunamadı ya da size atanmamış.';
    end if;
    if v_soru.durum not in ('acik', 'eskale') then
        raise exception 'Bu soru zaten cevaplanmış.';
    end if;
    if p_cevap not in ('geldi_saat_dogru', 'geldi_saat_farkli', 'kart_unuttu', 'gelmedi', 'bilmiyorum') then
        raise exception 'Geçersiz cevap: %', p_cevap;
    end if;
    select * into v_gun from pdks.gun_kaydi where id = v_soru.gun_kaydi_id;
    if v_gun.durum in ('devamsiz', 'izinli', 'raporlu') then
        raise exception 'Bu gün İK tarafından sonuçlandırılmıştır; cevap verilemez.';
    end if;

    if p_cevap = 'geldi_saat_farkli' and p_giris is null and p_cikis is null then
        raise exception 'Saat farklıysa giriş ya da çıkış saatini girin.';
    end if;

    if p_cevap in ('geldi_saat_dogru', 'kart_unuttu') and p_giris is null and p_cikis is null then
        if v_soru.soru_turu = 'vardiya_uyusmazligi' then
            if v_soru.onerilen_vardiya_id is null then
                raise exception 'Bu soru türünde saatleri girin.';
            end if;
            v_vardiya := v_soru.onerilen_vardiya_id;
            v_giris := v_soru.onerilen_zaman;
            v_cikis := v_soru.onerilen_cikis;
        end if;
        if v_soru.soru_turu in ('giris_yok', 'kanit_vardiya_sonrasi', 'ariza_kaniti_yok', 'hic_kayit_yok') then
            v_giris := coalesce(v_soru.onerilen_zaman, v_gun.planli_baslangic);
        end if;
        if v_soru.soru_turu = 'cikis_yok' then
            v_cikis := coalesce(v_soru.onerilen_zaman, v_gun.planli_bitis);
        end if;
        if v_soru.soru_turu = 'hic_kayit_yok' then
            v_cikis := v_gun.planli_bitis;
        end if;
    else
        v_giris := p_giris;
        v_cikis := p_cikis;
    end if;

    update pdks.amir_sorusu
    set cevap = p_cevap, cevap_giris = v_giris, cevap_cikis = v_cikis, cevap_aciklama = p_aciklama,
        cevaplayan_id = v_ben,
        durum = case when p_cevap in ('gelmedi', 'bilmiyorum') then 'ik_karari_bekliyor' else 'cevaplandi' end
    where id = p_soru_id;

    if p_cevap not in ('gelmedi', 'bilmiyorum') then
        if v_vardiya is not null then
            perform pdks.duzeltme_uygula(v_soru.gun_kaydi_id, 'vardiya_id', v_vardiya::text,
                'Amir cevabı: vardiya önerisi onaylandı' || coalesce(' (' || p_aciklama || ')', ''),
                'amir', v_ben, p_soru_id => p_soru_id);
        end if;
        -- Sorudan sonra İK'nın düzelttiği saatin üzerine yazılmaz (T-40)
        if exists (select 1 from pdks.duzeltme d where d.gun_kaydi_id = v_soru.gun_kaydi_id and d.kaynak = 'ik'
                     and d.alan = 'giris_zamani' and d.yapilma_zamani >= v_soru.olusturma_zamani) then
            v_giris := null;
        end if;
        if exists (select 1 from pdks.duzeltme d where d.gun_kaydi_id = v_soru.gun_kaydi_id and d.kaynak = 'ik'
                     and d.alan = 'cikis_zamani' and d.yapilma_zamani >= v_soru.olusturma_zamani) then
            v_cikis := null;
        end if;
        perform pdks.saat_yaz(v_soru.gun_kaydi_id, v_giris, v_cikis,
                              'Amir cevabı: ' || pdks.soru_cevabi_adi(p_cevap) || coalesce(' (' || p_aciklama || ')', ''),
                              'amir', v_ben, p_soru_id => p_soru_id);
    end if;

    -- Değişen gün hemen hesaplanır (kilitli ayda yapılmaz; düzeltme orada fark satırı olur)
    perform pdks.gun_hesapla(v_soru.gun_kaydi_id);
end;
$$;
