// Copyright (c) 2020 Bluespec, Inc.

package LLC_DMA_AXI4_Adapter;

// ================================================================
// This module converts the 512-bit-wide LLCache.dma interface into an
// AXI4 Server Interface with 512-bit-wide data bus.

// ================================================================
// BSV library imports

import FIFOF       :: *;
import Connectable :: *;

import FShow       :: *;
import GetPut      :: *;
import Vector      :: *;
import BuildVector :: *;
import FIFO        :: *;
import Assert      :: *;

// ----------------
// BSV additional libs

import Cur_Cycle  :: *;
import Semi_FIFOF :: *;
import EdgeFIFOFs :: *;

// ================================================================
// Project imports

// ----------------
// From RISCY-OOO

import Types       :: *;
import ProcTypes   :: *;
import LLCache_Aux :: *;
import CacheUtils  :: *;
import CCTypes     :: *;

// ----------------
// From Piccolo/Flute

import AXI4         :: *;
import SourceSink   :: *;
import Near_Mem_IFC :: *;    // For Wd_Id/Addr/User/Data_Dma

// ================================================================

module mkLLC_DMA_AXI4_Adapter #(DmaServer#(LLCDmaReqId) llc)
                               (AXI4_Slave #( Wd_Id_Dma, Wd_Addr_Dma, Wd_Data_Dma
						                    , Wd_AW_User_Dma, Wd_W_User_Dma, Wd_B_User_Dma
                                            , Wd_AR_User_Dma, Wd_R_User_Dma));

   // 0: quiet    1: rules
   Integer verbosity = 0;

   // Slave transactor for requests from external DMA
//   AXI4_Slave_Xactor_IFC #(Wd_Id_Dma,
//			   Wd_Addr_Dma,
//			   Wd_Data_Dma,
//			   Wd_User_Dma) axi4_slave_xactor <- mkAXI4_Slave_Xactor;
   let slaveShimPort <- mkAXI4Shim;

   // ================================================================
   // DMA requests/responses

   rule rl_wr_req;
      let wr_addr <- get (slaveShimPort.master.aw);
      let wr_data <- get (slaveShimPort.master.w);

      DmaRq #(LLCDmaReqId) req = DmaRq {addr:   wr_addr.awaddr,
					byteEn: unpack (wr_data.wstrb),
					data:   CLine { tag: unpack (0),
                                    data: unpack (wr_data.wdata)},
					id:     wr_addr.awid};
      llc.memReq.enq (req);
      if(verbosity >= 1) begin
         $display("%0d: %m.mkLLC_DMA_AXI4_Adapter.rl_wr_req", cur_cycle);
	 $display("    ", fshow (wr_addr));
	 $display("    ", fshow (wr_data));
      end
   endrule

   rule rl_wr_rsp;
      let bid = llc.respSt.first;
      llc.respSt.deq;

      // Send response to external client
      AXI4_BFlit #(Wd_Id_Dma, Wd_B_User_Dma)
      wr_resp = AXI4_BFlit {bid:   bid,
			      bresp: OKAY,
			      buser: ?};
      slaveShimPort.master.b.put (wr_resp);

      if(verbosity >= 1) begin
         $display("%0d: %m.mkLLC_DMA_AXI4_Adapter.rl_wr_rsp", cur_cycle);
         $display("    ", fshow(wr_resp));
      end
   endrule

   rule rl_rd_req;
      let rd_addr <- get (slaveShimPort.master.ar);

      DmaRq #(LLCDmaReqId) req =  DmaRq {addr:   rd_addr.araddr,
					 byteEn: replicate ( replicate (False)),    // for LLC, all False means 'read'
					 data:   ?,
					 id:     rd_addr.arid};
      llc.memReq.enq (req);
      if(verbosity >= 1) begin
         $display("%0d: %m.mkLLC_DMA_AXI4_Adapter.rl_rd_req", cur_cycle);
         $display("    ", fshow(rd_addr));
      end
   endrule

   rule rl_rd_rsp;
      let resp = llc.respLd.first;
      llc.respLd.deq;

      // Send response to external client
      AXI4_RFlit #(Wd_Id_Dma, Wd_Data_Dma, Wd_R_User_Dma)
      rd_data = AXI4_RFlit {rid:   resp.id,
			      rdata: pack (resp.data.data),
			      rresp: OKAY,
			      rlast: True,
			      ruser: unpack (0)};
      slaveShimPort.master.r.put (rd_data);

      if(verbosity >= 1) begin
         $display("%0d: %m.mkLLC_DMA_AXI4_Adapter.rl_rd_rsp", cur_cycle);
         $display("    ", fshow(rd_data));
      end
   endrule

   // ================================================================
   // INTERFACE

   return slaveShimPort.slave;

endmodule

endpackage
