local adapter = require("adapters/xoxocomics")

local Source = {}

function Source.fetch_manga_list(source, endpoint_name, page, query)
    return adapter.fetchMangaList(source, endpoint_name, page or 1, query or "")
end

function Source.fetch_manga_details(source, manga_url)
    return adapter.fetchMangaDetails(source, manga_url)
end

function Source.fetch_chapter_list(source, manga_url)
    return adapter.fetchChapterList(source, manga_url)
end

function Source.fetch_page_list(source, chapter_url)
    if adapter.fetchPages then
        return adapter.fetchPages(source, chapter_url)
    end
    local url, err = source:resolveUrl("page_list", { chapter_url = chapter_url })
    if not url then return nil, err end
    local body, fetch_err = source:fetch(url)
    if not body then return nil, fetch_err end
    return adapter.parsePages(source, body, chapter_url)
end

return Source
