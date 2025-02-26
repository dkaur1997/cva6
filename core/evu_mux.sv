// Author: Divjot Kaur, University of Waterloo
// Date: 27.05.2023
// Description: Performance counters interface

module evu_mux import ariane_pkg::*; (
  input logic                                     clk_i,
  input logic                                     rst_ni,
      // from commit stage
  input  scoreboard_entry_t [NR_COMMIT_PORTS-1:0] commit_instr_i,     // the instruction we want to commit
  input  logic [NR_COMMIT_PORTS-1:0]              commit_ack_i,       // acknowledge that we are indeed committing
    // from L1 caches
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
  input  logic                                    debug_mode_i, // debug mode
  input logic [3:0]sel_line,
  output logic evu_mux_output
);
int unsigned i = 0;
logic evu_mux_output0;
logic evu_mux_output1;
  //always_comb begin
    // don't increment counters in debug mode
    always @(posedge clk_i) begin
    if(!rst_ni)
        evu_mux_output=1'b0;
    else if (!debug_mode_i) begin
          if(sel_line==4'b0010) begin //I$ miss
             if (l1_icache_miss_i) begin
              evu_mux_output<=1'b1;
              end
              else evu_mux_output<=1'b0;
            end
          else if (sel_line==4'b0011) begin //D$ miss
             if (l1_dcache_miss_i) begin
              evu_mux_output<=1'b1;
              end
              else evu_mux_output<=1'b0;
            end
          else if (sel_line==4'b0100) begin //ITLB_miss
             if (itlb_miss_i) begin
              evu_mux_output=itlb_miss_i;
              end
            end
          else if (sel_line==4'b0101) begin //DTLB_miss
             if (dtlb_miss_i) begin
              evu_mux_output=dtlb_miss_i;
              end
            end
          else if (sel_line==4'b0110) begin //Loads
             if(commit_ack_i[0])begin
                if (commit_instr_i[0].fu == LOAD)
                  evu_mux_output0<=1'b1;
                else evu_mux_output0<=1'b0;
              end
            else evu_mux_output0<=1'b0;

            if(commit_ack_i[1])begin
                if (commit_instr_i[1].fu == LOAD)
                  evu_mux_output1<=1'b1;
                else evu_mux_output1<=1'b0;
            end
            else evu_mux_output1<=1'b0;
            evu_mux_output<=(evu_mux_output0 | evu_mux_output1);
            end
    else if (sel_line==4'b0111) begin //Stores
             if(commit_ack_i[0])begin
                if (commit_instr_i[0].fu == STORE)
                  evu_mux_output0<=1'b1;
                else evu_mux_output0<=1'b0;
              end
              else evu_mux_output0<=1'b0;
              
              if(commit_ack_i[1])begin
                if (commit_instr_i[1].fu == STORE)
                  evu_mux_output1<=1'b1;
                else evu_mux_output1<=1'b0;
              end
              else evu_mux_output1<=1'b0;
            evu_mux_output=evu_mux_output0 | evu_mux_output1;
    end
    else if (sel_line==4'b1000) begin //Taken Exceptions
            if (ex_i.valid)begin
            evu_mux_output=1'b1;
            end
            else evu_mux_output=1'b0;
    end
    else if (sel_line==4'b1001) begin //Exceptions Returned
             if (eret_i)begin
             evu_mux_output=1'b1;
             end
             else evu_mux_output=1'b0;
    end
    else if (sel_line==4'b1010) begin //Branches and Jumps
             if(commit_ack_i[0])begin
                if (commit_instr_i[0].fu == CTRL_FLOW)
                  evu_mux_output0=1'b1; 
             end
             else evu_mux_output0=1'b0;
              if(commit_ack_i[1])begin
                if (commit_instr_i[1].fu == CTRL_FLOW)
                  evu_mux_output1=1'b1; 
             end
             else evu_mux_output1=1'b0;
            evu_mux_output=evu_mux_output0 | evu_mux_output1;
    end 
    else if (sel_line==4'b1011) begin //Calls
             if(commit_ack_i[0])begin
                if (commit_instr_i[0].fu == CTRL_FLOW && (commit_instr_i[0].op == '0 || commit_instr_i[0].op == JALR) && (commit_instr_i[0].rd == 'd1 || commit_instr_i[0].rd == 'd5) )
                  evu_mux_output0=1'b1;
             end
             else evu_mux_output0=1'b0;
             if(commit_ack_i[1])begin
                if (commit_instr_i[1].fu == CTRL_FLOW && (commit_instr_i[1].op == '0 || commit_instr_i[1].op == JALR) && (commit_instr_i[1].rd == 'd1 || commit_instr_i[1].rd == 'd5) )
                  evu_mux_output1=1'b1;
             end
             else evu_mux_output1=1'b0;
            evu_mux_output=evu_mux_output0 | evu_mux_output1;
    end         
    else if (sel_line==4'b1100) begin //Returns
             if(commit_ack_i[0])begin
                if (commit_instr_i[0].op == JALR && (commit_instr_i[0].rd == 'd0))
                  evu_mux_output0=1'b1; 
              end
              else evu_mux_output0=1'b0;
              if(commit_ack_i[1])begin
                if (commit_instr_i[1].op == JALR && (commit_instr_i[1].rd == 'd0))
                  evu_mux_output1=1'b1; 
              end
              else evu_mux_output1=1'b0;
            evu_mux_output=evu_mux_output0 | evu_mux_output1;
    end
    else if (sel_line==4'b1101) begin //Mispreducted Branches
             if (resolved_branch_i.valid && resolved_branch_i.is_mispredict) begin
             evu_mux_output=1'b1;
             end
             else evu_mux_output=1'b0;
    end
    else if (sel_line==4'b1110) begin //Scoreboard Full
             if (sb_full_i) begin
             evu_mux_output=1'b1;
             end
             else evu_mux_output=1'b0;
    end
    else if (sel_line==4'b1111) begin //Instruction Fetch Empty
             if (if_empty_i) begin
             evu_mux_output=1'b1;
             end
             else evu_mux_output=1'b0;
    end
end
end
endmodule


        
