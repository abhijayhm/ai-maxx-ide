# Security Policy

## Supported versions

Security fixes are applied on the default branch (`main`). There are no long-term release branches at this time.

## Reporting a vulnerability

**Please do not open a public GitHub issue for security vulnerabilities.**

Report security issues privately by opening a [GitHub Security Advisory](https://github.com/abhijayhm/ai-maxx-ide/security/advisories/new) (preferred) or by contacting the maintainers through your organization's usual security channel if you already work with Abhijay

Include:

- A description of the issue and potential impact
- Steps to reproduce
- Affected components (Flutter app, Django server, tunnel scripts, standalone exe)
- Any suggested fix or mitigation

We aim to acknowledge reports within **5 business days** and will coordinate disclosure once a fix is available.

## Deployment security notes

AI Maxx IDE is **self-hosted**. Operators are responsible for:

- Keeping `API_KEY`, `DJANGO_SECRET_KEY`, and `CURSOR_API_KEY` secret (never commit `.env`)
- Restricting `EXPOSED_DIRECTORIES_ABSOLUTE_PATHS` to directories you intend to expose
- Using a strong, unique API key for every deployment
- Keeping Cloudflare Tunnel credentials and DNS under your control
- Setting `REMOTE_INPUT_ENABLED=false` if remote desktop input is not required

The product is designed around **scoped capability access** (configured project roots, explicit `@path` context, optional remote desktop) rather than full-machine exposure. Misconfiguration of exposed paths or tunnel credentials can still lead to data exposure—treat the Windows host as a sensitive production surface.
