// ---------------------------------------------------------------------------
// Lightweight self-check helpers shared by all testbenches.
//
// The counters are declared unguarded: every module that includes this file
// needs its own pair. Only the macros are guarded, because xsim compiles all
// testbenches into a single compilation unit where macros persist across
// files.
// ---------------------------------------------------------------------------

integer tb_errors = 0;
integer tb_checks = 0;

`ifndef TB_CHECK_SVH
`define TB_CHECK_SVH

// Boolean check.
`define CHK(NAME, COND) \
    begin \
        tb_checks = tb_checks + 1; \
        if (!(COND)) begin \
            tb_errors = tb_errors + 1; \
            $display("  FAIL [%0d]: %s", tb_checks, NAME); \
        end \
    end

// Equality check with value dump on mismatch (=== so X/Z are caught).
`define CHK_EQ(NAME, GOT, EXP) \
    begin \
        tb_checks = tb_checks + 1; \
        if ((GOT) !== (EXP)) begin \
            tb_errors = tb_errors + 1; \
            $display("  FAIL [%0d]: %s  got=%h exp=%h", tb_checks, NAME, (GOT), (EXP)); \
        end \
    end

// Final verdict. Prints a machine-parsable sentinel the Makefile greps for.
`define TB_SUMMARY(NAME) \
    begin \
        if (tb_errors == 0) begin \
            $display("[%s] TEST PASSED (%0d checks)", NAME, tb_checks); \
        end else begin \
            $display("[%s] TEST FAILED (%0d of %0d checks failed)", NAME, tb_errors, tb_checks); \
        end \
        $finish; \
    end

`endif
