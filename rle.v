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


wire	[15:0]	curr_read_addr_n, curr_write_addr_n;
wire 	[31:0]	curr_read_data_n;
wire				wen_n;
wire	[1:0]		compute_substate_n;
wire	[7:0]		curr_byte_n;

reg	[1:0]		state, compute_substate;
reg				write_substate;
reg	[15:0]	curr_read_addr_r, curr_write_addr_r;
reg	[31:0]	curr_read_data_r, curr_byte_count_r, total_count_r, curr_write_data_r, num_writes;
reg				wen_r;
reg	[7:0]		curr_byte_r;

parameter IDLE    = 2'b00;
parameter READ = 2'b01;
parameter WRITE = 2'b10;
parameter COMPUTE = 2'b11;
parameter C_STAGE_0 = 2'b00;
parameter C_STAGE_1 = 2'b01;
parameter C_STAGE_2 = 2'b10;
parameter C_STAGE_3 = 2'b11;
parameter W_STAGE_0 = 1'b0;
parameter W_STAGE_1 = 1'b1;



//increment the DPSRAM clock:
assign port_A_clk = clk;

//increment address to read:
assign curr_read_addr_n = curr_read_addr_r + 4;
assign port_A_addr = wen_r ? curr_write_addr_r : curr_read_addr_r; //TODO: there may be a read/write conflict here

//increment address to write:
assign curr_write_addr_n = (write_substate == W_STAGE_0) ? curr_write_addr_r + 4 : curr_write_addr_r;
assign port_A_data_in = curr_write_data_r;

//set size of the compressed text:
assign rle_size = (write_substate == W_STAGE_1) ? (1 + num_writes) * 4 : num_writes * 4;

//accept data:
assign curr_read_data_n = port_A_data_out;

//set wen:
assign wen_n = (state == WRITE && write_substate == W_STAGE_1) ? 1'b1 : 1'b0;
assign port_A_we = wen_r;
assign done = (state == IDLE && total_count_r == message_size) ? 1'b1 : 1'b0;


//Compute combinational logic
assign curr_byte_n = (compute_substate == C_STAGE_0) ? curr_read_data_r[7:0] :
							((compute_substate == C_STAGE_1) ? curr_read_data_r[15:8] : 
							((compute_substate == C_STAGE_2) ? curr_read_data_r[23:16] : curr_read_data_r[31:24])); //C_STAGE_3
assign compute_substate_n = ((state == COMPUTE) && (curr_byte_n == curr_byte_r) &&
									 ((compute_substate == C_STAGE_0) || (compute_substate == C_STAGE_1) ||
									 (compute_substate == C_STAGE_2) || (compute_substate == C_STAGE_3)
									 )) ? (compute_substate + 1) % 4 : compute_substate;
									 
									 
									 
//begin sequential logic
always @(posedge clk or negedge nreset)
begin
	if (!nreset) begin
		state <= IDLE;
		compute_substate <= C_STAGE_0;
		write_substate <= W_STAGE_0;
		curr_read_addr_r <= 16'b0;
		curr_write_addr_r <= 16'b0;
		curr_read_data_r <= 32'b0;
		wen_r <= 1'b0;
		curr_byte_r <= 8'b0;
		curr_byte_count_r <= 32'b0;
		total_count_r = 32'b0;
		num_writes = 32'b0;
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
					write_substate <= W_STAGE_0;
					curr_read_addr_r <= message_addr[15:0];
					curr_write_addr_r <= rle_addr[15:0];
					curr_read_data_r <= 32'b0;
					curr_byte_r <= 8'b0;
					curr_byte_count_r <= 32'b0;
					total_count_r <= 32'b0;
					num_writes = 32'b0;
				end
			end
		READ:
			begin
				state <= COMPUTE; 
				curr_read_addr_r <= curr_read_addr_n;
				curr_read_data_r <= curr_read_data_n;
			end
		WRITE:
			begin
			//TODO: there is something wrong with the write 
				curr_byte_count_r <= 0; //reset the byte count
				
				curr_write_addr_r <= curr_write_addr_n;
				state <= (total_count_r == message_size) ? IDLE : COMPUTE;
				write_substate <= ~write_substate;
				curr_byte_r <= curr_byte_n; //wrote data for this byte so change the current byte
				if(write_substate == W_STAGE_0) begin
					curr_write_data_r <= {16'b0, curr_byte_r, curr_byte_count_r};
				end
				else begin
					curr_write_data_r[31:16] <= {curr_byte_r, curr_byte_count_r};
					num_writes = num_writes + 1; //increment number of writes
				end
			end
		COMPUTE:
			begin
				compute_substate <= compute_substate_n;
				
				//current count == input count or there is a new byte from byte string
				if(total_count_r == message_size || compute_substate_n == compute_substate) begin
					state <= WRITE;
				end
				else begin //current byte same as bye we are looking at
					state <= ((compute_substate == C_STAGE_3) && (curr_read_data_r[31:24] == curr_byte_r)) ? READ : COMPUTE;
					curr_byte_count_r <= curr_byte_count_r + 1;
					total_count_r <= total_count_r + 1;
				end
			end
	  endcase
 end



endmodule