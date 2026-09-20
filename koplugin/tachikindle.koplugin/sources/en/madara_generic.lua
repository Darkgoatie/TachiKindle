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

function Source.fetch_page_list(source, chapter_url)
    return source:fetchPageListWithSelectors(chapter_url)
end

return Source
