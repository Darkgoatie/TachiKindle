-- SPDX-License-Identifier: Apache-2.0
-- Lua adaptation of keiyoushi/extensions-source Readcomiconline.kt and
-- keiyoushi/rco-script decrypt.json. Modified for KOReader: static data parsing,
-- never evaluate JavaScript or download executable decoder configuration.
-- Inspected decoder SHA-256: c0fc73f27c745baa46a7bee0776e034fd1f0f3531b4ec14ec92822beb223cbaf
-- Upstream license text is in readcomiconline.LICENSE beside this module.
local htmlparser = require('htmlparser')
local url = require('socket.url')
local BLOCKLIST = {
    ["https://2.bp.blogspot.com/pw/AP1GczP6zCVVfdmN6OoVnm7CLvEfmHMUawyEwJWouX9C6SHwsiuYfLkUr9FsM6Zo34qNzPKeQeahBx9ckBZJQckiJmX1UwKD7uh900yz5rKyG4zT2rfIrqFviEJIev1Pg_pGRuSG57rIH6BDwGCTmiE4MjA"] = true,
    ["https://2.bp.blogspot.com/pw/AP1GczP48thKMga7cud0tjtHtYqsvZzhYY0HyAxVzM3O1D6tkLbi0fT9NDZFFFH69hNnoGsnqJSEIh4mmpEoU1BJSfNXIz1f5aLXl41RM9os7ePn7ipbrYbIuqiQxAV0hhJZrNLl7FmauwLQ01paCrP6KAE"] = true,
    ["https://2.bp.blogspot.com/pw/AP1GczNXprTMfAP2AHFFWvCbKq6qReXrqSohz87KeBjV0nh6XoLsE1NpzL7Rp9llxoY208IPARiIDON_TO6dZB0ZMNeB8J7xzUzbS9h6To7aGpOZshFofw-wFQ0KJ3y3wolSwzLrduZZ_0w8_6gGuTEB-98"] = true,
    ["https://2.bp.blogspot.com/pw/AP1GczMVY_zWeag2n981CRX7jaZ73Sr0NtidtJhnvJ3-Rmh2fIo-PoQRI0ZksQEbpTjDHgBeNYbQ2hQodsY-Dv0FXUhiU_mus5z5L5lMVAH82kXYqOd2IEw"] = true,
    ["https://2.bp.blogspot.com/pw/AP1GczOKY-6EDGVvlQGB2wj0xxB5JgcyiujFJC3CHgwqBOLIidwmoP6DLiMpX__Fw6MMPvLezN6soeV0A8pKSHUrC4rxZyO5vov40g1g4ipZdkFlzUouAFA"] = true,
    ["https://2.bp.blogspot.com/pw/AP1GczO8AETT3k19nhJwxHm0sHCSy0tXyhSOYxnq3EUrmlvgY5yPqDaxcd1XZ7reQKH-lKgpGK4o3sW_9Yu6feqii79riXN3Ghi8Xs1S5Z4wi-aeHrq5PzOX"] = true,
}
local M = {}
local function trim(s) return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')) end
local function scripts(body)
    local out = {}
    for _, node in ipairs(htmlparser.parse(body, 5000):select('script')) do
        out[#out + 1] = node:getcontent()
    end
    return table.concat(out, '\n')
end
local function unbase64(s)
    local alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    if #s:gsub('=+$', '') % 4 == 1 or s:find('[^%w+/=]') then return nil end
    local out, value, bits = {}, 0, 0
    for ch in s:gmatch('[^=]') do
        local at = alphabet:find(ch, 1, true)
        if not at then return nil end
        value, bits = value * 64 + at - 1, bits + 6
        if bits >= 8 then
            bits = bits - 8
            out[#out + 1] = string.char(math.floor(value / 2 ^ bits))
            value = value % 2 ^ bits
        end
    end
    return table.concat(out)
end
local function prefixOffset(values)
    local first, count = values[1] or '', 0
    for i = 1, #first do
        for j = 2, #values do if values[j]:sub(i,i) ~= first:sub(i,i) then return count end end
        count = i
        if i >= 5 and first:sub(i-4,i) == 'https' then return i - 5 end
    end
    return count
end
local function decrypt(value, offset, image_base, server2)
    value = value:gsub('pw_.g28x', 'b'):gsub('d2pr.x_27', 'h'):sub(offset + 1)
    if value:match('=s0$') or value:match('=s1600$') then
        value = value:gsub('^https://2%.bp%.blogspot%.com/', '') .. '?'
    end
    if value:match('^https?://') then return value end
    local at, _, quality = value:find('(=s%d+)%?')
    if not at or (quality ~= '=s0' and quality ~= '=s1600') then return nil end
    local encoded = value:sub(1, at - 1)
    encoded = encoded:sub(16,33) .. encoded:sub(51)
    if #encoded < 11 then return nil end
    encoded = encoded:sub(1, #encoded-11) .. encoded:sub(-2)
    local decoded = unbase64(encoded)
    if not decoded then return nil end
    decoded = url.unescape(decoded)
    if #decoded < 19 then return nil end
    decoded = decoded:sub(1,13) .. decoded:sub(18)
    decoded = decoded:sub(1,-3) .. quality
    return image_base .. '/' .. decoded .. value:sub(at + #quality) .. (server2 and '&t=10' or '')
end
function M.parsePages(source, body, chapter_url)
    local script = scripts(body)
    local array
    for line in (script .. '\n'):gmatch('(.-)\n') do
        -- Match upstream: ignore loader candidates after a line-comment marker.
        local start, _, candidate = line:find('[%w_]+%s*%(%s*%d+%s*,%s*([%w_]+)%s*%[%s*currImage%s*%]')
        if start and not line:sub(1,start-1):find('//',1,true) then array = candidate; break end
    end
    local marker, replacement = script:match('%.replace%s*%(%s*/([%w_]+__[%w_]+_)/g%s*,%s*["\']([%w_])["\']%s*%)')
    if not marker then
        local variable
        marker, variable = script:match('%.replace%s*%(%s*/([%w_]+__[%w_]+_)/g%s*,%s*([%w_]+)%s*%)')
        if variable then
            local last
            for expr in script:gmatch('%f[%w_]' .. variable .. '%s*=%s*([^;]+);') do last = expr end
            if last then
                local literals = {}
                for quote, value in last:gmatch('(["\'])(.-)%1') do literals[#literals + 1] = value end
                if #literals > 0 then replacement = table.concat(literals) end
            end
        end
    end
    local obfuscation = marker or '[%w_][%w_]__[%w_][%w_][%w_][%w_][%w_][%w_]_'
    replacement = replacement or 'e'
    local arrays = {}
    if array then arrays[1] = array else
        for name in script:gmatch('var%s+([%w_]+)%s*=%s*new%s+Array%s*%(%s*%)') do arrays[#arrays + 1] = name end
    end
    local server2 = (source.def.reader or {}).server == 's2'
    local image_base = script:match('baeu%s*%([%w_]+%s*,%s*["\'](https?://[^"\']+)["\']')
        or (server2 and 'https://ano1.rconet.biz/pic' or 'https://2.bp.blogspot.com')
    local pages, seen = {}, {}
    for _, name in ipairs(arrays) do
        local values = {}
        for quote, value in script:gmatch(name .. '%.push%s*%(%s*(["\'])(.-)%1') do values[#values + 1] = value end
        if #values == 0 then
            for call in script:gmatch('[%w_]+%s*%([^%)]*%)') do
                if call:find('%f[%w_]' .. name .. '%f[^%w_]') then
                    local longest
                    for quote, value in call:gmatch('(["\'])(.-)%1') do
                        if #value >= 20 and (not longest or #value > #longest) then longest = value end
                    end
                    if longest then values[#values + 1] = longest end
                end
            end
        end
        local offset = prefixOffset(values)
        for _, value in ipairs(values) do
            value = decrypt(value:gsub(obfuscation, function() return replacement end), offset, image_base, server2)
            if not value then return nil, 'ReadComicOnline: unsupported encrypted page data; decoder may have changed' end
            local key = value:match('^[^?=]+')
            if value:match('^https?://[^/%s]+/') and not seen[key] and not BLOCKLIST[key] then
                pages[#pages + 1] = value
                seen[key] = true
            end
        end
    end
    if #pages == 0 then return nil, 'ReadComicOnline: no supported reader array found (site protection or decoder changed)' end
    return pages
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
local function absolute(source, value)
    if not value or trim(value) == '' then return nil end
    local result = url.absolute(source.def.base_url .. '/', value:gsub('&amp;', '&'))
    if result and result:match('^https?://') then return result end
end
local function getDocument(source, location, request)
    local body, err = source:fetch(location, request)
    if not body then return nil, err end
    if body:find('AreYouHuman', 1, true) or body:find('cf-chl-', 1, true) then
        return nil, 'ReadComicOnline: CAPTCHA/site protection requires an external browser; not solved by this adapter'
    end
    return htmlparser.parse(body, 5000)
end
function M.fetchMangaList(source, endpoint, page, query)
    page, query = page or 1, trim(query)
    local path
    if endpoint == 'popular' then path = '/ComicList/MostPopular?page=' .. page
    elseif endpoint == 'latest' then path = '/ComicList/LatestUpdate?page=' .. page
    elseif endpoint == 'search' then
        path = query == '' and '/ComicList?page=' .. page
            or '/AdvanceSearch?comicName=' .. url.escape(query) .. '&page=' .. page .. '&status=&ig=&eg='
    else return nil, 'ReadComicOnline: unsupported listing endpoint' end
    local root, err = getDocument(source, source.def.base_url .. path)
    if not root then return nil, err end
    if not root:select('.list-comic')[1] then return nil, 'ReadComicOnline: listing not found; site layout/protection changed' end
    local list = {}
    for _, item in ipairs(root:select('.list-comic > .item')) do
        local anchor = item:select('a')[1]
        local image = anchor and anchor:select('img')[1]
        local link = anchor and absolute(source, anchor.attributes.href)
        if link and text(anchor) ~= '' then
            list[#list + 1] = {title = text(anchor), url = link, cover = image and absolute(source, image.attributes.src)}
        end
    end
    local has_next = false
    for _, a in ipairs(root:select('ul.pager a')) do if text(a):find('Next', 1, true) then has_next = true end end
    return list, nil, has_next
end
function M.fetchMangaDetails(source, manga_url)
    local root, err = getDocument(source, absolute(source, manga_url))
    if not root then return nil, err end
    local info = root:select('div.barContent')[1]
    local title = info and text(info:select('a.bigChar')[1]) or ''
    if title == '' then return nil, 'ReadComicOnline: manga details not found' end
    local details = {title = title, genres = {}, status = 'Unknown'}
    local summary, description, metadata = false, {}, {}
    for _, p in ipairs(info:select('p')) do
        local label = text(p:select('span')[1])
        local links = {}
        for _, a in ipairs(p:select('a')) do links[#links + 1] = text(a) end
        if label:find('Writer:',1,true) then details.author = #links > 2 and links[1] .. ' & others' or table.concat(links, ', ')
        elseif label:find('Artist:',1,true) then details.artist = #links > 2 and links[1] .. ' & others' or table.concat(links, ', ')
        elseif label:find('Genres:',1,true) then details.genres = links
        elseif label:find('Status:',1,true) then
            details.status = text(p):find('Completed',1,true) and 'Completed' or text(p):find('Ongoing',1,true) and 'Ongoing' or 'Unknown'
        elseif label:find('Summary:',1,true) then summary = true
        elseif label:find('Publisher:',1,true) or label:find('Publication date:',1,true) or label:find('Views:',1,true) then metadata[#metadata + 1] = text(p)
        elseif summary then
            local fragment = htmlparser.parse(p:getcontent():gsub('<[bB][rR]%s*/?>', '\n'), 5000)
            description[#description + 1] = text(fragment)
        end
    end
    details.description = table.concat(description, '\n\n') .. (#metadata > 0 and '\n' .. table.concat(metadata, '\n') or '')
    local image = root:select('.rightBox img')[1]
    details.cover = image and absolute(source, image.attributes.src)
    return details
end
function M.fetchChapterList(source, manga_url)
    local root, err = getDocument(source, absolute(source, manga_url))
    if not root then return nil, err end
    if not root:select('table.listing')[1] then return nil, 'ReadComicOnline: chapter table not found' end
    local chapters = {}
    for i, row in ipairs(root:select('table.listing tr')) do
        if i > 2 then
            local a = row:select('a')[1]
            local link = a and absolute(source, a.attributes.href)
            if link then chapters[#chapters + 1] = {title = text(a), url = link, date = text(row:select('td')[2])} end
        end
    end
    return chapters
end
return M
