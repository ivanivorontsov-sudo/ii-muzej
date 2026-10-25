import fs from 'fs';
const UA={'User-Agent':'IvanMuseumBuilder/1.0 (personal)','Accept':'application/sparql-results+json'};
const q=`SELECT ?i ?l ?d ?img ?cr ?inc ?col ?sl WHERE { ?i wdt:P195 wd:MUS; wdt:P31 wd:Q3305213; wikibase:sitelinks ?sl . FILTER(?sl>8) ?i wdt:P18 ?img; rdfs:label ?l . FILTER(lang(?l)='ru')
 OPTIONAL{?i schema:description ?d FILTER(lang(?d)='ru')} OPTIONAL{?i wdt:P170 ?c . ?c rdfs:label ?cr FILTER(lang(?cr)='ru')}
 OPTIONAL{?i wdt:P571 ?inc} OPTIONAL{?i wdt:P195 ?cc . ?cc rdfs:label ?col FILTER(lang(?col)='ru')} } ORDER BY DESC(?sl) LIMIT 30`;
const out=[];const seen=new Set();
for(const M of ['Q19675','Q132783','Q160112','Q180788','Q190804','Q51252','Q183334','Q23402','Q160236','Q211043','Q2983474','Q1471477']){let j;try{const r=await fetch('https://query.wikidata.org/sparql?query='+encodeURIComponent(q.replace('MUS',M)),{headers:UA});j=await r.json();}catch(e){console.log(M,'fail');continue}
console.log(M,j.results.bindings.length);for(const b of j.results.bindings){const qid=b.i.value.split('/').pop();if(seen.has(qid))continue;seen.add(qid);
 out.push({qid,hall:'Шедевры живописи',title:b.l.value,desc:b.d?.value||'',author:b.cr?.value||'',date:b.inc?.value?.slice(0,4)||'',collection:b.col?.value||'',img:b.img.value,src:'https://www.wikidata.org/wiki/'+qid});}}
fs.writeFileSync('paint.json',JSON.stringify(out));console.log(out.length);
