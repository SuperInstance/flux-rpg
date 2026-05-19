///=====================================================================
/// FLXCHECK.rpgle — THE CORE: Exact INT8 bounds checking with sediment
///
/// Constraint engine: validate sensor inputs against bounds,
/// apply sediment corrections, compute severity.
/// RPG IV free-format. Indicators *IN01-*IN08 ARE the error mask.
///
/// The RPG Cycle reads input → checks constraints → writes result.
/// This IS the frozen hot path. Indicators were doing bitmask
/// constraint checking before Unix existed (1959).
///=====================================================================

Ctl-Opt Main(Main) Nomain;
Ctl-Opt Debug(*No);

///---------------------------------------------------------------------
/// Work variables (at module level so copybooks can reference WorkVal)
///---------------------------------------------------------------------
Dcl-S WorkVal   Packed(7:0);
Dcl-S WorkLo    Packed(7:0);
Dcl-S WorkHi    Packed(7:0);
Dcl-S BitVal    Zoned(5:0);
Dcl-S SevSum    Int(5) Inz(0);
Dcl-S LayerApplied Int(5) Inz(0);
Dcl-S Idx       Int(5);
Dcl-S SIdx      Int(5);

///---------------------------------------------------------------------
/// Shared definitions
///---------------------------------------------------------------------
/Copy copybooks/FLXCONST
/Copy copybooks/FLXRESULT
/Copy copybooks/FLXSEDIMNT

///---------------------------------------------------------------------
/// Input: 8 sensor values (packed decimal, INT8 saturated)
///---------------------------------------------------------------------
Dcl-S SensorValue Like(WorkVal) Dim(8);

///---------------------------------------------------------------------
/// Indicators *IN01-*IN08 — the 8 constraint violation flags
/// These ARE the error mask bits. RPG was doing bitmask constraint
/// checking in 1959. This is not nostalgia. This is frozen architecture.
///---------------------------------------------------------------------

///=====================================================================
/// MAIN — Self-test entry point
///=====================================================================
Dcl-Proc Main;
  Dcl-Pi *N;
  End-Pi;

  Dsply 'FLXCHECK — Flux Constraint Engine v1.0 (RPG IV)';
  Dsply '=================================================';

  RunSelfTest();

  *InLR = *On;
End-Proc Main;

///=====================================================================
/// RunSelfTest — Adversarial and boundary inputs
///=====================================================================
Dcl-Proc RunSelfTest;
  Dsply 'Running self-test...';

  // Setup 3 constraints: temperature, pressure, voltage
  ConstraintCount = 1;
  ConstraintTable.Constraint(1).cLo = -40;
  ConstraintTable.Constraint(1).cHi = 85;
  ConstraintTable.Constraint(1).cSeverity = 1;
  ConstraintTable.Constraint(1).cName = 'temperature';

  ConstraintCount += 1;
  ConstraintTable.Constraint(2).cLo = 800;
  ConstraintTable.Constraint(2).cHi = 1200;
  ConstraintTable.Constraint(2).cSeverity = 2;
  ConstraintTable.Constraint(2).cName = 'pressure';

  ConstraintCount += 1;
  ConstraintTable.Constraint(3).cLo = 0;
  ConstraintTable.Constraint(3).cHi = 50;
  ConstraintTable.Constraint(3).cSeverity = 1;
  ConstraintTable.Constraint(3).cName = 'voltage';

  // TEST 1: All values in bounds
  SensorValue(1) = 25;
  SensorValue(2) = 900;
  SensorValue(3) = 12;
  ValidateAll();
  If ResultRec.passed = *Off;
    Dsply '  FAIL: Test 1 (all pass)';
  Else;
    Dsply '  PASS: Test 1 (all in bounds)';
  EndIf;

  // TEST 2: Temperature violation
  SensorValue(1) = 100;
  ValidateAll();
  If ResultRec.passed = *On;
    Dsply '  FAIL: Test 2 (temp violation missed)';
  Else;
    Dsply '  PASS: Test 2 (temp caught)';
  EndIf;

  // TEST 3: Boundary — exactly at LO
  SensorValue(1) = -40;
  ValidateAll();
  If ResultRec.passed = *Off;
    Dsply '  FAIL: Test 3 (boundary LO)';
  Else;
    Dsply '  PASS: Test 3 (boundary LO pass)';
  EndIf;

  // TEST 4: INT8 saturation
  SensorValue(1) = -200;
  SaturateSensors();
  If SensorValue(1) <> -127;
    Dsply '  FAIL: Test 4 (saturate negative)';
  Else;
    Dsply '  PASS: Test 4 (INT8 saturate)';
  EndIf;

  // TEST 5: Sediment correction
  SedimentCount = 1;
  SedimentStack.layer(1).constraintIdx = 1;
  SedimentStack.layer(1).oldLo = -40;
  SedimentStack.layer(1).oldHi = 85;
  SedimentStack.layer(1).newLo = -40;
  SedimentStack.layer(1).newHi = 105;
  SedimentStack.layer(1).reason = 'extended_temp_range';
  SedimentStack.layer(1).timestamp = 20260519;

  SensorValue(1) = 95;
  ValidateAll();
  If ResultRec.passed = *Off;
    Dsply '  FAIL: Test 5 (sediment correction)';
  Else;
    Dsply '  PASS: Test 5 (sediment extended bounds)';
  EndIf;

  // TEST 6: Error mask from indicators
  // Violate temp AND voltage simultaneously
  SensorValue(1) = 100;  // temp violation (hi=105 after sediment)
  SensorValue(3) = 60;   // voltage violation (hi=50)
  ValidateAll();
  // *IN01 = temp violated, *IN03 = voltage violated
  // error mask = 2^0 + 2^2 = 1 + 4 = 5
  If ResultRec.errMask = 5;
    Dsply '  PASS: Test 6 (indicator bitmask = 5)';
  Else;
    Dsply '  FAIL: Test 6 (indicator bitmask)';
  EndIf;

  Dsply 'Self-test complete.';
End-Proc RunSelfTest;

///=====================================================================
/// ValidateAll — Full pipeline: saturate, sediment, check, severity
/// The RPG Cycle: read → process → write. This IS the cycle.
///=====================================================================
Dcl-Proc ValidateAll;
  // Clear result
  ResultRec.errMask = 0;
  ResultRec.violatedCnt = 0;
  ResultRec.severity = 0;
  ResultRec.passed = *On;

  // Clear indicators 01-08
  For Idx = 1 to 8;
    Select;
      When Idx = 1;
        *In01 = *Off;
      When Idx = 2;
        *In02 = *Off;
      When Idx = 3;
        *In03 = *Off;
      When Idx = 4;
        *In04 = *Off;
      When Idx = 5;
        *In05 = *Off;
      When Idx = 6;
        *In06 = *Off;
      When Idx = 7;
        *In07 = *Off;
      When Idx = 8;
        *In08 = *Off;
    EndSl;
  EndFor;

  SaturateSensors();
  ApplySediment();
  CheckConstraints();
  ComputeSeverity();
End-Proc ValidateAll;

///=====================================================================
/// SaturateSensors — Clamp all inputs to INT8 range [-127, 127]
/// No floating point. Packed decimal exact arithmetic.
///=====================================================================
Dcl-Proc SaturateSensors;
  For Idx = 1 to ConstraintCount;
    If SensorValue(Idx) < Int8Min;
      SensorValue(Idx) = Int8Min;
    EndIf;
    If SensorValue(Idx) > Int8Max;
      SensorValue(Idx) = Int8Max;
    EndIf;
  EndFor;
End-Proc SaturateSensors;

///=====================================================================
/// ApplySediment — Layer corrections onto constraint bounds
/// Each sediment layer modifies bounds for a specific constraint.
/// Oldest layers superseded when stack is full.
///=====================================================================
Dcl-Proc ApplySediment;
  LayerApplied = 0;
  For SIdx = 1 to SedimentCount;
    Idx = SedimentStack.layer(SIdx).constraintIdx;
    If Idx > 0 and Idx <= ConstraintCount;
      If SedimentStack.layer(SIdx).newLo <> 0;
        ConstraintTable.Constraint(Idx).cLo =
            SedimentStack.layer(SIdx).newLo;
      EndIf;
      If SedimentStack.layer(SIdx).newHi <> 0;
        ConstraintTable.Constraint(Idx).cHi =
            SedimentStack.layer(SIdx).newHi;
      EndIf;
      LayerApplied += 1;
    EndIf;
  EndFor;
End-Proc ApplySediment;

///=====================================================================
/// CheckConstraints — Compare each sensor to its bounds
/// Set indicators *IN01-*IN08 = violation flags.
/// Build error mask from indicators.
/// RPG indicators ARE the bitmask. 1959 technology, 2026 correctness.
///=====================================================================
Dcl-Proc CheckConstraints;
  For Idx = 1 to ConstraintCount;
    WorkVal = SensorValue(Idx);
    WorkLo  = ConstraintTable.Constraint(Idx).cLo;
    WorkHi  = ConstraintTable.Constraint(Idx).cHi;

    ConstraintTable.Constraint(Idx).cViolated = *Off;

    If WorkVal < WorkLo or WorkVal > WorkHi;
      ConstraintTable.Constraint(Idx).cViolated = *On;
      ResultRec.violatedCnt += 1;

      // Set the indicator for this constraint
      Select;
        When Idx = 1;
          *In01 = *On;
        When Idx = 2;
          *In02 = *On;
        When Idx = 3;
          *In03 = *On;
        When Idx = 4;
          *In04 = *On;
        When Idx = 5;
          *In05 = *On;
        When Idx = 6;
          *In06 = *On;
        When Idx = 7;
          *In07 = *On;
        When Idx = 8;
          *In08 = *On;
      EndSl;

      // Build error mask from indicator states
      // Bit 0 = *IN01, Bit 1 = *IN02, ... Bit 7 = *IN08
      BitVal = 1;
      ResultRec.errMask =
          %BitOr(ResultRec.errMask:
                 %BitAnd(*In01 * BitVal + *In02 * (BitVal*2) +
                         *In03 * (BitVal*4) + *In04 * (BitVal*8) +
                         *In05 * (BitVal*16) + *In06 * (BitVal*32) +
                         *In07 * (BitVal*64) + *In08 * (BitVal*128):
                         %BitOr(BitVal: BitVal*2: BitVal*4: BitVal*8:
                               BitVal*16: BitVal*32: BitVal*64: BitVal*128)));

      ResultRec.passed = *Off;
    EndIf;
  EndFor;

  // Rebuild mask cleanly from indicators
  ResultRec.errMask = 0;
  If *In01 = *On;
    ResultRec.errMask += 1;
  EndIf;
  If *In02 = *On;
    ResultRec.errMask += 2;
  EndIf;
  If *In03 = *On;
    ResultRec.errMask += 4;
  EndIf;
  If *In04 = *On;
    ResultRec.errMask += 8;
  EndIf;
  If *In05 = *On;
    ResultRec.errMask += 16;
  EndIf;
  If *In06 = *On;
    ResultRec.errMask += 32;
  EndIf;
  If *In07 = *On;
    ResultRec.errMask += 64;
  EndIf;
  If *In08 = *On;
    ResultRec.errMask += 128;
  EndIf;
End-Proc CheckConstraints;

///=====================================================================
/// ComputeSeverity — Sum severities of violated constraints
/// Uses %XFOOT pattern: iterate, check indicator, accumulate.
///=====================================================================
Dcl-Proc ComputeSeverity;
  SevSum = 0;

  If *In01 = *On;
    SevSum += ConstraintTable.Constraint(1).cSeverity;
  EndIf;
  If *In02 = *On;
    SevSum += ConstraintTable.Constraint(2).cSeverity;
  EndIf;
  If *In03 = *On;
    SevSum += ConstraintTable.Constraint(3).cSeverity;
  EndIf;
  If *In04 = *On;
    SevSum += ConstraintTable.Constraint(4).cSeverity;
  EndIf;
  If *In05 = *On;
    SevSum += ConstraintTable.Constraint(5).cSeverity;
  EndIf;
  If *In06 = *On;
    SevSum += ConstraintTable.Constraint(6).cSeverity;
  EndIf;
  If *In07 = *On;
    SevSum += ConstraintTable.Constraint(7).cSeverity;
  EndIf;
  If *In08 = *On;
    SevSum += ConstraintTable.Constraint(8).cSeverity;
  EndIf;

  ResultRec.severity = SevSum;
End-Proc ComputeSeverity;
