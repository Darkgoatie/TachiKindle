--[[--
Comick source_script.

Ported from keiyoushi/extensions-source's Kotlin "Comick (Unoriginal)"
extension (src/all/comicklive, class eu.kanade.tachiyomi.extension.all
.comicklive.Comick : KeiSource()), targeting a single mirror
(https://comick.live) since TachiKindle's extension format has no
multi-mirror concept.

Comick is a hybrid: manga list / latest / chapter-list are a real JSON
REST API, but manga details and page images live as JSON embedded
inside a <script id="comic-data"|"sv-data"> tag on real HTML pages --
there is no separate JSON API for those two. This script therefore:
  * uses source:fetch() + JSON.decode directly for pure-JSON endpoints
    (mirroring sources/en/mangadex.lua's pattern), and
  * for manga_details/page_list, fetches the HTML page as text and
    regex-extracts the JSON blob out of the relevant <script> tag
    before JSON-decoding it (there is no HTML DOM parsing here at all,
    so tachikindlesource.lua's htmlparser-based *WithSelectors helpers
    are not used for this either).

URL scheme (this source builds its own URLs, not run through
tachikindlesource.lua's generic fillTemplate/resolveUrl, same as
mangadex.lua):
  manga_url   = base_url .. "/comic/" .. <slug>
                (this IS the real details page URL, unlike MangaDex's
                opaque-UUID scheme -- fetched directly for details)
  chapter_url = base_url .. "/comic/" .. <slug> .. "/" .. <hid> ..
                "-chapter-" .. <chap> .. "-" .. <lang>
                (this IS the real chapter reader page URL)

Language handling: chapter-list is requested with ?lang=en only,
matching this repo's "en" source directory convention (id "en.comick"),
same rationale as mangadex.lua.

All live JSON/HTML shapes below were verified against real requests to
https://comick.live on 2026-09-22 (see comick.tkext.json's
"verification" block). The /api/search endpoint could not be verified
live (returned a Cloudflare JS challenge in every attempt) -- its query
parameters are taken from the real, current upstream Kotlin source but
its response shape is *assumed* identical to /api/comics/top's, and is
explicitly flagged as such below.
--]]--

local JSON = require("json")
local socket_url = require("socket.url")

local Source = {}

local API_BASE = "https://comick.live"
local PAGE_SIZE = 60

local HEADERS = {
    ["Accept"] = "application/json",
    ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Safari/537.36 TachiKindle/1.0 ComickSource/1.0",
}

local HTML_HEADERS = {
    ["Accept"] = "text/html,application/xhtml+xml",
    ["User-Agent"] = HEADERS["User-Agent"],
}

local function httpGetJson(source, path, params)
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
        return nil, "invalid JSON response from Comick"
    end
    return decoded
end

-- Fetches a real HTML page and extracts+decodes the JSON blob embedded
-- inside <script id="script_id">...</script>. Comick's real markup
-- (verified live) uses a plain, non-self-closing <script id="..."> tag
-- with the JSON as its literal text content -- no JS wrapper assignment.
local function fetchEmbeddedJson(source, url, script_id_pattern, script_id_name)
    local body, err = source:fetch(url, { headers = HTML_HEADERS })
    if not body then return nil, "HTTP request failed: " .. tostring(err) end

    local blob = body:match('<script%s+id=["\']' .. script_id_pattern .. '["\'][^>]*>(.-)</script>')
    if not blob then
        return nil, "could not find #" .. script_id_name .. " script tag in Comick page: " .. tostring(url)
    end

    local ok, decoded = pcall(JSON.decode, blob)
    if not ok or type(decoded) ~= "table" then
        return nil, "invalid embedded JSON in #" .. script_id_name .. " on Comick page: " .. tostring(url)
    end
    return decoded
end

local function slugFromMangaUrl(manga_url)
    return tostring(manga_url or ""):match("/comic/([%w%-]+)$")
end

-- chapter_url = base_url/comic/<slug>/<hid>-chapter-<chap>-<lang>
-- We only need to fetch it as-is (it's a real page URL); no parsing
-- back to slug/hid is required since fetch_page_list just re-fetches
-- the same URL.

local function mapBrowseComic(comic)
    return {
        title = comic.title,
        url = API_BASE .. "/comic/" .. tostring(comic.slug),
        cover = comic.default_thumbnail,
    }
end

-- endpoint_name: "popular" | "latest" | "search"
function Source.fetch_manga_list(source, endpoint_name, page, query)
    page = page or 1

    if endpoint_name == "latest" then
        local decoded, err = httpGetJson(source, "/api/chapters/latest", {
            { "order", "new" },
            { "page", tostring(page) },
        })
        if not decoded then return nil, err end
        if type(decoded.data) ~= "table" then
            return nil, "unexpected Comick response shape (missing data array)"
        end
        local list = {}
        for _, comic in ipairs(decoded.data) do
            table.insert(list, mapBrowseComic(comic))
        end
        -- Comick's real /api/chapters/latest is cursor-paginated, not
        -- page-numbered (see upstream Kotlin's `cursor` field); this
        -- schema only supports numeric {page}, so we conservatively
        -- report has_next as "there were results" rather than trying
        -- to track an opaque cursor across calls.
        return list, nil, (#list > 0)

    elseif query and query ~= "" then
        -- NOTE: unverified live (Cloudflare JS challenge blocked every
        -- attempt to observe a real response here during porting).
        -- Query params match the real, current upstream Kotlin source
        -- (Comick.kt's getSearchMangaList); response shape is assumed
        -- to match /api/comics/top's BrowseComic-shaped items.
        local decoded, err = httpGetJson(source, "/api/search", {
            { "q", query },
            { "type", "comic" },
            { "order_by", "follow_count" },
            { "order_direction", "desc" },
            { "showAll", "false" },
            { "exclude_mylist", "false" },
            { "page", tostring(page) },
        })
        if not decoded then return nil, err end
        if type(decoded.data) ~= "table" then
            return nil, "unexpected Comick response shape (missing data array)"
        end
        local list = {}
        for _, comic in ipairs(decoded.data) do
            table.insert(list, mapBrowseComic(comic))
        end
        return list, nil, (decoded.next_cursor ~= nil and decoded.next_cursor ~= JSON.null)

    else
        -- "popular" (or empty-query browse fallback): real, verified
        -- /api/comics/top endpoint. Upstream Kotlin maps browse pages
        -- 1-6 across two `type`s (follow / most_follow_new) and three
        -- `days` windows (7/30/90); we mirror that 6-page cycle.
        local days
        local list_type
        local p = ((page - 1) % 6) + 1
        if p == 1 or p == 4 then days = 7
        elseif p == 2 or p == 5 then days = 30
        else days = 90 end
        if p <= 3 then list_type = "follow" else list_type = "most_follow_new" end

        local decoded, err = httpGetJson(source, "/api/comics/top", {
            { "days", tostring(days) },
            { "type", list_type },
        })
        if not decoded then return nil, err end
        if type(decoded.data) ~= "table" then
            return nil, "unexpected Comick response shape (missing data array)"
        end
        local list = {}
        for _, comic in ipairs(decoded.data) do
            table.insert(list, mapBrowseComic(comic))
        end
        return list, nil, (page < 6)
    end
end

function Source.fetch_manga_details(source, manga_url)
    local slug = slugFromMangaUrl(manga_url)
    if not slug then return nil, "could not parse Comick manga slug from url: " .. tostring(manga_url) end

    local decoded, err = fetchEmbeddedJson(source, API_BASE .. "/comic/" .. slug, "comic%-data", "comic-data")
    if not decoded then return nil, err end

    local genres = {}
    for _, g in ipairs(decoded.md_comic_md_genres or {}) do
        if g.md_genres and g.md_genres.name then
            table.insert(genres, g.md_genres.name)
        end
    end

    local status_map = {
        [1] = "ongoing",
        [2] = decoded.translation_completed and "completed" or "publishing_finished",
        [3] = "cancelled",
        [4] = "hiatus",
    }

    local author
    if type(decoded.authors) == "table" and decoded.authors[1] and decoded.authors[1].name then
        author = decoded.authors[1].name
    end

    return {
        title = decoded.title,
        author = author,
        description = decoded.desc or decoded.parsed,
        status = status_map[decoded.status] or "unknown",
        genres = genres,
        cover = decoded.default_thumbnail,
    }
end

function Source.fetch_chapter_list(source, manga_url)
    local slug = slugFromMangaUrl(manga_url)
    if not slug then return nil, "could not parse Comick manga slug from url: " .. tostring(manga_url) end

    local chapters = {}
    local page = 1
    local last_page = 1

    -- Comick's real /api/comics/{slug}/chapter-list is page-numbered
    -- (verified live: pagination.current_page/last_page/per_page), so
    -- unlike the search/latest cursor endpoints we can safely paginate
    -- fully here, capped for safety against pathological chapter counts.
    local safety_pages = 20
    for _ = 1, safety_pages do
        local decoded, err = httpGetJson(source, "/api/comics/" .. slug .. "/chapter-list", {
            { "lang", "en" },
            { "page", tostring(page) },
        })
        if not decoded then return nil, err end
        if type(decoded.data) ~= "table" then
            return nil, "unexpected Comick response shape (missing chapter-list data array)"
        end

        for _, ch in ipairs(decoded.data) do
            local number = ch.chap and ("Chapter " .. ch.chap) or "Chapter ?"
            local title = ch.title and ch.title ~= "" and (number .. ": " .. ch.title) or number
            local chapter_url = API_BASE .. "/comic/" .. slug .. "/" .. ch.hid
                .. "-chapter-" .. tostring(ch.chap) .. "-" .. tostring(ch.lang)
            table.insert(chapters, {
                title = title,
                url = chapter_url,
                date = ch.created_at,
            })
        end

        if type(decoded.pagination) == "table" then
            last_page = tonumber(decoded.pagination.last_page) or last_page
        end
        if page >= last_page or #decoded.data == 0 then break end
        page = page + 1
    end

    return chapters
end

function Source.fetch_page_list(source, chapter_url)
    local decoded, err = fetchEmbeddedJson(source, chapter_url, "sv%-data", "sv-data")
    if not decoded then return nil, err end

    if type(decoded.chapter) ~= "table" or type(decoded.chapter.images) ~= "table" then
        return nil, "unexpected Comick response shape (missing chapter.images)"
    end

    local pages = {}
    for _, image in ipairs(decoded.chapter.images) do
        if image.url then
            table.insert(pages, image.url)
        end
    end
    if #pages == 0 then
        return nil, "Comick returned no page images for this chapter"
    end
    return pages
end

return Source
