"""Metadata-only live probe; never follows reader/image URLs or runs site JS.
Responses go to a caller-selected temporary directory, not committed fixtures.
Run: python tests/probe_comic_adapters_metadata.py OUTPUT_DIR
"""
import datetime
import json
import pathlib
import sys
import urllib.error
import urllib.request

out = pathlib.Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
probes = [
    ('readcomiconline', 'https://readcomiconline.li/ComicList/MostPopular?page=1'),
    ('readcomiconline_mirror', 'https://rcostation.xyz/ComicList/MostPopular?page=1'),
    ('batcave', 'https://batcave.biz/comix/'),
    ('readallcomics', 'https://readallcomics.com/'),
    ('xoxocomics', 'https://xoxocomic.com/hot-comic'),
]
results = []
for name, url in probes:
    req = urllib.request.Request(url, headers={
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Referer': url.split('/')[0] + '//' + url.split('/')[2] + '/',
    })
    if name == 'batcave':
        req.data = b'dlenewssortby=rating&dledirection=desc&set_new_sort=dle_sort_cat_1&set_direction_sort=dle_direction_cat_1'
        req.add_header('Content-Type', 'application/x-www-form-urlencoded')
        for key, value in {'Sec-Fetch-Dest': 'document', 'Sec-Fetch-Mode': 'navigate', 'Sec-Fetch-Site': 'none', 'Sec-Fetch-User': '?1'}.items():
            req.add_header(key, value)
    entry = {'source': name, 'request_url': url, 'method': req.get_method(), 'checked_at': datetime.datetime.now(datetime.timezone.utc).isoformat()}
    try:
        try:
            response = urllib.request.urlopen(req, timeout=40)
        except urllib.error.HTTPError as exc:
            response = exc
        with response:
            body = response.read(4_000_000)
            entry.update(status=response.code, final_url=response.url, bytes=len(body))
            path = out / (name + '-listing.html')
            path.write_bytes(body)
            entry['response_file'] = str(path)
            entry['guard_markers'] = [marker for marker in ['AreYouHuman', 'cf-chl-', '__guard_trust', 'DLE Guard', 'Just a moment'] if marker.encode() in body]
    except Exception as exc:
        entry['error'] = str(exc)
    results.append(entry)
(out / 'results.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
print(json.dumps(results, indent=2))
