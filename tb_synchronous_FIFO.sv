module tb_synchronous_FIFO();
    localparam DEPTH = 8;
    localparam DW = 32;
    localparam AW = $clog2(DEPTH)-1;
    
    //clock, rst, DUT
    logic clk = 0;
    logic rst_n = 0;
    logic wr_en, rd_en = 0;
    logic [DW-1:0] d_in = '0;
    logic [DW-1:0] d_out; //outputs arent initialized
    logic fifo_full, fifo_empty;
    
    synchronous_FIFO #(.FIFO_DEPTH(DEPTH), 
                       .DATA_WIDTH(DW)) 
                       dut (.*);
                       
    always #5 clk = ~clk;
    //Driver tasks
    task automatic cycle (input bit w, input bit r);
        @(negedge clk);
        wr_en = w;
        rd_en = r;
        d_in = $urandom; //unsigned random 32 bit int 
    endtask
    
    task automatic idle(input int n); //NOP
        repeat (n) cycle (0, 0);
    endtask
    
    task automatic reset_dut(); //reset, let things settle, then set high again
        @(negedge clk);
        rst_n = 0; wr_en = 0; rd_en = 0;
        repeat (2) @(negedge clk);
        rst_n = 1;
    endtask
    //reference model using the SystemVerilog Queue ($)
    logic [DW-1:0] golden_model [$];
    logic [DW-1:0] exp_data;
    bit check_pending;
    int errors, n_writes, n_reads;
    
    always_ff @ (posedge clk) begin
        if (!rst_n) begin
            golden_model.delete();
            check_pending = 0; 
        end else begin
            bit wr_ok, rd_ok;
            
            // (a) check data from the read accepted last cycle
            if (check_pending) begin
              if (d_out !== exp_data) begin
                errors++;
                $error("[%0t] DATA: got %h, expected %h", $time, d_out, exp_data);
              end
            end
            check_pending = 0;
            
            //check that the fifo empty flag is properly raised
            if (fifo_empty !== (golden_model.size() == 0)) begin
                errors++;
                $error("[%0t] EMPTY flag=%b, but model holds %0d ", $time, fifo_empty, model.size());
            end
            //check that the fifo full flag is properly 
            if (fifo_full !== (golden_model.size() == DEPTH)) begin
                errors++;
                $error("[%0t] FULL flag=%b, but model holds %0d ", $time, fifo_full, golden_model.size());
            end
            // (c) coverage sample of the state this edge sees for later bins
            cg.sample(model.size(), wr_en, rd_en);
            if (rd_ok) begin
              exp_data      = model.pop_front();
              check_pending = 1;
              n_reads++;
            end 
            if (wr_ok) begin
              model.push_back(d_in);
              n_writes++;
            end 
        end
    end
    //Assertions
    //flags should be known after each reset (never X)
    a_flags_known : assert property (@(posedge clk) disable iff (!rst_n)
        !$isunknown({fifo_full, fifo_empty}));
    //fifo_full and fifo_empty mutually exclusive
    a_flags_exclusive: assert property (@(posedge clk) disable iff (!rst_n)
        !(fifo_full && fifo_empty));
    //if a write while full happens, discard (overflow)
    a_overflow : assert property ()
    
    //if a read while empty happens, discard (underflow)
    a_underflow : assert property ()
    
    //if a read is accepted, data should be seen next cycle
    a_d_valid : assert property ()
    

    //Coverage
    //check wr ptr wrapping happens correctly
    c_wr_ptr_wrap : cover property ()
    
    //check rd ptr wrapping happens correctly
    c_rd_ptr_wrap : cover property ()
    
    
endmodule
