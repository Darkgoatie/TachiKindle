-- Runtime integration tests; dependencies at the KOReader/HTTP boundary are stubbed.
package.path = "koplugin/tachikindle.koplugin/?.lua;" .. package.path
local definition, request, cached
local parsed = { select = function() return {} end }
package.preload.htmlparser = function() return {parse = function() return parsed end} end
package.preload.socket = function() return {skip = function(_, _, code) return code end} end
package.preload["socket.url"] = function() return {escape = function(s) return s end} end
package.preload.socketutil = function() return {set_timeout = function() end, reset_timeout = function() end} end
package.preload["socket.http"] = function() return {request = function(r) request = r; r.sink("body"); return 1, 200 end} end
package.preload.ltn12 = function() return {sink = {table = function(t) return function(v) t[#t+1] = v end end}, source = {string = function(s) return s end}} end
package.preload.json = function() return {decode = function() return definition end} end
package.preload.logger = function() return {info = function() end, warn = function() end} end
package.preload.datastorage = function() return {getDataDir = function() return "." end} end
package.preload["libs/libkoreader-lfs"] = function() return {} end
local adapter = {
    fetchMangaList = function(source, endpoint, page, query)
        assert(source.def.adapter == "readallcomics" and endpoint == "search" and page == 2 and query == "test")
        return {{title = "AdapterResult"}}, nil, true
    end,
    fetchMangaDetails = function(_, url) return {title = url} end,
    fetchChapterList = function(_, url) return {{url = url .. "/issue"}} end,
    parsePages = function(_, body, url)
        assert(body == "body" and url == "https://example.test/chapter")
        return {"https://example.test/image.png"}
    end,
}
package.preload["adapters/readallcomics"] = function() return adapter end

local source_script = {
    fetch_manga_list = function(source, endpoint, page, query)
        assert(source.def.source_script == "sources/en/readallcomics")
        assert(endpoint == "search" and page == 2 and query == "test")
        return {{title = "ScriptResult"}}, nil, true
    end,
}
package.preload["sources/en/readallcomics"] = function() return source_script end
local Source = require("tachikindlesource")
local path = os.tmpname()
local file = assert(io.open(path, "w")); file:write("{}"); file:close()
local tests = 0
local function test(name, fn)
    fn(); tests = tests + 1; print("PASS " .. name)
end
local function load()
    definition = {
        id = "en.readallcomics",
        source_script = "sources/en/readallcomics",
        adapter = "readallcomics",
        base_url = "https://example.test",
        endpoints = {page_list = {method = "GET", path = "{chapter_url}"}},
    }
    return assert(Source:load(path))
end

test("reject non-canonical source_script path", function()
    definition = {id = "en.readallcomics", source_script = "sources/en/other"}
    local source, err = Source:load(path)
    assert(source == nil and err:match("unsupported source_script"))
end)

test("reject unknown adapter instead of requiring downloaded code", function()
    definition = {id = "en.readallcomics", source_script = "sources/en/readallcomics", adapter = "../../arbitrary"}
    local source, err = Source:load(path)
    assert(source == nil and err:match("unsupported adapter"))
end)
test("dispatch list through source script and retain pagination", function()
    local list, err, more = load():fetchMangaList("search", 2, "test")
    assert(list[1].title == "ScriptResult" and not err and more)
end)
test("dispatch details and chapters with complete URL", function()
    local source = load()
    assert(source:fetchMangaDetails("https://example.test/a/b/c").title == "https://example.test/a/b/c")
    assert(source:fetchChapterList("https://example.test/a/b/c")[1].url == "https://example.test/a/b/c/issue")
end)
test("parse adapter pages and preserve cache writes", function()
    local source = load()
    source.savePageListCache = function(_, _, pages) cached = pages end
    local pages = assert(source:fetchPageList("https://example.test/chapter"))
    assert(#pages == 1 and cached == pages)
end)
test("adapter parse error falls back to offline pages", function()
    local source = load()
    local original = adapter.parsePages
    adapter.parsePages = function() return nil, "challenge page" end
    source.loadPageListCache = function() return {"https://example.test/cached.png"} end
    local pages = assert(source:fetchPageList("https://example.test/chapter"))
    assert(pages[1] == "https://example.test/cached.png")
    source.loadPageListCache = function() return nil end
    local none, err = source:fetchPageList("https://example.test/chapter")
    assert(not none and err == "challenge page")
    adapter.parsePages = original
end)
test("empty page response reports failure, not successful blank chapter", function()
    local source = load()
    local original = adapter.parsePages
    adapter.parsePages = function() return {} end
    source.loadPageListCache = function() return nil end
    local pages, err = source:fetchPageList("https://example.test/chapter")
    assert(pages == nil and err:match("No page images"))
    adapter.parsePages = original
end)
test("HTTP request options carry method body and headers", function()
    local source = load()
    assert(source:fetch("https://example.test/search", {method = "POST", body = "q=test", headers = {["Content-Type"] = "application/x-www-form-urlencoded"}}) == "body")
    assert(request.method == "POST" and request.source == "q=test")
    assert(request.headers["Content-Length"] == "6")
    assert(request.headers["Content-Type"] == "application/x-www-form-urlencoded")
    source:fetch("https://example.test/default")
    assert(request.method == "GET" and request.source == nil)
end)
test("fetchPages adapter bypasses GET and retains cache fallback", function()
    local source = load()
    source.resolveUrl = function() error("fetchPages must bypass ordinary GET") end
    source.savePageListCache = function(_, _, pages) cached = pages end
    adapter.fetchPages = function(_, chapter_url)
        assert(chapter_url == "https://example.test/chapter")
        return {"https://example.test/api.png"}
    end
    local pages = assert(source:fetchPageList("https://example.test/chapter"))
    assert(pages[1] == "https://example.test/api.png" and cached == pages)
    adapter.fetchPages = function() return nil, "API blocked" end
    source.loadPageListCache = function() return {"https://example.test/offline.png"} end
    assert(source:fetchPageList("https://example.test/chapter")[1] == "https://example.test/offline.png")
    source.loadPageListCache = function() return nil end
    local none, err = source:fetchPageList("https://example.test/chapter")
    assert(not none and err == "API blocked")
    adapter.fetchPages = nil
end)
test("selector-only sources still load and cache page images", function()
    definition = {base_url = "https://example.test", endpoints = {page_list = {path = "{chapter_url}"}}, selectors = {page_image = {sel = "img", attr = "src"}}}
    local source = assert(Source:load(path))
    assert(source.adapter == nil)
    parsed.select = function(_, selector)
        assert(selector == "img")
        return {{attributes = {src = "/legacy.png"}}}
    end
    source.savePageListCache = function(_, _, pages) cached = pages end
    local pages = assert(source:fetchPageList("https://example.test/legacy"))
    assert(pages[1] == "https://example.test/legacy.png" and cached == pages)
end)
os.remove(path)
print(tests .. " runtime integration tests passed")
