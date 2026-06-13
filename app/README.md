# AI Maxx IDE — Flutter mobile client

VS Code–inspired dark workbench for Android/iOS. Connects to the Django backend over HTTPS and WebSockets.

## Prerequisites

### Flutter SDK

1. Clone Flutter to `C:\flutter` (or your preferred path).
2. Add `C:\flutter\bin` to your system `PATH`.
3. Verify: `flutter doctor`

## Setup

```powershell
cd app
flutter pub get
```

## Run on a device

```powershell
flutter devices
flutter run -d DEVICE_ID
```

Example: `flutter run -d 6000cc2e`

## Server

The backend must be running locally and exposed through the Cloudflare tunnel:

1. Start Django on `127.0.0.1:8000` (see repo root `sample.env` / `.env`).
2. Run the Cloudflare tunnel so `https://aimaxx.organisationapp.online` forwards to the local server.

Default client settings (overridable in the authenticate modal):

- Server: `https://aimaxx.organisationapp.online`
- API key: `change-me-to-a-long-random-secret` (matches repo `.env` `API_KEY`)

## Analyze

```powershell
flutter analyze
```
