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

local function weeb_list_item(title, href, cover)
    return {
        attributes = { href = href },
        textonly = function() return "" end,
        select = function(_, selector)
            if selector == "div:not([class])" then return { text_node(title) } end
            if selector == "img" then return { { attributes = { src = cover }, textonly = function() return "" end, select = function() return {} end } } end
            return {}
        end,
    }
end

local function weeb_chapter_item(title, href, date)
    return {
        attributes = { href = href },
        textonly = function() return "" end,
        select = function(_, selector)
            if selector == "span.flex > span" then return { text_node(title) } end
            if selector == "time" then return { text_node(date) } end
            return {}
        end,
    }
end

local function madara_list_item(title, href, cover)
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

local function madara_chapter_item(title, href, date)
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
            if body == "WB_LIST" then
                return {
                    select = function(_, selector)
                        if selector == "article > section > a" then
                            return {
                                weeb_list_item("WB Title 1", "https://weebcentral.com/series/wb-1/title", "https://weebcentral.com/covers/wb-1.jpg"),
                            }
                        end
                        if selector == "button" then return { text_node("next") } end
                        return {}
                    end,
                }
            end
            if body == "WB_DETAILS" then
                return {
                    select = function(_, selector)
                        if selector == "section[x-data] > section h1" then return { text_node("WB Title 1") } end
                        if selector == "ul > li strong" then return { text_node("WB Author") } end
                        if selector == "li p" then return { text_node("WB Description") } end
                        if selector == "ul > li a" then return { text_node("Ongoing"), text_node("Action") } end
                        if selector == "section[x-data] img" then return { { attributes = { src = "https://weebcentral.com/covers/wb-1.jpg" }, textonly = function() return "" end, select = function() return {} end } } end
                        return {}
                    end,
                }
            end
            if body == "WB_CHAPTERS" then
                return {
                    select = function(_, selector)
                        if selector == "div[x-data] > a" then
                            return {
                                weeb_chapter_item("Chapter 1", "https://weebcentral.com/chapters/wb-1-ch1", "2026-09-21T00:00:00+00:00"),
                            }
                        end
                        return {}
                    end,
                }
            end
            if body == "WB_PAGES" then
                return {
                    select = function(_, selector)
                        if selector == "section img" then
                            return {
                                { attributes = { src = "https://weebcentral.com/pages/wb-1-1.jpg" }, textonly = function() return "" end, select = function() return {} end },
                                { attributes = { src = "https://weebcentral.com/pages/wb-1-2.jpg" }, textonly = function() return "" end, select = function() return {} end },
                            }
                        end
                        return {}
                    end,
                }
            end

            if body == "MADARA_LIST" then
                return {
                    select = function(_, selector)
                        if selector == "div.page-item-detail" then
                            return {
                                madara_list_item("Madara Title 1", "https://REPLACE_WITH_REAL_SITE/manga/madara-1/", "https://REPLACE_WITH_REAL_SITE/covers/madara-1.jpg"),
                            }
                        end
                        if selector == "a.nextpostslink" then return { text_node("next") } end
                        return {}
                    end,
                }
            end
            if body == "MADARA_DETAILS" then
                return {
                    select = function(_, selector)
                        if selector == "div.post-title h1" then return { text_node("Madara Title 1") } end
                        if selector == "div.author-content > a" then return { text_node("Madara Author") } end
                        if selector == "div.description-summary div.summary__content" then return { text_node("Madara Description") } end
                        if selector == "div.summary-content" then return { text_node("Ongoing") } end
                        if selector == "div.genres-content a" then return { text_node("Fantasy"), text_node("Action") } end
                        if selector == "div.summary_image img" then return { { attributes = { ["data-src"] = "https://REPLACE_WITH_REAL_SITE/covers/madara-1.jpg" }, textonly = function() return "" end, select = function() return {} end } } end
                        return {}
                    end,
                }
            end
            if body == "MADARA_CHAPTERS" then
                return {
                    select = function(_, selector)
                        if selector == "li.wp-manga-chapter" then
                            return {
                                madara_chapter_item("Chapter 1", "https://REPLACE_WITH_REAL_SITE/manga/madara-1/chapter-1/", "September 21, 2026"),
                            }
                        end
                        return {}
                    end,
                }
            end
            if body == "MADARA_PAGES" then
                return {
                    select = function(_, selector)
                        if selector == "div.page-break img" then
                            return {
                                { attributes = { ["data-src"] = "https://REPLACE_WITH_REAL_SITE/pages/madara-1-1.jpg" }, textonly = function() return "" end, select = function() return {} end },
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

-- WeebCentral's descriptor uses a downloadable-form source_script
-- ("WeebCentral.lua"), which the runtime loads via loadfile() from
-- the installed scripts dir rather than require(). Mirror what the
-- real download flow does: copy the repo's bundled copy of the
-- script into that scratch location before loading the descriptor.
local function installBundledScript(name)
    local scripts_dir = Source.scriptsDir()
    os.execute('mkdir -p "' .. scripts_dir .. '" 2>/dev/null')
    local src_path = "koplugin/tachikindle.koplugin/sources/en/" .. name
    local sf = assert(io.open(src_path, "r"))
    local body = sf:read("*a")
    sf:close()
    local dest_path = Source.installedScriptPath(name)
    local df = assert(io.open(dest_path, "w"))
    df:write(body)
    df:close()
end

installBundledScript("WeebCentral.lua")
installBundledScript("BatCave.lua")

local tests = 0
local function test(name, fn)
    fn()
    tests = tests + 1
    print("PASS " .. name)
end

local function run_smoke(name, descriptor_path, fixtures)
    local source = assert(Source:load(descriptor_path))

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
    assert(#list > 0)
    assert(list[1].title and list[1].title ~= "")
    assert(list[1].url and list[1].url:match("^https?://"))
    assert(has_next == true)

    local details, details_err = source:fetchMangaDetails(list[1].url)
    assert(details, details_err)
    assert(details.title and details.title ~= "")
    assert(type(details.genres) == "table")

    local chapters, chapter_err = source:fetchChapterList(list[1].url)
    assert(chapters, chapter_err)
    assert(#chapters > 0)
    assert(chapters[1].title and chapters[1].title ~= "")
    assert(chapters[1].url and chapters[1].url:match("^https?://"))

    local pages, page_err = source:fetchPageList(chapters[1].url)
    assert(pages, page_err)
    assert(#pages > 0)
    assert(pages[1]:match("^https?://"))

    print("SMOKE OK " .. name)
end

test("selector extension smoke: weebcentral content+chapters+pages", function()
    run_smoke(
        "weebcentral",
        "extensions/sources/en/weebcentral.tkext.json",
        {
            ["https://weebcentral.com/search/data?text=&limit=32&offset=0&display_mode=Full+Display&sort=Popularity"] = "WB_LIST",
            ["https://weebcentral.com/series/wb-1/title"] = "WB_DETAILS",
            ["https://weebcentral.com/series/wb-1/title/full-chapter-list"] = "WB_CHAPTERS",
            ["https://weebcentral.com/chapters/wb-1-ch1/images?is_prev=False&reading_style=long_strip"] = "WB_PAGES",
        }
    )
end)

test("selector extension smoke: madara_generic content+chapters+pages", function()
    run_smoke(
        "madara_generic",
        "extensions/sources/en/madara_generic.tkext.json",
        {
            ["https://REPLACE_WITH_REAL_SITE/manga/?m_orderby=views&page=1"] = "MADARA_LIST",
            ["https://REPLACE_WITH_REAL_SITE/manga/madara-1/"] = { "MADARA_DETAILS", "MADARA_CHAPTERS" },
            ["https://REPLACE_WITH_REAL_SITE/manga/madara-1/chapter-1/"] = "MADARA_PAGES",
        }
    )
end)

print(tests .. " selector extension smoke tests passed")
