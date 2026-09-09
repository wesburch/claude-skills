# Model registry

Preference snapshot: 2026-09-09. These are starting candidates, not a benchmark
or a cross-provider price ranking. Availability depends on the actual host,
account, runtime, and tool surface. Do not refresh the web on every dispatch.

| Band | OpenAI candidates | Claude candidates |
|---|---|---|
| Small/fast | `gpt-5.6-luna` | An available Haiku model with suitable tools |
| Balanced | `gpt-5.6-terra`; `gpt-5.6-sol` for more demanding work | An available Sonnet model |
| Strong | `gpt-6-astra`; `gpt-5.6-sol` when context/access favors it | An available Opus or Fable model |

Resolve exact Claude IDs and supported reasoning controls from the runtime;
family names are not executable IDs. Prefer low effort for explicit repetitive
work, medium for bounded implementation, high for difficult reasoning/review,
where supported. Higher efforts need a task-specific reason, not a profile rule.

Before first use in a runtime, distinguish:

- Listed: selector/tool metadata or CLI exposes the model and effort.
- Accessible: local account/status evidence indicates access, when available.
- Observed: an actual completed invocation reports the model used.

Choose among exposed capabilities without launching paid probes. Record the
requested model/effort and observed identity when returned; label unobserved
identity instead of inventing it. A configured model is not proof it ran.
If an explicit user choice is unavailable, report that limitation and offer a
candidate; do not silently substitute. For agent-chosen defaults, use an available
candidate in the needed band and disclose a material fallback. If none fits,
keep useful work local and report the unmet capability/review requirement.

Prefer existing context and proven task fit over provider stereotypes. Native
model/effort selection should be used when available. A skill cannot make an
unsupported runtime selector work or switch the parent model by spawning a child.

Update preferences after representative outcomes or meaningful availability
changes. Consult current official sources for price or comparative claims:
[OpenAI models](https://developers.openai.com/api/docs/models),
[Claude models](https://platform.claude.com/docs/en/about-claude/models/overview).
Do not compare subscription consumption using API token prices.
