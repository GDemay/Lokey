# Lokey agent handoff

Paste this into a new chat and add the task at the end:

Work in /Users/guillaume/Lokey.

Read AGENTS.md, store/STATUS.md, and store/CLI.md before acting. Treat STATUS.md as a past record; check Apple's live state.

Use the saved CLI and Keychain setup. Reuse the existing Lokey app, API profile, and signing identity. Keep all Apple actions scoped to Lokey.

First check TestFlight status and App Store readiness. Then complete the change I request, test it, and verify the result with Apple. Use the browser only for steps the API cannot do.

Keep manual release. Do not submit for public review, release the app, or invite testers unless I ask. Never print or commit secrets.

If you change the setup or app, update store/STATUS.md and push the changes to the current personal-repo branch. Report what you verified and what still needs a user action.

My task: [describe the change or check here]

## Read-only starting checks

Run these from the repo root. They do not change Apple or GitHub. Local reports
are written under ignored `build/store/`.

```sh
python3 scripts/app-store.py check
python3 scripts/app-store.py status
python3 scripts/app-store.py plan
python3 scripts/app-store.py ready
python3 scripts/app-store.py screenshots-check --locale en-US
python3 scripts/app-store.py screenshots-check --locale fr-FR
```

`ready` needs the local release IPA. Pass `--ipa PATH` if it is elsewhere. A missing
IPA is a blocker for the full check. The public API cannot prove privacy answers
are published or that every account agreement is current. Report those limits.

The saved access is local to this Mac. A clone on a new Mac does not carry its
API key, signing private key, or installed profiles.

## Blind test

On November 2, 2026, an agent with no prior chat history found the setup from the
repo instructions. It used the saved API profile, verified live TestFlight and
store state, checked both screenshot sets, and signed a disposable local binary
with the saved distribution key. It made no Apple or GitHub changes.

It did not run a fresh archive, export, upload, or iPhone test. It did not check
live privacy publication or agreements. Local evidence is in
`build/blind-check/report.md` and `build/blind-check/commands.md`.
