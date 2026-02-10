CC      = gcc
CFLAGS  = -shared -fPIC -O2 -Wall -Wextra
LDFLAGS = -ldl -lm -lpthread
TARGET  = libscroll-speed.so
SRC     = scroll-speed.c

TEST_SRC    = test-interposer.c
TEST_BIN    = test-interposer

LIB_DIR     = /usr/local/lib/x86_64-linux-gnu
PRELOAD     = /etc/ld.so.preload
CONF_SRC    = scroll-speed.conf
CONF_DEST   = /etc/scroll-speed.conf

.PHONY: all test install uninstall clean

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

$(TEST_BIN): $(TEST_SRC) $(TARGET)
	$(CC) -O2 -Wall -o $@ $(TEST_SRC) -ldl -lm -Wl,--no-as-needed -linput

test: $(TEST_BIN)
	@echo "=== Raw mode ==="
	@./$(TEST_BIN) raw
	@echo ""
	@echo "=== LD_PRELOAD mode ==="
	@LD_PRELOAD=./$(TARGET) ./$(TEST_BIN) preload

install: $(TARGET)
	sudo install -m 644 $(TARGET) $(LIB_DIR)/$(TARGET)
	@# Remove old libinput-config if present
	@if grep -q 'libinput-config' $(PRELOAD) 2>/dev/null; then \
		echo "Replacing libinput-config in $(PRELOAD)..."; \
		sudo sed -i '/libinput-config/d' $(PRELOAD); \
	fi
	@if ! grep -q 'libscroll-speed' $(PRELOAD) 2>/dev/null; then \
		echo '$(LIB_DIR)/$(TARGET)' | sudo tee -a $(PRELOAD) > /dev/null; \
	fi
	@if [ ! -f $(CONF_DEST) ]; then \
		sudo install -m 644 $(CONF_SRC) $(CONF_DEST); \
		echo "Installed default config to $(CONF_DEST)"; \
	else \
		echo "$(CONF_DEST) already exists, not overwriting"; \
	fi
	@echo ""
	@echo "Installed. Log out and back in (or restart gnome-shell) to apply."

uninstall:
	sudo rm -f $(LIB_DIR)/$(TARGET)
	@if grep -q 'libscroll-speed' $(PRELOAD) 2>/dev/null; then \
		sudo sed -i '/libscroll-speed/d' $(PRELOAD); \
	fi
	@echo "Uninstalled. Log out and back in to revert."

clean:
	rm -f $(TARGET) $(TEST_BIN)
