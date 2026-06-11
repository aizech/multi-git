# Using Multiple Git Accounts in VS Code

You can use multiple accounts for GitHub, GitHub Enterprise, and Azure DevOps in VS Code by combining Git conditional includes for identity and SSH host aliases for authentication. This keeps commit author details and login credentials separated per account.

## 1. Create separate SSH keys

```bash
# Personal GitHub
ssh-keygen -t ed25519 -C "personal@email.com" -f ~/.ssh/id_ed25519_personal

# Work GitHub / GitHub Enterprise
ssh-keygen -t ed25519 -C "work@company.com" -f ~/.ssh/id_ed25519_work

# Azure DevOps
ssh-keygen -t ed25519 -C "azure@email.com" -f ~/.ssh/id_ed25519_azure
```

Add the keys to your SSH agent:

**Linux / macOS:**
```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519_personal
ssh-add ~/.ssh/id_ed25519_work
ssh-add ~/.ssh/id_ed25519_azure
```

**Windows (PowerShell as Administrator):**
```powershell
Set-Service -Name ssh-agent -StartupType Automatic
Start-Service ssh-agent
ssh-add $env:USERPROFILE\.ssh\id_ed25519_personal
ssh-add $env:USERPROFILE\.ssh\id_ed25519_work
ssh-add $env:USERPROFILE\.ssh\id_ed25519_azure
```

> ⚠️ On Windows the `ssh-agent` service requires **Administrator** rights to enable. Run the PowerShell commands above in an elevated terminal once; afterwards the agent starts automatically at login.

Add each public key to the corresponding account in its SSH key settings.

## 2. Configure SSH host aliases

Create or edit `~/.ssh/config` (on Windows: `%USERPROFILE%\.ssh\config`):

```
# Personal GitHub
Host github-personal
  HostName ssh.github.com
  Port 443
  User git
  IdentityFile ~/.ssh/id_ed25519_personal
  IdentitiesOnly yes

# Work GitHub / GitHub Enterprise
Host github-work
  HostName ssh.github.com
  Port 443
  User git
  IdentityFile ~/.ssh/id_ed25519_work
  IdentitiesOnly yes

# Azure DevOps
Host azure-devops
  HostName vs-ssh.visualstudio.com
  User git
  IdentityFile ~/.ssh/id_ed25519_azure
  IdentitiesOnly yes
```

> ⚠️ GitHub SSH uses `ssh.github.com` on **port 443** instead of `github.com` on port 22. Port 22 is frequently blocked on corporate or restricted networks; port 443 (HTTPS) is almost always open. Azure DevOps does not offer this fallback and uses port 22 only.

Test the connections:

```bash
ssh -T git@github-personal
ssh -T git@github-work
ssh -T git@azure-devops
```

A successful GitHub response looks like: `Hi username! You've successfully authenticated...`

## 3. Set Git identity per folder

Create separate Git config files:

**`~/.gitconfig.personal`**

```ini
[user]
  name = Your Personal Name
  email = {ID}+username@users.noreply.github.com
```

> ⚠️ **GitHub email privacy (GH007):** GitHub blocks pushes that expose a private email address. Use your GitHub no-reply address instead of your real email. Find it at [github.com/settings/emails](https://github.com/settings/emails) — it looks like `12345678+username@users.noreply.github.com`. Enable "Keep my email address private" on that page to enforce this.

**`~/.gitconfig.work`**

```ini
[user]
  name = Your Work Name
  email = work@company.com
```

Then add conditional includes to your global Git config (`~/.gitconfig`):

```ini
[user]
  name = Your Default Name
  email = {ID}+username@users.noreply.github.com

[includeIf "gitdir:~/projects/personal/"]
  path = ~/.gitconfig.personal

[includeIf "gitdir:~/projects/work/"]
  path = ~/.gitconfig.work

[includeIf "gitdir:~/projects/azure/"]
  path = ~/.gitconfig.azure
```

> On Windows use forward slashes in `gitdir` paths and always include the trailing slash, e.g. `gitdir:C:/Users/you/projects/work/`.

Keep your repositories in those matching folders so Git applies the right identity automatically.

## 4. Clone repositories with the right host alias

Always clone using the SSH host alias — **never** use the `https://` URL from GitHub, as that bypasses SSH and triggers the credential manager.

```bash
# Personal GitHub
git clone git@github-personal:username/personal-repo.git

# Work GitHub / GitHub Enterprise
git clone git@github-work:company/work-repo.git

# Azure DevOps
git clone git@azure-devops:company/project/_git/repo.git
```

For an **existing** repository cloned over HTTPS, switch it to SSH:

```bash
# Check current remote
git remote -v

# Switch to SSH
git remote set-url origin git@github-personal:username/repo.git
```

## 5. VS Code notes

VS Code uses the Git and SSH configuration from your system, so once the SSH config and Git identity files are in place, Git operations in the VS Code terminal work automatically. The VS Code Accounts sign-in and Git auth are separate, so you may still sign in to GitHub in the editor for extensions or sync without affecting Git commit identity.

## 6. Optional HTTPS approach

If you prefer HTTPS, Git Credential Manager can separate credentials by namespace or path. On Windows, this is useful when you want multiple accounts for the same provider without SSH keys.

### Cleaning up stale credential helpers (Windows)

Over time `~/.gitconfig` can accumulate duplicate or outdated `credential.helper` entries (e.g. the legacy `manager-core` binary that was renamed to `manager`). Check for duplicates:

```powershell
git config --list --show-origin | Select-String credential
```

The `[credential]` block in `~/.gitconfig` should contain a single helper entry:

```ini
[credential]
    helper = manager
    githubAuthModes = devicecode
```

Remove any lines referencing `manager-core`, the empty `helper =`, or the absolute path to `git-credential-manager.exe` — they are redundant and cause the warning `git: 'credential-manager-core' is not a git command`.

## 7. Recommended layout

```text
~/projects/
  personal/
  work/
  azure/
```

That simple folder split makes `includeIf` rules easy to maintain and reduces the chance of committing with the wrong identity.

## 8. Automated setup (Windows)

`Setup-MultipleGitAccounts.ps1` (in this repo) automates every step above interactively. Run it once in PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\Setup-MultipleGitAccounts.ps1
```

Then run the ssh-agent block from step 1 in an **elevated** PowerShell to finish. All operations are idempotent — safe to re-run.

## Quick reference

| Service | SSH Host Alias | Example remote |
|---|---|---|
| Personal GitHub | `github-personal` | `git@github-personal:user/repo.git` |
| Work GitHub / GHE | `github-work` | `git@github-work:org/repo.git` |
| Azure DevOps | `azure-devops` | `git@azure-devops:org/project/_git/repo.git` |