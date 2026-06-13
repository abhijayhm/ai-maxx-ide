# Windows setup scripts

## Cloudflare Tunnel + SSH

**Entry point:** `setup_cloudflare_tunnel.bat`

### Before running

1. Copy env template at repo root:
   ```bat
   copy ..\..\sample.env ..\..\.env
   ```
2. Edit `.env` — at minimum set:
   - `SERVER_DOMAIN` — e.g. `app.yourdomain.com`
   - `SSH_DOMAIN` — e.g. `ssh.yourdomain.com`
   - `TUNNEL_NAME` — e.g. `ai-maxx-ide`
   - `LOCAL_SERVER_PORT` — e.g. `8000`

The tunnel is configured for **2 hostnames by default** (`SERVER_DOMAIN` + `SSH_DOMAIN`), plus any entries in `TUNNEL_EXTRA_INGRESS`.

### Run

1. Run `setup_cloudflare_tunnel.bat` as **Administrator** (double-click is fine — it will elevate).
2. Complete Cloudflare browser login if prompted.

The batch file runs `setup_cloudflare_tunnel.py`, which reads `.env` directly (no domain prompts).

### What gets configured

| `.env` key | cloudflared ingress |
| --- | --- |
| `SERVER_DOMAIN` | `http://127.0.0.1:{LOCAL_SERVER_PORT}` |
| `SSH_DOMAIN` | `ssh://localhost:22` |
| each `TUNNEL_EXTRA_INGRESS[]` | custom `hostname` → `service` |

DNS CNAME routes are created for every hostname in that list.

**Requirements:** Python 3, Administrator, Cloudflare zone for your domains.

See [docs/plan/structure.md](../../docs/plan/structure.md) and [sample.env](../../sample.env).
