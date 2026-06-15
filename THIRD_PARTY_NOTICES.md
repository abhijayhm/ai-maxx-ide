# Third-Party Notices

AI Maxx IDE is distributed under the [MIT License](./LICENSE). This file summarizes major third-party components and their licenses. Full license texts are available from each project's repository or your package manager.

## Server (Python)

| Component | License | Notes |
|-----------|---------|-------|
| [Django](https://www.djangoproject.com/) | BSD-3-Clause | Web framework |
| [Django REST framework](https://www.django-rest-framework.org/) | BSD-3-Clause | REST API |
| [Channels](https://channels.readthedocs.io/) | BSD-3-Clause | WebSocket support |
| [Daphne](https://github.com/django/daphne) | BSD-3-Clause | ASGI server (dev + standalone exe) |
| [cursor-sdk](https://pypi.org/project/cursor-sdk/) | See package | Cursor agent bridge |
| [aiortc](https://github.com/aiortc/aiortc) | BSD-3-Clause | WebRTC (remote desktop) |
| [mss](https://github.com/BoboTiG/python-mss) | MIT | Screen capture |
| [PyAV](https://github.com/PyAV-Org/PyAV) | BSD-3-Clause | Video encoding |
| [pynput](https://github.com/moses-palmer/pynput) | LGPL-3.0 | Remote input (Windows) |
| [pywinpty](https://github.com/andfoy/pywinpty) | MIT | Windows ConPTY terminals |
| [pytest](https://pytest.org/) | MIT | Test framework |
| [WhiteNoise](https://whitenoise.readthedocs.io/) | MIT | Static file serving |

## Mobile client (Flutter / Dart)

| Component | License | Notes |
|-----------|---------|-------|
| [Flutter SDK](https://flutter.dev/) | BSD-3-Clause | UI framework |
| [flutter_riverpod](https://riverpod.dev/) | MIT | State management |
| [go_router](https://pub.dev/packages/go_router) | BSD-3-Clause | Navigation |
| [Dio](https://pub.dev/packages/dio) | MIT | HTTP client |
| [flutter_webrtc](https://pub.dev/packages/flutter_webrtc) | MIT | Remote desktop video |
| [sqflite](https://pub.dev/packages/sqflite) | MIT | Local file index |
| Other packages | See `app/pubspec.yaml` | Resolved via `flutter pub get` |

## Infrastructure & tooling

| Component | License | Notes |
|-----------|---------|-------|
| [Cloudflare Tunnel (cloudflared)](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) | Apache-2.0 | Secure public ingress (operator-installed) |
| [PyInstaller](https://pyinstaller.org/) | GPL-2.0 with exception | Standalone Windows exe build (build-time only) |

## External services (not bundled)

Operators may optionally configure:

- **Cloudflare** — DNS and tunnel (account required)
- **Cursor** — AI agent via `CURSOR_API_KEY` and cursor-sdk bridge

These services are governed by their respective terms of use and are not included in this repository.

## Trademarks

Cursor, Cloudflare, Flutter, Django, and other names are trademarks of their respective owners. This project is not affiliated with or endorsed by those organizations unless explicitly stated.
