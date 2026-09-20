package.path = "koplugin/tachikindle.koplugin/?.lua;" .. package.path

local definition
local call_count = 0
local sleep_calls = {}

package.preload.htmlparser = function() return { parse = function() return { select = function() return {} end } end } end
package.preload.socket = function()
    return {
        skip = function(_, _, code) return code end,
        sleep = function(sec) table.insert(sleep_calls, sec) end,
    }
end
package.preload["socket.url"] = function() return { escape = function(s) return s end } end
package.preload.socketutil = function() return { set_timeout = function() end, reset_timeout = function() end } end
package.preload["socket.http"] = function()
    return {
        request = function(r)
            call_count = call_count + 1
            if call_count < 3 then
                return nil, "Cannot assign requested address"
            end
            r.sink("ok")
            return 1, 200
        end,
    }
end
package.preload.ltn12 = function()
    return {
        sink = { table = function(t) return function(v) t[#t + 1] = v end end },
        source = { string = function(s) return s end },
    }
end
package.preload.json = function() return { decode = function() return definition end } end
package.preload.logger = function() return { info = function() end, warn = function() end } end
package.preload.datastorage = function() return { getDataDir = function() return "." end } end
package.preload["libs/libkoreader-lfs"] = function() return {} end

local Source = require("tachikindlesource")

local p = os.tmpname()
local f = assert(io.open(p, "w"))
f:write("{}")
f:close()

definition = {
    base_url = "https://example.test",
    endpoints = { manga_details = { path = "{manga_url}" } },
    selectors = {},
}

local source = assert(Source:load(p))
local body, err = source:fetch("https://example.test/a")
assert(body == "ok")
assert(err == nil)
assert(call_count == 3)
assert(#sleep_calls == 2)
assert(sleep_calls[1] == 0.4 and sleep_calls[2] == 0.8)

os.remove(p)
print("HTTP retry test PASS")
