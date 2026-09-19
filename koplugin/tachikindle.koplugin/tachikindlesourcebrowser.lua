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

function TachiKindleSourceBrowser:init()
    self.screen = SCREEN_SOURCE_LIST
    self.item_table = self:genSourceItemTable()
    Menu.init(self)
end

function TachiKindleSourceBrowser:sourcesDir()
    return DataStorage:getDataDir() .. "/tachikindle/sources"
end

function TachiKindleSourceBrowser:genSourceItemTable()
    local dir = self:sourcesDir()
    local item_table = {}
    if lfs.attributes(dir, "mode") == "directory" then
        for name in lfs.dir(dir) do
            if name:match("%.tkext%.json$") then
                local path = dir .. "/" .. name
                local source, err = TachiKindleSource:load(path)
                if source then
                    table.insert(item_table, {
                        text = source.def.name or name,
                        source = source,
                    })
                end
            end
        end
    end
    return item_table
end

function TachiKindleSourceBrowser:onMenuSelect(item)
    if item.callback then
        item.callback()
        return true
    end
    if self.screen == SCREEN_SOURCE_LIST and item.source then
        self:openSource(item.source)
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
    for _, m in ipairs(list) do
        table.insert(item_table, {
            text = m.title or m.url,
            source = source,
            manga = m,
        })
    end
    if has_next then
        table.insert(item_table, {
            text = _("Next page →"),
            callback = function() self:openSource(source, page + 1) end,
        })
    end
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
    for _, m in ipairs(list) do
        table.insert(item_table, {
            text = m.title or m.url,
            source = source,
            manga = m,
        })
    end
    if has_next then
        table.insert(item_table, {
            text = _("Next page →"),
            callback = function() self:runSearch(source, query, page + 1) end,
        })
    end
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
