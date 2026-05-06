.PHONY: test install

install:
	cp bin/graft /usr/local/bin/graft
	chmod +x /usr/local/bin/graft

test:
	@for f in test/test_*.sh; do \
		echo "=== $$f ==="; \
		bash "$$f" || exit 1; \
	done
	@echo "All tests passed."
