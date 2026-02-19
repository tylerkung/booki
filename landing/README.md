# Booki Landing Page

Static marketing landing page for Booki - captures email waitlist signups from potential bookies.

## Tech Stack

- Static HTML/CSS (no build step required)
- Hosted on Netlify
- Forms powered by Netlify Forms

## Local Development

1. Open the landing page directly in your browser:
   ```bash
   open index.html
   ```

2. Or use any local HTTP server:
   ```bash
   # Python
   python3 -m http.server 8000

   # Node.js (npx)
   npx serve .
   ```

3. Visit `http://localhost:8000` in your browser.

## Project Structure

```
landing/
  index.html        # Main landing page
  privacy.html      # Privacy Policy (placeholder)
  terms.html        # Terms of Service (placeholder)
  styles.css        # All styles (CSS custom properties for theming)
  netlify.toml      # Local Netlify config reference
  README.md         # This file
netlify.toml        # Root Netlify config (publish = "landing/")
```

## Deployment (Netlify)

The site deploys to Netlify. Configuration is split between two files:

- **`/netlify.toml`** (repo root) — Sets `publish = "landing/"` so Netlify serves files from this directory. Also configures security headers.
- **`/landing/netlify.toml`** — Local reference config (publish = `.` relative to this directory).

### Option 1: Git-based deployment (recommended)

1. Connect your GitHub repo to Netlify at [app.netlify.com](https://app.netlify.com).
2. Netlify will auto-detect the `netlify.toml` at the repo root.
3. No build command is needed — this is a static site.
4. Every push to the configured branch will auto-deploy.

### Option 2: Manual deploy via CLI

```bash
npm install -g netlify-cli
netlify login

# Preview deploy (generates a draft URL)
netlify deploy --dir=landing

# Production deploy
netlify deploy --prod --dir=landing
```

### Netlify Forms

The waitlist form uses [Netlify Forms](https://docs.netlify.com/forms/setup/) — no backend required. The form is detected automatically via the `data-netlify="true"` attribute on the `<form>` tag in `index.html`. Submissions appear in the Netlify dashboard under **Forms > waitlist**.

### Post-deploy checklist

- Verify all 3 pages load: `/`, `/privacy.html`, `/terms.html`
- Verify form submission works (submit an email, check Netlify Forms dashboard)
- Verify security headers are applied (check response headers in browser dev tools)

## Theme Colors

| Token              | Value     |
|-------------------|-----------|
| `--bg`            | `#0A0A12` |
| `--bg-card`       | `#14141F` |
| `--accent`        | `#00F5D4` |
| `--accent-secondary` | `#9D4EDD` |
| `--text-primary`  | `#F8F8F8` |
| `--text-secondary`| `#A8A8B8` |
| `--text-muted`    | `#6B6B7B` |
