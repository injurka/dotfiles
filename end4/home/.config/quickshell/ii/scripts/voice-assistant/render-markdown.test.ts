import { test } from 'bun:test'
import { renderResponse } from './render-markdown'
import { strict as assert } from 'node:assert'
const render = (s: string) => renderResponse(s, '#6750a4', '#201c25', '#eee8f4')
test('Voice markdown preserves structure and safely styles model text', () => {
const html = render('## Заголовок\n\nПервый *акцент* и **важное**.\n\nВторой абзац.\n\n- Один\n  - Вложенный\n- Два\n\n> Цитата\n\n```ts\nconst x = "<script>"\n```\n\n[Ссылка](https://example.com?a=1&b=2)')
assert.match(html, /margin-bottom:12px/)
assert.match(html, /color:#6750a4;font-style:italic/)
assert.match(html, /font-weight:600/)
assert.equal((html.match(/<ul /g) || []).length, 2)
assert.match(html, /&lt;script&gt;/)
assert.match(html, /href="https:\/\/example.com\?a=1&amp;b=2"/)
const unsafe = render('<img src="file:///etc/passwd">\n\n[bad](javascript:alert%281%29)\n\n![image](https://example.com/tracking.png)')
assert.doesNotMatch(unsafe, /<img|href="javascript:/)
assert.match(unsafe, /&lt;img/)
assert.match(render('`a < b && c > d`'), /a &lt; b &amp;&amp; c &gt; d/)
assert.match(render('| A | B |\n|---|---|\n| 1 | 2 |'), /<table/)


})
