import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import MarkdownIt from 'markdown-it';
import footnote from 'markdown-it-footnote';
import taskLists from 'markdown-it-task-lists';
import texmath from 'markdown-it-texmath';
import {blockOnly, documentStructure} from './src/structure.js';

// Same construction as src/editor.js; the engine is never called by a parse.
const engine = {renderToString: tex => tex};
const make = () => new MarkdownIt({html:true, linkify:true, breaks:false}).use(footnote).use(taskLists,{enabled:false}).use(texmath,{engine, delimiters:'dollars'});
const full = make(), blocks = blockOnly(make());
const synthetic = Array.from({length: 40}, (_, i) => `## 第 ${i} 节\n\n正文 **加粗** \`代码\` [链接](https://example.com) $x_${i}$。\n\n| a | b |\n| --- | ---: |\n| ${i} | $y$ |\n\n- [ ] 待办 ${i}\n- [x] 完成\n\n\`\`\`python\nprint(${i})\n\`\`\`\n` + (i % 10 ? '' : `\n$$Q = ${i}\\sqrt{2g}$$\n`)).join('');
const edges = `---\ntitle: 前言\n---\n\n# 标题 *强调* 与 \`代码\` $x^2$\n\n参见 [参数][CFG] 与脚注[^1]，行内 $a+b$、<span>HTML</span>。\n\n[CFG]: https://example.com/first "标题"\n\n[^1]: 脚注，含 **加粗**。\n    缩进续行\n\n- [ ] 待办\n  - 嵌套 [链接](http://a.b)\n\n> 引用 $$y$$\n> 第二行\n\n$$\nE = mc^2\n$$\n\n\`\`\`mermaid\ngraph TD; A-->B\n\`\`\`\n\n<div>\nHTML 块\n</div>\n\nSetext 标题\n===\n\n    缩进代码\n\n1. 有序\n\n***\n\n[^长注]: 另一个脚注\n`;

test('block-only parse yields exactly the structure of a full parse', async () => {
  const documents = {welcome: await readFile('../Resources/欢迎使用.md', 'utf8'), synthetic, edges};
  for (const [name, text] of Object.entries(documents)) {
    const a = documentStructure(full, text), b = documentStructure(blocks, text);
    assert.deepEqual(b.blocks, a.blocks, name + ' blocks');
    assert.deepEqual(b.headings, a.headings, name + ' headings');
    assert.deepEqual(b.env.references, a.env.references, name + ' references');
  }
  assert.ok(documentStructure(blocks, edges).env.references.CFG, 'reference definitions are still collected');
});

test('block-only parse skips inline tokenization', () => {
  const tokens = md => md.parse(synthetic, {}).reduce((sum, t) => sum + 1 + (t.children?.length || 0), 0);
  assert.ok(tokens(blocks) < tokens(full) * 0.7, `${tokens(blocks)} vs ${tokens(full)}`);
  assert.ok(blocks.parse(synthetic, {}).every(t => !t.children?.length), 'no inline children');
});
