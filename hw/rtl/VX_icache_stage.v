`include "VX_define.vh"

module VX_icache_stage #(
    parameter CORE_ID = 0
) (
    `SCOPE_IO_VX_icache_stage

    input  wire         clk,
    input  wire         reset,
    
    // Icache interface
    VX_icache_req_if    icache_req_if,
    VX_icache_rsp_if    icache_rsp_if,
    
    // request
    VX_ifetch_req_if    ifetch_req_if,

    // reponse
    VX_ifetch_rsp_if    ifetch_rsp_if
);

    `UNUSED_PARAM (CORE_ID)
    `UNUSED_VAR (reset)

    localparam OUTPUT_REG = 0;

    wire icache_req_fire = icache_req_if.valid && icache_req_if.ready;
    
    wire [`NW_BITS-1:0] req_tag = ifetch_req_if.wid;
    wire [`NW_BITS-1:0] rsp_tag = icache_rsp_if.tag[`NW_BITS-1:0];

    wire [31:0] rsp_PC;
    wire [`NUM_THREADS-1:0] rsp_tmask;

    VX_dp_ram #(
        .DATAW(32 + `NUM_THREADS),
        .SIZE(`NUM_WARPS),
        .FASTRAM(1)
    ) req_metadata (
        .clk(clk),
        .waddr(req_tag),                                
        .raddr(rsp_tag),
        .wren(icache_req_fire),
        .byteen(1'b1),
        .rden(ifetch_rsp_if.valid),
        .din({ifetch_req_if.PC,  ifetch_req_if.tmask}),
        .dout({rsp_PC,           rsp_tmask})
    );

    // Icache Request
    assign icache_req_if.valid = ifetch_req_if.valid;
    assign icache_req_if.addr  = ifetch_req_if.PC[31:2];

    // Can accept new request?
    assign ifetch_req_if.ready = icache_req_if.ready;

`ifdef DBG_CACHE_REQ_INFO  
    assign icache_req_if.tag = {ifetch_req_if.wid, ifetch_req_if.PC, req_tag};
`else
    assign icache_req_if.tag = req_tag;
`endif

    wire [`NW_BITS-1:0] rsp_wid = rsp_tag;

    wire stall_out = ~ifetch_rsp_if.ready && (0 == OUTPUT_REG && ifetch_rsp_if.valid);

    VX_pipe_register #(
        .DATAW  (1 + `NW_BITS + `NUM_THREADS + 32 + 32),
        .RESETW (1),
        .DEPTH  (OUTPUT_REG)
    ) pipe_reg (
        .clk      (clk),
        .reset    (reset),
        .enable   (!stall_out),
        .data_in  ({icache_rsp_if.valid, rsp_wid,           rsp_tmask,           rsp_PC,           icache_rsp_if.data}),
        .data_out ({ifetch_rsp_if.valid, ifetch_rsp_if.wid, ifetch_rsp_if.tmask, ifetch_rsp_if.PC, ifetch_rsp_if.data})
    );     
    
    // Can accept new response?
    assign icache_rsp_if.ready = ~stall_out;

    `SCOPE_ASSIGN (icache_req_fire, icache_req_fire);
    `SCOPE_ASSIGN (icache_req_wid,  ifetch_req_if.wid);
    `SCOPE_ASSIGN (icache_req_addr, {icache_req_if.addr, 2'b0});    
    `SCOPE_ASSIGN (icache_req_tag,  req_tag);
    `SCOPE_ASSIGN (icache_rsp_fire, icache_rsp_if.valid && icache_rsp_if.ready);
    `SCOPE_ASSIGN (icache_rsp_data, icache_rsp_if.data);
    `SCOPE_ASSIGN (icache_rsp_tag,  rsp_tag);

`ifdef DBG_PRINT_CORE_ICACHE
    always @(posedge clk) begin
        if (icache_req_if.valid && icache_req_if.ready) begin
            $display("%t: I$%0d req: wid=%0d, PC=%0h", $time, CORE_ID, ifetch_req_if.wid, ifetch_req_if.PC);
        end
        if (ifetch_rsp_if.valid && ifetch_rsp_if.ready) begin
            $display("%t: I$%0d rsp: wid=%0d, PC=%0h, data=%0h", $time, CORE_ID, ifetch_rsp_if.wid, ifetch_rsp_if.PC, ifetch_rsp_if.data);
        end
    end
`endif

endmodule