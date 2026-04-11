CXX ?= g++
CXXFLAGS ?= -O3 -std=c++17 -march=native -ffast-math -fopenmp -Wall -Wextra -Wpedantic
LDFLAGS ?= -fopenmp

TARGET := tdx
SRC := tdx.cpp
MIX_TARGET := tdmix_kstep
MIX_SRC := tdmix_kstep.cpp

.PHONY: all clean run-help

all: $(TARGET)

$(TARGET): $(SRC)
	$(CXX) $(CXXFLAGS) -o $@ $< $(LDFLAGS)

$(MIX_TARGET): $(MIX_SRC)
	$(CXX) $(CXXFLAGS) -o $@ $< $(LDFLAGS)

run-help: $(TARGET)
	./$(TARGET) --help

clean:
	rm -f $(TARGET) $(MIX_TARGET)
