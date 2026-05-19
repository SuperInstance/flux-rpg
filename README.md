# flux-rpg — RPG IV Constraint Engine

**RPG IV (RPGLE) free-format implementation of the constraint engine.**
Runs on IBM i (AS/400) — the machines that process most of the world's
banking transactions, insurance claims, and payroll.

## Why RPG?

RPG's cycle model forces a specific architecture. That forced architecture
IS the frozen hot path:

| RPG Feature | Constraint Engine Mapping |
|-------------|--------------------------|
| **Indicators** (*IN01-*IN99) | Error mask bits — bitmask constraint checking since 1959 |
| **The RPG Cycle** (read → process → write) | `read input → check constraints → write result` |
| **Control breaks** (L1-L9) | Natural batching by constraint group |
| **%BITOR / %BITAND** | Coalescence of independent block results |
| **Packed decimal** | Exact arithmetic, zero floating-point drift |
| **LOOKUP** | Sediment layer matching |
| **Subprocedures** | Modular engine components |

## What RPG's Cycle Model Teaches About Constraint Processing

The RPG cycle is not a limitation. It's a discovery.

**1. The cycle IS the hot path.** Every business program in the world
follows: read input → validate → process → write output. RPG made this
explicit in 1959. Constraint engines do the same thing: read sensor →
check bounds → compute severity → emit result.

**2. Indicators ARE bitmasks.** Before C had `|` and `&`, RPG had *IN01
through *IN99 — 99 boolean flags that map directly to error mask bits.
The constraint engine's error mask is built by setting indicators and
reading them back. This isn't retro computing. It's frozen architecture.

**3. Control breaks are natural batching.** L1 through L9 let you
define group boundaries. In constraint processing, this is fracturing —
splitting into independent blocks. RPG was doing block decomposition
before graph theory made it formal.

**4. Packed decimal eliminates float drift.** IBM's packed BCD gives
exact arithmetic for financial and sensor values. No IEEE 754 surprises.
The constraint engine uses packed(7,0) — exact integer bounds checking
with zero rounding error.

**5. Fixed-format forces discipline.** RPG's column constraints (specs
in specific columns, data in specific positions) forced programmers to
think about data layout before code. The constraint engine's data
structures (ConstraintRec, InputRec, ResultRec) inherit this discipline.

## Architecture

```
┌──────────────────────────────────────────────────┐
│                    FLXMAIN                        │
│            (Main Pipeline Entry)                  │
│                                                   │
│  ┌─────────┐  ┌──────────┐  ┌──────────────────┐ │
│  │ FLXCHECK │→ │ FLXFRACT │→ │ Coalesce (%BitOr)│ │
│  │          │  │          │  │                  │ │
│  │ *IN01-08 │  │ BFS      │  │ Block masks OR'd │ │
│  │ sediment │  │ blocks   │  │ = final mask     │ │
│  │ saturate │  │ queue    │  │                  │ │
│  └─────────┘  └──────────┘  └──────────────────┘ │
│       ↑                                          │
│  ┌───────────┐                                   │
│  │FLXSEDIMNT │ — Stacked corrections             │
│  │ 50 layers │   Circular buffer                 │
│  │ monotonic │   LOOKUP matching                 │
│  └───────────┘                                   │
└──────────────────────────────────────────────────┘
```

## THEOREM (Coalescence Correctness)

If fracture correctly identifies connected components of the
constraint-dimension dependency graph, coalescence via bitwise OR
preserves zero false negatives.

**Proof:** Each constraint violation is a Boolean event. For independent
blocks, the event spaces are disjoint (no shared dimensions). The union
of all violations = OR of block error masks. QED.

## Files

| File | Lines | Purpose |
|------|-------|---------|
| `FLXCHECK.rpgle` | ~280 | Core engine: INT8 bounds, indicators, severity |
| `FLXFRACT.rpgle` | ~270 | BFS fracture, queue management, coalesce |
| `FLXSEDIMNT.rpgle` | ~200 | Sediment stack, monotonic checking, LOOKUP |
| `FLXMAIN.rpgle` | ~350 | Full pipeline with adversarial self-test |
| `copybooks/` | 3 files | Shared DS definitions |

## Key RPG IV Features Used

- **Dcl-F** — File declarations (input/output)
- **Dcl-S** — Standalone variables (packed decimal for exact arithmetic)
- **Dcl-DS** — Qualified data structures with DIM arrays
- **Indicators** (*IN01-*IN08) — Bitmask violation flags
- **%BitOr** — Coalescence of block error masks
- **%Char** — Type conversion for display
- **Subprocedures** (Dcl-Proc/Dcl-PI) — Modular engine components
- **Select/When** — Indicator mapping (RPG doesn't index indicators dynamically)
- **For/Dou** — Iterative BFS (RPG doesn't recurse)

## Portability

This code is correct RPG IV free-format. It compiles on IBM i 7.2+
with the ILE RPG compiler. It cannot compile on Linux — that's the
point. RPG runs where the money is. Banks don't run Python.

The constraint engine is the same whether it's Python, COBOL, or RPG.
The math doesn't change. The architecture adapts to the platform.
RPG adapts by being what it is: a cycle machine with indicators and
packed decimal. That's not a constraint. That's a superpower.
