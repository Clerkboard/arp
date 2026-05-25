# ARP Roadmap: Settlements (v0.7)

> **Status: PLANNED — Not yet specced. This document captures the design intent for a future version (Section 21).**

## Summary

Settlements lets ARP agents agree on a price and prove a payment happened — without ARP itself transporting the money. ARP carries a signed **quote** and a signed **receipt**; settlement occurs natively on a payment rail (x402, Lightning/L402, card, SEPA, ...). This is the extension §17.3 already anticipates: *"Billing and payments. Layer it as an extension."*

## Motivation

`research/research.md` names the gap directly: *"B2B agent economics — metering, billing, SLAs — are uncharted."* An agent that can discover a stranger, negotiate, and complete a task still has no protocol-level way to be paid for it. Settlements closes that — reusing Completion Records (§13.1), the Agent Card declaration pattern (§12.7), Outcome Records (§13.4), and the extension mechanism (§17.2). No existing flow changes; it is purely additive.

## Design stance: ARP brackets the payment, it does not transport it

This is the defining decision. ARP standardizes two signed artifacts — the **quote** and the **receipt** — and nothing else. Money moves on the rail, directly between buyer and seller, the way that rail already works. ARP never carries rail secrets, account credentials, or card data.

Consequence: settlement messages carry amount + memo + a rail reference — metadata, not bearer secrets. Content encryption (§8.7) is therefore **SHOULD**, not MUST, at the ARP layer; a rail spec **MAY** raise it to MUST for rails whose quote carries a bearer secret (e.g. a card client-secret). Settlements is thereby decoupled from the §8.7 hardening track — neither blocks the other.

The rejected alternative ("ARP transports the settlement message, carrying rail data through the inbox") was discarded because it forces ARP to carry crown-jewel data, reimplements what x402/L402 already do at the endpoint level, and makes §8.7 a hard blocker.

## Planned Design

### New protocol additions

1. **One new Agent Card field: `settlements`** — declares supported rails (rail name + community rail-spec URL + currencies), supported primitives, and a settlement window. Discovery only; mirrors the §12.7 `accountLinking` declaration pattern.

2. **One new signed body shape: `SettlementQuote`** — amount, currency, primitive, per-rail payment targets, `validUntil`, `quoteId`, seller signature. Carried inside a `response`, or inside a `SETTLEMENT_REQUIRED` error body. Not a new message type.

3. **One new Completion Record sub-object: `settlement` (the receipt)** — amount, currency, rail, `railRef`, `quoteId`, `settledAt`. A Completion Record (§13.1) carrying a `settlement` object *is* the receipt — verifiable forever, by anyone, against the rail.

4. **Two conventional capability names: `arp:settlement.quote` and `arp:settlement.paid`** — the first lets a buyer request a quote before committing; the second is the "I paid, here is the rail reference" notification. Both reuse the `request` message type. `arp:settlement.paid` carries only `{quoteId, railRef}`, letting the seller correlate an on-rail payment to the ARP task.

5. **One new error code: `SETTLEMENT_REQUIRED`** — registered in §16; returned with the HTTP 402 status to signal "you must settle to proceed". Its body carries a `SettlementQuote`.

### Key design decisions

- **Standardize the signed claim, not the rail.** ARP defines the quote and receipt envelopes. Rail behavior — how money moves, how an on-rail payment carries the `quoteId` back for correlation — lives in community-maintained rail specs linked from the Agent Card. Same discipline as "standardize the envelope, not the events" for notifications.
- **Two settlement primitives: `prepay` and `postpay`.** Atomicity is not enforced — it is made *provable*. Each primitive produces two Completion Records sharing a `correlationId`, signed in a defined order. A missing second record is a provable unresolved obligation; either side files an Outcome Record (§13.4). The protocol provides evidence; reputation and legal layers do enforcement.
- **No money-movement code in ARP.** x402 and L402 are already endpoint-level HTTP-402 protocols. ARP composes beside them; it does not re-implement them.
- **Spending authority stays out of v0.7.** Wallet-based payment — the agent pays from its own rail wallet, limits enforced by the wallet (session keys, macaroon caveats, ERC-4337 spend limits) — needs nothing from ARP. Charging a human's standing account at a company is Account Linking territory, and is deferred (see below).

### Explicitly deferred beyond v0.7

- **Escrow** — third-party-held settlement with dispute logic. Valuable for trust-minimized transactions between strangers, but adds a third party, timeout handling, and dispute resolution. `prepay` + Outcome Records cover the long tail; revisit as a candidate for a later version.
- **Account-Linking credit / standing-account billing** — requires a payment-scope vocabulary added to §12 (e.g. `settlement.charge:max=X,perTx=Y,window=Z`). A §12 amendment, not a §21 invention.
- FX / currency conversion — rail-spec concern.
- Subscriptions and metered billing as protocol types — expressed as sequences of `postpay` receipts sharing a correlation key, not as new objects.
- Multi-party revenue splits.

## Prior art considered

| Source | Mechanism | What ARP borrows |
|--------|-----------|-----------------|
| x402 (Coinbase) | HTTP 402 + signed payload settled on-rail | The 402 challenge pattern; rail handles money movement |
| L402 (Lightning Labs) | HTTP 402 + macaroon + Lightning invoice | Endpoint-level pay-to-proceed; rail-native settlement |
| AP2 (Google → FIDO) | Signed "Mandate" credentials authorize a payment | Signed quote as an unforgeable, request-bound artifact |
| Agentic Commerce Protocol (OpenAI + Stripe) | Delegated single-use payment token | Confirms quote/receipt separation; rail prescription rejected |
| DKIM | Domain-signed, verifiable-forever artifact | The receipt is a signed claim anyone can verify later |
| HTTP 402 (1999) | Status code with no rail | Lesson: define the challenge, never the rail |

## Estimated spec size

~3 pages. Zero new message types. One Agent Card field, one error code, one body shape, one Completion Record sub-object, two conventional capability names.

## Related follow-ups

1. **§17.3 update** — once §21 lands, the "Billing and payments. Layer it as an extension." line should point to this specification.
2. **§8.7 hardening** — now decoupled from Settlements, but forward secrecy and algorithm agility remain worthwhile as an independent security track.
