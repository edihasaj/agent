# End-to-end testing

Use Probeport for evidence-first app validation:

```bash
probeport run change --repo <repo>
probeport run explore --repo <repo> --url <url>
```

Use `change` for a scoped implementation and `explore` for broad product
coverage. Probeport routes through browsers, desktop/native gates, real
machines, evidence storage, and its dashboard.

For a generic Linux or CLI smoke test, prefer:

```bash
vmlab run @docker-first -- <command>
```

Escalate to Parallels or cloud only for Windows, macOS, GUI, architecture, or
other OS-specific behavior. If `@docker-first` is unavailable, use the cheapest
matching local surface and continue up the routing ladder.

Save repeatable run, test, and deployment procedures in the project's storage
home or runbooks rather than re-deriving them each time.
