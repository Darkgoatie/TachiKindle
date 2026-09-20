-- SPDX-License-Identifier: Apache-2.0
-- Adapted from keiyoushi/extensions-source BatCave.kt and Dto.kt.
-- Modified for KOReader; no Android WebView or DLE Guard solver is provided.
local htmlparser = require('htmlparser')
local url = require('socket.url')
local JSON = require('json')
local M = {}
local function trim(s) return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')) end
local function absolute(source, value)
    if type(value) ~= 'string' or trim(value) == '' then return nil end
    local result = url.absolute(source.def.base_url .. '/', trim(value))
    if result and result:match('^https?://') then return result end
end
function M.parsePages(source, body)
    local ok, data = pcall(JSON.decode, body)
    if not ok or type(data) ~= 'table' or type(data.data) ~= 'table' or type(data.data.images) ~= 'table' then
        return nil, 'BatCave: invalid reader API response (possibly DLE Guard)'
    end
    local pages = {}
    for _, value in ipairs(data.data.images) do
        local image = absolute(source, value)
        if not image then return nil, 'BatCave: invalid image URL in reader API' end
        pages[#pages + 1] = image
    end
    if #pages == 0 then return nil, 'BatCave: reader API returned no images' end
    return pages
end
function M.fetchPages(source, chapter_url)
    local news, raw = chapter_url:match('/reader/(%d+)/([^/?#]+)')
    local chapter = raw and raw:match('^(%d+)')
    if not news or not chapter then return nil, 'BatCave: invalid chapter URL' end
    local body, err = source:fetch(source.def.base_url .. '/engine/ajax/controller.php?mod=api&action=reader/getChapterData', {
        method = 'POST', headers = {['Content-Type'] = 'application/json'},
        body = JSON.encode({news_id = news, chapter_id = chapter}),
    })
    if not body then return nil, err end
    return M.parsePages(source, body)
end
local function unicode(n)
    if not n or n < 0 or n > 1114111 or (n >= 55296 and n <= 57343) then return '�' end
    if n < 128 then return string.char(n) end
    if n < 2048 then return string.char(192 + math.floor(n/64), 128+n%64) end
    if n < 65536 then return string.char(224+math.floor(n/4096), 128+math.floor(n/64)%64, 128+n%64) end
    return string.char(240+math.floor(n/262144), 128+math.floor(n/4096)%64, 128+math.floor(n/64)%64, 128+n%64)
end
local function text(node)
    if not node then return '' end
    local raw = node:textonly():gsub('&#[xX]([%da-fA-F]+);', function(n) return unicode(tonumber(n,16)) end)
        :gsub('&#(%d+);', function(n) return unicode(tonumber(n)) end)
    return trim(raw:gsub('&nbsp;', ' '):gsub('&lt;', '<'):gsub('&gt;', '>'):gsub('&quot;', '"'):gsub('&apos;', "'"):gsub('&amp;', '&'))
end
local function getDocument(source, location, request)
    local body, err = source:fetch(location, request)
    if not body then return nil, err end
    if body:find('__guard_trust', 1, true) or body:find('DLE Guard', 1, true) or body:find('cf-chl-', 1, true) then
        return nil, 'BatCave: DLE Guard/site protection requires a browser; not solved by this adapter'
    end
    return htmlparser.parse(body, 5000)
end
function M.fetchMangaList(source, endpoint, page, query)
    page, query = page or 1, trim(query)
    local suffix = page > 1 and ('page/' .. page .. '/') or ''
    local path, request
    if endpoint == 'popular' or (endpoint == 'search' and query == '') then
        path = '/comix/' .. suffix
        request = {method = 'POST', headers = {['Content-Type'] = 'application/x-www-form-urlencoded'},
            body = 'dlenewssortby=rating&dledirection=desc&set_new_sort=dle_sort_cat_1&set_direction_sort=dle_direction_cat_1'}
    elseif endpoint == 'latest' then path = '/' .. suffix
    elseif endpoint == 'search' then path = '/search/' .. url.escape(query) .. '/' .. suffix
    else return nil, 'BatCave: unsupported listing endpoint' end
    local root, err = getDocument(source, source.def.base_url .. path, request)
    if not root then return nil, err end
    local latest = endpoint == 'latest'
    local container = latest and '#content-load' or '#dle-content'
    local kind = latest and 'latest' or 'readed'
    if not root:select(container)[1] then return nil, 'BatCave: listing not found; site layout/protection changed' end
    local list = {}
    for _, item in ipairs(root:select(container .. ' > .' .. kind)) do
        local a = item:select('.' .. kind .. '__title > a')[1]
        local image = item:select('.' .. kind .. '__img img')[1]
        local link = a and absolute(source, a.attributes.href)
        if link and text(a) ~= '' then
            list[#list + 1] = {title = text(a), url = link, cover = image and absolute(source, image.attributes[latest and 'src' or 'data-src'])}
        end
    end
    local pager = root:select('div.pagination__pages')[1]
    local has_next = latest and #root:select('li.pagination a[href]') > 0
        or (not latest and pager and pager.nodes[#pager.nodes] and pager.nodes[#pager.nodes].name == 'a') or false
    return list, nil, has_next
end
function M.fetchMangaDetails(source, manga_url)
    local root, err = getDocument(source, absolute(source, manga_url))
    if not root then return nil, err end
    local title = text(root:select('header.page__header h1')[1])
    if title == '' then return nil, 'BatCave: manga details not found' end
    local fields = {}
    for _, li in ipairs(root:select('.page__list > li')) do
        local label = text(li:select('div')[1])
        local anchor = li:select('a')[1]
        fields[label] = anchor and text(anchor) or trim(text(li):sub(#label + 1))
    end
    local genres = {}
    for _, a in ipairs(root:select('div.page__tags a')) do genres[#genres + 1] = text(a) end
    genres[#genres + 1] = 'Comic'
    local image = root:select('div.page__poster img')[1]
    return {title = title, author = fields.Writer, artist = fields.Artist, genres = genres,
        cover = image and absolute(source, image.attributes.src),
        status = (fields['Release type'] == 'Completed' or fields['Release type'] == 'Ongoing') and fields['Release type'] or 'Unknown',
        description = (fields.Publisher or '') .. (fields.Year and ' — ' .. fields.Year or '') .. '\n\n' .. text(root:select('div.page__text')[1])}
end
-- Read just the balanced JSON object, not JavaScript after the assignment.
local function chapterData(root)
    for _, script in ipairs(root:select('script')) do
        local raw = script:getcontent()
        local _, start = raw:find('window%.__DATA__%s*=%s*')
        if start then
            local quoted, escaped, depth, first = false, false, 0, nil
            for i = start + 1, #raw do
                local ch = raw:sub(i,i)
                if quoted then
                    if escaped then escaped = false elseif ch == '\\' then escaped = true elseif ch == '"' then quoted = false end
                elseif ch == '"' then quoted = true
                elseif ch == '{' then depth = depth + 1; first = first or i
                elseif ch == '}' then
                    depth = depth - 1
                    if depth == 0 and first then
                        local ok, data = pcall(JSON.decode, raw:sub(first,i))
                        if ok then return data end
                        return nil
                    end
                elseif not first and not ch:match('%s') then return nil end
            end
        end
    end
end
function M.fetchChapterList(source, manga_url)
    local root, err = getDocument(source, absolute(source, manga_url))
    if not root then return nil, err end
    local data = chapterData(root)
    if type(data) ~= 'table' or not tonumber(data.news_id) or type(data.chapters) ~= 'table'
        or (data.xhash ~= nil and type(data.xhash) ~= 'string') then
        return nil, 'BatCave: chapter JSON not found or invalid'
    end
    local chapters = {}
    for _, chapter in ipairs(data.chapters) do
        if type(chapter) ~= 'table' or not tonumber(chapter.id) or type(chapter.title) ~= 'string' then return nil, 'BatCave: malformed chapter data' end
        chapters[#chapters + 1] = {title = chapter.title, date = chapter.date, chapter_number = tonumber(chapter.posi),
            url = source.def.base_url .. '/reader/' .. data.news_id .. '/' .. chapter.id .. (data.xhash or '')}
    end
    return chapters
end
return M
