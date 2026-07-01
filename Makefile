include config.mk

.PHONY: all build clean run install uninstall

all: build

build:
	odin build . -define:VERSION=$(VERSION) $(OPTIMIZATION) -out:$(OUTPUT)

clean:
	rm -f $(OUTPUT)

run: build
	./$(OUTPUT)

install: build
	@mkdir -p $(DESTDIR)$(PREFIX)/bin
	cp -f $(OUTPUT) $(DESTDIR)$(PREFIX)/bin
	@chmod 755 $(DESTDIR)$(PREFIX)/bin/$(OUTPUT)

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/$(OUTPUT)
