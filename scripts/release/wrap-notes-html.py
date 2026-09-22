#!/usr/bin/env python3
"""Wrap rendered release-notes HTML in a small styled standalone document, so Sparkle can show it
directly with no further network fetch. Stdin: an HTML fragment (e.g. from GitHub's markdown render
API). Stdout: a full HTML document. See docs/superpowers/specs/2026-09-22-sparkle-release-notes-design.md.
"""
import sys

STYLE = """
body {
  font: 13px -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
  color: #1d1d1f;
  margin: 12px 16px;
  word-wrap: break-word;
}
a { color: #0068da; }
h1, h2, h3 { font-size: 1.05em; }
pre, code { font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: 0.95em; }
pre { white-space: pre-wrap; overflow-wrap: anywhere; }
@media (prefers-color-scheme: dark) {
  body { color: #f5f5f7; }
  a { color: #4da3ff; }
}
"""

FALLBACK = "<p>No release notes were provided for this update.</p>"


def wrap(fragment):
    body = fragment.strip() or FALLBACK
    return (
        "<!DOCTYPE html>\n<html>\n<head>\n<meta charset=\"utf-8\">\n"
        f"<style>{STYLE}</style>\n</head>\n<body>\n{body}\n</body>\n</html>\n"
    )


def main():
    sys.stdout.write(wrap(sys.stdin.read()))


if __name__ == "__main__":
    main()
