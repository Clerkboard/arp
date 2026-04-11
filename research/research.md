# Agent-to-Agent Communication on the Open Internet

**Research Foundations — April 2026**

---

## The Problem

AI agents today communicate through human interfaces. They fill out forms, call REST APIs designed for apps, send emails meant for people. When two agents need to coordinate, they go through a human — or through a platform that was built for humans and tolerates machines.

This won't hold. As agents become autonomous — booking travel, negotiating contracts, managing supply chains, coordinating workflows across organizations — they need a native communication layer. Not HTTP with extra steps. Not email with JSON in the body. Something designed from the ground up for machines that think.

The question is: what should that look like?

This document examines six protocol families that have shaped internet communication, extracts what works and what doesn't, and identifies the architectural foundations for an agent-native protocol.

---

## Part 1: What Exists Today

### The Two Standards That Emerged

The industry has converged on two complementary protocols, both now under the Linux Foundation:

**Model Context Protocol (MCP)** — Anthropic, November 2024. Donated to the Agentic AI Foundation (AAIF) in December 2025. 97 million monthly SDK downloads. Adopted by ChatGPT, Claude, Gemini, Cursor, VS Code.

MCP is *vertical*: it connects an agent downward to tools and data. A host application (Claude Desktop, Cursor) connects to MCP servers that expose resources, tools, and prompts. The host controls information flow. Servers can't see each other. It's "USB-C for AI" — a universal plug for any tool.

MCP does not solve agent-to-agent communication. It solves agent-to-tool communication. The Sampling feature (where a server asks the host to run a prompt through the model) enables some recursive patterns, but there's no peer discovery, no delegation, no multi-agent coordination.

**Agent2Agent (A2A)** — Google, April 2025. Donated to LF AI & Data in June 2025. 150+ supporting organizations. v1.0 stable.

A2A is *horizontal*: it connects agents to each other across organizational boundaries. Agent A (built by Company X on framework Y) can discover, negotiate with, and delegate tasks to Agent B (built by Company Z on framework W).

Core concepts:
- **Agent Card**: JSON metadata at `/.well-known/agent.json` describing capabilities, skills, endpoints, and authentication requirements
- **Task lifecycle**: `working` -> `completed` / `failed` / `input-required` — with multi-turn back-and-forth
- **Transport**: JSON-RPC 2.0 over HTTP, gRPC, or SSE for streaming
- **Authentication**: OAuth 2.0, mTLS, API keys, OpenID Connect

A2A is the closest thing to an agent-to-agent protocol that exists today. But it's enterprise-oriented — designed for known partners connecting known systems. It doesn't address the open internet problem: how does an agent *discover* another agent it has never heard of?

### What Else Is Out There

**Agent Protocol (agentprotocol.ai)** — A minimal REST API spec. Create tasks, execute steps, manage artifacts. No discovery, no authentication, no streaming. A "least common denominator" approach. Eclipsed by A2A.

**Agent Network Protocol (ANP)** — W3C Community Group. The most ambitious vision: DID-based identity, meta-protocol negotiation, JSON-LD semantic messaging. "HTTP for the agentic web." Pre-production. Worth monitoring.

**IBM's ACP** — Local-first multi-agent clusters. Merged into A2A in August 2025. Its ideas (agent lifecycle states, signed capability tokens) were absorbed.

**AGENTS.md** — OpenAI. A README file for AI coding agents. Not a communication protocol. Tells agents how to work within a codebase, not how to talk to each other.

**Agentic Commerce Protocol** — OpenAI + Stripe. Domain-specific: enables agents to complete purchases. Points to a future where vertical agent protocols layer on top of general-purpose ones.

### The Gap

MCP + A2A covers a lot. But neither addresses the open internet case:

- How does an agent find another agent it has never interacted with?
- How do agents establish trust without a pre-existing business relationship?
- How do agents communicate across organizational boundaries without a central registry?
- How do ephemeral agents (spun up for a single task) participate?

These are the problems that SMTP, DNS, and the federated web already solved for humans. The question is what we can learn from them.

---

## Part 2: Protocol Autopsy

### SMTP/Email

**Core idea worth keeping: Federated, asynchronous messaging with DNS-based discovery and domain-scoped identity.**

Email is the largest federated system on the internet. It works because of four interlocking design choices:

1. **`user@domain` addressing.** Two concerns in one identifier: the domain provides routing (via DNS MX records), the local part provides specificity. Globally unique without a central authority. The domain owner controls their namespace.

2. **DNS-based discovery.** To deliver mail to `alice@example.com`, query DNS for MX records. No service registry. No broker. No API gateway. The infrastructure that resolves names already exists everywhere. Discovery is O(1) per destination domain.

3. **Federation without permission.** Any domain operator can run a mail server. No sign-up, no approval, no platform gatekeeper. You implement the protocol, publish your DNS records, and you're part of the global network.

4. **Envelope/content separation.** The routing layer (MAIL FROM, RCPT TO) doesn't parse the payload. The transport evolves independently of the content format. This is why email carried plain text in 1985 and carries calendar invitations in 2026 — the transport never changed.

5. **Store-and-forward.** Sender and receiver don't need to be online simultaneously. The infrastructure handles temporal decoupling with automatic retries. This is message-oriented middleware at planetary scale.

**What's baggage from the human era:**

- **MIME.** Base64-encoded attachments wrapped in multipart boundaries. A Rube Goldberg machine born from retrofitting binary data onto a 7-bit ASCII protocol. An agent protocol should support structured data (JSON, CBOR, protobuf) natively, not through encoding layers.
- **The spam catastrophe.** Email's original sin: no sender authentication, no cost to sending, no consent mechanism. 90%+ of email traffic became spam. Authentication (SPF, DKIM, DMARC) was bolted on decades later. An agent protocol must build mutual authentication into the initial design — deny by default, not open by default.
- **Authentication as afterthought.** SPF (2003), DKIM (2007), DMARC (2012) — each a patch on a protocol that assumed good faith. Connection-level encryption (STARTTLS) was optional and opportunistic. Every one of these should be mandatory from day one.
- **Human-readable body assumption.** Subject lines, CC/BCC, reply chains, "Dear Sir/Madam" — the entire mental model assumes a person reading at the other end. Agent communication needs message types, correlation IDs, capability declarations, and schema negotiation instead.
- **Centralization by stealth.** Despite being architecturally decentralized, email in 2026 is practically centralized. Running an independent mail server is technically possible but practically futile — Google and Microsoft's spam filters will reject your mail unless you carefully maintain reputation. The *protocol* is open; the *ecosystem* is not. An agent protocol should learn from this: openness at the protocol level doesn't guarantee openness in practice.

**The one insight:** `agent@domain`, resolved via DNS, delivered asynchronously with store-and-forward, with structured payloads and built-in mutual authentication — that's what email would look like if designed today for machines.

---

### ActivityPub

**Core idea worth keeping: Inbox/outbox as a universal communication primitive, with a shared activity vocabulary.**

ActivityPub (W3C Recommendation, 2018) powers the Fediverse — Mastodon, Lemmy, PeerTube, and others. Its architecture is elegant in its simplicity:

Every entity is an **Actor** with an HTTPS URI. Every actor has two endpoints: **inbox** (receives messages) and **outbox** (sends messages). All communication is an Activity — a typed verb wrapping an object:

- `Create` a Note
- `Follow` an Actor
- `Accept` a Follow
- `Announce` (reshare) a Note
- `Delete` an object

Federation works by POSTing Activities as JSON to remote actors' inboxes. Discovery uses WebFinger: `@alice@mastodon.social` resolves to an actor document containing the inbox URL.

**What works:**

1. **Two endpoints for everything.** Inbox and outbox. That's the entire API surface. Any interaction — following, messaging, delegating, reporting — is an Activity delivered to an inbox. This maps naturally to agents: every agent has an inbox, every agent posts to other agents' inboxes.

2. **A shared vocabulary of verbs.** `Create`, `Update`, `Delete`, `Follow`, `Accept`, `Reject`, `Undo`. Both sides understand the intent without implementation-specific knowledge. For agents, the vocabulary would be different (`Request`, `Respond`, `Delegate`, `Report`, `Negotiate`, `Cancel`) but the principle holds: agree on verbs, disagree on everything else.

3. **Actor as first-class entity.** Every participant has its own URI, its own endpoints, its own public key. Not a row in a database. Not a function to call. A fully addressable entity. This is exactly what agents need.

4. **Decentralization without permission.** Like email: stand up a server, start federating, participate. No registry, no approval.

**What's baggage:**

- **JSON-LD.** Mandated by the spec, ignored by implementations. Most software treats `@context` as a magic string and processes the JSON structurally. No one runs a JSON-LD processor. For agents: use typed JSON with explicit schema references. A `type` field and a `schema` URL is sufficient.
- **Server-coupled identity.** Your identity IS your URI on a specific server. Server goes down, identity vanishes. No portability, no recovery. Fatal for agents that need to survive infrastructure changes.
- **No delivery guarantees.** No acknowledgments, no ordering, no idempotency keys. A "POST and hope" model. Retry behavior varies wildly across implementations. Agents coordinating tasks need at-least-once delivery with deduplication.
- **Spam in a federated system.** No reputation system, no proof of work, no staking. Moderation happens through instance-level blocklists ("defederation") — a blunt instrument. Agent networks would face the same problem amplified: automated agents can flood inboxes trivially.
- **Discovery is weak.** You need to know someone's `@user@instance` address out of band. No global directory, no DHT, no "find me an agent that can do X."

**The one insight:** The inbox/outbox model with a shared activity vocabulary is the simplest possible communication primitive that supports every interaction pattern. Keep this.

---

### AT Protocol / Bluesky

**Core idea worth keeping: Identity decoupled from infrastructure, with content-addressed data and typed schemas.**

AT Protocol (Authenticated Transfer Protocol) is the most architecturally ambitious protocol in this study. It separates three concerns that every other protocol conflates:

1. **Identity** (DIDs — Decentralized Identifiers). Your identity is a cryptographic key pair, not a URL on a server. `did:plc:abc123` resolves to a DID document containing your signing key, rotation keys, and current server. If your server goes down, you update your DID document to point to a new server. Identity survives infrastructure.

2. **Data hosting** (Personal Data Servers). Your data lives in a signed Merkle tree. Every record has a content-addressed ID (CID). The tree root is signed by your DID key. Anyone can verify that every record was authorized by the identity holder, regardless of which server hosts the data.

3. **Applications** (App Views). Different services index the same data differently. Bluesky builds a social media experience. A moderation dashboard indexes the same data for safety analysis. The data layer and the application layer are independent.

**What works:**

1. **True data portability.** Not theoretical — demonstrated. Move your data from Server A to Server B, update your DID, done. Your identity, relationships, and history follow you. For agents: an agent's state, task history, and reputation survive provider changes.

2. **Cryptographic identity with key rotation.** DIDs with rotation keys mean a compromised signing key doesn't destroy the identity — you rotate it. This is essential for agents that operate autonomously over long periods.

3. **Content-addressed data.** Every record is hash-referenced. You can verify data hasn't been tampered with. When Agent A says "I completed task X with result Y," Agent B can verify the claim against the content hash. Tamper-evident records are the foundation of inter-agent trust.

4. **The Lexicon system.** Typed, namespaced schemas using reverse-DNS conventions. `app.bsky.feed.post` defines a social media post. `com.myagent.task.request` could define a task delegation. New schemas don't conflict with existing ones. No central coordination needed. Versioning through namespacing rather than version numbers.

5. **Handle resolution via DNS.** `alice.com` maps to `did:plc:abc123` via a DNS TXT record at `_atproto.alice.com`. Human-readable when you want it, cryptographically verifiable always.

**What's baggage:**

- **Full-stack complexity.** PDS + Relay + App View + Feed Generator + Labeler. Running the complete stack is heavy infrastructure. A simple request-response between two agents shouldn't require a Merkle search tree and a firehose subscription.
- **The firehose model.** The Relay consumes every PDS's event stream and aggregates it into a unified firehose. This makes sense for social media (you want to see everything and filter). For agent communication, it's backwards — an agent doesn't need to subscribe to the entire network to receive messages addressed to it.
- **Centralization pressure.** The protocol supports decentralization, but Bluesky runs the dominant Relay, App View, and PLC directory. The Relay is expensive to operate. The PLC directory is a potential single point of control. Economic centralization emerges even when the protocol is technically open.
- **No ephemeral communication.** Everything is a record in a Merkle tree. This is great for posts but awkward for transient agent messages. Not every request-response exchange needs to be permanently stored and content-addressed.

**The one insight:** Separate identity from infrastructure. An agent's identity should be a cryptographic key pair, not a URL on a server. Everything else — data hosting, capability advertisement, task history — is infrastructure that can be replaced without breaking identity.

---

### Model Context Protocol (MCP)

**Core idea worth keeping: Capability negotiation through structured tool descriptions with runtime discovery.**

MCP's architecture is Host/Client/Server:
- The Host (Claude, ChatGPT) manages multiple Clients
- Each Client maintains a 1:1 session with a Server
- Servers expose Resources (data), Tools (functions), and Prompts (templates)

The key interaction: during session initialization, server and client exchange capabilities. The server declares what it can do (which tools, which resources). The client declares what it supports (sampling, roots, elicitation). Both sides know what the other offers before any work begins.

**What works:**

1. **Runtime capability discovery.** An MCP client doesn't hardcode what a server can do — it asks during initialization. The server responds with typed tool descriptions including input schemas (JSON Schema). The client can then reason about which tools to use for a given task. This is the closest thing to "an agent describing what it can do" that exists in production today.

2. **Typed tool descriptions.** Each tool has a name, description, and input schema. The description is natural language (for the LLM to reason about). The schema is formal (for validation). This dual-layer — semantic meaning for reasoning, structural schema for validation — is the right approach for agent capabilities.

3. **The Sampling pattern.** A server can ask the host to run a prompt through the model. This means an MCP server (a tool) can invoke AI reasoning as part of its execution. It's a primitive form of agent-to-agent delegation: "I need you to think about this."

**What's baggage:**

- **Human-in-the-loop assumption.** MCP is designed around the idea that a human controls the host. Tools require user consent. The security model assumes a person is approving actions. For autonomous agent-to-agent communication, the trust model needs to be machine-to-machine.
- **No cross-internet discovery.** MCP servers are pre-configured in the host application. There's no mechanism for an agent to discover MCP servers it hasn't been told about. A community registry exists, but it's not part of the protocol.
- **1:1 sessions, not peer-to-peer.** A client connects to a server. There's no concept of two peers with equal standing. Agent-to-agent communication needs symmetric relationships, not client-server hierarchy.

**The one insight:** Agents need to describe their capabilities in a format that is both machine-parseable (for validation and routing) and semantically rich (for reasoning about when to use them). MCP's dual-layer approach — natural language descriptions paired with formal schemas — is the right model.

---

### HTTP/REST

**Core idea worth keeping: Universal, stateless, intermediary-friendly communication with content negotiation.**

HTTP won because it works everywhere. Any language with sockets can speak it. It passes through every firewall. It scales through caching and proxies without those intermediaries understanding the application.

**What works:**

1. **Statelessness as default.** Each request carries everything needed to process it. No server-side session state required. Any server in a pool can handle any request. Failed requests can be retried. This enables horizontal scaling, fault tolerance, and simple deployment. Agents should default to stateless communication with opt-in statefulness for long-running collaborations.

2. **Content negotiation.** Client and server agree on representation formats via `Accept` headers. The same resource can be JSON, XML, or protobuf depending on what the client supports. For agents: negotiate not just data format but capability version, context budget, response detail level, and communication protocol variant.

3. **The intermediary principle.** Proxies, caches, CDNs, and load balancers process HTTP without understanding the application. They work because protocol metadata (methods, status codes, cache headers) is separate from payload. Agent communication should support the same: infrastructure components that route, cache, rate-limit, log, and monitor without parsing agent-specific content.

4. **Machine-readable API descriptions (OpenAPI).** OpenAPI specs describe endpoints, input/output schemas, authentication, and parameters. This is 80% of what agents need for capability discovery. The missing 20%: semantic meaning, composition rules, cost, side effects, and freshness.

5. **Caching with explicit freshness semantics.** `Cache-Control`, `ETag`, conditional requests. The data publisher decides how long responses are valid. This model applies directly to agent capability advertisements: the agent offering a capability specifies how long that advertisement is valid.

**What's baggage:**

- **Browser security model.** CORS, cookie scoping, same-origin policy, preflight OPTIONS requests — all exist because browsers run untrusted JavaScript with ambient authority (cookies). Agents authenticate explicitly with bearer tokens. None of this applies.
- **Human-oriented status codes.** `301 Moved Permanently` triggers browser redirects. `303 See Other` tells browsers to change POST to GET. `407 Proxy Authentication Required` assumes a human entering proxy credentials. Agents need rich, structured error objects — not a taxonomy designed for browser UX.
- **Verbose text headers.** User-Agent, Accept-Language, Accept-Encoding, Connection — sent with every request even when redundant. HTTP/2's HPACK helps, but the underlying verbosity remains. High-frequency agent communication should negotiate once and reference the agreement, not repeat it.
- **Request-response only.** HTTP was built for "client asks, server answers." Webhooks, SSE, and WebSockets are all workarounds for the lack of native server-initiated communication. Agent interactions need bidirectional streaming, event subscriptions, and push notifications as first-class patterns, not bolt-ons.

**The one insight:** The protocol that wins is the one that works in the most hostile network environments. HTTP passes through every firewall, works with every proxy, and can be implemented in any language. An agent protocol built on HTTP inherits all of this for free. Fighting HTTP is fighting the infrastructure of the internet.

---

### DNS

**Core idea worth keeping: Hierarchical naming with delegated authority, typed extensible records, and TTL-based caching.**

DNS is a hierarchical, distributed, eventually-consistent database that maps names to records. It works because of the delegation model: the root servers know who handles `.com`, Verisign knows who handles `vodafone.com`, and you know what's in your zone. No single entity manages the whole database. Adding a subdomain requires no upstream coordination.

**What works:**

1. **Hierarchical delegation.** `agent.vodafone.com` proves organizational ownership through the DNS delegation chain. The domain owner controls their agent namespace. No central agent registry needed. This gives you uniqueness, verifiability, and stability for free, using infrastructure that already exists.

2. **Typed, extensible records.** A records for addresses. MX records for mail routing. SRV records for service location. TXT records for arbitrary metadata. New capabilities are added by defining new record types (or abusing TXT records), without changing the protocol. Agents could use purpose-built record types: `AGENT` records for capability advertisement, or SRV-style records for `_agent._tcp.domain.com`.

3. **SRV records for service discovery.** `_http._tcp.example.com SRV 10 60 8080 web1.example.com` says "HTTP is available on web1.example.com port 8080, priority 10, weight 60." For agents: `_agent._tcp.example.com` discovers agent endpoints with failover and load balancing built in.

4. **TTL-based caching.** The publisher, not the consumer, decides freshness. A 5-minute TTL on an agent capability record means "re-check my capabilities every 5 minutes." A 24-hour TTL on an identity record means "my identity is stable; cache aggressively." The agent controls the tradeoff.

5. **Zero-config local discovery (mDNS/DNS-SD).** Within a local network, agents can discover each other without any central infrastructure. An agent starts up, announces its capabilities via multicast, and peers discover it automatically. This is the right model for agents within the same organization or infrastructure.

**What's baggage:**

- **Slow propagation.** TTL caching means changes take minutes to hours to propagate globally. For dynamic agent ecosystems where capabilities come and go in seconds, DNS propagation is too slow. Real-time discovery needs a faster mechanism (potentially backed by DNS for the stable layer).
- **The registrar system.** Domain registration requires a commercial transaction, annual fees, WHOIS data. For organizational agents, this is fine — the organization already has a domain. For ephemeral or personal agents, it's too much friction.
- **DNSSEC complexity.** Cryptographic signing of DNS responses to prevent cache poisoning. 20+ years of deployment effort, still incomplete. Key management is complex, misconfiguration fails catastrophically. The concept is right (authenticate your records), but the implementation is a cautionary tale.
- **Public by default.** Anyone can query any DNS name. There's no access control on queries. For agents, capability discovery might need to be restricted — not every agent should enumerate your capabilities. This requires a layer above DNS.
- **Small record size.** DNS records are limited to ~4096 bytes (EDNS). Agent capability descriptions, schemas, and certificates will exceed this. DNS works as a pointer ("my agent card is at this URL") but not as the storage layer itself.

**The one insight:** DNS gives you a globally agreed-upon, hierarchically delegated, cached naming system for free. Don't build a new one. Use DNS for stable identity resolution and service discovery, then layer real-time capability negotiation on top via HTTP.

---

## Part 3: Synthesis

### The Primitives an Agent Protocol Needs

Six things. Everything else is a feature built on top.

**1. Identity**

An agent needs a stable, portable, cryptographically verifiable identity that survives server changes, framework migrations, and provider switches.

The best model: DID-based identity (from AT Protocol) anchored to DNS (from email). `did:web:agents.vodafone.com:order-processor` resolves by fetching `https://agents.vodafone.com/.well-known/did.json`. The DID document contains:
- The agent's signing key (proves messages came from this agent)
- Rotation keys (recovers from key compromise)
- The agent's current endpoint

The domain provides organizational affiliation and trust context. The DID provides cryptographic verifiability. The two together give you: `agent@domain` with signatures.

**2. Discovery**

Three layers, from stable to dynamic:

- **DNS layer** (stable, cached): SRV-style records for agent endpoints. `_agent._tcp.vodafone.com` returns the host and port where agents for this domain can be reached. TTL-based caching. Changes propagate in minutes.
- **Agent Card layer** (semi-stable, HTTP-cached): JSON capability document at `/.well-known/agent.json` (from A2A). Describes what the agent can do, what schemas it accepts, authentication requirements. HTTP cache headers control freshness. Changes propagate in seconds.
- **Runtime negotiation layer** (dynamic, per-session): Capability exchange during session initialization (from MCP). The two agents agree on protocol version, supported message types, context limits, and interaction mode. Happens once per relationship, refreshed as needed.

For local/organizational discovery: mDNS-style announcement. An agent starts, broadcasts its capabilities, peers discover it without a registry.

For open internet discovery: this is the unsolved problem. No protocol has cracked "find me an agent I've never heard of that can do X." DNS can tell you "vodafone.com has agents." It can't tell you "who on the internet can process purchase orders?" That requires either a registry (centralization) or a gossip protocol (complexity). This is an open research question.

**3. Addressing**

The `agent@domain` model (from email) with modern routing:

- `order-processor@agents.vodafone.com` — identifies a specific agent (or class of agents) at a domain
- The domain resolves via DNS to an endpoint
- The local part is opaque to the network — the domain operator decides what it means
- Messages are delivered to the agent's inbox (from ActivityPub)

Why this works: it's globally unique without a central authority, it's routable via existing infrastructure, and the domain provides organizational trust context.

**4. Communication**

The inbox/outbox model (from ActivityPub) over HTTP (for universality):

- Every agent has an inbox URL. To communicate, POST a message to the inbox.
- Messages are typed activities with a shared vocabulary: `Request`, `Respond`, `Delegate`, `Report`, `Negotiate`, `Cancel`, `Acknowledge`.
- Each message carries: sender identity (DID), recipient, correlation ID (for request-response threading), message type, schema reference, and payload.
- Delivery is at-least-once with idempotency keys (not ActivityPub's "POST and hope").
- Supports synchronous request-response (HTTP POST, wait for response) and asynchronous fire-and-forget (POST, get 202 Accepted, poll or receive webhook).
- Streaming via SSE for long-running tasks (from A2A).
- Authentication on every message: the sender signs the message with their DID key. The receiver verifies against the sender's DID document.

**5. Capability Description**

The dual-layer model (from MCP) with namespaced schemas (from AT Protocol):

- **Semantic layer**: Natural language description of what the agent can do. "I process mobile phone contract orders. I handle new activations, upgrades, and SIM-only plans. I respond within 30 seconds."
- **Schema layer**: Formal schema defining input/output types, constraints, and validation rules. Using namespaced types: `com.vodafone.agent.order.request`, `com.vodafone.agent.order.response`.
- **Metadata**: Cost per interaction, rate limits, availability hours, geographic constraints, required authentication level, data handling policies.

Published in the Agent Card (semi-stable) and refined during runtime negotiation (dynamic).

**6. Trust**

Built-in from day one. Not bolted on later.

- **Authentication**: Mutual. Every message is signed by the sender's DID key. Every connection uses TLS. No plaintext fallback. No anonymous messages.
- **Authorization**: Capability-based. An agent declares what message types it accepts and from whom. "I accept `OrderRequest` messages from agents whose DID documents are anchored to domains with verified merchant status." Not ACLs — capabilities.
- **Reputation**: Content-addressed task completion records (from AT Protocol). When Agent A completes a task for Agent B, both sign a completion record. This builds a verifiable, tamper-evident reputation trail without a central authority. "I trust Agent X because I can verify its signed history of completing 500 tasks."
- **Default posture**: Deny by default. An agent only processes messages from senders that meet its stated trust requirements. Open by default is email's original sin — don't repeat it.

---

### What the Human-Era Protocols Got Right

| Principle | Source | Why It Matters |
|---|---|---|
| Federation without permission | SMTP, ActivityPub | No gatekeeper. Any domain operator can run agents. |
| DNS-based discovery | SMTP, DNS | Global, cached, fault-tolerant service discovery using existing infrastructure. |
| Domain-scoped identity | SMTP | `agent@domain` provides organizational context and trust signal. |
| Inbox/outbox simplicity | ActivityPub | Two endpoints for all communication. Maximum simplicity. |
| Shared vocabulary of verbs | ActivityPub | Both sides understand intent without implementation-specific knowledge. |
| Identity decoupled from infrastructure | AT Protocol | Agents survive server changes. Identity is a key pair, not a URL. |
| Content-addressed data | AT Protocol | Tamper-evident records. Verifiable claims. Trust without authority. |
| Typed, namespaced schemas | AT Protocol | Extensible capability descriptions without central coordination. |
| Dual-layer capability description | MCP | Semantic (for reasoning) + structural (for validation). |
| HTTP as universal transport | HTTP | Works through every firewall, with every proxy, in every language. |
| Statelessness as default | HTTP | Horizontal scaling, fault tolerance, retry safety. |
| The intermediary principle | HTTP | Infrastructure processes protocol metadata without understanding payloads. |
| TTL-based freshness | DNS, HTTP | The publisher controls caching. Changes propagate predictably. |
| Hierarchical delegation | DNS | No single entity manages the whole namespace. |

### What the Human-Era Protocols Got Wrong

| Mistake | Source | Lesson |
|---|---|---|
| Open by default | SMTP | Caused the spam catastrophe. Default to deny. Authenticate everything. |
| Authentication as afterthought | SMTP | SPF, DKIM, DMARC — each a decade-late patch. Build auth in from day one. |
| Server-coupled identity | ActivityPub | Server goes down, identity dies. Identity must be infrastructure-independent. |
| No delivery guarantees | ActivityPub | "POST and hope" doesn't work for coordination. Need at-least-once with dedup. |
| Text-first payload model | SMTP | MIME is 40 years of encoding hacks. Design for structured data natively. |
| Human-centric concepts | SMTP, HTTP | Subject lines, CC, CORS, cookie sessions — none of these apply to agents. |
| Slow propagation | DNS | Minutes-to-hours TTL caching is too slow for dynamic capability changes. |
| Complexity through ambition | AT Protocol, DNSSEC | Full PDS/Relay/AppView stack, DNSSEC key management — correct ideas, crushing complexity. Simpler implementations win. |
| Centralization by stealth | SMTP, AT Protocol | Protocols are open; ecosystems centralize around dominant operators. Protocol design alone doesn't prevent this. |
| JSON-LD | ActivityPub | Nobody processes it. Mandated complexity that implementations ignore. Use typed JSON. |

---

### Open Questions

These are the hard problems no existing protocol has solved:

1. **Open discovery.** "Find me an agent that can process purchase orders" — without knowing which domain to ask. DNS tells you about known domains. It doesn't search across all domains. This requires either a registry (centralization risk), a DHT (complexity), or a search/index service (who runs it?). A2A's Agent Cards at well-known URLs are discoverable by crawlers, but there's no standard search protocol.

2. **Trust bootstrapping.** Two agents that have never interacted need to establish trust. Reputation records help for known agents. What about new agents? Domain trust (a `.gov` agent, a Fortune 500 domain) provides some signal. Capability attestations from trusted third parties could work. But there's no established pattern.

3. **Semantic interoperability.** Two agents use different schemas for "purchase order." How do they map between them? Ontology alignment is an unsolved problem in computer science. LLMs make it tractable (they can reason about schema mappings) but not reliable.

4. **Economic coordination.** Agent A wants Agent B to do work. Who pays? How? The Agentic Commerce Protocol (OpenAI + Stripe) addresses the consumer case. B2B agent economics — metering, billing, SLAs — are uncharted.

5. **Liability and audit.** When Agent A delegates to Agent B and something goes wrong, who's responsible? Content-addressed completion records provide an audit trail. But the legal and governance frameworks don't exist.

6. **Preventing centralization.** Every federated protocol (email, ActivityPub, AT Protocol) eventually centralizes around dominant operators. How do you design a protocol where centralization is not just unnecessary but actively disadvantaged?

---

### Where This Leads

The foundations are clear. An agent protocol for the open internet would combine:

- **Email's addressing and federation model** — `agent@domain`, DNS discovery, no gatekeeper
- **ActivityPub's communication primitives** — inbox/outbox, typed activities, shared verbs
- **AT Protocol's identity and data model** — DIDs for portable identity, content-addressed records for trust
- **MCP's capability descriptions** — semantic + structural, runtime negotiation
- **HTTP's universality** — works everywhere, supports intermediaries, cacheable
- **DNS's naming** — hierarchical delegation, typed records, TTL-based freshness

None of these is the answer by itself. But together they point toward something: a federated, cryptographically authenticated, capability-negotiated messaging protocol where agents discover each other through DNS, communicate through typed messages over HTTP, prove their identity through DIDs, and build trust through verifiable records.

The hard part isn't the protocol. It's the ecosystem — discovery, trust bootstrapping, preventing centralization, and getting adoption without a dominant platform operator.

That's the next document.
