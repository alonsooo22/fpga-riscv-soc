#include "testbench_vbase.h"

#include "riscv_main.h"
#include "riscv.h"
#include "elf_load.h"

#include <unistd.h>
#include <cstdio>
#include <cstdlib>
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
        std::fflush(stdout);
        exit(exitcode);
    }

    void set_argcv(int argc, char* argv[]) { m_argc = argc; m_argv = argv; }

    //-----------------------------------------------------------------
    // Construction
    //-----------------------------------------------------------------
    SC_HAS_PROCESS(testbench);
    testbench(sc_module_name name): testbench_vbase(name),
        m_last_pc(0), m_step_count(0),
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
        m_side_last_commit_step(~static_cast<uint64_t>(0))
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
        const char *side_effect_mode = std::getenv("ULTRA_SIDE_EFFECT_TEST");
        m_side_effect_test_enabled = side_effect_mode &&
                                      std::strtoul(side_effect_mode, NULL, 0) != 0;
        SC_CTHREAD(mmio_monitor, clk);
        if (m_side_effect_test_enabled)
            std::printf("SIDE_EFFECT_DRIVER enabled: MMIO 0x%08x/0x%08x\n",
                        MMIO_NT_ADDR, MMIO_PT_ADDR);
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
        wait();
        m_step_count++;
        sample_irq_observation();
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
    bool      get_stopped(void) { return false; }
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
