`timescale 1ns / 1ps

module synchronous_FIFO #(
    parameter FIFO_DEPTH = 8,
    parameter DATA_WIDTH = 32
    )(
    input logic clk,
    input logic rst_n,
    //enables
    input logic rd_en, wr_en,
    //data
    input  logic [DATA_WIDTH-1:0] d_in,
    output logic [DATA_WIDTH-1:0] d_out,
    //flags
    output logic fifo_full,
    output logic fifo_empty
    );
    
    //pointers
    logic [$clog2(FIFO_DEPTH):0] rd_ptr;
    logic [$clog2(FIFO_DEPTH):0] wr_ptr;
    //memory
    logic [DATA_WIDTH-1:0] memory [0:FIFO_DEPTH-1];
    //localparam
    localparam int addressable = $clog2(FIFO_DEPTH)-1;
    
    //write
    always_ff @ (posedge clk) begin
        if (!rst_n) begin
            wr_ptr <= '0;
        end else begin
            if (wr_en && !fifo_full) begin
                memory[wr_ptr[addressable:0]] <= d_in;
                wr_ptr         <= wr_ptr + 1;
            end
        end
    end
    
    //read
    always_ff @ (posedge clk) begin
        if (!rst_n) begin
            rd_ptr <= '0;
            d_out <= '0;
        end else begin
            if (rd_en && !fifo_empty) begin
                d_out <= memory[rd_ptr[addressable:0]];
                rd_ptr <= rd_ptr + 1;
            end
        end
    end
    
    always_comb begin
        fifo_full = (rd_ptr[$clog2(FIFO_DEPTH)] != wr_ptr[$clog2(FIFO_DEPTH)]) 
                    && (rd_ptr[$clog2(FIFO_DEPTH)-1:0] == wr_ptr[$clog2(FIFO_DEPTH)-1:0]);
        fifo_empty = (rd_ptr == wr_ptr);
    end
endmodule
