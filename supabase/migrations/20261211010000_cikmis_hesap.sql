-- =====================================================================
-- K6 · T-71: Çıkmış çalışanın hesabı admin tarafından yeniden açılabiliyordu;
-- hesap tam yetkiyle çalışıyordu
--
-- İşten çıkış (isten_cikis_gir) çalışanı ve hesabını pasif yapıyor. Ama
-- kullanici_guncelle(p_aktif => true) çalışanın işten ayrılıp ayrılmadığına
-- bakmıyordu; oturum_kullanici_id de yalnızca kullanici.aktif'e bakıyordu. Ayrılmış
-- bir İK çalışanı, hesabı yeniden açılınca bütün çalışanların kayıtlarını görebiliyor
-- ve değiştirebiliyordu. (kullanici_ekle ise çıkmış çalışana yeni hesabı zaten
-- reddediyordu.)
--
-- Değişiklik (iki kat koruma):
--   * kullanici_guncelle: p_aktif = true iken bağlı çalışan aktif değilse ret:
--     "Çalışan işten ayrılmış (çıkış: 14.10.2026); hesabı yeniden açılamaz."
--   * oturum_kullanici_id: hesap aktif olsa bile bağlı çalışan aktif değilse oturum
--     yoktur (bütün yetki fonksiyonları ve RLS buradan geçer).
--   * Temizlik: çalışanı aktif olmayan ama hesabı açık kalmış kayıt varsa kapatılır.
--   Fonksiyonların geri kalanı son sürümle (pg_get_functiondef) birebir aynıdır;
--   yetkiler korunur.
-- Kapsam dışı: hesabı kimin ne zaman açtığının izi (kullanici_gecmisi) T-33 / T-72 ile.
-- Kalıcı test: supabase/tests/cikmis_hesap_testi.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Oturum: bağlı çalışan da aktif olmalı
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pdks.oturum_kullanici_id()
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pdks'
AS $function$
    select k.id
    from pdks.kullanici k
    join pdks.calisan c on c.id = k.calisan_id and c.aktif   -- işten ayrılan çalışanın oturumu yok (T-71)
    where k.auth_kullanici_id = auth.uid()
      and k.aktif;
$function$;

-- ---------------------------------------------------------------------
-- 2. kullanici_guncelle: işten ayrılmış çalışanın hesabı açılamaz
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pdks.kullanici_guncelle(p_kullanici_id bigint, p_rol text DEFAULT NULL::text, p_ust_amir_id bigint DEFAULT NULL::bigint, p_aktif boolean DEFAULT NULL::boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pdks'
AS $function$
declare
    v_ben  bigint := pdks.yetki_gerekli('admin');
    v_c    pdks.calisan;
begin
    if p_kullanici_id = v_ben then
        raise exception 'Görevler ayrılığı: kendi hesabınızı değiştiremezsiniz.';
    end if;
    if not exists (select 1 from pdks.kullanici where id = p_kullanici_id) then
        raise exception 'Kullanıcı bulunamadı.';
    end if;
    -- İşten ayrılmış çalışanın hesabı yeniden açılamaz (T-71; kullanici_ekle ile aynı kural)
    if p_aktif then
        select c.* into v_c
        from pdks.calisan c join pdks.kullanici k on k.calisan_id = c.id
        where k.id = p_kullanici_id;
        if not found or not v_c.aktif then
            raise exception 'Çalışan işten ayrılmış%; hesabı yeniden açılamaz.',
                coalesce(' (çıkış: ' || to_char(v_c.isten_cikis_tarihi, 'DD.MM.YYYY') || ')', '');
        end if;
    end if;
    if p_rol is not null and p_rol not in ('amir', 'ik', 'guvenlik', 'yonetici', 'isg', 'admin') then
        raise exception 'Geçersiz rol: %', p_rol;
    end if;
    if p_ust_amir_id is not null then
        if p_ust_amir_id = p_kullanici_id then
            raise exception 'Kullanıcı kendisinin üst amiri olamaz.';
        end if;
        if not exists (select 1 from pdks.kullanici where id = p_ust_amir_id and aktif) then
            raise exception 'Üst amir bulunamadı ya da aktif değil.';
        end if;
    end if;

    update pdks.kullanici
    set rol         = coalesce(p_rol, rol),
        ust_amir_id = coalesce(p_ust_amir_id, ust_amir_id),
        aktif       = coalesce(p_aktif, aktif)
    where id = p_kullanici_id;
    perform pdks.auth_hesabi_bagla(p_kullanici_id);
end;
$function$;

-- ---------------------------------------------------------------------
-- 3. Temizlik: çalışanı ayrılmış ama hesabı açık kalmış kayıt kapatılır
-- ---------------------------------------------------------------------
update pdks.kullanici k
set aktif = false
from pdks.calisan c
where c.id = k.calisan_id and k.aktif and not c.aktif;
