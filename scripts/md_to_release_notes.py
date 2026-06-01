#!/usr/bin/env python3
"""Render a Markdown fragment into a self-contained HTML page for Sparkle.

Reads Markdown from stdin and writes a complete HTML document to stdout. The
page carries its own CSS (light/dark-mode aware) so it renders sanely inside
Sparkle's WKWebView with no external assets. Supports the small Markdown subset
that release notes actually use: ATX headings, `-`/`*` bullet lists, and
inline bold/italic/code. Pure stdlib — no Markdown library dependency.
"""

import argparse
import html
import re
import sys

CSS = """
:root { color-scheme: light dark; }
body {
  font: -apple-system-body, -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
  font-size: 13px;
  line-height: 1.5;
  margin: 16px 18px;
  color: #1d1d1f;
  background: transparent;
}
h1 { font-size: 17px; margin: 0 0 8px; }
h2 { font-size: 15px; margin: 16px 0 6px; }
h3 { font-size: 13px; margin: 12px 0 4px; }
p { margin: 6px 0; }
ul { margin: 6px 0; padding-left: 20px; }
li { margin: 3px 0; }
code {
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  font-size: 12px;
  background: rgba(0, 0, 0, 0.06);
  padding: 1px 4px;
  border-radius: 4px;
}
a { color: #0a7aff; }
@media (prefers-color-scheme: dark) {
  body { color: #f5f5f7; }
  code { background: rgba(255, 255, 255, 0.12); }
  a { color: #4aa3ff; }
}
""".strip()


def render_inline(text: str) -> str:
    text = html.escape(text, quote=False)
    # Links first, before the emphasis passes — a URL's `_`/`*` shouldn't be
    # mangled into <em>. `&` in hrefs stays escaped (valid in HTML attrs).
    text = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", r'<a href="\2">\1</a>', text)
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    text = re.sub(r"(?<!\*)\*(?!\*)([^*]+?)\*(?!\*)", r"<em>\1</em>", text)
    text = re.sub(r"(?<!\w)_(?!_)([^_]+?)_(?!\w)", r"<em>\1</em>", text)
    return text


def render_body(md: str) -> str:
    out: list[str] = []
    para: list[str] = []
    in_list = False

    def flush_para() -> None:
        if para:
            out.append("<p>" + render_inline(" ".join(para)) + "</p>")
            para.clear()

    def close_list() -> None:
        nonlocal in_list
        if in_list:
            out.append("</ul>")
            in_list = False

    for raw in md.splitlines():
        stripped = raw.strip()
        if not stripped:
            flush_para()
            close_list()
            continue

        heading = re.match(r"(#{1,6})\s+(.*)", stripped)
        if heading:
            flush_para()
            close_list()
            level = len(heading.group(1))
            out.append(f"<h{level}>{render_inline(heading.group(2))}</h{level}>")
            continue

        bullet = re.match(r"[-*]\s+(.*)", stripped)
        if bullet:
            flush_para()
            if not in_list:
                out.append("<ul>")
                in_list = True
            out.append(f"<li>{render_inline(bullet.group(1))}</li>")
            continue

        close_list()
        para.append(stripped)

    flush_para()
    close_list()
    return "\n".join(out)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--title", default="Release Notes", help="HTML <title>")
    args = parser.parse_args()

    body = render_body(sys.stdin.read())
    title = html.escape(args.title, quote=True)
    sys.stdout.write(
        "<!DOCTYPE html>\n"
        '<html lang="en">\n'
        "<head>\n"
        '<meta charset="utf-8">\n'
        f"<title>{title}</title>\n"
        f"<style>\n{CSS}\n</style>\n"
        "</head>\n"
        "<body>\n"
        f"{body}\n"
        "</body>\n"
        "</html>\n"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
