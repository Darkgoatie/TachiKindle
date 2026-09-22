-- Comick source_script smoke test: Comick is a hybrid (real JSON REST
-- API for lists/chapter-list, real HTML pages with embedded JSON for
-- details/pages), so this stubs source:fetch() to return synthetic-
-- but-real-shaped JSON/HTML fixtures matching what was verified live
-- against https://comick.live on 2026-09-22 (see
-- extensions/sources/en/comick.tkext.json's "verification" block):
--   GET /api/comics/top?days=7&type=follow      -> browse JSON
--   GET /api/comics/{slug}/chapter-list?lang=en -> chapter JSON
--   GET /comic/{slug}                           -> HTML w/ #comic-data
--   GET /comic/{slug}/{hid}-chapter-{n}-{lang}  -> HTML w/ #sv-data
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

local TOP_JSON = [[
{
  "data": [
    {
      "id": 142276,
      "title": "World Destruction War",
      "slug": "world-destruction-war",
      "content_rating": "safe",
      "genres": [250, 252, 244, 245, 283],
      "demographic": null,
      "chapter_count": null,
      "created_at": null,
      "country": "",
      "default_thumbnail": "https://cdn1.comicknew.pictures/world-destruction-war/covers/40bb6193.webp"
    }
  ]
}
]]

local COMIC_DATA_HTML = [[
<html><body><script id="comic-data">
        {"id":142276,"hid":"RQNt8JF","title":"World Destruction War","country":"","origination":"","status":1,"links":[],"last_chapter":7,"chapter_count":8,"demographic_name":"","user_follow_count":0,"follow_rank":0,"follow_count":0,"desc":"World Destruction War summary: strongest beings gathered.","parsed":"World Destruction War summary: strongest beings gathered.","slug":"world-destruction-war","year":0,"bayesian_rating":"0.00","rating_count":0,"content_rating":"safe","translation_completed":false,"noindex":false,"adsense":true,"md_titles":[],"md_comic_md_genres":[{"md_genres":{"name":"Action","slug":"action","group":"Genre"}},{"md_genres":{"name":"Fantasy","slug":"fantasy","group":"Genre"}}],"default_thumbnail":"https://cdn1.comicknew.pictures/world-destruction-war/covers/40bb6193.webp"}
</script></body></html>
]]

local CHAPTER_LIST_JSON = [[
{
  "data": [
    {
      "id": 10683143,
      "hid": "RVbE7LG",
      "chap": "7",
      "title": "",
      "vol": null,
      "lang": "en",
      "group_name": ["Mangakakalot"],
      "created_at": "2026-09-20T02:01:41.000000Z",
      "updated_at": "2026-09-20T01:12:53.000000Z"
    }
  ],
  "pagination": { "current_page": 1, "per_page": 60, "last_page": 1, "total": 1 }
}
]]

local SV_DATA_HTML = [[
<html><body><script id="sv-data">
        {"chapter":{"id":10683143,"chap":"7","vol":null,"title":"","hid":"RVbE7LG","group_name":"Mangakakalot","created_at":"2026-09-20T02:01:41.000000Z","lang":"en","images":[{"h":1024,"w":1532,"name":"image 0","s":null,"url":"https://cdn1.comicknew.pictures/world-destruction-war/0_7/en/64be7829/0.webp","optimized":null},{"h":1500,"w":900,"name":"image 1","s":null,"url":"https://cdn1.comicknew.pictures/world-destruction-war/0_7/en/64be7829/1.webp","optimized":null}]}}
</script></body></html>
]]

local function load()
    local descriptor_path = "extensions/sources/en/comick.tkext.json"
    return assert(Source:load(descriptor_path))
end

test("descriptor loads and dispatches to real source_script", function()
    local source = load()
    assert(source.def.id == "en.comick")
    assert(type(source.source_script) == "table")
    assert(type(source.source_script.fetch_manga_list) == "function")
    assert(type(source.source_script.fetch_manga_details) == "function")
    assert(type(source.source_script.fetch_chapter_list) == "function")
    assert(type(source.source_script.fetch_page_list) == "function")
end)

test("fetch_manga_list: popular uses real /api/comics/top and maps fields", function()
    local source = load()
    local seen_url
    source.fetch = function(_, url)
        seen_url = url
        return TOP_JSON
    end
    local list, err, has_next = source:fetchMangaList("popular", 1, "")
    assert(list, err)
    assert(seen_url:match("^https://comick%.live/api/comics/top%?"))
    assert(seen_url:match("days=7"))
    assert(seen_url:match("type=follow"))
    assert(#list == 1)
    assert(list[1].title == "World Destruction War")
    assert(list[1].url == "https://comick.live/comic/world-destruction-war")
    assert(list[1].cover == "https://cdn1.comicknew.pictures/world-destruction-war/covers/40bb6193.webp")
    assert(has_next == true) -- page 1 of a 6-page cycle
end)

test("fetch_manga_list: page cycles through days/type combinations", function()
    local source = load()
    local seen_url
    source.fetch = function(_, url) seen_url = url; return TOP_JSON end
    source:fetchMangaList("popular", 4, "")
    assert(seen_url:match("days=7"))
    assert(seen_url:match("type=most_follow_new"))
    local _, _, has_next = source:fetchMangaList("popular", 6, "")
    assert(has_next == false)
end)

test("fetch_manga_details: real #comic-data embedded JSON extraction", function()
    local source = load()
    source.fetch = function(_, url)
        assert(url == "https://comick.live/comic/world-destruction-war")
        return COMIC_DATA_HTML
    end
    local details, err = source:fetchMangaDetails("https://comick.live/comic/world-destruction-war")
    assert(details, err)
    assert(details.title == "World Destruction War")
    assert(details.status == "ongoing")
    assert(#details.genres == 2 and details.genres[1] == "Action")
    assert(details.cover == "https://cdn1.comicknew.pictures/world-destruction-war/covers/40bb6193.webp")
    assert(details.description:match("strongest beings"))
end)

test("fetch_manga_details: malformed manga_url is a real error, not a crash", function()
    local source = load()
    local details, err = source:fetchMangaDetails("not-a-real-url")
    assert(details == nil and err:match("could not parse Comick manga slug"))
end)

test("fetch_chapter_list: real chapter-list JSON shape, builds real chapter_url", function()
    local source = load()
    source.fetch = function(_, url)
        assert(url:match("^https://comick%.live/api/comics/world%-destruction%-war/chapter%-list%?"))
        assert(url:match("lang=en"))
        return CHAPTER_LIST_JSON
    end
    local chapters, err = source:fetchChapterList("https://comick.live/comic/world-destruction-war")
    assert(chapters, err)
    assert(#chapters == 1)
    assert(chapters[1].title == "Chapter 7")
    assert(chapters[1].url == "https://comick.live/comic/world-destruction-war/RVbE7LG-chapter-7-en")
    assert(chapters[1].date == "2026-09-20T02:01:41.000000Z")
end)

test("fetch_page_list: real #sv-data embedded JSON, full-res image URLs", function()
    local source = load()
    source.fetch = function(_, url)
        assert(url == "https://comick.live/comic/world-destruction-war/RVbE7LG-chapter-7-en")
        return SV_DATA_HTML
    end
    local pages, err = source:fetchPageList("https://comick.live/comic/world-destruction-war/RVbE7LG-chapter-7-en")
    assert(pages, err)
    assert(#pages == 2)
    assert(pages[1] == "https://cdn1.comicknew.pictures/world-destruction-war/0_7/en/64be7829/0.webp")
    assert(pages[2] == "https://cdn1.comicknew.pictures/world-destruction-war/0_7/en/64be7829/1.webp")
end)

test("fetch_page_list: missing #sv-data script tag is a real error, not a crash", function()
    local source = load()
    source.fetch = function() return "<html><body>no embedded data here</body></html>" end
    local pages, err = source:fetchPageList("https://comick.live/comic/world-destruction-war/RVbE7LG-chapter-7-en")
    assert(pages == nil and err:match("could not find #sv%-data"))
end)

test("HTTP failure is a real error, not fabricated success", function()
    local source = load()
    source.fetch = function() return nil, "connection refused" end
    local list, err = source:fetchMangaList("popular", 1, "")
    assert(list == nil and err:match("HTTP request failed"))
end)

print(tests .. " Comick source_script smoke tests passed")
