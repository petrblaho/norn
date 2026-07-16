---
name: gh
description: Pluggable skill for GitHub CLI (gh) to interact with repositories, PRs, issues, and releases.
triggers:
  - gh
  - github
  - pull request
  - merge request
  - pull-request
  - issues
  - issue
  - gist
invocable: true
argument_hint: '[command] [args...]'
---

# /gh - GitHub CLI Command

Pluggable skill for interacting with GitHub repositories, pull requests, issues, gists, and releases via the standard GitHub CLI (`gh`).

## Quick Reference

| Command | Action | Description |
|---------|--------|-------------|
| `gh pr list` | List Pull Requests | Lists pull requests in the current repository |
| `gh pr view [number]` | View Pull Request | Shows the description and comments of a PR |
| `gh pr create` | Create Pull Request | Creates a new PR in the current repository |
| `gh pr diff` | View PR Diff | Shows the code changes for a pull request |
| `gh pr merge` | Merge Pull Request | Merges a pull request into the target branch |
| `gh pr checkout` | Checkout PR | Checks out a pull request branch locally |
| `gh issue list` | List Issues | Lists issues in the current repository |
| `gh issue view [number]` | View Issue | Shows details of a specific issue |
| `gh issue create` | Create Issue | Creates a new issue |
| `gh issue comment` | Comment on Issue | Adds a comment to an issue or PR |
| `gh repo view [repo]` | View Repository | Shows repository README and description |
| `gh repo clone [repo]` | Clone Repository | Clones a repository locally |
| `gh repo fork [repo]` | Fork Repository | Forks a repository to your account |
| `gh run list` | List Workflow Runs | Lists recent GitHub Actions runs |
| `gh run view [run_id]` | View Workflow Run | Shows details of a workflow run |
| `gh search issues [query]` | Search Issues/PRs | Searches across GitHub issues and PRs |

## Common Workflows

### Listing Pull Requests
```bash
gh pr list --state open --limit 10
```

### Viewing PR Details
```bash
gh pr view 42
```

### Checking out a Pull Request branch locally
```bash
gh pr checkout 42
```

### Creating a Pull Request interactively
```bash
gh pr create --title "feat: add gh skill" --body "Implements pluggable GitHub CLI skill" --draft
```

### Commenting on a Pull Request or Issue
```bash
gh pr comment 42 --body "LGTM! Approved."
```

### Checking Workflow/CI Status
```bash
gh run list --limit 5
gh run watch [run_id]
```

## Error Handling & Authentication

- **Not Authenticated:** If you get an authentication error, please run `gh auth login` or configure `GITHUB_TOKEN` in your environment.
- **Not a Git Repository:** Most `gh` commands require running inside a valid Git repository clone with a configured `origin` remote.
- **Repository Missing:** If not in a repository, you can specify target repos via `-R [owner]/[repo]`.
