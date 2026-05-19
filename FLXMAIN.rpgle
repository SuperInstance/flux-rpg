///=====================================================================
/// FLXMAIN.rpgle — Main Pipeline: check → fracture → coalesce → sediment
///
/// Chains all three engines together.
/// The RPG Cycle: read input → check constraints → fracture dependencies
/// → coalesce results → apply sediment → display results.
///
/// Process a sample input file (program-described).
/// Self-test with adversarial values.
///
/// This IS the cycle. RPG was born for this.
///=====================================================================

Ctl-Opt Main(Main);

Dcl-S WorkVal    Packed(7:0);
Dcl-S WorkLo    Packed(7:0);
Dcl-S WorkHi    Packed(7:0);
Dcl-S BitVal    Zoned(5:0);
Dcl-S SevSum    Int(5) Inz(0);
Dcl-S LayerApplied Int(5) Inz(0);
Dcl-S Idx       Int(5);
Dcl-S SIdx      Int(5);

/Copy copybooks/FLXCONST
/Copy copybooks/FLXRESULT
/Copy copybooks/FLXSEDIMNT

///---------------------------------------------------------------------
/// Input: 8 sensor values
///---------------------------------------------------------------------
Dcl-S SensorValue Like(WorkVal) Dim(8);

///---------------------------------------------------------------------
/// Dependency graph (same as FLXFRACT, inline for standalone)
///---------------------------------------------------------------------
Dcl-Ds DepGraph Qualified;
  adj          Unsf Dim(64);
  nConstraints Int(5) Inz(0);
  nDimensions  Int(5) Inz(0);
End-Ds;

Dcl-S AdjIdx     Int(5);

Dcl-Ds BlockTable Qualified;
  Block        Dim(8);
    constraintIdx Int(5) Dim(8);
    dimensionIdx Int(5) Dim(8);
    cCount       Int(5) Inz(0);
    dCount       Int(5) Inz(0);
    errMask      Zoned(5:0) Inz(0);
End-Ds;

Dcl-S BlockCount   Int(5) Inz(0);
Dcl-S CoalescedMask Zoned(5:0) Inz(0);
Dcl-S Queue       Int(5) Dim(32);
Dcl-S QueueFront  Int(5) Inz(0);
Dcl-S QueueBack   Int(5) Inz(0);
Dcl-S VisitedC    Ind Dim(8);
Dcl-S VisitedD    Ind Dim(8);
Dcl-S LargestBlock Int(5) Inz(0);

///---------------------------------------------------------------------
/// Test result tracking
///---------------------------------------------------------------------
Dcl-S TestPassed  Int(5) Inz(0);
Dcl-S TestFailed  Int(5) Inz(0);
Dcl-S TestMsg     Char(64);

///=====================================================================
/// MAIN — Run the full pipeline self-test
///=====================================================================
Dcl-Proc Main;
  Dcl-Pi *N;
  End-Pi;

  Dsply 'FLXMAIN — Flux Pipeline v1.0 (RPG IV)';
  Dsply '==========================================';
  Dsply 'Full pipeline: check -> fracture -> coalesce -> sediment';
  Dsply '';

  RunFullTest();

  Dsply '';
  Dsply ('Results: ' + %Char(TestPassed) + ' passed, ' +
         %Char(TestFailed) + ' failed');

  *InLR = *On;
End-Proc Main;

///=====================================================================
/// RunFullTest — End-to-end pipeline test
///=====================================================================
Dcl-Proc RunFullTest;

  // ==================================================================
  // PHASE 1: Setup constraints
  // ==================================================================
  Dsply '--- Phase 1: Setup ---';

  ConstraintCount = 4;

  // Temperature: -40 to 85
  ConstraintTable.Constraint(1).cLo = -40;
  ConstraintTable.Constraint(1).cHi = 85;
  ConstraintTable.Constraint(1).cSeverity = 2;
  ConstraintTable.Constraint(1).cName = 'temperature';

  // Pressure: 800 to 1200
  ConstraintTable.Constraint(2).cLo = 800;
  ConstraintTable.Constraint(2).cHi = 1200;
  ConstraintTable.Constraint(2).cSeverity = 3;
  ConstraintTable.Constraint(2).cName = 'pressure';

  // Voltage: 0 to 50
  ConstraintTable.Constraint(3).cLo = 0;
  ConstraintTable.Constraint(3).cHi = 50;
  ConstraintTable.Constraint(3).cSeverity = 1;
  ConstraintTable.Constraint(3).cName = 'voltage';

  // RPM: 0 to 5000
  ConstraintTable.Constraint(4).cLo = 0;
  ConstraintTable.Constraint(4).cHi = 5000;
  ConstraintTable.Constraint(4).cSeverity = 2;
  ConstraintTable.Constraint(4).cName = 'rpm';

  Dsply ('  4 constraints configured');

  // ==================================================================
  // PHASE 2: Sediment — extend temp bounds
  // ==================================================================
  Dsply '--- Phase 2: Sediment ---';

  SedimentCount = 1;
  SedimentStack.layer(1).constraintIdx = 1;
  SedimentStack.layer(1).oldLo = -40;
  SedimentStack.layer(1).oldHi = 85;
  SedimentStack.layer(1).newLo = -40;
  SedimentStack.layer(1).newHi = 105;
  SedimentStack.layer(1).reason = 'extended_temp_range';
  SedimentStack.layer(1).timestamp = 20260519;

  // Apply sediment to constraint table
  ConstraintTable.Constraint(1).cHi = 105;

  Dsply '  Temp bounds extended to 105 via sediment';

  // ==================================================================
  // PHASE 3: Check constraints — all pass
  // ==================================================================
  Dsply '--- Phase 3: Check (all pass) ---';

  SensorValue(1) = 25;
  SensorValue(2) = 900;
  SensorValue(3) = 12;
  SensorValue(4) = 3000;

  ValidateAll();
  Assert(ResultRec.passed = *On: 'All in bounds should pass');

  // ==================================================================
  // PHASE 4: Check constraints — adversarial violations
  // ==================================================================
  Dsply '--- Phase 4: Check (violations) ---';

  // Temperature 110 > 105 (violated), pressure 900 (ok),
  // voltage 60 > 50 (violated), rpm 6000 > 5000 (violated)
  SensorValue(1) = 110;
  SensorValue(2) = 900;
  SensorValue(3) = 60;
  SensorValue(4) = 6000;

  ValidateAll();

  Assert(ResultRec.passed = *Off: 'Violations should fail');
  Assert(ResultRec.violatedCnt = 3: '3 violations expected');
  // Bits: temp=1, voltage=4, rpm=8 → mask = 13
  Assert(ResultRec.errMask = 13: 'Error mask should be 13');
  // Severity: temp(2) + voltage(1) + rpm(2) = 5
  Assert(ResultRec.severity = 5: 'Severity should be 5');

  // ==================================================================
  // PHASE 5: Fracture — dependency decomposition
  // ==================================================================
  Dsply '--- Phase 5: Fracture ---';

  SetupDependencyGraph();
  FractureInline();

  Dsply ('  Blocks: ' + %Char(BlockCount));

  // ==================================================================
  // PHASE 6: Coalesce — OR all block masks
  // ==================================================================
  Dsply '--- Phase 6: Coalesce ---';

  CoalesceInline();
  Dsply ('  Coalesced mask: ' + %Char(CoalescedMask));

  Assert(CoalescedMask = ResultRec.errMask:
         'Coalesced should match check result');

  // ==================================================================
  // PHASE 7: INT8 saturation edge case
  // ==================================================================
  Dsply '--- Phase 7: INT8 saturation ---';

  SensorValue(1) = -200;
  SaturateSensors();
  Assert(SensorValue(1) = -127: 'Saturate negative');

  SensorValue(1) = 300;
  SaturateSensors();
  Assert(SensorValue(1) = 127: 'Saturate positive');

  // ==================================================================
  // PHASE 8: Boundary precision — exactly at bounds
  // ==================================================================
  Dsply '--- Phase 8: Boundary precision ---';

  SensorValue(1) = -40;  // Exactly at LO
  SensorValue(2) = 1200; // Exactly at HI
  SensorValue(3) = 0;    // Exactly at LO
  SensorValue(4) = 0;    // Exactly at LO

  // Reset sediment for clean test
  ConstraintTable.Constraint(1).cHi = 105;

  ValidateAll();
  Assert(ResultRec.passed = *On: 'Exact boundary should pass');

  Dsply '';
  Dsply '--- Pipeline Complete ---';

End-Proc RunFullTest;

///=====================================================================
/// Assert — Track test result
///=====================================================================
Dcl-Proc Assert;
  Dcl-Pi Assert;
    pCondition Ind Value;
    pMsg       Char(64) Value;
  End-Pi;

  If pCondition = *On;
    TestPassed += 1;
    Dsply ('  PASS: ' + pMsg);
  Else;
    TestFailed += 1;
    Dsply ('  FAIL: ' + pMsg);
  EndIf;
End-Proc Assert;

///=====================================================================
/// ValidateAll — Full validation pipeline
///=====================================================================
Dcl-Proc ValidateAll;
  ResultRec.errMask = 0;
  ResultRec.violatedCnt = 0;
  ResultRec.severity = 0;
  ResultRec.passed = *On;

  // Clear indicators
  *In01 = *Off; *In02 = *Off; *In03 = *Off; *In04 = *Off;
  *In05 = *Off; *In06 = *Off; *In07 = *Off; *In08 = *Off;

  SaturateSensors();
  CheckConstraintsInline();
  ComputeSeverityInline();
End-Proc ValidateAll;

///=====================================================================
/// SaturateSensors — Clamp to INT8
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
/// CheckConstraintsInline — Set indicators, build mask
///=====================================================================
Dcl-Proc CheckConstraintsInline;
  For Idx = 1 to ConstraintCount;
    WorkVal = SensorValue(Idx);
    WorkLo  = ConstraintTable.Constraint(Idx).cLo;
    WorkHi  = ConstraintTable.Constraint(Idx).cHi;

    ConstraintTable.Constraint(Idx).cViolated = *Off;

    If WorkVal < WorkLo or WorkVal > WorkHi;
      ConstraintTable.Constraint(Idx).cViolated = *On;
      ResultRec.violatedCnt += 1;
      ResultRec.passed = *Off;

      // Set indicator
      Select;
        When Idx = 1; *In01 = *On;
        When Idx = 2; *In02 = *On;
        When Idx = 3; *In03 = *On;
        When Idx = 4; *In04 = *On;
        When Idx = 5; *In05 = *On;
        When Idx = 6; *In06 = *On;
        When Idx = 7; *In07 = *On;
        When Idx = 8; *In08 = *On;
      EndSl;
    EndIf;
  EndFor;

  // Build mask from indicators
  ResultRec.errMask = 0;
  If *In01 = *On; ResultRec.errMask += 1;  EndIf;
  If *In02 = *On; ResultRec.errMask += 2;  EndIf;
  If *In03 = *On; ResultRec.errMask += 4;  EndIf;
  If *In04 = *On; ResultRec.errMask += 8;  EndIf;
  If *In05 = *On; ResultRec.errMask += 16; EndIf;
  If *In06 = *On; ResultRec.errMask += 32; EndIf;
  If *In07 = *On; ResultRec.errMask += 64; EndIf;
  If *In08 = *On; ResultRec.errMask += 128; EndIf;
End-Proc CheckConstraintsInline;

///=====================================================================
/// ComputeSeverityInline — Sum severities from indicators
///=====================================================================
Dcl-Proc ComputeSeverityInline;
  SevSum = 0;
  If *In01 = *On; SevSum += ConstraintTable.Constraint(1).cSeverity; EndIf;
  If *In02 = *On; SevSum += ConstraintTable.Constraint(2).cSeverity; EndIf;
  If *In03 = *On; SevSum += ConstraintTable.Constraint(3).cSeverity; EndIf;
  If *In04 = *On; SevSum += ConstraintTable.Constraint(4).cSeverity; EndIf;
  If *In05 = *On; SevSum += ConstraintTable.Constraint(5).cSeverity; EndIf;
  If *In06 = *On; SevSum += ConstraintTable.Constraint(6).cSeverity; EndIf;
  If *In07 = *On; SevSum += ConstraintTable.Constraint(7).cSeverity; EndIf;
  If *In08 = *On; SevSum += ConstraintTable.Constraint(8).cSeverity; EndIf;
  ResultRec.severity = SevSum;
End-Proc ComputeSeverityInline;

///=====================================================================
/// SetupDependencyGraph — Define constraint-dimension relationships
/// Constraints share dimensions through sensors:
///   C1(temp): dims 0(temp), 1(compensated_temp)
///   C2(pressure): dims 1(compensated_temp), 2(altitude)
///   C3(voltage): dims 3(power)
///   C4(rpm): dims 3(power)
/// Blocks: {C1,C2} share dim 1, {C3,C4} share dim 3
///=====================================================================
Dcl-Proc SetupDependencyGraph;
  DepGraph.nConstraints = 4;
  DepGraph.nDimensions  = 4;

  // Clear
  For AdjIdx = 1 to 64;
    DepGraph.adj(AdjIdx) = 0;
  EndFor;

  // C1 → dims 0, 1
  SetAdjMain(0: 0);
  SetAdjMain(0: 1);
  // C2 → dims 1, 2
  SetAdjMain(1: 1);
  SetAdjMain(1: 2);
  // C3 → dim 3
  SetAdjMain(2: 3);
  // C4 → dim 3
  SetAdjMain(3: 3);
End-Proc SetupDependencyGraph;

Dcl-Proc SetAdjMain;
  Dcl-Pi SetAdjMain;
    pCon Int(5) Value;
    pDim Int(5) Value;
  End-Pi;
  AdjIdx = (pCon * DepGraph.nDimensions) + pDim + 1;
  DepGraph.adj(AdjIdx) = 1;
End-Proc SetAdjMain;

Dcl-Proc GetAdjMain;
  Dcl-Pi GetAdjMain Int(5);
    pCon Int(5) Value;
    pDim Int(5) Value;
  End-Pi;
  AdjIdx = (pCon * DepGraph.nDimensions) + pDim + 1;
  Return DepGraph.adj(AdjIdx);
End-Proc GetAdjMain;

///=====================================================================
/// FractureInline — BFS fracture (inlined for standalone)
///=====================================================================
Dcl-Proc FractureInline;
  Dcl-S SeedC   Int(5);
  Dcl-S CurNode Int(5);
  Dcl-S J       Int(5);
  Dcl-S CurBlock Int(5);
  Dcl-S K       Int(5);

  For SeedC = 1 to 8;
    VisitedC(SeedC) = *Off;
    VisitedD(SeedC) = *Off;
  EndFor;

  BlockCount = 0;
  LargestBlock = 0;

  For SeedC = 0 to (DepGraph.nConstraints - 1);
    If VisitedC(SeedC + 1) = *On;
      Iter;
    EndIf;

    BlockCount += 1;
    CurBlock = BlockCount;
    BlockTable.Block(CurBlock).cCount = 0;
    BlockTable.Block(CurBlock).dCount = 0;

    QueueFront = 0;
    QueueBack  = 0;
    QueueBack += 1;
    Queue(QueueBack) = SeedC;
    VisitedC(SeedC + 1) = *On;

    Dou QueueFront >= QueueBack;
      QueueFront += 1;
      CurNode = Queue(QueueFront);

      BlockTable.Block(CurBlock).cCount += 1;
      BlockTable.Block(CurBlock).constraintIdx(
          BlockTable.Block(CurBlock).cCount) = CurNode;

      For J = 0 to (DepGraph.nDimensions - 1);
        If GetAdjMain(CurNode: J) = 1;
          If VisitedD(J + 1) = *Off;
            VisitedD(J + 1) = *On;
            BlockTable.Block(CurBlock).dCount += 1;
            BlockTable.Block(CurBlock).dimensionIdx(
                BlockTable.Block(CurBlock).dCount) = J;
            // Explore constraint neighbors
            For K = 0 to (DepGraph.nConstraints - 1);
              If GetAdjMain(K: J) = 1 and VisitedC(K + 1) = *Off;
                VisitedC(K + 1) = *On;
                QueueBack += 1;
                Queue(QueueBack) = K;
              EndIf;
            EndFor;
          EndIf;
        EndIf;
      EndFor;
    EndDo;

    If BlockTable.Block(CurBlock).cCount > LargestBlock;
      LargestBlock = BlockTable.Block(CurBlock).cCount;
    EndIf;
  EndFor;
End-Proc FractureInline;

///=====================================================================
/// CoalesceInline — OR all block masks with per-constraint bit mapping
///=====================================================================
Dcl-Proc CoalesceInline;
  Dcl-S BIdx Int(5);
  Dcl-S CIdx Int(5);

  // First, assign block masks based on which constraints are violated
  For BIdx = 1 to BlockCount;
    BlockTable.Block(BIdx).errMask = 0;
    For CIdx = 1 to BlockTable.Block(BIdx).cCount;
      If ConstraintTable.Constraint(
          BlockTable.Block(BIdx).constraintIdx(CIdx) + 1).cViolated = *On;
        BlockTable.Block(BIdx).errMask = %BitOr(
            BlockTable.Block(BIdx).errMask:
            2 ** BlockTable.Block(BIdx).constraintIdx(CIdx));
      EndIf;
    EndFor;
  EndFor;

  // Coalesce via bitwise OR
  CoalescedMask = 0;
  For BIdx = 1 to BlockCount;
    CoalescedMask = %BitOr(CoalescedMask:
                           BlockTable.Block(BIdx).errMask);
  EndFor;
End-Proc CoalesceInline;
