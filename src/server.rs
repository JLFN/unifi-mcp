//! unifi-mcp tool definitions.
//!
//! The server exposes the UniFi Network API v10.4.57 (developer.ui.com)
//! over MCP stdio. Every tool returns a JSON string: the API response body
//! pretty-printed, or `{ "error": ... }` on failure.
//!
//! Safety model: the server starts in readonly mode by default (the
//! diagnostics posture). In readonly mode every mutating tool is refused
//! before any HTTP request is made. Set UNIFI_MODE=readwrite to enable the
//! write tools (firewall changes, ACL changes, device/client actions,
//! adopt/remove, network and DNS policy changes).

use std::sync::Arc;

use anyhow::Result;
use rmcp::{
    ServerHandler,
    handler::server::{router::tool::ToolRouter, wrapper::Parameters},
    model::{ServerCapabilities, ServerInfo},
    schemars, tool, tool_handler, tool_router,
};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

use crate::client::UniFiClient;

// ---------------------------------------------------------------------------
// Request types
// ---------------------------------------------------------------------------

#[derive(Debug, Serialize, Deserialize, schemars::JsonSchema)]
struct PageRequest {
    /// Zero-based pagination offset. Default 0.
    offset: Option<u32>,
    /// Maximum number of items to return, 1..=200. Default 25.
    limit: Option<u32>,
    /// Filter expression as a JSON string, e.g. {"name": {"eq": "default"}}.
    /// See the Network API filtering guide (developer.ui.com/network/.../filtering).
    filter: Option<String>,
}

#[derive(Debug, Serialize, Deserialize, schemars::JsonSchema)]
struct SitePageRequest {
    /// Site ID (UUID), from unifi_list_sites.
    site_id: String,
    /// Zero-based pagination offset. Default 0.
    offset: Option<u32>,
    /// Maximum number of items to return, 1..=200. Default 25.
    limit: Option<u32>,
    /// Filter expression as a JSON string, e.g. {"name": {"eq": "default"}}.
    filter: Option<String>,
}

#[derive(Debug, Serialize, Deserialize, schemars::JsonSchema)]
struct SiteOnlyRequest {
    /// Site ID (UUID), from unifi_list_sites.
    site_id: String,
}

#[derive(Debug, Serialize, Deserialize, schemars::JsonSchema)]
struct SiteIdRequest {
    /// Site ID (UUID), from unifi_list_sites.
    site_id: String,
    /// Resource ID (UUID). The tool description says which resource: device,
    /// client, network, firewall policy, firewall zone, ACL rule, DNS policy.
    id: String,
}

#[derive(Debug, Serialize, Deserialize, schemars::JsonSchema)]
struct SiteBodyRequest {
    /// Site ID (UUID), from unifi_list_sites.
    site_id: String,
    /// Full request body for the endpoint, as a JSON object. Field names and
    /// types follow the Network API OpenAPI contract.
    body: Value,
}

#[derive(Debug, Serialize, Deserialize, schemars::JsonSchema)]
struct SiteBodyIdRequest {
    /// Site ID (UUID), from unifi_list_sites.
    site_id: String,
    /// Resource ID (UUID) to update or delete.
    id: String,
    /// Full request body for the endpoint, as a JSON object.
    body: Value,
}

#[derive(Debug, Serialize, Deserialize, schemars::JsonSchema)]
struct DeviceActionRequest {
    /// Site ID (UUID), from unifi_list_sites.
    site_id: String,
    /// Device ID (UUID), from unifi_list_devices.
    device_id: String,
    /// Action name, e.g. RESTART (see the Network API docs for the action list).
    action: String,
    /// Optional JSON object with action arguments, merged into the request body.
    body: Option<Value>,
}

#[derive(Debug, Serialize, Deserialize, schemars::JsonSchema)]
struct PortActionRequest {
    /// Site ID (UUID), from unifi_list_sites.
    site_id: String,
    /// Device ID (UUID), from unifi_list_devices.
    device_id: String,
    /// Port index on the device, e.g. 1 for the first port.
    port_idx: u32,
    /// Action name, e.g. POWER_CYCLE (see the Network API docs for the action list).
    action: String,
    /// Optional JSON object with action arguments, merged into the request body.
    body: Option<Value>,
}

#[derive(Debug, Serialize, Deserialize, schemars::JsonSchema)]
struct ClientActionRequest {
    /// Site ID (UUID), from unifi_list_sites.
    site_id: String,
    /// Client ID (UUID), from unifi_list_clients.
    client_id: String,
    /// Action name, e.g. AUTHORIZE_GUEST_ACCESS or UNAUTHORIZE_GUEST_ACCESS.
    action: String,
    /// Optional JSON object with action arguments, merged into the request body.
    body: Option<Value>,
}

#[derive(Debug, Serialize, Deserialize, schemars::JsonSchema)]
struct BlockClientRequest {
    /// Site ID (UUID), from unifi_list_sites.
    site_id: String,
    /// MAC address of the client to block, e.g. "aa:bb:cc:dd:ee:ff".
    mac_address: String,
    /// Optional rule name; defaults to "Blocked by unifi-mcp <mac>".
    name: Option<String>,
    /// Optional network ID (UUID) to scope the block to one network.
    network_id: Option<String>,
}

#[derive(Debug, Serialize, Deserialize, schemars::JsonSchema)]
struct UnblockClientRequest {
    /// Site ID (UUID), from unifi_list_sites.
    site_id: String,
    /// MAC address of the client to unblock.
    mac_address: String,
}

#[derive(Debug, Serialize, Deserialize, schemars::JsonSchema)]
struct RawRequest {
    /// HTTP method: GET (always allowed), or POST/PUT/PATCH/DELETE (requires readwrite mode).
    method: String,
    /// API path starting with '/', e.g. "/v1/sites/{siteId}/devices".
    path: String,
    /// Optional query parameters as a JSON object, e.g. {"limit": 50}.
    query: Option<serde_json::Map<String, Value>>,
    /// Optional JSON request body for write methods.
    body: Option<Value>,
}

// ---------------------------------------------------------------------------
// Server
// ---------------------------------------------------------------------------

pub struct UnifiServer {
    #[allow(dead_code)]
    tool_router: ToolRouter<Self>,
    client: Arc<UniFiClient>,
}

impl UnifiServer {
    pub fn new(client: Arc<UniFiClient>) -> Self {
        Self {
            tool_router: Self::tool_router(),
            client,
        }
    }

    /// One read: GET a path, render the JSON envelope.
    async fn one(&self, path: &str) -> String {
        match self.client.get(path).await {
            Ok(v) => UniFiClient::render(&v),
            Err(e) => err_json(&e),
        }
    }

    /// One page: GET a paginated list path.
    async fn page(&self, path: &str, req: &SitePageRequest) -> String {
        match self
            .client
            .get_page(path, req.offset, req.limit, req.filter.as_deref())
            .await
        {
            Ok(v) => UniFiClient::render(&v),
            Err(e) => err_json(&e),
        }
    }

    async fn page_global(&self, path: &str, req: &PageRequest) -> String {
        match self
            .client
            .get_page(path, req.offset, req.limit, req.filter.as_deref())
            .await
        {
            Ok(v) => UniFiClient::render(&v),
            Err(e) => err_json(&e),
        }
    }

    /// One write: run a mutating request (mode-gated inside the client).
    async fn write(&self, method: &str, path: &str, body: Option<Value>) -> String {
        match self.client.request(method, path, &[], body).await {
            Ok(v) => UniFiClient::render(&v),
            Err(e) => err_json(&e),
        }
    }

    /// Fetch every ACL rule on a site (follows pagination).
    async fn fetch_all_acl_rules(&self, site_id: &str) -> Result<Vec<Value>> {
        let mut rules: Vec<Value> = Vec::new();
        let mut offset: u32 = 0;
        loop {
            let v = self
                .client
                .get_page(&format!("/v1/sites/{site_id}/acl-rules"), Some(offset), Some(200), None)
                .await?;
            let data = v
                .get("data")
                .and_then(|d| d.as_array())
                .cloned()
                .unwrap_or_default();
            let total = v
                .get("totalCount")
                .and_then(|t| t.as_u64())
                .unwrap_or(data.len() as u64);
            let new_rules = rules.len();
            rules.extend(data);
            offset += 200;
            if rules.len() as u64 >= total || rules.len() == new_rules || offset > 10_000 {
                break;
            }
        }
        Ok(rules)
    }
}

// ---------------------------------------------------------------------------
// Tools
// ---------------------------------------------------------------------------

#[tool_router]
impl UnifiServer {
    /// Report the server's connection configuration and safety mode: base URL,
    /// whether an API key is set (never the key itself), and the current mode
    /// (readonly or readwrite). Call this first to confirm the server is in
    /// the safe readonly mode before running diagnostics.
    #[tool(description = "Show the server's configuration and safety mode: base URL, whether an API key is set (the key itself is never returned), and the mode (readonly or readwrite). Use first to confirm the safe readonly default before running diagnostics.")]
    async fn unifi_status(&self) -> String {
        json!({
            "base_url": self.client.base(),
            "api_key_set": self.client.api_key_set(),
            "mode": self.client.mode().as_str(),
        })
        .to_string()
    }

    /// General information about the UniFi Network application.
    #[tool(description = "Get general information about the UniFi Network application (GET /v1/info): version, platform, and capabilities. A cheap first call to verify the API key and connection work.")]
    async fn unifi_get_info(&self) -> String {
        self.one("/v1/info").await
    }

    /// List local sites managed by the Network application.
    #[tool(description = "List the local sites managed by this Network application (GET /v1/sites). Returns paginated { data, totalCount } with each site's id, name, and internalReference. The site id is required as site_id by most other tools.")]
    async fn unifi_list_sites(&self, Parameters(req): Parameters<PageRequest>) -> String {
        self.page_global("/v1/sites", &req).await
    }

    /// List adopted UniFi devices on a site.
    #[tool(description = "List the adopted devices on a site (GET /v1/sites/{siteId}/devices): access points, switches, gateways, with model, firmware, state, and health indicators. Use for inventory and diagnostics.")]
    async fn unifi_list_devices(&self, Parameters(req): Parameters<SitePageRequest>) -> String {
        self.page(&format!("/v1/sites/{}/devices", req.site_id), &req).await
    }

    /// Full details of one adopted device.
    #[tool(description = "Get full details of one adopted device (GET /v1/sites/{siteId}/devices/{deviceId}): interfaces, radios, uplink, configuration, and health. id is the device id from unifi_list_devices.")]
    async fn unifi_get_device(&self, Parameters(req): Parameters<SiteIdRequest>) -> String {
        self.one(&format!("/v1/sites/{}/devices/{}", req.site_id, req.id))
            .await
    }

    /// Latest statistics of one adopted device.
    #[tool(description = "Get the latest statistics of one adopted device (GET /v1/sites/{siteId}/devices/{deviceId}/statistics/latest): throughput, clients, radio utilization, CPU and memory. Core diagnostic data for a device. id is the device id.")]
    async fn unifi_get_device_statistics(
        &self,
        Parameters(req): Parameters<SiteIdRequest>,
    ) -> String {
        self.one(&format!(
            "/v1/sites/{}/devices/{}/statistics/latest",
            req.site_id, req.id
        ))
        .await
    }

    /// List devices pending adoption.
    #[tool(description = "List devices pending adoption on the Network application (GET /v1/pending-devices). Useful when diagnosing why a new device is not showing up: firmware state, adoption target sites, and model.")]
    async fn unifi_list_pending_devices(&self, Parameters(req): Parameters<PageRequest>) -> String {
        self.page_global("/v1/pending-devices", &req).await
    }

    /// List connected clients on a site.
    #[tool(description = "List the connected clients on a site (GET /v1/sites/{siteId}/clients): wired, wireless, VPN and guest clients with mac, ip, network, connection type, signal, and uptime. Use for connectivity diagnostics and inventory.")]
    async fn unifi_list_clients(&self, Parameters(req): Parameters<SitePageRequest>) -> String {
        self.page(&format!("/v1/sites/{}/clients", req.site_id), &req).await
    }

    /// Details of one connected client.
    #[tool(description = "Get details of one connected client (GET /v1/sites/{siteId}/clients/{clientId}): mac, ip, network, connection type, signal strength, tx/rx rates, uptime, and fingerprinting data. id is the client id from unifi_list_clients.")]
    async fn unifi_get_client(&self, Parameters(req): Parameters<SiteIdRequest>) -> String {
        self.one(&format!("/v1/sites/{}/clients/{}", req.site_id, req.id))
            .await
    }

    /// List networks (VLANs, WAN, guest) on a site.
    #[tool(description = "List the networks on a site (GET /v1/sites/{siteId}/networks): name, VLAN id, purpose (corporate/guest/wan), subnet, DHCP settings, and DNS. Use when reviewing segmentation or planning changes.")]
    async fn unifi_list_networks(&self, Parameters(req): Parameters<SitePageRequest>) -> String {
        self.page(&format!("/v1/sites/{}/networks", req.site_id), &req).await
    }

    /// Details of one network.
    #[tool(description = "Get details of one network (GET /v1/sites/{siteId}/networks/{networkId}): full DHCP, DNS, gateway and IP configuration. id is the network id from unifi_list_networks.")]
    async fn unifi_get_network(&self, Parameters(req): Parameters<SiteIdRequest>) -> String {
        self.one(&format!("/v1/sites/{}/networks/{}", req.site_id, req.id))
            .await
    }

    /// References (dependencies) of one network.
    #[tool(description = "Get what references a network (GET /v1/sites/{siteId}/networks/{networkId}/references): firewall policies, DNS policies, traffic rules and other objects that depend on it. Check before changing or deleting a network.")]
    async fn unifi_get_network_references(
        &self,
        Parameters(req): Parameters<SiteIdRequest>,
    ) -> String {
        self.one(&format!(
            "/v1/sites/{}/networks/{}/references",
            req.site_id, req.id
        ))
        .await
    }

    /// List WAN interfaces on a site.
    #[tool(description = "List the WAN interfaces of a site (GET /v1/sites/{siteId}/wans): provider, ip, gateway, DNS, and connection state. Core connectivity diagnostic for the uplink.")]
    async fn unifi_list_wans(&self, Parameters(req): Parameters<SitePageRequest>) -> String {
        self.page(&format!("/v1/sites/{}/wans", req.site_id), &req).await
    }

    /// List countries supported by the application.
    #[tool(description = "List the countries supported by the Network application (GET /v1/countries). Supporting resource, rarely needed.")]
    async fn unifi_list_countries(&self) -> String {
        self.one("/v1/countries").await
    }

    /// List DPI applications.
    #[tool(description = "List the DPI (deep packet inspection) applications known to the application (GET /v1/dpi/applications). Supporting resource for traffic classification.")]
    async fn unifi_list_dpi_applications(&self) -> String {
        self.one("/v1/dpi/applications").await
    }

    /// List DPI application categories.
    #[tool(description = "List the DPI application categories (GET /v1/dpi/categories). Supporting resource for traffic classification.")]
    async fn unifi_list_dpi_categories(&self) -> String {
        self.one("/v1/dpi/categories").await
    }

    /// List firewall policies on a site.
    #[tool(description = "List the firewall policies on a site (GET /v1/sites/{siteId}/firewall/policies): name, action (ALLOW/BLOCK/REJECT), enabled state, source/destination matches, and scope. The primary security-review tool.")]
    async fn unifi_list_firewall_policies(
        &self,
        Parameters(req): Parameters<SitePageRequest>,
    ) -> String {
        self.page(&format!("/v1/sites/{}/firewall/policies", req.site_id), &req)
            .await
    }

    /// Details of one firewall policy.
    #[tool(description = "Get details of one firewall policy (GET /v1/sites/{siteId}/firewall/policies/{firewallPolicyId}): full match criteria (source/destination, ports, apps, networks), action, and state. id is the policy id from unifi_list_firewall_policies.")]
    async fn unifi_get_firewall_policy(
        &self,
        Parameters(req): Parameters<SiteIdRequest>,
    ) -> String {
        self.one(&format!(
            "/v1/sites/{}/firewall/policies/{}",
            req.site_id, req.id
        ))
        .await
    }

    /// Get the user-defined firewall policy ordering.
    #[tool(description = "Get the ordering of user-defined firewall policies (GET /v1/sites/{siteId}/firewall/policies/ordering). Firewall rules are evaluated top-down; ordering matters.")]
    async fn unifi_get_firewall_policy_ordering(
        &self,
        Parameters(req): Parameters<SiteOnlyRequest>,
    ) -> String {
        self.one(&format!(
            "/v1/sites/{}/firewall/policies/ordering",
            req.site_id
        ))
        .await
    }

    /// List firewall zones on a site.
    #[tool(description = "List the firewall zones on a site (GET /v1/sites/{siteId}/firewall/zones): built-in zones (LAN, WAN, GUEST, VPN) and custom zones used by firewall policy matches.")]
    async fn unifi_list_firewall_zones(
        &self,
        Parameters(req): Parameters<SitePageRequest>,
    ) -> String {
        self.page(&format!("/v1/sites/{}/firewall/zones", req.site_id), &req)
            .await
    }

    /// Details of one firewall zone.
    #[tool(description = "Get details of one firewall zone (GET /v1/sites/{siteId}/firewall/zones/{firewallZoneId}). id is the zone id from unifi_list_firewall_zones.")]
    async fn unifi_get_firewall_zone(&self, Parameters(req): Parameters<SiteIdRequest>) -> String {
        self.one(&format!("/v1/sites/{}/firewall/zones/{}", req.site_id, req.id))
            .await
    }

    /// List ACL rules on a site.
    #[tool(description = "List the ACL rules on a site (GET /v1/sites/{siteId}/acl-rules): switch-enforced allow/block rules by MAC address or IP. Includes blocked clients. Use for security review and to find rules to clean up.")]
    async fn unifi_list_acl_rules(&self, Parameters(req): Parameters<SitePageRequest>) -> String {
        self.page(&format!("/v1/sites/{}/acl-rules", req.site_id), &req).await
    }

    /// Details of one ACL rule.
    #[tool(description = "Get details of one ACL rule (GET /v1/sites/{siteId}/acl-rules/{aclRuleId}): type (MAC/IPV4), action, source/destination filters, network scope, and enabled state. id is the rule id from unifi_list_acl_rules.")]
    async fn unifi_get_acl_rule(&self, Parameters(req): Parameters<SiteIdRequest>) -> String {
        self.one(&format!("/v1/sites/{}/acl-rules/{}", req.site_id, req.id))
            .await
    }

    /// Get the user-defined ACL rule ordering.
    #[tool(description = "Get the ordering of user-defined ACL rules (GET /v1/sites/{siteId}/acl-rules/ordering).")]
    async fn unifi_get_acl_rule_ordering(
        &self,
        Parameters(req): Parameters<SiteOnlyRequest>,
    ) -> String {
        self.one(&format!("/v1/sites/{}/acl-rules/ordering", req.site_id))
            .await
    }

    /// List DNS policies on a site.
    #[tool(description = "List the DNS policies on a site (GET /v1/sites/{siteId}/dns/policies): DNS filtering and content-ad category policies. Part of the security posture review.")]
    async fn unifi_list_dns_policies(&self, Parameters(req): Parameters<SitePageRequest>) -> String {
        self.page(&format!("/v1/sites/{}/dns/policies", req.site_id), &req).await
    }

    /// Details of one DNS policy.
    #[tool(description = "Get details of one DNS policy (GET /v1/sites/{siteId}/dns/policies/{dnsPolicyId}): matching, actions, and content categories. id is the policy id from unifi_list_dns_policies.")]
    async fn unifi_get_dns_policy(&self, Parameters(req): Parameters<SiteIdRequest>) -> String {
        self.one(&format!(
            "/v1/sites/{}/dns/policies/{}",
            req.site_id, req.id
        ))
        .await
    }

    /// List traffic matching lists on a site.
    #[tool(description = "List the traffic matching lists on a site (GET /v1/sites/{siteId}/traffic-matching-lists): reusable address/domain/port groups referenced by firewall and traffic rules.")]
    async fn unifi_list_traffic_matching_lists(
        &self,
        Parameters(req): Parameters<SitePageRequest>,
    ) -> String {
        self.page(
            &format!("/v1/sites/{}/traffic-matching-lists", req.site_id),
            &req,
        )
        .await
    }

    /// Details of one traffic matching list.
    #[tool(description = "Get details of one traffic matching list (GET /v1/sites/{siteId}/traffic-matching-lists/{trafficMatchingListId}): the addresses, domains, and ports in the group. id is the list id from unifi_list_traffic_matching_lists.")]
    async fn unifi_get_traffic_matching_list(
        &self,
        Parameters(req): Parameters<SiteIdRequest>,
    ) -> String {
        self.one(&format!(
            "/v1/sites/{}/traffic-matching-lists/{}",
            req.site_id, req.id
        ))
        .await
    }

    /// Create a traffic matching list (write).
    #[tool(description = "Create a traffic matching list (POST /v1/sites/{siteId}/traffic-matching-lists). body: the group definition per the openapi contract (name, addresses, domains, ports). Requires readwrite mode.")]
    async fn unifi_create_traffic_matching_list(
        &self,
        Parameters(req): Parameters<SiteBodyRequest>,
    ) -> String {
        self.write(
            "POST",
            &format!("/v1/sites/{}/traffic-matching-lists", req.site_id),
            Some(req.body),
        )
        .await
    }

    /// Update a traffic matching list (write).
    #[tool(description = "Update a traffic matching list (PUT /v1/sites/{siteId}/traffic-matching-lists/{trafficMatchingListId}). id is the list id. Requires readwrite mode.")]
    async fn unifi_update_traffic_matching_list(
        &self,
        Parameters(req): Parameters<SiteBodyIdRequest>,
    ) -> String {
        self.write(
            "PUT",
            &format!(
                "/v1/sites/{}/traffic-matching-lists/{}",
                req.site_id, req.id
            ),
            Some(req.body),
        )
        .await
    }

    /// Delete a traffic matching list (write).
    #[tool(description = "Delete a traffic matching list (DELETE /v1/sites/{siteId}/traffic-matching-lists/{trafficMatchingListId}). id is the list id. Requires readwrite mode.")]
    async fn unifi_delete_traffic_matching_list(
        &self,
        Parameters(req): Parameters<SiteIdRequest>,
    ) -> String {
        self.write(
            "DELETE",
            &format!(
                "/v1/sites/{}/traffic-matching-lists/{}",
                req.site_id, req.id
            ),
            None,
        )
        .await
    }

    /// List VPN servers on a site.
    #[tool(description = "List the VPN servers on a site (GET /v1/sites/{siteId}/vpn/servers): WireGuard and OpenVPN server configs. Part of connectivity and security review.")]
    async fn unifi_list_vpn_servers(&self, Parameters(req): Parameters<SitePageRequest>) -> String {
        self.page(&format!("/v1/sites/{}/vpn/servers", req.site_id), &req).await
    }

    /// List site-to-site VPN tunnels on a site.
    #[tool(description = "List the site-to-site VPN tunnels on a site (GET /v1/sites/{siteId}/vpn/site-to-site-tunnels): remote peers, networks, and tunnel state. Use when diagnosing site-to-site connectivity.")]
    async fn unifi_list_vpn_tunnels(&self, Parameters(req): Parameters<SitePageRequest>) -> String {
        self.page(
            &format!("/v1/sites/{}/vpn/site-to-site-tunnels", req.site_id),
            &req,
        )
        .await
    }

    /// List WiFi broadcasts on a site.
    #[tool(description = "List the WiFi broadcasts (SSIDs) on a site (GET /v1/sites/{siteId}/wifi/broadcasts): ssid, security settings, and enabled state. Use for wireless diagnostics.")]
    async fn unifi_list_wifi_broadcasts(
        &self,
        Parameters(req): Parameters<SitePageRequest>,
    ) -> String {
        self.page(&format!("/v1/sites/{}/wifi/broadcasts", req.site_id), &req)
            .await
    }

    /// Details of one WiFi broadcast.
    #[tool(description = "Get details of one WiFi broadcast (GET /v1/sites/{siteId}/wifi/broadcasts/{wifiBroadcastId}): ssid, security, and enabled state. id is the broadcast id from unifi_list_wifi_broadcasts.")]
    async fn unifi_get_wifi_broadcast(&self, Parameters(req): Parameters<SiteIdRequest>) -> String {
        self.one(&format!(
            "/v1/sites/{}/wifi/broadcasts/{}",
            req.site_id, req.id
        ))
        .await
    }

    /// Create a WiFi broadcast (write).
    #[tool(description = "Create a WiFi broadcast (POST /v1/sites/{siteId}/wifi/broadcasts). body: the broadcast definition per the openapi contract (ssid, security, networks). Requires readwrite mode.")]
    async fn unifi_create_wifi_broadcast(
        &self,
        Parameters(req): Parameters<SiteBodyRequest>,
    ) -> String {
        self.write(
            "POST",
            &format!("/v1/sites/{}/wifi/broadcasts", req.site_id),
            Some(req.body),
        )
        .await
    }

    /// Update a WiFi broadcast (write).
    #[tool(description = "Update a WiFi broadcast (PUT /v1/sites/{siteId}/wifi/broadcasts/{wifiBroadcastId}). id is the broadcast id. Requires readwrite mode.")]
    async fn unifi_update_wifi_broadcast(
        &self,
        Parameters(req): Parameters<SiteBodyIdRequest>,
    ) -> String {
        self.write(
            "PUT",
            &format!("/v1/sites/{}/wifi/broadcasts/{}", req.site_id, req.id),
            Some(req.body),
        )
        .await
    }

    /// Delete a WiFi broadcast (write).
    #[tool(description = "Delete a WiFi broadcast (DELETE /v1/sites/{siteId}/wifi/broadcasts/{wifiBroadcastId}). id is the broadcast id. Requires readwrite mode.")]
    async fn unifi_delete_wifi_broadcast(&self, Parameters(req): Parameters<SiteIdRequest>) -> String {
        self.write(
            "DELETE",
            &format!("/v1/sites/{}/wifi/broadcasts/{}", req.site_id, req.id),
            None,
        )
        .await
    }

    /// List hotspot vouchers on a site.
    #[tool(description = "List the hotspot vouchers on a site (GET /v1/sites/{siteId}/hotspot/vouchers). Supporting resource.")]
    async fn unifi_list_vouchers(&self, Parameters(req): Parameters<SitePageRequest>) -> String {
        self.page(&format!("/v1/sites/{}/hotspot/vouchers", req.site_id), &req)
            .await
    }

    /// Details of one hotspot voucher.
    #[tool(description = "Get details of one hotspot voucher (GET /v1/sites/{siteId}/hotspot/vouchers/{voucherId}). id is the voucher id from unifi_list_vouchers.")]
    async fn unifi_get_voucher(&self, Parameters(req): Parameters<SiteIdRequest>) -> String {
        self.one(&format!(
            "/v1/sites/{}/hotspot/vouchers/{}",
            req.site_id, req.id
        ))
        .await
    }

    /// Generate hotspot vouchers (write).
    #[tool(description = "Generate new hotspot vouchers (POST /v1/sites/{siteId}/hotspot/vouchers). body: generation parameters per the openapi contract (count, duration, notes). Requires readwrite mode.")]
    async fn unifi_create_vouchers(&self, Parameters(req): Parameters<SiteBodyRequest>) -> String {
        self.write(
            "POST",
            &format!("/v1/sites/{}/hotspot/vouchers", req.site_id),
            Some(req.body),
        )
        .await
    }

    /// Delete one hotspot voucher (write).
    #[tool(description = "Delete a single hotspot voucher (DELETE /v1/sites/{siteId}/hotspot/vouchers/{voucherId}). id is the voucher id. Requires readwrite mode.")]
    async fn unifi_delete_voucher(&self, Parameters(req): Parameters<SiteIdRequest>) -> String {
        self.write(
            "DELETE",
            &format!("/v1/sites/{}/hotspot/vouchers/{}", req.site_id, req.id),
            None,
        )
        .await
    }

    /// Delete hotspot vouchers in bulk (write).
    #[tool(description = "Delete hotspot vouchers in bulk (DELETE /v1/sites/{siteId}/hotspot/vouchers). body: the selection criteria per the openapi contract. Requires readwrite mode.")]
    async fn unifi_delete_vouchers(&self, Parameters(req): Parameters<SiteBodyRequest>) -> String {
        self.write(
            "DELETE",
            &format!("/v1/sites/{}/hotspot/vouchers", req.site_id),
            Some(req.body),
        )
        .await
    }

    /// List LAGs on a site.
    #[tool(description = "List the link aggregation groups (LAGs) on a site (GET /v1/sites/{siteId}/switching/lags). Use when diagnosing switch link aggregation.")]
    async fn unifi_list_lags(&self, Parameters(req): Parameters<SiteOnlyRequest>) -> String {
        self.one(&format!("/v1/sites/{}/switching/lags", req.site_id)).await
    }

    /// Details of one LAG.
    #[tool(description = "Get details of one link aggregation group (GET /v1/sites/{siteId}/switching/lags/{lagId}): member ports, speed, and state. id is the lag id from unifi_list_lags.")]
    async fn unifi_get_lag(&self, Parameters(req): Parameters<SiteIdRequest>) -> String {
        self.one(&format!("/v1/sites/{}/switching/lags/{}", req.site_id, req.id))
            .await
    }

    /// List MC-LAG domains on a site.
    #[tool(description = "List the MC-LAG domains on a site (GET /v1/sites/{siteId}/switching/mc-lag-domains). Use when diagnosing multi-chassis link aggregation.")]
    async fn unifi_list_mclag_domains(&self, Parameters(req): Parameters<SiteOnlyRequest>) -> String {
        self.one(&format!("/v1/sites/{}/switching/mc-lag-domains", req.site_id))
            .await
    }

    /// Details of one MC-LAG domain.
    #[tool(description = "Get details of one MC-LAG domain (GET /v1/sites/{siteId}/switching/mc-lag-domains/{mcLagDomainId}). id is the domain id from unifi_list_mclag_domains.")]
    async fn unifi_get_mclag_domain(&self, Parameters(req): Parameters<SiteIdRequest>) -> String {
        self.one(&format!(
            "/v1/sites/{}/switching/mc-lag-domains/{}",
            req.site_id, req.id
        ))
        .await
    }

    /// List switch stacks on a site.
    #[tool(description = "List the switch stacks on a site (GET /v1/sites/{siteId}/switching/switch-stacks).")]
    async fn unifi_list_switch_stacks(&self, Parameters(req): Parameters<SiteOnlyRequest>) -> String {
        self.one(&format!("/v1/sites/{}/switching/switch-stacks", req.site_id))
            .await
    }

    /// Details of one switch stack.
    #[tool(description = "Get details of one switch stack (GET /v1/sites/{siteId}/switching/switch-stacks/{switchStackId}): member switches and roles. id is the stack id from unifi_list_switch_stacks.")]
    async fn unifi_get_switch_stack(&self, Parameters(req): Parameters<SiteIdRequest>) -> String {
        self.one(&format!(
            "/v1/sites/{}/switching/switch-stacks/{}",
            req.site_id, req.id
        ))
        .await
    }

    /// List RADIUS profiles on a site.
    #[tool(description = "List the RADIUS profiles on a site (GET /v1/sites/{siteId}/radius/profiles). Supporting resource for 802.1X and captive portal.")]
    async fn unifi_list_radius_profiles(
        &self,
        Parameters(req): Parameters<SitePageRequest>,
    ) -> String {
        self.page(&format!("/v1/sites/{}/radius/profiles", req.site_id), &req)
            .await
    }

    /// List device tags on a site.
    #[tool(description = "List the device tags defined on a site (GET /v1/sites/{siteId}/device-tags). Supporting resource.")]
    async fn unifi_list_device_tags(&self, Parameters(req): Parameters<SitePageRequest>) -> String {
        self.page(&format!("/v1/sites/{}/device-tags", req.site_id), &req).await
    }

    // -----------------------------------------------------------------------
    // Write tools (gated by readonly mode)
    // -----------------------------------------------------------------------

    /// Adopt devices (write).
    #[tool(description = "Adopt pending devices on a site (POST /v1/sites/{siteId}/devices). body must identify the devices to adopt (see the Network API openapi contract). Requires readwrite mode.")]
    async fn unifi_adopt_devices(&self, Parameters(req): Parameters<SiteBodyRequest>) -> String {
        self.write("POST", &format!("/v1/sites/{}/devices", req.site_id), Some(req.body))
            .await
    }

    /// Remove (unadopt) a device (write).
    #[tool(description = "Remove a device from the site, unadopting it (DELETE /v1/sites/{siteId}/devices/{deviceId}). id is the device id. Requires readwrite mode.")]
    async fn unifi_remove_device(&self, Parameters(req): Parameters<SiteIdRequest>) -> String {
        self.write("DELETE", &format!("/v1/sites/{}/devices/{}", req.site_id, req.id), None)
            .await
    }

    /// Execute an action on a device (write).
    #[tool(description = "Execute an action on an adopted device (POST /v1/sites/{siteId}/devices/{deviceId}/actions), e.g. action 'RESTART' to reboot the device. body may carry action arguments. Requires readwrite mode.")]
    async fn unifi_device_action(&self, Parameters(req): Parameters<DeviceActionRequest>) -> String {
        let body = merge_action(req.body, &req.action);
        self.write(
            "POST",
            &format!("/v1/sites/{}/devices/{}/actions", req.site_id, req.device_id),
            body,
        )
        .await
    }

    /// Execute an action on a device port (write).
    #[tool(description = "Execute an action on a device port (POST /v1/sites/{siteId}/devices/{deviceId}/interfaces/ports/{portIdx}/actions), e.g. action 'POWER_CYCLE' to power-cycle PoE. Requires readwrite mode.")]
    async fn unifi_port_action(&self, Parameters(req): Parameters<PortActionRequest>) -> String {
        let body = merge_action(req.body, &req.action);
        self.write(
            "POST",
            &format!(
                "/v1/sites/{}/devices/{}/interfaces/ports/{}/actions",
                req.site_id, req.device_id, req.port_idx
            ),
            body,
        )
        .await
    }

    /// Execute an action on a client (write).
    #[tool(description = "Execute an action on a connected client (POST /v1/sites/{siteId}/clients/{clientId}/actions), e.g. action 'AUTHORIZE_GUEST_ACCESS' or 'UNAUTHORIZE_GUEST_ACCESS' with the applicable arguments in body. Requires readwrite mode.")]
    async fn unifi_client_action(&self, Parameters(req): Parameters<ClientActionRequest>) -> String {
        let body = merge_action(req.body, &req.action);
        self.write(
            "POST",
            &format!("/v1/sites/{}/clients/{}/actions", req.site_id, req.client_id),
            body,
        )
        .await
    }

    /// Create a firewall policy (write).
    #[tool(description = "Create a new firewall policy (POST /v1/sites/{siteId}/firewall/policies). body: the full policy object per the Network API openapi contract, including action (ALLOW/BLOCK/REJECT) and match criteria. Requires readwrite mode.")]
    async fn unifi_create_firewall_policy(
        &self,
        Parameters(req): Parameters<SiteBodyRequest>,
    ) -> String {
        self.write(
            "POST",
            &format!("/v1/sites/{}/firewall/policies", req.site_id),
            Some(req.body),
        )
        .await
    }

    /// Update a firewall policy (write).
    #[tool(description = "Update a firewall policy (PUT /v1/sites/{siteId}/firewall/policies/{firewallPolicyId}). id is the policy id; body is the full updated policy. Requires readwrite mode.")]
    async fn unifi_update_firewall_policy(
        &self,
        Parameters(req): Parameters<SiteBodyIdRequest>,
    ) -> String {
        self.write(
            "PUT",
            &format!("/v1/sites/{}/firewall/policies/{}", req.site_id, req.id),
            Some(req.body),
        )
        .await
    }

    /// Partially update a firewall policy (write).
    #[tool(description = "Partially update a firewall policy (PATCH /v1/sites/{siteId}/firewall/policies/{firewallPolicyId}). id is the policy id; body carries only the fields to change. Requires readwrite mode.")]
    async fn unifi_patch_firewall_policy(
        &self,
        Parameters(req): Parameters<SiteBodyIdRequest>,
    ) -> String {
        self.write(
            "PATCH",
            &format!("/v1/sites/{}/firewall/policies/{}", req.site_id, req.id),
            Some(req.body),
        )
        .await
    }

    /// Delete a firewall policy (write).
    #[tool(description = "Delete a firewall policy (DELETE /v1/sites/{siteId}/firewall/policies/{firewallPolicyId}). id is the policy id. Requires readwrite mode.")]
    async fn unifi_delete_firewall_policy(&self, Parameters(req): Parameters<SiteIdRequest>) -> String {
        self.write(
            "DELETE",
            &format!("/v1/sites/{}/firewall/policies/{}", req.site_id, req.id),
            None,
        )
        .await
    }

    /// Reorder user-defined firewall policies (write).
    #[tool(description = "Reorder the user-defined firewall policies (PUT /v1/sites/{siteId}/firewall/policies/ordering). body: the ordered id list per the openapi contract. Requires readwrite mode.")]
    async fn unifi_update_firewall_policy_ordering(
        &self,
        Parameters(req): Parameters<SiteBodyRequest>,
    ) -> String {
        self.write(
            "PUT",
            &format!("/v1/sites/{}/firewall/policies/ordering", req.site_id),
            Some(req.body),
        )
        .await
    }

    /// Create a custom firewall zone (write).
    #[tool(description = "Create a custom firewall zone (POST /v1/sites/{siteId}/firewall/zones). body: zone definition per the openapi contract. Requires readwrite mode.")]
    async fn unifi_create_firewall_zone(&self, Parameters(req): Parameters<SiteBodyRequest>) -> String {
        self.write(
            "POST",
            &format!("/v1/sites/{}/firewall/zones", req.site_id),
            Some(req.body),
        )
        .await
    }

    /// Update a firewall zone (write).
    #[tool(description = "Update a firewall zone (PUT /v1/sites/{siteId}/firewall/zones/{firewallZoneId}). id is the zone id. Requires readwrite mode.")]
    async fn unifi_update_firewall_zone(
        &self,
        Parameters(req): Parameters<SiteBodyIdRequest>,
    ) -> String {
        self.write(
            "PUT",
            &format!("/v1/sites/{}/firewall/zones/{}", req.site_id, req.id),
            Some(req.body),
        )
        .await
    }

    /// Delete a custom firewall zone (write).
    #[tool(description = "Delete a custom firewall zone (DELETE /v1/sites/{siteId}/firewall/zones/{firewallZoneId}). id is the zone id. Requires readwrite mode.")]
    async fn unifi_delete_firewall_zone(&self, Parameters(req): Parameters<SiteIdRequest>) -> String {
        self.write(
            "DELETE",
            &format!("/v1/sites/{}/firewall/zones/{}", req.site_id, req.id),
            None,
        )
        .await
    }

    /// Create an ACL rule (write).
    #[tool(description = "Create a user-defined ACL rule (POST /v1/sites/{siteId}/acl-rules). body: the rule per the openapi contract, e.g. { type: 'MAC', action: 'BLOCK', name: 'x', enabled: true, sourceFilter: { type: 'MAC_ADDRESSES', macAddresses: ['aa:bb:cc:dd:ee:ff'] } }. Requires readwrite mode.")]
    async fn unifi_create_acl_rule(&self, Parameters(req): Parameters<SiteBodyRequest>) -> String {
        self.write(
            "POST",
            &format!("/v1/sites/{}/acl-rules", req.site_id),
            Some(req.body),
        )
        .await
    }

    /// Update an ACL rule (write).
    #[tool(description = "Update an ACL rule (PUT /v1/sites/{siteId}/acl-rules/{aclRuleId}). id is the rule id. Requires readwrite mode.")]
    async fn unifi_update_acl_rule(&self, Parameters(req): Parameters<SiteBodyIdRequest>) -> String {
        self.write(
            "PUT",
            &format!("/v1/sites/{}/acl-rules/{}", req.site_id, req.id),
            Some(req.body),
        )
        .await
    }

    /// Delete an ACL rule (write).
    #[tool(description = "Delete an ACL rule (DELETE /v1/sites/{siteId}/acl-rules/{aclRuleId}). id is the rule id. Requires readwrite mode.")]
    async fn unifi_delete_acl_rule(&self, Parameters(req): Parameters<SiteIdRequest>) -> String {
        self.write(
            "DELETE",
            &format!("/v1/sites/{}/acl-rules/{}", req.site_id, req.id),
            None,
        )
        .await
    }

    /// Reorder user-defined ACL rules (write).
    #[tool(description = "Reorder the user-defined ACL rules (PUT /v1/sites/{siteId}/acl-rules/ordering). body: the ordered id list per the openapi contract. Requires readwrite mode.")]
    async fn unifi_update_acl_rule_ordering(
        &self,
        Parameters(req): Parameters<SiteBodyRequest>,
    ) -> String {
        self.write(
            "PUT",
            &format!("/v1/sites/{}/acl-rules/ordering", req.site_id),
            Some(req.body),
        )
        .await
    }

    /// Block a client by MAC address (write).
    #[tool(description = "Block a client on a site by creating a MAC ACL rule with action BLOCK (POST /v1/sites/{siteId}/acl-rules). Pass the client's mac address; optionally a rule name and a network id to scope the block. Requires readwrite mode.")]
    async fn unifi_block_client(&self, Parameters(req): Parameters<BlockClientRequest>) -> String {
        let mac = normalize_mac(&req.mac_address);
        if mac.is_empty() {
            return err_json(&anyhow::anyhow!("mac_address must be a MAC like 'aa:bb:cc:dd:ee:ff'"));
        }
        let mut body = json!({
            "type": "MAC",
            "action": "BLOCK",
            "name": req.name.clone().unwrap_or_else(|| format!("Blocked by unifi-mcp {mac}")),
            "enabled": true,
            "sourceFilter": { "type": "MAC_ADDRESSES", "macAddresses": [mac] },
        });
        if let Some(nid) = req.network_id.filter(|s| !s.is_empty()) {
            body["networkIdFilter"] = Value::String(nid);
        }
        self.write(
            "POST",
            &format!("/v1/sites/{}/acl-rules", req.site_id),
            Some(body),
        )
        .await
    }

    /// Unblock a client by MAC address (write).
    #[tool(description = "Unblock a client by deleting every MAC ACL rule that blocks its MAC address (action BLOCK, type MAC). Finds matching rules via GET /v1/sites/{siteId}/acl-rules, then deletes each with DELETE /acl-rules/{id}. Returns the ids deleted. Requires readwrite mode.")]
    async fn unifi_unblock_client(&self, Parameters(req): Parameters<UnblockClientRequest>) -> String {
        let mac = normalize_mac(&req.mac_address);
        if mac.is_empty() {
            return err_json(&anyhow::anyhow!("mac_address must be a MAC like 'aa:bb:cc:dd:ee:ff'"));
        }
        let rules = match self.fetch_all_acl_rules(&req.site_id).await {
            Ok(r) => r,
            Err(e) => return err_json(&e),
        };
        let mut deleted: Vec<String> = Vec::new();
        for rule in &rules {
            let is_block = rule.get("action").and_then(|a| a.as_str()) == Some("BLOCK");
            let is_mac = rule.get("type").and_then(|t| t.as_str()) == Some("MAC");
            let matches = rule
                .get("sourceFilter")
                .and_then(|s| s.get("macAddresses"))
                .and_then(|m| m.as_array())
                .map(|list| {
                    list.iter().any(|m| {
                        m.as_str()
                            .map(|s| normalize_mac(s) == mac)
                            .unwrap_or(false)
                    })
                })
                .unwrap_or(false);
            if is_block && is_mac && matches {
                if let Some(id) = rule.get("id").and_then(|i| i.as_str()) {
                    let result = self
                        .client
                        .request(
                            "DELETE",
                            &format!("/v1/sites/{}/acl-rules/{}", req.site_id, id),
                            &[],
                            None,
                        )
                        .await;
                    match result {
                        Ok(_) => deleted.push(id.to_string()),
                        Err(e) => return err_json(&e),
                    }
                }
            }
        }
        json!({ "mac": req.mac_address, "deleted_rule_ids": deleted, "count": deleted.len() }).to_string()
    }

    /// Create a network (write).
    #[tool(description = "Create a network (POST /v1/sites/{siteId}/networks). body: network definition per the openapi contract (name, purpose, vlan/subnet, DHCP, DNS). Requires readwrite mode.")]
    async fn unifi_create_network(&self, Parameters(req): Parameters<SiteBodyRequest>) -> String {
        self.write(
            "POST",
            &format!("/v1/sites/{}/networks", req.site_id),
            Some(req.body),
        )
        .await
    }

    /// Update a network (write).
    #[tool(description = "Update a network (PUT /v1/sites/{siteId}/networks/{networkId}). id is the network id. Check unifi_get_network_references first for dependencies. Requires readwrite mode.")]
    async fn unifi_update_network(&self, Parameters(req): Parameters<SiteBodyIdRequest>) -> String {
        self.write(
            "PUT",
            &format!("/v1/sites/{}/networks/{}", req.site_id, req.id),
            Some(req.body),
        )
        .await
    }

    /// Delete a network (write).
    #[tool(description = "Delete a network (DELETE /v1/sites/{siteId}/networks/{networkId}). id is the network id. Check unifi_get_network_references first for dependencies. Requires readwrite mode.")]
    async fn unifi_delete_network(&self, Parameters(req): Parameters<SiteIdRequest>) -> String {
        self.write(
            "DELETE",
            &format!("/v1/sites/{}/networks/{}", req.site_id, req.id),
            None,
        )
        .await
    }

    /// Create a DNS policy (write).
    #[tool(description = "Create a DNS policy (POST /v1/sites/{siteId}/dns/policies). body: policy per the openapi contract (matching, actions, content-categories). Requires readwrite mode.")]
    async fn unifi_create_dns_policy(&self, Parameters(req): Parameters<SiteBodyRequest>) -> String {
        self.write(
            "POST",
            &format!("/v1/sites/{}/dns/policies", req.site_id),
            Some(req.body),
        )
        .await
    }

    /// Update a DNS policy (write).
    #[tool(description = "Update a DNS policy (PUT /v1/sites/{siteId}/dns/policies/{dnsPolicyId}). id is the policy id. Requires readwrite mode.")]
    async fn unifi_update_dns_policy(&self, Parameters(req): Parameters<SiteBodyIdRequest>) -> String {
        self.write(
            "PUT",
            &format!("/v1/sites/{}/dns/policies/{}", req.site_id, req.id),
            Some(req.body),
        )
        .await
    }

    /// Delete a DNS policy (write).
    #[tool(description = "Delete a DNS policy (DELETE /v1/sites/{siteId}/dns/policies/{dnsPolicyId}). id is the policy id. Requires readwrite mode.")]
    async fn unifi_delete_dns_policy(&self, Parameters(req): Parameters<SiteIdRequest>) -> String {
        self.write(
            "DELETE",
            &format!("/v1/sites/{}/dns/policies/{}", req.site_id, req.id),
            None,
        )
        .await
    }

    /// Generic raw API request (mode-gated).
    #[tool(description = "Send a raw request to the Network API (any path under the configured base URL). method GET is always allowed; POST/PUT/PATCH/DELETE are refused in readonly mode and only work with UNIFI_MODE=readwrite. query is an optional JSON object of query parameters; body an optional JSON object for writes. Use for endpoints without a dedicated tool.")]
    async fn unifi_request(&self, Parameters(req): Parameters<RawRequest>) -> String {
        let method = req.method.trim().to_ascii_uppercase();
        if !matches!(
            method.as_str(),
            "GET" | "HEAD" | "OPTIONS" | "POST" | "PUT" | "PATCH" | "DELETE"
        ) {
            return err_json(&anyhow::anyhow!(
                "method '{method}' is not supported; use GET, HEAD, OPTIONS, POST, PUT, PATCH or DELETE"
            ));
        }
        let query: Vec<(String, String)> = match &req.query {
            Some(map) => map.iter().map(|(k, v)| (k.clone(), value_to_query(v))).collect(),
            None => Vec::new(),
        };
        match self
            .client
            .request(&method, &req.path, &query, req.body)
            .await
        {
            Ok(v) => UniFiClient::render(&v),
            Err(e) => err_json(&e),
        }
    }
}

#[tool_handler]
impl ServerHandler for UnifiServer {
    fn get_info(&self) -> ServerInfo {
        ServerInfo::new(ServerCapabilities::builder().enable_tools().build()).with_instructions(
            "UniFi Network API server (v10.4.57), covering the full endpoint \
             surface of the Network OpenAPI spec with a dedicated tool per \
             endpoint, plus a generic unifi_request passthrough for anything \
             else. The server defaults to READONLY mode: diagnostics, \
             inventory, and security review only, and every write tool is \
             refused before reaching the controller. Typical flow: unifi_status \
             to confirm the mode, unifi_get_info to verify connectivity, \
             unifi_list_sites to pick a site_id, then diagnostics \
             (unifi_list_devices, unifi_list_clients, unifi_list_wans, \
             unifi_get_device_statistics), security review (unifi_list_firewall_policies, \
             unifi_list_acl_rules, unifi_list_dns_policies, unifi_list_firewall_zones), \
             and network review (unifi_list_networks, unifi_get_network_references). \
             Write tools (unifi_block_client, unifi_create_firewall_policy, \
             unifi_device_action, and the rest) are only available when the \
             server runs with UNIFI_MODE=readwrite.",
        )
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn err_json(e: &anyhow::Error) -> String {
    json!({ "error": e.to_string() }).to_string()
}

/// Merge the action name into an optional action body, producing the request
/// body for the actions endpoints: `{ "action": name, ...args }`.
fn merge_action(body: Option<Value>, action: &str) -> Option<Value> {
    let mut map = match body {
        Some(Value::Object(m)) => m,
        Some(_) => return None, // non-object body: let the client report misuse
        None => serde_json::Map::new(),
    };
    map.insert("action".into(), Value::String(action.to_string()));
    Some(Value::Object(map))
}

/// Normalize a MAC address to lowercase alphanumerics for comparison.
pub fn normalize_mac(mac: &str) -> String {
    mac.chars()
        .filter(|c| c.is_ascii_alphanumeric())
        .collect::<String>()
        .to_ascii_lowercase()
}

/// Serialize a JSON value into a query parameter string.
fn value_to_query(v: &Value) -> String {
    match v {
        Value::String(s) => s.clone(),
        Value::Array(items) => items
            .iter()
            .map(value_to_query)
            .collect::<Vec<_>>()
            .join(","),
        Value::Null => "null".into(),
        other => other.to_string(),
    }
}

/// Convenience for tests and future expansion: build a block rule body.
pub fn block_rule_body(mac: &str, name: &str, network_id: Option<&str>) -> Value {
    let mut body = json!({
        "type": "MAC",
        "action": "BLOCK",
        "name": name,
        "enabled": true,
        "sourceFilter": { "type": "MAC_ADDRESSES", "macAddresses": [mac] },
    });
    if let Some(nid) = network_id {
        body["networkIdFilter"] = Value::String(nid.to_string());
    }
    body
}
