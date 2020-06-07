`default_nettype none
module video (
  input         clk,
  input         reset,
  output [3:0]  vga_r,
  output [3:0]  vga_b,
  output [3:0]  vga_g,
  output        vga_hs,
  output        vga_vs,
  output        vga_de,
  input  [7:0]  vga_din,
  output [7:0]  vga_dout,
  input [13:0]  vga_addr,
  input         vga_wr,
  input         vga_rd,
  input  [1:0]  mode,
  input         cpu_clk,
  input [13:0]  font_addr,
  input [13:0]  name_table_addr,
  output        n_int,
  input         video_on,
  output reg [7:0]  diag
);

  parameter HA = 640;
  parameter HS  = 96;
  parameter HFP = 16;
  parameter HBP = 48;
  parameter HT  = HA + HS + HFP + HBP;
  parameter HB = 80;
  parameter HB2 = HB/2;
  parameter HBadj = 12;

  parameter VA = 480;
  parameter VS  = 2;
  parameter VFP = 11;
  parameter VBP = 31;
  parameter VT  = VA + VS + VFP + VBP;
  parameter VB = 48;
  parameter VB2 = VB/2;

  reg [9:0] hc = 0;
  reg [9:0] vc = 0;

  reg INT = 0;
  reg[5:0] intCnt = 1;

  assign n_int = !INT;

  always @(posedge clk) begin
    if (hc == HT - 1) begin
      hc <= 0;
      if (vc == VT - 1) vc <= 0;
      else vc <= vc + 1;
    end else hc <= hc + 1;
    if (hc == HA + HFP && vc == VA + VFP) INT <= 1;
    if (INT) intCnt <= intCnt + 1;
    if (!intCnt) INT <= 0;
  end

  assign vga_hs = !(hc >= HA + HFP && hc < HA + HFP + HS);
  assign vga_vs = !(vc >= VA + VFP && vc < VA + VFP + VS);
  assign vga_de = !(hc > HA || vc > VA);

  wire [7:0] x = hc[9:1] - HB2;
  wire [7:0] y = vc[9:1] - VB2;

  reg [5:0] x_char;
  reg [2:0] x_pix;

  wire hBorder = (hc < (HB + HBadj) || hc >= HA - HB);
  wire vBorder = (vc < VB || vc >= VA - VB);
  wire border = hBorder || vBorder;

  reg [13:0] vid_addr;
  wire [7:0] vid_out; 

  vram video_ram (
    .clk_a(cpu_clk),
    .addr_a(vga_addr),
    .we_a(vga_wr),
    .re_a(vga_rd),
    .din_a(vga_din),
    .dout_a(vga_dout),
    .clk_b(clk),
    .addr_b(vid_addr),
    .dout_b(vid_out)
  );

  reg [7:0] r_char;
  reg [7:0] font_line;

  always @(posedge clk) if (video_on) begin
    if (mode == 0) begin
      if (hc[0] == 1) begin
        x_pix <= x_pix + 1;
        if (x_pix == 5) begin
          x_pix <= 0;
	  x_char <= x_char + 1;
        end
        if (x_pix == 3) begin
          // Set address for next character
          vid_addr <= name_table_addr + (y[7:3] * 40 + x_char + 1);
        end else if (x_pix == 4) begin
          // Set address for font line
          vid_addr <= font_addr + {vid_out, y[2:0]};
        end else if (x_pix == 5) begin
          // Store the font line ready for next character
          font_line <= vid_out;
        end
      end

      // Get ready for start of line
      if (hc == HB - 13) begin
        x_pix <= 0;
        x_char <= 63;
      end
    end else if (mode == 1) begin
      if (hc[0] == 1) begin
        x_pix <= x_pix + 1;
        if (x_pix == 7) begin
          x_pix <= 0;
	  x_char <= x_char + 1;
        end
        if (x_pix == 3) begin
          // Set address for next character
          vid_addr <= name_table_addr + (y[7:3] * 32 + x_char + 1);
        end else if (x_pix == 4) begin
          // Set address for font line
          vid_addr <= font_addr + {vid_out, y[2:0]};
        end else if (x_pix == 5) begin
          // Store the font line ready for next character
          font_line <= vid_out;
        end
      end

      // Get ready for start of line
      if (hc == HB - 17) begin
        x_pix <= 0;
        x_char <= 63;
      end
    end
  end
 
  wire pixel = font_line[7 - x_pix];
  wire pix = ~border & pixel;

  wire [3:0] red = {4{pix}};
  wire [3:0] green = {4{pix}};
  wire [3:0] blue = {4{pix}};

  assign vga_r = !vga_de ? 4'b0 : red;
  assign vga_g = !vga_de ? 4'b0 : green;
  assign vga_b = !vga_de ? 4'b0 : blue;

endmodule
