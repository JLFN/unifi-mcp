//! Client-level tests against an in-process mock UniFi API.

use serde_json::json;
use unifi_mcp::client::{Mode, UniFiClient};
use unifi_mcp::server::{block_rule_body, normalize_mac};
use wiremock::{Mock, MockServer, ResponseTemplate};
use wiremock::matchers::{body_json, header, method, path, query_param};

fn client(base: &str, mode: Mode) -> UniFiClient {
    UniFiClient::new(Some(base), "test-key", mode, false, 10).unwrap()
}

#[tokio::test]
async fn list_sites_sends_auth_and_parses_envelope() {
    let mock = MockServer::start().await;
    Mock::given(method("GET"))
        .and(path("/v1/sites"))
        .and(header("X-API-KEY", "test-key"))
        .and(query_param("limit", "25"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({
            "data": [ { "id": "site-1", "name": "Default" } ],
            "totalCount": 1
        })))
        .expect(1)
        .mount(&mock)
        .await;

    let c = client(&mock.uri(), Mode::Readonly);
    let v = c.get_page("/v1/sites", Some(0), Some(25), None).await.unwrap();
    assert_eq!(v["totalCount"], 1);
    assert_eq!(v["data"][0]["id"], "site-1");
}

#[tokio::test]
async fn readonly_mode_blocks_writes_before_network() {
    let mock = MockServer::start().await;
    // No mock is mounted: if the request leaked to the network it would 404.
    let c = client(&mock.uri(), Mode::Readonly);
    let err = c
        .request("POST", "/v1/sites/s/firewall/policies", &[], Some(json!({})))
        .await
        .unwrap_err();
    let msg = err.to_string();
    assert!(msg.contains("readonly"), "unexpected error: {msg}");
}

#[tokio::test]
async fn readwrite_mode_performs_post_with_auth_and_body() {
    let mock = MockServer::start().await;
    Mock::given(method("POST"))
        .and(path("/v1/sites/s/firewall/policies"))
        .and(header("X-API-KEY", "test-key"))
        .and(body_json(json!({ "action": "ALLOW" })))
        .respond_with(ResponseTemplate::new(201).set_body_json(json!({
            "data": [ { "id": "pol-1" } ], "totalCount": 1
        })))
        .expect(1)
        .mount(&mock)
        .await;

    let c = client(&mock.uri(), Mode::ReadWrite);
    let v = c
        .request(
            "POST",
            "/v1/sites/s/firewall/policies",
            &[],
            Some(json!({ "action": "ALLOW" })),
        )
        .await
        .unwrap();
    assert_eq!(v["totalCount"], 1);
}

#[tokio::test]
async fn http_errors_carry_status_and_body() {
    let mock = MockServer::start().await;
    Mock::given(method("GET"))
        .and(path("/v1/sites/x/devices"))
        .respond_with(ResponseTemplate::new(404).set_body_string("not found"))
        .mount(&mock)
        .await;

    let c = client(&mock.uri(), Mode::Readonly);
    let err = c.get("/v1/sites/x/devices").await.unwrap_err();
    let msg = err.to_string();
    assert!(msg.contains("404"), "unexpected error: {msg}");
    assert!(msg.contains("not found"), "unexpected error: {msg}");
}

#[tokio::test]
async fn paths_must_start_with_slash() {
    let mock = MockServer::start().await;
    let c = client(&mock.uri(), Mode::Readonly);
    let err = c.get("v1/sites").await.unwrap_err();
    assert!(err.to_string().contains("must start with '/'"));
}

#[tokio::test]
async fn missing_config_reports_clear_guidance() {
    // Missing base URL: report the base URL guidance.
    let c = UniFiClient::new(None, "", Mode::Readonly, false, 10).unwrap();
    let err = c.get("/v1/sites").await.unwrap_err();
    let msg = err.to_string();
    assert!(msg.contains("UNIFI_API_BASE"), "unexpected error: {msg}");

    // Base set but key missing: report the key guidance.
    let c2 = UniFiClient::new(
        Some("https://example.invalid"),
        "",
        Mode::Readonly,
        false,
        10,
    )
    .unwrap();
    let err2 = c2.get("/v1/sites").await.unwrap_err();
    assert!(err2.to_string().contains("UNIFI_API_KEY"));
}

#[tokio::test]
async fn missing_config_never_reaches_network() {
    // No mock server exists here at all; if the client tried to send the
    // request it would fail with a connection error rather than a config error.
    let c = UniFiClient::new(None, "k", Mode::Readonly, false, 10).unwrap();
    let err = c.get("/v1/sites").await.unwrap_err();
    assert!(err.to_string().contains("UNIFI_API_BASE"));
}

#[tokio::test]
async fn block_rule_body_has_mac_block_shape() {
    let body = block_rule_body("AA:BB:CC:DD:EE:FF", "block guest", Some("net-1"));
    assert_eq!(body["type"], "MAC");
    assert_eq!(body["action"], "BLOCK");
    assert_eq!(body["enabled"], true);
    assert_eq!(body["sourceFilter"]["type"], "MAC_ADDRESSES");
    assert_eq!(body["sourceFilter"]["macAddresses"][0], "AA:BB:CC:DD:EE:FF");
    assert_eq!(body["networkIdFilter"], "net-1");
}

#[test]
fn normalize_mac_is_case_and_separator_insensitive() {
    assert_eq!(normalize_mac("AA:BB:CC:DD:EE:FF"), "aabbccddeeff");
    assert_eq!(normalize_mac("aa-bb-cc-dd-ee-ff"), "aabbccddeeff");
    assert_eq!(normalize_mac("aabbccddeeff"), "aabbccddeeff");
}
