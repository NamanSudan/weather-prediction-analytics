"""Superset configuration (mounted read-only; every secret comes from the environment)."""

import os

SECRET_KEY = os.environ["SUPERSET_SECRET_KEY"]
SQLALCHEMY_DATABASE_URI = f"postgresql+psycopg2://airflow:{os.environ['POSTGRES_PASSWORD']}@postgres:5432/superset"

FEATURE_FLAGS = {
    "DASHBOARD_NATIVE_FILTERS": True,
    "DASHBOARD_CROSS_FILTERS": True,
    "ENABLE_TEMPLATE_PROCESSING": True,
}

# Local-only lab deployment: no public signup, no CSP report noise.
AUTH_USER_REGISTRATION = False
TALISMAN_ENABLED = False
WTF_CSRF_ENABLED = True
ROW_LIMIT = 50000
CACHE_CONFIG = {"CACHE_TYPE": "SimpleCache", "CACHE_DEFAULT_TIMEOUT": 300}
DATA_CACHE_CONFIG = CACHE_CONFIG
