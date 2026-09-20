local adapter = require("adapters/batcave")

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
    return adapter.fetchPages(source, chapter_url)
end

return Source
