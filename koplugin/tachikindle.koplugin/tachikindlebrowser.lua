--[[--
TachiKindleBrowser: the actual Menu-based UI. Modeled directly on
koreader's built-in opds.koplugin/opdsbrowser.lua (v2026.07.1, the
version installed on the target device) -- same "Menu:extend, tap a
row to go deeper, ButtonDialog for the 'add' action, InputDialog for
URL entry" shape, since OPDS is KOReader's own closest built-in
analog to what this plugin needs.

Unlike OPDS (multi-level catalog tree, book downloads, sync), this
browser has exactly two levels: repo list -> extension list. An
extension is a small JSON file (see extensions/format/schema-1.0.json
in the project root), not a book, so "download" here means "save the
.tkext.json to the plugin's sources dir", not open a document.

@module koplugin.TachiKindleBrowser
--]]--

local ButtonDialog = require("ui/widget/buttondialog")
local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local JSON = require("json")
local util = require("util")
local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")

local TachiKindleBrowser = Menu:extend{
    name = "tachikindlebrowser",
    is_popout = false,
    is_borderless = true,
    title = _("Extensions Manager"),
}

function TachiKindleBrowser:init()
    self.item_table = self:genRepoItemTable()
    self.title_bar_left_icon = "appbar.menu"
    self.onLeftButtonTap = function()
        self:showRepoMenu()
    end
    Menu.init(self)
end

function TachiKindleBrowser:genRepoItemTable()
    local item_table = {}
    local repos = self.plugin and self.plugin.repos or {}
    for i, repo in ipairs(repos) do
        table.insert(item_table, {
            text = repo.title or repo.url,
            mandatory_dim = true,
            mandatory = "",
            idx = i,
            repo = repo,
        })
    end
    return item_table
end

function TachiKindleBrowser:showInstalledExtensions()
    local installed = self:listInstalledExtensions()
    local item_table = {
        {
            text = _("(Tap to remove, hold to remove)"),
            callback = function() end,
        },
    }
    for _, ext in ipairs(installed) do
        table.insert(item_table, {
            text = string.format("%s [%s] (%s) v%d", ext.name or ext.id, ext.lang or "?", ext.content_warning or "SAFE", tonumber(ext.version_code) or 0),
            installed_ext = ext,
        })
    end
    if #item_table == 1 then
        UIManager:show(InfoMessage:new{ text = _("No installed extensions."), timeout = 1 })
        return
    end
    self:switchItemTable(_("Installed Extensions"), item_table)
end

function TachiKindleBrowser:installedVersionFor(ext_id)
    local meta = self:installedSourceMetadata(ext_id)
    return meta and tonumber(meta.version_code) or nil
end

function TachiKindleBrowser:formatRepoItemText(ext)
    local installed_version = self:installedVersionFor(ext.id)
    local state_prefix = ""
    if installed_version then
        if tonumber(ext.version_code) and tonumber(ext.version_code) > installed_version then
            state_prefix = "↑ "
        else
            state_prefix = "✓ "
        end
    end
    local version_txt = tonumber(ext.version_code) and (" v" .. tostring(ext.version_code)) or ""
    return string.format("%s%s [%s] (%s)%s", state_prefix, ext.name or ext.id, ext.lang or "?", ext.content_warning or "SAFE", version_txt)
end

function TachiKindleBrowser:downloadActionLabel(ext)
    if not self:isInstalled(ext.id) then
        return _("Download")
    end
    local installed_version = self:installedVersionFor(ext.id)
    local repo_version = tonumber(ext.version_code)
    if installed_version and repo_version and repo_version > installed_version then
        return _("Update")
    end
    return _("Reinstall")
end

function TachiKindleBrowser:showExtensionActions(repo_url, ext_entry)
    local dialog
    dialog = ButtonDialog:new{
        buttons = {
            {{
                text = self:downloadActionLabel(ext_entry),
                callback = function()
                    UIManager:close(dialog)
                    if self:downloadExtension(repo_url, ext_entry) then
                        self:openRepo({ title = self.title, url = repo_url })
                    end
                end,
                align = "left",
            }},
            {{
                text = self:isInstalled(ext_entry.id) and _("Remove installed") or _("Remove installed (not present)"),
                callback = function()
                    UIManager:close(dialog)
                    if not self:isInstalled(ext_entry.id) then
                        UIManager:show(InfoMessage:new{ text = _("Extension is not installed."), timeout = 1 })
                        return
                    end
                    if self:removeInstalledExtension(ext_entry) then
                        self:openRepo({ title = self.title, url = repo_url })
                    end
                end,
                align = "left",
            }},
            {{
                text = _("Cancel"),
                callback = function() UIManager:close(dialog) end,
                align = "left",
            }},
        },
    }
    UIManager:show(dialog)
end

function TachiKindleBrowser:showRepoMenu()
    local dialog
    dialog = ButtonDialog:new{
        buttons = {
            {{
                text = _("Add repo"),
                callback = function()
                    UIManager:close(dialog)
                    self:addRepo()
                end,
                align = "left",
            }},
            {{
                text = _("Installed extensions"),
                callback = function()
                    UIManager:close(dialog)
                    self:showInstalledExtensions()
                end,
                align = "left",
            }},
            {{
                text = _("Remove selected repo"),
                callback = function()
                    UIManager:close(dialog)
                    self:removeSelectedRepo()
                end,
                align = "left",
            }},
        },
    }
    UIManager:show(dialog)
end

function TachiKindleBrowser:removeSelectedRepo()
    local idx = self.selected_item and self.selected_item.idx
    if not idx then
        UIManager:show(InfoMessage:new{ text = _("Select a repo row first."), timeout = 1 })
        return
    end
    table.remove(self.plugin.repos, idx)
    self.plugin:saveRepos()
    self:switchItemTable(_("Extensions Manager"), self:genRepoItemTable())
    UIManager:show(InfoMessage:new{ text = _("Repo removed"), timeout = 1 })
end

function TachiKindleBrowser:addRepo()
    local input_dialog
    input_dialog = InputDialog:new{
        title = _("Add TachiKindle repo"),
        input_hint = _("https://raw.githubusercontent.com/user/repo/main"),
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
                    text = _("Add"),
                    is_enter_default = true,
                    callback = function()
                        local url = input_dialog:getInputText()
                        UIManager:close(input_dialog)
                        if url and url ~= "" then
                            table.insert(self.plugin.repos, { title = url, url = url })
                            self.plugin:saveRepos()
                            self:switchItemTable(_("Extensions Manager"), self:genRepoItemTable())
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function TachiKindleBrowser:installedSourcePath(ext_id)
    return DataStorage:getDataDir() .. "/tachikindle/sources/" .. tostring(ext_id) .. ".tkext.json"
end

function TachiKindleBrowser:installedSourceMetadata(ext_id)
    local f = io.open(self:installedSourcePath(ext_id), "r")
    if not f then return nil end
    local body = f:read("*a")
    f:close()
    local ok, parsed = pcall(JSON.decode, body)
    if not ok or type(parsed) ~= "table" then return nil end
    return parsed
end

function TachiKindleBrowser:isInstalled(ext_id)
    return self:installedSourceMetadata(ext_id) ~= nil
end

function TachiKindleBrowser:listInstalledExtensions()
    local sources_dir = DataStorage:getDataDir() .. "/tachikindle/sources"
    if lfs.attributes(sources_dir, "mode") ~= "directory" then
        return {}
    end
    local list = {}
    for name in lfs.dir(sources_dir) do
        if name ~= "." and name ~= ".." and name:match("%.tkext%.json$") then
            local ext_id = name:gsub("%.tkext%.json$", "")
            local meta = self:installedSourceMetadata(ext_id)
            if meta then
                table.insert(list, {
                    id = meta.id or ext_id,
                    name = meta.name or ext_id,
                    lang = meta.lang or "?",
                    version_code = tonumber(meta.version_code) or 0,
                    content_warning = meta.content_warning or "SAFE",
                    path = self:installedSourcePath(ext_id),
                })
            end
        end
    end
    table.sort(list, function(a, b)
        return tostring(a.name):lower() < tostring(b.name):lower()
    end)
    return list
end

function TachiKindleBrowser:removeInstalledExtension(ext_entry)
    local ok, err = os.remove(self:installedSourcePath(ext_entry.id))
    if not ok then
        UIManager:show(InfoMessage:new{ text = _("Remove failed: ") .. tostring(err), timeout = 2 })
        return false
    end
    UIManager:show(InfoMessage:new{ text = _("Removed: ") .. tostring(ext_entry.name or ext_entry.id), timeout = 1 })
    return true
end

-- Tapping a repo row fetches its index.json and shows the extension
-- list; tapping an extension row downloads that .tkext.json file.
function TachiKindleBrowser:onMenuSelect(item)
    if item.repo then
        self.selected_item = item
        self:openRepo(item.repo)
        return true
    end
    if item.ext_entry then
        self:showExtensionActions(item.repo_url, item.ext_entry)
        return true
    end
    if item.installed_ext then
        if self:removeInstalledExtension(item.installed_ext) then
            self:showInstalledExtensions()
        end
        return true
    end
    return true
end

function TachiKindleBrowser:onMenuHold(item)
    if item.installed_ext then
        if self:removeInstalledExtension(item.installed_ext) then
            self:showInstalledExtensions()
        end
        return true
    end
    if item.ext_entry and self:isInstalled(item.ext_entry.id) then
        self:removeInstalledExtension(item.ext_entry)
        if item.repo_url then
            self:openRepo({ title = self.title, url = item.repo_url })
        end
        return true
    end
    return true
end

function TachiKindleBrowser:openRepo(repo)
    UIManager:show(InfoMessage:new{ text = _("Loading repo index…"), timeout = 1 })

    local body, err = self.plugin:httpGet(repo.url .. "/index.json")
    if not body then
        UIManager:show(InfoMessage:new{ text = _("Failed to fetch repo: ") .. tostring(err) })
        return
    end

    local ok, parsed = pcall(JSON.decode, body)
    if not ok or type(parsed) ~= "table" or type(parsed.extensions) ~= "table" then
        UIManager:show(InfoMessage:new{ text = _("Repo index is not valid JSON.") })
        return
    end

    local item_table = {
        {
            text = _("(Tap extension for download/update/remove; hold installed to remove)"),
            callback = function() end,
        },
    }
    for _, ext in ipairs(parsed.extensions) do
        if ext.id and ext.path then
            table.insert(item_table, {
                text = self:formatRepoItemText(ext),
                repo_url = repo.url,
                ext_entry = ext,
            })
        end
    end
    if #item_table == 1 then
        UIManager:show(InfoMessage:new{ text = _("No extensions in this repo.") })
        return
    end

    self:switchItemTable(parsed.repo_name or repo.title, item_table)
end

function TachiKindleBrowser:downloadExtension(repo_url, ext_entry)
    local file_url = repo_url .. "/" .. ext_entry.path
    local body, err = self.plugin:httpGet(file_url)
    if not body then
        UIManager:show(InfoMessage:new{ text = _("Download failed: ") .. tostring(err) })
        return false
    end

    -- Minimal shape check against schema-1.0.json's required
    -- top-level keys -- not full JSON Schema validation, just enough
    -- to reject garbage before writing it to disk.
    local ok, parsed = pcall(JSON.decode, body)
    local required = { "id", "name", "lang", "base_url", "version_code", "source_script", "endpoints", "selectors" }
    if not ok or type(parsed) ~= "table" then
        UIManager:show(InfoMessage:new{ text = _("Downloaded file is not valid JSON.") })
        return false
    end
    for _, key in ipairs(required) do
        if parsed[key] == nil then
            UIManager:show(InfoMessage:new{
                text = _("Downloaded file is missing required field: ") .. key,
            })
            return false
        end
    end

    local sources_dir = DataStorage:getDataDir() .. "/tachikindle/sources"
    util.makePath(sources_dir)
    local dest = sources_dir .. "/" .. tostring(parsed.id) .. ".tkext.json"
    local f = io.open(dest, "w")
    if not f then
        UIManager:show(InfoMessage:new{ text = _("Could not write to: ") .. dest })
        return false
    end
    f:write(body)
    f:close()

    UIManager:show(InfoMessage:new{
        text = _("Downloaded: ") .. (parsed.name or parsed.id),
    })
    return true
end

return TachiKindleBrowser
