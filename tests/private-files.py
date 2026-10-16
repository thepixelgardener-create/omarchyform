#!/usr/bin/env python3
"""Exercise the native private transport and its process metadata on Linux."""
import fcntl
import errno
import importlib.util
import os
import stat
from pathlib import Path
import subprocess
import sys
import tempfile
import time

HELPER = Path(__file__).resolve().parent.parent / 'BoardFiles.py'


def message(op, args, body=b''):
    return ('\0'.join([op, str(len(args)), *map(str, args)]) + '\0').encode() + body


def run(op, args, body=b''):
    return subprocess.run(['python3', str(HELPER)], input=message(op, args, body), capture_output=True, timeout=8)


with tempfile.TemporaryDirectory(prefix='omarchyform-private-') as directory:
    root = Path(directory)
    canary = 'PRIVATE_TITLE_CANARY_€_"_$(not-shell)'
    boards, backups = root / 'boards', root / 'backups'
    boards.mkdir(mode=0o700)
    backups.mkdir(mode=0o700)
    board, backup, lock = boards / (canary + '.json'), backups / (canary + '.bak'), root / 'lock'
    body = b'{"items":[],"links":[]}'
    args = [board, backup, lock, '-', boards, backups]
    with lock.open('wb') as held:
        fcntl.flock(held, fcntl.LOCK_EX)
        child = subprocess.Popen(['python3', str(HELPER)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            child.stdin.write(message('commit', args, body))
            child.stdin.close()
            # The staged file proves the request was read; the held lock keeps
            # the real operation alive long enough to inspect metadata.
            deadline = time.monotonic() + 5
            while not list(boards.glob('.omarchyform-*')):
                assert child.poll() is None, 'helper exited before taking request'
                assert time.monotonic() < deadline, 'request did not arrive'
                time.sleep(.01)
            for _ in range(10):
                assert canary.encode() not in Path(f'/proc/{child.pid}/cmdline').read_bytes()
                assert canary.encode() not in Path(f'/proc/{child.pid}/environ').read_bytes()
                assert not Path(f'/proc/{child.pid}/task/{child.pid}/children').read_text().strip(), 'no downstream utility may receive titles'
                time.sleep(.01)
        finally:
            fcntl.flock(held, fcntl.LOCK_UN)
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
        assert child.returncode == 0, child.stderr.read()
    assert board.read_bytes() == body
    assert board.stat().st_mode & 0o777 == 0o600
    old_revision = run('revision', [board]).stdout
    assert run('commit', args, b'new').returncode == 0
    assert backup.read_bytes() == body
    stale = run('commit', [board, backup, lock, old_revision.decode(), boards, backups], b'wrong')
    assert stale.returncode == 7 and board.read_bytes() == b'new' and backup.read_bytes() == body
    renamed = canary + '-renamed.json'
    assert run('move', [boards, board.name, boards, renamed]).returncode == 0
    collision = boards / 'taken.json'
    collision.write_bytes(b'keep')
    assert run('move', [boards, renamed, boards, collision.name]).returncode != 0
    assert collision.read_bytes() == b'keep' and (boards / renamed).read_bytes() == b'new'
    staged = root / 'staged'
    staged.write_bytes(b'imported')
    assert run('publish', [boards, canary, staged]).returncode == 0
    assert board.read_bytes() == b'imported'
    assert run('purge', [boards, renamed]).returncode == 0
    assert not (boards / renamed).exists()
    # Exercise cross-filesystem fallback deterministically, including a
    # collision appearing at publication. Real filesystem copies/renames run;
    # only the initial EXDEV result is injected.
    sys.dont_write_bytecode = True
    spec = importlib.util.spec_from_file_location('private_helper', HELPER)
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    native_move = helper.move_new
    def crossing(old, new):
        if old == str(boards / 'cross.json'):
            raise OSError(errno.EXDEV, 'cross-device fixture')
        native_move(old, new)
    helper.move_new = crossing
    (boards / 'cross.json').write_bytes(b'across')
    helper.run('move', [str(boards), 'cross.json', str(backups), 'cross.json'], None)
    assert (backups / 'cross.json').read_bytes() == b'across'
    assert not (boards / 'cross.json').exists()
    (boards / 'cross.json').write_bytes(b'preserved')
    try:
        helper.run('move', [str(boards), 'cross.json', str(backups), 'cross.json'], None)
        raise AssertionError('collision must fail')
    except FileExistsError:
        pass
    assert (boards / 'cross.json').read_bytes() == b'preserved'
    assert (backups / 'cross.json').read_bytes() == b'across'
    assert not list(backups.glob('.omarchyform-move-*'))
    for malformed in [b'commit\0', b'commit\0' + b'9999\0', b'commit\0' + b'1\0' + b'x' * 65536]:
        result = subprocess.run(['python3', str(HELPER)], input=malformed, capture_output=True, timeout=5)
        assert result.returncode != 0
    # The folder check's two refusals. A folder that cannot be private is 3;
    # private folders holding something of another user's are 4, with the
    # rest still made private. Another owner needs root to create, so one is
    # injected through lstat.
    def exit_code(folders):
        try:
            helper.make_private([str(f) for f in folders])
        except SystemExit as stop:
            return stop.code
        return 0
    held = root / 'held'
    (held / 'inner').mkdir(parents=True)
    (held / 'mine.json').write_bytes(b'{}')
    (held / 'theirs.json').write_bytes(b'{}')
    os.chmod(held / 'mine.json', 0o644)
    os.chmod(held / 'inner', 0o755)
    native_lstat = os.lstat
    def foreign_lstat(path, *rest, **named):
        info = native_lstat(path, *rest, **named)
        if str(path).endswith('theirs.json'):
            fields = list(info)
            fields[stat.ST_UID] = os.getuid() + 1
            return os.stat_result(fields)
        return info
    helper.os.lstat = foreign_lstat
    try:
        assert exit_code([held]) == 4
        assert stat.S_IMODE(os.stat(held).st_mode) == 0o700
        assert stat.S_IMODE(os.stat(held / 'inner').st_mode) == 0o700
        assert stat.S_IMODE(os.stat(held / 'mine.json').st_mode) == 0o600, 'the rest is still made private'
        blocker = root / 'blocker'
        blocker.write_bytes(b'not a folder')
        assert exit_code([blocker]) == 3
        assert exit_code([held, blocker]) == 3, 'a folder that cannot be private outranks a foreign file'
    finally:
        helper.os.lstat = native_lstat
    assert exit_code([held]) == 0
print('ok — private filesystem transport: titles absent from argv/environment, no children, commit/backup/conflict/collision semantics')
