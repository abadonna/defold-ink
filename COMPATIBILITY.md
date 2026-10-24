# Ink runtime compatibility audit

This is a source audit against Ink JSON v21 and a focused regression suite, not
a claim of complete language conformance.

## First patch: shuffled dialogue

`seq` previously made an independent random pick and consumed only the element
count. It now consumes both the visit index and the element count and chooses
from a per-container permutation. Each cycle visits every element once. The
compiled `shuffle once` and `shuffle stopping` variants use the same operation.

Random draws still use the existing replay log. `serialize()` additionally saves
the current permutations, so loading partway through a cycle does not repeat a
previous variant. Old serialized data without this field still loads, but cannot
recover its old unfinished permutation. Histories containing the old broken
shuffle implementation are not compatible with the new sequence of random draws.

`restore()` now returns the paragraphs and choices produced by the last replayed
`jump()` instead of stale output from before the jump. Replayed random operations
no longer call `math.random` before using the recorded value.

This patch preserves shuffle behavior, not C# seed-for-seed random order.
`SEED_RANDOM` and story-local random generators remain future work.

## Remaining gaps

| Area | Source finding | Suggested priority |
| --- | --- | --- |
| Choice text | Choice processing pops one string regardless of the start-content and choice-only flags; mixed `start[choice]` text and empty strings need coverage and fixes. | Next |
| External functions | `story.bind` exists, but the standard `x()` / `exArgs` JSON instruction has no handler. Binding a normal `f()` is not equivalent. | Next if game callbacks need it |
| Seeded randomness | `srnd` is absent; story creation seeds the shared Lua RNG. | Next for deterministic story-local randomness |
| Turns and choices | `turn`, `turns`, `choiceCnt` have no handlers; containers do not track the turn flag. | When authored content needs them |
| Numeric built-ins | Unary negate `_`, `POW`, and `CEILING` have no handlers. | Small separate patch |
| Strings and arithmetic | `ev`/`/ev` are ignored; strings outside `str` go to output rather than the evaluation stack. String concatenation/containment and integer division differ from Ink. | Before general expression support |
| Lists | Missing intersection, min/max/count/all/invert, range/random, and list/integer increment semantics. | Separate list compatibility work |
| Function scope and references | Temporary scope is keyed by stitch, rather than call-stack frame; reference `ci` is ignored. Recursive/local scope needs conformance fixtures. | Before complex functions |
| Threads | The thread handler explicitly says it is tentative and does not clone a call stack. | Separate runtime work |
| Errors | Coroutine errors are printed rather than propagated consistently. | Before game integration |

## Verification

The checked-in fixture `tests/sequence.json` is compiled from `sequence.ink`
with inkjs 2.4.0. Regenerate with:

```
npx --yes --package inkjs@2.4.0 inkjs-compiler -o tests/sequence.json tests/sequence.ink
```

Run the regression suite with Python and Lupa (`python -m pip install lupa`):

```
python tests/test_sequences.py
```

It uses Lupa's LuaJIT 2.1 runtime, with minimal Defold JSON/logging shims. An
actual Defold Editor build of this fork passed on Defold 1.14.0, with no build issues or runtime errors in the bundled sample. All 12 LuaJIT regression tests passed.

## Reference sources

- [Ink JSON format](https://github.com/inkle/ink/blob/master/Documentation/ink_JSON_runtime_format.md)
- [Reference shuffle and control-command implementation](https://github.com/inkle/ink/blob/master/ink-engine-runtime/Story.cs)
- [Reference native operations](https://github.com/inkle/ink/blob/master/ink-engine-runtime/NativeFunctionCall.cs)
