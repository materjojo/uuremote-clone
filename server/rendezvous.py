"""Independent rendezvous for the clone. Never relays media or contacts NetEase.

Start behind HTTPS (or on a private LAN/tailnet): python -m server.rendezvous
All credentials are body/header values, never URL query parameters. The broker
is trusted for SDP authentication; DTLS/SRTP and SCTP carry peer media/data.
"""
import asyncio
import hashlib
import hmac
import os
import re
import secrets
import time
from dataclasses import dataclass, field
from aiohttp import web

ID = re.compile(r"^[a-zA-Z0-9-]{16,64}$")
KEY = re.compile(r"^[a-zA-Z0-9_-]{32,128}$")
STATE = web.AppKey("state", object)


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


def valid(value, pattern):
    if not isinstance(value, str) or not pattern.fullmatch(value):
        raise web.HTTPBadRequest(text="Invalid identity or key")
    return value


@dataclass
class Device:
    key_hash: str
    pair_hash: str
    name: str
    platform: str
    seen: float


@dataclass
class Session:
    target: str
    token_hash: str
    name: str
    platform: str
    touched: float
    accepted: bool = False
    closed: bool = False
    events: dict = field(default_factory=lambda: {"host": [], "controller": []})
    next_seq: dict = field(default_factory=lambda: {"host": 0, "controller": 0})
    sent_ids: dict = field(default_factory=dict)
    changed: asyncio.Event = field(default_factory=asyncio.Event)


class Broker:
    def __init__(self, clock=time.monotonic):
        self.devices = {}
        self.sessions = {}
        self.clock = clock

    def prune(self):
        now = self.clock()
        self.sessions = {k: v for k, v in self.sessions.items() if now - v.touched < 600}
        self.devices = {k: v for k, v in self.devices.items() if now - v.seen < 86400}

    def emit(self, session, recipient, kind, data):
        events = session.events[recipient]
        # Never silently drop an offer/candidate. A slow/offline peer must retry
        # a new session instead of consuming unbounded server memory.
        if len(events) >= 512:
            raise web.HTTPTooManyRequests(text="Session mailbox full")
        session.next_seq[recipient] += 1
        events.append({"seq": session.next_seq[recipient], "type": kind, "data": data})
        session.changed.set()

    def auth(self, request):
        session = self.sessions.get(request.match_info["session"])
        if session is None:
            raise web.HTTPNotFound(text="Session expired")
        credential = request.headers.get("Authorization", "").removeprefix("Bearer ")
        hashed = digest(credential)
        device = self.devices.get(session.target)
        if hmac.compare_digest(hashed, session.token_hash):
            role = "controller"
        elif device and hmac.compare_digest(hashed, device.key_hash):
            role = "host"
        else:
            raise web.HTTPUnauthorized()
        session.touched = self.clock()
        return session, role


async def body(request):
    try:
        data = await request.json()
    except (ValueError, UnicodeError):
        raise web.HTTPBadRequest(text="JSON required")
    if not isinstance(data, dict):
        raise web.HTTPBadRequest(text="JSON object required")
    return data


def description(data):
    name, platform = data.get("name", ""), data.get("platform", "")
    if not isinstance(name, str) or not 1 <= len(name.strip()) <= 100:
        raise web.HTTPBadRequest(text="Device name required")
    if platform not in ("windows", "mac", "android", "test"):
        raise web.HTTPBadRequest(text="Unknown platform")
    return name.strip(), platform


async def register(request):
    b = request.app[STATE]
    b.prune()
    data = await body(request)
    identity, key = valid(data.get("id"), ID), valid(data.get("key"), KEY)
    name, platform = description(data)
    pair_key = valid(data.get("pair_key"), KEY)
    existing = b.devices.get(identity)
    if existing and not hmac.compare_digest(existing.key_hash, digest(key)):
        raise web.HTTPForbidden(text="Identity already registered")
    if not existing and len(b.devices) >= 10000:
        raise web.HTTPServiceUnavailable(text="Device capacity reached")
    b.devices[identity] = Device(digest(key), digest(pair_key), name, platform, b.clock())
    return web.json_response({"id": identity})


async def inbox(request):
    b = request.app[STATE]
    b.prune()
    identity = request.match_info["device"]
    device = b.devices.get(identity)
    key = request.headers.get("Authorization", "").removeprefix("Bearer ")
    if not device or not hmac.compare_digest(device.key_hash, digest(key)):
        raise web.HTTPUnauthorized()
    device.seen = b.clock()
    return web.json_response({"requests": [
        {"id": identity, "name": s.name, "platform": s.platform}
        for identity, s in b.sessions.items()
        if s.target == request.match_info["device"] and not s.accepted and not s.closed
    ]})


async def connect(request):
    b = request.app[STATE]
    b.prune()
    data = await body(request)
    identity, key = valid(data.get("target"), ID), valid(data.get("key"), KEY)
    name, platform = description(data)
    device = b.devices.get(identity)
    # Same response for unknown IDs/invalid invitation keys.
    if not device or not hmac.compare_digest(device.pair_hash, digest(key)):
        raise web.HTTPForbidden(text="Invalid invitation")
    if b.clock() - device.seen > 15:
        raise web.HTTPConflict(text="Host is offline; enable receiving on that device")
    if len(b.sessions) >= 10000 or sum(s.target == identity and not s.closed for s in b.sessions.values()) >= 8:
        raise web.HTTPTooManyRequests(text="Too many connection requests")
    session_id, token = secrets.token_hex(16), secrets.token_urlsafe(32)
    b.sessions[session_id] = Session(identity, digest(token), name, platform, b.clock())
    return web.json_response({"id": session_id, "token": token})


async def signal(request):
    b = request.app[STATE]
    s, role = b.auth(request)
    data = await body(request)
    kind, payload = data.get("type"), data.get("data", {})
    message_id = data.get("message_id")
    if not isinstance(message_id, str) or not ID.fullmatch(message_id):
        raise web.HTTPBadRequest(text="message_id required for retry deduplication")
    if not isinstance(payload, dict):
        raise web.HTTPBadRequest(text="Signal data must be an object")
    marker = (role, message_id)
    if marker in s.sent_ids:
        return web.json_response({"ok": True})
    if s.closed:
        raise web.HTTPGone(text="Session closed")
    other = "controller" if role == "host" else "host"
    if kind == "accept" and role == "host" and not s.accepted:
        s.accepted = True
        b.emit(s, "controller", "accepted", {})
    elif kind == "close":
        b.emit(s, other, "close", {})
        s.closed = True
    elif s.accepted and ((kind == "offer" and role == "controller") or
                         (kind == "answer" and role == "host") or kind in ("candidate", "restart")):
        b.emit(s, other, kind, payload)
    else:
        raise web.HTTPConflict(text="Consent required or invalid signal role")
    s.sent_ids[marker] = True
    if len(s.sent_ids) > 2048:
        s.closed = True
        raise web.HTTPTooManyRequests(text="Session signal limit reached")
    return web.json_response({"ok": True})


async def poll(request):
    b = request.app[STATE]
    s, role = b.auth(request)
    try:
        after = int(request.query.get("after", "0"))
        if after < 0 or after > s.next_seq[role]:
            raise ValueError()
    except ValueError:
        raise web.HTTPBadRequest(text="Invalid cursor")
    s.events[role] = [e for e in s.events[role] if e["seq"] > after]
    if not s.events[role] and not s.closed:
        s.changed.clear()
        try:
            await asyncio.wait_for(s.changed.wait(), 10)
        except asyncio.TimeoutError:
            pass
    return web.json_response({"events": s.events[role], "closed": s.closed})


@web.middleware
async def no_cache(request, handler):
    response = await handler(request)
    response.headers["Cache-Control"] = "no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
    return response


def create_app(clock=time.monotonic):
    app = web.Application(client_max_size=128 * 1024, middlewares=[no_cache])
    app[STATE] = Broker(clock)
    app.add_routes([
        web.get("/health", lambda _: web.json_response({"protocol": 1})),
        web.post("/v1/register", register),
        web.get("/v1/devices/{device}/inbox", inbox),
        web.post("/v1/connect", connect),
        web.post("/v1/sessions/{session}/signals", signal),
        web.get("/v1/sessions/{session}/signals", poll),
    ])
    return app


if __name__ == "__main__":
    web.run_app(create_app(), host=os.getenv("UU_BIND", "127.0.0.1"),
                port=int(os.getenv("UU_PORT", "8080")), access_log=None)
