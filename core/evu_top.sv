// Author: Divjot Kaur, University of Waterloo
// Date: 27.05.2023
// Description: Performance counters interface
`include "axi/typedef.svh"
module evu_top 
import ariane_pkg::*;
import ariane_axi_soc::*; #(   
    parameter ariane_pkg::ariane_cfg_t ArianeCfg     = ariane_pkg::ArianeDefaultConfig, 
    parameter int unsigned ASID_WIDTH = 0,
    parameter int unsigned NUM_SEL_LINE_REG = 1,
    parameter int unsigned NUM_PC_REG = 1,
    parameter int unsigned AxiLiteAddrWidth = 32'd32,
    parameter int unsigned AxiLiteDataWidth = 32'd32
   //parameter type lite_req_t     = logic,
    //parameter type lite_resp_t    = logic
    ) (
  input logic                                     clk_i,
  input logic                                     rst_ni,
  //commit
  input  scoreboard_entry_t [NR_COMMIT_PORTS-1:0] commit_instr_i,     // the instruction we want to commit
  input  logic [NR_COMMIT_PORTS-1:0]              commit_ack_i,       // acknowledge that we are indeed committing
  //register
  input  logic                                    l1_icache_miss_i,
  input  logic                                    l1_dcache_miss_i,
  // from MMU
  input  logic                                    itlb_miss_i,
  input  logic                                    dtlb_miss_i,
  // from issue stage
  input  logic                                    sb_full_i,
  // from frontend
  input  logic                                    if_empty_i,
  // from PC Gen
  input  exception_t                              ex_i,
  input  logic                                    eret_i,
  input  bp_resolve_t                             resolved_branch_i,
  input ariane_axi_soc::req_lite_t                axi_evu_cfg_req_i,
  output ariane_axi_soc::resp_lite_t              axi_evu_cfg_resp_o,
  input riscv::priv_lvl_t                         priv_lvl_i,
  input logic [ASID_WIDTH-1:0]                    asid_i,
  SPU_INTF.Output                                 evu_output,
  input logic [riscv::VLEN-1:0]                   pc_commit_i,
  input  logic                                    debug_mode_i
);

reg [1:0] priv_lvl_o;
logic [riscv::VLEN-1:0] pc_1_compare_reg;
logic [riscv::VLEN-1:0] pc_2_compare_reg;
logic [riscv::VLEN-1:0] pc_3_compare_reg;
logic [riscv::VLEN-1:0] pc_4_compare_reg;

localparam int unsigned NumBytesCfgRegs = NUM_SEL_LINE_REG*32/8; // 32 bit - 4 bytes
localparam int unsigned NumBytesPCRegs = 4;
    
// Memory Map - Local Parameters and TypeDefs
localparam int unsigned REG_WIDTH = 32;
typedef logic [7:0] byte_t;
typedef logic [REG_WIDTH-1:0]   reg_t;
//typedef logic [REG_WIDTH-1:0]   reg_pc_t;
typedef logic [NumBytesCfgRegs-1:0]  strb_reg_t;
//typedef logic [NumBytesPCRegs-1:0]  strb_reg_pc_t;

    typedef struct packed {          
        reg_t            pc_4_compare_reg_msb;     
        reg_t            pc_4_compare_reg_lsb; 
        reg_t            pc_3_compare_reg_msb;     
        reg_t            pc_3_compare_reg_lsb; 
        reg_t            pc_2_compare_reg_msb;     
        reg_t            pc_2_compare_reg_lsb; 
        reg_t            pc_1_compare_reg_msb;     
        reg_t            pc_1_compare_reg_lsb; 
        reg_t            sel_line_reg;
    } reg_map_t; 

    typedef struct packed {
        strb_reg_t            pc_4_compare_reg_msb;     
        strb_reg_t            pc_4_compare_reg_lsb; 
        strb_reg_t            pc_3_compare_reg_msb;     
        strb_reg_t            pc_3_compare_reg_lsb; 
        strb_reg_t            pc_2_compare_reg_msb;     
        strb_reg_t            pc_2_compare_reg_lsb; 
        strb_reg_t            pc_1_compare_reg_msb;
        strb_reg_t            pc_1_compare_reg_lsb;
        strb_reg_t            sel_line_reg;  
    } strb_map_t; 
    
    typedef union packed {
        byte_t              [(NumBytesCfgRegs*9)-1:0]   ByteMap;
        reg_map_t                                       StructMap;
    } union_reg_data_t;

    typedef union packed {
        logic               [(NumBytesCfgRegs*9)-1:0]   LogicMap;
        strb_map_t                                      StrbMap;
    } union_strb_data_t;
    
    
    // ************************************************************************
    // AXI4-Lite Registers
    // ************************************************************************
    union_reg_data_t    reg_d, reg_q;
    union_strb_data_t   reg_wr_o;
    union_strb_data_t   reg_load_i;
    localparam strb_map_t RstVal = 0;
    localparam strb_map_t strb_ReadOnly=strb_map_t'{
        sel_line_reg: {NumBytesCfgRegs{4}},
        pc_1_compare_reg_lsb:{NumBytesPCRegs{4}},
        pc_1_compare_reg_msb:{NumBytesPCRegs{4}},
        pc_2_compare_reg_lsb:{NumBytesPCRegs{4}},
        pc_2_compare_reg_msb:{NumBytesPCRegs{4}},
        pc_3_compare_reg_lsb:{NumBytesPCRegs{4}},
        pc_3_compare_reg_msb:{NumBytesPCRegs{4}},
        pc_4_compare_reg_lsb:{NumBytesPCRegs{4}},
        pc_4_compare_reg_msb:{NumBytesPCRegs{4}},
        default: 0};
    localparam union_strb_data_t ReadOnly =strb_ReadOnly;

    // wr_active_o is asserted on the clock cycle at 
    // which the AXI4 write take places. 
    // Need to register it, to update the counter after the write. 
    strb_map_t   reg_wr_r;

    always_ff @ (posedge clk_i) begin
        if (!rst_ni) begin
            reg_wr_r <= 0;
        end else begin
            reg_wr_r <= reg_wr_o.StrbMap;
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        case (priv_lvl_i)
        riscv::PRIV_LVL_M: priv_lvl_o = 2'b01;
        riscv::PRIV_LVL_S: priv_lvl_o = 2'b10;
        riscv::PRIV_LVL_U: priv_lvl_o = 2'b11;
        endcase
    end

    // reg_load_i must be intialized. 
    // It allows non-AX4-Lite writes to the registers.
    // These non-AXI4-Lite writes take precedence over AXI4-Lite writes.
    // If the reg_load_i signal is True for any register than any AXI4-Lite 
    // to that register in that clock cycle is stalled.
    always_comb begin
        reg_load_i.StrbMap.sel_line_reg     = 0;
        reg_load_i.StrbMap.pc_1_compare_reg_lsb = 0;
        reg_load_i.StrbMap.pc_1_compare_reg_msb = 0;
        reg_load_i.StrbMap.pc_2_compare_reg_lsb = 0;
        reg_load_i.StrbMap.pc_2_compare_reg_msb = 0;
        reg_load_i.StrbMap.pc_3_compare_reg_lsb = 0;
        reg_load_i.StrbMap.pc_3_compare_reg_msb = 0;
        reg_load_i.StrbMap.pc_4_compare_reg_lsb = 0;
        reg_load_i.StrbMap.pc_4_compare_reg_msb = 0;
        reg_d.StructMap.sel_line_reg = reg_q.StructMap.sel_line_reg;
        reg_d.StructMap.pc_1_compare_reg_lsb = reg_q.StructMap.pc_1_compare_reg_lsb;
        reg_d.StructMap.pc_1_compare_reg_msb = reg_q.StructMap.pc_1_compare_reg_msb;
        reg_d.StructMap.pc_1_compare_reg_lsb = reg_q.StructMap.pc_2_compare_reg_lsb;
        reg_d.StructMap.pc_1_compare_reg_msb = reg_q.StructMap.pc_2_compare_reg_msb;
        reg_d.StructMap.pc_1_compare_reg_lsb = reg_q.StructMap.pc_3_compare_reg_lsb;
        reg_d.StructMap.pc_1_compare_reg_msb = reg_q.StructMap.pc_3_compare_reg_msb;
        reg_d.StructMap.pc_1_compare_reg_lsb = reg_q.StructMap.pc_4_compare_reg_lsb;
        reg_d.StructMap.pc_1_compare_reg_msb = reg_q.StructMap.pc_4_compare_reg_msb;

    end

    axi_lite_regs#(
        .RegNumBytes  ( NumBytesCfgRegs*9     ),
        .AxiAddrWidth ( AxiLiteAddrWidth    ),
        .AxiDataWidth ( AxiLiteDataWidth    ),
        .PrivProtOnly ( 1'b0                ),
        .SecuProtOnly ( 1'b0                ),
        .AxiReadOnly  ( ReadOnly.StrbMap    ), 
        .RegRstVal    ( RstVal              ),
        .req_lite_t   ( ariane_axi_soc::req_lite_t),
        .resp_lite_t  ( ariane_axi_soc::resp_lite_t)
        ) i_axi_lite_regs (
        .clk_i,
        .rst_ni,
        .axi_req_i   ( axi_evu_cfg_req_i    ),        
        .axi_resp_o  ( axi_evu_cfg_resp_o   ),
        .wr_active_o ( reg_wr_o.LogicMap    ),
        .rd_active_o (  /* Not user */      ),
        .reg_d_i     ( reg_d.ByteMap        ),
        .reg_load_i  ( reg_load_i.LogicMap  ),
        .reg_q_o     ( reg_q.ByteMap        )
    );

wire evu_mux0_output;
wire evu_mux1_output;
wire evu_mux2_output;
wire evu_mux3_output;

evu_mux evu_mux0(
    .clk_i (clk_i),
    .rst_ni(rst_ni),
    .commit_instr_i(commit_instr_i), 
    .commit_ack_i(commit_ack_i),
    .l1_icache_miss_i(l1_icache_miss_i), 
    .l1_dcache_miss_i(l1_dcache_miss_i), 
    .itlb_miss_i(itlb_miss_i), 
    .dtlb_miss_i(dtlb_miss_i), 
    .sb_full_i(sb_full_i), 
    .if_empty_i(if_empty_i), 
    .ex_i(ex_i), 
    .eret_i(eret_i), 
    .resolved_branch_i(resolved_branch_i), 
    .sel_line(reg_q.StructMap.sel_line_reg[3:0]), 
    .evu_mux_output(evu_mux0_output), 
    .debug_mode_i(debug_mode_i));

evu_mux evu_mux1(
    .clk_i (clk_i),
    .rst_ni(rst_ni),
    .commit_instr_i(commit_instr_i), 
    .commit_ack_i(commit_ack_i),
    .l1_icache_miss_i(l1_icache_miss_i), 
    .l1_dcache_miss_i(l1_dcache_miss_i), 
    .itlb_miss_i(itlb_miss_i), 
    .dtlb_miss_i(dtlb_miss_i), 
    .sb_full_i(sb_full_i), 
    .if_empty_i(if_empty_i), 
    .ex_i(ex_i), 
    .eret_i(eret_i), 
    .resolved_branch_i(resolved_branch_i), 
    .sel_line(reg_q.StructMap.sel_line_reg[7:4]), 
    .evu_mux_output(evu_mux1_output) ,
    .debug_mode_i(debug_mode_i));

evu_mux evu_mux2(
    .clk_i (clk_i),
    .rst_ni(rst_ni),
    .commit_instr_i(commit_instr_i), 
    .commit_ack_i(commit_ack_i),
    .l1_icache_miss_i(l1_icache_miss_i), 
    .l1_dcache_miss_i(l1_dcache_miss_i), 
    .itlb_miss_i(itlb_miss_i), 
    .dtlb_miss_i(dtlb_miss_i), 
    .sb_full_i(sb_full_i), 
    .if_empty_i(if_empty_i), 
    .ex_i(ex_i), 
    .eret_i(eret_i), 
    .resolved_branch_i(resolved_branch_i), 
    .sel_line(reg_q.StructMap.sel_line_reg[11:8]), 
    .evu_mux_output(evu_mux2_output),
    .debug_mode_i(debug_mode_i) );

evu_mux evu_mux3(
    .clk_i (clk_i),
    .rst_ni(rst_ni),
    .commit_instr_i(commit_instr_i), 
    .commit_ack_i(commit_ack_i),
    .l1_icache_miss_i(l1_icache_miss_i), 
    .l1_dcache_miss_i(l1_dcache_miss_i), 
    .itlb_miss_i(itlb_miss_i), 
    .dtlb_miss_i(dtlb_miss_i), 
    .sb_full_i(sb_full_i), 
    .if_empty_i(if_empty_i), 
    .ex_i(ex_i), 
    .eret_i(eret_i), 
    .resolved_branch_i(resolved_branch_i), 
    .sel_line(reg_q.StructMap.sel_line_reg[15:12]), 
    .evu_mux_output(evu_mux3_output),
    .debug_mode_i(debug_mode_i) );

logic pc_comparator_o;
logic [1:0] counter_no_o;


    assign pc_1_compare_reg[riscv::VLEN-1:0]={reg_q.StructMap.pc_1_compare_reg_msb, reg_q.StructMap.pc_1_compare_reg_lsb};
    assign pc_2_compare_reg[riscv::VLEN-1:0]={reg_q.StructMap.pc_2_compare_reg_msb, reg_q.StructMap.pc_2_compare_reg_lsb};
    assign pc_3_compare_reg[riscv::VLEN-1:0]={reg_q.StructMap.pc_3_compare_reg_msb, reg_q.StructMap.pc_3_compare_reg_lsb};
    assign pc_4_compare_reg[riscv::VLEN-1:0]={reg_q.StructMap.pc_4_compare_reg_msb, reg_q.StructMap.pc_4_compare_reg_lsb};
//To check if PC has reached the pc_1_compare_reg

always @(posedge clk_i) begin
    if(~rst_ni) begin
        pc_comparator_o=1'bx;
        counter_no_o='x;
    end
    else if(pc_1_compare_reg==pc_commit_i) begin
        pc_comparator_o=1'b1;
        counter_no_o=2'b00;
    end
    else if(pc_2_compare_reg==pc_commit_i) begin
        pc_comparator_o=1'b1;
        counter_no_o=2'b01;
    end
    else if(pc_3_compare_reg==pc_commit_i) begin
        pc_comparator_o=1'b1;
        counter_no_o=2'b10;
    end
    else if(pc_4_compare_reg==pc_commit_i) begin
        pc_comparator_o=1'b1;
        counter_no_o=2'b11;
    end
    else begin
        pc_comparator_o=1'b0;
        counter_no_o=2'b00;
    end
end

assign evu_output.e_id= {pc_comparator_o, evu_mux3_output, evu_mux2_output, evu_mux1_output, evu_mux0_output};
assign evu_output.e_info= {counter_no_o, priv_lvl_o, asid_i};

endmodule
