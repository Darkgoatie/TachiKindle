package.path = './koplugin/tachikindle.koplugin/?.lua;' .. package.path

local store = {}
package.preload.datastorage = function()
    return { getSettingsDir = function() return '/virtual' end }
end
package.preload.luasettings = function()
    return {
        open = function(_)
            return {
                readSetting = function(_, key, default)
                    if store[key] == nil then return default end
                    return store[key]
                end,
                saveSetting = function(_, key, value) store[key] = value end,
                flush = function() end,
            }
        end,
    }
end

local Progress = require('tachikindleprogress')

local function assertEq(a, b, msg)
    assert(a == b, (msg or 'values differ') .. ': ' .. tostring(a) .. ' != ' .. tostring(b))
end

Progress:recordChapterOpen('en.demo', 'Demo Source', {title='Manga A', url='https://manga/a'}, {title='Ch 1', url='https://manga/a/ch1'}, 10)
Progress:updateProgress('en.demo', 'Demo Source', {title='Manga A', url='https://manga/a'}, {title='Ch 1', url='https://manga/a/ch1'}, 3, 10)
local p = Progress:getChapterProgress('en.demo', 'https://manga/a/ch1')
assertEq(p.last_page, 3, 'last page')
assertEq(p.total_pages, 10, 'total pages')
assert(not p.is_read, 'should not be marked read yet')

Progress:markRead('en.demo', 'Demo Source', {title='Manga A', url='https://manga/a'}, {title='Ch 1', url='https://manga/a/ch1'}, true)
p = Progress:getChapterProgress('en.demo', 'https://manga/a/ch1')
assert(p.is_read, 'markRead(true)')
assertEq(p.last_page, 10, 'read should set page to total')

Progress:markRead('en.demo', 'Demo Source', {title='Manga A', url='https://manga/a'}, {title='Ch 1', url='https://manga/a/ch1'}, false)
p = Progress:getChapterProgress('en.demo', 'https://manga/a/ch1')
assert(not p.is_read, 'markRead(false)')

Progress:updateProgress('en.demo', 'Demo Source', {title='Manga A', url='https://manga/a'}, {title='Ch 1', url='https://manga/a/ch1'}, 10, 10)
assert(Progress:isRead('en.demo', 'https://manga/a/ch1'), 'page==total should mark read')

Progress:updateProgress('en.demo', 'Demo Source', {title='Manga A', url='https://manga/a'}, {title='Ch 2', url='https://manga/a/ch2'}, 2, 12)
local list = Progress:listContinue(10)
assert(#list >= 1, 'continue list must include in-progress chapters')
assertEq(list[1].chapter_url, 'https://manga/a/ch2', 'most recent in-progress first')

local analytics = Progress:getAnalytics()
assertEq(analytics.chapters_tracked, 2, 'tracked chapters')
assertEq(analytics.chapters_read, 1, 'read chapters')
assertEq(analytics.chapters_in_progress, 1, 'in-progress chapters')
assert(analytics.pages_read >= 12, 'pages_read should accumulate')

print('Progress tracking tests PASS')
