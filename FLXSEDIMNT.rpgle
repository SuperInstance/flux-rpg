///=====================================================================
/// FLXSEDIMNT.rpgle — Sediment Layers: accumulated correctness corrections
///
/// Sediment layers stack corrections onto constraint bounds.
/// Each layer records old bounds, new bounds, reason, and timestamp.
/// When the stack is full, the oldest layer is superseded.
/// Monotonic correctness: layers only narrow or extend, never corrupt.
///
/// RPG's LOOKUP op-code finds layers by constraint index.
/// The stack model maps directly to RPG array processing.
///=====================================================================

Ctl-Opt Main(Main) Nomain;

Dcl-S WorkVal Packed(7:0);

/Copy copybooks/FLXCONST
/Copy copybooks/FLXSEDIMNT

///---------------------------------------------------------------------
/// Sediment module state
///---------------------------------------------------------------------
Dcl-S NextSlot      Int(5) Inz(1);   // Circular write pointer
Dcl-S CorrectnessOk Ind    Inz(*On); // Monotonic correctness flag

///=====================================================================
/// MAIN — Self-test
///=====================================================================
Dcl-Proc Main;
  Dcl-Pi *N;
  End-Pi;

  Dsply 'FLXSEDIMNT — Flux Sediment Engine v1.0 (RPG IV)';
  Dsply '=================================================';

  RunSedimentTest();

  *InLR = *On;
End-Proc Main;

///=====================================================================
/// RunSedimentTest — Test sediment add/apply/monotonic
///=====================================================================
Dcl-Proc RunSedimentTest;
  Dcl-S OldLo  Like(WorkVal);
  Dcl-S OldHi  Like(WorkVal);
  Dcl-S NewLo  Like(WorkVal);
  Dcl-S NewHi  Like(WorkVal);
  Dcl-S Found  Int(5);

  Dsply 'Running sediment self-test...';

  // TEST 1: Add a layer
  AddLayer(1: -40: 85: -40: 105: 'extend_temp': 20260519);
  If SedimentCount = 1;
    Dsply '  PASS: Test 1 (layer added)';
  Else;
    Dsply '  FAIL: Test 1 (layer count)';
  EndIf;

  // TEST 2: Add another layer for different constraint
  AddLayer(2: 800: 1200: 900: 1200: 'raise_pressure_lo': 20260519);
  If SedimentCount = 2;
    Dsply '  PASS: Test 2 (second layer)';
  Else;
    Dsply '  FAIL: Test 2 (layer count)';
  EndIf;

  // TEST 3: Find layer for constraint 1 using LOOKUP pattern
  Found = FindLayer(1);
  If Found > 0;
    If SedimentStack.layer(Found).newHi = 105;
      Dsply '  PASS: Test 3 (layer lookup + value)';
    Else;
      Dsply '  FAIL: Test 3 (wrong value)';
    EndIf;
  Else;
    Dsply '  FAIL: Test 3 (layer not found)';
  EndIf;

  // TEST 4: Monotonic check — extending bounds is valid
  If CheckMonotonic(1: -40: 105: -40: 110);
    Dsply '  PASS: Test 4 (monotonic extension)';
  Else;
    Dsply '  FAIL: Test 4 (should be monotonic)';
  EndIf;

  // TEST 5: Supersede oldest when full — fill up and add one more
  SedimentCount = 0;
  NextSlot = 1;
  Dcl-S I Int(5);
  For I = 1 to SedimentMax;
    AddLayer(I: 0: 100: 0: 100 + I: 'fill_' + %Char(I): 20260519);
  EndFor;
  // Stack is full (50 layers). Add one more — should supersede oldest.
  AddLayer(1: 0: 100: 0: 200: 'supersede_test': 20260519);
  // The slot should have been reused
  Found = FindLayer(1);
  If Found > 0 and SedimentStack.layer(Found).newHi = 200;
    Dsply '  PASS: Test 5 (supersede oldest)';
  Else;
    Dsply '  FAIL: Test 5 (supersede)';
  EndIf;

  Dsply 'Sediment self-test complete.';
End-Proc RunSedimentTest;

///=====================================================================
/// AddLayer — Add a correction layer to the sediment stack
/// If stack is full, supersede the oldest layer (circular buffer).
///=====================================================================
Dcl-Proc AddLayer;
  Dcl-Pi AddLayer;
    pConstraintIdx Int(5)     Value;
    pOldLo         Like(WorkVal) Value;
    pOldHi         Like(WorkVal) Value;
    pNewLo         Like(WorkVal) Value;
    pNewHi         Like(WorkVal) Value;
    pReason        Char(32)   Value;
    pTimestamp     Zoned(8:0) Value;
  End-Pi;

  If SedimentCount >= SedimentMax;
    // Supersede oldest — circular buffer
    SedimentStack.layer(NextSlot).constraintIdx = pConstraintIdx;
    SedimentStack.layer(NextSlot).oldLo    = pOldLo;
    SedimentStack.layer(NextSlot).oldHi    = pOldHi;
    SedimentStack.layer(NextSlot).newLo    = pNewLo;
    SedimentStack.layer(NextSlot).newHi    = pNewHi;
    SedimentStack.layer(NextSlot).reason   = pReason;
    SedimentStack.layer(NextSlot).timestamp = pTimestamp;
  Else;
    // Append to stack
    SedimentCount += 1;
    SedimentStack.layer(SedimentCount).constraintIdx = pConstraintIdx;
    SedimentStack.layer(SedimentCount).oldLo    = pOldLo;
    SedimentStack.layer(SedimentCount).oldHi    = pOldHi;
    SedimentStack.layer(SedimentCount).newLo    = pNewLo;
    SedimentStack.layer(SedimentCount).newHi    = pNewHi;
    SedimentStack.layer(SedimentCount).reason   = pReason;
    SedimentStack.layer(SedimentCount).timestamp = pTimestamp;
  EndIf;

  // Advance circular pointer
  NextSlot += 1;
  If NextSlot > SedimentMax;
    NextSlot = 1;
  EndIf;
End-Proc AddLayer;

///=====================================================================
/// FindLayer — Find the latest sediment layer for a constraint
/// RPG LOOKUP pattern: scan array for matching key.
/// Returns the index or 0 if not found.
///=====================================================================
Dcl-Proc FindLayer;
  Dcl-Pi FindLayer Int(5);
    pConstraintIdx Int(5) Value;
  End-Pi;

  Dcl-S FIdx Int(5);
  Dcl-S Found Int(5) Inz(0);

  // Search backwards to find the most recent layer for this constraint
  For FIdx = SedimentCount Downto 1;
    If SedimentStack.layer(FIdx).constraintIdx = pConstraintIdx;
      Found = FIdx;
      Leave;
    EndIf;
  EndFor;

  Return Found;
End-Proc FindLayer;

///=====================================================================
/// ApplySedimentLayer — Apply a single sediment layer to constraints
///=====================================================================
Dcl-Proc ApplySedimentLayer;
  Dcl-Pi ApplySedimentLayer;
    pLayerIdx Int(5) Value;
  End-Pi;

  Dcl-S TIdx Int(5);

  TIdx = SedimentStack.layer(pLayerIdx).constraintIdx;
  If TIdx > 0 and TIdx <= ConstraintCount;
    If SedimentStack.layer(pLayerIdx).newLo <> 0;
      ConstraintTable.Constraint(TIdx).cLo =
          SedimentStack.layer(pLayerIdx).newLo;
    EndIf;
    If SedimentStack.layer(pLayerIdx).newHi <> 0;
      ConstraintTable.Constraint(TIdx).cHi =
          SedimentStack.layer(pLayerIdx).newHi;
    EndIf;
  EndIf;
End-Proc ApplySedimentLayer;

///=====================================================================
/// CheckMonotonic — Verify that new bounds are a valid extension
/// Extension: newLo <= oldLo AND newHi >= oldHi (widen only)
/// OR narrowing: newLo >= oldLo AND newHi <= oldHi (narrow only)
/// Mixed = invalid (both widen one side and narrow the other)
///=====================================================================
Dcl-Proc CheckMonotonic;
  Dcl-Pi CheckMonotonic Ind;
    pConstraintIdx Int(5)      Value;
    pOldLo         Like(WorkVal) Value;
    pOldHi         Like(WorkVal) Value;
    pNewLo         Like(WorkVal) Value;
    pNewHi         Like(WorkVal) Value;
  End-Pi;

  Dcl-S Widening Ind;
  Dcl-S Narrowing Ind;

  Widening  = (pNewLo <= pOldLo) and (pNewHi >= pOldHi);
  Narrowing = (pNewLo >= pOldLo) and (pNewHi <= pOldHi);

  // Monotonic if either pure widening or pure narrowing
  Return Widening or Narrowing;
End-Proc CheckMonotonic;
