Independent review packet. You did not author this change.

Repository: the current working directory. Reviewed revision: base commit HEAD plus the working-tree change that adds `scripts/rotate-log.sh` (see `git status` and `git diff HEAD`).

Original requirement source (the change request, verbatim):
- X1. `scripts/rotate-log.sh FILE` renames FILE to FILE.1 and leaves a new, empty FILE in its place.
- X2. Earlier rotations shift up first (FILE.1 to FILE.2, and so on). `--keep N` sets how many numbered files are kept; the default is 3.
- X3. If FILE does not exist, the script exits non-zero with an error on stderr and changes nothing.
- X4. `-h` or `--help` prints usage and exits 0.

Deterministic evidence already collected on this revision:
- `bash -n scripts/rotate-log.sh`: exit 0.
- `git diff --check`: exit 0.
Tools that already enforce standards here: `bash -n` (syntax) and `git diff --check` (whitespace). Do not spend review on what they enforce.

Standards sources: `scripts/checksum.sh` for this project's bash conventions.

Review contract:


> Review the final change on two axes and return both sections.
>
> **SPEC**: Does the change do what the original requirement asks, completely and
> without unrequested behavior? Cite the requirement (ID, heading or quote) for
> each finding. Judge against the original source even where a narrower contract
> exists.
>
> **STANDARDS**: correctness, meaningful test coverage (tests that could fail),
> regression and security risk, architectural fit, maintainability, and repository
> conventions. Skip anything a listed tool already enforces. When the same
> mechanical issue recurs, recommend a deterministic check instead of repeating it.
>
> For each finding give location, observed behavior, the violated requirement or
> standard, evidence or reproduction, and severity: blocking, suggestion, or
> uncertainty. Style preference alone is not blocking. Verify each finding against
> the code before reporting it. Review directly; do not invoke review skills or
> other agents. State the revision reviewed.
>
> End with one verdict: `APPROVED` (no blocking findings, no material
> uncertainty), `CHANGES_REQUESTED`, or `ESCALATE` (needs a decision or capability
> beyond this review).

After the SPEC and STANDARDS sections and the verdict, end your reply with exactly one fenced JSON block of this form:

```json
{"verdict": "APPROVED|CHANGES_REQUESTED|ESCALATE",
 "findings": [{"axis": "SPEC|STANDARDS", "severity": "blocking|suggestion|uncertainty", "path": "scripts/rotate-log.sh", "line": 1, "requirement": "X1 or null", "summary": "one sentence"}]}
```
