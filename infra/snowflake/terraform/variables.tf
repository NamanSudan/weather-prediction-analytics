# --- connection ---------------------------------------------------------------
variable "snowflake_organization_name" {
  description = "Snowflake organization name (SELECT CURRENT_ORGANIZATION_NAME())."
  type        = string
}

variable "snowflake_account_name" {
  description = "Snowflake account name (SELECT CURRENT_ACCOUNT_NAME())."
  type        = string
}

variable "terraform_user" {
  description = "Service user Terraform authenticates as (created by the bootstrap SQL)."
  type        = string
  default     = "SVC_TERRAFORM"
}

variable "terraform_private_key_path" {
  description = "Path to SVC_TERRAFORM's encrypted PKCS#8 private key."
  type        = string
  default     = "../../../secrets/snowflake/svc_terraform/rsa_key.p8"
}

variable "terraform_private_key_passphrase" {
  description = "Passphrase for the Terraform private key. Supply via TF_VAR_terraform_private_key_passphrase."
  type        = string
  sensitive   = true
}

# --- naming -------------------------------------------------------------------
variable "database_name" {
  description = "Lab database."
  type        = string
  default     = "WEATHER_DB"
}

variable "warehouse_name" {
  description = "Single shared compute warehouse."
  type        = string
  default     = "WEATHER_WH"
}

variable "dev_warehouse_name" {
  description = "Warehouse for human collaborators (separately hard-capped)."
  type        = string
  default     = "DEV_WH"
}

variable "warehouse_size" {
  description = "Warehouse size. Policy only allows XSMALL/SMALL."
  type        = string
  default     = "XSMALL"

  validation {
    condition     = contains(["XSMALL", "SMALL"], var.warehouse_size)
    error_message = "Only XSMALL or SMALL warehouses are allowed on this paid on-demand account."
  }
}

variable "secrets_dir" {
  description = "Directory holding <service>/rsa_key.pub for each service user."
  type        = string
  default     = "../../../secrets/snowflake"
}

# --- people -------------------------------------------------------------------
variable "developers" {
  description = <<-EOT
    Human collaborators to create, keyed by Snowflake user name. Each gets the LAB_DEVELOPER role
    (lab database only, DEV_WH only), a personal DEV_<NAME> schema, and a random one-time password
    (must be changed at first login; Snowflake prompts MFA enrolment).
    enabled = false disables the login without deleting anything; days_to_expiry makes access lapse
    automatically after the lab.
  EOT
  type = map(object({
    first_name     = string
    last_name      = string
    email          = string
    enabled        = optional(bool, true)
    days_to_expiry = optional(number, 14)
  }))
  default = {}
}

variable "existing_developer_users" {
  description = "Pre-existing users (not managed here) that should also get LAB_DEVELOPER, e.g. the account owner."
  type        = list(string)
  default     = []
}
