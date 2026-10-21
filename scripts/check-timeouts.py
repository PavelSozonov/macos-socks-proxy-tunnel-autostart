#!/usr/bin/env python3
"""Check that network calls and CI jobs carry a time limit.

  check-timeouts.py [--strict] FILE...
      the given files (the pre-commit hook passes the staged ones)
  check-timeouts.py [--strict] --all [DIR]
      every file git tracks under DIR (default: the current directory);
      paths with a `testdata` directory are skipped

Rules (every finding is a warning; --strict turns findings into exit 1):

* curl         `curl` without `--max-time` / `-m`;
* job-timeout  a GitHub Actions job without `timeout-minutes` (a job that
               calls a reusable workflow cannot carry one and is skipped);
* ssh          `ssh` / `scp` / `sftp` without `-o ConnectTimeout=...`;
* rsync        `rsync` to a remote without `--timeout` (or ConnectTimeout in
               its `-e` / `--rsh` command);
* docker-pull  `docker pull`, `docker image pull`, `docker compose pull`,
               `docker-compose pull` without a time limit;
* git-clone    `git clone` without a time limit (`timeout N`, or
               `-c http.lowSpeedLimit=...` / `http.lowSpeedTime`, or the
               GIT_HTTP_LOW_SPEED_* variables);
* py-http      `requests.<verb>()` and `urllib.request.urlopen()` without a
               timeout; httpx only with an explicit `timeout=None` (its
               default is 5 seconds);
* boto3        `boto3.client()` / `boto3.resource()` without `config=`, and a
               botocore `Config()` without `connect_timeout` or `read_timeout`;
* asyncpg      `asyncpg.connect()` / `asyncpg.create_pool()` without
               `command_timeout` (queries are unbounded by default).

Where commands are looked for: shell scripts (`*.sh`, `*.bash`, a shell
shebang, `*.sh.j2`), `run:` of workflow and composite-action steps, Ansible
`shell` / `command` / `raw` tasks in other YAML, Dockerfile `RUN`, and in
Python the argument list of `subprocess.*` / `asyncio.create_subprocess_*`.
A call is judged whole, across line breaks: Python by its syntax tree,
shell by logical lines (backslash continuations joined), YAML by its nodes.

A command wrapped in `timeout N`, a workflow step with its own
`timeout-minutes` and a Python subprocess call with `timeout=` count as
limited. Exception: a comment `# timeout-ok: <reason>` on any line of the
call or on the line right above it; the reason is required.

Exit code: 0 - no findings, or findings without --strict; 1 - findings with
--strict; 2 - usage error. Standard library only, plus PyYAML for YAML
files (without it YAML files are skipped with a notice).
"""

from __future__ import annotations

import argparse
import ast
import re
import shlex
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover - depends on the environment
    yaml = None

MARKER = re.compile(r"#\s*timeout-ok:\s*\S")
SHELLS = re.compile(r"^#!.*\b(?:ba|z|da|k)?sh\b")
SEPARATORS = {";", "&", "&&", "|", "||", "|&", "(", ")", ";;", "{", "}", "!", "\n"}
WRAPPERS = {"sudo", "exec", "command", "nice", "nohup", "time", "env", "stdbuf", "xargs"}
CONTROL = {"if", "then", "else", "elif", "do", "while", "until", "fi", "done", "!", "{", "}"}
CASE_LABEL = re.compile(r"^\s*[^\s()$=;&|]+\)")
HEREDOC = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")
# A clone from a local path (a test fixture, a bare repository on disk) does
# not touch the network.
LOCAL_SOURCE = re.compile(r"^(?:/|\.|~|file://|\$\{?[A-Za-z_][A-Za-z0-9_]*\}?/)")
CLONE_ARG_OPTS = {
    "-b",
    "--branch",
    "-o",
    "--origin",
    "--depth",
    "-c",
    "--config",
    "-u",
    "--upload-pack",
    "--reference",
    "--separate-git-dir",
    "--filter",
    "-j",
    "--jobs",
}
ANSIBLE_SHELL = {
    "shell",
    "command",
    "raw",
    "ansible.builtin.shell",
    "ansible.builtin.command",
    "ansible.builtin.raw",
}
HTTP_VERBS = {"get", "post", "put", "patch", "delete", "head", "options", "request"}
SUBPROCESS = {
    "subprocess.run",
    "subprocess.call",
    "subprocess.check_call",
    "subprocess.check_output",
    "subprocess.Popen",
    "asyncio.create_subprocess_exec",
    "asyncio.create_subprocess_shell",
}


@dataclass(frozen=True)
class Finding:
    path: str
    line: int
    rule: str
    message: str

    def __str__(self) -> str:
        return f"{self.path}:{self.line}: [{self.rule}] {self.message}"


# --- shell -----------------------------------------------------------------


def logical_lines(text: str, first_line: int = 1) -> list[tuple[int, int, str]]:
    """(first line, last line, text) with backslash continuations joined and
    heredoc bodies dropped."""
    out: list[tuple[int, int, str]] = []
    lines = text.splitlines()
    i = 0
    heredoc: str | None = None
    while i < len(lines):
        start = i
        if heredoc is not None:
            if lines[i].strip() == heredoc:
                heredoc = None
            i += 1
            continue
        buf = lines[i]
        while buf.endswith("\\") and i + 1 < len(lines):
            i += 1
            buf = buf[:-1] + " " + lines[i]
        m = HEREDOC.search(buf)
        if m:
            heredoc = m.group(2)
        out.append((first_line + start, first_line + i, buf))
        i += 1
    return out


def tokens(text: str) -> list[str]:
    lex = shlex.shlex(text, posix=True, punctuation_chars=";&|()<>")
    lex.whitespace_split = True
    lex.commenters = "#"
    try:
        return list(lex)
    except ValueError:
        # unbalanced quotes (templating, odd quoting): judge the plain words
        return re.findall(r"[;&|()]+|[^\s;&|()]+", text.split(" #", 1)[0])


def simple_commands(words: list[str]) -> list[list[str]]:
    """Split a token list into simple commands; `$(...)` inside a word is
    judged as a command of its own."""
    out: list[list[str]] = []
    cur: list[str] = []
    for w in words:
        if w in SEPARATORS or set(w) <= set(";&|()"):
            if cur:
                out.append(cur)
            cur = []
            continue
        if "$(" in w:
            inner = w.split("$(", 1)[1].rsplit(")", 1)[0]
            out.extend(simple_commands(tokens(inner)))
        cur.append(w)
    if cur:
        out.append(cur)
    return out


def _strip_wrappers(words: list[str]) -> tuple[list[str], bool, dict[str, str]]:
    """Command words without assignments and wrappers; limited by `timeout`?"""
    env: dict[str, str] = {}
    limited = False
    i = 0
    while i < len(words):
        w = words[i]
        if w in CONTROL:
            i += 1
        elif re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", w):
            k, _, v = w.partition("=")
            env[k] = v
            i += 1
        elif w == "timeout" or w == "gtimeout":
            limited = True
            i += 1
            while i < len(words) and words[i].startswith("-"):
                i += 2 if words[i] in ("-s", "-k", "--signal", "--kill-after") else 1
            i += 1  # the duration
        elif w in WRAPPERS:
            i += 1
            while i < len(words) and words[i].startswith("-"):
                i += 2 if words[i] in ("-u", "-g", "-n", "-I") else 1
        else:
            break
    return words[i:], limited, env


def _has_opt(args: list[str], long: str, short: str | None = None) -> bool:
    for a in args:
        if a == long or a.startswith(long + "="):
            return True
        if short and re.match(rf"^-[A-Za-z]*{short}(?:\d+)?$", a) and not a.startswith("--"):
            return True
    return False


def judge_command(words: list[str], limited: bool = False) -> tuple[str, str] | None:
    """(rule, message) for one simple command, or None."""
    words, wrapped, env = _strip_wrappers(words)
    limited = limited or wrapped
    if not words:
        return None
    cmd, args = Path(words[0]).name, words[1:]
    if cmd == "curl":
        if not _has_opt(args, "--max-time", "m"):
            return "curl", "curl without --max-time / -m"
    elif cmd in ("ssh", "scp", "sftp"):
        if "-G" in args or "-V" in args:  # prints the config or version, no connection
            return None
        if not any("ConnectTimeout" in a for a in args):
            return "ssh", f"{cmd} without -o ConnectTimeout=..."
    elif cmd == "rsync":
        remote = any(
            not a.startswith("-") and (re.match(r"^[^/=]*:", a) or a.startswith("rsync://"))
            for a in args
        )
        if remote and not (_has_opt(args, "--timeout") or any("ConnectTimeout" in a for a in args)):
            return "rsync", "rsync to a remote without --timeout"
    elif cmd in ("docker", "podman", "docker-compose"):
        sub = [a for a in args if not a.startswith("-")]
        # `docker pull`, `docker image pull`, `docker compose [-p x] pull`
        pull = bool(sub) and sub[0] in ("pull", "image", "compose") and "pull" in sub[:3]
        if pull and not limited:
            return "docker-pull", f"{cmd} {' '.join(sub[:2])} without a time limit (timeout N)"
    elif cmd == "git":
        i = 0
        low_speed = any(k.startswith("GIT_HTTP_LOW_SPEED") for k in env)
        while i < len(args) and args[i].startswith("-"):
            if args[i] in ("-C", "-c"):
                if args[i] == "-c" and i + 1 < len(args) and "lowspeed" in args[i + 1].lower():
                    low_speed = True
                i += 2
            else:
                i += 1
        if args[i : i + 1] == ["clone"] and not (limited or low_speed):
            rest = args[i + 1 :]
            j = 0
            while j < len(rest) and rest[j].startswith("-"):
                j += 2 if rest[j] in CLONE_ARG_OPTS else 1
            source = rest[j] if j < len(rest) else ""
            low_speed = any("lowspeed" in a.lower() for a in rest)
            if not (low_speed or LOCAL_SOURCE.match(source)):
                return (
                    "git-clone",
                    "git clone without a time limit (timeout N or http.lowSpeedLimit)",
                )
    return None


def scan_shell(
    text: str, path: str, first_line: int = 1, limited: bool = False, marks: set[int] = frozenset()
) -> list[Finding]:
    out = []
    for start, end, line in logical_lines(text, first_line):
        if any(n in marks for n in range(start - 1, end + 1)):
            continue
        if MARKER.search(line):
            continue
        line = CASE_LABEL.sub("", line, count=1)  # `sftp)` in a case is a label
        for words in simple_commands(tokens(line)):
            got = judge_command(words, limited)
            if got:
                out.append(Finding(path, start, *got))
    return out


# --- Python ----------------------------------------------------------------


def _aliases(tree: ast.AST) -> dict[str, str]:
    names: dict[str, str] = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for a in node.names:
                if a.asname:
                    names[a.asname] = a.name
                else:
                    head = a.name.split(".")[0]
                    names[head] = head
        elif isinstance(node, ast.ImportFrom) and node.module and not node.level:
            for a in node.names:
                names[a.asname or a.name] = f"{node.module}.{a.name}"
    return names


def _dotted(func: ast.expr, names: dict[str, str]) -> str | None:
    parts: list[str] = []
    while isinstance(func, ast.Attribute):
        parts.append(func.attr)
        func = func.value
    if not isinstance(func, ast.Name) or func.id not in names:
        return None
    return ".".join([names[func.id], *reversed(parts)])


def _kw(call: ast.Call) -> dict[str | None, ast.expr]:
    return {k.arg: k.value for k in call.keywords}


def judge_call(call: ast.Call, full: str) -> tuple[str, str] | None:
    kw = _kw(call)
    if None in kw:  # **kwargs: cannot judge
        return None
    mod, _, func = full.rpartition(".")
    if mod in ("requests", "requests.api") and func in HTTP_VERBS:
        if "timeout" not in kw:
            return "py-http", f"{full}() without timeout="
    elif full == "urllib.request.urlopen":
        if "timeout" not in kw and len(call.args) < 3:
            return "py-http", "urlopen() without timeout="
    elif mod == "httpx" and (func in HTTP_VERBS | {"stream", "Client", "AsyncClient"}):
        t = kw.get("timeout")
        if isinstance(t, ast.Constant) and t.value is None:
            return "py-http", f"{full}(timeout=None)"
    elif full in ("boto3.client", "boto3.resource"):
        if "config" not in kw:
            return "boto3", f"{full}() without config= (connect/read timeouts)"
    elif full == "botocore.config.Config":
        missing = [k for k in ("connect_timeout", "read_timeout") if k not in kw]
        if missing:
            return "boto3", f"botocore Config() without {' / '.join(missing)}"
    elif full in ("asyncpg.connect", "asyncpg.create_pool"):
        if "command_timeout" not in kw:
            return "asyncpg", f"{full}() without command_timeout="
    elif full in SUBPROCESS:
        if "timeout" in kw:
            return None
        if full.endswith("_exec"):
            items = call.args
        elif call.args and isinstance(call.args[0], (ast.List, ast.Tuple)):
            items = call.args[0].elts
        elif call.args and isinstance(call.args[0], ast.Constant):
            text = call.args[0].value
            if isinstance(text, str):
                for words in simple_commands(tokens(text)):
                    got = judge_command(words)
                    if got:
                        return got
            return None
        else:
            return None
        words = [
            e.value if isinstance(e, ast.Constant) and isinstance(e.value, str) else "…"
            for e in items
        ]
        return judge_command(words)
    return None


def scan_python(text: str, path: str) -> list[Finding]:
    try:
        tree = ast.parse(text)
    except (SyntaxError, ValueError, RecursionError, MemoryError):
        return []  # not Python, a NUL byte or nesting beyond the parser: skip
    lines = text.splitlines()
    names = _aliases(tree)
    out = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        full = _dotted(node.func, names)
        if not full:
            continue
        got = judge_call(node, full)
        if not got:
            continue
        span = lines[max(node.lineno - 2, 0) : node.end_lineno or node.lineno]
        if any(MARKER.search(s) for s in span):
            continue
        out.append(Finding(path, node.lineno, *got))
    return out


# --- YAML ------------------------------------------------------------------


def _marked_lines(text: str) -> set[int]:
    return {i for i, s in enumerate(text.splitlines(), 1) if MARKER.search(s)}


def _scalar_start(node) -> int:
    """1-based line of the first content line of a scalar."""
    return node.start_mark.line + (2 if node.style in ("|", ">") else 1)


def _get(mapping, key: str):
    for k, v in mapping.value:
        if getattr(k, "value", None) == key:
            return k, v
    return None, None


def _steps(steps_node, path: str, marks: set[int]) -> list[Finding]:
    out = []
    if not isinstance(steps_node, yaml.SequenceNode):
        return out
    for step in steps_node.value:
        if not isinstance(step, yaml.MappingNode):
            continue
        _, run = _get(step, "run")
        if not isinstance(run, yaml.ScalarNode):
            continue
        _, t = _get(step, "timeout-minutes")
        out += scan_shell(run.value, path, _scalar_start(run), limited=t is not None, marks=marks)
    return out


def scan_workflow(root, path: str, marks: set[int]) -> list[Finding]:
    out = []
    _, jobs = _get(root, "jobs")
    if not isinstance(jobs, yaml.MappingNode):
        return out
    for key, job in jobs.value:
        if not isinstance(job, yaml.MappingNode):
            continue
        line = key.start_mark.line + 1
        unlimited = _get(job, "uses")[1] is None and _get(job, "timeout-minutes")[1] is None
        if unlimited and not {line - 1, line} & marks:
            out.append(
                Finding(path, line, "job-timeout", f"job {key.value} without timeout-minutes")
            )
        out += _steps(_get(job, "steps")[1], path, marks)
    return out


def scan_ansible(node, path: str, marks: set[int]) -> list[Finding]:
    out = []
    if isinstance(node, yaml.MappingNode):
        for k, v in node.value:
            if getattr(k, "value", None) in ANSIBLE_SHELL:
                if isinstance(v, yaml.MappingNode):
                    v = _get(v, "cmd")[1]
                if isinstance(v, yaml.ScalarNode):
                    out += scan_shell(v.value, path, _scalar_start(v), marks=marks)
                    continue
            out += scan_ansible(v, path, marks)
    elif isinstance(node, yaml.SequenceNode):
        for v in node.value:
            out += scan_ansible(v, path, marks)
    return out


def scan_yaml(text: str, path: str) -> list[Finding]:
    if yaml is None:
        return []
    try:
        docs = list(yaml.compose_all(text, Loader=yaml.SafeLoader))
    except (yaml.YAMLError, RecursionError, MemoryError):
        return []
    marks = _marked_lines(text)
    out = []
    p = Path(path)
    for root in docs:
        if not isinstance(root, yaml.MappingNode) and not isinstance(root, yaml.SequenceNode):
            continue
        if ".github/workflows/" in p.as_posix() and isinstance(root, yaml.MappingNode):
            out += scan_workflow(root, path, marks)
        elif p.name in ("action.yml", "action.yaml") and isinstance(root, yaml.MappingNode):
            _, runs = _get(root, "runs")
            if isinstance(runs, yaml.MappingNode):
                out += _steps(_get(runs, "steps")[1], path, marks)
        else:
            out += scan_ansible(root, path, marks)
    return out


# --- Dockerfile ------------------------------------------------------------


def scan_dockerfile(text: str, path: str) -> list[Finding]:
    out = []
    marks = _marked_lines(text)
    for start, end, line in logical_lines(text):
        m = re.match(r"^\s*RUN\s+(.*)$", line, re.IGNORECASE)
        if not m or any(n in marks for n in range(start - 1, end + 1)):
            continue
        for words in simple_commands(tokens(m.group(1))):
            got = judge_command(words)
            if got:
                out.append(Finding(path, start, *got))
    return out


# --- files -----------------------------------------------------------------


def kind(path: Path, text: str) -> str | None:
    name = path.name
    if name.endswith(".py"):
        return "python"
    if name.endswith((".yml", ".yaml")):
        return "yaml"
    if name.endswith((".sh", ".bash", ".sh.j2", ".bash.j2")):
        return "shell"
    if name.startswith(("Dockerfile", "Containerfile")) or name.endswith(".Dockerfile"):
        return "dockerfile"
    if "." not in name and SHELLS.match(text.split("\n", 1)[0]):
        return "shell"
    return None


def scan_file(path: Path, shown: str | None = None) -> list[Finding]:
    shown = shown or str(path)
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return []
    scan = {
        "python": scan_python,
        "yaml": scan_yaml,
        "shell": lambda t, s: scan_shell(t, s, marks=_marked_lines(t)),
        "dockerfile": scan_dockerfile,
    }.get(kind(path, text))
    if scan is None:
        return []
    try:
        return scan(text, shown)
    except Exception as e:  # noqa: BLE001 - the check only warns; an odd file must not stop a commit
        print(f"check-timeouts: {shown}: skipped ({type(e).__name__})", file=sys.stderr)
        return []


def tracked(root: Path) -> list[Path]:
    out = subprocess.run(
        ["git", "-C", str(root), "ls-files", "-z"],
        capture_output=True,
        text=True,
        check=True,
        timeout=60,
    ).stdout
    return [root / p for p in out.split("\0") if p and "testdata" not in Path(p).parts]


def scan_tree(root: Path) -> list[Finding]:
    out = []
    for p in tracked(root):
        if p.is_file():
            out += scan_file(p, str(p.relative_to(root)))
    return out


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("--strict", action="store_true", help="findings give exit code 1")
    ap.add_argument("--all", metavar="DIR", nargs="?", const=".", help="every tracked file")
    ap.add_argument("files", nargs="*", type=Path)
    args = ap.parse_args(argv)
    if bool(args.all) == bool(args.files):
        ap.print_usage(sys.stderr)
        return 2
    if yaml is None:
        print("check-timeouts: PyYAML is not installed - YAML files skipped", file=sys.stderr)
    try:
        found = (
            scan_tree(Path(args.all)) if args.all else [f for p in args.files for f in scan_file(p)]
        )
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, OSError) as e:
        print(f"check-timeouts: {e}", file=sys.stderr)
        return 2
    for f in found:
        print(f"warning: {f}")
    if found:
        print(f"{len(found)} timeout finding(s); exception: '# timeout-ok: <reason>'")
    return 1 if (found and args.strict) else 0


if __name__ == "__main__":
    sys.exit(main())
