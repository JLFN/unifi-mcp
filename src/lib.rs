//! unifi-mcp — UniFi Network API MCP server.
//!
//! Safe-by-default: the server starts in readonly mode (diagnostics only)
//! and refuses every mutating call until UNIFI_MODE=readwrite is set.

pub mod client;
pub mod server;
