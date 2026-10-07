#!/usr/bin/env python3
"""Exercise the real shipped engine through its CLI, using only synthetic files."""
import base64
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import signal
import sqlite3
import subprocess
import sys
import threading
import time
import uuid

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
    for name in ['status', 'read', 'outline', 'write', 'open', 'index', 'build', 'search', 'files', 'stats', 'config', 'roots', 'session', 'settings', 'recent', 'tabs', 'graph', 'asset', 'update']:
        assert run(name, '--help').stdout.startswith('用法：folio'), name
    run('bogus', code=2)
    run(code=2)
    run('stats', 'extra', code=2)
    run('stats', '--full', code=2)
    run('search', '--limit', '-1', code=2)
    failure = json.loads(run('bogus', '--json', code=2).stdout)
    assert failure['ok'] is False and failure['usage'] is True and failure['error'] and failure['code'] == 'usage', failure
    missing = json.loads(run('stats', '--db', base / 'absent.db', '--json', code=1).stdout)
    assert missing['ok'] is False and missing['usage'] is False and missing['code'] == 'failed', missing
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
    assert 'app' not in status    # a binary outside Folio.app names no app bundle
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
    assert made['path'] == json.loads(run('read', fresh, '--json').stdout)['path']
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
    assert refused['code'] == 'window_unsaved', refused
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
    assert checked['app'] == 'cyou.tianli.TLMarkdown', checked
    run('open', agent / 'absent.md', '-n', code=1)
    run('open', agent / 'latin.md', '-n', code=1)
    run('open', png_early, '-n', code=1)
    run('open', '-n', code=2)
    run('open', fresh, '--example', '-n', code=2)
    # --example is the welcome page's document; a binary outside an app bundle has none to offer
    assert json.loads(run('open', '--example', '-n', '--json', code=1).stdout)['code'] == 'not_found'
    # settings / recent without an action only read: same values as status, nothing created in the state folder
    shown = json.loads(run('settings', '--json').stdout)
    assert shown['ok'] and shown['settings'] == status['settings'] and shown['limits']['font_size'] == [13, 26], shown
    assert 'changed' not in shown and 'applied_by' not in shown
    assert 'image_folder\tpics' in run('settings').stdout
    listed = json.loads(run('recent', '--json').stdout)
    assert listed['ok'] and listed['count'] == 1 and listed['recent'][0]['pinned'] and listed['recent'][0]['exists'], listed
    assert 'action' not in listed and '[固定]' in run('recent', 'list').stdout
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

    session_edits(state, session_file, snapshot, plan, agent)

    # an unreadable session fails without being rewritten, by the readers and by the writers
    session_file.write_text('not json')
    broken = json.loads(run('session', '--json', code=1).stdout)
    assert broken['ok'] is False and broken['code'] == 'session_unreadable' and session_file.read_text() == 'not json'
    for args in [('settings',), ('recent',), ('settings', 'set', 'font_size', '18'), ('recent', 'clear')]:
        refused = json.loads(run(*args, '--json', code=1).stdout)
        assert refused['code'] == 'session_unreadable' and session_file.read_text() == 'not json', (args, refused)

    # graph --json never opens a browser and reports the page's counts
    graph = json.loads(run('graph', agent, '--json', '--config', cfg).stdout)
    assert graph['ok'] and Path(graph['path']).name == '知识图谱.html' and graph['files'] >= 3 and graph['nodes'] >= 1

    removed = json.loads(run('roots', 'remove', agent, '--config', cfg, '--json').stdout)
    assert removed['changed'] and removed['roots'] == []
    absent = json.loads(run('roots', 'remove', agent, '--config', cfg, '--json').stdout)
    assert not absent['changed'] and len(absent['not_found']) == 1


def session_edits(state, session_file, snapshot, plan, agent):
    """settings set / recent …: the settings panel's and the recent list's changes, written to the same
    session.json. No window runs here, so the command edits the file itself (applied_by: file)."""
    def stored():
        return json.loads(session_file.read_text())
    changed = json.loads(run('settings', 'set', 'font_size', '21', 'content_width', '900', 'font_family', 'serif',
                             'restore_session', 'false', 'image_folder', 'img', '--json').stdout)
    assert changed['ok'] and changed['applied_by'] == 'file', changed
    assert changed['changed'] == ['font_family', 'font_size', 'content_width', 'restore_session', 'image_folder'], changed
    after = stored()
    assert after['settings'] == {**snapshot['settings'], 'fontSize': 21, 'contentWidth': 900, 'fontFamily': 'serif',
                                 'restoreSession': False, 'imageFolder': 'img'}, after['settings']
    # everything else in the record survives the rewrite: tabs with unsaved text, the active tab, closed drafts
    assert [d['text'] for d in after['documents']] == ['edited', 'draft text'] and after['documents'][0]['savedText'] == 'orig'
    assert after['documents'][0]['conflict'] is True and after['activeID'] == 'A' and after['closedDrafts'][0]['text'] == 'closed draft'
    assert (session_file.stat().st_mode & 0o777) == 0o600
    read_back = json.loads(run('status', '--json').stdout)['settings']
    assert read_back['font_size'] == 21 and read_back['font_family'] == 'serif' and read_back['restore_session'] is False
    assert json.loads(run('asset', 'add', plan, base / 'pixel.png', '--json').stdout)['folder'] == 'img'
    # ⌘+ / ⌘- stop at the same limits as the menu
    assert json.loads(run('settings', 'set', 'font_size', 'larger', '--json').stdout)['settings']['font_size'] == 22
    run('settings', 'set', 'font_size', '26')
    top = json.loads(run('settings', 'set', 'font_size', 'larger', '--json').stdout)
    assert top['settings']['font_size'] == 26 and top['changed'] == [], top
    run('settings', 'set', 'font_size', '13')
    assert json.loads(run('settings', 'set', 'font_size', 'smaller', '--json').stdout)['changed'] == []
    # the custom index: default returns every command to the default index
    cleared = json.loads(run('settings', 'set', 'note_index_path', 'default', '--json').stdout)
    assert cleared['changed'] == ['note_index_path'] and 'note_index_path' not in cleared['settings'], cleared
    assert json.loads(run('config', '--json').stdout)['database']['source'] == 'default'
    # a value outside the panel's range changes nothing and is a usage error
    saved = session_file.read_bytes()
    for bad in [('font_size', '40'), ('font_size', '17.5'), ('content_width', '825'), ('content_width', '2000'),
                ('font_family', 'comic'), ('image_folder', '../out'), ('image_folder', '/abs'), ('restore_session', 'maybe'),
                ('bogus', '1'), ('font_size',), ('font_size', '18', 'font_size', '19')]:
        refused = json.loads(run('settings', 'set', *bad, '--json', code=2).stdout)
        assert refused['ok'] is False and refused['usage'] is True, (bad, refused)
    assert json.loads(run('settings', 'set', 'font_size', '40', '--json', code=2).stdout)['code'] == 'invalid_value'
    run('settings', 'get', code=2)
    run('settings', 'set', code=2)
    assert session_file.read_bytes() == saved

    # recent: pin / unpin / remove / clear on a list with a file that no longer exists
    snake, gone = agent / 'snake.md', agent / 'moved-away.md'
    record = stored()
    record['recent'] = [{'path': str(p), 'opened': opened, 'pinned': False, 'scroll': 0, 'selection': 0}
                        for p, opened in [(plan, 300), (snake, 200), (gone, 100)]]
    session_file.write_text(json.dumps(record))
    def names(result):
        return [(item['name'], item['pinned']) for item in result['recent']]
    listed = json.loads(run('recent', '--json').stdout)
    assert names(listed) == [('plan.md', False), ('snake.md', False), ('moved-away.md', False)]
    assert [item['exists'] for item in listed['recent']] == [True, True, False]
    pinned = json.loads(run('recent', 'pin', snake, '--json').stdout)
    assert pinned['action'] == 'pin' and pinned['applied_by'] == 'file' and pinned['changed'] == [str(snake)], pinned
    assert names(pinned) == [('snake.md', True), ('plan.md', False), ('moved-away.md', False)]   # pinned first, as in the sidebar
    again = json.loads(run('recent', 'pin', snake, '--json').stdout)
    assert again['changed'] == [] and again['unchanged'] == [str(snake)]
    assert [(Path(r['path']).name, r['pinned']) for r in stored()['recent']] == [('snake.md', True), ('plan.md', False), ('moved-away.md', False)]
    unpinned = json.loads(run('recent', 'unpin', snake, '--json').stdout)
    assert names(unpinned) == [('plan.md', False), ('snake.md', False), ('moved-away.md', False)]
    removed = json.loads(run('recent', 'remove', gone, agent / 'never-opened.md', '--json').stdout)
    assert removed['changed'] == [str(gone)] and removed['not_found'] == [str(agent / 'never-opened.md')] and removed['count'] == 2, removed
    assert snake.exists() and plan.exists()      # only the record changes, never the file
    for bad in [('pin',), ('remove',), ('clear', 'extra'), ('list', 'extra'), ('forget', plan)]:
        run('recent', *bad, code=2)
    # a window that holds the session lock owns the file: the command asks it and, with no answer,
    # fails without writing and withdraws its request
    saved = session_file.read_bytes()
    with open(state / 'session.lock', 'a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        unanswered = json.loads(run('recent', 'clear', '--json', code=1).stdout)
        assert unanswered['ok'] is False and unanswered['code'] == 'window_no_reply', unanswered
        assert json.loads(run('recent', '--json').stdout)['count'] == 2      # reading never needs the lock
    assert session_file.read_bytes() == saved and list((state / 'requests').iterdir()) == []
    emptied = json.loads(run('recent', 'clear', '--json').stdout)
    assert emptied['cleared'] == 2 and emptied['count'] == 0 and stored()['recent'] == [], emptied
    assert len(stored()['documents']) == 2 and plan.exists()

    # open --example from inside an app bundle: the bundled guide is copied once and never overwritten
    bundle = base / 'Example.app/Contents/Resources'
    (bundle / 'bin').mkdir(parents=True, exist_ok=True)
    shutil.copy2(binary, bundle / 'bin/folio')
    (bundle / '欢迎使用.md').write_text('# 欢迎\n')
    def example():
        result = subprocess.run([str(bundle / 'bin/folio'), 'open', '--example', '-n', '--json'], env=env, text=True, capture_output=True, timeout=30)
        assert result.returncode == 0, result
        return json.loads(result.stdout)
    first = example()
    copy = state / '欢迎使用.md'
    assert first['opened'] is False and same(first['files'][0], copy) and copy.read_text() == '# 欢迎\n', first
    copy.write_text('# 本人改过\n')
    example()
    assert copy.read_text() == '# 本人改过\n'
    copy.unlink()


def lifecycle_and_tabs():
    """The「使用 iCloud 记住配置」switch is a preference, and a named preference domain is kept by the user's
    preferences daemon whatever HOME says: each run uses its own throwaway domain and removes it afterwards."""
    suite = 'test.tianli.folio.' + uuid.uuid4().hex
    try:
        lifecycle_and_tabs_cases(suite)
        upgrade_cases(suite)
    finally:
        subprocess.run(['/usr/bin/defaults', 'delete', suite], capture_output=True)
        forget_empty_preferences(suite)


def forget_empty_preferences(suite, patience=3.0):
    """The preferences daemon may write an empty 42-byte shell for a removed domain a moment after the last process
    that used it has gone. Wait for that moment, then remove the shell (never a file with anything in it)."""
    shell = Path.home() / 'Library/Preferences' / (suite + '.plist')
    deadline, quiet = time.monotonic() + patience, 0
    while time.monotonic() < deadline and quiet < 10:
        if shell.is_file() and shell.stat().st_size <= 42:
            shell.unlink()
            quiet = 0
        else:
            quiet += 1
        time.sleep(0.1)


def lifecycle_and_tabs_cases(suite):
    """config status|export|import|sync (the shared「配置与更新」command layer) and tabs close|restore|reload, with no
    window running: the command holds the session lock and works on session.json itself (applied_by: file). The
    state folder, the support folder and the "cloud" folder are inside the work folder; the switch is in `suite`."""
    state, support, cloud = base / 'lc-state', base / 'lc-support', base / 'lc-cloud'
    for folder in (state, support, cloud):
        shutil.rmtree(folder, ignore_errors=True)
    state.mkdir()
    lc = {'TL_MARKDOWN_STATE_DIR': str(state), 'APP_LIFECYCLE_SUPPORT_DIR': str(support), 'APP_LIFECYCLE_CLOUD_DIR': str(cloud),
          'FOLIO_PREFERENCES_SUITE': suite}
    session_file = state / 'session.json'

    def go(*args, code=0, extra=None):
        result = subprocess.run([str(binary), *map(str, args), '--json'], env={**env, **lc, **(extra or {})}, text=True, capture_output=True, timeout=60)
        assert result.returncode == code, (args, result.returncode, result.stdout, result.stderr)
        return json.loads(result.stdout), result.stderr

    def stored():
        return json.loads(session_file.read_text())

    def listing():
        return sorted(str(p.relative_to(base)) for folder in (state, support, cloud) if folder.exists() for p in folder.rglob('*'))

    def envelope(name, product='cyou.tianli.TLMarkdown', only=False, **changes):
        values = {} if only else {'file.0.settings.fontFamily': 'system', 'file.0.settings.fontSize': 17, 'file.0.settings.contentWidth': 820,
                                  'file.0.settings.restoreSession': True, 'file.0.settings.imageFolder': 'assets'}
        values.update({'file.0.settings.' + key: value for key, value in changes.items()})
        path = base / f'lc-{name}.json'
        path.write_text(json.dumps({'version': 1, 'product': product, 'values': values}))
        return path

    # help: every subcommand is listed in the top-level help as a command, and folio config --help still explains bare config
    top = run('--help').stdout
    for line in ['\n  config status ', '\n  update check ', '\n  config export -o <file> ', '\n  config import <file> --yes ', '\n  config sync on|off --yes ',
                 '\n  update install --yes ', '\n  tabs close ', '\n  tabs restore ', '\n  tabs reload ']:
        assert line in top, line
    # every item of the「配置与更新…」window has a command now: nothing is listed as having none, and the upgrade is a write
    assert '暂无命令' not in top and '静默' not in top and '打开「配置与更新…」窗口' in top.split('仅在窗口中')[-1]
    assert '\n  update install --yes ' in top.split('\n写入：')[1].split('\n通用参数')[0] and '同步状态' in top.split('\n  config status ')[1].split('\n')[0]
    for code in ['manual_install', 'needs_product_installer', 'upgrade_failed', 'app_busy', 'replace_failed', 'cleanup_failed']:
        assert code in top.split('退出码：')[0], code
    usage = run('config', '--help').stdout
    assert 'folio config [--show-rules]' in usage and 'folio config sync on|off --yes' in usage and 'applied_by' in usage
    assert 'sync_status{text, at, from, live}' in usage and all(word in usage for word in ['app（', 'record（', 'derived（']) and '由运行中的 App 持有' not in usage
    assert '\n    update install' not in usage      # config --help lists the three config writes; the upgrade is under update --help
    upgrade_usage = run('update', '--help').stdout
    assert run('config', 'sync', '--help').stdout == usage and run('update', 'check', '--help').stdout == upgrade_usage == run('update', 'install', '--help').stdout
    for word in ['folio update check [--json]', 'folio update install --yes [--dry-run] [--json]', 'would_install', 'will_quit_app', 'old_app_cleanup', 'upgrade: {in_app, button, how, download_url, command}',
                 'check_incomplete', 'manual_install', 'needs_product_installer', 'upgrade_failed', 'app_busy', 'replace_failed', 'cleanup_failed', 'isolation_incomplete', 'confirmation_required']:
        assert word in upgrade_usage, word
    assert '暂无命令' not in upgrade_usage and '静默' not in upgrade_usage

    # bare `folio config` is still the index configuration; an unknown word after it is a usage error as before
    assert 'state_directory' in json.loads(run('config', '--json').stdout)
    assert json.loads(run('config', 'bogus', '--json', code=2).stdout)['code'] == 'usage'
    for bad in [('update',), ('update', 'check', 'extra'), ('update', 'bogus'), ('update', 'install', 'extra'), ('update', 'install', '--no-such'),
                ('update', 'install', '-o', 'x'), ('config', 'status', 'extra'), ('config', 'export'),
                ('config', 'sync'), ('config', 'sync', 'maybe', '--yes'), ('config', 'import'), ('config', 'status', '--db', 'x')]:
        refused, err = go(*bad, code=2)
        assert refused['ok'] is False and refused['usage'] is True and refused['code'] == 'usage' and isinstance(refused['error'], str) and '[usage]' in err, (bad, refused)

    # half an isolation is refused: a test state folder with the owner's iCloud copy and preferences, or the reverse
    half = subprocess.run([str(binary), 'config', 'status', '--json'], env=env, text=True, capture_output=True, timeout=30)
    assert half.returncode == 1 and json.loads(half.stdout)['code'] == 'isolation_incomplete', half
    other = subprocess.run([str(binary), 'config', 'sync', 'on', '--yes', '--json'], text=True, capture_output=True, timeout=30,
                           env={**{k: v for k, v in env.items() if k != 'TL_MARKDOWN_STATE_DIR'}, 'APP_LIFECYCLE_SUPPORT_DIR': str(support)})
    # (the lock file is all a refused or mistyped write command leaves behind)
    assert other.returncode == 1 and json.loads(other.stdout)['code'] == 'isolation_incomplete' and listing() in ([], ['lc-state/session.lock']), (other, listing())

    # a session as the app leaves it: a saved tab, an untitled draft with unsaved text, a closed draft, a custom index
    notes = base / 'lc-notes'
    shutil.rmtree(notes, ignore_errors=True)
    notes.mkdir()
    one, two, three = notes / 'one.md', notes / 'two.md', notes / 'three.md'
    for path, text in [(one, '# One\n'), (two, '# Two\n'), (three, '# Three\n')]:
        path.write_text(text)

    def document(id, path, text, saved=None, on_disk=None, **more):
        doc = {'id': id, 'text': text, 'savedText': text if saved is None else saved, 'lineEnding': '\n', 'bom': False, 'scroll': 0,
               'selection': 0, 'revision': 0, 'conflict': False, 'message': '', **more}
        if path:
            doc['path'] = os.path.realpath(path)
            doc['diskData'] = base64.b64encode(Path(path).read_bytes() if on_disk is None else on_disk).decode()
        return doc
    record = {'documents': [document('ONE', one, '# One\n'), document('DRAFT', None, '没保存的草稿', saved='')], 'activeID': 'ONE', 'recent': [],
              'settings': {'fontFamily': 'serif', 'fontSize': 19, 'contentWidth': 860, 'restoreSession': True, 'imageFolder': 'pics', 'noteIndexPath': '/somewhere/index.db'},
              'closedDrafts': [document('CLOSED', None, '关掉的草稿', saved='')]}
    session_file.write_text(json.dumps(record))
    session_file.chmod(0o600)

    # config status: read-only, writes nothing (not even the lock file)
    before = (session_file.read_bytes(), listing())
    status, _ = go('config', 'status')
    # sync_status is the sentence under the window's switch; with no window and nothing synced yet it is the switch's initial one
    assert status == {'ok': True, 'command': 'config status', 'has_settings': True, 'sync_enabled': False, 'app_running': False, 'problem': None,
                      'sync_status': {'text': 'iCloud 配置同步已关闭', 'at': None, 'from': 'derived', 'live': False},
                      'keys': ['file.0.settings.' + k for k in ['contentWidth', 'fontFamily', 'fontSize', 'imageFolder', 'restoreSession']]}, status
    told = subprocess.run([str(binary), 'config', 'status'], env={**env, **lc}, text=True, capture_output=True, timeout=30)
    assert told.returncode == 0 and '\n同步状态：iCloud 配置同步已关闭' in told.stdout, told
    dry, _ = go('config', 'sync', 'on', '--dry-run')
    assert dry['dry_run'] is True and dry['would_change'] is True and dry['sync_enabled'] is False and 'applied_by' not in dry, dry
    needs, _ = go('config', 'sync', 'on', code=2)
    assert needs['code'] == 'confirmation_required' and needs['usage'] is True
    # export: the window's envelope, only the portable settings
    out = base / 'lc-out.json'
    out.unlink(missing_ok=True)
    exported, _ = go('config', 'export', '-o', out)
    written = json.loads(out.read_text())
    assert exported['bytes'] == out.stat().st_size and exported['keys'] == status['keys'] and same(exported['path'], out), exported
    assert written['product'] == 'cyou.tianli.TLMarkdown' and written['values'] == {'file.0.settings.fontFamily': 'serif', 'file.0.settings.fontSize': 19,
        'file.0.settings.contentWidth': 860, 'file.0.settings.restoreSession': True, 'file.0.settings.imageFolder': 'pics'}, written
    exists, _ = go('config', 'export', '-o', out, code=2)
    assert exists['code'] == 'file_exists' and exists['usage'] is True
    go('config', 'export', '-o', out, '--force')
    piped = subprocess.run([str(binary), 'config', 'export', '-o', '-'], env={**env, **lc}, text=True, capture_output=True, timeout=30)
    assert piped.returncode == 0 and json.loads(piped.stdout) == written
    unconfirmed, _ = go('config', 'import', out, code=2)
    assert unconfirmed['code'] == 'confirmation_required'
    assert (session_file.read_bytes(), listing()) == before, 'reading commands, a dry run and an unconfirmed write changed something'

    # import: refused whole when a value is outside the settings panel's limits, of the wrong type, missing, foreign or not portable
    for name, file in [('type', envelope('type', fontSize='big')), ('range', envelope('range', fontSize=99)), ('step', envelope('step', contentWidth=825)),
                       ('family', envelope('family', fontFamily='comic')), ('folder', envelope('folder', imageFolder='../out')),
                       ('switch', envelope('switch', restoreSession=1)), ('number', envelope('number', fontSize=True)),
                       ('partial', envelope('partial', only=True, fontSize=20)), ('foreign', envelope('foreign', product='someone.else')),
                       ('index', envelope('index', noteIndexPath='/other.db'))]:
        refused, err = go('config', 'import', file, '--yes', code=1)
        assert refused['code'] == 'import_rejected' and refused['ok'] is False and refused['usage'] is False and '[fail]' in err, (name, refused)
        assert session_file.read_bytes() == before[0], name
    missing, _ = go('config', 'import', base / 'lc-absent.json', '--yes', code=1)
    assert missing['code'] == 'not_found'
    # import: the portable settings change, everything else in the record stays, the file keeps its owner-only mode
    imported, _ = go('config', 'import', envelope('good', fontSize=21, contentWidth=900, fontFamily='mono', restoreSession=False, imageFolder='img'), '--yes')
    assert imported['imported'] is True and imported['applied_by'] == 'file' and imported['sync_enabled'] is False and imported['app_running'] is False and 'sync' not in imported, imported
    after = stored()
    assert after['settings'] == {'fontFamily': 'mono', 'fontSize': 21, 'contentWidth': 900, 'restoreSession': False, 'imageFolder': 'img', 'noteIndexPath': '/somewhere/index.db'}, after['settings']
    assert [d['text'] for d in after['documents']] == ['# One\n', '没保存的草稿'] and after['activeID'] == 'ONE' and after['closedDrafts'][0]['text'] == '关掉的草稿'
    assert (session_file.stat().st_mode & 0o777) == 0o600 and len(list((support / 'cyou.tianli.TLMarkdown/Backups').iterdir())) == 1
    view = json.loads(subprocess.run([str(binary), 'session', '--json'], env={**env, **lc}, text=True, capture_output=True, timeout=30).stdout)
    assert view['ok'] and view['settings']['font_size'] == 21 and len(view['documents']) == 2, view   # the app's own decoder still reads the record
    # a relative file name is resolved where the command was typed
    relative = subprocess.run([str(binary), 'config', 'import', envelope('relative', fontSize=22).name, '--yes', '--json'], cwd=base, env={**env, **lc}, text=True, capture_output=True, timeout=30)
    assert relative.returncode == 0 and stored()['settings']['fontSize'] == 22, relative

    # sync: the switch is stored for the next process to read; on uploads through the shared reconcile; an import made while it is on follows
    cloud_file = cloud / 'cyou.tianli.TLMarkdown.json'
    on, _ = go('config', 'sync', 'on', '--yes')
    assert on['changed'] is True and on['sync_enabled'] is True and on['applied_by'] == 'file' and on['action'] == 'on' and on['check_with'] == 'folio config status' and on['status'], on
    assert go('config', 'status')[0]['sync_enabled'] is True and json.loads(cloud_file.read_text())['values']['file.0.settings.fontSize'] == 22
    # no window is running: the sentence is the one that sync left behind, with when
    left = go('config', 'status')[0]['sync_status']
    assert left['text'] == on['status'] and left['from'] == 'record' and left['live'] is False and left['at'], left
    same_again, _ = go('config', 'sync', 'on', '--yes')
    assert same_again['changed'] is False and 'applied_by' not in same_again
    carried, _ = go('config', 'import', envelope('synced', fontSize=23), '--yes')
    assert carried['sync'] == {'completed': True, 'status': on['status']} and json.loads(cloud_file.read_text())['values']['file.0.settings.fontSize'] == 23, carried
    off, _ = go('config', 'sync', 'off', '--yes')
    assert off['changed'] is True and off['sync_enabled'] is False and go('config', 'status')[0]['sync_enabled'] is False
    closed_sentence = go('config', 'status')[0]['sync_status']
    assert closed_sentence['text'] == 'iCloud 配置同步已关闭' and closed_sentence['live'] is False and closed_sentence['from'] in ('record', 'derived'), closed_sentence
    # back to back, both orders: the second command's value is what every later process reads
    for last in (False, True, False):
        go('config', 'sync', 'off' if last else 'on', '--yes')
        go('config', 'sync', 'on' if last else 'off', '--yes')
        assert [go('config', 'status')[0]['sync_enabled'] for _ in range(5)] == [last] * 5, last
    local, _ = go('config', 'import', envelope('local', fontSize=24), '--yes')
    assert 'sync' not in local and stored()['settings']['fontSize'] == 24 and json.loads(cloud_file.read_text())['values']['file.0.settings.fontSize'] == 23
    assert len(stored()['documents']) == 2 and stored()['closedDrafts'][0]['text'] == '关掉的草稿'

    # a window that holds the lock owns the record: with no answer the command gives up quickly and nothing is written;
    # a window from before these commands answers the empty edit it can read, which is reported as outdated
    saved = session_file.read_bytes()
    with open(state / 'session.lock', 'a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        began = time.monotonic()
        unanswered, _ = go('config', 'import', envelope('held', fontSize=25), '--yes', code=1)
        assert unanswered['code'] == 'window_no_reply' and time.monotonic() - began < 15, unanswered
        held = go('config', 'status')[0]                              # reading never needs the lock
        # a window that has published no sentence yet shows the switch's initial one
        assert held['app_running'] is True and held['sync_status'] == {'text': 'iCloud 配置同步已关闭', 'at': None, 'from': 'derived', 'live': True}, held
        assert go('tabs', 'restore', code=1)[0]['code'] == 'window_no_reply'
        requests = state / 'requests'

        def old_window():
            deadline = time.monotonic() + 20
            while time.monotonic() < deadline:
                for request in requests.glob('*.request.json'):
                    request.unlink()
                    reply = {'outcome': {'settingsChanged': [], 'recentChanged': [], 'recentUnchanged': [], 'notFound': [], 'cleared': 0,
                                         'settings': after['settings'], 'recent': []}}
                    (requests / request.name.replace('.request.json', '.reply.json')).write_text(json.dumps(reply))
                    return
                time.sleep(0.01)
        for args in [('config', 'sync', 'on', '--yes'), ('tabs', 'close', one)]:
            answering = threading.Thread(target=old_window)
            answering.start()
            outdated, _ = go(*args, code=1)
            answering.join()
            assert outdated['code'] == 'window_outdated', (args, outdated)
    assert session_file.read_bytes() == saved and list((state / 'requests').iterdir()) == [] and go('config', 'status')[0]['sync_enabled'] is False

    # tabs close: a clean tab closes and joins the recent list; unsaved edits need an answer
    closed, _ = go('tabs', 'close', one)
    assert closed['action'] == 'close' and closed['id'] == 'ONE' and closed['applied_by'] == 'file' and closed['saved'] is False and closed['kept_draft'] is False, closed
    assert closed['documents'] == 1 and closed['active_id'] == 'DRAFT' and same(closed['session_file'], session_file)
    now = stored()
    assert [d['id'] for d in now['documents']] == ['DRAFT'] and now['activeID'] == 'DRAFT' and same(now['recent'][0]['path'], one) and one.read_text() == '# One\n'
    assert now['settings']['fontSize'] == 24 and (session_file.stat().st_mode & 0o777) == 0o600
    saved = session_file.read_bytes()
    unsaved, _ = go('tabs', 'close', 'DRAFT', code=1)
    assert unsaved['code'] == 'window_unsaved'
    assert go('tabs', 'close', 'DRAFT', '--save', code=1)[0]['code'] == 'failed'          # an untitled draft has no file name
    assert go('tabs', 'close', notes / 'never-opened.md', code=1)[0]['code'] == 'not_found'
    assert go('tabs', 'reload', 'DRAFT', code=1)[0]['code'] == 'failed'
    for bad in [('tabs',), ('tabs', 'frob'), ('tabs', 'close'), ('tabs', 'restore', 'x'), ('tabs', 'reload', one, '--save'), ('tabs', 'close', one, '--save', '--keep-draft'),
                ('tabs', 'restore', '--keep-draft')]:
        assert go(*bad, code=2)[0]['usage'] is True, bad
    assert session_file.read_bytes() == saved
    kept, _ = go('tabs', 'close', 'DRAFT', '--keep-draft')
    assert kept['kept_draft'] is True and kept['documents'] == 0 and kept['closed_drafts'] == 2 and 'active_id' not in kept, kept
    assert [d['id'] for d in stored()['closedDrafts']] == ['CLOSED', 'DRAFT']
    # tabs restore: the most recently closed draft first, as the current tab; nothing left is not_found
    first, _ = go('tabs', 'restore')
    assert first['action'] == 'restore' and first['id'] == 'DRAFT' and first['active_id'] == 'DRAFT' and first['closed_drafts'] == 1 and first['conflict'] is False, first
    restored = stored()['documents'][0]
    assert restored['text'] == '没保存的草稿' and restored['message'] == '已恢复关闭的草稿'
    assert go('tabs', 'restore')[0]['id'] == 'CLOSED'
    assert go('tabs', 'restore', code=1)[0]['code'] == 'not_found'
    # close --save: the edits go to the file by the editor's save rule; a file changed underneath refuses and keeps the tab
    record = stored()
    record['documents'] += [document('TWO', two, '# Two\n窗口里改过\n', saved='# Two\n'),
                            document('THREE', three, '# Three\n窗口里改过\n', saved='# Three\n', on_disk=b'# Three\n')]
    session_file.write_text(json.dumps(record))
    three.write_text('# Three\n别的软件改过\n')
    done, _ = go('tabs', 'close', two, '--save')
    assert done['saved'] is True and two.read_text() == '# Two\n窗口里改过\n' and 'TWO' not in [d['id'] for d in stored()['documents']], done
    conflict, _ = go('tabs', 'close', three, '--save', code=1)
    assert conflict['code'] == 'failed' and three.read_text() == '# Three\n别的软件改过\n' and 'THREE' in [d['id'] for d in stored()['documents']], conflict
    # tabs reload: the tab takes the file; the unsaved edits become a separate untitled draft
    count = len(stored()['documents'])
    reloaded, _ = go('tabs', 'reload', three)
    docs = {d['id']: d for d in stored()['documents']}
    assert reloaded['action'] == 'reload' and reloaded['draft_copy'] in docs and reloaded['documents'] == count + 1, reloaded
    assert docs['THREE']['text'] == '# Three\n别的软件改过\n' and docs['THREE']['savedText'] == docs['THREE']['text'] and docs['THREE']['conflict'] is False
    copy = docs[reloaded['draft_copy']]
    assert 'path' not in copy and copy['text'] == '# Three\n窗口里改过\n' and copy['message'] == '重新载入前的修改副本'
    assert 'draft_copy' not in go('tabs', 'reload', three)[0]                      # nothing unsaved: nothing to keep aside
    saved = session_file.read_bytes()
    three.unlink()
    assert go('tabs', 'reload', 'THREE', code=1)[0]['code'] == 'failed' and session_file.read_bytes() == saved
    # an unreadable record is left alone by every one of these
    session_file.write_text('not json')
    for args in [('config', 'import', envelope('good', fontSize=21), '--yes'), ('config', 'sync', 'on', '--yes'), ('tabs', 'restore'), ('tabs', 'close', 'DRAFT', '--keep-draft')]:
        assert go(*args, code=1)[0]['code'] == 'session_unreadable' and session_file.read_text() == 'not json', args
    assert go('config', 'status')[0]['sync_enabled'] is False


def upgrade_cases(suite):
    """update install, the window's「升级到新版…」as a command, on a throwaway signed app that holds the real folio in
    Resources/bin the way Folio.app holds the installed command (which is called through a link, as ~/.local/bin/folio
    is). The app, its isolated release record, the rollback copy and the "Trash" are all inside the work folder:
    APP_LIFECYCLE_NO_RELAUNCH keeps the last two under the isolated support folder, and nothing is opened."""
    stage = base / 'lc-upgrade'
    shutil.rmtree(stage, ignore_errors=True)
    fixture = 'test.tianli.folio.fixture'
    feed = stage / 'cloud/TianliApps/Updates' / fixture / 'isolated'
    feed.mkdir(parents=True)
    up = {**env, 'TL_MARKDOWN_STATE_DIR': str(stage / 'state'), 'APP_LIFECYCLE_SUPPORT_DIR': str(stage), 'APP_LIFECYCLE_CLOUD_DIR': str(stage / 'cloud'),
          'APP_LIFECYCLE_NO_RELAUNCH': '1', 'FOLIO_PREFERENCES_SUITE': suite}

    def signed(path, version, build):
        (path / 'Contents/MacOS').mkdir(parents=True)
        (path / 'Contents/Resources/bin').mkdir(parents=True)
        shutil.copyfile('/usr/bin/true', path / 'Contents/MacOS/Folio')
        shutil.copyfile(binary, path / 'Contents/Resources/bin/folio')
        for program in ('Contents/MacOS/Folio', 'Contents/Resources/bin/folio'):
            (path / program).chmod(0o755)
        (path / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': fixture, 'CFBundleExecutable': 'Folio', 'CFBundlePackageType': 'APPL',
                                                                   'CFBundleShortVersionString': version, 'CFBundleVersion': build, 'LSMinimumSystemVersion': '14.0'}))
        subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', '--identifier', 'cyou.tianli.TLMarkdown.cli', str(path / 'Contents/Resources/bin/folio')], check=True, capture_output=True, timeout=60)
        subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', str(path)], check=True, capture_output=True, timeout=60)

    def on_disk(path):
        info = plistlib.loads((path / 'Contents/Info.plist').read_bytes())
        return {'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion']}

    def publish(version, build, **changes):
        """The isolated channel's release record and package, as the private channel keeps them."""
        source = stage / f'source-{version}-{build}/Folio.app'
        if not source.exists():
            signed(source, version, build)
        package = feed / f'Folio-{version}-{build}.zip'
        package.unlink(missing_ok=True)
        subprocess.run(['/usr/bin/ditto', '-c', '-k', '--keepParent', str(source), str(package)], check=True, capture_output=True, timeout=120)
        record = {'version': version, 'build': build, 'bundle_id': fixture, 'channel': 'isolated', 'filename': package.name,
                  'sha256': hashlib.sha256(package.read_bytes()).hexdigest(), 'size_bytes': package.stat().st_size, **changes}
        (feed / 'release.json').write_text(json.dumps(record))

    installed = stage / 'installed/Folio.app'
    signed(installed, '1.2.1', '7')
    old, new = {'version': '1.2.1', 'build': '7'}, {'version': '1.3.0', 'build': '9'}
    (stage / 'bin').mkdir()
    command = stage / 'bin/folio'
    command.symlink_to(installed / 'Contents/Resources/bin/folio')

    def call(*args, code=0, through=command, environment=None, **more):
        result = subprocess.run([str(through), *map(str, args), '--json'], env=environment or up, text=True, capture_output=True, timeout=120, **more)
        assert result.returncode == code, (args, result.returncode, result.stdout, result.stderr)
        return json.loads(result.stdout)

    def untouched():
        return on_disk(installed) == old and not (stage / 'backups').exists() and not (stage / 'trash').exists() \
            and sorted(p.name for p in installed.parent.iterdir()) == ['Folio.app']

    # an isolated run reads the isolated release record, never the public channel or the network
    none = call('update', 'install', code=1)
    assert none['code'] == 'check_incomplete' and none['usage'] is False and isinstance(none['error'], str) and none['current'] == old \
        and none['source'] == {'kind': 'private_cloud', 'channel': 'isolated'} and untouched(), none
    assert call('update', 'check', code=1)['source'] == none['source']
    # no newer release: exit 0, installed false, with or without --yes
    publish('1.2.1', '7')
    for flags in ([], ['--yes'], ['--dry-run']):
        same_version = call('update', 'install', *flags)
        assert same_version['ok'] is True and same_version['command'] == 'update install' and same_version['installed'] is False and same_version['state'] == 'up_to_date' \
            and same_version['current'] == old and same_version['app_running'] is False and untouched(), (flags, same_version)
    told = subprocess.run([str(command), 'update', 'install', '--yes'], env=up, text=True, capture_output=True, timeout=60)
    assert told.returncode == 0 and '不需要升级' in told.stdout, told
    publish('1.2.0', '68')
    assert call('update', 'install', '--yes')['state'] == 'ahead_of_channel' and untouched()
    # a newer release: update check names the command, a dry run says what would happen, a missing --yes is exit 2
    publish(new['version'], new['build'])
    offer = call('update', 'check')
    assert offer['state'] == 'update_available' and offer['current'] == old and offer['latest']['version'] == new['version'] and offer['upgrade']['in_app'] is True \
        and offer['upgrade']['button'] == '升级到新版…' and offer['upgrade']['command'] == 'folio update install --yes' and offer['upgrade']['command'] in offer['upgrade']['how'], offer
    dry = call('update', 'install', '--dry-run')
    assert dry['dry_run'] is True and dry['installed'] is False and dry['would_install'] == {'from': old, 'to': new} and dry['installation'] == 'bundle' \
        and dry['will_quit_app'] is False and dry['will_relaunch'] is False and dry['app_running'] is False and untouched(), dry
    assert call('update', 'install', '--dry-run', '--yes')['dry_run'] is True and untouched()
    unconfirmed = subprocess.run([str(command), 'update', 'install', '--json'], env=up, text=True, capture_output=True, timeout=60)
    refused = json.loads(unconfirmed.stdout)
    assert unconfirmed.returncode == 2 and refused['ok'] is False and refused['code'] == 'confirmation_required' and refused['usage'] is True \
        and isinstance(refused['error'], str) and '[usage]' in unconfirmed.stderr and untouched(), unconfirmed
    # a package that does not match its record is refused, the app is as it was
    record = (feed / 'release.json').read_text()
    (feed / 'release.json').write_text(json.dumps(dict(json.loads(record), sha256='0' * 64)))
    wrong = call('update', 'install', '--yes', code=1)
    assert wrong['code'] == 'upgrade_failed' and wrong['current'] == old and untouched(), wrong
    (feed / 'release.json').write_text(record)
    # an app the command cannot replace where it is (the window shows「下载新版…」there): manual_install, nothing touched
    locked = stage / 'locked/Folio.app'
    shutil.copytree(installed, locked, symlinks=True)
    locked.parent.chmod(0o555)
    try:
        manual = call('update', 'install', '--yes', code=1, through=locked / 'Contents/Resources/bin/folio')
        button = call('update', 'check', through=locked / 'Contents/Resources/bin/folio')['upgrade']
    finally:
        locked.parent.chmod(0o755)
    assert manual['code'] == 'manual_install' and 'download_url' in manual and 'release_url' in manual and manual['usage'] is False and on_disk(locked) == old, manual
    assert button['in_app'] is False and button['button'] == '下载新版…' and button['command'] is None, button
    # a test or diagnostic run never replaces an app outside its own support folder: refused before anything is looked up
    outside = call('update', 'install', '--yes', code=1, through=binary)
    assert outside['code'] == 'isolation_incomplete' and outside['command'] == 'update install', outside
    half = call('update', 'install', '--yes', code=1, environment=env)       # its own state folder only: no network, nothing replaced
    assert half['code'] == 'isolation_incomplete', half
    assert untouched()
    # the real thing, through the link, while someone holds the session lock without being a process the command could
    # name (a test, as above): nobody is asked to quit. The command sits inside the app it replaces and still reports.
    (stage / 'state').mkdir(exist_ok=True)
    with open(stage / 'state/session.lock', 'a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        done = call('update', 'install', '--yes', start_new_session=True)
    assert done['ok'] is True and done['installed'] is True and done['state'] == 'installed' and done['previous'] == old and done['current'] == new \
        and done['backup'] is None and done['old_app_cleanup'] == 'trashed' and done['relaunched'] is False and done['app_running'] is False, done
    trashed = list((stage / 'trash').glob('*/Folio.app'))
    assert on_disk(installed) == new and not (stage / 'backups/Folio.app').exists() and len(trashed) == 1 and on_disk(trashed[0]) == old, (trashed, on_disk(installed))
    assert sorted(p.name for p in installed.parent.iterdir()) == ['Folio.app']      # nothing left beside the app, nothing reopened
    subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(installed)], check=True, capture_output=True, timeout=60)
    again = call('update', 'check')                                                 # the link now reaches the new app's command
    assert again['state'] == 'up_to_date' and again['current'] == new and again['upgrade']['command'] is None, again
    assert call('update', 'install', '--yes')['installed'] is False


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
    lifecycle_and_tabs()
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
