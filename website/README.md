# PixelFit website

Static site for https://pixelfit.elazer.wang — plain HTML/CSS/JS served by Cloudflare Workers static assets (no Worker script, no framework).

- `public/index.html` holds the Chinese copy; `public/app.js` holds the English strings (`?lang=en`) and the interactive demos.
- Downloads link to GitHub Releases; nothing is hosted here.
- `npm run check` verifies English coverage, that every `vX.Y.Z` matches `APP_VERSION` in `../script/build_and_run.sh`, and that pages contain no inline script or style (the CSP in `public/_headers` forbids them).

## Release update

After a new GitHub Release, replace the version in `public/index.html` (links + JSON-LD `softwareVersion`), `public/app.js` and `public/llms.txt`, then `npm run check`.

## Deploy

```bash
npm install
npx wrangler login   # once
npm run deploy       # runs the check, then wrangler deploy
```

Fonts: IBM Plex Mono (SIL OFL 1.1, `public/assets/fonts/IBM-Plex-Mono-OFL.txt`).
