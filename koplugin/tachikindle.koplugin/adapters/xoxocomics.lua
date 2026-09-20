-- SPDX-License-Identifier: Apache-2.0
-- Adapted and modified for TachiKindle from keiyoushi/extensions-source:
-- src/en/xoxocomics/src/eu/kanade/tachiyomi/extension/en/xoxocomics/XoxoComics.kt
-- lib-multisrc/wpcomics/src/eu/kanade/tachiyomi/multisrc/wpcomics/WPComics.kt
-- Upstream contributors; https://github.com/keiyoushi/extensions-source
-- License: https://www.apache.org/licenses/LICENSE-2.0
local htmlparser = require('htmlparser')
local URL = require('socket.url')
local M = {}
local function decode(s)
    local entities = {amp = '&', lt = '<', gt = '>', quot = '"', apos = "'", nbsp = ' '}
    return (s:gsub('&(#?[%w]+);', function(entity)
        if entities[entity] then return entities[entity] end
        local n = entity:match('^#(%d+)$')
        n = n and tonumber(n) or tonumber(entity:match('^#[xX](%x+)$') or '', 16)
        if not n or n == 0 or n > 1114111 or (n >= 55296 and n <= 57343) then
            return '&' .. entity .. ';'
        end
        if n < 128 then return string.char(n) end
        if n < 2048 then return string.char(192 + math.floor(n / 64), 128 + n % 64) end
        if n < 65536 then
            return string.char(224 + math.floor(n / 4096), 128 + math.floor(n / 64) % 64, 128 + n % 64)
        end
        return string.char(240 + math.floor(n / 262144), 128 + math.floor(n / 4096) % 64,
            128 + math.floor(n / 64) % 64, 128 + n % 64)
    end))
end
local function text(node)
    return node and decode(node:textonly()):gsub('%s+', ' '):match('^%s*(.-)%s*$') or nil
end
local function absolute(base, value)
    if not value then return nil end
    value = decode(value):match('^%s*(.-)%s*$')
    if value == '' then return nil end
    local result = URL.absolute(base, value)
    if result and result:match('^https?://') then return result end
end
local function image(base, node)
    if not node then return nil end
    for _, key in ipairs({'data-original', 'data-src', 'src'}) do
        local value = absolute(base, node.attributes[key])
        if value then return value end
    end
end
local function parse(body)
    if type(body) ~= 'string' or body == '' then return nil, 'empty HTML response' end
    if body:find('/cdn-cgi/challenge-platform/', 1, true) or body:find('<title>Just a moment', 1, true) then
        return nil, 'Cloudflare challenge; interactive browser verification is not supported'
    end
    return htmlparser.parse(body, 5000)
end
local function get(source, url)
    local body, err = source:fetch(url)
    if not body then return nil, err end
    return parse(body)
end
function M.fetchMangaList(source, endpoint_name, page, query)
    page = page or 1
    local base = source.def.base_url
    local url, selector = nil, 'div.items div.item'
    if endpoint_name == 'popular' then
        url = base .. '/hot-comic' .. (page > 1 and '?page=' .. page or '')
    elseif endpoint_name == 'search' then
        url = base .. '/search-comic?keyword=' .. URL.escape(query or '') .. '&page=' .. page
    elseif endpoint_name == 'latest' then
        url, selector = base .. '/comic-update?page=' .. page, 'li.row'
    else
        return nil, 'unsupported endpoint: ' .. tostring(endpoint_name)
    end
    local root, err = get(source, url)
    if not root then return nil, err end
    local rows = {}
    for _, item in ipairs(root:select(selector)) do
        local a = item:select('h3 a')[1]
        local href = a and absolute(url, a.attributes.href)
        if href then
            local cover
            if endpoint_name == 'latest' then
                local img = item:select('img')[1]
                cover = img and absolute(url, img.attributes['data-original'])
            else
                cover = image(url, item:select('div.image img')[1])
            end
            rows[#rows + 1] = {title = text(a), url = href, cover = cover}
        end
    end
    return rows, nil, #root:select('a.next-page') > 0 or #root:select('a[rel="next"]') > 0
end
function M.fetchMangaDetails(source, manga_url)
    local url = absolute(source.def.base_url, manga_url)
    if not url then return nil, 'invalid manga URL' end
    local root, err = get(source, url)
    if not root then return nil, err end
    local info = root:select('article#item-detail')[1]
    if not info then return nil, 'missing XOXO Comics detail container' end
    local paragraphs, genres = {}, {}
    for _, p in ipairs(info:select('div.detail-content p')) do
        paragraphs[#paragraphs + 1] = decode(p:textonly()):match('^%s*(.-)%s*$')
    end
    for _, a in ipairs(info:select('li.kind p.col-xs-8 a')) do genres[#genres + 1] = text(a) end
    local description = table.concat(paragraphs, '\n')
    local other = text(info:select('h2.other-name')[1])
    if other and other ~= '' then description = description .. '\n\nOther name: ' .. other end
    return {
        title = text(info:select('h1')[1]), author = text(info:select('li.author p.col-xs-8')[1]),
        status = text(info:select('li.status p.col-xs-8')[1]), genres = genres,
        cover = image(url, info:select('div.col-image img')[1]), description = description,
    }
end
function M.fetchChapterList(source, manga_url)
    local url = absolute(source.def.base_url, manga_url)
    if not url then return nil, 'invalid manga URL' end
    local rows, visited, seen = {}, {}, {}
    -- Bounded pagination: never silently return a truncated chapter list.
    for _ = 1, 100 do
        if visited[url] then return nil, 'chapter pagination cycle' end
        visited[url] = true
        local root, err = get(source, url)
        if not root then return nil, err end
        for _, item in ipairs(root:select('div.list-chapter li.row')) do
            local heading = false
            for token in (item.attributes.class or ''):gmatch('%S+') do
                if token == 'heading' then heading = true end
            end
            if not heading then
                local a = item:select('a')[1]
                local href = a and absolute(url, a.attributes.href)
                if href and not seen[href] then
                    seen[href] = true
                    rows[#rows + 1] = {title = text(a), url = href, date = text(item:select('div.col-xs-3')[1])}
                end
            end
        end
        local nextNode = root:select('ul.pagination a[rel="next"]')[1]
        if not nextNode then return rows end
        local nextUrl = absolute(url, nextNode.attributes.href)
        if not nextUrl then return nil, 'invalid chapter pagination URL' end
        if URL.parse(nextUrl).host ~= URL.parse(source.def.base_url).host then
            return nil, 'cross-host chapter pagination URL'
        end
        url = nextUrl
    end
    return nil, 'chapter pagination exceeded 100 pages'
end
function M.parsePages(source, body, chapter_url)
    local root, err = parse(body)
    if not root then return nil, err end
    local nodes, pages, seen = {}, {}, {}
    -- htmlparser has no comma-selector union; merge by DOM index explicitly.
    for _, selector in ipairs({'div.page-chapter > img', 'li.blocks-gallery-item img'}) do
        for _, node in ipairs(root:select(selector)) do nodes[#nodes + 1] = node end
    end
    table.sort(nodes, function(a, b) return a.index < b.index end)
    for _, node in ipairs(nodes) do
        -- Contract supplies the original chapter URL; HTML came from /all.
        local href = image(absolute(source.def.base_url, chapter_url .. '/all'), node)
        if href and not seen[href] then
            seen[href] = true
            pages[#pages + 1] = href
        end
    end
    if #pages == 0 then return nil, 'no XOXO Comics page images found' end
    return pages
end
return M
