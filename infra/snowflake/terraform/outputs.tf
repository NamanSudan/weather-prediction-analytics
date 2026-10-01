output "snowsight_url" {
  description = "Where collaborators sign in."
  value       = "https://app.snowflake.com/${lower(var.snowflake_organization_name)}/${lower(var.snowflake_account_name)}"
}

output "account_identifier" {
  description = "<org>-<account>, used by dbt, Airflow, Superset and Grafana connections."
  value       = "${lower(var.snowflake_organization_name)}-${lower(var.snowflake_account_name)}"
}

output "developer_logins" {
  description = "Login names of human collaborators."
  value       = keys(var.developers) # login_name == user name; the provider marks login_name sensitive
}

output "developer_initial_passwords" {
  description = "One-time passwords (must be changed at first login). Read with: terraform output -json developer_initial_passwords"
  value       = { for k, p in random_password.developer : k => p.result }
  sensitive   = true
}

output "service_users" {
  description = "Service users and their default roles."
  value       = { for k, u in snowflake_service_user.this : k => u.default_role }
}
