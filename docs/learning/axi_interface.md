# AXI Interface for Attention Accelerator - Learning Document
**Module:** axi_attention_wrapper  
**Date:** 2026-04-03  
**Purpose:** Understand AXI protocol and memory-mapped control

---

## What is AXI?

**AXI (Advanced eXtensible Interface)** is ARM's standard bus protocol for connecting IP blocks in SoC designs. It's part of the AMBA (Advanced Microcontroller Bus Architecture) specification.

### Why AXI for Zynq?

The Zynq-7020 has:
- **Processing System (PS):** Dual-core ARM Cortex-A9
- **Programmable Logic (PL):** FPGA fabric

**AXI connects PS to PL**, allowing the ARM processor to:
1. Configure the accelerator (write control registers)
2. Start/stop computation (write command register)
3. Check status (read status register)
4. Access results (read from memory)

---

## AXI Protocol Variants

### AXI4-Full (High Performance)
- Full read/write channels
- Burst transfers
- Out-of-order completion
- **Use case:** High-bandwidth data transfers

### AXI4-Lite (Simple Control)
- Single transaction per request
- No burst support
- In-order completion
- **Use case:** Register access, control/status ✓ (We'll use this)

### AXI4-Stream (Data Flow)
- No addresses (streaming data)
- Continuous data flow
- **Use case:** Video, DSP pipelines

**For our accelerator:** AXI4-Lite for control, direct BRAM access for data

---

## AXI4-Lite Signals

### Write Address Channel (AW)
```
AWADDR[31:0]  - Write address
AWVALID       - Address valid (master → slave)
AWREADY       - Address ready (slave → master)
AWPROT[2:0]   - Protection type (usually ignored)
```

### Write Data Channel (W)
```
WDATA[31:0]   - Write data
WSTRB[3:0]    - Byte strobe (which bytes to write)
WVALID        - Data valid (master → slave)
WREADY        - Data ready (slave → master)
```

### Write Response Channel (B)
```
BRESP[1:0]    - Write response (00=OK, 01=EXOKAY, 10=SLVERR, 11=DECERR)
BVALID        - Response valid (slave → master)
BREADY        - Response ready (master → slave)
```

### Read Address Channel (AR)
```
ARADDR[31:0]  - Read address
ARVALID       - Address valid (master → slave)
ARREADY       - Address ready (slave → master)
ARPROT[2:0]   - Protection type (usually ignored)
```

### Read Data Channel (R)
```
RDATA[31:0]   - Read data
RRESP[1:0]    - Read response (00=OK, 01=EXOKAY, 10=SLVERR, 11=DECERR)
RVALID        - Data valid (slave → master)
RREADY        - Data ready (master → slave)
```

**Total:** 5 channels, 22 signals (for 32-bit data)

---

## AXI Handshake Protocol

### Basic Handshake

**Rule:** Transaction occurs when VALID and READY are both HIGH

```
Master asserts VALID (data/address available)
Slave asserts READY (can accept data/address)
Transaction completes on clock edge when both HIGH
```

### Timing Diagrams

**Write Transaction:**
```
Clock:    __|‾|__|‾|__|‾|__|‾|__|‾|__
AWVALID:  ______|‾‾‾‾‾‾‾‾‾‾|________
AWREADY:  __________|‾‾‾‾‾‾|________
AWADDR:   ------< ADDR >------------
          
WVALID:   ______|‾‾‾‾‾‾‾‾‾‾|________
WREADY:   __________|‾‾‾‾‾‾|________
WDATA:    ------< DATA >------------

BVALID:   ______________|‾‾‾‾|______
BREADY:   ______________|‾‾‾‾|______
BRESP:    --------------< OK >------
```

**Read Transaction:**
```
Clock:    __|‾|__|‾|__|‾|__|‾|__|‾|__
ARVALID:  ______|‾‾‾‾‾‾‾‾‾‾|________
ARREADY:  __________|‾‾‾‾‾‾|________
ARADDR:   ------< ADDR >------------

RVALID:   ______________|‾‾‾‾|______
RREADY:   ______________|‾‾‾‾|______
RDATA:    --------------< DATA >----
RRESP:    --------------< OK >------
```

### Key Rules

1. **VALID must not depend on READY**
   - Master can assert VALID before slave asserts READY
   - Prevents combinational loops

2. **READY can depend on VALID**
   - Slave can wait for VALID before asserting READY
   - Allows slave to prepare for transaction

3. **VALID must stay HIGH until handshake**
   - Once asserted, VALID cannot drop until READY is HIGH
   - Ensures transaction completes

4. **Data must be stable when VALID is HIGH**
   - Address/data cannot change while VALID is asserted
   - Ensures data integrity

---

## Memory-Mapped Registers

### Register Map Design

For our attention accelerator, we need:

**Control Registers (Write):**
- Start computation
- Reset accelerator
- Configure parameters (L, D, scale_shift)

**Status Registers (Read):**
- Done flag
- Busy flag
- Error flags
- Cycle count

**Configuration Registers (Read/Write):**
- Q matrix base address
- K matrix base address
- V matrix base address
- Output base address

### Address Decoding

**Example Register Map:**
```
Address    | Register          | Access | Description
-----------|-------------------|--------|---------------------------
0x00       | CTRL              | W      | Control register
0x04       | STATUS            | R      | Status register
0x08       | CONFIG            | RW     | Configuration register
0x0C       | CYCLE_COUNT       | R      | Cycle counter
0x10       | Q_BASE_ADDR       | RW     | Q matrix address
0x14       | K_BASE_ADDR       | RW     | K matrix address
0x18       | V_BASE_ADDR       | RW     | V matrix address
0x1C       | OUT_BASE_ADDR     | RW     | Output address
```

**Address Decoding Logic:**
```verilog
wire [3:0] reg_addr = AWADDR[5:2];  // Word-aligned addresses

case (reg_addr)
    4'h0: // CTRL register
    4'h1: // STATUS register
    4'h2: // CONFIG register
    // ...
endcase
```

---

## Register Bit Fields

### CTRL Register (0x00) - Write Only

```
Bit 31-2: Reserved (write 0)
Bit 1:    RESET - Reset accelerator (self-clearing)
Bit 0:    START - Start computation (self-clearing)
```

**Usage:**
```c
// Start computation
*CTRL_REG = 0x00000001;

// Reset accelerator
*CTRL_REG = 0x00000002;
```

### STATUS Register (0x04) - Read Only

```
Bit 31-3: Reserved
Bit 2:    ERROR - Error occurred
Bit 1:    BUSY - Computation in progress
Bit 0:    DONE - Computation complete
```

**Usage:**
```c
// Poll for completion
while ((*STATUS_REG & 0x1) == 0) {
    // Wait for DONE bit
}

// Check for errors
if (*STATUS_REG & 0x4) {
    // Handle error
}
```

### CONFIG Register (0x08) - Read/Write

```
Bit 31-8: Reserved
Bit 7-4:  L - Sequence length (4 bits, 1-16)
Bit 3-0:  SCALE_SHIFT - Scaling factor (3 bits, 0-7)
```

**Usage:**
```c
// Configure L=8, scale_shift=3
*CONFIG_REG = (8 << 4) | 3;
```

### CYCLE_COUNT Register (0x0C) - Read Only

```
Bit 31-0: CYCLE_COUNT - Number of cycles for last computation
```

**Usage:**
```c
// Read cycle count
uint32_t cycles = *CYCLE_COUNT_REG;
printf("Computation took %u cycles\n", cycles);
```

---

## Data Transfer Methods

### Method 1: Direct BRAM Access (Recommended)

**Approach:** ARM writes Q, K, V directly to BRAM via AXI

**Advantages:**
- Simple hardware (no DMA needed)
- Low latency
- Easy to debug

**Disadvantages:**
- ARM must write all data (512 bytes × 3 = 1.5 KB)
- Blocks ARM during transfer

**Implementation:**
```
PS (ARM) ──AXI──> BRAM Controller ──> Q/K/V BRAMs
                                          │
                                          └──> Attention Accelerator
```

### Method 2: DMA Transfer (High Performance)

**Approach:** DMA engine transfers data from DDR to BRAM

**Advantages:**
- ARM can do other work during transfer
- Higher throughput
- Scalable to large matrices

**Disadvantages:**
- Complex hardware (DMA controller needed)
- More resources
- Harder to debug

**Implementation:**
```
PS (ARM) ──AXI──> DMA Controller ──AXI Stream──> BRAM
                                                    │
                                                    └──> Attention Accelerator
```

**For our design:** Use Method 1 (direct BRAM access) for simplicity

---

## Software Flow

### Typical Usage Sequence

```c
// 1. Configure accelerator
*CONFIG_REG = (L << 4) | scale_shift;
*Q_BASE_ADDR_REG = q_addr;
*K_BASE_ADDR_REG = k_addr;
*V_BASE_ADDR_REG = v_addr;
*OUT_BASE_ADDR_REG = out_addr;

// 2. Write input matrices to BRAM
memcpy((void*)Q_BASE_ADDR, q_matrix, L*D);
memcpy((void*)K_BASE_ADDR, k_matrix, L*D);
memcpy((void*)V_BASE_ADDR, v_matrix, L*D);

// 3. Start computation
*CTRL_REG = 0x1;

// 4. Wait for completion
while ((*STATUS_REG & 0x1) == 0) {
    // Poll or use interrupt
}

// 5. Check for errors
if (*STATUS_REG & 0x4) {
    printf("Error occurred!\n");
    return -1;
}

// 6. Read results from BRAM
memcpy(output, (void*)OUT_BASE_ADDR, L*D);

// 7. Read performance metrics
uint32_t cycles = *CYCLE_COUNT_REG;
printf("Completed in %u cycles (%.2f us)\n", 
       cycles, cycles * 0.01);  // @ 100 MHz
```

---

## Interrupt Support (Optional)

### Interrupt Signal

Instead of polling STATUS register, use interrupt:

```verilog
output reg irq;  // Interrupt request to PS

always @(posedge clk) begin
    if (done && !done_prev) begin
        irq <= 1'b1;  // Assert on done rising edge
    end else if (irq_clear) begin
        irq <= 1'b0;  // Clear when software acknowledges
    end
end
```

### Software Handler

```c
void attention_irq_handler(void) {
    // Read status
    uint32_t status = *STATUS_REG;
    
    // Clear interrupt
    *CTRL_REG = 0x4;  // IRQ_CLEAR bit
    
    // Process completion
    if (status & 0x1) {
        // Computation done
        process_results();
    }
}
```

---

## Performance Considerations

### Register Access Latency

**AXI4-Lite transaction:** ~2-3 cycles
- 1 cycle: Address phase
- 1 cycle: Data phase
- 1 cycle: Response phase

**Impact:** Negligible compared to computation time (1,752 cycles)

### Data Transfer Bandwidth

**BRAM write bandwidth:**
- 32-bit AXI: 4 bytes/cycle
- @ 100 MHz: 400 MB/s

**Transfer time for one attention:**
- Input: 1.5 KB (Q+K+V)
- Time: 1,500 / 4 = 375 cycles = 3.75 μs
- Output: 0.5 KB
- Time: 500 / 4 = 125 cycles = 1.25 μs
- **Total transfer: 5 μs**

**Computation time:** 17.5 μs

**Efficiency:** 17.5 / (17.5 + 5) = 78% (computation vs total)

### Optimization: Wider AXI

**Use 64-bit or 128-bit AXI:**
- 64-bit: 8 bytes/cycle → 2.5 μs transfer
- 128-bit: 16 bytes/cycle → 1.25 μs transfer
- Efficiency: 17.5 / (17.5 + 1.25) = 93%

---

## Key Concepts to Understand

Before proceeding to design, ensure you understand:

1. **AXI handshake protocol**
   - VALID/READY mechanism
   - Transaction completion rules

2. **Memory-mapped registers**
   - Address decoding
   - Read/write access control
   - Bit field definitions

3. **Data transfer methods**
   - Direct BRAM access vs DMA
   - Trade-offs and use cases

4. **Software integration**
   - Register access from C code
   - Polling vs interrupts
   - Error handling

5. **Performance impact**
   - Transfer time vs computation time
   - Bandwidth requirements
   - Optimization strategies

---

## Self-Check Questions

Before moving to design phase, answer these:

1. **What are the 5 AXI4-Lite channels?**
   - Answer: AW (write address), W (write data), B (write response), AR (read address), R (read data)

2. **When does an AXI transaction complete?**
   - Answer: When both VALID and READY are HIGH on the same clock edge

3. **Why use AXI4-Lite instead of AXI4-Full?**
   - Answer: Simpler for register access, no burst support needed

4. **What registers do we need for control?**
   - Answer: CTRL (start/reset), STATUS (done/busy/error), CONFIG (parameters)

5. **What is the data transfer overhead?**
   - Answer: ~5 μs for 2 KB transfer @ 100 MHz with 32-bit AXI

---

## Next Steps

After confirming understanding:
1. Design the AXI wrapper architecture
2. Specify register map in detail
3. Analyze timing and performance
4. Implement AXI slave interface RTL
5. Create testbench for AXI transactions
6. Write C driver code

---

**Status:** Teaching complete - ready for design phase  
**User Action Required:** Confirm understanding before proceeding to design
