`default_nettype none
module msx (
  input         clk25_mhz,
  // Buttons
  input [6:0]   btn,
  // HDMI
  output [3:0]  gpdi_dp,
  output [3:0]  gpdi_dn,
  // Keyboard
  output        usb_fpga_pu_dp,
  output        usb_fpga_pu_dn,
  inout         ps2Clk,
  inout         ps2Data,
  // Audio
  output [3:0]  audio_l,
  output [3:0]  audio_r,
  // ESP32 passthru
  input         ftdi_txd,
  output        ftdi_rxd,
  input         wifi_txd,
  output        wifi_rxd,  // SPI from ESP32
  input         wifi_gpio16,
  input         wifi_gpio5,
  output        wifi_gpio0,

  inout  sd_clk, sd_cmd,
  inout   [3:0] sd_d,

  inout  [27:0] gp,gn,
  // Leds
  output reg [7:0]  leds
);

  assign wifi_gpio0 = 0;

  // VGA (should be assigned to some gp/gn outputs
  wire   [3:0]  red;
  wire   [3:0]  green;
  wire   [3:0]  blue;
  wire          hSync;
  wire          vSync;
  
  parameter c_vga_out = 0;

  generate
    genvar i;
    if (c_vga_out) begin
      for(i = 0; i < 4; i = i+1) begin
        assign gp[10-i] = red[i];
        assign gn[3-i] = green[i];
        assign gn[10-i] = blue[i];
      end
      assign gp[2] = vSync;
      assign gp[3] = hSync;
    end 
  endgenerate

  reg [15:0] diag16;

  generate 
    genvar i;
    for(i = 0; i < 4; i = i+1)
    begin
      assign gn[17-i] = diag16[8+i];
      assign gp[17-i] = diag16[12+i];
      assign gn[24-i] = diag16[i];
      assign gp[24-i] = diag16[4+i];
    end
  endgenerate
  
  wire          n_WR;
  wire          n_RD;
  wire          n_INT;
  wire [15:0]   cpuAddress;
  wire [7:0]    cpuDataOut;
  wire [7:0]    cpuDataIn;
  wire          n_memWR;
  wire          n_memRD;
  wire          n_ioWR;
  wire          n_ioRD;
  wire          n_MREQ;
  wire          n_IORQ;
  wire          n_M1;
  wire          n_kbdCS;
  wire          n_int;

  reg [3:0]     sound = 0;

  reg [2:0]     cpuClockCount;
  wire          cpuClock;
  wire          cpuClockEnable;
  wire [7:0]    ramOut;

  // passthru to ESP32 micropython serial console
  assign wifi_rxd = ftdi_txd;
  assign ftdi_rxd = wifi_txd;

  // ===============================================================
  // System Clock generation
  // ===============================================================
  wire clk_hdmi, clk_vga;

  pll pll_i (
    .clkin(clk25_mhz),
    .clkout0(clk_hdmi),
    .clkout1(clk_vga),
    .clkout2(cpuClock)
  );

  // ===============================================================
  // Reset generation
  // ===============================================================
  reg [15:0] pwr_up_reset_counter = 0;
  wire       pwr_up_reset_n = &pwr_up_reset_counter;

  always @(posedge cpuClock) begin
     if (!pwr_up_reset_n)
       pwr_up_reset_counter <= pwr_up_reset_counter + 1;
  end

  // ===============================================================
  // CPU
  // ===============================================================
  wire [15:0] pc;
  
  wire n_hard_reset = pwr_up_reset_n & btn[0];

  tv80n cpu1 (
    .reset_n(n_hard_reset),
    //.clk(cpuClock), // turbo mode 28MHz
    .clk(cpuClockEnable), // normal mode 3.5MHz
    .wait_n(1'b1),
    .int_n(n_int),
    .nmi_n(1'b1),
    .busrq_n(1'b1),
    .mreq_n(n_MREQ),
    .m1_n(n_M1),
    .iorq_n(n_IORQ),
    .wr_n(n_WR),
    .rd_n(n_RD),
    .A(cpuAddress),
    .di(cpuDataIn),
    .do(cpuDataOut),
    .pc(pc)
  );

  // ===============================================================
  // RAM
  // ===============================================================
  ram #(
    .MEM_INIT_FILE("../roms/msx.mem")
  )
  ram64 (
    .clk(cpuClock),
    .we(!n_memWR && cpuAddress >= 16'h8000),
    .addr(cpuAddress),
    .din(cpuDataOut),
    .dout(ramOut)
  );

  // ===============================================================
  // Keyboard
  // ===============================================================
  wire [7:0]  key_data;
  wire [10:0] ps2_key;

    // Get PS/2 keyboard events
  ps2 ps2_kbd (
     .clk(cpuClock),
     .ps2_clk(ps2Clk),
     .ps2_data(ps2Data),
     .ps2_key(ps2_key)
  );

  // Keyboard matrix

  wire pause, scroll, reso;
  wire [7:0] f_keys;
  reg [7:0] ppi_port_a, ppi_port_c;
  wire [7:0] ppi_port_b;
  wire [7:0] key_diag;

  keyboard key_board (
    .clk(cpuClock),
    .reset(!n_hard_reset),
    .clk_ena(1'b1),
    .k_map(1'b1), // English
    .pause(pause),
    .scroll(scroll),
    .reso(reso),
    .f_keys(f_keys),
    .ps2_key(ps2_key),
    .ppi_port_c(ppi_port_c),
    .p_key_x(ppi_port_b),
    .diag(key_diag)
  );

  // pull-ups for us2 connector 
  assign usb_fpga_pu_dp = 1;
  assign usb_fpga_pu_dn = 1;
  
  // ===============================================================
  // VGA
  // ===============================================================
  wire        vga_de;
  wire [7:0]  vga_din = cpuDataOut;
  wire [7:0]  vga_dout;
  reg  [13:0] vga_addr;
  wire        vga_wr = cpuAddress[7:0] == 8'h98 && n_ioWR == 1'b0;
  reg  [1:0]  mode = 0;
  reg         is_second_addr_byte = 0;
  reg [7:0]   first_addr_byte;
  reg         r_n_ioWR;
  reg [13:0]  start_vga;
  reg [7:0]   r_vdp [0:7];
  reg [13:0]  font_addr = 14'h0800;
  reg [13:0]  name_table_addr = 14'h0;
  wire [7:0]  vga_diag;

  always @(posedge cpuClock) begin
    if (cpuClockEnable) begin
      r_n_ioWR <= n_ioWR;
      if (vga_wr && r_n_ioWR == 1'b1) vga_addr <= vga_addr + 1;
      if (cpuAddress[7:0] == 8'h99 && n_ioWR == 1'b0 && r_n_ioWR == 1'b1) begin
        is_second_addr_byte <= ~is_second_addr_byte;
        if (is_second_addr_byte) begin
	  if (!cpuDataOut[7]) begin
            vga_addr <=  {cpuDataOut[5:0], first_addr_byte};
            start_vga <=  {cpuDataOut[5:0], first_addr_byte};
          end else begin
            if (cpuDataOut[5:0] < 8) begin
              r_vdp[cpuDataOut[5:0]] <= first_addr_byte;
	    end
	  end
        end else begin
          first_addr_byte <= cpuDataOut;
        end
      end
      // PPI interface
      if (cpuAddress[7:0] == 8'ha8 && n_ioWR == 1'b0)
        ppi_port_a <= cpuDataOut;
      if (cpuAddress[7:0] == 8'haa && n_ioWR == 1'b0)
        ppi_port_c <= cpuDataOut;
      if (cpuAddress[7:0] == 8'hab && n_ioWR == 1'b0)
        ppi_port_c[cpuAddress[3:1]] <= cpuAddress[0];
    end
  end
      
  video vga (
    .clk(clk_vga),
    .vga_r(red),
    .vga_g(green),
    .vga_b(blue),
    .vga_de(vga_de),
    .vga_hs(hSync),
    .vga_vs(vSync),
    .vga_addr(vga_addr),
    .vga_din(vga_din),
    .vga_dout(vga_dout),
    .vga_wr(vga_wr),
    .mode(mode),
    .cpu_clk(cpuClock),
    .font_addr(font_addr),
    .name_table_addr(name_table_addr),
    .n_int(n_int),
    .diag(vga_diag)
  );

  // Convert VGA to HDMI
  HDMI_out vga2dvid (
    .pixclk(clk_vga),
    .pixclk_x5(clk_hdmi),
    .red  ({red, {4{red[0]}}}),
    .green({green, {4{green[0]}}}),
    .blue ({blue, {4{blue[0]}}}),
    .vde(vga_de),
    .hSync(hSync),
    .vSync(vSync),
    .gpdi_dp(gpdi_dp),
    .gpdi_dn(gpdi_dn)
  );

  // ===============================================================
  // MEMORY READ/WRITE LOGIC
  // ===============================================================

  assign n_ioWR = n_WR | n_IORQ;
  assign n_memWR = n_WR | n_MREQ;
  assign n_ioRD = n_RD | n_IORQ;
  assign n_memRD = n_RD | n_MREQ;

  // ===============================================================
  // Chip selects
  // ===============================================================

  assign n_kbdCS = !(cpuAddress[7:0] == 8'ha9);

  // ===============================================================
  // Memory decoding
  // ===============================================================

  assign cpuDataIn =  n_kbdCS == 1'b0 && n_ioRD == 1'b0 ? ppi_port_b :
                      ramOut;
  
  // ===============================================================
  // CPU clock enable
  // ===============================================================
   
  always @(posedge cpuClock) begin
    cpuClockCount <= cpuClockCount + 1;
  end

  assign cpuClockEnable = cpuClockCount[2]; // 3.5Mhz

  // ===============================================================
  // Audio
  // ===============================================================

  assign audio_l = sound;
  assign audio_r = sound;

  // ===============================================================
  // Leds
  // ===============================================================
  wire led1 = !n_kbdCS;
  wire led2 = 0;
  wire led3 = 0;
  wire led4 = !n_hard_reset;

  //assign leds = {led4, led3, led2, led1};
  always @(posedge cpuClock) if (ppi_port_b != 8'hff && ppi_port_c[3:0] == 6) leds = ppi_port_b;

  always @(posedge cpuClock) diag16 <= ps2_key;

endmodule
