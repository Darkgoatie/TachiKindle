-- SPDX-License-Identifier: Apache-2.0
-- Ported for TachiKindle from keiyoushi/extensions-source:
-- src/en/mangakatana/src/eu/kanade/tachiyomi/extension/en/mangakatana/MangaKatana.kt
-- Upstream contributors; https://github.com/keiyoushi/extensions-source
-- License: https://www.apache.org/licenses/LICENSE-2.0
--
-- Listing/details/chapters are plain HTML and are handled by the
-- runtime's generic selector engine (see mangakatana.tkext.json).
-- Page images are NOT: MangaKatana's reader HTML only ever contains
-- dead <img data-src="#"> placeholders; real per-page image URLs live
-- inside an inline <script> as a JS array literal, e.g.:
--   var thzq=['https://i1.mangakatana.com/token/.../0.jpg', ...];
-- confirmed live 2026-09-22 against a real chapter page (51/51 image
-- URLs recovered). This mirrors upstream's own two-regex approach
-- (imageArrayNameRegex finds the array's variable name via the
-- 'data-src' string literal that names it; imageUrlRegex then pulls
-- every quoted URL out of that array).
local Source = {}

function Source.fetch_manga_list(source, endpoint_name, page, query)
    return source:fetchMangaListWithSelectors(endpoint_name, page, query)
end

function Source.fetch_manga_details(source, manga_url)
    return source:fetchMangaDetailsWithSelectors(manga_url)
end

function Source.fetch_chapter_list(source, manga_url)
    return source:fetchChapterListWithSelectors(manga_url)
end

-- Extract the reader's image-array variable name from a <script> body
-- containing something like: images('data-src', thzq); ... var thzq=[...]
local function findArrayName(script_body)
    return script_body:match("data%-src['\"],%s*(%w+)")
end

-- Given the array name, pull the bracketed literal `var <name>=[...]`
-- (non-greedy up to the first `]`) and extract every single-quoted URL
-- inside it, in order.
local function findImageUrls(script_body, array_name)
    local pattern = "var%s+" .. array_name .. "%s*=%s*%[([^%[]-)%]"
    local array_body = script_body:match(pattern)
    if not array_body then return nil end
    local urls = {}
    for url in array_body:gmatch("'([^']*)'") do
        table.insert(urls, url)
    end
    return urls
end

function Source.fetch_page_list(source, chapter_url)
    local url, err = source:resolveUrl("page_list", { chapter_url = chapter_url })
    if not url then return nil, err end
    local body, ferr = source:fetch(url)
    if not body then return nil, ferr end

    -- Find whichever inline <script> contains the 'data-src' marker
    -- string (there may be several unrelated <script> tags on the page).
    for script_body in body:gmatch("<script[^>]*>(.-)</script>") do
        local array_name = findArrayName(script_body)
        if array_name then
            local urls = findImageUrls(script_body, array_name)
            if urls and #urls > 0 then
                return urls
            end
        end
    end
    return nil, "MangaKatana: no reader image script found; site layout may have changed"
end

return Source
