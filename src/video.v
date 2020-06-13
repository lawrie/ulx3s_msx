`default_nettype none
module video (
  input         clk,
  input         reset,
  output [7:0]  vga_r,
  output [7:0]  vga_b,
  output [7:0]  vga_g,
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
  input [13:0]  sprite_attr_addr,
  input [13:0]  sprite_pattern_table_addr,
  input [13:0]  color_table_addr,
  output        n_int,
  input         video_on,
  input [3:0]   text_color,
  input [3:0]   back_color,
  input         sprite_large,
  input         sprite_enlarged,
  input         vert_retrace_int,
  output        sprite_collision,
  output        too_many_sprites,
  output [4:0]  sprite5,
  output [7:0]  diag
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

  // MSX color pallette
  localparam transparent  = 24'h000000;
  localparam black        = 24'h010101;
  localparam medium_green = 24'h3eb849;
  localparam light_green  = 24'h74d07d;
  localparam dark_blue    = 24'h5955e0;
  localparam light_blue   = 24'h8076f1;
  localparam dark_red     = 24'hb95e51;
  localparam cyan         = 24'h65dbef;
  localparam medium_red   = 24'hdb6559;
  localparam light_red    = 24'hff897d;
  localparam dark_yellow  = 24'hccc35e;
  localparam light_yellow = 24'hded087;
  localparam dark_green   = 24'h3aa241;
  localparam magenta      = 24'hb766b5;
  localparam gray         = 24'hcccccc;
  localparam white        = 24'hffffff;

  wire [23:0] colors [0:15];
  assign colors[0]  = transparent;
  assign colors[1]  = black;
  assign colors[2]  = medium_green;
  assign colors[3]  = light_green;
  assign colors[4]  = dark_blue;
  assign colors[5]  = light_blue;
  assign colors[6]  = dark_red;
  assign colors[7]  = cyan;
  assign colors[8]  = medium_red;
  assign colors[9]  = light_red;
  assign colors[10] = dark_yellow;
  assign colors[11] = light_yellow;
  assign colors[12] = dark_green;
  assign colors[13] = magenta;
  assign colors[14] = gray;
  assign colors[15] = white;

  wire [3:0] border_color = back_color;

  reg [7:0] sprite_y [0:3];
  reg [7:0] sprite_x [0:3];
  reg [3:0] sprite_color [0:3];
  reg [7:0] sprite_pattern [0:3];

  assign diag = sprite_color[1];

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
  
  reg [7:0] sprite_patterns [0:31];
  reg [3:0] sprite_pixel;
  
  wire [7:0] sprite_row [0:3];
  wire [2:0] sprite_col [0:3];

  assign sprite_collision = 0;
  assign too_many_sprites = 0;
  assign sprite5 = 0;

  // Calculate pixel positions for 4 active sprites
  generate
    genvar j;
    for(j=0;j<4;j=j+1) begin
      assign sprite_row[j] = sprite_patterns[(j << 3) + y - sprite_y[j]];
      assign sprite_col[j] = x - sprite_x[j];
    end
  endgenerate

  integer i;

  // Generate VGA signal
  always @(posedge clk) if (video_on) begin
    if (mode == 0) begin
      sprite_pixel <= 0;
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
    end else begin
      if (hc[0] == 1) begin
        x_pix <= x_pix + 1;
        if (x_pix == 7) begin
          x_pix <= 0;
	  x_char <= x_char + 1;
        end
	if (hc < HA) begin 
          if (mode == 1) begin
            if (x_pix == 5) begin
              // Set address for next character
              vid_addr <= name_table_addr + (y[7:3] * 32 + x_char + 1);
            end else if (x_pix == 6) begin
              // Set address for font line
              vid_addr <= font_addr + {vid_out, y[2:0]};
            end else if (x_pix == 7) begin
              // Store the font line ready for next character
              font_line <= vid_out;
	    end
          end else if (mode == 2) begin
            if (x_pix == 5) begin
              // Set address for next character
              vid_addr <= name_table_addr + (y[7:3] * 32 + x_char + 1);
            end else if (x_pix == 6) begin
              // Set address for font line
              vid_addr <= (y[7:6] * 14'h800) + {vid_out, y[2:0]};
            end else if (x_pix == 7) begin
              // Store the font line ready for next character
              font_line <= vid_out;
	    end
	  end
        end else begin // Read sprite attributes and patterns
	  if (hc < HA + 32) vid_addr <= sprite_attr_addr + hc[4:1];
	  if (hc >= HA + 2 && hc < HA + 34) begin
	    case ((hc[3:1] - 1) & 2'b11)
              0: sprite_y[(hc[5:1]-1) >> 2] <= vid_out;
	      1: sprite_x[(hc[5:1]-1) >> 2] <= vid_out;
	      2: sprite_pattern[(hc[5:1]-1) >> 2] <= vid_out;
	      3: sprite_color[(hc[5:1]-1) >> 2] <= vid_out[3:0];
	    endcase
	  end
          if (hc >= HA + 32 && hc < HA + 96)
            vid_addr <= sprite_pattern_table_addr + (sprite_pattern[hc[5:4]] << 3) + hc[3:1];
	  if (hc >= HA + 34 && hc < HA + 98) sprite_patterns[hc[6:1] - 1] <= vid_out;
	end
      end

      // Get ready for start of line
      if (hc == HB - 17) begin
        x_pix <= 0;
        x_char <= 63;
      end

      // Look for up to 4 sprites on the current line
      sprite_pixel <= 0;
      for (i=0; i<4; i=i+1) begin
        if (sprite_y[i] < 192 && y >= sprite_y[i] && y < sprite_y[i] + 8) begin
          if (x >= sprite_x[i] && x < sprite_x[i] + 8) begin
	    sprite_pixel[i] <= sprite_row[i][~sprite_col[i]];
	  end
        end
      end
    end
  end
 
  wire [3:0] pixel_color = sprite_pixel[0] ? sprite_color[0] : 
	                   sprite_pixel[1] ? sprite_color[1] :
			   sprite_pixel[2] ? sprite_color[2] :
			   sprite_pixel[3] ? sprite_color[3] :
	                   font_line[~x_pix] ? text_color : back_color;
  
  wire [23:0] color = colors[border ? border_color : pixel_color];

  wire [7:0] red   = color[23:16];
  wire [7:0] green = color[15:8];
  wire [7:0] blue  = color[7:0];

  assign vga_r = !vga_de ? 8'b0 : red;
  assign vga_g = !vga_de ? 8'b0 : green;
  assign vga_b = !vga_de ? 8'b0 : blue;

endmodule
