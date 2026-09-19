CC = clang
# Universal binary at the app's deployment floor (macOS 13). Without an
# explicit -mmacosx-version-min the compiler defaults to the host SDK's
# minimum, which produced a minos=15.0 helper that cannot run on the
# macOS 13/14 machines the app claims to support.
CFLAGS = -Wall -O2 -fstack-protector-strong -D_FORTIFY_SOURCE=2 \
  -arch arm64 -arch x86_64 -mmacosx-version-min=13.0 \
  -framework IOKit -framework CoreFoundation
TARGET = smc-helper

all: $(TARGET)

$(TARGET): smc.c smc.h
	$(CC) $(CFLAGS) -o $(TARGET) smc.c

clean:
	rm -f $(TARGET)

install: $(TARGET)
	cp $(TARGET) ../../fan/Resources/

.PHONY: all clean install
