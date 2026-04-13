# ARP Integration Brief for Clerkboard (Go)

## Context

We just ran a live end-to-end test: Alfred (Tiago's agent on Clerkboard) contacted Ana (an ARP reference server running on a Cloudflare Tunnel). It worked, but Alfred's Claude had to iterate through 6 attempts before getting the protocol right. Every mistake is a friction point that Clerkboard should handle automatically in its Go codebase so agents never have to think about it.

## The Protocol in 30 Seconds

ARP is HTTP + Ed25519 signing + JCS canonicalization. Every message is a JSON object POSTed to the recipient's inbox. The sender signs the message, the receiver verifies. First contact requires a TOFU handshake (negotiate message with the sender's public key).

**v0.4.0 adds:** Open Capabilities (query without handshake), Relations (lifecycle states replacing raw key pins), Trust Annotations, and JSON-LD for search engine discovery.

**Spec**: https://github.com/Clerkboard/arp/blob/main/spec/arp-spec.md

## What Alfred Got Wrong (and what Clerkboard must handle)

### 1. JCS Canonicalization (THE critical one)

The signature is computed over JCS-canonicalized JSON (RFC 8785). This means:
- All object keys sorted **recursively** (not just top-level)
- No whitespace between tokens
- Numbers serialized per ES2024 rules (no trailing zeros, no +0)
- Strings use minimal Unicode escapes

Alfred's fix was `deepSort` on the message object before signing. **Clerkboard's Go code must implement JCS correctly.** Use a proper Go JCS library (e.g., `github.com/nicecycle/jcs` or implement per RFC 8785).

```go
// WRONG: json.Marshal does NOT sort keys by default in all cases
// RIGHT: Use JCS canonicalization before signing
canonical := jcs.Transform(messageWithoutSignature)
signature := ed25519.Sign(privateKey, canonical)
```

### 2. Multibase Key Format

Public keys in ARP use **multibase base58btc** encoding:
- Prefix: `z` (indicates base58btc)
- Payload: raw 32-byte Ed25519 public key bytes
- Example: `z6MksAbcVoHWZYNofRYfg5nNdCDMuwp9K7VMLev87e4kLRb1`

```go
multibase := "z" + base58.Encode(rawPublicKeyBytes)  // 32 bytes
```

For the **body.publicKey** field in negotiate messages, use this same format.

### 3. Signature Format

Signatures also use multibase base58btc:
```go
sig := ed25519.Sign(privateKey, jcsCanonicalBytes)
multibaseSig := "z" + base58.Encode(sig)  // 64 bytes -> base58btc
```

### 4. Content-Type Header

Must be `application/arp+json`. Servers MAY accept `application/json` as fallback, but the correct type is:
```
Content-Type: application/arp+json
```

### 5. First-Contact Handshake

Before sending any request, an unknown agent must negotiate:
```json
{
  "arp": "1.0",
  "id": "msg_<uuid>",
  "type": "negotiate",
  "from": "did:web:clerkboard.com:alfred",
  "to": "did:web:target-domain.com:agent-name",
  "createdAt": "2026-04-12T02:30:45.317Z",
  "body": {
    "firstContact": true,
    "publicKey": "z6Mk...",
    "intent": "I am Alfred, Tiago's personal agent. I want to send a message."
  },
  "signature": "z..."
}
```

The `firstContact: true` flag is **required** in the body. Without it, the server won't create a relation.

The acknowledge response now includes scoped approval:
```json
{
  "type": "acknowledge",
  "body": {
    "firstContact": true,
    "approvedCapabilities": ["echo"],
    "approvedUntil": "2026-05-12T...",
    "trustLevel": "new"
  }
}
```

Clerkboard should store `approvedCapabilities` and `approvedUntil` — if approval expires or the capability isn't in scope, the server returns `CAPABILITY_DENIED` and Alfred must re-negotiate.

### 6. Message Envelope

All fields at top level. The `arp` version field must be present:
```json
{
  "arp": "1.0",
  "id": "msg_<uuid>",
  "type": "request",
  "from": "<sender-did>",
  "to": "<recipient-did>",
  "capability": "echo",
  "correlationId": "task_<uuid>",
  "createdAt": "2026-04-12T02:31:00.000Z",
  "body": { ... },
  "signature": "z..."
}
```

### 7. Signing Process (exact steps)

```
1. Build the message object WITHOUT the "signature" field
2. JCS-canonicalize the object (RFC 8785: recursive key sort, minimal JSON)
3. Sign the UTF-8 bytes of the canonical string with Ed25519
4. Encode signature as "z" + base58btc(signature_bytes)
5. Add "signature" field to the message
6. POST to recipient's inbox
```

### 8. Verification Process (exact steps)

```
1. Remove the "signature" field from the received message
2. JCS-canonicalize the remaining object
3. Decode the signature: strip "z" prefix, base58btc-decode
4. Verify with Ed25519 using sender's public key
```

## v0.4.0 Features Alfred Must Support

### 9. Open Capabilities (browse before you buy)

Capabilities marked `open: true` in the Agent Card accept requests **without a prior negotiate**. Alfred can query price checks, availability, or public info without a handshake.

```go
// Check if capability is open before deciding to negotiate
for _, cap := range agentCard.Capabilities {
    if cap.Name == "check-availability" && cap.Open {
        // Skip handshake, send request directly
        // Must include publicKey in body for auth
    }
}
```

Open requests require `publicKey` in the body (no pinned key exists):
```json
{
  "arp": "1.0",
  "type": "request",
  "capability": "echo",
  "body": {
    "publicKey": "z6Mk...",
    "message": "Quick query"
  },
  "signature": "z..."
}
```

Constraints: synchronous only, single exchange, no relation created.

If Alfred targets a **non-open** capability without a relation, the server returns `FIRST_CONTACT_REQUIRED`. Clerkboard should auto-detect this and fall back to negotiate.

### 10. Relations (replaces raw key pins)

First contact now creates a **relation** — not just a key pin. Relations have lifecycle states:

| State | Meaning |
|-------|---------|
| `active` | Normal interaction |
| `dormant` | No activity for 90+ days (auto-transitions) |
| `terminated` | Explicitly ended — messages rejected |

Dormant relations **reactivate** on new activity. Clerkboard should track relation state per peer.

### 11. Termination

To end a relation, send a negotiate with `terminate: true`:
```json
{
  "type": "negotiate",
  "body": { "terminate": true },
  "signature": "z..."
}
```

Server responds with `{ "terminated": true }`. After termination, all messages from that DID are rejected.

### 12. Trust Annotations

Responses include a `trustLevel` field: `trusted`, `known`, `new`, or `unknown`. This is computed from the relation state and completion history:

- `trusted` — active relation + 5+ completions
- `known` — active relation + 1+ completions
- `new` — active relation + 0 completions
- `unknown` — no relation

Clerkboard can use this to adjust Alfred's behavior (e.g., require human approval for requests from `unknown` agents, auto-approve from `trusted`).

### 13. Agent Discovery via agents.txt

Before resolving an Agent Card, check `agents.txt` at the domain root:
```
GET https://target-domain.com/agents.txt
```

Returns:
```
arp-directory: https://agents.target-domain.com/.well-known/arp/index.json
arp-version: 1.0
open-capabilities: check-availability, store-hours
```

The `open-capabilities` field tells Alfred which capabilities he can query without negotiating. The `arp-directory` field points to the full agent index.

### 14. JSON-LD in Agent Cards

Agent Cards now include JSON-LD for search engine indexing:
```json
{
  "@context": {
    "@vocab": "https://schema.org/",
    "arp": "https://agentrelationsprotocol.com/ns/"
  },
  "@type": "SoftwareApplication",
  "arp": "1.0",
  "name": "order-processor",
  ...
}
```

Clerkboard doesn't need to do anything special with this — just parse the card fields as before. The `@context` and `@type` are for crawlers.

## What Clerkboard Should Build

### A. ARP Client (Go package)

A reusable Go package that any Clerkboard agent can use to talk ARP:

```go
// Ideal API for Clerkboard agents
client := arp.NewClient(agentDID, privateKey)

// Discover target agent (checks agents.txt → directory → card)
card, err := client.Discover("target-domain.com", "order-processor")

// Open capability — no handshake needed
resp, err := client.Query(card, "check-availability", map[string]any{
    "product": "organic-flour",
})
// resp.TrustLevel == "unknown" (no relation)

// Full handshake for non-open capabilities
err = client.Handshake(card)
// resp.ApprovedCapabilities == ["process-order", "check-availability"]
// resp.TrustLevel == "new"

// Send a request (signs automatically, uses relation)
resp, err := client.Send(card, "process-order", map[string]any{
    "items": [...],
})
// resp.TrustLevel == "new" → "known" → "trusted" over time

// Terminate when done
err = client.Terminate(card)
```

The client should:
- Generate and manage Ed25519 key pairs
- Handle JCS canonicalization internally
- Check `open` flag on capabilities — use `Query()` for open, `Send()` for relation-based
- Auto-negotiate on first contact (or on `FIRST_CONTACT_REQUIRED` / `CAPABILITY_DENIED`)
- Track relations per peer (status, approved capabilities, expiry)
- Sign all outbound messages
- Verify all inbound responses
- Set correct Content-Type headers
- Resolve agents.txt → directory → card for discovery

### B. Agent Card Resolution

When a Clerkboard agent wants to contact an external ARP agent, resolve the Agent Card:

```
GET https://<domain>/.well-known/arp/<agent-name>.json
```

The Agent Card contains:
- `inbox`: where to POST messages
- `publicKey`: for verifying responses
- `capabilities`: what the agent can do (check `open: true` for stateless queries)
- `auth`: authentication requirements
- `@context` / `@type`: JSON-LD metadata (ignore for client logic, useful for crawlers)

### C. DID Resolution

ARP uses `did:web` for identity:
- `did:web:domain.com:agent-name` resolves to `https://domain.com/agent-name/did.json`
- The DID document contains the agent's public key

### D. Key Management

Each Clerkboard agent needs a persistent Ed25519 key pair:
- Generate once, store securely
- Public key published in DID document and Agent Card
- Private key used for signing outbound messages
- Never regenerate (other agents have pinned the old key via TOFU)

## Go Implementation Checklist

**Core (required):**
- [ ] Ed25519 key generation and storage (`crypto/ed25519`)
- [ ] Base58btc encoding/decoding (e.g., `github.com/btcsuite/btcutil/base58`)
- [ ] JCS canonicalization (RFC 8785) — **test with floats and Unicode**
- [ ] Multibase encoding (`z` + base58btc for keys and signatures)
- [ ] Message signing (JCS canonical form → Ed25519 sign → multibase encode)
- [ ] Message verification (strip signature → JCS canonical → Ed25519 verify)
- [ ] First-contact negotiate flow (with `firstContact: true`)
- [ ] Agent Card fetching and parsing (handle `@context`/`@type` gracefully)
- [ ] DID document resolution
- [ ] Content-Type: `application/arp+json` on all requests
- [ ] Response signature verification

**v0.4.0 (required):**
- [ ] Relation store replacing key pin store (track status, trust level, completions)
- [ ] Open capability detection — check `open: true` on capabilities before negotiate
- [ ] Open request flow — include `publicKey` in body, skip handshake
- [ ] Auto-fallback: if `FIRST_CONTACT_REQUIRED` returned, negotiate then retry
- [ ] Store `approvedCapabilities` and `approvedUntil` from acknowledge
- [ ] Re-negotiate when `CAPABILITY_DENIED` received (approval expired)
- [ ] Termination: send `negotiate` with `terminate: true` to end a relation
- [ ] agents.txt resolution — check `arp-directory` and `open-capabilities` before discovery
- [ ] Handle dormant relation reactivation (just send a message — server reactivates)

## JCS Test Vectors

Use these to validate your JCS implementation:

**Input:**
```json
{"z":"last","a":"first","m":{"z":1,"a":2}}
```

**Expected JCS output:**
```
{"a":"first","m":{"a":2,"z":1},"z":"last"}
```

**Input with special chars:**
```json
{"emoji":"cafe\u0301","num":1.0,"neg":-0.5}
```

**Expected:**
```
{"emoji":"caf\u00e9","neg":-0.5,"num":1}
```

(Note: `1.0` becomes `1`, NFC normalization applies to Unicode)

## Error Codes to Handle

| Code | Meaning | Action |
|------|---------|--------|
| `FIRST_CONTACT_REQUIRED` (403) | Need to negotiate first | Send negotiate with `firstContact: true`, then retry |
| `CAPABILITY_DENIED` (403) | Approval expired or capability not in scope | Re-negotiate to get fresh approval |
| `AUTH_FAILED` (403) | Signature invalid | Check JCS canonicalization and key format |
| `AUTH_DENIED` (403) | Relation terminated or denylist | Cannot recover — relation is over |
| `KEY_MISMATCH` (403) | Key changed since first contact | Key rotation needed |
| `CAPABILITY_UNKNOWN` (400) | Agent doesn't have that capability | Check Agent Card capabilities list |
| `SCHEMA_INVALID` (400) | Message format wrong | Check envelope fields |
| `MESSAGE_EXPIRED` (400) | createdAt too old | Use fresh timestamp |

## Live Test Endpoints

Our reference servers for testing:

- **TypeScript**: `npx create-arp-agent test-agent && cd test-agent && npm i && npm start`
- **Python**: `git clone https://github.com/anthropics/arp-server-py && cd arp-server-py && pip install -r requirements.txt && python server.py`
- **Verify**: `npx arp-verify localhost:3141` (runs 16 protocol compliance checks including open capabilities, JSON-LD, and trust annotations)

## ARP SDK (TypeScript)

We also have an SDK at `@arp-protocol/sdk` that handles all of this for TypeScript/Node.js agents:

```typescript
import { ARPAgent } from '@arp-protocol/sdk';

const agent = new ARPAgent({ name: 'my-agent', domain: 'localhost' });

agent.handle('echo', {
  description: 'Echo back the message',
  schema: { type: 'object' },
  responseSchema: { type: 'object' },
}, async (msg) => {
  return { echo: msg.body, receivedAt: new Date().toISOString() };
});

agent.listen();
```

## Summary

The protocol itself is simple (HTTP + Ed25519 + JCS). The friction comes from getting the encoding details right. Build a Go `arp` package that handles JCS, multibase, signing, and the handshake flow internally, so Clerkboard agents can talk ARP with a single function call.
