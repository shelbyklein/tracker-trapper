# Tracker Trapper website

Public URL: https://trackertrapper.shelbyklein.com

The editing source is the existing WordPress Studio theme at
`/Users/shelbyklein/Studio/trapper-tracker/wp-content/themes/tracker-trapper`.
The public landing page is a static export, served on Beelink from
`/srv/projects/trackertrapper/public` by Docker Compose and Cloudflare Tunnel.
WordPress admin, database and private development files are not published.

`theme/` retains the PHP templates and artwork provenance. The shared CSS and
served assets are in `public/`. Run `python3 website/export.py` from the repo
with the Studio site running to refresh the export. Copy updated PHP templates
into `theme/` when their source changes.

Deployment:

```sh
rsync -az website/public/ beelink:/srv/projects/trackertrapper/public/
rsync -az website/deploy/ beelink:/srv/projects/trackertrapper/deploy/
ssh beelink 'cd /srv/projects/trackertrapper/deploy && docker compose up -d'
```

The web container listens only on Beelink loopback port 8087. Tunnel ingress
accepts only trackertrapper.shelbyklein.com and returns 404 for other hosts.
Containers restart unless stopped. The tunnel credential lives outside Git at
`/srv/projects/trackertrapper/secrets/tunnel.json`, mode 0600. Never add it here.
Cloudflare tunnel ID: `8f0f21a7-c16f-451c-b00a-7f2c90f02160`.

To roll back a content update, export `website/public` from the desired Git
commit and synchronize that directory. To stop this site only:
`ssh beelink 'cd /srv/projects/trackertrapper/deploy && docker compose down'`.
The original Studio site is retained unchanged.
