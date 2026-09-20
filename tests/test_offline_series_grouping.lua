package.path = './koplugin/tachikindle.koplugin/?.lua;' .. package.path

package.preload['ui/widget/buttondialog'] = function() return { new = function(_, o) return o end } end
package.preload['datastorage'] = function() return { getDataDir = function() return '/tmp' end } end
package.preload['ui/widget/infomessage'] = function() return { new = function(_, o) return o end } end
package.preload['ui/widget/inputdialog'] = function() return { new = function(_, o) return o end } end
package.preload['ui/widget/menu'] = function()
    local M = {}
    function M:extend(o) o = o or {}; setmetatable(o, { __index = self }); return o end
    function M.init() end
    function M:switchItemTable() end
    return M
end
package.preload['ui/uimanager'] = function() return { show=function() end, close=function() end, forceRePaint=function() end, setDirty=function() end } end
package.preload['tachikindlesource'] = function() return {} end
package.preload['tachikindlereader'] = function() return { show = function() end } end
package.preload['tachikindlefavorites'] = function() return { toggle=function() return false end, isFavorite=function() return false end, list=function() return {} end } end
package.preload['tachikindleprogress'] = function() return { getChapterProgress=function() return nil end, recordChapterOpen=function() end, updateProgress=function() end, listContinue=function() return {} end, getAnalytics=function() return { chapters_tracked=0, chapters_read=0, chapters_in_progress=0, pages_read=0, sessions=0 } end, markRead=function() end } end
package.preload['libs/libkoreader-lfs'] = function() return { attributes=function() return nil end, dir=function() return function() return nil end end } end
package.preload['gettext'] = function() return function(s) return s end end

local Browser = require('tachikindlesourcebrowser')

local source = {
    def = { id = 'weebcentral', name = 'Weeb Central' },
    listCachedChapters = function()
        return {
            { manga_title = 'Kagurabachi', chapter_title = 'Chapter 66', chapter_url = 'u66', size_bytes = 1000, complete = true },
            { manga_title = 'Kagurabachi', chapter_title = 'Chapter 123', chapter_url = 'u123', size_bytes = 1000, complete = true },
        }
    end,
}

Browser.loadAllSources = function() return { [source.def.id] = source } end

local series, total = Browser:collectOfflineSeries()
assert(#series == 1, 'should group by series')
assert(total == 2000, 'should sum cache size')
assert(series[1].min_ch == 66 and series[1].max_ch == 123, 'should compute chapter range')
local label = Browser:offlineSeriesLabel(series[1])
assert(label == 'Kagurabachi [Weeb Central] 66-123', 'label format should include source and range')

print('Offline series grouping test PASS')
