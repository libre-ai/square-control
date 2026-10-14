# Security policy

Square Control is a local macOS window layout tool. It has no network service, no account,
no telemetry and no model; its isolation boundary is the macOS user account. It acts on other
applications' windows through the Accessibility API, under a per-user grant, and keeps a
state file private to that user.

## Supported versions

Square Control is not released, not distributed and not signed for third parties. Security
fixes target the default branch only; there is no release branch and no backport.

## Reporting a vulnerability

Do not put a suspected vulnerability, an exposed secret or exploit detail in a public issue
or pull request.

Report privately through GitHub private vulnerability reporting on this repository:

<https://github.com/libre-ai/square-control/security/advisories/new>

The fleet intake in `project-governance` reaches the same maintainer and may be used instead:

<https://github.com/libre-ai/project-governance/security/advisories/new>

Include the commit concerned, the macOS version and architecture, the impact, and a minimal
reproduction. Remove window titles, screenshots, machine paths and any personal data from
what you attach.

There is no security mailing address, and this policy promises no response deadline.

## Relevant findings

In scope, for example:

- a way for the tool to move, read or act on windows beyond the documented layout actions;
- the release binary importing a symbol outside its closed list, declaring a URL scheme,
  opening a network connection or carrying a machine path;
- the state file becoming readable by another user, or carrying window titles or other
  personal data;
- a crafted window geometry or state file that makes the core or the shell crash, hang or
  write outside its state file.

The Accessibility grant itself is a macOS permission the user gives: a report that only
restates what that grant allows any granted application to do is not a finding about
Square Control.
