-- Synthetic metadata and page URLs only; no network requests.
package.path = './koplugin/tachikindle.koplugin/?.lua;' .. package.path
local ok, adapter = pcall(require, 'adapters/batcave')
assert(ok, 'BatCave adapter is implemented: ' .. tostring(adapter))
local source = {def = {base_url = 'https://batcave.biz'}}
local calls = 0
function source:fetch(url, request)
    calls = calls + 1
    assert(url == 'https://batcave.biz/engine/ajax/controller.php?mod=api&action=reader/getChapterData')
    assert(request.method == 'POST' and request.headers['Content-Type'] == 'application/json')
    local body = require('json').decode(request.body)
    assert(body.news_id == '42' and body.chapter_id == '7')
    return '{"data":{"images":[" /synthetic/1.jpg ","https://cdn.example.invalid/2.jpg"]}}'
end
local pages, err = adapter.fetchPages(source, 'https://batcave.biz/reader/42/7_xhash')
assert(pages, err)
assert(calls == 1 and #pages == 2)
assert(pages[1] == 'https://batcave.biz/synthetic/1.jpg')
assert(pages[2] == 'https://cdn.example.invalid/2.jpg')
function source:fetch(request_url, request)
    assert(request_url == 'https://batcave.biz/comix/page/2/')
    assert(request.method == 'POST' and request.body == 'dlenewssortby=rating&dledirection=desc&set_new_sort=dle_sort_cat_1&set_direction_sort=dle_direction_cat_1')
    return [[<div id="dle-content"><div class="readed"><div class="readed__title"><a href="/42-synthetic.html">Synthetic &amp; Test</a></div><div class="readed__img"><img data-src="/cover.jpg"></div></div></div><div class="pagination__pages"><span>1</span><a href="/comix/page/3/">3</a></div>]]
end
local list, list_err, next_page = adapter.fetchMangaList(source, 'popular', 2)
assert(list, list_err)
assert(#list == 1 and list[1].title == 'Synthetic & Test' and next_page)
assert(list[1].url == 'https://batcave.biz/42-synthetic.html' and list[1].cover == 'https://batcave.biz/cover.jpg')
function source:fetch(request_url)
    assert(request_url == 'https://batcave.biz/42-synthetic.html')
    return [[<header class="page__header"><h1>Synthetic Comic</h1></header><div class="page__poster"><img src="/cover.jpg"></div><ul class="page__list"><li><div>Writer</div><a>Synthetic Writer</a></li><li><div>Artist</div><a>Synthetic Artist</a></li><li><div>Publisher</div><a>Fixture Press</a></li><li><div>Year</div><a>2026</a></li><li><div>Release type</div>Completed</li></ul><div class="page__text">Synthetic summary</div><div class="page__tags"><a>Adventure</a></div><script>window.__DATA__ = {"news_id":42,"xhash":"_hash","chapters":[{"id":7,"posi":2.5,"title":"Synthetic ; Issue","date":"20.9.2026"}]}; window.other = true;</script>]]
end
local details, detail_err = adapter.fetchMangaDetails(source, '/42-synthetic.html')
assert(details, detail_err)
assert(details.title == 'Synthetic Comic' and details.author == 'Synthetic Writer' and details.artist == 'Synthetic Artist')
assert(details.status == 'Completed' and details.genres[1] == 'Adventure' and details.genres[2] == 'Comic')
assert(details.description:find('Fixture Press', 1, true))
local chapters, chapter_err = adapter.fetchChapterList(source, '/42-synthetic.html')
assert(chapters, chapter_err)
assert(#chapters == 1 and chapters[1].title == 'Synthetic ; Issue' and chapters[1].chapter_number == 2.5)
assert(chapters[1].url == 'https://batcave.biz/reader/42/7_hash' and chapters[1].date == '20.9.2026')
local invalid, invalid_err = adapter.parsePages(source, '{"data":{"images":["javascript:alert(1)"]}}')
assert(not invalid and invalid_err)
function source:fetch() return '<script>window.__DATA__={"news_id":42,"chapters":[{"id":7,"title":"Synthetic"}],"xhash":{}};</script>' end
local success, result, data_err = pcall(adapter.fetchChapterList, source, '/42-synthetic.html')
assert(success and not result and data_err, 'malformed xhash must return a parser error, not throw')
function source:fetch(request_url)
    assert(request_url == 'https://batcave.biz/page/2/')
    return '<div id="content-load"><div class="latest grid-item"><div class="latest__title"><a href="/synthetic.html">Synthetic &#x26; &#8217;</a></div><div class="latest__img"><img src="/cover.jpg"></div></div></div><li class="pagination"><a href="/page/3/">Next</a></li>'
end
list, list_err, next_page = adapter.fetchMangaList(source, 'latest', 2)
assert(list, list_err)
assert(list[1].title == 'Synthetic & ’' and next_page, list[1].title)
function source:fetch(request_url)
    assert(request_url == 'https://batcave.biz/search/test%20%2f%20query/page/2/')
    return '<div id="dle-content"></div><div class="pagination__pages"><a href="/previous">1</a><span>2</span></div>'
end
list, list_err, next_page = adapter.fetchMangaList(source, 'search', 2, 'test / query')
assert(list and #list == 0 and not next_page, list_err)
function source:fetch() return nil, 'synthetic network failure' end
pages, err = adapter.fetchPages(source, '/reader/42/7_hash')
assert(not pages and err == 'synthetic network failure')
function source:fetch() return '<title>DLE Guard</title>' end
details, detail_err = adapter.fetchMangaDetails(source, '/synthetic.html')
assert(not details and detail_err:find('DLE Guard', 1, true))
print('BatCave synthetic adapter suite PASS')
