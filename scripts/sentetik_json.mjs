// Sentetik veri çıktısını (veri/sentetik/*.csv) servis başına JSON dosyalarına çevirir → veri/sentetik/json/
// Çalıştırma: node scripts/sentetik_veri.mjs && node scripts/sentetik_json.mjs
import fs from 'node:fs';
import path from 'node:path';
const D='veri/sentetik',J=path.join(D,'json');fs.rmSync(J,{recursive:true,force:true});fs.mkdirSync(J,{recursive:true});
const oku=f=>{const [b,...s]=fs.readFileSync(path.join(D,f),'utf8').trim().split('\n');const h=b.split(';');
 return s.map(l=>{const v=l.split(';');const o={};h.forEach((k,i)=>{const x=v[i]??'';o[k]=x===''?null:(/^(satir_sayisi)$/.test(k)?Number(x):x)});return o;});};
const yaz=(ad,veri,aciklama)=>{fs.writeFileSync(path.join(J,ad),JSON.stringify({servis:ad.replace('.json',''),veri_turu:'sentetik',uyari:'Sentetik (uydurma) veridir; gerçek kişi ve kayıt içermez. Gerçek verilere benzetilerek üretilmiştir (scripts/sentetik_veri.mjs).',aciklama,kayit_sayisi:veri.length,veri},null,2)+'\n','utf8');return [ad,veri.length];};
const okuyucular=[
 ['PDKS-1','Ana giriş PDKS','pdks','İdari bina girişi','seed'],['PDKS-2','Atölye PDKS','pdks','Bobinaj atölyesi girişi','seed'],
 ['PDKS-3','Kazan-Nüve atölye PDKS','pdks','Kazan ve nüve atölyesi girişi','sentetik'],['KAPI-1','Ana kapı turnike','kapi','Fabrika ana kapısı','seed'],
 ['KAPI-2','Personel kapısı turnike','kapi','Fabrika arka personel kapısı','sentetik'],['YG-KAPI','YG Test Lab kapısı','kapi','Kalite binası','seed'],
 ['BOYA-KAPI','Boyahane kapısı','kapi','Boyahane','seed'],['YMK-1','Yemekhane','yemekhane','Yemekhane girişi','seed'],
 ['SRV-1','Servis 1 (Bornova)','servis','Servis aracı','seed'],['SRV-2','Servis 2 (Buca)','servis','Servis aracı','seed'],
 ['SRV-3','Servis 3 (Karşıyaka)','servis','Servis aracı','sentetik'],['SRV-4','Servis 4 (Çiğli)','servis','Servis aracı','sentetik'],
 ['SRV-5','Servis 5 (Menemen)','servis','Servis aracı','sentetik'],['SRV-6','Servis 6 (Kemalpaşa)','servis','Servis aracı','sentetik'],
 ['SRV-7','Servis 7 (Torbalı)','servis','Servis aracı','sentetik']].map(([kod,ad,sistem,konum,kaynak])=>({kod,ad,sistem,konum,tanimlandigi_yer:kaynak}));
const ozet=[];
ozet.push(yaz('calisanlar.json',oku('calisanlar.csv'),'İK personel servisi: sicil, ad, soyad, departman, vardiya düzeni, işe giriş/çıkış, aktif kart, servis hattı'));
ozet.push(yaz('kartlar.json',oku('kartlar.csv'),'Kart servisi: asıl kartlar ve iptal edilmiş eski kartlar'));
ozet.push(yaz('okuyucular.json',okuyucular,'Okuyucu (cihaz) listesi'));
ozet.push(yaz('vardiya_plani.json',oku('vardiya_plani.csv'),'Vardiya planı servisi: çalışan + gün + vardiya kodu (Ekim 2026)'));
ozet.push(yaz('izinler.json',oku('izinler.csv'),'İzin servisi: yıllık, rapor, mazeret, ücretsiz'));
ozet.push(yaz('isg_belgeleri.json',oku('isg_belgeleri.csv'),'İSG servisi: eğitim ve sağlık muayenesi geçerlilik tarihleri'));
ozet.push(yaz('gecici_kart_zimmet.json',oku('gecici_kart_zimmet.csv'),'Güvenlik servisi: geçici kart veriliş ve iade zamanları'));
ozet.push(yaz('dosyalar.json',oku('okutma/dosyalar.csv'),'Günlük okutma dosyalarının listesi, satır sayısı ve SHA-256 özeti'));
// Okutmalar: her kaynak için tek dosya (tüm ay), kayıtlar kaynak alanıyla
for(const k of ['pdks','kapi','yemekhane','servis']){
 const v=[];for(const f of oku('okutma/dosyalar.csv').filter(d=>d.kaynak===k))v.push(...oku('okutma/'+f.dosya_adi));
 ozet.push(yaz(`okutma_${k}.json`,v,`${k.toUpperCase()} okutmaları (tüm dönem). Saatler yerel saat (Europe/Istanbul)`));
}
// Bakması kolay örnek: 1 Ekim'in tüm kaynakları
const ornek=[];for(const k of ['pdks','kapi','yemekhane','servis'])oku(`okutma/${k}_20261001.csv`).forEach(o=>ornek.push({kaynak:k,...o}));
ornek.sort((a,b)=>a.zaman<b.zaman?-1:1);ozet.push(yaz('ornek_gun_20261001.json',ornek,'Örnek gün: 1 Ekim 2026 tüm kaynakların okutmaları, saate göre sıralı'));
for(const [a,n] of ozet)console.log(a.padEnd(28),String(n).padStart(7),(fs.statSync(path.join(J,a)).size/1048576).toFixed(1)+' MB');
