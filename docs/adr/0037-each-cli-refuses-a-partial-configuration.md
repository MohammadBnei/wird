# 37. Each CLI refuses a partial configuration

Date: 2026-10-28. Status: accepted. Amends ADR 0036.

## Context

ADR 0036 gave the three services one `Config` each and left the six command-line tools (`etl`, `ingest`, `rootcheck`, `rootdraft`, `senseseed`, `jidhrcorpus`) for later. They are run by hand on a developer's machine and are never in an image ([Dockerfile](../../Dockerfile), `.claude/spec.md`). Each parsed its flags in `main`, or in a `parseConfig` beside it, and checked what it was given late or not at all:

- `senseseed` and `jidhrcorpus` fell back to `postgres://wird:wird@localhost:5432/wird` when `DATABASE_URL` was unset. A production seed that forgot the variable, with a compose Postgres running, replaced the local senses and printed a version as if it had landed.
- `ingest` parsed `-suras` only after the morphology check and two downloads. A negative `-retries` made no attempt at all and gave up "after 0 attempts".
- `rootdraft` looked for its token only after reading the prompt, the corpus and the log. `-workers 0` blocked every worker forever, and a negative count panicked.
- The env ban (`server/env_test.go`) still let three `main.go` files read the environment.

## Decision

- Each tool has `config.go` with an exported `Config`, `loadConfig(fs, args[, getenv])` and `fromProcess()`. The three that read the environment take `getenv`; `etl`, `ingest` and `rootcheck` read none and do not. `rootdraft` also takes the `hf auth token` lookup as a function, so the exec lives in `config.go` too.
- `loadConfig` checks everything once, before any file or network is touched, and reports every problem together with `errors.Join`. The tool prints `config refused:` and exits 1. A bad flag still exits 2, and `-h` exits 0.
- `DATABASE_URL` is required by `senseseed` and `jidhrcorpus` unless `WIRD_DEV=1`, which names the local compose database, the same switch ADR 0036 gives the services. `senseseed -dry` touches no database and needs neither. `WIRD_DEV` set to anything but `1` is refused.
- `senseseed` prints the database and host it is about to replace before it writes, so a `WIRD_DEV=1` left exported in a shell cannot send a seed to the local database in silence.
- `rootdraft` refuses a run with no token, and `-workers` below 1, unless `-dry`, which calls nothing and runs no worker.
- `ingest` refuses a bad `-suras` and a negative `-retries` at start. The `-suras` refusal still quotes what was given: a sura list is not a secret, and it is the useful part of the message.
- Every flag, with its effective default, and every variable are in a table under `## Configuration` in `docs/architecture/pipelines.md`. Each tool's `TestConfigDocumented` holds its table to its flags and to the variables `loadConfig` reads, through `server/internal/configdoc`.
- No `main.go` reads the environment any more. The env ban allows only a `config.go` per binary, and `internal/testenv`.

## Alternatives

- **Keep the localhost fallback for the CLIs, since they only run on a laptop.** The laptop is exactly where a production `DATABASE_URL` is pasted, and where forgetting it hits a running compose database. The fallback is what made that mistake silent.
- **A `-dev` flag instead of `WIRD_DEV`.** The tools do have flag sets, but `WIRD_DEV=1` is already the local switch every service reads, and one name is easier to remember than two.
- **Refuse `-workers` below 1 under `-dry` too.** A dry run never starts a worker and works today with any value; refusing it would break a working command for no gain.
- **Reuse the services' `envVars` list in each CLI.** The doc table and the reads that `loadConfig` makes are already the two sides of the check; a third list would be one more place to forget.

## Consequences

- A local `senseseed` or `jidhrcorpus` run needs `WIRD_DEV=1` (or `DATABASE_URL`). The getting-started guide, the rootd README and the agent context say so.
- `rootdraft` and `ingest` say what is wrong before they do any work, so a mistyped run costs nothing.
- A new flag or variable goes into `config.go` and the tool's table in the same PR, or `TestConfigDocumented` fails. Variables the libraries read (pgx's `PG*`, langchaingo's `OPENAI_*`, Go's proxy variables) are named beside the tables, not in them.

## Reversibility

Cheap: restoring the localhost fallback is one line in each `databaseURL`. The signal to undo it would be a workflow that runs these tools unattended against a local database without being able to set `WIRD_DEV=1`; none does.
