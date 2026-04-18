module dual_port_mem_controller #(
    parameter integer DATA_WIDTH = 32,
    parameter integer ADDR_WIDTH = 8,
    parameter integer NUM_BANKS  = 4
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  port_a_en,
    input  wire                  port_a_we,
    input  wire [ADDR_WIDTH-1:0] port_a_addr,
    inout  wire [DATA_WIDTH-1:0] port_a_data,
    output reg                   port_a_drive_en,
    output reg                   port_a_busy,
    input  wire                  port_b_en,
    input  wire                  port_b_we,
    input  wire [ADDR_WIDTH-1:0] port_b_addr,
    inout  wire [DATA_WIDTH-1:0] port_b_data,
    output reg                   port_b_drive_en,
    output reg                   port_b_busy,
    output reg                   same_bank_hit,
    output reg                   write_collision,
    input  wire                  bist_start,
    output reg                   bist_active,
    output reg                   test_done,
    output reg                   test_fail,
    output reg  [2:0]            bist_phase,
    output reg  [ADDR_WIDTH-1:0] bist_addr
);

    localparam integer DEPTH      = (1 << ADDR_WIDTH);
    localparam integer BANK_SEL_W = (NUM_BANKS <= 1) ? 1 : $clog2(NUM_BANKS);

    localparam [2:0] BIST_IDLE       = 3'd0;
    localparam [2:0] BIST_W0         = 3'd1;
    localparam [2:0] BIST_UP_R0W1    = 3'd2;
    localparam [2:0] BIST_UP_R1W0    = 3'd3;
    localparam [2:0] BIST_DOWN_R0W1  = 3'd4;
    localparam [2:0] BIST_DOWN_R1W0  = 3'd5;
    localparam [2:0] BIST_R0         = 3'd6;

    localparam [ADDR_WIDTH-1:0] LAST_ADDR = {ADDR_WIDTH{1'b1}};

    reg  [DATA_WIDTH-1:0] mem_array [0:DEPTH-1];
    reg  [DATA_WIDTH-1:0] port_a_dout;
    reg  [DATA_WIDTH-1:0] port_b_dout;
    wire [DATA_WIDTH-1:0] port_a_din;
    wire [DATA_WIDTH-1:0] port_b_din;

    assign port_a_din  = port_a_data;
    assign port_b_din  = port_b_data;
    assign port_a_data = port_a_drive_en ? port_a_dout : {DATA_WIDTH{1'bz}};
    assign port_b_data = port_b_drive_en ? port_b_dout : {DATA_WIDTH{1'bz}};

    function [BANK_SEL_W-1:0] bank_sel;
        input [ADDR_WIDTH-1:0] addr;
        begin
            if (NUM_BANKS <= 1) begin
                bank_sel = {BANK_SEL_W{1'b0}};
            end else begin
                // Sequential addresses are interleaved across banks.
                bank_sel = addr[BANK_SEL_W-1:0];
            end
        end
    endfunction

    initial begin
        if (NUM_BANKS < 1) begin
            $display("ERROR: NUM_BANKS must be at least 1.");
            $finish;
        end

        if ((NUM_BANKS & (NUM_BANKS - 1)) != 0) begin
            $display("ERROR: NUM_BANKS must be a power of two.");
            $finish;
        end

        if (NUM_BANKS > DEPTH) begin
            $display("ERROR: NUM_BANKS cannot exceed total memory depth.");
            $finish;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            port_a_drive_en  <= 1'b0;
            port_b_drive_en  <= 1'b0;
            port_a_busy      <= 1'b0;
            port_b_busy      <= 1'b0;
            same_bank_hit    <= 1'b0;
            write_collision  <= 1'b0;
            port_a_dout      <= {DATA_WIDTH{1'b0}};
            port_b_dout      <= {DATA_WIDTH{1'b0}};
            bist_active      <= 1'b0;
            test_done        <= 1'b0;
            test_fail        <= 1'b0;
            bist_phase       <= BIST_IDLE;
            bist_addr        <= {ADDR_WIDTH{1'b0}};
        end else begin
            port_a_drive_en <= 1'b0;
            port_b_drive_en <= 1'b0;
            port_a_busy     <= 1'b0;
            port_b_busy     <= 1'b0;
            same_bank_hit   <= 1'b0;
            write_collision <= 1'b0;

            if (bist_active) begin
                port_a_busy <= 1'b1;
                port_b_busy <= 1'b1;

                // March C- sequence:
                // w0, up(r0,w1), up(r1,w0), down(r0,w1), down(r1,w0), r0
                case (bist_phase)
                    BIST_W0: begin
                        mem_array[bist_addr] <= {DATA_WIDTH{1'b0}};
                        if (bist_addr == LAST_ADDR) begin
                            bist_phase <= BIST_UP_R0W1;
                            bist_addr  <= {ADDR_WIDTH{1'b0}};
                        end else begin
                            bist_addr <= bist_addr + 1'b1;
                        end
                    end

                    BIST_UP_R0W1: begin
                        if (mem_array[bist_addr] !== {DATA_WIDTH{1'b0}}) begin
                            test_fail <= 1'b1;
                        end
                        mem_array[bist_addr] <= {DATA_WIDTH{1'b1}};
                        if (bist_addr == LAST_ADDR) begin
                            bist_phase <= BIST_UP_R1W0;
                            bist_addr  <= {ADDR_WIDTH{1'b0}};
                        end else begin
                            bist_addr <= bist_addr + 1'b1;
                        end
                    end

                    BIST_UP_R1W0: begin
                        if (mem_array[bist_addr] !== {DATA_WIDTH{1'b1}}) begin
                            test_fail <= 1'b1;
                        end
                        mem_array[bist_addr] <= {DATA_WIDTH{1'b0}};
                        if (bist_addr == LAST_ADDR) begin
                            bist_phase <= BIST_DOWN_R0W1;
                            bist_addr  <= LAST_ADDR;
                        end else begin
                            bist_addr <= bist_addr + 1'b1;
                        end
                    end

                    BIST_DOWN_R0W1: begin
                        if (mem_array[bist_addr] !== {DATA_WIDTH{1'b0}}) begin
                            test_fail <= 1'b1;
                        end
                        mem_array[bist_addr] <= {DATA_WIDTH{1'b1}};
                        if (bist_addr == {ADDR_WIDTH{1'b0}}) begin
                            bist_phase <= BIST_DOWN_R1W0;
                            bist_addr  <= LAST_ADDR;
                        end else begin
                            bist_addr <= bist_addr - 1'b1;
                        end
                    end

                    BIST_DOWN_R1W0: begin
                        if (mem_array[bist_addr] !== {DATA_WIDTH{1'b1}}) begin
                            test_fail <= 1'b1;
                        end
                        mem_array[bist_addr] <= {DATA_WIDTH{1'b0}};
                        if (bist_addr == {ADDR_WIDTH{1'b0}}) begin
                            bist_phase <= BIST_R0;
                            bist_addr  <= {ADDR_WIDTH{1'b0}};
                        end else begin
                            bist_addr <= bist_addr - 1'b1;
                        end
                    end

                    BIST_R0: begin
                        if (mem_array[bist_addr] !== {DATA_WIDTH{1'b0}}) begin
                            test_fail <= 1'b1;
                        end
                        if (bist_addr == LAST_ADDR) begin
                            bist_active <= 1'b0;
                            test_done   <= 1'b1;
                            bist_phase  <= BIST_IDLE;
                            bist_addr   <= {ADDR_WIDTH{1'b0}};
                        end else begin
                            bist_addr <= bist_addr + 1'b1;
                        end
                    end

                    default: begin
                        bist_phase <= BIST_IDLE;
                        bist_addr  <= {ADDR_WIDTH{1'b0}};
                    end
                endcase
            end else if (bist_start) begin
                bist_active <= 1'b1;
                test_done   <= 1'b0;
                test_fail   <= 1'b0;
                bist_phase  <= BIST_W0;
                bist_addr   <= {ADDR_WIDTH{1'b0}};
            end else begin
                if (port_a_en && port_b_en && (bank_sel(port_a_addr) == bank_sel(port_b_addr))) begin
                    same_bank_hit <= 1'b1;
                end

                if (port_a_en && port_b_en && port_a_we && port_b_we &&
                    (port_a_addr == port_b_addr)) begin
                    mem_array[port_a_addr] <= port_a_din;
                    port_b_busy            <= 1'b1;
                    write_collision        <= 1'b1;
                end else begin
                    if (port_a_en && port_a_we) begin
                        mem_array[port_a_addr] <= port_a_din;
                    end

                    if (port_b_en && port_b_we) begin
                        mem_array[port_b_addr] <= port_b_din;
                    end
                end

                if (port_a_en && !port_a_we) begin
                    port_a_drive_en <= 1'b1;
                    if (port_b_en && port_b_we && (port_b_addr == port_a_addr)) begin
                        port_a_dout <= port_b_din;
                    end else begin
                        port_a_dout <= mem_array[port_a_addr];
                    end
                end

                if (port_b_en && !port_b_we) begin
                    port_b_drive_en <= 1'b1;
                    if (port_a_en && port_a_we && (port_a_addr == port_b_addr)) begin
                        port_b_dout <= port_a_din;
                    end else begin
                        port_b_dout <= mem_array[port_b_addr];
                    end
                end
            end
        end
    end

endmodule
