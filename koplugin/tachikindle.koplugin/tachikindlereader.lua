--[[--
TachiKindleReader: shows a chapter's pages using KOReader's built-in
ImageViewer widget (frontend/ui/widget/imageviewer.lua), fed a lazy
"images_list" of loader functions -- each page's bytes are fetched
and decoded only when the reader actually swipes to it
(ImageViewer:switchToImageNum calls image() when image is a
function, confirmed by reading imageviewer.lua directly). Nothing is
ever written to disk: this is the "read online, don't download"
requirement.

Decoding raw HTTP bytes into a BlitBuffer uses RenderImage (frontend/
ui/renderimage.lua), which auto-detects JPEG/GIF/WebP/otherwise-
MuPDF -- covers what manga sites actually serve.

@module koplugin.TachiKindleReader
--]]--

local ImageViewer = require("ui/widget/imageviewer")
local RenderImage = require("ui/renderimage")
local Blitbuffer = require("ffi/blitbuffer")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local _ = require("gettext")

local TachiKindleReader = {}

-- A small blank placeholder bitmap, used whenever a page's bytes
-- fail to fetch or fail to decode. ImageWidget:_render() calls
-- error("cannot render image") when handed nil (confirmed via real
-- crash log: fetching a chapter with even one bad/undecodable page
-- crashed the whole reader, not just that page) -- returning a real,
-- if blank, BlitBuffer instead means one broken page shows an empty
-- square rather than taking down the app.
local function placeholderImage()
    local bb = Blitbuffer.new(600, 800, Blitbuffer.TYPE_BBRGB32)
    bb:fill(Blitbuffer.COLOR_WHITE)
    return bb
end

-- source: a loaded TachiKindleSource instance
-- chapter_url: canonical chapter URL used as cache key
-- page_urls: string array of page image URLs (from fetchPageList)
function TachiKindleReader.show(source, chapter_url, page_urls, chapter_title, options)
    options = options or {}
    if #page_urls == 0 then
        UIManager:show(InfoMessage:new{ text = _("This chapter has no pages.") })
        return
    end

    local images_list = setmetatable({}, {
        __len = function() return #page_urls end,
    })
    for i, url in ipairs(page_urls) do
        images_list[i] = function()
            local body, err = source:fetchChapterPage(chapter_url, i, url)
            if not body then
                UIManager:show(InfoMessage:new{
                    text = _("Failed to load page ") .. i .. ": " .. tostring(err),
                })
                return placeholderImage()
            end
            local ok, bb = pcall(function() return RenderImage:renderImageData(body, #body) end)
            if not ok or not bb then
                UIManager:show(InfoMessage:new{
                    text = _("Could not decode page ") .. i,
                })
                return placeholderImage()
            end
            return bb
        end
    end
    -- images_list_nb can't rely on plain #images_list since it holds
    -- functions, not the final decoded images -- give it explicitly.
    images_list.image_disposable = true

    local viewer = ImageViewer:new{
        image = images_list,
        images_list_nb = #page_urls,
        fullscreen = true,
        -- Start clean (no giant chapter bar). A center tap toggles controls,
        -- and we mirror the title bar visibility to that same toggle so the
        -- top bar appears only on demand.
        with_title_bar = false,
        title_text = chapter_title or "",
    }

    local total_pages = #page_urls
    local current_page = math.max(1, math.min(tonumber(options.start_page) or 1, total_pages))
    local function notify(closing)
        if type(options.on_progress) == "function" then
            options.on_progress(current_page, total_pages, closing and true or false)
        end
    end
    notify(false)

    local _orig_switchToImageNum = viewer.switchToImageNum
    function viewer:switchToImageNum(num)
        local result = _orig_switchToImageNum(self, num)
        current_page = math.max(1, math.min(tonumber(self.current_image) or tonumber(num) or 1, total_pages))
        notify(false)
        return result
    end

    local _orig_closeWidget = viewer.closeWidget
    function viewer:closeWidget(...)
        notify(true)
        return _orig_closeWidget(self, ...)
    end

    -- Disable tap-to-open viewer controls (rotate/close menu) to avoid
    -- accidental popups while reading.
    function viewer:onTap(_arg, _ges)
        return true
    end

    local function prevPage()
        local target = math.max(1, (tonumber(viewer.current_image) or current_page or 1) - 1)
        if target ~= (tonumber(viewer.current_image) or current_page or 1) then
            viewer:switchToImageNum(target)
        end
        return true
    end

    local function nextPage()
        local target = math.min(total_pages, (tonumber(viewer.current_image) or current_page or 1) + 1)
        if target ~= (tonumber(viewer.current_image) or current_page or 1) then
            viewer:switchToImageNum(target)
        end
        return true
    end

    -- Explicit horizontal swipe paging (left/right) so slide gestures always
    -- advance pages even when default viewer gesture behavior changes.
    function viewer:onSwipe(_arg, ges)
        local dir = ges and (ges.direction or ges.gesture)
        if dir == "west" or dir == "left" then
            return nextPage()
        elseif dir == "east" or dir == "right" then
            return prevPage()
        end

        local dx = 0
        local dy = 0
        if ges then
            dx = tonumber(ges.dx or (ges.distance and ges.distance.x)) or 0
            dy = tonumber(ges.dy or (ges.distance and ges.distance.y)) or 0
            if dx == 0 and ges.pos and ges.start_pos then
                dx = tonumber(ges.pos.x) - tonumber(ges.start_pos.x)
                dy = tonumber(ges.pos.y) - tonumber(ges.start_pos.y)
            end
        end
        if math.abs(dx) > math.abs(dy) and dx ~= 0 then
            if dx < 0 then return nextPage() end
            return prevPage()
        end
        return false
    end

    UIManager:show(viewer)
    if current_page > 1 then
        viewer:switchToImageNum(current_page)
    end
end

return TachiKindleReader
