// Author: Divjot Kaur, University of Waterloo
// Date: 27.05.2023
// Description: Performance counters interface

module evu_top import ariane_pkg::*; #(   
    parameter ariane_pkg::ariane_cfg_t ArianeCfg     = ariane_pkg::ArianeDefaultConfig, 
    parameter int unsigned ASID_WIDTH = 0,
    parameter int unsigned NUM_SEL_LINE_REG = 1,
    parameter int unsigned AxiLiteAddrWidth = 32'd0,
    parameter int unsigned AxiLiteDataWidth = 32'd0,
    parameter type lite_req_t     = logic,
    parameter type lite_resp_t    = logic
) (
  input logic                         clk_i,
  input logic                         rst_ni,
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
  input lite_req_t  axi_evu_cfg_req_i,
  output lite_resp_t axi_evu_cfg_resp_o,
  input riscv::priv_lvl_t priv_lvl_i,
  input logic [ASID_WIDTH-1:0]   asid_i,
  SPU_INTF.Output        evu_output

);

reg [1:0]priv_lvl_o;
`include "axi/typedef.svh"
localparam int unsigned NumBytesCfgRegs = NUM_SEL_LINE_REG*32/8; // 32 bit - 4 bytes
    
// Memory Map - Local Parameters and TypeDefs
localparam int unsigned REG_WIDTH = 32;
typedef logic [7:0] byte_t;
typedef logic [REG_WIDTH-1:0]   reg_t;
typedef logic [(REG_WIDTH/8):0]  strb_reg_t;

    typedef struct packed {
        reg_t            sel_line_reg;        
    } reg_map_t; 

    typedef struct packed {
        strb_reg_t            sel_line_reg;        
    } strb_map_t; 
    
    typedef union packed {
        byte_t              [NumBytesCfgRegs-1:0]   ByteMap;
        reg_map_t                                   StructMap;
    } union_reg_data_t;

    typedef union packed {
        logic               [NumBytesCfgRegs-1:0]   LogicMap;
        strb_map_t                                  StrbMap;
    } union_strb_data_t;

    // ************************************************************************
    // AXI4-Lite Registers
    // ************************************************************************
    union_reg_data_t    reg_d, reg_q;
    union_strb_data_t   reg_wr_o;
    union_strb_data_t   reg_load_i;

    axi_lite_regs#(
        .RegNumBytes  ( NumBytesCfgRegs     ),
        .AxiAddrWidth ( AxiLiteAddrWidth    ),
        .AxiDataWidth ( AxiLiteDataWidth    ),
        .PrivProtOnly ( 1'b0                ),
        .SecuProtOnly ( 1'b0                ),
        .AxiReadOnly  ( ReadOnly.StrbMap    ), 
        .RegRstVal    ( RstVal              ),
        .req_lite_t   ( lite_req_t          ),
        .resp_lite_t  ( lite_resp_t         )
        ) i_axi_lite_regs (
        .clk_i,
        .rst_ni,
        .axi_req_i   ( axi_evu_cfg_req_i    ),
        .axi_resp_o  ( axi_evu_cfg_resp_o   ),
        .wr_active_o ( reg_wr_o.LogicMap    ),
        .rd_active_o ( /*Not used*/         ),
        .reg_d_i     ( reg_d.ByteMap        ),
        .reg_load_i  ( reg_load_i.LogicMap  ),
        .reg_q_o     ( reg_q.ByteMap        )
    );
    always_ff @(posedge clk_i or negedge rst_ni) begin
        case (priv_lvl)
        riscv::PRIV_LVL_M: priv_lvl_o = 2'b01;
        riscv::PRIV_LVL_S: priv_lvl_o = 2'b10;
        riscv::PRIV_LVL_U: priv_lvl_o = 2'b11;
        endcase
    end

wire evu_mux0_output;
wire evu_mux1_output;
wire evu_mux2_output;
wire evu_mux3_output;

evu_mux evu_mux1(.commit_instr_i(commit_instr_i), .commit_ack_i(commit_ack_i),
 .l1_icache_miss_i(l1_icache_miss_i), .l1_dcache_miss_i(l1_dcache_miss_i), 
 .itlb_miss_i(itlb_miss_i), .dtlb_miss_i(dtlb_miss_i), .sb_full_i(sb_full_i), 
 .if_empty_i(if_empty_i), .ex_i(ex_i), .eret_i(eret_i), 
 .resolved_branch_i(resolved_branch_i), .sel_line(reg_q.StructMap.sel_line_reg[3:0]), .evu_mux_output(evu_mux0_output) );

evu_mux evu_mux2(.commit_instr_i(commit_instr_i), .commit_ack_i(commit_ack_i),
 .l1_icache_miss_i(l1_icache_miss_i), .l1_dcache_miss_i(l1_dcache_miss_i), 
 .itlb_miss_i(itlb_miss_i), .dtlb_miss_i(dtlb_miss_i), .sb_full_i(sb_full_i), 
 .if_empty_i(if_empty_i), .ex_i(ex_i), .eret_i(eret_i), 
 .resolved_branch_i(resolved_branch_i), .sel_line(reg_q.StructMap.sel_line_reg[3:0]), .evu_mux_output(evu_mux1_output) );

evu_mux evu_mux3(.commit_instr_i(commit_instr_i), .commit_ack_i(commit_ack_i),
 .l1_icache_miss_i(l1_icache_miss_i), .l1_dcache_miss_i(l1_dcache_miss_i), 
 .itlb_miss_i(itlb_miss_i), .dtlb_miss_i(dtlb_miss_i), .sb_full_i(sb_full_i), 
 .if_empty_i(if_empty_i), .ex_i(ex_i), .eret_i(eret_i), 
 .resolved_branch_i(resolved_branch_i), .sel_line(reg_q.StructMap.sel_line_reg[3:0]), .evu_mux_output(evu_mux2_output) );

evu_mux evu_mux4(.commit_instr_i(commit_instr_i), .commit_ack_i(commit_ack_i),
 .l1_icache_miss_i(l1_icache_miss_i), .l1_dcache_miss_i(l1_dcache_miss_i), 
 .itlb_miss_i(itlb_miss_i), .dtlb_miss_i(dtlb_miss_i), .sb_full_i(sb_full_i), 
 .if_empty_i(if_empty_i), .ex_i(ex_i), .eret_i(eret_i), 
 .resolved_branch_i(resolved_branch_i), .sel_line(reg_q.StructMap.sel_line_reg[3:0]), .evu_mux_output(evu_mux3_output) );


    assign evu_output.e_id= {evu_mux3_output, evu_mux2_output, evu_mux1_output, evu_mux0_output};
    assign vu_output.e_info= {priv_lvl_o, asid_i};
    assign evu_output.s_id=1'b0;


endmodule