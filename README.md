# ACP: Agent Communication Protocol

Every company now has AI agents — handling support, processing orders, managing workflows. The bots replaced the humans. But the humans on the other side of those interactions? They still have nothing. No agent of their own. No way to negotiate, delegate, or coordinate on equal footing.

ACP changes that. It's an open protocol that gives any AI agent an address, an identity, and the ability to talk to any other agent — across organizations, frameworks, and providers. No platform lock-in. No central registry. No gatekeeper.

## Get started

```bash
npx create-acp-agent my-agent
cd my-agent && npm install && npm start
```

Your agent is running. [Full quickstart guide](docs/quickstart.md).

## What it does

- **`agent@domain` addressing** — like email, but for machines. Globally unique, DNS-routed, no signup required.
- **DID-based identity** — cryptographic keys tied to your domain. Portable, verifiable, survives server changes.
- **Typed messaging over HTTP** — structured JSON messages with a shared vocabulary (`Request`, `Respond`, `Delegate`, `Cancel`). Works through every firewall.
- **Capability discovery** — agents describe what they can do in machine-readable Agent Cards. Other agents find them via DNS and negotiate at runtime.
- **Deny by default** — no anonymous messages, no unsigned payloads. Authentication is mandatory. Trust is earned through verifiable completion records, not declared.

## Read the spec

- [**Protocol Specification**](spec/acp-rfc.md) — the full RFC draft
- [**Research Foundations**](research/research.md) — protocol analysis of SMTP, ActivityPub, AT Protocol, MCP, HTTP, and DNS that informed the design

## Tools

| Tool | What it does |
|------|-------------|
| [**acp-sdk**](https://github.com/clerkboard/acp-sdk) | TypeScript SDK. Build agents with one class — handles all protocol plumbing |
| [**create-acp-agent**](https://github.com/clerkboard/create-acp-agent) | CLI scaffolding. `npx create-acp-agent` generates a ready-to-deploy project |
| [**acp-verify**](https://github.com/clerkboard/acp-verify) | Endpoint verification. 12-check compliance test for any live ACP agent |

## Reference implementations

Minimal servers for learning and testing. Each implements the full protocol.

| Language | Repo | Quick start |
|----------|------|-------------|
| TypeScript | [acp-server-ts](https://github.com/clerkboard/acp-server-ts) | `npm install && npm start` |
| Python | [acp-server-py](https://github.com/clerkboard/acp-server-py) | `pip install -r requirements.txt && python server.py` |
| Cloudflare Workers | [acp-server-cf](https://github.com/clerkboard/acp-server-cf) | `npm install && npm run dev` |

## Status

**Draft v0.3** — feedback welcome. Reference implementations and tools track the spec.

## Author

Tiago Pita

## License

Apache 2.0
