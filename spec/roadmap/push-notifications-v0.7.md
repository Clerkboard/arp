# ARP Roadmap: Push Notifications (v0.7)

> **Status: PLANNED — Not yet specced. This document captures the design intent for a future version.**

## Summary

Push Notifications will add fire-and-forget event delivery to ARP, enabling agents to receive real-time updates (order shipped, payment received, subscription expiring) without polling.

## Motivation

A B2B agent protocol where the only way to learn "your order shipped" is to poll every 30 seconds is not viable at scale. Notifications are fundamental for the use cases ARP targets, but they build entirely on existing infrastructure (relay, signing, relations) and are purely additive — no existing flows change.

## Planned Design

### New protocol additions

1. **One new message type: `notify`** — fire-and-forget, includes a unique `notification_id` for deduplication. Semantically distinct from `request` (no response expected, can be safely dropped/batched).

2. **One new relation property: `accept_notifications`** — an event type filter list negotiated during relation setup. Notification permission is a property of the relation itself, not a separate subscription object.

3. **One new error code: `NOTIFICATION_REJECTED`** — returned when notifications are rate-limited or permission has been revoked.

4. **Delivery via existing channels** — direct HTTP POST or relay fallback, same as requests. No new infrastructure, no broker, no WebSocket.

5. **Lease-based permission expiry** — notification permissions expire after a TTL (default 7 days), must be renewed. Prevents zombie subscriptions from dead agents.

### Key design decisions

- **At-least-once delivery**. Exactly-once across federated agents is impossible (Two Generals Problem). Every notification includes a unique ID for receiver-side deduplication.
- **Standardize the envelope, not the events**. ARP defines the notification structure (notification_id, event type, timestamp, data payload) and a naming convention (`order.shipped`, `payment.received`). Vertical communities define their own event types. ARP only standardizes protocol-level events (`relation.terminated`, `subscription.expiring`).
- **Notification permission is independent of relation state**. You can revoke notification permission without terminating the relation.

### Explicitly deferred beyond v0.7

- Fan-out optimization / relay delegation for high-volume publishers
- Standardized event type registries
- Notification batching/aggregation
- Delivery receipts
- SSE-based real-time streaming

## Prior art considered

| Protocol | Mechanism | What ARP borrows |
|----------|-----------|-----------------|
| A2A | Webhook callbacks OR SSE streaming | Callback model for delivery |
| MCP | JSON-RPC notifications (no `id`) | Distinct notify message type (but more explicit than JSON-RPC's approach) |
| MQTT | Broker-based pub/sub with 3 QoS levels | At-least-once semantics |
| WebSub | Hub-mediated, lease-based subscriptions | Lease-based permission expiry |
| CloudEvents | Standardized event envelope | Envelope structure, not event schemas |
| ActivityPub | POST to recipient's inbox | Delivery via existing inbox (but with proper retry semantics unlike AP) |

## Estimated spec size

2-3 pages. Minimal additions to the protocol.
