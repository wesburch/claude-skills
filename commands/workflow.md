Run the task through `engineering-workflow`.

1. Read `~/.claude/skills/engineering-workflow/SKILL.md`.
2. Treat an initial `quick`, `standard`, `full`, or `auto` as a profile override;
   the remaining arguments are the task. Otherwise use the entire argument as
   the task and select a profile from its risk and dependencies.
3. Follow the entrypoint, including any existing project configuration. Load
   references only at the decision points it names. Do not preload every
   reference, spawn a fixed role roster, or require a knowledge artifact.

Report the chosen profile briefly, then complete the task. Finish with the actual
change, checks, review outcome when required, and remaining limitations. Advice
or audit requests remain advice or audit; invoking the command does not turn
them into implementation permission.

$ARGUMENTS
