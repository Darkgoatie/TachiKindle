-- Synthetic reader data with real definitions, adapters and parser dependencies.
package.path = 'koplugin/tachikindle.koplugin/?.lua;' .. package.path
package.preload.socketutil = function() return {} end
package.preload.logger = function() return {info = function() end, warn = function() end} end
package.preload.datastorage = function() return {} end
package.preload['libs/libkoreader-lfs'] = function() return {} end
local Source = require('tachikindlesource')
local JSON = require('json')
local cases = {
    {
        name = 'readallcomics', chapter = 'https://readallcomics.com/synthetic-issue/',
        url = 'https://readallcomics.com/synthetic-issue/',
        body = '<body><img src="/synthetic.png"></body>',
        image = 'https://readallcomics.com/synthetic.png',
    },
    {
        name = 'xoxocomics', chapter = 'https://xoxocomic.com/comic/synthetic/issue-1',
        url = 'https://xoxocomic.com/comic/synthetic/issue-1/all',
        body = '<div class="page-chapter"><img data-original="synthetic.png"></div>',
        image = 'https://xoxocomic.com/comic/synthetic/issue-1/synthetic.png',
    },
    {
        name = 'readcomiconline', chapter = 'https://readcomiconline.li/Comic/Synthetic/Issue-1?id=1',
        url = 'https://readcomiconline.li/Comic/Synthetic/Issue-1?id=1&s=&quality=hq&readType=1',
        body = '<script>var pages = new Array(); pages.push("https://images.example.invalid/synthetic.png"); load(0,pages[currImage]);</script>',
        image = 'https://images.example.invalid/synthetic.png',
    },
    {
        name = 'batcave', chapter = 'https://batcave.biz/reader/42/7_hash',
        url = 'https://batcave.biz/engine/ajax/controller.php?mod=api&action=reader/getChapterData',
        body = '{"data":{"images":["/synthetic.png"]}}',
        image = 'https://batcave.biz/synthetic.png',
    },
}
for _, case in ipairs(cases) do
    local source = assert(Source:load('extensions/sources/en/' .. case.name .. '.tkext.json'))
    assert(source.def.id == 'en.' .. case.name and type(source.adapter) == 'table' and type(source.source_script) == 'table')
    local calls, stored = 0, nil
    function source:fetch(location, options)
        calls = calls + 1
        assert(location == case.url, location)
        if case.name == 'batcave' then
            assert(options.method == 'POST' and options.headers['Content-Type'] == 'application/json')
            local data = JSON.decode(options.body)
            assert(data.news_id == '42' and data.chapter_id == '7')
        else
            assert(not options or options.method == 'GET')
        end
        return case.body
    end
    function source:savePageListCache(chapter, pages)
        assert(chapter == case.chapter)
        stored = pages
    end
    function source:loadPageListCache() return stored end
    local pages, err = source:fetchPageList(case.chapter)
    assert(pages, err)
    assert(calls == 1 and #pages == 1 and pages[1] == case.image and stored == pages)
    function source:fetch() return nil, 'synthetic network failure' end
    assert(source:fetchPageList(case.chapter) == stored)
    print('PASS descriptor -> adapter -> reader -> cache: ' .. case.name)
end
print('4 actual descriptor integration cases passed')
