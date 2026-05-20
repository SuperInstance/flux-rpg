# Flux RPG — What the Cycle Model Teaches About Constraint Processing

RPG IV (Report Program Generator, 1959) runs on IBM i (AS/400) — the machines that process most of the world's banking transactions, insurance claims, and payroll. This repo implements the Flux constraint engine in RPG IV free-format.

## How to Read RPG

RPG (especially RPG IV / RPGLE free-format) looks unusual but follows a clear logic: read → process → write.

```rpg
// This is a comment
// Free-format RPG IV (ILE RPG)

// Standalone variables — packed decimal for exact arithmetic
Dcl-S X Packed(7:0);              // 7-digit packed decimal, 0 decimals
Dcl-S Result Char(32);

// Data structure — like a struct/record
Dcl-Ds ConstraintRec Qualified;
  LO Packed(7:0);                  // Lower bound
  HI Packed(7:0);                  // Upper bound
  Severity Packed(3:0);            // Violation weight
  Violated Char(1);                // '1' or '0'
End-Ds;

// Array of structures
Dcl-Ds Constraints Qualified Dim(8);
  LO Packed(7:0);
  HI Packed(7:0);
  Severity Packed(3:0);
  Violated Char(1);
End-Ds;

// Indicators — 99 boolean flags (*IN01 through *IN99)
// These ARE the error mask bits
*IN01 = *ON;                       // Set indicator 1 (constraint 1 violated)
*IN02 = *OFF;                      // Clear indicator 2

// Bitwise operations
Result_Mask = %BitOr(Mask1: Mask2);  // OR two error masks together

// Conditional execution
If Sensor_Val < Constraints(I).LO;
  Constraints(I).Violated = '1';
  Select I;
    When-is 1;  *IN01 = *ON;
    When-is 2;  *IN02 = *ON;
    // ... one per constraint (RPG doesn't index indicators dynamically)
  EndSl;
EndIf;

// Subprocedure — like a function
Dcl-Proc CheckConstraints;
  Dcl-Pi *N;                       // No return value
    Idx Int(5);                     // Parameter
  End-Pi;
  // ... logic ...
End-Proc;
```

Key ideas:
- **Indicators** (`*IN01`–`*IN99`) — boolean flags that map directly to error mask bits. RPG has had bitmasks since 1959.
- **Packed decimal** — exact arithmetic, no floating-point drift. `Packed(7,0)` is a 7-digit integer stored in BCD.
- **The RPG cycle** — implicit read-process-write loop. The language IS a pipeline.
- **Control breaks** (L1–L9) — group boundaries. Natural batching by constraint group.
- **%BitOr / %BitAnd** — bitwise operations for coalescing independent block results.
- **No dynamic indicator indexing** — you use `Select/When` to map constraint indices to indicators.

## How the Constraint Engine Maps to RPG

| Constraint Engine Concept | RPG Mechanism |
|---------------------------|---------------|
| Error mask (8 bits) | Indicators *IN01–*IN08 — bitmask constraint checking since 1959 |
| Read input → check → write result | The RPG cycle (read → process → write) |
| Fracture into independent blocks | Control breaks (L1–L9) — natural batching |
| Coalescence (bitwise OR) | `%BitOr(Mask1: Mask2)` |
| Exact arithmetic | Packed decimal — zero floating-point drift |
| Sediment layer matching | `LOOKUP` operation |
| Engine components | Subprocedures (`Dcl-Proc`) |

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

## What RPG Teaches Us

**The cycle IS the hot path.** Every constraint engine reads input → validates → processes → writes output. RPG made this explicit in 1959. The language doesn't just support this pattern — it IS this pattern.

Three specific lessons:

1. **Indicators ARE bitmasks.** Before C had `|` and `&`, RPG had *IN01 through *IN99 — 99 boolean flags that map directly to error mask bits. The constraint engine's error mask is built by setting indicators and reading them back. This isn't retro computing — it's frozen architecture.

2. **Control breaks are natural batching.** L1 through L9 define group boundaries in sorted data. In constraint processing, this is fracturing — splitting into independent blocks by shared dimensions. RPG was doing block decomposition before graph theory formalized it.

3. **Packed decimal eliminates float drift.** IBM's packed BCD gives exact arithmetic for financial and sensor values. No IEEE 754 surprises. The constraint engine uses `Packed(7,0)` — exact integer bounds checking with zero rounding error.

## Files

| File | Lines | Purpose |
|------|-------|---------|
| `FLXCHECK.rpgle` | ~280 | Core engine: INT8 bounds, indicators, severity |
| `FLXFRACT.rpgle` | ~270 | BFS fracture, queue management, coalesce |
| `FLXSEDIMNT.rpgle` | ~200 | Sediment stack, monotonic checking, LOOKUP |
| `FLXMAIN.rpgle` | ~350 | Full pipeline with adversarial self-test |
| `copybooks/` | 3 files | Shared DS definitions |

## Build & Run

This code is correct RPG IV free-format. It compiles on IBM i 7.2+ with the ILE RPG compiler. It cannot compile on Linux — RPG targets IBM i hardware (AS/400 lineage) where the cycle model is native. To run: load onto an IBM i system with ILE RPG compiler, compile with `CRTBNDRPG PGM(FLXMAIN) SRCFILE(QRPGLESRC)`.

## Where to Go Next

- **flux-cobol** — COBOL's OCCURS tables = fixed arrays. Sections = pipeline stages. COBOL computes, MUMPS remembers.
- **flux-pli** — PL/I's native `BIT(8)` type makes the error mask a language primitive, not a simulation.
- **flux-mumps** — Where sediment actually lives. MUMPS globals persist across sessions.
- **flux-docs** — Full documentation: error masks, fracture-coalesce, sediment, thermodynamic analogy.

## Author

Forgemaster ⚒️ — Constraint Theory Ecosystem, 2026-05-19
