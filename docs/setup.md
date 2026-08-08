# unifi-mcp setup guide

How to connect the unifi-mcp MCP server to your UniFi Network application,
safely, in a few minutes.

## 1. Get an API key

The Network API authenticates with an API key sent in the `X-API-KEY`
header. Generate the key in the UniFi cloud:

1. Go to unifi.ui.com and sign in.
2. Open Settings, then Admin & Users.
3. Under API Keys, create a new key with the access you need.
   - For diagnostics only: a read-only scoped key is enough and safest.
   - For read/write work: the key needs write access to the Network
     application.
4. Copy the key. It is shown once.

## 2. Find your API base URL

The Network API v10.4.57 is served from two places (see the OpenAPI spec,
`servers`):

- Cloud via the connector (no VPN needed):

  https://api.ui.com/v1/connector/consoles/{consoleId}/proxy/network/integration

  The console id is the identifier of your UniFi OS console as shown by
  the Site Manager Connector.

- On-prem controller:

  https://{controllerIp}/proxy/network/integration

  The controller must run a Network version that exposes the v10.4.57 API
  (or a compatible version).

## 3. Run the server

Build once (or use the shipped `bin/unifi-mcp`):

```console
bash /data/build/linux/build.sh -p /data/unifi-mcp-rs
```

Run it with the environment set:

```text
UNIFI_API_BASE=https://api.ui.com/v1/connector/consoles/CONSOLE_ID/proxy/network/integration
UNIFI_API_KEY=your-key
UNIFI_MODE=readonly
bin/unifi-mcp
```

The server starts in readonly mode by default. Diagnostics, inventory, and
security review work immediately; every write tool returns a refusal error
until you restart with `UNIFI_MODE=readwrite`.

## 4. Register with Open Grok

Add to `~/.opengrok/config.toml`:

```toml
[mcp_servers.unifi-mcp]
command = "unifi-mcp"
enabled = true
```

If you need environment variables inside Open Grok's process, wrap the
binary in a small launcher script that exports them, or run the server
through a shell command:

```toml
[mcp_servers.unifi-mcp]
command = "env"
args = [
  "UNIFI_API_BASE=https://api.ui.com/v1/connector/consoles/CONSOLE_ID/proxy/network/integration",
  "UNIFI_API_KEY=your-key",
  "UNIFI_MODE=readonly",
  "unifi-mcp",
]
enabled = true
```

Refresh the MCP list with `/mcps` (press `r`) or restart Open Grok. Verify
the server with:

```console
open-grok mcp doctor unifi-mcp
```

## 5. Verify with a probe

The first tool to call is `unifi_status`, which reports the mode, the base
URL, and whether a key is set. Then `unifi_get_info` verifies that the key
actually works against the application.

## 6. Switching to read/write

Write operations (firewall changes, blocking clients, device actions,
adopting/removing devices, network changes) are refused in readonly mode.
To enable them, restart the server with:

```text
UNIFI_MODE=readwrite
```

Keep the server in readonly mode unless you are actively performing a
change. There is no runtime mode switch on purpose: the safety boundary is
a process restart, which is hard to do by accident.

## Troubleshooting

- `unifi_status` shows `api_key_set: false` — the key is not set or is
  empty; fix `UNIFI_API_KEY`.
- `unifi_get_info` returns an HTTP 401 — the key is invalid or lacks
  access; regenerate it at unifi.ui.com.
- HTTP 404 — the base URL does not match the v10.4.57 server layout; check
  the console id or the on-prem path.
- Self-signed on-prem controller — set `UNIFI_INSECURE=1` only if you
  accept the TLS trust trade-off on a trusted network.
