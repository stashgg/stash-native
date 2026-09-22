export const CSS_ID = "stash-robot-live-css";
export function cssScript(css: string): string {
  return `(() => { let el = document.getElementById(${JSON.stringify(CSS_ID)}); if (!el) { el = document.createElement('style'); el.id = ${JSON.stringify(CSS_ID)}; (document.head || document.documentElement).appendChild(el); } el.textContent = ${JSON.stringify(css)}; return {css: el.textContent, url: location.href}; })()`;
}
export const resetCssScript = `(() => { document.getElementById(${JSON.stringify(CSS_ID)})?.remove(); return {css: '', url: location.href}; })()`;
export function inspectScript(selector?: string): string {
  return `(() => { const selector = ${JSON.stringify(selector || "body")}; const nodes = Array.from(document.querySelectorAll(selector)).slice(0, 25); return {url: location.href, title: document.title, readyState: document.readyState, css: document.getElementById(${JSON.stringify(CSS_ID)})?.textContent || '', elements: nodes.map(el => { const r = el.getBoundingClientRect(); const s = getComputedStyle(el); return {tag: el.tagName, id: el.id, text: (el.innerText || el.textContent || '').slice(0, 6000), html: el.outerHTML.slice(0, 20000), bounds: {x:r.x,y:r.y,width:r.width,height:r.height}, styles: Object.fromEntries(Array.from(s).map(k => [k,s.getPropertyValue(k)]))}; })}; })()`;
}
