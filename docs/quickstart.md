# Deploy Your First ACP Agent

Get an agent running in under 5 minutes.

## Option A: Using the SDK (recommended)

```bash
npx create-acp-agent my-agent
cd my-agent
npm install
npm start
```

Your agent is now running. Open a second terminal and verify:

```bash
npx acp-verify localhost:3141
```

You should see all 12 checks pass.

### Add your own capabilities

Open `agent.ts` and add handlers:

```typescript
agent.handle('process-order', {
  description: 'Process purchase orders',
  schema: { type: 'object' },
  responseSchema: { type: 'object' },
}, async (msg) => {
  const order = await yourBusinessLogic(msg.body);
  return { orderId: order.id, status: 'confirmed' };
});
```

Each capability is a function. The SDK handles signing, verification, key management, and discovery automatically.

## Option B: Clone a reference server

Pick your language:

```bash
# TypeScript
git clone https://github.com/clerkboard/acp-server-ts
cd acp-server-ts && npm install && npm start

# Python
git clone https://github.com/clerkboard/acp-server-py
cd acp-server-py && pip install -r requirements.txt && python server.py

# Cloudflare Workers
git clone https://github.com/clerkboard/acp-server-cf
cd acp-server-cf && npm install && npm run dev
```

## Go to production

Three things to change:

### 1. Set your domain

```bash
# In .env
ACP_DOMAIN=agents.yourcompany.com
```

### 2. Add DNS records

```
; Point ACP traffic to your server
_acp._tcp.agents.yourcompany.com. 300 IN SRV 10 100 443 acp.yourcompany.com.

; Optional: advertise protocol version
_acp.agents.yourcompany.com. 3600 IN TXT "v=acp1"
```

### 3. Deploy

```bash
# Docker
docker compose up -d

# Railway
railway up

# Render
git push  # auto-deploys via Procfile
```

### Verify your deployment

```bash
npx acp-verify agents.yourcompany.com
```

This checks discovery endpoints, signing, first-contact handshake, and response signatures.

## What you get

Once deployed, your agent has:

- **An address**: `my-agent@agents.yourcompany.com`
- **An identity**: `did:web:agents.yourcompany.com:my-agent` (Ed25519 key pair, generated automatically)
- **Discovery endpoints**: Agent Card at `/.well-known/acp/my-agent.json`, DID document at `/my-agent/did.json`
- **A signed inbox**: `POST /my-agent/inbox` — accepts ACP messages, verifies signatures, enforces first-contact handshake

Other ACP agents can discover yours through DNS, read your capabilities from the Agent Card, and start sending signed messages.

## Next steps

- [Full protocol specification](../spec/acp-rfc.md)
- [SDK documentation](https://github.com/clerkboard/acp-sdk)
- [Verification tool](https://github.com/clerkboard/acp-verify)
