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

  initial begin
    // Retain a one-cycle halt pulse while DECODE has no valid instruction.
    reset_and_boot(); instr_valid_i = 0; id_ready_i = 0;
    @(negedge clk); debug_req_i = 1;
    @(negedge clk); debug_req_i = 0;
    if (dut.debug_req_q !== 1'b1)
      fail("PULSED_DEBUG_RETENTION_FAILED", "halt pulse was not retained across invalid/stalled decode");
    irq_req_ctrl_i = 1;
    repeat (2) begin
      @(negedge clk);
      if (dut.ctrl_fsm_cs != DECODE || irq_ack_o !== 1'b0)
        fail("PULSED_DEBUG_RETENTION_FAILED", "stalled decode consumed interrupt or left DECODE");
    end
    instr_valid_i = 1; id_ready_i = 1;
    @(negedge clk);
    if (irq_ack_o !== 1'b0)
      fail("PULSED_DEBUG_RETENTION_FAILED", "pending interrupt beat retained halt request");
    wait_state(DBG_TAKEN_ID, 6, "PULSED_DEBUG_RETENTION_FAILED");
    if (debug_csr_save_o !== 1'b1 || debug_cause_o != DBG_CAUSE_HALTREQ)
      fail("PULSED_DEBUG_RETENTION_FAILED", "retained request did not save HALTREQ cause");
    @(negedge clk);
    if (debug_mode_o !== 1'b1 || debug_halted_o !== 1'b1 || irq_ack_o !== 1'b0)
      fail("PULSED_DEBUG_RETENTION_FAILED", "debug halt did not mask pending interrupt");

    // Fetch faults bypass instr_valid_i and outrank a simultaneous interrupt.
    reset_and_boot(); instr_valid_i = 0; id_ready_i = 0;
    @(negedge clk); is_fetch_failed_i = 1; irq_req_ctrl_i = 1; #1;
    if (irq_ack_o !== 1'b0 || csr_save_if_o !== 1'b1 || csr_save_cause_o !== 1'b1 ||
        csr_cause_o !== {1'b0, EXC_CAUSE_INSTR_FAULT})
      fail("STALLED_FETCH_FAULT_PRIORITY_FAILED", "stalled fetch fault did not beat interrupt and save cause");
    wait_state(FLUSH_WB, 3, "STALLED_FETCH_FAULT_PRIORITY_FAILED"); #1;
    if (irq_ack_o !== 1'b0 || pc_set_o !== 1'b1 || pc_mux_o != PC_EXCEPTION ||
        exc_pc_mux_o != EXC_PC_EXCEPTION)
      fail("STALLED_FETCH_FAULT_PRIORITY_FAILED", "fetch fault redirect was not preserved through FLUSH_WB");
    // A halt request during exception redirection is retained without disturbing
    // the active exception redirect. It is serviced before the still-held IRQ.
    debug_req_i = 1; #1;
    if (pc_set_o !== 1'b1 || exc_pc_mux_o != EXC_PC_EXCEPTION || irq_ack_o !== 1'b0)
      fail("EXCEPTION_FLUSH_DEBUG_FAILED", "halt pulse disturbed the active exception redirect");
    @(negedge clk); debug_req_i = 0; is_fetch_failed_i = 0; instr_valid_i = 1; id_ready_i = 1;
    #1;
    if (dut.debug_req_q !== 1'b1 || irq_ack_o !== 1'b0)
      fail("EXCEPTION_FLUSH_DEBUG_FAILED", "halt pulse during FLUSH_WB was lost or interrupt won early");
    wait_state(DBG_TAKEN_ID, 6, "EXCEPTION_FLUSH_DEBUG_FAILED");
    if (debug_csr_save_o !== 1'b1 || debug_cause_o != DBG_CAUSE_HALTREQ)
      fail("EXCEPTION_FLUSH_DEBUG_FAILED", "retained exception-flush request did not enter debug");
    irq_req_ctrl_i = 0;

    // Stall DRET, then pulse halt in XRET_JUMP. The pulse must win over held IRQ after resume.
    reset_and_boot(); debug_req_i = 1; irq_req_ctrl_i = 1;
    @(negedge clk); debug_req_i = 0;
    wait_state(DBG_TAKEN_ID, 6, "DRET_REHALT_PRIORITY_FAILED"); @(negedge clk);
    if (debug_mode_o !== 1'b1 || irq_ack_o !== 1'b0)
      fail("DRET_REHALT_PRIORITY_FAILED", "initial debug entry did not mask held interrupt");
    dret_insn_i = 1; id_ready_i = 0;
    repeat (3) begin
      @(negedge clk);
      if (dut.ctrl_fsm_cs != DECODE || csr_restore_dret_id_o !== 1'b0 || irq_ack_o !== 1'b0)
        fail("DRET_STALL_FAILED", "stalled DRET advanced, restored early, or acknowledged interrupt");
    end
    id_ready_i = 1;
    wait_state(FLUSH_EX, 3, "DRET_STALL_FAILED");
    wait_state(FLUSH_WB, 3, "DRET_STALL_FAILED");
    if (csr_restore_dret_id_o !== 1'b1)
      fail("DRET_STALL_FAILED", "DRET restore strobe missing after stall release");
    @(negedge clk);
    if (dut.ctrl_fsm_cs != XRET_JUMP || debug_mode_o !== 1'b1)
      fail("DRET_REHALT_PRIORITY_FAILED", "XRET_JUMP was not reached with debug mode set");
    dret_insn_i = 0; dret_dec_i = 1; debug_req_i = 1;
    @(negedge clk); dret_dec_i = 0; debug_req_i = 0;
    if (debug_mode_o !== 1'b0 || dut.debug_req_q !== 1'b1 || irq_ack_o !== 1'b0)
      fail("DRET_REHALT_PRIORITY_FAILED", "halt pulse was lost while DRET cleared debug mode");
    @(negedge clk);
    if (irq_ack_o !== 1'b0)
      fail("DRET_REHALT_PRIORITY_FAILED", "interrupt beat retained halt request after DRET");
    wait_state(DBG_TAKEN_ID, 6, "DRET_REHALT_PRIORITY_FAILED");
    if (debug_csr_save_o !== 1'b1 || debug_cause_o != DBG_CAUSE_HALTREQ)
      fail("DRET_REHALT_PRIORITY_FAILED", "post-DRET request did not re-enter with HALTREQ cause");

    // Independent debug-cause path sanity check.
    reset_and_boot(); debug_single_step_i = 1;
    wait_state(DBG_TAKEN_IF, 8, "SINGLE_STEP_FAILED");
    if (debug_csr_save_o !== 1'b1 || debug_cause_o != DBG_CAUSE_STEP)
      fail("SINGLE_STEP_FAILED", "single-step did not save STEP cause");

    if (failures == 0) begin
      $display("TEST_PASS: upstream CV32E40P controller temporal debug/interrupt/exception scenarios verified");
      $finish(0);
    end else $fatal(1, "TEST_FAIL: failures=%0d", failures);
  end

  initial begin #5000; $fatal(1, "TEST_TIMEOUT"); end
endmodule
