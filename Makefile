PREFIX ?= /usr/local
DESTDIR ?=

BINDIR    = $(DESTDIR)$(PREFIX)/bin
MANDIR    = $(DESTDIR)$(PREFIX)/share/man/man1
DOCDIR    = $(DESTDIR)$(PREFIX)/share/doc/expresso
BASHCOMPDIR = $(DESTDIR)$(PREFIX)/share/bash-completion/completions

SHELL_SOURCES = src/expresso completions/expresso.bash scripts/*.sh \
                tests/helpers.bash tests/fakes/fake tests/*.bats tests/integration.sh

BATS ?= bats

.PHONY: all install uninstall check test integration

all:
	@echo "Nothing to build. Run 'make install' (PREFIX=$(PREFIX))."

install:
	install -Dm755 src/expresso              $(BINDIR)/expresso
	install -Dm644 man/expresso.1            $(MANDIR)/expresso.1
	install -Dm644 completions/expresso.bash $(BASHCOMPDIR)/expresso
	install -Dm644 README.md                 $(DOCDIR)/README.md
	install -Dm644 examples/expresso.conf    $(DOCDIR)/expresso.conf.example

uninstall:
	rm -f  $(BINDIR)/expresso
	rm -f  $(MANDIR)/expresso.1
	rm -f  $(BASHCOMPDIR)/expresso
	rm -rf $(DOCDIR)

# Lint and formatting check (same as CI).
check:
	shellcheck -x $(SHELL_SOURCES)
	shfmt -d $(SHELL_SOURCES)

# Run the test suite (needs bats: pacman -S bash-bats).
test:
	$(BATS) tests

# Test against the real systemd; run locally before each release.
# SUSPEND=1 adds the suspend/resume check (interactive).
integration:
	tests/integration.sh $(if $(SUSPEND),--suspend)
