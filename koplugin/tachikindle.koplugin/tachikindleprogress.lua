--[[--
TachiKindleProgress: persistent reading progress and analytics.
Stores per-chapter state and aggregate counters in LuaSettings.

@module koplugin.TachiKindleProgress
--]]--

local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")

local TachiKindleProgress = {}

local settings_file = DataStorage:getSettingsDir() .. "/tachikindle_progress.lua"
local settings
local state

local function now()
    return os.time()
end

local function ensureLoaded()
    if settings then return end
    settings = LuaSettings:open(settings_file)
    state = settings:readSetting("progress", {
        chapters = {},
        stats = {
            pages_read = 0,
            sessions = 0,
            last_opened_at = nil,
        },
    })
    state.chapters = state.chapters or {}
    state.stats = state.stats or {}
    state.stats.pages_read = tonumber(state.stats.pages_read) or 0
    state.stats.sessions = tonumber(state.stats.sessions) or 0
end

local function save()
    settings:saveSetting("progress", state)
    settings:flush()
end

local function chapterKey(source_id, chapter_url)
    return tostring(source_id or "") .. "|" .. tostring(chapter_url or "")
end

local function ensureChapter(source_id, source_name, manga, chapter)
    local key = chapterKey(source_id, chapter.url)
    local rec = state.chapters[key]
    if not rec then
        rec = {
            key = key,
            source_id = source_id,
            source_name = source_name,
            manga_title = manga and manga.title or nil,
            manga_url = manga and manga.url or nil,
            chapter_title = chapter and chapter.title or nil,
            chapter_url = chapter and chapter.url or nil,
            total_pages = 0,
            last_page = 0,
            max_page_seen = 0,
            is_read = false,
            open_count = 0,
            started_at = nil,
            completed_at = nil,
            updated_at = now(),
        }
        state.chapters[key] = rec
    end
    if source_name then rec.source_name = source_name end
    if manga and manga.title then rec.manga_title = manga.title end
    if manga and manga.url then rec.manga_url = manga.url end
    if chapter and chapter.title then rec.chapter_title = chapter.title end
    rec.updated_at = now()
    return rec
end

function TachiKindleProgress:getChapterProgress(source_id, chapter_url)
    ensureLoaded()
    return state.chapters[chapterKey(source_id, chapter_url)]
end

function TachiKindleProgress:isRead(source_id, chapter_url)
    local rec = self:getChapterProgress(source_id, chapter_url)
    return rec and rec.is_read or false
end

function TachiKindleProgress:recordChapterOpen(source_id, source_name, manga, chapter, total_pages)
    ensureLoaded()
    local rec = ensureChapter(source_id, source_name, manga, chapter)
    rec.open_count = (tonumber(rec.open_count) or 0) + 1
    rec.started_at = rec.started_at or now()
    if tonumber(total_pages) and total_pages > 0 then
        rec.total_pages = math.max(tonumber(rec.total_pages) or 0, total_pages)
    end
    state.stats.sessions = (tonumber(state.stats.sessions) or 0) + 1
    state.stats.last_opened_at = now()
    save()
    return rec
end

function TachiKindleProgress:updateProgress(source_id, source_name, manga, chapter, page, total_pages)
    ensureLoaded()
    local rec = ensureChapter(source_id, source_name, manga, chapter)
    local p = tonumber(page) or 0
    local t = tonumber(total_pages) or tonumber(rec.total_pages) or 0
    if t > 0 then
        p = math.max(1, math.min(p, t))
        rec.total_pages = math.max(tonumber(rec.total_pages) or 0, t)
    else
        p = math.max(0, p)
    end

    rec.last_page = p
    if p > (tonumber(rec.max_page_seen) or 0) then
        state.stats.pages_read = (tonumber(state.stats.pages_read) or 0) + (p - (tonumber(rec.max_page_seen) or 0))
        rec.max_page_seen = p
    end

    if rec.total_pages > 0 and rec.last_page >= rec.total_pages then
        rec.is_read = true
        rec.completed_at = rec.completed_at or now()
    else
        rec.is_read = false
        rec.completed_at = nil
    end

    rec.updated_at = now()
    save()
    return rec
end

function TachiKindleProgress:markRead(source_id, source_name, manga, chapter, is_read)
    ensureLoaded()
    local rec = ensureChapter(source_id, source_name, manga, chapter)
    rec.is_read = is_read and true or false
    if rec.is_read then
        local total = tonumber(rec.total_pages) or 0
        if total > 0 then
            rec.last_page = total
            if total > (tonumber(rec.max_page_seen) or 0) then
                state.stats.pages_read = (tonumber(state.stats.pages_read) or 0) + (total - (tonumber(rec.max_page_seen) or 0))
                rec.max_page_seen = total
            end
        end
        rec.completed_at = now()
    else
        rec.completed_at = nil
    end
    rec.updated_at = now()
    save()
    return rec
end

function TachiKindleProgress:listContinue(limit)
    ensureLoaded()
    local list = {}
    for _, rec in pairs(state.chapters) do
        local total = tonumber(rec.total_pages) or 0
        local page = tonumber(rec.last_page) or 0
        local in_progress = (not rec.is_read) and page > 0 and ((total > 0 and page < total) or total == 0)
        if in_progress then
            table.insert(list, rec)
        end
    end
    table.sort(list, function(a, b)
        return (tonumber(a.updated_at) or 0) > (tonumber(b.updated_at) or 0)
    end)
    if limit and #list > limit then
        while #list > limit do table.remove(list) end
    end
    return list
end

function TachiKindleProgress:getAnalytics()
    ensureLoaded()
    local tracked, read, in_progress = 0, 0, 0
    for _, rec in pairs(state.chapters) do
        tracked = tracked + 1
        if rec.is_read then
            read = read + 1
        else
            local total = tonumber(rec.total_pages) or 0
            local page = tonumber(rec.last_page) or 0
            if page > 0 and ((total > 0 and page < total) or total == 0) then
                in_progress = in_progress + 1
            end
        end
    end
    return {
        chapters_tracked = tracked,
        chapters_read = read,
        chapters_in_progress = in_progress,
        pages_read = tonumber(state.stats.pages_read) or 0,
        sessions = tonumber(state.stats.sessions) or 0,
        last_opened_at = state.stats.last_opened_at,
    }
end

return TachiKindleProgress
