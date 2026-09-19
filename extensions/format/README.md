# TachiKindle Extension Format v1.0

A declarative JSON format for manga/comic scraper "extensions", designed
as a C-portable equivalent of keiyoushi/extensions-source's Kotlin
`HttpSource`/`ParsedHttpSource` model. One `.tkext.json` file = one
source (mirrors one keiyoushi `src/<lang>/<name>/` module).

## Why this exists

keiyoushi extensions are compiled Kotlin/JVM classes -- see
`../../TachiKindle` root README and skill `manga-extension-porting` for
the full reasoning. They cannot run on a Kindle's ARM binary (no JVM,
no Android compat shim, ~30MB usable RAM). This format captures the
*logic* of a source -- which URLs to hit, which CSS selectors map to
which fields -- as data, interpreted by a small C runtime instead of
executed as bytecode.

## Files

- `schema-1.0.json` -- the JSON Schema every extension file must validate against.
- `example.tkext.json` -- a worked example modeled on the real Madara theme
  (WordPress manga CMS covering ~200+ keiyoushi sources), showing every
  section of the format populated with realistic values.

## Status

Format defined and validated against real keiyoushi source code
(CONTRIBUTING.md interfaces + lib-multisrc/madara/Madara.kt, pulled
2026-09-19). The C runtime that loads and executes these files
(HTML parser, CSS-subset matcher, template substitution, HTTP client
glue) is separate, unbuilt work -- tracked as TachiKindle Phase 8.
This directory is the format spec only; do not assume a working
interpreter exists yet.

## Generating a new extension

Use skill `manga-extension-porting` to translate a keiyoushi Kotlin
source into a `.tkext.json` file by hand-mapping its selectors/URLs.
