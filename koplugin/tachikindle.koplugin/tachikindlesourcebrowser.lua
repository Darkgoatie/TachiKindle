--[[--
TachiKindleSourceBrowser: browse a downloaded/installed .tkext.json
source live -- manga list -> chapter list -> read online. This is
the second Menu-based browser, separate from TachiKindleBrowser
(which only handles the repo/download side), following the same
"Menu:extend, tap a row to go deeper" shape borrowed from opdsbrowser.

@module koplugin.TachiKindleSourceBrowser
--]]--

local ButtonDialog = require("ui/widget/buttondialog")
local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local TachiKindleSource = require("tachikindlesource")
local TachiKindleReader = require("tachikindlereader")
local TachiKindleFavorites = require("tachikindlefavorites")
local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")

local TachiKindleSourceBrowser = Menu:extend{
    name = "tachikindlesourcebrowser",
    is_popout = false,
    is_borderless = true,
}

-- Screen kinds this single Menu instance cycles through, so tap
-- handling in onMenuSelect knows what a row tap actually means.
local SCREEN_SOURCE_LIST = "source_list"
local SCREEN_MANGA_LIST = "manga_list"
local SCREEN_CHAPTER_LIST = "chapter_list"
local SCREEN_FAVORITES = "favorites"

function TachiKindleSourceBrowser:init()
    self.screen = self.start_screen or SCREEN_SOURCE_LIST
    if self.screen == SCREEN_FAVORITES then
        self.item_table = self:genFavoritesItemTable()
    else
        self.item_table = self:genSourceItemTable()
    end
    Menu.init(self)
end

function TachiKindleSourceBrowser:sourcesDir()
    return DataStorage:getDataDir() .. "/tachikindle/sources"
end

-- Loads every installed .tkext.json in sourcesDir(), returning a map
-- of source.def.id -> loaded TachiKindleSource, so favorites (which
-- only persist a source_id, not a live object) can be reopened.
function TachiKindleSourceBrowser:loadAllSources()
    local dir = self:sourcesDir()
    local by_id = {}
    if lfs.attributes(dir, "mode") == "directory" then
        for name in lfs.dir(dir) do
            if name:match("%.tkext%.json$") then
                local source, err = TachiKindleSource:load(dir .. "/" .. name)
                if source and source.def.id then
                    by_id[source.def.id] = source
                end
            end
        end
    end
    return by_id
end

function TachiKindleSourceBrowser:genSourceItemTable()
    local item_table = {}
    for _, source in pairs(self:loadAllSources()) do
        table.insert(item_table, {
            text = source.def.name or source.def.id,
            source = source,
        })
    end
    return item_table
end

-- Builds the star-marked, favorite-aware row list for a manga list
-- screen. Shared by openSource/runSearch/genFavoritesItemTable so the
-- star prefix and long-press hookup can't drift between call sites.
function TachiKindleSourceBrowser:buildMangaItemTable(source, mangas)
    local item_table = {}
    for _, m in ipairs(mangas) do
        local starred = TachiKindleFavorites:isFavorite(source.def.id, m.url)
        table.insert(item_table, {
            text = (starred and "★ " or "") .. (m.title or m.url),
            source = source,
            manga = m,
        })
    end
    return item_table
end

function TachiKindleSourceBrowser:genFavoritesItemTable()
    local favorites = TachiKindleFavorites:list()
    local sources_by_id = self:loadAllSources()
    local item_table = {}
    for _, f in ipairs(favorites) do
        table.insert(item_table, {
            text = "★ " .. (f.title or f.url) .. "  [" .. (f.source_name or f.source_id) .. "]",
            source = sources_by_id[f.source_id],
            manga = { title = f.title, url = f.url, cover = f.cover },
            missing_source = sources_by_id[f.source_id] == nil,
        })
    end
    if #item_table == 0 then
        table.insert(item_table, {
            text = _("No favorites yet -- hold a manga in Browse Sources to add one."),
        })
    end
    return item_table
end

function TachiKindleSourceBrowser:onMenuSelect(item)
    if item.callback then
        item.callback()
        return true
    end
    if item.missing_source then
        UIManager:show(InfoMessage:new{
            text = _("Source for this favorite is no longer installed."),
        })
        return true
    end
    if self.screen == SCREEN_SOURCE_LIST and item.source then
        self:openSource(item.source)
        return true
    end
    if self.screen == SCREEN_FAVORITES and item.manga then
        -- Favorites load chapters directly, skipping the manga-list
        -- step entirely (per the feature request: tapping a favorite
        -- goes straight to its source's chapter list).
        self:openManga(item.source, item.manga)
        return true
    end
    if self.screen == SCREEN_MANGA_LIST and item.manga then
        self:openManga(item.source, item.manga)
        return true
    end
    if self.screen == SCREEN_CHAPTER_LIST and item.chapter then
        self:openChapter(item.source, item.chapter)
        return true
    end
    return true
end

-- Long-press a manga row to toggle its favorite status. Confirmed
-- real hook: Menu:onMenuHold is meant to be overridden by callers
-- (base implementation is a no-op returning true, see menu.lua).
function TachiKindleSourceBrowser:onMenuHold(item)
    if item.manga and item.source then
        local now_favorite = TachiKindleFavorites:toggle(item.source.def.id, item.source.def.name, item.manga)
        UIManager:show(InfoMessage:new{
            text = now_favorite and _("Added to Favorites") or _("Removed from Favorites"),
            timeout = 1,
        })
        -- Re-render whichever manga-list-shaped screen is showing so
        -- the star prefix reflects the new state immediately.
        if self.screen == SCREEN_FAVORITES then
            self:switchItemTable(self.title, self:genFavoritesItemTable())
        elseif self.refresh_current_list then
            self.refresh_current_list()
        end
        UIManager:setDirty(self, "full")
    end
    return true
end

function TachiKindleSourceBrowser:openSource(source, page)
    page = page or 1
    local loading = InfoMessage:new{ text = _("Loading…") }
    UIManager:show(loading)
    UIManager:forceRePaint()
    local list, err, has_next = source:fetchMangaList("popular", page)
    UIManager:close(loading)

    if not list then
        UIManager:show(InfoMessage:new{ text = _("Failed to load source: ") .. tostring(err) })
        return
    end
    if #list == 0 then
        UIManager:show(InfoMessage:new{ text = _("No manga found.") })
        return
    end

    self.screen = SCREEN_MANGA_LIST
    local item_table = {}
    if page == 1 then
        table.insert(item_table, {
            text = _("🔍 Search…"),
            callback = function() self:promptSearch(source) end,
        })
    end
    local manga_rows = self:buildMangaItemTable(source, list)
    for _, row in ipairs(manga_rows) do table.insert(item_table, row) end
    if has_next then
        table.insert(item_table, {
            text = _("Next page →"),
            callback = function() self:openSource(source, page + 1) end,
        })
    end
    self.refresh_current_list = function() self:openSource(source, page) end
    self:switchItemTable(source.def.name, item_table)
    UIManager:setDirty(self, "full")
end

-- Shows a dialog to search this source over the network -- separate
-- from the "popular" list shown by default, following the same
-- shape as koreader's real opds.koplugin OPDSBrowser:searchCatalog.
function TachiKindleSourceBrowser:promptSearch(source)
    local input_dialog
    input_dialog = InputDialog:new{
        title = _("Search ") .. source.def.name,
        input_hint = _("Manga title…"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(input_dialog)
                    end,
                },
                {
                    text = _("Search"),
                    is_enter_default = true,
                    callback = function()
                        local query = input_dialog:getInputText()
                        UIManager:close(input_dialog)
                        if query and query ~= "" then
                            self:runSearch(source, query, 1)
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function TachiKindleSourceBrowser:runSearch(source, query, page)
    local loading = InfoMessage:new{ text = _("Searching…") }
    UIManager:show(loading)
    UIManager:forceRePaint()
    local list, err, has_next = source:fetchMangaList("search", page, query)
    UIManager:close(loading)

    if not list then
        UIManager:show(InfoMessage:new{ text = _("Search failed: ") .. tostring(err) })
        return
    end
    if #list == 0 then
        UIManager:show(InfoMessage:new{ text = _("No results for \"") .. query .. "\"." })
        return
    end

    self.screen = SCREEN_MANGA_LIST
    local item_table = {}
    local manga_rows = self:buildMangaItemTable(source, list)
    for _, row in ipairs(manga_rows) do table.insert(item_table, row) end
    if has_next then
        table.insert(item_table, {
            text = _("Next page →"),
            callback = function() self:runSearch(source, query, page + 1) end,
        })
    end
    self.refresh_current_list = function() self:runSearch(source, query, page) end
    self:switchItemTable(_("Search: ") .. query, item_table)
    UIManager:setDirty(self, "full")
end

function TachiKindleSourceBrowser:openManga(source, manga)
    local loading = InfoMessage:new{ text = _("Loading chapters…") }
    UIManager:show(loading)
    UIManager:forceRePaint()
    local chapters, err = source:fetchChapterList(manga.url)
    UIManager:close(loading)

    if not chapters then
        UIManager:show(InfoMessage:new{ text = _("Failed to load chapters: ") .. tostring(err) })
        return
    end
    if #chapters == 0 then
        UIManager:show(InfoMessage:new{ text = _("No chapters found.") })
        return
    end

    self.screen = SCREEN_CHAPTER_LIST
    local item_table = {}
    for _, c in ipairs(chapters) do
        table.insert(item_table, {
            text = c.date and (c.title .. "  (" .. c.date .. ")") or c.title,
            source = source,
            chapter = c,
        })
    end
    self:switchItemTable(manga.title, item_table)
    UIManager:setDirty(self, "full")
end

function TachiKindleSourceBrowser:openChapter(source, chapter)
    local loading = InfoMessage:new{ text = _("Loading pages…") }
    UIManager:show(loading)
    UIManager:forceRePaint()
    local pages, err = source:fetchPageList(chapter.url)
    UIManager:close(loading)

    if not pages then
        UIManager:show(InfoMessage:new{ text = _("Failed to load pages: ") .. tostring(err) })
        return
    end
    TachiKindleReader.show(source, pages, chapter.title)
end

return TachiKindleSourceBrowser
