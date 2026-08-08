//! unifi-mcp binary entry point: build the client from the environment and
//! serve MCP over stdio.

use std::sync::Arc;

use anyhow::Result;
use rmcp::{ServiceExt, transport::stdio};
use unifi_mcp::client::UniFiClient;
use unifi_mcp::server::UnifiServer;

#[tokio::main]
async fn main() -> Result<()> {
    let client = Arc::new(UniFiClient::from_env()?);
    let service = UnifiServer::new(client);
    let running = service.serve(stdio()).await?;
    running.waiting().await?;
    Ok(())
}
