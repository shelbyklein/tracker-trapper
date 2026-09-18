#!/usr/bin/env python3
"""Export the local Studio landing page; WordPress remains the editing source."""
from pathlib import Path
import urllib.request,re,shutil
base=Path(__file__).resolve().parent
source=Path('/Users/shelbyklein/Studio/trapper-tracker/wp-content/themes/tracker-trapper')
html=urllib.request.urlopen('http://localhost:8887/').read().decode()
html=re.sub(r'<link[^>]+(?:api\.w\.org|wp-json|xmlrpc|shortlink|wp-includes)[^>]*>','',html)
html=re.sub(r'<link[^>]+dns-prefetch[^>]*>','',html)
html=re.sub(r'<script[^>]*(?:wp-emoji|speculationrules)[^>]*>.*?</script>','',html,flags=re.S)
html=re.sub(r'<meta name="generator"[^>]*>','',html)
html=html.replace('http://localhost:8887/wp-content/themes/tracker-trapper/','/').replace('http://localhost:8887','https://trackertrapper.shelbyklein.com')
html=re.sub(r'<link rel="alternate"[^>]*>','',html)
html=re.sub(r'<link rel="canonical"[^>]*>','',html)
html=html.replace('</head>','<link rel="canonical" href="https://trackertrapper.shelbyklein.com/"></head>')
(base/'public/index.html').write_text(html)
shutil.copy2(source/'style.css',base/'public/style.css')
for p in (source/'assets').iterdir():
 if p.suffix in ['.webp','.js','.gif','.woff2','.txt'] or p.name=='checkmark-nest-poster.png':shutil.copy2(p,base/'public/assets'/p.name)
(base/'public/robots.txt').write_text('User-agent: *\nAllow: /\nSitemap: https://trackertrapper.shelbyklein.com/sitemap.xml\n')
(base/'public/sitemap.xml').write_text('<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"><url><loc>https://trackertrapper.shelbyklein.com/</loc></url></urlset>')
assert 'localhost' not in html
print('Exported',len(list((base/'public').rglob('*'))),'entries')
