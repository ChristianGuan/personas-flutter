#!/usr/bin/env python3
"""Create a new local upload key; never overwrite an existing signing identity."""
import argparse
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--create', action='store_true', help='Create a NEW upload key, only before first publication.')
    args = parser.parse_args()
    if not args.create:
        parser.error('Use --create only for a new app. Existing Play apps must reuse their registered upload key.')
    directory = ROOT / '.tooling/signing'
    keystore = directory / 'personas-upload.jks'
    properties = ROOT / 'flutter_app/android/key.properties'
    if keystore.exists() or properties.exists():
        parser.exit(1, 'Signing files already exist; nothing was changed. Reuse and back up that identity.\n')
    candidates = [Path(os.environ.get('JAVA_HOME', '')) / 'bin/keytool',
                  Path('/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool')]
    keytool = next((str(p) for p in candidates if p.is_file()), None) or shutil.which('keytool')
    if not keytool:
        parser.exit(1, 'Install a JDK or set JAVA_HOME first.\n')
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    directory.chmod(0o700)
    password = secrets.token_hex(32)
    env = {**os.environ, 'PERSONAS_UPLOAD_STORE_PASSWORD': password, 'PERSONAS_UPLOAD_KEY_PASSWORD': password}
    with tempfile.TemporaryDirectory(prefix='.new-upload-', dir=directory) as temporary:
        staged = Path(temporary) / 'upload.jks'
        result = subprocess.run([
            keytool, '-genkeypair', '-noprompt', '-keystore', str(staged), '-storetype', 'JKS',
            '-alias', 'personas-upload', '-keyalg', 'RSA', '-keysize', '4096', '-validity', '10000',
            '-dname', 'CN=Personas Upload Key',
            '-storepass:env', 'PERSONAS_UPLOAD_STORE_PASSWORD', '-keypass:env', 'PERSONAS_UPLOAD_KEY_PASSWORD',
        ], env=env, capture_output=True, text=True)
        if result.returncode:
            parser.exit(1, 'Key generation failed. No signing files were installed.\n')
        staged.chmod(0o600)
        # A hard link refuses replacement if another process created the destination meanwhile.
        os.link(staged, keystore)
        try:
            with open(properties, 'x', encoding='utf8', opener=lambda path, flags: os.open(path, flags, 0o600)) as f:
                f.write('storeFile=../../.tooling/signing/personas-upload.jks\n')
                f.write(f'storePassword={password}\nkeyAlias=personas-upload\nkeyPassword={password}\n')
        except Exception:
            keystore.unlink()
            raise
    print('Created local upload key and android/key.properties (permissions 600).')
    print('Passwords were not printed. Back up both files in your encrypted vault before publishing.')
    print('This key is not yet registered with Google Play. Nothing was uploaded.')


if __name__ == '__main__':
    main()
