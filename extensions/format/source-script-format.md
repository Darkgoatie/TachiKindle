# Source script format (v1)

Each extension must declare:

  "source_script": "sources/<lang>/<source_name>"

The value must match the extension id:
- id `en.weebcentral` -> `sources/en/weebcentral`
- id `en.readallcomics` -> `sources/en/readallcomics`

Security rule:
- Runtime only loads bundled modules with canonical names.
- Arbitrary paths/module names are rejected.

## Export contract

The module must return a Lua table. Function names can be snake_case or camelCase.

Recommended exports:
- fetch_manga_list(source, endpoint_name, page, query)
- fetch_manga_details(source, manga_url)
- fetch_chapter_list(source, manga_url)
- fetch_page_list(source, chapter_url)

Alias support:
- fetchMangaList
- fetchMangaDetails
- fetchChapterList
- fetchPageList

Arguments:
- `source` is `TachiKindleSource` runtime instance.
- Use runtime helpers when possible:
  - source:resolveUrl(endpoint_name, vars)
  - source:fetch(url[, options])
  - source:fetchMangaListWithSelectors(...)
  - source:fetchMangaDetailsWithSelectors(...)
  - source:fetchChapterListWithSelectors(...)
  - source:fetchPageListWithSelectors(...)

Return values:
- fetch_manga_list: `list, err, has_next`
- fetch_manga_details: `details, err`
- fetch_chapter_list: `chapters, err`
- fetch_page_list: `pages, err`

If a script omits one function:
- Runtime falls back to legacy adapter (if present), then selector-based parser.

## Minimal skeleton

local Source = {}

function Source.fetch_manga_list(source, endpoint_name, page, query)
    return source:fetchMangaListWithSelectors(endpoint_name, page, query)
end

function Source.fetch_manga_details(source, manga_url)
    return source:fetchMangaDetailsWithSelectors(manga_url)
end

function Source.fetch_chapter_list(source, manga_url)
    return source:fetchChapterListWithSelectors(manga_url)
end

function Source.fetch_page_list(source, chapter_url)
    return source:fetchPageListWithSelectors(chapter_url)
end

return Source
