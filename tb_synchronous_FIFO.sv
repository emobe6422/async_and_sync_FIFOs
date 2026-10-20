module tb_synchronous_FIFO();
    localparam DEPTH = 8;
    localparam DW = 32;
    localparam AW = $clog2(DEPTH);
    
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
                $error("[%0t] EMPTY flag=%b, but golden model holds %0d ", $time, fifo_empty, golden_model.size());
            end
            //check that the fifo full flag is properly 
            if (fifo_full !== (golden_model.size() == DEPTH)) begin
                errors++;
                $error("[%0t] FULL flag=%b, but golden model holds %0d ", $time, fifo_full, golden_model.size());
            end
            // (c) coverage sample of the state this edge sees for later bins
            cg.sample(golden_model.size(), wr_en, rd_en);
            
            rd_ok = rd_en && (golden_model.size() > 0);
            wr_ok = wr_en && (golden_model.size() < DEPTH);
            
            if (rd_ok) begin
              exp_data      = golden_model.pop_front();
              check_pending = 1;
              n_reads++;
            end 
            if (wr_ok) begin
              golden_model.push_back(d_in);
              n_writes++;
            end 
        end
    end
    //Assertions
    //flags should be known after each reset (never X)
    a_flags_known : assert property (@(posedge clk) disable  iff (!rst_n)
        !$isunknown({fifo_full, fifo_empty}));
    //fifo_full and fifo_empty mutually exclusive
    a_flags_exclusive: assert property (@(posedge clk) disable iff (!rst_n)
        !(fifo_full && fifo_empty));
    //if a write while full happens, discard (overflow)
    a_overflow : assert property (@(posedge clk) disable iff (!rst_n)
       fifo_full |=> $stable(dut.wr_ptr));
       //check if when fifo full triggered, on the next cycle if wr_ptr remains the same 
    
    //if a read while empty happens, discard (underflow)
    a_underflow : assert property (@(posedge clk) disable iff (!rst_n)
        fifo_empty |=> $stable(dut.rd_ptr));
    
    //if a read is accepted, known data should be seen next cycle
    a_d_valid : assert property (@(posedge clk) disable iff (!rst_n)
        (rd_en && !fifo_empty) |=> !$isunknown(d_out));
    

    //Coverage
    //check wr ptr wrapping happens correctly
    //tests to make sure it happens at some point
    c_wr_ptr_wrap : cover property (@(posedge clk) disable iff (!rst_n)
        $changed(dut.wr_ptr[AW]));
    
    //check rd ptr wrapping happens correctly
    c_rd_ptr_wrap : cover property (@(posedge clk) disable iff (!rst_n)
        $changed(dut.rd_ptr[AW]));
    
    //Functional Coverage with covergroups. _t for type
    covergroup cg_t with function sample(input int occ, input bit w, input bit r);
        cp_occ : coverpoint occ {
            //Ask yourself what states we want to ensure we hit
            bins empty       = {0};
            bins one         = {1};
            bins mid         = {[2:DEPTH-2]};
            bins almost_full = {DEPTH-1};
            bins full        = {DEPTH};
        }
        cp_op : coverpoint {w, r} {
            bins idle = {2'b00};
            bins rd   = {2'b01};
            bins wr   = {2'b10};
            bins both = {2'b11};
        }
        x_occ_op: cross cp_occ, cp_op;
    endgroup
    
    //instantiate the covergroup
    cg_t cg = new();
    
    //Testing
    
      // Fill to full, keep writing (overflow attempts), drain, keep reading
  // (underflow attempts).
  task automatic t_fill_drain();
    $display("[%0t] TEST fill_drain", $time);
    reset_dut();
    repeat (DEPTH)     cycle(1, 0);
    repeat (3)         cycle(1, 0);   // writes while full: must be dropped
    repeat (DEPTH)     cycle(0, 1);
    repeat (3)         cycle(0, 1);   // reads while empty: must be ignored
    idle(2);
  endtask
 
  // Simultaneous read+write at a given starting occupancy.
  task automatic t_simul(input int occ);
    $display("[%0t] TEST simul at occupancy %0d", $time, occ);
    reset_dut();
    repeat (occ)       cycle(1, 0);
    repeat (4)         cycle(1, 1);
    repeat (DEPTH + 1) cycle(0, 1);
    idle(2);
  endtask
 
  // Stream enough data to wrap both pointers several times.
  task automatic t_wrap();
    $display("[%0t] TEST wrap", $time);
    reset_dut();
    for (int i = 0; i < 4 * DEPTH; i++) cycle(1, i >= 3);
    repeat (DEPTH + 1) cycle(0, 1);
    idle(2);
  endtask
 
  // Reset in the middle of traffic; stale data must never come out.
  task automatic t_reset_midstream();
    $display("[%0t] TEST reset_midstream", $time);
    reset_dut();
    repeat (DEPTH / 2) cycle(1, 0);
    reset_dut();
    repeat (3)         cycle(0, 1);   // empty after reset: reads ignored
    repeat (DEPTH)     cycle(1, 0);
    repeat (DEPTH)     cycle(0, 1);
    idle(2);
  endtask
 
  // Constrained random with a bias toward writes or reads.
  task automatic t_random(input int n, input int wr_pct, input int rd_pct);
    $display("[%0t] TEST random n=%0d wr=%0d%% rd=%0d%%", $time, n, wr_pct, rd_pct);
    reset_dut();
    repeat (n) cycle($urandom_range(99) < wr_pct, $urandom_range(99) < rd_pct);
    repeat (DEPTH + 1) cycle(0, 1);
    idle(2);
  endtask
 
  initial begin
    t_fill_drain();
    t_simul(0);
    t_simul(1);
    t_simul(DEPTH / 2);
    t_simul(DEPTH - 1);
    t_simul(DEPTH);
    t_wrap();
    t_reset_midstream();
    t_random(2000, 70, 30);   // hovers near full
    t_random(2000, 30, 70);   // hovers near empty
    t_random(2000, 50, 50);   // mid-range churn
 
    $display("--------------------------------------------------");
    $display("writes=%0d reads=%0d errors=%0d coverage=%0.1f%%",
             n_writes, n_reads, errors, cg.get_inst_coverage());
    $display(errors == 0 ? "*** PASS ***" : "*** FAIL ***");
    $finish;
  end
 
  // watchdog
  initial begin
    #1ms;
    $fatal(1, "TIMEOUT");
  end
endmodule
