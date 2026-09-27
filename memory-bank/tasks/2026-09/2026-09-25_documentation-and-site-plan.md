# Documentation and glasspowertools.com — plan, 2026-09-25

State **PLAN**, nothing built. Decisions: D38 (distribution), D39 (documentation and site). The user: *"four apps in one, a suite of Power Tools … The primary use
case though, is devs looking for a first class Apple Vision Pro experience across the suite."*

## Agreed shape (the user's, refined in conversation)

1. **The vision** first — one page saying what this is and why, Vision Pro first.
2. **An audit of every surface against the code**, fixing discrepancies along the way. The surface
   list is taken *from the code* (capabilities, scenes, library panels, settings pages, commands and
   the key table in `systemPatterns.md`) — rule 57. Each surface is written Vision Pro first, with
   Mac, iPad and iPhone differences marked, and each claim at its verified level (device, simulator,
   unverified). The output of the audit *is* the help.
3. **The sites:** a landing page (overview, the why) linking to one product page per capability, and
   a help centre.

## Models to follow

- **Help centre: Anomalous** (anomalous.bot/help): one registry drives the
  grouped sidebar, ⌘K search from a prebuilt index, per-page meta, schema.org JSON-LD
  (TechArticle/HowTo), the sitemap and `llms.txt`. Callouts, captioned figures, light and dark.
  Here: the same system as **static files** — a registry in the repo, pages as Markdown rendered by
  pandoc, the index and JSON-LD generated at build time, nothing loaded from elsewhere.
- **Site machinery and landing: AudioPaper** (the author's open-source Mac app): `site/layout.html`, page
  fragments with front matter, `scripts/build_site.py` → `_site/`, `PRIVACY.md`/`NETWORK.md` rendered
  from the repo so the site cannot disagree with it. Landing order: hero, what it looks like, how it
  works, what leaves your devices, what it asks of you, leaving, who made it, check it yourself,
  the handback line.
- **Copy: Bedrock** — `bedrock-brand-voice` writes the landing and product pages; `ask-bedrock`
  judges them. Help pages are plain instruction. A page claims only what the audit verified.

## Hosting (the user, 2026-09-25)

**glasspowertools.com**, owned by the user, self-hosted as a static site. The build produces
`_site/`; deploying it follows the user's private infrastructure runbook — **no machine names,
addresses or server details in this repository** (the user: *"Machine names in general, tokens, keys
etc. need to be left out. 'hosting facts' aren't public knowledge."*). Scripts are written for the
user and run by the user. The feed and HTML must be served uncached.

Suggested order: a placeholder page live early (proves DNS and the deploy end to end),
content behind it.

## Distribution and updates — D38

Mac: Developer ID + notarization + Sparkle, feed at `https://glasspowertools.com/appcast.xml` (the Mac
App Store needs App Sandbox, which this app cannot adopt). iPhone, iPad, Vision Pro: TestFlight, then
the App Store. The landing page therefore has two paths: *Download for Mac* and *iPhone, iPad and
Vision Pro* (TestFlight at first). Pre-release checklist in D38.

## Open

- Fixing during the audit: small discrepancies fixed as found, behaviour and design brought to the
  user? (proposed)
- Which registrar holds glasspowertools.com?
