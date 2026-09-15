# A wizard walks a human through a manual procedure, step by step.
# PowerShell port of the wizard library in Setup.command (from the /wizard
# skill's template.sh). Double-click Setup.cmd to run it; see README.md.
#
# Everything above the "STAGES" marker is the wizard library: do not hand-edit
# it. Author the per-step stages below the marker.
#
# Targets Windows PowerShell 5.1 (the engine every Windows 11 machine has):
# no &&/|| pipeline chains, no ternary, no ??/?., no $PSStyle. The file is
# UTF-8 with BOM -- 5.1 reads BOM-less .ps1 as ANSI and mangles the glyphs.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Wizard library: delightful, consistent UX, mirroring template.sh helper for
# helper. Helper names keep bash parity (PSUseApprovedVerbs is deliberately
# unsatisfied). The env/secret helpers (write_env, ask_secret, set_secret,
# set_var) are omitted: this wizard captures no values, and the PowerShell
# library ships only what it uses until a template.ps1 exists.
# ---------------------------------------------------------------------------

# Distro output decodes as UTF-8; wsl.exe's own messages would otherwise be
# UTF-16LE and defeat string matching.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
$env:WSL_UTF8 = '1'
# $LASTEXITCODE does not exist until a native command runs; pre-seed it so
# strict mode never trips on an early read.
$global:LASTEXITCODE = 0

# The [[ -t 0 ]] equivalent: every mutation gates on this, so a run with
# redirected stdin (the agent readiness probe) changes nothing.
$script:Interactive = -not [Console]::IsInputRedirected
$script:Pretty = -not [Console]::IsOutputRedirected

# Raw VT escapes: Windows Terminal (the Windows 11 default console) renders
# them fine under PowerShell 5.1.
$esc = [char]27
if ($script:Pretty) {
  $script:BOLD = "$esc[1m"
  $script:DIM = "$esc[2m"
  $script:RESET = "$esc[0m"
  $script:BLUE = "$esc[34m"
  $script:GREEN = "$esc[32m"
  $script:YELLOW = "$esc[33m"
} else {
  $script:BOLD = ''
  $script:DIM = ''
  $script:RESET = ''
  $script:BLUE = ''
  $script:GREEN = ''
  $script:YELLOW = ''
}

# Author sets this at the top of the stages section.
$script:TotalStages = 0

$script:StageIndex = 0
$script:SKIPPED = @() # things we couldn't do (printed by finish)

# Exit status of the last Invoke-Ubuntu call (kept separate from
# $LASTEXITCODE, which later PowerShell-side native calls overwrite).
$script:UbuntuExit = 0

# Runs a native command with non-terminating error handling: PowerShell 5.1
# can turn native stderr into a terminating error when the stream is
# redirected under $ErrorActionPreference = 'Stop'.
function Invoke-Native {
  param([Parameter(Mandatory = $true)][scriptblock]$Block)
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try { & $Block } finally { $ErrorActionPreference = $prev }
}

# _clear wipes the terminal so only the current step is on screen. No-op when
# output isn't a terminal, so piped logs stay readable.
function _clear {
  if ($script:Pretty) { Clear-Host }
}

# banner "Title" shows the opening frame: what this wizard does.
function banner {
  param([string]$Title)
  _clear
  Write-Host ''
  Write-Host ("$($script:BOLD)$($script:BLUE)  $Title$($script:RESET)")
  Write-Host ("$($script:DIM)  $($script:TotalStages) stages$($script:RESET)")
  Write-Host ''
  Write-Host ("$($script:DIM)  This wizard tells you exactly what to do and checks each step as you")
  Write-Host ('  go. Close it any time and open it again later — it picks up where you')
  Write-Host ("  left off.$($script:RESET)")
  pause 'Ready to start?'
}

# stage "Name" clears the screen, then announces a stage and shows progress.
# Clearing keeps only the current step on screen.
function stage {
  param([string]$Name)
  _clear
  $script:StageIndex++
  Write-Host ''
  Write-Host ("$($script:BOLD)$($script:BLUE)▸ Stage $($script:StageIndex)/$($script:TotalStages) · $Name$($script:RESET)")
}

# say "..." prints a plain instruction line.
function say {
  param([string]$Message)
  Write-Host ('  ' + $Message)
}
# step "..." is a numbered-feeling action the human takes in the browser.
function step {
  param([string]$Message)
  Write-Host ("  $($script:BLUE)•$($script:RESET) " + $Message)
}
function note {
  param([string]$Message)
  Write-Host ("  $($script:DIM)" + $Message + $script:RESET)
}
function warn {
  param([string]$Message)
  Write-Host ("  $($script:YELLOW)⚠ " + $Message + $script:RESET)
}
# ok "..." marks a step done or already satisfied.
function ok {
  param([string]$Message)
  Write-Host ("  $($script:BOLD)$($script:GREEN)✓ " + $Message + $script:RESET)
}

# open_url URL opens it in the human's browser.
function open_url {
  param([string]$Url)
  Write-Host ("  $($script:GREEN)↗ opening$($script:RESET) " + $Url)
  try { Start-Process $Url } catch { warn ("couldn't open a browser; visit it manually: " + $Url) }
}

# pause "msg" waits for the human to confirm they've done the manual part.
# Returns immediately on a non-interactive run, like read at EOF in bash.
function pause {
  param([string]$Message = 'Press Enter to continue')
  if (-not $script:Interactive) { return }
  Write-Host -NoNewline ("  $($script:DIM)$Message$($script:RESET) ")
  $null = Read-Host
}

# confirm "question" is a y/N gate; returns $true on yes.
function confirm {
  param([string]$Question)
  if (-not $script:Interactive) { return $false }
  Write-Host -NoNewline ("  $($script:YELLOW)? $Question [y/N]$($script:RESET) ")
  $reply = Read-Host
  return ($reply -match '^[Yy]')
}

# ask "Prompt" reads a line of visible input and returns it (bash's ask sets a
# named variable; PowerShell returns the value instead).
function ask {
  param([string]$Prompt)
  if (-not $script:Interactive) { return '' }
  Write-Host -NoNewline ("  $($script:BOLD)$Prompt$($script:RESET) ")
  return Read-Host
}

# ConvertTo-BashSingleQuoted makes a value safe to splice into a bash script
# as a single-quoted literal, whatever characters it contains.
function ConvertTo-BashSingleQuoted {
  param([string]$Value)
  return "'" + ($Value -replace "'", "'\''") + "'"
}

# Invoke-Ubuntu runs a bash script inside the Ubuntu distro. The script
# travels base64-encoded so no call site ever quotes across three shells
# (PowerShell -> wsl.exe argv -> bash); --exec keeps wsl.exe from re-joining
# the argv through a shell, and the bootstrap line contains no double quotes,
# which PowerShell 5.1 cannot pass through reliably. The inner shell is a
# login shell (-l) so the Nix profile is sourced, and the console stays
# attached, so bash read, sudo prompts, and gh's sign-in flow all work.
# -InRepo prepends a cd into the project's Ubuntu copy. -Capture returns
# stdout+stderr as one string instead of streaming to the console. The exit
# status lands in $script:UbuntuExit.
function Invoke-Ubuntu {
  param(
    [Parameter(Mandatory = $true)][string]$Script,
    [switch]$Capture,
    [switch]$InRepo
  )
  if ($InRepo) {
    $target = ConvertTo-BashSingleQuoted $script:WslRepoName
    $Script = ('cd "$HOME"/' + $target + " 2>/dev/null || exit 97`n") + $Script
  }
  # Here-strings inherit the file's line endings; bash needs bare LF.
  $Script = $Script -replace "`r", ''
  $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Script))
  $boot = 'exec bash -l <(printf %s ' + $b64 + ' | base64 -d)'
  if ($Capture) {
    $out = Invoke-Native { & wsl.exe -d Ubuntu --cd ~ --exec bash -c $boot 2>&1 }
    $script:UbuntuExit = $LASTEXITCODE
    if ($null -eq $out) { return '' }
    return (@($out | ForEach-Object { "$_" }) -join "`n")
  }
  Invoke-Native { & wsl.exe -d Ubuntu --cd ~ --exec bash -c $boot }
  $script:UbuntuExit = $LASTEXITCODE
}

# Test-Ubuntu runs a bash probe silently and returns $true when it exits 0.
function Test-Ubuntu {
  param([string]$Script, [switch]$InRepo)
  $silenced = '{ ' + $Script + " ; } >/dev/null 2>&1"
  $null = Invoke-Ubuntu -Script $silenced -Capture -InRepo:$InRepo
  return ($script:UbuntuExit -eq 0)
}

# finish clears, then shows a closing summary of everything configured.
function finish {
  _clear
  Write-Host ''
  Write-Host ("$($script:BOLD)$($script:GREEN)  ✓ Setup complete$($script:RESET)")
  if ($script:SKIPPED.Count -gt 0) {
    Write-Host ''
    warn 'still to do by hand:'
    foreach ($s in $script:SKIPPED) { note ('  - ' + $s) }
  }
  Write-Host ''
}

# ---------------------------------------------------------------------------
# STAGES: author this section. One stage per step the human takes.
# ---------------------------------------------------------------------------

$script:TotalStages = 10

# Double-clicked in Explorer (via Setup.cmd), the shell starts wherever cmd
# put it — move to the directory this script lives in before anything else.
Set-Location -LiteralPath $PSScriptRoot
if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'flake.nix'))) {
  warn 'Setup.ps1 seems to have been moved out of the project folder it came'
  warn "with. Put it back next to the rest of the project's files, then"
  warn 'double-click Setup.cmd there.'
  note '(Detail for a helper: it must sit in the repository root, beside flake.nix.)'
  exit 1
}

# The unzipped folder's name ("<repository>-<branch>" for a GitHub ZIP) is
# reused as the project's directory name inside Ubuntu, which keeps the
# GitHub stage's folder-name matching working there unchanged.
$script:WslRepoName = Split-Path -Leaf $PSScriptRoot

banner 'First-time setup (Windows)'

# -- Stage 1: your PC --------------------------------------------------------
# The wizard's own prerequisites are Windows 11 and a PC that can run
# virtual machines (Ubuntu runs inside one). This stage verifies those two
# and stops with precise instructions when they're missing, so every later
# stage can assume them. It's a gate, not a task, so it is never skipped.
stage 'Your PC'
if ($env:OS -ne 'Windows_NT') {
  warn 'This wizard covers Windows only. On a Mac, double-click Setup.command'
  warn 'instead. Setup for Linux will ship as a separate wizard.'
  exit 0
}
$os = Get-CimInstance Win32_OperatingSystem
if ([int]$os.BuildNumber -lt 22000) {
  warn 'This project needs Windows 11. This PC is on an older Windows, which'
  warn 'no longer receives regular security updates.'
  step 'Open Settings → Windows Update and upgrade to Windows 11 (free on supported PCs).'
  say 'Then double-click Setup.cmd again.'
  exit 0
}
say 'Windows 11 detected.'
$virtOk = $false
try {
  $cs = Get-CimInstance Win32_ComputerSystem
  if ($cs.HypervisorPresent) { $virtOk = $true }
  if (-not $virtOk) {
    foreach ($cpu in @(Get-CimInstance Win32_Processor)) {
      if ($cpu.VirtualizationFirmwareEnabled) { $virtOk = $true }
    }
  }
} catch { $virtOk = $false }
if (-not $virtOk) {
  warn "This PC has virtualization switched off, and the project's tools run"
  warn 'inside a small virtual machine.'
  say "It's a one-time switch in the PC's firmware settings — usually called"
  say "'Virtualization', 'Intel VT-x', 'AMD-V', or 'SVM'. Ask for help turning"
  say 'it on if the firmware screens are unfamiliar, then run this wizard again.'
  note '(Detail for a helper: neither HypervisorPresent nor VirtualizationFirmwareEnabled is true.)'
  exit 0
}
ok 'Everything this wizard needs is here. It handles the rest.'

# -- Stage 2: WSL ------------------------------------------------------------
stage 'Turn on the Linux layer'
say "The project's tools run in a small Linux environment that Windows"
say 'provides, called WSL. Turning it on is built into Windows.'
# wsl.exe --status works unelevated and exits nonzero until WSL is installed,
# so it doubles as the done-state probe.
$null = Invoke-Native { & wsl.exe --status 2>&1 }
if ($LASTEXITCODE -eq 0) {
  ok 'The Linux layer is already turned on — nothing to do.'
} elseif ($script:Interactive) {
  say 'Windows asks for permission once — approve the prompt that appears.'
  try {
    Start-Process -FilePath 'powershell' -Verb RunAs -Wait -ArgumentList '-NoProfile', '-Command', 'wsl --install --no-distribution'
  } catch {
    warn "That permission prompt was closed without approving, so nothing changed."
    say 'Double-click Setup.cmd again any time to retry.'
  }
  # Recent Windows 11 builds sometimes finish without needing a restart, so
  # re-probe before asking for one.
  $null = Invoke-Native { & wsl.exe --status 2>&1 }
  if ($LASTEXITCODE -eq 0) {
    ok 'The Linux layer is on.'
  } else {
    warn 'Windows needs a restart to finish turning this on.'
    say 'Restart your PC, then double-click Setup.cmd again — it picks up'
    say 'where it left off.'
    exit 0
  }
} else {
  note '(Non-interactive run — skipping the Windows feature change.)'
  $script:SKIPPED += 'Turn on WSL: wsl --install --no-distribution (as administrator, then restart)'
}

# -- Stage 3: Ubuntu ---------------------------------------------------------
stage 'Install Ubuntu'
say 'Ubuntu is the Linux system the project lives in. Windows downloads and'
say 'runs it for you.'
# Provisioned means first-run setup created a user: whoami answers and it
# isn't root. Probed before registration so a re-run lands on ok fast.
$who = (Invoke-Ubuntu -Capture 'whoami').Trim()
$provisioned = ($script:UbuntuExit -eq 0 -and $who -ne '' -and $who -ne 'root')
if (-not $provisioned) {
  if ($script:Interactive) {
    $registered = $false
    $distros = Invoke-Native { & wsl.exe --list --quiet 2>&1 }
    foreach ($line in @($distros | ForEach-Object { "$_" })) {
      if ($line.Trim() -eq 'Ubuntu') { $registered = $true }
    }
    say 'Ubuntu asks you to invent a username and password the first time it'
    say 'starts. The password is yours to choose — remember it, the wizard'
    say 'needs you to type it again in a later stage.'
    note '(The username wants to be short and lowercase, like a first name.)'
    say "When Ubuntu finishes and leaves you at a colorful text prompt, type"
    say "exit and press Enter to come back to this wizard."
    pause 'Ready?'
    if ($registered) {
      Invoke-Native { & wsl.exe -d Ubuntu }
    } else {
      Invoke-Native { & wsl.exe --install -d Ubuntu }
    }
    $who = (Invoke-Ubuntu -Capture 'whoami').Trim()
    $provisioned = ($script:UbuntuExit -eq 0 -and $who -ne '' -and $who -ne 'root')
    if (-not $provisioned) {
      warn "Ubuntu isn't finished setting up yet. If it asked you to restart,"
      warn 'do that; then double-click Setup.cmd again — it picks up here.'
      $script:SKIPPED += 'Install Ubuntu: wsl --install -d Ubuntu (then create the username it asks for)'
    }
  } else {
    note '(Non-interactive run — skipping the Ubuntu install.)'
    $script:SKIPPED += 'Install Ubuntu: wsl --install -d Ubuntu (then create the username it asks for)'
  }
}
if ($provisioned) {
  ok 'Ubuntu is installed and set up.'
  # The Nix installer expects systemd; current Ubuntu images ship it on, so
  # this only fires on an image old enough to predate that default.
  $initComm = (Invoke-Ubuntu -Capture 'ps -p 1 -o comm=').Trim()
  if ($initComm -ne 'systemd') {
    if ($script:Interactive) {
      say "One Ubuntu setting needs turning on; the wizard does it now. Ubuntu"
      say "asks for the password you just created."
      Invoke-Ubuntu @'
if [ -f /etc/wsl.conf ] && grep -q '^\[boot\]' /etc/wsl.conf; then
  exit 2
fi
printf '[boot]\nsystemd=true\n' | sudo tee -a /etc/wsl.conf >/dev/null
'@
      if ($script:UbuntuExit -eq 2) {
        warn "Ubuntu's settings file already has a section this wizard won't touch."
        warn 'Ask for help turning systemd on in it.'
        note '(Detail for a helper: /etc/wsl.conf has a [boot] section without systemd=true.)'
        $script:SKIPPED += 'Enable systemd in Ubuntu: add systemd=true under [boot] in /etc/wsl.conf, then wsl --shutdown'
      } elseif ($script:UbuntuExit -eq 0) {
        Invoke-Native { & wsl.exe --shutdown }
        $initComm = (Invoke-Ubuntu -Capture 'ps -p 1 -o comm=').Trim()
        if ($initComm -eq 'systemd') {
          ok 'The setting is on.'
        } else {
          warn "The setting didn't take. Double-click Setup.cmd again to retry."
          $script:SKIPPED += 'Enable systemd in Ubuntu: add systemd=true under [boot] in /etc/wsl.conf, then wsl --shutdown'
        }
      } else {
        warn "That didn't finish (the password prompt may have been dismissed)."
        $script:SKIPPED += 'Enable systemd in Ubuntu: add systemd=true under [boot] in /etc/wsl.conf, then wsl --shutdown'
      }
    } else {
      note '(Non-interactive run — skipping the Ubuntu settings change.)'
      $script:SKIPPED += 'Enable systemd in Ubuntu: add systemd=true under [boot] in /etc/wsl.conf, then wsl --shutdown'
    }
  }
  # Two small standard tools the later stages lean on; current Ubuntu images
  # usually ship both already.
  if (-not (Test-Ubuntu 'command -v git >/dev/null && command -v curl >/dev/null')) {
    if ($script:Interactive) {
      say 'Two small standard tools are missing from Ubuntu; the wizard adds'
      say 'them now. Ubuntu asks for your password.'
      Invoke-Ubuntu 'sudo apt-get update && sudo apt-get install -y git curl'
      if (Test-Ubuntu 'command -v git >/dev/null && command -v curl >/dev/null') {
        ok 'Added.'
      } else {
        warn "That didn't finish. Double-click Setup.cmd again to retry."
        $script:SKIPPED += "Install git and curl in Ubuntu: wsl -d Ubuntu -- bash -lc 'sudo apt-get update && sudo apt-get install -y git curl'"
      }
    } else {
      note '(Non-interactive run — skipping the tools install.)'
      $script:SKIPPED += "Install git and curl in Ubuntu: wsl -d Ubuntu -- bash -lc 'sudo apt-get update && sudo apt-get install -y git curl'"
    }
  }
}

# -- Stage 4: Nix ------------------------------------------------------------
stage 'Install Nix in Ubuntu'
say 'Nix is the only thing this project needs installed inside Ubuntu, and'
say 'Determinate Systems makes a one-line installer for it.'
# Probe the capability, not the setting: the daemon socket is what the
# project's automated helpers need, and 'builtins ? getFlake' is true on
# Determinate Nix (flakes stable) and on upstream Nix with flakes enabled.
$nixPresent = Test-Ubuntu 'command -v nix'
if (-not $nixPresent) {
  if ($script:Interactive) {
    say 'The install takes a few minutes. Ubuntu asks for your password once.'
    if (confirm 'Install Nix inside Ubuntu now?') {
      Invoke-Ubuntu 'curl -fsSL https://install.determinate.systems/nix | sh -s -- install --no-confirm'
      $nixPresent = Test-Ubuntu 'command -v nix'
      if (-not $nixPresent) {
        warn "The install didn't finish. The usual causes: no internet connection,"
        warn 'or the password prompt being dismissed. Double-click Setup.cmd again to retry.'
      }
    } else {
      say 'Skipping for now — double-click Setup.cmd again when ready.'
    }
    if (-not $nixPresent) {
      $script:SKIPPED += "Install Nix in Ubuntu: wsl -d Ubuntu -- bash -lc 'curl -fsSL https://install.determinate.systems/nix | sh -s -- install'"
    }
  } else {
    note '(Non-interactive run — skipping the Nix install.)'
    $script:SKIPPED += "Install Nix in Ubuntu: wsl -d Ubuntu -- bash -lc 'curl -fsSL https://install.determinate.systems/nix | sh -s -- install'"
  }
}
if ($nixPresent) {
  ok 'Nix is installed.'
  if (Test-Ubuntu 'test -S /nix/var/nix/daemon-socket/socket') {
    say "It's set up the way this project expects."
  } else {
    warn "Nix is installed, but in a way this project can't fully use — Claude's"
    warn "automated helpers won't be able to build things on their own."
    say 'To fix it: uninstall Nix inside Ubuntu, then run this wizard again —'
    say 'it reinstalls Nix the way the project expects.'
    note '(Detail for a helper: no daemon socket at /nix/var/nix/daemon-socket/socket inside the distro.)'
    pause
  }
  # Determinate Nix ships flakes as stable; this fallback only fires on a
  # pre-existing upstream Nix. Mirrors Setup.command stage 3, including the
  # promise never to overwrite an existing settings line.
  $flakesOut = (Invoke-Ubuntu -Capture "nix eval --expr 'builtins ? getFlake' 2>/dev/null").Trim()
  if ($flakesOut -ne 'true') {
    say 'Nix needs one settings line turned on before it can build this project;'
    say 'the wizard adds it now.'
    note "(The line: 'experimental-features = nix-command flakes' in ~/.config/nix/nix.conf)"
    if ($script:Interactive) {
      Invoke-Ubuntu @'
mkdir -p "$HOME/.config/nix"
touch "$HOME/.config/nix/nix.conf"
if grep -q '^experimental-features' "$HOME/.config/nix/nix.conf"; then
  exit 2
fi
printf 'experimental-features = nix-command flakes\n' >>"$HOME/.config/nix/nix.conf"
'@
      if ($script:UbuntuExit -eq 0) {
        ok 'Done — the setting is on.'
      } elseif ($script:UbuntuExit -eq 2) {
        warn "Your Nix settings file already has a line this wizard won't overwrite."
        warn "Ask for help adding 'nix-command flakes' to it, or edit it yourself:"
        note '  ~/.config/nix/nix.conf (inside Ubuntu)'
        pause
      } else {
        warn "That didn't finish. Double-click Setup.cmd again to retry."
        $script:SKIPPED += "Enable flakes: add 'experimental-features = nix-command flakes' to ~/.config/nix/nix.conf in Ubuntu"
      }
    } else {
      note '(Non-interactive run — skipping the settings change.)'
      $script:SKIPPED += "Enable flakes: add 'experimental-features = nix-command flakes' to ~/.config/nix/nix.conf in Ubuntu"
    }
  }
}

# -- Stage 5: move the project in --------------------------------------------
stage 'Move the project into Ubuntu'
say 'The project runs many times faster on Ubuntu''s own disk than on the'
say 'Windows one, so the wizard copies this folder in. From then on the'
say 'Ubuntu copy is the project; this Windows folder just starts the wizard.'
# Once the copy exists it is the live project and may have diverged, so a
# re-run from the stale Windows folder must never copy again.
if (Test-Ubuntu ('test -f "$HOME"/' + (ConvertTo-BashSingleQuoted $script:WslRepoName) + '/flake.nix')) {
  ok 'The project is already inside Ubuntu — nothing to copy.'
  $wslUser = (Invoke-Ubuntu -Capture 'whoami').Trim()
  note ('(In Windows, that folder appears as \\wsl.localhost\Ubuntu\home\' + $wslUser + '\' + $script:WslRepoName + ')')
} elseif ($script:Interactive) {
  if ($PSScriptRoot.StartsWith('\\')) {
    warn 'This wizard is already running from a network location, so there is no'
    warn 'Windows folder to copy in. If the project lives in Ubuntu under a'
    warn 'different name, keep using that copy.'
    $script:SKIPPED += 'Copy the project into Ubuntu (run the wizard from the unzipped folder on the Windows disk)'
  } else {
    say 'Copying now — usually under a minute.'
    $drive = $PSScriptRoot.Substring(0, 1).ToLower()
    $srcLinux = '/mnt/' + $drive + ($PSScriptRoot.Substring(2) -replace '\\', '/')
    $copyScript = @'
set -uo pipefail
src=__SRC__
name=__NAME__
if [ ! -f "$src/flake.nix" ]; then exit 3; fi
if [ -e "$HOME/$name" ]; then exit 4; fi
rm -rf "$HOME/.setup-partial-$name"
mkdir -p "$HOME/.setup-partial-$name"
if ! tar -C "$src" -cf - . | tar -C "$HOME/.setup-partial-$name" -xf -; then
  rm -rf "$HOME/.setup-partial-$name"
  exit 5
fi
mv "$HOME/.setup-partial-$name" "$HOME/$name"
'@
    $copyScript = $copyScript.Replace('__SRC__', (ConvertTo-BashSingleQuoted $srcLinux))
    $copyScript = $copyScript.Replace('__NAME__', (ConvertTo-BashSingleQuoted $script:WslRepoName))
    Invoke-Ubuntu $copyScript
    if ($script:UbuntuExit -eq 0) {
      ok 'The project now lives in Ubuntu.'
      $wslUser = (Invoke-Ubuntu -Capture 'whoami').Trim()
      say ('In Windows, it appears as \\wsl.localhost\Ubuntu\home\' + $wslUser + '\' + $script:WslRepoName)
      note '(This Windows folder is now just the wizard launcher; nothing else reads it.)'
    } elseif ($script:UbuntuExit -eq 4) {
      warn 'Ubuntu already has something by that name that does not look like this'
      warn 'project, so nothing was copied over it. Ask for help sorting that out.'
      note ('(Detail for a helper: ~/' + $script:WslRepoName + ' exists in the distro but has no flake.nix.)')
      $script:SKIPPED += ('Copy the project into Ubuntu (something already sits at ~/' + $script:WslRepoName + ')')
    } else {
      warn "The copy didn't finish. The usual cause: Ubuntu (stage 3) not being"
      warn 'ready yet. Double-click Setup.cmd again to retry — it never leaves a'
      warn 'half-made copy behind.'
      $script:SKIPPED += 'Copy the project into Ubuntu (double-click Setup.cmd again)'
    }
  }
} else {
  note '(Non-interactive run — skipping the copy.)'
  $script:SKIPPED += 'Copy the project into Ubuntu (double-click Setup.cmd, or tar-copy the folder to ~ in the distro)'
}

# -- Stage 6: toolchain ------------------------------------------------------
stage "Download the project's tools"
say 'Everything this project uses — including Claude Code — comes as one'
say 'download, so every machine gets the exact same versions. The Claude app'
say 'uses these same tools when you open the project.'
if (Test-Ubuntu -InRepo 'test -e .devshell/bin') {
  ok 'The tools are already downloaded — nothing to do.'
  note '(If they ever need refreshing: nix build .#toolchain --out-link .devshell)'
} elseif ($script:Interactive) {
  say 'This is the big download — expect several minutes the first time.'
  Invoke-Ubuntu -InRepo 'nix build .#toolchain --out-link .devshell'
  if ($script:UbuntuExit -eq 0) {
    ok 'Tools downloaded.'
  } else {
    warn "The download didn't finish. The usual causes: no internet connection,"
    warn 'or an earlier stage being skipped. Fix that and double-click Setup.cmd again.'
    $script:SKIPPED += 'nix build .#toolchain --out-link .devshell (in the Ubuntu copy)'
  }
} else {
  note '(Non-interactive run — skipping the download.)'
  $script:SKIPPED += 'nix build .#toolchain --out-link .devshell (in the Ubuntu copy)'
}

# -- Stage 7: dev shell + dependencies ---------------------------------------
stage "Install the project's building blocks"
say "Next, the project downloads the pieces it's built from. Most of it is"
say 'already there from the tools download, so this is quicker.'
# pnpm writes .modules.yaml on a successful install; its presence means this
# machine has already been through this stage.
if (Test-Ubuntu -InRepo 'test -f node_modules/.modules.yaml') {
  ok 'Already installed — nothing to do.'
  note "(If the project's ingredient lists change later, re-run: nix develop -c pnpm install)"
} elseif ($script:Interactive) {
  say 'Installing now — this can take a few minutes.'
  note '(Runs: nix develop -c pnpm install)'
  Invoke-Ubuntu -InRepo 'nix develop -c pnpm install'
  if ($script:UbuntuExit -eq 0) {
    ok 'Building blocks installed.'
  } else {
    warn "That didn't finish. The usual causes: the Nix stage being skipped, or"
    warn 'no internet. Fix that and open this wizard again — it skips'
    warn "what's already done."
    $script:SKIPPED += 'nix develop -c pnpm install (in the Ubuntu copy)'
  }
} else {
  note '(Non-interactive run — skipping the install.)'
  $script:SKIPPED += 'nix develop -c pnpm install (in the Ubuntu copy)'
}

# -- Stage 8: smoke check ----------------------------------------------------
stage 'Quick health check'
say 'A quick check confirms everything on this PC fits together.'
if ($script:Interactive) {
  say 'Checking now — a minute or two.'
  note '(Runs: nix develop -c pnpm check)'
  Invoke-Ubuntu -InRepo 'nix develop -c pnpm check'
  if ($script:UbuntuExit -eq 0) {
    ok 'Everything checks out. Your PC is ready.'
  } else {
    warn 'The check found problems. Open the Claude app and ask it to reinstall'
    warn 'and re-check, or show this to a teammate.'
    $script:SKIPPED += 'Health check (nix develop -c pnpm install, then nix develop -c pnpm check)'
  }
} else {
  note '(Non-interactive run — skipping the check.)'
  $script:SKIPPED += 'nix develop -c pnpm check (in the Ubuntu copy)'
}

# -- Stage 9: the Claude app -------------------------------------------------
stage 'The Claude app'
say 'This project is worked on inside the Claude desktop app: its Code tab is'
say 'where you open the project and ask for changes in plain English.'
say ''
# Probe the capability: the installed app itself. The docs never name the
# install directory; %LOCALAPPDATA%\AnthropicClaude is what the installer
# creates today — re-verify on a machine with the app if this probe ever
# misfires.
if (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'AnthropicClaude')) {
  ok 'The Claude app is already installed — nothing to download.'
} elseif ($script:Interactive) {
  say "It isn't installed yet. The download is a normal Windows installer."
  open_url 'https://claude.com/download'
  step 'Download the Windows version and open the downloaded file.'
  step 'Let the installer finish, then open Claude from the Start menu.'
  step 'Sign in with your Claude account (create one on the same screen if needed).'
  pause "Press Enter once you're signed in."
} else {
  note '(Non-interactive run — skipping the guided install.)'
  $script:SKIPPED += 'Install the Claude app: https://claude.com/download'
}
say ''
say 'Inside the app, the tab you want is Code. It needs a paid Claude plan'
say '(Pro, Max, Team, or Enterprise) — if the Code tab asks you to upgrade,'
say 'the plan is what''s missing, not your setup.'
step 'In the app: Code tab → pick the Ubuntu (WSL) environment → open the project folder there.'
$wslUser = (Invoke-Ubuntu -Capture 'whoami').Trim()
if ($script:UbuntuExit -eq 0 -and $wslUser -ne '') {
  note ('(The project folder inside Ubuntu: /home/' + $wslUser + '/' + $script:WslRepoName + ')')
}
if (-not (Test-Ubuntu -InRepo 'test -e .devshell/bin')) {
  warn "The tools download (stage 6) hasn't happened yet, so the Claude app"
  warn 'would have nothing to work with. Re-run this wizard to finish that first.'
}

# -- Stage 10: GitHub --------------------------------------------------------
stage 'GitHub'
say "The project's home is a GitHub repository. This stage checks that you can"
say 'reach it and that sharing your work with the team will just work.'
note "GitHub runs the project's checks automatically — nothing to set up for that."

# Already-done probe mirrors Setup.command: origin reachable without any
# credential or host-key prompt, and the local branch following the team's.
$ghProbe = 'git remote get-url origin >/dev/null 2>&1 && GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes" git ls-remote --exit-code origin HEAD >/dev/null 2>&1 && git rev-parse --abbrev-ref --symbolic-full-name @{upstream} >/dev/null 2>&1'
if (Test-Ubuntu -InRepo $ghProbe) {
  $origin = (Invoke-Ubuntu -Capture -InRepo 'git remote get-url origin').Trim()
  ok ('You can already reach the repository: ' + $origin)
  note 'When you share work, GitHub checks it automatically.'
} elseif (-not $script:Interactive) {
  note '(Non-interactive run — skipping the guided GitHub setup.)'
  $script:SKIPPED += "GitHub access: sign in and connect the folder (wsl -d Ubuntu, then in the project: .devshell/bin/gh auth login --web)"
} else {
  # The whole guided flow is one bash block ported from Setup.command stage 8,
  # run inside the distro where git, gh, and the browser handoff live. Its
  # prompts reach this console through wsl.exe. A nonzero exit means it left
  # something undone (it prints its own specifics).
  Invoke-Ubuntu -InRepo @'
set -uo pipefail
if [ -t 1 ]; then
  BOLD=$(printf '\033[1m'); DIM=$(printf '\033[2m'); RESET=$(printf '\033[0m')
  BLUE=$(printf '\033[34m'); GREEN=$(printf '\033[32m'); YELLOW=$(printf '\033[33m')
else
  BOLD=""; DIM=""; RESET=""; BLUE=""; GREEN=""; YELLOW=""
fi
say() { printf '  %s\n' "$1"; }
step() { printf '  %s•%s %s\n' "$BLUE" "$RESET" "$1"; }
note() { printf '  %s%s%s\n' "$DIM" "$1" "$RESET"; }
warn() { printf '  %s⚠ %s%s\n' "$YELLOW" "$1" "$RESET"; }
ok() { printf '  %s%s✓ %s%s\n' "$BOLD" "$GREEN" "$1" "$RESET"; }
open_url() {
  printf '  %s↗ opening%s %s\n' "$GREEN" "$RESET" "$1"
  {
    if command -v wslview >/dev/null 2>&1; then wslview "$1"; else explorer.exe "$1"; fi
  } >/dev/null 2>&1 || warn "couldn't open a browser, so visit it manually: $1"
}
pause() {
  printf '  %s%s%s ' "$DIM" "${1:-Press Enter to continue}" "$RESET"
  read -r _ || true
}
confirm() {
  local reply=""
  printf '  %s? %s [y/N] ' "$YELLOW" "$1"
  read -r reply || true
  [[ $reply =~ ^[Yy] ]]
}
ask() {
  local key="$1" prompt="$2" input
  printf '  %s%s%s ' "$BOLD" "$prompt" "$RESET"
  read -r input || true
  printf -v "$key" '%s' "$input"
}

# gh ships in the pinned toolchain (stage 6); prefer the out-link so this
# works outside a dev shell, falling back to any gh already on PATH.
_gh() {
  if [[ -x .devshell/bin/gh ]]; then
    .devshell/bin/gh "$@"
  elif command -v gh >/dev/null 2>&1; then
    gh "$@"
  else
    return 127
  fi
}

_is_linked() {
  git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' >/dev/null 2>&1
}

# ZIP downloads arrive with no history inside; start one so the folder can be
# connected. Nothing is sent anywhere — this only happens on this PC.
if [[ ! -d .git ]]; then
  git init >/dev/null
  ok "Started keeping a history of changes for this folder."
fi
if ! _gh --version >/dev/null 2>&1; then
  warn "The GitHub sign-in tool comes with the tools download (stage 6), which"
  warn "isn't done yet. Open this wizard again to finish that first."
  say "  Later: .devshell/bin/gh auth login --web"
  exit 1
fi
if _gh auth status >/dev/null 2>&1; then
  ok "This PC is already signed in to GitHub."
else
  say ""
  say "GitHub needs a one-time sign-in, so this PC is allowed to send and"
  say "receive the team's work."
  say ""
  if ! confirm "Do you already have a GitHub account?"; then
    open_url "https://github.com/signup"
    step "Create the account (a personal email is fine) and verify the email."
    pause "Press Enter once the account exists."
  fi
  say "Now the sign-in. A browser window opens — approve it there."
  say "If a question here mentions 'authenticate Git', answer yes to it."
  if _gh auth login --hostname github.com --web --git-protocol https; then
    ok "Signed in. From now on this PC can send and receive the project automatically."
  else
    warn "The sign-in didn't finish; open this wizard again any time to retry."
    exit 1
  fi
fi
if ! _gh auth status >/dev/null 2>&1; then
  exit 1
fi
# Which repository? Ask GitHub itself: the invitation the user accepted is
# what vouches for the address, so nothing is baked into this script and
# the user confirms the match before anything is wired up.
_repo_choices() {
  _gh api "user/repos?affiliation=collaborator,organization_member&per_page=100" \
    --jq '.[].full_name' 2>/dev/null
}
if ! git remote get-url origin >/dev/null 2>&1; then
  say ""
  say "Looking up the team's repository on your GitHub account..."
  _repos=$(_repo_choices || true)
  if [[ -z $_repos ]]; then
    say "GitHub doesn't show a team repository for your account yet. A private"
    say "repository stays invisible until you accept the team's invitation."
    open_url "https://github.com/notifications"
    step "Accept the repository invitation there (it also arrives by email)."
    pause "Press Enter once it's accepted (or if it already was)."
    _repos=$(_repo_choices || true)
  fi
  _chosen=""
  _count=$(printf '%s' "$_repos" | grep -c . || true)
  # GitHub's ZIP unzips to a folder named "<repository>-<branch>", and the
  # copy stage kept that name, so the folder still identifies the repository.
  _folder=$(basename "$PWD")
  _candidate=""
  if [[ $_count -eq 1 ]]; then
    _candidate=$_repos
  elif [[ $_count -gt 1 ]]; then
    while IFS= read -r _r; do
      _n=${_r#*/}
      if [[ $_folder == "$_n" || $_folder == "$_n"-* ]]; then
        _candidate=$_r
        break
      fi
    done <<<"$_repos"
  fi
  if [[ -n $_candidate ]]; then
    if confirm "Connect this folder to github.com/${_candidate}? (Check it matches your invitation.)"; then
      _chosen=$_candidate
    fi
  fi
  if [[ -z $_chosen && $_count -gt 1 ]]; then
    say "Your account can reach more than one repository. Which one is this project?"
    _i=0
    while IFS= read -r _r; do
      _i=$((_i + 1))
      say "  ${_i}) github.com/${_r}"
    done <<<"$_repos"
    ask REPO_PICK "Type its number (or press Enter to skip):"
    if [[ $REPO_PICK =~ ^[0-9]+$ && $REPO_PICK -ge 1 && $REPO_PICK -le $_count ]]; then
      _chosen=$(printf '%s\n' "$_repos" | sed -n "${REPO_PICK}p")
    fi
  fi
  if [[ -n $_chosen ]]; then
    git remote add origin "https://github.com/${_chosen}.git"
  else
    say "No problem — the address can be given directly instead."
    step "In the browser, open the repository page — the invitation email links to it."
    step "Click the green 'Code' button and copy the web address it shows (the one starting with https)."
    ask GIT_REMOTE_URL "Paste the repository address (or press Enter to skip):"
    GIT_REMOTE_URL=${GIT_REMOTE_URL%/}
    if [[ $GIT_REMOTE_URL =~ ^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(\.git)?$ ]]; then
      git remote add origin "$GIT_REMOTE_URL"
    elif [[ -n $GIT_REMOTE_URL ]]; then
      warn "That doesn't look like a GitHub repository address (it should look"
      warn "like https://github.com/team/project). Open this wizard again to retry."
    fi
  fi
fi
if ! git remote get-url origin >/dev/null 2>&1; then
  warn "This folder isn't connected to the team's repository yet. Open this"
  warn "wizard again to retry, or ask the person who invited you which"
  warn "repository it is."
  exit 1
fi
say ""
say "Connecting this folder to the team's repository..."
_fetched=0
if git fetch origin >/dev/null 2>&1; then
  _fetched=1
else
  say "The repository isn't reachable yet. A private repository stays invisible"
  say "until you accept the team's invitation."
  open_url "https://github.com/notifications"
  step "Accept the repository invitation there (it also arrives by email)."
  pause "Press Enter once it's accepted (or if it already was)."
  git fetch origin >/dev/null 2>&1 && _fetched=1
fi
if [[ $_fetched == 1 ]]; then
  _default_branch=$(git remote show origin 2>/dev/null | sed -n 's/.*HEAD branch: //p')
  [[ -z $_default_branch ]] && _default_branch=main
  if _is_linked; then
    ok "Connected — this folder already follows the team's shared history."
  else
    say "Linking this folder to the team's shared history. Your files stay as they are."
    # Adopt in place: point HEAD at the team's branch, then a mixed reset —
    # it moves the branch and index only and never touches working files.
    git symbolic-ref HEAD "refs/heads/${_default_branch}"
    git reset -q "origin/${_default_branch}"
    git branch --set-upstream-to="origin/${_default_branch}" "$_default_branch" >/dev/null 2>&1 || true
    if [[ -z $(git status --porcelain 2>/dev/null) ]]; then
      ok "Connected — this folder now matches the team's project exactly."
    else
      ok "Connected. A few files differ from the team's copy; the Claude app"
      say "can show you what's different before you share anything."
    fi
  fi
  note "(This wizard never sends anything to GitHub for you.)"
  note "(One optional extra didn't come in the ZIP — reference copies of other"
  note " projects, under .repos/. Claude can fetch them later if ever wanted.)"
else
  warn "Still couldn't reach the repository. Usual causes: the invitation isn't"
  warn "accepted yet, or the sign-in above didn't finish. Open this wizard again to retry."
  git remote remove origin 2>/dev/null || true
  exit 1
fi
exit 0
'@
  if ($script:UbuntuExit -ne 0) {
    $script:SKIPPED += 'GitHub access: double-click Setup.cmd again to finish the sign-in and connect the folder'
  }
}

finish
note 'For developers: day-to-day commands are pnpm check / test / lint / build, nix fmt, nix flake check.'
note 'AGENTS.md is the full technical reference.'
