-- MangaDex source_script smoke test: this source is a real JSON REST
-- API (no HTML/selectors), so this test stubs source:fetch() to return
-- synthetic-but-real-shaped JSON fixtures matching what was verified
-- live against https://api.mangadex.org on 2026-09-22 (see
-- extensions/sources/en/mangadex.tkext.json's "verification" block):
--   GET /manga?...                         -> manga search/list
--   GET /manga/{id}?...                     -> manga details
--   GET /manga/{id}/feed?...                -> chapter feed
--   GET /at-home/server/{chapterId}         -> page image server info
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
-- htmlparser is required unconditionally by tachikindlesource.lua even
-- though this source never calls into it; stub it out here so this
-- test doesn't need the real KOReader module on LUA_PATH.
package.preload.htmlparser = function() return { parse = function() return { select = function() return {} end } end } end

local Source = require("tachikindlesource")

local tests = 0
local function test(name, fn)
    fn()
    tests = tests + 1
    print("PASS " .. name)
end

local MANGA_LIST_JSON = [[
{
  "result": "ok",
  "response": "collection",
  "data": [
    {
      "id": "fffbfac3-b7ad-41ee-9581-b4d90ecec941",
      "type": "manga",
      "attributes": {
        "title": { "en": "Grand Blue Dreaming" },
        "altTitles": [ { "ja": "\u3050\u3089\u3093\u3076\u308b" } ],
        "description": { "en": "A new life begins for Kitahara Iori." },
        "status": "ongoing",
        "tags": []
      },
      "relationships": [
        { "id": "cover-uuid-1", "type": "cover_art", "attributes": { "fileName": "cover1.jpg" } }
      ]
    }
  ],
  "total": 1
}
]]

local MANGA_DETAILS_JSON = [[
{
  "result": "ok",
  "response": "entity",
  "data": {
    "id": "fffbfac3-b7ad-41ee-9581-b4d90ecec941",
    "type": "manga",
    "attributes": {
      "title": { "en": "Grand Blue Dreaming" },
      "altTitles": [],
      "description": { "en": "A new life begins for Kitahara Iori." },
      "status": "ongoing",
      "tags": [
        { "id": "tag-1", "attributes": { "name": { "en": "Comedy" } } },
        { "id": "tag-2", "attributes": { "name": { "en": "Slice of Life" } } }
      ]
    },
    "relationships": [
      { "id": "cover-uuid-1", "type": "cover_art", "attributes": { "fileName": "cover1.jpg" } },
      { "id": "author-uuid-1", "type": "author", "attributes": { "name": "Kenji Inoue" } }
    ]
  }
}
]]

local FEED_JSON = [[
{
  "result": "ok",
  "response": "collection",
  "data": [
    {
      "id": "ab6cf572-521a-4c31-86f4-ce89d31a0561",
      "type": "chapter",
      "attributes": {
        "chapter": "1",
        "title": "First Dive",
        "translatedLanguage": "en",
        "publishAt": "2026-01-01T00:00:00+00:00",
        "externalUrl": null,
        "isUnavailable": false
      }
    }
  ],
  "total": 1
}
]]

local AT_HOME_JSON = [[
{
  "result": "ok",
  "baseUrl": "https://cmdxd98sb0x3yprd.mangadex.network",
  "chapter": {
    "hash": "abc123hash",
    "data": [ "1.png", "2.png" ],
    "dataSaver": [ "1-saver.png", "2-saver.png" ]
  }
}
]]

local function load()
    local descriptor_path = "extensions/sources/en/mangadex.tkext.json"
    return assert(Source:load(descriptor_path))
end

test("descriptor loads and dispatches to real source_script", function()
    local source = load()
    assert(source.def.id == "en.mangadex")
    assert(type(source.source_script) == "table")
    assert(type(source.source_script.fetch_manga_list) == "function")
    assert(type(source.source_script.fetch_manga_details) == "function")
    assert(type(source.source_script.fetch_chapter_list) == "function")
    assert(type(source.source_script.fetch_page_list) == "function")
end)

test("fetch_manga_list: popular returns real-shaped list with cover and has_next", function()
    local source = load()
    local seen_url
    source.fetch = function(_, url)
        seen_url = url
        return MANGA_LIST_JSON
    end
    local list, err, has_next = source:fetchMangaList("popular", 1, "")
    assert(list, err)
    assert(seen_url:match("^https://api%.mangadex%.org/manga%?"))
    assert(seen_url:match("order%[followedCount%]=desc"))
    assert(#list == 1)
    assert(list[1].title == "Grand Blue Dreaming")
    assert(list[1].url == "https://api.mangadex.org/title/fffbfac3-b7ad-41ee-9581-b4d90ecec941")
    assert(list[1].cover == "https://uploads.mangadex.org/covers/fffbfac3-b7ad-41ee-9581-b4d90ecec941/cover1.jpg")
    -- total=1, offset=0, #list=1 -> not more pages
    assert(has_next == false)
end)

test("fetch_manga_list: search includes title param when query given", function()
    local source = load()
    local seen_url
    source.fetch = function(_, url)
        seen_url = url
        return MANGA_LIST_JSON
    end
    local list, err = source:fetchMangaList("search", 1, "Grand Blue")
    assert(list, err)
    assert(seen_url:match("title=Grand%%20Blue") or seen_url:match("title=Grand%%2BBlue") or seen_url:match("title=Grand"))
end)

test("fetch_manga_details: real fields including author, genres, description", function()
    local source = load()
    source.fetch = function(_, url)
        assert(url == "https://api.mangadex.org/manga/fffbfac3-b7ad-41ee-9581-b4d90ecec941?includes[]=cover_art&includes[]=author&includes[]=artist")
        return MANGA_DETAILS_JSON
    end
    local details, err = source:fetchMangaDetails("https://api.mangadex.org/title/fffbfac3-b7ad-41ee-9581-b4d90ecec941")
    assert(details, err)
    assert(details.title == "Grand Blue Dreaming")
    assert(details.author == "Kenji Inoue")
    assert(details.status == "ongoing")
    assert(#details.genres == 2 and details.genres[1] == "Comedy")
    assert(details.cover == "https://uploads.mangadex.org/covers/fffbfac3-b7ad-41ee-9581-b4d90ecec941/cover1.jpg")
end)

test("fetch_manga_details: malformed manga_url is a real error, not a crash", function()
    local source = load()
    local details, err = source:fetchMangaDetails("not-a-real-url")
    assert(details == nil and err:match("could not parse MangaDex manga id"))
end)

test("fetch_chapter_list: real feed shape, filters unavailable/external chapters", function()
    local source = load()
    source.fetch = function(_, url)
        assert(url:match("^https://api%.mangadex%.org/manga/fffbfac3%-b7ad%-41ee%-9581%-b4d90ecec941/feed%?"))
        assert(url:match("translatedLanguage%[%]=en"))
        return FEED_JSON
    end
    local chapters, err = source:fetchChapterList("https://api.mangadex.org/title/fffbfac3-b7ad-41ee-9581-b4d90ecec941")
    assert(chapters, err)
    assert(#chapters == 1)
    assert(chapters[1].title == "Chapter 1: First Dive")
    assert(chapters[1].url == "https://api.mangadex.org/chapter/ab6cf572-521a-4c31-86f4-ce89d31a0561")
    assert(chapters[1].date == "2026-01-01T00:00:00+00:00")
end)

test("fetch_page_list: real at-home/server shape, builds full-resolution image URLs", function()
    local source = load()
    source.fetch = function(_, url)
        assert(url == "https://api.mangadex.org/at-home/server/ab6cf572-521a-4c31-86f4-ce89d31a0561")
        return AT_HOME_JSON
    end
    local pages, err = source:fetchPageList("https://api.mangadex.org/chapter/ab6cf572-521a-4c31-86f4-ce89d31a0561")
    assert(pages, err)
    assert(#pages == 2)
    assert(pages[1] == "https://cmdxd98sb0x3yprd.mangadex.network/data/abc123hash/1.png")
    assert(pages[2] == "https://cmdxd98sb0x3yprd.mangadex.network/data/abc123hash/2.png")
end)

test("fetch_page_list: chapter with no hosted pages (licensed/external) is an explicit error", function()
    -- Real observed live behavior: an external/licensed chapter returns
    -- result=ok with hash="" and empty data/dataSaver arrays, not an
    -- HTTP error. The script must treat this as a real failure, not a
    -- fabricated successful empty chapter.
    local source = load()
    source.fetch = function()
        return [[{"result":"ok","baseUrl":"https://cmdxd98sb0x3yprd.mangadex.network","chapter":{"hash":"","data":[],"dataSaver":[]}}]]
    end
    local pages, err = source:fetchPageList("https://api.mangadex.org/chapter/ab6cf572-521a-4c31-86f4-ce89d31a0561")
    assert(pages == nil and err:match("no page images"))
end)

test("HTTP failure and MangaDex API error responses are real errors, not fabricated success", function()
    local source = load()
    source.fetch = function() return nil, "connection refused" end
    local list, err = source:fetchMangaList("popular", 1, "")
    assert(list == nil and err:match("HTTP request failed"))

    source.fetch = function()
        return [[{"result":"error","errors":[{"detail":"rate limited"}]}]]
    end
    local list2, err2 = source:fetchMangaList("popular", 1, "")
    assert(list2 == nil and err2:match("rate limited"))
end)

print(tests .. " MangaDex source_script smoke tests passed")
