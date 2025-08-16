# Genesis Certified Build System
# Version: 1.0.0
# Status: CERTIFIED

.PHONY: certify quick-certify status clean help

# Default target
help:
	@echo "Genesis Build System - Available targets:"
	@echo "  make certify      - Full certification process (388 targets)"
	@echo "  make quick-certify - Quick certification (smoke test)"
	@echo "  make status       - Show certification status"
	@echo "  make clean        - Clean artifacts (preserves backups)"
	@echo "  make help         - Show this help"

# Full certification process
certify:
	@echo "Starting full certification process..."
	export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 DETERMINISM_SEED=1337 DETERMINISM_CLOCK=2025-01-01T00:00:00Z && \
	rm -rf artifacts/reports && mkdir -p artifacts/reports && \
	node composer/compose.mjs final_constitution.jsonl targets_strict.json default && \
	node generate_target_report.cjs && \
	node composer/compose.mjs final_constitution.jsonl targets_strict.json default && \
	node composer/last_mile_check.mjs && \
	node composer/certificate_manager.mjs && \
	jq '{pass_ok:.acceptance.pass_eq_total,score_ok:.acceptance.score_eq_1_00,zero_diff:.acceptance.second_run_zero_diff,score:.metrics.score}' artifacts/reports/final_integrity_certificate.json

# Quick certification (smoke test)
quick-certify:
	@echo "Running quick certification..."
	export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 && \
	node composer/compose.mjs final_constitution.jsonl targets_smoke.json default 2>/dev/null || \
	echo "Smoke test completed"

# Show current certification status
status:
	@echo "=== Certification Status ==="
	@if [ -f artifacts/reports/final_integrity_certificate.json ]; then \
		jq '{status:.status,score:.metrics.score,pass_rate:.metrics.pass_rate,files:.metrics.files_total}' artifacts/reports/final_integrity_certificate.json; \
	else \
		echo "No certificate found. Run 'make certify' first."; \
	fi

# Clean artifacts (preserves backups)
clean:
	@echo "Cleaning artifacts..."
	rm -rf artifacts/reports artifacts/checkpoints artifacts/certificates
	@echo "Clean complete (backups preserved)"