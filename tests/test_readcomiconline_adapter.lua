-- Synthetic fixtures only. No network or comic images are fetched.
-- Run from repo root with KOReader-compatible htmlparser/json/socket.url on LUA_PATH.
package.path = './koplugin/tachikindle.koplugin/?.lua;' .. package.path
local ok, adapter = pcall(require, 'adapters/readcomiconline')
assert(ok, 'ReadComicOnline adapter is implemented: ' .. tostring(adapter))
local source = { def = { base_url = 'https://readcomiconline.li' } }
local pages, err = adapter.parsePages(source, [[<script>
var decoy = new Array(); decoy.push('https://ads.example.invalid/advert.jpg');
var pages = new Array();
pages.push('https://images.example.invalid/synthetic-page-1.jpg');
pages.push('https://images.example.invalid/synthetic-page-2.jpg');
pages.push('https://images.example.invalid/synthetic-page-1.jpg?duplicate=1');
load(0, pages[currImage]);
</script>]], '/Comic/Synthetic?id=1')
assert(pages, err)
assert(#pages == 2 and pages[1] == 'https://images.example.invalid/synthetic-page-1.jpg')
assert(pages[2] == 'https://images.example.invalid/synthetic-page-2.jpg')
-- Construct labelled synthetic encrypted data by inverting upstream's string edits.
local b64 = require('mime').b64
local function encrypt(path)
    local payload = path:sub(1, 13) .. 'JUNK' .. path:sub(14) .. 'XX'
    local encoded = b64(payload)
    encoded = encoded:sub(1, -3) .. '123456789' .. encoded:sub(-2)
    return path:sub(1, 1) .. string.rep('A', 14) .. encoded:sub(1, 18) .. string.rep('B', 17) .. encoded:sub(19) .. '=s1600?token=synthetic'
end
local encrypted = '<script>var pages = new Array(); pages.push("' .. encrypt('syntheticpath/page-1') .. '"); pages.push("' .. encrypt('differentpath/page-2') .. '"); load(0,pages[currImage]); baeu(pages,"https://cdn.example.invalid/pic");</script>'
pages, err = adapter.parsePages(source, encrypted, '/Comic/Synthetic?id=1')
assert(pages, err)
assert(pages[1] == 'https://cdn.example.invalid/pic/syntheticpath/page-1=s1600?token=synthetic', pages[1])
assert(pages[2] == 'https://cdn.example.invalid/pic/differentpath/page-2=s1600?token=synthetic', pages[2])
local calls = {}
function source:fetch(request_url, request)
    calls[#calls + 1] = request_url
    return [[<div class="list-comic"><div class="item"><a href="/Comic/Synthetic"><img src="/covers/synthetic.jpg">Synthetic &amp; Test</a><a href="/not-a-comic">Ignored</a></div></div><ul class="pager"><li><a>Previous</a></li><li><a href="?page=2">Next</a></li></ul>]]
end
local list, list_err, next_page = adapter.fetchMangaList(source, 'search', 2, 'test / query')
assert(list, list_err)
assert(#list == 1 and list[1].title == 'Synthetic & Test' and next_page)
assert(list[1].url == 'https://readcomiconline.li/Comic/Synthetic')
assert(list[1].cover == 'https://readcomiconline.li/covers/synthetic.jpg')
assert(calls[1] == 'https://readcomiconline.li/AdvanceSearch?comicName=test%20%2f%20query&page=2&status=&ig=&eg=')
function source:fetch(request_url)
    assert(request_url == 'https://readcomiconline.li/Comic/Synthetic')
    return [[<div class="barContent"><a class="bigChar">Synthetic Comic</a><p><span>Writer:</span><a>A</a><a>B</a><a>C</a></p><p><span>Artist:</span><a>D</a></p><p><span>Genres:</span><a>Adventure</a></p><p><span>Status:</span>Completed</p><p><span>Summary:</span></p><p>Synthetic summary<br>Second line.</p></div><div class="rightBox"><img src="/cover.jpg"></div><table class="listing"><tr><th>Issues</th></tr><tr><td>Header</td></tr><tr><td><a href="/Comic/Synthetic/Issue-2?id=2&amp;readType=0">Issue 2</a></td><td>09/20/2026</td></tr></table>]]
end
local details, detail_err = adapter.fetchMangaDetails(source, '/Comic/Synthetic')
assert(details, detail_err)
assert(details.title == 'Synthetic Comic' and details.author == 'A & others' and details.artist == 'D')
assert(details.status == 'Completed' and details.genres[1] == 'Adventure')
assert(details.description:find('Synthetic summary\nSecond line.', 1, true))
local chapters, chapter_err = adapter.fetchChapterList(source, '/Comic/Synthetic')
assert(chapters, chapter_err)
assert(#chapters == 1 and chapters[1].title == 'Issue 2' and chapters[1].date == '09/20/2026')
assert(chapters[1].url == 'https://readcomiconline.li/Comic/Synthetic/Issue-2?id=2&readType=0')
local obfuscated = [[<script>var pages = new Array();
// load(0, decoy[currImage]);
pages.push('PREhttps://imagZZ__marker_s.example.invalid/synthetic-1.jpg');
pages.push('PREhttps://imagZZ__marker_s.example.invalid/synthetic-2.jpg');
load(0, pages[currImage]);
value.replace(/ZZ__marker_/g, 'e');
</script>]]
pages, err = adapter.parsePages(source, obfuscated, '/Comic/Synthetic?id=1')
assert(pages, err)
assert(pages[1] == 'https://images.example.invalid/synthetic-1.jpg')
assert(pages[2] == 'https://images.example.invalid/synthetic-2.jpg')
local via_function = [[<script>var pages = new Array();
store(pages, 'https://images.example.invalid/synthetic-3.jpg');
load(0,pages[currImage]);</script>]]
pages, err = adapter.parsePages(source, via_function, '/Comic/Synthetic?id=1')
assert(pages, err)
assert(#pages == 1 and pages[1] == 'https://images.example.invalid/synthetic-3.jpg')
local missing, missing_err = adapter.parsePages(source, '<html>Unrecognized reader</html>', '/Comic/Synthetic')
assert(not missing and missing_err)
local variable_marker = obfuscated:gsub('ZZ__marker_', 'long__replacement_marker_'):gsub("'e'", 'replacement'):gsub('</script>', "replacement=''; replacement='e';</script>")
pages, err = adapter.parsePages(source, variable_marker, '/Comic/Synthetic?id=1')
assert(pages, err)
assert(pages[1] == 'https://images.example.invalid/synthetic-1.jpg', pages[1])
-- Upstream's documented non-page URL is data, never fetched by this fixture.
local blocked_url = 'https://2.bp.blogspot.com/pw/AP1GczP6zCVVfdmN6OoVnm7CLvEfmHMUawyEwJWouX9C6SHwsiuYfLkUr9FsM6Zo34qNzPKeQeahBx9ckBZJQckiJmX1UwKD7uh900yz5rKyG4zT2rfIrqFviEJIev1Pg_pGRuSG57rIH6BDwGCTmiE4MjA'
pages, err = adapter.parsePages(source, '<script>var pages = new Array(); pages.push("' .. blocked_url .. '"); pages.push("https://images.example.invalid/synthetic-valid.jpg");</script>', '/Comic/Synthetic')
assert(pages, err)
assert(#pages == 1 and pages[1] == 'https://images.example.invalid/synthetic-valid.jpg')
function source:fetch(request_url)
    assert(request_url == 'https://readcomiconline.li/ComicList/LatestUpdate?page=1')
    return '<div class="list-comic"><div class="item"><a href="/Comic/Synthetic"><img src="/cover.jpg">Synthetic &#x26; &#8217;</a></div></div>'
end
list, list_err, next_page = adapter.fetchMangaList(source, 'latest', 1)
assert(list, list_err)
assert(list[1].title == 'Synthetic & ’' and not next_page, list[1].title)
function source:fetch() return nil, 'synthetic network failure' end
list, list_err = adapter.fetchMangaList(source, 'popular', 1)
assert(not list and list_err == 'synthetic network failure')
function source:fetch() return '<title>AreYouHuman</title>' end
details, detail_err = adapter.fetchMangaDetails(source, '/Comic/Synthetic')
assert(not details and detail_err:find('CAPTCHA', 1, true))
print('ReadComicOnline synthetic adapter suite PASS')
