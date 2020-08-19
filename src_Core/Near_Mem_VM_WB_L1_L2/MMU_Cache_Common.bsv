// Copyright (c) 2016-2020 Bluespec, Inc. All Rights Reserved.

package MMU_Cache_Common;

// ================================================================
// Types etc. shared by multiple modules in MMU_Cache complex.

// ================================================================
// BSV lib imports

import Vector :: *;

// ================================================================
// Project imports

import ISA_Decls   :: *;
import Fabric_Defs :: *;
import Cache_Decls :: *;

// ================================================================
// Near_Mem opcodes

typedef enum {  CACHE_LD
	      , CACHE_ST
`ifdef ISA_A
	      , CACHE_AMO
`endif
   } CacheOp
deriving (Bits, Eq, FShow);

// ================================================================
// Requests from CPU to MMU_Cache

typedef TDiv#(Bits_per_CWord, CLEN) Cache_Cap_Tag_Width;
typedef Tuple2#(Bit#(Cache_Cap_Tag_Width), CWord) Cache_Entry;

typedef struct {CacheOp    op;
		Bit #(3)   width_code;
        Bool is_unsigned;
        Bool is_cap;
		WordXL     va;
		Tuple2 #(Bool, CWord) st_value;
`ifdef ISA_A
		Bit #(5)   amo_funct5;
`endif
`ifdef ISA_PRIV_S
		// The following are needed/used for VM translation only
		Priv_Mode  priv;
		Bit #(1)   sstatus_SUM;
		Bit #(1)   mstatus_MXR;
		WordXL     satp;           // = { VM_Mode, ASID, PPN_for_page_table }
`endif
   } MMU_Cache_Req
deriving (Bits, FShow);

function Fmt fshow_MMU_Cache_Req (MMU_Cache_Req req);
   Fmt fmt = $format ("MMU_Cache_Req{", fshow (req.op), " width_code %3b", req.width_code);

`ifdef ISA_A
   if (req.op == CACHE_AMO) begin
      fmt = fmt + $format (" ", fshow_f5_AMO_op (req.amo_funct5));
      //fmt = fmt + $format (" aqrl %2b", req.amo_funct7 [1:0]);
   end
`endif
   fmt = fmt + $format (" va %0h", req.va);

   Bool show_st_val = (req.op == CACHE_ST);
`ifdef ISA_A
   if ((req.op == CACHE_AMO) && (! fv_is_AMO_LR (req)))
      show_st_val = True;
`endif
   if (show_st_val) fmt = fmt + $format (" st_val %0h", req.st_value);

`ifdef ISA_PRIV_S
   fmt = fmt + $format (" priv %0d sstatus_SUM %0d mstatus_MXR %0d satp %0h",
			req.priv, req.sstatus_SUM, req.mstatus_MXR, req.satp);
`endif
   fmt = fmt + $format ("}");
   return fmt;
endfunction

// ================================================================
// Final result of VM translation.

// There are two versions below: the actual version when we support S
// Privilege Mode and a 'dummy' version when we don't.

`ifdef ISA_PRIV_S

typedef enum { VM_XLATE_OK, VM_XLATE_TLB_MISS, VM_XLATE_EXCEPTION } VM_Xlate_Outcome
deriving (Bits, Eq, FShow);

typedef struct {
   VM_Xlate_Outcome  outcome;
   Bool              allow_cap;     // whether we will be allowed to load a cap
   PA                pa;            // phys addr, if VM_XLATE_OK
   Exc_Code          exc_code;      // if VM_XLATE_EXC

   // Information needed to write back updated PTE (A,D bits) to TLB and mem
   Bool              pte_modified;  // if VM_XLATE_OK and pte's A or D bits were modified
   PTE               pte;           // PTE (with possible A,D updates)
   Bit #(2)          pte_level;     // Level of leaf PTE for this translation
   PA                pte_pa;        // PA from which PTE was loaded
   } VM_Xlate_Result
deriving (Bits, FShow);

function Fmt fshow_VM_Xlate_Result (VM_Xlate_Result  r);
   Fmt fmt = $format ("VM_Xlate_Result{");
   fmt = fmt + fshow (r.outcome);
   if (r.outcome == VM_XLATE_OK) begin
      fmt = fmt + $format (" pa:%0h", r.pa);
      if (r.pte_modified)
	 fmt = fmt + $format (" pte (modified) %0h", r.pte);
   end
   else if (r.outcome == VM_XLATE_TLB_MISS) begin
   end
   else // exception
      fmt = fmt + $format (" ", fshow_trap_Exc_Code (r.exc_code));
   fmt = fmt + $format ("}");
   return fmt;
endfunction

// ----------------

`else // of ifdef ISA_PRIV_S

typedef enum { VM_XLATE_OK } VM_Xlate_Outcome
deriving (Bits, Eq, FShow);

typedef struct {
   VM_Xlate_Outcome   outcome;
   PA                 pa;            // phys addr, if VM_XLATE_OK
   } VM_Xlate_Result
deriving (Bits, FShow);

function Fmt fshow_VM_Xlate_Result (VM_Xlate_Result  r);
   Fmt fmt = $format ("VM_Xlate_Result{VM_XLATE_OK, pa:%0h}", r.pa);
   return fmt;
endfunction

`endif

// ================================================================
// Construct a PA from fields

function PA fn_CTag_and_CSet_to_CLine_PA (CTag  tag, CSet_in_Cache  cset);
   Byte_in_CLine  byte_in_cline = 0;
   return { tag, cset, byte_in_cline };
endfunction

// ================================================================
// Check if addr is aligned

function Bool fn_is_aligned (Bit #(3) width_code, Bit #(n) addr);
   return (    (width_code == 3'b000)                                // B
	   || ((width_code == 3'b001) && (addr [0] == 1'b0))         // H
	   || ((width_code == 3'b010) && (addr [1:0] == 2'b00))      // W
	   || ((width_code == 3'b011) && (addr [2:0] == 3'b000))     // D
	   || ((width_code == 3'b100) && (addr [3:0] == 4'b0000))    // Q
	   );
endfunction

// ================================================================
// Convert width of an address from PA to Fabric_Addr

function Fabric_Addr fv_PA_to_Fabric_Addr (PA pa);
   Bit #(TAdd #(Wd_Addr, PA_sz)) fa = zeroExtend (pa);
   Integer hi = valueOf (Wd_Addr) - 1;
   return fa [hi:0];
endfunction

// ================================================================
// Classify AMO ops into LR, SC and the rest (read-modify-write ops)

function Bool fv_is_AMO_LR (MMU_Cache_Req req);
`ifdef ISA_A
   return ((req.op == CACHE_AMO) && (req.amo_funct5 == f5_AMO_LR));
`else
   return False;
`endif
endfunction

function Bool fv_is_AMO_SC (MMU_Cache_Req req);
`ifdef ISA_A
   return ((req.op == CACHE_AMO) && (req.amo_funct5 == f5_AMO_SC));
`else
   return False;
`endif
endfunction

function Bool fv_is_AMO_RMW (MMU_Cache_Req req);
`ifdef ISA_A
   return ((req.op == CACHE_AMO)
	   && (req.amo_funct5 != f5_AMO_LR)
	   && (req.amo_funct5 != f5_AMO_SC));
`else
   return False;
`endif
endfunction

// ================================================================
// Cache-line states (also used in coherence protocol): MESI

typedef enum { META_INVALID, META_SHARED, META_EXCLUSIVE, META_MODIFIED } Meta_State
deriving (Bits, Eq);

instance FShow #(Meta_State);
   function Fmt fshow (Meta_State s);
      Fmt fmt = $format ("Meta_State_UNKNOWN");
      case (s)
	 META_INVALID:   $format ("INVALID");
	 META_SHARED:    $format ("SHARED");
	 META_EXCLUSIVE: $format ("EXCLUSIVE");
	 META_MODIFIED:  $format ("MODIFIED");
      endcase
   endfunction
endinstance

instance Ord #(Meta_State);
   function Bool \< (Meta_State x, Meta_State y)          = (pack (x) < pack (y));
   function Bool \<= (Meta_State x, Meta_State y)         = (pack (x) <= pack (y));
   function Bool \> (Meta_State x, Meta_State y)          = (pack (x) > pack (y));
   function Bool \>= (Meta_State x, Meta_State y)         = (pack (x) >= pack (y));
   function Ordering compare (Meta_State x, Meta_State y) = compare (pack (x), pack (y));
   function Meta_State min (Meta_State x, Meta_State y)   = ((pack (x) <= pack (y)) ? x : y);
   function Meta_State max (Meta_State x, Meta_State y)   = ((pack (x) <= pack (y)) ? y : x);
endinstance

// ================================================================
// Requests from L1 to next-level cache/memory, and responses
// For now: address is line-aligned; data starts from offset 0.
// TODO: 'wrapping' bursts, starting with actual line-offset of 'addr'

// L1_to_L2_Req corresponds to L2's CRqMsg

typedef struct {
   Bit #(64)   addr;
   Meta_State  from_state;
   Meta_State  to_state;       // Upgrade requested
   Bool        can_up_to_E;
   // Bool       is_read;    // TODO DELETE
   // CLine      cline;      // TODO DELETE For requests where is_read is False (i.e., write request)
   } L1_to_L2_Req
deriving (Bits, FShow);

function Fmt fshow_L1_to_L2_Req (L1_to_L2_Req  req);
   Fmt fmt = $format ("L1_to_L2_Req {%0h", req.addr);
   fmt = fmt + $format (" ", fshow (req.from_state), "->", fshow (req.to_state));
   if (req.can_up_to_E)
      fmt = fmt + $format (" can_up_to_E");
   fmt = fmt + $format ("}");
   return fmt;
endfunction

// L2_to_L1_Rsp corresponds to L2's PRqRsMsg.PRs

typedef struct {
   Bit #(64)       addr;
   Meta_State      to_state;   // Upgraded state
   Maybe #(Vector #(CWords_per_CLine, Cache_Entry)) m_cline;    // possible write-back data
   // id                       // Future (when L1 becomes non-blocking, out-of-order

   // Bool       ok;       // TODO DELETE
   // CLine      cline;    // TODO DELETE For requests where is_read is True (i.e., read request)
   } L2_to_L1_Rsp
deriving (Bits, FShow);

function Fmt fshow_L2_to_L1_Rsp (L2_to_L1_Rsp rsp);
   Fmt fmt = $format ("L2_to_L1_Rsp %0h -> ", rsp.addr, fshow (rsp.to_state));
   if (rsp.m_cline matches tagged Valid .cline) begin
      for (Integer j = 0; j < cwords_per_cline; j = j + 1)
	 fmt = fmt + $format ("\n        [%0d]  ", j, fshow (cline [j]));
   end
   else
      fmt = fmt + $format (" <no line>");
   return fmt;
endfunction

// ================================================================
// Requests from next-level cache/memory to L1, and responses
// These are downgrade requests (M/E/S -> S/I)
// If downgrading from M, response is write-back cache line

// L2_to_L1_Req corresponds to L2's PRqRsMsg.PRq

typedef struct {
   Bit #(64)   addr;
   Meta_State  to_state;    // Downgrade demanded
   // id                    // TODO: Future (when L1 becomes non-blocking, out-of-order
   } L2_to_L1_Req
deriving (Bits, FShow);

function Fmt fshow_L2_to_L1_Req (L2_to_L1_Req  req);
   Fmt fmt = $format ("L2_to_L1_Req {%0h", req.addr);
   fmt = fmt + $format ("->", fshow (req.to_state));
   fmt = fmt + $format ("}");
   return fmt;
endfunction

// L1_to_L2_Rsp corresponds to L2's CRsMsg

typedef struct {
   Bit #(64)       addr;
   Meta_State      to_state;    // Downgrade result
   Maybe #(Vector #(CWords_per_CLine, Cache_Entry)) m_cline;
   } L1_to_L2_Rsp
deriving (Bits, FShow);

function Fmt fshow_L1_to_L2_Rsp (L1_to_L2_Rsp rsp);
   Fmt fmt = $format ("L1_to_L2_Rsp %0h -> ", rsp.addr, fshow (rsp.to_state));
   if (rsp.m_cline matches tagged Valid .cline) begin
      for (Integer j = 0; j < cwords_per_cline; j = j + 1)
	 fmt = fmt + $format ("\n        [%0d]  ", j, fshow (cline [j]));
   end
   else
      fmt = fmt + $format (" <no line>");
   return fmt;
endfunction

// ================================================================
// Requests and responses between:
//     MMIO <-> MMU_Cache_AXI4_Adapter

// Single requests are from MMIO for 1, 2, 4 or 8 bytes.
typedef struct {
   Bool        is_read;
   Bit #(64)   addr;
   Bit #(3)    width_code;   // 2'b00=1 (B), 01=2 (H), 10=4 (W), 11=8 (D) bytes
   Cache_Entry data;         // For requests where is_read is False (i.e., write request)
   } Single_Req
deriving (Bits, FShow);

// Response (for a Single_Req write-request, there's no response, i.e., 'fire-and-forget')

typedef struct {
   Bool         ok;
   Cache_Entry data;         // For requests where is_read is True (i.e., read request)
   } Single_Rsp
deriving (Bits, FShow);

// ================================================================
// Functions to/from lsb-justified data to fabric-lane-aligned data

function Bit #(n) fv_size_code_to_mask (Bit #(3) width_code) =
   ~(~0 << (1 << (width_code + 3)));

//function Bit #(128) fv_size_code_to_mask (Bit #(3) width_code);
//   Bit #(128) mask = case (width_code)
//                        3'b000: 'h_0000_0000_0000_0000_0000_0000_0000_00FF;
//                        3'b001: 'h_0000_0000_0000_0000_0000_0000_0000_FFFF;
//                        3'b010: 'h_0000_0000_0000_0000_0000_0000_FFFF_FFFF;
//                        3'b011: 'h_0000_0000_0000_0000_FFFF_FFFF_FFFF_FFFF;
//                        3'b100: 'h_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF;
//                     endcase;
//   return mask;
//endfunction


function Bit #(n) fv_to_byte_lanes (Bit #(64) addr, Bit #(3) width_code, Bit #(n) data);
   Bit #(n) data1 = (data & fv_size_code_to_mask (width_code));

   Bit #(7)  shamt = { addr [3:0], 3'b0 };
   Bit #(n) data2 = (data1 << shamt);
   return data2;
endfunction

function Bit #(n) fv_from_byte_lanes (Bit #(64)  addr,
				       Bit #(3)  width_code,
				       Bit #(n)  data);
   Bit #(7)  shamt = { addr [3:0], 3'b0 };
   Bit #(n) data1 = (data >> shamt);

   return (data1 & fv_size_code_to_mask (width_code));
endfunction

function Bit #(n) fv_extend (Bit #(3) width_code, Bool is_unsigned, Bit #(n) data);
   Bit #(n) mask     = fv_size_code_to_mask (width_code);
   let sign_bit = data [(1 << (width_code + 3))-1];
   return (!is_unsigned && (sign_bit == 1'b1)) ? data | (~ mask) // sign extend
                                               : data & mask;    // zero extend

endfunction

// ================================================================
// Extract bytes from raw word read from near-mem.
// The bytes of interest are offset according to LSBs of addr.
// Arguments:
//  - a RISC-V LD/ST f3 value (encoding LB, LH, LW, LD, LBU, LHU, LWU)
//  - a byte-address
//  - a load-word (loaded from cache/mem)
// result:
//  - word with correct byte(s) shifted into LSBs and properly extended
function Tuple2#(Bool, Bit #(128)) fn_extract_and_extend_bytes (Bit #(3) f3, Bool is_unsigned, WordXL byte_addr, Cache_Entry word128_tagged);
   Bit #(64)  result_lo  = 0;
   Bit #(64)  result_hi  = 0;
   Bit #(4)  addr_lsbs = byte_addr [3:0];

   Bool tag = False;
   Bit #(128) word128 = tpl_2(word128_tagged);

   let u_s_extend = is_unsigned ? zeroExtend : signExtend;

   case (f3)
      0: case (addr_lsbs)
		'h0: result_lo = u_s_extend (word128 [ 7: 0]);
		'h1: result_lo = u_s_extend (word128 [15: 8]);
		'h2: result_lo = u_s_extend (word128 [23:16]);
		'h3: result_lo = u_s_extend (word128 [31:24]);
		'h4: result_lo = u_s_extend (word128 [39:32]);
		'h5: result_lo = u_s_extend (word128 [47:40]);
		'h6: result_lo = u_s_extend (word128 [55:48]);
		'h7: result_lo = u_s_extend (word128 [63:56]);
		'h8: result_lo = u_s_extend (word128 [71:64]);
		'h9: result_lo = u_s_extend (word128 [79:72]);
		'ha: result_lo = u_s_extend (word128 [87:80]);
		'hb: result_lo = u_s_extend (word128 [95:88]);
		'hc: result_lo = u_s_extend (word128 [103:96]);
		'hd: result_lo = u_s_extend (word128 [111:104]);
		'he: result_lo = u_s_extend (word128 [119:112]);
		'hf: result_lo = u_s_extend (word128 [127:120]);
	     endcase

      1: case (addr_lsbs)
		'h0: result_lo = u_s_extend (word128 [15: 0]);
		'h2: result_lo = u_s_extend (word128 [31:16]);
		'h4: result_lo = u_s_extend (word128 [47:32]);
		'h6: result_lo = u_s_extend (word128 [63:48]);
		'h8: result_lo = u_s_extend (word128 [79:64]);
		'ha: result_lo = u_s_extend (word128 [95:80]);
		'hc: result_lo = u_s_extend (word128 [111:96]);
		'he: result_lo = u_s_extend (word128 [127:112]);
	     endcase

      2: case (addr_lsbs)
		'h0: result_lo = u_s_extend (word128 [31: 0]);
		'h4: result_lo = u_s_extend (word128 [63:32]);
		'h8: result_lo = u_s_extend (word128 [95:64]);
		'hc: result_lo = u_s_extend (word128 [127:96]);
	     endcase

      3: case (addr_lsbs)
		'h0: begin
           result_lo = u_s_extend (word128 [63:0]);
`ifdef ISA_CHERI
           if (valueOf(CLEN) == 64) tag = tpl_1(word128_tagged)[0] == 1'b1;
`endif
         end
		'h8: begin
           result_lo = u_s_extend (word128 [127:64]);
`ifdef ISA_CHERI
           if (valueOf(CLEN) == 64) tag = tpl_1(word128_tagged)[1] == 1'b1;
`endif
         end
	     endcase

      4: begin
            result_lo = word128[63:0];
            result_hi = word128[127:64];
`ifdef ISA_CHERI
            tag = tpl_1(word128_tagged)[0] == 1'b1;
`endif
         end
   endcase
   return tuple2(tag, {result_hi, result_lo});
endfunction

// ================================================================
// Extract bytes from word read from fabric.
// The bytes of interest are already in the LSBs of 'word',
// they just have to be suitably extended.
// Arguments:
//  - a RISC-V LD/ST f3 value (encoding LB, LH, LW, LD, LBU, LHU, LWU)
//  - a byte-address
//  - a load-word (loaded from fabric)
// result:
//  - word with correct byte(s), properly extended.

function Bit #(64) fn_extend_bytes (Bit #(3) f3, Bit #(64) word64);
   Bit #(64) result = 0;
   case (f3)
      f3_LB:  result = signExtend (word64 [ 7: 0]);
      f3_LBU: result = zeroExtend (word64 [ 7: 0]);

      f3_LH:  result = signExtend (word64 [15: 0]);
      f3_LHU: result = zeroExtend (word64 [15: 0]);

      f3_LW:  result = signExtend (word64 [31: 0]);
      f3_LWU: result = zeroExtend (word64 [31: 0]);

      f3_LD:  result = word64;
   endcase

   return result;
endfunction

// ================================================================
// ALU for AMO ops.
// Returns the value to be stored back to mem.

`ifdef ISA_A
function Tuple2 #(Tuple2#(Bool, Bit #(128)),
		  Tuple2 #(Bool, Bit#(128))) fn_amo_op (
		                        Bit #(3)   funct3,    // encodes data size (.W or .D)
					Bit #(5)   funct5,    // encodes the AMO op
					WordXL     addr,      // lsbs indicate which 32b W in 64b D (.W)
					Cache_Entry ld_val,   // value loaded from mem
					Tuple2#(Bool, Bit #(128)) st_val);   // Value from CPU reg Rs2
   let extracted_q1 = fn_extract_and_extend_bytes(funct3, False, addr, ld_val);
   Bit #(128) q1    = tpl_2(extracted_q1);
   Bit #(128) q2    = tpl_2(st_val);
   Bit #(64) w1     = truncate(q1);
   Bit #(64) w2     = truncate(q2);
   Int #(64) i1     = unpack (w1);    // Signed, for signed ops
   Int #(64) i2     = unpack (w2);    // Signed, for signed ops
   if (funct3 == f3_AMO_W) begin
      w1 = zeroExtend (w1 [31:0]);
      w2 = zeroExtend (w2 [31:0]);
      i1 = unpack (signExtend (w1 [31:0]));
      i2 = unpack (signExtend (w2 [31:0]));
   end
   // new_st_val is new value to be stored back to mem (w1 op w2)
   Bit#(128) new_st_val_128;
   Bool new_st_tag = False;
   Bool old_ld_tag = False;
   if (funct3 == f3_AMO_CAP) begin
      new_st_val_128 = q2;
      new_st_tag = tpl_1(st_val);
      old_ld_tag = tpl_1 (extracted_q1);
   end else begin
     Bit #(64) new_st_val_64 = ?;
     case (funct5)
        f5_AMO_SWAP: new_st_val_64 = w2;
        f5_AMO_ADD:  new_st_val_64 = pack (i1 + i2);
        f5_AMO_XOR:  new_st_val_64 = w1 ^ w2;
        f5_AMO_AND:  new_st_val_64 = w1 & w2;
        f5_AMO_OR:   new_st_val_64 = w1 | w2;
        f5_AMO_MINU: new_st_val_64 = ((w1 < w2) ? w1 : w2);
        f5_AMO_MAXU: new_st_val_64 = ((w1 > w2) ? w1 : w2);
        f5_AMO_MIN:  new_st_val_64 = ((i1 < i2) ? w1 : w2);
        f5_AMO_MAX:  new_st_val_64 = ((i1 > i2) ? w1 : w2);
     endcase

     if (funct3 == f3_AMO_W)
       new_st_val_64 = zeroExtend (new_st_val_64 [31:0]);

     new_st_val_128 = zeroExtend(new_st_val_64);
   end

   return tuple2 (tuple2(old_ld_tag, q1),
                  tuple2(new_st_tag, zeroExtend(new_st_val_128)));
endfunction: fn_amo_op
`endif

endpackage
