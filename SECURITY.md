# Security Policy

## Reporting a vulnerability

Please report suspected vulnerabilities privately via GitHub's
[private security advisories](https://github.com/davidteren/hotwire-codex-skills/security/advisories/new)
rather than opening a public issue.

Include what you found, how to reproduce it, and the impact you expect. You'll
get an acknowledgement, and a fix or mitigation will be worked out from there.

## Scope

This project ships **skills, templates, and read-only checker scripts** — it
does not run a service or handle user data. The most relevant concerns are the
checker scripts (`skills/*/scripts/`) and anything they execute against a target
app. The checkers are heuristic text scanners and are documented as a gate, not
a proof; a clean run does not guarantee an app is secure.
