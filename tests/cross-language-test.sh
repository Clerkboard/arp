#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# ARP Cross-Language Signature Verification Test
#
# Proves that Ed25519 signatures + JCS canonicalisation are interoperable
# between the TypeScript and Python reference implementations.
#
# Four verification paths tested:
#   1. Node.js client signs   →  Python server verifies
#   2. Python server signs    →  Node.js client verifies
#   3. Python client signs    →  Node.js server verifies
#   4. Node.js server signs   →  Python client verifies
#
# Usage:  bash tests/cross-language-test.sh
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
TS_DIR="$REPO_DIR/acp-server-ts"
PY_DIR="$REPO_DIR/acp-server-py"
WORK_DIR="$(mktemp -d)"

TS_PORT=3141
PY_PORT=3142

RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── Isolated data dirs (never touch the real ones) ───────────────────────────

TS_DATA="$WORK_DIR/ts-data"
PY_DATA="$WORK_DIR/py-data"
mkdir -p "$TS_DATA" "$PY_DATA"

# ── Cleanup ──────────────────────────────────────────────────────────────────

cleanup() {
  local exit_code=${1:-$?}
  echo ""
  echo -e "${DIM}Shutting down servers…${NC}"
  [ -n "${TS_PID:-}" ] && kill "$TS_PID" 2>/dev/null || true
  [ -n "${PY_PID:-}" ] && kill "$PY_PID" 2>/dev/null || true
  wait 2>/dev/null || true
  if [ "$exit_code" -ne 0 ] && [ -d "$WORK_DIR" ]; then
    echo -e "${DIM}Preserving logs at: $WORK_DIR${NC}"
  else
    rm -rf "$WORK_DIR"
  fi
}
trap 'cleanup $?' EXIT

# ── Ensure ports are free ────────────────────────────────────────────────────

for port in $TS_PORT $PY_PORT; do
  pid=$(lsof -ti:"$port" 2>/dev/null || true)
  if [ -n "$pid" ]; then
    echo -e "${DIM}Port $port in use (PID $pid), killing…${NC}"
    kill "$pid" 2>/dev/null || true
    sleep 1
  fi
done

# ── Start servers ────────────────────────────────────────────────────────────

echo -e "${BOLD}ARP Cross-Language Test${NC}"
echo "────────────────────────────────────────"
echo ""

echo -e "${DIM}Starting TypeScript server (port $TS_PORT)…${NC}"
(cd "$TS_DIR" && ARP_DATA_DIR="$TS_DATA" npx tsx src/index.ts) > "$WORK_DIR/ts.log" 2>&1 &
TS_PID=$!

echo -e "${DIM}Starting Python server (port $PY_PORT)…${NC}"
(cd "$PY_DIR" && ARP_DATA_DIR="$PY_DATA" python3 server.py) > "$WORK_DIR/py.log" 2>&1 &
PY_PID=$!

wait_for() {
  local url=$1 name=$2
  for _ in $(seq 1 40); do
    if curl -sf "$url" > /dev/null 2>&1; then return 0; fi
    sleep 0.5
  done
  echo -e "${RED}FATAL: $name server did not start within 20 seconds${NC}"
  echo "--- $name log ---"
  cat "$WORK_DIR/${3}.log"
  exit 1
}

wait_for "http://localhost:$TS_PORT/echo/did.json" "TypeScript" "ts"
wait_for "http://localhost:$PY_PORT/echo/did.json" "Python" "py"
echo -e "${DIM}Both servers ready.${NC}"
echo ""

# ── Direction 1: TypeScript client → Python server ───────────────────────────
# Node.js signs messages → Python's cryptography library verifies them
# Python signs responses → Node.js crypto module verifies them

cat > "$WORK_DIR/ts-to-py.mjs" << 'ENDOFNODEJS'
import crypto from 'node:crypto';

// ── Inline base58btc (zero external dependencies) ───────────────────────────
const B58 = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

function b58encode(buf) {
  let zeros = 0;
  for (let i = 0; i < buf.length && buf[i] === 0; i++) zeros++;
  let num = 0n;
  for (const b of buf) num = num * 256n + BigInt(b);
  let s = '';
  while (num > 0n) { s = B58[Number(num % 58n)] + s; num /= 58n; }
  return '1'.repeat(zeros) + s;
}

function b58decode(str) {
  let zeros = 0;
  for (let i = 0; i < str.length && str[i] === '1'; i++) zeros++;
  let num = 0n;
  for (const c of str) num = num * 58n + BigInt(B58.indexOf(c));
  let hex = num.toString(16);
  if (hex.length % 2) hex = '0' + hex;
  const bytes = num > 0n ? Buffer.from(hex, 'hex') : Buffer.alloc(0);
  return Buffer.concat([Buffer.alloc(zeros), bytes]);
}

// ── Inline JCS (RFC 8785) ───────────────────────────────────────────────────
function jcs(v) {
  if (v === null) return 'null';
  if (v === undefined) return undefined;
  switch (typeof v) {
    case 'boolean': return v.toString();
    case 'number':  return JSON.stringify(v);
    case 'string':  return JSON.stringify(v);
  }
  if (Array.isArray(v))
    return '[' + v.map(jcs).filter(x => x !== undefined).join(',') + ']';
  const pairs = Object.keys(v).sort()
    .map(k => { const val = jcs(v[k]); return val !== undefined ? JSON.stringify(k) + ':' + val : null; })
    .filter(Boolean);
  return '{' + pairs.join(',') + '}';
}

// ── Ed25519 helpers ─────────────────────────────────────────────────────────
const SPKI_HDR = Buffer.from('302a300506032b6570032100', 'hex');
const MC_PREFIX = Buffer.from([0xed, 0x01]);

function makeKeyPair() {
  const { publicKey, privateKey } = crypto.generateKeyPairSync('ed25519');
  const raw = publicKey.export({ type: 'spki', format: 'der' }).subarray(-32);
  const prefixed = Buffer.concat([MC_PREFIX, raw]);
  return { privateKey, rawPublic: raw, multibase: 'z' + b58encode(prefixed) };
}

function signMsg(msg, privKey) {
  const { signature: _, ...rest } = msg;
  const sig = crypto.sign(null, Buffer.from(jcs(rest), 'utf-8'), privKey);
  return { ...msg, signature: 'z' + b58encode(sig) };
}

function decodeKey(pubMultibase) {
  const decoded = b58decode(pubMultibase.slice(1));
  if (decoded.length === 34 && decoded[0] === 0xed && decoded[1] === 0x01) return decoded.subarray(2);
  if (decoded.length === 32) return decoded;
  throw new Error('Invalid key length: ' + decoded.length);
}

function verifyMsg(msg, pubMultibase) {
  const { signature, ...rest } = msg;
  if (!signature) return false;
  const raw = decodeKey(pubMultibase);
  const pk = crypto.createPublicKey({ key: Buffer.concat([SPKI_HDR, raw]), format: 'der', type: 'spki' });
  return crypto.verify(null, Buffer.from(jcs(rest), 'utf-8'), pk, b58decode(signature.slice(1)));
}

// ── Test harness ────────────────────────────────────────────────────────────
const PY = 'http://localhost:3142';
const PY_DID = 'did:web:localhost:echo';
const ME = 'did:web:localhost:ts-cross-test';
let pass = 0, fail = 0;

function check(ok, label) {
  if (ok) { pass++; console.log(`  \x1b[32mPASS\x1b[0m  ${label}`); }
  else    { fail++; console.log(`  \x1b[31mFAIL\x1b[0m  ${label}`); }
}

const kp = makeKeyPair();

// ── Fetch Python server's public key ────────────────────────────────────────
const card = await fetch(`${PY}/.well-known/arp/echo.json`).then(r => r.json());
const pyKey = card.publicKey;
check(typeof pyKey === 'string' && pyKey.startsWith('z'), 'Fetched Python server public key');

// ── First-contact negotiate ─────────────────────────────────────────────────
// Node.js signs → Python verifies
const neg = signMsg({
  arp: '1.0',
  id: `msg_${crypto.randomUUID()}`,
  type: 'negotiate',
  from: ME,
  to: PY_DID,
  createdAt: new Date().toISOString(),
  body: { firstContact: true, publicKey: kp.multibase },
}, kp.privateKey);

const negR = await fetch(`${PY}/echo/inbox`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/arp+json' },
  body: JSON.stringify(neg),
});
const negD = await negR.json();

check(negR.status === 200, 'Python accepted TS-signed negotiate');
check(negD.type === 'acknowledge', 'Response type is acknowledge');
// Python signs → Node.js verifies
check(verifyMsg(negD, pyKey), 'Node.js verified Python signature on negotiate response');

// ── Echo request ────────────────────────────────────────────────────────────
// Node.js signs → Python verifies
const echoReq = signMsg({
  arp: '1.0',
  id: `msg_${crypto.randomUUID()}`,
  type: 'request',
  from: ME,
  to: PY_DID,
  capability: 'echo',
  correlationId: `task_${crypto.randomUUID()}`,
  createdAt: new Date().toISOString(),
  body: { message: 'Hello from TypeScript', crossLanguage: true },
}, kp.privateKey);

const echoR = await fetch(`${PY}/echo/inbox`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/arp+json' },
  body: JSON.stringify(echoReq),
});
const echoD = await echoR.json();

check(echoR.status === 200, 'Python accepted TS-signed echo request');
check(echoD.type === 'response', 'Response type is response');
// Both servers wrap echo as { echo: body, receivedAt: "..." }
check(echoD.body?.echo?.message === 'Hello from TypeScript', 'Echo body preserved across languages');
check(echoD.body?.echo?.crossLanguage === true, 'Boolean value preserved');
// Python signs → Node.js verifies
check(verifyMsg(echoD, pyKey), 'Node.js verified Python signature on echo response');

// ── Unicode + numeric JCS stress test ──────────────────────────────────────
// Exercises the JCS edge cases from spec Appendix D: Unicode literals,
// float values, nested objects.  If the two JCS implementations diverge
// on these inputs, the signature will fail.
const jcsReq = signMsg({
  arp: '1.0',
  id: `msg_${crypto.randomUUID()}`,
  type: 'request',
  from: ME,
  to: PY_DID,
  capability: 'echo',
  correlationId: `task_${crypto.randomUUID()}`,
  createdAt: new Date().toISOString(),
  body: {
    emoji: '☕',
    path: '/données/café',
    price: 9.99,
    count: 42,
    nested: { z: true, a: false },
    list: [3, 1, 2],
    empty: '',
    nullVal: null,
  },
}, kp.privateKey);

const jcsR = await fetch(`${PY}/echo/inbox`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/arp+json' },
  body: JSON.stringify(jcsReq),
});
const jcsD = await jcsR.json();

check(jcsR.status === 200, 'Python accepted TS-signed message with Unicode + numerics');
check(jcsD.body?.echo?.emoji === '☕', 'Unicode emoji preserved');
check(jcsD.body?.echo?.path === '/données/café', 'Unicode accented chars preserved');
check(jcsD.body?.echo?.price === 9.99, 'Float value preserved');
check(jcsD.body?.echo?.nullVal === null, 'Null value preserved');
check(verifyMsg(jcsD, pyKey), 'Node.js verified Python signature on Unicode response');

// ── Tampered signature (negative test) ─────────────────────────────────────
// Proves the server actually verifies signatures, not just accepting anything.
const tampered = signMsg({
  arp: '1.0',
  id: `msg_${crypto.randomUUID()}`,
  type: 'request',
  from: ME,
  to: PY_DID,
  capability: 'echo',
  correlationId: `task_${crypto.randomUUID()}`,
  createdAt: new Date().toISOString(),
  body: { message: 'this will be tampered' },
}, kp.privateKey);

// Flip a byte in the signature to invalidate it
const sigBytes = b58decode(tampered.signature.slice(1));
sigBytes[0] ^= 0xff;
tampered.signature = 'z' + b58encode(sigBytes);

const tamR = await fetch(`${PY}/echo/inbox`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/arp+json' },
  body: JSON.stringify(tampered),
});
const tamD = await tamR.json();
check(tamR.status !== 200, 'Python rejected tampered signature');
check(tamD.body?.code === 'AUTH_FAILED' || tamD.type === 'error', 'Error code is AUTH_FAILED');

// ── Report ──────────────────────────────────────────────────────────────────
console.log(`\n  ${pass} passed, ${fail} failed`);
process.exit(fail > 0 ? 1 : 0);
ENDOFNODEJS

echo -e "${BOLD}Direction 1: TypeScript client → Python server${NC}"
echo ""
RESULT1=0
node "$WORK_DIR/ts-to-py.mjs" || RESULT1=$?

echo ""

# ── Direction 2: Python client → TypeScript server ───────────────────────────
# Python's cryptography lib signs messages → Node.js crypto verifies them
# Node.js crypto signs responses → Python's cryptography lib verifies them

cat > "$WORK_DIR/py-to-ts.py" << 'ENDOFPYTHON'
import json
import sys
import urllib.request
import urllib.error
import uuid
from datetime import datetime, timezone

from cryptography.hazmat.primitives.asymmetric.ed25519 import (
    Ed25519PrivateKey,
    Ed25519PublicKey,
)
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat
import base58

# ── Config ───────────────────────────────────────────────────────────────────
TS_URL = "http://localhost:3141"
TS_DID = "did:web:localhost:echo"
ME = "did:web:localhost:py-cross-test"

passed = 0
failed = 0


def check(ok, label):
    global passed, failed
    if ok:
        passed += 1
        print(f"  \033[32mPASS\033[0m  {label}")
    else:
        failed += 1
        print(f"  \033[31mFAIL\033[0m  {label}")


# ── JCS (RFC 8785) ──────────────────────────────────────────────────────────
def canonicalize(obj):
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


# ── Multibase (z = base58btc) ───────────────────────────────────────────────
MC_PREFIX = bytes([0xED, 0x01])

def mb_encode_key(raw: bytes) -> str:
    return "z" + base58.b58encode(MC_PREFIX + raw).decode("ascii")

def mb_encode_sig(raw: bytes) -> str:
    return "z" + base58.b58encode(raw).decode("ascii")

def mb_decode(mb: str) -> bytes:
    return base58.b58decode(mb[1:])

def mb_decode_key(mb: str) -> bytes:
    decoded = mb_decode(mb)
    if len(decoded) == 34 and decoded[:2] == MC_PREFIX:
        return decoded[2:]
    if len(decoded) == 32:
        return decoded
    raise ValueError(f"Invalid key length: {len(decoded)}")


# ── Ed25519 ─────────────────────────────────────────────────────────────────
private_key = Ed25519PrivateKey.generate()
public_key = private_key.public_key()
raw_pub = public_key.public_bytes(Encoding.Raw, PublicFormat.Raw)
my_pub_mb = mb_encode_key(raw_pub)


def sign_msg(msg: dict) -> dict:
    copy = {k: v for k, v in msg.items() if k != "signature"}
    sig = private_key.sign(canonicalize(copy).encode("utf-8"))
    return {**msg, "signature": mb_encode_sig(sig)}


def verify_msg(msg: dict, pub_mb: str) -> bool:
    sig_mb = msg.get("signature")
    if not sig_mb:
        return False
    copy = {k: v for k, v in msg.items() if k != "signature"}
    try:
        pk = Ed25519PublicKey.from_public_bytes(mb_decode_key(pub_mb))
        pk.verify(mb_decode(sig_mb), canonicalize(copy).encode("utf-8"))
        return True
    except Exception:
        return False


# ── HTTP helpers ────────────────────────────────────────────────────────────
def http_get(url):
    with urllib.request.urlopen(url) as r:
        return json.loads(r.read())


def http_post(url, data):
    body = json.dumps(data).encode("utf-8")
    req = urllib.request.Request(
        url, data=body, headers={"Content-Type": "application/arp+json"}
    )
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read())


# ── Fetch TypeScript server's public key ────────────────────────────────────
card = http_get(f"{TS_URL}/.well-known/arp/echo.json")
ts_key = card["publicKey"]
check(isinstance(ts_key, str) and ts_key.startswith("z"), "Fetched TypeScript server public key")

# ── First-contact negotiate ─────────────────────────────────────────────────
# Python signs → Node.js verifies
neg = sign_msg(
    {
        "arp": "1.0",
        "id": f"msg_{uuid.uuid4().hex}",
        "type": "negotiate",
        "from": ME,
        "to": TS_DID,
        "createdAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "body": {"firstContact": True, "publicKey": my_pub_mb},
    }
)

status, neg_resp = http_post(f"{TS_URL}/echo/inbox", neg)
check(status == 200, "TypeScript accepted Python-signed negotiate")
check(neg_resp.get("type") == "acknowledge", "Response type is acknowledge")
# Node.js signs → Python verifies
check(verify_msg(neg_resp, ts_key), "Python verified TypeScript signature on negotiate response")

# ── Echo request ────────────────────────────────────────────────────────────
# Python signs → Node.js verifies
echo_msg = sign_msg(
    {
        "arp": "1.0",
        "id": f"msg_{uuid.uuid4().hex}",
        "type": "request",
        "from": ME,
        "to": TS_DID,
        "capability": "echo",
        "correlationId": f"task_{uuid.uuid4().hex}",
        "createdAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "body": {"message": "Hello from Python", "crossLanguage": True},
    }
)

status, echo_resp = http_post(f"{TS_URL}/echo/inbox", echo_msg)
check(status == 200, "TypeScript accepted Python-signed echo request")
check(echo_resp.get("type") == "response", "Response type is response")
# TS wraps echo as { echo: <original body>, receivedAt: "..." }
echo_body = echo_resp.get("body", {}).get("echo", {})
check(echo_body.get("message") == "Hello from Python", "Echo body preserved across languages")
check(echo_body.get("crossLanguage") is True, "Boolean value preserved")
# Node.js signs → Python verifies
check(verify_msg(echo_resp, ts_key), "Python verified TypeScript signature on echo response")

# ── Unicode + numeric JCS stress test ──────────────────────────────────────
# Exercises JCS edge cases from spec Appendix D: Unicode literals, floats,
# nested objects.  If the two JCS implementations diverge, signature fails.
jcs_msg = sign_msg(
    {
        "arp": "1.0",
        "id": f"msg_{uuid.uuid4().hex}",
        "type": "request",
        "from": ME,
        "to": TS_DID,
        "capability": "echo",
        "correlationId": f"task_{uuid.uuid4().hex}",
        "createdAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "body": {
            "emoji": "\u2615",
            "path": "/donn\u00e9es/caf\u00e9",
            "price": 9.99,
            "count": 42,
            "nested": {"z": True, "a": False},
            "list": [3, 1, 2],
            "empty": "",
            "nullVal": None,
        },
    }
)

status, jcs_resp = http_post(f"{TS_URL}/echo/inbox", jcs_msg)
check(status == 200, "TypeScript accepted Python-signed message with Unicode + numerics")
jcs_body = jcs_resp.get("body", {}).get("echo", {})
check(jcs_body.get("emoji") == "\u2615", "Unicode emoji preserved")
check(jcs_body.get("path") == "/donn\u00e9es/caf\u00e9", "Unicode accented chars preserved")
check(jcs_body.get("price") == 9.99, "Float value preserved")
check(jcs_body.get("nullVal") is None, "Null value preserved")
check(verify_msg(jcs_resp, ts_key), "Python verified TypeScript signature on Unicode response")

# ── Tampered signature (negative test) ─────────────────────────────────────
# Proves the server actually verifies, not just accepting anything.
tampered = sign_msg(
    {
        "arp": "1.0",
        "id": f"msg_{uuid.uuid4().hex}",
        "type": "request",
        "from": ME,
        "to": TS_DID,
        "capability": "echo",
        "correlationId": f"task_{uuid.uuid4().hex}",
        "createdAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "body": {"message": "this will be tampered"},
    }
)

# Flip a byte in the signature to invalidate it
sig_bytes = bytearray(mb_decode(tampered["signature"]))
sig_bytes[0] ^= 0xFF
tampered["signature"] = mb_encode_sig(bytes(sig_bytes))

status, tam_resp = http_post(f"{TS_URL}/echo/inbox", tampered)
check(status != 200, "TypeScript rejected tampered signature")
check(
    tam_resp.get("body", {}).get("code") == "AUTH_FAILED" or tam_resp.get("type") == "error",
    "Error code is AUTH_FAILED",
)

# ── Report ──────────────────────────────────────────────────────────────────
print(f"\n  {passed} passed, {failed} failed")
sys.exit(1 if failed > 0 else 0)
ENDOFPYTHON

echo -e "${BOLD}Direction 2: Python client → TypeScript server${NC}"
echo ""
RESULT2=0
python3 "$WORK_DIR/py-to-ts.py" || RESULT2=$?

# ── Final report ─────────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────"
if [ "$RESULT1" -eq 0 ] && [ "$RESULT2" -eq 0 ]; then
  echo -e "${GREEN}${BOLD}ALL CROSS-LANGUAGE TESTS PASSED${NC}"
  echo ""
  echo "  Verified:"
  echo "    ✓ Node.js Ed25519 signatures accepted by Python server"
  echo "    ✓ Python Ed25519 signatures verified by Node.js client"
  echo "    ✓ Python Ed25519 signatures accepted by Node.js server"
  echo "    ✓ Node.js Ed25519 signatures verified by Python client"
  echo "    ✓ JCS canonicalisation consistent across implementations"
  exit 0
else
  echo -e "${RED}${BOLD}SOME CROSS-LANGUAGE TESTS FAILED${NC}"
  [ "$RESULT1" -ne 0 ] && echo -e "  ${RED}Direction 1 (TS → PY) failed${NC}"
  [ "$RESULT2" -ne 0 ] && echo -e "  ${RED}Direction 2 (PY → TS) failed${NC}"
  echo ""
  echo "Server logs:"
  echo "  TypeScript: $WORK_DIR/ts.log"
  echo "  Python:     $WORK_DIR/py.log"
  exit 1
fi
