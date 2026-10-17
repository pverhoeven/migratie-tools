"""Genereert één versie van het template met de context uit .cruft.json, op dezelfde
manier als cruft dat bij een update doet (inclusief de skip-paden).

Gebruik: render-template.py <.cruft.json> <template-clone> <commit> <uitvoermap> <context.json>
Schrijft de gebruikte cookiecutter-context naar <context.json>.
"""
import json
import sys
from pathlib import Path

from cruft._commands import utils
from git import Repo

cruft_file, template_dir, commit, output_dir, context_file = sys.argv[1:6]
state = json.loads(Path(cruft_file).read_text())
context = utils.generate.cookiecutter_template(
    output_dir=Path(output_dir),
    repo=Repo(template_dir),
    cruft_state=state,
    checkout=commit,
)
Path(context_file).write_text(json.dumps(context, ensure_ascii=False, indent=2))
