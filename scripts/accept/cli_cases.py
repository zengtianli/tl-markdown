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


def run_env(extra, *args, code=0):
    result = subprocess.run([str(binary), *map(str, args)], env={**env, **extra}, text=True,
                            capture_output=True, timeout=30)
    assert result.returncode == code, (args, result.returncode, result.stdout, result.stderr)
    return result


def same(a, b):
    return os.path.realpath(str(a)) == os.path.realpath(str(b))


def agent_surface():
    """Agent-facing commands: help, exit codes, stable JSON, sandboxed writes, read-only state."""
    for name in ['status', 'read', 'outline', 'write', 'open', 'index', 'build', 'search', 'files', 'stats', 'config', 'roots', 'session', 'graph', 'asset']:
        assert run(name, '--help').stdout.startswith('用法：folio'), name
    run('bogus', code=2)
    run(code=2)
    run('stats', 'extra', code=2)
    run('stats', '--full', code=2)
    run('search', '--limit', '-1', code=2)
    failure = json.loads(run('bogus', '--json', code=2).stdout)
    assert failure['ok'] is False and failure['usage'] is True and failure['error'], failure
    missing = json.loads(run('stats', '--db', base / 'absent.db', '--json', code=1).stdout)
    assert missing['ok'] is False and missing['usage'] is False
    assert not (base / 'absent.db').exists()

    agent = home / 'Agent'
    (agent / '.git').mkdir(parents=True)
    plan = agent / 'plan.md'
    plan.write_text('# Plan\n取 10% 多年平均\n  Reservoir level\nreservoir again\n')
    (agent / 'snake.md').write_text('# Snake\nsnake_case\n')
    (agent / '水库.md').write_text('no heading\n')
    cfg, agent_db = base / 'agent.json', base / 'agent.db'

    # roots: the Settings add/remove rules, only on the named index.json
    added = json.loads(run('roots', 'add', agent, '--config', cfg, '--json').stdout)
    assert added['ok'] and added['changed'] and len(added['added']) == 1 and same(added['added'][0], agent), added
    again = json.loads(run('roots', 'add', agent, '--config', cfg, '--json').stdout)
    assert not again['changed'] and len(again['unchanged']) == 1
    saved = cfg.read_bytes()
    run('roots', 'add', base / 'no-such-folder', '--config', cfg, code=1)
    assert cfg.read_bytes() == saved and (cfg.stat().st_mode & 0o777) == 0o600
    assert same(json.loads(run('roots', '--config', cfg, '--json').stdout)['roots'][0], agent)
    built = json.loads(run('index', '--config', cfg, '--db', agent_db, '--json').stdout)
    assert built['ok'] and built['count'] == 3 and built['database_source'] == 'option' and 'changed' in built, built

    def q(*args):
        return json.loads(run(*args, '--db', agent_db, '--json').stdout)

    def names(result):
        return [Path(f['path']).name for f in result['files']]
    # search semantics are the sidebar's: literal %/_, title or body, trimmed, case-insensitive lines
    percent = q('files', '%')
    assert percent['ok'] and percent['mode'] == 'like' and names(percent) == ['plan.md'] and percent['files'][0]['lines'] == []
    assert names(q('files', '_')) == ['snake.md']
    assert names(q('files', '水库')) == ['水库.md']
    hits = q('search', ' reservoir ')
    assert hits['query'] == 'reservoir' and hits['mode'] == 'fts' and hits['count'] == 1, hits
    assert hits['files'][0]['lines'] == [{'line': 3, 'text': 'Reservoir level'}, {'line': 4, 'text': 'reservoir again'}]
    assert 'body' not in hits['files'][0] and 'again' in q('search', 'reservoir', '--body')['files'][0]['body']
    assert q('files', '--limit', '2')['truncated'] is True and q('files')['mode'] == 'filter'
    unlimited = q('files', '--limit', '0')
    assert unlimited['count'] == 3 and unlimited['truncated'] is False and unlimited['limit'] == 0, unlimited
    # an empty shell variable must not list the whole index
    blank = json.loads(run('files', '   ', '--db', agent_db, '--json', code=2).stdout)
    assert blank['ok'] is False and blank['usage'] is True, blank
    run('search', '', '--db', agent_db, code=2)
    # --since takes a real date; a malformed one is a usage error, not a silent empty result
    for bad in ['notadate', '2026-02-30', '2026-1-01', '2026-01-01T25:00', '2026-01-01 10:00']:
        run('files', '--since', bad, '--db', agent_db, code=2)
    assert q('files', '--since', '2000-01-01')['count'] == 3 and q('files', '--since', '2000-01-01T00:00')['count'] == 3
    assert q('files', '--since', '2999-12-31')['count'] == 0
    nothing = run('search', 'zzqqxxnomatch', '--db', agent_db, '--json')
    assert json.loads(nothing.stdout)['count'] == 0
    assert ':3\tReservoir level' in run('search', 'reservoir', '--db', agent_db).stdout
    stats = q('stats')
    assert stats['count'] == 3 and stats['updated_at'] and 'changed' not in stats
    assert '\tupdated=' in run('stats', '--db', agent_db).stdout
    config = json.loads(run('config', '--config', cfg, '--db', agent_db, '--json').stdout)
    assert config['ok'] and config['database']['source'] == 'option' and config['index']['count'] == 3
    assert config['roots'][0]['exists'] and 'rule_values' not in config
    assert 'rule_values' in json.loads(run('config', '--config', cfg, '--db', agent_db, '--show-rules', '--json').stdout)

    # session: read-only view of the app's own session.json (never written by the CLI)
    state = base / 'state'
    state.mkdir(exist_ok=True)
    def document(id, path, text, saved, conflict=False, message=''):
        doc = {'id': id, 'text': text, 'savedText': saved, 'lineEnding': '\n', 'bom': False, 'scroll': 0,
               'selection': 0, 'revision': 0, 'conflict': conflict, 'message': message}
        return {**doc, 'path': str(path)} if path else doc
    snapshot = {'documents': [document('A', plan, 'edited', 'orig', True, 'conflict'), document('B', None, 'draft text', '')],
                'activeID': 'A', 'recent': [{'path': str(plan), 'opened': 0, 'pinned': True, 'scroll': 0, 'selection': 0}],
                'settings': {'fontFamily': 'system', 'fontSize': 17, 'contentWidth': 820, 'restoreSession': True,
                             'imageFolder': 'pics', 'noteIndexPath': str(agent_db)},
                'closedDrafts': [document('C', None, 'closed draft', '')]}
    session_file = state / 'session.json'
    session_file.write_text(json.dumps(snapshot))
    before = (session_file.stat().st_mtime_ns, sorted(p.name for p in state.iterdir()))
    view = json.loads(run('session', '--json').stdout)
    a, b = view['documents']
    assert view['ok'] and view['active_id'] == 'A' and a['active'] and a['dirty'] and a['conflict'] and a['characters'] == 6
    assert 'text' not in a and 'path' not in b and b['dirty'] and view['recent'][0]['pinned']
    assert view['closed_drafts'][0]['characters'] == len('closed draft') and view['settings']['image_folder'] == 'pics'
    texts = json.loads(run('session', '--text', '--json').stdout)
    assert texts['documents'][0]['text'] == 'edited' and texts['closed_drafts'][0]['text'] == 'closed draft'
    only = json.loads(run('session', '--file', plan, '--json').stdout)
    assert [d['id'] for d in only['documents']] == ['A'] and only['closed_drafts'] == []
    assert 'plan.md' in run('session').stdout
    # the custom index path saved in Settings applies to every command; MDINDEX_DB still overrides it
    assert json.loads(run('stats', '--json').stdout)['database_source'] == 'settings'
    assert json.loads(run_env({'MDINDEX_DB': str(agent_db)}, 'stats', '--json').stdout)['database_source'] == 'environment'

    png_early = base / 'pixel.png'
    png_early.write_bytes(bytes.fromhex('89504e470d0a1a0a0000000d49484452'))
    # status: the read-back; version, config, index, folders, session summary and settings in one object
    status = json.loads(run('status', '--config', cfg, '--db', agent_db, '--json').stdout)
    assert status['ok'] and status['version'] and status['index']['count'] == 3 and status['roots'][0]['exists'], status
    assert status['session'] == {**status['session'], 'documents': 2, 'unsaved': 2, 'conflicts': 1, 'recent': 1, 'closed_drafts': 1}
    assert status['settings']['image_folder'] == 'pics' and same(status['state_directory'], state)
    assert '会话记录' in run('status', '--config', cfg, '--db', agent_db).stdout
    run('status', 'extra', code=2)

    # read / write: the editor's open and save rules (DocumentIO) on synthetic files
    crlf = agent / 'crlf.md'
    crlf.write_bytes(b'\xef\xbb\xbf# Title\r\nline two\r\n')
    got = json.loads(run('read', crlf, '--json').stdout)
    assert got['ok'] and got['text'] == '# Title\nline two\n' and got['line_ending'] == 'crlf' and got['bom'], got
    assert got['characters'] == 17 and got['lines'] == 2 and got['bytes'] == 22 and not got['open_in_folio']
    assert run('read', crlf).stdout == '# Title\nline two\n'
    wrote = json.loads(run('write', crlf, '--content', '# Title\nchanged\n', '--json').stdout)
    assert wrote['ok'] and wrote['changed'] and not wrote['created'] and wrote['line_ending'] == 'crlf' and wrote['bom'], wrote
    assert crlf.read_bytes() == b'\xef\xbb\xbf# Title\r\nchanged\r\n'      # line ending and BOM survive a save
    same_again = json.loads(run('write', crlf, '--content', '# Title\nchanged\n', '--json').stdout)
    assert same_again['ok'] and not same_again['changed']
    source = base / 'source.txt'
    source.write_text('# New\nfrom a file\n')
    fresh = agent / 'fresh.md'
    made = json.loads(run('write', fresh, '--from', source, '--json').stdout)
    assert made['created'] and fresh.read_text() == '# New\nfrom a file\n' and made['characters'] == 18
    piped = subprocess.run([str(binary), 'write', str(fresh), '--json'], env=env, input='piped\n', text=True, capture_output=True, timeout=30)
    assert piped.returncode == 0 and fresh.read_text() == 'piped\n', piped
    # outline: the sidebar's heading parser; fenced examples are not headings (same fixture as the editor test)
    run('write', fresh, '--content', '# Real\n\n````swift\n# Example only\n```\n# Still example\n````\n\n~~~\n# Tilde example\n~~~\n\n## After 标题\n')
    outline = json.loads(run('outline', fresh, '--json').stdout)
    assert outline['ok'] and outline['count'] == 2, outline
    assert outline['headings'] == [{'line': 1, 'level': 1, 'title': 'Real', 'offset': 0}, {'line': 13, 'level': 2, 'title': 'After 标题', 'offset': 84}], outline
    assert run('outline', fresh).stdout == '1\tReal\n13\t  After 标题\n'
    run('outline', agent / 'absent.md', code=1)
    run('outline', code=2)
    # a document with unsaved changes in the window is not overwritten unless forced
    plan_before = plan.read_bytes()
    refused = json.loads(run('write', plan, '--content', 'agent text\n', '--json', code=1).stdout)
    assert refused['ok'] is False and refused['usage'] is False and plan.read_bytes() == plan_before, refused
    seen = json.loads(run('read', plan, '--json').stdout)
    assert seen['open_in_folio'] and seen['dirty'] and seen['conflict']
    run('write', plan, '--content', plan_before.decode(), '--force')
    assert plan.read_bytes() == plan_before
    run('write', agent / 'shot.png', '--content', 'x', code=1)
    run('write', agent / 'no-such-folder/a.md', '--content', 'x', code=1)
    run('write', fresh, '--content', 'a', '--from', source, code=2)
    run('read', agent / 'absent.md', code=1)
    run('read', code=2)
    (agent / 'latin.md').write_bytes(b'caf\xe9')
    bad = json.loads(run('read', agent / 'latin.md', '--json', code=1).stdout)
    assert bad['ok'] is False and bad['error']
    # open: validated like the editor, then handed to the window; tests never launch the app (-n only)
    checked = json.loads(run('open', fresh, crlf, '-n', '--json').stdout)
    assert checked['ok'] and checked['opened'] is False and [Path(f).name for f in checked['files']] == ['fresh.md', 'crlf.md'], checked
    run('open', agent / 'absent.md', '-n', code=1)
    run('open', agent / 'latin.md', '-n', code=1)
    run('open', png_early, '-n', code=1)
    run('open', '-n', code=2)
    for extra in ['crlf.md', 'fresh.md', 'latin.md']:
        (agent / extra).unlink()

    # asset add: the editor's insert-image rule; the document is not modified
    png = png_early
    plan_bytes = plan.read_bytes()
    asset = json.loads(run('asset', 'add', plan, png, '--json').stdout)
    stored = Path(asset['path'])
    assert asset['ok'] and asset['folder'] == 'pics' and same(stored.parent, agent / 'pics') and stored.name.startswith('image-')
    assert asset['markdown'] == f'![图片](<pics/{stored.name}>)' and stored.read_bytes() == png.read_bytes()
    assert plan.read_bytes() == plan_bytes
    assert 'assets/' in run('asset', 'add', plan, png, '--folder', 'assets').stdout
    run('asset', 'add', plan, png, '--folder', '../outside', code=1)
    (base / 'note.txt').write_text('not an image')
    run('asset', 'add', plan, base / 'note.txt', code=1)
    run('asset', 'add', plan, code=2)
    assert (session_file.stat().st_mtime_ns, sorted(p.name for p in state.iterdir())) == before

    # an unreadable session fails without being rewritten
    session_file.write_text('not json')
    broken = json.loads(run('session', '--json', code=1).stdout)
    assert broken['ok'] is False and session_file.read_text() == 'not json'

    # graph --json never opens a browser and reports the page's counts
    graph = json.loads(run('graph', agent, '--json', '--config', cfg).stdout)
    assert graph['ok'] and Path(graph['path']).name == '知识图谱.html' and graph['files'] >= 3 and graph['nodes'] >= 1

    removed = json.loads(run('roots', 'remove', agent, '--config', cfg, '--json').stdout)
    assert removed['changed'] and removed['roots'] == []
    absent = json.loads(run('roots', 'remove', agent, '--config', cfg, '--json').stdout)
    assert not absent['changed'] and len(absent['not_found']) == 1


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
    agent_surface()
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
