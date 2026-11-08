#!/usr/bin/env python3
"""Build docs/.hub/index.html (and hub.json) from a planning-docs layout.

Standard library only. Links point at the local files, relative to docs/
(for example ../adr/0003-x.md), so serve_hub.py or a file:// page can open them.

    build_hub.py [DOCS_DIR] [--watch] [--interval SECONDS]
"""
import argparse
import hashlib
import json
import posixpath
import re
import subprocess
import sys
import time
from pathlib import Path

CHECK = re.compile(r"^\s*[-*]\s+\[( |x|X)\]\s+(.*)$")
LINK = re.compile(r"\[([^\]]+)\]\(([^)\s]+)\)")
HREF = re.compile(r"\]\(([^)\s]+)\)")
PHASE_H = re.compile(r"(?i)^phase\s+([A-Za-z0-9]+)\s*[:.—–-]*\s*(.*)$")
PHASE_REF = re.compile(r"(?i)\bphase\s+([A-Za-z0-9]+)")
TEMPLATE = Path(__file__).resolve().parent.parent / "assets" / "template.html"


def read(path):
    return path.read_text(encoding="utf-8", errors="replace")


def frontmatter(text):
    m = re.match(r"^---\n(.*?)\n---\n?", text, re.S)
    if not m:
        return {}, text
    fm = {}
    for line in m.group(1).splitlines():
        key, sep, val = line.partition(":")
        if sep:
            fm[key.strip()] = val.strip()
    return fm, text[m.end():]


def title_of(body, fallback):
    for line in body.splitlines():
        if line.startswith("# "):
            return line[2:].strip()
    return fallback


def rel(path, root):
    return path.relative_to(root).as_posix()


def resolve(href, base_dir):
    """Resolve a markdown href found in a file under base_dir (docs-relative) to a docs-relative path."""
    if re.match(r"^[a-z][a-z0-9+.-]*:", href) or href.startswith("#"):
        return None
    path = href.split("#")[0]
    if not path:
        return None
    return posixpath.normpath(posixpath.join(base_dir, path))


def strip_marks(text):
    text = re.sub(r"`([^`]+)`", r"\1", text)
    return re.sub(r"\*\*([^*]+)\*\*", r"\1", text)


def plain(text, base_dir):
    """Markdown to plain text plus the links it held: (text, [{label, path}])."""
    links = []

    def link(m):
        label = strip_marks(m.group(1))
        href = m.group(2)
        if re.match(r"^https?://", href):
            links.append({"label": label, "path": href})
        else:
            target = resolve(href, base_dir)
            if target:
                frag = "#" + href.split("#", 1)[1] if "#" in href else ""
                links.append({"label": label, "path": target + frag})
        return label

    out = strip_marks(LINK.sub(link, text))
    return out, links


def investigation_ids(text, base_dir):
    ids = []
    for href in HREF.findall(text):
        target = resolve(href, base_dir)
        if target and target.startswith("investigate/"):
            parts = target.split("/")
            if len(parts) > 1 and parts[1]:
                name = re.sub(r"\.md$", "", parts[1])
                if name and name not in ids:
                    ids.append(name)
    return ids


def parse_items(body):
    items, h2, h3 = [], "", ""
    for line in body.splitlines():
        if line.startswith("## "):
            h2, h3 = line[3:].strip(), ""
        elif line.startswith("### "):
            h3 = line[4:].strip()
        else:
            m = CHECK.match(line)
            if m:
                items.append({"h2": h2, "h3": h3, "done": m.group(1) != " ", "text": m.group(2).strip()})
    return items


def box(done):
    return "[x]" if done else "[ ]"


def file_date(root, path):
    """Date of the last commit that touched the file (YYYY-MM-DD); the file's mtime when untracked or no git."""
    try:
        r = subprocess.run(["git", "-C", str(root), "log", "-1", "--format=%cs", "--", str(path)],
                           capture_output=True, text=True, timeout=5)
        if r.returncode == 0 and r.stdout.strip():
            return r.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        pass
    return time.strftime("%Y-%m-%d", time.localtime(path.stat().st_mtime))


def parse_adrs(root):
    adr_dir = root / "adr"
    if not adr_dir.is_dir():
        return []
    index_status = {}
    readme = adr_dir / "README.md"
    if readme.exists():
        for line in read(readme).splitlines():
            m = re.match(r"^\|\s*\[?(\d{4,5})\]?(?:\([^)]*\))?\s*\|.*\|\s*([^|]+?)\s*\|\s*$", line)
            if m:
                index_status[m.group(1)] = m.group(2)
    adrs = []
    for p in sorted(adr_dir.glob("[0-9][0-9][0-9][0-9]-*.md")):
        fm, body = frontmatter(read(p))
        num = p.name[:4]
        status = fm.get("status") or index_status.get(num, "")
        if not status:
            m = re.search(r"^##\s+Status\s*\n+\s*(.+)$", body, re.M)
            status = m.group(1).strip() if m else "unknown"
        title = re.sub(r"^\d{4,5}\.?\s*", "", title_of(body, p.stem))
        adrs.append({"number": num, "title": strip_marks(title),
                     "status": re.split(r"[\s,.(]", status.strip().lower() or "unknown")[0] or "unknown",
                     "date": fm.get("date") or file_date(root, p), "path": rel(p, root)})
    return adrs


def parse_specs(root):
    spec_dir = root / "specs"
    if not spec_dir.is_dir():
        return []
    files = sorted(spec_dir.glob("*.md")) + sorted(spec_dir.glob("*/spec.md"))
    out = []
    for p in files:
        fm, body = frontmatter(read(p))
        name = p.stem if p.name != "spec.md" else p.parent.name
        title = re.sub(r"\s+Specification$", "", title_of(body, name))
        out.append({"title": strip_marks(title), "status": fm.get("status", "").lower(),
                    "date": fm.get("date") or file_date(root, p), "path": rel(p, root)})
    return sorted(out, key=lambda r: r["title"].lower())


def parse_process(root):
    proc_dir = root / "process"
    if not proc_dir.is_dir():
        return []
    files = sorted(proc_dir.glob("*.md")) + sorted(proc_dir.glob("*/README.md")) + sorted(proc_dir.glob("*/index.md"))
    out = []
    for p in files:
        _, body = frontmatter(read(p))
        out.append({"title": strip_marks(title_of(body, p.stem)), "date": file_date(root, p), "path": rel(p, root)})
    return sorted(out, key=lambda r: r["title"].lower())


def parse_plans(root):
    plans = []
    plan_dir = root / "plans"
    if not plan_dir.is_dir():
        return plans
    files = [(p, False) for p in sorted(plan_dir.glob("*.md")) if p.name != "TODO.md"]
    files += [(p, True) for p in sorted((plan_dir / "archive").glob("*.md"))]
    for p, archived in files:
        text = read(p)
        fm, body = frontmatter(text)
        items = parse_items(body)
        phases = {}
        for it in items:
            m = PHASE_H.match(it["h3"])
            if not m:
                continue
            key = m.group(1)
            ph = phases.setdefault(key, {"phase": key, "heading": strip_marks(m.group(2)).strip(),
                                         "done": 0, "total": 0, "items": []})
            ph["total"] += 1
            ph["done"] += 1 if it["done"] else 0
            ph["items"].append({"box": box(it["done"]), "done": it["done"], "text": plain(it["text"], "plans")[0]})
        done = sum(1 for i in items if i["done"])
        status = "archived" if archived else (fm.get("status") or ("done" if items and done == len(items) else "active"))
        m = re.match(r"^(\d{4,5})-", p.name)
        title = re.sub(r"\s+Implementation Plan$", "", re.sub(r"^(Plan\s+)?\d{4,5}[:.]?\s*", "", title_of(body, p.stem)))
        plans.append({
            "stem": p.stem, "id": m.group(1) if m else p.stem, "num": m.group(1) if m else "",
            "title": strip_marks(title), "status": status, "kind": "archived" if archived else "plan",
            "path": rel(p, root), "done": done, "total": len(items), "phases": list(phases.values()),
            "investigations": investigation_ids(text, "plans/archive" if archived else "plans"),
        })
    return plans


def slug(s):
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")


def match_plan(section_title, source_href, plans, base):
    if source_href:
        target = resolve(source_href, base)
        for pl in plans:
            if pl["path"] == target:
                return pl
    m = re.match(r"^(\d{4,5})\b", section_title)
    if m:
        for pl in plans:
            if pl["num"] == m.group(1):
                return pl
    s = slug(re.sub(r"^(Plan\s+)?\d{4,5}[:.]?\s*", "", section_title))
    for pl in plans:
        if slug(re.sub(r"^\d{4,5}-", "", pl["stem"])) == s or slug(pl["title"]) == s:
            return pl
    return None


def parse_todo(root, plans):
    """Return TODO sections: [{title, plan (dict or None), items: [{done, text, links, inv}]}]."""
    path = root / "plans" / "TODO.md"
    if not path.exists():
        return []
    _, body = frontmatter(read(path))
    sections, cur = [], None
    for line in body.splitlines():
        if line.startswith("## "):
            cur = {"title": line[3:].strip(), "lines": []}
            sections.append(cur)
        elif cur is not None:
            cur["lines"].append(line)
    out = []
    for sec in sections:
        text = "\n".join(sec["lines"])
        items = []
        for line in sec["lines"]:
            m = CHECK.match(line)
            if m:
                t = m.group(2).strip()
                shown, links = plain(t, "plans")
                items.append({"done": m.group(1) != " ", "text": shown, "links": links,
                              "inv": investigation_ids(t, "plans")})
        if not items:
            continue
        src = re.search(r"Source plan:\s*\[[^\]]*\]\(([^)\s]+)\)", text)
        out.append({"title": sec["title"], "items": items,
                    "plan": match_plan(sec["title"], src.group(1) if src else None, plans, "plans")})
    return out


def investigation_notes(root):
    inv_dir = root / "investigate"
    notes = {}
    if not inv_dir.is_dir():
        return notes
    for p in sorted(inv_dir.glob("*.md")):
        notes[p.stem] = p
    for d in sorted(x for x in inv_dir.iterdir() if x.is_dir()):
        anchor = d / (d.name + ".md")
        if anchor.exists():
            notes[d.name] = anchor
    return notes


def build_model(root, plans, sections, notes):
    """Turn parsed plans, TODO sections and investigation notes into the page's datasets."""
    inv_title, inv_path = {}, {}
    for name, p in notes.items():
        _, body = frontmatter(read(p))
        inv_title[name] = strip_marks(re.sub(r"^\d{4}-\d{2}-\d{2}\s*", "", title_of(body, name)))
        inv_path[name] = rel(p, root)

    work, phases_out, plan_rows = [], [], []
    cited = {name: {"plans": [], "refs": [], "done": []} for name in notes}
    used = set()

    def plan_row(pid, title, status, kind, done, total):
        plan_rows.append({"id": pid, "title": title, "status": status, "kind": kind,
                          "done": done, "open": total - done, "total": total})

    for sec in sections:
        pl = sec["plan"]
        pid = pl["id"] if pl else slug(sec["title"])
        if pid in used:  # a second TODO section for the same plan: keep its tasks under one id
            pid = pid + "-" + slug(sec["title"])
        used.add(pid)
        keys = {ph["phase"] for ph in pl["phases"]} if pl else set()
        work.append({"kind": "plan", "id": pid, "text": pl["title"] if pl else sec["title"], "box": "",
                     "plan": pid, "phases": "1" if keys else ""})
        for ph in (pl["phases"] if pl else []):
            phases_out.append(dict(ph, plan=pid))
        done_n = 0
        seen_notes = set()
        for n, it in enumerate(sec["items"], 1):
            ref = "%s-%d" % (pid, n)
            done_n += 1 if it["done"] else 0
            refs = [k for k in dict.fromkeys(PHASE_REF.findall(it["text"])) if k in keys]
            work.append({"kind": "task", "id": ref, "text": it["text"], "box": box(it["done"]),
                         "done": it["done"], "plan": pid, "links": it["links"], "phases": ",".join(refs)})
            for name in it["inv"]:
                if name in notes:
                    seen_notes.add(name)
                    work.append({"kind": "investigation", "id": "", "text": inv_title[name], "box": "",
                                 "plan": pid, "parent": ref})
                    c = cited[name]
                    if pid not in c["plans"]:
                        c["plans"].append(pid)
                    c["refs"].append(ref)
                    c["done"].append(it["done"])
        for name in (pl["investigations"] if pl else []):
            if name in notes and name not in seen_notes:
                work.append({"kind": "investigation", "id": "", "text": inv_title[name], "box": "",
                             "plan": pid, "parent": ""})
                if pid not in cited[name]["plans"]:
                    cited[name]["plans"].append(pid)
        if pl:
            pl["_counted"] = True
            plan_row(pid, pl["title"], pl["status"], pl["kind"], done_n, len(sec["items"]))
        else:
            plan_row(pid, sec["title"], "active", "todo", done_n, len(sec["items"]))

    for pl in plans:  # plans with a checklist of their own but no TODO section
        if not pl.get("_counted") and pl["total"]:
            plan_row(pl["id"], pl["title"], pl["status"], pl["kind"], pl["done"], pl["total"])
            for ph in pl["phases"]:
                phases_out.append(dict(ph, plan=pl["id"]))
            for name in pl["investigations"]:
                if name in cited and pl["id"] not in cited[name]["plans"]:
                    cited[name]["plans"].append(pl["id"])

    invs = []
    for name, p in sorted(notes.items(), reverse=True):
        c = cited[name]
        m = re.match(r"^(\d{4}-\d{2}-\d{2})", name)
        if c["refs"]:
            state = box(all(c["done"]))
        else:
            state = ""
        invs.append({"date": m.group(1) if m else "", "title": inv_title[name], "path": inv_path[name],
                     "plans": ", ".join(c["plans"]), "todo_ref": ", ".join(c["refs"]), "box": state})
    return plan_rows, work, phases_out, invs


def collect(root):
    plans = parse_plans(root)
    sections = parse_todo(root, plans)
    plan_rows, work, phases, invs = build_model(root, plans, sections, investigation_notes(root))
    data = {
        "project": re.sub(r"[-_]+", " ", root.resolve().parent.name),
        "adrs": parse_adrs(root),
        "specs": parse_specs(root), "process": parse_process(root),
        "plans": plan_rows, "work": work, "phases": phases, "invs": invs,
    }
    data["version"] = hashlib.sha1(json.dumps(data, sort_keys=True).encode()).hexdigest()[:12]
    data["generated"] = time.strftime("%Y-%m-%d %H:%M:%S")
    return data


def render(data):
    """Return (hub.json text, index.html text) for a collected model."""
    blob = json.dumps(data, ensure_ascii=False)
    page = read(TEMPLATE).replace("/*__DATA__*/null", blob.replace("</", "<\\/"))
    return blob, page


def build(root):
    root = Path(root)
    data = collect(root)
    out = root / ".hub"
    out.mkdir(exist_ok=True)
    blob, page = render(data)
    (out / "hub.json").write_text(blob, encoding="utf-8")
    (out / "index.html").write_text(page, encoding="utf-8")
    return data, out / "index.html"


def newest_mtime(root):
    latest = 0.0
    for p in Path(root).rglob("*"):
        if ".hub" in p.parts or not p.is_file():
            continue
        if p.suffix == ".md":
            latest = max(latest, p.stat().st_mtime)
    return latest


def summary(data, path):
    n_items = sum(1 for r in data["work"] if r["kind"] == "task")
    return "wrote %s: %d plans, %d ADRs, %d investigations, %d TODO items" % (
        path, len(data["plans"]), len(data["adrs"]), len(data["invs"]), n_items)


def not_ignored(page):
    """True when the page sits in a git repo that does not ignore it."""
    try:
        r = subprocess.run(["git", "-C", str(page.parent), "check-ignore", "-q", page.name],
                           capture_output=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return False
    return r.returncode == 1          # 0 = ignored, 128 = not a repo


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("docs", nargs="?", default="docs")
    ap.add_argument("--watch", action="store_true", help="rebuild when a markdown file changes")
    ap.add_argument("--interval", type=float, default=1.0)
    args = ap.parse_args(argv)
    root = Path(args.docs)
    if not root.is_dir():
        sys.exit("not a directory: %s" % root)
    data, path = build(root)
    print(summary(data, path), flush=True)
    if not_ignored(path):
        print("note: %s is not git-ignored; add `.hub/` to the repo's .gitignore" % path.parent, file=sys.stderr)
    for name, key in (("adr/", "adrs"), ("plans/", "plans"), ("investigate/", "invs"), ("specs/", "specs"), ("process/", "process")):
        if not data[key]:
            print("note: nothing found under %s" % name, file=sys.stderr)
    if args.watch:
        seen = newest_mtime(root)
        print("watching %s (Ctrl-C to stop)" % root, flush=True)
        try:
            while True:
                time.sleep(args.interval)
                cur = newest_mtime(root)
                if cur != seen:
                    seen = cur
                    data, path = build(root)
                    print(summary(data, path), flush=True)
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()
