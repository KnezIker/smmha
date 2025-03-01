/*
 * mac_engine.sv
 * Francesco Conti <fconti@iis.ee.ethz.ch>
 *
 * Copyright (C) 2018 ETH Zurich, University of Bologna
 * Copyright and related rights are licensed under the Solderpad Hardware
 * License, Version 0.51 (the "License"); you may not use this file except in
 * compliance with the License.  You may obtain a copy of the License at
 * http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
 * or agreed to in writing, software, hardware and materials distributed under
 * this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
 * CONDITIONS OF ANY KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations under the License.
 *
 * The architecture that follows is relatively straightforward; it supports two modes:
 *  - in 'simple_mult' mode, the a_i and b_i streams feed the 32b x 32b multiplier (mult).
 *    The output of the multiplier (64b) is registered in a pipeline stage
 *    (r_mult), which is then shifted by ctrl_i.shift to the right and streamed out as d_o.
 *    There is no control local to the module except for handshakes.
 *  - in 'scalar_prod' mode, the c_i stream is first shifted left by ctrl_i.shift, extended
 *    to 64b and saved in r_acc. Then, the a_i and b_i streams feed the 32b x 32b multiplier
 *    (mult) for ctrl_i.len cycles, controlled by a local counter. The output of mult is 
 *    registered in a pipeline stage (r_mult), whose value is used as input to an accumulator
 *    (r_acc) -- the one which was inited by the shifted value of c_i. At the end of the
 *    ctrl_i.len cycles, the output of r_acc is shifted back to the right by ctrl_i.shift
 *    bits and streamed out as d_o.
 */

import smmha_package::*;

module smmha_engine
(
  // global signals
  input  logic                   clk_i,
  input  logic                   rst_ni,
  input  logic                   test_mode_i,
  // input a stream
  hwpe_stream_intf_stream.sink   a_i,
  // output d stream
  hwpe_stream_intf_stream.source d_o,
  // control channel
  input  ctrl_engine_t           ctrl_i,
  output flags_engine_t          flags_o
);

  logic unsigned [$clog2(MAC_CNT_LEN):0] cnt;
  logic unsigned [$clog2(MAC_CNT_LEN):0] r_cnt;
  logic signed [63:0] c_shifted;
  logic signed [63:0] mult;
  logic signed [63:0] r_mult;
  logic               r_mult_valid;
  logic               r_mult_ready;
  logic signed [64+$clog2(MAC_CNT_LEN)-1:0] r_acc;
  logic                                     r_acc_valid;
  logic                                     r_acc_ready;
  logic signed [64+$clog2(MAC_CNT_LEN)-1:0] d_nonshifted;
  logic                                     d_nonshifted_valid;

  // A design choice of this accelerator is that at the interface of modules only a few categories
  // of signals are exposed:
  //  - global signals (clk, rst_n)
  //  - HWPE-Stream or TCDM interfaces (a_i, ...)
  //  - a control packed struct (ctrl_i) and a state packed struct (flags_o)
  // The flags_o packed struct encapsulates all of the information about the internal state
  // of the module that must be exposed to the controller, and the ctrl_i all the control
  // information necessary for configuring the current module. In this way, it is possible to
  // make significant changes to the control interface (which can typically propagate through
  // a big hierarchy of modules) without manually modifying the interface in all modules; it
  // is sufficient to change the packed struct definition in the package where it is defined.
  // Packed structs are essentially bit vectors where bit fields have a name, and as such
  // are easily synthesizable and much more readable than Verilog-2001-ish code.

  //data block
  assign d_o.strb = 1'b1
  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni) begin
      r_cnt <= '0;
    end
    else if(ctrl_i.clear) begin
      r_cnt <= '0;
    end
    else begin
      if(ctrl_i.start) begin
        case (ctrl_i.operation)
          0:begin
            d_o.data <= a_i.data + ctrl_i.operand;
          end
          1:begin
            d_o.data <= a_i.data - ctrl_i.operand;
          end
        endcase 
      end
    end
  end
  
  always_ff @(posedge clk_i or negedge rst_ni)
    begin
      if(~rst_ni) begin
        r_cnt <= '0;
      end
      else if(ctrl_i.clear) begin
        r_cnt <= '0;
      end
      else begin
        if(ctrl_i.start) begin
        d_o.valid <= a_i.valid;
        a_i.ready <= d_o.ready;
        end
      end
    end 

  // The control counter is implemented directly inside this module; as the control is
  // minimal, it was not deemed convenient to move it to another submodule. For bigger
  // FSMs that is typically the most advantageous choice.

  always_comb
  begin
    cnt = r_cnt + 1;
  end

  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni) begin
      r_cnt <= '0;
    end
    else if(ctrl_i.clear) begin
      r_cnt <= '0;
    end
    else if(ctrl_i.enable) begin
      if (ctrl_i.start == 1'b1 && a_i.valid && d_o.ready) begin
        r_cnt <= cnt;
      end
    end
  end
  flags_o.cnt = r_cnt;
endmodule // mac_engine
