package snowflake_test

import data.snowflake

rc(type, after) := {"address": sprintf("%s.x", [type]), "type": type, "change": {"actions": ["create"], "after": after}}

good_wh := {"warehouse_size": "XSMALL", "auto_suspend": 60, "statement_timeout_in_seconds": 600, "comment": "ok"}

test_good_warehouse_passes if {
	count(snowflake.deny) == 0 with input as {"resource_changes": [rc("snowflake_warehouse", good_wh)]}
}

test_large_warehouse_denied if {
	count(snowflake.deny) == 1 with input as {"resource_changes": [rc("snowflake_warehouse", object.union(good_wh, {"warehouse_size": "LARGE"}))]}
}

test_no_auto_suspend_denied if {
	count(snowflake.deny) == 1 with input as {"resource_changes": [rc("snowflake_warehouse", object.union(good_wh, {"auto_suspend": 0}))]}
}

test_accountadmin_grant_denied if {
	count(snowflake.deny) == 1 with input as {"resource_changes": [rc("snowflake_grant_account_role", {"role_name": "ACCOUNTADMIN", "user_name": "X"})]}
}

test_service_user_without_key_denied if {
	count(snowflake.deny) == 1 with input as {"resource_changes": [rc("snowflake_service_user", {"comment": "svc", "rsa_public_key": null})]}
}

test_human_user_must_change_password if {
	count(snowflake.deny) == 1 with input as {"resource_changes": [rc("snowflake_user", {"comment": "h", "email": "a@b.edu", "must_change_password": "false", "days_to_expiry": 14})]}
}

test_unknown_resource_denied if {
	count(snowflake.deny) == 1 with input as {"resource_changes": [rc("snowflake_table", {})]}
}

test_missing_comment_denied if {
	count(snowflake.deny) == 1 with input as {"resource_changes": [rc("snowflake_schema", {"comment": ""})]}
}

test_database_drop_denied if {
	count(snowflake.deny) == 1 with input as {"resource_changes": [{"address": "snowflake_database.x", "type": "snowflake_database", "change": {"actions": ["delete"], "after": null}}]}
}

test_unbounded_statement_timeout_denied if {
	count(snowflake.deny) == 1 with input as {"resource_changes": [rc("snowflake_warehouse", object.union(good_wh, {"statement_timeout_in_seconds": 172800}))]}
}

test_warehouse_modify_grant_denied if {
	count(snowflake.deny) == 1 with input as {"resource_changes": [rc("snowflake_grant_privileges_to_account_role", {"privileges": ["USAGE", "MODIFY"], "on_account_object": [{"object_type": "WAREHOUSE", "object_name": "DEV_WH"}]})]}
}

test_warehouse_usage_grant_passes if {
	count(snowflake.deny) == 0 with input as {"resource_changes": [rc("snowflake_grant_privileges_to_account_role", {"privileges": ["USAGE"], "on_account_object": [{"object_type": "WAREHOUSE", "object_name": "DEV_WH"}]})]}
}

test_developer_inheritance_denied if {
	count(snowflake.deny) == 1 with input as {"resource_changes": [rc("snowflake_grant_account_role", {"role_name": "TRANSFORMER", "parent_role_name": "LAB_DEVELOPER"})]}
}

test_account_level_privilege_denied if {
	count(snowflake.deny) == 1 with input as {"resource_changes": [rc("snowflake_grant_privileges_to_account_role", {"privileges": ["CREATE DATABASE"], "on_account": true})]}
}

test_user_without_expiry_denied if {
	count(snowflake.deny) == 1 with input as {"resource_changes": [rc("snowflake_user", {"comment": "h", "email": "a@b.edu", "must_change_password": "true"})]}
}
