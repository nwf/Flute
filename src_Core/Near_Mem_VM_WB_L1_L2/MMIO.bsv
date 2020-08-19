// Copyright (c) 2016-2020 Bluespec, Inc. All Rights Reserved.

package MMIO;

// ================================================================
// This module handles all load, store, and AMO ops for MMIO.
// - Loads and Stores go directly to mem
// - LR/SC are not supported: LR is treated like Load; SC always fails
// - AMO ops do a read-modify-write across the fabric
//    (CAVEAT: there is no 'locking' of the location at memory during
//     the operation, so it may not really be atomic.)

// ================================================================
// BSV lib imports

import Vector       :: *;
import FIFOF        :: *;
import GetPut       :: *;
import ClientServer :: *;

// ----------------
// BSV additional libs

import Cur_Cycle     :: *;
import GetPut_Aux    :: *;

// ================================================================
// Project imports

import ISA_Decls        :: *;
import Cache_Decls      :: *;
import MMU_Cache_Common :: *;

// ================================================================

export  MMIO_IFC (..),  mkMMIO;

// ================================================================
// MODULE INTERFACE

interface MMIO_IFC;
   method Action req (MMU_Cache_Req mmu_cache_req);
   method Action start (PA pa);

   method Tuple3 #(Bool, CWord, CWord) result;

   // ----------------
   // MMIO interface facing memory

   interface Client #(Single_Req, Single_Rsp) mmio_client;
endinterface

// ================================================================

typedef enum {FSM_IDLE,
	      FSM_START,
	      FSM_READ_RSP} FSM_State
deriving (Bits, Eq, FShow);

// ================================================================
// MODULE IMPLEMENTATION

(* synthesize *)
module mkMMIO #(parameter Bit #(3)  verbosity)
              (MMIO_IFC);

   Reg #(FSM_State) rg_fsm_state <- mkReg (FSM_IDLE);

   // Copy of the CPU's request (same as in parent MMU_Cache)
   Reg #(MMU_Cache_Req) rg_req <- mkRegU;
   Reg #(PA)            rg_pa  <- mkRegU;

   // Results
   Reg #(Bool)  rg_err          <- mkReg (False);
   Reg #(CWord) rg_ld_val       <- mkReg (0);
   Reg #(CWord) rg_final_st_val <- mkReg (0);

   // ----------------
   // Memory interface

   FIFOF #(Single_Req)  f_single_reqs  <- mkFIFOF;
   FIFOF #(Single_Rsp)  f_single_rsps  <- mkFIFOF;

   // ----------------------------------------------------------------
   // Help-function for single-writes to mem

   function Action fa_mem_single_write (CWord st_value);
      action
	 // Lane-align the outgoing data
	 Bit #(6) shamt_bits = { rg_pa [2:0], 3'b000 };
	 CWord    data       = (st_value << shamt_bits);

	 let req = Single_Req {is_read:   False,
			       addr:      zeroExtend (rg_pa),
			       width_code: rg_req.width_code,
			       data:      tuple2 (0, zeroExtend (data))}; // XXX TODO FIXME
	 f_single_reqs.enq (req);
      endaction
   endfunction

   // ----------------------------------------------------------------
   // Issue read request to mem for load, LR, and AMO Read-Modify-Write
   // (all ops other than store and SC)

   rule rl_read_req ((rg_fsm_state == FSM_START)
		     && (rg_req.op != CACHE_ST)
		     && (! fv_is_AMO_SC (rg_req)));
      if (verbosity >= 1)
	 $display ("%0d: %m.rl_read_req: width_code %0h vaddr %0h  paddr %0h",
		   cur_cycle, rg_req.width_code, rg_req.va, rg_pa);
      let req = Single_Req {is_read:   True,
			    addr:      zeroExtend (rg_pa),
			    width_code: rg_req.width_code,
			    data:      ?};
      f_single_reqs.enq (req);
      rg_fsm_state <= FSM_READ_RSP;
   endrule

   // ----------------------------------------------------------------
   // Receive read response from mem for Load, LR and AMO Read-Modify-Write
   // (all ops other than store and SC)

   rule rl_read_rsp (rg_fsm_state == FSM_READ_RSP);
      let rsp <- pop (f_single_rsps);

      if (verbosity >= 1) begin
	 $display ("%0d: %m.rl_read_rsp: vaddr %0h  paddr %0h", cur_cycle, rg_req.va, rg_pa);
	 $display ("    ", fshow (rsp));
      end

      // Bus error
      if (! rsp.ok) begin
	 if (verbosity >= 1)
	    $display ("    MEM_RSP_ERR");

	 rg_err       <= True;
	 rg_fsm_state <= FSM_IDLE;
      end

      // Successful read
      else begin
	 CWord ld_val_bits = truncate (tpl_2 (rsp.data)); // XXX TODO FIXME

	 // Loads and LR
	 if ((rg_req.op == CACHE_LD) || fv_is_AMO_LR (rg_req)) begin
	    let ld_val = fv_extend (rg_req.width_code, rg_req.is_unsigned, ld_val_bits);
	    rg_ld_val <= ld_val;
	    if (verbosity >= 1)
	      $display ("    Load or LR: width_code %0h ld_val %0h", rg_req.width_code, ld_val);
	 end
`ifdef ISA_A
	 // AMO read-modify-write
	 else begin
	    match {.final_ld_val,
		   .final_st_val} = fn_amo_op (rg_req.width_code,
					       rg_req.amo_funct5,
                           rg_req.va,
					       tuple2 (0, zeroExtend (ld_val_bits)), // XXX TODO FIXME
					       rg_req.st_value);
	    // Write back final_st_val
	    fa_mem_single_write (truncate (tpl_2 (final_st_val))); // XXX TODO FIXME
	    if (verbosity >= 1) begin
	      $display ("    AMO: width_code %0d  f7 %0h  ld_val %0h st_val %0h",
			rg_req.width_code, rg_req.amo_funct5, ld_val_bits, rg_req.st_value);
	      $display ("    => final_ld_val %0h final_st_val %0h",
			final_ld_val, final_st_val);
	    end
	    rg_ld_val       <= truncate (tpl_2 (final_ld_val)); // XXX TODO FIXME
	    rg_final_st_val <= truncate (tpl_2 (final_st_val)); // XXX TODO FIXME;
	 end
`endif
	 rg_fsm_state    <= FSM_IDLE;
      end
   endrule

   // ----------------------------------------------------------------
   // Store requests

   rule rl_write_req ((rg_fsm_state == FSM_START) && (rg_req.op == CACHE_ST));
      if (verbosity >= 1)
	 $display ("%0d: %m.rl_write_req; width_code %0h  vaddr %0h  paddr %0h  cword %0h",
		   cur_cycle, rg_req.width_code, rg_req.va, rg_pa, rg_req.st_value);

      CWord data = fv_to_byte_lanes (zeroExtend (rg_pa), rg_req.width_code, truncate (tpl_2 (rg_req.st_value))); // XXX TODO FIXME

      fa_mem_single_write (data);

      rg_final_st_val <= truncate (tpl_2 (rg_req.st_value)); // XXX TODO FIXME
      rg_fsm_state    <= FSM_IDLE;

      if (verbosity >= 2)
	 $display ("    goto MMIO_DONE");
   endrule

   // ----------------------------------------------------------------
   // Memory-mapped I/O AMO_SC requests. Always fail (and never do the write)

   rule rl_AMO_SC ((rg_fsm_state == FSM_START) && fv_is_AMO_SC (rg_req));

      rg_ld_val    <= 1;    // 1 is LR/SC failure value
      rg_fsm_state <= FSM_IDLE;

      if (verbosity >= 1) begin
	 $display ("%0d: %m.rl_AMO_SC; width_code %0h  vaddr %0h  paddr %0h  st_value %0h",
		   cur_cycle, rg_req.width_code, rg_req.va, rg_pa, rg_req.st_value);
	 $display ("    FAIL due to I/O address.");
	 $display ("    goto MMIO_DONE");
      end
   endrule

   // ================================================================
   // INTERFACE

   method Action req (MMU_Cache_Req mmu_cache_req);
      rg_req <= mmu_cache_req;
      rg_err <= False;
   endmethod

   method Action start (PA pa);
      rg_pa        <= pa;
      rg_fsm_state <= FSM_START;
   endmethod

   method result () if (rg_fsm_state == FSM_IDLE);
      return tuple3 (rg_err, rg_ld_val, rg_final_st_val);
   endmethod

   // ----------------
   // Memory interface (for refills, writebacks)

   interface Client mmio_client = toGPClient (f_single_reqs, f_single_rsps);
endmodule

// ================================================================

endpackage
