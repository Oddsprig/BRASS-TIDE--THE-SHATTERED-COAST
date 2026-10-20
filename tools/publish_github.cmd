@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "GIT_TERMINAL_PROMPT=0"
set "GCM_INTERACTIVE=Never"
set "GCM_GUI_PROMPT=0"
pushd "%~dp0.." || exit /b 1
git --version >nul 2>&1
if errorlevel 1 (
    echo Git for Windows is required to publish the source.
    goto failed
)
set "BRASS_REMOTE="
for /f "delims=" %%I in ('git remote get-url origin') do set "BRASS_REMOTE=%%I"
if not "%BRASS_REMOTE%"=="https://github.com/Oddsprig/BRASS-TIDE--THE-SHATTERED-COAST.git" (
    echo Stopped: origin does not match the owner's verified repository.
    goto failed
)
set "BRASS_PUSH_REMOTE="
for /f "delims=" %%I in ('git remote get-url --push origin') do set "BRASS_PUSH_REMOTE=%%I"
if not "%BRASS_PUSH_REMOTE%"=="%BRASS_REMOTE%" (
    echo Stopped: the push destination differs from the verified repository.
    goto failed
)
set "BRASS_PUSH_OVERRIDE="
for /f "delims=" %%I in ('git config --get-all remote.origin.pushurl') do set "BRASS_PUSH_OVERRIDE=1"
if defined BRASS_PUSH_OVERRIDE (
    echo Stopped: remove separate push URL overrides before publishing.
    goto failed
)
set "BRASS_BRANCH="
for /f "delims=" %%I in ('git symbolic-ref --quiet --short HEAD') do set "BRASS_BRANCH=%%I"
if not "%BRASS_BRANCH%"=="main" (
    echo Stopped: the source must be on main.
    goto failed
)
set "BRASS_ORIGINAL_TAG="
for /f "delims=" %%I in ('git rev-parse refs/tags/v0.001') do set "BRASS_ORIGINAL_TAG=%%I"
if not "%BRASS_ORIGINAL_TAG%"=="8c71de042ce02cc119ba74965c869e905fe6a642" (
    echo Stopped: the verified annotated v0.001 tag has changed.
    goto failed
)
git merge-base --is-ancestor v0.001 main
if errorlevel 1 (
    echo Stopped: main must include the verified release history.
    goto failed
)
set "BRASS_RELEASE="
for /f "tokens=2 delims==" %%I in ('findstr /b /c:"config/version=" game\project.godot') do set "BRASS_RELEASE=%%~I"
if not defined BRASS_RELEASE goto failed
set "BRASS_REF=v%BRASS_RELEASE%"
set "BRASS_TAG="
for /f "delims=" %%I in ('git rev-parse refs/tags/%BRASS_REF%') do set "BRASS_TAG=%%I"
set "BRASS_TAG_TYPE="
for /f "delims=" %%I in ('git cat-file -t refs/tags/%BRASS_REF%') do set "BRASS_TAG_TYPE=%%I"
if not "%BRASS_TAG_TYPE%"=="tag" (
    echo Stopped: the current release needs an annotated version tag.
    goto failed
)
git merge-base --is-ancestor %BRASS_REF% main
if errorlevel 1 goto failed
git diff --quiet %BRASS_REF% main -- game
if errorlevel 1 (
    echo Stopped: game files differ from the current tagged build.
    goto failed
)
set "BRASS_DIRTY="
for /f "delims=" %%I in ('git status --porcelain') do set "BRASS_DIRTY=1"
if defined BRASS_DIRTY (
    echo Stopped: commit or preserve local source changes before publishing.
    goto failed
)
set "BRASS_HEAD="
for /f "delims=" %%I in ('git rev-parse refs/heads/main') do set "BRASS_HEAD=%%I"
if /i "%~1"=="--check-only" (
    echo PASS: destination, clean main, tagged game and annotated %BRASS_REF% verified.
    popd
    exit /b 0
)
echo Publishing Brass Tide main and %BRASS_REF% to the verified repository.
echo Existing remote history is protected; this does not force-push.
git push --atomic --set-upstream --porcelain origin refs/heads/main:refs/heads/main refs/tags/%BRASS_REF%:refs/tags/%BRASS_REF%
if errorlevel 1 (
    echo Publishing did not complete. Check GitHub sign-in and the message above.
    echo No browser or sign-in window was opened by this publisher.
    goto failed
)
set "BRASS_REMOTE_HEAD="
set "BRASS_REMOTE_TAG="
for /f "tokens=1" %%I in ('git ls-remote --refs origin refs/heads/main') do set "BRASS_REMOTE_HEAD=%%I"
for /f "tokens=1" %%I in ('git ls-remote --refs origin refs/tags/%BRASS_REF%') do set "BRASS_REMOTE_TAG=%%I"
if not "%BRASS_REMOTE_HEAD%"=="%BRASS_HEAD%" goto unverified
if not "%BRASS_REMOTE_TAG%"=="%BRASS_TAG%" goto unverified
echo SUCCESS: GitHub main and the annotated %BRASS_REF% tag match the local source.
echo https://github.com/Oddsprig/BRASS-TIDE--THE-SHATTERED-COAST
popd
exit /b 0

:unverified
echo The push returned success, but remote verification did not match.
echo Check the repository before retrying; no force-push was attempted.
:failed
popd
exit /b 1
