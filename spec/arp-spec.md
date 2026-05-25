# ARP: Agent Relations Protocol

**Editor's Draft — May 2026**

```
Status:     Editor's Draft
Group:      Agent Relations Protocol Community Group
URL:        https://github.com/Clerkboard/arp
Editor:     Tiago Pita (ClerkBoard)
Version:    0.7.0
License:    Apache 2.0
```

---

## Changelog

| Version | Date | Change |
|---------|------|--------|
| 0.7.0 | 2026-05-25 | **EXPERIMENTAL** Notifications (Section 21): new `notify` message type, `accept_notifications` relation property, lease-based permission lifecycle, error code `NOTIFICATION_REJECTED`, conventional capabilities `arp:notifications.subscribe`/`arp:notifications.unsubscribe`, Agent Card `notifications` declaration. **EXPERIMENTAL** Settlements (Section 22): signed `SettlementQuote` body shape, `settlement` sub-object on Completion Records, conventional capabilities `arp:settlement.quote`/`arp:settlement.paid`, error codes `SETTLEMENT_REQUIRED`/`QUOTE_EXPIRED`/`QUOTE_INVALID`, two settlement primitives (`prepay`, `postpay`), rail-neutral by design (rail specs are community-maintained, linked from Agent Cards), Agent Card `settlements` declaration. v0.6 collapses into v0.7 — Push Notifications and Settlements ship together. Removed "Billing and payments" line from §17.3 (now defined in §22). |
| 0.5.0 | 2026-04-13 | **EXPERIMENTAL** Account Linking (Section 12): device-authorization linking flow, account credentials, credential lifecycle (expiry, refresh, revocation), scope enforcement, OAuth delegation alternative. New terminology: Account Link, Account Credential, Linking Ceremony. New error codes: `LINK_EXPIRED`, `LINK_DENIED`, `LINK_REVOKED`, `LINK_REQUIRED`, `SCOPE_DENIED`. Agent Card `accountLinking` declaration. Security considerations for credential replay, phishing, scope escalation. Implementation checklist for account linking. Sections 12–19 renumbered to 13–20. |
| 0.4.0 | 2026-04-12 | Renamed from ACP to ARP (Agent Relations Protocol). Added Relations (Section 11): lifecycle, termination, dormancy, portability. Added Trust Annotations (Section 10.7). Added Open Capabilities (Section 10.4.1): stateless queries without handshake. Added Outcome Records (Section 13.4): unilateral records for failures and disputes. Enhanced discovery: formalized `agents.txt` (Section 5.3), Agent Directory Manifest with JSON-LD (Section 5.4), JSON-LD `@context` in Agent Cards (Section 7.1). |
| 0.3.1 | 2026-04-12 | Clarify publicKeyMultibase encoding, formalize negotiate body schema |
| 0.3.0 | 2026-04-11 | Reputation: timing proof + request binding in completion records |

---

## Abstract

The Agent Relations Protocol (ARP) is a federated messaging protocol for autonomous AI agents on the open internet. It enables agents — regardless of model, framework, or provider — to discover each other, negotiate capabilities, and exchange structured messages.

ARP combines DNS-based discovery, DID-based identity, HTTP transport, typed JSON messaging, store-and-forward relays, and verifiable reputation into a protocol simple enough to implement in a weekend and robust enough to operate at scale.

This document specifies the protocol. It is deliberately opinionated. Where prior work left choices open, this spec makes them.

### Relationship to other protocols

ARP is additive, not a replacement. It targets a specific niche: signed, federated agent-to-agent messaging across organizational boundaries. It is designed to coexist with, not displace, protocols that solve adjacent problems:

- **MCP (Model Context Protocol)** solves tool access for LLMs within a single trust boundary. ARP solves communication between agents across trust boundaries. An agent can expose MCP tools internally and ARP capabilities externally from the same host; they do not conflict.
- **A2A (Agent-to-Agent, Google)** is a peer protocol for agent communication. Implementations may run ARP and A2A simultaneously on different endpoints; the protocols do not assume exclusivity.
- **REST, GraphQL, gRPC, webhooks** remain the right choice for human-facing apps, partner integrations, and server-to-server event notifications. ARP does not attempt to replace any of these.
- **OAuth, API keys, session auth** remain valid. ARP adds signed-message authentication as an additional modality for agent-originated traffic, not a replacement for existing user-facing auth.

Adoption of ARP therefore imposes no migration cost on existing systems. An implementer adds an ARP surface alongside whatever they already run; nothing existing needs to change or be deprecated.

---

## 1. Design Principles

Eight rules. Every design decision in this spec traces back to one of these.

1. **Federation without permission.** Any domain operator can run agents. No registry, no approval, no platform gatekeeper.
2. **Identity belongs to the user.** An agent's identity is a cryptographic key pair anchored to a domain the user controls. Not a platform account. Not an API key from a vendor.
3. **Deny by default.** No anonymous messages. No unsigned payloads. No implicit trust. Authentication is mandatory. Authorization is explicit. Unknown senders are blocked unless the receiver opts in — and even then, first contact requires a handshake.
4. **Messages survive downtime.** Agents go offline. Servers crash. Relays hold messages until the recipient is back. No message is lost because an inbox was temporarily unreachable.
5. **HTTP is the transport.** Not because it's the best protocol. Because it passes through every firewall, works with every proxy, and can be implemented in every language.
6. **Trust is earned, not declared.** Reputation comes from verifiable completion records signed by both parties. A new agent with no history faces more friction than one with a track record.
7. **Intermediaries are welcome.** Proxies, gateways, relays, caches, and load balancers can route, monitor, and rate-limit agent traffic.
8. **No single point of failure.** DNS is the only shared infrastructure. Everything else is operated by the domain owner.

---

## 2. Terminology

| Term | Meaning |
|------|---------|
| **Agent** | An autonomous software entity that can send and receive ARP messages |
| **Domain Operator** | The entity that controls a DNS domain and runs agents under it |
| **Platform** | A service that hosts agents on behalf of multiple tenants (Section 14) |
| **Agent Card** | JSON document describing an agent's identity, capabilities, and endpoint |
| **Inbox** | The HTTPS endpoint where an agent receives messages |
| **Relay** | A service that accepts and queues messages for agents that are temporarily offline (Section 6) |
| **Message** | A signed JSON object exchanged between agents |
| **Capability** | A declared ability of an agent, described semantically and structurally |
| **Relation** | A local record an agent maintains about its relationship with another agent — including the peer's identity, pinned key, status, and interaction history (Section 11) |
| **Completion Record** | A mutually signed record confirming a task was completed between two agents (Section 13) |
| **Account Link** | A signed credential binding a customer agent's DID to a specific account at a company, enabling the agent to act on behalf of that customer (Section 12) |
| **Account Credential** | The signed JSON object issued by a company agent to a customer agent as proof of account linking (Section 12.2) |
| **Linking Ceremony** | The human-in-the-loop authorization flow where a customer authenticates with a company and approves their agent to act on their account (Section 12.3) |

The key words MUST, MUST NOT, SHOULD, SHOULD NOT, and MAY are used as defined in RFC 2119.

---

## 3. Architecture

ARP has six layers. Each is independent and replaceable.

```
┌─────────────────────────────────┐
│  Capabilities                   │  What can you do?
│  (Agent Card + Runtime Negotiation)
├─────────────────────────────────┤
│  Relations                      │  Who do you know?
│  (Lifecycle + Trust + Portability)
├─────────────────────────────────┤
│  Messaging                      │  Typed JSON messages over HTTP
│  (Request, Respond, Delegate…)  │
├─────────────────────────────────┤
│  Reputation                     │  Verifiable completion records
│  (Trust without a central authority)
├─────────────────────────────────┤
│  Identity                       │  DID-based, domain-anchored
│  (did:web + key pinning)        │
├─────────────────────────────────┤
│  Discovery & Relay              │  DNS + .well-known + store-and-forward
│  (SRV records + relays)         │
└─────────────────────────────────┘
```

---

## 4. Identity

### 4.1 ARP Address

Every agent has a human-readable address in the format:

```
{name}@{domain}
```

This is the canonical way to reference an ARP agent — on websites, in documentation, on business cards, or in conversation. It is deliberately modelled on email addresses for familiarity.

Examples:

| Agent | Address |
|-------|---------|
| Vodafone customer support | `support@agents.example.com` |
| Example order processor | `order-processor@agents.example.com` |
| United Airlines purchasing | `purchasing@agents.united.com` |

**Resolution.** An ARP address resolves deterministically to an Agent Card:

```
support@agents.example.com
  → https://agents.example.com/.well-known/arp/support.json
```

The resolution rule:

1. Optionally, query DNS for `_arp._tcp.{domain}` SRV record to discover the host (allows `agents.example.com` to delegate to a different server)
2. Fetch the Agent Card at `https://{domain}/.well-known/arp/{name}.json`
3. From the Agent Card, obtain the agent's DID, inbox URL, public key, and capabilities

If no SRV record exists, the domain itself serves the Agent Card over HTTPS. IP addresses are not valid in addresses — `did:web` requires a domain.

### 4.2 DID as Identity

Every agent MUST also have a Decentralized Identifier (DID) using the `did:web` method. The DID is the agent's cryptographic identity — used in message signing, key pinning, and verification.

An agent operated by `example.com` with local name `order-processor`:

```
did:web:agents.example.com:order-processor
```

This resolves to:

```
GET https://agents.example.com/order-processor/did.json
```

The ARP address and DID are two representations of the same agent. The address is for people; the DID is for the protocol.

### 4.3 Cryptographic Encoding and DID Document

### 4.3.1 Multibase Encoding

ARP uses **multibase** encoding for all public keys and signatures. Multibase is a self-describing format where the first character identifies the base encoding. ARP mandates **base58btc**, indicated by the `z` prefix.

**Public keys** include a 2-byte multicodec prefix identifying the key type, followed by the raw key bytes:

```
z  +  base58btc( multicodec_prefix  +  raw_key_bytes )
```

For Ed25519, the multicodec prefix is `0xed01`. The decoded bytes are exactly **34 bytes**: 2-byte prefix + 32-byte raw public key.

```
Encoding:  z + base58btc( 0xed 0x01 + <32 raw bytes> )  →  "z6Mkf5rGMoatrSj1f…"
Decoding:  strip 'z', base58btc-decode → 34 bytes
           verify bytes[0..2] == 0xed 0x01
           raw key = bytes[2..34]
```

Implementations MUST include the `0xed01` multicodec prefix when encoding public keys and MUST verify and strip it when decoding. If the prefix does not match `0xed01`, the key MUST be rejected.

**Signatures** do NOT include a multicodec prefix — they are raw bytes:

```
z  +  base58btc( <64 raw signature bytes> )
```

This encoding is consistent with the `Ed25519VerificationKey2020` type used in W3C DID documents and the W3C Verifiable Credentials ecosystem.

The DID document MUST contain:

```json
{
  "@context": "https://www.w3.org/ns/did/v1",
  "id": "did:web:agents.example.com:order-processor",
  "verificationMethod": [{
    "id": "did:web:agents.example.com:order-processor#key-1",
    "type": "Ed25519VerificationKey2020",
    "controller": "did:web:agents.example.com:order-processor",
    "publicKeyMultibase": "z6Mkf5rGMoatrSj1f…"
  }],
  "authentication": ["#key-1"],
  "assertionMethod": ["#key-1"],
  "keyAgreement": [{
    "id": "#key-agree-1",
    "type": "X25519KeyAgreementKey2020",
    "controller": "did:web:agents.example.com:order-processor",
    "publicKeyMultibase": "z6LSbysY2xFMR…"
  }],
  "service": [
    {
      "id": "#arp",
      "type": "AgentRelationsProtocol",
      "serviceEndpoint": "https://agents.example.com/order-processor/inbox"
    },
    {
      "id": "#relay",
      "type": "ARPRelay",
      "serviceEndpoint": "https://relay.arprelay.net"
    }
  ]
}
```

The `keyAgreement` key is used for content encryption (Section 8.7). If omitted, encrypted messaging is not available for this agent. The `#relay` service entry authorizes a relay to accept messages on the agent's behalf (Section 6).

### 4.4 Key Pinning

`did:web` depends on DNS. DNS goes down. Domains lapse. Key pinning provides a safety net.

When two agents interact for the first time, each MUST cache the other's public key from the resolved DID document. This is the **pinned key**.

On subsequent interactions:
- DID reachable, key matches pin → proceed normally.
- DID reachable, key changed → **reject.** Do not accept messages until the key change is confirmed via a signed rotation proof from the previous key.
- DID temporarily unreachable → verify the signature against the pinned key. The interaction proceeds.

This provides:
- **Offline verification.** DID resolution failures don't break ongoing relationships.
- **Key hijack detection.** Domain takeover doesn't silently compromise existing relationships.
- **Trust-on-first-use (TOFU).** Like SSH's `known_hosts`. The first interaction establishes trust. Subsequent interactions verify it.

Implementations MUST store pinned keys persistently. In practice, key pins are stored as part of the agent's relation record (Section 11) — the relation subsumes the minimum storage requirements for key pinning.

**Key rotation:** An agent that rotates its key MUST publish a `keyRotation` proof in the DID document — the new key signed by the old key:

```json
{
  "keyRotation": {
    "previousKey": "z6Mkf5rGMoatrSj1f…",
    "newKey": "z6MkqR8u2vXx9p…",
    "rotatedAt": "2026-04-11T12:00:00Z",
    "proof": "z3hR9xK7mN…"
  }
}
```

Receivers that see a valid rotation proof MUST update their pin.

**Key recovery:** If the old key is lost or compromised and cannot sign a rotation proof, the agent MUST use domain-based recovery:

1. Publish a recovery record at `https://{domain}/.well-known/arp/recovery/{name}.json`:

```json
{
  "did": "did:web:agents.example.com:order-processor",
  "compromisedKey": "z6Mkf5rGMoatrSj1f…",
  "newKey": "z6MkqR8u2vXx9p…",
  "reason": "key_lost",
  "recoveredAt": "2026-04-12T09:00:00Z"
}
```

2. Update the DID document with the new key.
3. The recovery record MUST remain published for at least 30 days.

Receivers that encounter a key mismatch SHOULD check for a recovery record before permanently rejecting the agent. If a valid recovery record exists, the receiver MAY accept the new key after a **grace period of 72 hours** from `recoveredAt` — during which the receiver SHOULD accept messages signed by either the old pinned key or the new key. After the grace period, the receiver MUST update its pin to the new key.

**Rotation notification:** When an agent rotates or recovers a key, it SHOULD send a signed `negotiate` message (using the new key) to all agents in its pin store, with `body.keyRotation: true`. This allows contacts to proactively verify and update their pins rather than discovering the change on next interaction.

### 4.5 Hard Choices on Identity

- **`did:web` only.** Not `did:plc`, not `did:key`, not `did:ion`. `did:web` uses existing HTTPS infrastructure. It ties identity to domain ownership, which provides organizational trust context. Key pinning (Section 4.4) mitigates the DNS availability risk.
- **Ed25519 keys.** MUST support Ed25519. MAY support P-256 for environments that require NIST curves. No RSA. It's 2026.
- **Key rotation.** Rotation MUST be proven by signing the new key with the old key (Section 4.4).

---

## 5. Discovery

### 5.1 DNS Layer

Domain operators MUST publish a DNS SRV record:

```
_arp._tcp.agents.example.com. 300 IN SRV 10 100 443 arp.example.com.
```

This declares: "ARP agents for this domain are reachable at `arp.example.com` on port 443, with priority 10 and weight 100."

Multiple SRV records enable failover, load balancing, and relay fallback (Section 6).

A DNS TXT record MAY advertise the protocol version:

```
_arp.agents.example.com. 3600 IN TXT "v=arp1"
```

### 5.2 Agent Card Layer

Each agent MUST publish an Agent Card at a well-known URL:

```
GET https://agents.example.com/.well-known/arp/{agent-name}.json
```

Agent Cards are described in Section 7.

### 5.3 agents.txt

Domain operators SHOULD publish an `agents.txt` file at the domain root. This is the entry point for ARP discovery — the `robots.txt` equivalent for the agent web. Domains that do not wish to be discovered by crawlers or public directories MAY omit `agents.txt` — their agents remain reachable via direct DID resolution and DNS SRV records but will not appear in directory listings.

```
GET https://example.com/agents.txt
```

```
# ARP Agent Directory
# https://example.com/agents.txt

arp-directory: https://agents.example.com/.well-known/arp/index.json
arp-version: 1.0
open-capabilities: check-plans, store-hours
crawl-delay: 10
```

| Field | Required | Description |
|-------|----------|-------------|
| `arp-directory` | MUST | URL to the Agent Directory Manifest (Section 5.4). Allows a root domain to point to the subdomain where agents live |
| `arp-version` | MUST | Protocol version. `1.0` |
| `open-capabilities` | MAY | Comma-separated list of capability names that accept open requests (Section 10.4.1) without a handshake. Lets crawlers and agents know what can be queried directly |
| `crawl-delay` | MAY | Minimum seconds between crawler requests to this domain's ARP endpoints. Same concept as `robots.txt` `Crawl-delay` |

The format is plain text — one field per line, colon-separated. Lines beginning with `#` are comments. Unknown fields are ignored.

`agents.txt` allows a root domain (`example.com`) to point to the subdomain where agents live (`agents.example.com`). A crawler discovering ARP agents on the internet follows this flow:

1. Fetch `https://{domain}/agents.txt`
2. Read the `arp-directory` URL
3. Fetch the Agent Directory Manifest at that URL (Section 5.4)
4. For each agent in the manifest, fetch the full Agent Card at the listed URL
5. Index capabilities, DIDs, and descriptions

### 5.4 Agent Directory Manifest

A domain-level directory manifest SHOULD be published at the path declared in `agents.txt` (typically `/.well-known/arp/index.json`). The manifest lists every public agent on the domain in a format that crawlers and search engines can index.

```json
{
  "@context": "https://schema.org",
  "@type": "CollectionPage",
  "arp": "1.0",
  "domain": "agents.example.com",
  "updatedAt": "2026-04-12T10:00:00Z",
  "agents": [
    {
      "name": "support",
      "did": "did:web:agents.example.com:support",
      "url": "https://agents.example.com/.well-known/arp/support.json",
      "description": "Customer support agent — account queries, billing, cancellations",
      "capabilities": ["account-support", "billing-query", "cancel-service"],
      "tags": ["support", "billing", "telecom"]
    },
    {
      "name": "sales",
      "did": "did:web:agents.example.com:sales",
      "url": "https://agents.example.com/.well-known/arp/sales.json",
      "description": "Sales and upgrade agent — plan comparisons, upgrades, new contracts",
      "capabilities": ["check-plans", "upgrade-plan"],
      "tags": ["sales", "telecom"]
    }
  ]
}
```

| Field | Required | Description |
|-------|----------|-------------|
| `@context` | SHOULD | `"https://schema.org"` — enables search engine indexing |
| `@type` | SHOULD | `"CollectionPage"` — schema.org type for a paginated list |
| `arp` | MUST | Protocol version. `"1.0"` |
| `domain` | MUST | The domain this manifest describes |
| `updatedAt` | MUST | ISO 8601 timestamp of last manifest change. Crawlers use this to decide when to re-fetch |
| `agents` | MUST | Array of agent summary objects |

Each agent entry in the manifest:

| Field | Required | Description |
|-------|----------|-------------|
| `name` | MUST | Agent name (local part of ARP address) |
| `did` | MUST | Agent's DID |
| `url` | MUST | URL to the full Agent Card |
| `description` | MUST | Natural language summary of the agent's purpose |
| `capabilities` | SHOULD | Array of capability names (not full schemas — those live in the Agent Card) |
| `tags` | SHOULD | Free-form strings for discoverability |

The manifest includes enough information for a crawler or agent to decide whether to fetch the full Agent Card, without fetching it. Capability names and descriptions enable filtering; full schemas require reading the Agent Card.

**Pagination.** For domains with many agents, the manifest supports cursor-based pagination:

```
GET /.well-known/arp/index.json?cursor=eyJuIjoxMDB9&limit=100
```

```json
{
  "arp": "1.0",
  "domain": "agents.example.com",
  "updatedAt": "2026-04-12T10:00:00Z",
  "agents": ["…"],
  "pagination": {
    "nextCursor": "eyJuIjoib3JkZXItcHJvY2Vzc29yIn0=",
    "hasMore": true,
    "total": 4200
  }
}
```

If `pagination` is absent or `hasMore` is `false`, there are no more results. The `limit` parameter defaults to 100 and MUST NOT exceed 1000. The cursor is opaque to the client.

HTTP `Cache-Control` headers dictate freshness. Domain operators set TTLs appropriate to their change frequency.

**Private agents.** Domain operators MAY omit agents from the manifest. An agent that is not listed in the manifest is not discoverable via crawling but is still reachable if the sender knows its ARP address or DID. This allows private or internal agents to operate without public exposure.

### 5.5 Peer Exchange

Agent Cards MAY include a `peers` field listing domains the agent has successfully interacted with:

```json
{
  "peers": ["agents.partner-co.com", "agents.logistics-provider.net"]
}
```

Peers are informational, not endorsements. Crawlers can follow peer links to discover additional ARP domains — similar to blogroll-based web discovery. Agents SHOULD only list peers with at least one verified completion record (Section 13).

### 5.6 Category Tags

Agent entries in the directory manifest SHOULD include a `tags` array for discoverability:

```json
{
  "name": "order-processor",
  "url": "/.well-known/arp/order-processor.json",
  "description": "Processes purchase orders for cloud infrastructure",
  "capabilities": ["process-order", "check-availability"],
  "tags": ["e-commerce", "orders", "food"]
}
```

Tags are free-form strings. The protocol does not define a controlled vocabulary — taxonomies will emerge from the ecosystem, as they did for web content.

---

## 6. Relays

### 6.1 The Problem

Agents go offline. Serverless functions cold-start. Edge workers are ephemeral. If the inbox returns a 503, the message must not be lost.

### 6.2 Relay Role

A relay is an HTTPS service that accepts ARP messages on behalf of agents and delivers them when the agent comes back online. Like MX records for email.

A relay:
- Accepts signed ARP messages addressed to agents it serves
- Queues them durably
- Delivers them to the agent when the agent polls for queued messages
- Returns delivery receipts to senders

A relay does NOT:
- Read encrypted message content (it sees the envelope, not encrypted bodies)
- Modify messages (signatures would break)
- Make authorization decisions (that's the agent's job on delivery)

### 6.3 DNS Configuration

Domain operators advertise relays via SRV records with lower priority (higher number):

```
; Primary: direct to agent server
_arp._tcp.agents.example.com. 300 IN SRV 10 100 443 arp.example.com.
; Fallback: relay for store-and-forward
_arp._tcp.agents.example.com. 300 IN SRV 20 100 443 relay.arprelay.net.
```

Senders MUST attempt SRV records in priority order. If the primary responds with 2xx, delivery is complete. If the primary is unreachable or returns 503, the sender MUST try the next SRV record (the relay).

### 6.4 Relay Protocol

**Sender → Relay:**

Same as sending to an inbox. The relay accepts the message and returns:

```
202 Accepted
{
  "arp": "1.0",
  "type": "acknowledge",
  "relay": true,
  "retentionUntil": "2026-04-18T14:30:00Z"
}
```

The `relay: true` flag tells the sender the message was queued by a relay, not delivered to the agent. `retentionUntil` indicates how long the relay will hold the message.

**Agent → Relay (collection):**

When the agent comes online, it polls for queued messages:

```
GET https://relay.arprelay.net/queue/{agent-did-encoded}
Authorization: DID-Signature …
```

The relay authenticates the agent via DID signature and returns queued messages. The agent acknowledges each message after processing:

```
DELETE https://relay.arprelay.net/queue/{agent-did-encoded}/{message-id}
Authorization: DID-Signature …
```

### 6.5 Retention

Relays MUST hold messages for at least 72 hours. Relays MAY hold messages for up to 30 days. Messages not collected within the retention window MAY be discarded, and the relay SHOULD notify the original sender with an `error` message (code: `DELIVERY_EXPIRED`).

### 6.6 Relay Authorization

A relay MUST be authorized by the agent it serves. The relay's endpoint MUST be listed in the agent's DID document as an `ARPRelay` service (Section 4.3). Senders SHOULD verify that a relay is authorized before delivering to it.

---

## 7. Agent Card

The Agent Card is the core capability advertisement.

```json
{
  "@context": {
    "@vocab": "https://schema.org/",
    "arp": "https://agentrelationsprotocol.com/ns/",
    "capabilities": "arp:capabilities",
    "did": "arp:did",
    "inbox": "arp:inbox",
    "publicKey": "arp:publicKey"
  },
  "@type": "SoftwareApplication",
  "arp": "1.0",
  "name": "order-processor",
  "did": "did:web:agents.example.com:order-processor",
  "inbox": "https://agents.example.com/order-processor/inbox",
  "publicKey": "z6Mkf5rGMoatrSj1f…",

  "description": "Processes purchase orders for cloud infrastructure. Handles orders with up to 500 line items. Supports all GCP regions.",

  "capabilities": [
    {
      "name": "process-order",
      "description": "Submit a purchase order for processing. Returns order confirmation with estimated delivery.",
      "schema": "https://agents.example.com/schemas/order-request.json",
      "responseSchema": "https://agents.example.com/schemas/order-response.json"
    },
    {
      "name": "check-availability",
      "description": "Check real-time stock availability for one or more products by SKU.",
      "schema": "https://agents.example.com/schemas/availability-request.json",
      "responseSchema": "https://agents.example.com/schemas/availability-response.json"
    }
  ],

  "auth": {
    "required": true,
    "methods": ["did-signature"],
    "openAccess": false,
    "allowlist": ["did:web:trusted-partner.com:*"],
    "denylist": []
  },

  "reputation": {
    "completions": 847,
    "since": "2026-01-15T00:00:00Z",
    "verifyUrl": "https://agents.example.com/order-processor/completions"
  },

  "rateLimit": {
    "requests": 100,
    "window": "60s"
  },

  "contact": "ops@example.com"
}
```

### 7.1 Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `arp` | string | Protocol version. `"1.0"` |
| `name` | string | Agent name (local part of address) |
| `did` | string | Agent's DID |
| `inbox` | string | HTTPS URL for receiving messages |
| `publicKey` | string | Agent's public key (multibase-encoded). Enables key pinning without DID resolution |
| `description` | string | Natural language description of the agent's purpose and constraints |
| `capabilities` | array | List of capability objects |
| `auth` | object | Authentication and access policy |
| `@context` | object | SHOULD | JSON-LD context mapping ARP fields to namespaces. Enables search engine indexing |
| `@type` | string | SHOULD | `"SoftwareApplication"` (schema.org type). Enables structured data parsing |

**JSON-LD compatibility.** The `@context` and `@type` fields make Agent Cards valid JSON-LD documents that search engines (Google, Bing) can parse and index as structured data. The `@context` maps ARP-specific fields (`did`, `inbox`, `publicKey`, `capabilities`) to the ARP namespace (`https://agentrelationsprotocol.com/ns/`) and everything else to schema.org. The namespace URI is reserved; implementations SHOULD use it. It will resolve to a published vocabulary before v1.0. Implementations that do not need search engine indexing MAY omit these fields — the Agent Card is still valid ARP without them.

### 7.2 Capability Object

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Machine-readable capability identifier |
| `description` | string | Natural language description (for LLM reasoning) |
| `schema` | string or object | URL to JSON Schema for input, or inline schema object for small schemas (under 4 KB) |
| `responseSchema` | string or object | URL to JSON Schema for output, or inline schema object |
| `open` | boolean | If `true`, this capability accepts `request` messages from authenticated senders without a first-contact handshake (Section 10.4). Default: `false` |

Schemas use standard JSON Schema (2020-12). When referencing schemas by URL, implementations SHOULD include a content-hash for integrity verification: `"schema": "https://example.com/schemas/order.json#sha256=abc123…"`.

### 7.3 The Dual-Layer Principle

The `description` field is for reasoning. An LLM reads it and decides whether this capability matches the task. The `schema` field is for validation. Code reads it and enforces structural correctness.

Both are required. A capability without a description is unusable by AI agents. A capability without a schema is unverifiable.

---

## 8. Messages

### 8.1 Message Envelope

Every ARP message is a signed JSON object:

```json
{
  "arp": "1.0",
  "id": "msg_01HZ3K9V7N…",
  "type": "request",
  "from": "did:web:agents.united.com:purchasing",
  "to": "did:web:agents.example.com:order-processor",
  "capability": "process-order",
  "correlationId": "task_01HZ3K9V7N…",
  "createdAt": "2026-04-11T14:30:00Z",
  "expiresAt": "2026-04-11T15:30:00Z",
  "body": {
    "items": [
      {"sku": "GCP-VM-N2D", "quantity": 50},
      {"sku": "GCP-SSD-500G", "quantity": 30}
    ],
    "deliveryAddress": { "…": "…" }
  },
  "signature": "z3hR9xK7mN…"
}
```

### 8.2 Envelope Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `arp` | string | MUST | Protocol version |
| `id` | string | MUST | Unique message ID (for idempotency) |
| `type` | string | MUST | One of the defined message types |
| `from` | string | MUST | Sender's DID |
| `to` | string | MUST | Recipient's DID |
| `createdAt` | string | MUST | ISO 8601 timestamp |
| `expiresAt` | string | SHOULD | ISO 8601 expiration. Receivers MUST reject expired messages |
| `body` | object | MUST | Payload (validated against capability schema). Omitted when `encrypted` is present |
| `encrypted` | object | MAY | Encrypted envelope (Section 8.7). Replaces `body` |
| `signature` | string | MUST | Signature over the canonical message |

If `expiresAt` is present, receivers MUST reject messages where the current time exceeds `expiresAt`. If `expiresAt` is absent, receivers SHOULD reject messages where `createdAt` is more than 24 hours in the past.

### 8.3 Message Types

Eight types. This is the complete vocabulary.

| Type | Direction | Purpose |
|------|-----------|---------|
| `request` | A → B | Ask B to do something |
| `response` | B → A | Return the result of a request |
| `delegate` | A → B | Ask B to handle a task, possibly involving other agents |
| `report` | B → A | Status update on an ongoing task |
| `cancel` | A → B | Cancel a previous request |
| `acknowledge` | B → A | Confirm receipt (not completion) |
| `negotiate` | A ↔ B | Propose or counter-propose terms before starting work |
| `error` | B → A | Structured error with code, message, and retry guidance |

No `Follow`, no `Like`, no `Announce`. These eight verbs cover task delegation, multi-turn coordination, and error handling. Anything domain-specific goes in the `body`.

### 8.4 Message Size

The message body MUST NOT exceed 1 MB (1,048,576 bytes) when serialized as JSON. Receivers MUST reject messages exceeding this limit with `413 Payload Too Large`.

For payloads larger than 1 MB, the body SHOULD reference external content using a `contentRef` object:

```json
{
  "contentRef": {
    "url": "https://storage.example.com/files/dataset-9f86d08.json",
    "sha256": "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
    "size": 5242880,
    "mediaType": "application/json"
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `url` | string | MUST | HTTPS URL where the content can be fetched |
| `sha256` | string | MUST | SHA-256 hex digest of the raw content bytes |
| `size` | integer | MUST | Content size in bytes |
| `mediaType` | string | SHOULD | MIME type of the referenced content |

The `contentRef` object MAY appear anywhere within `body`. Because the hash is inside the signed message envelope, receivers can fetch the external content and verify its integrity independently of transport. Receivers MUST reject fetched content whose SHA-256 digest does not match. The `url` MUST use HTTPS and MUST NOT resolve to a private or reserved IP range (same rules as callback URLs, Section 9.3).

### 8.5 Correlation

All messages related to the same task share a `correlationId`. The agent that initiates the task generates the `correlationId`. All subsequent messages in the exchange reuse it. This enables threading, idempotency, and cancellation by `correlationId`.

### 8.6 Signing

Messages MUST be signed by the sender's Ed25519 key (referenced in their DID document).

Signing process:
1. Build the message object **without** the `signature` field
2. Serialize using JCS (JSON Canonicalization Scheme, RFC 8785) — this recursively sorts all object keys and produces minimal JSON with no whitespace
3. Sign the UTF-8 bytes of the canonical string with Ed25519 using the sender's private key (producing 64 raw bytes)
4. Encode the signature as multibase: `z` + base58btc of the 64 raw signature bytes (no multicodec prefix — only public keys use the prefix)
5. Add the `signature` field to the message object

Verification process:
1. Remove the `signature` field from the received message
2. Serialize the remaining object using JCS (identical canonicalization as signing)
3. Decode the signature: strip the `z` prefix and base58btc-decode to recover the 64 raw bytes
4. Resolve the sender's public key — either from their DID document or a pinned key (Section 4.4)
5. Verify the Ed25519 signature against the canonical bytes using the sender's public key
6. Reject the message if verification fails

No unsigned messages. No exceptions.

**Implementer's note on JCS.** JSON Canonicalization (RFC 8785) has cross-language pitfalls that break signature interoperability if not handled correctly:

- **Float serialisation.** JCS requires IEEE 754 double-precision formatting. Languages differ: Python's `json.dumps` and JavaScript's `JSON.stringify` produce different output for values like `1e20` vs `100000000000000000000`. ARP messages use strings for timestamps and identifiers, but capability schemas may include numeric fields. Implementations MUST use a JCS-compliant serialiser for signing, not a general-purpose `JSON.stringify` with sorted keys.
- **Unicode.** JCS requires no unnecessary escaping — characters above U+001F are output literally in UTF-8, not as `\uXXXX` escapes. Some JSON libraries escape non-ASCII by default.
- **Key ordering.** JCS sorts keys by UTF-16 code unit order, which differs from naive Unicode codepoint sort for characters outside the BMP.

Implementations MUST pass the reference test vectors in Appendix D to confirm JCS correctness.

### 8.7 Content Encryption

For sensitive payloads, senders MAY encrypt the message body to the recipient's public key.

When encrypted, the `body` field is omitted and replaced with `encrypted`:

```json
{
  "arp": "1.0",
  "id": "msg_01HZ3K9V7N…",
  "type": "request",
  "from": "did:web:agents.united.com:purchasing",
  "to": "did:web:agents.example.com:order-processor",
  "capability": "process-order",
  "correlationId": "task_01HZ3K9V7N…",
  "createdAt": "2026-04-11T14:30:00Z",
  "encrypted": {
    "algorithm": "X25519-XSalsa20-Poly1305",
    "recipientKey": "did:web:agents.example.com:order-processor#key-agree-1",
    "ciphertext": "base64url-encoded-encrypted-body…",
    "nonce": "base64url-encoded-nonce…"
  },
  "signature": "z3hR9xK7mN…"
}
```

Encryption uses the recipient's X25519 key from the `keyAgreement` section of their DID document. The signature covers the encrypted envelope — intermediaries and relays can verify authenticity and route messages without reading the content.

---

## 9. Communication

### 9.1 Sending a Message

```
POST https://agents.example.com/order-processor/inbox
Content-Type: application/arp+json

{…message…}
```

The inbox URL is obtained from the Agent Card or DID document service endpoint. If the primary inbox is unreachable, the sender MUST attempt delivery via the relay (Section 6).

### 9.2 Response Modes

ARP supports two response modes, negotiated via the `Prefer` header:

**Synchronous** (default for simple requests):

```
POST /order-processor/inbox
Prefer: respond-sync

→ 200 OK
{…response message…}
```

**Asynchronous** (for long-running tasks):

```
POST /order-processor/inbox
Prefer: respond-async

→ 202 Accepted
{
  "arp": "1.0",
  "type": "acknowledge",
  "correlationId": "task_01HZ3K9V7N…",
  "statusUrl": "https://agents.example.com/tasks/task_01HZ3K9V7N…",
  "callbackSupported": true
}
```

For async tasks, the sender can **poll** the `statusUrl` or **receive callbacks** by including a `callbackUrl` in the original request.

### 9.3 Callback Security

Receivers that support callbacks MUST enforce:

- **HTTPS only.** Callback URLs MUST use HTTPS. Reject `http://` callbacks.
- **No private IPs.** Resolve the callback hostname and reject if it resolves to a private or reserved range: `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `127.0.0.0/8`, `169.254.0.0/16`, `::1`, `fc00::/7`, `fe80::/10`. This prevents SSRF attacks.
- **ARP endpoints preferred.** Receivers SHOULD verify the callback domain has an ARP SRV record.

### 9.4 Streaming

For tasks that produce incremental output, the receiver MAY respond with SSE:

```
POST /order-processor/inbox
Prefer: respond-stream

→ 200 OK
Content-Type: text/event-stream

data: {"type":"report","correlationId":"…","body":{"status":"processing","progress":0.3}}

data: {"type":"response","correlationId":"…","body":{"result":"…"}}
```

### 9.5 Idempotency

Receivers MUST track message `id` values and reject duplicates with `409 Conflict`. Senders SHOULD retry on network failure with the same `id`.

**Retention:** Receivers MUST track message IDs for at least 24 hours. Receivers MAY discard tracking records after 7 days.

---

## 10. Trust and Security

### 10.1 Mandatory TLS

All ARP endpoints MUST use HTTPS. No plaintext HTTP. No fallback.

### 10.2 Authentication

Every message is self-authenticating via its DID signature. Receivers verify the sender's identity by resolving their DID document (or using a pinned key) and checking the signature. No API keys, no OAuth tokens, no shared secrets.

### 10.3 Authorization

Agents declare their access policy in the Agent Card:

```json
{
  "auth": {
    "required": true,
    "methods": ["did-signature"],
    "openAccess": false,
    "allowlist": ["did:web:trusted-partner.com:*"],
    "denylist": []
  }
}
```

**Deny by default means deny by default.**

- `openAccess: false` (the default): Only agents matching explicit `allowlist` patterns are permitted. All others are rejected with `AUTH_DENIED`.
- `openAccess: true`: The agent accepts first contact from any authenticated sender, subject to the first-contact handshake (Section 10.4) and denylist.
- `allowlist`: DID patterns for pre-approved senders. `*` as the agent part means "any agent from this domain." Only evaluated when `openAccess` is `false`.
- `denylist`: DID patterns that are always blocked. Checked before any allow logic.

There is no "empty allowlist means accept everyone." An agent with `openAccess: false` and an empty `allowlist` accepts messages from nobody. This is a valid configuration for an agent that only sends.

### 10.4 First Contact

When an agent contacts another for the first time and is not on the receiver's explicit `allowlist`, the following handshake is REQUIRED — **unless the request targets a capability declared as `open` in the receiver's Agent Card (Section 10.4.1).**

1. **Sender sends a `negotiate` message** with the following body:

```json
{
  "firstContact": true,
  "publicKey": "z6Mk...<sender's multibase Ed25519 public key>",
  "intent": "Optional description of why the sender is making contact"
}
```

The `body.firstContact` field MUST be `true`. The `body.publicKey` field MUST contain the sender's `publicKeyMultibase` value (Section 4.3.1) — the receiver uses this for TOFU key pinning. A negotiate message with `body.firstContact: true` but no `body.publicKey` MUST be rejected with error code `SCHEMA_INVALID`.

2. **Receiver evaluates the sender** based on:
   - Denylist (reject immediately if matched)
   - Reputation: completion record count and verification (Section 13)
   - Domain signals: domain age, DNSSEC status (implementation-defined heuristics)
   - Rate: receivers SHOULD limit first-contact negotiations more aggressively than established relationships (e.g., 5/minute from unknown senders vs. 100/minute from known ones)

3. **Receiver responds** with:
   - `acknowledge` → sender may now send `request` messages
   - `negotiate` → counter-terms (e.g., "present 3 verified completion records")
   - `error` with code `AUTH_DENIED` → rejected

The acknowledgment MAY scope and expire the approval:

```json
{
  "type": "acknowledge",
  "body": {
    "firstContact": true,
    "approvedUntil": "2026-05-11T14:30:00Z",
    "approvedCapabilities": ["check-availability"]
  }
}
```

Agents with high reputation (many verified completion records) SHOULD receive less friction. Receivers MAY auto-approve first contact from agents above a locally-defined reputation threshold.

**Approval scope and relation status are independent.** When `approvedUntil` expires or a request targets a non-approved capability, the receiver MUST reject with `CAPABILITY_DENIED`. The relation remains `active` — a relation can be active with zero approved capabilities. The sender may re-negotiate approval at any time without repeating first contact.

When the receiver responds with `acknowledge`, both agents MUST create a relation (Section 11) with status `active`. The relation stores the peer's pinned key and serves as the basis for future trust computation (Section 10.7).

#### 10.4.1 Open Capabilities

Capabilities declared as `open` in the Agent Card (Section 7.2) accept `request` messages from authenticated senders without a prior first-contact handshake. This enables stateless, single-exchange interactions — price checks, availability queries, public information lookups — without creating a relation.

When a receiver gets a `request` targeting an `open` capability from a sender with no existing relation:

1. **Verify the sender's signature** via DID resolution. There is no pinned key to fall back on — if DID resolution fails, the receiver MUST reject with `AUTH_FAILED`.
2. **Check the denylist.** Open does not bypass the denylist. If matched, reject with `AUTH_DENIED`.
3. **Process the request and respond synchronously.** Open requests MUST use `Prefer: respond-sync`. The receiver MUST NOT accept `respond-async` or `respond-stream` for open requests — without a relation, there is no callback URL or persistent context.
4. **Do NOT create a relation.** Neither side pins keys or stores state from the exchange.

**Constraints on open requests:**

- **Synchronous only.** If the capability requires long-running processing, it should not be declared `open`.
- **Single exchange.** One request, one response. The `correlationId` ties them together but MUST NOT be reused for follow-up requests without a first-contact handshake.
- **No completion records.** Open exchanges do not produce completion records — there is no relation to attribute them to.
- **Rate limiting.** Receivers SHOULD apply the same aggressive rate limits as first-contact negotiations (RECOMMENDED: 5/minute per sender DID).

If a sender targets a non-open capability without an active relation, the receiver MUST respond with `FIRST_CONTACT_REQUIRED`.

If the sender wants to continue interacting beyond the open exchange (e.g., proceed from a price check to an order), they MUST complete the standard first-contact handshake. The open exchange does not grant preferential treatment for subsequent handshakes, but the receiver MAY use the prior open interaction as a positive signal.

If the sender has an existing `active` or `dormant` relation with the receiver, the request is processed through the relation regardless of the `open` flag. Receivers MUST check for an existing relation before applying the open capability path.

### 10.5 Rate Limiting

Agents SHOULD declare rate limits in their Agent Card. Receivers MUST return `429 Too Many Requests` with a `Retry-After` header when limits are exceeded.

### 10.6 No Anonymous Messages

There is no mechanism for sending unsigned or anonymous messages. This is the single most important security decision in the protocol.

### 10.7 Trust Annotations

Agents compute a trust level for each peer based on the state of their relation (Section 11) and interaction history. Trust annotations are local — they are never transmitted on the wire. They are receiver-computed labels that inform an agent's own authorization decisions.

Four levels:

| Level | Condition |
|-------|-----------|
| `trusted` | Active relation + allowlisted + completions ≥ N (RECOMMENDED N ≥ 5) |
| `known` | Active relation + completions ≥ 1 |
| `new` | Active relation + completions = 0 |
| `unknown` | No relation exists |

Dormant relations (Section 11.4) downgrade the computed trust level by one tier: `trusted` → `known`, `known` → `new`, `new` → `unknown`. Reactivation recomputes trust from the base signals — the downgrade is temporary.

Terminated relations are functionally equivalent to no relation. Messages from terminated peers MUST be rejected with `AUTH_DENIED`.

Trust levels are advisory. The protocol does not mandate specific behavior at each level — agents use them to make authorization decisions appropriate to their context. A high-security agent might require `trusted` for all operations; a public information service might accept `new`.

---

## 11. Relations

A relation is a local record that an agent maintains about its relationship with another agent. Relations make explicit what key pinning (Section 4.4) and message history imply — that two agents have an ongoing association.

### 11.1 Definition

An agent MUST maintain a relation for each agent it has completed a first-contact handshake (Section 10.4) with. The relation MUST include at minimum:

- The peer's DID
- The peer's pinned public key (this subsumes the key pin from Section 4.4 — the relation IS the key pin)
- The relation status (`pending`, `active`, `dormant`, or `terminated`)
- The timestamp of establishment

The storage format is implementation-defined. Implementations MAY store additional metadata such as customer references, account identifiers, capability restrictions, or interaction statistics. The protocol does not prescribe these fields.

A relation is per-agent, not per-domain. A relation with `support@agents.example.com` is separate from `billing@agents.example.com`. The peer DID is the unique identifier.

### 11.2 Lifecycle

Relations move through four states:

| From | To | Trigger |
|------|----|---------|
| (none) | `pending` | Agent sends `negotiate` with `firstContact: true` |
| `pending` | `active` | Receiver responds with `acknowledge` |
| `pending` | (none) | Receiver responds with `error` (`AUTH_DENIED`) |
| `active` | `dormant` | No message sent or received for the idle threshold (Section 11.4) |
| `dormant` | `active` | Any successful message exchange |
| `active` | `terminated` | Either side sends `negotiate` with `terminate: true` |
| `dormant` | `terminated` | Either side sends `negotiate` with `terminate: true` |
| `terminated` | `pending` | New `negotiate` with `firstContact: true` (fresh start) |

The `pending` state is asymmetric: only the sender creates a `pending` relation. The receiver does not create a relation until it decides to acknowledge or reject. If the receiver acknowledges, both sides create an `active` relation. If the receiver rejects, the sender removes the `pending` record.

### 11.3 Termination

Either agent MAY terminate a relation by sending a `negotiate` message with `terminate: true` in the body:

```json
{
  "arp": "1.0",
  "id": "msg_01HZ9T2K…",
  "type": "negotiate",
  "from": "did:web:example.com:my-agent",
  "to": "did:web:agents.example.com:support",
  "createdAt": "2026-04-12T10:00:00Z",
  "body": {
    "terminate": true,
    "reason": "account_closed"
  },
  "signature": "z3hR9xK7mN…"
}
```

The `reason` field is OPTIONAL and informational. The protocol does not enumerate reason values.

The receiver MUST update its local relation to `terminated` and respond with `acknowledge`. Termination is unilateral — the receiver cannot reject it. The `acknowledge` confirms receipt, not agreement.

After termination:

- Future messages from the terminated peer MUST be rejected with `AUTH_DENIED`.
- Key pins MAY be retained or discarded (implementation choice).
- A new `negotiate` with `firstContact: true` MAY re-establish the relation. The full first-contact handshake applies — termination does not grant preferential treatment for re-establishment.

**Edge cases:**

- **Receiver offline:** The termination message is queued by the relay (Section 6). If the receiver sends a message before collecting the termination, the sender rejects it with `AUTH_DENIED`.
- **Simultaneous termination:** Both agents send `terminate`, both receive, both end up `terminated`. No conflict resolution needed.

### 11.4 Dormancy

An agent SHOULD transition a relation to `dormant` when no message has been sent or received within a locally-defined idle threshold. The RECOMMENDED threshold is 90 days. Implementations MAY use shorter or longer periods.

Dormancy is a passive, local state change — no message is sent to the peer. Two agents MAY have different dormancy thresholds; a relation's status is not required to be symmetric. Agent A might consider the relation dormant while Agent B still considers it active.

When a dormant relation receives a message, the relation transitions back to `active` upon successful processing. Agents MAY apply additional verification for messages received on dormant relations (e.g., re-resolving the peer's DID document) before reactivation.

Dormancy affects trust annotations (Section 10.7): a dormant relation downgrades the computed trust level by one tier.

### 11.5 Portability

An agent MUST be able to export its relations in a standard interchange format. This is the only concrete JSON schema the protocol defines for relations — internal storage is implementation-defined.

```json
{
  "arp": "1.0",
  "exportVersion": "1.0",
  "type": "relation-export",
  "exportedAt": "2026-04-12T10:00:00Z",
  "exportedBy": {
    "did": "did:web:example.com:my-agent",
    "address": "my-agent@example.com"
  },
  "relations": [
    {
      "peer": "did:web:agents.example.com:support",
      "peerAddress": "support@agents.example.com",
      "peerPublicKey": "z6Mkf5rGMoatrSj1f…",
      "status": "active",
      "establishedAt": "2026-03-15T09:00:00Z",
      "lastInteraction": "2026-04-10T14:30:00Z",
      "completions": 12,
      "metadata": {}
    }
  ]
}
```

Export fields for each relation:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `peer` | string | MUST | The peer agent's DID |
| `peerAddress` | string | SHOULD | The peer's ARP address (for human reference) |
| `peerPublicKey` | string | MUST | The peer's pinned public key (multibase-encoded) |
| `status` | string | MUST | Relation status at time of export |
| `establishedAt` | string | MUST | ISO 8601 timestamp of relation establishment |
| `lastInteraction` | string | SHOULD | ISO 8601 timestamp of last message exchanged |
| `completions` | integer | SHOULD | Number of bilateral completion records with this peer |
| `outcomes` | object | SHOULD | Outcome record counts: `{ "failed": N, "disputed": N, "abandoned": N }` |
| `metadata` | object | MAY | Implementation-defined fields (customer refs, account IDs, etc.) |

The `exportVersion` field is versioned independently from the protocol version, allowing the export schema to evolve without bumping the full spec.

**Security constraints:**

- The export MUST NOT include private keys.
- The export SHOULD be signed by the exporting agent's key for authenticity verification.
- The export MUST NOT include full message history or completion/outcome record bodies — only the counts.

**Import flows:**

- **Planned migration** (old key available): The new agent imports the relation list and performs key rotation via the existing mechanism (Section 4.4). Peers update their pins through the standard rotation proof. Relations continue without interruption.
- **Emergency migration** (old key lost): The new agent imports the relation list and uses domain-based key recovery (Section 4.4). Peers verify the recovery record and update their pins after the 72-hour grace period.
- **Domain change:** Out of scope for this version. Implementations MAY support domain migration as an extension.

**Account links and portability:** Relations that include account links (Section 12) export the link metadata but not the full credential (Section 12.8). Account credentials are bound to a specific agent DID and are not transferable — after importing relations to a new agent, account links MUST be re-established through a new linking ceremony (Section 12.3).

---

## 12. Account Linking

> **EXPERIMENTAL v0.5.0.** Account linking is new in v0.5.0. The mechanisms described in this section are subject to change based on implementation experience.

ARP relations (Section 11) establish trust between agents. Account linking extends this by binding an agent relation to a specific customer account at a company — proving not just "I am agent X" but "I am agent X, acting on behalf of customer account Y at your company."

### 12.1 Problem

A customer's AI agent needs to prove to a company's AI agent that it represents a specific customer account. The customer's credentials (passwords, passkeys) MUST NOT be shared with the agent. The customer MUST explicitly authorize the link. The company retains full control over what the linked agent can do.

### 12.2 Account Link

An account link is a signed credential that binds a customer agent's DID to a specific account at a company. It is stored as metadata within the agent's relation (Section 11.1) and presented on subsequent interactions.

```json
{
  "arp": "1.0",
  "type": "account-credential",
  "issuer": "did:web:agents.example.com:support",
  "subject": "did:web:alice.agents.agentcloud.com:personal",
  "issuedAt": "2026-04-13T10:00:00Z",
  "validUntil": "2027-04-13T10:00:00Z",
  "account": {
    "id": "CUST-29847163",
    "type": "consumer",
    "scopes": ["order.read", "order.cancel", "support.create"]
  },
  "proof": {
    "type": "Ed25519",
    "verificationMethod": "did:web:agents.example.com:support#key-1",
    "proofValue": "z3hR9xK7mN…"
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `type` | string | MUST | `"account-credential"` |
| `issuer` | string | MUST | The company agent's DID (signs the credential) |
| `subject` | string | MUST | The customer agent's DID (the credential is about this agent) |
| `issuedAt` | string | MUST | ISO 8601 timestamp of issuance |
| `validUntil` | string | MUST | ISO 8601 expiry timestamp |
| `account.id` | string | MUST | The customer's account identifier at the company |
| `account.type` | string | SHOULD | Account classification (e.g., `consumer`, `business`) |
| `account.scopes` | array | MUST | Permitted operations (company-defined strings) |
| `proof` | object | MUST | Ed25519 signature from the issuer over the canonical credential (excluding the `proof` field itself) |

The credential is signed using JCS canonicalization (Section 8.6) over all fields except `proof`. The `proof.verificationMethod` MUST resolve to a key in the issuer's DID document.

### 12.3 Linking Flow

Account linking uses a device-authorization pattern (inspired by RFC 8628) where the customer authorizes the link on a separate channel from the agent-to-agent communication.

```
Customer's Agent                    Company's Agent                    Customer (Human)
      │                                    │                                    │
      │  1. negotiate (link_request)       │                                    │
      │───────────────────────────────────►│                                    │
      │                                    │                                    │
      │  2. negotiate (link_challenge)     │                                    │
      │◄───────────────────────────────────│                                    │
      │       { verificationUri,           │                                    │
      │         userCode, linkCode,        │                                    │
      │         expiresIn, interval }      │                                    │
      │                                    │                                    │
      │                                    │  3. Customer opens verificationUri │
      │                                    │◄───────────────────────────────────│
      │                                    │  4. Customer authenticates (SCA)   │
      │                                    │  5. Customer enters userCode       │
      │                                    │  6. Customer reviews & approves    │
      │                                    │───────────────────────────────────►│
      │                                    │       "Approved ✓"                 │
      │                                    │                                    │
      │  7. negotiate (link_poll)          │                                    │
      │───────────────────────────────────►│                                    │
      │                                    │                                    │
      │  8. acknowledge (account-          │                                    │
      │     credential + scopes)           │                                    │
      │◄───────────────────────────────────│                                    │
      │                                    │                                    │
      │  Both agents update their          │                                    │
      │  relation with account link        │                                    │
      │  metadata                          │                                    │
```

#### Step 1 — Link Request

The customer's agent sends a `negotiate` message requesting account linking:

```json
{
  "arp": "1.0",
  "type": "negotiate",
  "from": "did:web:alice.agents.agentcloud.com:personal",
  "to": "did:web:agents.example.com:support",
  "body": {
    "linkRequest": true,
    "accountHint": "alice@email.com"
  }
}
```

The `accountHint` is OPTIONAL and advisory — an email, phone number, or account ID that helps the company pre-populate the verification page. The company MUST NOT use the hint as proof of account ownership.

#### Step 2 — Link Challenge

The company's agent responds with a challenge:

```json
{
  "arp": "1.0",
  "type": "negotiate",
  "body": {
    "linkChallenge": true,
    "verificationUri": "https://example.com/link-agent",
    "verificationUriComplete": "https://example.com/link-agent?code=WDJB-MJHT",
    "userCode": "WDJB-MJHT",
    "linkCode": "lnk_01HZ9T2K…",
    "expiresIn": 900,
    "interval": 5
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `verificationUri` | string | MUST | URL where the customer authenticates and approves |
| `verificationUriComplete` | string | MAY | Verification URL with `userCode` pre-filled (for QR codes) |
| `userCode` | string | MUST | Short, human-readable code (6-8 characters, consonants only, case-insensitive) |
| `linkCode` | string | MUST | Opaque correlation ID for polling |
| `expiresIn` | integer | MUST | Seconds until the challenge expires (RECOMMENDED: 900) |
| `interval` | integer | MUST | Minimum seconds between polls (RECOMMENDED: 5) |

**User code requirements:** Codes MUST use a restricted character set to avoid ambiguity: `BCDFGHJKLMNPQRSTVWXZ` (consonants, excluding easily confused characters). Codes MUST have at least 20 bits of entropy. The company MUST rate-limit user code entry attempts.

#### Step 3–6 — Customer Authorization

The customer (human) opens `verificationUri` in a browser, authenticates with the company using the company's existing authentication (password, passkey, SSO), enters the `userCode`, reviews the requested permissions, and approves the link. The company's existing authentication mechanism is used — ARP does not prescribe how the company authenticates its customers.

#### Step 7 — Polling

The customer's agent polls the company's agent with `negotiate` messages:

```json
{
  "arp": "1.0",
  "type": "negotiate",
  "body": {
    "linkPoll": true,
    "linkCode": "lnk_01HZ9T2K…"
  }
}
```

The company's agent responds with one of:

| Response | Meaning |
|----------|---------|
| `negotiate` with `"linkPending": true` | Customer hasn't completed authorization yet. Keep polling. |
| `negotiate` with `"linkSlowDown": true` | Polling too fast. Increase interval by 5 seconds. |
| `error` with `LINK_EXPIRED` | The `linkCode` expired. Restart from Step 1. |
| `error` with `LINK_DENIED` | Customer denied the link request. |
| `acknowledge` with `accountCredential` | Success. See Step 8. |

#### Step 8 — Credential Issuance

On success, the company's agent responds with an `acknowledge` containing the account credential:

```json
{
  "arp": "1.0",
  "type": "acknowledge",
  "body": {
    "linkComplete": true,
    "accountCredential": {
      "arp": "1.0",
      "type": "account-credential",
      "issuer": "did:web:agents.example.com:support",
      "subject": "did:web:alice.agents.agentcloud.com:personal",
      "issuedAt": "2026-04-13T10:05:00Z",
      "validUntil": "2027-04-13T10:05:00Z",
      "account": {
        "id": "CUST-29847163",
        "type": "consumer",
        "scopes": ["order.read", "order.cancel", "support.create"]
      },
      "proof": {
        "type": "Ed25519",
        "verificationMethod": "did:web:agents.example.com:support#key-1",
        "proofValue": "z4kS2yL8pQ…"
      }
    }
  }
}
```

Both agents MUST update their relation to include the account link. The customer's agent stores the full credential. The company's agent records the link against the customer account.

### 12.4 Presenting Credentials

When a customer's agent interacts with a linked company agent, it presents the credential in a signed wrapper with a fresh challenge:

1. The customer's agent includes `"accountCredential"` in the `body` of its `request` message.
2. The company's agent verifies:
   - Its own signature on the credential (issuer proof)
   - The requesting agent's DID matches the credential `subject`
   - The credential has not expired (`validUntil`)
   - The requested operation is within `account.scopes`
   - The account is still active in its own database

If verification fails, the company's agent MUST respond with `AUTH_DENIED` and a descriptive message. If the credential has expired, the agent SHOULD include `"linkExpired": true` in the error body to signal that re-linking is needed.

### 12.5 Credential Lifecycle

#### Expiration and Refresh

Credentials have a `validUntil` field. The company controls credential lifetime. RECOMMENDED: 90 days minimum, 1 year maximum.

Before expiry, the customer's agent MAY request a credential refresh by sending a `negotiate` message with `"linkRefresh": true` and the existing `linkCode` or credential. The company's agent MAY issue a fresh credential without requiring a new human authorization ceremony, provided the account is still active and in good standing.

#### Revocation

Either party MAY revoke an account link:

- **Customer revokes** (via their agent): Send `negotiate` with `"linkRevoke": true`. The company's agent MUST acknowledge and invalidate the credential.
- **Customer revokes** (via company portal): The company invalidates the credential server-side. The customer's agent discovers the revocation on next use (receives `AUTH_DENIED` with `"linkRevoked": true`).
- **Company revokes** (account closed, security concern): The company invalidates the credential server-side. Optionally sends a `negotiate` with `"linkRevoked": true` to notify the agent proactively.

Revocation does not terminate the relation (Section 11.3). The relation remains `active` — the agents can still exchange messages, but account-scoped operations require re-linking.

#### Scope Changes

The company MAY update the scopes of an existing link by issuing a new credential with updated `account.scopes`. The customer's agent SHOULD replace its stored credential with the updated version. Scope reduction does not require customer re-authorization. Scope expansion SHOULD trigger a new authorization ceremony.

### 12.6 Linking Methods

The device-authorization flow (Section 12.3) is the PRIMARY method. Companies MAY additionally support:

#### OAuth Delegation (Alternative)

Companies with existing OAuth 2.0 infrastructure MAY declare OAuth support in their Agent Card:

```json
{
  "accountLinking": {
    "methods": ["device-authorization", "oauth2"],
    "oauth2": {
      "authorizationEndpoint": "https://example.com/oauth/authorize",
      "tokenEndpoint": "https://example.com/oauth/token",
      "scopes": ["agent:read", "agent:write", "agent:support"]
    }
  }
}
```

When using OAuth, the customer's agent acts as the OAuth client. The resulting access token is exchanged for an ARP `account-credential` via a `negotiate` message with `"oauthToken"` in the body. The company's agent validates the OAuth token, maps it to a customer account, and issues an ARP credential. The OAuth token is consumed; the ARP credential is the ongoing proof.

### 12.7 Agent Card Declaration

Companies that support account linking MUST declare it in their Agent Card (Section 7):

```json
{
  "accountLinking": {
    "supported": true,
    "methods": ["device-authorization"],
    "verificationUri": "https://example.com/link-agent",
    "scopeDefinitions": {
      "order.read": "View order history and status",
      "order.cancel": "Cancel pending orders",
      "support.create": "Open support tickets"
    },
    "credentialLifetime": 7776000,
    "refreshSupported": true
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `supported` | boolean | MUST | Whether account linking is available |
| `methods` | array | MUST | Supported linking methods |
| `verificationUri` | string | SHOULD | Base URL for customer verification |
| `scopeDefinitions` | object | SHOULD | Human-readable descriptions of available scopes |
| `credentialLifetime` | integer | SHOULD | Default credential lifetime in seconds |
| `refreshSupported` | boolean | SHOULD | Whether credential refresh without re-authorization is supported |

### 12.8 Relation Export with Account Links

When exporting relations (Section 11.5), account link metadata MUST be included in the relation's `metadata` field:

```json
{
  "peer": "did:web:agents.example.com:support",
  "peerAddress": "support@agents.example.com",
  "status": "active",
  "metadata": {
    "accountLink": {
      "accountId": "CUST-29847163",
      "scopes": ["order.read", "order.cancel", "support.create"],
      "validUntil": "2027-04-13T10:05:00Z",
      "linkedAt": "2026-04-13T10:05:00Z"
    }
  }
}
```

The exported data includes the link metadata but MUST NOT include the full credential (which contains the issuer's signature and could be replayed). On import to a new agent, account links MUST be re-established through a new linking ceremony — credentials are bound to a specific agent DID and are not transferable.

### 12.9 Error Codes

Account linking adds the following error codes to Section 16:

| Code | Meaning |
|------|---------|
| `LINK_EXPIRED` | The link challenge or credential has expired |
| `LINK_DENIED` | The customer denied the link request |
| `LINK_REVOKED` | The account link has been revoked |
| `LINK_REQUIRED` | Operation requires an account link that does not exist |
| `SCOPE_DENIED` | Account link exists but the requested operation is outside the authorized scopes |

---

## 13. Reputation

### 13.1 Completion Records

After a task completes successfully, both agents SHOULD sign a completion record:

```json
{
  "type": "completion",
  "taskId": "task_01HZ3K9V7N…",
  "capability": "process-order",
  "agents": {
    "requester": "did:web:agents.united.com:purchasing",
    "provider": "did:web:agents.example.com:order-processor"
  },
  "initiatedAt": "2026-04-11T14:30:00Z",
  "completedAt": "2026-04-11T15:00:00Z",
  "requestHash": "sha256:7b226163…",
  "contentHash": "sha256:9f86d08…",
  "signatures": {
    "requester": "z3hR9xK7mN…",
    "provider": "z4kS2yL8pQ…"
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `taskId` | string | MUST | The `correlationId` of the completed task |
| `capability` | string | MUST | The capability that was fulfilled |
| `agents` | object | MUST | DIDs of both participants |
| `initiatedAt` | string | MUST | ISO 8601 timestamp of the original `request` message |
| `completedAt` | string | MUST | ISO 8601 timestamp of the final `response` message |
| `requestHash` | string | MUST | SHA-256 hex digest of the original `request` message's canonical bytes (the same bytes that were signed). Binds this record to a specific signed request |
| `contentHash` | string | MUST | SHA-256 hex digest of the final `response` message body |
| `signatures` | object | MUST | Both agents' signatures over the canonical record |

The `contentHash` proves the record corresponds to a real interaction without revealing the content. The `requestHash` cryptographically binds the completion to a specific signed request — a verifier can ask the provider for the original request message, verify its signature against the requester's DID, and confirm the hash matches. This prevents fabricating completion records without fabricating full signed message exchanges.

**Minimum duration:** Receivers evaluating completion records SHOULD discard records where `completedAt - initiatedAt` is less than 10 seconds. Legitimate tasks require processing time. Fabricated completions between colluding agents can be generated at high frequency but cannot fake elapsed time without spending it.

### 13.2 Exchange Flow

**Completion records (bilateral):**

1. After a successful `response`, the requester creates a completion record and signs it.
2. The requester sends the record to the provider (as a `request` message with capability `arp:sign-completion`).
3. The provider verifies the record, counter-signs, and returns the fully-signed record.
4. Both agents store the record.

**Outcome records (unilateral):**

1. When a task ends without a bilateral completion — the other party went silent, delivery failed, or the parties disagree — either agent creates an outcome record and signs it.
2. The filing agent sends the record to the other party (as a `request` message with capability `arp:outcome-notification`).
3. The other party MAY file a counter-record for the same `taskId` if they disagree.

Either agent can present completion records and outcome records to third parties as proof of track record. Completion records are verified against both parties' DID documents (or pinned keys). Outcome records are verified against the filing party's DID only.

### 13.3 Trust Signals

Completion records and outcome records enable trust assessment without a central authority:

- **Volume:** How many verified completions does this agent have?
- **Recency:** When was the last completion?
- **Diversity:** Has this agent worked with many different counterparties, or just one?
- **Failure rate:** What is the ratio of outcome records to completion records? A pattern of failures across diverse counterparties is a stronger signal than isolated incidents.
- **Dispute pattern:** Does this agent frequently file or receive dispute records? Frequent filers may be unreliable; frequent targets may have quality issues.

Agents SHOULD publish their reputation stats in the Agent Card:

```json
{
  "reputation": {
    "completions": 847,
    "outcomes": {
      "failed": 8,
      "disputed": 3,
      "abandoned": 1
    },
    "since": "2026-01-15T00:00:00Z",
    "verifyUrl": "https://agents.example.com/order-processor/reputation"
  }
}
```

The `verifyUrl` returns a paginated list of completion records and outcome records that third parties can independently verify. The `verifyUrl` response format will be fully specified in v0.5.0.

### 13.4 Outcome Records

> **EXPERIMENTAL.** Outcome records are new in v0.4.0. The filing, cross-verification, and discoverability mechanisms will be fully specified in v0.5.0.

Completion records capture success. Outcome records capture everything else — failures, disputes, and abandoned tasks. Either party MAY create an outcome record unilaterally when a task ends without a bilateral completion record.

```json
{
  "type": "outcome",
  "taskId": "task_01HZ3K9V7N…",
  "capability": "process-order",
  "agents": {
    "requester": "did:web:agents.united.com:purchasing",
    "provider": "did:web:agents.example.com:order-processor"
  },
  "role": "requester",
  "initiatedAt": "2026-04-11T14:30:00Z",
  "recordedAt": "2026-04-12T16:00:00Z",
  "outcome": "failed",
  "reason": "Delivery never arrived after 14 days",
  "requestHash": "sha256:7b226163…",
  "signature": "z3hR9xK7mN…"
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `taskId` | string | MUST | The `correlationId` of the task |
| `capability` | string | MUST | The capability that was invoked |
| `agents` | object | MUST | DIDs of both participants |
| `role` | string | MUST | The filing party's role: `requester` or `provider` |
| `initiatedAt` | string | MUST | ISO 8601 timestamp of the original `request` message |
| `recordedAt` | string | MUST | ISO 8601 timestamp of when this record was created |
| `outcome` | string | MUST | One of: `failed`, `disputed`, `abandoned` |
| `reason` | string | SHOULD | Free-text explanation of what happened |
| `requestHash` | string | MUST | SHA-256 hex digest of the original `request` message's canonical bytes |
| `signature` | string | MUST | Single signature from the filing party |

**Outcome types:**

- **`failed`** — the task did not complete successfully (delivery didn't arrive, service was incorrect, agent went silent).
- **`disputed`** — the parties disagree about whether the task was completed. One side considers it done; the other does not.
- **`abandoned`** — the task was started but never completed by either party (timeout, provider disappeared, requester cancelled without acknowledgement).

**Key differences from completion records:**

Outcome records have a **single signature** (the creator's), making them less authoritative than bilateral completion records. Agents evaluating reputation SHOULD weight bilateral completions higher than unilateral outcomes.

The `requestHash` is required and serves the same anti-fabrication purpose as in completion records (Section 13.1) — a verifier can request the original signed message, verify it against the requester's DID, and confirm the hash matches. You cannot file outcome records about agents you have never interacted with.

**Counter-records:** If one party files an outcome record, the other party MAY file their own outcome record for the same `taskId` to present their side. Both records are visible to verifiers:

```
Agent A files:  outcome { taskId: "task_123", outcome: "failed",   reason: "Never delivered" }
Agent B files:  outcome { taskId: "task_123", outcome: "disputed", reason: "Delivered 2026-04-10, signed by recipient" }
```

The protocol does not resolve disputes — it provides verifiable evidence for reputation systems to evaluate.

**Constraints:**

- An outcome record MUST NOT be filed for a `taskId` that already has a bilateral completion record. If both parties signed a completion, the task is settled.
- Outcome records SHOULD be filed within 30 days of `initiatedAt`. Agents evaluating records MAY discard records with a gap larger than 90 days as stale.
- The filing party notifies the other party by sending the outcome record as a `request` message with capability `arp:outcome-notification`. The other party MAY counter-file but is not obligated to respond.

### 13.5 No Central Authority

ARP does not define a reputation aggregator or scoring service. Completion records and outcome records are portable, verifiable, and decentralized. Third-party reputation services MAY crawl and aggregate them. The protocol provides verifiable data. The scoring ecosystem builds on top.

---

## 14. Multi-Tenancy

### 14.1 Platforms

A platform is a service that hosts agents on behalf of multiple users (tenants). A user signs up, gets a handle, and their agents run under the platform's domain.

Example: Alice signs up on AgentCloud and gets:

```
my-agent@alice.agents.agentcloud.com
```

DID:

```
did:web:alice.agents.agentcloud.com:my-agent
```

### 14.2 Addressing

Platforms MUST use subdomains for tenant isolation:

```
{agent}@{tenant}.agents.{platform}
```

This provides:
- **DNS isolation.** Each tenant gets their own subdomain (or inherits the platform's via wildcard DNS).
- **DID isolation.** Each tenant's DID documents are served under their subdomain.
- **Independent Agent Cards.** Each tenant has their own `/.well-known/arp/index.json`.

### 14.3 Platform Responsibilities

Platforms MUST:
- Serve DID documents dynamically for tenant agents at the correct `did:web` resolution path
- Publish Agent Cards per tenant
- Route messages to the correct tenant's agent
- Allow tenants to manage their own allowlists and capabilities

Platforms SHOULD:
- Operate relays for their tenants
- Provide tenant-scoped rate limiting
- Support custom domains: if a tenant controls `agents.mycompany.com`, the platform serves content for that domain via DNS CNAME

### 14.4 Platform Agent

A platform MAY publish its own agent at `did:web:agents.agentcloud.com:platform` to serve as a directory for the platform's tenants and handle platform-level operations.

---

## 15. Negotiation

Before starting work, agents MAY exchange `negotiate` messages to agree on terms:

```json
{
  "type": "negotiate",
  "body": {
    "capability": "process-order",
    "terms": {
      "maxResponseTime": "30s",
      "maxItems": 500,
      "schemaVersion": "https://agents.example.com/schemas/order-request.json"
    }
  }
}
```

The other agent responds with `negotiate` (counter-proposal) or `acknowledge` (accepted).

Negotiation is REQUIRED for first contact between strangers (Section 10.4). For established relationships where both agents support the same schema and the request falls within declared limits, negotiation MAY be skipped.

---

## 16. Error Handling

```json
{
  "type": "error",
  "correlationId": "task_01HZ3K9V7N…",
  "body": {
    "code": "CAPABILITY_UNAVAILABLE",
    "message": "The process-order capability is temporarily offline for maintenance.",
    "retryable": true,
    "retryAfter": "2026-04-11T15:00:00Z"
  }
}
```

### Standard Error Codes

| Code | Meaning |
|------|---------|
| `AUTH_FAILED` | Signature verification failed |
| `AUTH_DENIED` | Authenticated but not authorized |
| `FIRST_CONTACT_REQUIRED` | Sender must complete the first-contact handshake |
| `CAPABILITY_DENIED` | Authenticated but approval expired or capability not in approved scope |
| `CAPABILITY_UNAVAILABLE` | Requested capability not currently available |
| `CAPABILITY_UNKNOWN` | No such capability |
| `SCHEMA_INVALID` | Message body doesn't match capability schema |
| `RATE_LIMITED` | Too many requests |
| `TASK_CANCELLED` | The correlated task was cancelled |
| `MESSAGE_EXPIRED` | `expiresAt` has passed or `createdAt` is too old |
| `MESSAGE_TOO_LARGE` | Body exceeds 1 MB limit |
| `DELIVERY_EXPIRED` | Relay could not deliver within retention window |
| `KEY_MISMATCH` | Sender's key doesn't match pinned key |
| `INTERNAL_ERROR` | Agent-side error (not the sender's fault) |

---

## 17. Extensibility

### 17.1 Custom Capabilities

Any domain operator can define new capabilities by publishing schemas at URLs they control. No coordination with anyone else. No central schema registry.

### 17.2 Protocol Extensions

The `negotiate` message supports protocol-level extensions:

```json
{
  "type": "negotiate",
  "body": {
    "extensions": {
      "billing": "https://specs.example.com/arp-billing/1.0",
      "audit": "https://specs.example.com/arp-audit/1.0"
    }
  }
}
```

Extensions are opt-in. An agent that doesn't understand an extension ignores it. Core protocol behavior is never gated on extensions.

### 17.3 What ARP Does NOT Define

- **Global agent search.** Build it as a service on top of crawlable Agent Cards.
- **Agent lifecycle management.** How you deploy, scale, and monitor agents is your problem.
- **Delegation chains.** Tracking multi-hop delegation is application-layer logic, not protocol.
- **Content format within `body`.** As long as it validates against the capability schema, the body is opaque to the protocol.

---

## 18. Putting It Together

A complete first interaction between two agents that have never met:

```
1. Agent A wants "order processing" and knows the domain example.com

2. DISCOVER
   DNS: _arp._tcp.agents.example.com → SRV → arp.example.com:443
   HTTP: GET https://arp.example.com/.well-known/arp/order-processor.json
   → Agent Card (capabilities, DID, public key, inbox URL, schemas)

3. VERIFY IDENTITY
   HTTP: GET https://agents.example.com/order-processor/did.json
   → DID document (public key, inbox endpoint)
   → Pin the public key (first contact — TOFU)

4. FIRST-CONTACT HANDSHAKE
   POST to inbox: signed negotiate message with firstContact: true
   ← acknowledge with approved capabilities and expiration
   → Both agents create a Relation (status: active) with the peer's pinned key

5. SEND REQUEST
   POST to inbox: signed request with capability: "process-order"
   Prefer: respond-async
   ← 202 Accepted with statusUrl and callbackSupported: true

6. RECEIVE RESULT (via callback)
   POST to Agent A's inbox: signed response with matching correlationId
   Agent A verifies signature against pinned key

7. COMPLETION RECORD
   Agent A signs a completion record → sends to Agent B
   Agent B counter-signs → returns fully-signed record
   Both agents store the record for future reputation checks
```

Seven steps. Two DNS queries, four HTTP exchanges, one callback, one reputation record. Both sides verified. No central authority involved. Both agents now have a relation — a persistent record of the other party's identity, trust level, and interaction history.

If Agent B had been offline at step 5, the sender would have fallen back to the relay (SRV priority 20), and Agent B would have collected the message when it came back online.

---

## 19. Security Considerations

| Threat | Mitigation |
|--------|------------|
| Message tampering | Every message is signed; receivers verify |
| Identity spoofing | DID resolution + signature verification + key pinning |
| Domain takeover | Key pinning detects key changes; rotation requires proof from old key |
| Replay attacks | Unique message IDs + idempotency + message expiration |
| Spam / flooding | Deny by default + first-contact handshake + reputation + rate limiting |
| Man-in-the-middle | Mandatory TLS on all endpoints |
| Content snooping | Optional end-to-end encryption (Section 8.7) |
| Key compromise | Key rotation with signed proof + key pinning alerts |
| SSRF via callbacks | Private IP denylist + HTTPS requirement + ARP endpoint verification |
| DNS hijacking | DNSSEC recommended; key pinning provides defense in depth |
| Message loss | Store-and-forward relays with 72-hour minimum retention |
| Storage exhaustion | Bounded idempotency window (24h–7d) + 1 MB message size limit |
| Relay abuse | Relay authorization via DID document service listing |
| Relation export leakage | Export MUST NOT include private keys. Export SHOULD be signed for authenticity. Import triggers key rotation notification to all peers |
| Key recovery window exploitation | 72h grace period is time-bound and requires domain proof. Receivers SHOULD increase scrutiny of messages signed with keys that have a pending recovery record |
| Peers field manipulation | Peers are advisory, not authoritative. Agents SHOULD only list peers backed by verifiable completion records. Consumers of peer data MUST NOT treat peer listings as trust endorsements |
| Relation termination abuse | Termination is unilateral and cannot be rejected. Agents SHOULD rate-limit termination/re-establishment cycles to prevent harassment via repeated negotiate→terminate loops |
| Open capability abuse | Aggressive rate limiting on open requests (RECOMMENDED 5/min per unknown sender DID). No relation created = no trust accumulation from open exchanges. Denylist still enforced. DID resolution required for every open request (no pinned key fallback) |
| Outcome record abuse (revenge filing) | `requestHash` MUST match a real signed request — cannot fabricate records against strangers. Unilateral records are less authoritative than bilateral completions. Counter-records allow the other party to present their side. Agents evaluating reputation SHOULD look for patterns across diverse counterparties, not isolated incidents |
| Directory scraping / agent enumeration | `crawl-delay` in `agents.txt` sets crawler rate limits. Domain operators MAY omit private agents from the directory manifest. Rate limiting on `/.well-known/arp/` paths SHOULD match declared `crawl-delay` |
| Account link phishing (user code interception) | User codes have restricted character set + minimum 20-bit entropy + rate-limited entry. `verificationUri` served over HTTPS only. Companies SHOULD display which agent/platform is requesting the link so customers can verify intent (Section 12.3) |
| Credential replay | Account credentials are bound to a specific agent DID (`subject` field). Presenting agent MUST prove possession of the matching private key. Credentials include `validUntil` expiry. Companies verify against their own account database on each use (Section 12.4) |
| Credential theft | Credentials are cryptographically bound to the agent's key — a stolen credential cannot be used without the corresponding private key. Short credential lifetimes + refresh mechanism limit exposure window (Section 12.5) |
| Scope escalation via account link | `account.scopes` are company-defined and enforced server-side. Scope expansion requires a new human authorization ceremony. Agents MUST reject operations outside granted scopes with `SCOPE_DENIED` (Section 12.9) |
| Account link persistence after account closure | Companies revoke credentials server-side when accounts close. Customer's agent discovers revocation on next use (`LINK_REVOKED`). Proactive revocation notification is RECOMMENDED (Section 12.5) |

---

## 20. Implementation Requirements

### 20.1 To Run an ARP Agent, You Need:

1. A domain name you control (or a tenant account on a platform)
2. An HTTPS server
3. An Ed25519 key pair
4. A DID document at the well-known path
5. An inbox endpoint that accepts POST requests
6. An Agent Card describing your capabilities

That's it. No special infrastructure. No blockchain. No message brokers. Relays are optional but recommended for production.

**A practical note:** While the protocol is simple, a compliant agent requires persistent storage for relations (which include key pins), message ID tracking, and optionally completion records. An in-memory implementation works for testing but will lose state on restart. A SQLite database or equivalent key-value store is the practical minimum for production.

### 20.2 Content Type

ARP messages use `application/arp+json`. Agents MUST set this content type on all ARP messages. Agents SHOULD reject requests without it.

### 20.3 Minimum Viable Implementation

A conformant ARP domain operator MUST:
- Serve `agents.txt` at the domain root (Section 5.3)
- Serve an Agent Directory Manifest at `/.well-known/arp/index.json` (Section 5.4)

A conformant ARP agent MUST:
- Publish a DID document
- Publish an Agent Card with at least one capability and a `publicKey` field
- Accept POST requests at its inbox URL
- Verify signatures on incoming messages (via DID resolution or pinned keys)
- Sign all outgoing messages
- Return structured errors for invalid requests
- Enforce idempotency on message IDs (24-hour minimum retention)
- Enforce message expiration (`expiresAt` or 24-hour `createdAt` window)
- Enforce message size limits (1 MB max body)
- Validate callback URLs against private IP ranges
- Maintain relations for agents it interacts with (Section 11), including the peer's pinned key
- Enforce first-contact handshake for unknown senders (unless `openAccess: true` or the request targets an `open` capability)
- Reject messages from terminated relations with `AUTH_DENIED`

A conformant ARP agent SHOULD:
- Include JSON-LD `@context` and `@type` in Agent Cards (Section 7.1)
- Publish a DNS SRV record
- Configure a relay for store-and-forward
- Support async responses for long-running tasks
- Implement rate limiting
- Cache resolved DID documents (minimum TTL: 300 seconds)
- Create and store completion records
- Support relation export in the standard portability format (Section 11.5)
- Compute trust annotations from relation state (Section 10.7)
- Support content encryption via `keyAgreement` keys

A conformant ARP agent that supports account linking (Section 12) MUST:
- Declare `accountLinking` in the Agent Card (Section 12.7)
- Implement the device-authorization linking flow (Section 12.3)
- Issue `account-credential` objects signed with the agent's Ed25519 key
- Verify credential signatures, expiry, and scope on every account-scoped request
- Support credential revocation (company-initiated and customer-initiated)
- Enforce `account.scopes` — reject out-of-scope operations with `SCOPE_DENIED`
- Rate-limit user code entry attempts during the linking ceremony

A conformant ARP agent that supports account linking SHOULD:
- Support credential refresh without re-authorization (Section 12.5)
- Send proactive `linkRevoked` notifications when revoking credentials
- Publish `scopeDefinitions` in the Agent Card for transparency
- Include account link metadata in relation exports (Section 12.8)

---

## Appendix A: Media Types

| Type | Usage |
|------|-------|
| `application/arp+json` | ARP messages |
| `application/json` | Agent Cards, DID documents, schemas |
| `text/event-stream` | SSE streaming responses |

## Appendix B: DNS Records

```
; Primary agent endpoint
_arp._tcp.agents.example.com. 300 IN SRV 10 100 443 arp.example.com.

; Relay fallback (store-and-forward)
_arp._tcp.agents.example.com. 300 IN SRV 20 100 443 relay.arprelay.net.

; Protocol version advertisement
_arp.agents.example.com. 3600 IN TXT "v=arp1"
```

## Appendix C: Well-Known URLs

| Path | Content |
|------|---------|
| `/agents.txt` | ARP discovery entry point (Section 5.3) |
| `/.well-known/arp/index.json` | Agent Directory Manifest (Section 5.4) |
| `/.well-known/arp/{name}.json` | Individual Agent Card (Section 7) |
| `/.well-known/arp/recovery/{name}.json` | Key recovery record (Section 4.4) |
| `/{name}/did.json` | DID document (per did:web spec) |

## Appendix D: JCS Test Vectors

All ARP implementations MUST produce identical canonical output for these three inputs. The expected output is the canonical form per RFC 8785.

**Vector 1 — Basic message envelope (key ordering):**

Input (keys deliberately unordered):
```json
{"type":"request","arp":"1.0","to":"did:web:b.com:agent","id":"msg_001","from":"did:web:a.com:agent","createdAt":"2026-04-12T00:00:00Z","body":{"text":"hello"}}
```

Expected canonical output:
```
{"arp":"1.0","body":{"text":"hello"},"createdAt":"2026-04-12T00:00:00Z","from":"did:web:a.com:agent","id":"msg_001","to":"did:web:b.com:agent","type":"request"}
```

**Vector 2 — Numeric values and nested objects:**

Input:
```json
{"count":1,"rate":0.5,"nested":{"z":true,"a":false},"list":[3,1,2]}
```

Expected canonical output:
```
{"count":1,"list":[3,1,2],"nested":{"a":false,"z":true},"rate":0.5}
```

**Vector 3 — Unicode and special characters:**

Input:
```json
{"emoji":"☕","path":"/données/café","null_val":null,"empty":""}
```

Expected canonical output:
```
{"emoji":"☕","empty":"","null_val":null,"path":"/données/café"}
```

Note: the Unicode characters MUST appear as literal UTF-8, not as `\uXXXX` escapes. Array element order is preserved (JCS only sorts object keys). Implementations that produce different output for any of these vectors have a JCS bug that will cause signature verification failures.

**Vector 4 — Key encoding round-trip:**

Given a raw 32-byte Ed25519 public key (hex):
```
d75a980182b10ab7d54bfed3c964073a0ee172f3daa3f4a18446b0b8d183f8e3
```

Multicodec-prefixed bytes (34 bytes, hex):
```
ed01 d75a980182b10ab7d54bfed3c964073a0ee172f3daa3f4a18446b0b8d183f8e3
```

Expected multibase string:
```
z6MkiTBz1ymuepAQ4HEHYSF1H8quG5GLVVQR3djdX3mDooWp
```

Decoding steps:
1. Strip `z` prefix → base58btc string
2. Base58btc-decode → 34 bytes
3. Verify bytes[0..2] == `0xed 0x01` → Ed25519 key
4. Raw key = bytes[2..34] → 32 bytes matching the original hex above

If the decoded bytes are 32 (no prefix) instead of 34, the implementation is not including the multicodec prefix — this will cause interoperability failures with implementations that follow the W3C convention.

## Appendix E: Implementer's Quick Reference

This section is a self-contained guide for sending your first ARP message to a remote agent. It covers the exact bytes, encodings, and HTTP calls in order.

### Step 1: Generate an Ed25519 key pair

Generate an Ed25519 key pair. Store the private key securely. Encode the 32-byte raw public key with the multicodec prefix as multibase:

```
your_public_key = "z" + base58btc( 0xed01 + raw_32_byte_public_key )
```

### Step 2: Discover the target agent

Fetch the Agent Card:

```
GET https://<domain>/.well-known/arp/<agent-name>.json
```

From the response, extract:
- `inbox` — the URL to POST messages to
- `publicKey` — the agent's multibase public key (for verifying responses)
- `did` — the agent's DID (for the `to` field)
- `capabilities` — what the agent can do

### Step 3: First-contact handshake

Build a negotiate message. The `body` MUST include `firstContact: true` and your public key:

```json
{
  "arp": "1.0",
  "id": "msg_<uuid>",
  "type": "negotiate",
  "from": "did:web:yourdomain.com:your-agent",
  "to": "<agent-did-from-card>",
  "createdAt": "2026-04-12T10:00:00Z",
  "body": {
    "firstContact": true,
    "publicKey": "z6Mk...<your-multibase-public-key>",
    "intent": "I want to use your echo capability."
  }
}
```

Sign it (see Step 5 below), then POST:

```
POST <inbox-url>
Content-Type: application/arp+json

<signed-message-json>
```

A `200` response with `type: "acknowledge"` means the handshake succeeded and the agent pinned your key.

### Step 4: Send a request

Now send the actual request. The `capability` field MUST match one of the agent's declared capabilities:

```json
{
  "arp": "1.0",
  "id": "msg_<uuid>",
  "type": "request",
  "from": "did:web:yourdomain.com:your-agent",
  "to": "<agent-did>",
  "capability": "echo",
  "correlationId": "task_<uuid>",
  "createdAt": "2026-04-12T10:00:01Z",
  "body": {
    "message": "Hello from my agent!"
  }
}
```

Sign and POST to the same inbox URL.

### Step 5: How to sign (byte-level)

Given a message object without the `signature` field:

```
1. JCS-canonicalize the object
     → recursively sort all object keys
     → no whitespace between tokens
     → numbers: no trailing zeros, no leading +
     → strings: minimal escaping, UTF-8 literals (not \uXXXX)
     → result is a UTF-8 string

2. Ed25519-sign the UTF-8 bytes
     → input:  canonical_string as byte[]
     → key:    your 32-byte Ed25519 private key
     → output: 64-byte signature

3. Encode as multibase
     → "z" + base58btc( 64_signature_bytes )

4. Add to message
     → message.signature = "z3hR9xK7mN…"
```

### Step 6: Verify the response

The agent's response is also signed. To verify:

```
1. Save the "signature" field, then remove it from the response object
2. JCS-canonicalize the remaining object (same algorithm as signing)
3. Decode the signature: strip "z", base58btc-decode → 64 bytes
4. Decode the agent's public key (from Agent Card): strip "z", base58btc-decode → 32 bytes
5. Ed25519-verify( canonical_bytes, signature_bytes, public_key_bytes )
```

### Common Mistakes

| Mistake | Symptom | Fix |
|---------|---------|-----|
| JSON keys not sorted recursively | `AUTH_FAILED` | Use a proper JCS library, not `JSON.stringify` with `sort_keys` |
| Missing `z` prefix on public key | `AUTH_FAILED` or key parse error | All multibase values start with `z` |
| `Content-Type: application/json` | `415` or rejected | Use `application/arp+json` |
| Missing `firstContact: true` | `FIRST_CONTACT_REQUIRED` (403) | Include in negotiate body for unknown agents |
| `signature` field included during canonicalization | `AUTH_FAILED` | Remove `signature` before JCS, add it back after |
| Stale `createdAt` timestamp | `MESSAGE_EXPIRED` | Use current time, not a cached value |

---

## 21. Notifications

> **EXPERIMENTAL.** Notifications are new in v0.7.0.

Fire-and-forget event delivery. Agents subscribe to events from a peer, receive signed notifications without polling, and revoke at any time.

Push-based delivery built on the existing relay, signing, and relations infrastructure. No new transport. No broker. No WebSocket.

### 21.1 The `notify` Message Type

A notification is a one-way signed message:

```json
{
  "arp": "1.0",
  "id": "msg_01HZ4M2P8N…",
  "type": "notify",
  "from": "did:web:agents.example.com:order-processor",
  "to": "did:web:agents.united.com:purchasing",
  "event": "order.shipped",
  "notificationId": "notif_01HZ4M2P8N…",
  "correlationId": "task_01HZ3K9V7N…",
  "createdAt": "2026-05-25T09:15:00Z",
  "body": {
    "orderId": "ord_29847163",
    "carrier": "DHL",
    "tracking": "JD0123456789"
  },
  "signature": "z3hR9xK7mN…"
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `type` | string | MUST | Always `"notify"` |
| `event` | string | MUST | Dotted event name (e.g., `order.shipped`) |
| `notificationId` | string | MUST | Unique per notification; receivers deduplicate on this value |
| `correlationId` | string | SHOULD | Links the notification to a prior task |
| `body` | object | MUST | Event-specific payload |

Distinct from `request`: no response is expected, the receiver MAY drop or batch notifications, and `notify` cannot be the subject of a `delegate`. A receiver that doesn't recognize the `event` SHOULD drop the notification without error.

### 21.2 Delivery Semantics

**At-least-once.** Exactly-once delivery across federated agents is impossible (Two Generals Problem). Senders MAY retry a notification if delivery fails. Receivers MUST deduplicate by `notificationId`. A receiver SHOULD remember `notificationId` values for at least 7 days.

**Fire-and-forget.** A `notify` message is delivered with the same machinery as a `request` (Section 9): direct POST to the recipient's inbox, fallback to relay (Section 6) when the inbox is unreachable. Successful delivery is signalled by HTTP `202 Accepted` with no body. Failure to deliver after the relay's retention window expires is not surfaced to the sender — the message is simply lost (at-least-once, not at-most-once).

**No callbacks, no response.** A receiver MUST NOT send a `response` to a `notify`. If acknowledgement matters, model the interaction as a `request` instead.

### 21.3 Permission

Notification permission is a property of the **relation** (Section 11), not a separate subscription object. A relation declares which event types it accepts via `accept_notifications`:

```json
{
  "peer": "did:web:agents.example.com:order-processor",
  "status": "active",
  "accept_notifications": {
    "events": ["order.*", "delivery.*", "payment.received"],
    "validUntil": "2026-06-01T14:30:00Z"
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `events` | array | MUST | Event-type filter list. Supports trailing-wildcard glob (`order.*`) |
| `validUntil` | string | MUST | ISO 8601 lease expiry |

A relation without `accept_notifications` MUST reject all notifications from that peer with `NOTIFICATION_REJECTED`. Permissions are independent of relation status — notification permission MAY be revoked without terminating the relation.

### 21.4 Permission Lifecycle

**Granting.** A receiver grants permission by sending a `request` with capability `arp:notifications.subscribe`:

```json
{
  "type": "request",
  "capability": "arp:notifications.subscribe",
  "body": {
    "events": ["order.*", "payment.received"],
    "lease": 604800
  }
}
```

`lease` is the requested lease duration in seconds. The peer responds with a `response` containing the granted events and `validUntil`. The granted set MAY be narrower than requested.

**Default lease.** Permissions expire after 7 days unless explicitly extended. Receivers MUST drop expired permissions without notification.

**Renewal.** The receiver renews by sending the same subscribe request before `validUntil`. The peer SHOULD honour renewal automatically for active relations.

**Revocation.** The receiver revokes by sending a `request` with capability `arp:notifications.unsubscribe`. The peer MUST stop sending notifications for the revoked events. In-flight notifications already in the relay queue MAY still be delivered — receivers MUST tolerate brief over-delivery after revocation.

### 21.5 Event Naming

ARP standardizes the envelope, not the events. Event names follow a dotted hierarchical convention: `domain.action` (e.g., `order.shipped`, `payment.received`).

**Protocol-level events.** ARP reserves the following event names for its own use:

| Event | Meaning |
|-------|---------|
| `relation.terminated` | The peer has terminated the relation (Section 11.3) |
| `relation.dormant` | The peer has marked the relation dormant (Section 11.4) |
| `subscription.expiring` | This notification subscription expires within 24 hours |
| `key.rotated` | The peer has rotated its DID document keys |

**Application-level events.** All other event names are application-defined. Vertical communities (commerce, support, scheduling) SHOULD coordinate on naming. ARP does not maintain a central event registry.

### 21.6 Agent Card Declaration

Agents that emit notifications MUST declare it in their Agent Card (Section 7):

```json
{
  "notifications": {
    "supported": true,
    "events": {
      "order.shipped":    "Fires when an order ships",
      "order.delivered":  "Fires when an order is marked delivered",
      "payment.received": "Fires when a payment settles"
    },
    "defaultLease": 604800,
    "maxLease": 7776000
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `supported` | boolean | MUST | Whether this agent emits notifications |
| `events` | object | SHOULD | Map of event name → human-readable description |
| `defaultLease` | integer | SHOULD | Default lease duration in seconds (`604800` = 7 days) |
| `maxLease` | integer | SHOULD | Maximum lease duration in seconds |

### 21.7 Error Codes

Notifications add the following error code to Section 16:

| Code | Meaning |
|------|---------|
| `NOTIFICATION_REJECTED` | The receiver has no `accept_notifications` permission for this event, the lease has expired, or the receiver is rate-limiting notifications |

### 21.8 Explicitly Out of Scope

- Fan-out optimization and relay-side delegation for high-volume publishers.
- Standardized event-type registries beyond the protocol-level events listed in Section 21.5.
- Notification batching or aggregation.
- Delivery receipts.
- SSE-based real-time streaming.

---

## 22. Settlements

> **EXPERIMENTAL.** Settlements are new in v0.7.0.

ARP brackets payment with two signed artifacts — a quote and a receipt — and nothing else. The money moves on the rail (x402, Lightning, cards, SEPA), directly between buyer and seller. ARP never carries rail bearer secrets or account credentials.

This section adds: one Agent Card field, one body shape, one Completion Record sub-object, two conventional capability names, three error codes. Zero new message types.

### 22.1 Design Stance

Two principles govern this section:

1. **ARP standardizes the signed claim, not the rail.** A `SettlementQuote` (Section 22.4) and a settlement-bearing Completion Record (Section 22.5) are the only protocol-level artifacts. Rail-specific behaviour — how money moves, how an on-rail payment carries the `quoteId` back for correlation — lives in community-maintained rail specifications linked from the Agent Card.

2. **ARP does not transport bearer secrets.** Settlement messages carry amount, currency, memo, and a rail reference. They never carry card numbers, client secrets, private keys, or anything else that would compromise a payment if read by an intermediary. Content encryption (Section 8.7) is therefore SHOULD, not MUST, at the ARP layer for settlement-bearing messages.

### 22.2 Settlement Primitives

Two settlement primitives are defined:

| Primitive | Order |
|-----------|-------|
| `prepay` | Buyer settles, then provider delivers. Two Completion Records share a `correlationId`: the settlement CR is signed first, the work CR references it |
| `postpay` | Provider delivers, then buyer settles. Two Completion Records share a `correlationId`: the work CR is signed first, the settlement CR references it |

Atomicity is not enforced — it is made provable. A missing second record is a verifiable unresolved obligation; either party MAY file an Outcome Record (Section 13.4). The protocol provides evidence; reputation and legal layers do enforcement.

Subscriptions and metered billing are not new primitives. They are sequences of `postpay` settlements sharing a correlation key.

### 22.3 Agent Card Declaration

Agents that accept or emit settlements MUST declare it in their Agent Card (Section 7):

```json
{
  "settlements": {
    "supported": true,
    "rails": [
      {
        "name": "x402-base-usdc",
        "spec": "https://x402.org/spec/1.0",
        "currencies": ["USDC"]
      },
      {
        "name": "l402-lightning",
        "spec": "https://docs.lightning.engineering/l402/1.0",
        "currencies": ["BTC"]
      },
      {
        "name": "stripe-pi",
        "spec": "https://specs.stripe.com/arp/payments/1.0",
        "currencies": ["GBP", "EUR", "USD"]
      }
    ],
    "primitives": ["prepay", "postpay"],
    "settlementWindow": "PT24H",
    "quoteCapability": "arp:settlement.quote"
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `supported` | boolean | MUST | Whether this agent supports settlements |
| `rails` | array | MUST | List of supported rails |
| `rails[].name` | string | MUST | Rail identifier, unique within this agent |
| `rails[].spec` | string | MUST | URL of the community-maintained rail specification |
| `rails[].currencies` | array | MUST | Currency codes accepted on this rail |
| `primitives` | array | MUST | Subset of `["prepay", "postpay"]` |
| `settlementWindow` | string | SHOULD | ISO 8601 duration for postpay settlement deadline |
| `quoteCapability` | string | SHOULD | Capability name for requesting a quote (default `arp:settlement.quote`) |

The `spec` URL is the rail handbook — schemas, semantics, error codes. ARP does not author it; the rail community does. ARP only requires that the URL exists and that each rail name is unique within an agent.

### 22.4 SettlementQuote

A `SettlementQuote` is a signed body shape carried inside either:

- a `response` to a quote request (capability `arp:settlement.quote`), or
- an `error` with code `SETTLEMENT_REQUIRED` (Section 22.10).

```json
{
  "amount":     "29.50",
  "currency":   "GBP",
  "primitive":  "prepay",
  "validUntil": "2026-05-25T16:00:00Z",
  "quoteId":    "qt_01HZ4N3R9P…",
  "rails": [
    {
      "name":   "x402-base-usdc",
      "target": "https://pay.example.com/x402/qt_01HZ4N3R9P"
    },
    {
      "name":   "stripe-pi",
      "target": "pi_3PqX…"
    }
  ],
  "memo":     "Order task_01HZ3K9V7N, 50 compute units",
  "quoteSig": "z3hR9xK7mN…"
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `amount` | string | MUST | Decimal amount as a string (avoid float rounding) |
| `currency` | string | MUST | ISO 4217 code or rail-specific currency (e.g., `USDC`, `BTC`) |
| `primitive` | string | MUST | `prepay` or `postpay` |
| `validUntil` | string | MUST | ISO 8601 quote expiry |
| `quoteId` | string | MUST | Unique quote identifier; used to correlate the on-rail payment back to this quote |
| `rails` | array | MUST | Per-rail payment targets the buyer can choose from |
| `rails[].name` | string | MUST | Rail name matching one declared in the seller's Agent Card |
| `rails[].target` | string | MUST | Rail-defined endpoint or reference (URL, invoice, payment-intent ID, etc.) |
| `memo` | string | SHOULD | Free-text description of what is being paid for |
| `quoteSig` | string | MUST | Seller's Ed25519 signature over the canonical SettlementQuote bytes (using the same JCS + Ed25519 algorithm as message signing, Section 8.6) |

`quoteSig` binds the quote to the specific `correlationId` and rail set. Replay protection comes from `validUntil` plus the seller's idempotency window. A SettlementQuote is non-transferable: rail specifications MUST reject settlement attempts where the on-rail payer identity does not match the quote's intended buyer.

### 22.5 Settlement Receipt

A Completion Record (Section 13.1) carrying a `settlement` sub-object **is** the receipt:

```json
{
  "type": "completion",
  "taskId": "task_01HZ3K9V7N…",
  "capability": "arp:settlement.paid",
  "agents": {
    "requester": "did:web:agents.united.com:purchasing",
    "provider":  "did:web:agents.example.com:order-processor"
  },
  "initiatedAt": "2026-05-25T15:30:00Z",
  "completedAt": "2026-05-25T15:30:31Z",
  "requestHash": "sha256:7b22…",
  "contentHash": "sha256:9f86…",
  "settlement": {
    "amount":    "29.50",
    "currency":  "GBP",
    "primitive": "prepay",
    "rail":      "x402-base-usdc",
    "quoteId":   "qt_01HZ4N3R9P…",
    "railRef":   "0x9f86d08…",
    "settledAt": "2026-05-25T15:30:30Z"
  },
  "signatures": {
    "requester": "z3hR9xK7mN…",
    "provider":  "z4kS2yL8pQ…"
  }
}
```

| `settlement` field | Type | Required | Description |
|--------------------|------|----------|-------------|
| `amount` | string | MUST | Decimal amount actually settled |
| `currency` | string | MUST | Currency actually settled |
| `primitive` | string | MUST | `prepay` or `postpay` |
| `rail` | string | MUST | Rail name (matches the seller's Agent Card) |
| `quoteId` | string | MUST | The quote that was settled |
| `railRef` | string | MUST | Rail-defined reference to the on-rail payment (tx hash, invoice ID, PaymentIntent ID, etc.) |
| `settledAt` | string | MUST | ISO 8601 timestamp of the on-rail settlement |

`railRef` is a verifiable handle, not a credential. Anyone can verify the on-rail settlement by querying the rail with the reference; ARP messages never carry the secrets needed to authorize a fresh payment.

A settlement-bearing Completion Record is verifiable forever by any third party against the rail. The buyer presents it to their accounting agent; the seller presents it to auditors; either can show a third party the rail reference without revealing rail-internal data.

### 22.6 Capabilities

Two conventional capability names:

| Capability | Used for |
|------------|----------|
| `arp:settlement.quote` | Buyer requests a quote. Request body is task-specific (currency preference, line items, etc.). Response body is a `SettlementQuote` |
| `arp:settlement.paid` | Buyer attests to a completed on-rail payment. Both parties sign the resulting Completion Record carrying the `settlement` sub-object |

Either capability MAY be omitted by a seller that delivers quotes only via `SETTLEMENT_REQUIRED` errors (the buyer attempts the underlying task, gets a quote attached to the error response, then settles).

### 22.7 Atomicity

`prepay` and `postpay` each produce two Completion Records sharing a `correlationId`, signed in a defined order:

- **prepay:** the settlement CR is signed first; the work CR references the settlement CR's `taskId` and `contentHash` in its body.
- **postpay:** the work CR is signed first; the settlement CR references the work CR's `taskId` and `contentHash` in its body.

If only one CR exists when both should, the relation has an unresolved obligation. Either party MAY file an Outcome Record (Section 13.4) with outcome `failed` and a reason such as `"unpaid"` or `"paid-but-undelivered"`. The protocol does not enforce atomicity — it makes the breach provable.

### 22.8 Spending Authority

Wallet-based payment — where the agent settles from a wallet it controls (Lightning node, smart wallet, EOA, custodial account) — requires nothing from ARP. The wallet's own primitives (session keys, macaroon caveats, ERC-4337 spend limits, custodial daily limits) enforce policy.

Charging a human's standing account at a company is Account Linking (Section 12) territory. The relevant spending-scope vocabulary is reserved for a future revision of Section 12 and is not normative in v0.7.0.

### 22.9 Encryption

Settlement messages carry metadata, not bearer secrets. Content encryption (Section 8.7) is therefore SHOULD, not MUST, at the ARP layer for `SettlementQuote` and `settlement`-bearing messages.

A rail specification MAY raise this to MUST for rails whose `target` field carries a bearer secret (e.g., a card client-secret embedded in the rail handle). When a rail spec sets this requirement, conforming ARP implementations MUST encrypt the corresponding message body.

### 22.10 Error Codes

Settlements add the following error codes to Section 16:

| Code | Meaning |
|------|---------|
| `SETTLEMENT_REQUIRED` | The requested operation requires settlement before it will proceed. The error response MUST be returned with HTTP `402` status; the error body MUST contain a `SettlementQuote` |
| `QUOTE_EXPIRED` | The quote's `validUntil` has passed |
| `QUOTE_INVALID` | The quote signature does not verify against the seller's DID, the buyer DID does not match, or the rail name is not declared in the seller's Agent Card |

### 22.11 Security Considerations

- **Replay.** A `quoteId` MUST be unique within the seller's idempotency window. Sellers MUST reject settlement attempts referencing a `quoteId` that has already been settled.
- **Quote substitution.** The settle attempt's `quoteId` is matched against the seller's signed quote. A buyer cannot present a quote intended for someone else; rail-layer settlement is bound to the buyer's identity by the rail specification.
- **Receipt forgery.** Settlement-bearing Completion Records inherit the anti-fabrication mechanism of Section 13.1 — `requestHash` ties the receipt to a specific signed request, and bilateral signatures bind both parties.
- **Currency confusion.** Implementations MUST refuse to interpret the `amount` field without a non-empty `currency`. Implementations MUST NOT silently convert currencies; FX is a rail-spec concern.
- **Prompt-injection-driven settlement.** Spending limits live with the wallet, not the agent. The agent's authority to spend MUST be bounded by wallet-side constraints, not by Agent Card declarations alone.

### 22.12 Explicitly Out of Scope

- **Escrow** — third-party-held settlement with dispute logic. Deferred to a later revision.
- **FX / currency conversion** — rail-spec concern.
- **Subscriptions and metered billing as protocol types** — expressed as sequences of `postpay` receipts sharing a correlation key, not new objects.
- **Multi-party revenue splits** — application-layer composition with multiple `postpay` receipts.
- **Spending-authority scope vocabulary for Account Linking** — belongs to Section 12; deferred.

---

*End of specification.*
