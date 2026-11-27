-- =====================================================================
-- T-07, T-34, T-84: Kalan küçük kurallar
--
-- T-07: v_izin_amir'in açıklaması yoktu. Bilinçli olarak RLS'i aşan bir görünümün neden böyle olduğu
--       veritabanında yazmalı (eşi v_saatlik_izin_amir'de var).
-- T-34: kayit_duzelt'te düzeltmeye başka çalışanın, başka günün ya da reddedilmiş bir itirazı
--       bağlanabiliyordu (yalnızca yabancı anahtar vardı). Ekran tarafı PR #40'ta düzeltilmişti.
-- T-84: Geçici kart zimmetine ileri tarihli veriliş ve iade yazılabiliyordu (sistem yolu: seed,
--       migration); kart ileri tarihe kadar kimseye verilemiyor, mesaj "çakışıyor" diyordu. Verilişten
--       önceki iade ham İngilizce aralık hatası veriyordu.
--
-- Düzeltme:
--   - v_izin_amir'e açıklama.
--   - duzeltme tablosunda yeni tetikleyici: bağlanan itiraz aynı gün kaydına ait olmalı ve reddedilmiş
--     olmamalı (duzeltme_hazirla'ya dokunulmadı; T-93'teki gibi ayrı tetikleyici).
--   - gecici_kart_zimmet'te yeni tetikleyici (çakışma kontrolünden önce çalışır, adı "a_" ile başlar):
--     veriliş en çok 5 dakika ileri; iade verilişten önce olamaz ve en çok 5 dakika ileri olabilir.
-- Kalıcı test: supabase/tests/kalan_kurallar_testi.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. T-07
-- ---------------------------------------------------------------------
comment on view pdks.v_izin_amir is
    'Amirin izin görünümü: izin türü gizlidir (yıllık / rapor / mazeret yerine yalnızca "izinli"). '
    'izin tablosunda tür ve açıklama İK bilgisidir; amir RLS ile izin tablosunu okuyamaz, bu görünüm '
    'yalnızca kendi bölümünün geçerli izinlerini tarih aralığıyla verir (owner yetkisiyle, amirin_calisani_mi süzgeci).';

-- ---------------------------------------------------------------------
-- 2. T-34: düzeltmeye bağlanan itiraz
-- ---------------------------------------------------------------------
create function pdks.duzeltme_itiraz_denetle()
returns trigger
language plpgsql
set search_path = pdks
as $$
declare
    v_itiraz pdks.itiraz;
begin
    if new.itiraz_id is null then
        return new;
    end if;
    select * into v_itiraz from pdks.itiraz where id = new.itiraz_id;
    if not found then
        raise exception 'Bağlanan itiraz bulunamadı.';
    end if;
    if v_itiraz.gun_kaydi_id <> new.gun_kaydi_id then
        raise exception 'Bağlanan itiraz (no %) bu güne ait değil; düzeltme yalnızca aynı günün itirazına bağlanır.', v_itiraz.id;
    end if;
    if v_itiraz.durum = 'red' then
        raise exception 'Bağlanan itiraz (no %) reddedilmiş; reddedilmiş itiraza düzeltme bağlanamaz.', v_itiraz.id;
    end if;
    return new;
end;
$$;
revoke execute on function pdks.duzeltme_itiraz_denetle() from public, anon, authenticated;

create trigger duzeltme_itiraz_denetle
before insert on pdks.duzeltme
for each row execute function pdks.duzeltme_itiraz_denetle();

-- ---------------------------------------------------------------------
-- 3. T-84: zimmet zamanları
-- ---------------------------------------------------------------------
create function pdks.gecici_kart_zimmet_zaman_denetle()
returns trigger
language plpgsql
set search_path = pdks
as $$
begin
    if new.verilis_zamani > now() + interval '5 minutes' then
        raise exception 'Zimmetin veriliş zamanı ileri olamaz (%).',
            to_char(new.verilis_zamani at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI');
    end if;
    if new.iade_zamani is not null then
        if new.iade_zamani < new.verilis_zamani then
            raise exception 'İade zamanı veriliş zamanından önce olamaz (veriliş %, iade %).',
                to_char(new.verilis_zamani at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI'),
                to_char(new.iade_zamani at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI');
        end if;
        if new.iade_zamani > now() + interval '5 minutes' then
            raise exception 'İade zamanı ileri olamaz (%).',
                to_char(new.iade_zamani at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI');
        end if;
    end if;
    return new;
end;
$$;
revoke execute on function pdks.gecici_kart_zimmet_zaman_denetle() from public, anon, authenticated;

-- Tetikleyiciler ada göre sırayla çalışır; çakışma kontrolünden (gecici_kart_zimmet_kontrol) önce
create trigger gecici_kart_zimmet_a_zaman
before insert or update on pdks.gecici_kart_zimmet
for each row execute function pdks.gecici_kart_zimmet_zaman_denetle();
