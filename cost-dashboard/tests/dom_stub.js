// Runs the dashboard page's script against a stub DOM and prints {element id: innerHTML} as JSON. Used by test_build_dashboard.py.
// Optional argv[3] is a JSON list of actions replayed after load: {"pager":"next"|"prev"}, {"pageSize":25}, {"toggleWide":true},
// {"sort":"in_tok"}, {"expand":"<session id>"}, {"search":"text"}. Elements that got a className are reported as "<id>:class".
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
global.location = { hash: '' };
global.addEventListener = () => {};
require('vm').runInThisContext(fs.readFileSync(process.argv[2], 'utf8'));
const fire = (id, type, ev) => (listeners[id + ':' + type] || []).forEach(f => f(ev));
const closest = map => sel => (sel in map ? map[sel] : null);
for (const a of JSON.parse(process.argv[3] || '[]')) {
  if (a.pager) fire('pager', 'click', { target: { closest: closest({ button: { disabled: false, dataset: { pg: a.pager } } }) } });
  else if (a.pageSize) fire('pager', 'change', { target: { id: 'page-size', value: String(a.pageSize) } });
  else if (a.toggleWide) fire('sess', 'click', { target: { closest: closest({ '.cd-ptoggle': {} }) } });
  else if (a.sort) fire('sess', 'click', { target: { closest: closest({ th: { dataset: { k: a.sort } } }) } });
  else if (a.expand) fire('sess', 'click', { target: { closest: closest({ 'tr.s': { dataset: { id: a.expand } } }) } });
  else if (a.search !== undefined) { el('q').value = a.search; fire('q', 'input', {}); }
}
const out = {};
for (const k of Object.keys(ids)) { out[k] = ids[k]._h || ids[k].textContent; if (ids[k].className) out[k + ':class'] = ids[k].className; }
console.log(JSON.stringify(out));
