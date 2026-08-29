# Significance filter

Most tasks produce no durable knowledge. This filter exists so that
reconciliation stays worth reading — a knowledge base that grows on every
task is one nobody trusts or searches.

## The default question

Would a future engineer plausibly ask **"why is it like this?"**, or have to
**rediscover this** if it weren't recorded? If yes, durable knowledge is
probably warranted. If the answer is "they'd just read the code," it isn't.

## Usually promote or update knowledge for

- architecture changes
- a new subsystem or major feature
- a new integration
- data model / schema changes
- state-management changes
- auth / security / permissions changes
- important performance tradeoffs
- a new shared pattern or convention
- meaningful product/UX behavior that affects future work
- a non-obvious decision with real alternatives and tradeoffs
- an expensive-to-rediscover debugging discovery
- a future extension point or important constraint
- a change that invalidates previous documentation or assumptions

## Usually do not promote

- a typo or copy change
- a trivial styling adjustment
- a routine refactor with no architecture or behavior impact
- a straightforward bug fix with no reusable lesson
- a mechanical dependency bump
- a tiny implementation detail

## Applying it

1. Start from the handoff's own `significance_hint` — it's a hint from the
   implementer, not a verdict. Treat `none` as a soft signal to skip unless
   something in `candidate_decisions`/`candidate_lessons`/
   `unexpected_findings` clearly contradicts it.
2. Run each candidate line through the two lists above, not the whole task.
   A task can be a `none` overall and still contain one line worth
   promoting (an unexpected finding buried in an otherwise routine fix), and
   the reverse — a `likely` task can turn out, on inspection, to contain
   nothing that survives contact with an existing canonical entry (see
   `reconciliation.md`'s DUPLICATE classification).
3. `knowledge_mode` shifts the threshold, not the list:
   - `minimal` — only the clearly-critical items: architecture, data model,
     security, constraints that would actually break something later if
     lost. Skip lessons and learning-oriented material entirely.
   - `decisions` — the full list above, decision/tradeoff-weighted. Skip
     `learning-mode.md` enrichment.
   - `learning` — the full list above, plus run promoted entries through
     `learning-mode.md` for teaching-ready source material. This is the
     default for personal projects per the user's own stated preference to
     deeply learn what they build.
4. When genuinely unsure whether something clears the bar, promote it as an
   `OPEN_QUESTION` or a thin entry rather than dropping it — a knowledge base
   with an honest "not yet resolved" entry is more useful than one with a
   silent gap, and cheaper to fix later than a false negative that gets
   rediscovered the hard way.

## What "promote" actually means

Promoting a candidate does not automatically mean creating a new entry — it
means it's worth taking through the classification in `reconciliation.md`
(NEW / EXTEND / UPDATE / CONFLICT / DUPLICATE). Most promoted candidates on
an active project turn out to be EXTEND or UPDATE against something that
already exists, not NEW.
