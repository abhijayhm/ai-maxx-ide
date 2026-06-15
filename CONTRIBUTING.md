# Contributing to AI Maxx IDE

Thank you for your interest in contributing. This repository is a monorepo with a **Flutter mobile client** (`app/`) and a **Django ASGI server** (`server/`).

## Getting started

1. Fork and clone the repository.
2. Copy `sample.env` to `.env` at the repo root and configure paths and secrets locally.
3. Set up the Python environment and Flutter SDK (see [README.md](./README.md)).
4. Run server tests: `cd server && python -m pytest`
5. Run client analysis: `cd app && flutter analyze && flutter test`

## Pull requests

- Keep changes focused; one logical change per PR when possible.
- Match existing code style and conventions in each language.
- Update documentation when behavior, URLs, or setup steps change.
- Add or update tests for server-side behavior changes.
- Do not commit `.env`, databases, build artifacts, or secrets.

## URL and auth conventions

When touching API or WebSocket paths, follow the project rules in [`.cursor/rules/important-basics.mdc`](./.cursor/rules/important-basics.mdc):

- REST: `{SERVER_DOMAIN}/api/…`
- WebSockets: `wss://{SERVER_DOMAIN}/api/ws/…`
- Flutter must use `AppConfig.webSocketUri` / `webSocketSyncUri` (no manual URL concatenation).

## Code of conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). By participating, you agree to uphold it.

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](./LICENSE).
