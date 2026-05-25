/**
 * @file attention_accel.h
 * @brief Driver for Streaming Attention Accelerator v4
 *
 * This driver provides a C API for controlling the attention accelerator
 * via AXI4-Lite memory-mapped registers.
 *
 * @author Generated for streaming-attention-accelerator project
 * @date 2026-04-03
 */

#ifndef ATTENTION_ACCEL_H
#define ATTENTION_ACCEL_H

#include <stdint.h>
#include <stdbool.h>

//==============================================================================
// Register Offsets
//==============================================================================

#define ATTN_REG_CTRL           0x00    ///< Control register (W)
#define ATTN_REG_STATUS         0x04    ///< Status register (R)
#define ATTN_REG_CONFIG         0x08    ///< Configuration register (RW)
#define ATTN_REG_CYCLE_CNT      0x0C    ///< Cycle counter (R)
#define ATTN_REG_Q_ADDR         0x10    ///< Q matrix base address (RW)
#define ATTN_REG_K_ADDR         0x14    ///< K matrix base address (RW)
#define ATTN_REG_V_ADDR         0x18    ///< V matrix base address (RW)
#define ATTN_REG_OUT_ADDR       0x1C    ///< Output base address (RW)
#define ATTN_REG_VERSION        0x20    ///< Version register (R)
#define ATTN_REG_FEATURES       0x24    ///< Features register (R)

//==============================================================================
// Register Bit Definitions
//==============================================================================

// CTRL register bits
#define ATTN_CTRL_START         (1 << 0)    ///< Start computation
#define ATTN_CTRL_RESET         (1 << 1)    ///< Software reset
#define ATTN_CTRL_IRQ_CLEAR     (1 << 2)    ///< Clear interrupt

// STATUS register bits
#define ATTN_STATUS_DONE        (1 << 0)    ///< Computation complete
#define ATTN_STATUS_BUSY        (1 << 1)    ///< Computation in progress
#define ATTN_STATUS_ERROR       (1 << 2)    ///< Error occurred
#define ATTN_STATUS_IRQ         (1 << 3)    ///< Interrupt pending

// CONFIG register fields
#define ATTN_CONFIG_SCALE_SHIFT_MASK    0x0E    ///< Scale shift mask (bits 3:1)
#define ATTN_CONFIG_SCALE_SHIFT_SHIFT   1       ///< Scale shift bit position
#define ATTN_CONFIG_L_MASK              0xF0    ///< L mask (bits 7:4)
#define ATTN_CONFIG_L_SHIFT             4       ///< L bit position

//==============================================================================
// Constants
//==============================================================================

#define ATTN_MAX_L              16      ///< Maximum sequence length
#define ATTN_MAX_D              64      ///< Maximum embedding dimension
#define ATTN_TILE_WIDTH         16      ///< Tile width
#define ATTN_TIMEOUT_MS         1000    ///< Default timeout (ms)

//==============================================================================
// Data Structures
//==============================================================================

/**
 * @brief Attention accelerator device structure
 */
typedef struct {
    volatile uint32_t *base_addr;   ///< Base address of AXI registers
    uint32_t q_mem_addr;             ///< Q matrix memory address
    uint32_t k_mem_addr;             ///< K matrix memory address
    uint32_t v_mem_addr;             ///< V matrix memory address
    uint32_t out_mem_addr;           ///< Output memory address
    uint8_t L;                       ///< Sequence length
    uint8_t D;                       ///< Embedding dimension
    uint8_t scale_shift;             ///< Scaling factor
} attn_device_t;

/**
 * @brief Attention computation configuration
 */
typedef struct {
    uint8_t L;                       ///< Sequence length (1-16)
    uint8_t D;                       ///< Embedding dimension (16-64)
    uint8_t scale_shift;             ///< Scaling factor (0-7)
    bool use_interrupt;              ///< Use interrupt instead of polling
    uint32_t timeout_ms;             ///< Timeout in milliseconds
} attn_config_t;

/**
 * @brief Attention computation result
 */
typedef struct {
    uint32_t cycle_count;            ///< Number of cycles taken
    float latency_us;                ///< Latency in microseconds
    bool success;                    ///< Computation successful
    bool timeout;                    ///< Timeout occurred
    bool error;                      ///< Error occurred
} attn_result_t;

//==============================================================================
// Function Prototypes
//==============================================================================

/**
 * @brief Initialize attention accelerator device
 *
 * @param dev Pointer to device structure
 * @param base_addr Base address of AXI registers
 * @param q_mem Q matrix memory address
 * @param k_mem K matrix memory address
 * @param v_mem V matrix memory address
 * @param out_mem Output memory address
 * @return 0 on success, negative on error
 */
int attn_init(attn_device_t *dev,
              volatile uint32_t *base_addr,
              uint32_t q_mem,
              uint32_t k_mem,
              uint32_t v_mem,
              uint32_t out_mem);

/**
 * @brief Configure attention accelerator
 *
 * @param dev Pointer to device structure
 * @param config Pointer to configuration structure
 * @return 0 on success, negative on error
 */
int attn_configure(attn_device_t *dev, const attn_config_t *config);

/**
 * @brief Reset attention accelerator
 *
 * @param dev Pointer to device structure
 * @return 0 on success, negative on error
 */
int attn_reset(attn_device_t *dev);

/**
 * @brief Start attention computation
 *
 * @param dev Pointer to device structure
 * @return 0 on success, negative on error
 */
int attn_start(attn_device_t *dev);

/**
 * @brief Wait for computation to complete
 *
 * @param dev Pointer to device structure
 * @param timeout_ms Timeout in milliseconds (0 = infinite)
 * @return 0 on success, -1 on timeout, -2 on error
 */
int attn_wait(attn_device_t *dev, uint32_t timeout_ms);

/**
 * @brief Check if computation is complete
 *
 * @param dev Pointer to device structure
 * @return true if done, false otherwise
 */
bool attn_is_done(attn_device_t *dev);

/**
 * @brief Check if accelerator is busy
 *
 * @param dev Pointer to device structure
 * @return true if busy, false otherwise
 */
bool attn_is_busy(attn_device_t *dev);

/**
 * @brief Get computation result
 *
 * @param dev Pointer to device structure
 * @param result Pointer to result structure
 * @return 0 on success, negative on error
 */
int attn_get_result(attn_device_t *dev, attn_result_t *result);

/**
 * @brief Read version information
 *
 * @param dev Pointer to device structure
 * @param major Pointer to store major version
 * @param minor Pointer to store minor version
 * @return 0 on success, negative on error
 */
int attn_get_version(attn_device_t *dev, uint16_t *major, uint16_t *minor);

/**
 * @brief Read feature information
 *
 * @param dev Pointer to device structure
 * @param max_L Pointer to store maximum L
 * @param max_D Pointer to store maximum D
 * @param tile_width Pointer to store tile width
 * @return 0 on success, negative on error
 */
int attn_get_features(attn_device_t *dev,
                      uint8_t *max_L,
                      uint8_t *max_D,
                      uint8_t *tile_width);

/**
 * @brief Compute attention (high-level API)
 *
 * This function performs a complete attention computation:
 * 1. Writes Q, K, V matrices to memory
 * 2. Starts computation
 * 3. Waits for completion
 * 4. Reads output
 *
 * @param dev Pointer to device structure
 * @param Q Query matrix (L×D, INT8)
 * @param K Key matrix (L×D, INT8)
 * @param V Value matrix (L×D, INT8)
 * @param output Output matrix (L×D, INT8)
 * @param result Pointer to result structure (can be NULL)
 * @return 0 on success, negative on error
 */
int attn_compute(attn_device_t *dev,
                 const int8_t *Q,
                 const int8_t *K,
                 const int8_t *V,
                 int8_t *output,
                 attn_result_t *result);

/**
 * @brief Clear interrupt flag
 *
 * @param dev Pointer to device structure
 * @return 0 on success, negative on error
 */
int attn_clear_interrupt(attn_device_t *dev);

/**
 * @brief Print device information
 *
 * @param dev Pointer to device structure
 */
void attn_print_info(attn_device_t *dev);

/**
 * @brief Print result information
 *
 * @param result Pointer to result structure
 */
void attn_print_result(const attn_result_t *result);

//==============================================================================
// Register Access Macros
//==============================================================================

/**
 * @brief Write to register
 */
#define ATTN_WRITE_REG(dev, offset, value) \
    ((dev)->base_addr[(offset) >> 2] = (value))

/**
 * @brief Read from register
 */
#define ATTN_READ_REG(dev, offset) \
    ((dev)->base_addr[(offset) >> 2])

/**
 * @brief Write to memory
 */
#define ATTN_WRITE_MEM(addr, data, size) \
    memcpy((void*)(addr), (data), (size))

/**
 * @brief Read from memory
 */
#define ATTN_READ_MEM(data, addr, size) \
    memcpy((data), (void*)(addr), (size))

#endif // ATTENTION_ACCEL_H
