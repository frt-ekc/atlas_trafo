-- =====================================================================
-- K2 · T-41: Tek saatli cevap günü askıda bırakıyordu
--
-- Sorun: soru_cevapla ve soru_ik_karari "giriş ya da çıkış" saatinden birini yeterli sayıyordu.
-- Amir "giriş yok" sorusuna yalnızca çıkışı yazınca soru kapanıyor, günde giriş yine yok: gün
-- hesaplanamıyor ("soru_bekliyor" kalıyor), açık soru da kalmadığı için kimse fark etmiyor, ay
-- sonunda puantaja kodsuz giriyordu. İK'nın "geldi" kararında da aynısı. Ekran soru türüne göre
-- zorunlu saati istiyor (feature/53-t41-t11-ekran), ama "kanıt vardiya sonrası", "arıza kanıtı
-- yok" ve "vardiya uyuşmazlığı" türlerinde tek saati kabul ediyor; veritabanı hiç denetlemiyordu.
--
-- Karar (Yusuf, 1. yol): kural soru türüne değil sonuca bakar. Cevap ya da "geldi" kararı
-- uygulandığında günde hem giriş hem çıkış olmalı; biri eksik kalacaksa reddedilir, mesaj eksik
-- saati söyler, soru açık kalır. Saati gündeki mevcut değer (PDKS, kanıt, İK düzeltmesi) de
-- tamamlayabilir: "giriş yok" sorusunda çıkış PDKS'ten varsa yalnızca giriş yeter.
-- "Gelmedi" / "bilmiyorum" cevabı ve İK'nın "devamsız" kararı saat istemez.
-- Kilitli ayda gün kaydı değişmez, saat fark satırına yazılır: kural son fark satırındaki saati
-- de sayar.
-- Ekran değişmedi: veritabanının mesajı cevap penceresinde hata olarak görünür.
-- Kalıcı test: supabase/tests/eksik_saat_reddi_testi.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Ortak kontrol: cevap uygulanınca günde giriş ve çıkış olacak mı?
--    p_giris / p_cikis: cevabın yazacağı saatler (yoksa null). p_ipucu: mesaja eklenecek yol
--    (amirin "saat doğru" cevabında "Saat farklı" seçmesi gerektiğini söyler).
-- ---------------------------------------------------------------------
create function pdks.cevap_saatleri_denetle(p_gun_kaydi_id bigint, p_giris timestamptz, p_cikis timestamptz, p_ipucu text default null)
returns void
language plpgsql
stable
set search_path = pdks
as $$
declare
    v_gun    pdks.gun_kaydi;
    v_giris  timestamptz;
    v_cikis  timestamptz;
    v_eksik  text;
    v_hedef  text;
begin
    select * into v_gun from pdks.gun_kaydi where id = p_gun_kaydi_id;
    -- Geçerli saat: cevabın yazacağı, yoksa kilitli aydaki son fark satırı, yoksa gün kaydı
    v_giris := coalesce(p_giris,
        (select d.yeni_deger::timestamptz from pdks.duzeltme d
         where d.gun_kaydi_id = p_gun_kaydi_id and d.alan = 'giris_zamani' and d.fark_satiri
         order by d.id desc limit 1),
        v_gun.giris_zamani);
    v_cikis := coalesce(p_cikis,
        (select d.yeni_deger::timestamptz from pdks.duzeltme d
         where d.gun_kaydi_id = p_gun_kaydi_id and d.alan = 'cikis_zamani' and d.fark_satiri
         order by d.id desc limit 1),
        v_gun.cikis_zamani);

    if v_giris is null and v_cikis is null then
        v_eksik := 'giriş ve çıkış saati';
        v_hedef := 'iki saati';
    elsif v_giris is null then
        v_eksik := 'giriş saati';
        v_hedef := 'giriş saatini';
    elsif v_cikis is null then
        v_eksik := 'çıkış saati';
        v_hedef := 'çıkış saatini';
    else
        return;
    end if;
    raise exception 'Günde % yok; % de girin.', v_eksik, coalesce(p_ipucu || ' ', '') || v_hedef;
end;
$$;

comment on function pdks.cevap_saatleri_denetle(bigint, timestamptz, timestamptz, text) is
    'T-41: amirin cevabı ya da İK''nın "geldi" kararı uygulanınca günde giriş ve çıkış kalmayacaksa hata verir.';

revoke execute on function pdks.cevap_saatleri_denetle(bigint, timestamptz, timestamptz, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 2. Amirin cevabı
-- ---------------------------------------------------------------------
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
        -- T-41: cevaptan sonra günde giriş ve çıkış olmalı; yoksa cevap reddedilir, soru açık kalır
        perform pdks.cevap_saatleri_denetle(v_soru.gun_kaydi_id, v_giris, v_cikis,
            case when p_cevap in ('geldi_saat_dogru', 'kart_unuttu') and p_giris is null and p_cikis is null
                 then '"Saat farklı" seçip' end);
        perform pdks.saat_yaz(v_soru.gun_kaydi_id, v_giris, v_cikis,
                              'Amir cevabı: ' || pdks.soru_cevabi_adi(p_cevap) || coalesce(' (' || p_aciklama || ')', ''),
                              'amir', v_ben, p_soru_id => p_soru_id);
    end if;

    -- Değişen gün hemen hesaplanır (kilitli ayda yapılmaz; düzeltme orada fark satırı olur)
    perform pdks.gun_hesapla(v_soru.gun_kaydi_id);
end;
$$;

-- ---------------------------------------------------------------------
-- 3. İK kararı (T-32'deki hâli; yalnızca "geldi" yoluna kontrol eklendi)
-- ---------------------------------------------------------------------
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

    -- T-32: amirin cevabı (cevaplayan, cevap, zamanı) olduğu gibi kalır; İK'nın kararı ayrı sütunlarda
    update pdks.amir_sorusu
    set durum = 'kapandi', ik_karar_veren_id = v_ben, ik_karar_zamani = now(),
        -- Yalnızca sonuç: gerekçe, amirin okuyamadığı duzeltme satırındadır (T-106)
        ik_karari = case when p_devamsiz then 'devamsiz' else 'geldi' end
    where id = p_soru_id;

    if p_devamsiz then
        perform pdks.duzeltme_uygula(v_soru.gun_kaydi_id, 'durum', 'devamsiz', p_gerekce, 'ik', v_ben,
                                     p_soru_id => p_soru_id, p_aleyhine => true);
    else
        -- T-41: "geldi" kararından sonra günde giriş ve çıkış olmalı
        perform pdks.cevap_saatleri_denetle(v_soru.gun_kaydi_id, p_giris, p_cikis);
        perform pdks.saat_yaz(v_soru.gun_kaydi_id, p_giris, p_cikis, p_gerekce, 'ik', v_ben, p_soru_id => p_soru_id);
    end if;

    -- Değişen gün hemen hesaplanır (kilitli ayda yapılmaz; düzeltme orada fark satırı olur)
    perform pdks.gun_hesapla(v_soru.gun_kaydi_id);
end;
$$;
