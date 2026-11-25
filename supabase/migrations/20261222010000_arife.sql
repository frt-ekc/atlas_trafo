-- =====================================================================
-- K10 · T-28: Yarım gün arife tam iş günü sayılıyordu
--
-- Karar: Arifede çalışma 13:00'te biter. 13:00'ten sonraki erken çıkış sayılmaz; 13:00'ten sonraki
-- çalışma FM100'dür (yazılı onay ve havuz kuralları Pazar / tatildeki gibi; T-56, T-57).
--
-- Değişiklik:
--   * resmi_tatil.yarim_gun zaten vardı; 2026 ve 2027 arifeleri tamamlandı.
--   * arife_siniri(gün): 13:00. vardiya_araligi arifede 13:00'te biter (planlı bitiş);
--     okutma penceresi vardiyanın tanımdaki aralığıyla kalır (vardiya_ham_araligi).
--   * gun_hesabi: 13:00 sonrası FM100. Vardiya içi kısım yazılı onayla doğrudan, onaysızsa havuzdan;
--     vardiya bitişinden sonrası onaylı plan / havuz kadar.
--   * Arifede 13:00'te ya da sonra başlayan vardiyaya (14-22, 22-06) gelmeyen: "tatil", soru açılmaz.
--     Çalışırsa vardiyanın tamamı FM100 (gün türü is_gunu'ya göredir).
--   * Puantaj kodu: NÇ ve FM100 birlikte. Esnek mesaide arife hedefi yarım; FM100 hedefe sayılmaz.
--   * Yıllık toplamda (T-57) arife de tatil gibi sayılır.
-- Kilitli aylar ve işlenmiş günler kendiliğinden yeniden hesaplanmaz.
-- Kalıcı test: supabase/tests/arife_testi.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Arifeler (2027 tarihleri: Diyanet takvimi)
-- ---------------------------------------------------------------------
insert into pdks.resmi_tatil (tarih, ad, yarim_gun) values
    ('2026-03-19', 'Ramazan Bayramı arifesi',    true),
    ('2026-05-26', 'Kurban Bayramı arifesi',     true),
    ('2026-10-28', 'Cumhuriyet Bayramı arifesi', true),
    ('2027-03-08', 'Ramazan Bayramı arifesi',    true),
    ('2027-05-15', 'Kurban Bayramı arifesi',     true),
    ('2027-10-28', 'Cumhuriyet Bayramı arifesi', true)
on conflict (tarih) do nothing;

-- ---------------------------------------------------------------------
-- 2. Arife sınırı ve vardiya aralığı
-- ---------------------------------------------------------------------
-- Arife günü 13:00 (İstanbul); arife değilse null. Pazar ya da tam tatil olan arife tam tatil sayılır.
create function pdks.arife_siniri(p_gun date)
returns timestamptz
language sql
stable
set search_path = pdks
as $$
    select (p_gun + time '13:00') at time zone 'Europe/Istanbul'
    where exists (select 1 from pdks.resmi_tatil where tarih = p_gun and yarim_gun)
      and not pdks.fm100_gunu_mu(p_gun);
$$;
comment on function pdks.arife_siniri(date) is 'Arife günü çalışmanın bittiği an (13:00); arife değilse null.';

-- Vardiyanın tanımdaki aralığı. Okutma penceresi bununla kurulur: arifede de 17:00 çıkışı aranmalı
create function pdks.vardiya_ham_araligi(p_vardiya_id smallint, p_is_gunu date, out p_bas timestamptz, out p_bit timestamptz)
returns record
language sql
stable
set search_path = pdks
as $$
    select (p_is_gunu + baslangic) at time zone 'Europe/Istanbul',
           (p_is_gunu + case when gece_yarisini_asar then 1 else 0 end + bitis) at time zone 'Europe/Istanbul'
    from pdks.vardiya_tanim where id = p_vardiya_id;
$$;

-- Planlı aralık: arifede 13:00'ü aşan vardiya 13:00'te biter. 13:00'te ya da sonra başlayan vardiyanın
-- planlı saatleri değişmez; çalışması gun_hesabi'nda bütünüyle tatil çalışmasıdır
create or replace function pdks.vardiya_araligi(p_vardiya_id smallint, p_is_gunu date, out p_bas timestamptz, out p_bit timestamptz)
returns record
language sql
stable
set search_path = pdks
as $$
    select h.p_bas, case when h.p_bas < s.arife then least(h.p_bit, s.arife) else h.p_bit end
    from pdks.vardiya_ham_araligi(p_vardiya_id, p_is_gunu) h
    cross join (select pdks.arife_siniri(p_is_gunu) as arife) s;
$$;

revoke execute on function pdks.arife_siniri(date), pdks.vardiya_ham_araligi(smallint, date),
                           pdks.vardiya_araligi(smallint, date) from public, anon, authenticated;

create or replace function pdks.gun_penceresi(p_gun_kaydi_id bigint, out p_bas timestamptz, out p_bit timestamptz)
returns record
language sql
stable
set search_path = pdks
as $$
    select a.p_bas - make_interval(mins => t.pencere_once_dk),
           a.p_bit + make_interval(mins => t.pencere_sonra_dk)
    from pdks.gun_kaydi g
    join pdks.vardiya_tanim t on t.id = g.vardiya_id
    cross join lateral pdks.vardiya_ham_araligi(g.vardiya_id, g.is_gunu) a
    where g.id = p_gun_kaydi_id;
$$;

-- İşten çıkışta da okutma penceresi vardiyanın tanımdaki aralığıyla kurulur (T-65)
create or replace function pdks.cikistan_sonraki_okutma(p_calisan_id bigint, p_cikis_tarihi date)
returns timestamptz
language sql
stable
set search_path = pdks
as $$
    with gunler as (
        -- İşlenmiş günde gun_kaydi'nın vardiyası (düzeltilmiş olabilir), yoksa plan
        select coalesce(g.is_gunu, vp.tarih) as tarih, coalesce(g.vardiya_id, vp.vardiya_id) as vardiya_id
        from (select * from pdks.vardiya_plani
              where calisan_id = p_calisan_id and ik_onay_durumu <> 'reddedildi'
                and tarih between p_cikis_tarihi and p_cikis_tarihi + 1) vp
        full join (select * from pdks.gun_kaydi
                   where calisan_id = p_calisan_id
                     and is_gunu between p_cikis_tarihi and p_cikis_tarihi + 1) g on g.is_gunu = vp.tarih
    ), pencere as (
        select g.tarih,
               a.p_bas - make_interval(mins => vt.pencere_once_dk) as bas,
               a.p_bit + make_interval(mins => vt.pencere_sonra_dk) as bit
        from gunler g
        join pdks.vardiya_tanim vt on vt.id = g.vardiya_id
        cross join lateral pdks.vardiya_ham_araligi(g.vardiya_id, g.tarih) a
    ), sinir as (
        select ((p_cikis_tarihi + 1)::timestamp at time zone 'Europe/Istanbul') as gun_sonu,
               (select bas from pencere where tarih = p_cikis_tarihi) as son_bas,
               (select bit from pencere where tarih = p_cikis_tarihi) as son_bit,
               (select bas from pencere where tarih = p_cikis_tarihi + 1) as ertesi_bas
    ), kartlar as (
        select kart_no, iptal_zamani from pdks.kart where calisan_id = p_calisan_id
        union all
        select distinct gk.kart_no, null::timestamptz
        from pdks.gecici_kart_zimmet z
        join pdks.gecici_kart gk on gk.id = z.gecici_kart_id
        where z.calisan_id = p_calisan_id
    )
    select min(h.okutma_zamani)
    from sinir s
    cross join kartlar k
    join pdks.ham_okutma h on h.kart_no = k.kart_no
                          and h.okutma_zamani >= least(s.gun_sonu, s.ertesi_bas)
    where (k.iptal_zamani is null or h.okutma_zamani < k.iptal_zamani)
      and not coalesce(h.okutma_zamani between s.son_bas and s.son_bit, false)
      and pdks.okutma_sahibi(h.kart_no, h.okutma_zamani) = p_calisan_id;
$$;

-- ---------------------------------------------------------------------
-- 3. Gece işi: planlı bitiş, tatil, uyarılar
-- ---------------------------------------------------------------------
create or replace function pdks.gece_isi_gun_kayitlari(p_gun date, p_gece_isi_id bigint)
returns integer
language plpgsql
set search_path = pdks
as $$
declare
    v_n integer;
begin
    with plan as (
        select vp.calisan_id, vp.vardiya_id, vt.pencere_once_dk, vt.pencere_sonra_dk,
               (p_gun + vt.baslangic) at time zone 'Europe/Istanbul' as bas,
               (p_gun + case when vt.gece_yarisini_asar then 1 else 0 end + vt.bitis) at time zone 'Europe/Istanbul' as bit,
               (pdks.vardiya_araligi(vp.vardiya_id, p_gun)).p_bit as planli_bit
        from pdks.vardiya_plani vp
        join pdks.vardiya_tanim vt on vt.id = vp.vardiya_id
        -- O gün işte miydi? (aktif alanı çıkış girilince hemen false olur; tarih son günü de kapsar)
        join pdks.calisan c on c.id = vp.calisan_id
                           and p_gun >= c.ise_giris_tarihi
                           and (c.isten_cikis_tarihi is null or p_gun <= c.isten_cikis_tarihi)
        where vp.tarih = p_gun
          -- İK onayı bekleyen ya da reddedilmiş geriye dönük plan hesapta kullanılmaz
          and vp.ik_onay_durumu in ('gerekmez', 'onaylandi')
          and not exists (select 1 from pdks.gun_kaydi g where g.calisan_id = vp.calisan_id and g.is_gunu = p_gun)
    ), tam as (
        select p.* from plan p
        where pdks.pdks_verisi_tam_mi(p.bas - make_interval(mins => p.pencere_once_dk),
                                      p.bit + make_interval(mins => p.pencere_sonra_dk))
    ), okut as (
        select p.calisan_id,
               min(h.okutma_zamani) filter (where h.yon is distinct from 'cikis') as giris,
               max(h.okutma_zamani) filter (where h.yon is distinct from 'giris') as cikis
        from tam p
        join pdks.ham_okutma h
          on h.okutma_zamani between p.bas - make_interval(mins => p.pencere_once_dk)
                                 and p.bit + make_interval(mins => p.pencere_sonra_dk)
        where pdks.okutma_sahibi(h.kart_no, h.okutma_zamani) = p.calisan_id
          and not pdks.okutma_gecersiz_mi(h.id)
        group by p.calisan_id
    ), durumlu as (
        select t.calisan_id, t.vardiya_id, t.bas, t.planli_bit, o.giris,
               case when o.giris is null or o.cikis > o.giris then o.cikis end as cikis,
               (select i.tur from pdks.izin i
                where i.calisan_id = t.calisan_id and p_gun between i.baslangic and i.bitis
                  and i.iptal_zamani is null
                order by i.id limit 1) as izin_turu,
               -- Resmi tatil yalnızca hiç okutma yoksa "tatil"dir; okutma varsa çalışılmış gün işlenir
               -- (arifede 13:00'te ya da sonra başlayan vardiya da tatildir)
               (exists (select 1 from pdks.resmi_tatil r where r.tarih = p_gun and not r.yarim_gun)
                   or t.bas >= pdks.arife_siniri(p_gun)) is true
                   and o.giris is null and o.cikis is null as tatil
        from tam t
        left join okut o on o.calisan_id = t.calisan_id
    )
    insert into pdks.gun_kaydi (calisan_id, is_gunu, vardiya_id, planli_baslangic, planli_bitis,
                                giris_zamani, cikis_zamani, giris_kaynagi, cikis_kaynagi,
                                durum, hesap_tamam, gece_isi_id)
    select d.calisan_id, p_gun, d.vardiya_id, d.bas, d.planli_bit,
           d.giris, d.cikis,
           case when d.giris is not null then 'pdks' end,
           case when d.cikis is not null then 'pdks' end,
           case when d.izin_turu = 'rapor' then 'raporlu'
                when d.izin_turu is not null then 'izinli'
                when d.tatil then 'tatil'
                when d.giris is not null and d.cikis is not null then 'tamam'
                else 'eksik' end,
           (d.izin_turu is not null or d.tatil),
           p_gece_isi_id
    from durumlu d;
    get diagnostics v_n = row_count;
    return v_n;
end;
$$;

create or replace function pdks.gece_isi_uyarilar(p_gun date)
returns integer
language plpgsql
set search_path = pdks
as $$
declare
    v_esik    integer := pdks.ayar_al('fm_plansiz_esik_dk');
    v_gunluk  integer := pdks.ayar_al('gunluk_azami_calisma_dk');
    v_say     integer := 0;
    r         record;
begin
    for r in
        select g.id, g.calisan_id, g.giris_zamani, g.cikis_zamani, g.planli_baslangic, t.esnek,
               -- Arifede planlı bitiş 13:00'tür; yazılı onaylı çalışanın vardiya içi tatil çalışması plansız sayılmaz
               pdks.dakika(case when pdks.arife_siniri(p_gun) is not null and pdks.fm_onay_gecerli_mi(g.calisan_id, g.is_gunu)
                                then (pdks.vardiya_ham_araligi(g.vardiya_id, g.is_gunu)).p_bit
                                else g.planli_bitis end, g.cikis_zamani) as fazla,
               coalesce(p.planli_dk, 0) as plan,
               pdks.fm_onay_gecerli_mi(g.calisan_id, g.is_gunu) as onay
        from pdks.gun_kaydi g
        join pdks.vardiya_tanim t on t.id = g.vardiya_id
        left join pdks.fazla_mesai_plani p
          on p.calisan_id = g.calisan_id and p.is_gunu = g.is_gunu and p.durum = 'onaylandi'
        where g.is_gunu = p_gun and g.cikis_zamani is not null and g.planli_bitis is not null
    loop
        if not r.esnek and r.fazla - r.plan > v_esik then
            if r.plan = 0 and not r.onay then
                v_say := v_say + pdks.uyari_yaz('fm_onay_yok', 'fm:' || r.id,
                    format('%s tarihinde vardiya sonrası %s çalışıldı; yazılı fazla mesai onayı yok.',
                           to_char(p_gun, 'DD.MM.YYYY'), pdks.sure_metni(r.fazla::integer)), r.calisan_id);
            else
                v_say := v_say + pdks.uyari_yaz('fm_plansiz_calisma', 'fm:' || r.id,
                    format('%s tarihinde vardiya sonrası %s çalışıldı (onaylı plan %s). Aşan süre İK kararı bekliyor.',
                           to_char(p_gun, 'DD.MM.YYYY'), pdks.sure_metni(r.fazla::integer), pdks.sure_metni(r.plan::integer)), r.calisan_id);
            end if;
        end if;

        if r.giris_zamani is not null
           and pdks.dakika(case when r.esnek then r.giris_zamani else greatest(r.giris_zamani, r.planli_baslangic) end,
                           r.cikis_zamani) > v_gunluk + v_esik then
            v_say := v_say + pdks.uyari_yaz('fm_gunluk_sinir_asildi', 'gunluk:' || r.id,
                format('%s tarihinde %s çalışıldı (%ssınır %s).', to_char(p_gun, 'DD.MM.YYYY'),
                       pdks.sure_metni(pdks.dakika(case when r.esnek then r.giris_zamani else greatest(r.giris_zamani, r.planli_baslangic) end,
                                   r.cikis_zamani)::integer), case when v_gunluk = 660 then 'yasal ' else '' end, pdks.sure_metni(v_gunluk)),
                r.calisan_id);
        end if;
    end loop;

    for r in
        select k from unnest(array['pdks', 'kapi', 'yemekhane', 'servis']) k
        where not exists (select 1 from pdks.aktarim a where a.kaynak = k and a.veri_tarihi = p_gun)
    loop
        v_say := v_say + pdks.uyari_yaz('dosya_gelmedi', r.k || ':' || p_gun,
            format('%s tarihli %s dosyası yüklenmedi.', to_char(p_gun, 'DD.MM.YYYY'),
                   case r.k when 'pdks' then 'PDKS' when 'kapi' then 'kapı turnikesi' else r.k end));
    end loop;

    v_say := v_say + coalesce(pdks.gecici_kart_kontrol(p_gun), 0);
    v_say := v_say + coalesce(pdks.kart_paylasim_kontrol(p_gun), 0);
    v_say := v_say + coalesce(pdks.isg_kontrol(p_gun), 0);
    v_say := v_say + coalesce(pdks.bolge_kontrol(p_gun), 0);

    return v_say;
end;
$$;

-- ---------------------------------------------------------------------
-- 4. Günün hesabı, tablo kuralı, havuz türü
-- ---------------------------------------------------------------------
create or replace function pdks.gun_hesabi(p_calisan_id bigint, p_is_gunu date, p_bas timestamptz, p_bit timestamptz, p_giris timestamptz, p_cikis timestamptz, p_vardiya_id smallint default null, out gec_kalma_dk integer, out erken_cikis_dk integer, out calisma_dk integer, out fazla_mesai_dk integer, out fm50_dk integer, out fm100_dk integer, out gece_calisma_dk integer, out saatlik_izin_dk integer, out onaysiz_fm_dk integer, out mola_dk integer)
returns record
language plpgsql
stable
set search_path = pdks
as $$
declare
    v_izin   tstzmultirange := pdks.saatlik_izin_araligi(p_calisan_id, p_is_gunu);
    v_yuv    integer := pdks.ayar_al('tolerans_yuvarlama_dk');
    v_onay   boolean := pdks.fm_onay_gecerli_mi(p_calisan_id, p_is_gunu);
    v_tatil  boolean := pdks.fm100_gunu_mu(p_is_gunu);
    v_arife  timestamptz := pdks.arife_siniri(p_is_gunu);
    v_vardiya smallint;
    v_ham_bit timestamptz;   -- arifede vardiyanın tanımdaki bitişi (p_bit 13:00'e çekilir)
    v_arife_ici integer;
    v_ek100  integer;
    v_eksik  integer;
    v_esnek  boolean;
    v_plan   integer;
    v_havuz  integer;
    v_bas_is timestamptz;
    v_ici    integer;
    v_sonra  integer;
    v_ek     integer;
    v_brut   integer;
    v_gece   integer;
begin
    gec_kalma_dk := 0; erken_cikis_dk := 0; calisma_dk := 0; fazla_mesai_dk := 0;
    fm50_dk := 0; fm100_dk := 0; gece_calisma_dk := 0; saatlik_izin_dk := 0; onaysiz_fm_dk := 0; mola_dk := 0;
    if p_giris is null or p_cikis is null or p_bas is null or p_bit is null then
        return;
    end if;

    v_vardiya := coalesce(p_vardiya_id, (select g.vardiya_id from pdks.gun_kaydi g
                                         where g.calisan_id = p_calisan_id and g.is_gunu = p_is_gunu));
    select t.esnek into v_esnek from pdks.vardiya_tanim t where t.id = v_vardiya;
    if coalesce(v_esnek, false) then
        -- Esnek mesaide vardiya, çalışanın kendi giriş–çıkışıdır
        p_bas := p_giris;
        p_bit := p_cikis;
    end if;

    v_ham_bit := p_bit;
    if v_arife is not null then
        if v_vardiya is not null and not coalesce(v_esnek, false) then
            v_ham_bit := greatest(p_bit, (pdks.vardiya_ham_araligi(v_vardiya, p_is_gunu)).p_bit);
        end if;
        -- Arifede çalışma 13:00'te biter; sonra başlayan vardiyada planlı normal çalışma kalmaz
        p_bit := greatest(p_bas, least(p_bit, v_arife));
    end if;

    select planli_dk into v_plan from pdks.fazla_mesai_plani
    where calisan_id = p_calisan_id and is_gunu = p_is_gunu and durum = 'onaylandi';
    v_plan := case when v_onay then coalesce(v_plan, 0) else 0 end;

    select coalesce(sum(dakika), 0) into v_havuz from pdks.fazla_mesai_inceleme
    where calisan_id = p_calisan_id and is_gunu = p_is_gunu and durum = 'onaylandi';

    gec_kalma_dk   := pdks.tolerans_uygula(pdks.dakika_toplami(pdks.aralik(p_bas, case when v_arife is not null then least(p_giris, p_bit)
                                                                              else p_giris end) - v_izin),
                                           pdks.ayar_al('gec_kalma_tolerans_dk'), v_yuv);
    erken_cikis_dk := pdks.tolerans_uygula(pdks.dakika_toplami(pdks.aralik(p_cikis, p_bit) - v_izin),
                                           pdks.ayar_al('erken_cikis_tolerans_dk'), v_yuv);
    saatlik_izin_dk := pdks.dakika_toplami(pdks.aralik(p_bas, p_bit) * v_izin);

    v_bas_is := greatest(p_giris, p_bas);
    v_ici    := pdks.dakika_toplami(pdks.aralik(v_bas_is, least(p_cikis, p_bit)) - v_izin);
    v_sonra  := greatest(0, pdks.dakika(v_ham_bit, p_cikis));

    if v_arife is not null then
        -- 13:00'ten vardiya bitişine kadar: yazılı onay varsa FM100, yoksa havuz onayı kadar.
        -- Saat 13:00'ü birkaç dakika geçen çıkış (plansız çalışma eşiği) çalışma sayılmaz.
        v_arife_ici := pdks.dakika_toplami(pdks.aralik(greatest(v_bas_is, v_arife), least(p_cikis, v_ham_bit)) - v_izin);
        if v_ici > 0 and v_arife_ici <= pdks.ayar_al('fm_plansiz_esik_dk') then
            v_arife_ici := 0;
        end if;
        fm100_dk := case when v_onay then v_arife_ici else least(v_arife_ici, v_havuz) end;
        -- Vardiya bitişinden sonrası: onaylı plan + havuz; 13:00 öncesine düşen kısmı (ör. 00-08 vardiyası) FM50
        v_ek := least(v_sonra, v_plan + v_havuz - case when v_onay then 0 else fm100_dk end);
        v_ek100 := least(v_ek, greatest(0, pdks.dakika(greatest(v_arife, v_ham_bit), v_ham_bit + make_interval(mins => v_ek))));
        onaysiz_fm_dk := v_arife_ici - fm100_dk + v_sonra - v_ek;
        fm50_dk := v_ek - v_ek100;
        v_brut := v_ici + fm100_dk + v_ek;
        fm100_dk := fm100_dk + v_ek100;
    elsif not v_tatil then
        v_ek := least(v_sonra, v_plan + v_havuz);
        fm50_dk := v_ek;
        v_brut := v_ici + v_ek;
        onaysiz_fm_dk := greatest(0, v_sonra - v_plan - v_havuz);
    elsif v_onay then
        v_ek := least(v_sonra, v_plan + v_havuz);
        fm100_dk := v_ici + v_ek;
        v_brut := fm100_dk;
        onaysiz_fm_dk := greatest(0, v_sonra - v_plan - v_havuz);
    else
        fm100_dk := least(v_ici + v_sonra, v_havuz);
        v_brut := fm100_dk;
        v_ek := greatest(0, fm100_dk - v_ici);
        onaysiz_fm_dk := greatest(0, v_ici + v_sonra - v_havuz);
    end if;

    -- Brüt çalışmanın gece dilimine düşen kısmı
    v_gece := least(v_brut,
        pdks.dakika_toplami((pdks.aralik(v_bas_is, least(p_cikis, v_ham_bit + make_interval(mins => coalesce(v_ek, 0))))
                             - v_izin) * pdks.gece_araligi(p_is_gunu)));

    -- Mola (m.68)
    mola_dk := pdks.mola_suresi(v_brut);
    calisma_dk := v_brut - mola_dk;
    if v_arife is not null then
        -- Mola önce normal çalışmadan, kalan kısmı fazla mesaiden düşer
        v_eksik := greatest(0, mola_dk - v_ici);
        fm100_dk := greatest(0, fm100_dk - greatest(0, v_eksik - fm50_dk));
        fm50_dk := greatest(0, fm50_dk - v_eksik);
    elsif v_tatil then
        fm100_dk := greatest(0, fm100_dk - mola_dk);
    elsif v_ici < mola_dk then
        fm50_dk := greatest(0, fm50_dk - (mola_dk - v_ici));
    end if;
    fazla_mesai_dk := fm50_dk + fm100_dk;
    gece_calisma_dk := case when v_brut > 0 then greatest(0, v_gece - round(mola_dk::numeric * v_gece / v_brut)::integer)
                            else 0 end;
end;
$$;

create or replace function pdks.gun_kaydi_fazla_mesai_kontrol()
returns trigger
language plpgsql
set search_path = pdks
as $$
declare
    v_plan    integer;
    v_onay    boolean;
    v_havuz   integer;
    v_izinli  integer;
begin
    if coalesce(new.fazla_mesai_dk, 0) = 0 then
        return new;
    end if;
    select planli_dk into v_plan from pdks.fazla_mesai_plani
    where calisan_id = new.calisan_id and is_gunu = new.is_gunu and durum = 'onaylandi';
    v_onay := pdks.fm_onay_gecerli_mi(new.calisan_id, new.is_gunu);
    select coalesce(sum(dakika), 0) into v_havuz from pdks.fazla_mesai_inceleme
    where calisan_id = new.calisan_id and is_gunu = new.is_gunu and durum = 'onaylandi';

    v_izinli := case when v_onay then coalesce(v_plan, 0) else 0 end + v_havuz
              + case when v_onay and (pdks.fm100_gunu_mu(new.is_gunu) or pdks.arife_siniri(new.is_gunu) is not null) and new.vardiya_id is not null
                     then pdks.vardiya_suresi_dk(new.vardiya_id) else 0 end;

    if v_izinli = 0 then
        if v_plan is null then
            raise exception '% günü için onaylı fazla mesai planı yok; plansız çalışma puantaja yazılmaz (İK''ya uyarı verilir).',
                new.is_gunu;
        end if;
        raise exception '% günü için geçerli yazılı fazla mesai onayı yok.', new.is_gunu;
    end if;
    if new.fazla_mesai_dk > v_izinli then
        raise exception 'Fazla mesai % dk, izin verilen % dk (onaylı plan ve İK onayı); fazlası puantaja yazılmaz.',
            new.fazla_mesai_dk, v_izinli;
    end if;
    return new;
end;
$$;

create or replace function pdks.gun_sonrasi_kontroller(p_gun_kaydi_id bigint)
returns integer
language plpgsql
set search_path = pdks
as $$
declare
    g       pdks.gun_kaydi;
    h       record;
    v_mevcut pdks.fazla_mesai_inceleme;
    v_tur   text;
    v_say   integer := 0;
    v_toplam integer;
begin
    select * into g from pdks.gun_kaydi where id = p_gun_kaydi_id;
    if not g.hesap_tamam or g.durum <> 'tamam' then
        return 0;
    end if;
    select * into h from pdks.gun_hesabi(g.calisan_id, g.is_gunu, g.planli_baslangic, g.planli_bitis,
                                         g.giris_zamani, g.cikis_zamani);
    v_tur := case when (pdks.fm100_gunu_mu(g.is_gunu) or g.cikis_zamani > pdks.arife_siniri(g.is_gunu))
                       and not pdks.fm_onay_gecerli_mi(g.calisan_id, g.is_gunu)
                  then 'tatil_calismasi' else 'vardiya_sonrasi' end;

    select * into v_mevcut from pdks.fazla_mesai_inceleme where gun_kaydi_id = g.id;
    if h.onaysiz_fm_dk > pdks.ayar_al('fm_plansiz_esik_dk') then
        if v_mevcut.id is null then
            insert into pdks.fazla_mesai_inceleme (gun_kaydi_id, calisan_id, is_gunu, tur, dakika)
            values (g.id, g.calisan_id, g.is_gunu, v_tur, h.onaysiz_fm_dk);
            v_say := v_say + 1;
        elsif v_mevcut.durum = 'inceleme_bekliyor' and (v_mevcut.dakika, v_mevcut.tur) <> (h.onaysiz_fm_dk, v_tur) then
            update pdks.fazla_mesai_inceleme set dakika = h.onaysiz_fm_dk, tur = v_tur where id = v_mevcut.id;
        end if;
    end if;

    -- Yazılı onaylı tatil çalışması havuza düşmeden puantaja girer; yıllık sınırı aşarsa İK'ya bildirilir
    -- (havuzdan onaylanan gün kendi uyarısını karar anında yazar)
    if g.fm100_dk > 0 and v_mevcut.durum is distinct from 'onaylandi' then
        v_toplam := pdks.fm_yillik_toplam(g.calisan_id, extract(year from g.is_gunu)::integer);
        if v_toplam > pdks.ayar_al('fm_yillik_sinir_dk') then
            v_say := v_say + pdks.uyari_yaz('fm_yillik_sinir_asildi', 'gun:' || g.id,
                format('%s yılı onaylı fazla mesai süresi %s (sınır %s).',
                       extract(year from g.is_gunu), pdks.sure_metni(v_toplam), pdks.sure_metni(pdks.ayar_al('fm_yillik_sinir_dk'))),
                g.calisan_id);
        end if;
    end if;

    if g.gece_calisma_dk > pdks.ayar_al('gece_calisma_sinir_dk') then
        v_say := v_say + pdks.uyari_yaz('gece_calisma_siniri_asildi', 'gece:' || g.id,
            format('%s tarihinde %s gece çalışması yapıldı (%ssınır %s).',
                   to_char(g.is_gunu, 'DD.MM.YYYY'), pdks.sure_metni(g.gece_calisma_dk),
                   case when pdks.ayar_al('gece_calisma_sinir_dk') = 450 then 'yasal ' else '' end,
                   pdks.sure_metni(pdks.ayar_al('gece_calisma_sinir_dk'))),
            g.calisan_id);
    end if;
    return v_say;
end;
$$;

-- ---------------------------------------------------------------------
-- 5. Puantaj kodu, esnek mesai, yıllık toplam
-- ---------------------------------------------------------------------
create or replace function pdks.gun_kod_satirlari(p_calisan_id bigint, p_gun date, p_durum text, p_calisma_dk integer, p_fm50_dk integer, p_fm100_dk integer)
returns TABLE(kod text, gun numeric, dakika integer)
language plpgsql
stable
set search_path = pdks
as $$
declare
    v_izin text;
begin
    if p_durum is null or p_durum = 'vardiya_yok' then
        return query select case when exists (select 1 from pdks.resmi_tatil r where r.tarih = p_gun and not r.yarim_gun)
                                 then 'RT' else 'HT' end, 1::numeric, 0;
    elsif p_durum = 'tatil' then
        return query select 'RT'::text, 1::numeric, 0;
    elsif p_durum = 'raporlu' then
        return query select 'RPR'::text, 1::numeric, 0;
    elsif p_durum = 'devamsiz' then
        return query select 'DVMSZ'::text, 1::numeric, 0;
    elsif p_durum = 'izinli' then
        select i.tur into v_izin from pdks.izin i
        where i.calisan_id = p_calisan_id and p_gun between i.baslangic and i.bitis and i.iptal_zamani is null
        order by i.id limit 1;
        return query select case v_izin when 'yillik' then 'Yİ' when 'mazeret' then 'MZR'
                                        when 'ucretsiz' then 'ÜCSZ' when 'rapor' then 'RPR' else 'Dİ' end,
                            1::numeric, 0;
    elsif p_durum = 'tamam' then
        if pdks.fm100_gunu_mu(p_gun) then
            return query select 'FM100'::text, 1::numeric, coalesce(p_fm100_dk, 0);
        elsif pdks.arife_siniri(p_gun) is not null and coalesce(p_fm100_dk, 0) > 0
              and coalesce(p_calisma_dk, 0) = coalesce(p_fm50_dk, 0) + p_fm100_dk then
            -- Arifede vardiyanın tamamı 13:00'ten sonra: gün FM100 günüdür
            return query select 'FM100'::text, 1::numeric, p_fm100_dk;
            if coalesce(p_fm50_dk, 0) <> 0 then
                return query select 'FM50'::text, 0::numeric, p_fm50_dk;
            end if;
        else
            -- Arifede FM100, normal çalışmayla aynı gündedir
            return query select 'NÇ'::text, 1::numeric,
                                coalesce(p_calisma_dk, 0) - coalesce(p_fm50_dk, 0) - coalesce(p_fm100_dk, 0);
            if coalesce(p_fm100_dk, 0) <> 0 then
                return query select 'FM100'::text, 0::numeric, p_fm100_dk;
            end if;
            if coalesce(p_fm50_dk, 0) <> 0 then
                return query select 'FM50'::text, 0::numeric, p_fm50_dk;
            end if;
        end if;
    end if;
end;
$$;

create or replace function pdks.gun_katkisi(p_gun_kaydi_id bigint, p_duzeltmeler bigint[], out calisilan_gun numeric, out calisma_dk integer, out gec_kalma_dk integer, out erken_cikis_dk integer, out devamsiz_gun numeric, out izinli_gun numeric, out raporlu_gun numeric, out tatil_gun numeric, out fazla_mesai_dk integer, out fm50_dk integer, out fm100_dk integer, out gece_calisma_dk integer, out saatlik_izin_dk integer, out durum text, out mola_dk integer, out esnek_hedef_dk integer, out esnek_fark_dk integer)
returns record
language plpgsql
stable
set search_path = pdks
as $$
declare
    g        pdks.gun_kaydi;
    d        record;
    v_durum_duzeltildi boolean := false;
    v_ara    record;
    v_esnek  boolean;
    h        record;
begin
    select * into g from pdks.gun_kaydi where id = p_gun_kaydi_id;

    for d in select * from pdks.duzeltme where id = any (coalesce(p_duzeltmeler, '{}')) order by id loop
        case d.alan
            when 'giris_zamani' then g.giris_zamani := d.yeni_deger::timestamptz;
            when 'cikis_zamani' then g.cikis_zamani := d.yeni_deger::timestamptz;
            when 'durum'        then g.durum := d.yeni_deger; v_durum_duzeltildi := true;
            when 'vardiya_id'   then
                g.vardiya_id := d.yeni_deger::smallint;
                select * into v_ara from pdks.vardiya_araligi(g.vardiya_id, g.is_gunu);
                g.planli_baslangic := v_ara.p_bas;
                g.planli_bitis := v_ara.p_bit;
        end case;
    end loop;

    if not v_durum_duzeltildi and coalesce(array_length(p_duzeltmeler, 1), 0) > 0
       and g.durum in ('eksik', 'soru_bekliyor', 'devamsiz_suphesi')
       and g.giris_zamani is not null and g.cikis_zamani is not null then
        g.durum := 'tamam';
    end if;

    durum         := g.durum;
    calisilan_gun := case when g.durum = 'tamam'    then 1 else 0 end;
    devamsiz_gun  := case when g.durum = 'devamsiz' then 1 else 0 end;
    izinli_gun    := case when g.durum = 'izinli'   then 1 else 0 end;
    raporlu_gun   := case when g.durum = 'raporlu'  then 1 else 0 end;
    tatil_gun     := case when g.durum = 'tatil'    then 1 else 0 end;

    if g.durum = 'tamam' and g.giris_zamani is not null and g.cikis_zamani is not null
       and g.planli_baslangic is not null then
        select * into h from pdks.gun_hesabi(g.calisan_id, g.is_gunu, g.planli_baslangic, g.planli_bitis,
                                              g.giris_zamani, g.cikis_zamani, g.vardiya_id);
        calisma_dk := h.calisma_dk; gec_kalma_dk := h.gec_kalma_dk;
        erken_cikis_dk := h.erken_cikis_dk; fazla_mesai_dk := h.fazla_mesai_dk;
        fm50_dk := h.fm50_dk; fm100_dk := h.fm100_dk;
        gece_calisma_dk := h.gece_calisma_dk; saatlik_izin_dk := h.saatlik_izin_dk; mola_dk := h.mola_dk;
    else
        calisma_dk := 0; gec_kalma_dk := 0; erken_cikis_dk := 0; fazla_mesai_dk := 0;
        fm50_dk := 0; fm100_dk := 0; gece_calisma_dk := 0; saatlik_izin_dk := 0; mola_dk := 0;
    end if;

    select t.esnek into v_esnek from pdks.vardiya_tanim t where t.id = g.vardiya_id;
    if coalesce(v_esnek, false) and g.durum not in ('izinli', 'raporlu', 'tatil', 'vardiya_yok') then
        esnek_hedef_dk := pdks.ayar_al('esnek_gunluk_hedef_dk')
                          / case when pdks.arife_siniri(g.is_gunu) is not null then 2 else 1 end;
    else
        esnek_hedef_dk := 0;
    end if;
    esnek_fark_dk := case when coalesce(v_esnek, false)
                           then calisma_dk - case when pdks.arife_siniri(g.is_gunu) is not null then fm100_dk else 0 end
                           else 0 end - esnek_hedef_dk;
end;
$$;

create or replace view pdks.v_esnek_mesai with (security_invoker = true) as
select yil, ay, calisan_id,
       count(*) filter (where hedefli) as hedef_gun,
       coalesce(sum(hedef) filter (where hedefli), 0)::integer as hedef_dk,
       coalesce(sum(calisma) filter (where durum = 'tamam'), 0)::integer as gerceklesen_dk,
       (coalesce(sum(calisma) filter (where durum = 'tamam'), 0)
        - coalesce(sum(hedef) filter (where hedefli), 0))::integer as fark_dk,
       count(*) filter (where durum in ('eksik', 'soru_bekliyor', 'devamsiz_suphesi')
                           or (durum = 'tamam' and not hesap_tamam)) as bekleyen_gun
from (
    select extract(year from g.is_gunu)::integer as yil, extract(month from g.is_gunu)::integer as ay,
           g.calisan_id, g.durum, g.hesap_tamam,
           g.durum not in ('izinli', 'raporlu', 'tatil', 'vardiya_yok') as hedefli,
           pdks.ayar_al('esnek_gunluk_hedef_dk') / case when ar.tarih is not null then 2 else 1 end as hedef,
           g.calisma_dk - case when ar.tarih is not null then coalesce(g.fm100_dk, 0) else 0 end as calisma
    from pdks.gun_kaydi g
    join pdks.vardiya_tanim t on t.id = g.vardiya_id and t.esnek
    left join pdks.resmi_tatil ar on ar.tarih = g.is_gunu and ar.yarim_gun and not pdks.fm100_gunu_mu(ar.tarih)
) x
group by yil, ay, calisan_id;

create or replace view pdks.v_puantaj_canli with (security_invoker = true) as
WITH g AS (
         SELECT g_1.id,
            g_1.calisan_id,
            g_1.is_gunu,
            g_1.vardiya_id,
            g_1.planli_baslangic,
            g_1.planli_bitis,
            g_1.giris_zamani,
            g_1.cikis_zamani,
            g_1.giris_kaynagi,
            g_1.cikis_kaynagi,
            g_1.durum,
            g_1.gec_kalma_dk,
            g_1.erken_cikis_dk,
            g_1.calisma_dk,
            g_1.hesap_tamam,
            g_1.gece_isi_id,
            g_1.guncelleme_zamani,
            g_1.fazla_mesai_dk,
            g_1.fm50_dk,
            g_1.fm100_dk,
            g_1.gece_calisma_dk,
            g_1.saatlik_izin_dk,
            g_1.mola_dk,
            COALESCE(t.esnek, false) AS esnek,
            (COALESCE(t.esnek, false) AND (g_1.durum <> ALL (ARRAY['izinli'::text, 'raporlu'::text, 'tatil'::text, 'vardiya_yok'::text]))) AS esnek_hedefli,
            (ar.tarih IS NOT NULL) AS arife
           FROM pdks.gun_kaydi g_1
             LEFT JOIN pdks.vardiya_tanim t ON t.id = g_1.vardiya_id
             LEFT JOIN pdks.resmi_tatil ar ON ar.tarih = g_1.is_gunu AND ar.yarim_gun AND NOT pdks.fm100_gunu_mu(ar.tarih)
        )
 SELECT (EXTRACT(year FROM is_gunu))::integer AS yil,
    (EXTRACT(month FROM is_gunu))::integer AS ay,
    calisan_id,
    count(*) FILTER (WHERE (durum = 'tamam'::text)) AS calisilan_gun,
    COALESCE(sum(calisma_dk), (0)::bigint) AS calisma_dk,
    COALESCE(sum(gec_kalma_dk), (0)::bigint) AS gec_kalma_dk,
    COALESCE(sum(erken_cikis_dk), (0)::bigint) AS erken_cikis_dk,
    count(*) FILTER (WHERE (durum = 'devamsiz'::text)) AS devamsiz_gun,
    count(*) FILTER (WHERE (durum = 'izinli'::text)) AS izinli_gun,
    count(*) FILTER (WHERE (durum = 'raporlu'::text)) AS raporlu_gun,
    count(*) FILTER (WHERE (durum = 'tatil'::text)) AS tatil_gun,
    count(*) FILTER (WHERE ((durum = ANY (ARRAY['eksik'::text, 'soru_bekliyor'::text, 'devamsiz_suphesi'::text])) OR (NOT hesap_tamam))) AS bekleyen_gun,
    COALESCE(sum(fazla_mesai_dk), (0)::bigint) AS fazla_mesai_dk,
    COALESCE(sum(fm50_dk), (0)::bigint) AS fm50_dk,
    COALESCE(sum(fm100_dk), (0)::bigint) AS fm100_dk,
    COALESCE(sum(gece_calisma_dk), (0)::bigint) AS gece_calisma_dk,
    COALESCE(sum(saatlik_izin_dk), (0)::bigint) AS saatlik_izin_dk,
    COALESCE(sum(mola_dk), (0)::bigint) AS mola_dk,
    (coalesce(sum(pdks.ayar_al('esnek_gunluk_hedef_dk') / case when arife then 2 else 1 end) filter (where esnek_hedefli), 0))::integer AS esnek_hedef_dk,
    ((coalesce(sum(calisma_dk - case when arife then coalesce(fm100_dk, 0) else 0 end) filter (where esnek and durum = 'tamam'), 0) - coalesce(sum(pdks.ayar_al('esnek_gunluk_hedef_dk') / case when arife then 2 else 1 end) filter (where esnek_hedefli), 0)))::integer AS esnek_fark_dk
   FROM g
  GROUP BY ((EXTRACT(year FROM is_gunu))::integer), ((EXTRACT(month FROM is_gunu))::integer), calisan_id;

create or replace view pdks.v_fm_yillik_gun with (security_invoker = true) as
with gun as (
    select calisan_id, is_gunu, sum(plan)::integer as plan_dk, sum(havuz)::integer as havuz_dk,
           sum(fm100)::integer as fm100_dk, sum(gerceklesen)::integer as gerceklesen_dk
    from (
        select calisan_id, is_gunu, planli_dk as plan, 0 as havuz, 0 as fm100, 0 as gerceklesen
        from pdks.fazla_mesai_plani where durum = 'onaylandi'
        union all
        select calisan_id, is_gunu, 0, dakika,
               case when fark_satiri then fm100_etki_dk else 0 end,
               case when fark_satiri then fm50_etki_dk + fm100_etki_dk else 0 end
        from pdks.fazla_mesai_inceleme where durum = 'onaylandi'
        union all
        select calisan_id, is_gunu, 0, 0, coalesce(fm100_dk, 0), fazla_mesai_dk
        from pdks.gun_kaydi where fazla_mesai_dk > 0
    ) x
    group by calisan_id, is_gunu
)
select calisan_id, is_gunu, plan_dk, havuz_dk, fm100_dk, gerceklesen_dk,
       case when pdks.fm100_gunu_mu(is_gunu) then greatest(fm100_dk, plan_dk)
            -- Arife: 13:00 sonrası çalışma, plan ve havuz gün kaydındaki dakikanın içindedir
            when exists (select 1 from pdks.resmi_tatil r where r.tarih = is_gunu and r.yarim_gun)
                then greatest(gerceklesen_dk, plan_dk)
            else plan_dk + havuz_dk end as sinir_dk
from gun;
