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
local _ = require("gettext")

local TachiKindleBrowser = Menu:extend{
    name = "tachikindlebrowser",
    is_popout = false,
    is_borderless = true,
    title = _("TachiKindle Repos"),
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
    for i, repo in ipairs(self.plugin.repos) do
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
    self:switchItemTable(_("TachiKindle Repos"), self:genRepoItemTable())
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
                            self:switchItemTable(_("TachiKindle Repos"), self:genRepoItemTable())
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

function TachiKindleBrowser:isInstalled(ext_id)
    local f = io.open(self:installedSourcePath(ext_id), "r")
    if not f then return false end
    f:close()
    return true
end

function TachiKindleBrowser:removeInstalledExtension(ext_entry)
    local ok, err = os.remove(self:installedSourcePath(ext_entry.id))
    if not ok then
        UIManager:show(InfoMessage:new{ text = _("Remove failed: ") .. tostring(err), timeout = 2 })
        return
    end
    UIManager:show(InfoMessage:new{ text = _("Removed: ") .. tostring(ext_entry.name or ext_entry.id), timeout = 1 })
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
        self:downloadExtension(item.repo_url, item.ext_entry)
        return true
    end
    return true
end

function TachiKindleBrowser:onMenuHold(item)
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
            text = _("(Hold installed extension to remove)"),
            callback = function() end,
        },
    }
    for _, ext in ipairs(parsed.extensions) do
        if ext.id and ext.path then
            local installed = self:isInstalled(ext.id)
            table.insert(item_table, {
                text = string.format("%s%s [%s] (%s)", installed and "✓ " or "", ext.name or ext.id,
                                       ext.lang or "?", ext.content_warning or "SAFE"),
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
        return
    end

    -- Minimal shape check against schema-1.0.json's required
    -- top-level keys -- not full JSON Schema validation, just enough
    -- to reject garbage before writing it to disk.
    local ok, parsed = pcall(JSON.decode, body)
    local required = { "id", "name", "lang", "base_url", "version_code", "endpoints", "selectors" }
    if not ok or type(parsed) ~= "table" then
        UIManager:show(InfoMessage:new{ text = _("Downloaded file is not valid JSON.") })
        return
    end
    for _, key in ipairs(required) do
        if parsed[key] == nil then
            UIManager:show(InfoMessage:new{
                text = _("Downloaded file is missing required field: ") .. key,
            })
            return
        end
    end

    local sources_dir = DataStorage:getDataDir() .. "/tachikindle/sources"
    util.makePath(sources_dir)
    local dest = sources_dir .. "/" .. ext_entry.id .. ".tkext.json"
    local f = io.open(dest, "w")
    if not f then
        UIManager:show(InfoMessage:new{ text = _("Could not write to: ") .. dest })
        return
    end
    f:write(body)
    f:close()

    UIManager:show(InfoMessage:new{
        text = _("Downloaded: ") .. (ext_entry.name or ext_entry.id),
    })
end

return TachiKindleBrowser
