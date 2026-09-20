-- SPDX-License-Identifier: Apache-2.0
-- Adapted and modified for TachiKindle from keiyoushi/extensions-source:
-- src/en/readallcomicscom/src/eu/kanade/tachiyomi/extension/en/readallcomicscom/ReadAllComics.kt
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
local function hasClass(node, name)
    for token in (node.attributes.class or ''):gmatch('%S+') do
        if token == name then return true end
    end
    return false
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
    local url
    if endpoint_name == 'popular' then
        url = page == 1 and base or base .. '/?paged=' .. page
    elseif endpoint_name == 'search' then
        url = base .. '/?story=' .. URL.escape(query or '') .. '&s=&type=comic'
        if page > 1 then url = url .. '&paged=' .. page end
    else
        return nil, 'unsupported endpoint: ' .. tostring(endpoint_name)
    end
    local root, err = get(source, url)
    if not root then return nil, err end
    local rows = {}
    for _, item in ipairs(root:select('ul.list-story.categories li')) do
        local a = item:select('a.cat-title')[1]
        local href = a and absolute(url, a.attributes.href)
        if href then
            local img = item:select('img.book-cover')[1]
            rows[#rows + 1] = {title = text(a), url = href, cover = img and absolute(url, img.attributes.src)}
        end
    end
    local more = false
    if endpoint_name == 'search' then
        more = #root:select('a.next') > 0
    else
        -- htmlparser cannot implement Jsoup's adjacent-sibling combinator.
        for _, current in ipairs(root:select('.pagination .page-numbers.current')) do
            for i, sibling in ipairs(current.parent.nodes) do
                if sibling == current then
                    local nextNode = current.parent.nodes[i + 1]
                    more = nextNode ~= nil and hasClass(nextNode, 'page-numbers')
                    break
                end
            end
            if more then break end
        end
    end
    return rows, nil, more
end
function M.fetchMangaDetails(source, manga_url)
    local url = absolute(source.def.base_url, manga_url)
    if not url then return nil, 'invalid manga URL' end
    local root, err = get(source, url)
    if not root then return nil, err end
    local archive = root:select('.description-archive')[1]
    if not archive then return nil, 'missing ReadAllComics detail container' end
    local title = text(archive:select('h1')[1])
    if not title or title == '' then return nil, 'missing manga title' end
    local info = archive:select('.b > p strong')
    local img = archive:select('p img')[1]
    local description = archive:select('#hidden-description')[1]
    return {
        title = title, author = text(info[#info]),
        genres = info[1] and {text(info[1])} or {},
        cover = img and absolute(url, img.attributes.src),
        description = description and decode(description:textonly()):match('^%s*(.-)%s*$'),
    }
end
function M.fetchChapterList(source, manga_url)
    local url = absolute(source.def.base_url, manga_url)
    if not url then return nil, 'invalid manga URL' end
    local root, err = get(source, url)
    if not root then return nil, err end
    local rows = {}
    for _, a in ipairs(root:select('.list-story a')) do
        local href = absolute(url, a.attributes.href)
        if href then
            local title = text(a)
            local suffix = title:match('.*%((.*)$')
            local year = suffix and suffix:match('^(%d%d%d%d)%)')
            rows[#rows + 1] = {title = title, url = href, date = year and year .. '-01-01'}
        end
    end
    return rows
end
function M.parsePages(source, body, chapter_url)
    local root, err = parse(body)
    if not root then return nil, err end
    local pages = {}
    for _, img in ipairs(root:select('body img')) do
        local parent, logo = img.parent, false
        while parent do
            if parent.name == 'div' and parent.attributes.id == 'logo' then logo = true; break end
            parent = parent.parent
        end
        if not logo then
            local href = absolute(chapter_url, img.attributes.src)
            if href then pages[#pages + 1] = href end
        end
    end
    if #pages == 0 then return nil, 'no ReadAllComics page images found' end
    return pages
end
return M
