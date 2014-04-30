module rle (
	clk, 		
	nreset, 	
	start,
	message_addr,
	message_size, 	
	rle_addr, 	
	rle_size, 	
	done, 		
	port_A_clk,
        port_A_data_in,
        port_A_data_out,
        port_A_addr,
        port_A_we
	);

input	clk;
input	nreset;
// Initializes the RLE module

input	start;
// Tells RLE to start compressing the given frame

input 	[31:0] message_addr;
// Starting address of the plaintext frame
// i.e., specifies from where RLE must read the plaintext frame

input	[31:0] message_size;
// Length of the plain text in bytes

input	[31:0] rle_addr;
// Starting address of the ciphertext frame
// i.e., specifies where RLE must write the ciphertext frame

input   [31:0] port_A_data_out;
// read data from the dpsram (plaintext)

output  [31:0] port_A_data_in;
// write data to the dpsram (ciphertext)

output  [15:0] port_A_addr;
// address of dpsram being read/written

output  port_A_clk;
// clock to dpsram (drive this with the input clk)

output  port_A_we;
// read/write selector for dpsram

output	[31:0] rle_size;
// Length of the compressed text in bytes

output	done; // done is a signal to indicate that encryption of the frame is complete


wire			A_clk_n;
wire	[15:0] curr_read_addr_n, curr_read_data_n;

reg	[1:0] state;
reg			A_clk_r;
reg	[15:0] curr_read_addr_r, curr_read_data_r;

parameter IDLE    = 2'b00;
parameter READ = 2'b01;
parameter WRITE = 2'b01;
parameter READWRITE = 2'b11;



//increment the DPSRAM clock:
assign A_clk_n = ~A_clk_r;
assign port_A_clk = A_clk_r;

//increment address to read;
assign curr_read_addr_n = curr_read_addr_r + 4;
assign port_A_addr = curr_read_addr_r;

//accept data:
assign curr_read_data_n = port_A_data_out;


always @(posedge clk or negedge nreset)
begin
	if (!nreset) begin
		state <= IDLE;
		A_clk_r <= 1'b1;
		curr_read_addr_r <= rle_addr[15:0];
	end
	else
		case (state)
		IDLE:
			begin
				if (start) begin
					//initializations
					state <= READ;
				end
			end
		READ:
			begin
				state <= READ;
				A_clk_r <= A_clk_n; //change clk
				
				if(A_clk_n) begin //A_clk is high
					curr_read_addr_r <= curr_read_addr_n;
				end
			end
		WRITE:
			begin
				state <= WRITE;
				
				if(A_clk_n) begin //A_clk is high
				
				end
			end
		READWRITE:
			begin
				state <= READWRITE;
				
				if(A_clk_n) begin //A_clk is high
				
				end
			end
	  endcase
 end




endmodule