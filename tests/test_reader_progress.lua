package.path = './koplugin/tachikindle.koplugin/?.lua;' .. package.path

local shown
package.preload['ui/widget/imageviewer'] = function()
    return {
        new = function(_, o)
            o.current_image = 1
            function o:switchToImageNum(num)
                self.current_image = num
                return true
            end
            function o:closeWidget() self._closed = true end
            function o:onTap() self.buttons_visible = not self.buttons_visible; return true end
            function o:update() end
            return o
        end,
    }
end
package.preload['ui/renderimage'] = function()
    return { renderImageData = function() return {ok=true} end }
end
package.preload['ffi/blitbuffer'] = function()
    return { TYPE_BBRGB32 = 1, COLOR_WHITE = 1, new = function() return {fill=function() end} end }
end
package.preload['ui/uimanager'] = function()
    return {
        show = function(self, v) shown = v end,
        forceRePaint = function() end,
    }
end
package.preload['ui/widget/infomessage'] = function()
    return { new = function(_, o) return o end }
end
package.preload.gettext = function() return function(s) return s end end

local Reader = require('tachikindlereader')

local progress = {}
local source = {
    fetchChapterPage = function(_, _, _, _) return 'bytes', nil end,
}
Reader.show(source, 'https://example/ch', {'u1','u2','u3'}, 'Ch', {
    start_page = 2,
    on_progress = function(page, total, closing)
        progress[#progress+1] = {page=page,total=total,closing=closing}
    end,
})
assert(shown, 'viewer should be shown')
assert(progress[1].page == 2 and progress[1].total == 3 and progress[1].closing == false, 'initial callback uses start page')
shown:switchToImageNum(3)
assert(progress[#progress].page == 3 and progress[#progress].closing == false, 'switch should report progress')
shown:onSwipe(nil, { direction = 'east' })
assert(progress[#progress].page == 2 and progress[#progress].closing == false, 'east swipe should go previous page')
shown:onSwipe(nil, { direction = 'west' })
assert(progress[#progress].page == 3 and progress[#progress].closing == false, 'west swipe should go next page')
shown:closeWidget()
assert(progress[#progress].closing == true and progress[#progress].page == 3, 'close should report final position')
print('Reader progress callback tests PASS')
