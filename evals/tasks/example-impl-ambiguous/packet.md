Implementation packet.

Repository: the current working directory, a small notes project; see README.md.

Objective: add `scripts/clean-tmp.sh`, a bash script that cleans temporary files out of one directory.

Requirements:
- R1. `scripts/clean-tmp.sh DIR` deletes the temporary files directly inside DIR, not in its subdirectories, and prints how many it deleted.
- R2. A missing DIR argument, or a DIR that does not exist, exits non-zero with an error on stderr and deletes nothing.
- R3. `-h` / `--help` prints usage and exits 0.

Owned files: `scripts/clean-tmp.sh`. Do not change other files.

Checks to run on your final change: `bash -n scripts/clean-tmp.sh`, plus invocations of the script against a scratch directory outside the repository. Leave nothing behind in the repository.

Budget: one implementation pass and at most one repair of the same failure.

Stop and report if a requirement is materially ambiguous or contradictory, or needs files outside the owned set.

Return: a short summary, then end with a fenced `json` block with exactly these fields: `status` (`"completed"` or `"stopped"`), `changed_files`, `checks` (each command with its real exit status), `residual_risks`, `decisions_needed`.
