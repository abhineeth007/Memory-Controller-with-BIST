`timescale 1ns / 1ps

module tb_dual_port_mem_controller;

    localparam integer DATA_WIDTH = 32;
    localparam integer ADDR_WIDTH = 4;
    localparam integer NUM_BANKS  = 4;

    localparam [2:0] BIST_IDLE       = 3'd0;
    localparam [2:0] BIST_W0         = 3'd1;
    localparam [2:0] BIST_UP_R0W1    = 3'd2;

    reg                   clk;
    reg                   rst_n;
    reg                   port_a_en;
    reg                   port_a_we;
    reg  [ADDR_WIDTH-1:0] port_a_addr;
    tri  [DATA_WIDTH-1:0] port_a_data;
    reg                   port_a_host_drive_en;
    reg  [DATA_WIDTH-1:0] port_a_host_data;
    wire                  port_a_drive_en;
    wire                  port_a_busy;
    reg                   port_b_en;
    reg                   port_b_we;
    reg  [ADDR_WIDTH-1:0] port_b_addr;
    tri  [DATA_WIDTH-1:0] port_b_data;
    reg                   port_b_host_drive_en;
    reg  [DATA_WIDTH-1:0] port_b_host_data;
    wire                  port_b_drive_en;
    wire                  port_b_busy;
    wire                  same_bank_hit;
    wire                  write_collision;
    reg                   bist_start;
    wire                  bist_active;
    wire                  test_done;
    wire                  test_fail;
    wire [2:0]            bist_phase;
    wire [ADDR_WIDTH-1:0] bist_addr;

    integer failures;
    integer cycles_waited;

    assign port_a_data = port_a_host_drive_en ? port_a_host_data : {DATA_WIDTH{1'bz}};
    assign port_b_data = port_b_host_drive_en ? port_b_host_data : {DATA_WIDTH{1'bz}};

    dual_port_mem_controller #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .NUM_BANKS(NUM_BANKS)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .port_a_en(port_a_en),
        .port_a_we(port_a_we),
        .port_a_addr(port_a_addr),
        .port_a_data(port_a_data),
        .port_a_drive_en(port_a_drive_en),
        .port_a_busy(port_a_busy),
        .port_b_en(port_b_en),
        .port_b_we(port_b_we),
        .port_b_addr(port_b_addr),
        .port_b_data(port_b_data),
        .port_b_drive_en(port_b_drive_en),
        .port_b_busy(port_b_busy),
        .same_bank_hit(same_bank_hit),
        .write_collision(write_collision),
        .bist_start(bist_start),
        .bist_active(bist_active),
        .test_done(test_done),
        .test_fail(test_fail),
        .bist_phase(bist_phase),
        .bist_addr(bist_addr)
    );

    always #5 clk = ~clk;

    task expect_true;
        input             actual;
        input [8*64-1:0]  label;
        begin
            if (actual !== 1'b1) begin
                failures = failures + 1;
                $display("FAIL: %0s", label);
                $display("  expected 1, got %b", actual);
            end else begin
                $display("PASS: %0s", label);
            end
        end
    endtask

    task expect_false;
        input             actual;
        input [8*64-1:0]  label;
        begin
            if (actual !== 1'b0) begin
                failures = failures + 1;
                $display("FAIL: %0s", label);
                $display("  expected 0, got %b", actual);
            end else begin
                $display("PASS: %0s", label);
            end
        end
    endtask

    task expect_word;
        input [DATA_WIDTH-1:0] actual;
        input [DATA_WIDTH-1:0] expected;
        input [8*64-1:0]       label;
        begin
            if (actual !== expected) begin
                failures = failures + 1;
                $display("FAIL: %0s", label);
                $display("  expected %h, got %h", expected, actual);
            end else begin
                $display("PASS: %0s", label);
            end
        end
    endtask

    task expect_bus_z;
        input [DATA_WIDTH-1:0] actual;
        input [8*64-1:0]       label;
        begin
            if (actual !== {DATA_WIDTH{1'bz}}) begin
                failures = failures + 1;
                $display("FAIL: %0s", label);
                $display("  expected Z, got %h", actual);
            end else begin
                $display("PASS: %0s", label);
            end
        end
    endtask

    task set_all_idle;
        begin
            port_a_en            = 1'b0;
            port_a_we            = 1'b0;
            port_a_addr          = {ADDR_WIDTH{1'b0}};
            port_a_host_drive_en = 1'b0;
            port_a_host_data     = {DATA_WIDTH{1'b0}};
            port_b_en            = 1'b0;
            port_b_we            = 1'b0;
            port_b_addr          = {ADDR_WIDTH{1'b0}};
            port_b_host_drive_en = 1'b0;
            port_b_host_data     = {DATA_WIDTH{1'b0}};
            bist_start           = 1'b0;
        end
    endtask

    task port_a_write;
        input [ADDR_WIDTH-1:0] addr;
        input [DATA_WIDTH-1:0] data;
        begin
            @(negedge clk);
            port_a_en            = 1'b1;
            port_a_we            = 1'b1;
            port_a_addr          = addr;
            port_a_host_drive_en = 1'b1;
            port_a_host_data     = data;
            @(posedge clk);
            #1;
            expect_false(port_a_drive_en, "port A stays off the bus during write");
            @(negedge clk);
            port_a_en            = 1'b0;
            port_a_we            = 1'b0;
            port_a_addr          = {ADDR_WIDTH{1'b0}};
            port_a_host_drive_en = 1'b0;
            port_a_host_data     = {DATA_WIDTH{1'b0}};
        end
    endtask

    task port_b_write;
        input [ADDR_WIDTH-1:0] addr;
        input [DATA_WIDTH-1:0] data;
        begin
            @(negedge clk);
            port_b_en            = 1'b1;
            port_b_we            = 1'b1;
            port_b_addr          = addr;
            port_b_host_drive_en = 1'b1;
            port_b_host_data     = data;
            @(posedge clk);
            #1;
            expect_false(port_b_drive_en, "port B stays off the bus during write");
            @(negedge clk);
            port_b_en            = 1'b0;
            port_b_we            = 1'b0;
            port_b_addr          = {ADDR_WIDTH{1'b0}};
            port_b_host_drive_en = 1'b0;
            port_b_host_data     = {DATA_WIDTH{1'b0}};
        end
    endtask

    task port_a_read_and_check;
        input [ADDR_WIDTH-1:0] addr;
        input [DATA_WIDTH-1:0] expected;
        input [8*64-1:0]       label;
        begin
            @(negedge clk);
            port_a_en            = 1'b1;
            port_a_we            = 1'b0;
            port_a_addr          = addr;
            port_a_host_drive_en = 1'b0;
            @(posedge clk);
            #1;
            expect_true(port_a_drive_en, "port A drives the bus during read");
            expect_word(port_a_data, expected, label);
            @(negedge clk);
            port_a_en   = 1'b0;
            port_a_addr = {ADDR_WIDTH{1'b0}};
            @(posedge clk);
            #1;
            expect_bus_z(port_a_data, "port A returns to high-Z after read");
        end
    endtask

    task port_b_read_and_check;
        input [ADDR_WIDTH-1:0] addr;
        input [DATA_WIDTH-1:0] expected;
        input [8*64-1:0]       label;
        begin
            @(negedge clk);
            port_b_en            = 1'b1;
            port_b_we            = 1'b0;
            port_b_addr          = addr;
            port_b_host_drive_en = 1'b0;
            @(posedge clk);
            #1;
            expect_true(port_b_drive_en, "port B drives the bus during read");
            expect_word(port_b_data, expected, label);
            @(negedge clk);
            port_b_en   = 1'b0;
            port_b_addr = {ADDR_WIDTH{1'b0}};
            @(posedge clk);
            #1;
            expect_bus_z(port_b_data, "port B returns to high-Z after read");
        end
    endtask

    task start_bist_sequence;
        begin
            @(negedge clk);
            bist_start = 1'b1;
            @(posedge clk);
            #1;
            expect_true(bist_active, "BIST enters active state");
            expect_false(test_done, "BIST clears the done flag at launch");
            @(negedge clk);
            bist_start = 1'b0;
        end
    endtask

    task wait_for_bist_done;
        begin
            cycles_waited = 0;
            while ((test_done !== 1'b1) && (cycles_waited < 128)) begin
                @(posedge clk);
                #1;
                cycles_waited = cycles_waited + 1;
                if (bist_active === 1'b1) begin
                    if ((port_a_busy !== 1'b1) || (port_b_busy !== 1'b1)) begin
                        failures = failures + 1;
                        $display("FAIL: ports must stay busy while BIST owns the array");
                        $display("  port_a_busy=%b port_b_busy=%b", port_a_busy, port_b_busy);
                    end
                end
            end

            if (test_done !== 1'b1) begin
                failures = failures + 1;
                $display("FAIL: BIST timed out after %0d cycles", cycles_waited);
            end else begin
                $display("PASS: BIST completed in %0d cycles", cycles_waited);
            end
        end
    endtask

    initial begin
        clk      = 1'b0;
        rst_n    = 1'b0;
        failures = 0;
        set_all_idle;

        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        #1;

        expect_bus_z(port_a_data, "port A bus is high-Z in idle");
        expect_bus_z(port_b_data, "port B bus is high-Z in idle");

        port_a_write(4'h1, 32'h1111_AAAA);
        port_a_read_and_check(4'h1, 32'h1111_AAAA, "port A basic write/readback");

        @(negedge clk);
        port_a_en            = 1'b1;
        port_a_we            = 1'b1;
        port_a_addr          = 4'h0;
        port_a_host_drive_en = 1'b1;
        port_a_host_data     = 32'hAAAA_0001;
        port_b_en            = 1'b1;
        port_b_we            = 1'b1;
        port_b_addr          = 4'h1;
        port_b_host_drive_en = 1'b1;
        port_b_host_data     = 32'hBBBB_0002;
        @(posedge clk);
        #1;
        expect_false(write_collision, "different-bank writes do not collide");
        expect_false(same_bank_hit, "different-bank writes do not overlap banks");
        @(negedge clk);
        set_all_idle;

        port_a_read_and_check(4'h0, 32'hAAAA_0001, "port A reads different-bank write");
        port_b_read_and_check(4'h1, 32'hBBBB_0002, "port B reads different-bank write");

        @(negedge clk);
        port_a_en            = 1'b1;
        port_a_we            = 1'b1;
        port_a_addr          = 4'h0;
        port_a_host_drive_en = 1'b1;
        port_a_host_data     = 32'h1234_0000;
        port_b_en            = 1'b1;
        port_b_we            = 1'b1;
        port_b_addr          = 4'h4;
        port_b_host_drive_en = 1'b1;
        port_b_host_data     = 32'h5678_0004;
        @(posedge clk);
        #1;
        expect_true(same_bank_hit, "same-bank accesses are detected");
        expect_false(write_collision, "same-bank different-address writes stay legal");
        expect_false(port_b_busy, "port B is not stalled for same-bank different-address write");
        @(negedge clk);
        set_all_idle;

        port_a_read_and_check(4'h0, 32'h1234_0000, "port A reads same-bank different-address write");
        port_b_read_and_check(4'h4, 32'h5678_0004, "port B reads same-bank different-address write");

        @(negedge clk);
        port_a_en            = 1'b1;
        port_a_we            = 1'b1;
        port_a_addr          = 4'h6;
        port_a_host_drive_en = 1'b1;
        port_a_host_data     = 32'hAAAA_F0F0;
        port_b_en            = 1'b1;
        port_b_we            = 1'b1;
        port_b_addr          = 4'h6;
        port_b_host_drive_en = 1'b1;
        port_b_host_data     = 32'hBBBB_0F0F;
        @(posedge clk);
        #1;
        expect_true(write_collision, "same-address dual write raises collision flag");
        expect_true(port_b_busy, "port B is stalled by lower-priority write collision");
        expect_true(same_bank_hit, "same-address dual write is also a same-bank hit");
        @(negedge clk);
        set_all_idle;

        port_a_read_and_check(4'h6, 32'hAAAA_F0F0, "port A write wins same-address collision");

        @(negedge clk);
        port_a_en            = 1'b1;
        port_a_we            = 1'b1;
        port_a_addr          = 4'h3;
        port_a_host_drive_en = 1'b1;
        port_a_host_data     = 32'hDEAD_BEEF;
        port_b_en            = 1'b1;
        port_b_we            = 1'b0;
        port_b_addr          = 4'h3;
        port_b_host_drive_en = 1'b0;
        @(posedge clk);
        #1;
        expect_true(port_b_drive_en, "port B can read while port A writes");
        expect_word(port_b_data, 32'hDEAD_BEEF, "port B sees forwarded data from port A write");
        expect_false(write_collision, "write-plus-read does not raise write collision");
        @(negedge clk);
        set_all_idle;
        @(posedge clk);
        #1;
        expect_bus_z(port_b_data, "port B bus releases after forwarded read");

        @(negedge clk);
        port_a_en            = 1'b1;
        port_a_we            = 1'b0;
        port_a_addr          = 4'h9;
        port_a_host_drive_en = 1'b0;
        port_b_en            = 1'b1;
        port_b_we            = 1'b1;
        port_b_addr          = 4'h9;
        port_b_host_drive_en = 1'b1;
        port_b_host_data     = 32'hCAFE_FEED;
        @(posedge clk);
        #1;
        expect_true(port_a_drive_en, "port A can read while port B writes");
        expect_word(port_a_data, 32'hCAFE_FEED, "port A sees forwarded data from port B write");
        @(negedge clk);
        set_all_idle;
        @(posedge clk);
        #1;
        expect_bus_z(port_a_data, "port A bus releases after forwarded read");

        port_a_write(4'h2, 32'h1357_2468);
        port_b_write(4'h5, 32'hAAAA_5555);
        start_bist_sequence;
        wait_for_bist_done;
        expect_false(test_fail, "BIST passes on a healthy memory image");
        port_a_read_and_check(4'h2, 32'h0000_0000, "BIST restores memory word 2 to zero");
        port_b_read_and_check(4'h5, 32'h0000_0000, "BIST restores memory word 5 to zero");

        start_bist_sequence;
        while (!((bist_active === 1'b1) &&
                 (bist_phase == BIST_UP_R0W1) &&
                 (bist_addr == 4'h4))) begin
            @(negedge clk);
        end
        dut.mem_array[4'h4] = {DATA_WIDTH{1'b1}};
        wait_for_bist_done;
        expect_true(test_fail, "BIST flags injected memory corruption");

        if (failures == 0) begin
            $display("All dual-port memory controller tests passed.");
        end else begin
            $display("Dual-port memory controller tests failed: %0d case(s).", failures);
        end

        $finish;
    end

endmodule
