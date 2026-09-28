#!/usr/bin/env python3
"""Exercise the real shipped engine through its CLI, using only synthetic files."""
import json
import os
from pathlib import Path
import signal
import sqlite3
import subprocess
import sys
import time

binary, base, mode = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve(), sys.argv[3]
base.mkdir(parents=True, exist_ok=True)
home = base / 'home'
home.mkdir(exist_ok=True)
root = home / 'Notes'
root.mkdir(exist_ok=True)
(root / '.git').mkdir(exist_ok=True)
db, config = base / 'index.db', base / 'index.json'
config.write_text(json.dumps({'roots': [str(root)]}))
env = {**os.environ, 'HOME': str(home), 'CFFIXED_USER_HOME': str(home),
       'TL_MARKDOWN_STATE_DIR': str(base / 'state')}
env.pop('MDINDEX_DB', None)


def run(*args, code=0):
    result = subprocess.run([str(binary), *map(str, args)], env=env, text=True,
                            capture_output=True, timeout=30)
    assert result.returncode == code, (args, result.returncode, result.stdout, result.stderr)
    return result


def index(*args):
    return run('index', '--config', config, '--db', db, *args)


def paths():
    with sqlite3.connect(f'file:{db}?mode=ro', uri=True) as con:
        return {Path(r[0]).name for r in con.execute('SELECT path FROM doc')}


run('--help')
assert run('--version').stdout.strip()
a = root / 'alpha.md'
a.write_text('# 生态流量\n水库中的 reservoir\nsecond reservoir\n')
os.utime(a, (1704067200, 1704067200))
(root / 'nul.md').write_bytes(b'# binary\x00reservoir')
os.mkfifo(root / 'pipe.md')
(root / 'alias.md').symlink_to(a)
(root / 'node_modules').mkdir()
(root / 'node_modules/hidden.md').write_text('reservoir')

if mode == 'functionality':
    index('--full')
    assert paths() == {'alpha.md'}, paths()
    result = run('search', 'reservoir', '--db', db, '--per-file', '1')
    assert f'  ~/Notes/alpha.md:2\t水库中的 reservoir\n' in result.stdout, result.stdout
    assert result.stderr == '\n-- 1 个文件命中 (limit=20) --\n', result.stderr
    short = run('search', '水库', '--db', db)
    assert '[note] 查询词 2 字符 < 3, 已自动改走 LIKE (结果等价, 略慢)\n' in short.stderr
    assert ':2\t水库中的 reservoir' in short.stdout
    for options in [('--ws', 'Notes'), ('--repo', 'Notes'), ('--since', '2024-01-01'),
                    ('--path', 'alpha.md')]:
        assert 'alpha.md' in run('files', 'reservoir', '--db', db, *options).stdout
    assert run('files', 'reservoir', '--db', db, '--since', '2099-01-01').stdout == ''
    assert 'alpha.md' in run('files', '生态流量', '--db', db, '--title').stdout
    assert run('files', 'reservoir', '--db', db, '--title').stdout == ''
    assert json.loads(run('stats', '--db', db, '--json').stdout)
    assert json.loads(run('search', '水库', '--db', db, '--json').stdout)
    index()
    with sqlite3.connect(db) as con:
        original_id = con.execute('SELECT id FROM doc').fetchone()[0]
    index()
    with sqlite3.connect(db) as con:
        assert con.execute('SELECT id FROM doc').fetchone()[0] == original_id
    a.write_text('# Changed\nupdated phrase\n')
    (root / 'added.md').write_text('# Added\nnew phrase\n')
    index()
    assert paths() == {'alpha.md', 'added.md'}
    assert 'alpha.md' in run('files', 'updated', '--db', db).stdout
    a.unlink()
    index()
    assert paths() == {'added.md'}
    graph = run('graph', root, '--launcher', '-n', '--config', config)
    html = root / '知识图谱.html'
    launcher = root / '知识图谱.command'
    assert html.is_file() and 'folio graph' in launcher.read_text()
    html.write_text('User-owned content')
    run('graph', root, '-n', '--config', config, code=1)
    assert html.read_text() == 'User-owned content'
elif mode == 'recovery':
    db.write_bytes(b'corrupt database fixture')
    index()
    assert paths() == {'alpha.md'}
    assert any('corrupt' in p.name and p.read_bytes() == b'corrupt database fixture'
               for p in base.iterdir() if p.is_file() and p != db)
    missing = run('index', '--config', base / 'missing.json', '--db', base / 'absent.db', code=1)
    assert missing.stderr.strip() and not (base / 'absent.db').exists()
    # A separate engine test deterministically cancels in the scan and checks rollback.
    assert (Path(__file__).resolve().parents[2] / 'Tests/IndexEngineTests.swift').is_file()
elif mode == 'privacy':
    missing = run('index', '--config', base / 'missing.json', '--db', base / 'absent.db', code=1)
    assert missing.stderr.strip() and not (base / 'absent.db').exists()
    run('index', code=1)
    assert not (base / 'state/md_index.db').exists()
    excluded = root / 'Excluded'
    excluded.mkdir()
    (excluded / 'secret.md').write_text('SYNTHETIC_SECRET_TOKEN')
    config.write_text(json.dumps({'roots': [str(root)], 'full_text_excluded_paths': [str(excluded)]}))
    index()
    assert paths() == {'alpha.md'}
    assert run('files', 'SYNTHETIC_SECRET_TOKEN', '--db', db).stdout == ''
    project = Path(__file__).resolve().parents[2]
    forbidden = [b'/Users/', b'ip-legal', b'Personal/legal', b'investment']
    shipped = list((project / 'Sources').glob('*.swift')) + list((project / 'CLI').glob('*.swift'))
    shipped += [project / 'Resources/graph-view.html', binary]
    for path in shipped:
        data = path.read_bytes()
        assert not any(term in data for term in forbidden), f'Private string in {path.name}'
    assert binary.stat().st_size <= 2_000_000
else:
    raise AssertionError(mode)
print(json.dumps({'ok': True, 'mode': mode, 'scope': 'synthetic CLI and shared engine'}, ensure_ascii=False))
