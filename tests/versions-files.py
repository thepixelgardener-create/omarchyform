#!/usr/bin/env python3
"""A board's earlier versions, in the helper that keeps them.

Which saves are kept, how many, what going back does to the board and to
what was there, and that none of it can stop a save. Time is in the names,
so a version is aged here by renaming it rather than by waiting.
"""
import os
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

HELPER = Path(__file__).resolve().parent.parent / 'BoardFiles.py'


def run(op, args, body=b''):
    request = ('\0'.join([op, str(len(args)), *map(str, args)]) + '\0').encode() + body
    return subprocess.run(['python3', str(HELPER)], input=request, capture_output=True, timeout=30)


def names(folder):
    return sorted(p.name for p in folder.iterdir()) if folder.is_dir() else []


def aged(folder, name, to):
    # A version kept long ago: the name is the time, and nothing else is read.
    (folder / name).rename(folder / to)
    return to


with tempfile.TemporaryDirectory(prefix='omarchyform-versions-') as directory:
    root = Path(directory)
    boards, backups, versions = root / 'boards', root / 'backups', root / 'versions'
    for folder in (boards, backups, versions):
        folder.mkdir(mode=0o700)
    title = 'Plans for "next" year €'
    board, backup, lock = boards / (title + '.json'), backups / (title + '.bak'), root / 'lock'
    kept = versions / 'v1' / (title + '.json')

    def commit(body, mode='spaced', expected='-'):
        return run('commit', [board, backup, lock, expected, boards, backups, kept, versions, mode], body)

    # A stale folder under a new board's name is another board's, and goes.
    kept.mkdir(parents=True)
    (kept / '20200101-000000.json').write_bytes(b'somebody else')
    assert commit(b'one').returncode == 0
    assert not kept.exists(), 'a new board does not inherit versions left under its name'

    # The first save over a board keeps what it replaced.
    assert commit(b'two').returncode == 0
    assert len(names(kept)) == 1 and (kept / names(kept)[0]).read_bytes() == b'one'
    assert stat.S_IMODE(kept.stat().st_mode) == 0o700 and stat.S_IMODE((kept / names(kept)[0]).stat().st_mode) == 0o600
    assert not [n for n in names(kept) if n.startswith('.')], 'nothing staged is left'

    # A board is saved every time typing pauses: within ten minutes of the
    # last version, another is not kept.
    assert commit(b'three').returncode == 0 and commit(b'four').returncode == 0
    assert len(names(kept)) == 1
    # Ten minutes on, the next save keeps what it replaces.
    first = aged(kept, names(kept)[0], '20200101-000000.json')
    assert commit(b'five').returncode == 0
    assert len(names(kept)) == 2 and (kept / names(kept)[-1]).read_bytes() == b'four'

    # Asked to keep one whatever the time, it does, but not the same bytes twice.
    assert commit(b'six', 'always').returncode == 0
    assert len(names(kept)) == 3 and (kept / names(kept)[-1]).read_bytes() == b'five'
    board.write_bytes(b'five')
    assert commit(b'seven', 'always').returncode == 0
    assert len(names(kept)) == 3, 'what the newest version already holds is not kept again'

    # Names sort by time even when the clock has been put back.
    future = aged(kept, names(kept)[-1], '29990101-000000.json')
    assert commit(b'eight', 'always').returncode == 0
    assert names(kept)[-1] == '29990101-000001.json' and (kept / names(kept)[-1]).read_bytes() == b'seven'
    (kept / '29990101-000001.json').unlink()
    aged(kept, future, '20200102-000000.json')

    # Listed newest first, each with its size; anything else in the folder,
    # and a link named like a version, is not one.
    (kept / 'notes.txt').write_bytes(b'mine')
    (kept / '20200103-000000.json').symlink_to(board)
    listed = run('versions', [kept, versions])
    assert listed.returncode == 0
    lines = listed.stdout.decode().split('\n')
    assert len(lines) == 4 and lines[0].endswith('\t4') and lines[1:] == ['20200102-000000.json\t4', '20200101-000000.json\t3', ''], listed.stdout
    assert run('versions', [versions / 'v1' / 'none.json', versions]).stdout == b'', 'a board with none has none'
    (kept / '20200103-000000.json').unlink()

    # Going back puts the version in the board's place, keeps the board as it
    # was as a version of its own, and leaves the version gone back to.
    revision = run('revision', [board]).stdout.decode()
    back = run('restore', [board, kept, '20200101-000000.json', backup, lock, revision, boards, backups, versions])
    assert back.returncode == 0, back.stderr
    assert board.read_bytes() == b'one' and backup.read_bytes() == b'eight'
    assert back.stdout == run('revision', [board]).stdout, 'the answer is the revision now there'
    assert (kept / '20200101-000000.json').read_bytes() == b'one'
    newest = [n for n in names(kept) if n.endswith('.json')][-1]
    assert (kept / newest).read_bytes() == b'eight', 'what was there can be gone back to in turn'

    # Only onto the revision the caller read; a version that is not there, a
    # name that is not a version's, and a link are each refused, with the
    # board as it was.
    def refused(name, expected, code):
        result = run('restore', [board, kept, name, backup, lock, expected, boards, backups, versions])
        assert result.returncode == code, (name, result.returncode, result.stderr)
        assert board.read_bytes() == b'one'
    refused('20200102-000000.json', revision, 7)
    refused('20190101-000000.json', '-', 8)
    refused('../../boards/x.json', '-', 2)
    (kept / '20200104-000000.json').symlink_to(backup)
    refused('20200104-000000.json', '-', 3)
    (kept / '20200104-000000.json').unlink()

    # Forty a board: the oldest go first, and the one being gone back to is
    # read before keeping the board can push it out.
    for name in list(names(kept)):
        (kept / name).unlink()
    for day in range(1, 41):
        (kept / ('201901%02d-000000.json' % day if day <= 31 else '201902%02d-000000.json' % (day - 31))).write_bytes(b'v%d' % day)
    assert len(names(kept)) == 40
    back = run('restore', [board, kept, '20190101-000000.json', backup, lock, '-', boards, backups, versions])
    assert back.returncode == 0 and board.read_bytes() == b'v1'
    assert len(names(kept)) == 40 and '20190101-000000.json' not in names(kept) and (kept / names(kept)[-1]).read_bytes() == b'one'

    # And no more than two boards' worth of bytes, however few that is.
    for name in list(names(kept)):
        (kept / name).unlink()
    big = b'x' * (24 * 1024 * 1024)
    for stamp in ('20190101-000000.json', '20190102-000000.json'):
        (kept / stamp).write_bytes(big)
    board.write_bytes(big[:-1])
    assert commit(b'small').returncode == 0
    assert names(kept)[0] == '20190102-000000.json' and len(names(kept)) == 2

    # A version that cannot be kept never stops the save: the folder is a
    # file, is a link, or is outside where versions go.
    for name in list(names(kept)):
        (kept / name).unlink()
    kept.rmdir()
    kept.write_bytes(b'in the way')
    assert commit(b'saved anyway').returncode == 0 and board.read_bytes() == b'saved anyway'
    kept.unlink()
    elsewhere = root / 'elsewhere'
    elsewhere.mkdir()
    kept.symlink_to(elsewhere)
    assert commit(b'and again').returncode == 0 and board.read_bytes() == b'and again' and names(elsewhere) == []
    kept.unlink()
    outside = run('commit', [board, backup, lock, '-', boards, backups, elsewhere / 'x.json', versions, 'always'], b'once more')
    assert outside.returncode == 0 and board.read_bytes() == b'once more' and names(elsewhere) == []

    # A save that says nothing about versions keeps none, as before.
    assert run('commit', [board, backup, lock, '-', boards, backups], b'plain').returncode == 0
    assert not kept.exists()

    # A board's versions go where it goes: renamed, into the trash, back out,
    # and gone for good with it. Whatever was left at the new name by a board
    # no longer there gives way.
    assert commit(b'moving', 'always').returncode == 0 and len(names(kept)) == 1
    trash = root / 'trash'
    trash.mkdir()
    renamed = versions / 'v1' / 'renamed.json'
    renamed.mkdir()
    (renamed / '20180101-000000.json').write_bytes(b'left by another')
    assert run('move', [boards, board.name, boards, 'renamed.json', kept, renamed, versions]).returncode == 0
    assert not kept.exists()
    assert len(names(renamed)) == 1 and (renamed / names(renamed)[0]).read_bytes() == b'plain'
    binned = versions / 'trash' / '20260101-000000-renamed.json'
    assert run('move', [boards, 'renamed.json', trash, binned.name, renamed, binned, versions]).returncode == 0
    assert not renamed.exists() and len(names(binned)) == 1
    assert run('move', [trash, binned.name, boards, 'renamed.json', binned, renamed, versions]).returncode == 0
    assert len(names(renamed)) == 1 and not binned.exists()
    assert run('move', [boards, 'renamed.json', trash, binned.name, renamed, binned, versions]).returncode == 0
    assert run('purge', [trash, binned.name, binned, versions]).returncode == 0
    assert not (trash / binned.name).exists() and not binned.exists()
    # A board with no versions moves as it always did, and a move that names
    # somewhere outside the versions folder moves the board and nothing else.
    (boards / 'bare.json').write_bytes(b'{}')
    assert run('move', [boards, 'bare.json', boards, 'bare2.json', versions / 'v1' / 'bare.json', versions / 'v1' / 'bare2.json', versions]).returncode == 0
    (elsewhere / 'keep').write_bytes(b'not a version')
    assert run('move', [boards, 'bare2.json', boards, 'bare3.json', elsewhere, root / 'stolen', versions]).returncode == 0
    assert (boards / 'bare3.json').exists() and (elsewhere / 'keep').exists() and not (root / 'stolen').exists()
    assert run('purge', [boards, 'bare3.json', elsewhere, versions]).returncode == 0
    assert (elsewhere / 'keep').exists(), 'nothing outside the versions folder is destroyed'

print('ok — earlier versions: which saves are kept, how many, going back, and following a board that moves')
