# RPG IV Constraint Engine — Build & Deploy

## Files

| File | Purpose |
|------|---------|
| `FLXCHECK.rpgle` | Core engine: INT8 bounds checking with sediment |
| `FLXFRACT.rpgle` | Fracture: BFS decomposition into independent blocks |
| `FLXSEDIMNT.rpgle` | Sediment: stacked correction layers |
| `FLXMAIN.rpgle` | Main pipeline: check → fracture → coalesce → sediment |
| `copybooks/FLXCONST.rpgleinc` | Constraint DS definition |
| `copybooks/FLXRESULT.rpgleinc` | Result DS definition |
| `copybooks/FLXSEDIMNT.rpgleinc` | Sediment DS definition |

## Building on IBM i

```bash
# Compile each module
CRTSQLRPGI OBJ(FLXCHECK) SRCFILE(QRPGLESRC) SRCMBR(FLXCHECK) RPGPPOPT(*LVL2)
CRTSQLRPGI OBJ(FLXFRACT) SRCFILE(QRPGLESRC) SRCMBR(FLXFRACT) RPGPPOPT(*LVL2)
CRTSQLRPGI OBJ(FLXSEDIMNT) SRCFILE(QRPGLESRC) SRCMBR(FLXSEDIMNT) RPGPPOPT(*LVL2)
CRTSQLRPGI OBJ(FLXMAIN) SRCFILE(QRPGLESRC) SRCMBR(FLXMAIN) RPGPPOPT(*LVL2)

# Create program (bind modules)
CRTPGM PGM(FLXMAIN) MODULE(FLXCHECK FLXFRACT FLXSEDIMNT FLXMAIN)
```

Or use `CRTBNDRPG` for standalone programs:

```bash
CRTBNDRPG PGM(FLXCHECK) SRCFILE(QRPGLESRC) SRCMBR(FLXCHECK)
```

## Linux (no compiler)

The code is syntactically correct RPG IV free-format but cannot be compiled
on Linux. It's designed for correctness and review.

## Compiler Directives

- `Ctl-Opt Main(Main)` — Use MAIN procedure (no RPG cycle)
- `Ctl-Opt Nomain` — Module has no default cycle (for service programs)
- `/Copy copybooks/...` — Copybook inclusion
