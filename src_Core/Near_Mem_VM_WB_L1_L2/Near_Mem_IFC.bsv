// Copyright (c) 2016-2020 Bluespec, Inc. All Rights Reserved.

// Near_Mem_IFC encapsulates the MMU and L1 cache.
// It is 'near' the CPU (1-cycle access in common case).

// On the CPU side it directly services instruction fetches and DMem
// reads and writes.

// On the Fabric side it has two Master sub-interfaces.
// One master sub-interface is used for instruction-memory access.
// The other master sub-interface is used for data-memory and I/O access.

// It can have various implementations:
//  - As an almost empty pass-through to the fabric
//  - As a cache (unified or separate I- and D-)
//        Fabric-side Server interface is not used (no back door to caches)
//  - As a TCM (Tightly-Coupled Memory)
//        Fabric-side IMem Client is not used (all fabric traffic is data or I/O mem)

package Near_Mem_IFC;

// ================================================================
// BSV lib imports

import GetPut       :: *;
import ClientServer :: *;

// ----------------
// BSV additional libs

import Cur_Cycle :: *;

// ================================================================
// Project imports

import ISA_Decls :: *;

import MMU_Cache_Common :: *;
import AXI4             :: *;
import Fabric_Defs      :: *;
import Cache_Decls      :: *;

`ifdef INCLUDE_DMEM_SLAVE
import AXI4_Lite        :: *;
`endif

// ================================================================
// Near-Mem parameters (statically defined)

// Id of requestor for 'coherent DMA' port into (optional) L2 cache

typedef 6   Wd_Id_Dma;
typedef 64  Wd_Addr_Dma;
typedef 512 Wd_Data_Dma;
typedef 0   Wd_AW_User_Dma;
typedef 0   Wd_W_User_Dma;
typedef 0   Wd_B_User_Dma;
typedef 0   Wd_AR_User_Dma;
typedef 0   Wd_R_User_Dma;

// ================================================================

interface Near_Mem_IFC;
   // Reset
   interface Server #(Token, Token) server_reset;

   // ----------------
   // IMem

   // CPU side
   interface IMem_IFC  imem;

   // Fabric side
   interface AXI4_Master #( Wd_MId, Wd_Addr, Wd_Data
                          , Wd_AW_User, Wd_W_User, Wd_B_User
                          , Wd_AR_User, Wd_R_User) imem_master;

   // ----------------
   // DMem

   // CPU side
   interface DMem_IFC  dmem;

   // Fabric side
   //interface AXI4_Master #( Wd_MId_2x3, Wd_Addr, Wd_Data
   //                       , Wd_AW_User, Wd_W_User, Wd_B_User
   //                       , Wd_AR_User, Wd_R_User) mem_master;
   interface Near_Mem_Fabric_IFC mem_master;

   // ----------------------------------------------------------------
   // Optional AXI4-Lite DMem slave interface

`ifdef INCLUDE_DMEM_SLAVE
   interface AXI4_Lite_Slave_IFC #(Wd_Addr, Wd_Data, Wd_User) dmem_slave;
`endif

   // ----------------
   // Fences

   interface Server #(Token, Token) server_fence_i;

   interface Server #(Fence_Ordering, Token) server_fence;

`ifdef ISA_PRIV_S
   interface Server #(Token, Token) sfence_vma_server;
`endif

   // ----------------------------------------------------------------
   // Interface to 'coherent DMA' port of optional L2 cache

   interface AXI4_Slave #( Wd_Id_Dma, Wd_Addr_Dma, Wd_Data_Dma
                         , Wd_AW_User_Dma, Wd_W_User_Dma, Wd_B_User_Dma
                         , Wd_AR_User_Dma, Wd_R_User_Dma)  dma_server;

   // ----------------------------------------------------------------
   // Misc. control and status

   // ----------------
   // For ISA tests: watch memory writes to <tohost> addr

`ifdef WATCH_TOHOST
   method Action set_watch_tohost (Bool watch_tohost, Bit #(64) tohost_addr);
   method Bit #(64) mv_tohost_value;
`endif

   // Inform core that DDR4 has been initialized and is ready to accept requests
   method Action ma_ddr4_ready;

   // Misc. status; 0 = running, no error
   (* always_ready *)
   method Bit #(8) mv_status;

endinterface

// ================================================================
// Cache flush specs

Bit #(1) flush_to_invalid = 0;
Bit #(1) flush_to_clean   = 1;

// ================================================================
// IMem interface

interface IMem_IFC;
   // CPU side: IMem request
   (* always_ready *)
   method Action  req (Bit #(3) f3,
		       WordXL addr,
		       // The following  args for VM
		       Priv_Mode  priv,
		       Bit #(1)   sstatus_SUM,
		       Bit #(1)   mstatus_MXR,
		       WordXL     satp);    // { VM_Mode, ASID, PPN_for_page_table }
   (* always_ready *)  method Action commit;

   // CPU side: IMem response
   (* always_ready *)  method Bool     valid;
   (* always_ready *)  method Bool     is_i32_not_i16;
   (* always_ready *)  method WordXL   pc;
   (* always_ready *)  method Instr    instr;
   (* always_ready *)  method Bool     exc;
   (* always_ready *)  method Exc_Code exc_code;
   (* always_ready *)  method WordXL   tval;        // can be different from PC
endinterface

// ================================================================
// DMem interface

interface DMem_IFC;
   // CPU side: DMem request
   (* always_ready *)
   method Action  req (CacheOp op,
		       Bit #(3) f3,
               Bool is_unsigned,
`ifdef ISA_A
		       Bit #(5) amo_funct5,
`endif
		       Addr addr,
               Tuple2#(Bool, Bit #(128)) store_value,
		       // The following  args for VM
		       Priv_Mode  priv,
		       Bit #(1)   sstatus_SUM,
		       Bit #(1)   mstatus_MXR,
		       WordXL     satp);    // { VM_Mode, ASID, PPN_for_page_table }
   (* always_ready *)  method Action commit;

   // CPU side: DMem response
   (* always_ready *)  method Bool       valid;
   (* always_ready *)  method Tuple2#(Bool, Bit #(128))  word128;      // Load-value
   (* always_ready *)  method Tuple2#(Bool, Bit #(128))  st_amo_val;  // Final store-value for ST, SC, AMO
   (* always_ready *)  method Bool       exc;
   (* always_ready *)  method Exc_Code   exc_code;
endinterface

// ================================================================

endpackage: Near_Mem_IFC
