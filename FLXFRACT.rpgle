///=====================================================================
/// FLXFRACT.rpgle — FRACTURE-COALESCE: Disjoint constraint decomposition
///
/// Fractures constraint systems into independent blocks via BFS on
/// the bipartite constraint-dimension dependency graph.
/// Coalescence via bitwise OR preserves zero false negatives.
///
/// THEOREM: If fracture correctly identifies connected components,
/// the union of all violations = OR of block error masks. QED.
///
/// RPG doesn't do recursion. BFS is iterative with explicit queue.
/// That forced iteration IS the architecture.
///=====================================================================

Ctl-Opt Main(Main) Nomain;

///---------------------------------------------------------------------
/// Work variables
///---------------------------------------------------------------------
Dcl-S WorkVal    Packed(7:0);

/Copy copybooks/FLXCONST
/Copy copybooks/FLXRESULT

///---------------------------------------------------------------------
/// Dependency graph: constraint × dimension adjacency matrix
/// Max 8 constraints × 8 dimensions = 64 cells
///---------------------------------------------------------------------
Dcl-Ds DepGraph Qualified;
  adj          Unsf Dim(64);       // Flat: adj[(i*8)+j] for row i, col j
  nConstraints Int(5) Inz(0);
  nDimensions  Int(5) Inz(0);
End-Ds;

Dcl-S AdjIdx     Int(5);  // Flat index into adj

///---------------------------------------------------------------------
/// Block table: connected components of the dependency graph
///---------------------------------------------------------------------
Dcl-S MaxBlocks  Int(5) Inz(8);
Dcl-S MaxPerBlock Int(5) Inz(8);

Dcl-Ds BlockTable Qualified;
  Block        Dim(8);
    constraintIdx Int(5) Dim(8);  // Constraint indices in this block
    dimensionIdx Int(5) Dim(8);  // Dimension indices in this block
    cCount       Int(5) Inz(0);  // Constraints in block
    dCount       Int(5) Inz(0);  // Dimensions in block
    errMask      Zoned(5:0) Inz(0); // Block-local error mask
End-Ds;

Dcl-S BlockCount   Int(5) Inz(0);
Dcl-S LargestBlock Int(5) Inz(0);
Dcl-S Speedup      Packed(5:2) Inz(1.00);

///---------------------------------------------------------------------
/// BFS queue (iterative — RPG doesn't recurse)
///---------------------------------------------------------------------
Dcl-S Queue       Int(5) Dim(32);  // Mixed constraint/dimension nodes
Dcl-S QueueFront  Int(5) Inz(0);
Dcl-S QueueBack   Int(5) Inz(0);
Dcl-S QueueItem   Int(5);

Dcl-S VisitedC    Ind Dim(8);     // Visited constraints
Dcl-S VisitedD    Ind Dim(8);     // Visited dimensions

///---------------------------------------------------------------------
/// Coalesced result
///---------------------------------------------------------------------
Dcl-S CoalescedMask Zoned(5:0) Inz(0);

///=====================================================================
/// MAIN — Self-test entry point
///=====================================================================
Dcl-Proc Main;
  Dcl-Pi *N;
  End-Pi;

  Dsply 'FLXFRACT — Flux Fracture Engine v1.0 (RPG IV)';
  Dsply '================================================';

  RunFractureTest();

  *InLR = *On;
End-Proc Main;

///=====================================================================
/// RunFractureTest — Test fracture and coalesce
///=====================================================================
Dcl-Proc RunFractureTest;
  Dsply 'Running fracture self-test...';

  // Setup: 4 constraints, 4 dimensions
  // Constraint 0: involves dim 0, 1  (temperature+pressure)
  // Constraint 1: involves dim 1, 2  (pressure+voltage)
  // Constraint 2: involves dim 3     (rpm — independent)
  // Constraint 3: involves dim 0     (temperature again)
  //
  // Expected blocks:
  //   Block 1: constraints {0,1,3} dims {0,1,2} — connected via dim 0,1
  //   Block 2: constraints {2}   dims {3}       — independent

  DepGraph.nConstraints = 4;
  DepGraph.nDimensions  = 4;

  // Clear adjacency
  For AdjIdx = 1 to 64;
    DepGraph.adj(AdjIdx) = 0;
  EndFor;

  // Constraint 1 (idx 0): dims 0, 1
  SetAdj(0: 0);
  SetAdj(0: 1);

  // Constraint 2 (idx 1): dims 1, 2
  SetAdj(1: 1);
  SetAdj(1: 2);

  // Constraint 3 (idx 2): dim 3
  SetAdj(2: 3);

  // Constraint 4 (idx 3): dim 0
  SetAdj(3: 0);

  // Fracture
  Fracture();

  If BlockCount = 2;
    Dsply '  PASS: Test 1 (2 blocks found)';
  Else;
    Dsply ('  FAIL: Test 1 (expected 2 blocks, got ' +
           %Char(BlockCount) + ')');
  EndIf;

  // Simulate constraint violations:
  // Block 1: constraints 0 and 3 violated (mask = 2^0 + 2^3 = 9)
  // Block 2: constraint 2 violated (mask = 2^2 = 4)
  If BlockCount >= 2;
    BlockTable.Block(1).errMask = 9;   // Constraints 0+3
    BlockTable.Block(2).errMask = 4;   // Constraint 2
  EndIf;

  // Coalesce
  Coalesce();

  // Coalesced mask should be 9 OR 4 = 13
  If CoalescedMask = 13;
    Dsply '  PASS: Test 2 (coalesced mask = 13)';
  Else;
    Dsply ('  FAIL: Test 2 (expected 13, got ' +
           %Char(CoalescedMask) + ')');
  EndIf;

  Dsply 'Fracture self-test complete.';
End-Proc RunFractureTest;

///=====================================================================
/// SetAdj — Set adjacency matrix cell (constraint i, dimension j)
/// Flat array: index = (i * nDimensions) + j + 1
///=====================================================================
Dcl-Proc SetAdj;
  Dcl-Pi SetAdj;
    pCon  Int(5) Value;
    pDim  Int(5) Value;
  End-Pi;

  AdjIdx = (pCon * DepGraph.nDimensions) + pDim + 1;
  DepGraph.adj(AdjIdx) = 1;
End-Proc SetAdj;

///=====================================================================
/// GetAdj — Get adjacency matrix cell
///=====================================================================
Dcl-Proc GetAdj;
  Dcl-Pi GetAdj Int(5);
    pCon  Int(5) Value;
    pDim  Int(5) Value;
  End-Pi;

  AdjIdx = (pCon * DepGraph.nDimensions) + pDim + 1;
  Return DepGraph.adj(AdjIdx);
End-Proc GetAdj;

///=====================================================================
/// Enqueue — Add item to BFS queue
///=====================================================================
Dcl-Proc Enqueue;
  Dcl-Pi Enqueue;
    pItem Int(5) Value;
  End-Pi;

  QueueBack += 1;
  If QueueBack <= %Elem(Queue);
    Queue(QueueBack) = pItem;
  EndIf;
End-Proc Enqueue;

///=====================================================================
/// Dequeue — Remove item from BFS queue, return -1 if empty
///=====================================================================
Dcl-Proc Dequeue;
  Dcl-Pi Dequeue Int(5);

  If QueueFront >= QueueBack;
    Return -1;
  EndIf;
  QueueFront += 1;
  Return Queue(QueueFront);
End-Proc Dequeue;

///=====================================================================
/// Fracture — BFS connected components on bipartite graph
/// RPG doesn't recurse. BFS with explicit queue. That IS the point.
///=====================================================================
Dcl-Proc Fracture;
  Dcl-S SeedC    Int(5);
  Dcl-S CurNode  Int(5);
  Dcl-S J        Int(5);
  Dcl-S CurBlock Int(5);
  Dcl-S IsConstraint Ind;
  Dcl-S NodeId  Int(5);

  // Clear visited flags
  For SeedC = 1 to 8;
    VisitedC(SeedC) = *Off;
    VisitedD(SeedC) = *Off;
  EndFor;

  BlockCount = 0;
  LargestBlock = 0;

  // Seed BFS from each unvisited constraint
  For SeedC = 0 to (DepGraph.nConstraints - 1);
    If VisitedC(SeedC + 1) = *On;
      Iter;
    EndIf;

    // Start new block
    BlockCount += 1;
    CurBlock = BlockCount;
    BlockTable.Block(CurBlock).cCount = 0;
    BlockTable.Block(CurBlock).dCount = 0;

    // Reset queue
    QueueFront = 0;
    QueueBack  = 0;

    // Enqueue seed constraint (positive = constraint, negative = dimension)
    Enqueue(SeedC);
    VisitedC(SeedC + 1) = *On;

    // BFS loop
    Dou QueueFront >= QueueBack;
      CurNode = Dequeue();
      If CurNode < 0;
        Leave;
      EndIf;

      // CurNode is a constraint index — explore its dimensions
      // Add constraint to block
      BlockTable.Block(CurBlock).cCount += 1;
      BlockTable.Block(CurBlock).constraintIdx(
          BlockTable.Block(CurBlock).cCount) = CurNode;

      // Find all dimensions this constraint involves
      For J = 0 to (DepGraph.nDimensions - 1);
        If GetAdj(CurNode: J) = 1;
          // Dimension J is involved
          If VisitedD(J + 1) = *Off;
            VisitedD(J + 1) = *On;
            // Add dimension to block
            BlockTable.Block(CurBlock).dCount += 1;
            BlockTable.Block(CurBlock).dimensionIdx(
                BlockTable.Block(CurBlock).dCount) = J;
            // Explore constraint neighbors of this dimension
            ExploreDim(J: CurBlock);
          EndIf;
        EndIf;
      EndFor;
    EndDo;

    // Track largest block
    If BlockTable.Block(CurBlock).cCount > LargestBlock;
      LargestBlock = BlockTable.Block(CurBlock).cCount;
    EndIf;
  EndFor;

  // Compute speedup potential
  If LargestBlock > 0;
    Speedup = DepGraph.nConstraints / LargestBlock;
  Else;
    Speedup = 1;
  EndIf;
End-Proc Fracture;

///=====================================================================
/// ExploreDim — Find all unvisited constraints connected to dimension
///=====================================================================
Dcl-Proc ExploreDim;
  Dcl-Pi ExploreDim;
    pDim      Int(5) Value;
    pBlock    Int(5) Value;
  End-Pi;

  Dcl-S K Int(5);

  For K = 0 to (DepGraph.nConstraints - 1);
    If GetAdj(K: pDim) = 1 and VisitedC(K + 1) = *Off;
      VisitedC(K + 1) = *On;
      Enqueue(K);
    EndIf;
  EndFor;
End-Proc ExploreDim;

///=====================================================================
/// Coalesce — OR all block error masks into coalesced result
/// Independent blocks → disjoint event spaces → OR preserves
/// zero false negatives. This is the theorem made operational.
///=====================================================================
Dcl-Proc Coalesce;
  Dcl-S BIdx Int(5);

  CoalescedMask = 0;
  For BIdx = 1 to BlockCount;
    CoalescedMask = %BitOr(CoalescedMask:
                           BlockTable.Block(BIdx).errMask);
  EndFor;
End-Proc Coalesce;
