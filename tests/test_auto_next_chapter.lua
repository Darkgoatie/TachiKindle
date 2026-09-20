package.path = './koplugin/tachikindle.koplugin/?.lua;' .. package.path

local shown_widget

package.preload['ui/widget/buttondialog'] = function()
    return {
        new = function(_, o) return o end,
    }
end
package.preload['datastorage'] = function()
    return { getDataDir = function() return '/tmp' end }
end
package.preload['ui/widget/infomessage'] = function()
    return { new = function(_, o) return o end }
end
package.preload['ui/widget/inputdialog'] = function()
    return { new = function(_, o) return o end }
end
package.preload['ui/widget/menu'] = function()
    local M = {}
    function M:extend(o)
        o = o or {}
        setmetatable(o, { __index = self })
        return o
    end
    function M.init() end
    function M:switchItemTable() end
    return M
end
package.preload['ui/uimanager'] = function()
    return {
        show = function(_, w) shown_widget = w end,
        close = function() end,
        forceRePaint = function() end,
        setDirty = function() end,
    }
end
package.preload['tachikindlesource'] = function() return {} end
package.preload['tachikindlereader'] = function()
    return {
        show = function(_, _, _, _, opts)
            -- simulate closing reader at final page
            opts.on_progress(2, 2, true)
        end,
    }
end
package.preload['tachikindlefavorites'] = function()
    return { toggle = function() return false end, isFavorite = function() return false end, list = function() return {} end }
end
package.preload['tachikindleprogress'] = function()
    return {
        getChapterProgress = function() return nil end,
        recordChapterOpen = function() end,
        updateProgress = function() end,
        listContinue = function() return {} end,
        getAnalytics = function() return { chapters_tracked = 0, chapters_read = 0, chapters_in_progress = 0, pages_read = 0, sessions = 0 } end,
        markRead = function() end,
    }
end
package.preload['libs/libkoreader-lfs'] = function()
    return { attributes = function() return nil end, dir = function() return function() return nil end end }
end
package.preload['gettext'] = function() return function(s) return s end end

local Browser = require('tachikindlesourcebrowser')

-- 1) finishing a chapter should call maybeAdvanceToNextChapter
local advanced = false
local original_maybe_advance = Browser.maybeAdvanceToNextChapter
Browser.current_manga = { title = 'Manga', url = 'manga-url' }
Browser.current_chapters = {
    { title = 'Ch1', url = 'ch1' },
    { title = 'Ch2', url = 'ch2' },
}
Browser.maybeAdvanceToNextChapter = function(_, _, chapter)
    if chapter and chapter.url == 'ch1' then advanced = true end
end

local source = {
    def = { id = 'src', name = 'Source' },
    fetchPageList = function() return { 'p1', 'p2' } end,
    chapterCacheStats = function() return { complete = false, saved = 0, total = 2 } end,
}
Browser:openChapter(source, { title = 'Ch1', url = 'ch1' })
assert(advanced, 'should auto-advance hook when chapter closes at last page')
Browser.maybeAdvanceToNextChapter = original_maybe_advance

-- 2) if finished chapter is downloaded, ask before delete+advance
Browser.current_chapters = {
    { title = 'Ch1', url = 'ch1' },
    { title = 'Ch2', url = 'ch2' },
}
local opened_next
Browser.openChapter = function(_, _, chapter)
    opened_next = chapter and chapter.url
end

local source2 = {
    isChapterDownloaded = function(_, chapter_url) return chapter_url == 'ch1' end,
    deleteChapterCache = function() end,
}
Browser:maybeAdvanceToNextChapter(source2, { title = 'Ch1', url = 'ch1' })

assert(shown_widget and shown_widget.buttons and #shown_widget.buttons == 3, 'should show delete/keep/stay prompt')
-- choose keep cache + next chapter
shown_widget.buttons[2][1].callback()
assert(opened_next == 'ch2', 'keep-cache choice should open next chapter')

print('Auto next chapter tests PASS')
