#!/usr/bin/env python3
"""Inject ttyd-patch/inject.css and inject.js into the built ttyd web client.

The CSS/JS live in separate template files next to this script
(ttyd-patch/inject.css, ttyd-patch/inject.js) so they can be edited without
touching Python. Idempotent: skips if the marker is already present.

Usage: patch-ttyd-mobile.py /usr/share/ttyd/index.html
"""
import os
import sys

MARKER = "ttyd-patch"
HERE = os.path.dirname(os.path.abspath(__file__))


def main() -> int:
    path = sys.argv[1]
    with open(os.path.join(HERE, "ttyd-patch", "inject.css"), encoding="utf-8") as fh:
        css = fh.read()
    with open(os.path.join(HERE, "ttyd-patch", "inject.js"), encoding="utf-8") as fh:
        js = fh.read()
    with open(path, encoding="utf-8") as fh:
        html = fh.read()
    if MARKER in html:
        print("ttyd patch already present, skipping")
        return 0
    style = f"<style>/* {MARKER} */\n{css}</style>"
    script = f"<script>/* {MARKER} */\n{js}</script>"
    if "</head>" in html:
        html = html.replace("</head>", style + "\n</head>", 1)
    else:
        html = style + "\n" + html
    if "</body>" in html:
        html = html.replace("</body>", script + "\n</body>", 1)
    else:
        html = html + "\n" + script + "\n"
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(html)
    print("injected ttyd patch (css+js) into", path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
