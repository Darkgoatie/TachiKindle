--[[--
TachiKindleUpdater: self-update the TachiKindle *plugin's own code*
(koplugin/tachikindle.koplugin/*) from the real plugin repo at
https://github.com/Darkgoatie/TachiKindle. Unrelated to and entirely
separate from tachikindlebrowser.lua's Extensions Manager, which
manages downloadable *manga sources* (extensions/*.tkext.json) from
the separate tachikindle-sources catalog repo -- this module never
touches that code path.

== Version tracking convention ==
Two separate files ship at the plugin root (next to main.lua):
  - VERSION: a human-facing semver string (e.g. "1.0.0"), bumped
    manually for real releases; purely cosmetic now, not used for
    update-check comparisons.
  - BUILD: the full commit SHA from DEV_BRANCH that produced the
    currently-installed files. This is what update checks actually
    compare, since this project ships continuously from a dev branch
    rather than cutting a GitHub release per change -- every push to
    DEV_BRANCH is treated as a new "build", regardless of whether
    VERSION was touched.

== Update-check source: commits API on DEV_BRANCH ==
Confirmed live via curl against the real repo:
  GET https://api.github.com/repos/Darkgoatie/TachiKindle/commits?sha=test/source-script-format-system&per_page=1
  -> 200, real commit object with a real "sha" field.
This is the sole update-check source now (a prior release-tag-based
check was removed: the repo's actual GitHub Releases are cut
infrequently from `main` and had drifted far behind DEV_BRANCH, so
comparing against them made the updater report "up to date" even
when DEV_BRANCH -- where all real work happens -- had moved on).

== Apply-update mechanism: real zip extraction via ffi/archiver ==
Confirmed by reading a local reference KOReader checkout
(frontend/ui/otamanager.lua for KOReader's own OTA self-updater, and
koreader-base/ffi/archiver.lua, the libarchive FFI binding it and
plugins/archiveviewer.koplugin/main.lua both use) that KOReader ships
a real, already-used-by-a-real-koplugin zip/archive reader accessible
from Lua as `require("ffi/archiver")` (Archiver.Reader, backed by
libarchive, with FORMAT_ALIASES mapping "epub" -> "zip" and real
:extractToPath()/:iterate() methods). archiveviewer.koplugin uses this
exact API to browse/extract .zip and .cbz files on real installs,
including Kindle, so this is a confirmed-available capability, not a
guess -- extraction is used here rather than re-downloading each file
individually via GitHub's git/trees API, since:
  1. It's one HTTP request (the zipball) instead of O(files) requests,
     which matters on a Kindle's slow/unreliable wifi and avoids
     GitHub API rate limits (60 req/hr unauthenticated).
  2. It atomically captures a consistent tree snapshot (no risk of
     racing a mid-update push upstream between per-file fetches).
  3. It reuses an already-shipped, already-tested KOReader capability
     instead of adding a new one.
If ffi/archiver ever turns out to be unavailable on some target device
(unconfirmed for every possible KOReader build/device combination --
only confirmed present in the reference checkout and used by a real
bundled koplugin), loadModule() below fails loudly with a clear error
instead of silently doing nothing.

== KOReader plugins cannot hot-reload themselves ==
KOReader's own self-updater (frontend/ui/otamanager.lua) always ends a
successful update with Device:install(), which restarts/relaunches the
whole KOReader process to pick up new code -- it does not attempt to
swap running Lua modules in place. No other real KOReader plugin found
in the reference checkout attempts in-process plugin hot-reload either.
Consistent with that, this module deliberately does NOT try to
re-require() the updated files after writing them; it writes the new
files to disk and then instructs the user to fully restart KOReader,
exactly like KOReader's own OTA flow does.
--]]--

local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local ButtonDialog = require("ui/widget/buttondialog")
local UIManager = require("ui/uimanager")
local JSON = require("json")
local util = require("util")
local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")

local COMMITS_URL = "https://api.github.com/repos/Darkgoatie/TachiKindle/commits?sha=test/source-script-format-system&per_page=1"
local DEV_BRANCH = "test/source-script-format-system"

local TachiKindleUpdater = {}

-- Plugin's own on-disk root, e.g. .../plugins/tachikindle.koplugin.
-- debug.getinfo is used (not an assumed constant path) so this works
-- regardless of where KOReader actually installed the plugin.
function TachiKindleUpdater.pluginDir()
    local info = debug.getinfo(1, "S")
    local src = info and info.source or ""
    src = src:gsub("^@", "")
    return src:match("^(.*)[/\\][^/\\]+$") or "."
end

function TachiKindleUpdater.versionFilePath()
    return TachiKindleUpdater.pluginDir() .. "/VERSION"
end

-- Separate from VERSION (a human-facing semver string that's bumped
-- manually, e.g. for a real release). BUILD tracks the actual
-- installed commit SHA from DEV_BRANCH, since every push is treated
-- as a build regardless of whether VERSION was touched.
function TachiKindleUpdater.buildFilePath()
    return TachiKindleUpdater.pluginDir() .. "/BUILD"
end

function TachiKindleUpdater:readLocalBuild()
    local f = io.open(self.buildFilePath(), "r")
    if not f then return nil end
    local v = f:read("*a")
    f:close()
    if not v then return nil end
    return v:gsub("%s+$", ""):gsub("^%s+", "")
end

function TachiKindleUpdater:writeLocalBuild(sha)
    local f = io.open(self.buildFilePath(), "w")
    if not f then return false, _("Could not write BUILD file") end
    f:write(tostring(sha) .. "\n")
    f:close()
    return true
end

-- Read the locally-installed version marker. Returns a trimmed
-- string (e.g. "1.0.0") or nil if the VERSION file is missing
-- (older install predating this feature) -- callers must treat nil
-- as "unknown, assume update available" rather than crashing.
function TachiKindleUpdater:readLocalVersion()
    local f = io.open(self.versionFilePath(), "r")
    if not f then return nil end
    local v = f:read("*a")
    f:close()
    if not v then return nil end
    return v:gsub("%s+$", ""):gsub("^%s+", "")
end

function TachiKindleUpdater:writeLocalVersion(version)
    local f = io.open(self.versionFilePath(), "w")
    if not f then return false, _("Could not write VERSION file") end
    f:write(tostring(version) .. "\n")
    f:close()
    return true
end

-- Parse a semver-ish "1.2.3" (optional leading "v", optional
-- trailing suffix like "-rc1" which is ignored for comparison
-- purposes) into {major, minor, patch}. Returns nil on malformed
-- input rather than guessing.
local function parseVersion(v)
    if type(v) ~= "string" then return nil end
    v = v:gsub("^v", "")
    local major, minor, patch = v:match("^(%d+)%.(%d+)%.(%d+)")
    if not major then
        major, minor = v:match("^(%d+)%.(%d+)")
        patch = "0"
    end
    if not major then
        major = v:match("^(%d+)")
        minor, patch = "0", "0"
    end
    if not major then return nil end
    return { tonumber(major), tonumber(minor), tonumber(patch) }
end

-- Returns true if `latest` is strictly newer than `current`.
-- Malformed/nil versions on either side are treated as "can't prove
-- it's not newer" -> true, so users aren't silently stuck on a broken
-- comparison forever; this mirrors readLocalVersion()'s nil handling.
function TachiKindleUpdater.isNewer(current, latest)
    local c, l = parseVersion(current), parseVersion(latest)
    if not c or not l then return true end
    for i = 1, 3 do
        if l[i] > c[i] then return true end
        if l[i] < c[i] then return false end
    end
    return false
end

-- Fetch the latest build. "Build" == latest commit on DEV_BRANCH: every
-- push is a build, regardless of whether VERSION or a release tag was
-- bumped. Returns a table:
--   { kind = "commit", version = "<7-char sha>", sha = "<full sha>", zip_url = ... }
-- or nil, err_message. (A real GitHub release, if one exists, is not
-- consulted here anymore -- see module comment for why build-per-commit
-- was chosen over release-per-version for this project's workflow.)
function TachiKindleUpdater:fetchLatest(plugin)
    local commits_body, commits_err = plugin:httpGet(COMMITS_URL)
    if not commits_body then
        return nil, commits_err or _("Network error while checking for updates")
    end
    local ok, parsed = pcall(JSON.decode, commits_body)
    if not ok or type(parsed) ~= "table" or not parsed[1] or not parsed[1].sha then
        return nil, _("Unexpected response from GitHub commits API")
    end
    local sha = parsed[1].sha
    return {
        kind = "commit",
        version = sha:sub(1, 7),
        sha = sha,
        zip_url = "https://github.com/Darkgoatie/TachiKindle/archive/" .. sha .. ".zip",
    }
end

-- Entry point wired from main.lua's menu. Always user-initiated;
-- never called automatically/on a timer.
function TachiKindleUpdater:checkForUpdates(plugin)
    UIManager:show(InfoMessage:new{ text = _("Checking for updates…"), timeout = 1 })

    local latest, err = self:fetchLatest(plugin)
    if not latest then
        UIManager:show(InfoMessage:new{
            text = _("Update check failed: ") .. tostring(err),
        })
        return
    end

    local current_build = self:readLocalBuild()
    local update_available = (current_build == nil) or (current_build ~= latest.sha)

    if not update_available then
        UIManager:show(InfoMessage:new{
            text = _("TachiKindle is up to date (build ") .. tostring(latest.version) .. ")",
            timeout = 2,
        })
        return
    end

    local dialog
    local current_label = current_build and current_build:sub(1, 7) or _("unknown")
    local latest_label = latest.version
    dialog = ButtonDialog:new{
        title = _("Update available"),
        title_align = "center",
        buttons = {
            {{
                text = _("Not now"),
                callback = function() UIManager:close(dialog) end,
                align = "left",
            }},
            {{
                text = _("Update now"),
                callback = function()
                    UIManager:close(dialog)
                    self:applyUpdate(plugin, latest)
                end,
                align = "left",
            }},
        },
        text = string.format(
            _("A new build of TachiKindle is available.\n\nInstalled build: %s\nAvailable build: %s\n\nUpdating will replace the plugin's own files. Your settings and downloaded sources are not affected. KOReader must be restarted afterwards."),
            tostring(current_label), tostring(latest_label)
        ),
    }
    UIManager:show(dialog)
end

-- Load ffi/archiver, KOReader's real libarchive-backed zip reader
-- (see module comment for why this is confirmed-available rather
-- than assumed). Isolated into its own function so a missing/broken
-- archiver on some exotic build fails with one clear message instead
-- of a raw require() traceback deep inside applyUpdate.
function TachiKindleUpdater:loadArchiver()
    local ok, Archiver = pcall(require, "ffi/archiver")
    if not ok or type(Archiver) ~= "table" or not Archiver.Reader then
        return nil, _("This KOReader build does not provide ffi/archiver; cannot extract the update archive.")
    end
    return Archiver
end

-- Download the GitHub archive zip to a temp file, then extract only
-- the koplugin/tachikindle.koplugin/ subtree over the currently
-- installed plugin directory. GitHub codeload zips wrap all content
-- in a single top-level "<repo>-<ref>/" directory, so entries are
-- matched by suffix on "koplugin/tachikindle.koplugin/".
function TachiKindleUpdater:applyUpdate(plugin, latest)
    local Archiver, arch_err = self:loadArchiver()
    if not Archiver then
        UIManager:show(InfoMessage:new{ text = arch_err })
        return
    end

    UIManager:show(InfoMessage:new{ text = _("Downloading update…"), timeout = 1 })

    local zip_body, dl_err = plugin:httpGet(latest.zip_url)
    if not zip_body or #zip_body == 0 then
        UIManager:show(InfoMessage:new{
            text = _("Download failed: ") .. tostring(dl_err or _("empty response")),
        })
        return
    end

    local tmp_dir = DataStorage:getDataDir() .. "/tachikindle/update_tmp"
    util.makePath(tmp_dir)
    local zip_path = tmp_dir .. "/update.zip"
    local f = io.open(zip_path, "wb")
    if not f then
        UIManager:show(InfoMessage:new{ text = _("Could not write temp file: ") .. zip_path })
        return
    end
    f:write(zip_body)
    f:close()

    local reader = Archiver.Reader:new()
    if not reader:open(zip_path) then
        UIManager:show(InfoMessage:new{
            text = _("Could not open downloaded archive: ") .. tostring(reader.err or "?"),
        })
        os.remove(zip_path)
        return
    end

    local plugin_dir = self.pluginDir()
    local marker = "koplugin/tachikindle.koplugin/"
    local extracted, failed = 0, 0
    local last_err

    for entry in reader:iterate() do
        if entry.mode == "file" then
            local idx = entry.path:find(marker, 1, true)
            if idx then
                local rel_path = entry.path:sub(idx + #marker)
                if rel_path ~= "" then
                    local dest_path = plugin_dir .. "/" .. rel_path
                    local dest_dir = dest_path:match("^(.*)[/\\][^/\\]+$")
                    if dest_dir then util.makePath(dest_dir) end
                    if reader:extractToPath(entry.path, dest_path) then
                        extracted = extracted + 1
                    else
                        failed = failed + 1
                        last_err = reader.err
                    end
                end
            end
        end
    end
    reader:close()
    os.remove(zip_path)

    if extracted == 0 then
        UIManager:show(InfoMessage:new{
            text = _("Update failed: no matching plugin files found in the downloaded archive (unexpected archive layout)."),
        })
        return
    end
    if failed > 0 then
        UIManager:show(InfoMessage:new{
            text = string.format(
                _("Update partially failed: %d file(s) updated, %d failed (%s). Some plugin files may now be mismatched -- reinstall manually if TachiKindle misbehaves."),
                extracted, failed, tostring(last_err or "?")
            ),
        })
        return
    end

    self:writeLocalBuild(latest.sha)

    UIManager:show(InfoMessage:new{
        text = _("TachiKindle updated successfully. Please restart KOReader to load the new version."),
    })
end

return TachiKindleUpdater
