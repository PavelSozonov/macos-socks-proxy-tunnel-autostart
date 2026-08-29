# Convenience wrapper around the install/uninstall scripts.
# Run `make` or `make help` to list targets.

SHELL := /bin/bash
DOMAIN := gui/$(shell id -u)
SERVICES := tunnel-proxy gost-proxy tunnel-watchdog

.DEFAULT_GOAL := help
.PHONY: help install install-tunnel install-gost install-watchdog \
        uninstall uninstall-tunnel uninstall-gost uninstall-watchdog \
        status logs restart check

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

install: install-tunnel install-gost install-watchdog ## Install everything (tunnel, gost, watchdog)

install-tunnel: ## Install SSH SOCKS tunnel
	@bash scripts/install-tunnel.sh

install-gost: ## Install gost HTTP-to-SOCKS bridge (requires: brew install gost)
	@bash scripts/install-gost.sh

install-watchdog: ## Install tunnel watchdog
	@bash scripts/install-watchdog.sh

uninstall: uninstall-watchdog uninstall-gost uninstall-tunnel ## Uninstall everything

uninstall-tunnel: ## Uninstall SSH SOCKS tunnel
	@bash scripts/uninstall-tunnel.sh

uninstall-gost: ## Uninstall gost HTTP proxy
	@bash scripts/uninstall-gost.sh

uninstall-watchdog: ## Uninstall tunnel watchdog
	@bash scripts/uninstall-watchdog.sh

status: ## Show state of all services
	@for s in $(SERVICES); do \
		if launchctl print $(DOMAIN)/$$s >/dev/null 2>&1; then \
			pid=$$(launchctl print $(DOMAIN)/$$s | awk '/^\tpid =/{print $$3}'); \
			printf "  %-16s loaded%s\n" "$$s" "$${pid:+, pid $$pid}"; \
		else \
			printf "  %-16s not installed\n" "$$s"; \
		fi; \
	done

logs: ## Tail logs of all installed services
	@tail -f $(foreach s,$(SERVICES),$(wildcard $(HOME)/scripts/$(s).log))

restart: ## Restart the SSH tunnel now
	@launchctl kickstart -k $(DOMAIN)/tunnel-proxy && echo "tunnel-proxy restarted"

check: ## Run the health check through the SOCKS proxy once
	@. ./.env 2>/dev/null; curl --socks5-hostname 127.0.0.1:$${SOCKS_PORT:-8090} -m $${WATCHDOG_TIMEOUT:-3} -fsS -o /dev/null $${WATCHDOG_URL:-https://www.google.com/generate_204} && echo "tunnel OK"
