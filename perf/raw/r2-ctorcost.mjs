// Attribution of RenderedBlock construction work on the keystroke benchmark document (node, no DOM).
// Run from Editor/ (needs its node_modules):  cp ../perf/raw/r2-ctorcost.mjs .r2.mjs && node .r2.mjs; rm .r2.mjs
// Replays, for every block, what the round-1 constructor did on each keystroke: slice the source,
// test the mermaid / '$' / fence patterns, JSON.stringify the reference map. 20-run medians.
import MarkdownIt from 'markdown-it';
import footnote from 'markdown-it-footnote';
import taskLists from 'markdown-it-task-lists';
import texmath from 'markdown-it-texmath';
import {blockOnly, documentStructure} from './src/structure.js';
function section(i,rep){
  let s=`\n## 第 ${rep}-${i} 节 · 水位与流量记录\n\n`;
  s+='这是一段用于测量的中文正文，包含**加粗**、*斜体*、`行内代码`和[链接](https://example.com)。'.repeat(3)+'\n\n';
  s+='| 站点 | 水位 (m) | 流量 (m³/s) |\n| --- | ---: | ---: |\n';
  for(let j=1;j<5;j++)s+=`| 站 ${i}-${j} | ${(10+j*0.37).toFixed(2)} | ${(120+i*j).toFixed(1)} |\n`;
  s+=`\n- [ ] 待办 ${i}\n- [x] 已完成 ${i}\n\n\`\`\`python\ndef flow_${i}(h):\n    return ${i} * h ** 1.5\n\`\`\`\n`;
  if(i%20===0)s+=`\n$$Q = ${i} \\cdot b \\sqrt{2g} H^{3/2}$$\n\n行内公式 $h_${i}=${i}$ 见[资料][r${i}]。\n\n[r${i}]: https://example.com/${rep}/${i}\n`;
  if(i%100===0)s+='\n```mermaid\ngraph TD\n  A-->B\n```\n';
  return s;
}
let text='# Folio 按键基准\n';
for(let rep=0;Buffer.byteLength(text)<1_000_000;rep++)for(let i=1;i<=200;i++)text+=section(i,rep);
const engine={renderToString:t=>t};
const structure=blockOnly(new MarkdownIt({html:true,linkify:true}).use(footnote).use(taskLists,{enabled:false}).use(texmath,{engine,delimiters:'dollars'}));
const mermaidFence=/^\s*(`{3,}|~{3,})mermaid[^\n]*\n([\s\S]*?)\n\s*(?:`{3,}|~{3,})\s*$/;
const time=(f,n=20)=>{const r=[];for(let i=0;i<n;i++){const t=performance.now();f();r.push(performance.now()-t)}r.sort((a,b)=>a-b);return +r[n>>1].toFixed(2)};
const parsed=documentStructure(structure,text);
console.log('blocks',parsed.blocks.length,'refs',Object.keys(parsed.env.references||{}).length);
console.log('parse ms',time(()=>documentStructure(structure,text),10));
console.log('slice ms',time(()=>{for(const b of parsed.blocks)text.slice(b.from,b.to)}));
const raws=parsed.blocks.map(b=>text.slice(b.from,b.to));
console.log('scans ms (mermaid+$+fence)',time(()=>{let x=0;for(const raw of raws){x+=mermaidFence.test(raw)?1:(raw.includes('$')?2:0)+(/```|~~~/.test(raw)?4:0)}return x}));
console.log('JSON.stringify(references) per block ms',time(()=>{for(const b of parsed.blocks)JSON.stringify(parsed.env.references)}));
