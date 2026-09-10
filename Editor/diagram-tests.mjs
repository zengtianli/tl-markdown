import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
import {mermaidLoader, drawDiagram} from './src/diagram.js';

function fixture() {
  const element = {dataset:{}, classList:{add() {}}, textContent:'', innerHTML:''};
  let measures = 0;
  return {element, source:'flowchart LR\n A --> B', sanitize:svg=>svg, measure:()=>measures++, measures:()=>measures};
}

test('drawing starts without an IntersectionObserver callback', async () => {
  const item=fixture(); let calls=0;
  const task=drawDiagram({...item, load:async()=>({render:async(id, source)=>{calls++;assert.equal(source,item.source);return {svg:'<svg></svg>'};}})});
  await task.done;
  assert.equal(calls,1);assert.equal(item.element.dataset.diagramState,'ready');assert.equal(item.measures(),1);
});

test('a renderer that never resolves leaves loading with a readable timeout', async () => {
  const item=fixture();
  await drawDiagram({...item,timeout:5,load:async()=>({render:()=>new Promise(()=>{})})}).done;
  assert.equal(item.element.dataset.diagramState,'error');assert.match(item.element.textContent,/绘制超时/);
});

test('disposed widgets never get an obsolete render result', async () => {
  const item=fixture();let finish;
  const task=drawDiagram({...item,load:async()=>({render:()=>new Promise(resolve=>{finish=resolve;})})});
  await new Promise(resolve=>setImmediate(resolve));task.dispose();finish({svg:'<svg></svg>'});await task.done;
  assert.equal(item.element.innerHTML,'');assert.equal(item.measures(),0);
});

test('local loader shares work, rejects a missing API, and allows retry', async () => {
  const scope={}, scripts=[];
  const document={createElement:()=>({remove(){}}),head:{append:script=>scripts.push(script)}};
  const load=mermaidLoader(scope,document,100);
  const first=load();assert.equal(load(),first);
  await new Promise(resolve=>setImmediate(resolve));assert.equal(scripts[0].src,'mermaid.js');scripts[0].onload();
  await assert.rejects(first,/组件不完整/);
  const retry=load();await new Promise(resolve=>setImmediate(resolve));scope.TLMermaid={render(){}};scripts[1].onload();
  assert.equal(await retry,scope.TLMermaid);
});

test('a script that emits neither load nor error has a bounded failure', async () => {
  const scope={},document={createElement:()=>({remove(){}}),head:{append(){}}};
  await assert.rejects(mermaidLoader(scope,document,5)(),/加载超时/);
});

test('production Mermaid bundle initializes with no network or runtime imports', async () => {
  // This verifies the shipped asset initializes offline, not SVG layout. Real
  // WKWebView geometry and final appearance still require in-app verification.
  const context=vm.createContext({console,setTimeout,clearTimeout});
  context.window=context;context.globalThis=context;
  vm.runInContext(await readFile('../Resources/Editor/mermaid.js','utf8'),context,{timeout:5000});
  assert.equal(typeof context.TLMermaid.render,'function');
});
