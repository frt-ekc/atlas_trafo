-- =====================================================================
-- Durum düzeltmesi: son duruma geçen günün dakikaları temizlenir, hesap kapanır
--
-- Kod incelemesinde çıkan iki sorun (ikisi de duzeltme_uygula'nın 'durum' dalında):
--   1. Hesaplanmış gün (ör. tamam, 480 dk) İK kararıyla devamsız / izinli / raporlu /
--      tatil / vardiya yok yapılınca yalnızca durum değişiyordu; çalışma, fazla mesai,
--      gece vb. dakikalar eski hâliyle kalıyordu. v_puantaj_canli dakikaları durumdan
--      bağımsız topladığı için devamsız gün çalışılmış gibi dakika getiriyor, kilitte de
--      puantaj_satiri'na ve ERP aktarımına geçiyordu.
--   2. Aynı düzeltme hesap_tamam = false bırakıyordu. gun_hesapla bu durumları hiç
--      hesaplamadığı için işaret bir daha true olmuyor, gün puantajda ay boyunca
--      "bekleyen gün" sayılıyordu.
-- Çözüm: gün bu "son" durumlardan birine geçerse dakika alanları boşaltılır (gece işinin
-- izinli / tatil gün için açtığı kayıtla aynı) ve hesap_tamam = true olur. Diğer durumlar
-- (tamam, eksik, soru bekliyor, devamsızlık şüphesi) eskisi gibi yeniden hesaba bırakılır.
-- Kilitli ayda değişiklik yok: düzeltme yine yalnızca fark satırı olur (gun_katkisi bu
-- durumlarda dakikayı zaten 0 sayar).
-- Fonksiyonun geri kalanı 20261124010000_vardiya_kurallari.sql ile aynı.
-- =====================================================================

create or replace function pdks.duzeltme_uygula(
    p_gun_kaydi_id   bigint,
    p_alan           text,
    p_yeni_deger     text,
    p_gerekce        text,
    p_kaynak         text,
    p_yapan_id       bigint  default null,
    p_kanit_kaydi_id bigint  default null,
    p_izin_id        bigint  default null,
    p_ariza_id       bigint  default null,
    p_soru_id        bigint  default null,
    p_itiraz_id      bigint  default null,
    p_aleyhine       boolean default false
)
returns bigint
language plpgsql
set search_path = pdks
as $$
declare
    v_gun   pdks.gun_kaydi;
    v_eski  text;
    v_id    bigint;
    v_fark  boolean;
    v_kayn  text := case when p_kaynak = 'gece_isi' then 'kanit' else p_kaynak end;
    v_ara   record;
begin
    select * into v_gun from pdks.gun_kaydi where id = p_gun_kaydi_id for update;
    if not found then
        raise exception 'Günlük kayıt bulunamadı: %', p_gun_kaydi_id;
    end if;

    v_eski := case p_alan
                when 'giris_zamani' then v_gun.giris_zamani::text
                when 'cikis_zamani' then v_gun.cikis_zamani::text
                when 'vardiya_id'   then v_gun.vardiya_id::text
                when 'durum'        then v_gun.durum
              end;

    p_yeni_deger := case p_alan
                when 'giris_zamani' then p_yeni_deger::timestamptz::text
                when 'cikis_zamani' then p_yeni_deger::timestamptz::text
                when 'vardiya_id'   then p_yeni_deger::smallint::text
                else p_yeni_deger
              end;

    insert into pdks.duzeltme (gun_kaydi_id, calisan_id, is_gunu, alan, eski_deger, yeni_deger,
                               gerekce, kaynak, yapan_id, calisan_aleyhine,
                               kanit_kaydi_id, izin_id, ariza_id, soru_id, itiraz_id, hedef_donem_id)
    values (p_gun_kaydi_id, v_gun.calisan_id, v_gun.is_gunu, p_alan, v_eski, p_yeni_deger,
            p_gerekce, p_kaynak, p_yapan_id, p_aleyhine,
            p_kanit_kaydi_id, p_izin_id, p_ariza_id, p_soru_id, p_itiraz_id, 0)
    returning id, fark_satiri into v_id, v_fark;

    if v_fark then
        return v_id;
    end if;

    perform set_config('pdks.duzeltme_id', v_id::text, true);
    case p_alan
        when 'giris_zamani' then
            update pdks.gun_kaydi set giris_zamani = p_yeni_deger::timestamptz, giris_kaynagi = v_kayn,
                                      hesap_tamam = false where id = p_gun_kaydi_id;
        when 'cikis_zamani' then
            update pdks.gun_kaydi set cikis_zamani = p_yeni_deger::timestamptz, cikis_kaynagi = v_kayn,
                                      hesap_tamam = false where id = p_gun_kaydi_id;
        when 'vardiya_id' then
            select * into v_ara from pdks.vardiya_araligi(p_yeni_deger::smallint, v_gun.is_gunu);
            update pdks.gun_kaydi set vardiya_id = p_yeni_deger::smallint,
                                      planli_baslangic = v_ara.p_bas, planli_bitis = v_ara.p_bit,
                                      hesap_tamam = false
            where id = p_gun_kaydi_id;
        when 'durum' then
            if p_yeni_deger in ('devamsiz', 'izinli', 'raporlu', 'tatil', 'vardiya_yok') then
                -- Son durum: hesaplanacak bir şey yok. Eski dakikalar temizlenir, hesap kapanır.
                update pdks.gun_kaydi
                set durum           = p_yeni_deger,
                    gec_kalma_dk    = null,
                    erken_cikis_dk  = null,
                    calisma_dk      = null,
                    fazla_mesai_dk  = null,
                    fm50_dk         = null,
                    fm100_dk        = null,
                    gece_calisma_dk = null,
                    saatlik_izin_dk = null,
                    mola_dk         = null,
                    hesap_tamam     = true
                where id = p_gun_kaydi_id;
            else
                update pdks.gun_kaydi set durum = p_yeni_deger, hesap_tamam = false where id = p_gun_kaydi_id;
            end if;
    end case;
    perform set_config('pdks.duzeltme_id', '', true);
    return v_id;
end;
$$;
