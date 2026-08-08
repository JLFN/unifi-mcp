# unifi-mcp — UniFi Network API for AI assistants

An MCP server that gives AI assistants the full UniFi Network API v10.4.57
(developer.ui.com) — diagnostics, security review, firewall management,
clients, devices, and more — through one stdio server. It is safe by
default: the server starts in **readonly mode**, so diagnostics and
inventory can never break anything, and write operations are only enabled
when you explicitly opt in.

- **Diagnostics** — sites, devices, clients, WANs, device statistics,
  pending adoptions, LAGs, MC-LAG domains, switch stacks.
- **Security review** — firewall policies and zones, ACL rules, DNS
  policies, traffic matching lists, VPN servers and tunnels.
- **Read/write when you want it** — firewall and ACL changes, client
  block/unblock, device and port actions (restart, power-cycle), adopt and
  remove devices, network and DNS policy changes.
- **Full surface** — every endpoint in the Network OpenAPI spec has a
  dedicated tool, plus a generic `unifi_request` passthrough for anything
  new or unusual.
- **Safety gate** — in readonly mode every mutating tool is refused before
  any HTTP request is sent to the controller. Nothing can break.

## How it talks to UniFi

The server speaks the Network API v10.4.57 over HTTPS, authenticating with
an `X-API-KEY` header. API keys are generated at unifi.ui.com. The base
URL is one of the two servers from the OpenAPI spec:

- Cloud via the connector: `https://api.ui.com/v1/connector/consoles/{consoleId}/proxy/network/integration`
- On-prem console: `https://{controllerIp}/proxy/network/integration`

Responses are the API's own JSON envelopes (`{ "data": [...], "totalCount": n }`)
passed through untouched.

## Installation

Build with the standard builder (produces `bin/unifi-mcp`):

```console
bash /data/build/linux/build.sh -p /data/unifi-mcp-rs
```

or directly with cargo for development:

```console
cargo build --release
```

## Configure with Open Grok

Add the server to `~/.opengrok/config.toml`:

```toml
[mcp_servers.unifi-mcp]
command = "unifi-mcp"
enabled = true
```

Set the environment (a wrapper script or your shell profile):

```text
UNIFI_API_BASE=https://api.ui.com/v1/connector/consoles/CONSOLE_ID/proxy/network/integration
UNIFI_API_KEY=your-api-key-from-unifi.ui.com
UNIFI_MODE=readonly
```

Refresh the MCP list with `/mcps` (press `r`) or restart, and the tools are
available. The repository also ships an Open Grok skill at
`skills/unifi-mcp/SKILL.md`; install it with:

```console
cp -r skills/unifi-mcp ~/.opengrok/skills/unifi-mcp
```

## Environment variables

| Variable | Required | Default | Meaning |
| --- | --- | --- | --- |
| `UNIFI_API_BASE` | recommended | — | Network API base URL (cloud connector or on-prem). If missing, the server still starts and tools report what to set. |
| `UNIFI_API_KEY` | recommended | — | X-API-KEY credential from unifi.ui.com. If missing, the server still starts and tools report what to set. |
| `UNIFI_MODE` | no | `readonly` | `readonly` (diagnostics only) or `readwrite`. |
| `UNIFI_INSECURE` | no | off | `1`/`true`/`yes` to skip TLS certificate verification. Only for self-signed on-prem controllers. |
| `UNIFI_TIMEOUT` | no | `30` | HTTP request timeout in seconds. |

## Tools

| Tool | Answers |
| --- | --- |
| `unifi_status` | What mode and base URL is the server using? |
| `unifi_get_info` | What version is the Network application? |
| `unifi_list_sites` | Which sites exist (site_id needed by most tools)? |
| `unifi_list_devices` / `unifi_get_device` | Which devices are adopted, and their full state? |
| `unifi_get_device_statistics` | What are the live stats of one device? |
| `unifi_list_pending_devices` | Which devices are waiting for adoption? |
| `unifi_list_clients` / `unifi_get_client` | Who is connected, and how? |
| `unifi_list_networks` / `unifi_get_network` / `unifi_get_network_references` | Networks, VLANs, DHCP, and what depends on them. |
| `unifi_list_wans` | Uplink/WAN state. |
| `unifi_list_firewall_policies` / `unifi_get_firewall_policy` | The firewall rule set. |
| `unifi_list_firewall_zones` / `unifi_get_firewall_zone` | Firewall zones and custom zones. |
| `unifi_list_acl_rules` / `unifi_get_acl_rule` | ACL rules, including blocked clients. |
| `unifi_list_dns_policies` / `unifi_get_dns_policy` | DNS filtering policies. |
| `unifi_list_traffic_matching_lists` / `unifi_get_traffic_matching_list` | Reusable address/domain/port groups. |
| `unifi_list_vpn_servers` / `unifi_list_vpn_tunnels` | VPN endpoints and tunnels. |
| `unifi_list_wifi_broadcasts` / `unifi_get_wifi_broadcast` | SSIDs and wireless config. |
| `unifi_list_vouchers` / `unifi_get_voucher` | Hotspot vouchers. |
| `unifi_list_lags` / `unifi_get_lag` | Link aggregation groups. |
| `unifi_list_mclag_domains` / `unifi_get_mclag_domain` | MC-LAG domains. |
| `unifi_list_switch_stacks` / `unifi_get_switch_stack` | Switch stacks. |
| `unifi_list_radius_profiles` / `unifi_list_device_tags` | Supporting resources. |
| `unifi_list_countries` / `unifi_list_dpi_applications` / `unifi_list_dpi_categories` | Reference data. |
| `unifi_block_client` / `unifi_unblock_client` | Block or unblock a client by MAC (writes). |
| `unifi_device_action` / `unifi_port_action` / `unifi_client_action` | Restart, power-cycle, guest auth (writes). |
| `unifi_create_firewall_policy` / `unifi_update_firewall_policy` / `unifi_patch_firewall_policy` / `unifi_delete_firewall_policy` | Firewall policy changes (writes). |
| `unifi_update_firewall_policy_ordering` | Reorder policies (write). |
| `unifi_create_firewall_zone` / `unifi_update_firewall_zone` / `unifi_delete_firewall_zone` | Firewall zone changes (writes). |
| `unifi_create_acl_rule` / `unifi_update_acl_rule` / `unifi_delete_acl_rule` / `unifi_update_acl_rule_ordering` | ACL changes (writes). |
| `unifi_create_network` / `unifi_update_network` / `unifi_delete_network` | Network changes (writes). |
| `unifi_create_dns_policy` / `unifi_update_dns_policy` / `unifi_delete_dns_policy` | DNS policy changes (writes). |
| `unifi_adopt_devices` / `unifi_remove_device` | Adopt or unadopt devices (writes). |
| `unifi_create_wifi_broadcast` / `unifi_update_wifi_broadcast` / `unifi_delete_wifi_broadcast` | SSID changes (writes). |
| `unifi_create_vouchers` / `unifi_delete_voucher` / `unifi_delete_vouchers` | Hotspot voucher changes (writes). |
| `unifi_create_traffic_matching_list` / `unifi_update_traffic_matching_list` / `unifi_delete_traffic_matching_list` | Traffic group changes (writes). |
| `unifi_request` | Any raw Network API call not covered above. |

Write tools return a clear refusal error in readonly mode and never touch
the controller.

## Example

Diagnosing a site and its firewall posture:

1. `unifi_status` — confirms `readonly` mode.
2. `unifi_list_sites` — get the site id.
3. `unifi_list_devices(site_id)` and `unifi_get_device_statistics(site_id, device_id)` — device health.
4. `unifi_list_clients(site_id)` — who is connected.
5. `unifi_list_firewall_policies(site_id)` and `unifi_list_acl_rules(site_id)` — security review.

To block a rogue client, restart the server with `UNIFI_MODE=readwrite`,
then `unifi_block_client(site_id, mac)`. The mode gate is the only switch
between "look" and "touch".

## Development

```console
cargo test --all-targets
```

Tests mock the UniFi API in-process (wiremock) and cover the safety gate:
readonly mode refuses writes before any network traffic, readwrite mode
sends the authenticated request, URL building, error mapping, and the
block/unblock rule shapes.

To probe the server over stdio:

```console
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"probe","version":"0.1"}}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  | bin/unifi-mcp
```

## Known limitations

- Targets the documented Network API v10.4.57 surface. The legacy local
  API (`/api/s/default/...` endpoints such as stat/health and events) is
  not part of this contract and is not covered.
- Cloud access requires a console id in the base URL (or an on-prem
  controller base URL).
- `UNIFI_INSECURE` disables TLS verification: only use it for self-signed
  on-prem controllers on a trusted network.

## License

Licensed under either of [Apache License, Version
2.0](LICENSE-APACHE) or [MIT license](LICENSE-MIT) at your option.
