-- AsuraScans source_script smoke test: Astro-island prop extraction +
-- JSON API fixtures derived from REAL live responses fetched from
-- asurascans.com / api.asurascans.com on 2026-09-22 (see
-- extensions/sources/en/asurascans.tkext.json's "verification" block).
package.path = "koplugin/tachikindle.koplugin/?.lua;" .. package.path

package.preload.socket = function() return { skip = function(_, _, code) return code end } end
package.preload.socketutil = function() return { set_timeout = function() end, reset_timeout = function() end } end
package.preload["socket.http"] = function() return { request = function() return 1, 200 end } end
package.preload.ltn12 = function()
    return {
        sink = { table = function() return function() end end },
        source = { string = function(s) return s end },
    }
end
package.preload.logger = function() return { info = function() end, warn = function() end } end
package.preload.datastorage = function() return { getDataDir = function() return "." end } end
package.preload["libs/libkoreader-lfs"] = function() return { attributes = function() return nil end, mkdir = function() return true end } end
package.preload.htmlparser = function() return { parse = function() return { select = function() return {} end } end } end

local Source = require("tachikindlesource")

local tests = 0
local function test(name, fn)
    fn()
    tests = tests + 1
    print("PASS " .. name)
end

-- Real shape derived from GET https://api.asurascans.com/api/series?offset=0&limit=5
local SERIES_LIST_JSON = [[
{"data":[{"id":2144,"slug":"mount-hua-sects-genius-phantom-swordsman","title":"Mount Hua Sect's Genius Phantom Swordsman","cover":"https://cdn.asurascans.com/asura-images/covers/mount-hua-sects-genius-phantom-swordsman.ff7339.webp","status":"ongoing","type":"manhwa","chapter_count":82,"public_url":"/comics/mount-hua-sects-genius-phantom-swordsman-05c7df14"}],"meta":{"total":348,"per_page":5,"has_more":true}}
]]

-- Real shape derived from GET https://api.asurascans.com/api/series/mount-hua-sects-genius-phantom-swordsman
local SERIES_DETAILS_JSON = [[
{"series":{"id":2144,"slug":"mount-hua-sects-genius-phantom-swordsman","title":"Mount Hua Sect's Genius Phantom Swordsman","description":"<p>Phantom Swordsman Dokgo Heon.</p><p>Second para.</p>","cover":"https://cdn.asurascans.com/asura-images/covers/mount-hua-sects-genius-phantom-swordsman.ff7339.webp","status":"ongoing","type":"manhwa","author":"Muhyang","artist":"Studio DCCENT","public_url":"/comics/mount-hua-sects-genius-phantom-swordsman-05c7df14","genres":[{"id":1,"name":"Action","slug":"action"},{"id":4,"name":"Adventure","slug":"adventure"}]}}
]]

-- Real shape derived from the astro-island props="..." attribute on
-- https://asurascans.com/comics/mount-hua-sects-genius-phantom-swordsman
local CHAPTER_LIST_HTML = [==[
<html><body><astro-island uid="X" props="{&quot;chapters&quot;:[1,[[0,{&quot;id&quot;:[0,261660],&quot;series_id&quot;:[0,2144],&quot;number&quot;:[0,82],&quot;slug&quot;:[0,&quot;chapter-82&quot;],&quot;is_locked&quot;:[0,false],&quot;published_at&quot;:[0,&quot;2026-09-22T03:35:44.284926Z&quot;],&quot;series_slug&quot;:[0,&quot;mount-hua-sects-genius-phantom-swordsman&quot;]}],[0,{&quot;id&quot;:[0,261497],&quot;series_id&quot;:[0,2144],&quot;number&quot;:[0,81],&quot;slug&quot;:[0,&quot;chapter-81&quot;],&quot;is_locked&quot;:[0,true],&quot;published_at&quot;:[0,&quot;2026-09-15T16:26:00.32766Z&quot;],&quot;series_slug&quot;:[0,&quot;mount-hua-sects-genius-phantom-swordsman&quot;]}]]]}"></astro-island></body></html>
]==]

-- Real shape derived from the astro-island props="..." attribute on
-- https://asurascans.com/comics/mount-hua-sects-genius-phantom-swordsman/chapter/1
local PAGE_LIST_HTML = [==[
<html><body><astro-island uid="Y" component-export="default" props="{&quot;seriesSlug&quot;:[0,&quot;mount-hua-sects-genius-phantom-swordsman-05c7df14&quot;],&quot;pages&quot;:[1,[[0,{&quot;url&quot;:[0,&quot;https://cdn.asurascans.com/asura-images/chapters/mount-hua-sects-genius-phantom-swordsman/1/001.webp?v=1770499638&quot;],&quot;width&quot;:[0,1200],&quot;height&quot;:[0,800]}],[0,{&quot;url&quot;:[0,&quot;https://cdn.asurascans.com/asura-images/chapters/mount-hua-sects-genius-phantom-swordsman/1/002.webp?v=1770499638&quot;],&quot;width&quot;:[0,800],&quot;height&quot;:[0,13825]}]]]}"></astro-island></body></html>
]==]

local function load()
    return assert(Source:load("extensions/sources/en/asurascans.tkext.json"))
end

test("descriptor loads and dispatches to real source_script", function()
    local source = load()
    assert(source.def.id == "en.asurascans")
    assert(type(source.source_script) == "table")
    assert(type(source.source_script.fetch_manga_list) == "function")
    assert(type(source.source_script.fetch_manga_details) == "function")
    assert(type(source.source_script.fetch_chapter_list) == "function")
    assert(type(source.source_script.fetch_page_list) == "function")
end)

test("fetch_manga_list: popular parses real API shape", function()
    local source = load()
    local seen_url
    source.fetch = function(_, url)
        seen_url = url
        return SERIES_LIST_JSON
    end
    local list, err, has_next = source:fetchMangaList("popular", 1, "")
    assert(list, err)
    assert(seen_url == "https://api.asurascans.com/api/series?offset=0&limit=20")
    assert(#list == 1)
    assert(list[1].title == "Mount Hua Sect's Genius Phantom Swordsman")
    assert(list[1].url == "https://asurascans.com/series/mount-hua-sects-genius-phantom-swordsman")
    assert(list[1].cover:find("cdn.asurascans.com", 1, true))
    assert(has_next == true)
end)

test("fetch_manga_details: parses real API details shape", function()
    local source = load()
    source.fetch = function(_, url)
        assert(url == "https://api.asurascans.com/api/series/mount-hua-sects-genius-phantom-swordsman")
        return SERIES_DETAILS_JSON
    end
    local details, err = source:fetchMangaDetails("https://asurascans.com/series/mount-hua-sects-genius-phantom-swordsman")
    assert(details, err)
    assert(details.title == "Mount Hua Sect's Genius Phantom Swordsman")
    assert(details.author == "Muhyang")
    assert(details.status == "Ongoing")
    assert(#details.genres == 2 and details.genres[1] == "Action")
    assert(not details.description:find("<p>", 1, true))
end)

test("fetch_chapter_list: parses real Astro-prop chapters, marks locked", function()
    local source = load()
    source.fetch = function(_, url)
        if url:find("api.asurascans.com", 1, true) then
            assert(url == "https://api.asurascans.com/api/series/mount-hua-sects-genius-phantom-swordsman")
            return SERIES_DETAILS_JSON
        else
            assert(url == "https://asurascans.com/comics/mount-hua-sects-genius-phantom-swordsman-05c7df14")
            return CHAPTER_LIST_HTML
        end
    end
    local chapters, err = source:fetchChapterList("https://asurascans.com/series/mount-hua-sects-genius-phantom-swordsman")
    assert(chapters, err)
    assert(#chapters == 2)
    assert(chapters[1].title == "Chapter 82")
    assert(chapters[1].url == "https://asurascans.com/series/mount-hua-sects-genius-phantom-swordsman/chapter/82")
    assert(chapters[1].date == "2026-09-22T03:35:44.284926Z")
    assert(chapters[2].title:find("\240\159\148\146", 1, true), "locked chapter should be marked")
end)

test("fetch_page_list: parses real Astro-prop pages", function()
    local source = load()
    source.fetch = function(_, url)
        if url:find("api.asurascans.com", 1, true) then
            return SERIES_DETAILS_JSON
        else
            assert(url == "https://asurascans.com/comics/mount-hua-sects-genius-phantom-swordsman-05c7df14/chapter/1")
            return PAGE_LIST_HTML
        end
    end
    local pages, err = source:fetchPageList("https://asurascans.com/series/mount-hua-sects-genius-phantom-swordsman/chapter/1")
    assert(pages, err)
    assert(#pages == 2)
    assert(pages[1] == "https://cdn.asurascans.com/asura-images/chapters/mount-hua-sects-genius-phantom-swordsman/1/001.webp?v=1770499638")
    assert(pages[2]:find("002.webp", 1, true))
end)

test("fetch_page_list: empty pages array surfaces a real error, not a crash", function()
    local source = load()
    source.fetch = function(_, url)
        if url:find("api.asurascans.com", 1, true) then
            return SERIES_DETAILS_JSON
        else
            return [==[<html><body><astro-island props="{&quot;pages&quot;:[1,[]]}"></astro-island></body></html>]==]
        end
    end
    local pages, err = source:fetchPageList("https://asurascans.com/series/mount-hua-sects-genius-phantom-swordsman/chapter/999")
    assert(not pages and err and err:find("premium", 1, true))
end)

print(tests .. " AsuraScans source_script smoke tests passed")
