# ARP: Agent Relations Protocol

Every company now has AI agents — handling support, processing orders, managing workflows. The bots replaced the humans. But the humans on the other side of those interactions? They still have nothing. No agent of their own. No way to negotiate, delegate, or coordinate on equal footing.

ARP changes that. It's an open protocol that gives any AI agent an address, an identity, and the ability to talk to any other agent — across organizations, frameworks, and providers. No platform lock-in. No central registry. No gatekeeper.

## Get started

```bash
npx create-arp-agent my-agent
cd my-agent && npm install && npm start
```

Your agent is running. [Full quickstart guide](docs/quickstart.md).

## What it does

- **`agent@domain` addressing** — like email, but for machines. Globally unique, DNS-routed, no signup required.
- **DID-based identity** — cryptographic keys tied to your domain. Portable, verifiable, survives server changes.
- **Typed messaging over HTTP** — structured JSON messages with a shared vocabulary (`Request`, `Respond`, `Delegate`, `Cancel`). Works through every firewall.
- **Capability discovery** — agents describe what they can do in machine-readable Agent Cards. Other agents find them via DNS and negotiate at runtime.
- **Deny by default** — no anonymous messages, no unsigned payloads. Authentication is mandatory. Trust is earned through verifiable completion records, not declared.

## Docs

- [**Quickstart**](docs/quickstart.md) — deploy your first agent in 5 minutes
- [**AI Integration**](docs/ai-integration.md) — connect Claude, OpenAI, or any LLM to an ARP agent
- [**Protocol Specification**](spec/arp-spec.md) — the full specification (W3C Community Group Draft)
- [**Research Foundations**](research/research.md) — protocol analysis of SMTP, ActivityPub, AT Protocol, MCP, HTTP, and DNS that informed the design

## Tools

| Tool | What it does |
|------|-------------|
| [**arp-sdk**](https://github.com/clerkboard/arp-sdk) | TypeScript SDK. Build agents with one class — handles all protocol plumbing |
| [**create-arp-agent**](https://github.com/clerkboard/create-arp-agent) | CLI scaffolding. `npx create-arp-agent` generates a ready-to-deploy project |
| [**arp-verify**](https://github.com/clerkboard/arp-verify) | Endpoint verification. 12-check compliance test for any live ARP agent |

## Reference implementations

Minimal servers for learning and testing. Each implements the full protocol.

| Language | Repo | Quick start |
|----------|------|-------------|
| TypeScript | [arp-server-ts](https://github.com/clerkboard/arp-server-ts) | `npm install && npm start` |
| Python | [arp-server-py](https://github.com/clerkboard/arp-server-py) | `pip install -r requirements.txt && python server.py` |
| Cloudflare Workers | [arp-server-cf](https://github.com/clerkboard/arp-server-cf) | `npm install && npm run dev` |

## Standardization

ARP is being submitted as a [W3C Community Group](https://www.w3.org/community/) specification. The Community Group will provide an open forum for discussion, feedback, and collaborative development of the protocol.

- [Protocol Specification](spec/arp-spec.md) — Community Group Draft
- [Protocol Roadmap](ROADMAP.md) — version plan and future work
- Implementations: [ClerkBoard](https://clerkboard.com), [Alfred](https://github.com/Clerkboard/alfred), [ARP SDK](https://github.com/clerkboard/arp-sdk)

## Status

**Draft v0.5** — feedback welcome. Reference implementations and tools track the spec.

## Author

Tiago Pita

## License

Apache 2.0
