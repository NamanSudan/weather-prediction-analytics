# Guardrails for every Snowflake Terraform plan.
# Run: make policy   (terraform show -json tfplan | conftest test -)
package snowflake

allowed_resources := {
	"snowflake_warehouse",
	"snowflake_database",
	"snowflake_schema",
	"snowflake_account_role",
	"snowflake_grant_account_role",
	"snowflake_grant_privileges_to_account_role",
	"snowflake_service_user",
	"snowflake_user",
	"random_password",
}

allowed_warehouse_sizes := {"XSMALL", "X-SMALL", "SMALL"}

privileged_roles := {"ACCOUNTADMIN", "SECURITYADMIN", "ORGADMIN", "USERADMIN"}

# resource types whose `comment` must document purpose/ownership
commented_types := {
	"snowflake_warehouse", "snowflake_database", "snowflake_schema",
	"snowflake_account_role", "snowflake_service_user", "snowflake_user",
}

changes contains rc if {
	some rc in input.resource_changes
	some action in rc.change.actions
	action in {"create", "update"}
}

deny contains msg if {
	some rc in changes
	not allowed_resources[rc.type]
	msg := sprintf("%s: resource type %s is not on the allow-list", [rc.address, rc.type])
}

# --- cost -------------------------------------------------------------------
deny contains msg if {
	some rc in changes
	rc.type == "snowflake_warehouse"
	not allowed_warehouse_sizes[upper(rc.change.after.warehouse_size)]
	msg := sprintf("%s: warehouse_size %v not allowed (XSMALL/SMALL only; account is paid on-demand)", [rc.address, rc.change.after.warehouse_size])
}

deny contains msg if {
	some rc in changes
	rc.type == "snowflake_warehouse"
	not warehouse_suspends_fast(rc.change.after)
	msg := sprintf("%s: auto_suspend must be between 1 and 300 seconds", [rc.address])
}

warehouse_suspends_fast(after) if {
	after.auto_suspend > 0
	after.auto_suspend <= 300
}

deny contains msg if {
	some rc in changes
	rc.type == "snowflake_warehouse"
	not bounded_statements(rc.change.after)
	msg := sprintf("%s: statement_timeout_in_seconds must be set (1..3600) so no query runs away", [rc.address])
}

bounded_statements(after) if {
	after.statement_timeout_in_seconds > 0
	after.statement_timeout_in_seconds <= 3600
}

# warehouses: USAGE only; resizing/owning stays with SYSADMIN (the account owner's Terraform)
deny contains msg if {
	some rc in changes
	rc.type == "snowflake_grant_privileges_to_account_role"
	some obj in rc.change.after.on_account_object
	obj.object_type == "WAREHOUSE"
	some p in rc.change.after.privileges
	p != "USAGE"
	msg := sprintf("%s: only USAGE may be granted on warehouses (got %s)", [rc.address, p])
}

# account-level privileges (CREATE DATABASE/USER/ROLE, MANAGE GRANTS, ...) are owner-only
deny contains msg if {
	some rc in changes
	rc.type == "snowflake_grant_privileges_to_account_role"
	rc.change.after.on_account == true
	msg := sprintf("%s: account-level privileges are reserved for the account owner", [rc.address])
}

# collaborators must not inherit pipeline roles (that would leak WEATHER_WH + write access)
deny contains msg if {
	some rc in changes
	rc.type == "snowflake_grant_account_role"
	upper(rc.change.after.parent_role_name) == "LAB_DEVELOPER"
	msg := sprintf("%s: LAB_DEVELOPER must not inherit other roles", [rc.address])
}

deny contains msg if {
	some rc in changes
	rc.type == "snowflake_user"
	not rc.change.after.days_to_expiry
	msg := sprintf("%s: collaborator access must expire (days_to_expiry)", [rc.address])
}

# --- security ---------------------------------------------------------------
deny contains msg if {
	some rc in changes
	rc.type == "snowflake_grant_account_role"
	privileged_roles[upper(rc.change.after.role_name)]
	msg := sprintf("%s: granting %s is forbidden; use a functional role", [rc.address, rc.change.after.role_name])
}

deny contains msg if {
	some rc in changes
	rc.type == "snowflake_grant_privileges_to_account_role"
	rc.change.after.all_privileges == true
	msg := sprintf("%s: ALL PRIVILEGES is forbidden; list privileges explicitly", [rc.address])
}

deny contains msg if {
	some rc in changes
	rc.type == "snowflake_service_user"
	not has_value(rc.change.after, "rsa_public_key")
	msg := sprintf("%s: service users must authenticate with an RSA public key", [rc.address])
}

deny contains msg if {
	some rc in changes
	rc.type == "snowflake_user"
	rc.change.after.must_change_password != "true"
	msg := sprintf("%s: human users must change the one-time password at first login", [rc.address])
}

deny contains msg if {
	some rc in changes
	rc.type == "snowflake_user"
	not has_value(rc.change.after, "email")
	msg := sprintf("%s: human users need an email for onboarding and notifications", [rc.address])
}

# --- hygiene & safety -------------------------------------------------------
deny contains msg if {
	some rc in changes
	commented_types[rc.type]
	not has_value(rc.change.after, "comment")
	msg := sprintf("%s: a comment describing purpose/owner is required", [rc.address])
}

deny contains msg if {
	some rc in input.resource_changes
	rc.type in {"snowflake_database", "snowflake_schema"}
	"delete" in rc.change.actions
	msg := sprintf("%s: plan would DROP data (%v); do it deliberately outside the pipeline", [rc.address, rc.change.actions])
}

has_value(obj, key) if {
	v := obj[key]
	v != null
	v != ""
}
