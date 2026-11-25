-- =====================================================================
-- K5 · T-49: Geriye dönük plan geçerli planın üstüne yazılıyordu; İK reddedince eski plan
-- geri gelmiyor, gün hiç işlenmiyordu
--
-- vardiya_plani_gir "on conflict do update" ile eski planın vardiyasını ve onay durumunu eziyordu;
-- eski plan hiçbir yerde tutulmuyordu. İK geriye dönük değişikliği reddedince plan "V2/reddedildi"
-- kalıyor, gerçek GÜNDÜZ planı kayboluyordu. Gece işi reddedilmiş planı kullanmadığı için çalışılan
-- gün hiç işlenmiyor, çalışan puantajda görünmüyordu. "Bu gün aslında hangi vardiyaydı, kim
-- değiştirdi?" sorusunun cevabı da kayboluyordu.
--
-- Karar (Yusuf, 25.11.2026; Fırat PR'da kontrol eder): plan geçmişi tablosu.
--   * vardiya_plani_gecmisi: plan her değiştiğinde ya da silindiğinde ESKİ hâli yazılır.
--     Yazma işini trigger yapar (hangi yoldan değişirse değişsin). Silinmez, değiştirilmez
--     (bolge_yetkisi_gecmisi ile aynı kalıp).
--   * vardiya_plani_onayla, ret: son GEÇERLİ plan (gerekmez / onaylandi) geçmişten geri yüklenir.
--     Gün onay beklediği için işlenmemişse hemen gece işinden geçer (onaydaki gibi).
--     Önceden plan yoksa geri yüklenecek bir şey yoktur; plan eskisi gibi "reddedildi" kalır.
--   * Okuma: İK / yönetici herkesi, amir kendi çalışanlarını görür (vardiya_plani ile aynı).
-- Onay dalı değişmez. Fonksiyonun imzası ve yetkisi aynı kalır.
-- Kalıcı test: supabase/tests/plan_gecmisi_testi.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Geçmiş tablosu
-- ---------------------------------------------------------------------
create table pdks.vardiya_plani_gecmisi (
    id              bigint generated always as identity primary key,
    plan_id         bigint not null,   -- planın kendisi sonradan silinebilir (işten çıkış); iz kalır
    calisan_id      bigint not null references pdks.calisan (id),
    tarih           date not null,
    vardiya_id      smallint not null references pdks.vardiya_tanim (id),
    geriye_donuk    boolean not null,
    ik_onay_durumu  text not null,
    giren_id        bigint references pdks.kullanici (id),
    giris_zamani    timestamptz not null,
    aciklama        text,
    islem           text not null check (islem in ('degisti', 'silindi')),
    kayit_zamani    timestamptz not null default now()
);
create index vardiya_plani_gecmisi_plan on pdks.vardiya_plani_gecmisi (plan_id, id);
create index vardiya_plani_gecmisi_calisan on pdks.vardiya_plani_gecmisi (calisan_id, tarih);
comment on table pdks.vardiya_plani_gecmisi is
    'Vardiya planının eski hâlleri: plan değişince ya da silinince önceki satır buraya yazılır (T-49). Silinmez, değiştirilmez.';

create trigger vardiya_plani_gecmisi_degistirilemez before update or delete on pdks.vardiya_plani_gecmisi
    for each row execute function pdks.degistirilemez();
create trigger vardiya_plani_gecmisi_bosaltilamaz before truncate on pdks.vardiya_plani_gecmisi
    for each statement execute function pdks.degistirilemez();

create function pdks.vardiya_plani_iz()
returns trigger
language plpgsql
set search_path = pdks
as $$
begin
    if tg_op = 'UPDATE'
       and (new.vardiya_id, new.geriye_donuk, new.ik_onay_durumu, new.giren_id, new.giris_zamani, new.aciklama)
           is not distinct from
           (old.vardiya_id, old.geriye_donuk, old.ik_onay_durumu, old.giren_id, old.giris_zamani, old.aciklama) then
        return new;
    end if;
    insert into pdks.vardiya_plani_gecmisi (plan_id, calisan_id, tarih, vardiya_id, geriye_donuk, ik_onay_durumu,
                                            giren_id, giris_zamani, aciklama, islem)
    values (old.id, old.calisan_id, old.tarih, old.vardiya_id, old.geriye_donuk, old.ik_onay_durumu,
            old.giren_id, old.giris_zamani, old.aciklama,
            case when tg_op = 'DELETE' then 'silindi' else 'degisti' end);
    return case when tg_op = 'DELETE' then old else new end;
end;
$$;
create trigger vardiya_plani_iz after update or delete on pdks.vardiya_plani
    for each row execute function pdks.vardiya_plani_iz();
revoke execute on function pdks.vardiya_plani_iz() from public, anon, authenticated;

alter table pdks.vardiya_plani_gecmisi enable row level security;
create policy ik_yonetici_okur on pdks.vardiya_plani_gecmisi for select to authenticated
    using ((select pdks.tum_veriyi_gorur()));
create policy amir_okur on pdks.vardiya_plani_gecmisi for select to authenticated
    using (calisan_id = any ((select pdks.oturum_calisanlari())::bigint[]));
grant select on pdks.vardiya_plani_gecmisi to authenticated;

-- ---------------------------------------------------------------------
-- 2. Ret son geçerli planı geri getirir
--    (20261224010000'daki fonksiyon; yalnızca ret dalı değişti, "T-49" satırları)
-- ---------------------------------------------------------------------
create or replace function pdks.vardiya_plani_onayla(p_plan_id bigint, p_onay boolean)
returns void
language plpgsql
security definer
set search_path = pdks
as $$
declare
    v_ben    bigint := pdks.yetki_gerekli('ik');
    v_plan   pdks.vardiya_plani;
    v_gun    pdks.gun_kaydi;
    v_onceki pdks.vardiya_plani_gecmisi;
begin
    select * into v_plan from pdks.vardiya_plani where id = p_plan_id for update;
    if not found or v_plan.ik_onay_durumu <> 'bekliyor' then
        raise exception 'Onay bekleyen plan bulunamadı.';
    end if;
    if v_plan.giren_id = v_ben then
        raise exception 'Görevler ayrılığı: kendi girdiğiniz planı onaylayamazsınız.';
    end if;
    -- kendi_kaydi_engelle ile aynı kural (planda onaylayan sütunu olmadığı için burada denetlenir)
    if pdks.kullanici_calisani(v_ben) = v_plan.calisan_id then
        raise exception 'Görevler ayrılığı: kimse kendi kaydında işlem yapamaz (vardiya_plani.onay).';
    end if;
    -- Plansız gün olarak havuzdan onaylanmış çalışma ayrıca plana göre sayılamaz (T-79)
    if p_onay and exists (select 1 from pdks.fazla_mesai_inceleme i join pdks.gun_kaydi g on g.id = i.gun_kaydi_id
                          where g.calisan_id = v_plan.calisan_id and g.is_gunu = v_plan.tarih
                            and g.vardiya_id is null and i.durum = 'onaylandi') then
        raise exception 'Bu günün plansız çalışması havuzdan onaylanmıştır; geriye dönük plan onaylanamaz.';
    end if;
    update pdks.vardiya_plani set ik_onay_durumu = case when p_onay then 'onaylandi' else 'reddedildi' end
    where id = p_plan_id;

    -- T-49: Ret geçerli plana döner. Reddedilen değişiklik geçmişte kalır (vardiya_plani_iz).
    if not p_onay then
        select * into v_onceki from pdks.vardiya_plani_gecmisi
        where plan_id = p_plan_id and islem = 'degisti' and ik_onay_durumu in ('gerekmez', 'onaylandi')
        order by id desc limit 1;
        if not found then
            return;   -- önceden geçerli plan yoktu: plan "reddedildi" kalır
        end if;
        update pdks.vardiya_plani
        set vardiya_id = v_onceki.vardiya_id, geriye_donuk = v_onceki.geriye_donuk,
            ik_onay_durumu = v_onceki.ik_onay_durumu, giren_id = v_onceki.giren_id,
            giris_zamani = v_onceki.giris_zamani, aciklama = v_onceki.aciklama
        where id = p_plan_id;
        -- Gün onay beklediği için işlenmemişse geri gelen plana göre şimdi işlenir
        if not exists (select 1 from pdks.gun_kaydi where calisan_id = v_plan.calisan_id and is_gunu = v_plan.tarih)
           and not pdks.donem_kilitli_mi(v_plan.tarih)
           and exists (select 1 from pdks.aktarim where kaynak = 'pdks' and veri_tarihi = v_plan.tarih) then
            perform pdks.gece_isi_calistir(v_plan.tarih);
        end if;
        return;
    end if;

    select * into v_gun from pdks.gun_kaydi where calisan_id = v_plan.calisan_id and is_gunu = v_plan.tarih;
    if found then
        -- Gün işlenmiş: vardiya düzeltmesi (kilitli ayda fark satırı olur) ve hemen hesap
        if v_gun.vardiya_id is distinct from v_plan.vardiya_id then
            perform pdks.duzeltme_uygula(v_gun.id, 'vardiya_id', v_plan.vardiya_id::text,
                'Geriye dönük vardiya planı onaylandı' || coalesce(' (' || v_plan.aciklama || ')', ''),
                'ik', v_ben);
        end if;
        if v_gun.vardiya_id is null and v_gun.durum = 'vardiya_yok' and v_gun.giris_zamani is not null then
            -- Plansız gün artık planlıdır: plana göre hesaplanır
            perform pdks.duzeltme_uygula(v_gun.id, 'durum', 'tamam', 'Geriye dönük vardiya planı onaylandı', 'ik', v_ben);
        end if;
        perform pdks.gun_hesapla(v_gun.id);
        if v_gun.vardiya_id is null then
            -- Plana göre havuzda süre kalmadıysa bekleyen kayıt kapanır (kalan varsa gun_hesapla güncelledi)
            update pdks.fazla_mesai_inceleme i
            set durum = 'reddedildi', karar_veren_id = v_ben,
                karar_aciklama = 'Geriye dönük vardiya planı onaylandı; süre plana göre hesaplandı'
            from pdks.gun_kaydi g
            where i.gun_kaydi_id = v_gun.id and g.id = v_gun.id and i.durum = 'inceleme_bekliyor'
              and (pdks.donem_kilitli_mi(g.is_gunu)
                   or (select h.onaysiz_fm_dk from pdks.gun_hesabi(g.calisan_id, g.is_gunu, g.planli_baslangic, g.planli_bitis,
                                                                   g.giris_zamani, g.cikis_zamani, g.vardiya_id) h)
                      <= pdks.ayar_al('fm_plansiz_esik_dk'));
        end if;
    elsif not pdks.donem_kilitli_mi(v_plan.tarih)
          and exists (select 1 from pdks.aktarim where kaynak = 'pdks' and veri_tarihi = v_plan.tarih) then
        -- Gün onay beklediği için işlenmemiş: o gün gece işinden yeniden geçer (var olan kayıtlar bozulmaz)
        perform pdks.gece_isi_calistir(v_plan.tarih);
    end if;
end;
$$;
