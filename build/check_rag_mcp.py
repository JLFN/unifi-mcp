#!/usr/bin/env python3
"""Generic health check for docs-rag-template derived MCP servers.

Confirms, for one project, everything the template workflow is supposed
to produce: a clean rename, a built binary, a corpus checkout, a built
hybrid index, working queries, a passing smoke test, the Open Grok
registration, the installed skill, and (optionally) the test suites.

Usage:
  python3 /data/build/check_rag_mcp.py [project-dir] [options]

Defaults: project-dir is the current directory; the server name is read
from Cargo.toml; the index env var is read from src/rag.rs (HOME_ENV);
the index dir resolves to that env var, else <project>/index, else
<project>/.rag-index; the binary resolves to <project>/bin/<name>, else
~/.local/bin/<name>.

Options:
  --server NAME    override the server name
  --index DIR      override the index directory
  --bin PATH       override the binary path
  --with-tests     also run cargo test and the pytest suite (slow)
  --no-doctor      skip the open-grok mcp doctor probe
  --no-smoke       skip the smoke.py probe
  --query TEXT     hybrid query used for the query checks (default
                   "how does it work")
  -q/--quiet       only print failures and the summary

Exit code is 0 when every check passes, 1 when any fails.

The script is intentionally project-agnostic: it derives everything it
needs from the project layout and the source, so the same copy confirms
microsoft-365-mcp, powershell-mcp, and any future project built from the
docs-rag-template.
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tomllib

PASS = "PASS"
FAIL = "FAIL"
WARN = "WARN"


def main() -> int:
    args = parse_args()
    project = pathlib.Path(args.project).resolve()
    if not (project / "Cargo.toml").exists():
        fail_line(f"no Cargo.toml at {project}")
        return 1

    results: list[tuple[str, str, str]] = []
    quiet = args.quiet

    def check(name: str, ok: bool, detail: str, status: str | None = None) -> None:
        status = status or (PASS if ok else FAIL)
        results.append((name, status, detail))
        if not quiet or status != PASS:
            print(f"[{status}] {name}: {detail}")

    # ------------------------------------------------------------------
    # Identity and rename completeness
    # ------------------------------------------------------------------
    server = args.server or package_name(project)
    check(
        "server name",
        bool(server) and bool(re.fullmatch(r"[a-z0-9-]{1,64}", server)),
        f"name '{server}' from Cargo.toml",
    )

    env_var = args.env or home_env_from_src(project)
    check("env prefix", bool(env_var), f"HOME_ENV '{env_var}' from src/rag.rs")

    residue = template_residue(project)
    check(
        "template residue",
        not residue,
        "no docs-rag-template/DOCS_RAG strings in source"
        if not residue
        else f"found in {', '.join(residue[:5])}",
    )

    # ------------------------------------------------------------------
    # Build artifact
    # ------------------------------------------------------------------
    binary = args.bin or resolve_binary(project, server)
    check("binary", binary is not None and binary.is_file(), str(binary) if binary else "not found")
    if binary and binary.is_file():
        if not os.access(binary, os.X_OK):
            check("binary executable", False, "not executable")

    # ------------------------------------------------------------------
    # Corpus
    # ------------------------------------------------------------------
    corpus = resolve_corpus(project)
    if corpus:
        md_count = count_md(corpus)
        check(
            "corpus",
            md_count > 0,
            f"{corpus.name} with {md_count} markdown files",
            WARN if md_count == 0 else None,
        )
    else:
        check("corpus", False, "no corpus/ checkout found", WARN)

    # ------------------------------------------------------------------
    # Index
    # ------------------------------------------------------------------
    index = args.index or resolve_index(project, env_var)
    manifest = read_manifest(index) if index else None
    if manifest is None:
        check("index", False, f"no manifest.json at {index}" if index else "index dir not resolved")
        index = None
    else:
        check(
            "index",
            manifest["chunk_count"] > 0 and manifest["file_count"] > 0,
            f"{manifest['chunk_count']} chunks / {manifest['file_count']} files, "
            f"model {manifest['model']}, dim {manifest['dim']}",
        )
        blob = index / "embeddings.bin"
        expected = manifest["chunk_count"] * manifest["dim"] * 4
        ok_size = blob.is_file() and blob.stat().st_size == expected
        check(
            "embeddings.bin",
            ok_size,
            f"{blob.stat().st_size} bytes (expected {expected})" if blob.is_file() else "missing",
        )
        chunks_lines = count_lines(index / "chunks.jsonl")
        check(
            "chunks.jsonl",
            chunks_lines == manifest["chunk_count"],
            f"{chunks_lines} lines (manifest says {manifest['chunk_count']})",
        )
        check(
            "tantivy index",
            (index / "tantivy").is_dir(),
            "present" if (index / "tantivy").is_dir() else "missing",
        )

    # ------------------------------------------------------------------
    # Queries
    # ------------------------------------------------------------------
    if binary and index and manifest:
        check_queries(binary, index, env_var, args.query, args, check, quiet)
    else:
        check("queries", False, "skipped: binary or index unavailable")

    # ------------------------------------------------------------------
    # Smoke test
    # ------------------------------------------------------------------
    if not args.no_smoke and binary and index and manifest:
        smoke = project / "smoke.py"
        if smoke.is_file():
            ok, out = run_smoke(smoke, index, binary, env_var)
            check("smoke.py", ok, out.splitlines()[-1] if out else "no output")
        else:
            check("smoke.py", False, "no smoke.py in project", WARN)

    # ------------------------------------------------------------------
    # Open Grok registration
    # ------------------------------------------------------------------
    check_registration(server, env_var, index, check, quiet)

    if not args.no_doctor:
        check_doctor(server, check, quiet)

    # ------------------------------------------------------------------
    # Test suites (opt-in)
    # ------------------------------------------------------------------
    if args.with_tests:
        ok, out = run_cargo_test(project)
        tail = summarize_tail(out)
        check("cargo test", ok, tail)
        ok, out = run_pytest(project)
        tail = summarize_tail(out)
        check("pytest", ok, tail)

    # ------------------------------------------------------------------
    # Summary
    # ------------------------------------------------------------------
    passed = sum(1 for _, s, _ in results if s == PASS)
    failed = sum(1 for _, s, _ in results if s == FAIL)
    warned = sum(1 for _, s, _ in results if s == WARN)
    print(f"\nsummary: {passed} passed, {failed} failed, {warned} warnings")
    return 1 if failed else 0


# ---------------------------------------------------------------------------
# Resolution helpers
# ---------------------------------------------------------------------------


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", nargs="?", default=".", help="project directory (default: cwd)")
    parser.add_argument("--server", default=None)
    parser.add_argument("--index", default=None)
    parser.add_argument("--bin", default=None)
    parser.add_argument("--env", default=None, help="override the HOME_ENV index env var name")
    parser.add_argument("--with-tests", action="store_true")
    parser.add_argument("--no-doctor", action="store_true")
    parser.add_argument("--no-smoke", action="store_true")
    parser.add_argument("--query", default="how does it work")
    parser.add_argument("-q", "--quiet", action="store_true")
    return parser.parse_args()


def package_name(project: pathlib.Path) -> str | None:
    try:
        with open(project / "Cargo.toml", "rb") as fh:
            data = tomllib.load(fh)
        return data.get("package", {}).get("name")
    except Exception:
        return None


def home_env_from_src(project: pathlib.Path) -> str | None:
    path = project / "src" / "rag.rs"
    if not path.is_file():
        return None
    text = path.read_text(encoding="utf-8", errors="replace")
    m = re.search(r'HOME_ENV:\s*&str\s*=\s*"([A-Z0-9_]+)"', text)
    return m.group(1) if m else None


def template_residue(project: pathlib.Path) -> list[str]:
    """Template strings that must not survive a rename, ignoring build
    artifacts, the corpus checkout, and the index."""
    skip_dirs = {".git", "target", "bin", "corpus", "index", "__pycache__", ".pytest_cache"}
    patterns = re.compile(
        r"docs-rag-template|DOCS_RAG|docs_rag_template|docs rag template|Docs Rag Template"
    )
    hits: list[str] = []
    for root, dirs, files in os.walk(project):
        dirs[:] = [d for d in dirs if d not in skip_dirs]
        for name in files:
            if not name.endswith((".rs", ".toml", ".md", ".py", ".txt")):
                continue
            path = pathlib.Path(root) / name
            try:
                text = path.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            if patterns.search(text):
                hits.append(str(path.relative_to(project)))
                if len(hits) >= 5:
                    return hits
    return hits


def resolve_binary(project: pathlib.Path, server: str) -> pathlib.Path | None:
    candidates = [project / "bin" / server, pathlib.Path.home() / ".local" / "bin" / server]
    for c in candidates:
        if c.is_file():
            return c
    return None


def resolve_corpus(project: pathlib.Path) -> pathlib.Path | None:
    corpus_root = project / "corpus"
    if not corpus_root.is_dir():
        return None
    for entry in sorted(corpus_root.iterdir()):
        if entry.is_dir() and not entry.name.startswith("."):
            return entry
    return None


def count_md(corpus: pathlib.Path) -> int:
    return sum(1 for _ in corpus.rglob("*.md"))


def resolve_index(project: pathlib.Path, env_var: str | None) -> pathlib.Path | None:
    if env_var and os.environ.get(env_var):
        return pathlib.Path(os.environ[env_var])
    for candidate in (project / "index", project / ".rag-index"):
        if candidate.is_dir():
            return candidate
    return project / "index"  # likely missing; callers report


def read_manifest(index: pathlib.Path) -> dict | None:
    path = index / "manifest.json"
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None


def count_lines(path: pathlib.Path) -> int:
    if not path.is_file():
        return -1
    with open(path, encoding="utf-8", errors="replace") as fh:
        return sum(1 for _ in fh)


# ---------------------------------------------------------------------------
# Probes
# ---------------------------------------------------------------------------


def check_queries(
    binary: pathlib.Path,
    index: pathlib.Path,
    env_var: str,
    query: str,
    args: argparse.Namespace,
    check,
    quiet: bool,
) -> None:
    env = dict(os.environ)
    env[env_var] = str(index)

    def run(mode: str) -> tuple[bool, str]:
        proc = subprocess.run(
            [str(binary), "query", query, mode, "3"],
            capture_output=True,
            text=True,
            env=env,
            timeout=180,
        )
        if proc.returncode != 0:
            return False, proc.stderr.strip().splitlines()[-1] if proc.stderr.strip() else "non-zero exit"
        try:
            hits = json.loads(proc.stdout)
        except json.JSONDecodeError:
            return False, "stdout is not JSON"
        if not isinstance(hits, list) or not hits:
            return False, "no hits"
        hit = hits[0]
        fields = ("file", "line_start", "line_end", "text", "score")
        missing = [f for f in fields if f not in hit]
        return (not missing), f"{len(hits)} hits, top {hit.get('file')}" if not missing else f"missing {missing}"

    ok, detail = run("hybrid")
    check(f"query hybrid '{query}'", ok, detail)
    ok, detail = run("bm25")
    check(f"query bm25 '{query}'", ok, detail)


def run_smoke(smoke: pathlib.Path, index: pathlib.Path, binary: pathlib.Path, env_var: str) -> tuple[bool, str]:
    env = dict(os.environ)
    env[env_var] = str(index)
    proc = subprocess.run(
        [sys.executable, str(smoke), str(index), str(binary)],
        capture_output=True,
        text=True,
        env=env,
        timeout=300,
    )
    out = (proc.stdout or proc.stderr).strip()
    return proc.returncode == 0, out or "no output"


def check_registration(server: str, env_var: str | None, index: pathlib.Path | None, check, quiet: bool) -> None:
    config = pathlib.Path.home() / ".opengrok" / "config.toml"
    if not config.is_file():
        check("config registration", False, "no ~/.opengrok/config.toml", WARN)
    else:
        text = config.read_text(encoding="utf-8", errors="replace")
        has_server = f"[mcp_servers.{server}]" in text
        has_env = f"[mcp_servers.{server}.env]" in text
        env_points_at = True
        if env_var and index:
            env_points_at = f'{env_var} = "{index}"' in text
        check(
            "config registration",
            has_server and has_env and env_points_at,
            f"[mcp_servers.{server}] + {env_var} -> {index}",
        )

    skill = pathlib.Path.home() / ".opengrok" / "skills" / server / "SKILL.md"
    name_ok = False
    if skill.is_file():
        m = re.search(r"^name:\s*([a-z0-9-]+)", skill.read_text(encoding="utf-8", errors="replace"), re.M)
        name_ok = bool(m and m.group(1) == server)
    check(
        "installed skill",
        skill.is_file() and name_ok,
        str(skill) if skill.is_file() else "missing",
    )


def check_doctor(server: str, check, quiet: bool) -> None:
    doctor = shutil.which("open-grok")
    if not doctor:
        check("open-grok doctor", False, "open-grok CLI not on PATH", WARN)
        return
    proc = subprocess.run(
        [doctor, "mcp", "doctor", server],
        capture_output=True,
        text=True,
        timeout=300,
    )
    out = (proc.stdout or proc.stderr)
    m = re.search(r"Found (\d+) healthy, (\d+) failing", out)
    if m:
        healthy, failing = int(m.group(1)), int(m.group(2))
        check("open-grok doctor", healthy >= 1 and failing == 0, f"Found {healthy} healthy, {failing} failing")
    else:
        check("open-grok doctor", proc.returncode == 0, "no summary line in doctor output", WARN)


def run_cargo_test(project: pathlib.Path) -> tuple[bool, str]:
    proc = subprocess.run(
        ["cargo", "test"],
        cwd=project,
        capture_output=True,
        text=True,
        timeout=1800,
    )
    return proc.returncode == 0, proc.stdout or proc.stderr


def run_pytest(project: pathlib.Path) -> tuple[bool, str]:
    proc = subprocess.run(
        [sys.executable, "-m", "pytest", "pytest/", "-q"],
        cwd=project,
        capture_output=True,
        text=True,
        timeout=900,
    )
    return proc.returncode == 0, proc.stdout or proc.stderr


def summarize_tail(output: str) -> str:
    lines = [ln for ln in output.splitlines() if ln.strip()]
    return lines[-1].strip() if lines else "no output"


def fail_line(message: str) -> None:
    print(f"[FAIL] {message}")


if __name__ == "__main__":
    sys.exit(main())
