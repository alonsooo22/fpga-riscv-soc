#include "testbench_vbase.h"

#include "riscv_main.h"
#include "riscv.h"
#include "elf_load.h"

#include <unistd.h>
#include <cstdio>
#include <cstdlib>
#include <deque>
#include <map>
#include <sstream>
#include <string>

#include "cosim_api.h"

#include "riscv_tcm_top_rtl.h"
#include "Vriscv_tcm_top.h"
#include "Vriscv_tcm_top__Syms.h"

#include "verilated.h"
#include "verilated_vcd_sc.h"

//-----------------------------------------------------------------
// Module
//-----------------------------------------------------------------
class testbench: public testbench_vbase, public cosim_cpu_api, public cosim_mem_api
{
public:
    //-----------------------------------------------------------------
    // Instances / Members
    //-----------------------------------------------------------------      
    riscv_tcm_top_rtl           *m_dut;

    int                          m_argc;
    char**                       m_argv;
    uint32_t                     m_last_pc;
    uint64_t                     m_step_count;
    bool                         m_bounded_diag_enabled;
    uint64_t                     m_diag_interval;
    uint64_t                     m_diag_retired_count;
    uint64_t                     m_diag_iter_entries;
    uint64_t                     m_diag_stall_cycles;
    uint64_t                     m_diag_early_live_cycles;
    uint64_t                     m_diag_early_hold_cycles;
    uint64_t                     m_diag_normal_pending_cycles;
    uint64_t                     m_diag_request_cycles;
    uint64_t                     m_diag_accept_cycles;
    uint64_t                     m_diag_ack_cycles;
    uint32_t                     m_diag_last_commit_pc;
    bool                         m_irq_script_enabled;
    int                          m_irq_script_stage;
    uint32_t                     m_irq_mask_trigger_pc;
    uint32_t                     m_irq_mask_clear_pc;
    uint32_t                     m_irq_enabled_trigger_pc;
    uint32_t                     m_irq_handler_pc;
    uint32_t                     m_irq_take_count;
    uint32_t                     m_irq_accept_pc;
    uint32_t                     m_irq_accept_mepc;
    uint32_t                     m_irq_accept_mcause;
    bool                         m_irq_take_seen;
    uint32_t                     m_irq_exception_event_count;
    bool                         m_irq_exception_seen;
    uint32_t                     m_irq_branch_pc;
    bool                         m_irq_enabled_source_seen;
    bool                         m_irq_branch_window_seen;
    bool                         m_irq_branch_mispredict_seen;
    bool                         m_closure_failure;
    bool                         m_side_effect_test_enabled;
    uint32_t                     m_mmio_write_count;
    uint32_t                     m_mmio_nt_count;
    uint32_t                     m_mmio_pt_count;
    uint32_t                     m_mmio_nt_last_data;
    uint32_t                     m_mmio_pt_last_data;
    bool                         m_mmio_aw_pending;
    bool                         m_mmio_w_pending;
    uint32_t                     m_mmio_pending_addr;
    uint32_t                     m_mmio_pending_data;
    uint32_t                     m_mmio_pending_strb;
    bool                         m_mmio_bvalid;
    bool                         m_side_expect_pred_taken;
    uint32_t                     m_side_nt_wrong_pc[4];
    uint32_t                     m_side_pt_target_pc[4];
    uint32_t                     m_side_nt_wrong_commits[4];
    uint32_t                     m_side_pt_target_commits[4];
    uint64_t                     m_side_last_commit_step;
    bool                         m_raw_trace_enabled;
    FILE                        *m_raw_trace_fd;
    uint64_t                     m_raw_trace_rows;
    uint64_t                     m_raw_trace_limit;

    // One bounded, event-only observer shared by the v4 load and BTB
    // feasibility analysis.  It is disabled unless explicitly requested and
    // never changes the DUT inputs or control decisions.
    bool                         m_shared_observer_enabled;
    bool                         m_shared_corrected_mode;
    FILE                        *m_shared_event_fd;
    uint64_t                     m_shared_event_rows;
    uint64_t                     m_shared_event_limit;
    uint64_t                     m_shared_event_dropped;
    uint32_t                     m_shared_warmup_iters;
    uint32_t                     m_shared_sample_iters;
    uint32_t                     m_shared_iter_entries;
    bool                         m_shared_roi_active;
    bool                         m_shared_stop_requested;
    uint64_t                     m_shared_roi_start_cycle;
    uint64_t                     m_shared_roi_end_cycle;
    uint64_t                     m_shared_last_iter_cycle;
    bool                         m_shared_prev_e1_load;
    bool                         m_shared_prev_e2_load;
    bool                         m_shared_prev_wb_load;
    uint32_t                     m_shared_prev_e1_pc;
    uint32_t                     m_shared_prev_e2_pc;
    uint32_t                     m_shared_prev_wb_pc;
    bool                         m_shared_prev_early_result_valid;
    uint32_t                     m_shared_prev_early_result_rd;
    bool                         m_shared_prev_early_live;
    bool                         m_shared_prev_early_hold;
    bool                         m_shared_prev_branch_flush;
    bool                         m_shared_prev_mem_request;
    uint32_t                     m_shared_prev_mem_addr;
    uint32_t                     m_shared_prev_mem_data;
    uint32_t                     m_shared_prev_mem_wr;

    // Dynamic identities for the corrected bounded observer.  These are
    // testbench-only tokens; no identity field is added to the CPU.
    struct corrected_fetch_token
    {
        uint64_t id;
        uint32_t pc;
        bool     lookup_pred_taken;
        bool     response_seen;
    };

    struct corrected_dynamic_inst
    {
        uint64_t id;
        uint32_t pc;
        uint32_t opcode;
        bool     pred_taken;
        bool     updated;
    };

    struct corrected_branch_token
    {
        uint64_t id;
        uint32_t pc;
        bool     pred_taken;
    };

    std::deque<corrected_fetch_token> m_corrected_fetch_tokens;
    std::deque<corrected_dynamic_inst> m_corrected_dynamic_insts;
    std::deque<corrected_branch_token> m_corrected_branch_tokens;
    uint64_t                     m_corrected_next_id;
    uint64_t                     m_corrected_lookup_count;
    uint64_t                     m_corrected_update_count;
    uint64_t                     m_corrected_commit_count;
    uint64_t                     m_corrected_fetch_issue_count;
    uint64_t                     m_corrected_fetch_cancel_count;
    uint64_t                     m_corrected_branch_cancel_count;
    uint64_t                     m_corrected_lookup_unresolved;
    uint64_t                     m_corrected_unresolved_reported;
    uint64_t                     m_corrected_update_unassociated;
    uint64_t                     m_corrected_update_duplicate;
    uint64_t                     m_corrected_update_pred_mismatch;
    uint64_t                     m_corrected_update_after_cancel;
    uint64_t                     m_corrected_commit_unassociated;
    uint64_t                     m_corrected_commit_order_error;
    uint64_t                     m_corrected_duplicate_token_consume;
    uint64_t                     m_corrected_decode_token_mismatch;
    uint64_t                     m_corrected_orphan_response;
    std::map<uint64_t, uint32_t> m_corrected_cancelled_ids;
    bool                         m_corrected_prev_response_valid;
    bool                         m_corrected_prev_skid_valid;
    bool                         m_corrected_prev_decode_valid;
    bool                         m_corrected_prev_fetch_drop;
    uint32_t                     m_corrected_prev_decode_pc;
    uint32_t                     m_corrected_prev_decode_instr;
    bool                         m_corrected_prev_decode_pred;
    bool                         m_corrected_prev_normal_active;
    bool                         m_corrected_prev_pending_conflict;
    bool                         m_corrected_prev_slot_free;
    bool                         m_corrected_prev_early_offer;
    bool                         m_corrected_prev_early_accept;
    bool                         m_corrected_prev_early_fire;
    bool                         m_corrected_prev_early_response;
    bool                         m_corrected_prev_normal_rd;
    bool                         m_corrected_prev_normal_error;

    struct v4_shared_snapshot
    {
        bool     issue_valid;
        bool     issue_accept;
        uint32_t issue_pc;
        uint32_t issue_opcode;
        uint32_t issue_ra;
        uint32_t issue_rb;
        uint32_t issue_rd;
        uint32_t issue_ra_value;
        uint32_t issue_rb_value;
        uint32_t dependency;
        const char *base_source;
        uint32_t load_width;
        bool     tcm;
        bool     aligned;
        bool     base_ok;
        bool     port_ready;
        bool     early_candidate;
        bool     early_launch;
        bool     early_live;
        bool     early_hold;
        bool     early_result_valid;
        uint32_t early_result_rd;
        uint32_t early_result_value;
        uint32_t agu_addr;
        uint32_t mem_addr;
        uint32_t mem_data;
        uint32_t mem_wr;
        bool     e1_load;
        bool     e1_mul;
        uint32_t e1_pc;
        uint32_t e1_opcode;
        uint32_t e1_rd;
        bool     e2_load;
        bool     e2_mul;
        uint32_t e2_pc;
        uint32_t e2_opcode;
        uint32_t e2_rd;
        uint32_t e2_result;
        bool     wb_valid;
        uint32_t wb_pc;
        uint32_t wb_opcode;
        uint32_t wb_rd;
        uint32_t wb_result;
        bool     scoreboard_stall;
        bool     load_raw;
        bool     mul_raw;
        bool     waw;
        bool     blanket;
        bool     mem_request;
        bool     mem_accept;
        bool     mem_ack;
        bool     lookup_accept;
        uint32_t lookup_pc;
        bool     lookup_hit;
        bool     lookup_taken;
        uint32_t lookup_target;
        bool     update_valid;
        uint32_t update_pc;
        uint32_t update_target;
        bool     update_is_jal;
        bool     update_taken;
        bool     update_pred_taken;
        bool     update_mispredict;
        bool     update_hit;
        bool     invalidate;
        bool     branch_request;
        bool     branch_mispredict;
        bool     branch_flush;
        bool     commit_valid;
        uint32_t commit_pc;
        uint32_t commit_opcode;

        // Exact early/normal LSU and front-end boundaries for the corrected
        // observer.  The original fields above remain for the historical
        // observer format.
        bool     normal_active;
        bool     normal_pending_conflict;
        bool     mem_unaligned_e1;
        bool     early_slot_free;
        bool     early_offer;
        bool     early_accept;
        bool     early_fire;
        bool     early_response;
        bool     normal_rd;
        bool     normal_error;
        bool     lsu_opcode_valid;
        uint32_t normal_addr;
        uint32_t early_addr;
        uint32_t early_request_addr;
        uint32_t lsu_opcode;
        uint32_t lsu_pc;
        uint32_t lsu_ra;
        uint32_t lsu_rb;
        uint32_t lsu_ra_value;
        uint32_t lsu_rb_value;
        bool     fetch_response_valid;
        bool     fetch_skid_valid;
        bool     fetch_decode_valid;
        bool     fetch_decode_accept;
        bool     fetch_decode_pred_taken;
        uint32_t fetch_decode_pc;
        uint32_t fetch_decode_instr;
        bool     fetch_response_drop;
        bool     fetch_icache_fetch;
        bool     fetch_stall;
    };

    // Bounded early-load feasibility observer.  It is runtime-disabled by
    // default and writes only a finite witness trace plus aggregate counts.
    bool                         m_early_observer_enabled;
    FILE                        *m_early_trace_fd;
    uint64_t                     m_early_trace_rows;
    uint64_t                     m_early_trace_limit;
    uint64_t                     m_early_trace_dropped;
    uint32_t                     m_early_warmup_iters;
    uint32_t                     m_early_sample_iters;
    uint32_t                     m_early_iter_entries;
    bool                         m_early_roi_active;
    bool                         m_early_stop_requested;
    bool                         m_early_reported;
    uint64_t                     m_early_roi_start_cycle;
    uint64_t                     m_early_roi_end_cycle;
    uint64_t                     m_early_last_iter_cycle;
    uint64_t                     m_early_stall_run;
    uint64_t                     m_early_l2l_pair_run;
    uint64_t                     m_early_l2l_max_pair_run;
    uint32_t                     m_early_l2l_last_a_pc;
    uint32_t                     m_early_l2l_last_b_pc;
    bool                         m_early_last_load_valid;
    uint32_t                     m_early_last_load_pc;
    uint32_t                     m_early_last_load_rd;
    uint32_t                     m_early_last_load_chain;
    uint64_t                     m_early_instr_since_last_load;
    std::map<std::string, uint64_t> m_early_counts;

    // E-TCM phase-1 directed witness.  This is simulation-only and remains
    // disabled unless the focused ELF explicitly enables it.
    bool                         m_e_tcm_focus_enabled;
    FILE                        *m_e_tcm_focus_fd;
    uint64_t                     m_e_tcm_focus_rows;
    uint64_t                     m_e_tcm_focus_limit;
    uint64_t                     m_e_tcm_candidate_count;
    uint64_t                     m_e_tcm_launch_count;
    uint64_t                     m_e_tcm_response_count;
    uint64_t                     m_e_tcm_consume_count;
    uint64_t                     m_e_tcm_fast_capture_count;
    uint64_t                     m_e_tcm_branch_count;
    uint64_t                     m_e_tcm_branch_mispredict_count;
    uint64_t                     m_e_tcm_release_alu_count;
    uint64_t                     m_e_tcm_release_branch_count;
    uint64_t                     m_e_tcm_release_store_count;
    uint64_t                     m_e_tcm_store_data_count[3];
    uint64_t                     m_e_tcm_store_address_count;
    uint64_t                     m_e_tcm_store_both_count;
    uint64_t                     m_e_tcm_bad_count;
    uint64_t                     m_e_tcm_last_launch_cycle;
    uint32_t                     m_e_tcm_last_launch_addr;
    uint32_t                     m_e_tcm_last_launch_rd;
    bool                         m_e_tcm_transaction_pending;
    bool                         m_e_tcm_prev_result_valid;
    bool                         m_e_tcm_prev_fast_e2;
    bool                         m_e_tcm_reported;

    // Simulation-only AXI-TCM occupancy check.  The driver uses the real
    // external AXI input of tcm_mem and never enters the synthesized design.
    bool                         m_tcm_port_test_enabled;
    uint32_t                     m_tcm_port_trigger_pc;
    bool                         m_tcm_port_started;
    bool                         m_tcm_port_external_inflight;
    bool                         m_tcm_port_busy_seen;
    bool                         m_tcm_port_wait_fallback;
    bool                         m_tcm_port_failure;
    uint64_t                     m_tcm_port_ext_ar_count;
    uint64_t                     m_tcm_port_ext_r_count;
    uint64_t                     m_tcm_port_candidate_count;
    uint64_t                     m_tcm_port_early_launch_count;
    uint64_t                     m_tcm_port_blocked_candidate_count;
    uint64_t                     m_tcm_port_fallback_request_count;
    uint64_t                     m_tcm_port_fallback_accept_count;
    uint64_t                     m_tcm_port_trace_rows;
    uint64_t                     m_tcm_port_trace_limit;
    FILE                        *m_tcm_port_trace_fd;

    static constexpr uint32_t MMIO_NT_ADDR = 0x10000000u;
    static constexpr uint32_t MMIO_PT_ADDR = 0x10000004u;

    uint32_t read_word(uint32_t address)
    {
        return static_cast<uint32_t>(read(address)) |
               (static_cast<uint32_t>(read(address + 1)) << 8) |
               (static_cast<uint32_t>(read(address + 2)) << 16) |
               (static_cast<uint32_t>(read(address + 3)) << 24);
    }

    enum
    {
        IRQ_WAIT_MASK_TRIGGER = 0,
        IRQ_MASK_ASSERTED,
        IRQ_WAIT_ENABLED_TRIGGER,
        IRQ_ENABLED_ASSERTED,
        IRQ_SCRIPT_DONE,
        IRQ_SCRIPT_ERROR
    };

    uint32_t env_u32(const char *name, uint32_t default_value)
    {
        const char *value = std::getenv(name);
        return (value && *value) ? static_cast<uint32_t>(std::strtoul(value, NULL, 0)) : default_value;
    }

    uint64_t env_u64(const char *name, uint64_t default_value)
    {
        const char *value = std::getenv(name);
        return (value && *value) ? static_cast<uint64_t>(std::strtoull(value, NULL, 0)) : default_value;
    }

    void drive_irq_script(void)
    {
        if (!m_irq_script_enabled)
            return;

        // m_last_pc is the last committed PC sampled by get_pc().  Driving
        // the level before the following wait makes this an external source
        // event, rather than a CSR/software pending-bit write.
        switch (m_irq_script_stage)
        {
        case IRQ_WAIT_MASK_TRIGGER:
            if (m_last_pc == m_irq_mask_trigger_pc)
            {
                set_interrupt(1);
                m_irq_script_stage = IRQ_MASK_ASSERTED;
                std::printf("IRQ_DRIVER assert masked source at commit PC 0x%08x, cycle %llu\n",
                            m_last_pc, static_cast<unsigned long long>(m_step_count));
            }
            break;
        case IRQ_MASK_ASSERTED:
            if (m_last_pc == m_irq_mask_clear_pc)
            {
                set_interrupt(0);
                m_irq_script_stage = IRQ_WAIT_ENABLED_TRIGGER;
                std::printf("IRQ_DRIVER withdraw masked source at commit PC 0x%08x, cycle %llu\n",
                            m_last_pc, static_cast<unsigned long long>(m_step_count));
            }
            break;
        case IRQ_WAIT_ENABLED_TRIGGER:
            if (m_last_pc == m_irq_enabled_trigger_pc)
            {
                set_interrupt(1);
                m_irq_enabled_source_seen = true;
                m_irq_script_stage = IRQ_ENABLED_ASSERTED;
                std::printf("IRQ_DRIVER assert enabled source at commit PC 0x%08x, cycle %llu\n",
                            m_last_pc, static_cast<unsigned long long>(m_step_count));
            }
            break;
        case IRQ_ENABLED_ASSERTED:
            if (m_last_pc == m_irq_handler_pc)
            {
                set_interrupt(0);
                m_irq_script_stage = IRQ_SCRIPT_DONE;
                std::printf("IRQ_DRIVER withdraw enabled source at handler PC 0x%08x, cycle %llu\n",
                            m_last_pc, static_cast<unsigned long long>(m_step_count));
            }
            break;
        default:
            break;
        }
    }

    void tcm_port_driver(void)
    {
        axi4_master request;
        request.init();
        axi_t_in.write(request);
        wait();

        while (!m_tcm_port_test_enabled)
            wait();

        if (m_tcm_port_trigger_pc == 0xffffffffu)
        {
            std::fprintf(stderr, "ETCM_TXN missing ULTRA_E_TCM_PORT_TRIGGER_PC\n");
            m_tcm_port_failure = true;
            m_closure_failure = true;
            while (true)
                wait();
        }

        while (m_last_pc != m_tcm_port_trigger_pc)
            wait();

        m_tcm_port_started = true;
        request.init();
        request.ARVALID = 1;
        request.ARADDR = 0x00006000u;
        request.ARID = 7;
        // Use one legal eight-beat INCR burst so the shared RAM port remains
        // occupied for several cycles; this is stronger than holding only a
        // response-channel handshake, which does not keep the RAM busy.
        request.ARLEN = 7;
        request.ARBURST = 1;
        request.RREADY = 1;
        axi_t_in.write(request);
        std::printf("ETCM_TXN external_read_start trigger_pc=0x%08x cycle=%llu\n",
                    m_tcm_port_trigger_pc,
                    static_cast<unsigned long long>(m_step_count));

        for (unsigned guard = 0; guard < 32u; ++guard)
        {
            wait();
            const axi4_slave response = axi_t_out.read();
            if (request.ARVALID && response.ARREADY)
            {
                ++m_tcm_port_ext_ar_count;
                request.ARVALID = 0;
                m_tcm_port_external_inflight = true;
                m_tcm_port_busy_seen = true;
                std::printf("ETCM_TXN external_read_accept cycle=%llu\n",
                            static_cast<unsigned long long>(m_step_count));
            }
            if (response.RVALID && request.RREADY)
            {
                ++m_tcm_port_ext_r_count;
                const bool final_beat = response.RLAST;
                if (final_beat)
                    m_tcm_port_external_inflight = false;
                if (final_beat)
                    request.RREADY = 0;
                std::printf("ETCM_TXN external_read_response data=0x%08x beat=%llu last=%u cycle=%llu\n",
                             static_cast<unsigned>(response.RDATA),
                             static_cast<unsigned long long>(m_tcm_port_ext_r_count),
                             final_beat ? 1u : 0u,
                             static_cast<unsigned long long>(m_step_count));
                if (final_beat)
                {
                    axi_t_in.write(request);
                    return;
                }
            }
            axi_t_in.write(request);
        }

        std::fprintf(stderr, "ETCM_TXN external AXI read did not complete\n");
        m_tcm_port_failure = true;
        m_closure_failure = true;
        request.init();
        axi_t_in.write(request);
        while (true)
            wait();
    }

    void sample_irq_observation(void)
    {
        if (!m_irq_script_enabled)
            return;
        auto *core = m_dut->m_rtl->v->u_core;
        const uint32_t fetch_pc = core->fetch_pc_value();
        const uint32_t predictor_pc = core->predictor_pc_value();
        const uint32_t branch_exec_pc = core->branch_exec_pc_value();
        const bool branch_exec_request = core->branch_exec_request_value() != 0;
        const bool branch_request = core->branch_request_value() != 0;
        const bool branch_mispredict = core->branch_mispredict_value() != 0;
        // The image places the one-time taken branch immediately after the
        // enabled source trigger. Seeing its real fetch/predictor/execute PC
        // while the source is asserted proves the interrupt window was
        // interleaved with the branch front-end activity, rather than merely
        // running as two unrelated tests.
        if (m_irq_enabled_source_seen && !m_irq_branch_window_seen &&
            (fetch_pc == m_irq_branch_pc || predictor_pc == m_irq_branch_pc ||
             (branch_exec_request && branch_exec_pc == m_irq_branch_pc) ||
             (branch_request && branch_exec_pc == m_irq_branch_pc)))
        {
            m_irq_branch_window_seen = true;
            std::printf("IRQ_OBS branch_window fetch_pc=0x%08x predictor_pc=0x%08x exec_pc=0x%08x exec_req=%u redirect_req=%u\n",
                        fetch_pc, predictor_pc, branch_exec_pc,
                        branch_exec_request ? 1 : 0, branch_request ? 1 : 0);
        }
        if (m_irq_enabled_source_seen && branch_mispredict && branch_exec_pc == m_irq_branch_pc &&
            !m_irq_branch_mispredict_seen)
        {
            m_irq_branch_mispredict_seen = true;
            std::printf("IRQ_OBS branch_mispredict pc=0x%08x\n", branch_exec_pc);
        }
        const bool take = core->take_interrupt_value() != 0;
        const uint32_t exception_code = core->exception_code_value();
        if (take && !m_irq_take_seen)
        {
            m_irq_take_count++;
            m_irq_accept_pc = core->irq_exception_pc_value();
            m_irq_accept_mepc = core->csr_mepc_value();
            m_irq_accept_mcause = core->csr_mcause_value();
            std::printf("IRQ_OBS take=%u exception_pc=0x%08x mepc=0x%08x mcause=0x%08x mip=0x%08x\n",
                        m_irq_take_count, m_irq_accept_pc, m_irq_accept_mepc,
                        m_irq_accept_mcause, core->csr_mip_value());
        }
        // 0x20 is EXCEPTION_INTERRUPT in riscv_defs.v. This is the actual
        // writeback exception boundary used to populate mepc, so it is the
        // authoritative acceptance PC for this test—not the source edge.
        if (exception_code == 0x20 && !m_irq_exception_seen)
        {
            m_irq_exception_event_count++;
            m_irq_accept_pc = core->irq_exception_pc_value();
            std::printf("IRQ_OBS exception_event=%u exception_pc=0x%08x mepc=0x%08x mcause=0x%08x\n",
                        m_irq_exception_event_count, m_irq_accept_pc,
                        core->csr_mepc_value(), core->csr_mcause_value());
        }
        m_irq_exception_seen = exception_code == 0x20;
        if (m_irq_take_count != 0 && m_irq_accept_mepc == 0 && core->csr_mepc_value() != 0)
        {
            m_irq_accept_mepc = core->csr_mepc_value();
            m_irq_accept_mcause = core->csr_mcause_value();
        }
        m_irq_take_seen = take;
    }

    void mmio_monitor(void)
    {
        axi4_lite_slave slave;
        slave.init();
        slave.AWREADY = 1;
        slave.WREADY = 1;
        slave.ARREADY = 1;
        axi_i_in.write(slave);
        wait();

        while (true)
        {
            const axi4_lite_master request = axi_i_out.read();

            // AXI4-Lite allows the address and data channels to arrive in
            // either order.  Record both handshakes and count one completed
            // write transaction only after both have arrived.
            if (m_side_effect_test_enabled && request.AWVALID && slave.AWREADY)
            {
                m_mmio_aw_pending = true;
                m_mmio_pending_addr = request.AWADDR;
            }
            if (m_side_effect_test_enabled && request.WVALID && slave.WREADY)
            {
                m_mmio_w_pending = true;
                m_mmio_pending_data = request.WDATA;
                m_mmio_pending_strb = request.WSTRB;
            }

            if (m_mmio_bvalid && request.BREADY)
                m_mmio_bvalid = false;

            if (m_side_effect_test_enabled && m_mmio_aw_pending && m_mmio_w_pending)
            {
                m_mmio_write_count++;
                if (m_mmio_pending_addr == MMIO_NT_ADDR)
                {
                    m_mmio_nt_count++;
                    m_mmio_nt_last_data = m_mmio_pending_data;
                }
                else if (m_mmio_pending_addr == MMIO_PT_ADDR)
                {
                    m_mmio_pt_count++;
                    m_mmio_pt_last_data = m_mmio_pending_data;
                }
                std::printf("MMIO_OBS write=%u addr=0x%08x data=0x%08x strb=0x%x\n",
                            m_mmio_write_count, m_mmio_pending_addr,
                            m_mmio_pending_data, m_mmio_pending_strb);
                m_mmio_aw_pending = false;
                m_mmio_w_pending = false;
                m_mmio_bvalid = true;
            }

            slave.init();
            slave.AWREADY = 1;
            slave.WREADY = 1;
            slave.ARREADY = 1;
            slave.BVALID = m_mmio_bvalid ? 1 : 0;
            axi_i_in.write(slave);
            wait();
        }
    }

    void sample_side_effect_commit(uint32_t pc)
    {
        if (!m_side_effect_test_enabled)
            return;
        for (int i = 0; i < 4; i++)
        {
            if (m_side_nt_wrong_pc[i] != 0 && pc == m_side_nt_wrong_pc[i])
                m_side_nt_wrong_commits[i]++;
            if (m_side_pt_target_pc[i] != 0 && pc == m_side_pt_target_pc[i])
                m_side_pt_target_commits[i]++;
        }
    }

    void raw_trace_sample(void)
    {
        if (!m_raw_trace_enabled || !m_raw_trace_fd ||
            m_raw_trace_rows >= m_raw_trace_limit)
            return;

        auto *core = m_dut->m_rtl->v->u_core;
        auto *issue = core->u_issue;
        const bool interesting =
            issue->raw_decode_valid() || issue->raw_issue_valid() ||
            issue->raw_stall() || issue->raw_squash() ||
            issue->raw_pipe_load_e1() || issue->raw_pipe_store_e1() ||
            issue->raw_pipe_mul_e1() || issue->raw_pipe_load_e2() ||
            issue->raw_pipe_mul_e2() || issue->raw_valid_wb() ||
            issue->raw_lsu_opcode_valid() || core->raw_mem_request_value() ||
            core->raw_mem_ack_value() || core->raw_mem_writeback_valid_value() ||
            core->branch_request_value() || core->branch_mispredict_value() ||
            core->raw_branch_flush_value();
        if (!interesting)
            return;

        std::fprintf(
            m_raw_trace_fd,
            "%llu,%u,%u,%u,%08x,%08x,%u,%u,%u,%08x,%08x,%u,%u,%u,%u,%u,%u,%u,%u,%08x,%08x,%u,%u,%u,%08x,%u,%u,%08x,%08x,%08x,%u,%08x,%08x,%u,%u,%08x,%08x,%u,%u,%u,%08x,%08x,%x,%u,%08x,%u,%u,%u\n",
            static_cast<unsigned long long>(m_step_count),
            issue->raw_decode_valid() ? 1 : 0,
            issue->raw_issue_valid() ? 1 : 0,
            issue->raw_issue_accept() ? 1 : 0,
            issue->raw_issue_pc(), issue->raw_issue_opcode(),
            issue->raw_issue_ra(), issue->raw_issue_rb(), issue->raw_issue_rd(),
            issue->raw_issue_ra_value(), issue->raw_issue_rb_value(),
            issue->raw_scoreboard_hazard() ? 1 : 0,
            issue->raw_stall() ? 1 : 0, issue->raw_lsu_stall() ? 1 : 0,
            issue->raw_squash() ? 1 : 0,
            issue->raw_pipe_load_e1() ? 1 : 0,
            issue->raw_pipe_store_e1() ? 1 : 0,
            issue->raw_pipe_mul_e1() ? 1 : 0, issue->raw_pipe_rd_e1(),
            issue->raw_pipe_pc_e1(), issue->raw_pipe_opcode_e1(),
            issue->raw_pipe_load_e2() ? 1 : 0,
            issue->raw_pipe_mul_e2() ? 1 : 0, issue->raw_pipe_rd_e2(),
            issue->raw_pipe_result_e2(), issue->raw_valid_wb() ? 1 : 0,
            issue->raw_rd_wb(), issue->raw_pc_wb(), issue->raw_opcode_wb(),
            issue->raw_result_wb(), issue->raw_lsu_opcode_valid() ? 1 : 0,
            issue->raw_lsu_pc(), issue->raw_lsu_opcode(), issue->raw_lsu_ra(),
            issue->raw_lsu_rb(), issue->raw_lsu_ra_value(),
            issue->raw_lsu_rb_value(), core->raw_mem_request_value() ? 1 : 0,
            core->raw_mem_accept_value() ? 1 : 0,
            core->raw_mem_ack_value() ? 1 : 0, core->data_addr_value(),
            core->data_write_value(), core->data_write_strobe_value(),
            core->raw_mem_writeback_valid_value() ? 1 : 0,
            core->raw_mem_exception_value(), core->branch_request_value() ? 1 : 0,
            core->branch_mispredict_value() ? 1 : 0,
            core->raw_branch_flush_value() ? 1 : 0);
        std::fflush(m_raw_trace_fd);
        m_raw_trace_rows++;
    }

    void bounded_diag_sample(void)
    {
        if (!m_bounded_diag_enabled)
            return;

        auto *core = m_dut->m_rtl->v->u_core;
        auto *issue = core->u_issue;
        const bool commit = issue->complete_valid0();
        if (commit)
        {
            ++m_diag_retired_count;
            m_diag_last_commit_pc = issue->complete_pc0();
            if (m_diag_last_commit_pc == 0x000020acu)
                ++m_diag_iter_entries;
        }
        if (issue->raw_stall())
            ++m_diag_stall_cycles;
        if (core->early_lsu_live_value())
            ++m_diag_early_live_cycles;
        if (core->early_lsu_hold_valid_value())
            ++m_diag_early_hold_cycles;
        if (core->early_lsu_pending_value())
            ++m_diag_normal_pending_cycles;
        if (core->raw_mem_request_value())
            ++m_diag_request_cycles;
        if (core->raw_mem_accept_value())
            ++m_diag_accept_cycles;
        if (core->raw_mem_ack_value())
            ++m_diag_ack_cycles;

        if (m_step_count == 1u ||
            (m_diag_interval != 0u && (m_step_count % m_diag_interval) == 0u))
        {
            std::fprintf(stderr,
                         "BOUNDED_DIAG progress cycle=%llu sim_time=%s retired=%llu last_commit_pc=0x%08x iter_entries=%llu stall=%llu early_live=%llu early_hold=%llu normal_pending=%llu request=%llu accept=%llu ack=%llu\n",
                         static_cast<unsigned long long>(m_step_count),
                         sc_time_stamp().to_string().c_str(),
                         static_cast<unsigned long long>(m_diag_retired_count),
                         m_diag_last_commit_pc,
                         static_cast<unsigned long long>(m_diag_iter_entries),
                         static_cast<unsigned long long>(m_diag_stall_cycles),
                         static_cast<unsigned long long>(m_diag_early_live_cycles),
                         static_cast<unsigned long long>(m_diag_early_hold_cycles),
                         static_cast<unsigned long long>(m_diag_normal_pending_cycles),
                         static_cast<unsigned long long>(m_diag_request_cycles),
                         static_cast<unsigned long long>(m_diag_accept_cycles),
                         static_cast<unsigned long long>(m_diag_ack_cycles));
            std::fflush(stderr);
        }
    }

    void tcm_transaction_sample(void)
    {
        if (!m_tcm_port_test_enabled || !m_tcm_port_started)
            return;

        auto *core = m_dut->m_rtl->v->u_core;
        const bool candidate = core->early_lsu_candidate_value() != 0;
        const bool launch = core->early_lsu_launch_value() != 0;
        const bool normal_request = core->raw_mem_request_value() && !candidate;
        const bool normal_accept = core->raw_mem_accept_value() && !candidate;

        if (candidate)
            ++m_tcm_port_candidate_count;
        if (launch)
            ++m_tcm_port_early_launch_count;
        if (m_tcm_port_busy_seen && m_tcm_port_external_inflight &&
            candidate && !launch)
        {
            ++m_tcm_port_blocked_candidate_count;
            m_tcm_port_wait_fallback = true;
        }
        if (m_tcm_port_wait_fallback && normal_request)
            ++m_tcm_port_fallback_request_count;
        if (m_tcm_port_wait_fallback && normal_accept)
        {
            ++m_tcm_port_fallback_accept_count;
            m_tcm_port_wait_fallback = false;
        }

        const bool interesting = candidate || launch || normal_request ||
                                 normal_accept || core->raw_mem_ack_value() ||
                                 m_tcm_port_external_inflight;
        if (!interesting || !m_tcm_port_trace_fd ||
            m_tcm_port_trace_rows >= m_tcm_port_trace_limit)
            return;

        std::fprintf(m_tcm_port_trace_fd,
                     "%llu,%u,%u,%u,%u,%u,%u,%u,%u,%u,%08x,%08x,%08x\n",
                     static_cast<unsigned long long>(m_step_count),
                     m_tcm_port_external_inflight ? 1u : 0u,
                     candidate ? 1u : 0u, launch ? 1u : 0u,
                     normal_request ? 1u : 0u, normal_accept ? 1u : 0u,
                     core->raw_mem_ack_value() ? 1u : 0u,
                     core->early_lsu_live_value() ? 1u : 0u,
                     core->early_lsu_hold_valid_value() ? 1u : 0u,
                     core->early_lsu_pending_value() ? 1u : 0u,
                     core->data_addr_value(), core->data_write_value(),
                     core->data_write_strobe_value());
        std::fflush(m_tcm_port_trace_fd);
        ++m_tcm_port_trace_rows;
    }

    void tcm_transaction_report(void)
    {
        if (!m_tcm_port_test_enabled)
            return;
        if (m_tcm_port_trace_fd)
        {
            std::fflush(m_tcm_port_trace_fd);
            std::fclose(m_tcm_port_trace_fd);
            m_tcm_port_trace_fd = NULL;
        }

        const uint32_t expected[4] = {
            0x11112222u, 0x33334444u, 0x55556666u, 0x33334444u
        };
        bool signature_ok = true;
        std::printf("ETCM_TXN signature");
        for (unsigned i = 0; i < 4u; ++i)
        {
            const uint32_t observed = read_word(0x0000e000u + i * 4u);
            std::printf(" s%u=0x%08x", i, observed);
            if (observed != expected[i])
                signature_ok = false;
        }
        std::printf(" status=%s\n", signature_ok ? "PASS" : "FAIL");
        std::printf("ETCM_TXN counts ext_ar=%llu ext_r=%llu candidate=%llu early_launch=%llu blocked_candidate=%llu fallback_request=%llu fallback_accept=%llu trace_rows=%llu\n",
                    static_cast<unsigned long long>(m_tcm_port_ext_ar_count),
                    static_cast<unsigned long long>(m_tcm_port_ext_r_count),
                    static_cast<unsigned long long>(m_tcm_port_candidate_count),
                    static_cast<unsigned long long>(m_tcm_port_early_launch_count),
                    static_cast<unsigned long long>(m_tcm_port_blocked_candidate_count),
                    static_cast<unsigned long long>(m_tcm_port_fallback_request_count),
                    static_cast<unsigned long long>(m_tcm_port_fallback_accept_count),
                    static_cast<unsigned long long>(m_tcm_port_trace_rows));

        const bool coverage_ok = signature_ok && !m_tcm_port_failure &&
            m_tcm_port_ext_ar_count == 1u && m_tcm_port_ext_r_count == 8u &&
            m_tcm_port_candidate_count != 0u &&
            m_tcm_port_blocked_candidate_count != 0u &&
            m_tcm_port_fallback_request_count != 0u &&
            m_tcm_port_fallback_accept_count != 0u &&
            !m_tcm_port_external_inflight && !m_tcm_port_wait_fallback;
        if (!coverage_ok)
        {
            std::fprintf(stderr, "ETCM_TXN closure failed: occupancy/fallback/signature check\n");
            m_closure_failure = true;
        }
    }

    static bool early_is_load(uint32_t opcode)
    {
        return (opcode & 0x7fu) == 0x03u;
    }

    static bool early_is_store(uint32_t opcode)
    {
        return (opcode & 0x7fu) == 0x23u;
    }

    static bool early_is_branch(uint32_t opcode)
    {
        return (opcode & 0x7fu) == 0x63u;
    }

    static bool early_is_mul(uint32_t opcode)
    {
        return (opcode & 0x7fu) == 0x33u && ((opcode >> 25) & 0x7fu) == 0x01u;
    }

    static bool early_uses_rs1(uint32_t opcode)
    {
        switch (opcode & 0x7fu)
        {
        case 0x13u: case 0x03u: case 0x23u: case 0x33u: case 0x63u: case 0x67u:
            return true;
        case 0x73u:
            return ((opcode >> 12) & 0x7u) == 1u ||
                   ((opcode >> 12) & 0x7u) == 2u ||
                   ((opcode >> 12) & 0x7u) == 3u;
        default:
            return false;
        }
    }

    static bool early_uses_rs2(uint32_t opcode)
    {
        return (opcode & 0x7fu) == 0x23u ||
               (opcode & 0x7fu) == 0x33u ||
               (opcode & 0x7fu) == 0x63u;
    }

    static unsigned early_width(uint32_t opcode)
    {
        const unsigned funct3 = (opcode >> 12) & 0x7u;
        if (funct3 == 0u || funct3 == 4u)
            return 0u; // byte
        if (funct3 == 1u || funct3 == 5u)
            return 1u; // half
        if (funct3 == 2u || funct3 == 6u)
            return 2u; // word
        return 3u;
    }

    static const char *early_width_name(unsigned width)
    {
        return width == 0u ? "B" : width == 1u ? "H" : width == 2u ? "W" : "NA";
    }

    static bool early_aligned(uint32_t address, uint32_t opcode)
    {
        const unsigned width = early_width(opcode);
        return width == 0u || (width == 1u ? ((address & 1u) == 0u) :
                               (width == 2u ? ((address & 3u) == 0u) : false));
    }

    static const char *early_consumer_name(uint32_t opcode, unsigned dep)
    {
        if (early_is_branch(opcode))
            return "branch";
        if (early_is_load(opcode))
            return "load-address";
        if (early_is_store(opcode))
        {
            if (dep == 1u) return "store-address";
            if (dep == 2u) return "store-data";
            if (dep == 3u) return "store-address-data";
            return "store-other";
        }
        switch (opcode & 0x7fu)
        {
        case 0x13u: case 0x33u: case 0x37u: case 0x17u: case 0x6fu: case 0x67u:
            return "alu";
        default:
            return "other";
        }
    }

    static const char *early_dep_name(unsigned dep)
    {
        return dep == 1u ? "rs1-only" : dep == 2u ? "rs2-only" :
               dep == 3u ? "both" : "none";
    }

    static unsigned early_dependency_mask(uint32_t opcode, uint32_t ra, uint32_t rb,
                                          bool e1_load, bool e1_mul, uint32_t e1_rd,
                                          bool e2_load, bool e2_mul, uint32_t e2_rd)
    {
        unsigned dep = 0u;
        if (early_uses_rs1(opcode) &&
            (((e1_load || e1_mul) && e1_rd != 0u && ra == e1_rd) ||
             ((e2_load || e2_mul) && e2_rd != 0u && ra == e2_rd)))
            dep |= 1u;
        if (early_uses_rs2(opcode) &&
            (((e1_load || e1_mul) && e1_rd != 0u && rb == e1_rd) ||
             ((e2_load || e2_mul) && e2_rd != 0u && rb == e2_rd)))
            dep |= 2u;
        return dep;
    }

    static const char *early_source_name(uint32_t ra, uint32_t e1_rd, bool e1_load,
                                         bool e1_mul, uint32_t e2_rd, bool e2_load,
                                         bool e2_mul, uint32_t wb_rd)
    {
        if (ra == 0u)
            return "X0";
        // riscv_issue applies successive overriding assignments.  The last
        // matching producer therefore wins: E1, then E2, then WB, then RF.
        // The public rd signals are already validity-masked by pipe_ctrl;
        // x0 is handled above so a zero rd can never claim a source.
        if (e1_rd != 0u && ra == e1_rd)
            return e1_load ? "E1_LOAD" : e1_mul ? "E1_MUL" : "E1_ALU";
        if (e2_rd != 0u && ra == e2_rd)
            return e2_load ? "E2_LOAD" : e2_mul ? "E2_MUL" : "E2_ALU";
        if (wb_rd != 0u && ra == wb_rd)
            return "WB";
        return "RF";
    }

    v4_shared_snapshot v4_shared_collect(void)
    {
        v4_shared_snapshot s = {};
        auto *core = m_dut->m_rtl->v->u_core;
        auto *issue = core->u_issue;

        s.issue_valid = issue->raw_issue_valid() != 0;
        s.issue_accept = s.issue_valid && issue->raw_issue_accept() != 0;
        s.issue_pc = issue->raw_issue_pc();
        s.issue_opcode = issue->raw_issue_opcode();
        s.issue_ra = issue->raw_issue_ra();
        s.issue_rb = issue->raw_issue_rb();
        s.issue_rd = issue->raw_issue_rd();
        s.issue_ra_value = issue->raw_issue_ra_value();
        s.issue_rb_value = issue->raw_issue_rb_value();

        s.e1_load = issue->raw_pipe_load_e1() && issue->raw_pipe_rd_e1() != 0u;
        s.e1_mul = issue->raw_pipe_mul_e1() && issue->raw_pipe_rd_e1() != 0u;
        s.e1_pc = issue->raw_pipe_pc_e1();
        s.e1_opcode = issue->raw_pipe_opcode_e1();
        s.e1_rd = issue->raw_pipe_rd_e1();
        s.e2_load = issue->raw_pipe_load_e2() && issue->raw_pipe_rd_e2() != 0u;
        s.e2_mul = issue->raw_pipe_mul_e2() && issue->raw_pipe_rd_e2() != 0u;
        s.e2_pc = issue->raw_pipe_pc_e2();
        s.e2_opcode = issue->raw_pipe_opcode_e2();
        s.e2_rd = issue->raw_pipe_rd_e2();
        s.e2_result = issue->raw_pipe_result_e2();
        s.wb_valid = issue->raw_valid_wb() != 0;
        s.wb_pc = issue->raw_pc_wb();
        s.wb_opcode = issue->raw_opcode_wb();
        s.wb_rd = issue->raw_rd_wb();
        s.wb_result = issue->raw_result_wb();

        const bool load = early_is_load(s.issue_opcode);
        const unsigned dep = early_dependency_mask(
            s.issue_opcode, s.issue_ra, s.issue_rb,
            s.e1_load, s.e1_mul, s.e1_rd,
            s.e2_load, s.e2_mul, s.e2_rd);
        s.dependency = dep;
        const uint32_t agu_addr = core->early_lsu_agu_addr_value();
        s.base_source = load ? early_source_name(
            s.issue_ra, s.e1_rd, s.e1_load, s.e1_mul,
            s.e2_rd, s.e2_load, s.e2_mul, s.wb_rd) : "NA";
        s.load_width = load ? early_width(s.issue_opcode) : 3u;
        s.tcm = load && agu_addr < 0x00010000u;
        s.aligned = !load || early_aligned(agu_addr, s.issue_opcode);
        s.base_ok = load && issue->early_base_ok_value() != 0;
        s.port_ready = load && core->early_mmu_accept_value() != 0 &&
                       !core->early_lsu_pending_value();
        s.early_candidate = core->early_lsu_candidate_value() != 0;
        s.early_launch = core->early_lsu_launch_value() != 0;
        s.early_live = core->early_lsu_live_value() != 0;
        s.early_hold = core->early_lsu_hold_valid_value() != 0;
        s.early_result_valid = core->early_result_valid_value() != 0;
        s.early_result_rd = core->early_result_rd_value();
        s.early_result_value = core->early_result_value_value();
        s.agu_addr = agu_addr;
        s.mem_addr = core->data_addr_value();
        s.mem_data = core->data_write_value();
        s.mem_wr = core->data_write_strobe_value();

        s.scoreboard_stall = issue->early_trace_scoreboard_stall() != 0;
        s.load_raw = issue->early_trace_load_raw() != 0;
        s.mul_raw = issue->early_trace_mul_raw() != 0;
        s.waw = issue->early_trace_waw() != 0;
        s.blanket = issue->early_trace_blanket() != 0;
        s.mem_request = core->raw_mem_request_value() != 0;
        s.mem_accept = core->raw_mem_accept_value() != 0;
        s.mem_ack = core->raw_mem_ack_value() != 0;

        s.lookup_accept = core->predictor_lookup_accept_value() != 0;
        // The request PC is the identity used by the predictor transaction;
        // predictor_pc_value() is only the speculative fetch register and may
        // have changed while a request was stalled.
        s.lookup_pc = core->predictor_lookup_request_pc_value();
        s.lookup_hit = core->predictor_lookup_hit_value() != 0;
        s.lookup_taken = core->predictor_lookup_taken_value() != 0;
        s.lookup_target = core->predictor_lookup_target_value();
        s.update_valid = core->predictor_update_valid_value() != 0;
        s.update_pc = core->predictor_update_pc_value();
        s.update_target = core->predictor_update_target_value();
        s.update_is_jal = core->predictor_update_is_jal_value() != 0;
        s.update_taken = core->predictor_update_taken_value() != 0;
        s.update_pred_taken = core->predictor_update_pred_taken_value() != 0;
        s.update_mispredict = core->predictor_update_mispredict_value() != 0;
        s.update_hit = core->predictor_update_hit_value() != 0;
        s.invalidate = core->predictor_invalidate_value() != 0;
        s.branch_request = core->branch_request_value() != 0;
        s.branch_mispredict = core->branch_mispredict_value() != 0;
        s.branch_flush = core->raw_branch_flush_value() != 0;
        s.commit_valid = issue->complete_valid0() != 0;
        s.commit_pc = issue->complete_pc0();
        s.commit_opcode = issue->complete_opcode0();

        s.normal_active = core->early_lsu_normal_active_value() != 0;
        s.normal_pending_conflict =
            core->early_lsu_pending_conflict_value() != 0;
        s.mem_unaligned_e1 = core->early_lsu_unaligned_e1_value() != 0;
        s.early_slot_free = core->early_lsu_slot_free_value() != 0;
        s.early_offer = core->early_lsu_candidate_value() != 0;
        s.early_accept = core->early_lsu_early_accept_value() != 0;
        s.early_fire = core->early_lsu_early_fire_value() != 0;
        s.early_response = core->early_lsu_response_value() != 0;
        s.normal_rd = core->early_lsu_normal_rd_value() != 0;
        s.normal_error = core->early_lsu_normal_error_value() != 0;
        s.lsu_opcode_valid = core->early_lsu_opcode_valid_value() != 0;
        s.normal_addr = core->early_lsu_normal_addr_value();
        s.early_addr = core->early_lsu_early_addr_value();
        s.early_request_addr = core->early_lsu_request_addr_value();
        s.lsu_opcode = core->early_lsu_opcode_value();
        s.lsu_pc = core->early_lsu_opcode_pc_value();
        s.lsu_ra = issue->raw_lsu_ra();
        s.lsu_rb = issue->raw_lsu_rb();
        s.lsu_ra_value = core->early_lsu_opcode_ra_value();
        s.lsu_rb_value = core->early_lsu_opcode_rb_value();
        s.fetch_response_valid = core->fetch_response_valid_value() != 0;
        s.fetch_skid_valid = core->fetch_skid_valid_value() != 0;
        s.fetch_decode_valid = core->fetch_decode_valid_value() != 0;
        s.fetch_decode_accept = core->fetch_decode_accept_value() != 0;
        s.fetch_decode_pred_taken =
            core->fetch_decode_pred_taken_value() != 0;
        s.fetch_decode_pc = core->fetch_decode_pc_value();
        s.fetch_decode_instr = core->fetch_decode_instr_value();
        s.fetch_response_drop = core->fetch_response_drop_value() != 0;
        s.fetch_icache_fetch = core->fetch_icache_fetch_value() != 0;
        s.fetch_stall = core->fetch_stall_value() != 0;
        return s;
    }

    void v4_shared_emit(const char *event, const v4_shared_snapshot &s)
    {
        if (!m_shared_event_fd)
            return;
        if (m_shared_event_rows >= m_shared_event_limit)
        {
            ++m_shared_event_dropped;
            return;
        }

        const auto b = [](bool value) { return value ? 1u : 0u; };
        std::ostringstream row;
        row << m_step_count << ',' << m_shared_iter_entries << ','
            << b(m_shared_roi_active) << ',' << event << ','
            ;
        const std::string kind(event);
        if (kind == "lookup")
        {
            row << s.lookup_pc << ',' << b(s.lookup_hit) << ','
                << b(s.lookup_taken) << ',' << s.lookup_target;
        }
        else if (kind == "update")
        {
            row << s.update_pc << ',' << s.update_target << ','
                << b(s.update_is_jal) << ',' << b(s.update_taken) << ','
                << b(s.update_pred_taken) << ',' << b(s.update_mispredict) << ','
                << b(s.update_hit);
        }
        else if (kind == "issue")
        {
            row << s.issue_pc << ',' << s.issue_opcode << ',' << s.issue_ra << ','
                << s.issue_rb << ',' << s.issue_rd << ',' << s.issue_ra_value << ','
                << s.issue_rb_value << ',' << s.base_source << ',' << s.load_width << ','
                << b(s.tcm) << ',' << b(s.aligned) << ',' << b(s.base_ok) << ','
                << b(s.port_ready) << ',' << b(s.early_candidate) << ','
                << b(s.early_launch) << ',' << s.agu_addr << ',' << s.mem_addr << ','
                << s.mem_data << ',' << s.mem_wr;
        }
        else if (kind == "load_stall")
        {
            row << s.issue_pc << ',' << s.issue_opcode << ',' << s.issue_ra << ','
                << s.issue_rb << ',' << s.issue_rd << ',' << s.issue_ra_value << ','
                << s.issue_rb_value << ',' << s.dependency << ','
                << b(s.scoreboard_stall) << ',' << b(s.load_raw) << ','
                << b(s.mul_raw) << ',' << b(s.waw) << ',' << b(s.blanket) << ','
                << b(s.e1_load) << ',' << b(s.e1_mul) << ',' << s.e1_pc << ','
                << s.e1_opcode << ',' << s.e1_rd << ',' << b(s.e2_load) << ','
                << b(s.e2_mul) << ',' << s.e2_pc << ',' << s.e2_opcode << ','
                << s.e2_rd << ',' << s.e2_result << ',' << b(s.wb_valid) << ','
                << s.wb_pc << ',' << s.wb_opcode << ',' << s.wb_rd << ','
                << s.wb_result << ',' << b(s.early_candidate) << ','
                << b(s.early_launch) << ',' << b(s.early_live) << ','
                << b(s.early_hold) << ',' << b(s.early_result_valid) << ','
                << s.early_result_rd << ',' << s.early_result_value;
        }
        else if (kind == "lsu")
        {
            row << b(s.mem_request) << ',' << b(s.mem_accept) << ','
                << b(s.mem_ack) << ',' << s.agu_addr << ',' << s.mem_addr << ','
                << s.mem_data << ',' << s.mem_wr << ',' << b(s.early_candidate) << ','
                << b(s.early_launch) << ',' << b(s.early_live) << ','
                << b(s.early_hold) << ',' << b(s.early_result_valid) << ','
                << s.early_result_rd << ',' << s.early_result_value;
        }
        else if (kind == "load_stage")
        {
            row << b(s.e1_load) << ',' << s.e1_pc << ',' << s.e1_opcode << ','
                << s.e1_rd << ',' << b(s.e2_load) << ',' << s.e2_pc << ','
                << s.e2_opcode << ',' << s.e2_rd << ',' << s.e2_result << ','
                << b(s.wb_valid) << ',' << s.wb_pc << ',' << s.wb_opcode << ','
                << s.wb_rd << ',' << s.wb_result << ',' << b(s.early_result_valid)
                << ',' << s.early_result_rd << ',' << s.early_result_value;
        }
        else if (kind == "control")
        {
            row << b(s.branch_request) << ',' << b(s.branch_mispredict) << ','
                << b(s.branch_flush);
        }
        std::fprintf(m_shared_event_fd, "%s\n", row.str().c_str());
        ++m_shared_event_rows;
    }

    void v4_shared_sample_pre(void)
    {
        if (!m_shared_observer_enabled || !m_shared_event_fd)
            return;
        if (m_shared_corrected_mode)
        {
            v4_corrected_sample_pre();
            return;
        }
        const v4_shared_snapshot s = v4_shared_collect();
        const bool load = early_is_load(s.issue_opcode);
        const bool wb_load = s.wb_valid && early_is_load(s.wb_opcode);
        const bool early_state_changed =
            s.early_result_valid != m_shared_prev_early_result_valid ||
            (s.early_result_valid &&
             s.early_result_rd != m_shared_prev_early_result_rd) ||
            s.early_live != m_shared_prev_early_live ||
            s.early_hold != m_shared_prev_early_hold;

        if (rst.read())
            v4_shared_emit("reset", s);
        if (s.issue_valid && s.issue_accept && load)
            v4_shared_emit("issue", s);
        if (s.scoreboard_stall && s.load_raw)
            v4_shared_emit("load_stall", s);
        if (s.early_launch || early_state_changed)
            v4_shared_emit("lsu", s);
        if (s.lookup_accept)
            v4_shared_emit("lookup", s);
        if (s.update_valid)
            v4_shared_emit("update", s);
        if (s.invalidate)
            v4_shared_emit("invalidate", s);
        if (s.branch_request || s.branch_mispredict ||
            (s.branch_flush && !m_shared_prev_branch_flush))
            v4_shared_emit("control", s);

        m_shared_prev_early_result_valid = s.early_result_valid;
        m_shared_prev_early_result_rd = s.early_result_rd;
        m_shared_prev_early_live = s.early_live;
        m_shared_prev_early_hold = s.early_hold;
        m_shared_prev_branch_flush = s.branch_flush;
    }

    void v4_shared_iteration_boundary(void)
    {
        if (!m_shared_observer_enabled)
            return;
        auto *issue = m_dut->m_rtl->v->u_core->u_issue;
        if (!issue->complete_valid0() || issue->complete_pc0() != 0x000020acu ||
            m_shared_last_iter_cycle == m_step_count)
            return;

        m_shared_last_iter_cycle = m_step_count;
        ++m_shared_iter_entries;
        if (!m_shared_roi_active &&
            m_shared_iter_entries == m_shared_warmup_iters + 1u)
        {
            m_shared_roi_active = true;
            m_shared_roi_start_cycle = m_step_count;
            std::printf("V4_SHARED_ROI start_iter=%u cycle=%llu\n",
                        m_shared_iter_entries,
                        static_cast<unsigned long long>(m_step_count));
        }
        else if (m_shared_roi_active &&
                 m_shared_iter_entries ==
                     m_shared_warmup_iters + m_shared_sample_iters + 1u)
        {
            m_shared_roi_active = false;
            m_shared_roi_end_cycle = m_step_count;
            m_shared_stop_requested = true;
            std::printf("V4_SHARED_ROI end_iter=%u cycle=%llu\n",
                        m_shared_iter_entries,
                        static_cast<unsigned long long>(m_step_count));
        }
    }

    void v4_shared_report(void)
    {
        if (!m_shared_observer_enabled)
            return;
        if (m_shared_event_fd)
        {
            std::fflush(m_shared_event_fd);
            std::fclose(m_shared_event_fd);
            m_shared_event_fd = NULL;
        }
        std::printf("%s rows=%llu dropped=%llu roi_start=%llu roi_end=%llu iters=%u\n",
                    m_shared_corrected_mode ? "V4_CORRECTED" : "V4_SHARED",
                    static_cast<unsigned long long>(m_shared_event_rows),
                    static_cast<unsigned long long>(m_shared_event_dropped),
                    static_cast<unsigned long long>(m_shared_roi_start_cycle),
                    static_cast<unsigned long long>(m_shared_roi_end_cycle),
                    m_shared_iter_entries);
        if (m_shared_event_dropped != 0u || m_shared_roi_end_cycle == 0u)
        {
            std::fprintf(stderr,
                         "%s closure failed: incomplete event stream or ROI\n",
                         m_shared_corrected_mode ? "V4_CORRECTED" : "V4_SHARED");
            m_closure_failure = true;
        }
        if (m_shared_corrected_mode)
        {
            std::printf("V4_CORRECTED association lookup=%llu fetch_issue=%llu update=%llu commit=%llu fetch_cancel=%llu branch_cancel=%llu lookup_unresolved=%llu update_unassociated=%llu update_duplicate=%llu pred_mismatch=%llu update_after_cancel=%llu commit_unassociated=%llu commit_order_error=%llu duplicate_consume=%llu decode_mismatch=%llu orphan_response=%llu\n",
                        static_cast<unsigned long long>(m_corrected_lookup_count),
                        static_cast<unsigned long long>(m_corrected_fetch_issue_count),
                        static_cast<unsigned long long>(m_corrected_update_count),
                        static_cast<unsigned long long>(m_corrected_commit_count),
                        static_cast<unsigned long long>(m_corrected_fetch_cancel_count),
                        static_cast<unsigned long long>(m_corrected_branch_cancel_count),
                        static_cast<unsigned long long>(m_corrected_lookup_unresolved),
                        static_cast<unsigned long long>(m_corrected_update_unassociated),
                        static_cast<unsigned long long>(m_corrected_update_duplicate),
                        static_cast<unsigned long long>(m_corrected_update_pred_mismatch),
                        static_cast<unsigned long long>(m_corrected_update_after_cancel),
                        static_cast<unsigned long long>(m_corrected_commit_unassociated),
                        static_cast<unsigned long long>(m_corrected_commit_order_error),
                        static_cast<unsigned long long>(m_corrected_duplicate_token_consume),
                        static_cast<unsigned long long>(m_corrected_decode_token_mismatch),
                        static_cast<unsigned long long>(m_corrected_orphan_response));
            if (m_corrected_update_unassociated != 0u ||
                m_corrected_update_duplicate != 0u ||
                m_corrected_update_pred_mismatch != 0u ||
                m_corrected_update_after_cancel != 0u ||
                m_corrected_duplicate_token_consume != 0u ||
                m_corrected_decode_token_mismatch != 0u)
            {
                std::fprintf(stderr,
                             "V4_CORRECTED closure failed: dynamic token association\n");
                m_closure_failure = true;
            }
        }
    }

    static bool corrected_is_lw(uint32_t opcode)
    {
        return (opcode & 0x7fu) == 0x03u && ((opcode >> 12) & 0x7u) == 2u;
    }

    static bool corrected_is_control(uint32_t opcode)
    {
        const uint32_t major = opcode & 0x7fu;
        return major == 0x63u || major == 0x6fu || major == 0x67u;
    }

    static bool corrected_base_allowed(const char *source)
    {
        return source && (std::string(source) == "X0" ||
                          std::string(source) == "RF" ||
                          std::string(source) == "WB");
    }

    void corrected_emit_payload(const char *event, const std::string &payload)
    {
        if (!m_shared_event_fd)
            return;
        if (m_shared_event_rows >= m_shared_event_limit)
        {
            ++m_shared_event_dropped;
            return;
        }
        std::fprintf(m_shared_event_fd, "%llu,%u,%u,%s",
                     static_cast<unsigned long long>(m_step_count),
                     m_shared_iter_entries, m_shared_roi_active ? 1u : 0u,
                     event);
        if (!payload.empty())
            std::fprintf(m_shared_event_fd, ",%s", payload.c_str());
        std::fputc('\n', m_shared_event_fd);
        ++m_shared_event_rows;
    }

    uint64_t corrected_dynamic_id(uint32_t pc) const
    {
        for (const auto &item : m_corrected_dynamic_insts)
            if (item.pc == pc)
                return item.id;
        return 0u;
    }

    uint64_t corrected_fetch_id(uint32_t pc) const
    {
        for (const auto &item : m_corrected_fetch_tokens)
            if (item.pc == pc)
                return item.id;
        return 0u;
    }

    void corrected_discard_fetch_before(uint32_t pc)
    {
        // The TCM fixture can accept a request on the same edge as a response.
        // A request that is not represented by a later decode item is kept as
        // an explicit unresolved lookup, rather than being silently matched
        // by a PC-keyed popleft operation.
        while (!m_corrected_fetch_tokens.empty() &&
               m_corrected_fetch_tokens.front().pc != pc)
        {
            const corrected_fetch_token item = m_corrected_fetch_tokens.front();
            m_corrected_fetch_tokens.pop_front();
            m_corrected_cancelled_ids[item.id] = item.pc;
            ++m_corrected_lookup_unresolved;
            if (m_corrected_unresolved_reported < 64u)
            {
                std::ostringstream row;
                row << item.id << ',' << item.pc << ",superseded_before_decode";
                corrected_emit_payload("lookup_unresolved", row.str());
                ++m_corrected_unresolved_reported;
            }
        }
    }

    void corrected_cancel_fetch(const char *reason)
    {
        while (!m_corrected_fetch_tokens.empty())
        {
            const corrected_fetch_token item = m_corrected_fetch_tokens.front();
            m_corrected_fetch_tokens.pop_front();
            m_corrected_cancelled_ids[item.id] = item.pc;
            ++m_corrected_fetch_cancel_count;
            std::ostringstream row;
            row << item.id << ',' << item.pc << ',' << reason;
            corrected_emit_payload("fetch_cancel", row.str());
        }
    }

    void corrected_cancel_younger(std::size_t branch_index, const char *reason)
    {
        while (m_corrected_dynamic_insts.size() > branch_index + 1u)
        {
            const corrected_dynamic_inst item =
                m_corrected_dynamic_insts.back();
            m_corrected_dynamic_insts.pop_back();
            m_corrected_cancelled_ids[item.id] = item.pc;
            std::ostringstream row;
            row << item.id << ',' << item.pc << ',' << reason;
            corrected_emit_payload("dynamic_cancel", row.str());
        }
    }

    void corrected_cancel_younger_branch(std::size_t branch_index,
                                         const char *reason)
    {
        while (m_corrected_branch_tokens.size() > branch_index + 1u)
        {
            const corrected_branch_token item =
                m_corrected_branch_tokens.back();
            m_corrected_branch_tokens.pop_back();
            m_corrected_cancelled_ids[item.id] = item.pc;
            ++m_corrected_branch_cancel_count;
            std::ostringstream row;
            row << item.id << ',' << item.pc << ',' << reason;
            corrected_emit_payload("branch_dynamic_cancel", row.str());
        }
    }

    bool corrected_model_offer(const v4_shared_snapshot &s) const
    {
        if (!s.issue_valid || !s.issue_accept || !corrected_is_lw(s.issue_opcode) ||
            s.issue_rd == 0u || !s.lsu_opcode_valid ||
            s.lsu_pc != s.issue_pc || s.lsu_opcode != s.issue_opcode)
            return false;
        return corrected_base_allowed(s.base_source) &&
               ((s.normal_addr & 3u) == 0u) &&
               s.normal_addr < 0x00010000u &&
               !s.normal_active && !s.normal_pending_conflict &&
               !s.mem_unaligned_e1 && s.early_slot_free;
    }

    bool corrected_model_known(const v4_shared_snapshot &s) const
    {
        return s.issue_valid && s.issue_accept && corrected_is_lw(s.issue_opcode) &&
               s.lsu_opcode_valid && s.lsu_pc == s.issue_pc &&
               s.lsu_opcode == s.issue_opcode;
    }

    void corrected_emit_load_issue(const v4_shared_snapshot &s, uint64_t id)
    {
        const bool known = corrected_model_known(s);
        const bool model_offer = known && corrected_model_offer(s);
        const bool model_fire = model_offer && s.early_accept;
        const bool true_tcm = s.normal_addr < 0x00010000u;
        const bool true_aligned = ((s.normal_addr & 3u) == 0u);
        std::ostringstream row;
        row << id << ',' << s.issue_pc << ',' << s.issue_opcode << ','
            << s.issue_ra << ',' << s.issue_rb << ',' << s.issue_rd << ','
            << s.base_source << ',' << s.load_width << ',' << s.normal_addr << ','
            << s.early_addr << ',' << s.early_request_addr << ','
            << (true_tcm ? 1u : 0u) << ',' << (true_aligned ? 1u : 0u) << ','
            << (s.base_ok ? 1u : 0u) << ','
            << (s.normal_active ? 1u : 0u) << ','
            << (s.normal_pending_conflict ? 1u : 0u) << ','
            << (s.mem_unaligned_e1 ? 1u : 0u) << ','
            << (s.early_slot_free ? 1u : 0u) << ','
            << (s.early_offer ? 1u : 0u) << ','
            << (s.early_accept ? 1u : 0u) << ','
            << (s.early_fire ? 1u : 0u) << ','
            << (s.early_response ? 1u : 0u) << ','
            << (s.normal_rd ? 1u : 0u) << ','
            << (s.normal_error ? 1u : 0u) << ','
            << (known ? 1u : 0u) << ',' << (model_offer ? 1u : 0u) << ','
            << (model_fire ? 1u : 0u) << ','
            << (s.lsu_opcode_valid ? 1u : 0u) << ',' << s.lsu_pc << ','
            << s.lsu_opcode << ',' << s.lsu_ra_value << ',' << s.lsu_rb_value << ','
            << (s.early_live ? 1u : 0u) << ',' << (s.early_hold ? 1u : 0u) << ','
            << (s.early_result_valid ? 1u : 0u) << ',' << s.early_result_rd << ','
            << s.early_result_value;
        corrected_emit_payload("load_issue", row.str());
    }

    void corrected_emit_load_stall(const v4_shared_snapshot &s, uint64_t id)
    {
        const char *consumer = early_consumer_name(s.issue_opcode, s.dependency);
        const bool e1_ready = s.e1_load && s.early_result_valid &&
                              s.early_result_rd == s.e1_rd;
        // e2_result is a value, not a valid bit.  A zero load result is still
        // a produced result; the stage's load-valid qualification is the
        // available observer-side readiness indication.
        const bool e2_ready = s.e2_load;
        const char *producer_state = "none";
        if (s.dependency == 3u)
            producer_state = (e1_ready || e2_ready) ? "both_ready" : "both_not_ready";
        else if ((s.dependency & 1u) != 0u)
            producer_state = e1_ready ? "E1_ready" : "E1_not_ready";
        else if ((s.dependency & 2u) != 0u)
            producer_state = e1_ready ? "E1_ready" : e2_ready ? "E2_ready" : "E2_not_ready";
        else if (s.wb_valid && s.wb_rd != 0u)
            producer_state = "WB_ready";

        const uint64_t e1_id = corrected_dynamic_id(s.e1_pc);
        const uint64_t e2_id = corrected_dynamic_id(s.e2_pc);
        const uint64_t wb_id = corrected_dynamic_id(s.wb_pc);
        std::ostringstream row;
        row << id << ',' << s.issue_pc << ',' << s.issue_opcode << ','
            << s.issue_ra << ',' << s.issue_rb << ',' << s.issue_rd << ','
            << consumer << ',' << s.dependency << ','
            << (s.scoreboard_stall ? 1u : 0u) << ',' << (s.load_raw ? 1u : 0u) << ','
            << (s.mul_raw ? 1u : 0u) << ',' << (s.waw ? 1u : 0u) << ','
            << (s.blanket ? 1u : 0u) << ',' << s.base_source << ','
            << s.load_width << ',' << s.normal_addr << ',' << s.early_addr << ','
            << (s.normal_addr < 0x00010000u ? 1u : 0u) << ','
            << (((s.normal_addr & 3u) == 0u) ? 1u : 0u) << ','
            << (s.base_ok ? 1u : 0u) << ','
            << (s.normal_active ? 1u : 0u) << ','
            << (s.normal_pending_conflict ? 1u : 0u) << ','
            << (s.mem_unaligned_e1 ? 1u : 0u) << ','
            << (s.early_slot_free ? 1u : 0u) << ','
            << (s.early_offer ? 1u : 0u) << ','
            << (s.early_accept ? 1u : 0u) << ','
            << (s.early_fire ? 1u : 0u) << ','
            << (s.early_response ? 1u : 0u) << ','
            << (s.early_result_valid ? 1u : 0u) << ',' << s.early_result_rd << ','
            << s.early_result_value << ',' << s.e1_pc << ',' << s.e1_opcode << ','
            << s.e1_rd << ',' << (s.e1_load ? 1u : 0u) << ','
            << (s.e1_mul ? 1u : 0u) << ',' << s.e2_pc << ',' << s.e2_opcode << ','
            << s.e2_rd << ',' << (s.e2_load ? 1u : 0u) << ','
            << (s.e2_mul ? 1u : 0u) << ',' << s.e2_result << ',' << s.wb_pc << ','
            << s.wb_opcode << ',' << s.wb_rd << ',' << (s.wb_valid ? 1u : 0u) << ','
            << s.wb_result << ',' << e1_id << ',' << e2_id << ',' << wb_id << ','
            << producer_state;
        corrected_emit_payload("load_stall", row.str());
    }

    void corrected_emit_lsu(const v4_shared_snapshot &s)
    {
        std::ostringstream row;
        row << (s.normal_active ? 1u : 0u) << ','
            << (s.normal_pending_conflict ? 1u : 0u) << ','
            << (s.mem_unaligned_e1 ? 1u : 0u) << ','
            << (s.early_slot_free ? 1u : 0u) << ','
            << (s.early_offer ? 1u : 0u) << ','
            << (s.early_accept ? 1u : 0u) << ','
            << (s.early_fire ? 1u : 0u) << ','
            << (s.early_response ? 1u : 0u) << ','
            << (s.normal_rd ? 1u : 0u) << ',' << (s.normal_error ? 1u : 0u) << ','
            << s.normal_addr << ',' << s.early_addr << ',' << s.early_request_addr << ','
            << (s.mem_request ? 1u : 0u) << ',' << (s.mem_accept ? 1u : 0u) << ','
            << (s.mem_ack ? 1u : 0u) << ',' << s.mem_addr << ',' << s.mem_data << ','
            << s.mem_wr << ',' << (s.early_live ? 1u : 0u) << ','
            << (s.early_hold ? 1u : 0u) << ','
            << (s.early_result_valid ? 1u : 0u) << ',' << s.early_result_rd << ','
            << s.early_result_value << ',' << (s.lsu_opcode_valid ? 1u : 0u) << ','
            << s.lsu_pc << ',' << s.lsu_opcode;
        corrected_emit_payload("lsu_state", row.str());
    }

    void v4_corrected_sample_pre(void)
    {
        if (!m_shared_observer_enabled || !m_shared_corrected_mode ||
            !m_shared_event_fd)
            return;

        const v4_shared_snapshot s = v4_shared_collect();
        if (rst.read())
        {
            m_corrected_fetch_tokens.clear();
            m_corrected_dynamic_insts.clear();
            m_corrected_branch_tokens.clear();
            m_corrected_cancelled_ids.clear();
            corrected_emit_payload("reset", "1");
            m_corrected_prev_response_valid = s.fetch_response_valid;
            m_corrected_prev_skid_valid = s.fetch_skid_valid;
            m_corrected_prev_decode_valid = s.fetch_decode_valid;
            m_corrected_prev_fetch_drop = s.fetch_response_drop;
            return;
        }

        if (s.invalidate)
        {
            corrected_emit_payload("invalidate", "1");
            corrected_cancel_fetch("invalidate");
            while (!m_corrected_branch_tokens.empty())
            {
                const corrected_branch_token item =
                    m_corrected_branch_tokens.front();
                m_corrected_branch_tokens.pop_front();
                m_corrected_cancelled_ids[item.id] = item.pc;
                ++m_corrected_branch_cancel_count;
            }
        }
        if (s.fetch_response_drop &&
            (s.fetch_response_valid || s.fetch_skid_valid) &&
            !m_corrected_prev_fetch_drop)
        {
            std::ostringstream row;
            row << (s.fetch_response_valid ? 1u : 0u) << ','
                << (s.fetch_skid_valid ? 1u : 0u);
            corrected_emit_payload("fetch_drop", row.str());
            corrected_cancel_fetch("response_drop");
        }

        if (s.lookup_accept)
        {
            corrected_fetch_token item = {};
            item.id = ++m_corrected_next_id;
            item.pc = s.lookup_pc;
            item.lookup_pred_taken = s.lookup_taken;
            item.response_seen = false;
            m_corrected_fetch_tokens.push_back(item);
            ++m_corrected_lookup_count;
            std::ostringstream row;
            row << item.id << ',' << s.lookup_pc << ','
                << (s.lookup_hit ? 1u : 0u) << ','
                << (s.lookup_taken ? 1u : 0u) << ',' << s.lookup_target;
            corrected_emit_payload("lookup", row.str());
        }

        const bool response_rise = s.fetch_response_valid &&
                                   !m_corrected_prev_response_valid;
        const bool skid_rise = s.fetch_skid_valid && !m_corrected_prev_skid_valid;
        if ((response_rise || skid_rise) &&
            (m_shared_roi_active || skid_rise || s.fetch_response_drop))
        {
            uint64_t id = 0u;
            uint32_t pc = 0u;
            if (!m_corrected_fetch_tokens.empty())
            {
                id = m_corrected_fetch_tokens.front().id;
                pc = m_corrected_fetch_tokens.front().pc;
                m_corrected_fetch_tokens.front().response_seen = true;
            }
            else
                ++m_corrected_orphan_response;
            std::ostringstream row;
            row << id << ',' << pc << ',' << (response_rise ? 1u : 0u) << ','
                << (skid_rise ? 1u : 0u) << ','
                << (s.fetch_response_drop ? 1u : 0u);
            corrected_emit_payload("fetch_response", row.str());
        }

        const bool decode_payload_changed =
            s.fetch_decode_valid != m_corrected_prev_decode_valid ||
            s.fetch_decode_pc != m_corrected_prev_decode_pc ||
            s.fetch_decode_instr != m_corrected_prev_decode_instr ||
            s.fetch_decode_pred_taken != m_corrected_prev_decode_pred;
        if (s.fetch_decode_valid && decode_payload_changed &&
            (m_shared_roi_active || !s.fetch_decode_accept))
        {
            const uint64_t id = corrected_fetch_id(s.fetch_decode_pc);
            std::ostringstream row;
            row << id << ',' << s.fetch_decode_pc << ',' << s.fetch_decode_instr << ','
                << (s.fetch_decode_pred_taken ? 1u : 0u) << ','
                << (s.fetch_decode_accept ? 1u : 0u);
            corrected_emit_payload("fetch_present", row.str());
        }

        uint64_t current_issue_id = 0u;
        if (s.fetch_decode_valid && s.fetch_decode_accept)
        {
            std::string status = "unresolved";
            corrected_discard_fetch_before(s.fetch_decode_pc);
            if (!m_corrected_fetch_tokens.empty() &&
                m_corrected_fetch_tokens.front().pc == s.fetch_decode_pc)
            {
                current_issue_id = m_corrected_fetch_tokens.front().id;
                const bool pred_match =
                    m_corrected_fetch_tokens.front().lookup_pred_taken ==
                    s.fetch_decode_pred_taken;
                if (!pred_match)
                    ++m_corrected_decode_token_mismatch;
                status = pred_match ? "ok" : "lookup_pred_mismatch";
                m_corrected_fetch_tokens.pop_front();
            }
            else
                ++m_corrected_decode_token_mismatch;

            ++m_corrected_fetch_issue_count;
            std::ostringstream row;
            row << current_issue_id << ',' << s.fetch_decode_pc << ','
                << s.fetch_decode_instr << ','
                << (s.fetch_decode_pred_taken ? 1u : 0u) << ',' << status;
            if (m_shared_roi_active || current_issue_id == 0u || status != "ok")
                corrected_emit_payload("fetch_issue", row.str());
            if (current_issue_id != 0u)
            {
                // Only control-flow instructions need a token for predictor
                // training.  A general instruction queue cannot be used for
                // update identity: younger wrong-path instructions and
                // repeated PCs make PC-only matching ambiguous.
                if (corrected_is_control(s.fetch_decode_instr))
                {
                    corrected_branch_token item = {};
                    item.id = current_issue_id;
                    item.pc = s.fetch_decode_pc;
                    item.pred_taken = s.fetch_decode_pred_taken;
                    m_corrected_branch_tokens.push_back(item);
                }
            }
        }

        if (m_shared_roi_active && s.issue_valid && s.issue_accept &&
            early_is_load(s.issue_opcode))
            corrected_emit_load_issue(s, corrected_dynamic_id(s.issue_pc));
        if (m_shared_roi_active && s.scoreboard_stall && s.load_raw)
            corrected_emit_load_stall(s, corrected_dynamic_id(s.issue_pc));

        const bool lsu_state_changed =
            s.normal_active != m_corrected_prev_normal_active ||
            s.normal_pending_conflict != m_corrected_prev_pending_conflict ||
            s.early_slot_free != m_corrected_prev_slot_free ||
            s.early_offer != m_corrected_prev_early_offer ||
            s.early_accept != m_corrected_prev_early_accept ||
            s.early_fire != m_corrected_prev_early_fire ||
            s.early_response != m_corrected_prev_early_response ||
            s.normal_rd != m_corrected_prev_normal_rd ||
            s.normal_error != m_corrected_prev_normal_error ||
            s.mem_request != m_shared_prev_mem_request ||
            s.mem_addr != m_shared_prev_mem_addr ||
            s.mem_data != m_shared_prev_mem_data ||
            s.mem_wr != m_shared_prev_mem_wr;
        if ((lsu_state_changed || s.mem_accept || s.mem_ack) &&
            (m_shared_roi_active || s.early_offer || s.early_fire ||
             s.early_response))
            corrected_emit_lsu(s);

        if (s.update_valid)
        {
            ++m_corrected_update_count;
            std::size_t update_index = m_corrected_branch_tokens.size();
            for (std::size_t i = 0; i < m_corrected_branch_tokens.size(); ++i)
            {
                if (m_corrected_branch_tokens[i].pc == s.update_pc)
                {
                    update_index = i;
                    break;
                }
            }

            uint64_t id = 0u;
            std::string status = "unassociated";
            int pred_state = -1;
            const bool update_matched =
                update_index < m_corrected_branch_tokens.size();
            if (update_matched)
            {
                const corrected_branch_token item =
                    m_corrected_branch_tokens[update_index];
                id = item.id;
                status = "ok";
                pred_state = item.pred_taken == s.update_pred_taken ? 1 : 0;
                if (pred_state == 0)
                    ++m_corrected_update_pred_mismatch;
            }
            else
            {
                for (const auto &cancelled : m_corrected_cancelled_ids)
                {
                    if (cancelled.second == s.update_pc)
                    {
                        id = cancelled.first;
                        status = "canceled";
                        ++m_corrected_update_after_cancel;
                        break;
                    }
                }
                if (status == "unassociated")
                    ++m_corrected_update_unassociated;
            }

            std::ostringstream row;
            row << id << ',' << s.update_pc << ',' << s.update_target << ','
                << (s.update_is_jal ? 1u : 0u) << ','
                << (s.update_taken ? 1u : 0u) << ','
                << (s.update_pred_taken ? 1u : 0u) << ','
                << (s.update_mispredict ? 1u : 0u) << ','
                << (s.update_hit ? 1u : 0u) << ',' << status << ',' << pred_state;
            corrected_emit_payload("update", row.str());

            if (update_matched && s.update_mispredict)
            {
                corrected_cancel_younger_branch(update_index, "branch_squash");
                corrected_cancel_fetch("branch_squash");
            }
            if (update_matched)
            {
                // A branch update consumes exactly the branch token that
                // caused it.  Younger tokens were canceled above when the
                // update redirected control flow.
                m_corrected_branch_tokens.erase(
                    m_corrected_branch_tokens.begin() + update_index);
            }
        }

        if (s.commit_valid)
        {
            ++m_corrected_commit_count;
            std::ostringstream row;
            // Commit is retained as a retirement observation for the load
            // and frontend evidence.  It is not used for predictor identity:
            // the predictor update is the architectural training event and
            // its branch token was already consumed above.
            row << 0u << ',' << s.commit_pc << ',' << s.commit_opcode
                << ",observed";
            if (m_shared_roi_active)
                corrected_emit_payload("commit", row.str());
        }

        if (m_shared_roi_active &&
            (s.branch_request || s.branch_mispredict || s.branch_flush))
        {
            std::ostringstream row;
            row << (s.branch_request ? 1u : 0u) << ','
                << (s.branch_mispredict ? 1u : 0u) << ','
                << (s.branch_flush ? 1u : 0u) << ',' << s.update_pc;
            corrected_emit_payload("control", row.str());
        }

        m_corrected_prev_response_valid = s.fetch_response_valid;
        m_corrected_prev_skid_valid = s.fetch_skid_valid;
        m_corrected_prev_decode_valid = s.fetch_decode_valid;
        m_corrected_prev_fetch_drop = s.fetch_response_drop;
        m_corrected_prev_decode_pc = s.fetch_decode_pc;
        m_corrected_prev_decode_instr = s.fetch_decode_instr;
        m_corrected_prev_decode_pred = s.fetch_decode_pred_taken;
        m_corrected_prev_normal_active = s.normal_active;
        m_corrected_prev_pending_conflict = s.normal_pending_conflict;
        m_corrected_prev_slot_free = s.early_slot_free;
        m_corrected_prev_early_offer = s.early_offer;
        m_corrected_prev_early_accept = s.early_accept;
        m_corrected_prev_early_fire = s.early_fire;
        m_corrected_prev_early_response = s.early_response;
        m_corrected_prev_normal_rd = s.normal_rd;
        m_corrected_prev_normal_error = s.normal_error;
        m_shared_prev_mem_request = s.mem_request;
        m_shared_prev_mem_addr = s.mem_addr;
        m_shared_prev_mem_data = s.mem_data;
        m_shared_prev_mem_wr = s.mem_wr;
    }

    void early_count(const std::string &key)
    {
        ++m_early_counts[key];
    }

    void early_flush_stall_run(void)
    {
        if (m_early_stall_run == 0u)
            return;
        early_count(std::string("STALL_RUN|length=") +
                    (m_early_stall_run == 1u ? "1" :
                     m_early_stall_run == 2u ? "2" : "3plus"));
        m_early_stall_run = 0u;
    }

    void early_flush_l2l_pair_run(void)
    {
        if (m_early_l2l_pair_run == 0u)
            return;
        early_count(std::string("L2L_PAIR_RUN|length=") +
                    (m_early_l2l_pair_run == 1u ? "1" :
                     m_early_l2l_pair_run == 2u ? "2" : "3plus"));
        if (m_early_l2l_pair_run > m_early_l2l_max_pair_run)
            m_early_l2l_max_pair_run = m_early_l2l_pair_run;
        m_early_l2l_pair_run = 0u;
    }

    void early_reset_roi_state(void)
    {
        m_early_stall_run = 0u;
        m_early_l2l_pair_run = 0u;
        m_early_l2l_max_pair_run = 0u;
        m_early_l2l_last_a_pc = 0u;
        m_early_l2l_last_b_pc = 0u;
        m_early_last_load_valid = false;
        m_early_last_load_pc = 0u;
        m_early_last_load_rd = 0u;
        m_early_last_load_chain = 0u;
        m_early_instr_since_last_load = 0u;
    }

    void early_iteration_boundary(void)
    {
        if (!m_early_observer_enabled)
            return;
        auto *core = m_dut->m_rtl->v->u_core;
        auto *issue = core->u_issue;
        // The fixed 516-iteration ELF calls iterate() only once.  The
        // committed s1 increment in the loop body is the repeatable
        // per-iteration boundary for this observer.
        if (!issue->complete_valid0() || issue->complete_pc0() != 0x000020acu ||
            m_early_last_iter_cycle == m_step_count)
            return;

        m_early_last_iter_cycle = m_step_count;
        ++m_early_iter_entries;
        if (!m_early_roi_active && m_early_iter_entries == m_early_warmup_iters + 1u)
        {
            m_early_roi_active = true;
            m_early_roi_start_cycle = m_step_count;
            early_reset_roi_state();
            std::printf("EARLY_ROI start_iter=%u cycle=%llu\n",
                        m_early_iter_entries,
                        static_cast<unsigned long long>(m_step_count));
        }
        else if (m_early_roi_active &&
                 m_early_iter_entries == m_early_warmup_iters + m_early_sample_iters + 1u)
        {
            early_flush_stall_run();
            early_flush_l2l_pair_run();
            m_early_roi_active = false;
            m_early_roi_end_cycle = m_step_count;
            m_early_stop_requested = true;
            std::printf("EARLY_ROI end_iter=%u cycle=%llu\n",
                        m_early_iter_entries,
                        static_cast<unsigned long long>(m_step_count));
        }
    }

    void early_classify_pre(void)
    {
        if (!m_early_observer_enabled || !m_early_roi_active)
            return;

        auto *core = m_dut->m_rtl->v->u_core;
        auto *issue = core->u_issue;
        const uint32_t opcode = issue->raw_issue_opcode();
        const uint32_t ra = issue->raw_issue_ra();
        const uint32_t rb = issue->raw_issue_rb();
        const uint32_t e1_rd = issue->raw_pipe_rd_e1();
        const uint32_t e2_rd = issue->raw_pipe_rd_e2();
        const uint32_t wb_rd = issue->raw_rd_wb();
        const bool e1_load = issue->raw_pipe_load_e1() && e1_rd != 0u;
        const bool e1_mul = issue->raw_pipe_mul_e1() && e1_rd != 0u;
        const bool e2_load = issue->raw_pipe_load_e2() && e2_rd != 0u;
        const bool e2_mul = issue->raw_pipe_mul_e2() && e2_rd != 0u;
        const unsigned dep = early_dependency_mask(opcode, ra, rb, e1_load, e1_mul, e1_rd,
                                                   e2_load, e2_mul, e2_rd);
        const bool score_stall = issue->early_trace_scoreboard_stall();

        if (score_stall)
        {
            ++m_early_stall_run;
            const bool load_raw = issue->early_trace_load_raw();
            const bool mul_raw = issue->early_trace_mul_raw();
            const bool mixed = load_raw && mul_raw;
            const bool blanket = issue->early_trace_blanket();
            const bool waw = issue->early_trace_waw();
            const bool false_only = issue->early_trace_false_only();
            const bool field_blocker = issue->early_trace_unused_rs1() ||
                                       issue->early_trace_unused_rs2() ||
                                       issue->early_trace_invalid_rd() ||
                                       issue->early_trace_x0_field() ||
                                       issue->early_trace_system_or_invalid();
            const char *bucket = blanket ? "blanket" : mixed ? "mixed-raw" :
                                 load_raw ? "load-raw" : mul_raw ? "mul-raw" :
                                 waw ? "waw" : false_only ? "false-only" : "other";
            early_count(std::string("STALL_BUCKET|bucket=") + bucket);

            if (load_raw || mul_raw)
            {
                const char *consumer = early_consumer_name(opcode, dep);
                const char *dep_text = early_dep_name(dep);
                const char *width = early_width_name(early_is_store(opcode) ? early_width(opcode) : 3u);
                const char *blocker = waw ? "waw" : field_blocker ? "other" : "none";
                if (load_raw)
                {
                    early_count(std::string("STALL_DETAIL|producer=load|consumer=") +
                                consumer + "|dependency=" + dep_text + "|width=" + width +
                                "|blocker=" + blocker);
                }
                if (mul_raw)
                {
                    early_count(std::string("STALL_DETAIL|producer=mul|consumer=") +
                                consumer + "|dependency=" + dep_text + "|width=" + width +
                                "|blocker=" + blocker);
                }

                const bool safe_store_data = early_is_store(opcode) && dep == 2u &&
                    !blanket && !waw && !false_only && !field_blocker;
                if (safe_store_data && load_raw)
                    early_count(std::string("STORE_DATA_CANDIDATE|producer=load|width=") +
                                early_width_name(early_width(opcode)));
                if (safe_store_data && mul_raw)
                    early_count(std::string("STORE_DATA_CANDIDATE|producer=mul|width=") +
                                early_width_name(early_width(opcode)));
            }

            if (early_is_load(opcode) && load_raw && (dep & 1u) && e1_load &&
                !issue->early_trace_waw() && !issue->early_trace_blanket() &&
                !issue->early_trace_false_only() &&
                !issue->early_trace_unused_rs1() && !issue->early_trace_unused_rs2() &&
                !issue->early_trace_invalid_rd() &&
                !issue->early_trace_system_or_invalid())
            {
                const uint32_t a_pc = issue->raw_pipe_pc_e1();
                const uint32_t b_pc = issue->raw_issue_pc();
                early_count(std::string("L2L_CANDIDATE|dependency=") + early_dep_name(dep));
                if (m_early_l2l_pair_run != 0u &&
                    m_early_l2l_last_a_pc == a_pc && m_early_l2l_last_b_pc == b_pc)
                    ++m_early_l2l_pair_run;
                else
                {
                    early_flush_l2l_pair_run();
                    m_early_l2l_pair_run = 1u;
                    m_early_l2l_last_a_pc = a_pc;
                    m_early_l2l_last_b_pc = b_pc;
                }
                early_count(std::string("L2L_PAIR|a_pc=") +
                            std::to_string(a_pc) + "|b_pc=" + std::to_string(b_pc));
            }
        }
        else
        {
            early_flush_stall_run();
            if (m_early_l2l_pair_run != 0u)
                early_flush_l2l_pair_run();
        }

        const bool issue_valid = issue->raw_decode_valid() && issue->raw_issue_valid();
        const bool issue_accept = issue_valid && issue->raw_issue_accept();
        if (issue_accept)
        {
            if (early_is_load(opcode))
            {
                const uint32_t address = core->early_lsu_agu_addr_value();
                const bool tcm = address < 0x00010000u;
                const bool aligned = early_aligned(address, opcode);
                const bool port_ready = core->early_mmu_accept_value() != 0 &&
                                        !core->early_lsu_pending_value();
                const char *source = early_source_name(
                    ra, e1_rd, e1_load, e1_mul, e2_rd, e2_load, e2_mul, wb_rd);
                early_count(std::string("LOAD_OP|base_source=") + source);
                if (!tcm)
                    early_count("LOAD_OP|status=non-tcm");
                else if (!aligned)
                    early_count("LOAD_OP|status=misaligned");
                else if (!port_ready)
                    early_count("LOAD_OP|status=port-or-pending");
                else
                {
                    early_count("LOAD_OP|status=tcm-aligned-ready");
                    if (std::string(source) != "E1_LOAD" && std::string(source) != "E1_MUL" &&
                        std::string(source) != "E2_LOAD" && std::string(source) != "E2_MUL")
                        early_count("LOAD_OP|status=tcm-aligned-fast-source");
                    else
                        early_count("LOAD_OP|status=tcm-aligned-memory-source");
                }
            }

            if (early_is_load(opcode) && m_early_last_load_valid &&
                m_early_last_load_rd != 0u && early_uses_rs1(opcode) &&
                ra == m_early_last_load_rd)
            {
                const uint64_t gap = m_early_instr_since_last_load;
                early_count(std::string("L2L_ADJACENCY|gap=") +
                            (gap == 0u ? "0" : gap == 1u ? "1" : "2plus"));
                if (gap == 0u)
                {
                    early_count("L2L_ADJACENCY|kind=adjacent-load-address");
                    if (m_early_last_load_chain >= 2u)
                        early_count("L2L_CHAIN|length=3plus");
                }
            }

            if (early_is_load(opcode))
            {
                uint32_t chain = 1u;
                if (m_early_last_load_valid && m_early_instr_since_last_load == 0u &&
                    m_early_last_load_rd != 0u && ra == m_early_last_load_rd)
                    chain = m_early_last_load_chain + 1u;
                m_early_last_load_valid = true;
                m_early_last_load_pc = issue->raw_issue_pc();
                m_early_last_load_rd = issue->raw_issue_rd();
                m_early_last_load_chain = chain;
                m_early_instr_since_last_load = 0u;
            }
            else if (m_early_last_load_valid && m_early_instr_since_last_load < 3u)
                ++m_early_instr_since_last_load;
        }
    }

    void early_trace_sample(const char *phase)
    {
        if (!m_early_observer_enabled || !m_early_roi_active || !m_early_trace_fd)
            return;

        auto *core = m_dut->m_rtl->v->u_core;
        auto *issue = core->u_issue;
        auto *tcm = m_dut->m_rtl->v->u_tcm;
        const uint32_t opcode = issue->raw_issue_opcode();
        const bool issue_event = issue->raw_issue_valid() &&
            (issue->raw_issue_accept() || issue->raw_scoreboard_hazard()) &&
            (early_is_load(opcode) || early_is_store(opcode) || early_is_mul(opcode) ||
             early_is_branch(opcode));
        const bool backend_event = issue->raw_pipe_load_e1() || issue->raw_pipe_mul_e1() ||
            issue->raw_pipe_load_e2() || issue->raw_pipe_mul_e2() || issue->raw_valid_wb() ||
            core->raw_mem_request_value() || core->raw_mem_ack_value() ||
            core->raw_mem_writeback_valid_value() || core->raw_branch_flush_value() ||
            tcm->early_ram_request_value() || tcm->early_ram_ack_value();
        if (!issue_event && !backend_event)
            return;
        if (m_early_trace_rows >= m_early_trace_limit)
        {
            ++m_early_trace_dropped;
            return;
        }

        std::fprintf(m_early_trace_fd,
            "%llu,%s,%u,%u,%u,%u,%08x,%08x,%u,%u,%u,%08x,%08x,%u,%u,%u,%u,%u,%u,%u,%u,%08x,%08x,%u,%u,%u,%08x,%u,%u,%08x,%08x,%08x,%u,%08x,%08x,%u,%u,%08x,%08x,%08x,%08x,%08x,%08x,%x,%x,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%08x,%08x,%u,%u,%u,%08x,%08x,%x,%08x,%u,%x,%u,%u,%u,%u,%08x,%u,%u,%u,%u,%u,%u,%08x,%08x,%08x\n",
            static_cast<unsigned long long>(m_step_count), phase, m_early_iter_entries,
            issue->raw_decode_valid() ? 1u : 0u, issue->raw_issue_valid() ? 1u : 0u,
            issue->raw_issue_accept() ? 1u : 0u, issue->raw_issue_pc(), opcode,
            issue->raw_issue_ra(), issue->raw_issue_rb(), issue->raw_issue_rd(),
            issue->raw_issue_ra_value(), issue->raw_issue_rb_value(),
            issue->early_trace_scoreboard_stall() ? 1u : 0u,
            issue->raw_scoreboard_hazard() ? 1u : 0u, issue->raw_stall() ? 1u : 0u,
            issue->raw_lsu_stall() ? 1u : 0u, issue->raw_squash() ? 1u : 0u,
            issue->raw_pipe_load_e1() ? 1u : 0u, issue->raw_pipe_store_e1() ? 1u : 0u,
            issue->raw_pipe_mul_e1() ? 1u : 0u, issue->raw_pipe_rd_e1(),
            issue->raw_pipe_pc_e1(), issue->raw_pipe_opcode_e1(),
            issue->raw_pipe_load_e2() ? 1u : 0u, issue->raw_pipe_mul_e2() ? 1u : 0u,
            issue->raw_pipe_rd_e2(), issue->raw_pipe_result_e2(), issue->raw_valid_wb() ? 1u : 0u,
            issue->raw_rd_wb(), issue->raw_pc_wb(), issue->raw_opcode_wb(), issue->raw_result_wb(),
            issue->raw_lsu_opcode_valid() ? 1u : 0u, issue->raw_lsu_pc(), issue->raw_lsu_opcode(),
            issue->raw_lsu_ra(), issue->raw_lsu_rb(), issue->raw_lsu_ra_value(), issue->raw_lsu_rb_value(),
            core->early_lsu_agu_addr_value(), core->early_lsu_addr_q_value(),
            core->early_lsu_data_r_value(), core->early_lsu_data_q_value(),
            core->early_lsu_rd_r_value() ? 1u : 0u, core->early_lsu_rd_q_value() ? 1u : 0u,
            core->early_lsu_wr_r_value(), core->early_lsu_wr_q_value(),
            core->early_lsu_pending_value() ? 1u : 0u, core->early_lsu_delay_value() ? 1u : 0u,
            core->early_lsu_unaligned_e1_value() ? 1u : 0u,
            core->early_lsu_unaligned_e2_value() ? 1u : 0u,
            core->early_lsu_issue_value() ? 1u : 0u,
            core->early_lsu_complete_ok_value() ? 1u : 0u,
            core->early_lsu_complete_error_value() ? 1u : 0u,
            core->raw_mem_request_value() ? 1u : 0u, core->raw_mem_accept_value() ? 1u : 0u,
            core->raw_mem_ack_value() ? 1u : 0u, core->data_addr_value(), core->data_write_value(),
            core->data_write_strobe_value(), core->raw_mem_writeback_valid_value() ? 1u : 0u,
            core->raw_mem_exception_value(), core->early_mmu_addr_value(),
            core->early_mmu_rd_value() ? 1u : 0u, core->early_mmu_wr_value(),
            core->early_mmu_accept_value() ? 1u : 0u, core->early_mmu_ack_value() ? 1u : 0u,
            core->early_mmu_data_value(), static_cast<unsigned>(tcm->early_ram_addr_value()),
            tcm->early_ram_request_value() ? 1u : 0u, tcm->early_ram_accept_value() ? 1u : 0u,
            tcm->early_ram_ack_value() ? 1u : 0u, tcm->early_ram_data_value(),
            core->branch_request_value() ? 1u : 0u, core->branch_mispredict_value() ? 1u : 0u,
            core->raw_branch_flush_value() ? 1u : 0u,
            issue->complete_valid0() ? 1u : 0u, issue->complete_pc0(), issue->complete_opcode0());
        std::fflush(m_early_trace_fd);
        ++m_early_trace_rows;
    }

    void early_report(void)
    {
        if (!m_early_observer_enabled || m_early_reported)
            return;
        early_flush_stall_run();
        early_flush_l2l_pair_run();
        if (m_early_trace_fd)
        {
            std::fflush(m_early_trace_fd);
            std::fclose(m_early_trace_fd);
            m_early_trace_fd = NULL;
        }
        FILE *fd = std::fopen("early_summary.csv", "w");
        if (!fd)
        {
            std::fprintf(stderr, "EARLY_OBS cannot open early_summary.csv\n");
            m_closure_failure = true;
        }
        else
        {
            std::fprintf(fd, "record,key,count\n");
            std::fprintf(fd, "WINDOW|iter_entries=%u|roi_start=%llu|roi_end=%llu|roi_cycles=%llu,window,1\n",
                         m_early_iter_entries,
                         static_cast<unsigned long long>(m_early_roi_start_cycle),
                         static_cast<unsigned long long>(m_early_roi_end_cycle),
                         m_early_roi_end_cycle >= m_early_roi_start_cycle ?
                         static_cast<unsigned long long>(m_early_roi_end_cycle - m_early_roi_start_cycle) : 0ull);
            std::fprintf(fd, "TRACE|rows=%llu|dropped=%llu,trace,1\n",
                         static_cast<unsigned long long>(m_early_trace_rows),
                         static_cast<unsigned long long>(m_early_trace_dropped));
            std::fprintf(fd, "L2L_PAIR_RUN|max=%llu,l2l_pair_run_max,1\n",
                         static_cast<unsigned long long>(m_early_l2l_max_pair_run));
            for (const auto &entry : m_early_counts)
                std::fprintf(fd, "%s,%s,%llu\n", entry.first.c_str(), entry.first.c_str(),
                             static_cast<unsigned long long>(entry.second));
            std::fflush(fd);
            std::fclose(fd);
        }
        std::printf("EARLY_OBS summary iter_entries=%u roi_start=%llu roi_end=%llu roi_cycles=%llu trace_rows=%llu trace_dropped=%llu\n",
                    m_early_iter_entries,
                    static_cast<unsigned long long>(m_early_roi_start_cycle),
                    static_cast<unsigned long long>(m_early_roi_end_cycle),
                    m_early_roi_end_cycle >= m_early_roi_start_cycle ?
                    static_cast<unsigned long long>(m_early_roi_end_cycle - m_early_roi_start_cycle) : 0ull,
                    static_cast<unsigned long long>(m_early_trace_rows),
                    static_cast<unsigned long long>(m_early_trace_dropped));
        if (!m_early_stop_requested || m_early_iter_entries <
            m_early_warmup_iters + m_early_sample_iters + 1u)
        {
            std::fprintf(stderr, "EARLY_OBS ROI did not close at the required iterate boundary\n");
            m_closure_failure = true;
        }
        m_early_reported = true;
    }

    void e_tcm_focus_sample(const char *phase)
    {
        if (!m_e_tcm_focus_enabled || !m_e_tcm_focus_fd)
            return;

        auto *core = m_dut->m_rtl->v->u_core;
        auto *issue = core->u_issue;
        auto *tcm = m_dut->m_rtl->v->u_tcm;
        const bool pre = phase[0] == 'p' && phase[1] == 'r';
        const uint32_t opcode = issue->raw_issue_opcode();
        const uint32_t major = opcode & 0x7fu;
        const bool issue_accept = issue->raw_issue_valid() && issue->raw_issue_accept();
        const bool early_candidate = core->early_lsu_candidate_value() != 0;
        const bool early_launch = core->early_lsu_launch_value() != 0;
        const bool early_live = core->early_lsu_live_value() != 0;
        const bool early_hold = core->early_lsu_hold_valid_value() != 0;
        const bool early_result_valid = core->early_result_valid_value() != 0;
        const bool early_result_consume = core->early_result_consume_value() != 0;
        const bool raw_request = core->raw_mem_request_value() != 0;
        const bool raw_accept = core->raw_mem_accept_value() != 0;
        const bool raw_ack = core->raw_mem_ack_value() != 0;
        const bool branch_mispredict = core->branch_mispredict_value() != 0;
        const uint32_t mem_addr = core->data_addr_value();
        const unsigned ram_addr = static_cast<unsigned>(tcm->early_ram_addr_value());
        const bool early_pending_before = m_e_tcm_transaction_pending;

        if (pre)
        {
            if (early_candidate)
                ++m_e_tcm_candidate_count;

            if (issue_accept && major == 0x63u)
                ++m_e_tcm_branch_count;
            if (branch_mispredict)
                ++m_e_tcm_branch_mispredict_count;

            if (early_launch)
            {
                ++m_e_tcm_launch_count;
                if (!early_candidate || !core->early_load_accept_value() ||
                    !issue_accept || !raw_request || !raw_accept ||
                    core->data_write_strobe_value() != 0u ||
                    !tcm->early_ram_request_value() ||
                    !tcm->early_ram_accept_value() ||
                    ((ram_addr << 2) != (mem_addr & ~3u)))
                    ++m_e_tcm_bad_count;
                if (early_pending_before)
                    ++m_e_tcm_bad_count;
                m_e_tcm_transaction_pending = true;
                m_e_tcm_last_launch_cycle = m_step_count;
                m_e_tcm_last_launch_addr = mem_addr & ~3u;
                m_e_tcm_last_launch_rd = issue->raw_issue_rd();
            }

            if (early_result_valid && !m_e_tcm_prev_result_valid)
                ++m_e_tcm_response_count;
            if (issue->early_fast_load_e2_value() && !m_e_tcm_prev_fast_e2)
                ++m_e_tcm_fast_capture_count;

            if (early_result_consume)
            {
                ++m_e_tcm_consume_count;
                if (!early_result_valid || (!early_live && !early_hold))
                    ++m_e_tcm_bad_count;
            }

            if (raw_ack && early_pending_before)
            {
                if (!early_live || !early_result_valid ||
                    core->early_lsu_early_rd_value() != m_e_tcm_last_launch_rd)
                    ++m_e_tcm_bad_count;
                m_e_tcm_transaction_pending = false;
            }
            else if (early_pending_before && raw_request && raw_accept &&
                     !early_launch && mem_addr == m_e_tcm_last_launch_addr)
                ++m_e_tcm_bad_count;

            if (issue->early_release_value())
            {
                const bool match_ra = issue->early_match_ra_value() != 0;
                const bool match_rb = issue->early_match_rb_value() != 0;
                if (match_ra == match_rb)
                    ++m_e_tcm_bad_count;
                else
                {
                    const uint32_t selected = match_ra ? issue->raw_issue_ra_value() :
                                                       issue->raw_issue_rb_value();
                    if (selected != core->early_result_value_value())
                        ++m_e_tcm_bad_count;
                }

                if (major == 0x13u || major == 0x33u)
                    ++m_e_tcm_release_alu_count;
                else if (major == 0x63u)
                    ++m_e_tcm_release_branch_count;
                else if (major == 0x23u)
                {
                    ++m_e_tcm_release_store_count;
                    const unsigned funct3 = (opcode >> 12) & 0x7u;
                    if (match_ra && !match_rb)
                        ++m_e_tcm_store_address_count;
                    else if (!match_ra && match_rb)
                    {
                        if (funct3 == 0u)
                            ++m_e_tcm_store_data_count[0];
                        else if (funct3 == 1u)
                            ++m_e_tcm_store_data_count[1];
                        else if (funct3 == 2u)
                            ++m_e_tcm_store_data_count[2];
                        else
                            ++m_e_tcm_bad_count;
                    }
                    else
                        ++m_e_tcm_store_both_count;
                }
            }

            m_e_tcm_prev_result_valid = early_result_valid;
            m_e_tcm_prev_fast_e2 = issue->early_fast_load_e2_value() != 0;
        }

        if (m_e_tcm_focus_rows < m_e_tcm_focus_limit)
        {
            std::fprintf(m_e_tcm_focus_fd,
                "%llu,%s,%u,%u,%08x,%08x,%u,%u,%u,%08x,%08x,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%08x,%u,%u,%u,%u,%08x,%08x,%x,%x,%u,%u,%u,%08x,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%08x,%08x\n",
                static_cast<unsigned long long>(m_step_count), phase,
                issue->raw_issue_valid() ? 1u : 0u,
                issue_accept ? 1u : 0u,
                issue->raw_issue_pc(), opcode,
                issue->raw_issue_ra(), issue->raw_issue_rb(), issue->raw_issue_rd(),
                issue->raw_issue_ra_value(), issue->raw_issue_rb_value(),
                issue->early_fast_load_e1_value() ? 1u : 0u,
                issue->early_fast_load_e2_value() ? 1u : 0u,
                issue->early_release_value() ? 1u : 0u,
                issue->early_match_ra_value() ? 1u : 0u,
                issue->early_match_rb_value() ? 1u : 0u,
                issue->early_base_ok_value() ? 1u : 0u,
                early_candidate ? 1u : 0u, early_launch ? 1u : 0u,
                early_live ? 1u : 0u, early_hold ? 1u : 0u,
                early_result_valid ? 1u : 0u,
                core->early_result_rd_value(), core->early_result_value_value(),
                early_result_consume ? 1u : 0u,
                raw_request ? 1u : 0u, raw_accept ? 1u : 0u, raw_ack ? 1u : 0u,
                mem_addr, core->data_write_value(),
                static_cast<unsigned>(core->data_write_strobe_value()),
                ram_addr, tcm->early_ram_request_value() ? 1u : 0u,
                tcm->early_ram_accept_value() ? 1u : 0u,
                tcm->early_ram_ack_value() ? 1u : 0u,
                tcm->early_ram_data_value(),
                issue->raw_pipe_load_e1() ? 1u : 0u,
                issue->raw_pipe_load_e2() ? 1u : 0u,
                issue->raw_pipe_rd_e1(), issue->raw_pipe_rd_e2(),
                issue->raw_stall() ? 1u : 0u, issue->raw_lsu_stall() ? 1u : 0u,
                core->branch_request_value() ? 1u : 0u, branch_mispredict ? 1u : 0u,
                core->raw_branch_flush_value() ? 1u : 0u,
                issue->complete_valid0() ? 1u : 0u, issue->complete_pc0(),
                issue->complete_opcode0());
            std::fflush(m_e_tcm_focus_fd);
            ++m_e_tcm_focus_rows;
        }
    }

    void e_tcm_focus_report(void)
    {
        if (!m_e_tcm_focus_enabled || m_e_tcm_reported)
            return;

        if (m_e_tcm_focus_fd)
        {
            std::fflush(m_e_tcm_focus_fd);
            std::fclose(m_e_tcm_focus_fd);
            m_e_tcm_focus_fd = NULL;
        }

        const uint32_t expected[17] = {
            0x11223345u, 0x11223345u, 0xbeef0001u, 0xbeef0002u,
            0x11223344u, 0x00004400u, 0x00003344u, 0xcafebabeu,
            0x11223344u, 0x11223345u, 0x11223344u, 0x11223344u,
            0x00003344u, 0x11223344u, 0x00006200u, 0xcafebabeu,
            0x00006200u
        };
        bool signature_ok = true;
        std::printf("ETCM_FOCUS signature");
        for (unsigned i = 0; i < 17u; ++i)
        {
            const uint32_t observed = read_word(0x0000e000u + i * 4u);
            std::printf(" s%u=0x%08x", i, observed);
            if (observed != expected[i])
                signature_ok = false;
        }
        std::printf(" status=%s\n", signature_ok ? "PASS" : "FAIL");
        std::printf("ETCM_FOCUS counts candidate=%llu launch=%llu response=%llu consume=%llu fast_capture=%llu branches=%llu branch_mispredict=%llu release_alu=%llu release_branch=%llu release_store=%llu store_data_B=%llu store_data_H=%llu store_data_W=%llu store_address=%llu store_both=%llu bad=%llu pending=%u trace_rows=%llu\n",
                    static_cast<unsigned long long>(m_e_tcm_candidate_count),
                    static_cast<unsigned long long>(m_e_tcm_launch_count),
                    static_cast<unsigned long long>(m_e_tcm_response_count),
                    static_cast<unsigned long long>(m_e_tcm_consume_count),
                    static_cast<unsigned long long>(m_e_tcm_fast_capture_count),
                    static_cast<unsigned long long>(m_e_tcm_branch_count),
                    static_cast<unsigned long long>(m_e_tcm_branch_mispredict_count),
                    static_cast<unsigned long long>(m_e_tcm_release_alu_count),
                    static_cast<unsigned long long>(m_e_tcm_release_branch_count),
                    static_cast<unsigned long long>(m_e_tcm_release_store_count),
                    static_cast<unsigned long long>(m_e_tcm_store_data_count[0]),
                    static_cast<unsigned long long>(m_e_tcm_store_data_count[1]),
                    static_cast<unsigned long long>(m_e_tcm_store_data_count[2]),
                    static_cast<unsigned long long>(m_e_tcm_store_address_count),
                    static_cast<unsigned long long>(m_e_tcm_store_both_count),
                    static_cast<unsigned long long>(m_e_tcm_bad_count),
                    m_e_tcm_transaction_pending ? 1u : 0u,
                    static_cast<unsigned long long>(m_e_tcm_focus_rows));

        auto *core = m_dut->m_rtl->v->u_core;
        const bool coverage_ok = core->early_support_value() &&
            m_e_tcm_launch_count != 0u && m_e_tcm_response_count != 0u &&
            m_e_tcm_consume_count != 0u && m_e_tcm_fast_capture_count != 0u &&
            m_e_tcm_release_alu_count != 0u &&
            m_e_tcm_release_branch_count != 0u &&
            m_e_tcm_release_store_count != 0u &&
            m_e_tcm_store_data_count[0] != 0u &&
            m_e_tcm_store_data_count[1] != 0u &&
            m_e_tcm_store_data_count[2] != 0u &&
            m_e_tcm_store_address_count != 0u &&
            m_e_tcm_store_both_count == 0u &&
            m_e_tcm_branch_count >= 2u &&
            !m_e_tcm_transaction_pending && m_e_tcm_bad_count == 0u;
        if (!signature_ok || !coverage_ok)
        {
            std::fprintf(stderr, "ETCM_FOCUS closure failed: coverage or signature mismatch\n");
            m_closure_failure = true;
        }
        m_e_tcm_reported = true;
    }

    //-----------------------------------------------------------------
    // Signals
    //-----------------------------------------------------------------    
    sc_signal <bool>            rst_cpu_in;

    sc_signal <axi4_master>      axi_t_in;
    sc_signal <axi4_slave>       axi_t_out;

    sc_signal <axi4_lite_master> axi_i_out;
    sc_signal <axi4_lite_slave>  axi_i_in;

    sc_signal < sc_uint <32> >   intr_in;


    //-----------------------------------------------------------------
    // process: Main loop for CPU execution
    //-----------------------------------------------------------------
    void process(void) 
    {
        cosim::instance()->attach_cpu("rtl", this);
        cosim::instance()->attach_mem("rtl", this, 0, 0xFFFFFFFF);
        wait();
        int exitcode = riscv_main(cosim::instance(), m_argc, m_argv);
        if (m_irq_script_enabled && m_irq_script_stage != IRQ_SCRIPT_DONE)
        {
            std::fprintf(stderr, "IRQ_DRIVER incomplete stage=%d (masked trigger/withdrawal, enabled trigger, handler withdrawal)\n",
                         m_irq_script_stage);
            exitcode = 1;
        }
        auto *core = m_dut->m_rtl->v->u_core;
        sample_irq_observation();
        const uint64_t scoreboard_ledger =
            core->u_issue->trace_ledger_blanket_count() +
            core->u_issue->trace_ledger_load_count() +
            core->u_issue->trace_ledger_mul_count() +
            core->u_issue->trace_ledger_mixed_count() +
            core->u_issue->trace_ledger_waw_count() +
            core->u_issue->trace_ledger_false_count() +
            core->u_issue->trace_ledger_other_count();
        const bool require_scoreboard_window =
            env_u32("ULTRA_SCOREBOARD_REQUIRE_WINDOW", 0) != 0;
        const uint64_t expected_scoreboard_total =
            env_u64("ULTRA_SCOREBOARD_EXPECT_TOTAL", 0);
        if (scoreboard_ledger != core->u_issue->trace_perf_total())
        {
            std::fprintf(stderr,
                         "SCOREBOARD_TRACE ledger does not close: total=%llu ledger=%llu\n",
                         static_cast<unsigned long long>(core->u_issue->trace_perf_total()),
                         static_cast<unsigned long long>(scoreboard_ledger));
            exitcode = 1;
        }
        if (require_scoreboard_window &&
            (!core->u_issue->trace_window_start_seen() ||
             !core->u_issue->trace_window_end_seen()))
        {
            std::fprintf(stderr,
                         "SCOREBOARD_TRACE window not closed: start=%u end=%u\n",
                         core->u_issue->trace_window_start_seen() ? 1 : 0,
                         core->u_issue->trace_window_end_seen() ? 1 : 0);
            exitcode = 1;
        }
        if (expected_scoreboard_total != 0 &&
            core->u_issue->trace_perf_total() != expected_scoreboard_total)
        {
            std::fprintf(stderr,
                         "SCOREBOARD_TRACE expected total mismatch: expected=%llu actual=%llu\n",
                         static_cast<unsigned long long>(expected_scoreboard_total),
                         static_cast<unsigned long long>(core->u_issue->trace_perf_total()));
            exitcode = 1;
        }
        if (m_irq_script_enabled)
        {
            const uint32_t sig0 = read_word(0x0000e000);
            const uint32_t sig1 = read_word(0x0000e004);
            const uint32_t sig2 = read_word(0x0000e008);
            const uint32_t sig3 = read_word(0x0000e00c);
            std::printf("IRQ_OBS signature masked_handlers=%u enabled_handlers=%u mcause=0x%08x mepc=0x%08x\n",
                        sig0, sig1, sig2, sig3);
            if (sig0 != 0 || sig1 != 1 || sig2 != 0x8000000b || sig3 == 0)
            {
                std::fprintf(stderr, "IRQ_DRIVER signature check failed\n");
                exitcode = 1;
            }
            std::printf("IRQ_OBS summary takes=%u exception_pc=0x%08x mepc=0x%08x mcause=0x%08x mip=0x%08x\n",
                        m_irq_take_count, m_irq_accept_pc, m_irq_accept_mepc,
                        m_irq_accept_mcause, core->csr_mip_value());
        }
        std::printf("branch_resolved       : %u\n", core->branch_resolved_count());
        std::printf("branch_conditional    : %u\n", core->branch_conditional_count());
        std::printf("branch_jal            : %u\n", core->branch_jal_count());
        std::printf("branch_jalr_ret       : %u\n", core->branch_jalr_count());
        std::printf("branch_btb_hit        : %u\n", core->branch_btb_hit_count());
        std::printf("branch_btb_miss       : %u\n", core->branch_btb_miss_count());
        std::printf("branch_pred_taken     : %u\n", core->branch_pred_taken_count());
        std::printf("branch_correct        : %u\n", core->branch_correct_count());
        std::printf("branch_mispredict     : %u\n", core->branch_mispredict_count());
        std::printf("scoreboard_trace_total       : %llu\n", static_cast<unsigned long long>(core->u_issue->trace_perf_total()));
        std::printf("scoreboard_trace_program_total: %llu\n", static_cast<unsigned long long>(core->u_issue->trace_program_perf_total()));
        std::printf("scoreboard_trace_window_start_seen: %u\n", core->u_issue->trace_window_start_seen() ? 1 : 0);
        std::printf("scoreboard_trace_window_end_seen  : %u\n", core->u_issue->trace_window_end_seen() ? 1 : 0);
        std::printf("scoreboard_trace_window_start_cycle: %llu\n", static_cast<unsigned long long>(core->u_issue->trace_window_start_cycle()));
        std::printf("scoreboard_trace_window_end_cycle  : %llu\n", static_cast<unsigned long long>(core->u_issue->trace_window_end_cycle()));
        std::printf("scoreboard_trace_blanket     : %llu\n", static_cast<unsigned long long>(core->u_issue->trace_blanket_count()));
        std::printf("scoreboard_trace_blanket_load: %llu\n", static_cast<unsigned long long>(core->u_issue->trace_blanket_load_count()));
        std::printf("scoreboard_trace_blanket_store: %llu\n", static_cast<unsigned long long>(core->u_issue->trace_blanket_store_count()));
        std::printf("scoreboard_trace_blanket_load_mul: %llu\n", static_cast<unsigned long long>(core->u_issue->trace_blanket_load_mul_count()));
        std::printf("scoreboard_trace_blanket_load_div: %llu\n", static_cast<unsigned long long>(core->u_issue->trace_blanket_load_div_count()));
        std::printf("scoreboard_trace_blanket_load_csr: %llu\n", static_cast<unsigned long long>(core->u_issue->trace_blanket_load_csr_count()));
        std::printf("scoreboard_trace_blanket_store_mul: %llu\n", static_cast<unsigned long long>(core->u_issue->trace_blanket_store_mul_count()));
        std::printf("scoreboard_trace_blanket_store_div: %llu\n", static_cast<unsigned long long>(core->u_issue->trace_blanket_store_div_count()));
        std::printf("scoreboard_trace_blanket_store_csr: %llu\n", static_cast<unsigned long long>(core->u_issue->trace_blanket_store_csr_count()));
        std::printf("scoreboard_trace_blanket_load_mul_raw: %llu\n", static_cast<unsigned long long>(core->u_issue->trace_blanket_load_mul_raw_count()));
        std::printf("scoreboard_trace_blanket_load_div_raw: %llu\n", static_cast<unsigned long long>(core->u_issue->trace_blanket_load_div_raw_count()));
        std::printf("scoreboard_trace_blanket_load_csr_raw: %llu\n", static_cast<unsigned long long>(core->u_issue->trace_blanket_load_csr_raw_count()));
        std::printf("scoreboard_trace_blanket_store_mul_raw: %llu\n", static_cast<unsigned long long>(core->u_issue->trace_blanket_store_mul_raw_count()));
        std::printf("scoreboard_trace_blanket_store_div_raw: %llu\n", static_cast<unsigned long long>(core->u_issue->trace_blanket_store_div_raw_count()));
        std::printf("scoreboard_trace_blanket_store_csr_raw: %llu\n", static_cast<unsigned long long>(core->u_issue->trace_blanket_store_csr_raw_count()));
        std::printf("scoreboard_trace_blanket_load_mul_waw: %llu\n", static_cast<unsigned long long>(core->u_issue->trace_blanket_load_mul_waw_count()));
        std::printf("scoreboard_trace_blanket_load_div_waw: %llu\n", static_cast<unsigned long long>(core->u_issue->trace_blanket_load_div_waw_count()));
        std::printf("scoreboard_trace_blanket_load_csr_waw: %llu\n", static_cast<unsigned long long>(core->u_issue->trace_blanket_load_csr_waw_count()));
        std::printf("scoreboard_trace_blanket_store_mul_waw: %llu\n", static_cast<unsigned long long>(core->u_issue->trace_blanket_store_mul_waw_count()));
        std::printf("scoreboard_trace_blanket_store_div_waw: %llu\n", static_cast<unsigned long long>(core->u_issue->trace_blanket_store_div_waw_count()));
        std::printf("scoreboard_trace_blanket_store_csr_waw: %llu\n", static_cast<unsigned long long>(core->u_issue->trace_blanket_store_csr_waw_count()));
        std::printf("scoreboard_trace_unused_rs1  : %llu\n", static_cast<unsigned long long>(core->u_issue->trace_unused_rs1_count()));
        std::printf("scoreboard_trace_unused_rs2  : %llu\n", static_cast<unsigned long long>(core->u_issue->trace_unused_rs2_count()));
        std::printf("scoreboard_trace_invalid_rd  : %llu\n", static_cast<unsigned long long>(core->u_issue->trace_invalid_rd_count()));
        std::printf("scoreboard_trace_x0           : %llu\n", static_cast<unsigned long long>(core->u_issue->trace_x0_count()));
        std::printf("scoreboard_trace_load_raw    : %llu\n", static_cast<unsigned long long>(core->u_issue->trace_load_raw_count()));
        std::printf("scoreboard_trace_mul_raw     : %llu\n", static_cast<unsigned long long>(core->u_issue->trace_mul_raw_count()));
        std::printf("scoreboard_trace_mixed_raw   : %llu\n", static_cast<unsigned long long>(core->u_issue->trace_mixed_raw_count()));
        std::printf("scoreboard_trace_waw         : %llu\n", static_cast<unsigned long long>(core->u_issue->trace_waw_count()));
        std::printf("scoreboard_trace_false_only  : %llu\n", static_cast<unsigned long long>(core->u_issue->trace_false_only_count()));
        std::printf("scoreboard_trace_x0_only     : %llu\n", static_cast<unsigned long long>(core->u_issue->trace_x0_only_count()));
        std::printf("scoreboard_trace_other       : %llu\n", static_cast<unsigned long long>(core->u_issue->trace_other_count()));
        std::printf("scoreboard_ledger_blanket    : %llu\n", static_cast<unsigned long long>(core->u_issue->trace_ledger_blanket_count()));
        std::printf("scoreboard_ledger_load_raw   : %llu\n", static_cast<unsigned long long>(core->u_issue->trace_ledger_load_count()));
        std::printf("scoreboard_ledger_mul_raw    : %llu\n", static_cast<unsigned long long>(core->u_issue->trace_ledger_mul_count()));
        std::printf("scoreboard_ledger_mixed_raw  : %llu\n", static_cast<unsigned long long>(core->u_issue->trace_ledger_mixed_count()));
        std::printf("scoreboard_ledger_waw        : %llu\n", static_cast<unsigned long long>(core->u_issue->trace_ledger_waw_count()));
        std::printf("scoreboard_ledger_false_only : %llu\n", static_cast<unsigned long long>(core->u_issue->trace_ledger_false_count()));
        std::printf("scoreboard_ledger_other      : %llu\n", static_cast<unsigned long long>(core->u_issue->trace_ledger_other_count()));
        std::printf("scoreboard_class_seen        : 0x%03x\n", static_cast<unsigned>(core->u_issue->trace_class_seen()));
        std::printf("scoreboard_sem_mismatch      : %u\n", core->u_issue->trace_sem_mismatch());
        std::printf("scoreboard_witness_mask      : 0x%02x\n", static_cast<unsigned>(core->u_issue->trace_witness_mask()));
        std::fflush(stdout);
        if (m_raw_trace_fd)
        {
            std::fflush(m_raw_trace_fd);
            std::fclose(m_raw_trace_fd);
            m_raw_trace_fd = NULL;
            std::printf("RAW_TRACE rows=%llu file=raw_trace.csv\n",
                        static_cast<unsigned long long>(m_raw_trace_rows));
        }
        exit(exitcode);
    }

    void set_argcv(int argc, char* argv[]) { m_argc = argc; m_argv = argv; }

    //-----------------------------------------------------------------
    // Construction
    //-----------------------------------------------------------------
    SC_HAS_PROCESS(testbench);
    testbench(sc_module_name name): testbench_vbase(name),
        m_last_pc(0), m_step_count(0),
        m_bounded_diag_enabled(false), m_diag_interval(100000),
        m_diag_retired_count(0), m_diag_iter_entries(0),
        m_diag_stall_cycles(0), m_diag_early_live_cycles(0),
        m_diag_early_hold_cycles(0), m_diag_normal_pending_cycles(0),
        m_diag_request_cycles(0), m_diag_accept_cycles(0),
        m_diag_ack_cycles(0), m_diag_last_commit_pc(0),
        m_irq_script_enabled(false), m_irq_script_stage(IRQ_SCRIPT_DONE),
        m_irq_mask_trigger_pc(0), m_irq_mask_clear_pc(0),
        m_irq_enabled_trigger_pc(0), m_irq_handler_pc(0),
        m_irq_take_count(0), m_irq_accept_pc(0), m_irq_accept_mepc(0),
        m_irq_accept_mcause(0), m_irq_take_seen(false),
        m_irq_exception_event_count(0), m_irq_exception_seen(false),
        m_irq_branch_pc(0), m_irq_enabled_source_seen(false),
        m_irq_branch_window_seen(false),
        m_irq_branch_mispredict_seen(false),
        m_closure_failure(false), m_side_effect_test_enabled(false),
        m_mmio_write_count(0), m_mmio_nt_count(0), m_mmio_pt_count(0),
        m_mmio_nt_last_data(0), m_mmio_pt_last_data(0),
        m_mmio_aw_pending(false), m_mmio_w_pending(false),
         m_mmio_pending_addr(0), m_mmio_pending_data(0),
         m_mmio_pending_strb(0), m_mmio_bvalid(false),
          m_side_last_commit_step(~static_cast<uint64_t>(0)),
          m_raw_trace_enabled(false), m_raw_trace_fd(NULL),
          m_raw_trace_rows(0), m_raw_trace_limit(20000),
          m_shared_observer_enabled(false), m_shared_corrected_mode(false),
          m_shared_event_fd(NULL),
          m_shared_event_rows(0), m_shared_event_limit(1000000),
          m_shared_event_dropped(0), m_shared_warmup_iters(2),
          m_shared_sample_iters(8), m_shared_iter_entries(0),
          m_shared_roi_active(false), m_shared_stop_requested(false),
          m_shared_roi_start_cycle(0), m_shared_roi_end_cycle(0),
          m_shared_last_iter_cycle(~static_cast<uint64_t>(0)),
          m_shared_prev_e1_load(false), m_shared_prev_e2_load(false),
          m_shared_prev_wb_load(false), m_shared_prev_e1_pc(0),
          m_shared_prev_e2_pc(0), m_shared_prev_wb_pc(0),
          m_shared_prev_early_result_valid(false),
          m_shared_prev_early_result_rd(0), m_shared_prev_early_live(false),
          m_shared_prev_early_hold(false), m_shared_prev_branch_flush(false),
          m_shared_prev_mem_request(false), m_shared_prev_mem_addr(0),
          m_shared_prev_mem_data(0), m_shared_prev_mem_wr(0),
          m_corrected_next_id(0), m_corrected_lookup_count(0),
          m_corrected_update_count(0), m_corrected_commit_count(0),
          m_corrected_fetch_issue_count(0), m_corrected_fetch_cancel_count(0),
          m_corrected_branch_cancel_count(0),
          m_corrected_lookup_unresolved(0),
          m_corrected_unresolved_reported(0),
          m_corrected_update_unassociated(0), m_corrected_update_duplicate(0),
          m_corrected_update_pred_mismatch(0),
          m_corrected_update_after_cancel(0),
          m_corrected_commit_unassociated(0), m_corrected_commit_order_error(0),
          m_corrected_duplicate_token_consume(0),
          m_corrected_decode_token_mismatch(0), m_corrected_orphan_response(0),
          m_corrected_prev_response_valid(false),
          m_corrected_prev_skid_valid(false),
          m_corrected_prev_decode_valid(false),
          m_corrected_prev_fetch_drop(false),
          m_corrected_prev_decode_pc(0), m_corrected_prev_decode_instr(0),
          m_corrected_prev_decode_pred(false),
          m_corrected_prev_normal_active(false),
          m_corrected_prev_pending_conflict(false),
          m_corrected_prev_slot_free(false),
          m_corrected_prev_early_offer(false),
          m_corrected_prev_early_accept(false),
          m_corrected_prev_early_fire(false),
          m_corrected_prev_early_response(false),
          m_corrected_prev_normal_rd(false),
          m_corrected_prev_normal_error(false),
          m_early_observer_enabled(false), m_early_trace_fd(NULL),
         m_early_trace_rows(0), m_early_trace_limit(50000),
         m_early_trace_dropped(0), m_early_warmup_iters(2),
         m_early_sample_iters(8), m_early_iter_entries(0),
         m_early_roi_active(false), m_early_stop_requested(false),
         m_early_reported(false), m_early_roi_start_cycle(0),
         m_early_roi_end_cycle(0), m_early_last_iter_cycle(~static_cast<uint64_t>(0)),
         m_early_stall_run(0), m_early_l2l_pair_run(0),
         m_early_l2l_max_pair_run(0), m_early_l2l_last_a_pc(0),
         m_early_l2l_last_b_pc(0), m_early_last_load_valid(false),
         m_early_last_load_pc(0), m_early_last_load_rd(0),
          m_early_last_load_chain(0), m_early_instr_since_last_load(0),
          m_e_tcm_focus_enabled(false), m_e_tcm_focus_fd(NULL),
          m_e_tcm_focus_rows(0), m_e_tcm_focus_limit(20000),
          m_e_tcm_candidate_count(0), m_e_tcm_launch_count(0),
          m_e_tcm_response_count(0), m_e_tcm_consume_count(0),
          m_e_tcm_fast_capture_count(0), m_e_tcm_branch_count(0),
          m_e_tcm_branch_mispredict_count(0), m_e_tcm_release_alu_count(0),
          m_e_tcm_release_branch_count(0), m_e_tcm_release_store_count(0),
          m_e_tcm_store_address_count(0), m_e_tcm_store_both_count(0),
          m_e_tcm_bad_count(0), m_e_tcm_last_launch_cycle(0),
          m_e_tcm_last_launch_addr(0), m_e_tcm_last_launch_rd(0),
           m_e_tcm_transaction_pending(false), m_e_tcm_prev_result_valid(false),
           m_e_tcm_prev_fast_e2(false), m_e_tcm_reported(false),
           m_tcm_port_test_enabled(false), m_tcm_port_trigger_pc(0xffffffffu),
           m_tcm_port_started(false), m_tcm_port_external_inflight(false),
           m_tcm_port_busy_seen(false), m_tcm_port_wait_fallback(false),
           m_tcm_port_failure(false), m_tcm_port_ext_ar_count(0),
           m_tcm_port_ext_r_count(0), m_tcm_port_candidate_count(0),
           m_tcm_port_early_launch_count(0),
           m_tcm_port_blocked_candidate_count(0),
           m_tcm_port_fallback_request_count(0),
           m_tcm_port_fallback_accept_count(0),
           m_tcm_port_trace_rows(0), m_tcm_port_trace_limit(256),
           m_tcm_port_trace_fd(NULL)
    {
        m_dut = new riscv_tcm_top_rtl("DUT");
        m_dut->clk_in(clk);
        m_dut->rst_in(rst);
        m_dut->rst_cpu_in(rst_cpu_in);
        m_dut->axi_t_out(axi_t_out);
        m_dut->axi_t_in(axi_t_in);
        m_dut->axi_i_out(axi_i_out);
        m_dut->axi_i_in(axi_i_in);
        m_dut->intr_in(intr_in);

        intr_in.write(0);
        axi4_lite_slave axi_i_defaults;
        axi_i_defaults.init();
        axi_i_in.write(axi_i_defaults);
        axi4_master axi_t_defaults;
        axi_t_defaults.init();
        axi_t_in.write(axi_t_defaults);

        const char *bounded_diag = std::getenv("ULTRA_BOUNDED_DIAG");
        m_bounded_diag_enabled = bounded_diag &&
                                 std::strtoul(bounded_diag, NULL, 0) != 0;
        if (m_bounded_diag_enabled)
        {
            m_diag_interval = env_u64("ULTRA_BOUNDED_DIAG_INTERVAL", 100000);
            std::printf("BOUNDED_DIAG enabled interval=%llu\n",
                        static_cast<unsigned long long>(m_diag_interval));
        }

        const char *txn_mode = std::getenv("ULTRA_E_TCM_TRANSACTION");
        const char *port_mode = std::getenv("ULTRA_E_TCM_PORT_OCCUPY");
        m_tcm_port_test_enabled = txn_mode && port_mode &&
                                   std::strtoul(txn_mode, NULL, 0) != 0 &&
                                   std::strtoul(port_mode, NULL, 0) != 0;
        if (m_tcm_port_test_enabled)
        {
            m_tcm_port_trigger_pc = env_u32("ULTRA_E_TCM_PORT_TRIGGER_PC",
                                             0xffffffffu);
            m_tcm_port_trace_limit = env_u64("ULTRA_E_TCM_TRACE_LIMIT", 256);
            m_tcm_port_trace_fd = std::fopen("e_tcm_transaction.csv", "w");
            if (!m_tcm_port_trace_fd)
            {
                std::fprintf(stderr,
                             "ETCM_TXN cannot open e_tcm_transaction.csv\n");
                m_tcm_port_failure = true;
                m_closure_failure = true;
            }
            else
            {
                std::fprintf(m_tcm_port_trace_fd,
                    "cycle,external_inflight,candidate,early_launch,normal_request,normal_accept,ack,early_live,early_hold,normal_pending,addr,data,wr\n");
            }
            std::printf("ETCM_TXN enabled trigger_pc=0x%08x trace_limit=%llu\n",
                        m_tcm_port_trigger_pc,
                        static_cast<unsigned long long>(m_tcm_port_trace_limit));
        }

        const char *side_effect_mode = std::getenv("ULTRA_SIDE_EFFECT_TEST");
        m_side_effect_test_enabled = side_effect_mode &&
                                      std::strtoul(side_effect_mode, NULL, 0) != 0;
        SC_CTHREAD(mmio_monitor, clk);
        SC_CTHREAD(tcm_port_driver, clk);
        if (m_side_effect_test_enabled)
            std::printf("SIDE_EFFECT_DRIVER enabled: MMIO 0x%08x/0x%08x\n",
                        MMIO_NT_ADDR, MMIO_PT_ADDR);
        const char *raw_trace_mode = std::getenv("ULTRA_RAW_TRACE");
        m_raw_trace_enabled = raw_trace_mode &&
                               std::strtoul(raw_trace_mode, NULL, 0) != 0;
        if (m_raw_trace_enabled)
        {
            m_raw_trace_limit = env_u64("ULTRA_RAW_TRACE_LIMIT", 20000);
            m_raw_trace_fd = std::fopen("raw_trace.csv", "w");
            if (!m_raw_trace_fd)
            {
                std::fprintf(stderr, "RAW_TRACE cannot open raw_trace.csv\n");
                m_closure_failure = true;
            }
            else
            {
                std::fprintf(m_raw_trace_fd,
                    "cycle,decode_valid,issue_valid,issue_accept,issue_pc,issue_opcode,issue_ra,issue_rb,issue_rd,issue_ra_value,issue_rb_value,scoreboard_hazard,stall,lsu_stall,squash,pipe_load_e1,pipe_store_e1,pipe_mul_e1,pipe_rd_e1,pipe_pc_e1,pipe_opcode_e1,pipe_load_e2,pipe_mul_e2,pipe_rd_e2,pipe_result_e2,wb_valid,wb_rd,wb_pc,wb_opcode,wb_result,lsu_opcode_valid,lsu_pc,lsu_opcode,lsu_ra,lsu_rb,lsu_ra_value,lsu_rb_value,mem_request,mem_accept,mem_ack,mem_addr,mem_data,mem_wr,mem_wb_valid,mem_exception,branch_request,branch_mispredict,branch_flush\n");
                std::printf("RAW_TRACE enabled limit=%llu file=raw_trace.csv\n",
                            static_cast<unsigned long long>(m_raw_trace_limit));
            }
        }

        const char *shared_mode = std::getenv("ULTRA_V4_SHARED_OBS");
        const char *corrected_mode = std::getenv("ULTRA_V4_CORRECTED_OBS");
        m_shared_corrected_mode = corrected_mode &&
                                  std::strtoul(corrected_mode, NULL, 0) != 0;
        m_shared_observer_enabled = m_shared_corrected_mode ||
                                     (shared_mode &&
                                      std::strtoul(shared_mode, NULL, 0) != 0);
        if (m_shared_observer_enabled)
        {
            const char *warmup_name = m_shared_corrected_mode ?
                                       "ULTRA_V4_CORRECTED_WARMUP_ITERS" :
                                       "ULTRA_V4_SHARED_WARMUP_ITERS";
            const char *sample_name = m_shared_corrected_mode ?
                                       "ULTRA_V4_CORRECTED_SAMPLE_ITERS" :
                                       "ULTRA_V4_SHARED_SAMPLE_ITERS";
            const char *limit_name = m_shared_corrected_mode ?
                                      "ULTRA_V4_CORRECTED_EVENT_LIMIT" :
                                      "ULTRA_V4_SHARED_EVENT_LIMIT";
            m_shared_warmup_iters = env_u32(warmup_name, 2);
            m_shared_sample_iters = env_u32(sample_name, 8);
            m_shared_event_limit = env_u64(limit_name, 1000000);
            const char *event_file = m_shared_corrected_mode ?
                                     std::getenv("ULTRA_V4_CORRECTED_EVENT_FILE") :
                                     std::getenv("ULTRA_V4_SHARED_EVENT_FILE");
            if (!event_file || !*event_file)
                event_file = m_shared_corrected_mode ?
                             "v4_corrected_events.csv" : "v4_shared_events.csv";
            m_shared_event_fd = std::fopen(event_file, "w");
            if (!m_shared_event_fd)
            {
                std::fprintf(stderr, "%s cannot open %s\n",
                             m_shared_corrected_mode ? "V4_CORRECTED" : "V4_SHARED",
                             event_file);
                m_closure_failure = true;
            }
            else
            {
                if (m_shared_corrected_mode)
                    std::fprintf(m_shared_event_fd,
                        "cycle,roi_iter,roi,event,p0,p1,p2,p3,p4,p5,p6,p7,p8,p9,p10,p11,p12,p13,p14,p15,p16,p17,p18,p19,p20,p21,p22,p23,p24,p25,p26,p27,p28,p29,p30,p31,p32,p33,p34,p35,p36,p37,p38,p39,p40,p41,p42,p43,p44,p45,p46,p47,p48,p49,p50,p51,p52,p53,p54,p55,p56,p57,p58,p59,p60,p61,p62,p63\n");
                else
                    std::fprintf(m_shared_event_fd,
                        "cycle,roi_iter,roi,event,a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r,s,t,u,v,w,x,y,z\n");
                std::printf("%s enabled warmup=%u sample=%u event_limit=%llu file=%s iteration_boundary_pc=0x000020ac\n",
                            m_shared_corrected_mode ? "V4_CORRECTED" : "V4_SHARED",
                            m_shared_warmup_iters, m_shared_sample_iters,
                            static_cast<unsigned long long>(m_shared_event_limit),
                            event_file);
            }
        }
        const char *early_mode = std::getenv("ULTRA_EARLY_TCM_TRACE");
        m_early_observer_enabled = early_mode && std::strtoul(early_mode, NULL, 0) != 0;
        if (m_early_observer_enabled)
        {
            m_early_warmup_iters = env_u32("ULTRA_EARLY_WARMUP_ITERS", 2);
            m_early_sample_iters = env_u32("ULTRA_EARLY_SAMPLE_ITERS", 8);
            m_early_trace_limit = env_u64("ULTRA_EARLY_TRACE_LIMIT", 50000);
            m_early_trace_fd = std::fopen("early_trace.csv", "w");
            if (!m_early_trace_fd)
            {
                std::fprintf(stderr, "EARLY_OBS cannot open early_trace.csv\n");
                m_closure_failure = true;
            }
            else
            {
                std::fprintf(m_early_trace_fd,
                    "cycle,phase,iter_entries,issue_decode_valid,issue_valid,issue_accept,issue_pc,issue_opcode,issue_ra,issue_rb,issue_rd,issue_ra_value,issue_rb_value,scoreboard_stall,scoreboard_hazard,stall,lsu_stall,squash,pipe_load_e1,pipe_store_e1,pipe_mul_e1,pipe_rd_e1,pipe_pc_e1,pipe_opcode_e1,pipe_load_e2,pipe_mul_e2,pipe_rd_e2,pipe_result_e2,wb_valid,wb_rd,wb_pc,wb_opcode,wb_result,lsu_opcode_valid,lsu_pc,lsu_opcode,lsu_ra,lsu_rb,lsu_ra_value,lsu_rb_value,lsu_agu_addr,lsu_addr_q,lsu_data_r,lsu_data_q,lsu_rd_r,lsu_rd_q,lsu_wr_r,lsu_wr_q,lsu_pending,lsu_delay,unaligned_e1,unaligned_e2,lsu_issue,lsu_complete_ok,lsu_complete_error,mem_request,mem_accept,mem_ack,mem_addr,mem_data,mem_wr,mem_wb_valid,mem_exception,mmu_addr,mmu_rd,mmu_wr,mmu_accept,mmu_ack,mmu_data,ram_addr,ram_request,ram_accept,ram_ack,ram_data,branch_request,branch_mispredict,branch_flush,commit_valid,commit_pc,commit_opcode\n");
                std::printf("EARLY_OBS enabled warmup=%u sample=%u trace_limit=%llu iteration_boundary_pc=0x000020ac\n",
                            m_early_warmup_iters, m_early_sample_iters,
                            static_cast<unsigned long long>(m_early_trace_limit));
            }
        }
        m_e_tcm_store_data_count[0] = 0;
        m_e_tcm_store_data_count[1] = 0;
        m_e_tcm_store_data_count[2] = 0;
        const char *focus_mode = std::getenv("ULTRA_E_TCM_FOCUS");
        m_e_tcm_focus_enabled = focus_mode && std::strtoul(focus_mode, NULL, 0) != 0;
        if (m_e_tcm_focus_enabled)
        {
            m_e_tcm_focus_limit = env_u64("ULTRA_E_TCM_TRACE_LIMIT", 20000);
            m_e_tcm_focus_fd = std::fopen("e_tcm_focus.csv", "w");
            if (!m_e_tcm_focus_fd)
            {
                std::fprintf(stderr, "ETCM_FOCUS cannot open e_tcm_focus.csv\n");
                m_closure_failure = true;
            }
            else
            {
                std::fprintf(m_e_tcm_focus_fd,
                    "cycle,phase,issue_valid,issue_accept,issue_pc,issue_opcode,issue_ra,issue_rb,issue_rd,issue_ra_value,issue_rb_value,fast_load_e1,fast_load_e2,early_release,match_ra,match_rb,base_ok,early_candidate,early_launch,early_live,early_hold,early_result_valid,early_result_rd,early_result_value,early_consume,mem_request,mem_accept,mem_ack,mem_addr,mem_data,mem_wr,ram_addr,ram_request,ram_accept,ram_ack,ram_data,pipe_load_e1,pipe_load_e2,pipe_rd_e1,pipe_rd_e2,stall,lsu_stall,branch_request,branch_mispredict,branch_flush,commit_valid,commit_pc,commit_opcode\n");
                std::printf("ETCM_FOCUS enabled limit=%llu file=e_tcm_focus.csv\n",
                            static_cast<unsigned long long>(m_e_tcm_focus_limit));
            }
        }
        for (int i = 0; i < 4; i++)
        {
            const std::string nt_name = std::string("ULTRA_SIDE_NT_WRONG_PC_") + std::to_string(i);
            const std::string pt_name = std::string("ULTRA_SIDE_PT_TARGET_PC_") + std::to_string(i);
            m_side_nt_wrong_pc[i] = env_u32(nt_name.c_str(), 0);
            m_side_pt_target_pc[i] = env_u32(pt_name.c_str(), 0);
            m_side_nt_wrong_commits[i] = 0;
            m_side_pt_target_commits[i] = 0;
        }
        m_side_expect_pred_taken = env_u32("ULTRA_SIDE_EXPECT_PRED_TAKEN", 0) != 0;
        const char *irq_mode = std::getenv("ULTRA_IRQ_TEST");
        m_irq_script_enabled = irq_mode && std::strtoul(irq_mode, NULL, 0) != 0;
        if (m_irq_script_enabled)
        {
            m_irq_mask_trigger_pc = env_u32("ULTRA_IRQ_MASK_TRIGGER_PC", 0xffffffffu);
            m_irq_mask_clear_pc = env_u32("ULTRA_IRQ_MASK_CLEAR_PC", 0xffffffffu);
            m_irq_enabled_trigger_pc = env_u32("ULTRA_IRQ_ENABLED_TRIGGER_PC", 0xffffffffu);
            m_irq_handler_pc = env_u32("ULTRA_IRQ_HANDLER_PC", 0xffffffffu);
            m_irq_branch_pc = env_u32("ULTRA_IRQ_BRANCH_PC", 0x00002054u);
            m_irq_script_stage = IRQ_WAIT_MASK_TRIGGER;
            std::printf("IRQ_DRIVER enabled: masked_trigger=0x%08x masked_clear=0x%08x enabled_trigger=0x%08x handler=0x%08x branch=0x%08x\n",
                        m_irq_mask_trigger_pc, m_irq_mask_clear_pc,
                        m_irq_enabled_trigger_pc, m_irq_handler_pc,
                        m_irq_branch_pc);
        }
		
    }
    //-----------------------------------------------------------------
    // Trace
    //-----------------------------------------------------------------
    void add_trace(sc_trace_file * fp, std::string prefix)
    {
        if (!waves_enabled())
            return;

        verilator_trace_enable("verilator.vcd", m_dut);

        // Add signals to trace file
        #define TRACE_SIGNAL(a) sc_trace(fp,a,#a);
        TRACE_SIGNAL(clk);
        TRACE_SIGNAL(rst);

        m_dut->add_trace(fp, "");
    }

    //-----------------------------------------------------------------
    // create_memory: Create memory region
    //-----------------------------------------------------------------
    bool create_memory(uint32_t base, uint32_t size, uint8_t *mem = NULL)
    {
        sc_assert(base >= 0x00000000 && ((base + size) < (0x00000000 + (64 * 1024))));
        return true;
    }
    //-----------------------------------------------------------------
    // valid_addr: Check address range
    //-----------------------------------------------------------------
    bool valid_addr(uint32_t addr) { return true; } 
    //-----------------------------------------------------------------
    // write: Write byte into memory
    //-----------------------------------------------------------------
    void write(uint32_t addr, uint8_t data)
    {
        m_dut->m_rtl->v->u_tcm->write(addr, data);
    }
    //-----------------------------------------------------------------
    // write: Read byte from memory
    //-----------------------------------------------------------------
    uint8_t read(uint32_t addr)
    {
        return m_dut->m_rtl->v->u_tcm->read(addr);
    }
    //-----------------------------------------------------------------
    // step: Execute 1 clock cycle
    //-----------------------------------------------------------------
    void step(void)
    {
        drive_irq_script();
        sample_irq_observation();
        v4_shared_sample_pre();
        early_classify_pre();
        e_tcm_focus_sample("pre");
        early_trace_sample("pre");
        wait();
        m_step_count++;
        sample_irq_observation();
        early_iteration_boundary();
        v4_shared_iteration_boundary();
        e_tcm_focus_sample("post");
        early_trace_sample("post");
        bounded_diag_sample();
        tcm_transaction_sample();
        raw_trace_sample();
    }
    //-----------------------------------------------------------------
    // reset: Release core from reset
    //-----------------------------------------------------------------
    void reset(uint32_t addr)
    {
        rst_cpu_in.write(true);
        wait();
        rst_cpu_in.write(false);
    }

    // The upstream testbench left these hooks as stubs. Expose the
    // Verilator-public completion hooks so isa_sim's -r stop-PC option can
    // terminate a bare-metal image instead of relying on an external kill.
    bool      get_stopped(void) {
        return (m_early_observer_enabled && m_early_stop_requested) ||
               (m_shared_observer_enabled && m_shared_stop_requested);
    }
    bool      get_fault(void)  { return m_closure_failure; }
    void      set_interrupt(int irq)
    {
        // The RTL top exposes a level-sensitive 32-bit interrupt bus; the
        // scalar core consumes bit 0 as its machine external interrupt.
        // Non-zero means source asserted, zero means source withdrawn.
        intr_in.write(irq ? 1 : 0);
    }
    void      report_stats(void)
    {
        auto *core = m_dut->m_rtl->v->u_core;
        sample_irq_observation();
        v4_shared_report();
        early_report();
        e_tcm_focus_report();
        tcm_transaction_report();
        const char *short_mode = std::getenv("ULTRA_SHORT_TRACE");
        if (short_mode && std::strtoul(short_mode, NULL, 0) != 0)
        {
            const uint32_t short_sig[10] = {
                read_word(0x0000e000), read_word(0x0000e004),
                read_word(0x0000e008), read_word(0x0000e00c),
                read_word(0x0000e010), read_word(0x0000e014),
                read_word(0x0000e018), read_word(0x0000e01c),
                read_word(0x0000e020), read_word(0x0000e024)
            };
            const uint32_t short_exp[10] = {
                0x11223344u, 0x00004400u, 0x00003344u, 0x0000003fu,
                0x13579bdfu, 0xcafebabeu, 0x11223344u, 0x00000037u,
                0xcafebabeu, 0x00006030u
            };
            std::printf("SHORT_OBS signature");
            bool short_ok = true;
            for (unsigned i = 0; i < 10u; ++i)
            {
                std::printf(" s%u=0x%08x", i, short_sig[i]);
                if (short_sig[i] != short_exp[i])
                    short_ok = false;
            }
            std::printf(" status=%s\n", short_ok ? "PASS" : "FAIL");
            if (!short_ok)
                m_closure_failure = true;
        }
        if (m_irq_script_enabled)
        {
            const uint32_t sig0 = read_word(0x0000e000);
            const uint32_t sig1 = read_word(0x0000e004);
            const uint32_t sig2 = read_word(0x0000e008);
            const uint32_t sig3 = read_word(0x0000e00c);
            std::printf("IRQ_OBS signature masked_handlers=%u enabled_handlers=%u mcause=0x%08x mepc=0x%08x\n",
                        sig0, sig1, sig2, sig3);
            if (m_irq_script_stage != IRQ_SCRIPT_DONE ||
                sig0 != 0 || sig1 != 1 || sig2 != 0x8000000b || sig3 == 0)
            {
                std::fprintf(stderr,
                             "IRQ_DRIVER closure failed: stage=%d signature or source-state check mismatch\n",
                             m_irq_script_stage);
                m_closure_failure = true;
            }
            std::printf("IRQ_OBS summary takes=%u exception_events=%u exception_pc=0x%08x mepc=0x%08x mcause=0x%08x mip=0x%08x\n",
                        m_irq_take_count, m_irq_exception_event_count,
                        m_irq_accept_pc, m_irq_accept_mepc,
                        m_irq_accept_mcause, core->csr_mip_value());
            std::printf("IRQ_OBS branch_interleave window=%u mispredict=%u branch_pc=0x%08x\n",
                        m_irq_branch_window_seen ? 1 : 0,
                        m_irq_branch_mispredict_seen ? 1 : 0,
                        m_irq_branch_pc);
            if (!m_irq_branch_window_seen || !m_irq_branch_mispredict_seen)
            {
                std::fprintf(stderr,
                             "IRQ_DRIVER did not observe the enabled interrupt window crossing the target branch and its mispredict\n");
                m_closure_failure = true;
            }
        }
        if (m_side_effect_test_enabled)
        {
            const uint32_t sig0 = read_word(0x0000e000);
            const uint32_t sig1 = read_word(0x0000e004);
            const uint32_t sig2 = read_word(0x0000e008);
            const uint32_t sig3 = read_word(0x0000e00c);
            const uint32_t sig4 = read_word(0x0000e010);
            const uint32_t sig5 = read_word(0x0000e014);
            const uint32_t sig6 = read_word(0x0000e018);
            const uint32_t sig7 = read_word(0x0000e01c);
            std::printf("SIDE_EFFECT_OBS signature nt_reg=%u nt_wrong_tcm=0x%08x nt_pos_tcm=0x%08x nt_mscratch=0x%08x nt_mtvec=0x%08x pt_reg=%u pt_tcm=0x%08x pt_mscratch=0x%08x\n",
                        sig0, sig1, sig2, sig3, sig4, sig5, sig6, sig7);
            std::printf("SIDE_EFFECT_OBS mmio total=%u nt_count=%u nt_last=0x%08x pt_count=%u pt_last=0x%08x\n",
                        m_mmio_write_count, m_mmio_nt_count, m_mmio_nt_last_data,
                        m_mmio_pt_count, m_mmio_pt_last_data);
            if (sig0 != 2 || sig1 != 0 || sig2 != 0x51aa0001 ||
                sig3 != 0 || sig4 != 0x00002220 || sig5 != 1 ||
                sig6 != 0x5a550001 || sig7 != 0x0000a501 ||
                m_mmio_write_count != 2 || m_mmio_nt_count != 1 ||
                m_mmio_pt_count != 1 || m_mmio_nt_last_data != 0x11110001 ||
                m_mmio_pt_last_data != 0x22220001 ||
                m_mmio_aw_pending || m_mmio_w_pending || m_mmio_bvalid)
            {
                std::fprintf(stderr, "SIDE_EFFECT_DRIVER closure failed\n");
                m_closure_failure = true;
            }
            for (int i = 0; i < 4; i++)
            {
                std::printf("SIDE_EFFECT_OBS commit nt_wrong[%d]=%u pt_target[%d]=%u\n",
                            i, m_side_nt_wrong_commits[i], i,
                            m_side_pt_target_commits[i]);
                if (m_side_nt_wrong_pc[i] != 0 && m_side_nt_wrong_commits[i] != 0)
                    m_closure_failure = true;
                if (m_side_pt_target_pc[i] != 0 && m_side_pt_target_commits[i] != 1)
                    m_closure_failure = true;
            }
            if (m_side_expect_pred_taken && core->branch_pred_taken_count() < 4)
            {
                std::fprintf(stderr, "SIDE_EFFECT_DRIVER did not observe four predicted-taken branches\n");
                m_closure_failure = true;
            }
        }
        std::printf("branch_resolved       : %u\n", core->branch_resolved_count());
        std::printf("branch_conditional    : %u\n", core->branch_conditional_count());
        std::printf("branch_jal            : %u\n", core->branch_jal_count());
        std::printf("branch_jalr_ret       : %u\n", core->branch_jalr_count());
        std::printf("branch_btb_hit        : %u\n", core->branch_btb_hit_count());
        std::printf("branch_btb_miss       : %u\n", core->branch_btb_miss_count());
        std::printf("branch_pred_taken     : %u\n", core->branch_pred_taken_count());
        std::printf("branch_correct        : %u\n", core->branch_correct_count());
        std::printf("branch_mispredict     : %u\n", core->branch_mispredict_count());
        std::fflush(stdout);
    }
    void      enable_trace(uint32_t mask) { }
    uint32_t  get_opcode(void)    { return m_dut->m_rtl->v->u_core->u_issue->complete_opcode0(); }
    uint32_t  get_pc(void)
    {
        if (m_dut->m_rtl->v->u_core->u_issue->complete_valid0())
        {
            m_last_pc = m_dut->m_rtl->v->u_core->u_issue->complete_pc0();
            if (m_side_last_commit_step != m_step_count)
            {
                sample_side_effect_commit(m_last_pc);
                m_side_last_commit_step = m_step_count;
            }
        }
        return m_last_pc;
    }
    bool      get_reg_valid(int r){ return 0; }
    uint32_t  get_register(int r) { return 0; }
    int       get_num_reg(void)   { return 32; }
    void      set_register(int r, uint32_t val) { }    
};
