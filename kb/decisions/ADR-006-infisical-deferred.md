---
id: adr-006-infisical-deferred
title: ADR-006 — Infisical Deferred (Superseded by ADR-008)
tier: "x"
ctid: "n/a"
ip: n/a
status: superseded
last_verified: unreleased
tags: [decision, infisical, secrets-manager, superseded]
retrievable: true
---

# ADR-006 — Infisical Deferred (Superseded by ADR-008)

> **Superseded by [ADR-008](ADR-008-zero-trust-security-zones-and-infisical.md).**
> Self-hosted Infisical has been promoted out of the legacy Tier 30 (`CT 330`) slot into **Zone 1 Immutable Core (`CT 110` at `192.168.100.10`)**, provisioned out-of-band outside Terraform state and ACLs so it survives all Zone 2–4 rebuilds and eliminates static `.vault_pass` / `terraform.tfvars` secrets on the disposable control node (`haytham-ctl`).

## Original Context (Historical)

The initial pre-hardening blueprint deferred Infisical under legacy Tier 30 (`CTID 330`) because no application required runtime secrets beyond Ansible Vault. Once an AI agent was placed on the Linux control node, storing plaintext `.vault_pass` and static credentials on `haytham-ctl` became unacceptable, triggering promotion of lean-tuned Infisical to Zone 1 (`services/zone1-infisical-110.md`).

## Status

Superseded by `ADR-008`.
