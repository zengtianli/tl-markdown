import {EditorState, StateEffect, StateField} from '@codemirror/state';
import {EditorView, Decoration, WidgetType, keymap, drawSelection, highlightActiveLine, placeholder} from '@codemirror/view';
import {defaultKeymap, history, historyKeymap, undo, redo, indentWithTab} from '@codemirror/commands';
import {markdown, markdownKeymap, insertNewlineContinueMarkupCommand} from '@codemirror/lang-markdown';
import {syntaxHighlighting, defaultHighlightStyle} from '@codemirror/language';
import {search, searchKeymap, openSearchPanel, findNext, getSearchQuery, SearchCursor} from '@codemirror/search';
import MarkdownIt from 'markdown-it';
import footnote from 'markdown-it-footnote';
import taskLists from 'markdown-it-task-lists';
import texmath from 'markdown-it-texmath';
import DOMPurify from 'dompurify';
import {mermaidLoader, drawDiagram} from './diagram.js';
import {blockOnly, documentStructure} from './structure.js';
import 'highlight.js/styles/github.css';
import './style.css';

const post = data => { window.webkit?.messageHandlers?.editor?.postMessage(data); window.dispatchEvent(new CustomEvent('tl-message',{detail:data})); };
const previewOnly = Boolean(window.TL_PREVIEW_ONLY);
window.addEventListener('error', e => post({type:'error', message:e.message}));
window.addEventListener('unhandledrejection', e => post({type:'error', message:String(e.reason)}));
// KaTeX (~0.3 MB of script plus its stylesheet) and highlight.js (~0.2 MB, 37 language grammars
// built at start-up) are fetched the first time a formula or a fenced code block with a language
// is actually rendered; documents without them never parse either. Until one arrives, formulas
// show their TeX source and code shows unhighlighted; each block drawn that way is marked
// (data-pending) while it renders, and only those blocks re-render once the component arrives.
// Mermaid follows the same rule in diagram.js.
const lazy={
  katex:{files:['katex.css','katex.js'],global:'TLKatex',state:'idle',failure:'本地公式组件加载失败，公式暂以源码显示'},
  hljs:{files:['highlight.js'],global:'TLHljs',state:'idle',failure:'本地代码高亮组件加载失败，代码暂不着色'}
};
let missing=null; // components the block being rendered asked for but does not have yet
function ready(name) {
  const asset=lazy[name];
  if(asset.state==='ready')return window[asset.global];
  if(asset.state==='failed')return null;
  missing?.add(name);
  if(asset.state==='loading')return null;
  asset.state='loading';
  const loaded=file=>new Promise((resolve,reject)=>{
    const element=file.endsWith('.css')?Object.assign(document.createElement('link'),{rel:'stylesheet',href:file}):Object.assign(document.createElement('script'),{src:file});
    element.onload=resolve;element.onerror=reject;document.head.append(element);
  });
  Promise.all(asset.files.map(loaded)).then(()=>{
    if(!window[asset.global])throw new Error('incomplete');
    asset.state='ready';
    document.querySelectorAll('.rendered[data-pending]').forEach(element=>{if(element.dataset.pending.split(' ').includes(name))element._rerender?.()});
  }).catch(()=>{asset.state='failed';post({type:'error',message:asset.failure});});
  return null;
}
const mathEngine={renderToString(tex,options) {
  const katex=ready('katex');
  return katex?katex.renderToString(tex,options):`<span class="math-pending">${md.utils.escapeHtml(tex)}</span>`;
}};
const md = new MarkdownIt({html:true, linkify:true, breaks:false, highlight(code,lang) {
  if(!lang)return '';
  const hljs=ready('hljs');
  return hljs?.getLanguage(lang) ? hljs.highlight(code,{language:lang,ignoreIllegals:true}).value : '';
}}).use(footnote).use(taskLists,{enabled:false}).use(texmath,{engine:mathEngine, delimiters:'dollars', katexOptions:{throwOnError:false,strict:false,trust:false}});
// Same options and plugins, block pass only: used for block ranges, headings and references.
const structure = blockOnly(new MarkdownIt({html:true, linkify:true, breaks:false}).use(footnote).use(taskLists,{enabled:false}).use(texmath,{engine:mathEngine, delimiters:'dollars'}));

const modeEffect = StateEffect.define(), editingEffect = StateEffect.define();
const modeField = StateField.define({create:()=>false, update:(v,tr)=>tr.effects.reduce((x,e)=>e.is(modeEffect)?e.value:x,v)});
const editingField = StateField.define({create:()=>false, update:(v,tr)=>tr.effects.reduce((x,e)=>e.is(editingEffect)?e.value:x,v)});
const cached = new WeakMap();
let currentID = '', currentRevision = 0, view, hydrating = false;
const sessions = new Map();
const loadMermaid = mermaidLoader();
function parse(doc) {
  if(cached.has(doc)) return cached.get(doc);
  const result=documentStructure(structure,doc.toString());
  // Compared by every block widget; serialized once per parse, not once per block.
  result.referenceKey=JSON.stringify(result.env.references);
  cached.set(doc,result); return result;
}
function assetURL(src) {
  if(/^(https?:|data:image\/)/i.test(src))return src;
  if(/^[a-z][a-z\d+.-]*:/i.test(src))return '';
  let decoded; try {decoded=decodeURIComponent(src)}catch{decoded=src}
  return 'mdasset://image?id='+encodeURIComponent(currentID)+'&path='+encodeURIComponent(decoded);
}
function activateBlock(v,from,to,event) {
  if(previewOnly)return;
  event.preventDefault();
  let position=from;
  // Place the source cursor near the clicked word, not always at the document start.
  const target=event.target.closest?.('.rendered');
  const caret=document.caretRangeFromPoint?.(event.clientX,event.clientY);
  if(target&&caret&&target.contains(caret.startContainer)) {
    const pre=document.createRange(); pre.selectNodeContents(target); pre.setEnd(caret.startContainer,caret.startOffset);
    const before=pre.toString(), word=before.match(/[^\s<>]{1,20}$/)?.[0];
    const raw=v.state.doc.sliceString(from,to);
    if(word) {const at=raw.indexOf(word); if(at>=0)position=from+at+word.length;}
  }
  v.dispatch({selection:{anchor:Math.min(to,position)},effects:editingEffect.of(true)}); v.focus();
}
const mermaidFence=/^\s*(`{3,}|~{3,})mermaid[^\n]*\n([\s\S]*?)\n\s*(?:`{3,}|~{3,})\s*$/;
// Every edit rebuilds one widget per block of the document, so construction and eq() only store
// and compare; anything that scans the block's source happens in toDOM, for blocks on screen.
class RenderedBlock extends WidgetType {
  constructor(raw,kind,from,to,id,references,referenceKey) {super();Object.assign(this,{raw,kind,from,to,id,references,referenceKey});}
  eq(other){return this.raw===other.raw&&this.kind===other.kind&&this.from===other.from&&this.id===other.id&&this.referenceKey===other.referenceKey;}
  get estimatedHeight(){return this.kind==='table_open'?120:this.kind==='fence'?110:this.kind==='heading_open'?58:48;}
  toDOM(v) {
    const element=document.createElement('div'); element.className='rendered'; element.dataset.from=this.from;
    if(this.kind==='reference-definition'){element.style.display='none';return element;}
    const edit=(event)=>activateBlock(v,this.from,this.to,event);
    element.addEventListener('mousedown',e=>{if(!e.target.closest('a,button,summary,input'))edit(e)});
    if(this.kind==='frontmatter') {
      const details=document.createElement('details'), summary=document.createElement('summary'), code=document.createElement('pre');
      summary.textContent='文档属性 · Frontmatter'; code.textContent=this.raw; details.append(summary,code); element.append(details); return element;
    }
    if(this.kind==='footnote') element.id='note-'+this.raw.match(/^\[\^([^\]]+)\]:/)?.[1];
    const mermaid=mermaidFence.exec(this.raw);
    if(mermaid) {
      element.classList.add('diagram');
      element._diagram=drawDiagram({element,source:mermaid[2],load:loadMermaid,
        sanitize:svg=>DOMPurify.sanitize(svg,{USE_PROFILES:{svg:true,svgFilters:true}}),measure:()=>v.requestMeasure()});
      return element;
    }
    this.fill(element,v);
    element._rerender=()=>{element.replaceChildren();this.fill(element,v);v.requestMeasure();};
    return element;
  }
  // Markdown output plus its controls; records which lazy components were missing while rendering.
  fill(element,v) {
    missing=new Set();
    try {this.renderMarkdown(element,v);}
    finally {
      if(missing.size)element.dataset.pending=[...missing].join(' ');else delete element.dataset.pending;
      missing=null;
    }
  }
  renderMarkdown(element,v) {
    if(this.kind==='footnote') {
      const m=this.raw.match(/^\[\^([^\]]+)\]:\s*([\s\S]*)/);
      element.innerHTML=DOMPurify.sanitize(md.renderInline((m?.[1]||'')+'. '+(m?.[2]||this.raw)));return;
    }
    // Footnote references across independently rendered blocks remain navigable.
    let input=['fence','code_block'].includes(this.kind)?this.raw:this.raw.replace(/(`+)[\s\S]*?\1|(?<!\\)\[\^([^\]]+)\](?!:)/g,(whole,ticks,id)=>ticks?whole:`<sup><a href="#note-${md.utils.escapeHtml(id)}">${md.utils.escapeHtml(id)}</a></sup>`);
    let taskIndex=0;
    const html=md.render(input,{references:this.references}).replace(/<input\b[^>]*type="checkbox"[^>]*>/g,tag=>`<button class="task-toggle" data-task="${taskIndex++}" role="checkbox" aria-checked="${tag.includes('checked')}">${tag.includes('checked')?'☑':'☐'}</button>`);
    element.innerHTML=DOMPurify.sanitize(html,{FORBID_TAGS:['script','style','iframe','object','embed','form','input'],ADD_TAGS:['eq','eqn']});
    element.querySelectorAll('.task-toggle').forEach(button=>button.addEventListener('click',event=>{
      event.preventDefault();event.stopPropagation();
      if(previewOnly)return;
      const tasks=[...this.raw.matchAll(/^\s*[-+*]\s+\[([ xX])\]/gm)];
      const task=tasks[Number(button.dataset.task)];if(!task)return;
      const at=this.from+task.index+task[0].lastIndexOf('[')+1;
      v.dispatch({changes:{from:at,to:at+1,insert:task[1]===' '?'x':' '}});
    }));
    element.querySelectorAll('img').forEach(img=>{
      const raw=img.getAttribute('src')||''; img.src=assetURL(raw); img.loading='lazy';
      img.addEventListener('load',()=>v.requestMeasure());
      img.addEventListener('error',()=>{const error=document.createElement('span');error.className='missing-image';error.textContent='图片无法显示：'+raw;img.replaceWith(error);v.requestMeasure();});
    });
    element.querySelectorAll('a').forEach(a=>a.addEventListener('click',e=>{e.preventDefault();post({type:'link',id:this.id,href:a.getAttribute('href')});}));
    element.querySelectorAll('pre').forEach(pre=>{
      const copy=document.createElement('button');copy.className='copy-code';copy.textContent='复制';
      copy.addEventListener('click',async e=>{e.stopPropagation();const text=pre.querySelector('code')?.textContent??'';
        try{await navigator.clipboard.writeText(text);copy.textContent='已复制'}catch{post({type:'copy',text})}
      });pre.append(copy);
    });
    element.querySelectorAll('table').forEach(table=>{const wrap=document.createElement('div');wrap.className='table-scroll';table.replaceWith(wrap);wrap.append(table)});
  }
  destroy(dom){dom._diagram?.dispose();}
  // Widgets own pointer events; CodeMirror must not replace the block before a button's click fires.
  ignoreEvent(){return true;}
}
function decorations(state) {
  if(state.field(modeField))return Decoration.none;
  const active=state.field(editingField), ranges=[];
  const parsed=parse(state.doc);
  for(const block of parsed.blocks) {
    const selected=active&&state.selection.ranges.some(s=>s.from<=block.to&&s.to>=block.from);
    if(!selected)ranges.push(Decoration.replace({widget:new RenderedBlock(state.doc.sliceString(block.from,block.to),block.kind,block.from,block.to,currentID,parsed.env.references,parsed.referenceKey),block:true}).range(block.from,block.to));
  }
  return Decoration.set(ranges,true);
}
const renderedField=StateField.define({create:decorations,update(value,tr){
  return tr.docChanged||tr.selection||tr.effects.some(e=>e.is(modeEffect)||e.is(editingEffect))?decorations(tr.state):value;
},provide:f=>EditorView.decorations.from(f)});
function position(){return {type:'position',id:currentID,selection:view.state.selection.main.head,scroll:view.scrollDOM.scrollTop};}
let positionTimer;
function notifyPosition(){clearTimeout(positionTimer);positionTimer=setTimeout(()=>{if(currentID)post(position())},100);}
let lastOutline='';
function outline(){if(currentID){const items=parse(view.state.doc).headings,key=currentID+JSON.stringify(items);if(key!==lastOutline){lastOutline=key;post({type:'outline',id:currentID,items})}}}
let countTimer;
function searchCount(){
  clearTimeout(countTimer);countTimer=setTimeout(()=>{
    const panel=document.querySelector('.cm-search');if(!panel)return;
    let label=panel.querySelector('.match-count');if(!label){label=document.createElement('span');label.className='match-count';label.setAttribute('aria-live','polite');panel.append(label)}
    const query=getSearchQuery(view.state);if(!query.search||!query.valid){label.textContent='';return;}
    let count=0,current=0,cursor=query.getCursor(view.state),result;
    while(!(result=cursor.next()).done){count++;if(result.value.from<=view.state.selection.main.from)current=count;if(count>=10000)break;}
    label.textContent=count>=10000?'10,000+ 个匹配':`${current} / ${count} 个匹配`;
  },60);
}
function changed(){if(!hydrating&&currentID)post({...position(),type:'change',text:view.state.doc.toString()});}
function wrap(before,after=before) {
  const range=view.state.selection.main, selected=view.state.sliceDoc(range.from,range.to);
  view.dispatch({changes:{from:range.from,to:range.to,insert:before+selected+after},selection:{anchor:range.from+before.length,head:range.from+before.length+selected.length},effects:editingEffect.of(true)});view.focus();return true;
}
function setMode(source){view.dispatch({effects:modeEffect.of(source)});document.body.classList.toggle('source',source);post({type:'mode',source});}
function find(){setMode(true);openSearchPanel(view);searchCount();return true;}
async function acceptImage(file){
  if(!file||!file.type.startsWith('image/'))return false;
  const id=currentID;if(!id)return false;
  if(file.size>40_000_000){post({type:'error',message:'图片超过 40 MB，请压缩后插入。'});return true;}
  const reader=new FileReader();reader.onload=()=>post({type:'image',id,mime:file.type,data:String(reader.result).split(',')[1]});reader.readAsDataURL(file);return true;
}
const phrases=EditorState.phrases.of({'Find':'查找','Replace':'替换','next':'下一项','previous':'上一项','all':'选择全部','match case':'区分大小写','regexp':'正则表达式','by word':'全词','replace':'替换','replace all':'全部替换','close':'关闭','current match':'当前匹配'});
function extensions(){return [EditorState.readOnly.of(previewOnly),EditorView.editable.of(!previewOnly),modeField,editingField,renderedField,history(),drawSelection(),EditorView.lineWrapping,
  markdown({addKeymap:false}),syntaxHighlighting(defaultHighlightStyle),search({top:true}),phrases,placeholder('开始写作…'),
  keymap.of([{key:'Enter',run:insertNewlineContinueMarkupCommand({nonTightLists:false})},{key:'Mod-f',run:find},{key:'Mod-b',run:()=>wrap('**')},{key:'Mod-i',run:()=>wrap('*')},...markdownKeymap,...defaultKeymap,...historyKeymap,...searchKeymap,indentWithTab]),
  EditorView.updateListener.of(update=>{if(update.docChanged){changed();outline()}if(update.selectionSet)notifyPosition();if(update.docChanged||update.selectionSet||update.transactions.some(t=>t.effects.length))searchCount()}),
  EditorView.domEventHandlers({
    focus:()=>{if(!previewOnly&&!view.state.field(editingField))view.dispatch({effects:editingEffect.of(true)})},
    blur:()=>{setTimeout(()=>{if(!view.hasFocus&&!view.composing)view.dispatch({effects:editingEffect.of(false)})},0)},
    scroll:notifyPosition,
    paste:(e)=>{const image=[...(e.clipboardData?.files??[])].find(f=>f.type.startsWith('image/'));if(image){e.preventDefault();acceptImage(image);return true}return false},
    drop:(e)=>{const image=[...(e.dataTransfer?.files??[])].find(f=>f.type.startsWith('image/'));if(image){e.preventDefault();acceptImage(image);return true}return false}
  })
]}
view=new EditorView({state:EditorState.create({doc:'',extensions:extensions()}),parent:document.querySelector('#editor')});
function settings(v){document.documentElement.style.setProperty('--font-size',v.fontSize+'px');document.documentElement.style.setProperty('--content-width',v.contentWidth+'px');document.documentElement.style.setProperty('--font-family',({system:'-apple-system,"PingFang SC",sans-serif',serif:'"Songti SC",serif',mono:'ui-monospace,"SF Mono","PingFang SC",monospace'})[v.fontFamily]||'-apple-system,"PingFang SC",sans-serif');view.requestMeasure();}
const commands={undo:()=>undo(view),redo:()=>redo(view),find,findNext:()=>findNext(view),bold:()=>wrap('**'),italic:()=>wrap('*'),link:()=>wrap('[','](网址)')};
window.tl={
  receive({action,value:v}) {
    if(action==='load') {
      if(currentID){post(position());sessions.set(currentID,{state:view.state,scroll:view.scrollDOM.scrollTop,revision:currentRevision})}
      currentID=v.id;currentRevision=v.revision;hydrating=true;
      const old=sessions.get(v.id);
      const state=old&&old.revision===v.revision&&old.state.doc.toString()===v.text?old.state:EditorState.create({doc:v.text,selection:{anchor:Math.min(v.selection||0,v.text.length)},extensions:extensions()});
      view.setState(state);view.dispatch({effects:[modeEffect.of(v.source),editingEffect.of(false)]});
      settings(v);document.body.classList.toggle('source',v.source);hydrating=false;
      requestAnimationFrame(()=>{view.scrollDOM.scrollTop=old&&old.revision===v.revision?old.scroll:v.scroll||0;view.requestMeasure()});outline();
    } else if(action==='refresh'&&previewOnly&&v.id===currentID) {
      const scroll=view.scrollDOM.scrollTop;
      hydrating=true;
      try {view.dispatch({changes:{from:0,to:view.state.doc.length,insert:v.text},selection:{anchor:Math.min(view.state.selection.main.head,v.text.length)}})}
      finally {hydrating=false;}
      requestAnimationFrame(()=>{view.scrollDOM.scrollTop=scroll;view.requestMeasure()});
    } else if(action==='mode')setMode(v);
    else if(action==='settings')settings(v);
    else if(action==='command'){commands[v]?.();}
    else if(action==='goto'){view.dispatch({selection:{anchor:Math.min(v,view.state.doc.length)},effects:[editingEffect.of(false),EditorView.scrollIntoView(Math.min(v,view.state.doc.length),{y:'start'})]});}
    else if(action==='anchor') {
      let anchor=v;try{anchor=decodeURIComponent(v)}catch{}
      const el=document.getElementById(anchor);if(el)el.scrollIntoView({block:'center'});
      else if(anchor.startsWith('note-')){const marker='[^'+anchor.slice(5)+']:',source=view.state.doc.toString(),at=source.indexOf(marker);if(at>=0)this.receive({action:'goto',value:at});}
      else{const target=parse(view.state.doc).headings.find(h=>h.title===anchor||h.title.toLowerCase().replace(/\s+/g,'-')===anchor);if(target)this.receive({action:'goto',value:target.position});}
    }
    else if(action==='insert'){
      if(v.id===currentID){const r=view.state.selection.main;view.dispatch({changes:{from:r.from,to:r.to,insert:v.text},selection:{anchor:r.from+v.text.length},effects:editingEffect.of(true)});view.focus();}
      else if(sessions.has(v.id)){const previous=sessions.get(v.id),r=previous.state.selection.main;
        const state=previous.state.update({changes:{from:r.from,to:r.to,insert:v.text},selection:{anchor:r.from+v.text.length}}).state;
        sessions.set(v.id,{...previous,state});post({type:'change',id:v.id,text:state.doc.toString(),selection:state.selection.main.head,scroll:previous.scroll});}
    } else if(action==='forget')sessions.delete(v);
    else if(action==='empty'){currentID='';view.setState(EditorState.create({doc:'',extensions:extensions()}));}
    else if(action==='flush'){changed();post(position());}
  },
  // Introspection uses the actual editor state, allowing deterministic integration tests.
  getText:()=>view.state.doc.toString(), getView:()=>view,
  inspect:()=>({id:currentID,length:view.state.doc.length,selection:view.state.selection.main.head,scroll:view.scrollDOM.scrollTop,source:view.state.field(modeField),headings:parse(view.state.doc).headings})
};
post({type:'ready'});
