--[[--
TachiKindleFavorites: persists favorited manga entries across
sessions via LuaSettings (same storage mechanism as repos in
main.lua). A favorite is enough to re-open a manga's chapter list
directly from its source -- source id, manga url/title/cover --
without going through the repo/extension-list flow again.

@module koplugin.TachiKindleFavorites
--]]--

local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")

local TachiKindleFavorites = {}

local settings_file = DataStorage:getSettingsDir() .. "/tachikindle_favorites.lua"
local settings = nil
local favorites = nil

local function ensureLoaded()
    if settings then return end
    settings = LuaSettings:open(settings_file)
    favorites = settings:readSetting("favorites", {})
end

local function keyFor(source_id, manga_url)
    return source_id .. "|" .. manga_url
end

function TachiKindleFavorites:list()
    ensureLoaded()
    return favorites
end

function TachiKindleFavorites:isFavorite(source_id, manga_url)
    ensureLoaded()
    local key = keyFor(source_id, manga_url)
    for _, f in ipairs(favorites) do
        if f.key == key then return true end
    end
    return false
end

function TachiKindleFavorites:add(source_id, source_name, manga)
    ensureLoaded()
    local key = keyFor(source_id, manga.url)
    if self:isFavorite(source_id, manga.url) then return end
    table.insert(favorites, {
        key = key,
        source_id = source_id,
        source_name = source_name,
        title = manga.title,
        url = manga.url,
        cover = manga.cover,
    })
    settings:saveSetting("favorites", favorites)
    settings:flush()
end

function TachiKindleFavorites:remove(source_id, manga_url)
    ensureLoaded()
    local key = keyFor(source_id, manga_url)
    for i, f in ipairs(favorites) do
        if f.key == key then
            table.remove(favorites, i)
            break
        end
    end
    settings:saveSetting("favorites", favorites)
    settings:flush()
end

function TachiKindleFavorites:toggle(source_id, source_name, manga)
    ensureLoaded()
    if self:isFavorite(source_id, manga.url) then
        self:remove(source_id, manga.url)
        return false
    else
        self:add(source_id, source_name, manga)
        return true
    end
end

return TachiKindleFavorites
