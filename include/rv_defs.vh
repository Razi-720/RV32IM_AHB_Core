`ifndef RV_DEFS_VH
`define RV_DEFS_VH

// ---------------------------------------------------------------------------
// Shared global definitions for RV32I core + AHB-lite integration
// ---------------------------------------------------------------------------

// AHB-lite HTRANS encoding
`define AHB_HTRANS_IDLE    2'b00
`define AHB_HTRANS_BUSY    2'b01
`define AHB_HTRANS_NONSEQ  2'b10
`define AHB_HTRANS_SEQ     2'b11

// AHB-lite HSIZE encoding
`define AHB_HSIZE_BYTE      3'b000
`define AHB_HSIZE_HALFWORD  3'b001
`define AHB_HSIZE_WORD      3'b010

// Internal memory access size encoding (2-bit width selectors in pipeline)
`define MEM_SIZE_BYTE      2'b00
`define MEM_SIZE_HALFWORD  2'b01
`define MEM_SIZE_WORD      2'b10

// ═══════════════════════════════════════════════════════════
// SoC Memory Map (STM32-style dual-bus architecture)
// ═══════════════════════════════════════════════════════════

// IAHB (Instruction Bus) - Single slave
`define ITCM_BASE_ADDR     32'h0000_0000
`define ITCM_MASK          32'hFFFF_0000  // 64KB

// DAHB (Data Bus) - Multiple slaves
`define DTCM_BASE_ADDR     32'h2000_0000
`define DTCM_MASK          32'hFFFF_0000  // 64KB

`define APB_BASE_ADDR      32'h4000_0000
`define APB_MASK           32'hFFFF_0000  // 64KB total APB space

// APB Peripheral offsets (within APB bridge space)
`define UART_OFFSET        32'h0000_0000  // 0x4000_0000
`define GPIO_OFFSET        32'h0000_1000  // 0x4000_1000
`define TIMER_OFFSET       32'h0000_2000  // 0x4000_2000
`define APB_PERIPH_MASK    32'hFFFF_F000  // 4KB per peripheral

// Slave select encoding (for data bus)
`define AHB_SLAVE_DTCM     2'd0
`define AHB_SLAVE_APB      2'd1
`define AHB_SLAVE_DEFAULT  2'd2  // Error response

`endif
