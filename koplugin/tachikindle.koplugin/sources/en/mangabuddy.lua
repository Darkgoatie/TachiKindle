-- MangaBuddy source_script.
--
-- REAL SITE QUIRK (confirmed live 2026-09-22): mangabuddy.com no longer
-- serves manga at all -- it 301-redirects every path (verified: "/" ->
-- https://comizy.io/, "/popular" -> https://comizy.io/popular) to a
-- rebrand at comizy.io ("Comizy"), same underlying Next.js app. This
-- descriptor targets the live comizy.io site since mangabuddy.com itself
-- returns nothing but redirects.
--
-- REAL SITE QUIRK: this is NOT a server-rendered HTML site with CSS-class
-- list items like Madara/WeebCentral. Two different real mechanisms were
-- confirmed live:
--   1) Popular/latest/search results come from a genuine separate JSON API
--      host, https://api.comizy.io/titles/search?sort=...&page=...&limit=...
--      -- confirmed live: real JSON body with items[]/pagination{has_next}.
--   2) Manga details, the chapter list, and chapter pages are NOT in that
--      API -- they're embedded as a Next.js <script id="__NEXT_DATA__"
--      type="application/json"> blob on each HTML page (props.pageProps.
--      initialManga / initialChapter). The real chapter list itself is
--      fetched from yet another separate ajax endpoint,
--      https://api.comizy.io/titles/{id}/chapters?cv={cv}, where {id} and
--      {cv} are only obtainable by first parsing that __NEXT_DATA__ blob
--      off the manga details page -- confirmed live end-to-end for
--      "Nice to See You" (bNYW81j8): details page -> id/cv extracted ->
--      chapters endpoint returned real 29-chapter list.
-- Selectors-only passthrough cannot express any of this (no CSS selector
-- can reach a same-page separate JSON API call, or a two-hop id+cv fetch),
-- so this source implements custom logic instead of reusing
-- fetchMangaListWithSelectors/fetchChapterListWithSelectors/etc.
local JSON = require("json")

local M = {}

local API_HOST = "https://api.comizy.io"

local function absolute(base_url, path)
    if not path or path == "" then return nil end
    if path:match("^https?://") then return path end
    if path:match("^/") then return base_url .. path end
    return base_url .. "/" .. path
end

-- Pulls the embedded Next.js data blob out of a rendered page. Real pages
-- (confirmed live) look like:
--   <script id="__NEXT_DATA__" type="application/json">{...}</script>
local function extractNextData(body)
    if type(body) ~= "string" then return nil, "empty body" end
    local blob = body:match('__NEXT_DATA__"%s*type="application/json">(.-)</script>')
    if not blob then
        return nil, "could not find __NEXT_DATA__ blob (site layout may have changed, or a bot wall was served)"
    end
    local ok, decoded = pcall(JSON.decode, blob)
    if not ok or type(decoded) ~= "table" then
        return nil, "invalid JSON in __NEXT_DATA__ blob"
    end
    return decoded
end

local function joinNames(list)
    if type(list) ~= "table" then return nil end
    local names = {}
    for _, entry in ipairs(list) do
        if type(entry) == "table" and entry.name then
            table.insert(names, entry.name)
        end
    end
    if #names == 0 then return nil end
    return table.concat(names, ", ")
end

-- Popular/latest/search -> https://api.comizy.io/titles/search, a real
-- separate JSON API (confirmed live, NOT HTML). limit=24 mirrors the
-- real upstream Kotlin extension's DEFAULT_PAGE_LIMIT.
function M.fetch_manga_list(source, endpoint_name, page, query)
    page = page or 1
    local base_url = source.def.base_url
    local url
    if endpoint_name == "popular" then
        url = API_HOST .. "/titles/search?sort=popular&window=week&page=" .. tostring(page) .. "&limit=24"
    elseif endpoint_name == "latest" then
        url = API_HOST .. "/titles/search?sort=latest&page=" .. tostring(page) .. "&limit=24"
    elseif endpoint_name == "search" then
        url = API_HOST .. "/titles/search?page=" .. tostring(page) .. "&limit=24"
        if query and query ~= "" then
            local socket_url = require("socket.url")
            url = url .. "&q=" .. socket_url.escape(query)
        end
    else
        return nil, "unsupported endpoint: " .. tostring(endpoint_name)
    end

    local body, err = source:fetch(url)
    if not body then return nil, err end
    local ok, decoded = pcall(JSON.decode, body)
    if not ok or type(decoded) ~= "table" or type(decoded.data) ~= "table" then
        return nil, "invalid JSON from MangaBuddy/Comizy search API"
    end

    local list = {}
    for _, item in ipairs(decoded.data.items or {}) do
        table.insert(list, {
            title = item.name,
            url = absolute(base_url, item.url),
            cover = item.cover,
        })
    end
    local has_next = decoded.data.pagination and decoded.data.pagination.has_next or false
    return list, nil, has_next
end

-- Manga details: parsed from the __NEXT_DATA__ blob on the manga's own
-- HTML page (props.pageProps.initialManga) -- confirmed live, real field
-- names (name/summary/status/genres/authors/cover).
function M.fetch_manga_details(source, manga_url)
    local body, err = source:fetch(manga_url)
    if not body then return nil, err end
    local next_data, nerr = extractNextData(body)
    if not next_data then return nil, nerr end

    local manga = next_data.props and next_data.props.pageProps and next_data.props.pageProps.initialManga
    if not manga then return nil, "no initialManga in page data" end

    local genres = {}
    for _, g in ipairs(manga.genres or {}) do
        if type(g) == "table" and g.name then table.insert(genres, g.name) end
    end

    return {
        title = manga.name,
        author = joinNames(manga.authors),
        description = manga.summary,
        status = manga.status,
        genres = genres,
        cover = manga.cover,
    }
end

-- Chapter list: REAL SITE QUIRK -- not on the details page itself. The
-- details page's __NEXT_DATA__ only carries a few "latestChapters"; the
-- full chapter list is a separate ajax endpoint,
-- https://api.comizy.io/titles/{id}/chapters?cv={cv}, where id/cv are the
-- manga's internal API id and a cache-version timestamp, both only found
-- by first parsing the details page's __NEXT_DATA__ blob. Confirmed live:
-- "Nice to See You" (id=bNYW81j8) returned all 29 real chapters this way.
function M.fetch_chapter_list(source, manga_url)
    local base_url = source.def.base_url
    local body, err = source:fetch(manga_url)
    if not body then return nil, err end
    local next_data, nerr = extractNextData(body)
    if not next_data then return nil, nerr end

    local manga = next_data.props and next_data.props.pageProps and next_data.props.pageProps.initialManga
    if not manga or not manga.id then
        return nil, "could not find manga id for chapter list lookup"
    end

    local cv = manga.cv or os.time()
    local chapters_url = API_HOST .. "/titles/" .. tostring(manga.id) .. "/chapters?cv=" .. tostring(cv)
    local chapters_body, cerr = source:fetch(chapters_url)
    if not chapters_body then return nil, cerr end

    local ok, decoded = pcall(JSON.decode, chapters_body)
    if not ok or type(decoded) ~= "table" or type(decoded.data) ~= "table" then
        return nil, "invalid JSON from MangaBuddy/Comizy chapters API"
    end

    local list = {}
    -- Real API already returns chapters newest-first (confirmed live);
    -- no re-sort needed, matching this project's general chapter-list
    -- convention of trusting the site's own order.
    for _, chapter in ipairs(decoded.data.chapters or {}) do
        table.insert(list, {
            title = chapter.name,
            url = absolute(base_url, chapter.url),
            date = chapter.updated_at,
        })
    end
    return list
end

-- Page list: parsed from the __NEXT_DATA__ blob on the chapter's own HTML
-- page (props.pageProps.initialChapter.pages[].url) -- confirmed live,
-- real per-page CDN URLs (x1.cmzcdn.org.../e/....webp style).
function M.fetch_page_list(source, chapter_url)
    local body, err = source:fetch(chapter_url)
    if not body then return nil, err end
    local next_data, nerr = extractNextData(body)
    if not next_data then return nil, nerr end

    local chapter = next_data.props and next_data.props.pageProps and next_data.props.pageProps.initialChapter
    if not chapter or type(chapter.pages) ~= "table" then
        return nil, "no initialChapter.pages in page data"
    end

    local pages = {}
    for _, p in ipairs(chapter.pages) do
        if type(p) == "table" and p.url then
            table.insert(pages, p.url)
        end
    end
    if #pages == 0 then return nil, "no page images found" end
    return pages
end

return M
