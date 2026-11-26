-- =====================================================================
-- K3 · T-93: Kilitli ayda geriye dönük plan onayı fark satırına yalnızca kaybı yazıyordu
--
-- Sorun: Plan Gündüz (08–17), okutma 08:00–17:05. Amir "aslında Sabah (06–14)" planını girer;
-- plan İK onayı beklerken ay (zorla) kilitlenir, İK sonra onaylar. Kilitli günde gün kaydı
-- değişmez, vardiya düzeltmesi sonraki aya fark satırı olur: fark "geç kalma +120, çalışma −150"
-- yazar. Yeni vardiyanın dışında kalan 14:00–17:05 çalışma havuza düşmez, hiçbir yerde görünmez
-- (havuz kaydı yalnızca gün hesabında üretilir, kilitli günde hesap çalışmaz). Aynı onay açık
-- ayda bu 185 dk'yı fazla mesai incelemesine gönderiyordu. Çalışan aleyhine sonuç.
--
-- Karar (Yusuf): kilitli ayın vardiyası değişmez. Vardiya planı "o gün nasıl çalışılacaktı"
-- planıdır; ay kapandıktan sonra değiştirmek anlam taşımaz ve doğru hesaplanamaz. Kilitli günde
-- vardiya düzeltmesi reddedilir: plan onayı (bekleyen plan yalnızca reddedilebilir), İK kayıt
-- düzeltmesi ve amirin "vardiya uyuşmazlığı" cevabı. Saat, durum ve izin düzeltmeleri eskisi gibi
-- sonraki aya fark satırı olur (itiraz, kart unutma vb.).
-- Kilitli aya yeni plan girmek zaten reddediliyordu (vardiya_plani_gir); bu boşluk kilitten önce
-- girilip sonra onaylanan plandaydı.
-- Kural tablonun üstünde (duzeltme trigger'ı): vardiyayı değiştiren her yol aynı düzeltme satırını
-- yazdığı için tek yerde denetlenir.
-- Kalıcı test: supabase/tests/kilitli_vardiya_testi.sql
-- =====================================================================

create function pdks.kilitli_vardiya_engelle()
returns trigger
language plpgsql
set search_path = pdks
as $$
declare
    v_gun date;
begin
    if new.alan <> 'vardiya_id' then
        return new;
    end if;
    select is_gunu into v_gun from pdks.gun_kaydi where id = new.gun_kaydi_id;
    if pdks.donem_kilitli_mi(v_gun) then
        raise exception 'Kilitli ayda vardiya değiştirilemez (%). Bekleyen plan yalnızca reddedilebilir; giriş ya da çıkış saati yanlışsa kayıt düzeltmesiyle düzeltin.',
            to_char(v_gun, 'MM.YYYY');
    end if;
    return new;
end;
$$;

comment on function pdks.kilitli_vardiya_engelle() is
    'T-93: kilitli ayın gününe vardiya düzeltmesi yazılamaz (fark satırı yeni vardiyanın dışında kalan çalışmayı havuza taşıyamaz).';

revoke execute on function pdks.kilitli_vardiya_engelle() from public, anon, authenticated;

create trigger duzeltme_kilitli_vardiya before insert on pdks.duzeltme
    for each row execute function pdks.kilitli_vardiya_engelle();
