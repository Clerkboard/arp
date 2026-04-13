# ARP Protocol Roadmap

## Version Plan

### v0.4.0 (Current)

Core protocol: discovery, negotiation, messaging, trust lifecycle.

- Relations as first-class primitive (Section 11)
- Trust Annotations — 4 levels (Section 10.7)
- Open Capabilities — stateless queries without handshake (Section 10.4.1)

### v0.5.0 (In Progress)

Account Linking, Outcome Records, Trust Credential format.

- [Account Linking spec (Section 12)](spec/arp-spec.md) — EXPERIMENTAL
- Account Linking: 3 methods (Handle Challenge, Device Grant, OAuth Delegation)
- Outcome Records for failures and disputes

### v0.6.0 (Planned)

Push Notifications.

- [Push Notifications design](spec/roadmap/push-notifications-v0.6.md) — fire-and-forget `notify` message type, notification permissions as a relation property, lease-based expiry, relay-mediated delivery for offline agents.

### v1.0.0 (Target)

Stable protocol with interoperability test suite.

- JSON-LD namespace for agent discovery
- Standardized event type registries
- Cross-implementation conformance tests
