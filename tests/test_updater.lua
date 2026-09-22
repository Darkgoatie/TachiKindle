-- Updater unit tests: version comparison, check-flow against the
-- real GitHub API response shapes, and error handling. JSON fixture
-- shapes below were verified live on 2026-09-22 via:
--   curl https://api.github.com/repos/Darkgoatie/TachiKindle/releases/latest
--   curl "https://api.github.com/repos/Darkgoatie/TachiKindle/commits?per_page=1"
-- (see tachikindleupdater.lua's module comment for the confirmed
-- real fields used: tag_name, zipball_url, and commits[1].sha).
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
-- api.github.com/repos/Darkgoatie/TachiKindle/releases/latest
local REAL_RELEASE_JSON = [[
{
  "tag_name": "v1.0.0",
  "name": "v1.0.0",
  "target_commitish": "main",
  "zipball_url": "https://api.github.com/repos/Darkgoatie/TachiKindle/zipball/v1.0.0",
  "tarball_url": "https://api.github.com/repos/Darkgoatie/TachiKindle/tarball/v1.0.0",
  "draft": false,
  "prerelease": false
}
]]

-- Real shape confirmed live against
-- api.github.com/repos/Darkgoatie/TachiKindle/commits?per_page=1
local REAL_COMMITS_JSON = [[
[
  {
    "sha": "2e23c3a58b8cded994715481b38e797ce7a2a1c3",
    "commit": { "message": "Set default repo to in-repo production index" },
    "html_url": "https://github.com/Darkgoatie/TachiKindle/commit/2e23c3a58b8cded994715481b38e797ce7a2a1c3"
  }
]
]]

test("version compare: lower current, higher latest => update available", function()
    assert(Updater.isNewer("1.0.0", "1.0.1") == true)
    assert(Updater.isNewer("1.0.0", "1.1.0") == true)
    assert(Updater.isNewer("1.0.0", "2.0.0") == true)
end)

test("version compare: equal or current ahead => no update", function()
    assert(Updater.isNewer("1.0.0", "1.0.0") == false)
    assert(Updater.isNewer("1.2.0", "1.1.9") == false)
    assert(Updater.isNewer("2.0.0", "1.9.9") == false)
end)

test("version compare: leading 'v' and missing components tolerated", function()
    assert(Updater.isNewer("v1.0.0", "v1.0.1") == true)
    assert(Updater.isNewer("1.0", "1.1") == true)
end)

test("version compare: unparsable input defaults to 'update available'", function()
    assert(Updater.isNewer(nil, "1.0.0") == true)
    assert(Updater.isNewer("1.0.0", "garbage") == true)
end)

test("fetchLatest: real release JSON shape parsed correctly", function()
    http_response_body, http_response_code = REAL_RELEASE_JSON, 200
    local plugin = newPlugin()
    local latest, err = Updater:fetchLatest(plugin)
    assert(latest, err)
    assert(latest.kind == "release")
    assert(latest.version == "1.0.0")
    assert(latest.tag == "v1.0.0")
    assert(latest.zip_url == "https://api.github.com/repos/Darkgoatie/TachiKindle/zipball/v1.0.0")
    assert(plugin.last_url:match("^https://api%.github%.com/repos/Darkgoatie/TachiKindle/releases/latest"))
end)

test("fetchLatest: falls back to commits API when releases response has no tag_name", function()
    local calls = {}
    local orig_httpGet = FakePlugin.httpGet
    FakePlugin.httpGet = function(self, url)
        table.insert(calls, url)
        if url:match("/releases/latest") then
            return [[{ "message": "Not Found" }]]
        end
        return REAL_COMMITS_JSON
    end
    local plugin = newPlugin()
    local latest, err = Updater:fetchLatest(plugin)
    FakePlugin.httpGet = orig_httpGet
    assert(latest, err)
    assert(latest.kind == "commit")
    assert(latest.version == "2e23c3a")
    assert(latest.sha == "2e23c3a58b8cded994715481b38e797ce7a2a1c3")
    assert(#calls == 2 and calls[2]:match("/commits%?per_page=1"))
end)

test("fetchLatest: network failure on both endpoints reports a real error", function()
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
    FakePlugin.httpGet = function(self, url)
        if url:match("/releases/latest") then
            return [[{ "message": "Not Found" }]]
        end
        return [[{ "this": "is not a commit list" }]]
    end
    local plugin = newPlugin()
    local latest, err = Updater:fetchLatest(plugin)
    FakePlugin.httpGet = orig_httpGet
    assert(latest == nil)
    assert(err and err:match("Unexpected response"))
end)

test("readLocalVersion/writeLocalVersion round-trip via VERSION file", function()
    local tmp_version_path = os.tmpname()
    local orig_versionFilePath = Updater.versionFilePath
    Updater.versionFilePath = function() return tmp_version_path end

    local ok, err = Updater:writeLocalVersion("9.9.9")
    assert(ok, err)
    assert(Updater:readLocalVersion() == "9.9.9")

    Updater.versionFilePath = orig_versionFilePath
    os.remove(tmp_version_path)
end)

test("readLocalVersion: missing VERSION file returns nil, not an error", function()
    local orig_versionFilePath = Updater.versionFilePath
    Updater.versionFilePath = function() return "/nonexistent/path/VERSION" end
    assert(Updater:readLocalVersion() == nil)
    Updater.versionFilePath = orig_versionFilePath
end)

test("checkForUpdates: no update available shows an info message, not a confirm dialog", function()
    http_response_body, http_response_code = REAL_RELEASE_JSON, 200 -- "1.0.0"
    local tmp_version_path = os.tmpname()
    local vf = assert(io.open(tmp_version_path, "w")); vf:write("1.0.0"); vf:close()
    local orig_versionFilePath = Updater.versionFilePath
    Updater.versionFilePath = function() return tmp_version_path end

    _G.__last_shown = nil
    Updater:checkForUpdates(newPlugin())
    assert(_G.__last_shown and _G.__last_shown.text:match("up to date"))

    Updater.versionFilePath = orig_versionFilePath
    os.remove(tmp_version_path)
end)

test("checkForUpdates: update available shows a confirm dialog with both actions", function()
    http_response_body, http_response_code = REAL_RELEASE_JSON, 200 -- "1.0.0"
    local tmp_version_path = os.tmpname()
    local vf = assert(io.open(tmp_version_path, "w")); vf:write("0.9.0"); vf:close()
    local orig_versionFilePath = Updater.versionFilePath
    Updater.versionFilePath = function() return tmp_version_path end

    _G.__last_shown = nil
    Updater:checkForUpdates(newPlugin())
    local shown = _G.__last_shown
    assert(shown and shown.buttons and #shown.buttons == 2)
    assert(shown.buttons[1][1].text == "Not now")
    assert(shown.buttons[2][1].text == "Update now")
    assert(shown.text:match("0.9.0") and shown.text:match("1.0.0"))

    Updater.versionFilePath = orig_versionFilePath
    os.remove(tmp_version_path)
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
