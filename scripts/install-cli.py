#!/usr/bin/env python3
"""Install only the verified Folio command symlink; never overwrite an unrelated file."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def install(app):
    target = app / 'Contents/Resources/bin/folio'
    stamp = json.loads((app / 'Contents/Resources/FolioBuild.json').read_text())
    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    if digest != stamp.get('cli_sha256'):
        raise RuntimeError('Bundled CLI does not match its build stamp')
    subprocess.run(['codesign', '--verify', '--strict', str(target)], check=True)
    subprocess.run([str(target), '--help'], check=True, capture_output=True)
    link = Path.home() / '.local/bin/folio'
    link.parent.mkdir(parents=True, exist_ok=True)
    if link.is_symlink():
        if link.resolve() == target.resolve():
            return str(link)
        raise RuntimeError('folio already points to another installation; left unchanged')
    if link.exists():
        raise RuntimeError('folio is an existing file; left unchanged')
    link.symlink_to(target)
    assert link.resolve() == target.resolve()
    return str(link)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    print(install(parser.parse_args().app))
