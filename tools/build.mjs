import fs from 'fs';import crypto from 'crypto';
const BAN=/политич|ядерн|оруж|ракет|военн|танк|бомб|политик|партия|президент|выбор|депутат|пропаганд|революц|диктат|фашиз|нацизм|коммунизм|ленин|сталин|гитлер|муссолини|наполеон|император|царь|король|королев|король|войн|битв|сражен|армия|флаг|герб|стрелецк|манифест|булла|портрет .*(министр|генерал)/i;
const thumb=u=>{let n=decodeURIComponent(u.split('/Special:FilePath/')[1].split('?')[0]).replace(/ /g,'_');
 if(!/\.(jpe?g|png)$/i.test(n))return null;const h=crypto.createHash('md5').update(n).digest('hex');
 return `https://upload.wikimedia.org/wikipedia/commons/thumb/${h[0]}/${h.slice(0,2)}/${encodeURIComponent(n)}/500px-${encodeURIComponent(n)}`;};
const all=[...JSON.parse(fs.readFileSync('wd.json')),...JSON.parse(fs.readFileSync('paint.json'))];
const halls=new Map();let skipped=0;
const ORDER=['Древний Египет','Античность','Археология мира','Шедевры живописи','Скульптура','Мозаики','Гобелены и ткани','Рукописи','Метеориты','Наука и техника'];
for(const e of all){const t=e.title+' '+e.desc;if(BAN.test(t)||/^Q\d+$/.test(e.title)){skipped++;continue}
 const img=thumb(e.img);if(!img){skipped++;continue}
 const ex={title:e.title,desc:e.desc?e.desc[0].toUpperCase()+e.desc.slice(1)+'.':'',author:e.author,date:e.date,collection:e.collection,img,src:e.src,lic:'Wikidata (CC0); изображение — Wikimedia Commons, лицензия на странице файла'};
 const key=e.hall;if(!halls.has(key))halls.set(key,[]);halls.get(key).push(ex);}
const out={version:1,halls:[]};
for(const hn of ORDER){const items=halls.get(hn)||[];
 let groups;
 if(hn==='Шедевры живописи'){const m=new Map();for(const x of items){const k=x.collection||'Разные собрания';if(!m.has(k))m.set(k,[]);m.get(k).push(x)}
  groups=[];for(const [k,v] of m)for(let i=0;i<Math.min(v.length,18);i+=6)groups.push({name:k+(i?` (${i/6+1})`:''),exhibits:v.slice(i,i+6)});}
 else{groups=[];const v=items.slice(0,48);for(let i=0;i<v.length;i+=6)groups.push({name:`${hn}: стеллаж ${i/6+1}`,exhibits:v.slice(i,i+6)});}
 for(let i=0;i<groups.length;i+=8){out.halls.push({name:hn+(i?` — часть ${i/8+1}`:''),shelves:groups.slice(i,i+8)})}}
fs.writeFileSync('../game/data/museum.json',JSON.stringify(out));
console.log('halls',out.halls.length,'exhibits',out.halls.reduce((a,h)=>a+h.shelves.reduce((b,s)=>b+s.exhibits.length,0),0),'skipped',skipped);
