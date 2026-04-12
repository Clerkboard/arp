# ACP: Agent Communication Protocol

**RFC Draft — April 2026**

```
Status:     Draft
Version:    0.3.1
Authors:    Tiago Pita
```

---

## Abstract

The Agent Communication Protocol (ACP) is a federated messaging protocol for autonomous AI agents on the open internet. It enables agents — regardless of model, framework, or provider — to discover each other, negotiate capabilities, and exchange structured messages.

ACP combines DNS-based discovery, DID-based identity, HTTP transport, typed JSON messaging, store-and-forward relays, and verifiable reputation into a protocol simple enough to implement in a weekend and robust enough to operate at scale.

This document specifies the protocol. It is deliberately opinionated. Where prior work left choices open, this spec makes them.

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
| **Agent** | An autonomous software entity that can send and receive ACP messages |
| **Domain Operator** | The entity that controls a DNS domain and runs agents under it |
| **Platform** | A service that hosts agents on behalf of multiple tenants (Section 12) |
| **Agent Card** | JSON document describing an agent's identity, capabilities, and endpoint |
| **Inbox** | The HTTPS endpoint where an agent receives messages |
| **Relay** | A service that accepts and queues messages for agents that are temporarily offline (Section 6) |
| **Message** | A signed JSON object exchanged between agents |
| **Capability** | A declared ability of an agent, described semantically and structurally |
| **Completion Record** | A mutually signed record confirming a task was completed between two agents (Section 11) |

The key words MUST, MUST NOT, SHOULD, SHOULD NOT, and MAY are used as defined in RFC 2119.

---

## 3. Architecture

ACP has five layers. Each is independent and replaceable.

```
┌─────────────────────────────────┐
│  Capabilities                   │  What can you do?
│  (Agent Card + Runtime Negotiation)
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

### 4.1 ACP Address

Every agent has a human-readable address in the format:

```
{name}@{domain}
```

This is the canonical way to reference an ACP agent — on websites, in documentation, on business cards, or in conversation. It is deliberately modelled on email addresses for familiarity.

Examples:

| Agent | Address |
|-------|---------|
| Vodafone customer support | `support@agents.vodafone.com` |
| Google order processor | `order-processor@agents.google.com` |
| United Airlines purchasing | `purchasing@agents.united.com` |

**Resolution.** An ACP address resolves deterministically to an Agent Card:

```
support@agents.vodafone.com
  → https://agents.vodafone.com/.well-known/acp/support.json
```

The resolution rule:

1. Optionally, query DNS for `_acp._tcp.{domain}` SRV record to discover the host (allows `agents.vodafone.com` to delegate to a different server)
2. Fetch the Agent Card at `https://{domain}/.well-known/acp/{name}.json`
3. From the Agent Card, obtain the agent's DID, inbox URL, public key, and capabilities

If no SRV record exists, the domain itself serves the Agent Card over HTTPS. IP addresses are not valid in addresses — `did:web` requires a domain.

### 4.2 DID as Identity

Every agent MUST also have a Decentralized Identifier (DID) using the `did:web` method. The DID is the agent's cryptographic identity — used in message signing, key pinning, and verification.

An agent operated by `google.com` with local name `order-processor`:

```
did:web:agents.google.com:order-processor
```

This resolves to:

```
GET https://agents.google.com/order-processor/did.json
```

The ACP address and DID are two representations of the same agent. The address is for people; the DID is for the protocol.

### 4.3 Cryptographic Encoding and DID Document

### 4.3.1 Multibase Encoding

ACP uses **multibase** encoding for all public keys and signatures. Multibase is a self-describing format where the first character identifies the base encoding. ACP mandates **base58btc**, indicated by the `z` prefix.

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
  "id": "did:web:agents.google.com:order-processor",
  "verificationMethod": [{
    "id": "did:web:agents.google.com:order-processor#key-1",
    "type": "Ed25519VerificationKey2020",
    "controller": "did:web:agents.google.com:order-processor",
    "publicKeyMultibase": "z6Mkf5rGMoatrSj1f…"
  }],
  "authentication": ["#key-1"],
  "assertionMethod": ["#key-1"],
  "keyAgreement": [{
    "id": "#key-agree-1",
    "type": "X25519KeyAgreementKey2020",
    "controller": "did:web:agents.google.com:order-processor",
    "publicKeyMultibase": "z6LSbysY2xFMR…"
  }],
  "service": [
    {
      "id": "#acp",
      "type": "AgentCommunicationProtocol",
      "serviceEndpoint": "https://agents.google.com/order-processor/inbox"
    },
    {
      "id": "#relay",
      "type": "ACPRelay",
      "serviceEndpoint": "https://relay.acprelay.net"
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

Implementations MUST store pinned keys persistently. The storage format is implementation-defined but MUST include: the agent's DID, the pinned public key, and the timestamp of first contact.

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

1. Publish a recovery record at `https://{domain}/.well-known/acp/recovery/{name}.json`:

```json
{
  "did": "did:web:agents.google.com:order-processor",
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
_acp._tcp.agents.google.com. 300 IN SRV 10 100 443 acp.google.com.
```

This declares: "ACP agents for this domain are reachable at `acp.google.com` on port 443, with priority 10 and weight 100."

Multiple SRV records enable failover, load balancing, and relay fallback (Section 6).

A DNS TXT record MAY advertise the protocol version:

```
_acp.agents.google.com. 3600 IN TXT "v=acp1"
```

### 5.2 Agent Card Layer

Each agent MUST publish an Agent Card at a well-known URL:

```
GET https://agents.google.com/.well-known/acp/{agent-name}.json
```

A domain-level index MUST be published at:

```
GET https://agents.google.com/.well-known/acp/index.json
```

The index supports cursor-based pagination:

```
GET /.well-known/acp/index.json?cursor=eyJuIjoxMDB9&limit=100
```

```json
{
  "domain": "agents.google.com",
  "protocol": "acp/1.0",
  "agents": [
    {
      "name": "order-processor",
      "url": "/.well-known/acp/order-processor.json",
      "summary": "Processes purchase orders for cloud infrastructure"
    }
  ],
  "pagination": {
    "nextCursor": "eyJuIjoib3JkZXItcHJvY2Vzc29yIn0=",
    "hasMore": true,
    "total": 4200
  }
}
```

If `pagination` is absent or `hasMore` is `false`, there are no more results. The `limit` parameter defaults to 100 and MUST NOT exceed 1000. The cursor is opaque to the client.

HTTP `Cache-Control` headers dictate freshness. Domain operators set TTLs appropriate to their change frequency.

### 5.3 Open Discovery

ACP does not define a global search protocol. This is deliberate. But it provides concrete mechanisms for decentralised discovery.

**Domain hint file.** Domain operators SHOULD publish an `agents.txt` file at the domain root:

```
GET https://google.com/agents.txt
```

```
# ACP agents for this domain
acp-version: 1.0
acp-index: https://agents.google.com/.well-known/acp/index.json
```

This is analogous to `robots.txt` — a single, predictable file that crawlers check first. It allows a root domain to point to the subdomain where agents live. The `acp-version` field declares the protocol version. Operators MAY add an `acp-docs` field linking to protocol documentation.

**Peer exchange.** Agent Cards MAY include a `peers` field listing domains the agent has successfully interacted with:

```json
{
  "peers": ["agents.partner-co.com", "agents.logistics-provider.net"]
}
```

Peers are informational, not endorsements. Crawlers can follow peer links to discover additional ACP domains — similar to blogroll-based web discovery. Agents SHOULD only list peers with at least one verified completion record (Section 11).

**Category tags.** Entries in the Agent Card index SHOULD include a `tags` array for discoverability:

```json
{
  "name": "order-processor",
  "url": "/.well-known/acp/order-processor.json",
  "summary": "Processes purchase orders for cloud infrastructure",
  "tags": ["e-commerce", "orders", "food"]
}
```

Tags are free-form strings. The protocol does not define a controlled vocabulary — taxonomies will emerge from the ecosystem, as they did for web content.

---

## 6. Relays

### 6.1 The Problem

Agents go offline. Serverless functions cold-start. Edge workers are ephemeral. If the inbox returns a 503, the message must not be lost.

### 6.2 Relay Role

A relay is an HTTPS service that accepts ACP messages on behalf of agents and delivers them when the agent comes back online. Like MX records for email.

A relay:
- Accepts signed ACP messages addressed to agents it serves
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
_acp._tcp.agents.google.com. 300 IN SRV 10 100 443 acp.google.com.
; Fallback: relay for store-and-forward
_acp._tcp.agents.google.com. 300 IN SRV 20 100 443 relay.acprelay.net.
```

Senders MUST attempt SRV records in priority order. If the primary responds with 2xx, delivery is complete. If the primary is unreachable or returns 503, the sender MUST try the next SRV record (the relay).

### 6.4 Relay Protocol

**Sender → Relay:**

Same as sending to an inbox. The relay accepts the message and returns:

```
202 Accepted
{
  "acp": "1.0",
  "type": "acknowledge",
  "relay": true,
  "retentionUntil": "2026-04-18T14:30:00Z"
}
```

The `relay: true` flag tells the sender the message was queued by a relay, not delivered to the agent. `retentionUntil` indicates how long the relay will hold the message.

**Agent → Relay (collection):**

When the agent comes online, it polls for queued messages:

```
GET https://relay.acprelay.net/queue/{agent-did-encoded}
Authorization: DID-Signature …
```

The relay authenticates the agent via DID signature and returns queued messages. The agent acknowledges each message after processing:

```
DELETE https://relay.acprelay.net/queue/{agent-did-encoded}/{message-id}
Authorization: DID-Signature …
```

### 6.5 Retention

Relays MUST hold messages for at least 72 hours. Relays MAY hold messages for up to 30 days. Messages not collected within the retention window MAY be discarded, and the relay SHOULD notify the original sender with an `error` message (code: `DELIVERY_EXPIRED`).

### 6.6 Relay Authorization

A relay MUST be authorized by the agent it serves. The relay's endpoint MUST be listed in the agent's DID document as an `ACPRelay` service (Section 4.3). Senders SHOULD verify that a relay is authorized before delivering to it.

---

## 7. Agent Card

The Agent Card is the core capability advertisement.

```json
{
  "acp": "1.0",
  "name": "order-processor",
  "did": "did:web:agents.google.com:order-processor",
  "inbox": "https://agents.google.com/order-processor/inbox",
  "publicKey": "z6Mkf5rGMoatrSj1f…",

  "description": "Processes purchase orders for cloud infrastructure. Handles orders with up to 500 line items. Supports all GCP regions.",

  "capabilities": [
    {
      "name": "process-order",
      "description": "Submit a purchase order for processing. Returns order confirmation with estimated delivery.",
      "schema": "https://agents.google.com/schemas/order-request.json",
      "responseSchema": "https://agents.google.com/schemas/order-response.json"
    },
    {
      "name": "check-availability",
      "description": "Check real-time stock availability for one or more products by SKU.",
      "schema": "https://agents.google.com/schemas/availability-request.json",
      "responseSchema": "https://agents.google.com/schemas/availability-response.json"
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
    "verifyUrl": "https://agents.google.com/order-processor/completions"
  },

  "rateLimit": {
    "requests": 100,
    "window": "60s"
  },

  "contact": "ops@google.com"
}
```

### 7.1 Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `acp` | string | Protocol version. `"1.0"` |
| `name` | string | Agent name (local part of address) |
| `did` | string | Agent's DID |
| `inbox` | string | HTTPS URL for receiving messages |
| `publicKey` | string | Agent's public key (multibase-encoded). Enables key pinning without DID resolution |
| `description` | string | Natural language description of the agent's purpose and constraints |
| `capabilities` | array | List of capability objects |
| `auth` | object | Authentication and access policy |

### 7.2 Capability Object

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Machine-readable capability identifier |
| `description` | string | Natural language description (for LLM reasoning) |
| `schema` | string or object | URL to JSON Schema for input, or inline schema object for small schemas (under 4 KB) |
| `responseSchema` | string or object | URL to JSON Schema for output, or inline schema object |

Schemas use standard JSON Schema (2020-12). When referencing schemas by URL, implementations SHOULD include a content-hash for integrity verification: `"schema": "https://example.com/schemas/order.json#sha256=abc123…"`.

### 7.3 The Dual-Layer Principle

The `description` field is for reasoning. An LLM reads it and decides whether this capability matches the task. The `schema` field is for validation. Code reads it and enforces structural correctness.

Both are required. A capability without a description is unusable by AI agents. A capability without a schema is unverifiable.

---

## 8. Messages

### 8.1 Message Envelope

Every ACP message is a signed JSON object:

```json
{
  "acp": "1.0",
  "id": "msg_01HZ3K9V7N…",
  "type": "request",
  "from": "did:web:agents.united.com:purchasing",
  "to": "did:web:agents.google.com:order-processor",
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
| `acp` | string | MUST | Protocol version |
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

- **Float serialisation.** JCS requires IEEE 754 double-precision formatting. Languages differ: Python's `json.dumps` and JavaScript's `JSON.stringify` produce different output for values like `1e20` vs `100000000000000000000`. ACP messages use strings for timestamps and identifiers, but capability schemas may include numeric fields. Implementations MUST use a JCS-compliant serialiser for signing, not a general-purpose `JSON.stringify` with sorted keys.
- **Unicode.** JCS requires no unnecessary escaping — characters above U+001F are output literally in UTF-8, not as `\uXXXX` escapes. Some JSON libraries escape non-ASCII by default.
- **Key ordering.** JCS sorts keys by UTF-16 code unit order, which differs from naive Unicode codepoint sort for characters outside the BMP.

Implementations MUST pass the reference test vectors in Appendix D to confirm JCS correctness.

### 8.7 Content Encryption

For sensitive payloads, senders MAY encrypt the message body to the recipient's public key.

When encrypted, the `body` field is omitted and replaced with `encrypted`:

```json
{
  "acp": "1.0",
  "id": "msg_01HZ3K9V7N…",
  "type": "request",
  "from": "did:web:agents.united.com:purchasing",
  "to": "did:web:agents.google.com:order-processor",
  "capability": "process-order",
  "correlationId": "task_01HZ3K9V7N…",
  "createdAt": "2026-04-11T14:30:00Z",
  "encrypted": {
    "algorithm": "X25519-XSalsa20-Poly1305",
    "recipientKey": "did:web:agents.google.com:order-processor#key-agree-1",
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
POST https://agents.google.com/order-processor/inbox
Content-Type: application/acp+json

{…message…}
```

The inbox URL is obtained from the Agent Card or DID document service endpoint. If the primary inbox is unreachable, the sender MUST attempt delivery via the relay (Section 6).

### 9.2 Response Modes

ACP supports two response modes, negotiated via the `Prefer` header:

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
  "acp": "1.0",
  "type": "acknowledge",
  "correlationId": "task_01HZ3K9V7N…",
  "statusUrl": "https://agents.google.com/tasks/task_01HZ3K9V7N…",
  "callbackSupported": true
}
```

For async tasks, the sender can **poll** the `statusUrl` or **receive callbacks** by including a `callbackUrl` in the original request.

### 9.3 Callback Security

Receivers that support callbacks MUST enforce:

- **HTTPS only.** Callback URLs MUST use HTTPS. Reject `http://` callbacks.
- **No private IPs.** Resolve the callback hostname and reject if it resolves to a private or reserved range: `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `127.0.0.0/8`, `169.254.0.0/16`, `::1`, `fc00::/7`, `fe80::/10`. This prevents SSRF attacks.
- **ACP endpoints preferred.** Receivers SHOULD verify the callback domain has an ACP SRV record.

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

All ACP endpoints MUST use HTTPS. No plaintext HTTP. No fallback.

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

When an agent contacts another for the first time and is not on the receiver's explicit `allowlist`, the following handshake is REQUIRED:

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
   - Reputation: completion record count and verification (Section 11)
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

### 10.5 Rate Limiting

Agents SHOULD declare rate limits in their Agent Card. Receivers MUST return `429 Too Many Requests` with a `Retry-After` header when limits are exceeded.

### 10.6 No Anonymous Messages

There is no mechanism for sending unsigned or anonymous messages. This is the single most important security decision in the protocol.

---

## 11. Reputation

### 11.1 Completion Records

After a task completes successfully, both agents SHOULD sign a completion record:

```json
{
  "type": "completion",
  "taskId": "task_01HZ3K9V7N…",
  "capability": "process-order",
  "agents": {
    "requester": "did:web:agents.united.com:purchasing",
    "provider": "did:web:agents.google.com:order-processor"
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

### 11.2 Exchange Flow

1. After a successful `response`, the requester creates a completion record and signs it.
2. The requester sends the record to the provider (as a `request` message with capability `acp:sign-completion`).
3. The provider verifies the record, counter-signs, and returns the fully-signed record.
4. Both agents store the record.

Either agent can present completion records to third parties as proof of track record. The third party verifies both signatures against the agents' DID documents (or pinned keys).

### 11.3 Trust Signals

Completion records enable trust assessment without a central authority:

- **Volume:** How many verified completions does this agent have?
- **Recency:** When was the last completion?
- **Diversity:** Has this agent worked with many different counterparties, or just one?

Agents SHOULD publish their completion stats in the Agent Card:

```json
{
  "reputation": {
    "completions": 847,
    "since": "2026-01-15T00:00:00Z",
    "verifyUrl": "https://agents.google.com/order-processor/completions"
  }
}
```

The `verifyUrl` returns a paginated list of completion records that third parties can independently verify.

### 11.4 No Central Authority

ACP does not define a reputation aggregator or scoring service. Completion records are portable, verifiable, and decentralized. Third-party reputation services MAY crawl and aggregate them. The protocol provides verifiable data. The scoring ecosystem builds on top.

---

## 12. Multi-Tenancy

### 12.1 Platforms

A platform is a service that hosts agents on behalf of multiple users (tenants). A user signs up, gets a handle, and their agents run under the platform's domain.

Example: Alice signs up on AgentCloud and gets:

```
my-agent@alice.agents.agentcloud.com
```

DID:

```
did:web:alice.agents.agentcloud.com:my-agent
```

### 12.2 Addressing

Platforms MUST use subdomains for tenant isolation:

```
{agent}@{tenant}.agents.{platform}
```

This provides:
- **DNS isolation.** Each tenant gets their own subdomain (or inherits the platform's via wildcard DNS).
- **DID isolation.** Each tenant's DID documents are served under their subdomain.
- **Independent Agent Cards.** Each tenant has their own `/.well-known/acp/index.json`.

### 12.3 Platform Responsibilities

Platforms MUST:
- Serve DID documents dynamically for tenant agents at the correct `did:web` resolution path
- Publish Agent Cards per tenant
- Route messages to the correct tenant's agent
- Allow tenants to manage their own allowlists and capabilities

Platforms SHOULD:
- Operate relays for their tenants
- Provide tenant-scoped rate limiting
- Support custom domains: if a tenant controls `agents.mycompany.com`, the platform serves content for that domain via DNS CNAME

### 12.4 Platform Agent

A platform MAY publish its own agent at `did:web:agents.agentcloud.com:platform` to serve as a directory for the platform's tenants and handle platform-level operations.

---

## 13. Negotiation

Before starting work, agents MAY exchange `negotiate` messages to agree on terms:

```json
{
  "type": "negotiate",
  "body": {
    "capability": "process-order",
    "terms": {
      "maxResponseTime": "30s",
      "maxItems": 500,
      "schemaVersion": "https://agents.google.com/schemas/order-request.json"
    }
  }
}
```

The other agent responds with `negotiate` (counter-proposal) or `acknowledge` (accepted).

Negotiation is REQUIRED for first contact between strangers (Section 10.4). For established relationships where both agents support the same schema and the request falls within declared limits, negotiation MAY be skipped.

---

## 14. Error Handling

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

## 15. Extensibility

### 15.1 Custom Capabilities

Any domain operator can define new capabilities by publishing schemas at URLs they control. No coordination with anyone else. No central schema registry.

### 15.2 Protocol Extensions

The `negotiate` message supports protocol-level extensions:

```json
{
  "type": "negotiate",
  "body": {
    "extensions": {
      "billing": "https://specs.example.com/acp-billing/1.0",
      "audit": "https://specs.example.com/acp-audit/1.0"
    }
  }
}
```

Extensions are opt-in. An agent that doesn't understand an extension ignores it. Core protocol behavior is never gated on extensions.

### 15.3 What ACP Does NOT Define

- **Billing and payments.** Layer it as an extension.
- **Global agent search.** Build it as a service on top of crawlable Agent Cards.
- **Agent lifecycle management.** How you deploy, scale, and monitor agents is your problem.
- **Delegation chains.** Tracking multi-hop delegation is application-layer logic, not protocol.
- **Content format within `body`.** As long as it validates against the capability schema, the body is opaque to the protocol.

---

## 16. Putting It Together

A complete first interaction between two agents that have never met:

```
1. Agent A wants "order processing" and knows the domain google.com

2. DISCOVER
   DNS: _acp._tcp.agents.google.com → SRV → acp.google.com:443
   HTTP: GET https://acp.google.com/.well-known/acp/order-processor.json
   → Agent Card (capabilities, DID, public key, inbox URL, schemas)

3. VERIFY IDENTITY
   HTTP: GET https://agents.google.com/order-processor/did.json
   → DID document (public key, inbox endpoint)
   → Pin the public key (first contact — TOFU)

4. FIRST-CONTACT HANDSHAKE
   POST to inbox: signed negotiate message with firstContact: true
   ← acknowledge with approved capabilities and expiration

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

Seven steps. Two DNS queries, four HTTP exchanges, one callback, one reputation record. Both sides verified. No central authority involved.

If Agent B had been offline at step 5, the sender would have fallen back to the relay (SRV priority 20), and Agent B would have collected the message when it came back online.

---

## 17. Security Considerations

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
| SSRF via callbacks | Private IP denylist + HTTPS requirement + ACP endpoint verification |
| DNS hijacking | DNSSEC recommended; key pinning provides defense in depth |
| Message loss | Store-and-forward relays with 72-hour minimum retention |
| Storage exhaustion | Bounded idempotency window (24h–7d) + 1 MB message size limit |
| Relay abuse | Relay authorization via DID document service listing |
| Key recovery window exploitation | 72h grace period is time-bound and requires domain proof. Receivers SHOULD increase scrutiny of messages signed with keys that have a pending recovery record |
| Peers field manipulation | Peers are advisory, not authoritative. Agents SHOULD only list peers backed by verifiable completion records. Consumers of peer data MUST NOT treat peer listings as trust endorsements |

---

## 18. Implementation Requirements

### 18.1 To Run an ACP Agent, You Need:

1. A domain name you control (or a tenant account on a platform)
2. An HTTPS server
3. An Ed25519 key pair
4. A DID document at the well-known path
5. An inbox endpoint that accepts POST requests
6. An Agent Card describing your capabilities

That's it. No special infrastructure. No blockchain. No message brokers. Relays are optional but recommended for production.

**A practical note:** While the protocol is simple, a compliant agent requires persistent storage for key pins, message ID tracking, and optionally completion records. An in-memory implementation works for testing but will lose state on restart. A SQLite database or equivalent key-value store is the practical minimum for production.

### 18.2 Content Type

ACP messages use `application/acp+json`. Agents MUST set this content type on all ACP messages. Agents SHOULD reject requests without it.

### 18.3 Minimum Viable Implementation

A conformant ACP agent MUST:
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
- Implement key pinning for agents it interacts with
- Enforce first-contact handshake for unknown senders (unless `openAccess: true`)

A conformant ACP agent SHOULD:
- Publish a DNS SRV record
- Configure a relay for store-and-forward
- Support async responses for long-running tasks
- Implement rate limiting
- Cache resolved DID documents (minimum TTL: 300 seconds)
- Create and store completion records
- Support content encryption via `keyAgreement` keys

---

## Appendix A: Media Types

| Type | Usage |
|------|-------|
| `application/acp+json` | ACP messages |
| `application/json` | Agent Cards, DID documents, schemas |
| `text/event-stream` | SSE streaming responses |

## Appendix B: DNS Records

```
; Primary agent endpoint
_acp._tcp.agents.example.com. 300 IN SRV 10 100 443 acp.example.com.

; Relay fallback (store-and-forward)
_acp._tcp.agents.example.com. 300 IN SRV 20 100 443 relay.acprelay.net.

; Protocol version advertisement
_acp.agents.example.com. 3600 IN TXT "v=acp1"
```

## Appendix C: Well-Known URLs

| Path | Content |
|------|---------|
| `/.well-known/acp/index.json` | Domain agent index (paginated) |
| `/.well-known/acp/{name}.json` | Individual Agent Card |
| `/.well-known/acp/recovery/{name}.json` | Key recovery record (Section 4.4) |
| `/{name}/did.json` | DID document (per did:web spec) |
| `/agents.txt` | Domain hint file for discovery (Section 5.3) |

## Appendix D: JCS Test Vectors

All ACP implementations MUST produce identical canonical output for these three inputs. The expected output is the canonical form per RFC 8785.

**Vector 1 — Basic message envelope (key ordering):**

Input (keys deliberately unordered):
```json
{"type":"request","acp":"1.0","to":"did:web:b.com:agent","id":"msg_001","from":"did:web:a.com:agent","createdAt":"2026-04-12T00:00:00Z","body":{"text":"hello"}}
```

Expected canonical output:
```
{"acp":"1.0","body":{"text":"hello"},"createdAt":"2026-04-12T00:00:00Z","from":"did:web:a.com:agent","id":"msg_001","to":"did:web:b.com:agent","type":"request"}
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

This section is a self-contained guide for sending your first ACP message to a remote agent. It covers the exact bytes, encodings, and HTTP calls in order.

### Step 1: Generate an Ed25519 key pair

Generate an Ed25519 key pair. Store the private key securely. Encode the 32-byte raw public key with the multicodec prefix as multibase:

```
your_public_key = "z" + base58btc( 0xed01 + raw_32_byte_public_key )
```

### Step 2: Discover the target agent

Fetch the Agent Card:

```
GET https://<domain>/.well-known/acp/<agent-name>.json
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
  "acp": "1.0",
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
Content-Type: application/acp+json

<signed-message-json>
```

A `200` response with `type: "acknowledge"` means the handshake succeeded and the agent pinned your key.

### Step 4: Send a request

Now send the actual request. The `capability` field MUST match one of the agent's declared capabilities:

```json
{
  "acp": "1.0",
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
| `Content-Type: application/json` | `415` or rejected | Use `application/acp+json` |
| Missing `firstContact: true` | `FIRST_CONTACT_REQUIRED` (403) | Include in negotiate body for unknown agents |
| `signature` field included during canonicalization | `AUTH_FAILED` | Remove `signature` before JCS, add it back after |
| Stale `createdAt` timestamp | `MESSAGE_EXPIRED` | Use current time, not a cached value |

---

*End of specification.*
