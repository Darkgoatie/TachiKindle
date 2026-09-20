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
local TachiKindleProgress = require("tachikindleprogress")
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
local SCREEN_OFFLINE = "offline"
local SCREEN_CONTINUE = "continue"
local SCREEN_ANALYTICS = "analytics"

function TachiKindleSourceBrowser:init()
    self.screen = self.start_screen or SCREEN_SOURCE_LIST
    if self.screen == SCREEN_FAVORITES then
        self.item_table = self:genFavoritesItemTable()
    elseif self.screen == SCREEN_OFFLINE then
        self.item_table = self:genOfflineItemTable()
    elseif self.screen == SCREEN_CONTINUE then
        self.item_table = self:genContinueItemTable()
    elseif self.screen == SCREEN_ANALYTICS then
        self.item_table = self:genAnalyticsItemTable()
    else
        self.item_table = self:genSourceItemTable()
    end
    Menu.init(self)
end

function TachiKindleSourceBrowser:sourcesDir()
    return DataStorage:getDataDir() .. "/tachikindle/sources"
end

function TachiKindleSourceBrowser:sourcePathById(source_id)
    return self:sourcesDir() .. "/" .. tostring(source_id) .. ".tkext.json"
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
    local item_table = {
        {
            text = _("Continue Reading"),
            callback = function() self:showContinueReading() end,
        },
        {
            text = _("Reading Analytics"),
            callback = function() self:showAnalytics() end,
        },
        {
            text = _("Offline Library"),
            callback = function() self:showOfflineLibrary() end,
        },
        {
            text = _("Process download queue"),
            callback = function() self:processDownloadQueue() end,
        },
    }
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


function TachiKindleSourceBrowser:genContinueItemTable()
    local items = {
        {
            text = _("← Back to Sources"),
            callback = function()
                self.screen = SCREEN_SOURCE_LIST
                self:switchItemTable(_("Sources"), self:genSourceItemTable())
                UIManager:setDirty(self, "full")
            end,
        },
    }
    local sources = self:loadAllSources()
    for _, rec in ipairs(TachiKindleProgress:listContinue(100)) do
        local source = sources[rec.source_id]
        local progress = (tonumber(rec.last_page) or 0) .. "/" .. (tonumber(rec.total_pages) or 0)
        table.insert(items, {
            text = string.format("▶ %s / %s  (%s)", rec.manga_title or "Manga", rec.chapter_title or rec.chapter_url, progress),
            source = source,
            chapter = { title = rec.chapter_title or rec.chapter_url, url = rec.chapter_url },
            manga = { title = rec.manga_title, url = rec.manga_url },
            missing_source = source == nil,
        })
    end
    if #items == 1 then
        table.insert(items, { text = _("No in-progress chapters yet.") })
    end
    return items
end

function TachiKindleSourceBrowser:showContinueReading()
    self.screen = SCREEN_CONTINUE
    self:switchItemTable(_("Continue Reading"), self:genContinueItemTable())
    UIManager:setDirty(self, "full")
end

function TachiKindleSourceBrowser:genAnalyticsItemTable()
    local a = TachiKindleProgress:getAnalytics()
    return {
        {
            text = _("← Back to Sources"),
            callback = function()
                self.screen = SCREEN_SOURCE_LIST
                self:switchItemTable(_("Sources"), self:genSourceItemTable())
                UIManager:setDirty(self, "full")
            end,
        },
        { text = _("Tracked chapters: ") .. tostring(a.chapters_tracked) },
        { text = _("Read chapters: ") .. tostring(a.chapters_read) },
        { text = _("In progress: ") .. tostring(a.chapters_in_progress) },
        { text = _("Pages read: ") .. tostring(a.pages_read) },
        { text = _("Reading sessions: ") .. tostring(a.sessions) },
    }
end

function TachiKindleSourceBrowser:showAnalytics()
    self.screen = SCREEN_ANALYTICS
    self:switchItemTable(_("Reading Analytics"), self:genAnalyticsItemTable())
    UIManager:setDirty(self, "full")
end

local function fmtMB(bytes)
    bytes = tonumber(bytes) or 0
    return string.format("%.1fMB", bytes / (1024 * 1024))
end

function TachiKindleSourceBrowser:genOfflineItemTable()
    local items = {
        {
            text = _("Process queue now"),
            callback = function() self:processDownloadQueue() end,
        },
        {
            text = _("Clean failed caches"),
            callback = function() self:cleanFailedCaches() end,
        },
        {
            text = _("Pause queue"),
            callback = function() self:setQueuePaused(true) end,
        },
        {
            text = _("Resume queue"),
            callback = function() self:setQueuePaused(false) end,
        },
        {
            text = _("Clear queue"),
            callback = function() self:clearQueue() end,
        },
        {
            text = _("Export offline manifest"),
            callback = function() self:exportOfflineManifest() end,
        },
        {
            text = _("Import offline manifest"),
            callback = function() self:importOfflineManifest() end,
        },
    }
    local sources = self:loadAllSources()
    local total_bytes = 0
    for _, source in pairs(sources) do
        local cached = source:listCachedChapters()
        for _, ch in ipairs(cached) do
            total_bytes = total_bytes + (ch.size_bytes or 0)
            table.insert(items, {
                text = string.format("[%s] %s / %s  (%s)", ch.complete and "Complete" or "Partial", ch.manga_title or "Manga", ch.chapter_title or ch.chapter_url, fmtMB(ch.size_bytes)),
                source = source,
                chapter = { title = ch.chapter_title, url = ch.chapter_url },
                offline_entry = ch,
            })
        end
    end
    if #items == 2 then
        table.insert(items, { text = _("No offline chapters yet.") })
    else
        table.insert(items, 3, { text = _("Total cache: ") .. fmtMB(total_bytes) })
    end
    return items
end

function TachiKindleSourceBrowser:showOfflineLibrary()
    self.screen = SCREEN_OFFLINE
    self:switchItemTable(_("Offline Library"), self:genOfflineItemTable())
    UIManager:setDirty(self, "full")
end

function TachiKindleSourceBrowser:cleanFailedCaches()
    local removed = 0
    for _, source in pairs(self:loadAllSources()) do
        removed = removed + source:cleanFailedCaches()
    end
    UIManager:show(InfoMessage:new{ text = _("Removed failed caches: ") .. tostring(removed), timeout = 2 })
    if self.screen == SCREEN_OFFLINE then
        self:showOfflineLibrary()
    end
end

function TachiKindleSourceBrowser:exportOfflineManifest()
    local sources = self:loadAllSources()
    local all = {}
    for _, source in pairs(sources) do
        for _, ch in ipairs(source:listCachedChapters()) do
            table.insert(all, ch)
        end
    end
    local path = DataStorage:getDataDir() .. "/tachikindle/offline_manifest.json"
    local f = io.open(path, "w")
    if not f then
        UIManager:show(InfoMessage:new{ text = _("Failed to export manifest") })
        return
    end
    f:write(require("json").encode({ exported_at = os.time(), chapters = all }))
    f:close()
    UIManager:show(InfoMessage:new{ text = _("Manifest exported: ") .. path, timeout = 2 })
end

function TachiKindleSourceBrowser:importOfflineManifest()
    local path = DataStorage:getDataDir() .. "/tachikindle/offline_manifest.json"
    local f = io.open(path, "r")
    if not f then
        UIManager:show(InfoMessage:new{ text = _("No manifest file found") })
        return
    end
    local body = f:read("*a")
    f:close()
    local ok, obj = pcall(require("json").decode, body)
    if not ok or type(obj) ~= "table" or type(obj.chapters) ~= "table" then
        UIManager:show(InfoMessage:new{ text = _("Invalid manifest file") })
        return
    end
    local sources = self:loadAllSources()
    local imported = 0
    for _, ch in ipairs(obj.chapters) do
        local s = sources[ch.source_id]
        if s and ch.chapter_url then
            local meta = {
                source_id = ch.source_id,
                source_name = ch.source_name,
                chapter_url = ch.chapter_url,
                chapter_title = ch.chapter_title,
                manga_title = ch.manga_title,
                cached_at = ch.cached_at,
                total = ch.total,
                saved = ch.saved,
                failed = ch.failed,
                complete = ch.complete,
                size_bytes = ch.size_bytes,
            }
            s:saveChapterMeta(ch.chapter_url, meta)
            imported = imported + 1
        end
    end
    UIManager:show(InfoMessage:new{ text = _("Manifest imported entries: ") .. tostring(imported), timeout = 2 })
    if self.screen == SCREEN_OFFLINE then self:showOfflineLibrary() end
end

function TachiKindleSourceBrowser:downloadChapterRange(source, chapters, count, force)
    count = math.min(tonumber(count) or 0, #chapters)
    if count <= 0 then return end
    local done, failed = 0, 0
    for i = 1, count do
        local ch = chapters[i]
        local result = source:prefetchChapter(ch.url, {
            force = force,
            chapter_title = ch.title,
            manga_title = self.current_manga and self.current_manga.title or nil,
        })
        if result and result.saved > 0 then done = done + 1 else failed = failed + 1 end
    end
    UIManager:show(InfoMessage:new{ text = string.format("Downloaded %d chapters (failed %d)", done, failed), timeout = 2 })
end

function TachiKindleSourceBrowser:queueChapterRange(source, chapters, count, priority)
    count = math.min(tonumber(count) or 0, #chapters)
    local qn = 0
    for i = 1, count do
        local ch = chapters[i]
        qn = source:enqueueChapter({
            chapter_url = ch.url,
            chapter_title = ch.title,
            manga_title = self.current_manga and self.current_manga.title or nil,
            priority = priority,
        })
    end
    UIManager:show(InfoMessage:new{ text = string.format("Queued %d chapters. Jobs: %d", count, qn), timeout = 2 })
end

function TachiKindleSourceBrowser:processDownloadQueue()
    local done, failed, remaining = 0, 0, 0
    for _, source in pairs(self:loadAllSources()) do
        local r = source:processQueue(5)
        done = done + (r.done or 0)
        failed = failed + (r.failed or 0)
        remaining = remaining + (r.remaining or 0)
    end
    UIManager:show(InfoMessage:new{
        text = string.format("Queue: done=%d failed=%d remaining=%d", done, failed, remaining),
        timeout = 2,
    })
    if self.screen == SCREEN_OFFLINE then
        self:showOfflineLibrary()
    end
end

function TachiKindleSourceBrowser:setQueuePaused(paused)
    for _, source in pairs(self:loadAllSources()) do
        source:setAllQueuePaused(paused)
    end
    UIManager:show(InfoMessage:new{ text = paused and _("Queue paused") or _("Queue resumed"), timeout = 1 })
end

function TachiKindleSourceBrowser:clearQueue()
    for _, source in pairs(self:loadAllSources()) do
        source:clearQueue()
    end
    UIManager:show(InfoMessage:new{ text = _("Queue cleared"), timeout = 1 })
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
    if self.screen == SCREEN_CONTINUE and item.manga then
        if item.missing_source then
            UIManager:show(InfoMessage:new{
                text = _("Source for this chapter is no longer installed."),
            })
            return true
        end
        self.current_manga = item.manga
        self.refresh_current_list = function()
            self:showContinueReading()
        end
        self:openChapter(item.source, item.chapter)
        return true
    end
    if self.screen == SCREEN_FAVORITES and item.manga then
        -- Favorites load chapters directly, skipping the manga-list
        -- step entirely (per the feature request: tapping a favorite
        -- goes straight to its source's chapter list).
        self.refresh_current_list = function()
            self.screen = SCREEN_FAVORITES
            self:switchItemTable(_("Favorites"), self:genFavoritesItemTable())
            UIManager:setDirty(self, "full")
        end
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
    if self.screen == SCREEN_OFFLINE and item.chapter and item.source then
        self.refresh_current_list = function() self:showOfflineLibrary() end
        self:openChapter(item.source, item.chapter)
        return true
    end
    return true
end

function TachiKindleSourceBrowser:showSourceActions(item)
    local dialog
    local source = item.source
    dialog = ButtonDialog:new{
        buttons = {
            {{ text = _("Remove extension"), callback = function() UIManager:close(dialog); self:removeInstalledSource(source) end, align = "left" }},
            {{ text = _("Cancel"), callback = function() UIManager:close(dialog) end, align = "left" }},
        },
    }
    UIManager:show(dialog)
end

function TachiKindleSourceBrowser:showChapterActions(item)
    local dialog
    local source = item.source
    local chapter = item.chapter
    dialog = ButtonDialog:new{
        buttons = {
            {{ text = _("Download offline"), callback = function() UIManager:close(dialog); self:downloadChapterForOffline(source, chapter, false) end, align = "left" }},
            {{ text = _("Redownload"), callback = function() UIManager:close(dialog); self:downloadChapterForOffline(source, chapter, true) end, align = "left" }},
            {{ text = _("Verify cache"), callback = function() UIManager:close(dialog); self:verifyOfflineChapter(source, chapter) end, align = "left" }},
            {{ text = _("Delete cache"), callback = function() UIManager:close(dialog); self:deleteOfflineChapter(source, chapter) end, align = "left" }},
            {{ text = _("Queue high"), callback = function() UIManager:close(dialog); self:queueChapter(source, chapter, 1) end, align = "left" }},
            {{ text = _("Queue normal"), callback = function() UIManager:close(dialog); self:queueChapter(source, chapter, 5) end, align = "left" }},
            {{ text = _("Queue low"), callback = function() UIManager:close(dialog); self:queueChapter(source, chapter, 9) end, align = "left" }},
            {{ text = _("Mark as read"), callback = function() UIManager:close(dialog); self:markChapterRead(source, chapter, true) end, align = "left" }},
            {{ text = _("Mark as unread"), callback = function() UIManager:close(dialog); self:markChapterRead(source, chapter, false) end, align = "left" }},
            {{ text = _("Cancel"), callback = function() UIManager:close(dialog) end, align = "left" }},
        },
    }
    UIManager:show(dialog)
end

-- Long-press row actions.
function TachiKindleSourceBrowser:onMenuHold(item)
    if self.screen == SCREEN_SOURCE_LIST and item.source then
        self:showSourceActions(item)
        return true
    end
    if (self.screen == SCREEN_CHAPTER_LIST or self.screen == SCREEN_OFFLINE) and item.chapter and item.source then
        self:showChapterActions(item)
        return true
    end
    if item.manga and item.source then
        local now_favorite = TachiKindleFavorites:toggle(item.source.def.id, item.source.def.name, item.manga)
        UIManager:show(InfoMessage:new{
            text = now_favorite and _("Added to Favorites") or _("Removed from Favorites"),
            timeout = 1,
        })
        if self.screen == SCREEN_FAVORITES then
            self:switchItemTable(self.title, self:genFavoritesItemTable())
        elseif self.refresh_current_list then
            self.refresh_current_list()
        end
        UIManager:setDirty(self, "full")
    end
    return true
end

function TachiKindleSourceBrowser:removeInstalledSource(source)
    local path = self:sourcePathById(source.def.id)
    local ok, err = os.remove(path)
    if not ok then
        UIManager:show(InfoMessage:new{ text = _("Remove failed: ") .. tostring(err), timeout = 2 })
        return
    end
    UIManager:show(InfoMessage:new{ text = _("Removed extension: ") .. tostring(source.def.name or source.def.id), timeout = 1 })
    self.screen = SCREEN_SOURCE_LIST
    self:switchItemTable(_("Sources"), self:genSourceItemTable())
    UIManager:setDirty(self, "full")
end

function TachiKindleSourceBrowser:markChapterRead(source, chapter, is_read)
    TachiKindleProgress:markRead(source.def.id, source.def.name, self.current_manga, chapter, is_read)
    UIManager:show(InfoMessage:new{
        text = is_read and _("Marked as read") or _("Marked as unread"),
        timeout = 1,
    })
    if self.refresh_current_list then
        self.refresh_current_list()
    end
end

function TachiKindleSourceBrowser:queueChapter(source, chapter, priority)
    local n = source:enqueueChapter({
        chapter_url = chapter.url,
        chapter_title = chapter.title,
        manga_title = self.current_manga and self.current_manga.title or nil,
        priority = priority,
    })
    UIManager:show(InfoMessage:new{ text = _("Queued. Jobs: ") .. tostring(n), timeout = 1 })
end

function TachiKindleSourceBrowser:verifyOfflineChapter(source, chapter)
    local s = source:verifyChapterCache(chapter.url)
    UIManager:show(InfoMessage:new{
        text = string.format("Cache verify: %d/%d saved", s.saved or 0, s.total or 0),
        timeout = 2,
    })
    if self.screen == SCREEN_OFFLINE then self:showOfflineLibrary() end
end

function TachiKindleSourceBrowser:deleteOfflineChapter(source, chapter)
    source:deleteChapterCache(chapter.url)
    UIManager:show(InfoMessage:new{ text = _("Offline cache deleted"), timeout = 1 })
    if self.screen == SCREEN_OFFLINE then self:showOfflineLibrary() end
end

function TachiKindleSourceBrowser:downloadChapterForOffline(source, chapter, force)
    local loading = InfoMessage:new{ text = _("Downloading for offline…") }
    UIManager:show(loading)
    UIManager:forceRePaint()
    local result, err = source:prefetchChapter(chapter.url, {
        force = force,
        chapter_title = chapter.title,
        manga_title = self.current_manga and self.current_manga.title or nil,
    })
    UIManager:close(loading)

    if not result then
        UIManager:show(InfoMessage:new{ text = _("Offline download failed: ") .. tostring(err) })
        return
    end

    UIManager:show(InfoMessage:new{
        text = _("Offline saved: ") .. tostring(result.saved) .. "/" .. tostring(result.total)
            .. (result.failed > 0 and (_(" (failed: ") .. tostring(result.failed) .. ")") or ""),
        timeout = 2,
    })
    if self.screen == SCREEN_OFFLINE then self:showOfflineLibrary() end
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
    local item_table = {
        {
            text = _("← Back to Sources"),
            callback = function()
                self.screen = SCREEN_SOURCE_LIST
                self:switchItemTable(_("Sources"), self:genSourceItemTable())
                UIManager:setDirty(self, "full")
            end,
        },
    }
    if page == 1 then
        table.insert(item_table, {
            text = _("🔍 Search…"),
            callback = function() self:promptSearch(source) end,
        })
    else
        table.insert(item_table, {
            text = _("← Prev page"),
            callback = function() self:openSource(source, page - 1) end,
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
    local item_table = {
        {
            text = _("← Back to Source"),
            callback = function() self:openSource(source, 1) end,
        },
    }
    if page > 1 then
        table.insert(item_table, {
            text = _("← Prev page"),
            callback = function() self:runSearch(source, query, page - 1) end,
        })
    end
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
    self.current_manga = manga
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
    local item_table = {
        {
            text = _("← Back"),
            callback = function()
                if self.refresh_current_list then
                    self.refresh_current_list()
                else
                    self.screen = SCREEN_SOURCE_LIST
                    self:switchItemTable(_("Sources"), self:genSourceItemTable())
                    UIManager:setDirty(self, "full")
                end
            end,
        },
        {
            text = _("Hold a chapter for offline actions"),
            callback = function() end,
        },
        {
            text = _("Download next 3 chapters"),
            callback = function() self:downloadChapterRange(source, chapters, 3, false) end,
        },
        {
            text = _("Download next 10 chapters"),
            callback = function() self:downloadChapterRange(source, chapters, 10, false) end,
        },
        {
            text = _("Queue next 10 chapters"),
            callback = function() self:queueChapterRange(source, chapters, 10, 5) end,
        },
        {
            text = _("Queue all chapters"),
            callback = function() self:queueChapterRange(source, chapters, #chapters, 5) end,
        },
        {
            text = _("Continue latest in-progress"),
            callback = function()
                for _, c in ipairs(chapters) do
                    local pr = TachiKindleProgress:getChapterProgress(source.def.id, c.url)
                    if pr and not pr.is_read and (tonumber(pr.last_page) or 0) > 0 then
                        self:openChapter(source, c)
                        return
                    end
                end
                UIManager:show(InfoMessage:new{ text = _("No in-progress chapters in this manga."), timeout = 1 })
            end,
        },
    }
    for _, c in ipairs(chapters) do
        local progress = TachiKindleProgress:getChapterProgress(source.def.id, c.url)
        local prefix = ""
        if progress then
            if progress.is_read then
                prefix = "✓ "
            elseif (tonumber(progress.last_page) or 0) > 0 then
                prefix = string.format("• %d/%d ", tonumber(progress.last_page) or 0, tonumber(progress.total_pages) or 0)
            end
        end
        table.insert(item_table, {
            text = prefix .. (c.date and (c.title .. "  (" .. c.date .. ")") or c.title),
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

    local stats = source:chapterCacheStats(chapter.url)
    if stats.complete then
        UIManager:show(InfoMessage:new{ text = _("Using offline copy"), timeout = 1 })
    elseif stats.saved > 0 then
        UIManager:show(InfoMessage:new{ text = _("Partial offline cache: ") .. tostring(stats.saved) .. "/" .. tostring(stats.total), timeout = 2 })
    end
    if stats.total > 0 and #pages > stats.total then
        UIManager:show(InfoMessage:new{ text = _("Newer online version available"), timeout = 2 })
    end

    local chapter_manga = self.current_manga or { title = nil, url = nil }
    local progress = TachiKindleProgress:getChapterProgress(source.def.id, chapter.url)
    local start_page = progress and (tonumber(progress.last_page) or 1) or 1
    TachiKindleProgress:recordChapterOpen(source.def.id, source.def.name, chapter_manga, chapter, #pages)

    TachiKindleReader.show(source, chapter.url, pages, chapter.title, {
        start_page = start_page,
        on_progress = function(page, total, _closing)
            TachiKindleProgress:updateProgress(source.def.id, source.def.name, chapter_manga, chapter, page, total)
        end,
    })
end

return TachiKindleSourceBrowser
