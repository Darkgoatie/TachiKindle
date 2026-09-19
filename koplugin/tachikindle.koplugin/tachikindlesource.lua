--[[--
TachiKindleSource: the runtime that actually executes a downloaded
.tkext.json against a live website. Loads the JSON, resolves
endpoint URL templates, fetches HTML over the network (never saves
pages/images to disk -- everything is read live, per the user's
requirement that chapters are read online, not downloaded), and
extracts data using KOReader's own bundled htmlparser
(common/htmlparser.lua + common/htmlparser/ElementNode.lua) --
confirmed present and used elsewhere in KOReader (newsdownloader's
epubdownloadbackend.lua) via `require("htmlparser")`, real CSS-class/
id/attribute selector engine, verified end-to-end on-device against
a synthetic Madara-shaped fixture before this file was written.

See extensions/format/schema-1.0.json (project root) for the field
reference this module consumes.

@module koplugin.TachiKindleSource
--]]--

local htmlparser = require("htmlparser")
local socket = require("socket")
local socket_url = require("socket.url")
local socketutil = require("socketutil")
local http = require("socket.http")
local ltn12 = require("ltn12")
local JSON = require("json")
local logger = require("logger")

local TachiKindleSource = {}
TachiKindleSource.__index = TachiKindleSource

-- Load a .tkext.json file from disk into a runnable source object.
function TachiKindleSource:load(path)
    local f = io.open(path, "r")
    if not f then return nil, "cannot open " .. path end
    local body = f:read("*a")
    f:close()

    local ok, def = pcall(JSON.decode, body)
    if not ok or type(def) ~= "table" then
        return nil, "invalid JSON in " .. path
    end

    return setmetatable({ def = def }, self)
end

-- Fill {placeholders} in an endpoint path template. query is
-- URL-encoded since it's user-typed free text; page/offset/manga_url/
-- chapter_url are either numeric or already-URL-safe scraped links.
-- NOTE: placeholder names use underscores (manga_url, chapter_url),
-- and Lua's %w character class does NOT include '_' -- using %w+
-- here silently failed to match those two placeholders at all,
-- leaving the literal "{manga_url}" in the URL and producing an
-- invalid URL (real symptom: "HTTP host or service not provided").
local function fillTemplate(tpl, vars)
    return (tpl:gsub("{([%w_]+)}", function(key)
        local v = tostring(vars[key] or "")
        if key == "query" then v = socket_url.escape(v) end
        return v
    end))
end

function TachiKindleSource:resolveUrl(endpoint_name, vars)
    local ep = self.def.endpoints and self.def.endpoints[endpoint_name]
    if not ep then return nil, "no endpoint: " .. endpoint_name end
    local path = fillTemplate(ep.path, vars or {})
    -- path may already be an absolute URL (manga_url/chapter_url
    -- endpoints just echo back a previously-scraped absolute link)
    if path:match("^https?://") then
        return path
    end
    return self.def.base_url .. path
end

-- GET a URL using this source's declared user_agent/headers. Default
-- Accept mimics a real browser -- weebcentral.com (and likely other
-- sites behind similar bot-detection) serves a near-empty stub page
-- for Accept: */* (curl/plain HTTP client default) but real content
-- for a browser-shaped Accept header. Confirmed live: same URL, same
-- UA, only the Accept header differed between a 300-byte stub and a
-- real 247KB page with all 133 chapters.
function TachiKindleSource:fetch(url)
    local sink = {}
    local headers = {
        ["Accept-Encoding"] = "identity",
        ["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        ["Accept-Language"] = "en-US,en;q=0.9",
    }
    local client = self.def.client or {}
    if client.user_agent then headers["User-Agent"] = client.user_agent end
    for k, v in pairs(client.extra_headers or {}) do headers[k] = v end

    socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
    local ok, code = pcall(function()
        return socket.skip(1, http.request{
            url = url, method = "GET", headers = headers,
            sink = ltn12.sink.table(sink),
        })
    end)
    socketutil:reset_timeout()

    if not ok then return nil, tostring(code) end
    if code ~= 200 then return nil, "HTTP " .. tostring(code) end
    return table.concat(sink)
end

-- Run a selector (string or {sel,attr,fallback_attr}) against a
-- parsed node, returning text or an attribute value. sel == "self"
-- (or omitted) means "read the attribute off the node passed in
-- directly" -- needed when the list-item selector already IS the
-- link (e.g. WeebCentral's "article > section > a" list items),
-- so there's no child <a> to select into.
local function applySelector(node, selector)
    if type(selector) == "string" then
        local found = node:select(selector)[1]
        return found and found:textonly():gsub("^%s+", ""):gsub("%s+$", "") or nil
    end
    local found = node
    if selector.sel and selector.sel ~= "self" then
        found = node:select(selector.sel)[1]
    end
    if not found then return nil end
    local v = found.attributes[selector.attr]
    if (not v or v == "") and selector.fallback_attr then
        v = found.attributes[selector.fallback_attr]
    end
    return v
end

-- Popular/latest/search manga list -> { {title, url, cover}, ... }.
-- offset is derived from page (1-indexed) using a fixed page size,
-- since WeebCentral's real API takes offset=(page-1)*pageSize, not
-- a page number -- passing page directly into {offset} silently
-- skipped/missed real results (confirmed: page=1 produced offset=1,
-- which returned wrong/empty results against the live site).
local SEARCH_PAGE_SIZE = 32
function TachiKindleSource:fetchMangaList(endpoint_name, page, query)
    page = page or 1
    local url, err = self:resolveUrl(endpoint_name, {
        page = page,
        offset = (page - 1) * SEARCH_PAGE_SIZE,
        query = query or "",
    })
    if not url then return nil, err end
    local body, ferr = self:fetch(url)
    if not body then return nil, ferr end

    local root = htmlparser.parse(body, 5000)
    local sel = self.def.selectors
    local items = root:select(sel.manga_list_item)
    local list = {}
    for _, item in ipairs(items) do
        table.insert(list, {
            title = applySelector(item, sel.manga_title),
            url = applySelector(item, sel.manga_url),
            cover = applySelector(item, sel.manga_cover),
        })
    end
    local has_next = sel.has_next_page and (#root:select(sel.has_next_page) > 0) or false
    return list, nil, has_next
end

-- Manga details page -> { title, author, description, status, genres, cover }
function TachiKindleSource:fetchMangaDetails(manga_url)
    local url, err = self:resolveUrl("manga_details", { manga_url = manga_url })
    if not url then return nil, err end
    local body, ferr = self:fetch(url)
    if not body then return nil, ferr end

    local root = htmlparser.parse(body, 5000)
    local sel = self.def.selectors
    local genres = {}
    for _, g in ipairs(root:select(sel.details_genres or "")) do
        table.insert(genres, g:textonly())
    end
    return {
        title = applySelector(root, sel.details_title),
        author = applySelector(root, sel.details_author),
        description = applySelector(root, sel.details_description),
        status = applySelector(root, sel.details_status),
        genres = genres,
        cover = applySelector(root, sel.details_cover),
    }
end

-- Chapter list for a manga -> { {title, url, date}, ... }, newest first
-- as the site returns them (no re-sorting -- most theme sites already
-- list newest-first, and re-sorting risks fighting a source that isn't).
--
-- WeebCentral's real chapter-list URL is /series/{seriesId}/full-chapter-list
-- WITHOUT the trailing slug -- the manga_url scraped from search/popular
-- includes the slug (.../series/{id}/Kagurabachi), and appending
-- /full-chapter-list to THAT 404s (confirmed live: identical bytes to
-- a real fetched 404 page, "manga you are looking for might have been
-- moved or deleted"). Strip back to base_url + first two path segments
-- before resolving this one endpoint.
function TachiKindleSource:fetchChapterList(manga_url)
    local trimmed_url = manga_url:match("^(https?://[^/]+/[^/]+/[^/]+)")  or manga_url
    local url, err = self:resolveUrl("chapter_list", { manga_url = trimmed_url })
    if not url then return nil, err end
    logger.info("TachiKindle: fetching chapter list from " .. tostring(url))
    local body, ferr = self:fetch(url)
    if not body then
        logger.info("TachiKindle: chapter list fetch failed: " .. tostring(ferr))
        return nil, ferr
    end
    logger.info("TachiKindle: chapter list body length " .. #body)

    local root = htmlparser.parse(body, 5000)
    local sel = self.def.selectors
    local items = root:select(sel.chapter_item)
    logger.info("TachiKindle: chapter_item selector '" .. tostring(sel.chapter_item) .. "' matched " .. #items .. " items")
    local list = {}
    for _, item in ipairs(items) do
        table.insert(list, {
            title = applySelector(item, sel.chapter_title),
            url = applySelector(item, sel.chapter_url),
            date = sel.chapter_date and applySelector(item, sel.chapter_date) or nil,
        })
    end
    return list
end

-- Page image URLs for a chapter -> { url, url, ... }. Nothing is
-- downloaded to disk here -- the reader UI fetches each image URL
-- on demand as the user turns pages (see ui_online_reader.lua).
function TachiKindleSource:fetchPageList(chapter_url)
    local url, err = self:resolveUrl("page_list", { chapter_url = chapter_url })
    if not url then return nil, err end
    local body, ferr = self:fetch(url)
    if not body then return nil, ferr end

    local root = htmlparser.parse(body, 5000)
    local sel = self.def.selectors
    local pages = {}
    for _, img in ipairs(root:select(sel.page_image.sel)) do
        local v = img.attributes[sel.page_image.attr]
        if (not v or v == "") and sel.page_image.fallback_attr then
            v = img.attributes[sel.page_image.fallback_attr]
        end
        if v and v ~= "" then table.insert(pages, v) end
    end
    return pages
end

return TachiKindleSource
