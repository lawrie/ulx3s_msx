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
  input         video_on,
  input [3:0]   text_color,
  input [3:0]   back_color,
  input         sprite_large,
  input         sprite_enlarged,
  input         vert_retrace_int,
  output        n_int,
  output        sprite_collision,
  output        too_many_sprites,
  output        interrupt_flag,
  output [4:0]  sprite5,
  output [7:0]  diag
);

  // VGA output parameters for 60hz 640x480
  parameter HA = 640;
  parameter HS  = 96;
  parameter HFP = 16;
  parameter HBP = 48;
  parameter HT  = HA + HS + HFP + HBP;
  parameter HB = 80;
  parameter HB2 = HB/2;
  parameter HBadj = 12; // Border adjustment

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

  // Data for graphics and sprites
  reg [7:0] screen_color;
  reg [7:0] screen_color_next;

  reg [7:0] sprite_y [0:3];
  reg [7:0] sprite_x [0:3];
  reg [3:0] sprite_color [0:3];
  reg [7:0] sprite_pattern [0:3];
  reg [5:0] sprite_num [0:3];
  reg [7:0] next_sprite_line [0:3];
  reg [7:0] sprite_line [0:3];

  reg [9:0] hc = 0;
  reg [9:0] vc = 0;

  reg INT = 0;
  reg[5:0] intCnt = 1;

  reg [7:0] r_char;
  reg [7:0] font_line;
  
  reg [3:0] sprite_pixel;
  
  // Sprite collision count
  wire [2:0] sprite_count = sprite_pixel[3] + sprite_pixel[2] + 
	                    sprite_pixel[1] + sprite_pixel[0];

  // Sprite collision status data
  assign sprite_collision  = (sprite_count > 1);
  assign too_many_sprites = 0;
  assign sprite5 = 0;

  // Set CPU interrupt flag
  assign n_int = !INT;
  // Status interrupt flag
  assign interrupt_flag = (hc == VA);

  // Set horizontal and vertical counters, generate sync signals and
  // vertical sync interrupt interrupt
  always @(posedge clk) begin
    if (hc == HT - 1) begin
      hc <= 0;
      if (vc == VT - 1) vc <= 0;
      else vc <= vc + 1;
    end else hc <= hc + 1;
    if (hc == HA + HFP && vc == VA + VFP && vert_retrace_int) INT <= 1;
    if (INT) intCnt <= intCnt + 1;
    if (!intCnt) INT <= 0;
  end

  assign vga_hs = !(hc >= HA + HFP && hc < HA + HFP + HS);
  assign vga_vs = !(vc >= VA + VFP && vc < VA + VFP + VS);
  assign vga_de = !(hc > HA || vc > VA);

  // Set x and y to screen pixel coordinates. x not valid in text mode
  wire [7:0] x = hc[9:1] - HB2;
  wire [7:0] y = vc[9:1] - VB2;

  // Set the x position as a character and pixel offset. Valid in all modes.
  reg [5:0] x_char;
  reg [2:0] x_pix;

  wire [3:0] char_width = (mode == 0 ? 6 : 8);
  wire [4:0] next_char = x_char + 1;

  // Calculate the border
  wire hBorder = (hc < (HB + HBadj) || hc >= HA - HB);
  wire vBorder = (vc < VB || vc >= VA - VB);
  wire border = hBorder || vBorder;

  // VRAM
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

  // Calculate pixel positions for 4 active sprites
  wire [2:0] sprite_col [0:3];

  generate
    genvar j;
    for(j=0;j<4;j=j+1) begin
      assign sprite_col[j] = ((x - sprite_x[j]) >> sprite_enlarged);
    end
  endgenerate

  // Calculate x_char and x_pix
  always @(posedge clk) begin
    if (hc[0] == 1) begin
      x_pix <= x_pix + 1;
      if (x_pix == (char_width - 1)) begin
        x_pix <= 0;
        x_char <= x_char + 1;
      end
    end

    // Get ready for start of line
    if (hc == HB - (char_width << 1) - 1) begin
      x_pix <= 0;
      x_char <= 63;
    end
  end

  integer i;

  // Fetch VRAM data and create pixel output
  always @(posedge clk) if (video_on) begin
    if (mode == 0) begin
      sprite_pixel <= 0;
      if (hc[0] == 1) begin
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
    end else begin
      if (mode == 1 || mode == 2) begin
        // In screen mode 1, 32 entries in color table specify the colors for
        // groups of 8 characters.
	// In screen mode 2, there are two colors for each line of 8 pixels,
	// the screen is 256x192 pixels
        if (hc[0] == 0 && hc < HA) begin
          // Get the colors
          if (x_pix == 5) begin
            // Set address for next character
            vid_addr <= name_table_addr + {y[7:3], next_char};
          end else if (x_pix == 6) begin
            // Set address for next color block
            if (mode == 2) vid_addr <= color_table_addr + {y[7:6], 11'b0} + {vid_out, y[2:0]};
            else vid_addr <= color_table_addr + vid_out[7:5];
          end else if (x_pix == 7) begin
            // Store the color block ready for next character
            screen_color_next <= vid_out;
	  end
	end
      end
      // Fetch the pattern data, on odd cycles
      if (hc[0] == 1) begin
	if (hc < HA) begin 
          // Fetch the patterns for the 4 sprites
	  if (x_pix < 5) begin
            if (x_pix  < 4) begin
              if (sprite_large)
                vid_addr <= sprite_pattern_table_addr + (sprite_pattern[x_pix] << 5) + y[3:0];
              else
                vid_addr <= sprite_pattern_table_addr + (sprite_pattern[x_pix] << 3) + y[2:0];
            end
            if (x_pix > 0) 
              next_sprite_line[x_pix - 1] <= vid_out;
          end
          // Fetch the font for screen mode 1 to 3
          if (x_pix == 5) begin
            // Set address for next character
            vid_addr <= name_table_addr + {y[7:3], next_char};
          end else if (x_pix == 6) begin
            // Set address for font line, 3 blocks if mode == 2
	    if (mode == 3) vid_addr <= font_addr + {vid_out, y[4:2]};
            else vid_addr <= font_addr + (mode == 2 ? {y[7:6] , 11'b0} : 13'b0) +  {vid_out, y[2:0]};
          end else if (x_pix == 7) begin
            // Store the font line (or colors for mode 3) ready for next character
            font_line <= vid_out;
	    // For modeis 1 or  2, set screen color for next block
	    if (mode == 1 || mode == 2) begin
              screen_color <= screen_color_next;
	      for(i=0;i<4;i=i+1) sprite_line[i] <= next_sprite_line[i];
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
	end
      end

      // Look for up to 4 sprites on the current line
      sprite_pixel <= 0;
      for (i=0; i<4; i=i+1) begin
        if (sprite_y[i] < 208 && y >= sprite_y[i] && 
            y < sprite_y[i] + ((8 << sprite_enlarged) << sprite_large)) begin
          if (x >= sprite_x[i] && x < sprite_x[i] + ((8 << sprite_enlarged) << sprite_large)) begin
	    sprite_pixel[i] <= (sprite_line[i][~sprite_col[i]]);
	  end
        end
      end
    end
  end

  // Set the pixel from highest priority plane 
  wire [3:0] pixel_color = sprite_pixel[0] ? sprite_color[0] : 
	                   sprite_pixel[1] ? sprite_color[1] :
			   sprite_pixel[2] ? sprite_color[2] :
			   sprite_pixel[3] ? sprite_color[3] : 
	                   mode == 0 ? (font_line[~x_pix] ? text_color : back_color) :
			   mode == 3 ? (x_pix < 4 ? font_line[7:4] : font_line[3:0]) :
			   font_line[~x_pix] ? screen_color[7:4] : screen_color[3:0];
  
  // Set the 24-bit color value, taking border into account
  wire [23:0] color = colors[border ? back_color : pixel_color];

  // Set the 8-bit VGA output signals
  assign vga_r = !vga_de ? 8'b0 : color[23:16];
  assign vga_g = !vga_de ? 8'b0 : color[15:8];
  assign vga_b = !vga_de ? 8'b0 : color[7:0];

  assign diag = 0;

endmodule
