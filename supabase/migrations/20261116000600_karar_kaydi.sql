-- =====================================================================
-- 6: Karar kaydı ve itiraz ayrıntıları (amir / İK ekranları için)
--
-- duzeltme tablosu yalnızca saat / vardiya / durum değişikliklerini tutar.
-- "İK'ya gönderildi", "itiraz kaydedildi", "ham kayıt geçerli sayıldı" gibi
-- saat değiştirmeyen kararlar da silinemez bir yerde kim / ne zaman / eski /
-- yeni / gerekçe ile tutulmalı. İK ekranındaki "Denetim kaydı" bu tabloyu ve
-- duzeltme tablosunu birlikte gösterir.
--
-- Yalnızca ekleme yapar; mevcut tablo ve verilere dokunmaz.
-- =====================================================================

create table pdks.karar_kaydi (
    id             bigint generated always as identity primary key,
    zaman          timestamptz not null default now(),
    kullanici_id   bigint not null references pdks.kullanici (id),
    nesne_turu     text not null check (nesne_turu in ('amir_sorusu', 'itiraz')),
    nesne_id       bigint not null,
    islem          text not null,
    eski_deger     text,
    yeni_deger     text,
    gerekce        text not null check (length(trim(gerekce)) > 0)
);
create index karar_kaydi_nesne on pdks.karar_kaydi (nesne_turu, nesne_id);

comment on table pdks.karar_kaydi is
    'Saat değiştirmeyen kararların izi (İK''ya gönderme, itiraz kaydı/sonucu). Silinemez.';

-- Zaman sunucuda belirlenir; geriye tarihli kayıt yazılamaz
create or replace function pdks.karar_kaydi_hazirla()
returns trigger
language plpgsql
set search_path = pdks
as $$
begin
    new.zaman := now();
    if pdks.kullanici_rolu(new.kullanici_id) is null then
        raise exception 'Kararı veren kullanıcı bulunamadı ya da pasif.';
    end if;
    return new;
end;
$$;
create trigger karar_kaydi_hazirla before insert on pdks.karar_kaydi
    for each row execute function pdks.karar_kaydi_hazirla();

create trigger karar_kaydi_degistirilemez before update or delete on pdks.karar_kaydi
    for each row execute function pdks.degistirilemez();
create trigger karar_kaydi_bosaltilamaz before truncate on pdks.karar_kaydi
    for each statement execute function pdks.degistirilemez();

-- İtirazı İK, çalışan adına girer (sözlü / dilekçe / e-posta)
alter table pdks.itiraz
    add column konu text,
    add column basvuru_sekli text check (basvuru_sekli in ('sozlu', 'dilekce', 'eposta')),
    add column kaydeden_id bigint references pdks.kullanici (id);

-- Yetkiler: herkes okur, yalnızca uygulama ekler; değiştirme / silme yok
revoke all on pdks.karar_kaydi from public;
grant select on pdks.karar_kaydi to pdks_uygulama, pdks_gece_isi;
grant insert on pdks.karar_kaydi to pdks_uygulama;
revoke update, delete, truncate on pdks.karar_kaydi from pdks_uygulama, pdks_gece_isi;
grant execute on function pdks.karar_kaydi_hazirla() to pdks_uygulama;
revoke execute on function pdks.karar_kaydi_hazirla() from public;
