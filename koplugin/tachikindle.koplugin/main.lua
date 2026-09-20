--[[--
TachiKindle: browse and download manga sources into your KOReader
library. See extensions/format/repo-protocol.md (repo root of this
project) for the wire format -- unchanged from the standalone C
app's design, just consumed from Lua now.

Networking/settings patterns copied from the real koreader.koplugin
"opds" plugin (frontend/plugins/opds.koplugin/{main,opdsbrowser}.lua,
v2026.07.1, the on-device KOReader version) since it's KOReader's own
closest built-in analog: fetch a remote catalog, list entries, let
the user browse/download into the library.

@module koplugin.TachiKindle
--]]--

local Dispatcher = require("dispatcher")  -- luacheck:ignore
local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local Menu = require("ui/widget/menu")
local TachiKindleBrowser = require("tachikindlebrowser")
local TachiKindleSourceBrowser = require("tachikindlesourcebrowser")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local http = require("socket.http")
local socket = require("socket")
local socketutil = require("socketutil")
local ltn12 = require("ltn12")
local JSON = require("json")
local util = require("util")
local _ = require("gettext")

local TachiKindle = WidgetContainer:extend{
    name = "tachikindle",
    is_doc_only = false,
    settings_file = DataStorage:getSettingsDir() .. "/tachikindle.lua",
    settings = nil,
    repos = nil,
    default_repos = {
        {
            title = "TachiKindle Sources",
            url = "https://raw.githubusercontent.com/Darkgoatie/TachiKindle/main/extensions/testrepo",
        },
    },
}

function TachiKindle:onDispatcherRegisterActions()
    Dispatcher:registerAction("tachikindle_open_action", {
        category = "none",
        event = "TachiKindleOpen",
        title = _("TachiKindle"),
        general = true,
    })
end

function TachiKindle:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

function TachiKindle:loadSettings()
    if self.settings then return end
    self.settings = LuaSettings:open(self.settings_file)
    self.repos = self.settings:readSetting("repos", self.default_repos)
end

function TachiKindle:saveRepos()
    self.settings:saveSetting("repos", self.repos)
    self.settings:flush()
end

function TachiKindle:addToMainMenu(menu_items)
    menu_items.tachikindle = {
        text = _("TachiKindle"),
        sorting_hint = "more_tools",
        sub_item_table = {
            {
                text = _("Browse Sources"),
                callback = function()
                    self:showSourceList()
                end,
            },
            {
                text = _("Continue Reading"),
                callback = function()
                    self:showContinueReading()
                end,
            },
            {
                text = _("Reading Analytics"),
                callback = function()
                    self:showReadingAnalytics()
                end,
            },
            {
                text = _("Favorites"),
                callback = function()
                    self:showFavorites()
                end,
            },
            {
                text = _("Offline Library"),
                callback = function()
                    self:showOfflineLibrary()
                end,
            },
            {
                text = _("Manage Repos"),
                callback = function()
                    self:showRepoList()
                end,
            },
        },
    }
end

function TachiKindle:showSourceList()
    self:loadSettings()
    self.source_browser = TachiKindleSourceBrowser:new{
        title = _("Sources"),
        is_popout = false,
        is_borderless = true,
        title_bar_fm_style = true,
        close_callback = function()
            UIManager:close(self.source_browser)
            self.source_browser = nil
        end,
    }
    UIManager:show(self.source_browser)
end

function TachiKindle:showFavorites()
    self:loadSettings()
    self.favorites_browser = TachiKindleSourceBrowser:new{
        title = _("Favorites"),
        start_screen = "favorites",
        is_popout = false,
        is_borderless = true,
        title_bar_fm_style = true,
        close_callback = function()
            UIManager:close(self.favorites_browser)
            self.favorites_browser = nil
        end,
    }
    UIManager:show(self.favorites_browser)
end

function TachiKindle:showContinueReading()
    self:loadSettings()
    self.continue_browser = TachiKindleSourceBrowser:new{
        title = _("Continue Reading"),
        start_screen = "continue",
        is_popout = false,
        is_borderless = true,
        title_bar_fm_style = true,
        close_callback = function()
            UIManager:close(self.continue_browser)
            self.continue_browser = nil
        end,
    }
    UIManager:show(self.continue_browser)
end

function TachiKindle:showReadingAnalytics()
    self:loadSettings()
    self.analytics_browser = TachiKindleSourceBrowser:new{
        title = _("Reading Analytics"),
        start_screen = "analytics",
        is_popout = false,
        is_borderless = true,
        title_bar_fm_style = true,
        close_callback = function()
            UIManager:close(self.analytics_browser)
            self.analytics_browser = nil
        end,
    }
    UIManager:show(self.analytics_browser)
end

function TachiKindle:showOfflineLibrary()
    self:loadSettings()
    self.offline_browser = TachiKindleSourceBrowser:new{
        title = _("Offline Library"),
        start_screen = "offline",
        is_popout = false,
        is_borderless = true,
        title_bar_fm_style = true,
        close_callback = function()
            UIManager:close(self.offline_browser)
            self.offline_browser = nil
        end,
    }
    UIManager:show(self.offline_browser)
end

function TachiKindle:onTachiKindleOpen()
    self:loadSettings()
    self:showSourceList()
end

function TachiKindle:showRepoList()
    self.browser = TachiKindleBrowser:new{
        plugin = self,
        title = _("TachiKindle Repos"),
        is_popout = false,
        is_borderless = true,
        title_bar_fm_style = true,
        close_callback = function()
            UIManager:close(self.browser)
            self.browser = nil
        end,
    }
    UIManager:show(self.browser)
end

-- GET url and return the response body as a string, or nil + an
-- error message. Same request shape as OPDSBrowser:fetchFeed (see
-- module comment) -- Accept-Encoding: identity since the repo index
-- is plain small JSON, no need to negotiate compression.
function TachiKindle:httpGet(url)
    local sink = {}
    socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
    local request = {
        url = url,
        method = "GET",
        headers = { ["Accept-Encoding"] = "identity" },
        sink = ltn12.sink.table(sink),
    }
    local ok, code = pcall(function()
        return socket.skip(1, http.request(request))
    end)
    socketutil:reset_timeout()

    if not ok then
        return nil, tostring(code)
    end
    if code ~= 200 then
        return nil, _("HTTP error: ") .. tostring(code)
    end
    return table.concat(sink)
end

return TachiKindle
