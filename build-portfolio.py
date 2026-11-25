"""Сборка «нечитаемой» версии портфолио для публикации.

Что делает:
  1. Минифицирует CSS (убирает комментарии, пробелы, лишние ; и }).
  2. Минифицирует JS (убирает комментарии и отступы; строки не трогает).
  3. Собирает всё в один index.html: CSS — внутрь <style>, JS — внутрь <script>.
     Отдельных файлов css/*.css и js/*.js в публикации не остаётся вовсе.
  4. Убирает HTML-комментарии.

Честно: это НЕ защита. Браузер обязан получить код, чтобы отрисовать страницу.
Задача — чтобы в F12 было нечего читать глазами, а не чтобы скрыть логику.

Использование:
    py -I build-portfolio.py            # собрать в dist/
    py -I build-portfolio.py --check    # только проверить, ничего не писать
"""
from __future__ import annotations

import re
import shutil
import sys
from pathlib import Path

ROOT = Path(r"E:\portfolio")
DIST = ROOT / "dist"

# Порядок важен: каскад CSS зависит от него.
CSS_ORDER = ["tokens.css", "base.css", "layout.css", "components.css", "about.css"]


def minify_css(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r"\s+", " ", text)
    # пробелы вокруг служебных символов не нужны
    text = re.sub(r"\s*([{};:,>~+])\s*", r"\1", text)
    text = re.sub(r";}", "}", text)
    text = re.sub(r"\s*!\s*important", "!important", text)
    return text.strip()


def minify_js(text: str) -> str:
    out: list[str] = []
    i, n = 0, len(text)
    quote = ""
    while i < n:
        ch = text[i]
        if quote:
            out.append(ch)
            if ch == "\\" and i + 1 < n:
                out.append(text[i + 1])
                i += 2
                continue
            if ch == quote:
                quote = ""
            i += 1
            continue
        # строки в кавычках копируем дословно
        if ch in "\"'`":
            quote = ch
            out.append(ch)
            i += 1
            continue
        # комментарии
        if ch == "/" and i + 1 < n:
            nxt = text[i + 1]
            if nxt == "/":
                j = text.find("\n", i)
                i = n if j < 0 else j
                continue
            if nxt == "*":
                j = text.find("*/", i + 2)
                i = n if j < 0 else j + 2
                continue
        out.append(ch)
        i += 1
    js = "".join(out)
    # схлопываем пробелы, но сохраняем переводы строк: в JS они иногда значимы (ASI)
    js = re.sub(r"[ \t]+", " ", js)
    js = re.sub(r"\n\s*\n+", "\n", js)
    js = re.sub(r"^\s+|\s+$", "", js, flags=re.M)
    return js.strip()


def strip_html_comments(text: str) -> str:
    return re.sub(r"<!--(?!\[if).*?-->", "", text, flags=re.S)


def build() -> str:
    css = "\n".join(minify_css((ROOT / "css" / name).read_text(encoding="utf-8")) for name in CSS_ORDER)
    js = minify_js((ROOT / "js" / "main.js").read_text(encoding="utf-8"))
    html = strip_html_comments((ROOT / "index.html").read_text(encoding="utf-8"))

    # Убираем внешние подключения — всё уже внутри.
    html = re.sub(r'<link[^>]+href="css/[^"]+"[^>]*>', "", html)
    html = re.sub(r'<script[^>]+src="js/[^"]+"[^>]*>\s*</script>', "", html)
    html = re.sub(r"\n{3,}", "\n\n", html)

    inject = f"<style>{css}</style>"
    if "</head>" in html:
        html = html.replace("</head>", inject + "\n</head>", 1)
    else:
        html = inject + html

    script = f"<script>{js}</script>"
    if "</body>" in html:
        html = html.replace("</body>", script + "\n</body>", 1)
    else:
        html += script

    return html


def main() -> int:
    check_only = "--check" in sys.argv
    html = build()
    original = (ROOT / "index.html").stat().st_size
    css_size = sum((ROOT / "css" / n).stat().st_size for n in CSS_ORDER)
    js_size = (ROOT / "js" / "main.js").stat().st_size
    print(f"исходно: html={original} css={css_size} js={js_size} всего={original + css_size + js_size}")
    print(f"после:   index.html={len(html.encode('utf-8'))} байт, внешних файлов 0")
    print(f"сжатие:  {100 - len(html.encode()) * 100 // (original + css_size + js_size)}%")

    if check_only:
        return 0

    if DIST.exists():
        shutil.rmtree(DIST)
    DIST.mkdir(parents=True)
    (DIST / "index.html").write_text(html, encoding="utf-8")
    # Ассеты копируем как есть: картинки и модели без них не работают.
    for item in ("assets", ".nojekyll"):
        src = ROOT / item
        if not src.exists():
            continue
        dst = DIST / item
        if src.is_dir():
            shutil.copytree(src, dst)
        else:
            shutil.copy2(src, dst)
    print(f"готово: {DIST}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())