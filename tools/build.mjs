import fs from 'fs';import crypto from 'crypto';
const BAN=/политич|ядерн|оруж|ракет|военн|танк|бомб|политик|партия|президент|выбор|депутат|пропаганд|революц|диктат|фашиз|нацизм|коммунизм|ленин|сталин|гитлер|муссолини|наполеон|император|царь|король|королев|король|войн|битв|сражен|армия|флаг|герб|стрелецк|манифест|булла|портрет .*(министр|генерал)/i;
const thumb=u=>{let n=decodeURIComponent(u.split('/Special:FilePath/')[1].split('?')[0]).replace(/ /g,'_');
 if(!/\.(jpe?g|png)$/i.test(n))return null;const h=crypto.createHash('md5').update(n).digest('hex');
 return `https://upload.wikimedia.org/wikipedia/commons/thumb/${h[0]}/${h.slice(0,2)}/${encodeURIComponent(n)}/500px-${encodeURIComponent(n)}`;};
const all=[...JSON.parse(fs.readFileSync('wd.json')),...JSON.parse(fs.readFileSync('paint.json'))];
const AUD=Object.fromEntries(JSON.parse(fs.readFileSync('audit.json')).map(r=>[r.qid,r]));
const WHITELIST={Q7596743:'Гносис — античный мозаичист (IV в. до н. э.), дата смерти неизвестна, произведение в общественном достоянии'};
const removed=[];
function verdict(e){const a=AUD[e.qid];if(!a)return ['нет данных аудита'];
 let why=a.why.filter(w=>!(w.startsWith('возможна запрещённая')&&!/swastika|свастик|\bnazis?\b|hammer and sickle|серп и молот|\bsoviet|ссср|\bussr|red star|third reich|третий рейх|insignia/i.test(e.title+' '+e.desc+' '+a.file)));
 if(WHITELIST[e.qid])why=why.filter(w=>!w.startsWith('нет даты смерти'));
 if(a.restr)why.push('ограничение Commons «'+a.restr+'» (не авторское право: для публикации/коммерческого использования нужно разрешение учреждения культуры) — атрибуции недостаточно');
 for(const w of a.warn)if(/ВОВ/.test(w))why.push(w.replace(' — проверить','')+' (ГК РФ ст. 1281 п. 4: срок охраны в РФ ещё не истёк) — атрибуции недостаточно');
 return why;}
const halls=new Map();let skipped=0;
const ORDER=['Древний Египет','Античность','Археология мира','Шедевры живописи','Скульптура','Мозаики','Гобелены и ткани','Рукописи','Метеориты','Наука и техника'];
for(const e of all){const t=e.title+' '+e.desc;if(BAN.test(t)||/^Q\d+$/.test(e.title)){skipped++;continue}
 const vw=verdict(e);if(vw.length){if(!['Драгоценности','Палеонтология'].includes(e.hall))removed.push({hall:e.hall,title:e.title,qid:e.qid,file:AUD[e.qid]?.file,lic:AUD[e.qid]?.lic,why:vw});continue}
 const A=AUD[e.qid];
 const img=thumb(e.img);if(!img){skipped++;continue}
 const _d=(()=>{const a=AUD[e.qid];return a&&a.inception!=null?(a.inception<0?(-a.inception)+' до н. э.':String(a.inception)):''})();
 const ex={title:e.title,desc:e.desc?e.desc[0].toUpperCase()+e.desc.slice(1)+'.':'',author:e.author,date:_d,collection:e.collection,img,src:e.src,text_lic:'wikidata',img_author:A.artist.slice(0,160),img_lic:A.lic,img_lic_url:A.licUrl||(/^cc0$/i.test(A.lic)?'https://creativecommons.org/publicdomain/zero/1.0/deed.ru':/gfdl/i.test(A.lic)?'https://www.gnu.org/licenses/fdl-1.3.html':''),img_page:A.page,img_file:A.file,img_warn:A.warn.join('; ')};
 const key=e.hall;if(!halls.has(key))halls.set(key,[]);halls.get(key).push(ex);}
const out={version:1,halls:[]};
for(const hn of ORDER){const items=halls.get(hn)||[];
 let groups;
 if(hn==='Шедевры живописи'){const m=new Map();for(const x of items){const k=x.collection||'Разные собрания';if(!m.has(k))m.set(k,[]);m.get(k).push(x)}
  groups=[];for(const [k,v] of m)for(let i=0;i<Math.min(v.length,18);i+=6)groups.push({name:k+(i?` (${i/6+1})`:''),exhibits:v.slice(i,i+6)});}
 else{groups=[];const v=items.slice(0,48);for(let i=0;i<v.length;i+=6)groups.push({name:`${hn}: стеллаж ${i/6+1}`,exhibits:v.slice(i,i+6)});}
 for(let i=0;i<groups.length;i+=8){out.halls.push({name:hn+(i?` — часть ${i/8+1}`:''),shelves:groups.slice(i,i+8)})}}
fs.writeFileSync('../game/data/museum.json',JSON.stringify(out));fs.writeFileSync('removed.json',JSON.stringify(removed,null,1));
const lc={};for(const h of out.halls)for(const s of h.shelves)for(const x of s.exhibits){const k=/^(public domain|pd)/i.test(x.img_lic)?'Public domain':x.img_lic;lc[k]=(lc[k]||0)+1}fs.writeFileSync('licstats.json',JSON.stringify(lc,null,1));console.log('removed',removed.length,lc);
console.log('halls',out.halls.length,'exhibits',out.halls.reduce((a,h)=>a+h.shelves.reduce((b,s)=>b+s.exhibits.length,0),0),'skipped',skipped);
