#Requires -Version 5.1
<#
.SYNOPSIS
    Interactive setup for multiple Git accounts in VS Code on Windows.

.DESCRIPTION
    Automates the full setup described in howto-multiple-git-accounts-vscode.md:
    - Generates SSH key pairs for Personal GitHub, Work GitHub, and Azure DevOps
    - Starts the OpenSSH Authentication Agent and registers keys
    - Writes/merges ~/.ssh/config with host aliases
    - Creates per-account .gitconfig files
    - Patches ~/.gitconfig with conditional [includeIf] blocks
    - Creates recommended project folder structure
    - Prints public keys ready to paste into each platform

.NOTES
    Requires Git for Windows (provides ssh-keygen) or Windows OpenSSH feature.
    Run from PowerShell (not PS Core) for best compatibility, though PS 7+ works.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Helpers ─────────────────────────────────────────────────────────────────

function Write-Header([string]$text) {
    Write-Host "`n╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  $text" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
}

function Write-Step([string]$text) {
    Write-Host "`n▶  $text" -ForegroundColor Yellow
}

function Write-OK([string]$text) {
    Write-Host "  ✔  $text" -ForegroundColor Green
}

function Write-Info([string]$text) {
    Write-Host "  ℹ  $text" -ForegroundColor DarkCyan
}

function Write-Warn([string]$text) {
    Write-Host "  ⚠  $text" -ForegroundColor DarkYellow
}

function Prompt-Input([string]$prompt, [string]$default = '') {
    if ($default) {
        $display = "$prompt [$default]"
    } else {
        $display = $prompt
    }
    $val = Read-Host $display
    if (-not $val -and $default) { return $default }
    return $val
}

# Convert Windows path to Unix-style for Git config (forward slashes, trailing slash)
function To-GitPath([string]$path) {
    return ($path.Replace('\', '/').TrimEnd('/') + '/')
}

# ── Prerequisite check ───────────────────────────────────────────────────────

Write-Header "Multiple Git Accounts Setup"
Write-Info "This script sets up Personal GitHub, Work GitHub and Azure DevOps."

Write-Step "Checking prerequisites"

$sshKeygen = Get-Command ssh-keygen -ErrorAction SilentlyContinue
if (-not $sshKeygen) {
    Write-Host "`n  ✘  ssh-keygen not found." -ForegroundColor Red
    Write-Host "     Install 'Git for Windows' (https://git-scm.com) or enable the" -ForegroundColor Red
    Write-Host "     'OpenSSH Client' optional feature in Windows Settings." -ForegroundColor Red
    exit 1
}
Write-OK "ssh-keygen found at $($sshKeygen.Source)"

$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if (-not $gitCmd) {
    Write-Host "`n  ✘  git not found. Install Git for Windows first." -ForegroundColor Red
    exit 1
}
Write-OK "git found at $($gitCmd.Source)"

# ── Gather user input ─────────────────────────────────────────────────────────

Write-Header "Account Information"

Write-Host "`n--- Personal GitHub ---" -ForegroundColor Magenta
Write-Info "Use your GitHub no-reply address to avoid push rejections (GH007)."
Write-Info "Find it at: https://github.com/settings/emails  (format: {ID}+username@users.noreply.github.com)"
$personalName  = Prompt-Input "  Full name (commits)"
$personalEmail = Prompt-Input "  Email address"

Write-Host "`n--- Work GitHub ---" -ForegroundColor Magenta
Write-Info "If this is a github.com account, use the no-reply address from https://github.com/settings/emails"
$workName      = Prompt-Input "  Full name (commits)"
$workEmail     = Prompt-Input "  Email address"
$workHostname  = Prompt-Input "  GitHub hostname (github.com or your GHE domain)" "github.com"

Write-Host "`n--- Azure DevOps ---" -ForegroundColor Magenta
$azureName     = Prompt-Input "  Full name (commits)"
$azureEmail    = Prompt-Input "  Email address"

Write-Host "`n--- Work-Public GitHub (bertrandt-public org) ---" -ForegroundColor Magenta
Write-Info "Separate GitHub user account for the bertrandt-public organisation."
Write-Info "Uses its own SSH key (id_ed25519_work_public)."
$workPublicName  = Prompt-Input "  Full name (commits)"
$workPublicEmail = Prompt-Input "  Email address"

Write-Host "`n--- Project Folders ---" -ForegroundColor Magenta
Write-Info "Git uses folder paths to decide which identity to use."
$defaultProjects = "$env:USERPROFILE\projects"
$personalDir     = Prompt-Input "  Personal repos root folder"          "$defaultProjects\personal"
$workDir         = Prompt-Input "  Work repos root folder"              "$defaultProjects\work"
$azureDir        = Prompt-Input "  Azure repos root folder"             "$defaultProjects\azure"
$workPublicDir   = Prompt-Input "  Work-public repos root folder"       "$defaultProjects\work-public"

# ── SSH key paths ─────────────────────────────────────────────────────────────

$sshDir          = "$env:USERPROFILE\.ssh"
$keyPersonal     = "$sshDir\id_ed25519_personal"
$keyWork         = "$sshDir\id_ed25519_work"
$keyAzure        = "$sshDir\id_ed25519_azure"
$keyWorkPublic   = "$sshDir\id_ed25519_work_public"

# ── Step 1: Create .ssh directory ─────────────────────────────────────────────

Write-Header "Step 1 – SSH Keys"

if (-not (Test-Path $sshDir)) {
    New-Item -ItemType Directory -Path $sshDir | Out-Null
    Write-OK "Created $sshDir"
}

function New-SshKey([string]$keyFile, [string]$email, [string]$label) {
    if (Test-Path $keyFile) {
        Write-Warn "$label key already exists at $keyFile"
        $overwrite = Read-Host "  Regenerate it? This replaces the existing key (y/N)"
        if ($overwrite -notmatch '^[Yy]') {
            Write-Info "Keeping existing $label key."
            return
        }
        Remove-Item $keyFile -Force
        Remove-Item "$keyFile.pub" -Force -ErrorAction SilentlyContinue
    }
    Write-Step "Generating $label key (no passphrase)"
    ssh-keygen -t ed25519 -C $email -f $keyFile -N ""
    Write-OK "$label key created"
}

New-SshKey $keyPersonal    $personalEmail    "Personal GitHub"
New-SshKey $keyWork        $workEmail        "Work GitHub"
New-SshKey $keyAzure       $azureEmail       "Azure DevOps"
New-SshKey $keyWorkPublic  $workPublicEmail  "Work-Public GitHub (bertrandt-public)"

# ── Step 2: SSH Agent ─────────────────────────────────────────────────────────

Write-Header "Step 2 – SSH Agent"

try {
    $agentService = Get-Service -Name 'ssh-agent' -ErrorAction SilentlyContinue
    if ($agentService) {
        if ($agentService.Status -ne 'Running') {
            Write-Step "Starting OpenSSH Authentication Agent service"
            Set-Service -Name 'ssh-agent' -StartupType Automatic
            Start-Service 'ssh-agent'
            Write-OK "ssh-agent service started"
        } else {
            Write-OK "ssh-agent service is already running"
        }
        ssh-add $keyPersonal   2>$null
        ssh-add $keyWork        2>$null
        ssh-add $keyAzure       2>$null
        ssh-add $keyWorkPublic  2>$null
        Write-OK "Keys added to ssh-agent"
    } else {
        Write-Warn "Windows OpenSSH ssh-agent service not found."
        Write-Info "If you use Git Bash, run: eval `"`$(ssh-agent -s)`" && ssh-add ..."
        Write-Info "Keys will still work if you start the agent manually before use."
    }
} catch {
    Write-Warn "Could not configure ssh-agent automatically: $_"
    Write-Info "You may need to run this script as Administrator to manage services."
}

# ── Step 3: SSH Config ────────────────────────────────────────────────────────

Write-Header "Step 3 – SSH Config (~/.ssh/config)"

$sshConfigPath = "$sshDir\config"

$newBlock = @"

# ── Personal GitHub (added by Setup-MultipleGitAccounts.ps1) ──
# Uses ssh.github.com:443 to work on networks where port 22 is blocked.
Host github-personal
  HostName ssh.github.com
  Port 443
  User git
  IdentityFile ~/.ssh/id_ed25519_personal
  IdentitiesOnly yes

# ── Work GitHub / GHE ──
Host github-work
  HostName ssh.github.com
  Port 443
  User git
  IdentityFile ~/.ssh/id_ed25519_work
  IdentitiesOnly yes

# ── Work-Public GitHub (bertrandt-public org, separate user) ──
Host github-work-public
  HostName ssh.github.com
  Port 443
  User git
  IdentityFile ~/.ssh/id_ed25519_work_public
  IdentitiesOnly yes

# ── Azure DevOps ──
Host azure-devops
  HostName vs-ssh.visualstudio.com
  User git
  IdentityFile ~/.ssh/id_ed25519_azure
  IdentitiesOnly yes
"@

$existingConfig = if (Test-Path $sshConfigPath) { Get-Content $sshConfigPath -Raw } else { '' }

if ($existingConfig -match 'github-personal' -or $existingConfig -match 'github-work' -or $existingConfig -match 'azure-devops' -or $existingConfig -match 'github-work-public') {
    Write-Warn "Host aliases already present in $sshConfigPath – skipping SSH config update."
    Write-Info "Review the file manually if needed: $sshConfigPath"
} else {
    Add-Content -Path $sshConfigPath -Value $newBlock -Encoding UTF8
    Write-OK "SSH host aliases appended to $sshConfigPath"
}

# ── Step 4: Per-account .gitconfig files ─────────────────────────────────────

Write-Header "Step 4 – Per-account .gitconfig files"

$gitconfigPersonal   = "$env:USERPROFILE\.gitconfig.personal"
$gitconfigWork       = "$env:USERPROFILE\.gitconfig.work"
$gitconfigAzure      = "$env:USERPROFILE\.gitconfig.azure"
$gitconfigWorkPublic = "$env:USERPROFILE\.gitconfig.work-public"

function Write-GitConfig([string]$path, [string]$name, [string]$email, [string]$label) {
    if (Test-Path $path) {
        Write-Warn "$label config already exists at $path – skipping."
    } else {
        @"
[user]
    name  = $name
    email = $email
"@ | Set-Content -Path $path -Encoding UTF8
        Write-OK "$label config written to $path"
    }
}

Write-GitConfig $gitconfigPersonal   $personalName    $personalEmail    "Personal"
Write-GitConfig $gitconfigWork       $workName        $workEmail        "Work"
Write-GitConfig $gitconfigAzure      $azureName       $azureEmail       "Azure"
Write-GitConfig $gitconfigWorkPublic $workPublicName  $workPublicEmail  "Work-Public"

# ── Step 5: Patch global ~/.gitconfig ────────────────────────────────────────

Write-Header "Step 5 – Global ~/.gitconfig (conditional includes)"

$globalGitConfig = "$env:USERPROFILE\.gitconfig"

$personalGitPath   = To-GitPath $personalDir
$workGitPath       = To-GitPath $workDir
$azureGitPath      = To-GitPath $azureDir
$workPublicGitPath = To-GitPath $workPublicDir

$includeBlock = @"

# ── Per-directory identity (added by Setup-MultipleGitAccounts.ps1) ──
[includeIf "gitdir:$personalGitPath"]
    path = ~/.gitconfig.personal

[includeIf "gitdir:$workGitPath"]
    path = ~/.gitconfig.work

[includeIf "gitdir:$azureGitPath"]
    path = ~/.gitconfig.azure

[includeIf "gitdir:$workPublicGitPath"]
    path = ~/.gitconfig.work-public
"@

$existingGlobal = if (Test-Path $globalGitConfig) { Get-Content $globalGitConfig -Raw } else { '' }

if ($existingGlobal -match 'gitconfig\.personal' -or $existingGlobal -match 'gitconfig\.work') {
    Write-Warn "includeIf blocks already present in $globalGitConfig – skipping."
    Write-Info "Review manually: $globalGitConfig"
} else {
    # Ensure a default [user] block exists
    if ($existingGlobal -notmatch '\[user\]') {
        $defaultUser = @"
[user]
    name  = $personalName
    email = $personalEmail

"@
        $defaultUser | Set-Content -Path $globalGitConfig -Encoding UTF8
        $existingGlobal = $defaultUser
        Write-OK "Added default [user] block to ~/.gitconfig"
    }
    Add-Content -Path $globalGitConfig -Value $includeBlock -Encoding UTF8
    Write-OK "Conditional includes appended to $globalGitConfig"
}

# ── Step 6: Create project directories ───────────────────────────────────────

Write-Header "Step 6 – Project Directories"

foreach ($dir in @($personalDir, $workDir, $azureDir, $workPublicDir)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-OK "Created $dir"
    } else {
        Write-Info "$dir already exists"
    }
}

# ── Step 7: Public key summary ────────────────────────────────────────────────

Write-Header "Step 7 – Add Public Keys to Each Platform"

Write-Host "`nCopy each public key below and add it in the platform's SSH key settings.`n" -ForegroundColor White

foreach ($item in @(
    @{ Label = 'Personal GitHub   → https://github.com/settings/ssh/new';               Key = "$keyPersonal.pub" },
    @{ Label = 'Work GitHub       → https://github.com/settings/ssh/new (or GHE)';      Key = "$keyWork.pub" },
    @{ Label = 'Work-Public GitHub → https://github.com/settings/ssh/new (btag account)'; Key = "$keyWorkPublic.pub" },
    @{ Label = 'Azure DevOps      → https://dev.azure.com → User Settings → SSH';     Key = "$keyAzure.pub" }
)) {
    Write-Host "  $($item.Label)" -ForegroundColor Cyan
    if (Test-Path $item.Key) {
        $pubKey = Get-Content $item.Key
        Write-Host "  $pubKey`n" -ForegroundColor White
    } else {
        Write-Warn "Key file not found: $($item.Key)"
    }
}

# ── Step 8: Quick-reference ───────────────────────────────────────────────────

Write-Header "Quick Reference – Cloning"

Write-Host @"
  Personal GitHub:
    git clone git@github-personal:USERNAME/repo.git

  Work GitHub / GHE:
    git clone git@github-work:ORG/repo.git

  Work-Public GitHub (bertrandt-public org):
    git clone git@github-work-public:bertrandt-public/repo.git

  Azure DevOps:
    git clone git@azure-devops:ORG/PROJECT/_git/REPO

  Switch an existing HTTPS remote to SSH:
    git remote set-url origin git@github-personal:USERNAME/repo.git

  Test connections:
    ssh -T git@github-personal
    ssh -T git@github-work
    ssh -T git@github-work-public
    ssh -T git@azure-devops

  IMPORTANT: Always clone/push via the SSH alias above.
  Never use the https:// URL from GitHub - it bypasses SSH
  and triggers the credential manager popup.
"@ -ForegroundColor White

Write-Host "`n  ✔  Setup complete!`n" -ForegroundColor Green
