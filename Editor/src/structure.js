// Block structure of a Markdown document: the ranges rendered as blocks, headings for the outline
// and link reference definitions. It needs only markdown-it's block pass, so the parser used here
// skips inline tokenization of the whole document, which ran again on every edit. On a 137 KB
// document that is ~44% fewer tokens and a third less parse time. structure-tests.mjs checks the
// result is identical to a full parse.
export function blockOnly(md) {
  md.core.ruler.disable(['inline', 'github-task-lists', 'linkify', 'replacements', 'smartquotes', 'text_join']);
  return md;
}

export function documentStructure(md, text) {
  const lines=text.split('\n');
  const offsets=[0]; for(let i=0;i<lines.length;i++) offsets.push(offsets.at(-1)+lines[i].length+1);
  // Frontmatter is preserved and shown in a compact, editable disclosure.
  let frontEnd=0;
  if(lines[0]==='---') { const end=lines.findIndex((l,i)=>i>0&&(l==='---'||l==='...')); if(end>0)frontEnd=end+1; }
  const source=frontEnd?lines.map((s,i)=>i<frontEnd?'':s).join('\n'):text;
  const env={}, tokens=md.parse(source,env), blocks=[], headings=[];
  if(frontEnd)blocks.push({from:0,to:Math.min(text.length,offsets[frontEnd]-1),kind:'frontmatter'});
  for(let i=0;i<tokens.length;i++) {
    const t=tokens[i];
    if(t.type==='heading_open'&&t.map) headings.push({position:offsets[t.map[0]],level:Number(t.tag.slice(1)),title:tokens[i+1]?.content||''});
    if(t.level!==0||!t.map||t.nesting===-1)continue;
    const from=offsets[t.map[0]], to=Math.min(text.length,offsets[t.map[1]]-1);
    if(to>from && from >= (blocks.at(-1)?.to??0))blocks.push({from,to,kind:t.type,info:t.info});
  }
  // Footnote definitions may be consumed by markdown-it without a mapped top-level token.
  for(let i=0;i<lines.length;i++)if(/^ {0,3}\[(?!\^)[^\]]+\]:\s*\S/.test(lines[i])&&!blocks.some(b=>offsets[i]>=b.from&&offsets[i]<b.to)) {
    blocks.push({from:offsets[i],to:Math.min(text.length,offsets[i+1]-1),kind:'reference-definition'});
  }
  for(let i=0;i<lines.length;i++)if(/^\[\^[^\]]+\]:/.test(lines[i])&&!blocks.some(b=>offsets[i]>=b.from&&offsets[i]<b.to)) {
    let end=i+1; while(end<lines.length&&/^ {2,}\S/.test(lines[end]))end++;
    blocks.push({from:offsets[i],to:Math.min(text.length,offsets[end]-1),kind:'footnote'}); i=end-1;
  }
  blocks.sort((a,b)=>a.from-b.from);
  return {blocks,headings,env};
}
