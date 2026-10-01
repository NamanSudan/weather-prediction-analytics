"""Load Airflow connections and variables from code (runs in the airflow-init container).

connections.json.tpl -> env-var substitution -> `airflow connections import --overwrite`
variables.json       -> `airflow variables import --action-on-existing-key overwrite`

The rendered file holds secrets, so it only ever exists in a private temp dir and is deleted.
Re-running is safe: both imports overwrite, so the metadata DB always matches the repo.
"""

import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).parent


def render(template: Path) -> str:
    text = template.read_text()
    missing = sorted(set(re.findall(r"\$\{(\w+)\}", text)) - set(os.environ))
    if missing:
        sys.exit(f"missing env vars for {template.name}: {', '.join(missing)}")
    return os.path.expandvars(text)


def airflow(*args: str) -> None:
    subprocess.run(["airflow", *args], check=True)


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        rendered = Path(tmp) / "connections.json"
        rendered.write_text(render(HERE / "connections.json.tpl"))
        rendered.chmod(0o600)
        airflow("connections", "import", "--overwrite", str(rendered))
    airflow("variables", "import", "--action-on-existing-key", "overwrite", str(HERE / "variables.json"))
    print("airflow connections + variables loaded from config/airflow")


if __name__ == "__main__":
    main()
