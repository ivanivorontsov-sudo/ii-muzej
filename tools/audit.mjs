import fs from 'fs';
const UA={'User-Agent':'IIMuzejAudit/1.0 (ivanivorontsov-sudo; personal)'};
const pool=[...JSON.parse(fs.readFileSync('wd.json')),...JSON.parse(fs.readFileSync('paint.json'))];
const fname=u=>decodeURIComponent(u.split('/Special:FilePath/')[1].split('?')[0]).replace(/_/g,' ');
const strip=s=>String(s||'').replace(/<[^>]+>/g,'').replace(/\s+/g,' ').trim();
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
async function J(u){for(let i=0;i<4;i++){try{const r=await fetch(u,{headers:UA});if(r.ok)return await r.json()}catch(e){}await sleep(5000*(i+1))}console.error('FAIL',u.slice(0,120));return null}
// 1. Commons
const meta={};const files=[...new Set(pool.map(e=>fname(e.img)))];
for(let i=0;i<files.length;i+=25){const t=files.slice(i,i+25).map(f=>'File:'+f).join('|');
 const j=await J('https://commons.wikimedia.org/w/api.php?action=query&format=json&prop=imageinfo&iiprop=extmetadata|url&titles='+encodeURIComponent(t));
 const norm={};for(const n of j?.query?.normalized||[])norm[n.to]=n.from;
 for(const p of Object.values(j?.query?.pages||{})){const m=p.imageinfo?.[0]?.extmetadata||{};const v=k=>strip(m[k]?.value);
  meta[p.title.replace(/^File:/,'')]={missing:!!p.missing,lic:v('LicenseShortName'),licUrl:v('LicenseUrl'),license:v('License'),artist:v('Artist'),credit:v('Credit').slice(0,200),restr:v('Restrictions'),attr:v('AttributionRequired'),nonfree:v('NonFree'),usage:v('UsageTerms'),page:p.imageinfo?.[0]?.descriptionurl||''};}
 await sleep(300);}
// 2. Wikidata: creators + death
const ents={};const get=async ids=>{ids=ids.filter(x=>!ents[x]);for(let i=0;i<ids.length;i+=50){const j=await J('https://www.wikidata.org/w/api.php?action=wbgetentities&format=json&props=claims|labels&languages=ru|en&ids='+ids.slice(i,i+50).join('|'));Object.assign(ents,j?.entities||{});await sleep(300)}};
await get(pool.map(e=>e.qid));
const cl=(q,p)=>(ents[q]?.claims?.[p]||[]).map(c=>c.mainsnak?.datavalue?.value).filter(Boolean);
const creators=new Set();for(const e of pool)for(const v of cl(e.qid,'P170'))creators.add(v.id);
await get([...creators]);
const yr=t=>t&&t.time?parseInt(t.time.slice(0,5)):null;
// 3. rules
const OK=/^(public domain|pd\b|pd-|cc0|gfdl|gnu free|fal\b|free art|cc[- ]by(-sa)?[- ]\d|cc[- ]by(-sa)?$|attribution|no restrictions|copyrighted free use)/i;
const INSIG=/insignia|swastika|свастик|\bnazi|hammer and sickle|серп и молот|\bsoviet|ссср|\bussr|red star|third reich|третий рейх/i;
const res=[];const Y=2026;
for(const e of pool){const f=fname(e.img);const m=meta[f]||{missing:true};const why=[];const warn=[];
 const deaths=cl(e.qid,'P170').map(c=>({id:c.id,name:ents[c.id]?.labels?.ru?.value||ents[c.id]?.labels?.en?.value||c.id,d:cl(c.id,'P570').map(yr).filter(x=>x)[0]??null,anon:c.id==='Q4233718'||!cl(c.id,'P31').some(v=>v.id==='Q5')}));
 const inc=cl(e.qid,'P571').map(yr).filter(x=>x)[0]??null;
 if(m.missing)why.push('файл отсутствует на Commons');
 if(m.nonfree&&m.nonfree!=='false')why.push('несвободный файл (NonFree)');
 if(/fair use|non-free|добросовестн/i.test(m.lic+m.usage))why.push('fair use');
 if(/\b(nc|nd)\b/i.test(m.lic))why.push('лицензия с NC/ND: '+m.lic);
 else if(!m.missing&&!OK.test(m.lic))why.push('лицензия файла не из списка разрешённых: '+(m.lic||'нет'));
 for(const c of deaths){if(c.d&&c.d>=Y-70)why.push(`автор произведения ${c.name} умер в ${c.d}: срок охраны (жизнь+70) не истёк`);
  else if(c.d&&c.d>=Y-74)warn.push(`автор ${c.name} умер в ${c.d}: в РФ +4 года для участников ВОВ/работавших в войну — проверить`);
  else if(!c.d&&!c.anon&&(inc===null||inc>1850))why.push(`нет даты смерти автора ${c.name}`);}
 if(inc&&inc>=1956&&!deaths.some(c=>c.anon))why.push(`произведение создано в ${inc}: вероятно охраняется`);
 if(m.restr){if(/insignia/i.test(m.restr))why.push('ограничение: символика (insignia)');else warn.push('ограничения: '+m.restr);}
 if(INSIG.test(e.title+' '+e.desc+' '+f))why.push('возможна запрещённая/политическая символика');
 if(/PD-US|PD-1996|PD-US-expired/i.test(m.lic+m.license)&&!/PD-old|PD-Art/i.test(m.lic))warn.push('PD только в США ('+m.lic+') — может охраняться в ЕС/РФ');
 if(/PD-Art|PD-scan/i.test(m.lic+m.license))warn.push('PD-Art: фото плоской работы, статус = статус оригинала');
 const sculpt=['Скульптура','Мозаики'].includes(e.hall)||/скульпт|статуя|памятник|монумент|sculpture|statue/i.test(e.desc);
 if(sculpt&&/cc|attribution/i.test(m.lic))warn.push('фото объёмного объекта: действует лицензия фотографа ('+m.lic+'), указываем автора фото');
 res.push({qid:e.qid,hall:e.hall,title:e.title,file:f,inception:inc,creators:deaths,...m,ok:why.length===0,why,warn});}
fs.writeFileSync('audit.json',JSON.stringify(res,null,1));
console.log('pool',res.length,'ok',res.filter(r=>r.ok).length);
