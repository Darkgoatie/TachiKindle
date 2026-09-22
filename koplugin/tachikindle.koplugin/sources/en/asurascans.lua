--[===[
AsuraScans source_script.

Asura Scans is a real JSON REST API (https://api.asurascans.com/api) for
popular/latest/search/manga-details, PLUS an Astro/SSR HTML frontend
(https://asurascans.com) that embeds chapter-list and page-list data as
a JSON blob inside an <astro-island props="..."> attribute rather than
plain <a>/<img> tags. There is no CSS-selector-only path through this
site (see asurascans.tkext.json's "_notes" for the full rationale), so
this file, like sources/en/mangadex.lua, implements all four
source_script hooks directly instead of using tachikindlesource.lua's
htmlparser-based *WithSelectors helpers.

Astro props wire format: the raw HTML attribute value is HTML-entity
encoded JSON of the shape [type_tag, value] recursively (Astro's
"serialized props" scheme) -- e.g. {"chapters":[1,[[0,{"id":[0,7]}]]]}
means chapters is an array whose real value is [{"id": 7}]. This
mirrors upstream AsuraScans.kt's JsonElement.unwrapAstro(): a 2-element
JsonArray whose first element is a JsonPrimitive is unwrapped to its
second element; anything else recurses structurally. See
asurascans.tkext.json's "verification" block for the real live props
strings this was derived from (2026-09-22).

manga_url / chapter_url encoding (mirrors upstream's own slug-remapping
indirection, since the real public URL suffix is an unpredictable
API-assigned 8-hex-digit string only discoverable via the API):
  manga_url   = base_url .. "/series/" .. <api slug>
  chapter_url = base_url .. "/series/" .. <api slug> .. "/chapter/" .. <number>
These are opaque identifiers; fetch_chapter_list/fetch_page_list parse
the slug/number back out and resolve the REAL page path
(/comics/<slug>-<suffix>[/chapter/<number>]) via the API/HTML at
request time, not by string concatenation alone.
--]===]

local JSON = require("json")

local Source = {}

local API_BASE = "https://api.asurascans.com/api"
local HEADERS = {
    ["Accept"] = "application/json",
    ["User-Agent"] = "Mozilla/5.0 (Linux; Android 10) TachiKindle/1.0",
}
local HTML_HEADERS = {
    ["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    ["User-Agent"] = "Mozilla/5.0 (Linux; Android 10) TachiKindle/1.0",
    ["Referer"] = "https://asurascans.com/",
}
local PAGE_SIZE = 20

local function apiGet(source, path)
    local body, err = source:fetch(API_BASE .. path, { headers = HEADERS })
    if not body then return nil, "HTTP request failed: " .. tostring(err) end
    local ok, decoded = pcall(JSON.decode, body)
    if not ok or type(decoded) ~= "table" then
        return nil, "invalid JSON response from Asura Scans API"
    end
    return decoded
end

-- Recursively unwrap Astro's [type_tag, value] serialized-props
-- encoding. A 2-element array whose first element is a plain
-- string/number/boolean/nil (never itself a table) is a tagged
-- primitive/value wrapper -> unwrap to element 2. Anything else
-- (including a real 2-element array of two tables/tagged values) is
-- walked structurally so nested arrays/objects also get unwrapped.
local function unwrapAstro(v)
    if type(v) ~= "table" then return v end
    local n = 0
    for _ in pairs(v) do n = n + 1 end
    if n == 2 and v[1] ~= nil and v[2] ~= nil and type(v[1]) ~= "table" then
        return unwrapAstro(v[2])
    end
    local out = {}
    local is_array = (#v > 0)
    for k, val in pairs(v) do
        out[k] = unwrapAstro(val)
    end
    return out
end

-- Extract and JSON-decode an Astro island's props="..." attribute
-- whose raw value contains the given key (e.g. "chapters" or "pages"),
-- then run it through unwrapAstro(). HTML entities (&quot;) are
-- decoded first since the attribute is serialized as HTML.
local function extractAstroProp(html, key)
    for props in html:gmatch('props="(.-)"') do
        if props:find(key, 1, true) then
            local decoded_html = props:gsub("&quot;", '"'):gsub("&amp;", "&"):gsub("&#39;", "'")
            local ok, obj = pcall(JSON.decode, decoded_html)
            if ok and type(obj) == "table" then
                return unwrapAstro(obj)
            end
        end
    end
    return nil, "could not find/parse Astro prop '" .. key .. "' in page"
end

local function mangaSlugFromUrl(manga_url)
    return tostring(manga_url or ""):match("/series/([^/]+)")
end

local function chapterInfoFromUrl(chapter_url)
    local slug, number = tostring(chapter_url or ""):match("/series/([^/]+)/chapter/([^/]+)")
    return slug, number
end

function Source.fetch_manga_list(source, endpoint_name, page, query)
    page = page or 1
    local offset = (page - 1) * PAGE_SIZE
    local path = string.format("/series?offset=%d&limit=%d", offset, PAGE_SIZE)
    if endpoint_name == "latest" then
        path = path .. "&sort=latest"
    elseif query and query ~= "" then
        path = path .. "&search=" .. require("socket.url").escape(query)
    end

    local decoded, err = apiGet(source, path)
    if not decoded then return nil, err end
    if type(decoded.data) ~= "table" then
        return nil, "unexpected Asura Scans response shape (missing data array)"
    end

    local list = {}
    for _, manga in ipairs(decoded.data) do
        table.insert(list, {
            title = manga.title,
            url = source.def.base_url .. "/series/" .. tostring(manga.slug),
            cover = manga.cover,
        })
    end

    local has_next = false
    if type(decoded.meta) == "table" then
        has_next = decoded.meta.has_more == true
    end
    return list, nil, has_next
end

function Source.fetch_manga_details(source, manga_url)
    local slug = mangaSlugFromUrl(manga_url)
    if not slug then return nil, "could not parse Asura Scans manga slug from url: " .. tostring(manga_url) end

    local decoded, err = apiGet(source, "/series/" .. slug)
    if not decoded then return nil, err end

    local series = decoded.series
    if type(series) ~= "table" then
        -- some responses may return the series object unwrapped at top level
        series = decoded
    end
    if type(series) ~= "table" or not series.title then
        return nil, "unexpected Asura Scans response shape (missing series.title)"
    end

    local genres = {}
    for _, g in ipairs(series.genres or {}) do
        if type(g) == "table" and g.name then table.insert(genres, g.name) end
    end

    local status_map = {
        ongoing = "Ongoing", completed = "Completed",
        hiatus = "On Hiatus", dropped = "Dropped", axed = "Cancelled",
    }

    return {
        title = series.title,
        author = series.author,
        description = series.description and (series.description:gsub("<[^>]+>", "")) or nil,
        status = status_map[tostring(series.status or ""):lower()] or series.status,
        genres = genres,
        cover = series.cover,
    }
end

-- Chapter list lives inside an Astro island's props on the real HTML
-- comic page, not the JSON API -- fetch the real /comics/<slug>...
-- page directly using the manga_url's slug (the API call is needed
-- first only to resolve the real public_url path segment, mirroring
-- upstream's slugMap indirection).
function Source.fetch_chapter_list(source, manga_url)
    local slug = mangaSlugFromUrl(manga_url)
    if not slug then return nil, "could not parse Asura Scans manga slug from url: " .. tostring(manga_url) end

    local decoded, err = apiGet(source, "/series/" .. slug)
    if not decoded then return nil, err end
    local series = decoded.series or decoded
    local public_url = series.public_url
    if type(public_url) ~= "string" or public_url == "" then
        return nil, "Asura Scans API did not return a public_url for slug " .. slug
    end

    local html, ferr = source:fetch(source.def.base_url .. public_url, { headers = HTML_HEADERS })
    if not html then return nil, "HTTP request failed: " .. tostring(ferr) end

    local chapters_obj, perr = extractAstroProp(html, "chapters")
    if not chapters_obj then return nil, perr end

    local list = chapters_obj.chapters
    if type(list) ~= "table" then
        return nil, "Asura Scans chapter page did not contain a chapters array"
    end

    local chapters = {}
    for _, ch in ipairs(list) do
        local number = ch.number
        local number_str = tostring(number or "?")
        if number_str:match("%.0$") then number_str = number_str:gsub("%.0$", "") end
        local title = (ch.is_locked and "\240\159\148\146 " or "") .. "Chapter " .. number_str
        if ch.title and ch.title ~= "" then title = title .. " - " .. ch.title end
        table.insert(chapters, {
            title = title,
            url = source.def.base_url .. "/series/" .. slug .. "/chapter/" .. number_str,
            date = ch.published_at,
        })
    end
    return chapters
end

-- Pages live inside the chapter reader page's Astro island props.
function Source.fetch_page_list(source, chapter_url)
    local slug, number = chapterInfoFromUrl(chapter_url)
    if not slug or not number then
        return nil, "could not parse Asura Scans slug/chapter number from url: " .. tostring(chapter_url)
    end

    local decoded, err = apiGet(source, "/series/" .. slug)
    if not decoded then return nil, err end
    local series = decoded.series or decoded
    local public_url = series.public_url
    if type(public_url) ~= "string" or public_url == "" then
        return nil, "Asura Scans API did not return a public_url for slug " .. slug
    end

    local html, ferr = source:fetch(source.def.base_url .. public_url .. "/chapter/" .. number, { headers = HTML_HEADERS })
    if not html then return nil, "HTTP request failed: " .. tostring(ferr) end

    local pages_obj, perr = extractAstroProp(html, "pages")
    if not pages_obj then return nil, perr end

    local list = pages_obj.pages
    if type(list) ~= "table" then
        return nil, "Asura Scans chapter page did not contain a pages array"
    end
    if #list == 0 then
        return nil, "this chapter has no unlocked pages (likely premium/locked content requiring an authenticated session, which this port does not support)"
    end

    local pages = {}
    local scrambled_seen = false
    for _, p in ipairs(list) do
        if type(p.tiles) == "table" and #p.tiles > 0 then
            scrambled_seen = true
        end
        table.insert(pages, p.url)
    end
    if scrambled_seen then
        require("logger").warn("asurascans: chapter " .. number .. " of " .. slug ..
            " contains tile-scrambled images; this Lua port does not de-scramble them (see tkext.json limitations)")
    end
    return pages
end

return Source
