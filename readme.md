Summer with Tailscale
===

This repository provides scripts and code patterns to programmatically provision isolated Tailscale networks (tailnets), embed Zero-Trust connectivity directly into application binaries using tsnet, and automate cross-tailnet resource sharing via policy files.

What's Included
Programmatic Tailnet Management: Scripts to create, list, and delete isolated tailnet sandboxes using the Tailscale Console API without manual dashboard interaction.

Embedded App Networking (tsnet): Examples demonstrating how to bundle Tailscale directly inside Go applications to run isolated microservices and automatically handle HTTPS TLS certificates.

Declarative Sharing: Policy configuration patterns to establish secure cross-tailnet communication channels entirely via code.

# Prerequisites

* A Tailscale account with API access
* Docker or GO (for tsnet applications)
* curl and jq installed locally

