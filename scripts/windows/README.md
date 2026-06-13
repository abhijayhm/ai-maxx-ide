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

**Health check:** `https://{SERVER_DOMAIN}/api/health/`

See [docs/plan/structure.md](../../docs/plan/structure.md) and [sample.env](../../sample.env).
