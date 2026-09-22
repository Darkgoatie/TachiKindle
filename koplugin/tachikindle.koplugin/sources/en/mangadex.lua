--[[--
MangaDex source_script.

Unlike every other bundled source, MangaDex is a real public JSON REST
API (https://api.mangadex.org) -- there is no HTML to select from, so
this file does NOT use tachikindlesource.lua's htmlparser-based
*WithSelectors helpers at all. It implements the four source_script
hooks (fetch_manga_list/fetch_manga_details/fetch_chapter_list/
fetch_page_list) directly against MangaDex's JSON endpoints, following
the same "require('json'), pcall around JSON.decode, real nil+err on
failure" pattern established by sources/en/batcave's adapter.

URL-encoding scheme used by this source (documented since MangaDex's
schema.json endpoints are not run through tachikindlesource.lua's
generic fillTemplate/resolveUrl -- this script builds its own URLs):
  manga_url   = base_url .. "/title/"   .. <mangadex manga UUID>
  chapter_url = base_url .. "/chapter/" .. <mangadex chapter UUID>
These mirror mangadex.org's own real web URL scheme and are only ever
used here as opaque identifier strings; the trailing UUID is parsed
back out locally before making the real API call.

Language handling: chapter feed is filtered to translatedLanguage=en
only (this is an "en" lang source per its .tkext.json id "en.mangadex";
a separate source file per UI language would be needed to cover other
scanlation languages, matching how this repo splits sources by lang
directory rather than exposing a language filter within one source).

Image quality: fetch_page_list uses the full-resolution "data" array
from /at-home/server/{chapterId}, not the lower-res "dataSaver" array,
since KOReader's own reader can downscale for e-ink displays and
readers on a metered/slow connection can rely on TachiKindle's normal
chapter-level caching rather than a permanently degraded image set.

All live JSON shapes below were verified against real requests to
https://api.mangadex.org on 2026-09-22 (see mangadex.tkext.json's
"verification" block) -- nothing here is a guessed response shape.
--]]--

local JSON = require("json")
local socket_url = require("socket.url")

local Source = {}

local API_BASE = "https://api.mangadex.org"
local COVER_BASE = "https://uploads.mangadex.org/covers"
local PAGE_SIZE = 20

-- MangaDex asks integrators to send a real, descriptive User-Agent
-- (generic/empty ones are rate-limited or blocked). The .tkext.json's
-- client.user_agent carries the same string for documentation, but
-- this script sets its own headers directly since it calls
-- source:fetch() with an explicit options.headers override rather
-- than relying on tachikindlesource.lua's default Accept header
-- (which is HTML-shaped, not JSON-shaped).
local HEADERS = {
    ["Accept"] = "application/json",
    ["User-Agent"] = "TachiKindle/1.0 (KOReader manga plugin) MangaDexSource/1.0",
}

local function httpGet(source, path, params)
    local qs = {}
    for _, kv in ipairs(params or {}) do
        table.insert(qs, socket_url.escape(kv[1]) .. "=" .. socket_url.escape(kv[2]))
    end
    local url = API_BASE .. path
    if #qs > 0 then
        url = url .. "?" .. table.concat(qs, "&")
    end
    local body, err = source:fetch(url, { headers = HEADERS })
    if not body then return nil, "HTTP request failed: " .. tostring(err) end

    local ok, decoded = pcall(JSON.decode, body)
    if not ok or type(decoded) ~= "table" then
        return nil, "invalid JSON response from MangaDex"
    end
    if decoded.result ~= "ok" then
        local msg = "MangaDex API error"
        if type(decoded.errors) == "table" and decoded.errors[1] and decoded.errors[1].detail then
            msg = msg .. ": " .. tostring(decoded.errors[1].detail)
        end
        return nil, msg
    end
    return decoded
end

-- best available localized title: prefer en, else the first alt title
-- present, else the first title of any language, else "Unknown".
local function pickTitle(attrs)
    if not attrs then return "Unknown" end
    if attrs.title and attrs.title.en then return attrs.title.en end
    for _, alt in ipairs(attrs.altTitles or {}) do
        if alt.en then return alt.en end
    end
    if attrs.title then
        for _, v in pairs(attrs.title) do
            return v
        end
    end
    return "Unknown"
end

local function coverUrlFromRelationships(manga_id, relationships)
    for _, rel in ipairs(relationships or {}) do
        if rel.type == "cover_art" and rel.attributes and rel.attributes.fileName then
            return COVER_BASE .. "/" .. manga_id .. "/" .. rel.attributes.fileName
        end
    end
    return nil
end

local function mangaIdFromUrl(manga_url)
    return tostring(manga_url or ""):match("/title/([%w%-]+)")
end

local function chapterIdFromUrl(chapter_url)
    return tostring(chapter_url or ""):match("/chapter/([%w%-]+)")
end

-- endpoint_name: "popular" | "latest" | "search"
function Source.fetch_manga_list(source, endpoint_name, page, query)
    page = page or 1
    local offset = (page - 1) * PAGE_SIZE
    local params = {
        { "limit", tostring(PAGE_SIZE) },
        { "offset", tostring(offset) },
        { "includes[]", "cover_art" },
    }
    if endpoint_name == "popular" then
        table.insert(params, { "order[followedCount]", "desc" })
    elseif endpoint_name == "latest" then
        table.insert(params, { "order[latestUploadedChapter]", "desc" })
    elseif query and query ~= "" then
        table.insert(params, { "title", query })
    else
        -- empty search query: fall back to popular-style browsing
        table.insert(params, { "order[followedCount]", "desc" })
    end

    local decoded, err = httpGet(source, "/manga", params)
    if not decoded then return nil, err end
    if type(decoded.data) ~= "table" then
        return nil, "unexpected MangaDex response shape (missing data array)"
    end

    local list = {}
    for _, manga in ipairs(decoded.data) do
        table.insert(list, {
            title = pickTitle(manga.attributes),
            url = source.def.base_url .. "/title/" .. manga.id,
            cover = coverUrlFromRelationships(manga.id, manga.relationships),
        })
    end

    local total = tonumber(decoded.total) or 0
    local has_next = (offset + #list) < total
    return list, nil, has_next
end

function Source.fetch_manga_details(source, manga_url)
    local manga_id = mangaIdFromUrl(manga_url)
    if not manga_id then return nil, "could not parse MangaDex manga id from url: " .. tostring(manga_url) end

    local decoded, err = httpGet(source, "/manga/" .. manga_id, {
        { "includes[]", "cover_art" },
        { "includes[]", "author" },
        { "includes[]", "artist" },
    })
    if not decoded then return nil, err end
    if type(decoded.data) ~= "table" or type(decoded.data.attributes) ~= "table" then
        return nil, "unexpected MangaDex response shape (missing data.attributes)"
    end

    local manga = decoded.data
    local attrs = manga.attributes

    local genres = {}
    for _, tag in ipairs(attrs.tags or {}) do
        local name = tag.attributes and tag.attributes.name and tag.attributes.name.en
        if name then table.insert(genres, name) end
    end

    local author
    for _, rel in ipairs(manga.relationships or {}) do
        if rel.type == "author" and rel.attributes and rel.attributes.name then
            author = rel.attributes.name
            break
        end
    end

    local description
    if attrs.description then
        description = attrs.description.en
        if not description then
            for _, v in pairs(attrs.description) do
                description = v
                break
            end
        end
    end

    return {
        title = pickTitle(attrs),
        author = author,
        description = description,
        status = attrs.status,
        genres = genres,
        cover = coverUrlFromRelationships(manga.id, manga.relationships),
    }
end

function Source.fetch_chapter_list(source, manga_url)
    local manga_id = mangaIdFromUrl(manga_url)
    if not manga_id then return nil, "could not parse MangaDex manga id from url: " .. tostring(manga_url) end

    local chapters = {}
    local limit = 100
    local offset = 0
    local total = math.huge

    -- MangaDex paginates /feed at up to 500/request; we page in
    -- batches of 100 and stop once we've seen `total` items or hit a
    -- safety cap, to avoid unbounded requests against a manga with an
    -- enormous chapter count.
    local safety_pages = 20
    for _ = 1, safety_pages do
        if offset >= total then break end
        local decoded, err = httpGet(source, "/manga/" .. manga_id .. "/feed", {
            { "translatedLanguage[]", "en" },
            { "order[chapter]", "desc" },
            { "limit", tostring(limit) },
            { "offset", tostring(offset) },
        })
        if not decoded then return nil, err end
        if type(decoded.data) ~= "table" then
            return nil, "unexpected MangaDex response shape (missing feed data array)"
        end

        for _, ch in ipairs(decoded.data) do
            local attrs = ch.attributes or {}
            if not attrs.externalUrl and not attrs.isUnavailable then
                local number = attrs.chapter and ("Chapter " .. attrs.chapter) or "Chapter ?"
                local title = attrs.title and attrs.title ~= "" and (number .. ": " .. attrs.title) or number
                table.insert(chapters, {
                    title = title,
                    url = source.def.base_url .. "/chapter/" .. ch.id,
                    date = attrs.publishAt or attrs.readableAt,
                })
            end
        end

        total = tonumber(decoded.total) or #decoded.data
        offset = offset + limit
        if #decoded.data == 0 then break end
    end

    -- MangaDex's order[chapter]=desc sorts by chapter NUMBER, which is
    -- usually but not strictly the same as upload recency (e.g. a late
    -- special/omake chapter can be numbered lower than a main chapter
    -- uploaded earlier). We keep the site's own ordering rather than
    -- re-sorting by date to match this repo's stated convention of
    -- trusting the source's own ordering (see fetchChapterListWithSelectors's
    -- comment in tachikindlesource.lua).
    return chapters
end

function Source.fetch_page_list(source, chapter_url)
    local chapter_id = chapterIdFromUrl(chapter_url)
    if not chapter_id then return nil, "could not parse MangaDex chapter id from url: " .. tostring(chapter_url) end

    local decoded, err = httpGet(source, "/at-home/server/" .. chapter_id, {})
    if not decoded then return nil, err end
    if type(decoded.baseUrl) ~= "string" or type(decoded.chapter) ~= "table"
        or type(decoded.chapter.hash) ~= "string" or type(decoded.chapter.data) ~= "table" then
        return nil, "unexpected MangaDex response shape (missing baseUrl/chapter.hash/chapter.data)"
    end

    local pages = {}
    for _, filename in ipairs(decoded.chapter.data) do
        table.insert(pages, decoded.baseUrl .. "/data/" .. decoded.chapter.hash .. "/" .. filename)
    end
    if #pages == 0 then
        return nil, "MangaDex returned no page images for this chapter"
    end
    return pages
end

return Source
