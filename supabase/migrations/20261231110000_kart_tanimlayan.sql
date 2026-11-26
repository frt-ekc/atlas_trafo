-- =====================================================================
-- K6 · T-82: İK kendine asıl kart tanımlayabiliyordu; kartı kimin tanımladığı hiçbir yerde yazmıyordu
--
-- Sorun: İK müdürü, İK uzmanının kartını iptal etti; İK uzmanı kendine yeni bir asıl kart
-- tanımlayabildi. Kart, okutmanın kime yazılacağını belirler: kendine kart tanımlayan biri başkasının
-- elindeki kartın numarasını kendi adına kaydedip onun okutmalarını kendi günü gibi gösterebilir.
-- Kart satırında tanımlayan yoktu (iptal edenin aksine); bunu kimin yaptığı bulunamıyordu.
--
-- Düzeltme (rapor önerisi):
--   1. kart.tanimlayan_id: kart_tanimla oturumdaki İK kullanıcısını yazar. Eski kayıtlarda ve toplu
--      kurulum verisinde (seed) boştur; bu yüzden NOT NULL değil.
--   2. Görevler ayrılığı tetikleyicisi tanimlayan_id'ye de bakar: kimse kendine kart tanımlayamaz.
--   3. tanimlayan_id sonradan değiştirilemez (iptal yolu yalnızca iptal sütunlarını yazar).
-- Kalıcı test: supabase/tests/kart_tanimlayan_testi.sql
-- =====================================================================

alter table pdks.kart add column tanimlayan_id bigint references pdks.kullanici (id);
comment on column pdks.kart.tanimlayan_id is
    'Kartı tanımlayan İK kullanıcısı (kart_tanimla yazar; T-82). Eski kayıtlarda ve seed verisinde boş.';

-- Görevler ayrılığı: tanımlayan da kartın sahibi olamaz
drop trigger kart_gorev_ayriligi on pdks.kart;
create trigger kart_gorev_ayriligi
before insert or update on pdks.kart
for each row execute function pdks.kendi_kaydi_engelle('calisan', 'iptal_eden_id', 'tanimlayan_id');

-- Tanımlayan değiştirilemez
create function pdks.kart_tanimlayan_degismez()
returns trigger
language plpgsql
set search_path = pdks
as $$
begin
    if new.tanimlayan_id is distinct from old.tanimlayan_id then
        raise exception 'Kartı tanımlayan değiştirilemez.';
    end if;
    return new;
end;
$$;
revoke execute on function pdks.kart_tanimlayan_degismez() from public, anon, authenticated;

create trigger kart_tanimlayan_degismez
before update of tanimlayan_id on pdks.kart
for each row execute function pdks.kart_tanimlayan_degismez();

-- kart_tanimla (son hâli 20261119010000; yalnızca tanımlayan yazılıyor)
create or replace function pdks.kart_tanimla(p_calisan_id bigint, p_kart_no text)
returns bigint
language plpgsql
security definer
set search_path = pdks
as $$
declare
    v_ben bigint := pdks.yetki_gerekli('ik');
    v_id  bigint;
begin
    if exists (select 1 from pdks.kart where calisan_id = p_calisan_id and durum = 'aktif') then
        raise exception 'Çalışanın aktif kartı var; önce iptal edin.';
    end if;
    insert into pdks.kart (kart_no, calisan_id, tanimlayan_id) values (p_kart_no, p_calisan_id, v_ben)
    returning id into v_id;
    return v_id;
end;
$$;
