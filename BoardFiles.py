#!/usr/bin/env python3
"""Private board filesystem operations. Paths arrive on stdin, never argv.

No child processes: directory and file names never reach utility arguments.
The shell keeps image decoding/clipboard operations; both entry points share
this implementation for board operations and their lock/revision protocol.
"""
import datetime
import errno
import fcntl
import io
import os
import re
import stat
import sys
from contextlib import contextmanager

# shutil, tempfile and ctypes cost about 35 ms to import, more than Python's
# own start. They are imported by the operations that use them, so a revision,
# a size or a path check, which the board asks for most, starts in about 20.

MAX_BOARD_BYTES = 33554432
os.umask(0o077)


def refuse(code=3):
    raise SystemExit(code)


def confined(base, relative):
    if not os.path.isdir(base) or not relative or relative.startswith('/'):
        refuse()
    current = base
    for part in relative.split('/'):
        if part in ('', '.', '..') or any(ord(c) < 32 or ord(c) == 127 for c in part):
            refuse()
        current = os.path.join(current, part)
        if os.path.islink(current):
            refuse()
    return current


def under(path, root):
    if root:
        if not path.startswith(root + '/'):
            refuse()
        confined(root, path[len(root) + 1:])


def revision(path):
    if not os.path.isfile(path):
        return ''
    info = os.stat(path)
    stamp = datetime.datetime.fromtimestamp(info.st_mtime_ns // 1000000000).astimezone()
    time = stamp.strftime('%Y-%m-%d%H:%M:%S') + '.%09d' % (info.st_mtime_ns % 1000000000) + stamp.strftime('%z')
    return f'{info.st_size}|{info.st_ino}|{time}'


def fits(path):
    if os.path.isfile(path) and os.stat(path).st_size > MAX_BOARD_BYTES:
        refuse(5)


def bounded(source, sink):
    # Copy at most a board's worth. A size asked for first and a read made
    # afterwards are two looks at a file that may change between them; this
    # bounds the bytes actually read, so a file that grows meanwhile is
    # refused with 5 rather than read whole.
    remaining = MAX_BOARD_BYTES + 1
    while remaining:
        block = source.read(min(65536, remaining))
        if not block:
            return
        sink.write(block)
        remaining -= len(block)
    refuse(5)


def read_bounded(path):
    # One open, then everything about the file is asked of that descriptor.
    # Not blocking, so a FIFO cannot hold the helper at open(); anything that
    # is not a regular file reads as nothing, as a missing one does.
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_CLOEXEC)
    except FileNotFoundError:
        return b''
    info = os.fstat(fd)
    if not stat.S_ISREG(info.st_mode):
        os.close(fd)
        return b''
    with os.fdopen(fd, 'rb') as stream:
        if info.st_size > MAX_BOARD_BYTES:
            refuse(5)
        data = io.BytesIO()
        bounded(stream, data)
        return data.getvalue()


def parents(path):
    os.makedirs(os.path.dirname(path) or '.', mode=0o700, exist_ok=True)


@contextmanager
def locked(path):
    parents(path)
    with open(path, 'a+b') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield


@contextmanager
def temporary(folder, prefix='.omarchyform-'):
    import tempfile
    fd, path = tempfile.mkstemp(dir=folder, prefix=prefix)
    os.close(fd)
    try:
        yield path
    finally:
        if os.path.lexists(path):
            os.unlink(path)


def move_new(source, destination):
    # Linux renameat2(RENAME_NOREPLACE), like mv -nT without a race between
    # checking the destination and renaming. Applies to directories as well.
    import ctypes
    libc = ctypes.CDLL(None, use_errno=True)
    rename = libc.renameat2
    rename.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
    rename.restype = ctypes.c_int
    if rename(-100, os.fsencode(source), -100, os.fsencode(destination), 1):
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error))


# Earlier versions of a board: the file a save is about to replace, kept in a
# folder of the board's own outside the boards tree. A board is saved every
# time typing pauses, so not every save is kept: one at most every ten
# minutes, forty a board, and no more than two boards' worth of bytes, the
# oldest going first. The name is when it was kept, in UTC.
VERSION_NAME = re.compile(r'^\d{8}-\d{6}\.json$')
VERSION_STAMP = '%Y%m%d-%H%M%S'
VERSION_GAP_SECONDS = 600
MAX_VERSIONS = 40
MAX_VERSION_BYTES = 2 * MAX_BOARD_BYTES


def versions_in(folder):
    # Oldest first. Only plain files named the way this names them: a link or
    # anything else someone put there is not a version.
    try:
        names = sorted(name for name in os.listdir(folder) if VERSION_NAME.match(name))
    except OSError:
        return []
    return [name for name in names
            if not os.path.islink(os.path.join(folder, name)) and os.path.isfile(os.path.join(folder, name))]


def same_bytes(one, other):
    import filecmp
    try:
        return os.stat(one).st_size == os.stat(other).st_size and filecmp.cmp(one, other, shallow=False)
    except OSError:
        return False


def keep_version(board, folder, root, always):
    # Called with the board's lock held, before the board is replaced. A
    # version that cannot be kept never stops the save it rides on: whatever
    # goes wrong here, the board is still written.
    import shutil
    try:
        if not folder:
            return
        under(folder, root)
        if os.path.islink(folder):
            return
        if not os.path.isfile(board) or os.path.islink(board):
            # Nothing is being replaced: the board is new. Versions already
            # under its name were another board's, since moved or deleted by
            # hand, and are not this one's to go back to.
            if os.path.isdir(folder):
                shutil.rmtree(folder)
            return
        if os.stat(board).st_size > MAX_BOARD_BYTES:
            return
        names = versions_in(folder)
        utc = datetime.timezone.utc
        now = datetime.datetime.now(utc)
        if names:
            newest = datetime.datetime.strptime(names[-1][:15], VERSION_STAMP).replace(tzinfo=utc)
            if not always and 0 <= (now - newest).total_seconds() < VERSION_GAP_SECONDS:
                return
            if same_bytes(board, os.path.join(folder, names[-1])):
                return
            # Names sort by time. A clock put back must not file a newer
            # version behind an older one.
            now = max(now, newest + datetime.timedelta(seconds=1))
        os.makedirs(folder, mode=0o700, exist_ok=True)
        with temporary(folder) as staged:
            with open(board, 'rb') as original, open(staged, 'wb') as copy:
                bounded(original, copy)
            os.replace(staged, os.path.join(folder, now.strftime(VERSION_STAMP) + '.json'))
        names = versions_in(folder)
        sizes = {name: os.stat(os.path.join(folder, name)).st_size for name in names}
        while len(names) > 1 and (len(names) > MAX_VERSIONS or sum(sizes[name] for name in names) > MAX_VERSION_BYTES):
            os.unlink(os.path.join(folder, names.pop(0)))
    except (OSError, SystemExit, ValueError):
        pass


def keep_backup(board, backup):
    import shutil
    parents(backup)
    if os.path.exists(board):
        with temporary(os.path.dirname(backup) or '.') as aside:
            with open(board, "rb") as original, open(aside, "wb") as saved:
                shutil.copyfileobj(original, saved)
            os.replace(aside, backup)


def follow_versions(old, new, root):
    # A board's versions go where it goes. Whatever is already at the new
    # place was left by a board that is no longer there: the move itself
    # refuses to land on one that is. Never worth failing a move over.
    import shutil
    try:
        if not old or not new:
            return
        under(old, root)
        under(new, root)
        if os.path.islink(new) or os.path.isfile(new):
            os.unlink(new)
        elif os.path.isdir(new):
            shutil.rmtree(new)
        if os.path.isdir(old) and not os.path.islink(old):
            parents(new)
            os.rename(old, new)
    except (OSError, SystemExit):
        pass


def make_private(folders):
    # Exit 3 when a folder cannot be made private: not a plugin folder, not
    # made, not this user's, not a folder, or its mode cannot be set. Then
    # nothing may be read or written. Exit 4 when the folders are private but
    # hold something that is not this user's or cannot be read: only root can
    # put that inside a 0700 folder, nobody else can reach it through one, and
    # refusing every board over it would lock the owner out of their own.
    failed = False
    foreign = False
    uid = os.getuid()
    home = os.path.realpath(os.environ.get('HOME', '/'))
    for folder in folders:
        try:
            if not os.path.isabs(folder) or any(ord(c) < 32 or ord(c) == 127 for c in folder) or os.path.realpath(folder) == home:
                refuse()
            os.makedirs(folder, mode=0o700, exist_ok=True)
            info = os.stat(folder)
            if info.st_uid != uid or not stat.S_ISDIR(info.st_mode):
                raise PermissionError()
            os.chmod(folder, 0o700)
        except (OSError, SystemExit):
            failed = True
            continue
        device = info.st_dev
        unreadable = []
        for base, dirs, files in os.walk(folder, followlinks=False, onerror=unreadable.append):
            for name in dirs + files:
                path = os.path.join(base, name)
                try:
                    info = os.lstat(path)
                except OSError:
                    foreign = True
                    continue
                if info.st_uid != uid:
                    foreign = True
                if info.st_dev != device or stat.S_ISLNK(info.st_mode) or info.st_uid != uid:
                    if name in dirs:
                        dirs.remove(name)
                    continue
                try:
                    if stat.S_ISDIR(info.st_mode):
                        os.chmod(path, 0o700)
                    elif stat.S_ISREG(info.st_mode):
                        os.chmod(path, stat.S_IMODE(info.st_mode) & ~0o077)
                except OSError:
                    failed = True
        if unreadable:
            foreign = True
    if failed:
        refuse(3)
    if foreign:
        refuse(4)


def run(op, args, source):
    if op == 'private':
        make_private(args)
    elif op == 'revision':
        sys.stdout.write(revision(args[0]))
    elif op == 'read':
        sys.stdout.buffer.write(read_bounded(args[0]))
    elif op == 'filesize':
        sys.stdout.write(str(os.stat(args[0]).st_size if os.path.isfile(args[0]) else 0))
    elif op == 'check':
        path = confined(*args)
        fits(path)
        sys.stdout.write(revision(path))
    elif op == 'snapshot':
        import shutil
        board, lock, root = args
        under(board, root)
        with locked(lock):
            if not os.path.isfile(board) or os.path.islink(board):
                refuse()
            fits(board)
            before = revision(board)
            with temporary(os.path.dirname(lock), '.omarchyform-snapshot-') as staged:
                with open(board, 'rb') as original, open(staged, 'wb') as copy:
                    bounded(original, copy)
                if before != revision(board):
                    refuse(7)
                sys.stdout.buffer.write((before + '\n').encode())
                with open(staged, 'rb') as stream:
                    shutil.copyfileobj(stream, sys.stdout.buffer)
    elif op == 'commit':
        import shutil
        board, backup, lock, expected = args[:4]
        root, backup_root, versions, versions_root, version_mode = (args[4:] + [''] * 5)[:5]
        under(board, root)
        under(backup, backup_root)
        if any(os.path.islink(p) for p in (board, backup, backup + '.tmp')):
            refuse()
        parents(board)
        with temporary(os.path.dirname(board) or '.') as staged:
            with open(staged, 'wb') as stream:
                # Bound data before allocating or writing beyond the board cap.
                remaining = MAX_BOARD_BYTES + 1
                while remaining:
                    block = source.read(min(65536, remaining))
                    if not block:
                        break
                    stream.write(block)
                    remaining -= len(block)
            fits(staged)
            with locked(lock):
                current = revision(board)
                if expected != '-' and expected != current:
                    sys.stdout.write(current)
                    refuse(7)
                keep_version(board, versions, versions_root, version_mode == 'always')
                keep_backup(board, backup)
                os.replace(staged, board)
                sys.stdout.write(revision(board))
    elif op == 'versions':
        # A board's earlier versions, newest first: each one's name and size.
        folder, root = args
        if os.path.isdir(folder):
            under(folder, root)
            for name in reversed(versions_in(folder)):
                sys.stdout.write(f'{name}\t{os.stat(os.path.join(folder, name)).st_size}\n')
    elif op == 'restore':
        # An earlier version put back as the board, under the lock and only
        # onto the revision the caller read, as a save is. The board as it is
        # goes into its versions first, so going back can itself be gone back
        # on. Exit 8 says the version asked for is not there.
        board, versions, name, backup, lock, expected, root, backup_root, versions_root = args
        under(board, root)
        under(backup, backup_root)
        under(versions, versions_root)
        if not VERSION_NAME.match(name):
            refuse(2)
        chosen = os.path.join(versions, name)
        if any(os.path.islink(p) for p in (board, backup, versions, chosen)):
            refuse()
        if not os.path.isfile(chosen):
            refuse(8)
        parents(board)
        with temporary(os.path.dirname(board) or '.') as staged:
            # Copied first: keeping the board as it is can push the oldest
            # version out, and that may be the one being gone back to.
            with open(chosen, 'rb') as original, open(staged, 'wb') as copy:
                bounded(original, copy)
            with locked(lock):
                current = revision(board)
                if expected != '-' and expected != current:
                    sys.stdout.write(current)
                    refuse(7)
                keep_version(board, versions, versions_root, True)
                keep_backup(board, backup)
                os.replace(staged, board)
                sys.stdout.write(revision(board))
    elif op == 'mkdir':
        os.mkdir(confined(*args), mode=0o700)
    elif op == 'move':
        import shutil
        source_root, source_name, target_root, target_name = args[:4]
        versions_from, versions_to, versions_root = (args[4:] + [''] * 3)[:3]
        old = confined(source_root, source_name)
        new = confined(target_root, target_name)
        parents(new)
        try:
            move_new(old, new)
        except OSError as error:
            if error.errno != errno.EXDEV:
                raise
            # Roots may live on different filesystems. Copy privately beside
            # the destination, then publish without replacing a collision.
            import tempfile
            with tempfile.TemporaryDirectory(prefix='.omarchyform-move-', dir=os.path.dirname(new)) as stage:
                copied = os.path.join(stage, 'entry')
                if os.path.isdir(old):
                    shutil.copytree(old, copied, symlinks=True)
                else:
                    shutil.copy2(old, copied, follow_symlinks=False)
                move_new(copied, new)
            if os.path.isdir(old):
                shutil.rmtree(old)
            else:
                os.unlink(old)
        follow_versions(versions_from, versions_to, versions_root)
    elif op == 'purge':
        import shutil
        root, name = args[:2]
        versions, versions_root = (args[2:] + [''] * 2)[:2]
        if '/' in name:
            refuse()
        path = confined(root, name)
        if os.path.isdir(path):
            shutil.rmtree(path)
        elif os.path.lexists(path):
            os.unlink(path)
        # What is destroyed for good takes its earlier versions with it.
        try:
            if versions:
                under(versions, versions_root)
                if os.path.isdir(versions) and not os.path.islink(versions):
                    shutil.rmtree(versions)
        except (OSError, SystemExit):
            pass
    elif op == 'publish':
        root, name, staged = args
        if '/' in name:
            refuse()
        confined(root, name + '.json')
        if not os.path.isfile(staged) or os.path.islink(staged):
            refuse()
        os.chmod(staged, 0o600)
        number = 1
        while True:
            candidate = name + (f'-{number}' if number > 1 else '') + '.json'
            try:
                os.link(staged, os.path.join(root, candidate), follow_symlinks=False)
                break
            except FileExistsError:
                number += 1
        os.unlink(staged)
        sys.stdout.write(candidate)
    elif op == 'export':
        import shutil
        staged, destination, root = args
        resolved, private = os.path.realpath(destination), os.path.realpath(root)
        if not os.path.isfile(staged) or os.path.islink(destination) or resolved == private or resolved.startswith(private + '/'):
            refuse()
        with temporary(os.path.dirname(destination) or '.', '.omarchyform-export-') as tmp:
            shutil.copyfile(staged, tmp)
            os.replace(tmp, destination)
        os.unlink(staged)
    else:
        refuse(2)


def main():
    stream = sys.stdin.buffer
    budget = 65536
    def field():
        nonlocal budget
        data = bytearray()
        while budget:
            byte = stream.read(1)
            budget -= 1
            if byte == b'\0':
                return data.decode('utf-8')
            if not byte:
                refuse(2)
            data += byte
        refuse(2)
    op = field()
    count = int(field())
    if not 0 <= count <= 32:
        refuse(2)
    args = [field() for _ in range(count)]
    run(op, args, stream)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, IndexError, TypeError):
        # Paths belong only in the application UI, never diagnostics.
        print('Board filesystem operation failed', file=sys.stderr)
        sys.exit(1)
