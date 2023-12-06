module spi(input clk,rst,newdata,
           input [11:0] din,
          output reg sclk,cs,mosi);
  
//   parameter idle=1'b0;
//   parameter send=1'b1;
  
  typedef enum bit[1:0] {idle=2'b00, send=2'b10} state_type;
  state_type state;
  
  int count;
  int countc;
  
  //sclk generation where clk=100MHz and sclk=1MHz
  always@(posedge clk)begin
    if(rst==1'b1)begin
      countc<=0;
      sclk<=1'b0;
    end
    else begin
      if(countc<50) countc<=countc+1;
      else begin
        countc<=0;
        sclk <= ~sclk;
      end
    end
  end
  
  //operation
//   reg state;
  reg[11:0] temp;
  always@(posedge sclk)begin
    if(rst==1'b1)begin
      cs<=1'b1;
      mosi<=1'b0;
      state<=idle;
    end
    else begin
      case(state)
        idle:begin
          if(newdata==1'b1)begin
            state<=send;
            temp<=din;
            cs<=1'b0;
          end
          else begin
            state<=idle;
            temp<=8'h00;
          end
        end
        send:begin
          if(count<=11)begin
            mosi<=temp[count];
            count<=count+1;
          end
          else begin
            count <=0;
            state<=idle;
            cs<=1'b1;
            mosi<=1'b0;
          end
        end
        default: state<=idle;
      endcase
    end
  end
  
endmodule
