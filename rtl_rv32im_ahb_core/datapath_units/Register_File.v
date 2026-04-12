//! @brief 32-bit Register File (32 registers)
//! - Contains 32 general-purpose 32-bit registers (x0–x31).
//! - x0 is hardwired to zero.
//! - Allows synchronous write and read operations.
//! - Implements hazard forwarding on read ports.

module Register_File(
    input Clk_In,                    //! Clock input
    input Rst_In,                    //! Synchronous reset
    input WrEn_In,                   //! Write enable
    input [4:0] Src_Addr1_In,        //! Address for source register 1 (rs1)
    input [4:0] Src_Addr2_In,        //! Address for source register 2 (rs2)
    input [4:0] Des_Addr_In,         //! Address for destination register (rd)
    input [31:0] Des_Data_In,        //! Data to write into destination register
    output [31:0] Src_Data1_Out,     //! Output data from rs1
    output [31:0] Src_Data2_Out      //! Output data from rs2
);

    reg [31:0] Temp_Src_Data1;
    reg [31:0] Temp_Src_Data2;
    reg [4:0]  Src_Addr1_Sampled;
    reg [4:0]  Src_Addr2_Sampled;

    // Register file memory: 32 registers (x0–x31)
    reg [31:0] register [0:31];
    integer i;

    // Write logic with reset
    always @(posedge Clk_In) begin
        if (Rst_In) begin
            for (i = 0; i < 32; i = i + 1) begin
                register[i] <= 32'h00000000;
            end
        end
        else if (WrEn_In && Des_Addr_In != 5'd0) begin
            register[0] <= 32'b0;  // x0 is always 0
            register[Des_Addr_In] <= Des_Data_In;
        end
    end

    // Read logic
    always @(posedge Clk_In) begin
        Src_Addr1_Sampled <= Src_Addr1_In;
        Src_Addr2_Sampled <= Src_Addr2_In;
        Temp_Src_Data1 <= register[Src_Addr1_In];
        Temp_Src_Data2 <= register[Src_Addr2_In];
    end

    // Forwarding logic to resolve write-after-read hazard.
    // Compare against sampled read addresses so forwarding applies to the
    // same instruction whose data was captured into Temp_Src_Data*.
    assign Src_Data1_Out =
        (WrEn_In && (Src_Addr1_Sampled == Des_Addr_In) && (Des_Addr_In != 5'd0))
            ? Des_Data_In : Temp_Src_Data1;
    assign Src_Data2_Out =
        (WrEn_In && (Src_Addr2_Sampled == Des_Addr_In) && (Des_Addr_In != 5'd0))
            ? Des_Data_In : Temp_Src_Data2;

endmodule
