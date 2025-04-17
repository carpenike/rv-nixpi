#!/bin/bash
# Script to collect debug information from a working Raspberry Pi CAN setup
# Execute this script on your working Raspberry Pi before reflashing

# Create a timestamp for the output directory
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
OUTPUT_DIR="debug_data_${TIMESTAMP}"
mkdir -p "${OUTPUT_DIR}"

echo "Starting debug data collection - results will be in ${OUTPUT_DIR}/"

# Basic system information
echo "Collecting system information..."
mkdir -p "${OUTPUT_DIR}/system"
uname -a > "${OUTPUT_DIR}/system/uname.txt"
cat /proc/cpuinfo > "${OUTPUT_DIR}/system/cpuinfo.txt"
cat /proc/meminfo > "${OUTPUT_DIR}/system/meminfo.txt"
cat /proc/cmdline > "${OUTPUT_DIR}/system/cmdline.txt"
cat /etc/os-release > "${OUTPUT_DIR}/system/os-release.txt"
dmesg > "${OUTPUT_DIR}/system/dmesg.txt"
journalctl -b -0 > "${OUTPUT_DIR}/system/journal.txt"
ls -la /dev/ > "${OUTPUT_DIR}/system/dev_listing.txt"
lsblk -a > "${OUTPUT_DIR}/system/block_devices.txt"
dpkg -l > "${OUTPUT_DIR}/system/installed_packages.txt" 2>/dev/null || rpm -qa > "${OUTPUT_DIR}/system/installed_packages.txt" 2>/dev/null || echo "Package manager not recognized" > "${OUTPUT_DIR}/system/installed_packages.txt"

# Kernel modules and boot configuration
echo "Collecting kernel and module information..."
mkdir -p "${OUTPUT_DIR}/kernel"
lsmod > "${OUTPUT_DIR}/kernel/loaded_modules.txt"
modinfo mcp251x > "${OUTPUT_DIR}/kernel/mcp251x_info.txt" 2>/dev/null || echo "mcp251x module not found" > "${OUTPUT_DIR}/kernel/mcp251x_info.txt"
modinfo can > "${OUTPUT_DIR}/kernel/can_info.txt" 2>/dev/null || echo "can module not found" > "${OUTPUT_DIR}/kernel/can_info.txt"
modinfo can_raw > "${OUTPUT_DIR}/kernel/can_raw_info.txt" 2>/dev/null || echo "can_raw module not found" > "${OUTPUT_DIR}/kernel/can_raw_info.txt"
modinfo can_dev > "${OUTPUT_DIR}/kernel/can_dev_info.txt" 2>/dev/null || echo "can_dev module not found" > "${OUTPUT_DIR}/kernel/can_dev_info.txt"
modinfo spi_bcm2835 > "${OUTPUT_DIR}/kernel/spi_bcm2835_info.txt" 2>/dev/null || echo "spi_bcm2835 module not found" > "${OUTPUT_DIR}/kernel/spi_bcm2835_info.txt"

# Copy any module configuration files
mkdir -p "${OUTPUT_DIR}/kernel/modules_config"
if [ -d "/etc/modules-load.d" ]; then
    cp -r /etc/modules-load.d/* "${OUTPUT_DIR}/kernel/modules_config/" 2>/dev/null
fi
if [ -f "/etc/modules" ]; then
    cp /etc/modules "${OUTPUT_DIR}/kernel/modules_config/" 2>/dev/null
fi

# Boot configuration
mkdir -p "${OUTPUT_DIR}/boot"
if [ -d "/boot/firmware" ]; then
    cp /boot/firmware/config.txt "${OUTPUT_DIR}/boot/" 2>/dev/null
    cp /boot/firmware/cmdline.txt "${OUTPUT_DIR}/boot/" 2>/dev/null
elif [ -d "/boot" ]; then
    cp /boot/config.txt "${OUTPUT_DIR}/boot/" 2>/dev/null
    cp /boot/cmdline.txt "${OUTPUT_DIR}/boot/" 2>/dev/null
fi

# Network and CAN interface information
echo "Collecting network and CAN interface information..."
mkdir -p "${OUTPUT_DIR}/network"
ip -details link show > "${OUTPUT_DIR}/network/ip_link.txt"
ip -details addr show > "${OUTPUT_DIR}/network/ip_addr.txt"
ifconfig -a > "${OUTPUT_DIR}/network/ifconfig.txt" 2>/dev/null || echo "ifconfig not found" > "${OUTPUT_DIR}/network/ifconfig.txt"
ip -details link show can0 > "${OUTPUT_DIR}/network/can0_link.txt" 2>/dev/null || echo "can0 interface not found" > "${OUTPUT_DIR}/network/can0_link.txt"
ip -details link show can1 > "${OUTPUT_DIR}/network/can1_link.txt" 2>/dev/null || echo "can1 interface not found" > "${OUTPUT_DIR}/network/can1_link.txt"
ifconfig can0 > "${OUTPUT_DIR}/network/can0_ifconfig.txt" 2>/dev/null || echo "can0 interface not found or ifconfig not available" > "${OUTPUT_DIR}/network/can0_ifconfig.txt"
ifconfig can1 > "${OUTPUT_DIR}/network/can1_ifconfig.txt" 2>/dev/null || echo "can1 interface not found or ifconfig not available" > "${OUTPUT_DIR}/network/can1_ifconfig.txt"
ls -la /sys/class/net/ > "${OUTPUT_DIR}/network/net_interfaces.txt"
ls -la /sys/class/net/can* > "${OUTPUT_DIR}/network/can_interfaces.txt" 2>/dev/null || echo "No CAN interfaces found" > "${OUTPUT_DIR}/network/can_interfaces.txt"

# CAN utilities output (if available)
if command -v candump >/dev/null 2>&1; then
    echo "Collecting CAN utilities information (quick sampling only)..."
    candump can0 -t z -n 10 > "${OUTPUT_DIR}/network/candump_can0.txt" 2>/dev/null &
    CANDUMP_PID=$!
    sleep 5
    kill $CANDUMP_PID 2>/dev/null
fi
if command -v ip >/dev/null 2>&1; then
    ip -details -statistics link show can0 > "${OUTPUT_DIR}/network/can0_statistics.txt" 2>/dev/null
    ip -details -statistics link show can1 > "${OUTPUT_DIR}/network/can1_statistics.txt" 2>/dev/null
fi

# SPI information
echo "Collecting SPI information..."
mkdir -p "${OUTPUT_DIR}/spi"
ls -la /dev/spi* > "${OUTPUT_DIR}/spi/spi_devices.txt" 2>/dev/null || echo "No SPI device nodes found" > "${OUTPUT_DIR}/spi/spi_devices.txt"
ls -la /sys/bus/spi/devices/ > "${OUTPUT_DIR}/spi/spi_sys_devices.txt" 2>/dev/null || echo "No SPI devices in sysfs" > "${OUTPUT_DIR}/spi/spi_sys_devices.txt"
ls -la /sys/bus/spi/drivers/ > "${OUTPUT_DIR}/spi/spi_drivers.txt" 2>/dev/null || echo "No SPI drivers found" > "${OUTPUT_DIR}/spi/spi_drivers.txt"
if [ -d "/sys/bus/spi/devices/spi0.0" ]; then
    ls -la /sys/bus/spi/devices/spi0.0/ > "${OUTPUT_DIR}/spi/spi0.0_details.txt"
    cat /sys/bus/spi/devices/spi0.0/modalias > "${OUTPUT_DIR}/spi/spi0.0_modalias.txt" 2>/dev/null
    cat /sys/bus/spi/devices/spi0.0/driver/uevent > "${OUTPUT_DIR}/spi/spi0.0_driver_uevent.txt" 2>/dev/null
fi
if [ -d "/sys/bus/spi/devices/spi0.1" ]; then
    ls -la /sys/bus/spi/devices/spi0.1/ > "${OUTPUT_DIR}/spi/spi0.1_details.txt"
    cat /sys/bus/spi/devices/spi0.1/modalias > "${OUTPUT_DIR}/spi/spi0.1_modalias.txt" 2>/dev/null
    cat /sys/bus/spi/devices/spi0.1/driver/uevent > "${OUTPUT_DIR}/spi/spi0.1_driver_uevent.txt" 2>/dev/null
fi

# Device tree information
echo "Collecting device tree information..."
mkdir -p "${OUTPUT_DIR}/device_tree"
cat /proc/device-tree/compatible > "${OUTPUT_DIR}/device_tree/compatible.txt" 2>/dev/null || echo "Cannot read /proc/device-tree/compatible" > "${OUTPUT_DIR}/device_tree/compatible.txt"
ls -la /proc/device-tree/ > "${OUTPUT_DIR}/device_tree/dt_root_listing.txt" 2>/dev/null
ls -la /proc/device-tree/soc/ > "${OUTPUT_DIR}/device_tree/dt_soc_listing.txt" 2>/dev/null
ls -la /proc/device-tree/soc/spi@7e204000/ > "${OUTPUT_DIR}/device_tree/dt_spi_listing.txt" 2>/dev/null || echo "SPI device tree node not found" > "${OUTPUT_DIR}/device_tree/dt_spi_listing.txt"

# Export full device tree if dtc is available
if command -v dtc >/dev/null 2>&1; then
    echo "Exporting full device tree..."
    dtc -I fs -O dts /proc/device-tree > "${OUTPUT_DIR}/device_tree/current-devicetree.dts" 2>/dev/null || echo "Failed to export device tree" > "${OUTPUT_DIR}/device_tree/dtc_error.txt"
else
    echo "dtc command not found, cannot export full device tree"
    echo "dtc not available" > "${OUTPUT_DIR}/device_tree/dtc_missing.txt"
fi

# Service information
echo "Collecting service information..."
mkdir -p "${OUTPUT_DIR}/services"
systemctl status "can*" > "${OUTPUT_DIR}/services/can_services_status.txt" 2>/dev/null || echo "No CAN services found" > "${OUTPUT_DIR}/services/can_services_status.txt"
systemctl list-unit-files > "${OUTPUT_DIR}/services/all_services.txt"
systemctl list-unit-files | grep enabled > "${OUTPUT_DIR}/services/enabled_services.txt"
if [ -d "/etc/systemd/system" ]; then
    ls -la /etc/systemd/system/ > "${OUTPUT_DIR}/services/systemd_services.txt"
    if [ -d "/etc/systemd/system/network-online.target.wants" ]; then
        ls -la /etc/systemd/system/network-online.target.wants/ > "${OUTPUT_DIR}/services/network_services.txt"
    fi
fi

# CAN-specific dmesg and log extracts
echo "Extracting CAN and SPI related logs..."
mkdir -p "${OUTPUT_DIR}/logs"
dmesg | grep -i "can" > "${OUTPUT_DIR}/logs/dmesg_can.txt"
dmesg | grep -i "spi" > "${OUTPUT_DIR}/logs/dmesg_spi.txt"
dmesg | grep -i "mcp" > "${OUTPUT_DIR}/logs/dmesg_mcp.txt"
journalctl -b -0 | grep -i "can" > "${OUTPUT_DIR}/logs/journal_can.txt" 2>/dev/null
journalctl -b -0 | grep -i "spi" > "${OUTPUT_DIR}/logs/journal_spi.txt" 2>/dev/null
journalctl -b -0 | grep -i "mcp" > "${OUTPUT_DIR}/logs/journal_mcp.txt" 2>/dev/null

# Create a summary file
echo "Creating summary file..."
{
    echo "Debug data collection summary - $(date)"
    echo "================================="
    echo ""
    echo "System: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d \")"
    echo "Kernel: $(uname -r)"
    echo ""
    echo "CAN Interfaces:"
    if grep -q "can0" "${OUTPUT_DIR}/network/net_interfaces.txt"; then
        echo "- can0: Found"
        if grep -q "UP" "${OUTPUT_DIR}/network/can0_link.txt"; then
            echo "  Status: UP"
        else
            echo "  Status: DOWN"
        fi
    else
        echo "- can0: Not found"
    fi
    if grep -q "can1" "${OUTPUT_DIR}/network/net_interfaces.txt"; then
        echo "- can1: Found"
        if grep -q "UP" "${OUTPUT_DIR}/network/can1_link.txt"; then
            echo "  Status: UP"
        else
            echo "  Status: DOWN"
        fi
    else
        echo "- can1: Not found"
    fi
    echo ""
    echo "SPI Devices:"
    if [ -d "/sys/bus/spi/devices/spi0.0" ]; then
        echo "- spi0.0: Found"
    else
        echo "- spi0.0: Not found"
    fi
    if [ -d "/sys/bus/spi/devices/spi0.1" ]; then
        echo "- spi0.1: Found"
    else
        echo "- spi0.1: Not found"
    fi
    echo ""
    echo "Relevant Kernel Modules:"
    if grep -q "mcp251x" "${OUTPUT_DIR}/kernel/loaded_modules.txt"; then
        echo "- mcp251x: Loaded"
    else
        echo "- mcp251x: Not loaded"
    fi
    if grep -q "can " "${OUTPUT_DIR}/kernel/loaded_modules.txt"; then
        echo "- can: Loaded"
    else
        echo "- can: Not loaded"
    fi
    if grep -q "can_raw" "${OUTPUT_DIR}/kernel/loaded_modules.txt"; then
        echo "- can_raw: Loaded"
    else
        echo "- can_raw: Not loaded"
    fi
    if grep -q "can_dev" "${OUTPUT_DIR}/kernel/loaded_modules.txt"; then
        echo "- can_dev: Loaded"
    else
        echo "- can_dev: Not loaded"
    fi
    if grep -q "spi_bcm2835" "${OUTPUT_DIR}/kernel/loaded_modules.txt"; then
        echo "- spi_bcm2835: Loaded"
    else
        echo "- spi_bcm2835: Not loaded"
    fi
    echo ""
    echo "Device Tree:"
    if [ -f "${OUTPUT_DIR}/device_tree/current-devicetree.dts" ]; then
        echo "- Full device tree exported successfully"
    else
        echo "- Full device tree export failed or not available"
    fi
    echo ""
    echo "For more details, examine the files in the ${OUTPUT_DIR}/ directory."
} > "${OUTPUT_DIR}/summary.txt"

# Create a compressed archive of all the data
echo "Creating compressed archive of debug data..."
tar -czf "debug_data_${TIMESTAMP}.tar.gz" "${OUTPUT_DIR}"

echo "Debug data collection completed! Archive saved as debug_data_${TIMESTAMP}.tar.gz"
echo "You can transfer this file to your development machine for analysis."
echo "Run: scp user@raspberry-pi:path/to/debug_data_${TIMESTAMP}.tar.gz /path/on/local/machine/"
