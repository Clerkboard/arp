# Connecting AI Models to ARP

An ARP agent is just an HTTP server that signs messages. The capability handler is where your logic lives — including calling an LLM.

## Claude

```typescript
import { ARPAgent } from '@arp-protocol/sdk';
import Anthropic from '@anthropic-ai/sdk';

const claude = new Anthropic(); // uses ANTHROPIC_API_KEY env var
const agent = new ARPAgent({ name: 'assistant', domain: 'localhost' });

agent.handle('ask', {
  description: 'Ask a question, get an AI-powered answer',
  schema: {
    type: 'object',
    properties: { question: { type: 'string' } },
    required: ['question'],
  },
  responseSchema: { type: 'object' },
}, async (msg) => {
  const response = await claude.messages.create({
    model: 'claude-sonnet-4-20250514',
    max_tokens: 1024,
    messages: [{ role: 'user', content: msg.body.question as string }],
  });
  return { answer: response.content[0].text };
});

agent.listen();
```

```bash
npm install @arp-protocol/sdk @anthropic-ai/sdk
ANTHROPIC_API_KEY=sk-... npm start
```

## OpenAI

```typescript
import { ARPAgent } from '@arp-protocol/sdk';
import OpenAI from 'openai';

const openai = new OpenAI(); // uses OPENAI_API_KEY env var
const agent = new ARPAgent({ name: 'assistant', domain: 'localhost' });

agent.handle('ask', {
  description: 'Ask a question, get an AI-powered answer',
  schema: {
    type: 'object',
    properties: { question: { type: 'string' } },
    required: ['question'],
  },
  responseSchema: { type: 'object' },
}, async (msg) => {
  const response = await openai.chat.completions.create({
    model: 'gpt-4o',
    messages: [{ role: 'user', content: msg.body.question as string }],
  });
  return { answer: response.choices[0].message.content };
});

agent.listen();
```

## Multiple capabilities, one model

A single agent can expose several capabilities backed by the same LLM with different system prompts:

```typescript
const agent = new ARPAgent({ name: 'support', domain: 'agents.mycompany.com' });

agent.handle('answer-question', {
  description: 'Answer customer questions about our products',
  schema: { type: 'object' },
  responseSchema: { type: 'object' },
}, async (msg) => {
  const response = await claude.messages.create({
    model: 'claude-sonnet-4-20250514',
    max_tokens: 1024,
    system: 'You are a customer support agent for MyCompany. Answer based on our product catalog.',
    messages: [{ role: 'user', content: JSON.stringify(msg.body) }],
  });
  return { answer: response.content[0].text };
});

agent.handle('summarize-ticket', {
  description: 'Summarize a support ticket into key points',
  schema: { type: 'object' },
  responseSchema: { type: 'object' },
}, async (msg) => {
  const response = await claude.messages.create({
    model: 'claude-sonnet-4-20250514',
    max_tokens: 512,
    system: 'Summarize the support ticket into 3-5 bullet points.',
    messages: [{ role: 'user', content: JSON.stringify(msg.body) }],
  });
  return { summary: response.content[0].text };
});

agent.listen();
```

## Agent-to-agent with AI reasoning

The real power of ARP: an AI agent that talks to other ARP agents. Agent A receives a request, uses Claude to decide what to do, then calls Agent B over ARP.

```typescript
agent.handle('fulfill-order', {
  description: 'Process an order, checking inventory with a partner agent',
  schema: { type: 'object' },
  responseSchema: { type: 'object' },
}, async (msg) => {
  // 1. Ask Claude to analyze the order
  const analysis = await claude.messages.create({
    model: 'claude-sonnet-4-20250514',
    max_tokens: 1024,
    system: 'Analyze this order. Extract the list of SKUs and quantities needed.',
    messages: [{ role: 'user', content: JSON.stringify(msg.body) }],
  });

  // 2. Call the inventory agent over ARP (standard HTTP + signing)
  // Your agent signs and sends a request to the partner's inbox
  // The partner verifies your signature and responds

  // 3. Return the result
  return {
    status: 'processed',
    analysis: analysis.content[0].text,
  };
});
```

The pattern is always the same: receive ARP message, call your AI, return the result. ARP handles the identity, signing, and trust. The AI handles the reasoning.
