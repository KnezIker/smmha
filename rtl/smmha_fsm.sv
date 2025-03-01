/* 
 * mac_fsm.sv
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
 */

import mac_package::*;
import hwpe_ctrl_package::*;

module smmha_fsm (
  // global signals
  input  logic                clk_i,
  input  logic                rst_ni,
  input  logic                test_mode_i,
  input  logic                clear_i,
  // ctrl & flags
  output ctrl_streamer_t      ctrl_streamer_o,
  input  flags_streamer_t     flags_streamer_i,
  output ctrl_engine_t        ctrl_engine_o,
  input  flags_engine_t       flags_engine_i,
  output ctrl_slave_t         ctrl_slave_o,
  input  flags_slave_t        flags_slave_i,
  input  ctrl_regfile_t       reg_file_i,
  input  ctrl_fsm_t           ctrl_i
);

  state_fsm_t curr_state, next_state;

  always_ff @(posedge clk_i or negedge rst_ni)
  begin : main_fsm_seq
    if(~rst_ni) begin
      curr_state <= FSM_IDLE;
    end
    else if(clear_i) begin
      curr_state <= FSM_IDLE;
    end
    else begin
      curr_state <= next_state;
    end
  end

  always_comb
  begin : main_fsm_comb
    // direct mappings - these have to be here due to blocking/non-blocking assignment
    // combination with the same ctrl_engine_o/ctrl_streamer_o variable
    // shift-by-3 due to conversion from bits to bytes
    // a stream
    ctrl_streamer_o.a_source_ctrl.addressgen_ctrl.trans_size  = ctrl_i.len;
    ctrl_streamer_o.a_source_ctrl.addressgen_ctrl.line_stride = '0;
    ctrl_streamer_o.a_source_ctrl.addressgen_ctrl.line_length = ctrl_i.len;
    ctrl_streamer_o.a_source_ctrl.addressgen_ctrl.feat_stride = '0;
    ctrl_streamer_o.a_source_ctrl.addressgen_ctrl.feat_length = 1;
    ctrl_streamer_o.a_source_ctrl.addressgen_ctrl.base_addr   = reg_file_i.hwpe_params[SMMHA_IN_BASE_ADDR];
    ctrl_streamer_o.a_source_ctrl.addressgen_ctrl.feat_roll   = '0;
    ctrl_streamer_o.a_source_ctrl.addressgen_ctrl.loop_outer  = '0;
    ctrl_streamer_o.a_source_ctrl.addressgen_ctrl.realign_type = '0;
    // d stream
    ctrl_streamer_o.d_sink_ctrl.addressgen_ctrl.trans_size  = ctrl_i.len;
    ctrl_streamer_o.d_sink_ctrl.addressgen_ctrl.line_stride = '0;
    ctrl_streamer_o.d_sink_ctrl.addressgen_ctrl.line_length = ctrl_i.len;
    ctrl_streamer_o.d_sink_ctrl.addressgen_ctrl.feat_stride = '0;
    ctrl_streamer_o.d_sink_ctrl.addressgen_ctrl.feat_length = 1;
    ctrl_streamer_o.d_sink_ctrl.addressgen_ctrl.base_addr   = reg_file_i.hwpe_params[SMMHA_OUT_BASE_ADDR];
    ctrl_streamer_o.d_sink_ctrl.addressgen_ctrl.feat_roll   = '0;
    ctrl_streamer_o.d_sink_ctrl.addressgen_ctrl.loop_outer  = '0;
    ctrl_streamer_o.d_sink_ctrl.addressgen_ctrl.realign_type = '0;

    // engine
    ctrl_engine_o.clear      = '1;
    ctrl_engine_o.start      = '0;
    ctrl_engine_o.len        = ctrl_i.len;
    ctrl_engine_o.operand    = reg_file_i.hwpe_params[SMMHA_OPERAND];
    ctrl_engine_o.operaton   = reg_file_i.hwpe_params[SMMHA_OPERATION];

    // slave
    ctrl_slave_o.done = '0;
    ctrl_slave_o.evt  = '0;

    // real finite-state machine
    next_state   = curr_state;
    ctrl_streamer_o.a_source_ctrl.req_start = '0;
    ctrl_streamer_o.d_sink_ctrl.req_start   = '0;
    case(curr_state)
      FSM_IDLE: begin
        ctrl_engine_o.start      = 1'b0;
        // wait for a start signal
        if(flags_slave_i.start) begin
          next_state = FSM_START;
        end
      end
      FSM_START: begin
        // update the indeces, then load the first feature
        if(flags_streamer_i.a_source_flags.ready_start &
           flags_streamer_i.d_sink_flags.ready_start) begin
          next_state  = FSM_COMPUTE;
          //engine flags
          ctrl_engine_o.start  = 1'b1;
          ctrl_engine_o.clear  = 1'b0;
          //start transmission
          ctrl_streamer_o.a_source_ctrl.req_start = 1'b1;
          ctrl_streamer_o.d_sink_ctrl.req_start = 1'b1; //ctrl_i.simple_mul
        end
        else begin
          next_state = FSM_WAIT;
        end
      end
      FSM_COMPUTE: begin
        ctrl_engine_o.clear  = 1'b0;
        // compute, then update the indeces (and write output if necessary)
        if(flags_engine_i.cnt == ctrl_i.len) begin
          next_state = FSM_TERMINATE;
        end
      end
      FSM_WAIT: begin
        // wait for the flags to be ok then go back to load
        //engine flags
        ctrl_engine_o.clear  = 1'b0;
        if(flags_streamer_i.a_source_flags.ready_start &
           flags_streamer_i.d_sink_flags.ready_start) begin
          next_state = FSM_COMPUTE;
          //engine flags
          ctrl_engine_o.start = 1'b1;
          //start transmission
          ctrl_streamer_o.a_source_ctrl.req_start = 1'b1;
          ctrl_streamer_o.d_sink_ctrl.req_start   = 1'b1;
        end
      end
      FSM_TERMINATE: begin
        // wait for the flags to be ok then go back to idle
        ctrl_engine_o.clear  = 1'b0;
        if(flags_streamer_i.a_source_flags.ready_start &
           flags_streamer_i.d_sink_flags.ready_start) begin
          next_state = FSM_IDLE;
          ctrl_slave_o.done = 1'b1;
        end
      end
    endcase // curr_state
  end

endmodule // mac_fsm
