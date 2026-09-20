package.path = "koplugin/tachikindle.koplugin/?.lua;" .. package.path

local definition
local current_body = ""

local function make_node(text, attrs)
    return {
        attributes = attrs or {},
        textonly = function() return text or "" end,
        select = function(self, selector)
            if selector == "span.flex > span" then
                return { make_node("Chapter 1") }
            end
            return {}
        end,
    }
end

package.preload.htmlparser = function()
    return {
        parse = function(body)
            current_body = body
            return {
                select = function(_, selector)
                    if selector == "div[x-data] > a" then
                        if current_body == "has_chapters" then
                            return { make_node(nil, { href = "/chapters/ch-1" }) }
                        end
                        return {}
                    end
                    return {}
                end,
            }
        end,
    }
end
package.preload.socket = function() return { skip = function(_, _, code) return code end } end
package.preload["socket.url"] = function() return { escape = function(s) return s end } end
package.preload.socketutil = function() return { set_timeout = function() end, reset_timeout = function() end } end
package.preload["socket.http"] = function() return { request = function() return 1, 200 end } end
package.preload.ltn12 = function() return { sink = { table = function() return function() end end } } end
package.preload.json = function() return { decode = function() return definition end } end
package.preload.logger = function() return { info = function() end, warn = function() end } end
package.preload.datastorage = function() return { getDataDir = function() return "." end } end
package.preload["libs/libkoreader-lfs"] = function() return {} end

local Source = require("tachikindlesource")
local p = os.tmpname()
local f = assert(io.open(p, "w")); f:write("{}"); f:close()

definition = {
    base_url = "https://weebcentral.com",
    endpoints = { chapter_list = { path = "{manga_url}/full-chapter-list" } },
    selectors = {
        chapter_item = "div[x-data] > a",
        chapter_title = "span.flex > span",
        chapter_url = { sel = "self", attr = "href" },
    },
}

local source = assert(Source:load(p))
local calls = {}
source.fetch = function(_, url)
    calls[#calls + 1] = url
    if url == "https://weebcentral.com/series/abc123/my-series/full-chapter-list" then
        return "stub"
    end
    if url == "https://weebcentral.com/series/abc123/full-chapter-list" then
        return "has_chapters"
    end
    return nil, "unexpected url"
end

local chapters, err = source:fetchChapterList("https://weebcentral.com/series/abc123/my-series")
assert(not err)
assert(#chapters == 1)
assert(chapters[1].title == "Chapter 1")
assert(chapters[1].url == "https://weebcentral.com/chapters/ch-1")
assert(#calls == 2)
assert(calls[1] == "https://weebcentral.com/series/abc123/my-series/full-chapter-list")
assert(calls[2] == "https://weebcentral.com/series/abc123/full-chapter-list")

os.remove(p)
print("WeebCentral chapter URL fallback test PASS")
