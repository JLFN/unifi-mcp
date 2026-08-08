# UniFi Network API v10.4.57 — local documentation mirror

A complete local copy of the live Network API documentation from
developer.ui.com, downloaded 2026-08-08. Refresh any time with:

    python3 tools/mirror_docs.py

## What is here

- pages/ — 82 markdown pages, one per doc page: every API endpoint
  (method, path, operationId, description, filterable-property tables)
  plus the guides: Getting Started, Filtering, Error Handling, and the
  Ansible Quick Start.
- network-v10.4.57-openapi.json — the machine-readable OpenAPI contract:
  every endpoint, schema, and example. The authoritative source.
- postman-collection.json — ready-to-import Postman collection.
- network-v10.4.57-llms.txt — the official LLM-oriented endpoint index.
- root-llms.txt — the root index across all UniFi developer APIs.
- ai-gettingstarted.md — the official AI onboarding guide for this API.
- tools/mirror_docs.py — the mirror script. It decodes the Next.js page
  payloads (endpoint objects and mdx content) into clean markdown.

## How the mirror works

The doc site is a Next.js app; its pages embed the content in the React
Server Components flight payload of the plain HTML response. The script
fetches each page, extracts either the endpoint object (JSON with path,
method, operationId, and a markdown description) or the mdxContent tree
(guide pages), and writes clean markdown. The apidoc-cdn.ui.com CDN serves
true markdown for a couple of guide pages, but the payload extraction
covers every page uniformly.

## Suggested use

The corpus is a good basis for a local documentation RAG index (see the
docs-rag-template on this machine, used by powershell-mcp and obs-docs-mcp)
or for the repo-rag-mcp server. The OpenAPI JSON is the best source for
request/response schemas; pages/ is the best source for prose and
filtering semantics.
