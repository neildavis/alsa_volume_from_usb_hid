TARGET := alsa_vol_from_usb_hid
TARGET_PY := $(TARGET).py
ARGS ?= 

CORE_DIR := src
CONFIG_DIR := config
SYSTEMD_CONFIG_DIR := $(CONFIG_DIR)/etc/systemd/system
SYSTEMD_CONFIG_FILE := $(TARGET).service

USER_SYSTEMD_CONFIG_DIR := /home/$(USER)/.config/systemd/user
INSTALL_DIR := /home/$(USER)/.local/opt/$(TARGET)
VENV_PATH := $(INSTALL_DIR)/env

install:
	mkdir -p $(INSTALL_DIR)
	mkdir -p $(USER_SYSTEMD_CONFIG_DIR)
	python3 -m venv $(VENV_PATH)
	$(VENV_PATH)/bin/pip install evdev pyalsaaudio
	cp $(CORE_DIR)/$(TARGET_PY) $(INSTALL_DIR)/$(TARGET_PY)
	cp $(SYSTEMD_CONFIG_DIR)/$(SYSTEMD_CONFIG_FILE) $(USER_SYSTEMD_CONFIG_DIR)/
	sed -i 's|%VENV_PATH%|$(VENV_PATH)|g' $(USER_SYSTEMD_CONFIG_DIR)/$(SYSTEMD_CONFIG_FILE)
	sed -i 's|%TARGET_PY%|$(INSTALL_DIR)/$(TARGET_PY)|g' $(USER_SYSTEMD_CONFIG_DIR)/$(SYSTEMD_CONFIG_FILE)
	sed -i 's|%ARGS%|$(ARGS)|g' $(USER_SYSTEMD_CONFIG_DIR)/$(SYSTEMD_CONFIG_FILE)
	systemctl --user daemon-reload
	systemctl --user enable $(TARGET)

uninstall:
	systemctl --user stop $(TARGET) 2> /dev/null || true
	killall $(TARGET) 2> /dev/null || true
	systemctl --user disable $(TARGET) 2> /dev/null || true
	rm $(USER_SYSTEMD_CONFIG_DIR)/$(SYSTEMD_CONFIG_FILE) 2> /dev/null || true
	rm -rf $(INSTALL_DIR) 2> /dev/null || true

start:
	systemctl --user start $(TARGET)

stop:
	systemctl --user stop $(TARGET)

