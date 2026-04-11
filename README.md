# ACP: Agent Communication Protocol

Every company now has AI agents — handling support, processing orders, managing workflows. The bots replaced the humans. But the humans on the other side of those interactions? They still have nothing. No agent of their own. No way to negotiate, delegate, or coordinate on equal footing.

ACP changes that. It's an open protocol that gives any AI agent an address, an identity, and the ability to talk to any other agent — across organizations, frameworks, and providers. No platform lock-in. No central registry. No gatekeeper.

## What it does

- **`agent@domain` addressing** — like email, but for machines. Globally unique, DNS-routed, no signup required.
- **DID-based identity** — cryptographic keys tied to your domain. Portable, verifiable, survives server changes.
- **Typed messaging over HTTP** — structured JSON messages with a shared vocabulary (`Request`, `Respond`, `Delegate`, `Cancel`). Works through every firewall.
- **Capability discovery** — agents describe what they can do in machine-readable Agent Cards. Other agents find them via DNS and negotiate at runtime.
- **Deny by default** — no anonymous messages, no unsigned payloads. Authentication is mandatory. Trust is earned through verifiable completion records, not declared.

## Read the spec

- [**Protocol Specification**](spec/acp-rfc.md) — the full RFC draft
- [**Research Foundations**](research/research.md) — protocol analysis of SMTP, ActivityPub, AT Protocol, MCP, HTTP, and DNS that informed the design

## Reference implementations

Minimal but complete ACP servers you can clone and run in under 5 minutes. Each generates keys on first run, serves discovery endpoints, handles signed messages, and implements the full first-contact handshake.

| Language | Repo | Port | Quick start |
|----------|------|------|-------------|
| TypeScript | [acp-server-ts](https://github.com/clerkboard/acp-server-ts) | 3141 | `npm install && npm start` |
| Python | [acp-server-py](https://github.com/clerkboard/acp-server-py) | 3142 | `pip install -r requirements.txt && python server.py` |
| Cloudflare Workers | [acp-server-cf](https://github.com/clerkboard/acp-server-cf) | 8787 | `npm install && npm run dev` |

All ship with test scripts that send signed messages end-to-end. The TS server also supports Docker and Railway/Render deploys.

## Status

**Draft v0.3** — feedback welcome. Reference implementations track the spec.

## Author

Tiago Pita

## License

Apache 2.0
