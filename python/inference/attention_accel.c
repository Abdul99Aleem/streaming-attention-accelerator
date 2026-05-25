/**
 * @file attention_accel.c
 * @brief Driver implementation for Streaming Attention Accelerator v4
 *
 * @author Generated for streaming-attention-accelerator project
 * @date 2026-04-03
 */

#include "attention_accel.h"
#include <string.h>
#include <stdio.h>
#include <unistd.h>

//==============================================================================
// Private Helper Functions
//==============================================================================

/**
 * @brief Get current time in microseconds
 */
static uint64_t get_time_us(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000 + ts.tv_nsec / 1000;
}

/**
 * @brief Sleep for specified microseconds
 */
static void sleep_us(uint32_t us) {
    usleep(us);
}

//==============================================================================
// Public API Implementation
//==============================================================================

int attn_init(attn_device_t *dev,
              volatile uint32_t *base_addr,
              uint32_t q_mem,
              uint32_t k_mem,
              uint32_t v_mem,
              uint32_t out_mem)
{
    if (!dev || !base_addr) {
        return -1;
    }

    // Initialize device structure
    dev->base_addr = base_addr;
    dev->q_mem_addr = q_mem;
    dev->k_mem_addr = k_mem;
    dev->v_mem_addr = v_mem;
    dev->out_mem_addr = out_mem;
    dev->L = 8;              // Default
    dev->D = 64;             // Default
    dev->scale_shift = 3;    // Default (sqrt(64) = 8 = 2^3)

    // Reset accelerator
    attn_reset(dev);

    // Configure base addresses
    ATTN_WRITE_REG(dev, ATTN_REG_Q_ADDR, q_mem);
    ATTN_WRITE_REG(dev, ATTN_REG_K_ADDR, k_mem);
    ATTN_WRITE_REG(dev, ATTN_REG_V_ADDR, v_mem);
    ATTN_WRITE_REG(dev, ATTN_REG_OUT_ADDR, out_mem);

    // Set default configuration
    uint32_t config = (dev->L << ATTN_CONFIG_L_SHIFT) |
                      (dev->scale_shift << ATTN_CONFIG_SCALE_SHIFT_SHIFT);
    ATTN_WRITE_REG(dev, ATTN_REG_CONFIG, config);

    return 0;
}

int attn_configure(attn_device_t *dev, const attn_config_t *config)
{
    if (!dev || !config) {
        return -1;
    }

    // Validate parameters
    if (config->L < 1 || config->L > ATTN_MAX_L) {
        return -2;  // Invalid L
    }
    if (config->D < 16 || config->D > ATTN_MAX_D) {
        return -3;  // Invalid D
    }
    if (config->scale_shift > 7) {
        return -4;  // Invalid scale_shift
    }

    // Update device structure
    dev->L = config->L;
    dev->D = config->D;
    dev->scale_shift = config->scale_shift;

    // Write configuration register
    uint32_t config_val = (config->L << ATTN_CONFIG_L_SHIFT) |
                          (config->scale_shift << ATTN_CONFIG_SCALE_SHIFT_SHIFT);
    ATTN_WRITE_REG(dev, ATTN_REG_CONFIG, config_val);

    return 0;
}

int attn_reset(attn_device_t *dev)
{
    if (!dev) {
        return -1;
    }

    // Assert reset
    ATTN_WRITE_REG(dev, ATTN_REG_CTRL, ATTN_CTRL_RESET);

    // Wait for reset to complete (small delay)
    sleep_us(10);

    return 0;
}

int attn_start(attn_device_t *dev)
{
    if (!dev) {
        return -1;
    }

    // Check if already busy
    if (attn_is_busy(dev)) {
        return -2;  // Already busy
    }

    // Start computation
    ATTN_WRITE_REG(dev, ATTN_REG_CTRL, ATTN_CTRL_START);

    return 0;
}

int attn_wait(attn_device_t *dev, uint32_t timeout_ms)
{
    if (!dev) {
        return -1;
    }

    uint64_t start_time = get_time_us();
    uint64_t timeout_us = (uint64_t)timeout_ms * 1000;

    while (!attn_is_done(dev)) {
        // Check for error
        uint32_t status = ATTN_READ_REG(dev, ATTN_REG_STATUS);
        if (status & ATTN_STATUS_ERROR) {
            return -2;  // Error occurred
        }

        // Check timeout
        if (timeout_ms > 0) {
            uint64_t elapsed = get_time_us() - start_time;
            if (elapsed > timeout_us) {
                return -1;  // Timeout
            }
        }

        // Small delay to avoid hammering the bus
        sleep_us(10);
    }

    return 0;
}

bool attn_is_done(attn_device_t *dev)
{
    if (!dev) {
        return false;
    }

    uint32_t status = ATTN_READ_REG(dev, ATTN_REG_STATUS);
    return (status & ATTN_STATUS_DONE) != 0;
}

bool attn_is_busy(attn_device_t *dev)
{
    if (!dev) {
        return false;
    }

    uint32_t status = ATTN_READ_REG(dev, ATTN_REG_STATUS);
    return (status & ATTN_STATUS_BUSY) != 0;
}

int attn_get_result(attn_device_t *dev, attn_result_t *result)
{
    if (!dev || !result) {
        return -1;
    }

    // Read status
    uint32_t status = ATTN_READ_REG(dev, ATTN_REG_STATUS);

    // Read cycle count
    uint32_t cycles = ATTN_READ_REG(dev, ATTN_REG_CYCLE_CNT);

    // Fill result structure
    result->cycle_count = cycles;
    result->latency_us = cycles * 0.01f;  // @ 100 MHz
    result->success = (status & ATTN_STATUS_DONE) && !(status & ATTN_STATUS_ERROR);
    result->timeout = false;  // Set by caller if timeout occurred
    result->error = (status & ATTN_STATUS_ERROR) != 0;

    return 0;
}

int attn_get_version(attn_device_t *dev, uint16_t *major, uint16_t *minor)
{
    if (!dev || !major || !minor) {
        return -1;
    }

    uint32_t version = ATTN_READ_REG(dev, ATTN_REG_VERSION);
    *major = (version >> 16) & 0xFFFF;
    *minor = version & 0xFFFF;

    return 0;
}

int attn_get_features(attn_device_t *dev,
                      uint8_t *max_L,
                      uint8_t *max_D,
                      uint8_t *tile_width)
{
    if (!dev) {
        return -1;
    }

    uint32_t features = ATTN_READ_REG(dev, ATTN_REG_FEATURES);

    if (max_L) {
        *max_L = (features >> 16) & 0xFFFF;
    }
    if (max_D) {
        *max_D = (features >> 8) & 0xFF;
    }
    if (tile_width) {
        *tile_width = features & 0xFF;
    }

    return 0;
}

int attn_compute(attn_device_t *dev,
                 const int8_t *Q,
                 const int8_t *K,
                 const int8_t *V,
                 int8_t *output,
                 attn_result_t *result)
{
    if (!dev || !Q || !K || !V || !output) {
        return -1;
    }

    int ret;
    uint32_t matrix_size = dev->L * dev->D;

    // 1. Write input matrices to memory
    ATTN_WRITE_MEM(dev->q_mem_addr, Q, matrix_size);
    ATTN_WRITE_MEM(dev->k_mem_addr, K, matrix_size);
    ATTN_WRITE_MEM(dev->v_mem_addr, V, matrix_size);

    // 2. Start computation
    ret = attn_start(dev);
    if (ret < 0) {
        return ret;
    }

    // 3. Wait for completion
    ret = attn_wait(dev, ATTN_TIMEOUT_MS);
    if (ret < 0) {
        if (result) {
            result->timeout = (ret == -1);
            result->error = (ret == -2);
            result->success = false;
        }
        return ret;
    }

    // 4. Read output
    ATTN_READ_MEM(output, dev->out_mem_addr, matrix_size);

    // 5. Get result metrics
    if (result) {
        attn_get_result(dev, result);
    }

    return 0;
}

int attn_clear_interrupt(attn_device_t *dev)
{
    if (!dev) {
        return -1;
    }

    ATTN_WRITE_REG(dev, ATTN_REG_CTRL, ATTN_CTRL_IRQ_CLEAR);

    return 0;
}

void attn_print_info(attn_device_t *dev)
{
    if (!dev) {
        return;
    }

    uint16_t major, minor;
    uint8_t max_L, max_D, tile_width;

    attn_get_version(dev, &major, &minor);
    attn_get_features(dev, &max_L, &max_D, &tile_width);

    printf("========================================\n");
    printf("Attention Accelerator Information\n");
    printf("========================================\n");
    printf("Version:        v%u.%u\n", major, minor);
    printf("Max L:          %u\n", max_L);
    printf("Max D:          %u\n", max_D);
    printf("Tile Width:     %u\n", tile_width);
    printf("Current L:      %u\n", dev->L);
    printf("Current D:      %u\n", dev->D);
    printf("Scale Shift:    %u\n", dev->scale_shift);
    printf("Q Memory:       0x%08X\n", dev->q_mem_addr);
    printf("K Memory:       0x%08X\n", dev->k_mem_addr);
    printf("V Memory:       0x%08X\n", dev->v_mem_addr);
    printf("Output Memory:  0x%08X\n", dev->out_mem_addr);
    printf("========================================\n");
}

void attn_print_result(const attn_result_t *result)
{
    if (!result) {
        return;
    }

    printf("========================================\n");
    printf("Computation Result\n");
    printf("========================================\n");
    printf("Success:        %s\n", result->success ? "Yes" : "No");
    printf("Cycle Count:    %u\n", result->cycle_count);
    printf("Latency:        %.2f us\n", result->latency_us);
    printf("Throughput:     %.0f att/sec\n", 1000000.0f / result->latency_us);

    if (result->timeout) {
        printf("Status:         TIMEOUT\n");
    } else if (result->error) {
        printf("Status:         ERROR\n");
    } else if (result->success) {
        printf("Status:         SUCCESS\n");
    }

    printf("========================================\n");
}

//==============================================================================
// Example Usage
//==============================================================================

#ifdef ATTN_EXAMPLE

int main(void)
{
    attn_device_t dev;
    attn_config_t config;
    attn_result_t result;
    int ret;

    // Define memory addresses (example for Zynq)
    volatile uint32_t *axi_base = (volatile uint32_t *)0x43C00000;
    uint32_t q_mem = 0x10000000;
    uint32_t k_mem = 0x10001000;
    uint32_t v_mem = 0x10002000;
    uint32_t out_mem = 0x10003000;

    // Initialize device
    ret = attn_init(&dev, axi_base, q_mem, k_mem, v_mem, out_mem);
    if (ret < 0) {
        printf("Failed to initialize device\n");
        return -1;
    }

    // Print device info
    attn_print_info(&dev);

    // Configure for L=8, D=64
    config.L = 8;
    config.D = 64;
    config.scale_shift = 3;  // sqrt(64) = 8 = 2^3
    config.use_interrupt = false;
    config.timeout_ms = 1000;

    ret = attn_configure(&dev, &config);
    if (ret < 0) {
        printf("Failed to configure device\n");
        return -1;
    }

    // Allocate matrices
    int8_t *Q = malloc(config.L * config.D);
    int8_t *K = malloc(config.L * config.D);
    int8_t *V = malloc(config.L * config.D);
    int8_t *output = malloc(config.L * config.D);

    // Initialize with test data
    for (int i = 0; i < config.L * config.D; i++) {
        Q[i] = rand() % 256 - 128;
        K[i] = rand() % 256 - 128;
        V[i] = rand() % 256 - 128;
    }

    // Compute attention
    printf("Starting attention computation...\n");
    ret = attn_compute(&dev, Q, K, V, output, &result);
    if (ret < 0) {
        printf("Computation failed: %d\n", ret);
        return -1;
    }

    // Print results
    attn_print_result(&result);

    // Print sample output
    printf("\nSample output (first 8 elements):\n");
    for (int i = 0; i < 8; i++) {
        printf("%4d ", output[i]);
    }
    printf("\n");

    // Cleanup
    free(Q);
    free(K);
    free(V);
    free(output);

    return 0;
}

#endif // ATTN_EXAMPLE
