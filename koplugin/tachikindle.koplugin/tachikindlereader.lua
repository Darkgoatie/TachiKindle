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
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local _ = require("gettext")

local TachiKindleReader = {}

-- source: a loaded TachiKindleSource instance
-- page_urls: string array of page image URLs (from fetchPageList)
function TachiKindleReader.show(source, page_urls, chapter_title)
    if #page_urls == 0 then
        UIManager:show(InfoMessage:new{ text = _("This chapter has no pages.") })
        return
    end

    local images_list = setmetatable({}, {
        __len = function() return #page_urls end,
    })
    for i, url in ipairs(page_urls) do
        images_list[i] = function()
            local body, err = source:fetch(url)
            if not body then
                UIManager:show(InfoMessage:new{
                    text = _("Failed to load page ") .. i .. ": " .. tostring(err),
                })
                return nil
            end
            local bb = RenderImage:renderImageData(body, #body)
            if not bb then
                UIManager:show(InfoMessage:new{
                    text = _("Could not decode page ") .. i,
                })
                return nil
            end
            return bb
        end
    end
    -- images_list_nb can't rely on plain #images_list since it holds
    -- functions, not the final decoded images -- give it explicitly.
    images_list.image_disposable = true

    UIManager:show(ImageViewer:new{
        image = images_list,
        images_list_nb = #page_urls,
        fullscreen = true,
        with_title_bar = true,
        title_text = chapter_title or "",
    })
end

return TachiKindleReader
