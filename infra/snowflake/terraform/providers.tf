# Terraform authenticates as SVC_TERRAFORM (TYPE=SERVICE, key-pair JWT, no password/MFA),
# created once by infra/snowflake/bootstrap/00_bootstrap.sql.tpl.
#
# Two aliases keep duties separated:
#   default   -> SYSADMIN      : warehouses, databases, schemas (object owner)
#   security  -> SECURITYADMIN : roles, users, grants

provider "snowflake" {
  organization_name      = var.snowflake_organization_name
  account_name           = var.snowflake_account_name
  user                   = var.terraform_user
  role                   = "SYSADMIN"
  authenticator          = "SNOWFLAKE_JWT"
  private_key            = file(var.terraform_private_key_path)
  private_key_passphrase = var.terraform_private_key_passphrase
}

provider "snowflake" {
  alias                  = "security"
  organization_name      = var.snowflake_organization_name
  account_name           = var.snowflake_account_name
  user                   = var.terraform_user
  role                   = "SECURITYADMIN"
  authenticator          = "SNOWFLAKE_JWT"
  private_key            = file(var.terraform_private_key_path)
  private_key_passphrase = var.terraform_private_key_passphrase
}
