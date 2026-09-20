--[[--
TachiKindleSource: the runtime that actually executes a downloaded
.tkext.json against a live website. Loads the JSON, resolves
endpoint URL templates, fetches HTML over the network, and
extracts data using KOReader's own bundled htmlparser. Chapter page
lists and image bytes are cached on disk for offline reading.
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
local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")

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

    -- Only bundled adapters are executable; repository JSON cannot name arbitrary modules.
    local adapters = {
        readallcomics = "adapters/readallcomics",
        xoxocomics = "adapters/xoxocomics",
        readcomiconline = "adapters/readcomiconline",
        batcave = "adapters/batcave",
    }
    local adapter
    if def.adapter then
        local module = adapters[def.adapter]
        if not module then return nil, "unsupported adapter: " .. tostring(def.adapter) end
        local loaded, result = pcall(require, module)
        if not loaded then return nil, "adapter unavailable: " .. tostring(result) end
        adapter = result
    end
    return setmetatable({ def = def, adapter = adapter }, self)
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
function TachiKindleSource:fetch(url, options)
    options = options or {}
    local headers = {
        ["Accept-Encoding"] = "identity",
        ["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        ["Accept-Language"] = "en-US,en;q=0.9",
        ["Connection"] = "close",
    }
    local client = self.def.client or {}
    if client.user_agent then headers["User-Agent"] = client.user_agent end
    for k, v in pairs(client.extra_headers or {}) do headers[k] = v end
    for k, v in pairs(options.headers or {}) do headers[k] = v end
    if options.body then headers["Content-Length"] = tostring(#options.body) end

    local attempts = 6
    local last_err
    for i = 1, attempts do
        local sink = {}
        socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
        local ok, code = pcall(function()
            return socket.skip(1, http.request{
                url = url, method = options.method or "GET", headers = headers,
                source = options.body and ltn12.source.string(options.body) or nil,
                sink = ltn12.sink.table(sink),
            })
        end)
        socketutil:reset_timeout()

        if ok and code == 200 then
            return table.concat(sink)
        end

        local msg = ok and tostring(code) or tostring(code)
        last_err = msg
        local lower = msg:lower()
        local transient = lower:match("cannot assign requested address")
            or lower:match("timeout")
            or lower:match("closed")
            or lower:match("refused")
        if i < attempts and transient then
            socket.sleep(0.4 * i)
        else
            break
        end
    end

    return nil, "HTTP " .. tostring(last_err)
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

local function normalizeUrl(base_url, v)
    if not v then return nil end
    v = tostring(v):gsub("^%s+", ""):gsub("%s+$", "")
    v = v:gsub('^"', ""):gsub('"$', "")
    if v == "" or v == "nil" then return nil end
    if v:match("^https?://") then return v end
    if v:match("^//") then return "https:" .. v end
    if v:match("^/") then return base_url .. v end
    return nil
end

local function safeKey(s)
    s = tostring(s or "")
    return (s:gsub("[^%w]", "_"))
end

local function ensureDir(path)
    if lfs.attributes(path, "mode") == "directory" then return true end
    local cur = ""
    for part in path:gmatch("[^/]+") do
        cur = cur == "" and part or (cur .. "/" .. part)
        if lfs.attributes(cur, "mode") ~= "directory" then
            local ok, err = lfs.mkdir(cur)
            if not ok then return nil, err end
        end
    end
    return true
end

function TachiKindleSource:cacheRoot()
    return DataStorage:getDataDir() .. "/tachikindle/cache"
end

function TachiKindleSource:chapterCacheDir(chapter_url)
    return self:cacheRoot() .. "/" .. safeKey(self.def.id) .. "/" .. safeKey(chapter_url)
end

function TachiKindleSource:pageListCachePath(chapter_url)
    return self:chapterCacheDir(chapter_url) .. "/pages.json"
end

function TachiKindleSource:pageCachePath(chapter_url, index, page_url)
    local ext = tostring(page_url or ""):match("%.([A-Za-z0-9]+)(%?.*)?$")
    ext = ext and ext:lower() or "img"
    if #ext > 5 then ext = "img" end
    return string.format("%s/page_%04d.%s", self:chapterCacheDir(chapter_url), index, ext)
end

function TachiKindleSource:savePageListCache(chapter_url, pages)
    local dir = self:chapterCacheDir(chapter_url)
    local ok, err = ensureDir(dir)
    if not ok then return nil, err end
    local f, ferr = io.open(self:pageListCachePath(chapter_url), "w")
    if not f then return nil, ferr end
    f:write(JSON.encode({ pages = pages }))
    f:close()
    return true
end

function TachiKindleSource:loadPageListCache(chapter_url)
    local f = io.open(self:pageListCachePath(chapter_url), "r")
    if not f then return nil end
    local body = f:read("*a")
    f:close()
    local ok, obj = pcall(JSON.decode, body)
    if not ok or type(obj) ~= "table" or type(obj.pages) ~= "table" then
        return nil
    end
    return obj.pages
end

function TachiKindleSource:saveCachedPage(chapter_url, index, page_url, body)
    local dir = self:chapterCacheDir(chapter_url)
    local ok, err = ensureDir(dir)
    if not ok then return nil, err end
    local path = self:pageCachePath(chapter_url, index, page_url)
    local tmp = path .. ".tmp"
    local f, ferr = io.open(tmp, "wb")
    if not f then return nil, ferr end
    f:write(body)
    f:close()
    os.remove(path)
    local rok, rerr = os.rename(tmp, path)
    if not rok then
        os.remove(tmp)
        return nil, rerr
    end
    return path
end

function TachiKindleSource:loadCachedPage(chapter_url, index, page_url)
    local path = self:pageCachePath(chapter_url, index, page_url)
    local f = io.open(path, "rb")
    if not f then return nil end
    local body = f:read("*a")
    f:close()
    if not body or #body == 0 then return nil end
    return body
end

-- Popular/latest/search manga list -> { {title, url, cover}, ... }.
-- offset is derived from page (1-indexed) using a fixed page size,
-- since WeebCentral's real API takes offset=(page-1)*pageSize, not
-- a page number -- passing page directly into {offset} silently
-- skipped/missed real results (confirmed: page=1 produced offset=1,
-- which returned wrong/empty results against the live site).
local SEARCH_PAGE_SIZE = 32
function TachiKindleSource:fetchMangaList(endpoint_name, page, query)
    if self.adapter and self.adapter.fetchMangaList then
        return self.adapter.fetchMangaList(self, endpoint_name, page or 1, query or "")
    end
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
    if self.adapter and self.adapter.fetchMangaDetails then
        return self.adapter.fetchMangaDetails(self, manga_url)
    end
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
-- Some sources drift between slugged and slugless chapter-list routes.
-- Try the scraped manga_url first, then a trimmed /segment1/segment2
-- fallback if the first response yields no chapter items.
function TachiKindleSource:fetchChapterList(manga_url)
    if self.adapter and self.adapter.fetchChapterList then
        return self.adapter.fetchChapterList(self, manga_url)
    end

    local candidates = { manga_url }
    local trimmed = manga_url:match("^(https?://[^/]+/[^/]+/[^/]+)")
    if trimmed and trimmed ~= manga_url then
        table.insert(candidates, trimmed)
    end

    local sel = self.def.selectors
    local saw_body = false
    local last_list = {}
    local last_err

    for _, candidate in ipairs(candidates) do
        local url, err = self:resolveUrl("chapter_list", { manga_url = candidate })
        if not url then
            last_err = err
        else
            logger.info("TachiKindle: fetching chapter list from " .. tostring(url))
            local body, ferr = self:fetch(url)
            if body then
                saw_body = true
                logger.info("TachiKindle: chapter list body length " .. #body)

                local root = htmlparser.parse(body, 5000)
                local items = root:select(sel.chapter_item)
                logger.info("TachiKindle: chapter_item selector '" .. tostring(sel.chapter_item) .. "' matched " .. #items .. " items")
                local list = {}
                for _, item in ipairs(items) do
                    local chapter_url = normalizeUrl(self.def.base_url, applySelector(item, sel.chapter_url))
                    if chapter_url then
                        table.insert(list, {
                            title = applySelector(item, sel.chapter_title),
                            url = chapter_url,
                            date = sel.chapter_date and applySelector(item, sel.chapter_date) or nil,
                        })
                    end
                end
                if #list > 0 then
                    return list
                end
                last_list = list
            else
                logger.info("TachiKindle: chapter list fetch failed: " .. tostring(ferr))
                last_err = ferr
            end
        end
    end

    if saw_body then
        return last_list
    end
    return nil, last_err
end

-- Page image URLs for a chapter -> { url, url, ... }.
-- If online fetch fails, falls back to previously cached page-list metadata.
function TachiKindleSource:fetchPageList(chapter_url)
    local pages, ferr
    if self.adapter and self.adapter.fetchPages then
        pages, ferr = self.adapter.fetchPages(self, chapter_url)
    else
        local url, err = self:resolveUrl("page_list", { chapter_url = chapter_url })
        if not url then return nil, err end
        local body
        body, ferr = self:fetch(url)
        if body then
            if self.adapter and self.adapter.parsePages then
                pages, ferr = self.adapter.parsePages(self, body, chapter_url)
            else
                local root = htmlparser.parse(body, 5000)
                local sel = self.def.selectors
                pages = {}
                for _, img in ipairs(root:select(sel.page_image.sel)) do
                    local v = img.attributes[sel.page_image.attr]
                    if (not v or v == "") and sel.page_image.fallback_attr then
                        v = img.attributes[sel.page_image.fallback_attr]
                    end
                    v = normalizeUrl(self.def.base_url, v)
                    if v then table.insert(pages, v) end
                end
            end
        end
    end
    if pages and #pages > 0 then
        self:savePageListCache(chapter_url, pages)
        return pages
    end
    ferr = ferr or "No page images found; the site may require browser access or its layout has changed."

    local cached_pages = self:loadPageListCache(chapter_url)
    if cached_pages and #cached_pages > 0 then
        logger.info("TachiKindle: using cached page list for offline chapter: " .. tostring(chapter_url))
        return cached_pages
    end
    return nil, ferr
end

-- Returns bytes for one chapter page. Reads cache first for offline support,
-- falls back to network and stores successful fetches into cache.
function TachiKindleSource:fetchChapterPage(chapter_url, page_index, page_url)
    local cached = self:loadCachedPage(chapter_url, page_index, page_url)
    if cached then return cached, nil, true end
    local body, err = self:fetch(page_url)
    if not body then return nil, err, false end
    self:saveCachedPage(chapter_url, page_index, page_url, body)
    return body, nil, false
end

function TachiKindleSource:chapterMetaPath(chapter_url)
    return self:chapterCacheDir(chapter_url) .. "/meta.json"
end

function TachiKindleSource:saveChapterMeta(chapter_url, meta)
    local dir = self:chapterCacheDir(chapter_url)
    local ok, err = ensureDir(dir)
    if not ok then return nil, err end
    local f, ferr = io.open(self:chapterMetaPath(chapter_url), "w")
    if not f then return nil, ferr end
    f:write(JSON.encode(meta or {}))
    f:close()
    return true
end

function TachiKindleSource:loadChapterMeta(chapter_url)
    local f = io.open(self:chapterMetaPath(chapter_url), "r")
    if not f then return nil end
    local body = f:read("*a")
    f:close()
    local ok, meta = pcall(JSON.decode, body)
    if not ok or type(meta) ~= "table" then return nil end
    return meta
end

function TachiKindleSource:chapterCacheStats(chapter_url)
    local pages = self:loadPageListCache(chapter_url) or {}
    local saved = 0
    local size_bytes = 0
    for i, page_url in ipairs(pages) do
        local path = self:pageCachePath(chapter_url, i, page_url)
        local st = lfs.attributes(path)
        if st and st.size and st.size > 0 then
            saved = saved + 1
            size_bytes = size_bytes + st.size
        end
    end
    return {
        total = #pages,
        saved = saved,
        failed = math.max(#pages - saved, 0),
        complete = #pages > 0 and saved == #pages,
        size_bytes = size_bytes,
    }
end

function TachiKindleSource:isChapterDownloaded(chapter_url)
    local stats = self:chapterCacheStats(chapter_url)
    if stats.complete then
        return true, stats
    end
    local meta = self:loadChapterMeta(chapter_url)
    if meta and meta.complete == true then
        return true, {
            total = tonumber(meta.total) or 0,
            saved = tonumber(meta.saved) or 0,
            failed = tonumber(meta.failed) or 0,
            complete = true,
            size_bytes = tonumber(meta.size_bytes) or 0,
        }
    end
    return false, stats
end

-- Best-effort prefetch for offline reading: saves page list + every page image.
-- opts:
--   force=true         redownload all pages
--   manga_title=string persisted in chapter metadata
--   chapter_title=string persisted in chapter metadata
function TachiKindleSource:prefetchChapter(chapter_url, opts)
    opts = opts or {}

    if not opts.force then
        local already_downloaded, stats = self:isChapterDownloaded(chapter_url)
        if already_downloaded then
            return {
                total = stats.total or 0,
                saved = stats.saved or 0,
                failed = 0,
                skipped = true,
            }
        end
    end

    local pages, err = self:fetchPageList(chapter_url)
    if not pages then return nil, err end

    local ok_count, fail_count = 0, 0
    for i, page_url in ipairs(pages) do
        local body = (not opts.force) and self:loadCachedPage(chapter_url, i, page_url) or nil
        if body then
            ok_count = ok_count + 1
        else
            local fetched, ferr = self:fetch(page_url)
            if fetched then
                self:saveCachedPage(chapter_url, i, page_url, fetched)
                ok_count = ok_count + 1
            else
                logger.warn("TachiKindle: prefetch page failed", i, ferr)
                fail_count = fail_count + 1
            end
        end
    end

    local result = {
        total = #pages,
        saved = ok_count,
        failed = fail_count,
    }

    local stats = self:chapterCacheStats(chapter_url)
    self:saveChapterMeta(chapter_url, {
        source_id = self.def.id,
        source_name = self.def.name,
        chapter_url = chapter_url,
        chapter_title = opts.chapter_title,
        manga_title = opts.manga_title,
        cached_at = os.time(),
        total = stats.total,
        saved = stats.saved,
        failed = stats.failed,
        complete = stats.complete,
        size_bytes = stats.size_bytes,
    })

    return result
end

function TachiKindleSource:verifyChapterCache(chapter_url)
    local stats = self:chapterCacheStats(chapter_url)
    local meta = self:loadChapterMeta(chapter_url) or {}
    meta.total = stats.total
    meta.saved = stats.saved
    meta.failed = stats.failed
    meta.complete = stats.complete
    meta.size_bytes = stats.size_bytes
    meta.verified_at = os.time()
    self:saveChapterMeta(chapter_url, meta)
    return stats
end

function TachiKindleSource:deleteChapterCache(chapter_url)
    local dir = self:chapterCacheDir(chapter_url)
    if lfs.attributes(dir, "mode") ~= "directory" then
        return true
    end
    for name in lfs.dir(dir) do
        if name ~= "." and name ~= ".." then
            os.remove(dir .. "/" .. name)
        end
    end
    lfs.rmdir(dir)
    return true
end

function TachiKindleSource:listCachedChapters()
    local root = self:cacheRoot() .. "/" .. safeKey(self.def.id)
    local out = {}
    if lfs.attributes(root, "mode") ~= "directory" then return out end
    for dirname in lfs.dir(root) do
        if dirname ~= "." and dirname ~= ".." then
            local dir = root .. "/" .. dirname
            if lfs.attributes(dir, "mode") == "directory" then
                local f = io.open(dir .. "/meta.json", "r")
                local meta = nil
                if f then
                    local body = f:read("*a")
                    f:close()
                    local ok, m = pcall(JSON.decode, body)
                    if ok and type(m) == "table" then meta = m end
                end
                local chapter_url = meta and meta.chapter_url or nil
                if chapter_url then
                    local stats = self:chapterCacheStats(chapter_url)
                    table.insert(out, {
                        source_id = self.def.id,
                        source_name = self.def.name,
                        chapter_url = chapter_url,
                        chapter_title = meta.chapter_title or chapter_url,
                        manga_title = meta.manga_title,
                        cached_at = meta.cached_at,
                        total = stats.total,
                        saved = stats.saved,
                        failed = stats.failed,
                        complete = stats.complete,
                        size_bytes = stats.size_bytes,
                    })
                end
            end
        end
    end
    table.sort(out, function(a, b) return (a.cached_at or 0) > (b.cached_at or 0) end)
    return out
end

function TachiKindleSource:queuePath()
    return self:cacheRoot() .. "/download_queue.json"
end

function TachiKindleSource:loadQueue()
    local f = io.open(self:queuePath(), "r")
    if not f then return {} end
    local body = f:read("*a")
    f:close()
    local ok, q = pcall(JSON.decode, body)
    if not ok or type(q) ~= "table" then return {} end
    return q
end

function TachiKindleSource:saveQueue(q)
    local ok, err = ensureDir(self:cacheRoot())
    if not ok then return nil, err end
    local f, ferr = io.open(self:queuePath(), "w")
    if not f then return nil, ferr end
    f:write(JSON.encode(q or {}))
    f:close()
    return true
end

function TachiKindleSource:enqueueChapter(job)
    local q = self:loadQueue()
    job = job or {}

    if not job.chapter_url then
        return #q, "missing_chapter_url"
    end

    local already_downloaded = self:isChapterDownloaded(job.chapter_url)
    if already_downloaded then
        return #q, "already_downloaded"
    end

    for _, existing in ipairs(q) do
        if existing.source_id == self.def.id and existing.chapter_url == job.chapter_url then
            return #q, "already_queued"
        end
    end

    job.source_id = self.def.id
    job.source_name = self.def.name
    job.created_at = os.time()
    table.insert(q, job)
    table.sort(q, function(a, b)
        return (a.created_at or 0) < (b.created_at or 0)
    end)
    self:saveQueue(q)
    return #q, "queued"
end

function TachiKindleSource:removeQueueJob(index)
    local q = self:loadQueue()
    table.remove(q, index)
    self:saveQueue(q)
    return q
end

function TachiKindleSource:clearQueue()
    local q = self:loadQueue()
    local kept = {}
    for _, job in ipairs(q) do
        if job.source_id ~= self.def.id then table.insert(kept, job) end
    end
    self:saveQueue(kept)
    return kept
end

function TachiKindleSource:processQueue(max_jobs)
    max_jobs = tonumber(max_jobs) or 1
    local q = self:loadQueue()
    local done, failed = 0, 0
    local i = 1
    while i <= #q and done < max_jobs do
        local job = q[i]
        if job.source_id == self.def.id and job.chapter_url then
            local result = self:prefetchChapter(job.chapter_url, {
                force = job.force,
                manga_title = job.manga_title,
                chapter_title = job.chapter_title,
            })
            if result and (result.skipped or (result.total > 0 and result.saved > 0)) then
                table.remove(q, i)
                done = done + 1
            else
                job.last_error = "download_failed"
                failed = failed + 1
                i = i + 1
            end
        else
            i = i + 1
        end
    end
    self:saveQueue(q)
    return { done = done, failed = failed, remaining = #q }
end

function TachiKindleSource:totalCacheBytes()
    local root = self:cacheRoot()
    local total = 0
    local function walk(dir)
        if lfs.attributes(dir, "mode") ~= "directory" then return end
        for name in lfs.dir(dir) do
            if name ~= "." and name ~= ".." then
                local path = dir .. "/" .. name
                local st = lfs.attributes(path)
                if st and st.mode == "directory" then
                    walk(path)
                elseif st and st.size then
                    total = total + st.size
                end
            end
        end
    end
    walk(root)
    return total
end

function TachiKindleSource:cleanFailedCaches()
    local removed = 0
    for _, ch in ipairs(self:listCachedChapters()) do
        if ch.failed > 0 and ch.saved == 0 then
            self:deleteChapterCache(ch.chapter_url)
            removed = removed + 1
        end
    end
    return removed
end

return TachiKindleSource
