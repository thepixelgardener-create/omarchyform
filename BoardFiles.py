#!/usr/bin/env python3
"""Private board filesystem operations. Paths arrive on stdin, never argv.

No child processes: directory and file names never reach utility arguments.
The shell keeps image decoding/clipboard operations; both entry points share
this implementation for board operations and their lock/revision protocol.
"""
import datetime
import errno
import fcntl
import os
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
                shutil.copyfile(board, staged)
                if before != revision(board):
                    refuse(7)
                sys.stdout.buffer.write((before + '\n').encode())
                with open(staged, 'rb') as stream:
                    shutil.copyfileobj(stream, sys.stdout.buffer)
    elif op == 'commit':
        import shutil
        board, backup, lock, expected = args[:4]
        root, backup_root = (args[4:] + ['', ''])[:2]
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
                parents(backup)
                if os.path.exists(board):
                    with temporary(os.path.dirname(backup) or '.') as aside:
                        with open(board, "rb") as original, open(aside, "wb") as saved:
                            shutil.copyfileobj(original, saved)
                        os.replace(aside, backup)
                os.replace(staged, board)
                sys.stdout.write(revision(board))
    elif op == 'mkdir':
        os.mkdir(confined(*args), mode=0o700)
    elif op == 'move':
        import shutil
        source_root, source_name, target_root, target_name = args
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
    elif op == 'purge':
        import shutil
        root, name = args
        if '/' in name:
            refuse()
        path = confined(root, name)
        if os.path.isdir(path):
            shutil.rmtree(path)
        elif os.path.lexists(path):
            os.unlink(path)
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
