-- =====================================================================
-- K6 · T-72 (+ T-33): Admin tek başına İK / admin hesabı açabiliyor, rol verebiliyordu;
-- kullanıcı değişikliği iz bırakmıyordu
--
-- Karar: İK ya da admin rolü verme / yükseltme iki adımlıdır. Admin önerir, rolü 'ik' olan BAŞKA
-- bir kullanıcı onaylar; o zamana kadar hesap eski rolüyle (yeni hesapsa pasif) kalır.
--
-- Değişiklik:
--   * rol_onerisi: öneri ve karar (kim önerdi, kime, hangi rol, hangi çalışan, kim karar verdi).
--   * kullanici_gecmisi (T-33): hesap, rol, aktiflik, üst amir, çalışan bağı değişikliklerinin izi.
--   * kullanici_ekle / kullanici_guncelle: ayrıcalıklı rolde öneri açar. Bu roldeki pasif hesabı
--     yeniden açmak da öneridir (yoksa onay, pasif hesap açılarak atlanırdı).
--   * rol_onerisi_karar (İK): onaylar ya da gerekçeyle reddeder.
-- Veritabanı sahibinin doğrudan yazması (örnek veri, testler) bu kapsamda değildir; iz yine yazılır.
-- Kalıcı test: supabase/tests/rol_onayi_testi.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Rol önerisi
-- ---------------------------------------------------------------------
create table pdks.rol_onerisi (
    id              bigint generated always as identity primary key,
    kullanici_id    bigint not null references pdks.kullanici (id),
    calisan_id      bigint references pdks.calisan (id),
    eski_rol        text not null,
    yeni_rol        text not null check (yeni_rol in ('ik', 'admin')),
    aktif_yap       boolean not null,
    yeni_hesap      boolean not null,
    oneren_id       bigint not null references pdks.kullanici (id),
    oneri_zamani    timestamptz not null default now(),
    durum           text not null default 'bekliyor' check (durum in ('bekliyor', 'onaylandi', 'reddedildi', 'iptal')),
    karar_veren_id  bigint references pdks.kullanici (id),
    karar_zamani    timestamptz,
    karar_aciklama  text,
    check ((durum = 'bekliyor') = (karar_veren_id is null)),
    check ((durum = 'bekliyor') = (karar_zamani is null))
);
create unique index rol_onerisi_tek_bekleyen on pdks.rol_onerisi (kullanici_id) where durum = 'bekliyor';
comment on table pdks.rol_onerisi is
    'İK / admin rolü verme önerisi: admin önerir, başka bir İK kullanıcısı karar verir. Silinmez; karar değişmez (T-72).';

create function pdks.rol_onerisi_kontrol()
returns trigger
language plpgsql
set search_path = pdks
as $$
begin
    if tg_op = 'DELETE' then
        raise exception 'Rol önerisi silinemez.';
    end if;
    if tg_op = 'INSERT' then
        if new.durum <> 'bekliyor' then
            raise exception 'Yeni öneri "bekliyor" olarak girilir; kararı İK verir.';
        end if;
        if pdks.kullanici_rolu(new.oneren_id) is distinct from 'admin' then
            raise exception 'Rol değişikliğini yalnızca sistem yöneticisi önerir.';
        end if;
        new.oneri_zamani := now();
        return new;
    end if;
    if old.durum <> 'bekliyor' then
        raise exception 'Karara bağlanmış rol önerisi değiştirilemez.';
    end if;
    if (new.kullanici_id, new.calisan_id, new.eski_rol, new.yeni_rol, new.aktif_yap, new.yeni_hesap, new.oneren_id, new.oneri_zamani)
       is distinct from
       (old.kullanici_id, old.calisan_id, old.eski_rol, old.yeni_rol, old.aktif_yap, old.yeni_hesap, old.oneren_id, old.oneri_zamani) then
        raise exception 'Rol önerisinin içeriği değiştirilemez.';
    end if;
    if new.durum in ('onaylandi', 'reddedildi') then
        if pdks.kullanici_rolu(new.karar_veren_id) is distinct from 'ik' then
            raise exception 'Rol önerisine yalnızca İK karar verir.';
        end if;
        -- Öneren, hesabın sahibi ya da bunların çalışanına bağlı kimse karar veremez
        if new.karar_veren_id in (new.oneren_id, new.kullanici_id)
           or pdks.kullanici_calisani(new.karar_veren_id) in (new.calisan_id, pdks.kullanici_calisani(new.oneren_id)) then
            raise exception 'Görevler ayrılığı: kendi önerinize ya da kendi hesabınıza karar veremezsiniz.';
        end if;
    end if;
    new.karar_zamani := now();
    return new;
end;
$$;
create trigger rol_onerisi_kontrol before insert or update or delete on pdks.rol_onerisi
    for each row execute function pdks.rol_onerisi_kontrol();
create trigger rol_onerisi_bosaltilamaz before truncate on pdks.rol_onerisi
    for each statement execute function pdks.degistirilemez();

-- ---------------------------------------------------------------------
-- 2. Kullanıcı geçmişi (T-33)
-- ---------------------------------------------------------------------
create table pdks.kullanici_gecmisi (
    id              bigint generated always as identity primary key,
    kullanici_id    bigint not null,
    calisan_id      bigint,
    alan            text not null check (alan in ('hesap', 'rol', 'aktif', 'ust_amir_id', 'calisan_id', 'eposta')),
    eski_deger      text,
    yeni_deger      text,
    yapan_id        bigint references pdks.kullanici (id),
    rol_onerisi_id  bigint references pdks.rol_onerisi (id),
    zaman           timestamptz not null default now()
);
create index kullanici_gecmisi_kullanici on pdks.kullanici_gecmisi (kullanici_id, id);
comment on table pdks.kullanici_gecmisi is
    'Kullanıcı hesabı değişikliklerinin izi (kim, kime, hangi rol, hangi çalışan, ne zaman). Silinmez, değiştirilmez.';
comment on column pdks.kullanici_gecmisi.yapan_id is 'Oturumdaki kullanıcı; veritabanı sahibinin işleminde boştur.';

create trigger kullanici_gecmisi_degistirilemez before update or delete on pdks.kullanici_gecmisi
    for each row execute function pdks.degistirilemez();
create trigger kullanici_gecmisi_bosaltilamaz before truncate on pdks.kullanici_gecmisi
    for each statement execute function pdks.degistirilemez();

create function pdks.kullanici_iz()
returns trigger
language plpgsql
security definer
set search_path = pdks
as $$
declare
    v_eski  jsonb := case when tg_op = 'UPDATE' then to_jsonb(old) end;
    v_yeni  jsonb := to_jsonb(new);
begin
    insert into pdks.kullanici_gecmisi (kullanici_id, calisan_id, alan, eski_deger, yeni_deger, yapan_id, rol_onerisi_id)
    select new.id, new.calisan_id, a.alan, v_eski ->> a.alan,
           case when a.alan = 'hesap' then 'açıldı' else v_yeni ->> a.alan end,
           pdks.oturum_kullanici_id(), nullif(current_setting('pdks.rol_onerisi', true), '')::bigint
    from unnest(array['hesap', 'rol', 'aktif', 'ust_amir_id', 'calisan_id', 'eposta']) with ordinality a(alan, sira)
    where (tg_op = 'INSERT' and (a.alan = 'hesap' or v_yeni ->> a.alan is not null))
       or (tg_op = 'UPDATE' and v_eski ->> a.alan is distinct from v_yeni ->> a.alan)
    order by a.sira;
    return null;
end;
$$;
create trigger kullanici_iz after insert or update on pdks.kullanici
    for each row execute function pdks.kullanici_iz();

-- Bu migration'dan önce açılmış hesaplar: kimin açtığı bilinmiyor
insert into pdks.kullanici_gecmisi (kullanici_id, calisan_id, alan, yeni_deger, zaman)
select k.id, k.calisan_id, x.alan, x.deger, k.olusturma_zamani
from pdks.kullanici k
cross join lateral (values ('hesap', 'açıldı'), ('rol', k.rol), ('aktif', k.aktif::text)) x(alan, deger)
order by k.id;

-- ---------------------------------------------------------------------
-- 3. Öneri açan ekran fonksiyonları (admin)
-- ---------------------------------------------------------------------
create or replace function pdks.kullanici_ekle(p_eposta text, p_rol text, p_calisan_id bigint, p_ust_amir_id bigint default null)
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
    -- Ayrıcalıklı rol (ik, admin): hesap İK onayına kadar pasif kalır (T-72)
    insert into pdks.kullanici (ad_soyad, eposta, rol, calisan_id, ust_amir_id, aktif)
    values ('', lower(trim(p_eposta)), p_rol, p_calisan_id, p_ust_amir_id, p_rol not in ('ik', 'admin'))
    returning id into v_id;
    if p_rol in ('ik', 'admin') then
        insert into pdks.rol_onerisi (kullanici_id, calisan_id, eski_rol, yeni_rol, aktif_yap, yeni_hesap, oneren_id)
        values (v_id, p_calisan_id, p_rol, p_rol, true, true, v_ben);
    end if;
    perform pdks.auth_hesabi_bagla(v_id);
    return v_id;
end;
$$;

create or replace function pdks.kullanici_guncelle(p_kullanici_id bigint, p_rol text default null, p_ust_amir_id bigint default null, p_aktif boolean default null)
returns void
language plpgsql
security definer
set search_path = pdks
as $$
declare
    v_ben  bigint := pdks.yetki_gerekli('admin');
    v_c    pdks.calisan;
    v_k    pdks.kullanici;
    v_rol  text;
    v_aktif boolean;
begin
    if p_kullanici_id = v_ben then
        raise exception 'Görevler ayrılığı: kendi hesabınızı değiştiremezsiniz.';
    end if;
    select * into v_k from pdks.kullanici where id = p_kullanici_id for update;
    if not found then
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

    v_rol   := coalesce(p_rol, v_k.rol);
    v_aktif := coalesce(p_aktif, v_k.aktif);

    -- Ayrıcalıklı rol (ik, admin) verme ya da bu roldeki pasif hesabı açma iki adımlıdır (T-72):
    -- admin önerir, İK onaylar; o zamana kadar rol ve aktiflik eski hâlinde kalır
    if v_rol in ('ik', 'admin') and (v_rol <> v_k.rol or (v_aktif and not v_k.aktif)) then
        if exists (select 1 from pdks.rol_onerisi where kullanici_id = p_kullanici_id and durum = 'bekliyor') then
            raise exception 'Bu hesap için onay bekleyen bir rol değişikliği vardır.';
        end if;
        insert into pdks.rol_onerisi (kullanici_id, calisan_id, eski_rol, yeni_rol, aktif_yap, yeni_hesap, oneren_id)
        values (p_kullanici_id, v_k.calisan_id, v_k.rol, v_rol, v_aktif and not v_k.aktif, false, v_ben);
        v_rol   := v_k.rol;
        v_aktif := v_aktif and v_k.aktif;   -- pasife alma hemen geçerlidir
    elsif v_rol <> v_k.rol or (v_k.aktif and not v_aktif) then
        -- Başka role geçen ya da pasife alınan hesabın bekleyen önerisi geçersizdir
        update pdks.rol_onerisi
        set durum = 'iptal', karar_veren_id = v_ben, karar_aciklama = 'Hesabın rolü ya da durumu değiştirildi'
        where kullanici_id = p_kullanici_id and durum = 'bekliyor';
    end if;

    update pdks.kullanici
    set rol         = v_rol,
        ust_amir_id = coalesce(p_ust_amir_id, ust_amir_id),
        aktif       = v_aktif
    where id = p_kullanici_id;
    perform pdks.auth_hesabi_bagla(p_kullanici_id);
end;
$$;

-- ---------------------------------------------------------------------
-- 4. Karar (İK)
-- ---------------------------------------------------------------------
create function pdks.rol_onerisi_karar(p_oneri_id bigint, p_onay boolean, p_aciklama text default null)
returns void
language plpgsql
security definer
set search_path = pdks
as $$
declare
    v_ben  bigint := pdks.yetki_gerekli('ik');
    v_o    pdks.rol_onerisi;
    v_k    pdks.kullanici;
begin
    -- Önce hesap kilitlenir (kullanici_guncelle ile aynı sıra)
    select k.* into v_k from pdks.kullanici k
    where k.id = (select kullanici_id from pdks.rol_onerisi where id = p_oneri_id) for update;
    select * into v_o from pdks.rol_onerisi where id = p_oneri_id for update;
    if v_o.id is null or v_o.durum <> 'bekliyor' then
        raise exception 'Onay bekleyen rol değişikliği bulunamadı.';
    end if;
    if p_onay is null then
        raise exception 'Karar (onay / ret) belirtilmelidir.';
    end if;
    if not p_onay and (p_aciklama is null or length(trim(p_aciklama)) < 5) then
        raise exception 'Ret gerekçesi girilmelidir (en az 5 karakter).';
    end if;

    update pdks.rol_onerisi
    set durum = case when p_onay then 'onaylandi' else 'reddedildi' end,
        karar_veren_id = v_ben, karar_aciklama = nullif(trim(p_aciklama), '')
    where id = p_oneri_id;
    if not p_onay then
        return;
    end if;

    if not exists (select 1 from pdks.calisan where id = v_k.calisan_id and aktif) then
        raise exception 'Çalışan işten ayrılmış; rol değişikliği onaylanamaz.';
    end if;
    if v_k.rol <> v_o.eski_rol or v_k.calisan_id is distinct from v_o.calisan_id then
        raise exception 'Hesap öneriden sonra değiştirilmiş; öneri onaylanamaz.';
    end if;
    perform set_config('pdks.rol_onerisi', p_oneri_id::text, true);
    update pdks.kullanici set rol = v_o.yeni_rol, aktif = aktif or v_o.aktif_yap where id = v_k.id;
    perform set_config('pdks.rol_onerisi', '', true);
end;
$$;

-- ---------------------------------------------------------------------
-- 5. RLS ve yetkiler
-- ---------------------------------------------------------------------
alter table pdks.rol_onerisi       enable row level security;
alter table pdks.kullanici_gecmisi enable row level security;
create policy ik_yonetici_okur on pdks.rol_onerisi for select to authenticated using ((select pdks.tum_veriyi_gorur()));
create policy admin_okur       on pdks.rol_onerisi for select to authenticated using ((select pdks.oturum_rolu()) = 'admin');
create policy ik_yonetici_okur on pdks.kullanici_gecmisi for select to authenticated using ((select pdks.tum_veriyi_gorur()));
create policy admin_okur       on pdks.kullanici_gecmisi for select to authenticated using ((select pdks.oturum_rolu()) = 'admin');
grant select on pdks.rol_onerisi, pdks.kullanici_gecmisi to authenticated;

revoke execute on function pdks.rol_onerisi_kontrol(), pdks.kullanici_iz() from public, anon, authenticated;
revoke execute on function pdks.rol_onerisi_karar(bigint, boolean, text) from public, anon;
grant execute on function pdks.rol_onerisi_karar(bigint, boolean, text) to authenticated;
