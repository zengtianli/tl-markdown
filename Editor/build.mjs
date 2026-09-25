import {build} from 'esbuild';
import {mkdir, writeFile, readFile, readdir, rm} from 'node:fs/promises';
await mkdir('../Resources/Editor', {recursive:true});
// KaTeX (katex.js + katex.css) and highlight.js (highlight.js) are on-demand bundles, loaded by
// editor.js when a formula or a fenced code block with a language is first rendered. markdown-it-texmath receives that engine as an object and never reaches its own
// require('katex') fallback, so stub it: esbuild would otherwise inline a second full copy of KaTeX.
const noBundledKatex={name:'no-bundled-katex',setup(b){
  b.onResolve({filter:/^katex(\/|$)/},()=>({path:'katex',namespace:'no-bundled-katex'}));
  b.onLoad({filter:/.*/,namespace:'no-bundled-katex'},()=>({contents:'module.exports=null',loader:'js'}));
}};
const editor = await build({entryPoints:['src/editor.js'], bundle:true, minify:true, format:'iife', target:'safari17', outdir:'../Resources/Editor', loader:{'.woff2':'file','.woff':'file','.ttf':'file'}, assetNames:'fonts/[name]-[hash]', plugins:[noBundledKatex], metafile:true});
if(Object.keys(editor.metafile.inputs).some(input=>/node_modules\/(katex|highlight\.js\/lib\/languages)\//.test(input)))throw new Error('KaTeX and highlight.js must load on demand, not inside editor.js');
await build({entryPoints:['src/katex.js','src/highlight.js'], bundle:true, minify:true, format:'iife', target:'safari17', outdir:'../Resources/Editor', loader:{'.woff2':'file','.woff':'file','.ttf':'file'}, assetNames:'fonts/[name]-[hash]'});
const diagram = await build({entryPoints:['src/mermaid.js'], bundle:true, minify:true, format:'iife', target:'safari17', outfile:'../Resources/Editor/mermaid.js', metafile:true});
// Mermaid's diagram modules must be inside this local asset. A leftover runtime
// import would fail under the editor's offline connect-src 'none' policy.
if(Object.values(diagram.metafile.outputs).some(output=>output.imports.length))throw new Error('Mermaid must have no runtime imports');
await writeFile('../Resources/Editor/index.html', await readFile('src/index.html'));
// WebKit on macOS 15+ always takes KaTeX's first source, WOFF2. The WOFF and
// TTF fallbacks were ~0.9 MB of installed weight that never loads; drop them
// from the stylesheet and remove every font file it no longer references.
const usedFonts=new Set();
for(const cssPath of ['../Resources/Editor/editor.css','../Resources/Editor/katex.css']) {
  const css=(await readFile(cssPath,'utf8')).replace(/,url\("[^"]+\.(?:woff|ttf)"\) format\("(?:woff|truetype)"\)/g,'');
  if(/\.(?:woff|ttf)"\)/.test(css))throw new Error('Unexpected non-WOFF2 font source left in '+cssPath);
  await writeFile(cssPath,css);
  for(const m of css.matchAll(/\.\/fonts\/([^")]+)/g))usedFonts.add(m[1]);
}
for(const name of await readdir('../Resources/Editor/fonts'))if(!usedFonts.has(name))await rm('../Resources/Editor/fonts/'+name);
const notices=[];
async function licenseNotices(directory) {
  const packageFile=directory+'/package.json';
  let pkg;try{pkg=JSON.parse(await readFile(packageFile,'utf8'))}catch{return}
  const names=await readdir(directory);
  const licenses=names.filter(name=>/^(license|licence|copying|notice)(\.|$)/i.test(name));
  notices.push(`\n=== ${pkg.name} ${pkg.version} (${pkg.license||'see below'}) ===\n`);
  for(const name of licenses){try{notices.push(await readFile(directory+'/'+name,'utf8'))}catch{}}
}
for(const name of await readdir('node_modules')) {
  if(name.startsWith('@'))for(const child of await readdir('node_modules/'+name))await licenseNotices('node_modules/'+name+'/'+child);
  else if(!name.startsWith('.'))await licenseNotices('node_modules/'+name);
}
await writeFile('../Resources/THIRD-PARTY-NOTICES.txt',notices.join('\n'));
console.log('Editor resources bundled locally.');
