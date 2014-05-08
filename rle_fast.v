module rle_fast (
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


parameter IDLE = 2'b00;
parameter POSTIDLE_READ = 2'b01;
parameter COMPUTE = 2'b10;


reg [31:0]	byte_str, write_buffer, total_count, size_of_writes;
reg [15:0]	read_addr, write_addr;
reg [7:0]	byte, byte_count;
reg [1:0]	state, shift_count;
reg			first_flag, wen, first_half, post_read;

wire [31:0]	size_of_writes_n, byte_str_n, total_count_n;
wire [15:0]	read_addr_n, write_addr_n;
wire [1:0]	shift_count_n;
wire [7:0]	byte_count_n;
wire			end_of_byte_str, reached_length, whole_str_same, skip_byte_str;

//READ:
assign read_addr_n = read_addr + 4;

//READ/WRITE;
assign port_A_addr = (wen) ? write_addr : read_addr;
assign port_A_clk = clk;
assign done = (reached_length && state == IDLE && !wen); //reached_length and is idle

//WRITE:
assign port_A_we = wen;
assign write_addr_n = write_addr + 4;
assign port_A_data_in = write_buffer;
assign size_of_writes_n = size_of_writes + 4;
assign rle_size = size_of_writes;

//COMPUTE:
assign skip_byte_str = whole_str_same && !shift_count;
assign byte_str_n = {8'b0,byte_str[31:8]};
assign shift_count_n = (skip_byte_str) ? shift_count : shift_count + 1; // keep track of where the bytes have been shifted
assign end_of_byte_str = (shift_count == 2'b11); // mark the end of the byte array to get new data
assign reached_length = total_count == message_size; // length has been reached
assign whole_str_same = &(byte_str ^~ {byte_str[7:0], byte_str[7:0], byte_str[7:0], byte_str[7:0]}); //check if all bytes are the same (optimization)
assign byte_count_n = (skip_byte_str) ? (byte_count + 4) : (byte_count + 1);
assign total_count_n = (skip_byte_str) ? (total_count + 4): (total_count + 1);

always@(posedge clk or negedge nreset)
begin
	if(!nreset) begin
		byte_str <= 32'b0;
		state <= IDLE;
		first_flag <= 1'b1;
		shift_count <= 2'b0;
		read_addr <= 16'b0;
		write_addr <= 16'b0;
		first_half <= 1'b1;
		write_buffer <= 32'b0;
		byte_count <= 8'b0;
		total_count <= 32'b0;
		size_of_writes <= 32'b0;
		wen <= 1'b0;
		post_read <=1'b0;
		
		
	end
	else begin
		case(state)
		
			IDLE: begin
				if(start) begin
					byte_str <= 32'b0;
					state <= POSTIDLE_READ;
					read_addr <= message_addr[15:0];
					write_addr <= rle_addr[15:0];
					first_flag <= 1'b1;
					shift_count <= 2'b0;
					first_half <= 1'b1;
					write_buffer <= 32'b0;
					byte_count <= 8'b0;
					total_count <= 32'b0;
					size_of_writes <= 32'b0;
					wen <= 1'b0;
					post_read <= 1'b0;
					
				end
				if(wen == 1'b1) begin
					wen <= 1'b0;
				end
			end
			
			POSTIDLE_READ: begin
				state <= COMPUTE;
				read_addr <= read_addr_n; // increment read address
				post_read <= 1'b1;
				
			end
			COMPUTE: begin
				if(wen == 1'b1) begin
					wen <= 1'b0;
					write_addr <= write_addr_n;
				end
				if(post_read) begin
					byte_str <= port_A_data_out; //get byte from read;
					post_read <= 1'b0;
				end
				else begin
					//check if we want to do any writing to memory:
					if((byte != byte_str[7:0] && !first_flag ) || reached_length) begin
						//check which half of they byte array buffer we want to set:
						if(first_half) begin
							write_buffer <= {16'b0, byte, byte_count};
							first_half <= 1'b0;
							size_of_writes <= (reached_length) ? size_of_writes_n : size_of_writes;
						end
						else begin
							write_buffer[31:16] <= {byte, byte_count};
							wen <= 1'b1;
							first_half <= 1'b1;
							size_of_writes <= size_of_writes_n;
						end
						state <= (reached_length) ? IDLE : COMPUTE;
						byte <= byte_str[7:0];
						byte_count <= 8'b0;
					end
					else begin //byte == byte_str[7:0];
						//check if this is the first run:
						if(first_flag) begin
							byte <= byte_str[7:0];
							first_flag <= 1'b0;
						end
						
						//check if we want to read or not:
						read_addr <= (end_of_byte_str || skip_byte_str) ? read_addr_n : read_addr; // increment read address
						post_read <= end_of_byte_str || skip_byte_str;
							
						state <= (reached_length) ? IDLE : COMPUTE;
						
						//shift bytes
						byte_str <= byte_str_n;
						shift_count <= shift_count_n;
						byte_count <= byte_count_n;
						total_count <= total_count_n;
					end
				end
			end
		endcase
	end
	

end


endmodule

