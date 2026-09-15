// SPDX-License-Identifier: Apache-2.0
`timescale 1ns/1ps

module controller_debug_irq_tb;
  import cv32e40p_pkg::*;

  logic clk = 0, rst_n = 0;
  logic fetch_enable_i = 1;
  logic is_fetch_failed_i = 0;
  logic instr_valid_i = 1, id_ready_i = 1, id_valid_i = 1;
  logic ex_valid_i = 1, wb_ready_i = 1;
  logic irq_req_ctrl_i = 0;
  logic [4:0] irq_id_ctrl_i = 5'd7;
  logic debug_req_i = 0, debug_single_step_i = 0;
  logic dret_insn_i = 0, dret_dec_i = 0;
  logic csr_status_i = 0;
  logic irq_ack_o, debug_mode_o, debug_csr_save_o;
  logic [2:0] debug_cause_o;
  logic debug_havereset_o, debug_running_o, debug_halted_o;
  logic csr_restore_dret_id_o;
  logic csr_save_if_o, csr_save_cause_o, pc_set_o;
  logic [5:0] csr_cause_o;
  logic [3:0] pc_mux_o;
  logic [2:0] exc_pc_mux_o;
  integer failures = 0;
  integer irq_ack_count = 0;
  integer n;
  reg saw_post_resume_ack;

  always #5 clk = ~clk;
  always @(posedge clk) if (irq_ack_o) irq_ack_count <= irq_ack_count + 1;

  cv32e40p_controller dut (
    .clk(clk), .clk_ungated_i(clk), .rst_n(rst_n),
    .fetch_enable_i(fetch_enable_i), .is_fetch_failed_i(is_fetch_failed_i),
    .illegal_insn_i(1'b0), .ecall_insn_i(1'b0), .mret_insn_i(1'b0), .uret_insn_i(1'b0),
    .dret_insn_i(dret_insn_i), .mret_dec_i(1'b0), .uret_dec_i(1'b0), .dret_dec_i(dret_dec_i),
    .wfi_i(1'b0), .ebrk_insn_i(1'b0), .fencei_insn_i(1'b0), .csr_status_i(csr_status_i),
    .instr_valid_i(instr_valid_i), .pc_id_i(32'h1000),
    .hwlp_start_addr_i('0), .hwlp_end_addr_i('0), .hwlp_counter_i('0),
    .data_req_ex_i(1'b0), .data_we_ex_i(1'b0), .data_misaligned_i(1'b0),
    .data_load_event_i(1'b0), .data_err_i(1'b0), .mult_multicycle_i(1'b0),
    .apu_en_i(1'b0), .apu_read_dep_i(1'b0), .apu_read_dep_for_jalr_i(1'b0), .apu_write_dep_i(1'b0),
    .branch_taken_ex_i(1'b0), .ctrl_transfer_insn_in_id_i('0), .ctrl_transfer_insn_in_dec_i('0),
    .irq_req_ctrl_i(irq_req_ctrl_i), .irq_sec_ctrl_i(1'b0), .irq_id_ctrl_i(irq_id_ctrl_i),
    .irq_wu_ctrl_i(irq_req_ctrl_i), .current_priv_lvl_i(PRIV_LVL_M),
    .irq_ack_o(irq_ack_o), .debug_mode_o(debug_mode_o), .debug_cause_o(debug_cause_o),
    .debug_csr_save_o(debug_csr_save_o), .debug_req_i(debug_req_i),
    .debug_single_step_i(debug_single_step_i), .debug_ebreakm_i(1'b0), .debug_ebreaku_i(1'b0),
    .trigger_match_i(1'b0), .debug_havereset_o(debug_havereset_o),
    .debug_running_o(debug_running_o), .debug_halted_o(debug_halted_o),
    .csr_save_if_o(csr_save_if_o), .csr_save_cause_o(csr_save_cause_o),
    .csr_cause_o(csr_cause_o), .pc_set_o(pc_set_o), .pc_mux_o(pc_mux_o),
    .exc_pc_mux_o(exc_pc_mux_o),
    .csr_restore_dret_id_o(csr_restore_dret_id_o),
    .regfile_we_id_i(1'b0), .regfile_alu_waddr_id_i('0), .regfile_we_ex_i(1'b0),
    .regfile_waddr_ex_i('0), .regfile_we_wb_i(1'b0), .regfile_alu_we_fw_i(1'b0),
    .reg_d_ex_is_reg_a_i(1'b0), .reg_d_ex_is_reg_b_i(1'b0), .reg_d_ex_is_reg_c_i(1'b0),
    .reg_d_wb_is_reg_a_i(1'b0), .reg_d_wb_is_reg_b_i(1'b0), .reg_d_wb_is_reg_c_i(1'b0),
    .reg_d_alu_is_reg_a_i(1'b0), .reg_d_alu_is_reg_b_i(1'b0), .reg_d_alu_is_reg_c_i(1'b0),
    .id_ready_i(id_ready_i), .id_valid_i(id_valid_i), .ex_valid_i(ex_valid_i), .wb_ready_i(wb_ready_i)
  );

  task fail(input string marker, input string detail);
    begin
      $display("%s: %s", marker, detail);
      failures = failures + 1;
    end
  endtask

  task wait_state(input ctrl_state_e wanted, input integer limit);
    integer n;
    begin : waiting
      for (n = 0; n < limit; n = n + 1) begin
        @(negedge clk);
        if (dut.ctrl_fsm_cs == wanted) disable waiting;
      end
      fail("STATE_TIMEOUT", "controller did not reach expected state");
    end
  endtask

  task reset_and_boot;
    begin
      rst_n = 0; debug_req_i = 0; debug_single_step_i = 0;
      irq_req_ctrl_i = 0; dret_insn_i = 0; dret_dec_i = 0; csr_status_i = 0;
      is_fetch_failed_i = 0;
      repeat (2) @(negedge clk);
      rst_n = 1;
      wait_state(DECODE, 8);
    end
  endtask

  initial begin
    // Scenario 1: simultaneous halt request and interrupt. Debug has priority.
    reset_and_boot();
    @(negedge clk); debug_req_i = 1; irq_req_ctrl_i = 1;
    @(negedge clk); debug_req_i = 0;
    if (irq_ack_o !== 0) fail("DEBUG_IRQ_PRIORITY_FAILED", "interrupt acknowledged during debug entry");
    wait_state(DBG_TAKEN_ID, 6);
    if (debug_csr_save_o !== 1'b1 || debug_cause_o != DBG_CAUSE_HALTREQ)
      fail("DEBUG_ENTRY_FAILED", "halt request did not save HALTREQ cause");
    @(negedge clk);
    if (debug_mode_o !== 1'b1 || debug_halted_o !== 1'b1)
      fail("DEBUG_ENTRY_FAILED", "controller did not enter halted debug mode");
    repeat (3) begin
      @(negedge clk);
      if (irq_ack_o !== 0) fail("IRQ_MASK_IN_DEBUG_FAILED", "interrupt acknowledged while debug_mode_o=1");
    end

    // Execute DRET through the real DECODE -> XRET_JUMP path.
    dret_insn_i = 1;
    wait_state(FLUSH_EX, 3);
    wait_state(FLUSH_WB, 3);
    if (csr_restore_dret_id_o !== 1'b1) fail("DEBUG_RESUME_FAILED", "DRET restore strobe was not asserted in FLUSH_WB");
    @(negedge clk);
    if (dut.ctrl_fsm_cs != XRET_JUMP) fail("DEBUG_RESUME_FAILED", "controller did not enter XRET_JUMP");
    dret_insn_i = 0; dret_dec_i = 1;
    @(negedge clk); dret_dec_i = 0;
    @(negedge clk);
    if (debug_mode_o !== 1'b0 || debug_running_o !== 1'b1)
      fail("DEBUG_RESUME_FAILED", "DRET did not return the controller to running mode");
    // The externally-held interrupt becomes serviceable only after resume.
    saw_post_resume_ack = 0;
    begin : wait_irq_ack
      for (n = 0; n < 4; n = n + 1) begin
        @(negedge clk);
        if (irq_ack_o === 1'b1) begin
          saw_post_resume_ack = 1;
          irq_req_ctrl_i = 0; // qualified request drops as trap entry masks it
          disable wait_irq_ack;
        end
      end
    end
    @(negedge clk);
    if (!saw_post_resume_ack)
      fail("PENDING_IRQ_AFTER_RESUME_FAILED", "held qualified interrupt was not acknowledged after DRET");
    if (irq_ack_o !== 1'b0)
      fail("PENDING_IRQ_AFTER_RESUME_FAILED", "interrupt acknowledge did not drop with qualified request");

    // Scenario 2: enabled single-step causes debug entry with STEP cause.
    reset_and_boot();
    debug_single_step_i = 1;
    wait_state(DBG_TAKEN_IF, 8);
    if (debug_csr_save_o !== 1'b1 || debug_cause_o != DBG_CAUSE_STEP)
      fail("SINGLE_STEP_FAILED", "single-step entry did not save STEP cause");
    @(negedge clk);
    if (debug_mode_o !== 1'b1 || debug_halted_o !== 1'b1)
      fail("SINGLE_STEP_FAILED", "single-step did not halt in debug mode");

    // Scenario 3: instruction-fetch exception has priority over a qualified IRQ.
    reset_and_boot();
    @(negedge clk); is_fetch_failed_i = 1; irq_req_ctrl_i = 1;
    #1;
    if (irq_ack_o !== 1'b0)
      fail("EXCEPTION_IRQ_PRIORITY_FAILED", "interrupt acknowledged instead of instruction-fetch exception");
    if (csr_save_if_o !== 1'b1 || csr_save_cause_o !== 1'b1 ||
        csr_cause_o !== {1'b0, EXC_CAUSE_INSTR_FAULT})
      fail("EXCEPTION_TRAP_OUTPUT_FAILED", "fetch fault did not save the expected exception cause");
    wait_state(FLUSH_WB, 3);
    if (pc_set_o !== 1'b1 || pc_mux_o != PC_EXCEPTION ||
        exc_pc_mux_o != EXC_PC_EXCEPTION)
      fail("EXCEPTION_TRAP_OUTPUT_FAILED", "fetch fault did not select the exception redirect in FLUSH_WB");
    is_fetch_failed_i = 0; irq_req_ctrl_i = 0;

    if (failures == 0) begin
      $display("TEST_PASS: upstream CV32E40P controller debug/interrupt/exception scenarios verified");
      $finish(0);
    end else begin
      $fatal(1, "TEST_FAIL: failures=%0d", failures);
    end
  end

  initial begin
    #5000;
    $fatal(1, "TEST_TIMEOUT");
  end
endmodule
