#!/usr/bin/env python3
"""Mirror the UniFi Network API v10.4.57 docs from developer.ui.com.

The site is a Next.js app: endpoint pages embed the full doc content
(the openapi-derived endpoint object with markdown description) in the
React Server Components flight payload of the plain HTML response. This
script fetches each page, decodes the payload, and writes clean markdown
files into ../pages/ for offline reading and RAG indexing.

Usage: python3 mirror_docs.py [--base URL] [--out DIR] [--slug SLUG]
"""

import json
import os
import re
import sys
import time
import urllib.request
from html import unescape

BASE = "https://developer.ui.com/network/v10.4.57"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "pages")
PUSH_RE = re.compile(r'self\.__next_f\.push\(\[1,"((?:[^"\\]|\\.)*)"\]\)', re.S)
ENDPOINT_RE = re.compile(r'^\s*[A-Za-z0-9]+:\s*(\[.*\])\s*$', re.S)


def fetch(url: str) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": "unifi-mcp-doc-mirror/0.1"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return resp.read().decode("utf-8", errors="replace")


def decode_pushes(raw: str):
    out = []
    for p in PUSH_RE.findall(raw):
        try:
            out.append(json.loads('"' + p + '"'))
        except Exception:
            pass
    return out


def find_endpoint(pushes):
    """Return the endpoint dict if the page carries one."""
    for s in pushes:
        if '"endpoint":{"path"' not in s:
            continue
        m = ENDPOINT_RE.match(s)
        if not m:
            continue
        try:
            arr = json.loads(m.group(1))
            ep = arr[3]["endpoint"]
            if isinstance(ep, dict) and "path" in ep:
                return ep
        except Exception:
            continue
    return None


def clean_html(s: str) -> str:
    """Light cleanup of the markdown-with-HTML descriptions."""
    s = s.replace("<details>", "").replace("</details>", "")
    s = re.sub(r"<summary>(.*?)</summary>", r"**\1:**\n\n", s, flags=re.S)
    s = s.replace("<br>", "\n").replace("<br/>", "\n").replace("<br />", "\n")
    s = re.sub(r"<[^>]+>", "", s)
    return unescape(s)


def render_endpoint(ep: dict) -> str:
    method = ep.get("method", "")
    path = ep.get("path", "")
    title = ep.get("summary") or ep.get("operationId") or path
    lines = [f"# {title}", ""]
    lines.append(f"`{method} {path}`  ")
    if ep.get("operationId"):
        lines.append(f"operationId: `{ep['operationId']}`  ")
    lines.append("")
    desc = clean_html(ep.get("description") or "")
    if desc.strip():
        lines.append(desc.strip())
        lines.append("")
    return "\n".join(lines)


def find_guide_body(pushes):
    """Prose pushes for guide pages (no endpoint object)."""
    parts = []
    for s in pushes:
        if s.startswith("0:") or s.startswith("1:"):
            continue
        if re.match(r'^[A-Za-z0-9]+:(I\[|E\{|\["\$")', s):
            continue  # module refs / JSX shells
        if len(s) < 120:
            continue
        if "sidebarData" in s:
            continue
        if "dangerouslySetInnerHTML" in s:
            continue
        # keep pushes that read like prose
        if re.search(r"\n\n|^#|\|.*\|", s):
            parts.append(s)
    body = "\n\n".join(parts)
    return clean_html(body).strip()


COMPONENT_RE = re.compile(r'(\d+):I\[\d+,\[.*?\],"([A-Za-z0-9_]+)"\]', re.S)


def component_names(pushes):
    """Map RSC component ids to their display names (e.g. 20 -> StyledH1)."""
    names = {}
    for s in pushes:
        for m in COMPONENT_RE.finditer(s):
            names[m.group(1)] = m.group(2)
    return names


def find_mdx(pushes):
    """Return the mdxContent list if the page carries a rendered guide."""
    for s in pushes:
        m = re.match(r'^\s*[A-Za-z0-9]+:\s*(\[.*\])\s*$', s, re.S)
        if not m:
            continue
        try:
            arr = json.loads(m.group(1))
            node = arr[3]
            if isinstance(node, dict) and "mdxContent" in node:
                return node["mdxContent"]
        except Exception:
            continue
    return None


def node_text(node):
    """Plain text of a node, recursing through children. Component nodes
    (["$", ref, null, props]) contribute only their props' text."""
    if isinstance(node, str):
        return node
    if isinstance(node, list):
        if node and node[0] == "$" and len(node) >= 4 and isinstance(node[3], dict):
            props = node[3]
            if "children" in props:
                return node_text(props["children"])
            return ""
        out = []
        for item in node:
            out.append(node_text(item))
        return "".join(out)
    if isinstance(node, dict):
        if "children" in node:
            return node_text(node["children"])
        return ""
    return ""


def render_mdx_node(node, names):
    """Render one mdxContent node to markdown."""
    if isinstance(node, str):
        return node
    if not isinstance(node, list) or not node:
        return ""
    if node[0] == "$":
        _, ref, _, props = (list(node) + [None, None, None, None])[:4]
        props = props or {}
        name = ""
        if isinstance(ref, str) and ref.startswith("$L"):
            name = names.get(ref[2:], "")
        children = props.get("children", "")
        if name == "StyledH1":
            return f"# {node_text(children)}\n\n"
        if name == "StyledH2":
            return f"## {node_text(children)}\n\n"
        if name == "StyledH3":
            return f"### {node_text(children)}\n\n"
        if name == "StyledH4":
            return f"#### {node_text(children)}\n\n"
        if name in ("StyledP", "StyledParagraph"):
            return render_mdx_node(children, names) + "\n\n"
        if name == "StyledInlineCode":
            return f"`{node_text(children)}`"
        if name in ("StyledPre", "PrismCodeBlock", "StyledCodeBlock"):
            # code lives one level down: {children: [["$","$L25",null,{"code":...}]}
            code, lang = None, ""
            for sub in node_text(children) or []:
                pass
            code = None
            lang = ""
            def walk(n):
                nonlocal code, lang
                if isinstance(n, list) and n and n[0] == "$":
                    p = n[3] if len(n) > 3 else None
                    if isinstance(p, dict):
                        if "code" in p:
                            code = p["code"]
                            lang = p.get("language", "") or ""
                        if "children" in p:
                            walk(p["children"])
                elif isinstance(n, list):
                    for it in n:
                        walk(it)
                elif isinstance(n, dict):
                    if "code" in n:
                        code = n.get("code")
                        lang = n.get("language", "") or ""
                    if "children" in n:
                        walk(n["children"])
            walk(children)
            if code:
                fence = "```" + (lang or "")
                return f"{fence}\n{code}\n```\n\n"
            return ""
        if name in ("StyledLi", "StyledUl", "StyledOl"):
            return f"{node_text(children)}\n"
        if name == "StyledTable":
            return f"{node_text(children)}\n\n"
        # Unknown components: recurse through children.
        return render_mdx_node(children, names)
    # Plain nested array of nodes.
    return "".join(render_mdx_node(item, names) for item in node)


def render_mdx(mdx, names):
    parts = []
    for node in mdx:
        parts.append(render_mdx_node(node, names))
    text = "".join(parts)
    # Strip unresolved RSC lazy references (table cells render them as text).
    text = re.sub(r"\$L[0-9a-fA-F]+", "", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip() + "\n"


def sidebar_paths(raw: str):
    """Extract all doc paths+labels from the sidebarData of any page."""
    pushes = decode_pushes(raw)
    items = []
    for s in pushes:
        if '"sidebarData"' not in s:
            continue
        for m in re.finditer(r'\{"type":"doc","label":"((?:[^"\\]|\\.)*)","path":"([^"]+)"', s):
            label = m.group(1).encode().decode("unicode_escape")
            path = m.group(2)
            if path.startswith("/network/v10.4.57/"):
                items.append((path.rsplit("/", 1)[-1], label))
        break
    return items


def main():
    args = sys.argv[1:]
    only = None
    for i, a in enumerate(args):
        if a == "--slug" and i + 1 < len(args):
            only = args[i + 1]
        if a == "--out" and i + 1 < len(args):
            global OUT
            OUT = args[i + 1]
        if a == "--base" and i + 1 < len(args):
            global BASE
            BASE = args[i + 1].rstrip("/")
    os.makedirs(OUT, exist_ok=True)

    # Page list: from the sidebar of a known-good page.
    seed = fetch(f"{BASE}/getinfo")
    pages = sidebar_paths(seed)
    if only:
        pages = [p for p in pages if p[0] == only]
        if not pages:
            pages = [(only, only)]
    print(f"pages to mirror: {len(pages)}")

    ok = fail = 0
    for slug, label in pages:
        url = f"{BASE}/{slug}"
        try:
            raw = fetch(url)
        except Exception as e:
            print(f"FAIL fetch {slug}: {e}")
            fail += 1
            continue
        pushes = decode_pushes(raw)
        if any("NEXT_HTTP_ERROR_FALLBACK;404" in s for s in pushes):
            print(f"SKIP {slug}: 404")
            fail += 1
            continue
        ep = find_endpoint(pushes)
        if ep:
            md = render_endpoint(ep)
        else:
            names = component_names(pushes)
            mdx = find_mdx(pushes)
            if mdx is not None:
                rendered = render_mdx(mdx, names)
                # The guide content usually starts with its own H1; don't
                # duplicate the title when it does.
                if rendered.startswith("# "):
                    md = rendered
                else:
                    md = f"# {label}\n\n{rendered}"
            else:
                body = find_guide_body(pushes)
                md = f"# {label}\n\n{body}\n" if body else ""
        if not md.strip():
            print(f"SKIP {slug}: no content extracted")
            fail += 1
            continue
        with open(os.path.join(OUT, f"{slug}.md"), "w", encoding="utf-8") as f:
            f.write(md)
        ok += 1
        if only:
            print(f"WROTE {slug}.md ({len(md)} chars)")
        time.sleep(0.15)
    print(f"done: {ok} ok, {fail} failed")


if __name__ == "__main__":
    main()
