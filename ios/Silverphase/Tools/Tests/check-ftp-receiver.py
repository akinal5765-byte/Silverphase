#!/usr/bin/env python3
"""Build the native listener for macOS and exercise it on loopback only."""
import ftplib
import hashlib
import io
import json
from pathlib import Path
import socket
import struct
import subprocess
import tempfile

TOOLS = Path(__file__).resolve().parents[1]
HOST, PORT = '127.0.0.1', 2121


def require_error(code, action):
    try:
        action()
    except ftplib.Error as error:
        assert str(error).startswith(str(code)), str(error)
    else:
        raise AssertionError(f'Expected FTP {code}')


def connect(password=None):
    client = ftplib.FTP(timeout=4)
    client.connect(HOST, PORT)
    if password:
        client.login('silverphase', password)
    return client


class ExtendedPassiveFTP(ftplib.FTP):
    def makepasv(self):
        return ftplib.parse229(self.sendcmd('EPSV'), self.sock.getpeername())


def start(binary, inbox):
    p = subprocess.Popen([binary, inbox], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    password = p.stdout.readline().strip()
    assert len(password) == 12, 'Could not start test listener; is loopback port 2121 free?'
    return p, password


def stop(process):
    if process.poll() is None:
        process.stdin.write('\n')
        process.stdin.flush()
        assert process.wait(timeout=5) == 0


def raw_fixture():
    # Minimal TIFF structure for receiver preflight, not a decoded Sony sensor sample.
    offset = 8 + 2 + 2 * 12 + 4
    payload = bytes(range(32))
    return (b'II' + struct.pack('<HIH', 42, 8, 2)
            + struct.pack('<HHII', 273, 4, 1, offset)
            + struct.pack('<HHII', 279, 4, 1, len(payload))
            + struct.pack('<I', 0) + payload)


with tempfile.TemporaryDirectory(prefix='silverphase-ftp-qa-') as tmp:
    binary = Path(tmp, 'listener')
    inbox = Path(tmp, 'inbox')
    inbox.mkdir()
    subprocess.run(['xcrun', '-sdk', 'macosx', 'clang++', '-std=c++20', '-fobjc-arc',
                    '-DDEBUG=1', '-DSILVERPHASE_FTP_LOOPBACK_TEST=1', '-framework', 'Foundation',
                    str(TOOLS.parent / 'Sources/SilverphaseFTPReceiver.mm'),
                    str(TOOLS / 'Tests/FTPReceiverHarness.mm'), '-o', str(binary)], check=True)
    p, password = start(binary, inbox)
    try:
        with connect() as client:
            require_error(530, lambda: client.sendcmd('PASV'))
            require_error(530, lambda: client.login('silverphase', 'wrong'))
        with connect(password) as client:
            require_error(502, lambda: client.sendcmd('PORT 127,0,0,1,8,73'))
            require_error(502, lambda: client.sendcmd('RETR IMG.ARW'))
            require_error(553, lambda: client.storbinary('STOR ../escape.ARW', io.BytesIO(b'no')))
            require_error(550, lambda: client.storbinary('STOR Bad.ARW', io.BytesIO(b'not a RAW')))
            raw = raw_fixture()
            require_error(550, lambda: client.storbinary('STOR Truncated.ARW', io.BytesIO(raw[:-1])))
            assert not list(inbox.iterdir())
            assert client.storbinary('STOR DSC00001.ARW', io.BytesIO(raw)) == '226 Transfer complete'
            file = inbox / (hashlib.sha256(raw).hexdigest() + '.ARW')
            assert file.read_bytes() == raw
            record = file.with_suffix('.ARW.json')
            assert json.loads(record.read_text()) == {'name': 'DSC00001.ARW', 'film': 'QA-film'}
            assert client.storbinary('STOR DifferentName.ARW', io.BytesIO(raw)).startswith('226 Already')
            assert sorted(inbox.iterdir()) == sorted((file, record))
            receipt = file.with_suffix('.ARW.done')
            record.rename(receipt)
            file.unlink()
            assert client.storbinary('STOR DSC00001.ARW', io.BytesIO(raw)).startswith('226 Already')
            assert list(inbox.iterdir()) == [receipt]
            pending = raw[:-1] + b'X'
            pending_file = inbox / (hashlib.sha256(pending).hexdigest() + '.ARW')
            pending_record = pending_file.with_suffix('.ARW.json')
            with ExtendedPassiveFTP(timeout=4) as extended:
                extended.connect(HOST, PORT)
                extended.login('silverphase', password)
                assert extended.storbinary('STOR DSC00002.ARW', io.BytesIO(pending)) == '226 Transfer complete'
            with client.transfercmd('STOR Interrupted.ARW') as data:
                data.sendall(raw[:12])
                stop(p)
    finally:
        stop(p)

    p, second = start(binary, inbox)
    try:
        assert password != second
        assert set(inbox.iterdir()) == {receipt, pending_file, pending_record}
        assert pending_file.read_bytes() == pending
        assert json.loads(pending_record.read_text())['film'] == 'QA-film'
        with connect(second) as client:
            assert client.storbinary('STOR DSC00001.ARW', io.BytesIO(raw)).startswith('226 Already')
        with socket.create_connection((HOST, PORT), timeout=3) as peer:
            assert peer.recv(200).startswith(b'220 ')
    finally:
        stop(p)
print('PASS: auth, upload-only, filename/RAW validation, byte identity, recipe metadata, dedup, stop and restart')
