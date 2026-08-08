---
name: unifi-mcp
description: >
  Query and manage a UniFi Network application through the unifi-mcp MCP
  server (UniFi Network API v10.4.57): diagnostics (devices, clients, WANs,
  statistics), security review (firewall policies, ACL rules, DNS policies,
  VPN), and optional read/write operations (block clients, change firewall
  rules, restart devices). The server defaults to readonly mode so nothing
  can break; write tools need UNIFI_MODE=readwrite.
argument-hint: "[question about unifi network, firewall, clients, devices]"
when-to-use: unifi, unifi network, unifi firewall, firewall policy, acl rule, block client, unifi device, unifi diagnostics, wifi broadcast, unifi vpn, /unifi-mcp
user-invocable: true
---

# Unifi-mcp — UniFi Network API

Answer questions about and manage a UniFi Network application with the
unifi-mcp MCP server (project /data/unifi-mcp-rs, binary unifi-mcp). It
talks to the UniFi Network API v10.4.57 with an X-API-KEY header and covers
the full documented endpoint surface, plus a generic unifi_request
passthrough. Tools are invoked as unifi-mcp__unifi_<name>.

## Safety model (read this first)

The server starts in readonly mode (UNIFI_MODE=readonly). In readonly mode:

- Diagnostics, inventory, and security review tools all work.
- Every write tool returns a refusal error and never contacts the
  controller: "refused: the server is in readonly mode".

Write tools (blocking clients, firewall/ACL/DNS/network changes, device and
port actions, adopt/remove, voucher generation) only work when the server
was started with UNIFI_MODE=readwrite. The mode is fixed at process start;
there is no runtime switch. If a write is refused, tell the user the server
must be restarted with UNIFI_MODE=readwrite, and confirm before any change
touches a live network.

## When to Use

- "Diagnose my UniFi network" / "is a device down?" / "who is connected?"
- "Review the firewall" / "which firewall policies exist?" / "what is blocked?"
- "Block this client" / "unblock a device by MAC"
- "Restart a device" / "power-cycle a port"
- "Check WAN/uplink" / "VPN tunnel state" / "pending adoptions"
- Any question about sites, networks, SSIDs, DNS policies, ACL rules, or vouchers

## The Tools

Diagnostics and inventory (read-only):

1. unifi_status — mode, base URL, whether a key is set. Call first.
2. unifi_get_info — Network application version and capabilities.
3. unifi_list_sites — sites; every site tool needs the site_id.
4. unifi_list_devices / unifi_get_device / unifi_get_device_statistics — adopted devices and their live stats.
5. unifi_list_pending_devices — devices waiting for adoption.
6. unifi_list_clients / unifi_get_client — connected clients and details.
7. unifi_list_networks / unifi_get_network / unifi_get_network_references — networks, VLANs, DHCP, dependencies.
8. unifi_list_wans — WAN/uplink state.
9. unifi_list_lags / unifi_get_lag, unifi_list_mclag_domains / unifi_get_mclag_domain, unifi_list_switch_stacks / unifi_get_switch_stack — switching diagnostics.
10. unifi_list_wifi_broadcasts / unifi_get_wifi_broadcast — SSIDs.
11. unifi_list_vouchers / unifi_get_voucher, unifi_list_radius_profiles, unifi_list_device_tags, unifi_list_countries, unifi_list_dpi_applications, unifi_list_dpi_categories — supporting resources.

Security review (read-only):

12. unifi_list_firewall_policies / unifi_get_firewall_policy / unifi_get_firewall_policy_ordering — the firewall rule set.
13. unifi_list_firewall_zones / unifi_get_firewall_zone — zones used by policies.
14. unifi_list_acl_rules / unifi_get_acl_rule / unifi_get_acl_rule_ordering — ACLs, including blocked clients.
15. unifi_list_dns_policies / unifi_get_dns_policy — DNS filtering.
16. unifi_list_traffic_matching_lists / unifi_get_traffic_matching_list — address/domain/port groups.
17. unifi_list_vpn_servers / unifi_list_vpn_tunnels — VPN posture.

Write (refused in readonly mode):

18. unifi_block_client / unifi_unblock_client — block or unblock a client by MAC via MAC ACL rules.
19. unifi_device_action / unifi_port_action / unifi_client_action — RESTART, POWER_CYCLE, guest auth, etc.
20. unifi_create_firewall_policy / unifi_update_firewall_policy / unifi_patch_firewall_policy / unifi_delete_firewall_policy / unifi_update_firewall_policy_ordering.
21. unifi_create_firewall_zone / unifi_update_firewall_zone / unifi_delete_firewall_zone.
22. unifi_create_acl_rule / unifi_update_acl_rule / unifi_delete_acl_rule / unifi_update_acl_rule_ordering.
23. unifi_create_network / unifi_update_network / unifi_delete_network.
24. unifi_create_dns_policy / unifi_update_dns_policy / unifi_delete_dns_policy.
25. unifi_adopt_devices / unifi_remove_device.
26. unifi_create_wifi_broadcast / unifi_update_wifi_broadcast / unifi_delete_wifi_broadcast.
27. unifi_create_vouchers / unifi_delete_voucher / unifi_delete_vouchers.
28. unifi_create_traffic_matching_list / unifi_update_traffic_matching_list / unifi_delete_traffic_matching_list.

Catch-all:

29. unifi_request — any raw Network API call: method, path, optional query and body. GET is always allowed; write methods need readwrite mode. Use for endpoints added after this server was built.

## Workflow

1. Orient: unifi_status (confirm readonly), unifi_get_info, unifi_list_sites.
2. Diagnose: unifi_list_devices, unifi_get_device_statistics, unifi_list_clients, unifi_list_wans.
3. Security review: unifi_list_firewall_policies, unifi_list_acl_rules, unifi_list_dns_policies, unifi_list_firewall_zones.
4. Change (only with UNIFI_MODE=readwrite and user confirmation): unifi_block_client, firewall/ACL changes, device actions.

## Rules

- The server is readonly by default. If a write tool refuses, do not work
  around it; tell the user to restart with UNIFI_MODE=readwrite.
- Confirm with the user before any write that affects a live network
  (firewall rules, blocking clients, device restarts, deletions).
- Before deleting or changing a network, call unifi_get_network_references
  to see what depends on it.
- Before reordering firewall policies, fetch the ordering first.
- MAC addresses compare case- and separator-insensitively; unifi_unblock_client
  deletes every MAC BLOCK rule for the address.
- If the server is not listed, check it with: open-grok mcp doctor unifi-mcp.
- The API targets the v10.4.57 Network contract; legacy local API endpoints
  (stat/health/events) are not part of it — use unifi_request only for
  documented v1 paths.

## Example

User: "Is anything wrong with my network and who is connected?"

Flow: unifi_status to confirm readonly mode; unifi_list_sites for the site
id; unifi_list_devices(site_id) and unifi_get_device_statistics for device
health; unifi_list_clients(site_id) for who is connected; unifi_list_wans
for the uplink; unifi_list_firewall_policies and unifi_list_acl_rules for a
quick security posture check.

User: "Block that device aa:bb:cc:dd:ee:ff."

Flow: confirm the server is running with UNIFI_MODE=readwrite and the user
really wants it blocked; then unifi_block_client(site_id,
mac_address="aa:bb:cc:dd:ee:ff"); verify with unifi_list_acl_rules.
