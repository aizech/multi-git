# multi-git

Set up and manage multiple Git identities (Personal GitHub, Work GitHub, Azure DevOps) on a single Windows machine using SSH host aliases and Git conditional includes.

## Contents

| File | Purpose |
|---|---|
| [`howto-multiple-git-accounts-vscode.md`](./howto-multiple-git-accounts-vscode.md) | Step-by-step manual guide |
| [`Setup-MultipleGitAccounts.ps1`](./Setup-MultipleGitAccounts.ps1) | Interactive PowerShell script that automates the full setup |

## Quick start

**Option A — automated (recommended):**

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\Setup-MultipleGitAccounts.ps1
```

Then run the ssh-agent block in an **elevated** PowerShell once to register the keys with the Windows OpenSSH service.

**Option B — manual:**

Follow the steps in [`howto-multiple-git-accounts-vscode.md`](./howto-multiple-git-accounts-vscode.md).

## How it works

Git picks the right identity based on which folder a repo lives in:

```
~/projects/
  personal/     →  ~/.gitconfig.personal      (GitHub no-reply email, aizech)
  work/         →  ~/.gitconfig.work          (work email)
  azure/        →  ~/.gitconfig.azure         (Azure DevOps email)
  btag-public/  →  ~/.gitconfig.btag-public   (GitHub no-reply email, aizech — reuses personal key)
```

SSH host aliases (`github-personal`, `github-work`, `github-btag-public`, `azure-devops`) ensure the correct key is used for each remote. Both GitHub aliases route through `ssh.github.com:443` to work on networks where port 22 is blocked.

> **Always use the SSH alias for remotes** — both when cloning (`git clone git@github-personal:user/repo.git`) and when adding a remote to a new repo (`git remote add origin git@github-personal:user/repo.git`). The `https://` URL GitHub shows by default bypasses SSH entirely and triggers the credential manager popup.

## Requirements

- Windows 10/11
- [Git for Windows](https://git-scm.com) (provides `ssh-keygen` and `ssh-add`)
- PowerShell 5.1 or later

## Key gotcha — GitHub email privacy

GitHub rejects pushes that expose a private email address (`GH007` error). Use your GitHub no-reply address in any GitHub-facing `.gitconfig`:

```
{ID}+username@users.noreply.github.com
```

Find yours at [github.com/settings/emails](https://github.com/settings/emails).

## Author

**Bernhard Zechmann** — [github.com/aizech](https://github.com/aizech)
