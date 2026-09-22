-- Test for MangaBuddy (en.mangabuddy). Unlike the selector-passthrough
-- sources in test_selector_extensions_smoke.lua, MangaBuddy's
-- source_script does not use htmlparser at all (see real-site-quirk
-- comments in koplugin/tachikindle.koplugin/sources/en/mangabuddy.lua):
-- popular/latest/search hit a real separate JSON API, while details/
-- chapter-list/pages parse a __NEXT_DATA__ JSON blob embedded in HTML.
-- Fixtures below mirror the REAL shapes confirmed live against
-- api.comizy.io and comizy.io on 2026-09-22 (field names, nesting, and
-- the details->id/cv->chapters two-hop lookup), but with placeholder
-- title/author/etc. text rather than real scraped copy.
package.path = "koplugin/tachikindle.koplugin/?.lua;" .. package.path

package.preload.socket = function() return { skip = function(_, _, code) return code end } end
package.preload["socket.url"] = function() return { escape = function(s) return s end } end
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
-- MangaBuddy's source_script does not require htmlparser, but
-- tachikindlesource.lua does at module load time -- provide a stub.
package.preload.htmlparser = function()
    return { parse = function() return { select = function() return {} end } end }
end

local JSON = require("json")
local Source = require("tachikindlesource")

local tests = 0
local function test(name, fn)
    fn()
    tests = tests + 1
    print("PASS " .. name)
end

-- Real shape confirmed live: https://api.comizy.io/titles/search?...
local SEARCH_API_BODY = JSON.encode({
    success = true,
    data = {
        items = {
            { name = "Placeholder Title 1", url = "/placeholder-title-1", cover = "https://rx.comizy.io/covers/placeholder1.webp" },
        },
        pagination = { has_next = true, page = 1, total_pages = 999 },
    },
})

-- Real shape confirmed live: __NEXT_DATA__ blob on a manga details page.
local DETAILS_NEXT_DATA = JSON.encode({
    props = {
        pageProps = {
            initialManga = {
                id = "PH0001id",
                cv = 1234567890,
                name = "Placeholder Title 1",
                summary = "Placeholder description.",
                status = "Ongoing",
                genres = { { name = "Fantasy" }, { name = "Action" } },
                authors = { { name = "Placeholder Author" } },
                cover = "https://rx.comizy.io/covers/placeholder1.webp",
            },
        },
    },
})
local DETAILS_HTML = '<html><body><script id="__NEXT_DATA__" type="application/json">'
    .. DETAILS_NEXT_DATA .. '</script></body></html>'

-- Real shape confirmed live: https://api.comizy.io/titles/{id}/chapters?cv={cv}
local CHAPTERS_API_BODY = JSON.encode({
    success = true,
    data = {
        chapters = {
            { name = "Chapter 2", url = "/placeholder-title-1/chapter-2", updated_at = "2026-09-20T00:00:00.000Z" },
            { name = "Chapter 1", url = "/placeholder-title-1/chapter-1", updated_at = "2026-09-10T00:00:00.000Z" },
        },
    },
})

-- Real shape confirmed live: __NEXT_DATA__ blob on a chapter reader page.
local PAGES_NEXT_DATA = JSON.encode({
    props = {
        pageProps = {
            initialChapter = {
                pages = {
                    { url = "https://x1.cmzcdn.org/e/placeholder1.webp" },
                    { url = "https://x2.cmzcdn.org/e/placeholder2.webp" },
                },
            },
        },
    },
})
local PAGES_HTML = '<html><body><script id="__NEXT_DATA__" type="application/json">'
    .. PAGES_NEXT_DATA .. '</script></body></html>'

test("mangabuddy: popular list from JSON search API", function()
    local source = assert(Source:load("extensions/sources/en/mangabuddy.tkext.json"))
    source.fetch = function(_, url)
        if url == "https://api.comizy.io/titles/search?sort=popular&window=week&page=1&limit=24" then
            return SEARCH_API_BODY
        end
        return nil, "missing fixture for " .. url
    end

    local list, err, has_next = source:fetchMangaList("popular", 1, "")
    assert(list, err)
    assert(#list == 1)
    assert(list[1].title == "Placeholder Title 1")
    assert(list[1].url == "https://comizy.io/placeholder-title-1", list[1].url)
    assert(list[1].cover == "https://rx.comizy.io/covers/placeholder1.webp")
    assert(has_next == true)
end)

test("mangabuddy: details parsed from __NEXT_DATA__", function()
    local source = assert(Source:load("extensions/sources/en/mangabuddy.tkext.json"))
    source.fetch = function(_, url)
        if url == "https://comizy.io/placeholder-title-1" then return DETAILS_HTML end
        return nil, "missing fixture for " .. url
    end

    local details, err = source:fetchMangaDetails("https://comizy.io/placeholder-title-1")
    assert(details, err)
    assert(details.title == "Placeholder Title 1")
    assert(details.author == "Placeholder Author")
    assert(details.status == "Ongoing")
    assert(#details.genres == 2)
    assert(details.genres[1] == "Fantasy")
end)

test("mangabuddy: chapter list via two-hop id/cv ajax lookup", function()
    local source = assert(Source:load("extensions/sources/en/mangabuddy.tkext.json"))
    source.fetch = function(_, url)
        if url == "https://comizy.io/placeholder-title-1" then return DETAILS_HTML end
        if url == "https://api.comizy.io/titles/PH0001id/chapters?cv=1234567890" then return CHAPTERS_API_BODY end
        return nil, "missing fixture for " .. url
    end

    local chapters, err = source:fetchChapterList("https://comizy.io/placeholder-title-1")
    assert(chapters, err)
    assert(#chapters == 2)
    assert(chapters[1].title == "Chapter 2")
    assert(chapters[1].url == "https://comizy.io/placeholder-title-1/chapter-2")
    assert(chapters[2].title == "Chapter 1")
end)

test("mangabuddy: page list parsed from chapter __NEXT_DATA__", function()
    local source = assert(Source:load("extensions/sources/en/mangabuddy.tkext.json"))
    source.fetch = function(_, url)
        if url == "https://comizy.io/placeholder-title-1/chapter-1" then return PAGES_HTML end
        return nil, "missing fixture for " .. url
    end

    local pages, err = source:fetchPageList("https://comizy.io/placeholder-title-1/chapter-1")
    assert(pages, err)
    assert(#pages == 2)
    assert(pages[1] == "https://x1.cmzcdn.org/e/placeholder1.webp")
    assert(pages[2] == "https://x2.cmzcdn.org/e/placeholder2.webp")
end)

print(tests .. " mangabuddy tests passed")
