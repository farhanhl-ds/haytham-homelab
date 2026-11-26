variable "pve_endpoint" {
  description = "Proxmox VE API URL, e.g.: https://192.168.100.2:8006/"
  type        = string
}

variable "pve_api_token" {
  description = "Format: terraform@pve!terraform=<secret-uuid>. Injected at runtime via TF_VAR_pve_api_token from Zone 1 Infisical (CT 110)."
  type        = string
  sensitive   = true
}

variable "ssh_public_key_path" {
  description = "Absolute path to revocable Control Node public key baked into every LXC (file() does not expand ~), e.g.: /var/lib/haytham-ops/.ssh/id_ed25519_control.pub"
  type        = string
}

variable "breakglass_ssh_public_key_path" {
  description = "Optional absolute path to Windows-only Break-Glass & Backup-Pull public key (survives control node key revocation), e.g.: /var/lib/haytham-ops/.ssh/windows_breakglass.pub"
  type        = string
  default     = ""
}

variable "ct_root_password" {
  description = "Root password for Terraform-managed containers (fallback via Proxmox console). Injected at runtime via TF_VAR_ct_root_password from Zone 1 Infisical (CT 110)."
  type        = string
  sensitive   = true
}
