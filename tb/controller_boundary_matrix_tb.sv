// SPDX-License-Identifier: Apache-2.0
`timescale 1ns/1ps

module controller_debug_irq_tb;
  import cv32e40p_pkg::*;
  logic clk = 0, rst_n = 0, fetch_enable_i = 1, is_fetch_failed_i = 0;
  logic instr_valid_i = 1, id_ready_i = 1, id_valid_i = 1, ex_valid_i = 1, wb_ready_i = 1;
  logic irq_req_ctrl_i = 0; logic [4:0] irq_id_ctrl_i = 5'd7;
  logic debug_req_i = 0, debug_single_step_i = 0, dret_insn_i = 0, dret_dec_i = 0;
  logic irq_ack_o, debug_mode_o, debug_csr_save_o, debug_havereset_o, debug_running_o, debug_halted_o;
  logic [2:0] debug_cause_o; logic csr_restore_dret_id_o, csr_save_if_o, csr_save_cause_o, pc_set_o;
  logic [5:0] csr_cause_o; logic [3:0] pc_mux_o; logic [2:0] exc_pc_mux_o;
  integer failures = 0;
  always #5 clk = ~clk;

  cv32e40p_controller dut (
    .clk(clk), .clk_ungated_i(clk), .rst_n(rst_n), .fetch_enable_i(fetch_enable_i),
    .is_fetch_failed_i(is_fetch_failed_i), .illegal_insn_i(1'b0), .ecall_insn_i(1'b0),
    .mret_insn_i(1'b0), .uret_insn_i(1'b0), .dret_insn_i(dret_insn_i), .mret_dec_i(1'b0),
    .uret_dec_i(1'b0), .dret_dec_i(dret_dec_i), .wfi_i(1'b0), .ebrk_insn_i(1'b0),
    .fencei_insn_i(1'b0), .csr_status_i(1'b0), .instr_valid_i(instr_valid_i), .pc_id_i(32'h1000),
    .hwlp_start_addr_i('0), .hwlp_end_addr_i('0), .hwlp_counter_i('0), .data_req_ex_i(1'b0),
    .data_we_ex_i(1'b0), .data_misaligned_i(1'b0), .data_load_event_i(1'b0), .data_err_i(1'b0),
    .mult_multicycle_i(1'b0), .apu_en_i(1'b0), .apu_read_dep_i(1'b0),
    .apu_read_dep_for_jalr_i(1'b0), .apu_write_dep_i(1'b0), .branch_taken_ex_i(1'b0),
    .ctrl_transfer_insn_in_id_i('0), .ctrl_transfer_insn_in_dec_i('0),
    .irq_req_ctrl_i(irq_req_ctrl_i), .irq_sec_ctrl_i(1'b0), .irq_id_ctrl_i(irq_id_ctrl_i),
    .irq_wu_ctrl_i(irq_req_ctrl_i), .current_priv_lvl_i(PRIV_LVL_M), .irq_ack_o(irq_ack_o),
    .debug_mode_o(debug_mode_o), .debug_cause_o(debug_cause_o), .debug_csr_save_o(debug_csr_save_o),
    .debug_req_i(debug_req_i), .debug_single_step_i(debug_single_step_i), .debug_ebreakm_i(1'b0),
    .debug_ebreaku_i(1'b0), .trigger_match_i(1'b0), .debug_havereset_o(debug_havereset_o),
    .debug_running_o(debug_running_o), .debug_halted_o(debug_halted_o), .csr_save_if_o(csr_save_if_o),
    .csr_save_cause_o(csr_save_cause_o), .csr_cause_o(csr_cause_o), .pc_set_o(pc_set_o),
    .pc_mux_o(pc_mux_o), .exc_pc_mux_o(exc_pc_mux_o), .csr_restore_dret_id_o(csr_restore_dret_id_o),
    .regfile_we_id_i(1'b0), .regfile_alu_waddr_id_i('0), .regfile_we_ex_i(1'b0),
    .regfile_waddr_ex_i('0), .regfile_we_wb_i(1'b0), .regfile_alu_we_fw_i(1'b0),
    .reg_d_ex_is_reg_a_i(1'b0), .reg_d_ex_is_reg_b_i(1'b0), .reg_d_ex_is_reg_c_i(1'b0),
    .reg_d_wb_is_reg_a_i(1'b0), .reg_d_wb_is_reg_b_i(1'b0), .reg_d_wb_is_reg_c_i(1'b0),
    .reg_d_alu_is_reg_a_i(1'b0), .reg_d_alu_is_reg_b_i(1'b0), .reg_d_alu_is_reg_c_i(1'b0),
    .id_ready_i(id_ready_i), .id_valid_i(id_valid_i), .ex_valid_i(ex_valid_i), .wb_ready_i(wb_ready_i)
  );

  task fail(input string marker, input string detail);
    begin
      failures = failures + 1;
      $display("%s: %s", marker, detail);
      $fatal(1, "TEST_FAIL");
    end
  endtask

  task wait_state(input ctrl_state_e wanted, input integer limit, input string marker);
    integer cycle;
    begin : waiting
      for (cycle = 0; cycle < limit; cycle = cycle + 1) begin
        @(negedge clk); if (dut.ctrl_fsm_cs == wanted) disable waiting;
      end
      fail(marker, "controller did not reach expected state");
    end
  endtask

  task reset_and_boot;
    begin
      rst_n = 0; debug_req_i = 0; debug_single_step_i = 0; irq_req_ctrl_i = 0;
      dret_insn_i = 0; dret_dec_i = 0; is_fetch_failed_i = 0; instr_valid_i = 1; id_ready_i = 1;
      repeat (2) @(negedge clk); rst_n = 1; wait_state(DECODE, 8, "BOOT_STATE_TIMEOUT");
    end
  endtask

  task case_pass(input string case_id, input string pulse_position,
                 input integer stall_length, input bit sampled_request, input string outcome);
    begin
      $display("BOUNDARY_EXERCISE: %s pulse_position=%s pulse_width_cycles=1 stall_length=%0d sampled_request=%0d service_order=%s",
               case_id, pulse_position, stall_length, sampled_request, outcome);
      $display("BOUNDARY_CASE_PASS: %s outcome=%s", case_id, outcome);
    end
  endtask

  task enter_debug_with_irq(input string marker);
    begin
      reset_and_boot();
      @(negedge clk); debug_req_i = 1; irq_req_ctrl_i = 1;
      @(negedge clk); debug_req_i = 0;
      wait_state(DBG_TAKEN_ID, 6, marker);
      if (debug_csr_save_o !== 1'b1 || debug_cause_o != DBG_CAUSE_HALTREQ)
        fail(marker, "initial halt did not save HALTREQ");
      @(negedge clk);
      if (debug_mode_o !== 1'b1 || irq_ack_o !== 1'b0)
        fail(marker, "initial debug mode did not mask held interrupt");
    end
  endtask

  task run_stall_case(input integer stall_length, input string case_id);
    integer cycle;
    string marker;
    begin
      marker = $sformatf("BOUNDARY_CASE_FAILED_%s", case_id);
      reset_and_boot();
      if (stall_length != 0) begin instr_valid_i = 0; id_ready_i = 0; end
      @(negedge clk); debug_req_i = 1;
      @(negedge clk); debug_req_i = 0; irq_req_ctrl_i = 1;
      if (dut.debug_req_q !== 1'b1) fail(marker, "request was not sampled into debug_req_q");
      for (cycle = 1; cycle < stall_length; cycle = cycle + 1) begin
        @(negedge clk);
        if (dut.ctrl_fsm_cs != DECODE || irq_ack_o !== 1'b0)
          fail(marker, "stalled DECODE did not hold state and suppress interrupt acknowledge");
      end
      instr_valid_i = 1; id_ready_i = 1;
      wait_state(DBG_TAKEN_ID, 6, marker);
      if (debug_csr_save_o !== 1'b1 || debug_cause_o != DBG_CAUSE_HALTREQ || irq_ack_o !== 1'b0)
        fail(marker, "retained halt was not serviced before held interrupt");
      @(negedge clk);
      if (debug_mode_o !== 1'b1 || debug_halted_o !== 1'b1) fail(marker, "debug mode was not entered");
      case_pass(case_id, stall_length == 0 ? "DECODE_VALID" : "DECODE_INVALID",
                stall_length, 1'b1, "halt_before_irq");
    end
  endtask

  task run_fetch_case(input integer pulse_position, input string case_id);
    string marker;
    begin
      marker = $sformatf("BOUNDARY_CASE_FAILED_%s", case_id);
      reset_and_boot();
      instr_valid_i = (pulse_position == 3); id_ready_i = (pulse_position == 3);
      @(negedge clk);
      is_fetch_failed_i = 1; irq_req_ctrl_i = 1;
      if (pulse_position == 0) debug_req_i = 1;
      #1;
      if (dut.ctrl_fsm_cs != DECODE || irq_ack_o !== 1'b0 || csr_save_if_o !== 1'b1 ||
          csr_save_cause_o !== 1'b1 || csr_cause_o !== {1'b0, EXC_CAUSE_INSTR_FAULT})
        fail(marker, "DECODE did not prioritize and save fetch-fault cause");
      @(negedge clk);
      if (dut.ctrl_fsm_cs != FLUSH_WB || pc_set_o !== 1'b1 || pc_mux_o != PC_EXCEPTION ||
          exc_pc_mux_o != EXC_PC_EXCEPTION || irq_ack_o !== 1'b0)
        fail(marker, "FLUSH_WB did not drive exception redirect with interrupt suppressed");
      if (pulse_position == 0) debug_req_i = 0;
      if (pulse_position == 1) debug_req_i = 1;
      @(negedge clk);
      debug_req_i = 0; is_fetch_failed_i = 0; instr_valid_i = 1; id_ready_i = 1;
      if (pulse_position == 2) debug_req_i = 1;
      if (pulse_position == 3) begin
        irq_req_ctrl_i = 0;
        case_pass(case_id, "none", 0, 1'b0, "exception_redirect");
      end else begin
        #1;
        if (irq_ack_o !== 1'b0) fail(marker, "held interrupt acknowledged before halt service");
        if (pulse_position == 2) begin @(negedge clk); debug_req_i = 0; end
        wait_state(DBG_TAKEN_ID, 6, marker);
        if (debug_csr_save_o !== 1'b1 || debug_cause_o != DBG_CAUSE_HALTREQ || irq_ack_o !== 1'b0)
          fail(marker, "halt request was not eventually serviced before held interrupt");
        case_pass(case_id,
                  pulse_position == 0 ? "DECODE_WITH_FETCH_FAULT_BEFORE_FLUSH_WB" :
                  pulse_position == 1 ? "FETCH_FAULT_FLUSH_WB" :
                                        "DECODE_AFTER_FETCH_FAULT_FLUSH_WB",
                  1, 1'b1, "halt_before_irq");
      end
    end
  endtask

  task run_xret_case(input integer pulse_position, input string case_id);
    string marker;
    begin
      marker = $sformatf("BOUNDARY_CASE_FAILED_%s", case_id);
      enter_debug_with_irq(marker);
      dret_insn_i = 1; id_ready_i = 1;
      wait_state(FLUSH_EX, 3, marker);
      wait_state(FLUSH_WB, 3, marker);
      if (csr_restore_dret_id_o !== 1'b1 || irq_ack_o !== 1'b0)
        fail(marker, "DRET restore missing or interrupt acknowledged in FLUSH_WB");
      if (pulse_position == 0) debug_req_i = 1;
      @(negedge clk);
      if (dut.ctrl_fsm_cs != XRET_JUMP || debug_mode_o !== 1'b1)
        fail(marker, "XRET_JUMP was not observed while debug mode remained set");
      if (pulse_position == 0) debug_req_i = 0;
      if (pulse_position == 0 && dut.debug_req_q !== 1'b1)
        fail(marker, "pre-XRET halt pulse was not sampled before supported debug-mode clearing");
      if (pulse_position == 1) debug_req_i = 1;
      dret_insn_i = 0; dret_dec_i = 1; #1;
      if (pc_set_o !== 1'b1 || pc_mux_o != PC_DRET || irq_ack_o !== 1'b0)
        fail(marker, "XRET_JUMP did not select DRET with interrupt suppressed");
      @(negedge clk);
      dret_dec_i = 0;
      if (pulse_position == 1) debug_req_i = 0;
      if (pulse_position == 2) debug_req_i = 1;
      #1;
      if (debug_mode_o !== 1'b0) fail(marker, "DRET did not clear debug mode");
      if (pulse_position == 0) begin
        if (dut.debug_req_q !== 1'b0 || irq_ack_o !== 1'b1)
          fail(marker, "request wholly inside prior debug mode should clear; held interrupt should become serviceable");
        irq_req_ctrl_i = 0;
        case_pass(case_id, "DRET_FLUSH_WB_BEFORE_XRET_JUMP", 0, 1'b1, "irq_after_dret");
      end else begin
        if (irq_ack_o !== 1'b0) fail(marker, "held interrupt acknowledged before post-DRET halt");
        if (pulse_position == 1 && dut.debug_req_q !== 1'b1)
          fail(marker, "XRET_JUMP halt pulse was not sampled");
        if (pulse_position == 2) begin
          @(negedge clk);
          if (dut.debug_req_q !== 1'b1) fail(marker, "post-XRET halt pulse was not sampled");
          debug_req_i = 0;
        end
        wait_state(DBG_TAKEN_ID, 6, marker);
        if (debug_csr_save_o !== 1'b1 || debug_cause_o != DBG_CAUSE_HALTREQ || irq_ack_o !== 1'b0)
          fail(marker, "post-DRET halt was not serviced before held interrupt");
        case_pass(case_id,
                  pulse_position == 1 ? "DRET_XRET_JUMP" : "DECODE_AFTER_DRET_XRET_JUMP",
                  0, 1'b1, "halt_before_irq");
      end
    end
  endtask

  initial begin
    string selected;
    if (!$value$plusargs("CASE=%s", selected)) fail("BOUNDARY_CASE_SELECTION_FAILED", "missing +CASE");
    if      (selected == "STALL_0")       run_stall_case(0, selected);
    else if (selected == "STALL_1")       run_stall_case(1, selected);
    else if (selected == "STALL_3")       run_stall_case(3, selected);
    else if (selected == "FETCH_VALID")   run_fetch_case(3, selected);
    else if (selected == "FLUSH_BEFORE")  run_fetch_case(0, selected);
    else if (selected == "FLUSH_DURING")  run_fetch_case(1, selected);
    else if (selected == "FLUSH_AFTER")   run_fetch_case(2, selected);
    else if (selected == "XRET_BEFORE")   run_xret_case(0, selected);
    else if (selected == "XRET_DURING")   run_xret_case(1, selected);
    else if (selected == "XRET_AFTER")    run_xret_case(2, selected);
    else fail("BOUNDARY_CASE_SELECTION_FAILED", "unknown +CASE");
    $finish(0);
  end

  initial begin #5000; $fatal(1, "TEST_TIMEOUT"); end
endmodule
