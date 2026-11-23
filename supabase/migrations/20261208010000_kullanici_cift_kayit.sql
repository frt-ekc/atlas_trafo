-- =====================================================================
-- T-105 · kullanici tablosundaki iki çift kayıt (normalizasyon)
--
-- 1) kullanici.izinli_mi kaldırıldı.
--    Amirin izinli olup olmadığı zaten izin tablosunda var. Bayrağı değiştiren
--    hiçbir ekran ya da fonksiyon yoktu; bu yüzden hep false kalıyor,
--    "amir izinliyse soru vekile gider" kuralı fiilen çalışmıyordu.
--    Artık soru_atanacak() izin tablosuna bakar: amirin çalışan kaydı için
--    bugün (İstanbul) iptal edilmemiş izin ya da rapor var mı?
--
-- 2) kullanici.ad_soyad artık calisan tablosundan gelir.
--    Kolon ekranların hızlı okuması için kalır, ama kaynağı calisan.ad / soyad'dır:
--      - kullanıcı eklenir ya da çalışan bağı değişirse ad çalışandan yazılır,
--      - çalışanın adı değişirse kullanıcı satırı da güncellenir.
--    kullanici_ekle artık ad soyad parametresi almaz.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Amir izinli mi? (izin tablosundan)
-- ---------------------------------------------------------------------
-- Kullanıcının çalışan kaydı için o gün iptal edilmemiş izin ya da rapor var mı?
-- Çalışana bağlı olmayan kullanıcı için false.
create function pdks.kullanici_izinli_mi(p_kullanici_id bigint, p_tarih date default pdks.bugun())
returns boolean
language sql
stable
security definer
set search_path = pdks
as $$
    select exists (
        select 1
        from pdks.kullanici k
        join pdks.izin i on i.calisan_id = k.calisan_id
        where k.id = p_kullanici_id
          and i.iptal_zamani is null
          and p_tarih between i.baslangic and i.bitis);
$$;

comment on function pdks.kullanici_izinli_mi(bigint, date) is
    'Kullanıcının çalışan kaydı için o gün iptal edilmemiş izin ya da rapor var mı (varsayılan: bugün, İstanbul).';

-- Çalışanın departman amiri; amir bugün izinliyse vekili; ikisi de yoksa İK
create or replace function pdks.soru_atanacak(p_calisan_id bigint)
returns bigint
language sql
stable
set search_path = pdks
as $$
    select coalesce(
        (select case when d.vekil_amir_id is not null and pdks.kullanici_izinli_mi(d.amir_id)
                     then d.vekil_amir_id else d.amir_id end
         from pdks.calisan c
         join pdks.departman d on d.id = c.departman_id
         where c.id = p_calisan_id),
        pdks.ik_sorumlusu(p_calisan_id));
$$;

alter table pdks.kullanici drop column izinli_mi;

-- ---------------------------------------------------------------------
-- 2. Ad soyad çalışan kaydından
-- ---------------------------------------------------------------------
-- Kullanıcı satırı yazılırken: çalışana bağlıysa ad soyad çalışandan alınır
create function pdks.kullanici_ad_soyad()
returns trigger
language plpgsql
set search_path = pdks
as $$
begin
    if new.calisan_id is not null then
        select c.ad || ' ' || c.soyad into new.ad_soyad
        from pdks.calisan c
        where c.id = new.calisan_id;
    end if;
    return new;
end;
$$;

create trigger kullanici_ad_soyad
    before insert or update of ad_soyad, calisan_id on pdks.kullanici
    for each row execute function pdks.kullanici_ad_soyad();

-- Çalışanın adı değişirse bağlı kullanıcı satırı da güncellenir
create function pdks.calisan_adi_degisti()
returns trigger
language plpgsql
set search_path = pdks
as $$
begin
    update pdks.kullanici k
    set ad_soyad = new.ad || ' ' || new.soyad
    where k.calisan_id = new.id;
    return null;
end;
$$;

create trigger calisan_adi_degisti
    after update of ad, soyad on pdks.calisan
    for each row
    when (old.ad is distinct from new.ad or old.soyad is distinct from new.soyad)
    execute function pdks.calisan_adi_degisti();

-- Var olan satırlar bir kez eşitlenir (trigger adı çalışandan yazar)
update pdks.kullanici k
set ad_soyad = c.ad || ' ' || c.soyad
from pdks.calisan c
where c.id = k.calisan_id
  and k.ad_soyad is distinct from c.ad || ' ' || c.soyad;

-- kullanici_ekle: ad soyad parametresi kalktı (adı çalışan kaydından gelir)
drop function pdks.kullanici_ekle(text, text, text, bigint, bigint);

-- Yeni kullanıcı (sisteme giren kişi) tanımlar. Ad soyad çalışan kaydından gelir.
-- Giriş hesabı Supabase Auth'ta aynı e-postayla açılır; hesap varsa hemen,
-- yoksa kullanici_guncelle çağrıldığında bağlanır.
create function pdks.kullanici_ekle(p_eposta text, p_rol text, p_calisan_id bigint,
                                    p_ust_amir_id bigint default null)
returns bigint
language plpgsql
security definer
set search_path = pdks
as $$
declare
    v_ben  bigint := pdks.yetki_gerekli('admin');
    v_id   bigint;
begin
    if p_eposta is null or p_eposta !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
        raise exception 'Geçerli bir e-posta yazılmalı.';
    end if;
    if p_rol not in ('amir', 'ik', 'guvenlik', 'yonetici', 'isg', 'admin') then
        raise exception 'Geçersiz rol: %', p_rol;
    end if;
    if not exists (select 1 from pdks.calisan where id = p_calisan_id and aktif) then
        raise exception 'Çalışan bulunamadı ya da aktif değil.';
    end if;
    if p_calisan_id = pdks.kullanici_calisani(v_ben) then
        raise exception 'Görevler ayrılığı: kendinize hesap açamazsınız.';
    end if;
    if exists (select 1 from pdks.kullanici where calisan_id = p_calisan_id) then
        raise exception 'Bu çalışanın zaten bir kullanıcı hesabı var.';
    end if;
    if exists (select 1 from pdks.kullanici where lower(eposta) = lower(trim(p_eposta))) then
        raise exception 'Bu e-posta başka bir kullanıcıda kayıtlı.';
    end if;
    if p_ust_amir_id is not null
       and not exists (select 1 from pdks.kullanici where id = p_ust_amir_id and aktif) then
        raise exception 'Üst amir bulunamadı ya da aktif değil.';
    end if;

    -- ad_soyad'ı kullanici_ad_soyad trigger'ı çalışan kaydından yazar
    insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, ust_amir_id)
    values ('', lower(trim(p_eposta)), p_rol, p_calisan_id, p_ust_amir_id)
    returning id into v_id;
    perform pdks.auth_hesabi_bagla(v_id);
    return v_id;
end;
$$;

-- ---------------------------------------------------------------------
-- 3. Yetkiler
-- ---------------------------------------------------------------------
revoke execute on function pdks.kullanici_izinli_mi(bigint, date) from public, anon, authenticated;
revoke execute on function pdks.kullanici_ad_soyad(), pdks.calisan_adi_degisti() from public, anon, authenticated;

revoke execute on function pdks.kullanici_ekle(text, text, bigint, bigint) from public, anon;
grant execute on function pdks.kullanici_ekle(text, text, bigint, bigint) to authenticated;
