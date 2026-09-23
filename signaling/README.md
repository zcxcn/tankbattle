# Iron Embers room signaling

This small Node service keeps a 2–4 player room directory and relays only WebRTC
SDP/ICE messages. It does not relay combat traffic. Run it behind an HTTPS reverse
proxy so the GitHub Pages game can reach it over `wss://`.

## Run

Node 20+ is required. In this directory:

```sh
npm ci --omit=dev
SIGNAL_HOST=127.0.0.1 SIGNAL_PORT=8787 npm start
```

`GET /health` returns room and connected peer counts. The WebSocket endpoint is
`/ws` (the root path is also accepted). `npm test` runs protocol checks.

Environment:

- `SIGNAL_HOST`: listen address, default `127.0.0.1` (appropriate behind a local
  reverse proxy); set `0.0.0.0` only when intentional.
- `SIGNAL_PORT`: listen port, default `8787`.
- `SIGNAL_ALLOWED_ORIGINS`: comma-separated exact browser Origins. Defaults to
  `https://zcxcn.github.io,http://127.0.0.1:5173,http://localhost:5173`.
  Configure any other development or deployment origin explicitly. Non-browser
  clients without an Origin are accepted; Origin is a browser defense, not auth.

The server limits each message to 64 KiB, each connection to 120 messages per
10 seconds, and room creation to six per source address per minute. Room codes
contain 10 random characters from an unambiguous 32-character alphabet. It
allows at most 1024 concurrent rooms by default. Rooms vanish when the host
disconnects; a 30-second ping keeps dead sockets from occupying rooms forever.
For an internet deployment, additionally rate-limit connections at the reverse
proxy and monitor availability. No identity or persistent history is stored.

## WebSocket protocol

All messages are JSON objects. `requestId` is an optional client-generated
string up to 64 characters, echoed on corresponding responses/errors.

| Client sends | Server replies / broadcasts |
| --- | --- |
| `{type:"create",version:1,requestId,maxPlayers:2..4}` | Creator receives `{type:"created",version:1,requestId,roomCode,peerId,hostId,maxPlayers,locked:false,peers:[]}`. |
| `{type:"join",version:1,requestId,roomCode}` | Joiner receives `{type:"joined",version:1,requestId,roomCode,peerId,hostId,maxPlayers,locked,peers:[{peerId,role}]}`. |
| `{type:"ready"}` from the joiner after processing `joined` | Prior peers then receive `{type:"peer-joined",peerId,role:"guest"}`. This acknowledgement prevents a host offer from reaching a browser before its `joined` response. The host does not send `ready`. |
| `{type:"signal",to,data}` | Target receives `{type:"signal",from,data}`. The server accepts object `data` and does not parse SDP/ICE. |
| `{type:"lock",requestId,expectedPeers:[guestPeerId,...]}` (host only) | Server verifies every admitted guest has sent `ready` and the guest ID set exactly matches `expectedPeers`. All peers then receive `{type:"locked",roomCode}`; host response echoes `requestId`. New joins fail with `room-locked`. A race returns `join-in-progress` or `roster-changed` instead, so the host can refresh and retry. |
| `{type:"leave",requestId}` | Sender receives `{type:"left",requestId}`; peers receive `{type:"peer-left",peerId}`. If host leaves, guests receive `{type:"room-closed",reason:"host-left"}`. |

Errors are `{type:"error",requestId?,code,message}`. Missing or incompatible
`version` on create/join receives `version-mismatch`. Room codes are
case-insensitive on input. A WebSocket close has the same effect as `leave`.
Keep the signaling socket open during a match so new ICE candidates and network
reconnects can be exchanged. This service does not include TURN; cross-NAT
connectivity requires separately configured, time-limited TURN credentials.

## J6412 deployment

J6412 runs Ubuntu 24.04. A checksum-verified official Node 22.23.2 archive was
installed under `/home/zcx/opt/` without replacing the system Node. Only the
service source and lockfile were copied to `/home/zcx/tankbattle-signaling/`,
followed by `npm ci --omit=dev`. The included `iron-embers-signaling.service`
is installed as a **user** systemd unit and enabled with lingering. Confirm:

```sh
systemctl --user is-active iron-embers-signaling.service
curl -fsS http://127.0.0.1:8787/health
```

The unrelated WakeWeb service on port 8443 was not changed. A separate
`iron-embers-quick-tunnel.service` uses an official cloudflared binary and
temporarily exposes `127.0.0.1:8787` through a trusted `*.trycloudflare.com`
HTTPS/WSS URL. Retrieve the current URL with:

```sh
journalctl --user -u iron-embers-quick-tunnel.service --no-pager \
  | grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' | tail -1
```

Use the corresponding `wss://…/ws` address in the room page or set
`VITE_SIGNAL_URL` when building GitHub Pages. Quick Tunnel hostnames change
after restart and are intended only for testing. A stable deployment requires
a trusted, fixed WSS endpoint. The current setup has no TURN relay; it cannot
guarantee connectivity through strict NAT or carrier firewalls. Do not put a
TURN long-term secret in the browser bundle.
