-- Test for MangaKatana (en.mangakatana). Popular/details/chapters use
-- the generic selector engine (mocked htmlparser, same technique as
-- test_selector_extensions_smoke.lua); page-image extraction is real,
-- unmocked regex logic run against a raw HTML fixture shaped exactly
-- like a real fetched chapter page (see mangakatana.tkext.json's
-- "verification" block for the live-fetch details this mirrors).
package.path = "koplugin/tachikindle.koplugin/?.lua;" .. package.path

package.preload.socket = function() return { skip = function(_, _, code) return code end } end
package.preload["socket.url"] = function()
    return {
        escape = function(s) return (tostring(s):gsub("([^%w])", function(c) return string.format("%%%02X", string.byte(c)) end)) end,
    }
end
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

local function leaf(attrs, text)
    return { attributes = attrs or {}, textonly = function() return text or "" end, select = function() return {} end }
end

-- Real card markup shape confirmed live 2026-09-22 against
-- https://mangakatana.com/manga/page/1 (div#book_list > div.item).
package.preload.htmlparser = function()
    return {
        parse = function(body)
            if body == "POPULAR" then
                return {
                    select = function(_, selector)
                        if selector == "div#book_list > div.item" then
                            return {
                                {
                                    attributes = {},
                                    textonly = function() return "" end,
                                    select = function(_, s)
                                        if s == "div.text > h3 > a" then
                                            return { leaf({ href = "https://mangakatana.com/manga/aishiteru-uso-dakedo.10797" }, '"Aishiteru", Uso Dakedo.') }
                                        end
                                        if s == "img" then
                                            return { leaf({ src = "https://mangakatana.com/imgs/cover/04e/36/39bbc.jpg" }) }
                                        end
                                        return {}
                                    end,
                                },
                            }
                        end
                        if selector == "a.next.page-numbers" then return { leaf({}, "Next") } end
                        return {}
                    end,
                }
            end
            if body == "DETAILS" then
                return {
                    select = function(_, selector)
                        if selector == "h1.heading" then return { leaf({}, '"Aishiteru", Uso Dakedo.') } end
                        if selector == ".author" then return { leaf({}, "Mitsuki Miko") } end
                        if selector == ".value.status" then return { leaf({}, "Ongoing") } end
                        if selector == ".genres > a" then return { leaf({}, "Romance"), leaf({}, "School Life") } end
                        if selector == ".summary > p" then return { leaf({}, "From Chibi Manga: He's a liar.") } end
                        if selector == "div.media div.cover img" then return { leaf({ src = "https://mangakatana.com/imgs/cover/04e/36/39bbc.jpg" }) } end
                        if selector == "div.chapters tr" then
                            return {
                                {
                                    attributes = {}, textonly = function() return "" end,
                                    select = function(_, s)
                                        if s == "div.chapter a" then
                                            return { leaf({ href = "https://mangakatana.com/manga/aishiteru-uso-dakedo.10797/c2" }, "Chapter 2: Majou wa Geboku ni Koi wo Suru") }
                                        end
                                        if s == ".update_time" then return { leaf({}, "Aug-03-2018") } end
                                        return {}
                                    end,
                                },
                                {
                                    attributes = {}, textonly = function() return "" end,
                                    select = function(_, s)
                                        if s == "div.chapter a" then
                                            return { leaf({ href = "https://mangakatana.com/manga/aishiteru-uso-dakedo.10797/c1" }, "Chapter 1 : Story 1") }
                                        end
                                        if s == ".update_time" then return { leaf({}, "Feb-25-2018") } end
                                        return {}
                                    end,
                                },
                            }
                        end
                        return {}
                    end,
                }
            end
            return { select = function() return {} end }
        end,
    }
end

local Source = require("tachikindlesource")

-- Real reader-page shape independently re-confirmed live 2026-09-22
-- against https://mangakatana.com/manga/aishiteru-uso-dakedo.10797/c1
-- (HTTP 200, 55217 bytes): every <img data-src="#"> is a dead
-- placeholder (51 of them); the real image URLs live in an inline
-- <script> as `var thzq=['url', ...]`, matched via the same
-- 'data-src'-marker regex the upstream Kotlin extension uses.
local CHAPTER_HTML = [[
<div id="imgs" data-alt="Chapter 1">
<div class="uk-grid uk-grid-collapse">
<div id="page1" class="wrap_img uk-width-1-1" data-pages="2"><img data-src="#" alt=""/></div>
<div id="page2" class="wrap_img uk-width-1-1" data-pages="2"><img data-src="#" alt=""/></div>
</div>
</div>
<script>
images('data-src', thzq);
var thzq=['https://i1.mangakatana.com/token/d5d12a1.../0.jpg','https://i1.mangakatana.com/token/aa6700.../1.jpg'];
</script>
]]

local tests = 0
local function test(name, fn)
    fn()
    tests = tests + 1
    print("PASS " .. name)
end

test("mangakatana: popular list + details + chapters + page images", function()
    local source = assert(Source:load("extensions/sources/en/mangakatana.tkext.json"))

    local fixtures = {
        ["https://mangakatana.com/manga/page/1"] = "POPULAR",
        ["https://mangakatana.com/manga/aishiteru-uso-dakedo.10797"] = "DETAILS",
        ["https://mangakatana.com/manga/aishiteru-uso-dakedo.10797/c1"] = CHAPTER_HTML,
    }
    source.fetch = function(_, url)
        local body = fixtures[url]
        if body then return body end
        return nil, "missing fixture for " .. url
    end
    source.savePageListCache = function() return true end

    local list, list_err, has_next = source:fetchMangaList("popular", 1, "")
    assert(list, list_err)
    assert(#list == 1, "expected 1 popular item, got " .. tostring(#list))
    assert(list[1].title == '"Aishiteru", Uso Dakedo.', tostring(list[1].title))
    assert(list[1].url == "https://mangakatana.com/manga/aishiteru-uso-dakedo.10797", tostring(list[1].url))
    assert(list[1].cover == "https://mangakatana.com/imgs/cover/04e/36/39bbc.jpg", tostring(list[1].cover))
    assert(has_next == true)

    local details, details_err = source:fetchMangaDetails(list[1].url)
    assert(details, details_err)
    assert(details.title == '"Aishiteru", Uso Dakedo.', tostring(details.title))
    assert(details.author == "Mitsuki Miko", tostring(details.author))
    assert(details.status == "Ongoing", tostring(details.status))
    assert(#details.genres == 2, #details.genres)

    local chapters, chapter_err = source:fetchChapterList(list[1].url)
    assert(chapters, chapter_err)
    assert(#chapters == 2, #chapters)
    assert(chapters[1].title == "Chapter 2: Majou wa Geboku ni Koi wo Suru", chapters[1].title)
    assert(chapters[1].url == "https://mangakatana.com/manga/aishiteru-uso-dakedo.10797/c2", chapters[1].url)

    local pages, page_err = source:fetchPageList("https://mangakatana.com/manga/aishiteru-uso-dakedo.10797/c1")
    assert(pages, page_err)
    assert(#pages == 2, #pages)
    assert(pages[1] == "https://i1.mangakatana.com/token/d5d12a1.../0.jpg", pages[1])
    assert(pages[2] == "https://i1.mangakatana.com/token/aa6700.../1.jpg", pages[2])

    print("SMOKE OK mangakatana")
end)

print(tests .. " mangakatana source tests passed")
