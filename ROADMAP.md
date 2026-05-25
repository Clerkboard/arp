# ARP Protocol Roadmap

## Version Plan

### v0.5.0 (Current)

Account Linking, Outcome Records, Trust Credential format.

- Account Linking (Section 12) — EXPERIMENTAL
- 3 linking methods: Handle Challenge, Device Grant, OAuth Delegation
- Outcome Records for failures and disputes

### v0.7.0 (In Progress)

Push Notifications + Settlements — bundled release.

- [Push Notifications design](spec/roadmap/push-notifications-v0.7.md) — fire-and-forget `notify` message type, notification permissions as a relation property, lease-based expiry, relay-mediated delivery for offline agents.
- [Settlements design](spec/roadmap/settlements-v0.7.md) — agent-to-agent payments via signed quote + receipt; rail-neutral (x402, Lightning, cards); reuses Account Linking for spend authority.

### v1.0.0 (Target)

Stable protocol with interoperability test suite.

- JSON-LD namespace for agent discovery
- Standardized event type registries
- Cross-implementation conformance tests
