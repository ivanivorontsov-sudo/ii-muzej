import fs from 'fs';
const UA={'User-Agent':'IvanMuseumBuilder/1.0 (personal, ivanivorontsov)','Accept':'application/sparql-results+json'};
const cats=[
 ['egypt','Древний Египет','?i wdt:P2596 wd:Q11768 .',''],
 ['greece','Античность','?i wdt:P2596 ?cu . VALUES ?cu {wd:Q11772 wd:Q1747689} .',''],
 ['paint','Шедевры живописи','?i wdt:P31 wd:Q3305213 .',''],
 ['sculpt','Скульптура','?i wdt:P31 wd:Q860861 .',''],
 ['fossil','Палеонтология','?i wdt:P31 wd:Q40050 .',''],
 ['arch','Археология мира','?i wdt:P31 wd:Q220659 .',''],
 ['instr','Наука и техника','?i wdt:P31 wd:Q1183543 .',''],
 ['meteor','Метеориты','?i wdt:P31 wd:Q60186 .',''],
 ['gem','Драгоценности','?i wdt:P31 wd:Q1364556 .',''],
 ['tap','Гобелены и ткани','?i wdt:P31 wd:Q184296 .',''],
 ['mosaic','Мозаики','?i wdt:P31 wd:Q133067 .',''],
 ['manus','Рукописи','?i wdt:P31 wd:Q87167 .',''],
];
const out=[];
for(const [id,hall,where] of cats){
 const q=`SELECT ?i ?l ?d ?img ?cr ?inc ?col ?sl WHERE { ${where} ?i wdt:P18 ?img; wikibase:sitelinks ?sl; rdfs:label ?l . FILTER(lang(?l)='ru')
 FILTER NOT EXISTS{?i wdt:P136 wd:Q742333} FILTER NOT EXISTS{?i wdt:P136 wd:Q215080}
 
 OPTIONAL{?i schema:description ?d FILTER(lang(?d)='ru')} OPTIONAL{?i wdt:P170 ?c . ?c rdfs:label ?cr FILTER(lang(?cr)='ru')}
 OPTIONAL{?i wdt:P571 ?inc} OPTIONAL{?i wdt:P195 ?cc . ?cc rdfs:label ?col FILTER(lang(?col)='ru')} } ORDER BY DESC(?sl) LIMIT 90`;
 try{const r=await fetch('https://query.wikidata.org/sparql?query='+encodeURIComponent(q),{headers:UA});
 const j=await r.json();const seen=new Set();let n=0;
 for(const b of j.results.bindings){const qid=b.i.value.split('/').pop();if(seen.has(qid)||out.some(o=>o.qid===qid))continue;seen.add(qid);
  out.push({qid,hall,title:b.l.value,desc:b.d?.value||'',author:b.cr?.value||'',date:b.inc?.value?.slice(0,4)||'',collection:b.col?.value||'',
   img:b.img.value.replace('http:','https:')+'?width=640',src:'https://www.wikidata.org/wiki/'+qid,lic:'Wikimedia Commons (см. страницу файла)'});n++;}
 console.error(id,r.status,n);}catch(e){console.error(id,e.message)}
 await new Promise(r=>setTimeout(r,1500));
}
fs.writeFileSync('wd.json',JSON.stringify(out));
