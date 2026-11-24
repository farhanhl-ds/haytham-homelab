@echo off
setlocal
chcp 65001 >nul

REM Off-host local-network backup pull script for native Windows cmd.
REM Zero WSL, zero third-party binaries (Device Guard / Smart App Control safe).
REM Uses only Microsoft-signed inbox Windows tools: cmd.exe, ssh.exe, and tar.exe.
REM
REM Prerequisites:
REM   SSH key at %USERPROFILE%\.ssh\id_ed25519 authorized on:
REM     - CT 610 Immich (192.168.100.61) for Track 2 photos
REM     - Proxmox host  (192.168.100.2)  for Track 1 restic state
REM
REM Usage:
REM   scripts\pull-homelab-backups.bat                 Pull both Track 1 + Track 2
REM   scripts\pull-homelab-backups.bat --state-only    Track 1 only (encrypted restic repo)
REM   scripts\pull-homelab-backups.bat --photos-only   Track 2 only (Immich originals)
REM
REM Customize destinations via environment variables before running (or edit defaults below):
REM   set "STATE_BACKUP_DIR=C:\Users\you\Backups\haytham\state"
REM   set "PHOTOS_BACKUP_DIR=D:\Backups\haytham\immich-originals"

if not defined PVE_HOST set "PVE_HOST=192.168.100.2"
if not defined IMMICH_HOST set "IMMICH_HOST=192.168.100.61"
if not defined SSH_USER set "SSH_USER=root"
if not defined SSH_KEY set "SSH_KEY=%USERPROFILE%\.ssh\id_ed25519"

if not defined STATE_BACKUP_DIR set "STATE_BACKUP_DIR=%USERPROFILE%\Backups\haytham\state"
if not defined PHOTOS_BACKUP_DIR set "PHOTOS_BACKUP_DIR=%USERPROFILE%\Backups\haytham\immich-originals"

if not "%STATE_BACKUP_DIR:~-2%"==":\" if "%STATE_BACKUP_DIR:~-1%"=="\" set "STATE_BACKUP_DIR=%STATE_BACKUP_DIR:~0,-1%"
if not "%PHOTOS_BACKUP_DIR:~-2%"==":\" if "%PHOTOS_BACKUP_DIR:~-1%"=="\" set "PHOTOS_BACKUP_DIR=%PHOTOS_BACKUP_DIR:~0,-1%"

set "RUN_STATE=1"
set "RUN_PHOTOS=1"

:parse_args
if "%~1"=="" goto :args_done
if /I "%~1"=="--state-only" (
  set "RUN_PHOTOS=0"
  shift
  goto :parse_args
)
if /I "%~1"=="--photos-only" (
  set "RUN_STATE=0"
  shift
  goto :parse_args
)
if /I "%~1"=="-h" goto :usage
if /I "%~1"=="--help" goto :usage
if "%~1"=="/?" goto :usage

echo Unknown argument: %~1 >&2
exit /b 1

:args_done
where ssh >nul 2>&1
if errorlevel 1 (
  echo ERROR: Built-in OpenSSH client ^(ssh.exe^) not found in PATH. >&2
  exit /b 1
)

where tar >nul 2>&1
if errorlevel 1 (
  echo ERROR: Built-in tar.exe not found in PATH. >&2
  exit /b 1
)

if not exist "%SSH_KEY%" (
  echo ERROR: SSH private key not found at "%SSH_KEY%". >&2
  echo Generate one with: ssh-keygen -t ed25519 >&2
  echo Then add "%SSH_KEY%.pub" to /root/.ssh/authorized_keys on %IMMICH_HOST% ^(and %PVE_HOST% for Track 1^). >&2
  exit /b 1
)

if not "%RUN_STATE%"=="1" goto :track2

echo === Track 1: Pulling encrypted restic repo from %SSH_USER%@%PVE_HOST% ===
if not exist "%STATE_BACKUP_DIR%" mkdir "%STATE_BACKUP_DIR%"
if not exist "%STATE_BACKUP_DIR%" (
  echo ERROR: Cannot create "%STATE_BACKUP_DIR%". Is the target drive connected? >&2
  exit /b 1
)

ssh -i "%SSH_KEY%" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 "%SSH_USER%@%PVE_HOST%" "test -f /var/backups/homelab/restic/config"
if errorlevel 1 (
  echo ERROR: Cannot reach %SSH_USER%@%PVE_HOST% or /var/backups/homelab/restic/config is missing. >&2
  exit /b 1
)

if exist "%STATE_BACKUP_DIR%\restic.new" rmdir /s /q "%STATE_BACKUP_DIR%\restic.new"
mkdir "%STATE_BACKUP_DIR%\restic.new"
if not exist "%STATE_BACKUP_DIR%\restic.new" (
  echo ERROR: Cannot create staging directory "%STATE_BACKUP_DIR%\restic.new". >&2
  exit /b 1
)

ssh -i "%SSH_KEY%" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 "%SSH_USER%@%PVE_HOST%" "tar -C /var/backups/homelab/restic -cf - ." | tar -xf - -C "%STATE_BACKUP_DIR%\restic.new"
if errorlevel 1 (
  echo ERROR: Track 1 transfer failed. Existing backup was left untouched. >&2
  rmdir /s /q "%STATE_BACKUP_DIR%\restic.new" 2>nul
  exit /b 1
)

if not exist "%STATE_BACKUP_DIR%\restic.new\config" (
  echo ERROR: Track 1 staging missing restic config. Aborting swap. >&2
  rmdir /s /q "%STATE_BACKUP_DIR%\restic.new" 2>nul
  exit /b 1
)

if exist "%STATE_BACKUP_DIR%\restic.old" rmdir /s /q "%STATE_BACKUP_DIR%\restic.old"
if exist "%STATE_BACKUP_DIR%\restic" move /y "%STATE_BACKUP_DIR%\restic" "%STATE_BACKUP_DIR%\restic.old" >nul
move /y "%STATE_BACKUP_DIR%\restic.new" "%STATE_BACKUP_DIR%\restic" >nul
if errorlevel 1 (
  echo ERROR: Failed to activate new restic mirror. Restoring previous copy... >&2
  if exist "%STATE_BACKUP_DIR%\restic.old" move /y "%STATE_BACKUP_DIR%\restic.old" "%STATE_BACKUP_DIR%\restic" >nul
  exit /b 1
)
if exist "%STATE_BACKUP_DIR%\restic.old" rmdir /s /q "%STATE_BACKUP_DIR%\restic.old"
echo Track 1 synced -^> %STATE_BACKUP_DIR%\restic

:track2
if not "%RUN_PHOTOS%"=="1" goto :done

echo === Track 2: Pulling Immich original media from %SSH_USER%@%IMMICH_HOST% ===
echo (Excludes regeneratable thumbs/ and encoded-video/; incremental, no deletes for safety)
if not exist "%PHOTOS_BACKUP_DIR%" mkdir "%PHOTOS_BACKUP_DIR%"
if not exist "%PHOTOS_BACKUP_DIR%" (
  echo ERROR: Cannot create "%PHOTOS_BACKUP_DIR%". Is the target drive connected? >&2
  exit /b 1
)

ssh -i "%SSH_KEY%" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 "%SSH_USER%@%IMMICH_HOST%" "test -d /opt/immich/library && command -v python3 >/dev/null && command -v tar >/dev/null"
if errorlevel 1 (
  echo ERROR: Cannot reach %SSH_USER%@%IMMICH_HOST% or /opt/immich/library, python3, or tar is missing. >&2
  exit /b 1
)

set "PAYLOAD_FILE=%TEMP%\haytham-track2-%RANDOM%-%RANDOM%.tmp"
echo Scanning local backup folder "%PHOTOS_BACKUP_DIR%"...

> "%PAYLOAD_FILE%" echo import os, subprocess, sys
>> "%PAYLOAD_FILE%" echo base = '/opt/immich/library'
>> "%PAYLOAD_FILE%" echo lines = m.splitlines()
>> "%PAYLOAD_FILE%" echo pref = lines[0].replace('\\', '/').rstrip('/').lower() + '/'
>> "%PAYLOAD_FILE%" echo have = {}
>> "%PAYLOAD_FILE%" echo for line in lines[1:]:
>> "%PAYLOAD_FILE%" echo     if '?' not in line:
>> "%PAYLOAD_FILE%" echo         continue
>> "%PAYLOAD_FILE%" echo     sz, p = line.split('?', 1)
>> "%PAYLOAD_FILE%" echo     p = p.replace('\\', '/')
>> "%PAYLOAD_FILE%" echo     if sz.isdigit() and p.lower().startswith(pref):
>> "%PAYLOAD_FILE%" echo         have[p[len(pref):]] = int(sz)
>> "%PAYLOAD_FILE%" echo need = []
>> "%PAYLOAD_FILE%" echo skipped = 0
>> "%PAYLOAD_FILE%" echo for sub in ('library', 'upload', 'profile'):
>> "%PAYLOAD_FILE%" echo     root = os.path.join(base, sub)
>> "%PAYLOAD_FILE%" echo     if not os.path.isdir(root):
>> "%PAYLOAD_FILE%" echo         continue
>> "%PAYLOAD_FILE%" echo     for dp, _, fns in os.walk(root):
>> "%PAYLOAD_FILE%" echo         for fn in fns:
>> "%PAYLOAD_FILE%" echo             fp = os.path.join(dp, fn)
>> "%PAYLOAD_FILE%" echo             rel = os.path.relpath(fp, base).replace('\\', '/')
>> "%PAYLOAD_FILE%" echo             if have.get(rel) == os.path.getsize(fp):
>> "%PAYLOAD_FILE%" echo                 skipped += 1
>> "%PAYLOAD_FILE%" echo             else:
>> "%PAYLOAD_FILE%" echo                 need.append(rel)
>> "%PAYLOAD_FILE%" echo sys.stderr.write('[Track 2] ' + str(len(need)) + ' new/changed files (' + str(skipped) + ' already backed up)\n')
>> "%PAYLOAD_FILE%" echo sys.stderr.flush()
>> "%PAYLOAD_FILE%" echo if not need:
>> "%PAYLOAD_FILE%" echo     sys.exit(subprocess.call(['tar', '-cf', '-', '-T', '/dev/null']))
>> "%PAYLOAD_FILE%" echo proc = subprocess.Popen(['tar', '-C', base, '-cf', '-', '--null', '-T', '-'], stdin=subprocess.PIPE)
>> "%PAYLOAD_FILE%" echo proc.communicate(b'\0'.join(r.encode('utf-8') for r in need) + b'\0')
>> "%PAYLOAD_FILE%" echo sys.exit(proc.returncode)
>> "%PAYLOAD_FILE%" echo ================
>> "%PAYLOAD_FILE%" echo %PHOTOS_BACKUP_DIR%
(for /r "%PHOTOS_BACKUP_DIR%" %%F in (*) do @echo %%~zF?%%~fF) >> "%PAYLOAD_FILE%"

ssh -i "%SSH_KEY%" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 "%SSH_USER%@%IMMICH_HOST%" "python3 -c 'import sys; s,m=sys.stdin.read().replace(chr(13)+chr(10),chr(10)).split(chr(10)+chr(61)*16+chr(10),1); exec(s)'" < "%PAYLOAD_FILE%" | tar -xvf - -C "%PHOTOS_BACKUP_DIR%"
set "SYNC_RC=%ERRORLEVEL%"
del /q "%PAYLOAD_FILE%" 2>nul

if not "%SYNC_RC%"=="0" (
  echo ERROR: Track 2 transfer failed. Re-run to resume from where it stopped. >&2
  exit /b 1
)
echo Track 2 synced -^> %PHOTOS_BACKUP_DIR%

:done
echo === Off-host backup pull complete ===
exit /b 0

:usage
echo Usage: %~nx0 [--state-only ^| --photos-only]
echo.
echo Environment overrides:
echo   PVE_HOST          (default: 192.168.100.2)
echo   IMMICH_HOST       (default: 192.168.100.61)
echo   SSH_USER          (default: root)
echo   SSH_KEY           (default: %%USERPROFILE%%\.ssh\id_ed25519)
echo   STATE_BACKUP_DIR  (default: %%USERPROFILE%%\Backups\haytham\state)
echo   PHOTOS_BACKUP_DIR (default: %%USERPROFILE%%\Backups\haytham\immich-originals)
exit /b 0
