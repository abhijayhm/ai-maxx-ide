# Windows setup scripts

## Cloudflare Tunnel (server only)

**Entry point:** `setup_cloudflare_tunnel.bat`

Exposes **one hostname** (`SERVER_DOMAIN`) → `http://127.0.0.1:{BIND_PORT}` for Django REST + WebSockets. No SSH ingress.

### Before running

```bat
copy ..\..\sample.env ..\..\.env
```

Edit `.env`:

| Key | Example |
| --- | --- |
| `SERVER_DOMAIN` | `aimaxx.organisationapp.online` |
| `TUNNEL_NAME` | `ai-maxx-ide` |
| `BIND_PORT` | `8000` |

### Run

1. Double-click `setup_cloudflare_tunnel.bat` (elevates for cloudflared install if needed).
2. Complete Cloudflare browser login if prompted.

### After setup

```bat
cd server
uvicorn config.asgi:application --host 127.0.0.1 --port 8000
cloudflared tunnel run ai-maxx-ide
```

Or use `start_services.bat` to launch the tunnel in the background.

### Watchdog (silent background)

`install_watchdog_task.bat` registers a scheduled task that runs every minute with **no visible console**:

- Checks Cloudflare tunnel edge connections (`cloudflared tunnel list`)
- Checks local server health (`/api/health/` on `SERVER_PORT`)
- Restarts either process hidden if down

Actions are logged to `data/watchdog.log`. Remove with `remove_schedulers.bat`.

**Health check:** `https://{SERVER_DOMAIN}/api/health/`

See [docs/plan/structure.md](../../docs/plan/structure.md) and [sample.env](../../sample.env).
