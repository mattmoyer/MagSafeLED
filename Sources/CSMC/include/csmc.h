// SPDX-License-Identifier: GPL-2.0-or-later
#ifndef CSMC_H
#define CSMC_H

#include <stdint.h>

// Layout of the AppleSMC user-client parameter block (same as smcFanControl's SMCKeyData_t).
// Must be exactly 80 bytes.

#define SMC_KERNEL_INDEX      2
#define SMC_CMD_READ_BYTES    5
#define SMC_CMD_WRITE_BYTES   6
#define SMC_CMD_READ_KEYINFO  9

typedef struct {
    char     major;
    char     minor;
    char     build;
    char     reserved;
    uint16_t release;
} SMCVersion;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} SMCPLimitData;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t  dataAttributes;
} SMCKeyInfo;

typedef struct {
    uint32_t      key;
    SMCVersion    vers;
    SMCPLimitData pLimitData;
    SMCKeyInfo    keyInfo;
    uint8_t       result;
    uint8_t       status;
    uint8_t       data8;
    uint32_t      data32;
    uint8_t       bytes[32];
} SMCParamStruct;

// IOMessage.h macros Swift can't import (iokit_common_msg(x) = 0xE0000000 | x).
static const uint32_t CSMCMessageCanSystemSleep    = 0xE0000270;
static const uint32_t CSMCMessageSystemWillSleep   = 0xE0000280;
static const uint32_t CSMCMessageSystemHasPoweredOn = 0xE0000300;

_Static_assert(sizeof(SMCParamStruct) == 80, "SMCParamStruct must be 80 bytes");

#endif
