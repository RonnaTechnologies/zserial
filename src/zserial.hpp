#pragma once

#include <zserial.h>

#include <cstdint>
#include <string>
#include <vector>

struct PortInfo {
  std::string device;
  std::string product;
  std::string manufacturer;
  std::string serialNumber;
  std::uint16_t vid{};
  std::uint16_t pid{};
  std::string location;
};

class ZSerial {
public:
  static auto ListPorts() -> std::vector<std::string> {
    std::size_t len{};
    auto *c_ports = zserial_list_ports(&len);

    std::vector<std::string> ports(len);

    for (std::size_t i = 0; i < len; ++i) {
      const auto port = zserial_port_name(c_ports, i);
      ports[i] = std::string{port};
    }

    zserial_free(c_ports);

    return ports;
  }

private:
};