//============================================================================
//  Arcade: Performan
//
//  Manufaturer: Toaplan
//  Type: Arcade Game
//  Genre: Puzzle
//  Orientation: Vertical
//
//  Hardware Description by Anton Gale
//  https://github.com/antongale/Arcade-Performan_MiSTer
//
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

///////// Default values for ports not used in this core /////////
assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
wire [15:0] sdram_sz;
assign VGA_F1 = 0;
assign VGA_SCALER = 0;
assign HDMI_FREEZE = 0;
assign VGA_DISABLE = 0;
assign FB_FORCE_BLANK = 0;

wire [9:0] snd_right;
wire [9:0] snd_left;

assign AUDIO_S = 0;//signed for audio out
assign AUDIO_MIX = 3;

assign LED_DISK = 0;
assign LED_POWER = 0;
assign BUTTONS = 0;

//copy dip switch setting for DIP menu
reg [7:0] sw[8];

always @(posedge clk_sys) begin
	if (ioctl_wr && (ioctl_index==254) && !ioctl_addr[24:3]) begin
		sw[ioctl_addr[2:0]] <= ioctl_dout;
	end
end	

////////////////////   HPS   /////////////////////

wire [31:0] status;
wire  [1:0] buttons;
wire        forced_scandoubler;
wire        direct_video;
wire        video_rotated;

wire        ioctl_download;
wire        ioctl_upload;
wire        ioctl_upload_req;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire  [7:0] ioctl_din;
wire  [7:0] ioctl_index;
wire        ioctl_wait;

wire [15:0] joystick_0;

wire [21:0] gamma_bus;

//////////////////////////////////////////////////////////////////

wire [1:0] ar = status[30:29];  //[20:19]

assign VIDEO_ARX = (!ar) ? ((status[2])  ? 8'd4 : 8'd3) : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? ((status[2])  ? 8'd3 : 8'd4) : 12'd0;

reg [7:0] MODE,DEBUG1,DEBUG2,DEBUG3,DEBUG4,DEBUG5,DEBUG6;

always @(posedge clk_sys) begin
	reg [7:0] mod_1 = 0;
	reg [7:0] mod_2 = 0;
	reg [7:0] mod_3 = 0;
	reg [7:0] mod_4 = 0;
	reg [7:0] mod_5 = 0;
	reg [7:0] mod_6 = 0;
	reg [7:0] mod_7 = 0;	
	
	if (ioctl_wr & (ioctl_index==1)) mod_1 <= ioctl_dout;
	if (ioctl_wr & (ioctl_index==2)) mod_2 <= ioctl_dout;
	if (ioctl_wr & (ioctl_index==3)) mod_3 <= ioctl_dout;
	if (ioctl_wr & (ioctl_index==5)) mod_4 <= ioctl_dout;
	if (ioctl_wr & (ioctl_index==6)) mod_5 <= ioctl_dout;	
	if (ioctl_wr & (ioctl_index==7)) mod_6 <= ioctl_dout;	
	if (ioctl_wr & (ioctl_index==8)) mod_7 <= ioctl_dout;	
	
	MODE<=mod_1;
	DEBUG1<=mod_2;
	DEBUG2<=mod_3;
	DEBUG3<=mod_4;
	DEBUG4<=mod_5;	
	DEBUG5<=mod_6;		
	DEBUG6<=mod_7;			
end

// Status Bit Map:
//                  Upper                          Lower
//     0         1         2         3          4         5         6
//     01234567890123456789012345678901 23456789012345678901234567890123
//     0123456789ABCDEFGHIJKLMNOPQRSTUV 0123456789ABCDEFGHIJKLMNOPQRSTUV
//AR:                               XXX
//OR:    X
//SD:     XXX  
//MRA:         XXXXXXXXXXXXXXXX
//HI :                          XX


//59.94 / 56.89Hz = 1.053612234136052
//37.93 / 36Mhz

`include "build_id.v"
localparam CONF_STR = {
	"A.PERFORMAN;;",
	"OTU,Aspect ratio,Original,Full Screen;",
	"O2,Orientation,Vert,Horz;",
	"O6,Flip,Off,On;",
	"O35,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
//	"OV,Frequency,60,Original;",	
	"-;",
	"DIP;",
	"-;",
	"H1OS,Autosave Hiscores,Off,On;",
	"P1,Pause options;",
	"P1OP,Pause when OSD is open,On,Off;",
	"P1OQ,Dim video after 10s,On,Off;",
	"-;",
	"R0,Reset;",
	"J1,Button 1,Button 2,Start 1P,Start 2P,Coin,Pause;",
	//"Jn,A,B,Start,Select;",
	"V,v",`BUILD_DATE
};

wire        sd_buff_wr, img_readonly;
wire  [7:0] sd_buff_addr;	// Address inside 256-word sector
wire [15:0] sd_buff_dout;
wire [15:0] sd_buff_din[2];
wire [15:0] sd_req_type;
wire [63:0] img_size;
wire [31:0] sd_lba[2];
wire  [1:0] sd_wr;
wire  [1:0] sd_rd;
wire  [1:0] sd_ack;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),

	.buttons(buttons),
	.status(status),
	.status_menumask({~hs_configured,direct_video}),

	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus),
	.direct_video(direct_video),
	.video_rotated(video_rotated),

	.ioctl_download(ioctl_download),
	.ioctl_upload(ioctl_upload),
	.ioctl_upload_req(ioctl_upload_req),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_din(ioctl_din),
	.ioctl_index(ioctl_index),
	.ioctl_wait(ioctl_wait),

	//SD RAM implementation?
	//.sdram_sz(sdram_sz),
	//.sd_lba(sd_lba),
	//.sd_rd(sd_rd),
	//.sd_wr(sd_wr),
	//.sd_ack(sd_ack),
	//.sd_buff_addr(sd_buff_addr),
	//.sd_buff_dout(sd_buff_dout),
	//.sd_buff_din(sd_buff_din),
	//.sd_buff_wr(sd_buff_wr),

	.joystick_0(joystick_0)
);

////////////////////   CLOCKS   ///////////////////

wire clkm_32MHZ,clkm_34MHZ,clkc_8MHZ;
wire clk_4M;
wire clk_sys=clkm_32MHZ;
wire clk_vid=clk_sys;
reg ce_pix;

pll pll(
		.refclk(CLK_50M),  			// refclk.clk FPGA_CLK1_50
		.rst(0),            			// reset.reset
		.outclk_0(clkm_32MHZ),     // outclk0.clk
		.outclk_1(clkm_34MHZ),     // outclk1.clk
		.outclk_2(clk_4M),			// outclk2.clk
		.outclk_3(clkc_8MHZ)
);

wire m_right  		= joystick_0[0];
wire m_left   		= joystick_0[1];
wire m_down   		= joystick_0[2];
wire m_up     		= joystick_0[3];
wire m_shoot  		= joystick_0[4];
wire m_shoot2		= joystick_0[5];
wire m_start1p  	= joystick_0[6];
wire m_start2p  	= joystick_0[7];
wire m_coin   		= joystick_0[8];
wire m_pause  		= joystick_0[9];

///////////////////   CLOCK DIVIDER   ////////////////////

always @(posedge clk_vid) begin
	reg [1:0] div;
	div <= div + (forced_scandoubler ? 2'd1 : 2'd2);
	//ce_pix <= !div;
end

///////////////////   VIDEO   ////////////////////
wire hblank, vblank;
wire hs, vs;

wire [3:0] r;
wire [3:0] g;
wire [3:0] b;
wire [11:0] rgb = {rgb_out[11:8],rgb_out[7:4],rgb_out[3:0]};//23:0

wire no_rotate = status[2] | direct_video;
wire core_flip = status[6];
wire rotate_ccw = 1'b0;
wire flip = 1'b0;

screen_rotate screen_rotate (.*);

arcade_video #(256,12) arcade_video //  12 : 4R 4G 4B - 288 //perf--
(
	.*,
	.clk_video(clk_vid),
	.ce_pix(core_pix_clk),	
	.RGB_in(rgb),
	.HBlank(hblank),
	.VBlank(vblank),
	.HSync(hs),
	.VSync(vs),
	.fx(status[5:3])
);

// PAUSE SYSTEM
wire pause_cpu;
wire [11:0] rgb_out;
pause #(4,4,4,38) pause
(
	.*,
	.user_button(m_pause),
	.pause_request(hs_pause),
	.options(~status[26:25])
);

// HISCORE SYSTEM
// --------------

wire [15:0]hs_address;
wire [7:0]hs_data_out;
wire [7:0]hs_data_in;
wire hs_write;
wire hs_access_read;
wire hs_access_write;
wire hs_pause;
wire hs_configured;

hiscore #(
	.HS_ADDRESSWIDTH(16),
	.CFG_ADDRESSWIDTH(6),
	.CFG_LENGTHWIDTH(2)
) hi (
	.*,
	.clk(clk_sys),
	.paused(pause_cpu),
	.reset(reset),
	.autosave(status[28]),
	.ram_address(hs_address),
	.data_from_ram(hs_data_out),
	.data_to_ram(hs_data_in),
	.data_from_hps(ioctl_dout),
	.data_to_hps(ioctl_din),
	.ram_write(hs_write),
	.ram_intent_read(hs_access_read),
	.ram_intent_write(hs_access_write),
	.pause_cpu(hs_pause),
	.configured(hs_configured)
);

///////////////////   GAME   ////////////////////
wire rom_download = ioctl_download && (ioctl_index == 0);
wire reset = (RESET | status[0] | buttons[1] | ioctl_download);
assign LED_USER = ioctl_download;
wire core_pix_clk;

performan_fpga perfcore(
	.clkm_master(clk_sys),
	.clkf_cpu(clkc_8MHZ),
	.clkaudio(clk_4M),
	.pcb(MODE),
	.DEBUG1(DEBUG1),
	.DEBUG2(DEBUG2),
	.DEBUG3(DEBUG3),
	.DEBUG4(DEBUG4),	
	.DEBUG5(DEBUG5),		
	.DEBUG6(DEBUG6),			
	.RED(r),
	.GREEN(g),
	.BLUE(b),
	.core_pix_clk(core_pix_clk),		//from fpga core to sv		
	.H_SYNC(hs), //hs
	.V_SYNC(vs), //vs
	.H_BLANK(hblank),
	.V_BLANK(vblank),
	.RESET_n(~reset),
	.flip(core_flip),
	.pause(pause_cpu),
	.CONTROLS(~{m_coin,m_start2p,m_start1p,m_shoot2,m_shoot,m_up,m_down,m_left,m_right}),
	.DIP1(sw[1]), 
	.DIP2(sw[2]),
	.dn_addr(ioctl_addr),
	.dn_data(ioctl_dout),
	.dn_wr(ioctl_wr && rom_download), //& rom_download
	.audio_l(AUDIO_L),
	.audio_r(AUDIO_R),
	.hs_address(hs_address),
	.hs_data_out(hs_data_out),
	.hs_data_in(hs_data_in),
	.hs_write(hs_write)
);

endmodule
