import {build} from 'esbuild';
import {mkdir, writeFile, readFile, readdir} from 'node:fs/promises';
await mkdir('../Resources/Editor', {recursive:true});
await build({entryPoints:['src/editor.js'], bundle:true, minify:true, format:'iife', target:'safari17', outdir:'../Resources/Editor', loader:{'.woff2':'file','.woff':'file','.ttf':'file'}, assetNames:'fonts/[name]-[hash]'});
const diagram = await build({entryPoints:['src/mermaid.js'], bundle:true, minify:true, format:'iife', target:'safari17', outfile:'../Resources/Editor/mermaid.js', metafile:true});
// Mermaid's diagram modules must be inside this local asset. A leftover runtime
// import would fail under the editor's offline connect-src 'none' policy.
if(Object.values(diagram.metafile.outputs).some(output=>output.imports.length))throw new Error('Mermaid must have no runtime imports');
await writeFile('../Resources/Editor/index.html', await readFile('src/index.html'));
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
