# Convenience wrapper around the install/uninstall scripts.
# Run `make` or `make help` to list targets.

SHELL := /bin/bash
DOMAIN := gui/$(shell id -u)
SERVICES := tunnel-proxy gost-proxy tunnel-watchdog log-cap

.DEFAULT_GOAL := help
.PHONY: help check-gost install install-tunnel install-http-proxy install-watchdog install-log-cap \
        uninstall uninstall-tunnel uninstall-http-proxy uninstall-watchdog uninstall-log-cap \
        status logs restart check lint

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

install: check-gost install-tunnel install-http-proxy install-watchdog install-log-cap ## Install everything (tunnel, HTTP proxy, watchdog, log cap)

# Checked before anything is installed, so a missing or crashing gost never
# leaves a half-installed setup (tunnel present, HTTP bridge and watchdog absent).
check-gost: ## Verify that gost is installed and starts (brew install gost)
	@bash scripts/check-gost.sh >/dev/null

install-tunnel: ## Install SSH SOCKS tunnel
	@bash scripts/install-tunnel.sh

install-http-proxy: check-gost ## Install the HTTP proxy (gost HTTP-to-SOCKS bridge; requires: brew install gost)
	@bash scripts/install-http-proxy.sh

install-watchdog: ## Install tunnel watchdog
	@bash scripts/install-watchdog.sh

install-log-cap: ## Install the log size cap (keeps service logs under LOG_CAP_BYTES)
	@bash scripts/install-log-cap.sh

uninstall: uninstall-log-cap uninstall-watchdog uninstall-http-proxy uninstall-tunnel ## Uninstall everything

uninstall-tunnel: ## Uninstall SSH SOCKS tunnel
	@bash scripts/uninstall-tunnel.sh

uninstall-http-proxy: ## Uninstall the HTTP proxy (gost)
	@bash scripts/uninstall-http-proxy.sh

uninstall-watchdog: ## Uninstall tunnel watchdog
	@bash scripts/uninstall-watchdog.sh

uninstall-log-cap: ## Uninstall the log size cap
	@bash scripts/uninstall-log-cap.sh

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
	@. ./.env 2>/dev/null; curl --socks5-hostname 127.0.0.1:$${SOCKS_PORT:-8090} -m $${WATCHDOG_TIMEOUT:-8} -fsS -o /dev/null $${WATCHDOG_URL:-http://www.google.com/generate_204} && echo "tunnel OK"

lint: ## Run the same checks as CI (pre-commit: whitespace, file endings, shellcheck)
	@pre-commit run --all-files
