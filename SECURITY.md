# Security Policy

Automate Scripts executes local commands, so security issues can affect user data.

## Reporting

Please report vulnerabilities privately before public disclosure. If no private contact is configured yet, open a GitHub security advisory in the repository.

## Scope

- Command execution safety
- Scheduler file generation
- Secret handling
- Path traversal or unintended file overwrite

## User guidance

- Do not schedule scripts you do not trust.
- Prefer explicit absolute script paths.
- Avoid storing secrets in job environment variables until Keychain integration is available.
