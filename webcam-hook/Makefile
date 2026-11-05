LABEL     := me.arne.webcam-hook
BIN_DIR   := $(HOME)/.local/bin
BIN       := $(BIN_DIR)/webcam-hook
AGENT_DIR := $(HOME)/Library/LaunchAgents
PLIST     := $(AGENT_DIR)/$(LABEL).plist
LOG       := $(HOME)/Library/Logs/webcam-hook.log
DOMAIN    := gui/$(shell id -u)

.PHONY: build install uninstall logs

build:
	swift build -c release

# The ad hoc re-sign binds the embedded Info.plist and gives the binary the
# stable identifier me.arne.webcam-hook, which Local Network privacy needs
# (see README).
install: build
	mkdir -p $(BIN_DIR) $(AGENT_DIR) $(dir $(LOG))
	launchctl bootout $(DOMAIN)/$(LABEL) 2>/dev/null || true
	rm -f $(BIN)
	cp .build/release/webcam-hook $(BIN)
	codesign --force --sign - --identifier $(LABEL) $(BIN)
	sed 's|__HOME__|$(HOME)|g' launchd/$(LABEL).plist > $(PLIST)
	launchctl bootstrap $(DOMAIN) $(PLIST)

uninstall:
	-launchctl bootout $(DOMAIN)/$(LABEL)
	rm -f $(BIN) $(PLIST)

logs:
	tail -f $(LOG)
