#!/usr/bin/env python3
"""Builds glasspowertools.com into _site/ — the landing and product pages, the help, and the feeds.

    python3 Tools/Site/build_site.py           # build into _site/
    python3 -m http.server -d _site 8090       # preview at http://localhost:8090

Sources, all in site/:
- pages/*.html   hand-written page fragments; a leading <!-- key: value --> block sets title,
                 description and nav label.
- help/registry.json and help/<slug>.md
                 the help: one registry drives the sidebar, search, metadata, sitemap and llms.txt.
                 Pages are GitHub-flavoured Markdown, rendered by pandoc, GitHub alerts included.
- static/        stylesheet, script, images, and appcast.xml (the Mac update feed, written by the
                 release script).
- layout.html    the one page shell.

SECURITY.md is rendered from the repository root, so the site cannot disagree with it.

The build fails, and writes nothing, if a registry entry has no page or a page no entry, if an internal
link or anchor does not resolve, or if an IPv4 address outside the ranges reserved for documentation
appears in a page (the repository's rule 61: examples, not machines). Deploying _site/ is the
maintainer's, and how and where is not recorded here.
"""
import html
import json
import re
import shutil
import subprocess
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
SITE = ROOT / "site"
OUT = ROOT / "_site"
BASE_URL = "https://glasspowertools.com/"
REPO = "https://github.com/msitarzewski/GlassPowerTools"

# (output, nav label). Order is the header's order; pages without a label are footer links.
NAV = [("index.html", "Overview"), ("why.html", "Why"), ("help/index.html", "Help"),
       ("security.html", "Security")]
FOOTER = [("terminal.html", "Terminal"), ("databases.html", "Databases"), ("desktops.html", "Remote desktops"),
          ("editor.html", "Editor"), ("security.html", "Security"), ("help/index.html", "Help"),
          (REPO, "Source")]
MARKDOWN = {"SECURITY.md": ("security.html", "Security", "How Glass Power Tools protects credentials and connections, what it does not protect, and how to report a problem.")}
DOCUMENTATION_RANGES = ("192.0.2.", "198.51.100.", "203.0.113.", "127.0.0.1", "0.0.0.0", "255.255.255.")

errors = []


def fail(message):
    errors.append(message)


def front_matter(text):
    match = re.match(r"\s*<!--(.*?)-->", text, re.S)
    meta = {}
    if match:
        for line in match.group(1).strip().splitlines():
            key, _, value = line.partition(":")
            meta[key.strip()] = value.strip()
        text = text[match.end():]
    return meta, text


def pandoc(markdown_text):
    return subprocess.run(["pandoc", "--from=gfm+alerts", "--to=html5", "--wrap=none"],
                          input=markdown_text, check=True, capture_output=True, text=True).stdout


def plain(fragment):
    fragment = re.sub(r'<a class="anchor"[^>]*>#</a>', "", fragment)
    text = re.sub(r"<[^>]+>", " ", fragment)
    return re.sub(r"\s+", " ", html.unescape(text)).strip()


def nav_html(current, root):
    items = []
    for target, label in NAV:
        here = ' aria-current="page"' if target == current or (target == "help/index.html" and current.startswith("help/")) else ""
        items.append(f'      <a href="{root}{target}"{here}>{html.escape(label)}</a>')
    return "\n".join(items)


def footer_html(root):
    links = []
    for target, label in FOOTER:
        href = target if target.startswith("http") else root + target
        links.append(f'    <a href="{href}">{html.escape(label)}</a>')
    return "\n".join(links)


def render(layout, output, *, title, description, body, og_type="website", jsonld=None):
    depth = output.count("/")
    root = "../" * depth
    graph = jsonld or {"@context": "https://schema.org", "@type": "WebPage", "name": title,
                       "description": description, "url": BASE_URL + output}
    page = (layout
            .replace("{{title}}", html.escape(title))
            .replace("{{og_title}}", html.escape(title))
            .replace("{{description}}", html.escape(description, quote=True))
            .replace("{{canonical}}", BASE_URL + ("" if output == "index.html" else output))
            .replace("{{base_url}}", BASE_URL)
            .replace("{{og_type}}", og_type)
            .replace("{{jsonld}}", json.dumps(graph, ensure_ascii=False).replace("</", "<\\/"))
            .replace("{{nav}}", nav_html(output, root))
            .replace("{{footer}}", footer_html(root))
            .replace("{{body}}", body)
            .replace("{{root}}", root))
    path = OUT / output
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(page)
    return page


def link_help(fragment):
    """`page.md#anchor` between help pages becomes `page.html#anchor`; headings get anchor links."""
    fragment = re.sub(r'href="([a-z0-9-]+)\.md(#[^"]*)?"', lambda m: f'href="{m.group(1)}.html{m.group(2) or ""}"', fragment)
    fragment = re.sub(r'<(h[23]) id="([^"]+)">(.*?)</\1>',
                      lambda m: f'<{m.group(1)} id="{m.group(2)}">{m.group(3)}<a class="anchor" href="#{m.group(2)}" aria-label="Link to this section">#</a></{m.group(1)}>',
                      fragment)
    return fragment


def build_help(layout, registry):
    pages = [(group["name"], page) for group in registry["groups"] for page in group["pages"]]
    slugs = [page["slug"] for _, page in pages]
    on_disk = {p.stem for p in (SITE / "help").glob("*.md")}
    for missing in sorted(set(slugs) - on_disk):
        fail(f"help: registry names {missing}, which has no site/help/{missing}.md")
    for extra in sorted(on_disk - set(slugs)):
        fail(f"help: site/help/{extra}.md is not in registry.json")

    index, sidebar_groups = [], []
    for group in registry["groups"]:
        items = "".join(f'<li><a href="{{ROOTH}}{p["slug"]}.html" data-slug="{p["slug"]}">{html.escape(p["title"])}</a></li>'
                        for p in group["pages"])
        sidebar_groups.append(f'<h4>{html.escape(group["name"])}</h4><ul>{items}</ul>')
    sidebar = "".join(sidebar_groups)

    rendered = {}
    for position, (group, page) in enumerate(pages):
        slug = page["slug"]
        source = SITE / "help" / f"{slug}.md"
        if not source.exists():
            continue
        text = source.read_text()
        heading = re.match(r"#\s+(.+)", text)
        if heading and heading.group(1).strip() != page["title"]:
            fail(f"help/{slug}: its heading '{heading.group(1).strip()}' differs from the registry title '{page['title']}'")
        body = link_help(pandoc(text))
        rendered[slug] = body
        for section in re.split(r"(?=<h2 id=)", body):
            match = re.match(r'<h2 id="([^"]+)">(.*?)<a class="anchor"', section)
            entry = {"title": page["title"], "group": group, "body": plain(section)[:2000]}
            if match:
                entry.update(heading=plain(match.group(2)), url=f"help/{slug}.html#{match.group(1)}")
            else:
                entry.update(url=f"help/{slug}.html")
            index.append(entry)

        previous = pages[position - 1][1] if position > 0 else None
        following = pages[position + 1][1] if position + 1 < len(pages) else None
        pager = '<nav class="pager" aria-label="Previous and next">'
        pager += f'<a class="prev" href="{previous["slug"]}.html"><span>← Previous</span>{html.escape(previous["title"])}</a>' if previous else "<span></span>"
        pager += f'<a class="next" href="{following["slug"]}.html"><span>Next →</span>{html.escape(following["title"])}</a>' if following else ""
        pager += "</nav>"
        side = sidebar.replace("{ROOTH}", "").replace(f'data-slug="{slug}"', f'data-slug="{slug}" aria-current="page"')
        main = (f'<div class="docs"><aside class="sidebar" aria-label="Help">{side}</aside>'
                f'<main class="doc" id="content"><details class="mobile-nav"><summary>Browse the help</summary><div class="sidebar-body sidebar" style="display:block;position:static;height:auto;width:auto">{side}</div></details>'
                f'<div class="crumbs"><a href="index.html">Help</a> / {html.escape(group)}</div>'
                f'<article class="prose">{body}</article><hr class="rule">{pager}'
                f'<p class="contrib">Something wrong or missing? This help is written from the app\'s own code and is in the '
                f'<a href="{REPO}/tree/main/site/help/{slug}.md">repository</a>; corrections are welcome.</p></main></div>')
        jsonld = {"@context": "https://schema.org", "@graph": [
            {"@type": "TechArticle", "headline": page["title"], "description": page["summary"],
             "url": f"{BASE_URL}help/{slug}.html", "inLanguage": "en",
             "about": {"@type": "SoftwareApplication", "name": "Glass Power Tools",
                       "operatingSystem": "macOS, iOS, iPadOS, visionOS", "applicationCategory": "DeveloperApplication"}},
            {"@type": "BreadcrumbList", "itemListElement": [
                {"@type": "ListItem", "position": 1, "name": "Help", "item": f"{BASE_URL}help/"},
                {"@type": "ListItem", "position": 2, "name": page["title"], "item": f"{BASE_URL}help/{slug}.html"}]}]}
        render(layout, f"help/{slug}.html", title=f'{page["title"]} · Glass Power Tools Help',
               description=page["summary"], body=main, og_type="article", jsonld=jsonld)

    hub = ['<div class="docs"><aside class="sidebar" aria-label="Help">' + sidebar.replace("{ROOTH}", "") + "</aside>",
           '<main class="doc prose" id="content"><h1>Help</h1><p class="doc-summary">How to use Glass Power Tools on Vision Pro, Mac, iPad and iPhone. '
           'Press <kbd>⌘K</kbd> or <kbd>/</kbd> to search every page.</p>']
    for group in registry["groups"]:
        hub.append(f'<div class="hub-group"><h2>{html.escape(group["name"])}</h2><div class="grid">')
        for p in group["pages"]:
            hub.append(f'<a class="card" href="{p["slug"]}.html"><h3>{html.escape(p["title"])}</h3><p>{html.escape(p["summary"])}</p></a>')
        hub.append("</div></div>")
    hub.append("</main></div>")
    render(layout, "help/index.html", title="Help · Glass Power Tools",
           description="How to use Glass Power Tools: the library of your machines, the terminal, databases, remote desktops and the editor.",
           body="".join(hub))
    (OUT / "help" / "search-index.json").write_text(json.dumps(index, ensure_ascii=False))
    return pages


def check_links():
    """Every internal href resolves to a built file, and every #anchor to an id in it."""
    ids = {}
    for page in OUT.rglob("*.html"):
        ids[page] = set(re.findall(r'id="([^"]+)"', page.read_text()))
    for page in OUT.rglob("*.html"):
        for href in re.findall(r'href="([^"]+)"', page.read_text()):
            if re.match(r"[a-z]+:|//", href) or href.startswith("mailto:"):
                continue
            target, _, anchor = href.partition("#")
            path = (page.parent / target).resolve() if target else page
            if target.endswith("/"):
                path = path / "index.html"
            if not path.exists():
                fail(f"{page.relative_to(OUT)}: link to {href} does not resolve")
            elif anchor and path.suffix == ".html" and anchor not in ids.get(path, set()):
                fail(f"{page.relative_to(OUT)}: anchor #{anchor} not found in {target or 'the same page'}")


def check_addresses():
    for page in OUT.rglob("*.html"):
        text = plain(page.read_text())
        for address in re.findall(r"(?<![\d.])(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})(?![\d.])", text):
            if not address.startswith(DOCUMENTATION_RANGES):
                fail(f"{page.relative_to(OUT)}: address {address} is outside the documentation ranges")


def main():
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir()
    shutil.copytree(SITE / "static", OUT / "static")
    layout = (SITE / "layout.html").read_text()

    outputs = []
    for fragment in sorted((SITE / "pages").glob("*.html")):
        meta, body = front_matter(fragment.read_text())
        output = fragment.name
        title = meta.get("title", "Glass Power Tools")
        jsonld = None
        if output == "index.html":
            jsonld = {"@context": "https://schema.org", "@type": "SoftwareApplication", "name": "Glass Power Tools",
                      "operatingSystem": "macOS, iOS, iPadOS, visionOS", "applicationCategory": "DeveloperApplication",
                      "description": meta.get("description", ""), "url": BASE_URL, "license": "https://www.gnu.org/licenses/gpl-3.0.html"}
        render(layout, output, title=title, description=meta.get("description", ""), body=body, jsonld=jsonld)
        outputs.append((output, title, meta.get("description", "")))
    for source, (output, title, description) in MARKDOWN.items():
        body = pandoc((ROOT / source).read_text())
        body = re.sub(r'href="(?!https?:|#|mailto:)([^"]+)"', lambda m: f'href="{REPO}/blob/main/{m.group(1)}"', body)
        render(layout, output, title=f"{title} · Glass Power Tools", description=description,
               body=f'<main class="page doc prose" id="content" style="max-width:760px">{body}</main>')
        outputs.append((output, title, description))

    registry = json.loads((SITE / "help" / "registry.json").read_text())
    help_pages = build_help(layout, registry)

    # The Mac update feed (D38) is served from the site root; the release script writes it.
    feed = SITE / "static" / "appcast.xml"
    if feed.exists():
        shutil.copyfile(feed, OUT / "appcast.xml")

    urls = [BASE_URL] + [BASE_URL + o for o, _, _ in outputs if o != "index.html"] + [BASE_URL + "help/"] + \
           [f"{BASE_URL}help/{p['slug']}.html" for _, p in help_pages]
    today = date.today().isoformat()
    (OUT / "sitemap.xml").write_text('<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
                                     + "".join(f"  <url><loc>{u}</loc><lastmod>{today}</lastmod></url>\n" for u in urls) + "</urlset>\n")
    (OUT / "robots.txt").write_text(f"User-agent: *\nAllow: /\nSitemap: {BASE_URL}sitemap.xml\n")
    llms = ["# Glass Power Tools", "",
            "> One app for the machines you work on — SSH terminal, databases (MySQL, PostgreSQL, SQLite), remote desktops (RDP, VNC) and a code editor — built natively for Apple Vision Pro, Mac, iPad and iPhone. Free software under the GPLv3.",
            "", "## Pages", ""]
    llms += [f"- [{t}]({BASE_URL}{'' if o == 'index.html' else o}): {d}" for o, t, d in outputs]
    group = None
    for name, page in help_pages:
        if name != group:
            llms += ["", f"## Help: {name}", ""]
            group = name
        llms.append(f"- [{page['title']}]({BASE_URL}help/{page['slug']}.html): {page['summary']}")
    (OUT / "llms.txt").write_text("\n".join(llms) + "\n")

    check_links()
    check_addresses()
    if errors:
        print("build_site: the site was not built:", file=sys.stderr)
        for message in errors:
            print(f"  - {message}", file=sys.stderr)
        shutil.rmtree(OUT)
        sys.exit(1)
    print(f"build_site: {len(outputs)} pages, {len(help_pages)} help pages → {OUT.relative_to(ROOT)}/")


if __name__ == "__main__":
    main()
