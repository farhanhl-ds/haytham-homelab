@echo off
setlocal
chcp 65001 >nul

REM Off-host local-network backup pull script for native Windows cmd.
REM Zero WSL, zero third-party binaries (Device Guard / Smart App Control safe).
REM Uses only Microsoft-signed inbox Windows tools: cmd.exe, ssh.exe, and tar.exe.
REM
REM Prerequisites:
REM   Windows-only Break-Glass / Backup-Pull SSH key at %USERPROFILE%\.ssh\id_ed25519
REM   (separate from haytham-ctl's revocable control-node key) authorized on:
REM     - Zone 2 CT 121 Immich (192.168.100.21) for Track 2 photos
REM     - Zone 0 Proxmox host  (192.168.100.2)  for Track 1 restic state (incl. CT 110 Infisical)
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
if not defined IMMICH_HOST set "IMMICH_HOST=192.168.100.21"
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

ssh -i "%SSH_KEY%" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 "%SSH_USER%@%PVE_HOST%" "test -f /var/backups/homelab/restic/config && command -v python3 >/dev/null"
if errorlevel 1 (
  echo ERROR: Cannot reach %SSH_USER%@%PVE_HOST%, /var/backups/homelab/restic/config is missing, or python3 is missing. >&2
  exit /b 1
)

if exist "%STATE_BACKUP_DIR%\restic.new" rmdir /s /q "%STATE_BACKUP_DIR%\restic.new"
mkdir "%STATE_BACKUP_DIR%\restic.new"
if not exist "%STATE_BACKUP_DIR%\restic.new" (
  echo ERROR: Cannot create staging directory "%STATE_BACKUP_DIR%\restic.new". >&2
  exit /b 1
)

set "T1_SCRIPT=%TEMP%\haytham-track1-%RANDOM%-%RANDOM%.tmp"
> "%T1_SCRIPT%" echo import os, sys, tarfile, time
>> "%T1_SCRIPT%" echo base = "/var/backups/homelab/restic"
>> "%T1_SCRIPT%" echo dirs, files, total_bytes = [], [], 0
>> "%T1_SCRIPT%" echo for dp, dns, fns in os.walk(base):
>> "%T1_SCRIPT%" echo     for d in dns:
>> "%T1_SCRIPT%" echo         fp = os.path.join(dp, d)
>> "%T1_SCRIPT%" echo         dirs.append((fp, os.path.relpath(fp, base).replace("\\", "/")))
>> "%T1_SCRIPT%" echo     for fn in fns:
>> "%T1_SCRIPT%" echo         fp = os.path.join(dp, fn)
>> "%T1_SCRIPT%" echo         if not os.path.isfile(fp):
>> "%T1_SCRIPT%" echo             continue
>> "%T1_SCRIPT%" echo         sz = os.path.getsize(fp)
>> "%T1_SCRIPT%" echo         files.append((fp, os.path.relpath(fp, base).replace("\\", "/"), sz))
>> "%T1_SCRIPT%" echo         total_bytes += sz
>> "%T1_SCRIPT%" echo def hsz(n):
>> "%T1_SCRIPT%" echo     for u in ("B", "KB", "MB", "GB", "TB"):
>> "%T1_SCRIPT%" echo         if n ^< 1024 or u == "TB":
>> "%T1_SCRIPT%" echo             return f"{n:.0f}B" if u == "B" else f"{n:.1f}{u}"
>> "%T1_SCRIPT%" echo         n /= 1024.0
>> "%T1_SCRIPT%" echo def htm(s):
>> "%T1_SCRIPT%" echo     s = max(0, int(s))
>> "%T1_SCRIPT%" echo     m2, s2 = divmod(s, 60)
>> "%T1_SCRIPT%" echo     h2, m2 = divmod(m2, 60)
>> "%T1_SCRIPT%" echo     return f"{h2:d}:{m2:02d}:{s2:02d}" if h2 else f"{m2:02d}:{s2:02d}"
>> "%T1_SCRIPT%" echo sys.stderr.write(f"[Track 1] {len(files)} files ({hsz(total_bytes)})\n")
>> "%T1_SCRIPT%" echo sys.stderr.flush()
>> "%T1_SCRIPT%" echo done_bytes, t0, last_t, last_len = 0, time.monotonic(), 0.0, 0
>> "%T1_SCRIPT%" echo def show(idx, name, final=False):
>> "%T1_SCRIPT%" echo     global last_t, last_len
>> "%T1_SCRIPT%" echo     now = time.monotonic()
>> "%T1_SCRIPT%" echo     if not final and (now - last_t) ^< 0.2:
>> "%T1_SCRIPT%" echo         return
>> "%T1_SCRIPT%" echo     last_t = now
>> "%T1_SCRIPT%" echo     pct = 100.0 if total_bytes == 0 else min(100.0, done_bytes * 100.0 / total_bytes)
>> "%T1_SCRIPT%" echo     fill = int(pct * 16 / 100)
>> "%T1_SCRIPT%" echo     bar = "#" * fill + "-" * (16 - fill)
>> "%T1_SCRIPT%" echo     el = max(0.001, now - t0)
>> "%T1_SCRIPT%" echo     spd = done_bytes / el
>> "%T1_SCRIPT%" echo     if final:
>> "%T1_SCRIPT%" echo         msg = f"[{bar}] 100.0%% {len(files)}/{len(files)} {hsz(done_bytes)}/{hsz(total_bytes)} {hsz(spd)}/s done ({htm(el)})"
>> "%T1_SCRIPT%" echo     else:
>> "%T1_SCRIPT%" echo         eta_s = htm((total_bytes - done_bytes) / spd) if spd ^> 0 else "--:--"
>> "%T1_SCRIPT%" echo         pre = f"[{bar}] {pct:5.1f}%% {idx}/{len(files)} {hsz(done_bytes)}/{hsz(total_bytes)} {hsz(spd)}/s ETA {eta_s} "
>> "%T1_SCRIPT%" echo         rem = 78 - len(pre)
>> "%T1_SCRIPT%" echo         nm = name if len(name) ^<= rem else (name[:max(1, rem - 3)] + "...")
>> "%T1_SCRIPT%" echo         msg = pre + (nm if rem ^> 3 else "")
>> "%T1_SCRIPT%" echo     pad = " " * max(0, last_len - len(msg))
>> "%T1_SCRIPT%" echo     last_len = len(msg)
>> "%T1_SCRIPT%" echo     sys.stderr.write("\r" + msg + pad + ("\n" if final else ""))
>> "%T1_SCRIPT%" echo     sys.stderr.flush()
>> "%T1_SCRIPT%" echo class PF:
>> "%T1_SCRIPT%" echo     def __init__(self, f, idx, name):
>> "%T1_SCRIPT%" echo         self.f, self.idx, self.name = f, idx, name
>> "%T1_SCRIPT%" echo     def read(self, n=-1):
>> "%T1_SCRIPT%" echo         global done_bytes
>> "%T1_SCRIPT%" echo         b = self.f.read(n)
>> "%T1_SCRIPT%" echo         if b:
>> "%T1_SCRIPT%" echo             done_bytes += len(b)
>> "%T1_SCRIPT%" echo             show(self.idx, self.name)
>> "%T1_SCRIPT%" echo         return b
>> "%T1_SCRIPT%" echo with tarfile.open(fileobj=sys.stdout.buffer, mode="w|") as tf:
>> "%T1_SCRIPT%" echo     for fp, rel in dirs:
>> "%T1_SCRIPT%" echo         tf.add(fp, arcname=rel, recursive=False)
>> "%T1_SCRIPT%" echo     for i, (fp, rel, _) in enumerate(files, 1):
>> "%T1_SCRIPT%" echo         nm = os.path.basename(rel)
>> "%T1_SCRIPT%" echo         show(i, nm)
>> "%T1_SCRIPT%" echo         with open(fp, "rb") as f:
>> "%T1_SCRIPT%" echo             ti = tf.gettarinfo(arcname=rel, fileobj=f)
>> "%T1_SCRIPT%" echo             tf.addfile(ti, PF(f, i, nm))
>> "%T1_SCRIPT%" echo sys.stdout.buffer.flush()
>> "%T1_SCRIPT%" echo if files:
>> "%T1_SCRIPT%" echo     show(len(files), "", True)

ssh -i "%SSH_KEY%" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 "%SSH_USER%@%PVE_HOST%" "python3 -" < "%T1_SCRIPT%" | tar -xf - -C "%STATE_BACKUP_DIR%\restic.new"
set "T1_RC=%ERRORLEVEL%"
del /q "%T1_SCRIPT%" 2>nul
if not "%T1_RC%"=="0" (
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

ssh -i "%SSH_KEY%" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 "%SSH_USER%@%IMMICH_HOST%" "test -d /opt/immich/library && command -v python3 >/dev/null"
if errorlevel 1 (
  echo ERROR: Cannot reach %SSH_USER%@%IMMICH_HOST% or /opt/immich/library or python3 is missing. >&2
  exit /b 1
)

set "PAYLOAD_FILE=%TEMP%\haytham-track2-%RANDOM%-%RANDOM%.tmp"
echo Scanning local backup folder "%PHOTOS_BACKUP_DIR%"...

> "%PAYLOAD_FILE%" echo import os, sys, tarfile, time
>> "%PAYLOAD_FILE%" echo base = "/opt/immich/library"
>> "%PAYLOAD_FILE%" echo lines = m.splitlines()
>> "%PAYLOAD_FILE%" echo pref = lines[0].replace("\\", "/").rstrip("/").lower() + "/"
>> "%PAYLOAD_FILE%" echo have = {}
>> "%PAYLOAD_FILE%" echo for line in lines[1:]:
>> "%PAYLOAD_FILE%" echo     if "?" not in line:
>> "%PAYLOAD_FILE%" echo         continue
>> "%PAYLOAD_FILE%" echo     sz, p = line.split("?", 1)
>> "%PAYLOAD_FILE%" echo     p = p.replace("\\", "/")
>> "%PAYLOAD_FILE%" echo     if sz.isdigit() and p.lower().startswith(pref):
>> "%PAYLOAD_FILE%" echo         have[p[len(pref):]] = int(sz)
>> "%PAYLOAD_FILE%" echo need, skipped, total_bytes = [], 0, 0
>> "%PAYLOAD_FILE%" echo for sub in ("library", "upload", "profile"):
>> "%PAYLOAD_FILE%" echo     root = os.path.join(base, sub)
>> "%PAYLOAD_FILE%" echo     if not os.path.isdir(root):
>> "%PAYLOAD_FILE%" echo         continue
>> "%PAYLOAD_FILE%" echo     for dp, _, fns in os.walk(root):
>> "%PAYLOAD_FILE%" echo         for fn in fns:
>> "%PAYLOAD_FILE%" echo             fp = os.path.join(dp, fn)
>> "%PAYLOAD_FILE%" echo             if not os.path.isfile(fp):
>> "%PAYLOAD_FILE%" echo                 continue
>> "%PAYLOAD_FILE%" echo             rel = os.path.relpath(fp, base).replace("\\", "/")
>> "%PAYLOAD_FILE%" echo             fsz = os.path.getsize(fp)
>> "%PAYLOAD_FILE%" echo             if have.get(rel) == fsz:
>> "%PAYLOAD_FILE%" echo                 skipped += 1
>> "%PAYLOAD_FILE%" echo             else:
>> "%PAYLOAD_FILE%" echo                 need.append((fp, rel, fsz))
>> "%PAYLOAD_FILE%" echo                 total_bytes += fsz
>> "%PAYLOAD_FILE%" echo def hsz(n):
>> "%PAYLOAD_FILE%" echo     for u in ("B", "KB", "MB", "GB", "TB"):
>> "%PAYLOAD_FILE%" echo         if n ^< 1024 or u == "TB":
>> "%PAYLOAD_FILE%" echo             return f"{n:.0f}B" if u == "B" else f"{n:.1f}{u}"
>> "%PAYLOAD_FILE%" echo         n /= 1024.0
>> "%PAYLOAD_FILE%" echo def htm(s):
>> "%PAYLOAD_FILE%" echo     s = max(0, int(s))
>> "%PAYLOAD_FILE%" echo     m2, s2 = divmod(s, 60)
>> "%PAYLOAD_FILE%" echo     h2, m2 = divmod(m2, 60)
>> "%PAYLOAD_FILE%" echo     return f"{h2:d}:{m2:02d}:{s2:02d}" if h2 else f"{m2:02d}:{s2:02d}"
>> "%PAYLOAD_FILE%" echo sys.stderr.write(f"[Track 2] {len(need)} new/changed files ({hsz(total_bytes)}) - {skipped} already backed up\n")
>> "%PAYLOAD_FILE%" echo sys.stderr.flush()
>> "%PAYLOAD_FILE%" echo done_bytes, t0, last_t, last_len = 0, time.monotonic(), 0.0, 0
>> "%PAYLOAD_FILE%" echo def show(idx, name, final=False):
>> "%PAYLOAD_FILE%" echo     global last_t, last_len
>> "%PAYLOAD_FILE%" echo     now = time.monotonic()
>> "%PAYLOAD_FILE%" echo     if not final and (now - last_t) ^< 0.2:
>> "%PAYLOAD_FILE%" echo         return
>> "%PAYLOAD_FILE%" echo     last_t = now
>> "%PAYLOAD_FILE%" echo     pct = 100.0 if total_bytes == 0 else min(100.0, done_bytes * 100.0 / total_bytes)
>> "%PAYLOAD_FILE%" echo     fill = int(pct * 16 / 100)
>> "%PAYLOAD_FILE%" echo     bar = "#" * fill + "-" * (16 - fill)
>> "%PAYLOAD_FILE%" echo     el = max(0.001, now - t0)
>> "%PAYLOAD_FILE%" echo     spd = done_bytes / el
>> "%PAYLOAD_FILE%" echo     if final:
>> "%PAYLOAD_FILE%" echo         msg = f"[{bar}] 100.0%% {len(need)}/{len(need)} {hsz(done_bytes)}/{hsz(total_bytes)} {hsz(spd)}/s done ({htm(el)})"
>> "%PAYLOAD_FILE%" echo     else:
>> "%PAYLOAD_FILE%" echo         eta_s = htm((total_bytes - done_bytes) / spd) if spd ^> 0 else "--:--"
>> "%PAYLOAD_FILE%" echo         pre = f"[{bar}] {pct:5.1f}%% {idx}/{len(need)} {hsz(done_bytes)}/{hsz(total_bytes)} {hsz(spd)}/s ETA {eta_s} "
>> "%PAYLOAD_FILE%" echo         rem = 78 - len(pre)
>> "%PAYLOAD_FILE%" echo         nm = name if len(name) ^<= rem else (name[:max(1, rem - 3)] + "...")
>> "%PAYLOAD_FILE%" echo         msg = pre + (nm if rem ^> 3 else "")
>> "%PAYLOAD_FILE%" echo     pad = " " * max(0, last_len - len(msg))
>> "%PAYLOAD_FILE%" echo     last_len = len(msg)
>> "%PAYLOAD_FILE%" echo     sys.stderr.write("\r" + msg + pad + ("\n" if final else ""))
>> "%PAYLOAD_FILE%" echo     sys.stderr.flush()
>> "%PAYLOAD_FILE%" echo class PF:
>> "%PAYLOAD_FILE%" echo     def __init__(self, f, idx, name):
>> "%PAYLOAD_FILE%" echo         self.f, self.idx, self.name = f, idx, name
>> "%PAYLOAD_FILE%" echo     def read(self, n=-1):
>> "%PAYLOAD_FILE%" echo         global done_bytes
>> "%PAYLOAD_FILE%" echo         b = self.f.read(n)
>> "%PAYLOAD_FILE%" echo         if b:
>> "%PAYLOAD_FILE%" echo             done_bytes += len(b)
>> "%PAYLOAD_FILE%" echo             show(self.idx, self.name)
>> "%PAYLOAD_FILE%" echo         return b
>> "%PAYLOAD_FILE%" echo with tarfile.open(fileobj=sys.stdout.buffer, mode="w|") as tf:
>> "%PAYLOAD_FILE%" echo     for i, (fp, rel, _) in enumerate(need, 1):
>> "%PAYLOAD_FILE%" echo         nm = os.path.basename(rel)
>> "%PAYLOAD_FILE%" echo         show(i, nm)
>> "%PAYLOAD_FILE%" echo         with open(fp, "rb") as f:
>> "%PAYLOAD_FILE%" echo             ti = tf.gettarinfo(arcname=rel, fileobj=f)
>> "%PAYLOAD_FILE%" echo             tf.addfile(ti, PF(f, i, nm))
>> "%PAYLOAD_FILE%" echo sys.stdout.buffer.flush()
>> "%PAYLOAD_FILE%" echo if need:
>> "%PAYLOAD_FILE%" echo     show(len(need), "", True)
>> "%PAYLOAD_FILE%" echo ================
>> "%PAYLOAD_FILE%" echo %PHOTOS_BACKUP_DIR%
(for /r "%PHOTOS_BACKUP_DIR%" %%F in (*) do @echo %%~zF?%%~fF) >> "%PAYLOAD_FILE%"

ssh -i "%SSH_KEY%" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 "%SSH_USER%@%IMMICH_HOST%" "python3 -c 'import sys; s,m=sys.stdin.read().replace(chr(13)+chr(10),chr(10)).split(chr(10)+chr(61)*16+chr(10),1); exec(s)'" < "%PAYLOAD_FILE%" | tar -xf - -C "%PHOTOS_BACKUP_DIR%"
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
echo   IMMICH_HOST       (default: 192.168.100.21)
echo   SSH_USER          (default: root)
echo   SSH_KEY           (default: %%USERPROFILE%%\.ssh\id_ed25519)
echo   STATE_BACKUP_DIR  (default: %%USERPROFILE%%\Backups\haytham\state)
echo   PHOTOS_BACKUP_DIR (default: %%USERPROFILE%%\Backups\haytham\immich-originals)
exit /b 0
