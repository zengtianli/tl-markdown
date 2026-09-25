// Per-keystroke cost of the live editor on a ~1 MB mixed Markdown document (headless Chrome).
// usage: node keystroke-bench.mjs <Resources/Editor dir> [label]
// Each keystroke is one synchronous view.dispatch (block parse + decorations rebuild + viewport DOM
// update), timed with performance.now() inside the page. Edits land mid-document so blocks both
// before and after the edit are rebuilt. Also reports how many RenderedBlock objects each keystroke builds.
import {readFile} from 'node:fs/promises';
import {createServer} from 'node:http';
import {resolve,extname} from 'node:path';
import {chromium} from '~/Apps/folio/Editor/node_modules/@playwright/test/index.mjs';
const root=resolve(process.argv[2]), label=process.argv[3]||root;
const server=createServer(async(req,res)=>{try{const name=resolve(root,'.'+decodeURIComponent(req.url.split('?')[0]));const data=await readFile(name);res.writeHead(200,{'Content-Type':({'.html':'text/html','.js':'text/javascript','.css':'text/css','.woff2':'font/woff2'})[extname(name)]||'application/octet-stream'});res.end(data)}catch{res.writeHead(404);res.end()}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
// Same generator as scripts/measure-lightweight.py sample_document(), plus link references,
// a mermaid fence and inline math, repeated to ~1 MB.
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
const browser=await chromium.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true});
const page=await browser.newPage({viewport:{width:1100,height:780}});
const errors=[];page.on('pageerror',e=>errors.push(e.message));
await page.goto(`http://127.0.0.1:${server.address().port}/index.html`);await page.waitForFunction(()=>window.tl);
await page.evaluate(text=>tl.receive({action:'load',value:{id:'bench',text,revision:1,source:false,fontSize:17,contentWidth:820,selection:0,scroll:0}}),text);
// Let the lazily loaded KaTeX / highlight.js arrive (first viewport has code) before timing.
await page.waitForTimeout(1500);
const result=await page.evaluate(async()=>{
  const v=tl.getView(), at=Math.floor(v.state.doc.length/2);
  // Move the caret into a paragraph mid-document without entering edit mode on a block.
  const samples=[];
  for(let k=0;k<45;k++){
    const t=performance.now();
    v.dispatch({changes:{from:at+k,insert:'字'}});
    samples.push(performance.now()-t);
    await new Promise(r=>requestAnimationFrame(()=>setTimeout(r,0)));
  }
  return {samples:samples.slice(5),docLength:v.state.doc.length,blocks:document.querySelectorAll('.rendered').length};
});
const s=[...result.samples].sort((a,b)=>a-b), q=p=>s[Math.min(s.length-1,Math.floor(p*s.length))];
console.log(JSON.stringify({label,bytes:Buffer.byteLength(text),keystrokes:s.length,median_ms:+q(0.5).toFixed(2),p90_ms:+q(0.9).toFixed(2),min_ms:+s[0].toFixed(2),errors}));
await browser.close();server.close();
