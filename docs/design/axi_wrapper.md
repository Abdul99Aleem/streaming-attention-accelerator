# AXI Interface for Attention Accelerator - Design Document
**Module:** axi_attention_wrapper  
**Date:** 2026-04-03  
**Purpose:** Detailed AXI4-Lite slave interface specification

---

## Design Overview

**Module Name:** `axi_attention_wrapper`  
**Purpose:** AXI4-Lite slave interface wrapper for streaming_attention_v4  
**Protocol:** AXI4-Lite (simplified register access)  
**Data Width:** 32 bits  
**Address Width:** 32 bits (byte-addressable)

### Design Goals

1. **Simplicity:** Easy to integrate with Zynq PS
2. **Standard Compliance:** Full AXI4-Lite protocol support
3. **Performance:** Minimal latency for register access
4. **Debuggability:** Clear status and error reporting

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                  axi_attention_wrapper                      │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │           AXI4-Lite Slave Interface                  │  │
│  │  - Write Address Channel (AW)                        │  │
│  │  - Write Data Channel (W)                            │  │
│  │  - Write Response Channel (B)                        │  │
│  │  - Read Address Channel (AR)                         │  │
│  │  - Read Data Channel (R)                             │  │
│  └──────────────────────────────────────────────────────┘  │
│                          │                                  │
│                          ▼                                  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              Register Bank                           │  │
│  │  0x00: CTRL       (W)  - Control register            │  │
│  │  0x04: STATUS     (R)  - Status register             │  │
│  │  0x08: CONFIG     (RW) - Configuration               │  │
│  │  0x0C: CYCLE_CNT  (R)  - Cycle counter               │  │
│  │  0x10: Q_ADDR     (RW) - Q matrix base address       │  │
│  │  0x14: K_ADDR     (RW) - K matrix base address       │  │
│  │  0x18: V_ADDR     (RW) - V matrix base address       │  │
│  │  0x1C: OUT_ADDR   (RW) - Output base address         │  │
│  └──────────────────────────────────────────────────────┘  │
│                          │                                  │
│                          ▼                                  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │         Control Logic & State Machine                │  │
│  │  - Start/reset control                               │  │
│  │  - Status monitoring                                 │  │
│  │  - Cycle counting                                    │  │
│  └──────────────────────────────────────────────────────┘  │
│                          │                                  │
│                          ▼                                  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │       streaming_attention_v4 Instance                │  │
│  │  - Tiled attention computation                       │  │
│  │  - 16-way parallel processing                        │  │
│  └──────────────────────────────────────────────────────┘  │
│                          │                                  │
│                          ▼                                  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              BRAM Controllers                        │  │
│  │  - Q matrix BRAM (512 bytes)                         │  │
│  │  - K matrix BRAM (512 bytes)                         │  │
│  │  - V matrix BRAM (512 bytes)                         │  │
│  │  - Output BRAM (512 bytes)                           │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Module Interface

### AXI4-Lite Slave Ports

```verilog
module axi_attention_wrapper #(
    parameter C_S_AXI_DATA_WIDTH = 32,
    parameter C_S_AXI_ADDR_WIDTH = 32,
    parameter L = 8,
    parameter D = 64,
    parameter TILE_WIDTH = 16
)(
    // Global signals
    input  wire S_AXI_ACLK,
    input  wire S_AXI_ARESETN,
    
    // Write address channel
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] S_AXI_AWADDR,
    input  wire [2:0]                     S_AXI_AWPROT,
    input  wire                           S_AXI_AWVALID,
    output wire                           S_AXI_AWREADY,
    
    // Write data channel
    input  wire [C_S_AXI_DATA_WIDTH-1:0] S_AXI_WDATA,
    input  wire [3:0]                     S_AXI_WSTRB,
    input  wire                           S_AXI_WVALID,
    output wire                           S_AXI_WREADY,
    
    // Write response channel
    output wire [1:0]                     S_AXI_BRESP,
    output wire                           S_AXI_BVALID,
    input  wire                           S_AXI_BREADY,
    
    // Read address channel
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] S_AXI_ARADDR,
    input  wire [2:0]                     S_AXI_ARPROT,
    input  wire                           S_AXI_ARVALID,
    output wire                           S_AXI_ARREADY,
    
    // Read data channel
    output wire [C_S_AXI_DATA_WIDTH-1:0] S_AXI_RDATA,
    output wire [1:0]                     S_AXI_RRESP,
    output wire                           S_AXI_RVALID,
    input  wire                           S_AXI_RREADY,
    
    // Optional interrupt
    output wire                           IRQ
);
```

---

## Register Map

### Complete Register Specification

| Offset | Name | Access | Reset | Description |
|--------|------|--------|-------|-------------|
| 0x00 | CTRL | W | 0x0 | Control register |
| 0x04 | STATUS | R | 0x0 | Status register |
| 0x08 | CONFIG | RW | 0x83 | Configuration (L=8, shift=3) |
| 0x0C | CYCLE_CNT | R | 0x0 | Cycle counter |
| 0x10 | Q_ADDR | RW | 0x0 | Q matrix base address |
| 0x14 | K_ADDR | RW | 0x0 | K matrix base address |
| 0x18 | V_ADDR | RW | 0x0 | V matrix base address |
| 0x1C | OUT_ADDR | RW | 0x0 | Output base address |
| 0x20 | VERSION | R | 0x00040000 | Version (major.minor) |
| 0x24 | FEATURES | R | 0x00001040 | Features (L=16, D=64) |

### Register Bit Fields

**CTRL Register (0x00) - Write Only**
```
Bit 31-3: Reserved (write 0)
Bit 2:    IRQ_CLEAR - Clear interrupt flag
Bit 1:    RESET - Software reset (self-clearing)
Bit 0:    START - Start computation (self-clearing)
```

**STATUS Register (0x04) - Read Only**
```
Bit 31-4: Reserved
Bit 3:    IRQ_PENDING - Interrupt pending
Bit 2:    ERROR - Error occurred
Bit 1:    BUSY - Computation in progress
Bit 0:    DONE - Computation complete
```

**CONFIG Register (0x08) - Read/Write**
```
Bit 31-8: Reserved
Bit 7-4:  L - Sequence length (1-16)
Bit 3-1:  SCALE_SHIFT - Scaling factor (0-7)
Bit 0:    Reserved
```

**CYCLE_CNT Register (0x0C) - Read Only**
```
Bit 31-0: CYCLE_COUNT - Cycles for last computation
```

**Q_ADDR Register (0x10) - Read/Write**
```
Bit 31-0: Q_BASE_ADDR - Q matrix base address in memory
```

**K_ADDR Register (0x14) - Read/Write**
```
Bit 31-0: K_BASE_ADDR - K matrix base address in memory
```

**V_ADDR Register (0x18) - Read/Write**
```
Bit 31-0: V_BASE_ADDR - V matrix base address in memory
```

**OUT_ADDR Register (0x1C) - Read/Write**
```
Bit 31-0: OUT_BASE_ADDR - Output base address in memory
```

**VERSION Register (0x20) - Read Only**
```
Bit 31-16: MAJOR_VERSION - Major version (0x0004 = v4)
Bit 15-0:  MINOR_VERSION - Minor version (0x0000)
```

**FEATURES Register (0x24) - Read Only**
```
Bit 31-16: MAX_L - Maximum sequence length (16)
Bit 15-8:  MAX_D - Maximum embedding dimension (64)
Bit 7-0:   TILE_WIDTH - Tile width (16)
```

---

## AXI State Machines

### Write State Machine

```verilog
localparam WRITE_IDLE = 2'b00;
localparam WRITE_DATA = 2'b01;
localparam WRITE_RESP = 2'b10;

reg [1:0] write_state;
reg [C_S_AXI_ADDR_WIDTH-1:0] write_addr;

always @(posedge S_AXI_ACLK) begin
    if (!S_AXI_ARESETN) begin
        write_state <= WRITE_IDLE;
        write_addr <= 0;
    end else begin
        case (write_state)
            WRITE_IDLE: begin
                if (S_AXI_AWVALID && S_AXI_AWREADY) begin
                    write_addr <= S_AXI_AWADDR;
                    write_state <= WRITE_DATA;
                end
            end
            
            WRITE_DATA: begin
                if (S_AXI_WVALID && S_AXI_WREADY) begin
                    // Write to register
                    write_register(write_addr, S_AXI_WDATA, S_AXI_WSTRB);
                    write_state <= WRITE_RESP;
                end
            end
            
            WRITE_RESP: begin
                if (S_AXI_BVALID && S_AXI_BREADY) begin
                    write_state <= WRITE_IDLE;
                end
            end
        endcase
    end
end
```

### Read State Machine

```verilog
localparam READ_IDLE = 2'b00;
localparam READ_DATA = 2'b01;

reg [1:0] read_state;
reg [C_S_AXI_ADDR_WIDTH-1:0] read_addr;

always @(posedge S_AXI_ACLK) begin
    if (!S_AXI_ARESETN) begin
        read_state <= READ_IDLE;
        read_addr <= 0;
    end else begin
        case (read_state)
            READ_IDLE: begin
                if (S_AXI_ARVALID && S_AXI_ARREADY) begin
                    read_addr <= S_AXI_ARADDR;
                    read_state <= READ_DATA;
                end
            end
            
            READ_DATA: begin
                if (S_AXI_RVALID && S_AXI_RREADY) begin
                    read_state <= READ_IDLE;
                end
            end
        endcase
    end
end
```

---

## Register Access Logic

### Write Logic

```verilog
task write_register;
    input [C_S_AXI_ADDR_WIDTH-1:0] addr;
    input [C_S_AXI_DATA_WIDTH-1:0] data;
    input [3:0] strb;
    
    reg [3:0] reg_addr;
    begin
        reg_addr = addr[5:2];  // Word-aligned
        
        case (reg_addr)
            4'h0: begin  // CTRL
                if (strb[0]) begin
                    ctrl_start <= data[0];
                    ctrl_reset <= data[1];
                    ctrl_irq_clear <= data[2];
                end
            end
            
            4'h2: begin  // CONFIG
                if (strb[0]) begin
                    config_scale_shift <= data[3:1];
                end
                if (strb[1]) begin
                    config_L <= data[7:4];
                end
            end
            
            4'h4: q_base_addr <= data;      // Q_ADDR
            4'h5: k_base_addr <= data;      // K_ADDR
            4'h6: v_base_addr <= data;      // V_ADDR
            4'h7: out_base_addr <= data;    // OUT_ADDR
            
            default: begin
                // Invalid address - ignore
            end
        endcase
    end
endtask
```

### Read Logic

```verilog
function [C_S_AXI_DATA_WIDTH-1:0] read_register;
    input [C_S_AXI_ADDR_WIDTH-1:0] addr;
    
    reg [3:0] reg_addr;
    begin
        reg_addr = addr[5:2];
        
        case (reg_addr)
            4'h1: read_register = {28'b0, status_irq, status_error, 
                                   status_busy, status_done};  // STATUS
            4'h2: read_register = {24'b0, config_L, config_scale_shift, 1'b0};  // CONFIG
            4'h3: read_register = cycle_count;  // CYCLE_CNT
            4'h4: read_register = q_base_addr;  // Q_ADDR
            4'h5: read_register = k_base_addr;  // K_ADDR
            4'h6: read_register = v_base_addr;  // V_ADDR
            4'h7: read_register = out_base_addr;  // OUT_ADDR
            4'h8: read_register = 32'h00040000;  // VERSION (v4.0)
            4'h9: read_register = {16'd16, 8'd64, 8'd16};  // FEATURES
            
            default: read_register = 32'hDEADBEEF;  // Invalid address
        endcase
    end
endfunction
```

---

## Control Logic

### Start/Reset Control

```verilog
reg accel_start;
reg accel_reset_n;

always @(posedge S_AXI_ACLK) begin
    if (!S_AXI_ARESETN) begin
        accel_start <= 1'b0;
        accel_reset_n <= 1'b0;
    end else begin
        // Reset is active low, self-clearing
        if (ctrl_reset) begin
            accel_reset_n <= 1'b0;
        end else begin
            accel_reset_n <= 1'b1;
        end
        
        // Start is self-clearing (pulse)
        if (ctrl_start && !status_busy) begin
            accel_start <= 1'b1;
        end else begin
            accel_start <= 1'b0;
        end
    end
end
```

### Status Monitoring

```verilog
always @(posedge S_AXI_ACLK) begin
    if (!S_AXI_ARESETN) begin
        status_done <= 1'b0;
        status_busy <= 1'b0;
        status_error <= 1'b0;
    end else begin
        // Update from accelerator
        status_done <= accel_done;
        status_busy <= accel_busy;
        
        // Error detection (placeholder)
        status_error <= 1'b0;  // No error conditions yet
    end
end
```

### Cycle Counter

```verilog
reg [31:0] cycle_counter;

always @(posedge S_AXI_ACLK) begin
    if (!S_AXI_ARESETN || ctrl_reset) begin
        cycle_counter <= 32'b0;
        cycle_count <= 32'b0;
    end else begin
        if (accel_start) begin
            cycle_counter <= 32'b0;
        end else if (status_busy) begin
            cycle_counter <= cycle_counter + 1;
        end else if (status_done && !status_done_prev) begin
            cycle_count <= cycle_counter;
        end
    end
end
```

### Interrupt Generation

```verilog
reg irq_pending;

always @(posedge S_AXI_ACLK) begin
    if (!S_AXI_ARESETN || ctrl_reset) begin
        irq_pending <= 1'b0;
    end else begin
        if (status_done && !status_done_prev) begin
            irq_pending <= 1'b1;  // Set on completion
        end else if (ctrl_irq_clear) begin
            irq_pending <= 1'b0;  // Clear on software request
        end
    end
end

assign IRQ = irq_pending;
assign status_irq = irq_pending;
```

---

## Accelerator Integration

### Instantiation

```verilog
streaming_attention_v4 #(
    .L(L),
    .D(D),
    .TILE_WIDTH(TILE_WIDTH)
) attention_core (
    .clk(S_AXI_ACLK),
    .rst_n(accel_reset_n),
    .start(accel_start),
    .done(accel_done),
    .busy(accel_busy),
    
    // Memory interfaces
    .q_addr(q_addr_int),
    .q_rd_en(q_rd_en_int),
    .q_data(q_data_int),
    
    .k_addr(k_addr_int),
    .k_rd_en(k_rd_en_int),
    .k_data(k_data_int),
    
    .v_addr(v_addr_int),
    .v_rd_en(v_rd_en_int),
    .v_data(v_data_int),
    
    .out_addr(out_addr_int),
    .out_data(out_data_int),
    .out_wr_en(out_wr_en_int),
    
    .scale_shift(config_scale_shift)
);
```

---

## BRAM Integration

### BRAM Controller Instantiation

```verilog
// Q matrix BRAM (512 bytes = 4096 bits)
blk_mem_gen_0 q_bram (
    .clka(S_AXI_ACLK),
    .ena(q_rd_en_int),
    .wea(1'b0),  // Read-only from accelerator
    .addra(q_addr_int),
    .dina(128'b0),
    .douta(q_data_int),
    
    .clkb(S_AXI_ACLK),
    .enb(q_axi_en),
    .web(q_axi_we),
    .addrb(q_axi_addr),
    .dinb(q_axi_din),
    .doutb(q_axi_dout)
);

// Similar for K, V, and Output BRAMs
```

### AXI to BRAM Bridge

```verilog
// Convert AXI writes to BRAM writes
// This allows ARM to write Q, K, V matrices via AXI
always @(*) begin
    q_axi_en = 1'b0;
    q_axi_we = 4'b0;
    q_axi_addr = 10'b0;
    q_axi_din = 32'b0;
    
    if (S_AXI_AWVALID && (S_AXI_AWADDR >= q_base_addr) && 
        (S_AXI_AWADDR < q_base_addr + 512)) begin
        q_axi_en = 1'b1;
        q_axi_we = S_AXI_WSTRB;
        q_axi_addr = S_AXI_AWADDR - q_base_addr;
        q_axi_din = S_AXI_WDATA;
    end
end
```

---

## Timing Analysis

### AXI Transaction Latency

**Write Transaction:**
```
Cycle 0: AWVALID & AWREADY (address phase)
Cycle 1: WVALID & WREADY (data phase, register write)
Cycle 2: BVALID & BREADY (response phase)
Total: 3 cycles minimum
```

**Read Transaction:**
```
Cycle 0: ARVALID & ARREADY (address phase)
Cycle 1: Register read, RVALID asserted
Cycle 2: RVALID & RREADY (data phase)
Total: 3 cycles minimum
```

### Critical Path

**Longest path:** AXI read address → register mux → read data

**Estimated delay:**
- Address decode: 1 ns
- Register mux: 2 ns
- Output register: 1 ns
- **Total: 4 ns**

**Timing margin @ 100 MHz:**
- Clock period: 10 ns
- Critical path: 4 ns
- **Slack: 6 ns (60% margin)** ✓

---

## Resource Estimates

### Additional Resources for AXI Wrapper

| Resource | AXI Wrapper | v4 Core | Total |
|----------|-------------|---------|-------|
| LUTs | ~500 | 4,000 | 4,500 |
| FFs | ~300 | 5,000 | 5,300 |
| DSP48 | 0 | 16 | 16 |
| BRAM | 0 | 5 | 5 |

**Total Utilization:**
- LUTs: 4,500 / 53,200 = 8.5%
- FFs: 5,300 / 106,400 = 5.0%
- DSP48: 16 / 220 = 7.3%
- BRAM: 5 / 140 = 3.6%

**Conclusion:** AXI wrapper adds minimal overhead (~12% more LUTs/FFs)

---

## Design Validation

### Checklist

- [ ] All AXI signals properly connected
- [ ] Write state machine handles all cases
- [ ] Read state machine handles all cases
- [ ] Register map complete and documented
- [ ] Control logic properly sequences start/reset
- [ ] Status monitoring captures all states
- [ ] Cycle counter accurate
- [ ] Interrupt generation correct
- [ ] BRAM integration functional
- [ ] Timing meets 100 MHz requirement

---

## Next Steps

After design review:
1. Implement AXI wrapper RTL
2. Create AXI testbench (BFM-based)
3. Verify register access
4. Verify accelerator control
5. Create C driver code
6. Test on Zynq hardware (when board available)

---

**Status:** Design complete - ready for implementation  
**Confidence:** HIGH - Standard AXI4-Lite implementation  
**Next Action:** Implement RTL and create driver code
