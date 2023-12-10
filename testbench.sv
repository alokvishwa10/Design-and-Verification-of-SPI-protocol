interface spi_if;
  logic clk;
  logic rst;
  logic newdata;
  logic [11:0] din;
  logic sclk;
  logic cs;
  logic mosi;
  
endinterface



//testbench 
module tb;
  
  spi_if sif();
  spi dut(sif.clk,sif.rst,sif.newdata,sif.din,sif.sclk,sif.cs,sif.mosi);
  environment env;
  initial sif.clk<=0;
  always #5 sif.clk<=~sif.clk;
  
  initial begin
    env=new(sif);
    env.run;
  end
  
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(1);
  end
endmodule


//transaction
class transaction;
  rand bit newdata;
  rand bit[11:0] din;
  bit cs;
  bit mosi;
  
  constraint c1 {newdata dist {0:=30, 1:=70};
                din>1 && din<100;}
  
  function void display(string tag);
    $display("[%s] : newdata=%0b, cs=%0b, din=%0d, mosi=%0b",tag,newdata,cs,din,mosi);
  endfunction
  
  function transaction copy();
    copy =new;
    copy.newdata = this.newdata;
    copy.cs = this.cs;
    copy.din = this.din;
    copy.mosi = this.mosi;
  endfunction
  
endclass


//gen
class generator;
  transaction t;
  mailbox #(transaction) mbxgd;
  event dnext,snext,done;
  int num;
  
  function new(mailbox #(transaction) mbxgd,int num);
    this.mbxgd=mbxgd;
    this.num=num;
    t=new;
  endfunction
  
  task run;
    repeat(num)begin
      assert(t.randomize) else $error("Randomization Failed");
      t.display("GEN"); 
      mbxgd.put(t.copy);
      
      @(dnext);
      @(snext);
    end
    ->done;
  endtask
endclass


//drv
class driver;
  virtual spi_if sif;
  transaction t;
  mailbox #(transaction) mbxgd;
  mailbox #(bit[11:0]) mbxds;
  
  event dnext;
  
  
  function new(mailbox #(transaction) mbxgd,mailbox #(bit[11:0]) mbxds);
    this.mbxgd=mbxgd;
    this.mbxds=mbxds;
  endfunction
  
  task reset;
    sif.rst<=1'b1;
    sif.cs<=1'b1;
    sif.newdata<=1'b0;
    sif.din<=0;
    sif.mosi<=1'b0;
    repeat(5) @(posedge sif.clk);
    sif.rst<=1'b0;
    repeat(2) @(posedge sif.clk);
    $display("Reset done");
  endtask
  
  task run;
    forever begin
      mbxgd.get(t);
      t.display("DRV");
      @(posedge sif.sclk);
      sif.newdata<=1'b1;
      sif.din<=t.din;
      mbxds.put(t.din);
      @(posedge sif.sclk);
      sif.newdata<=0;
      wait(sif.cs==1'b1);
      $display("Data sent to DAC: %0d", t.din);
      ->dnext;
    end
  endtask
  
endclass

//mon
class monitor;
  mailbox #(bit[11:0]) mbxms;
  virtual spi_if sif;
  bit[11:0] srx;
  
  function new(mailbox #(bit[11:0]) mbxms);
    this.mbxms=mbxms;
  endfunction
  
  task run;
    forever begin
      @(posedge sif.sclk);
      wait(sif.cs==1'b0);
      @(posedge sif.sclk);
      for(int i=0;i<=11;i++)begin
        @(posedge sif.sclk);
        srx[i]=sif.mosi;
        
      end
      
      wait(sif.cs==1'b1);
      $display("[MON] : Data = %0d",srx);
      
      mbxms.put(srx);
      
    end
  endtask
endclass


//sco
class scoreboard;
  mailbox #(bit[11:0]) mbxds,mbxms;
  bit[11:0] ds,ms;
  event snext;
  
  function new(mailbox #(bit[11:0]) mbxds, mailbox #(bit[11:0]) mbxms);
    this.mbxds=mbxds;
    this.mbxms=mbxms;
  endfunction
  
  task run;
    forever begin
      mbxds.get(ds);
      mbxms.get(ms);
      $display("[SCO] : Drv data: %0d, Mon data: %0d", ds,ms);
      if(ds==ms) 
        $display("Matched");
      else 
        $display("Mismatched data");
      ->snext;
    end
  endtask
endclass



//Environment 
`include "transaction.sv"
`include "generator.sv"
`include "driver.sv"
`include "monitor.sv"
`include "scoreboard.sv"

class environment;
  generator g;
  driver d;
  monitor m;
  scoreboard s;
  
  event done;
  event nextgs;
  event nextgd;
  
  
  virtual spi_if sif;
  
  mailbox #(transaction) mbxgd;
  mailbox #(bit[11:0]) mbxds;
  mailbox #(bit[11:0]) mbxms;
  
  
  function new(virtual spi_if sif);
    mbxgd=new;
    mbxds=new;
    mbxms=new;
    
    g=new(mbxgd,20);
    d=new(mbxgd,mbxds);
    m=new(mbxms);
    s=new(mbxds,mbxms);
    
    this.sif=sif;
    d.sif=this.sif;
    m.sif=this.sif;
    
    g.dnext=nextgd;
    g.snext=nextgs;
    d.dnext=nextgd;
    s.snext=nextgs;
 
  endfunction
  
  task pre_test;
    d.reset;
  endtask
  
  task test;
    fork
      g.run;
      d.run;
      m.run;
      s.run;
    join_any
  endtask
  
  task post_test;
    wait(g.done.triggered);
    $finish;
  endtask
  
  task run;
    pre_test;
    test;
    post_test;
  endtask
  
endclass
