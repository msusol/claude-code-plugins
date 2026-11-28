// Runs the dashboard page's script against a stub DOM and prints {element id: innerHTML} as JSON. Used by test_build_dashboard.py.
// Optional argv[4] is the initial location.hash and argv[5] the initial location.search; every history.replaceState URL comes back in "__urls" (a JSON list).
// Optional argv[3] is a JSON list of actions replayed after load: {"pager":"next"|"prev"}, {"pageSize":25}, {"toggleWide":true},
// {"sort":"in_tok"}, {"expand":"<session id>"}, {"search":"text"}, {"abSearch":"text"} (type in the A/B search box), {"abToggle":"<row key>"} (click an A/B row, for
// example "plan:x", "round:x-r2" or "run:x-fable-r2"), {"abAll":true|false} (Expand all / Collapse all), {"sessView":"graph"|"table"} (the Sessions Table / Graph buttons), {"sessRange":"1m"|"3m"|"6m"|"12m"|"all"|"YYYY"} (the graph's range menu), {"clickLink":"<session id>"} and {"abLink":"<row key>"} (click a link inside a row). Elements that got a className are reported as "<id>:class".
const fs = require('fs');
const ids = {}, listeners = {};
function el(id) {
  if (!ids[id]) ids[id] = { id, _h: '', textContent: '', hidden: false, style: {}, dataset: {}, value: '', className: '',
    set innerHTML(v) { this._h = v; }, get innerHTML() { return this._h; },
    addEventListener(type, fn) { (listeners[id + ':' + type] = listeners[id + ':' + type] || []).push(fn); },
    setAttribute() {}, getAttribute() { return null; } };
  return ids[id];
}
global.document = { getElementById: el, querySelectorAll: () => [] };
global.location = { hash: process.argv[4] || '', search: process.argv[5] || '', pathname: '/' };
const replaced = [];   // every history.replaceState URL, reported as "__urls"
global.history = { replaceState(_s, _t, url) { replaced.push(url); const u = new URL(url, 'http://x'); location.search = u.search; } };
global.addEventListener = () => {};
require('vm').runInThisContext(fs.readFileSync(process.argv[2], 'utf8'));
const fire = (id, type, ev) => (listeners[id + ':' + type] || []).forEach(f => f(ev));
const closest = map => sel => (sel in map ? map[sel] : null);
for (const a of JSON.parse(process.argv[3] || '[]')) {
  if (a.pager) fire('pager', 'click', { target: { closest: closest({ button: { disabled: false, dataset: { pg: a.pager } } }) } });
  else if (a.pageSize) fire('pager', 'change', { target: { id: 'page-size', value: String(a.pageSize) } });
  else if (a.sessView) fire('sess-view', 'click', { target: { closest: closest({ button: { dataset: { view: a.sessView } } }) } });
  else if (a.sessRange) { el('sess-range').value = a.sessRange; fire('sess-range', 'change', {}); }
  else if (a.toggleWide) fire('sess', 'click', { target: { closest: closest({ '.cd-ptoggle': {} }) } });
  else if (a.sort) fire('sess', 'click', { target: { closest: closest({ th: { dataset: { k: a.sort } } }) } });
  else if (a.expand) fire('sess', 'click', { target: { closest: closest({ 'tr.s': { dataset: { id: a.expand } } }) } });
  else if (a.search !== undefined) { el('q').value = a.search; fire('q', 'input', {}); }
  else if (a.abSearch !== undefined) { el('ab-q').value = a.abSearch; fire('ab-q', 'input', {}); }
  else if (a.abToggle) fire('ab-runs', 'click', { target: { closest: closest({ 'tr.ab': { dataset: { key: a.abToggle } } }) } });
  else if (a.clickLink) fire('sess', 'click', { target: { closest: closest({ a: {}, 'tr.s': { dataset: { id: a.clickLink } } }) } });
  else if (a.abLink) fire('ab-runs', 'click', { target: { closest: closest({ a: {}, 'tr.ab': { dataset: { key: a.abLink } } }) } });
  else if (a.abAll !== undefined) fire(a.abAll ? 'ab-expand' : 'ab-collapse', 'click', {});
}
const out = { __urls: JSON.stringify(replaced) };
for (const k of Object.keys(ids)) { out[k] = ids[k]._h || ids[k].textContent; if (ids[k].className) out[k + ':class'] = ids[k].className; if (ids[k].hidden) out[k + ':hidden'] = true; }
console.log(JSON.stringify(out));
