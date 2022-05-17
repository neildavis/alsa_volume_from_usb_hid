TARGET := alsa_vol_from_usb_hid

CORE_DIR := src
CONFIG_DIR := config
SYSTEMD_CONFIG_DIR := $(CONFIG_DIR)/etc/systemd/system
UDEV_RULES_DIR := $(CONFIG_DIR)/etc/udev/rules.d

SYSTEMD_CONFIG_FILE := $(TARGET).service
UDEV_RULES_FILE := 80-alsa-vol-from-usb-hid.rules

SYSTEM_SYSTEMD_CONFIG_DIR := /etc/systemd/system
SYSTEM_UDEV_RULES_DIR := /etc/udev/rules.d
INSTALL_DIR_BIN := /usr/local/bin

install:
	mkdir -p $(INSTALL_DIR_BIN)
	cp $(CORE_DIR)/$(TARGET).sh $(INSTALL_DIR_BIN)/$(TARGET)
	chmod a+x $(INSTALL_DIR_BIN)/$(TARGET)
	cp $(SYSTEMD_CONFIG_DIR)/$(SYSTEMD_CONFIG_FILE) $(SYSTEM_SYSTEMD_CONFIG_DIR)/
	sed -i 's|%TARGET%|$(INSTALL_DIR_BIN)/$(TARGET)|g' $(SYSTEM_SYSTEMD_CONFIG_DIR)/$(SYSTEMD_CONFIG_FILE)
	systemctl daemon-reload
	systemctl enable $(TARGET)
	cp $(UDEV_RULES_DIR)/$(UDEV_RULES_FILE) $(SYSTEM_UDEV_RULES_DIR)/
	udevadm control --reload

uninstall:
	systemctl stop $(TARGET) 2> /dev/null || true
	killall $(TARGET) 2> /dev/null || true
	systemctl disable $(TARGET) 2> /dev/null || true
	rm $(SYSTEM_SYSTEMD_CONFIG_DIR)/$(SYSTEMD_CONFIG_FILE) 2> /dev/null || true
	rm $(INSTALL_DIR_BIN)/$(TARGET) 2> /dev/null || true
	rm $(SYSTEM_UDEV_RULES_DIR)/$(UDEV_RULES_FILE)
	udevadm control --reload

start:
	systemctl start $(TARGET)

stop:
	systemctl stop $(TARGET)

