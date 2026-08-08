//! Thin HTTP client for the UniFi Network API (v10.4.57) with a safety gate
//! that keeps the server read-only unless explicitly switched to read/write.
//!
//! Authentication uses the `X-API-KEY` header. API keys are generated at
//! unifi.ui.com. The base URL is one of the two server URLs from the Network
//! OpenAPI specification:
//!
//!   cloud:   https://api.ui.com/v1/connector/consoles/{consoleId}/proxy/network/integration
//!   on-prem: https://{controllerIp}/proxy/network/integration
//!
//! Responses from the v1 API are JSON envelopes of the shape
//! `{ "data": [...], "totalCount": n }` for pages, or plain objects for
//! single resources. This module passes those envelopes through untouched.

use anyhow::{Context, Result, bail};
use serde_json::Value;
use std::time::Duration;

/// Server safety mode. Readonly blocks every mutating HTTP method; only GET
/// (plus HEAD/OPTIONS) reach the controller.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Mode {
    /// Default. Diagnostics and inventory only; all write tools are refused.
    Readonly,
    /// Opt-in. Write tools (POST/PUT/PATCH/DELETE) are allowed.
    ReadWrite,
}

impl Mode {
    /// Parse a mode from the `UNIFI_MODE` environment variable.
    pub fn parse(s: &str) -> Result<Self> {
        match s.trim().to_ascii_lowercase().as_str() {
            "readonly" | "read-only" | "ro" => Ok(Mode::Readonly),
            "readwrite" | "read-write" | "rw" => Ok(Mode::ReadWrite),
            other => bail!(
                "invalid UNIFI_MODE '{other}'; use 'readonly' (default) or 'readwrite'"
            ),
        }
    }

    pub fn as_str(&self) -> &'static str {
        match self {
            Mode::Readonly => "readonly",
            Mode::ReadWrite => "readwrite",
        }
    }
}

/// Upper bound on tool output size, in bytes, to keep MCP responses sane.
const MAX_BODY_BYTES: usize = 200_000;

/// A configured connection to one UniFi Network application.
///
/// The base URL and API key are optional at construction: if either is
/// missing the server still starts (so the MCP registration stays healthy)
/// and every tool call returns a clear configuration error.
pub struct UniFiClient {
    http: reqwest::Client,
    base: Option<String>,
    api_key: String,
    mode: Mode,
}

impl UniFiClient {
    /// Build a client from environment variables:
    ///
    ///   UNIFI_API_BASE   Network API base URL (cloud connector or on-prem)
    ///   UNIFI_API_KEY    X-API-KEY credential from unifi.ui.com
    ///   UNIFI_MODE       readonly (default) | readwrite
    ///   UNIFI_INSECURE   1/true/yes to skip TLS certificate verification (on-prem self-signed only)
    ///   UNIFI_TIMEOUT    request timeout in seconds, default 30
    ///
    /// Missing UNIFI_API_BASE / UNIFI_API_KEY do not fail startup; tools
    /// report the missing piece when called.
    pub fn from_env() -> Result<Self> {
        let base = std::env::var("UNIFI_API_BASE")
            .ok()
            .filter(|s| !s.is_empty());
        let api_key = std::env::var("UNIFI_API_KEY").unwrap_or_default();

        let mode = match std::env::var("UNIFI_MODE").ok().filter(|s| !s.is_empty()) {
            Some(m) => Mode::parse(&m)?,
            None => Mode::Readonly,
        };

        let insecure = matches!(
            std::env::var("UNIFI_INSECURE").as_deref(),
            Ok("1") | Ok("true") | Ok("yes")
        );

        let timeout = std::env::var("UNIFI_TIMEOUT")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(30);

        Self::new(base.as_deref(), &api_key, mode, insecure, timeout)
    }

    /// Build a client with explicit configuration (used by tests).
    pub fn new(
        base: Option<&str>,
        api_key: &str,
        mode: Mode,
        insecure: bool,
        timeout_secs: u64,
    ) -> Result<Self> {
        let mut builder = reqwest::Client::builder()
            .timeout(Duration::from_secs(timeout_secs))
            .user_agent(concat!("unifi-mcp/", env!("CARGO_PKG_VERSION")));
        if insecure {
            builder = builder.danger_accept_invalid_certs(true);
        }
        let http = builder.build().context("failed to build HTTP client")?;
        Ok(Self {
            http,
            base: base.map(|b| b.trim_end_matches('/').to_string()),
            api_key: api_key.to_string(),
            mode,
        })
    }

    pub fn mode(&self) -> Mode {
        self.mode
    }

    pub fn base(&self) -> &str {
        self.base.as_deref().unwrap_or("(not set)")
    }

    pub fn api_key_set(&self) -> bool {
        !self.api_key.is_empty()
    }

    /// The read-only gate. Every mutating request passes through here.
    fn guard_write(&self) -> Result<()> {
        if self.mode == Mode::Readonly {
            bail!(
                "refused: the server is in readonly mode (safe diagnostics only). \
                 Nothing was sent to the controller. Set UNIFI_MODE=readwrite and \
                 restart the server to enable write operations."
            );
        }
        Ok(())
    }

    /// Configuration gate: the request cannot proceed without a base URL
    /// and an API key.
    fn guard_config(&self) -> Result<()> {
        if self.base.is_none() {
            bail!(
                "UNIFI_API_BASE is not set. Use a Network API base URL from the OpenAPI spec, e.g.\n\
                 cloud:   https://api.ui.com/v1/connector/consoles/CONSOLE_ID/proxy/network/integration\n\
                 on-prem: https://CONTROLLER_IP/proxy/network/integration"
            );
        }
        if self.api_key.is_empty() {
            bail!(
                "UNIFI_API_KEY is not set. Generate an API key at unifi.ui.com \
                 (Settings, Admin & Users, API Keys) and export it."
            );
        }
        Ok(())
    }

    fn url(&self, path: &str) -> Result<String> {
        if !path.starts_with('/') {
            bail!("path must start with '/', got '{path}'");
        }
        let base = self
            .base
            .as_deref()
            .context("UNIFI_API_BASE is not set; cannot build a request URL")?;
        Ok(format!("{base}{path}"))
    }

    /// Fetch a paginated list (`{ data, totalCount }` envelope).
    pub async fn get_page(
        &self,
        path: &str,
        offset: Option<u32>,
        limit: Option<u32>,
        filter: Option<&str>,
    ) -> Result<Value> {
        let mut query: Vec<(String, String)> = Vec::new();
        if let Some(o) = offset {
            query.push(("offset".into(), o.to_string()));
        }
        if let Some(l) = limit {
            query.push(("limit".into(), l.to_string()));
        }
        if let Some(f) = filter.filter(|s| !s.is_empty()) {
            query.push(("filter".into(), f.to_string()));
        }
        self.request("GET", path, &query, None).await
    }

    /// Fetch a single resource by path.
    pub async fn get(&self, path: &str) -> Result<Value> {
        self.request("GET", path, &[], None).await
    }

    /// Send an arbitrary request. The write-safety gate is enforced here, so
    /// every tool -- including the generic passthrough -- inherits it.
    pub async fn request(
        &self,
        method: &str,
        path: &str,
        query: &[(String, String)],
        body: Option<Value>,
    ) -> Result<Value> {
        let method_upper = method.to_ascii_uppercase();
        let is_write = !matches!(method_upper.as_str(), "GET" | "HEAD" | "OPTIONS");
        if is_write {
            self.guard_write()?;
        }
        self.guard_config()?;

        let url = self.url(path)?;
        let http_method = reqwest::Method::from_bytes(method_upper.as_bytes())
            .with_context(|| format!("invalid HTTP method '{method_upper}'"))?;

        let mut req = self
            .http
            .request(http_method, &url)
            .header("X-API-KEY", &self.api_key)
            .header("Accept", "application/json");
        if !query.is_empty() {
            req = req.query(&query);
        }
        if let Some(b) = body {
            req = req.json(&b);
        }

        let resp = req.send().await.context("request to UniFi API failed")?;
        let status = resp.status();
        let text = resp.text().await.unwrap_or_default();
        if !status.is_success() {
            let snippet: String = text.chars().take(400).collect();
            bail!("UniFi API returned HTTP {status} for {method_upper} {path}: {snippet}");
        }
        if text.trim().is_empty() {
            return Ok(Value::Null);
        }
        let value: Value = serde_json::from_str(&text)
            .with_context(|| format!("response from {path} was not valid JSON (HTTP {status})"))?;
        Ok(value)
    }

    /// Pretty-print a response value for an MCP tool, capped in size.
    pub fn render(value: &Value) -> String {
        let pretty = serde_json::to_string_pretty(value).unwrap_or_else(|_| "{}".into());
        if pretty.len() <= MAX_BODY_BYTES {
            return pretty;
        }
        let mut capped: String = pretty.chars().take(MAX_BODY_BYTES).collect();
        capped.push_str("\n... (truncated)");
        serde_json::json!({ "truncated": true, "body": capped }).to_string()
    }
}
