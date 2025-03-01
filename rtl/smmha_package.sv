/*
 * smmha_package.sv
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

import hwpe_stream_package::*;

package smmha_package;

  parameter int unsigned MAC_CNT_LEN = 1024; // maximum length of the vectors for a scalar product

  // registers in register file
  parameter int unsigned SMMHA_OPERATION = 0;
  parameter int unsigned SMMHA_OPERAND = 1;
  parameter int unsigned SMMHA_LENGHT = 2;
  parameter int unsigned SMMHA_IN_BASE_ADDR = 3;
  parameter int unsigned SMMHA_OUT_BASE_ADDR = 4;

  // microcode offset indeces -- this should be aligned to the microcode compiler of course!
  parameter int unsigned MAC_UCODE_A_OFFS = 0;
  parameter int unsigned MAC_UCODE_D_OFFS = 3;

  // microcode mnemonics -- this should be aligned to the microcode compiler of course!
  parameter int unsigned MAC_UCODE_MNEM_NBITER     = 4 - 4;
  parameter int unsigned MAC_UCODE_MNEM_ITERSTRIDE = 5 - 4;
  parameter int unsigned MAC_UCODE_MNEM_ONESTRIDE  = 6 - 4;

  typedef struct packed {
    logic clear;
    logic start;
    logic [31:0] len; // 1 bit more as cnt starts from 1, not 0
    logic [31:0] operand;
    logic [31:0] operaton; 
  } ctrl_engine_t; 

  typedef struct packed {
    logic unsigned [$clog2(MAC_CNT_LEN):0] cnt; // 1 bit more as cnt starts from 1, not 0
  } flags_engine_t;

  typedef struct packed {
    hwpe_stream_package::ctrl_sourcesink_t a_source_ctrl;
    hwpe_stream_package::ctrl_sourcesink_t d_sink_ctrl;
  } ctrl_streamer_t;

  typedef struct packed {
    hwpe_stream_package::flags_sourcesink_t a_source_flags;
    hwpe_stream_package::flags_sourcesink_t d_sink_flags;
  } flags_streamer_t;

  typedef struct packed {
    logic [31:0] operaton;
    logic [31:0] operand;
    logic [31:0] len;
  } ctrl_fsm_t;

  typedef enum {
    FSM_IDLE,
    FSM_START,
    FSM_COMPUTE,
    FSM_WAIT,
    FSM_UPDATEIDX,
    FSM_TERMINATE
  } state_fsm_t;

endpackage // smmha_package
