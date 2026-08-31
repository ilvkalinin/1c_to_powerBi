# Windows Task Scheduler: observation refresh chain

This is a handoff script, not an installed task. Install it only on VM-2 by an
operator with Windows Task Scheduler authority after reviewing the project path
and Python path.

```bat
@echo off
setlocal
cd /d C:\path\to\База sql НФГ
C:\path\to\python.exe scripts\run_renewal_management_observation_chain.py
exit /b %ERRORLEVEL%
```

Create one task with no parallel instances, a timeout and a log destination
without credentials. A non-zero process exit is a failed chain; do not run the
observation loader separately after such a failure. This command runs the
parent refresh first and calls observation append only after its commit marker.
