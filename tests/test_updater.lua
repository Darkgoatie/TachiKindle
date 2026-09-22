-- Updater unit tests: build-SHA comparison, check-flow against the
-- real GitHub commits API response shape, and error handling. JSON
-- fixture shape below was verified live on 2026-09-22 via:
--   curl "https://api.github.com/repos/Darkgoatie/TachiKindle/commits?sha=test/source-script-format-system&per_page=1"
-- (see tachikindleupdater.lua's module comment: every push to
-- DEV_BRANCH is treated as a new build, compared by commit SHA, not
-- by a manually-bumped VERSION/release tag).
package.path = "koplugin/tachikindle.koplugin/?.lua;" .. package.path

local http_response_body, http_response_code = "{}", 200
package.preload.socket = function() return { skip = function(_, _, code) return code end } end
package.preload.socketutil = function() return { set_timeout = function() end, reset_timeout = function() end } end
package.preload["socket.http"] = function()
    return {
        request = function(r)
            r.sink(http_response_body)
            return 1, http_response_code
        end,
    }
end
package.preload.ltn12 = function()
    return {
        sink = { table = function(t) return function(v) t[#t + 1] = v end end },
        source = { string = function(s) return s end },
    }
end
package.preload.logger = function() return { info = function() end, warn = function() end } end
package.preload.datastorage = function() return { getDataDir = function() return "." end } end
package.preload["libs/libkoreader-lfs"] = function() return {} end
package.preload["ui/widget/infomessage"] = function() return { new = function(_, o) return o end } end
package.preload["ui/widget/buttondialog"] = function() return { new = function(_, o) return o end } end
package.preload["ui/uimanager"] = function()
    return { show = function(_, w) _G.__last_shown = w end, close = function() end }
end
package.preload.util = function() return { makePath = function() end } end
package.preload.gettext = function() return setmetatable({}, { __call = function(_, s) return s end }) end

local Updater = require("tachikindleupdater")

local tests = 0
local function test(name, fn)
    fn()
    tests = tests + 1
    print("PASS " .. name)
end

-- A fake `plugin` object providing httpGet like main.lua's TachiKindle,
-- driven entirely by the module-level http_response_body/code above --
-- matches how test_mangadex_source.lua/test_source_adapters.lua stub
-- the HTTP boundary rather than reimplementing socket internals per test.
local FakePlugin = {}
FakePlugin.__index = FakePlugin
function FakePlugin:httpGet(url)
    self.last_url = url
    if http_response_code ~= 200 then
        return nil, "HTTP error: " .. tostring(http_response_code)
    end
    return http_response_body
end
local function newPlugin() return setmetatable({}, FakePlugin) end

-- Real shape confirmed live against
-- api.github.com/repos/Darkgoatie/TachiKindle/commits?sha=test/source-script-format-system&per_page=1
local REAL_COMMITS_JSON = [[
[
  {
    "sha": "9db004c55961ec0e6f3eead51ca93f91018ef29f",
    "commit": { "message": "Flag Toonily as live-blocked by Cloudflare, like BatCave" },
    "html_url": "https://github.com/Darkgoatie/TachiKindle/commit/9db004c55961ec0e6f3eead51ca93f91018ef29f"
  }
]
]]

test("version compare util: still available for cosmetic/manual use", function()
    assert(Updater.isNewer("1.0.0", "1.0.1") == true)
    assert(Updater.isNewer("1.0.0", "1.0.0") == false)
    assert(Updater.isNewer(nil, "1.0.0") == true)
end)

test("fetchLatest: real commits-API shape parsed into a build entry", function()
    http_response_body, http_response_code = REAL_COMMITS_JSON, 200
    local plugin = newPlugin()
    local latest, err = Updater:fetchLatest(plugin)
    assert(latest, err)
    assert(latest.kind == "commit")
    assert(latest.version == "9db004c")
    assert(latest.sha == "9db004c55961ec0e6f3eead51ca93f91018ef29f")
    assert(latest.zip_url == "https://github.com/Darkgoatie/TachiKindle/archive/9db004c55961ec0e6f3eead51ca93f91018ef29f.zip")
    assert(plugin.last_url:match("/commits%?sha=test/source%-script%-format%-system&per_page=1"))
end)

test("fetchLatest: network failure reports a real error, not a crash", function()
    local orig_httpGet = FakePlugin.httpGet
    FakePlugin.httpGet = function() return nil, "connection refused" end
    local plugin = newPlugin()
    local latest, err = Updater:fetchLatest(plugin)
    FakePlugin.httpGet = orig_httpGet
    assert(latest == nil)
    assert(err and err:match("connection refused"))
end)

test("fetchLatest: malformed commits response is a real error, not a crash", function()
    local orig_httpGet = FakePlugin.httpGet
    FakePlugin.httpGet = function() return [[{ "this": "is not a commit list" }]] end
    local plugin = newPlugin()
    local latest, err = Updater:fetchLatest(plugin)
    FakePlugin.httpGet = orig_httpGet
    assert(latest == nil)
    assert(err and err:match("Unexpected response"))
end)

test("readLocalBuild/writeLocalBuild round-trip via BUILD file", function()
    local tmp_build_path = os.tmpname()
    local orig_buildFilePath = Updater.buildFilePath
    Updater.buildFilePath = function() return tmp_build_path end

    local ok, err = Updater:writeLocalBuild("deadbeefdeadbeefdeadbeefdeadbeefdeadbeef")
    assert(ok, err)
    assert(Updater:readLocalBuild() == "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef")

    Updater.buildFilePath = orig_buildFilePath
    os.remove(tmp_build_path)
end)

test("readLocalBuild: missing BUILD file returns nil, not an error", function()
    local orig_buildFilePath = Updater.buildFilePath
    Updater.buildFilePath = function() return "/nonexistent/path/BUILD" end
    assert(Updater:readLocalBuild() == nil)
    Updater.buildFilePath = orig_buildFilePath
end)

test("checkForUpdates: matching build SHA shows an info message, not a confirm dialog", function()
    http_response_body, http_response_code = REAL_COMMITS_JSON, 200 -- sha 9db004c5...
    local tmp_build_path = os.tmpname()
    local bf = assert(io.open(tmp_build_path, "w")); bf:write("9db004c55961ec0e6f3eead51ca93f91018ef29f"); bf:close()
    local orig_buildFilePath = Updater.buildFilePath
    Updater.buildFilePath = function() return tmp_build_path end

    _G.__last_shown = nil
    Updater:checkForUpdates(newPlugin())
    assert(_G.__last_shown and _G.__last_shown.text:match("up to date"))

    Updater.buildFilePath = orig_buildFilePath
    os.remove(tmp_build_path)
end)

test("checkForUpdates: different build SHA shows a confirm dialog with both actions", function()
    http_response_body, http_response_code = REAL_COMMITS_JSON, 200 -- sha 9db004c5...
    local tmp_build_path = os.tmpname()
    local bf = assert(io.open(tmp_build_path, "w")); bf:write("0000000000000000000000000000000000000"); bf:close()
    local orig_buildFilePath = Updater.buildFilePath
    Updater.buildFilePath = function() return tmp_build_path end

    _G.__last_shown = nil
    Updater:checkForUpdates(newPlugin())
    local shown = _G.__last_shown
    assert(shown and shown.buttons and #shown.buttons == 2)
    assert(shown.buttons[1][1].text == "Not now")
    assert(shown.buttons[2][1].text == "Update now")
    assert(shown.text:match("0000000") and shown.text:match("9db004c"))

    Updater.buildFilePath = orig_buildFilePath
    os.remove(tmp_build_path)
end)

test("checkForUpdates: missing BUILD file (fresh install) shows a confirm dialog", function()
    http_response_body, http_response_code = REAL_COMMITS_JSON, 200
    local orig_buildFilePath = Updater.buildFilePath
    Updater.buildFilePath = function() return "/nonexistent/path/BUILD" end

    _G.__last_shown = nil
    Updater:checkForUpdates(newPlugin())
    local shown = _G.__last_shown
    assert(shown and shown.buttons and #shown.buttons == 2)

    Updater.buildFilePath = orig_buildFilePath
end)

test("checkForUpdates: network failure surfaces as an info message with the error", function()
    local orig_httpGet = FakePlugin.httpGet
    FakePlugin.httpGet = function() return nil, "connection refused" end
    _G.__last_shown = nil
    Updater:checkForUpdates(newPlugin())
    FakePlugin.httpGet = orig_httpGet
    assert(_G.__last_shown and _G.__last_shown.text:match("Update check failed"))
end)

print(tests .. " updater unit tests passed")
