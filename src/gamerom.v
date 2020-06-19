module gamerom (
  input            clk,
  input [13:0]     addr,
  input            we,
  input [7:0]      din,
  output reg [7:0] dout,
);

  parameter MEM_INIT_FILE = "";
   
  reg [7:0] rom [0:16383];

  initial
    if (MEM_INIT_FILE != "")
      $readmemh(MEM_INIT_FILE, rom);
   
  always @(posedge clk) begin
    if (we)
      rom[addr] <= din;
    dout <= rom[addr];
  end

endmodule
