// Local-only presentation: no credentials, network requests, or conversation storage.
export function renderResponse(markdown: string, accent: string, foreground: string, surface: string): string {
  const color = (value: string, fallback: string) => /^#[\da-f]{6}$/i.test(value) ? value : fallback
  accent = color(accent, '#65558f')
  foreground = color(foreground, '#242126')
  surface = color(surface, '#efedf1')
  const escape = (value: string) => value.replace(/&/g, '&amp;').replace(/</g, '&lt;')
    .replace(/>/g, '&gt;').replace(/"/g, '&quot;')
  const link = (children: string, href: string) => /^(https?:|mailto:)/i.test(href)
    ? `<a href="${escape(href)}" style="color:${accent};text-decoration:underline">${children}</a>` : children
  return Bun.markdown.render(markdown, {
    text: escape,
    html: escape,
    paragraph: children => `<p style="margin-top:0;margin-bottom:12px;line-height:145%">${children}</p>`,
    heading: (children, meta) => `<h${Math.min(meta.level, 4)} style="font-size:${meta.level === 1 ? 120 : meta.level === 2 ? 112 : 104}%;font-weight:600;margin-top:18px;margin-bottom:8px;color:${foreground}">${children}</h${Math.min(meta.level, 4)}>`,
    emphasis: children => `<span style="color:${accent};font-style:italic">${children}</span>`,
    strong: children => `<span style="font-weight:600;color:${foreground}">${children}</span>`,
    strikethrough: children => `<s>${children}</s>`,
    codespan: children => `<code style="color:${accent};background-color:${surface}">${children}</code>`,
    code: children => `<pre style="background-color:${surface};margin-top:8px;margin-bottom:14px;padding:10px;white-space:pre-wrap">${children}</pre>`,
    list: (children, meta) => meta.ordered
      ? `<ol start="${meta.start ?? 1}" style="margin-top:4px;margin-bottom:12px;margin-left:20px">${children}</ol>`
      : `<ul style="margin-top:4px;margin-bottom:12px;margin-left:20px">${children}</ul>`,
    listItem: (children, meta) => `<li style="margin-top:0;margin-bottom:6px;line-height:140%">${meta.checked === undefined ? '' : meta.checked ? '☑ ' : '☐ '}${children}</li>`,
    blockquote: children => `<blockquote style="margin-top:8px;margin-bottom:14px;margin-left:16px;color:${accent}">${children}</blockquote>`,
    link: (children, meta) => link(children, meta.href),
    // Never load model-provided images or local resources while displaying an answer.
    image: children => children,
    hr: () => '<hr />',
    table: children => `<table border="0" cellspacing="0" cellpadding="6" style="margin-top:8px;margin-bottom:14px">${children}</table>`,
    thead: children => `<thead>${children}</thead>`,
    tbody: children => `<tbody>${children}</tbody>`,
    tr: children => `<tr>${children}</tr>`,
    th: children => `<th bgcolor="${surface}">${children}</th>`,
    td: children => `<td>${children}</td>`,
  }, { noHtmlBlocks: true, noHtmlSpans: true })
}

if (import.meta.main) {
  const input = await Bun.stdin.text()
  const data = JSON.parse(input)
  console.log(JSON.stringify({ html: renderResponse(data.markdown, data.accent, data.foreground, data.surface) }))
}
