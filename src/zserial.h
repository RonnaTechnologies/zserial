#pragma once
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ZSerialPortList ZSerialPortList;

ZSerialPortList *zserial_list_ports(size_t *len);
const char *zserial_port_name(ZSerialPortList *ports, size_t index);
void zserial_free(ZSerialPortList *ports);

#ifdef __cplusplus
}
#endif