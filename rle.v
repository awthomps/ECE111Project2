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


wire				A_clk_n;
wire	[15:0]	curr_read_addr_n;
wire 	[31:0]	curr_read_data_n;
wire				wen_n;

reg	[1:0]		state, state_n, compute_substate, compute_substate_n;
reg				A_clk_r;
reg	[15:0]	curr_read_addr_r;
reg	[31:0]	curr_read_data_r, curr_byte_count_r, total_count_r, curr_byte_count_n, total_count_n;
reg				wen_r;
reg	[7:0]		curr_byte_r;

parameter IDLE    = 2'b00;
parameter READ = 2'b01;
parameter WRITE = 2'b01;
parameter COMPUTE = 2'b11;
parameter C_STAGE_0 = 2'b00;
parameter C_STAGE_1 = 2'b01;
parameter C_STAGE_2 = 2'b01;
parameter C_STAGE_3 = 2'b11;



//increment the DPSRAM clock:
assign port_A_clk = clk;

//increment address to read;
assign curr_read_addr_n = curr_read_addr_r + 4;
assign port_A_addr = curr_read_addr_r;

//accept data:
assign curr_read_data_n = port_A_data_out;

//set wen:
assign wen_n = (state == WRITE) ? 1'b1 : 1'b0;
assign port_A_we = wen_r;





always@(*)
begin

	case(state)
		COMPUTE:
		begin
			case(compute_substate)
				C_STAGE_0:
				begin
					compute_substate_n = (curr_read_data_n[7:0] == curr_byte_r) ? C_STAGE_0 : C_STAGE_1;
				end
				C_STAGE_1:
				begin
					compute_substate_n = (curr_read_data_n[15:8] == curr_byte_r) ? C_STAGE_1 : C_STAGE_2;
				end
				C_STAGE_2:
				begin
					compute_substate_n = (curr_read_data_n[23:16] == curr_byte_r) ? C_STAGE_2 : C_STAGE_3;
				end
				C_STAGE_3:
				begin
					compute_substate_n = (curr_read_data_n[31:24] == curr_byte_r) ? C_STAGE_3 : C_STAGE_0;
				end
			endcase
			if(compute_substate_n != compute_substate) begin
				state_n = (curr_byte_count_r == message_size) ? WRITE : COMPUTE;
				curr_byte_count_n = 1 + curr_byte_count_r;
				total_count_n = 1 + total_count_r;
			end
			else begin
				state_n = READ;
			end
		end
		READ:
			begin
				state_n = COMPUTE;
			end
		WRITE:
			begin
				state_n = (total_count_r == message_size) ? IDLE : COMPUTE;
			end
	endcase
end



always @(posedge clk or negedge nreset)
begin
	if (!nreset) begin
		state <= IDLE;
		compute_substate <= C_STAGE_0;
		//A_clk_r <= 1'b1;
		curr_read_addr_r <= 16'b0;
		wen_r <= 1'b0;
		curr_byte_r <= 8'b0;
		curr_byte_count_r <= 32'b0;
		total_count_r = 32'b0;
	end
	else
		
		//set next cycles read/write
		wen_r <= wen_n;
		case (state)
		IDLE:
			begin
				if (start) begin
					//initializations
					state <= READ;
					compute_substate <= C_STAGE_0;
					curr_read_addr_r <= message_addr[15:0];
					curr_byte_r <= 8'b0;
					curr_byte_count_r <= 32'b0;
					total_count_r <= 32'b0;
				end
			end
		READ:
			begin
				state <= state_n; 
				curr_read_addr_r <= curr_read_addr_n;
			end
		WRITE:
			begin
				state <= state_n;
				curr_byte_count_r <= 0; //reset the byte count
				//TODO: determine how to output done signal
				// and how to write the data
			end
		COMPUTE:
			begin
				state <= state_n;
				curr_byte_count_r <= curr_byte_count_n;
				total_count_r <= total_count_n;
				compute_substate <= compute_substate_n;
			end
	  endcase
 end



endmodule