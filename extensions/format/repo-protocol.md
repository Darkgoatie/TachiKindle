# TachiKindle Extension Repository Protocol v1

Defines what a "repo" is for TachiKindle: a plain HTTPS-hosted static
file tree (e.g. a `gh-pages` branch, same hosting model keiyoushi
uses) that the Kindle can browse and download from directly via curl.
No APKs, no Kotlin, no JVM anywhere in this pipeline -- every file in
a TachiKindle repo is already in the native `.tkext.json` format
described in `extensions/format/`.

## Repo layout (what you host)

```
<repo-root>/
  index.json            <- catalog, see schema below
  sources/
    en/foo.tkext.json
    en/bar.tkext.json
    ...
```

`index.json`:
```json
{
  "repo_name": "My TachiKindle Repo",
  "repo_format_version": 1,
  "extensions": [
    {
      "id": "en.foo",
      "name": "Foo Scans",
      "lang": "en",
      "version_code": 1,
      "content_warning": "SAFE",
      "path": "sources/en/foo.tkext.json"
    }
  ]
}
```

- `path` is relative to the repo root URL the user entered.
- `content_warning` mirrors the field already in `.tkext.json` files
  (SAFE/MIXED/NSFW) so the Kindle can filter without downloading
  every extension file first.
- Client behavior: fetch `<repo_url>/index.json`, list `extensions[]`
  in a screen, on select fetch `<repo_url>/<path>`, validate against
  `extensions/format/schema-1.0.json`'s shape (checked in C by
  presence of required keys, not full JSON Schema), then copy into
  `/mnt/us/tachikindle/extensions/<id>.tkext.json`.

## Client requirements (on-device)

- Uses the system `curl` already present on Kindle firmware
  (confirmed at `/usr/bin/curl`, linked against `/usr/lib/libssl.so`)
  via `popen`/`fork+exec` -- no TLS stack written in TachiKindle
  itself. This is why a repo MUST be plain HTTPS static files: no
  auth, no GraphQL, nothing curl-with-a-URL can't fetch.
- User enters a repo root URL once (e.g.
  `https://halit.github.io/tachikindle-repo`) via an on-device text
  entry screen; it's saved to
  `/mnt/us/tachikindle/repos.json` (list of `{name, url}`).
- Repo list screen -> extension list screen (per repo) -> confirm
  download screen. Downloaded files land in
  `/mnt/us/tachikindle/extensions/`. The library/reader picks these
  up as sources at next app start (no hot-reload required for v1).

## Why not keiyoushi's real repos directly

keiyoushi's `index.json` points at compiled Kotlin/JVM `.apk` files.
Fetching one changes nothing -- there's still no JVM on a Kindle to
run it. Real keiyoushi sources have to go through the manual
`manga-extension-porting` skill and get re-hosted as `.tkext.json` in
a repo following *this* protocol before a Kindle can use them. This
document defines the repo format for hosting already-ported sources,
not for reading keiyoushi's repo directly.
