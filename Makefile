TARGET := alsa_vol_from_usb_hid

CORE_DIR := src
CONFIG_DIR := config
SYSTEMD_CONFIG_DIR := $(CONFIG_DIR)/etc/systemd/system

SYSTEMD_CONFIG_FILE := $(TARGET).service

SYSTEM_SYSTEMD_CONFIG_DIR := /etc/systemd/system
INSTALL_DIR_BIN := /usr/local/bin

install:
	mkdir -p $(INSTALL_DIR_BIN)
	cp $(CORE_DIR)/$(TARGET).sh $(INSTALL_DIR_BIN)/$(TARGET)
	chmod a+x $(INSTALL_DIR_BIN)/$(TARGET)
	cp $(SYSTEMD_CONFIG_DIR)/$(SYSTEMD_CONFIG_FILE) $(SYSTEM_SYSTEMD_CONFIG_DIR)/
	sed -i 's|%TARGET%|$(INSTALL_DIR_BIN)/$(TARGET)|g' $(SYSTEM_SYSTEMD_CONFIG_DIR)/$(SYSTEMD_CONFIG_FILE)
	systemctl daemon-reload
	systemctl enable $(TARGET)

uninstall:
	systemctl stop $(TARGET) 2> /dev/null || true
	killall $(TARGET) 2> /dev/null || true
	systemctl disable $(TARGET) 2> /dev/null || true
	rm $(SYSTEM_SYSTEMD_CONFIG_DIR)/$(SYSTEMD_CONFIG_FILE) 2> /dev/null || true
	rm $(INSTALL_DIR_BIN)/$(TARGET) 2> /dev/null || true

start:
	systemctl start $(TARGET)

stop:
	systemctl stop $(TARGET)

