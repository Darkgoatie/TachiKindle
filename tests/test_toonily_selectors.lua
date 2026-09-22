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

local function text_node(value)
    return {
        attributes = {},
        textonly = function() return value end,
        select = function() return {} end,
    }
end

-- Toonily uses the standard Madara theme markup (same list-item/chapter
-- classes as extensions/sources/en/madara_generic.tkext.json), so these
-- fixture builders mirror madara_list_item/madara_chapter_item in
-- tests/test_selector_extensions_smoke.lua -- structural markup only,
-- no real page/panel content.
local function toonily_list_item(title, href, cover)
    return {
        attributes = {},
        textonly = function() return "" end,
        select = function(_, selector)
            if selector == ".post-title a" then
                return {
                    {
                        attributes = { href = href },
                        textonly = function() return title end,
                        select = function() return {} end,
                    },
                }
            end
            if selector == "img" then
                return {
                    {
                        attributes = { ["data-src"] = cover },
                        textonly = function() return "" end,
                        select = function() return {} end,
                    },
                }
            end
            return {}
        end,
    }
end

local function toonily_chapter_item(title, href, date)
    return {
        attributes = {},
        textonly = function() return "" end,
        select = function(_, selector)
            if selector == "a" then
                return {
                    {
                        attributes = { href = href },
                        textonly = function() return title end,
                        select = function() return {} end,
                    },
                }
            end
            if selector == "span.chapter-release-date" then return { text_node(date) } end
            return {}
        end,
    }
end

package.preload.htmlparser = function()
    return {
        parse = function(body)
            if body == "TOONILY_LIST" then
                return {
                    select = function(_, selector)
                        if selector == "div.page-item-detail.manga" then
                            return {
                                toonily_list_item(
                                    "The Beginning After the End",
                                    "https://toonily.com/serie/the-beginning-after-the-end-ea2130e6/",
                                    "https://toonily.com/covers/tbate.jpg"
                                ),
                            }
                        end
                        if selector == "a.nextpostslink" then return { text_node("next") } end
                        return {}
                    end,
                }
            end
            if body == "TOONILY_DETAILS" then
                return {
                    select = function(_, selector)
                        if selector == "div.post-title h1" then return { text_node("The Beginning After the End") } end
                        if selector == "div.author-content > a" then return { text_node("TurtleMe") } end
                        if selector == "div.summary__content" then return { text_node("Description placeholder") } end
                        if selector == "div.summary-content" then return { text_node("Ongoing") } end
                        if selector == "div.genres-content a" then return { text_node("Fantasy"), text_node("Action") } end
                        if selector == "div.summary_image img" then
                            return {
                                {
                                    attributes = { ["data-src"] = "https://toonily.com/covers/tbate.jpg" },
                                    textonly = function() return "" end,
                                    select = function() return {} end,
                                },
                            }
                        end
                        return {}
                    end,
                }
            end
            if body == "TOONILY_CHAPTERS" then
                return {
                    select = function(_, selector)
                        if selector == "li.wp-manga-chapter" then
                            return {
                                toonily_chapter_item(
                                    "Chapter 243 - Mission Complete",
                                    "https://toonily.com/serie/the-beginning-after-the-end-ea2130e6/chapter-243/",
                                    "Jul 10, 26"
                                ),
                            }
                        end
                        return {}
                    end,
                }
            end
            if body == "TOONILY_PAGES" then
                return {
                    select = function(_, selector)
                        if selector == "div.page-break img" then
                            return {
                                {
                                    attributes = { ["data-src"] = "https://toonily.com/pages/tbate-243-1.jpg" },
                                    textonly = function() return "" end,
                                    select = function() return {} end,
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

local tests = 0
local function test(name, fn)
    fn()
    tests = tests + 1
    print("PASS " .. name)
end

test("toonily selectors: content+chapters+pages", function()
    local source = assert(Source:load("extensions/sources/en/toonily.tkext.json"))

    local fixtures = {
        ["https://toonily.com/webtoons?m_orderby=views&page=1"] = "TOONILY_LIST",
        ["https://toonily.com/serie/the-beginning-after-the-end-ea2130e6/"] = { "TOONILY_DETAILS", "TOONILY_CHAPTERS" },
        ["https://toonily.com/serie/the-beginning-after-the-end-ea2130e6/chapter-243/"] = "TOONILY_PAGES",
    }

    source.fetch = function(_, url)
        local body = fixtures[url]
        if type(body) == "table" then
            local next_body = table.remove(body, 1)
            if next_body then return next_body end
        elseif body then
            return body
        end
        return nil, "missing fixture for " .. url
    end
    source.savePageListCache = function() return true end

    local list, list_err, has_next = source:fetchMangaList("popular", 1, "")
    assert(list, list_err)
    assert(#list == 1)
    assert(list[1].title == "The Beginning After the End")
    assert(list[1].url == "https://toonily.com/serie/the-beginning-after-the-end-ea2130e6/")
    assert(has_next == true)

    local details, details_err = source:fetchMangaDetails(list[1].url)
    assert(details, details_err)
    assert(details.title == "The Beginning After the End")
    assert(details.author == "TurtleMe")
    assert(type(details.genres) == "table")
    assert(#details.genres == 2)

    local chapters, chapter_err = source:fetchChapterList(list[1].url)
    assert(chapters, chapter_err)
    assert(#chapters == 1)
    assert(chapters[1].title == "Chapter 243 - Mission Complete")
    assert(chapters[1].url == "https://toonily.com/serie/the-beginning-after-the-end-ea2130e6/chapter-243/")

    local pages, page_err = source:fetchPageList(chapters[1].url)
    assert(pages, page_err)
    assert(#pages == 1)
    assert(pages[1] == "https://toonily.com/pages/tbate-243-1.jpg")

    print("SMOKE OK toonily")
end)

print(tests .. " toonily selector tests passed")
