CXX ?= g++
CXXFLAGS ?= -std=c++17 -O2 -Wall -Wextra -pedantic
TARGET := smartbed_stream_processor
SRC := src/smartbed_stream_processor.cpp
CSV := smartbed-sensor-stream.csv
OUTDIR := output

.PHONY: all run test clean

all: $(TARGET)

$(TARGET): $(SRC)
	$(CXX) $(CXXFLAGS) $(SRC) -o $(TARGET)

run: $(TARGET)
	./$(TARGET) $(CSV) --outdir $(OUTDIR)

test: $(TARGET)
	bash tests/run_tests.sh ./$(TARGET)

clean:
	rm -f $(TARGET)
	rm -rf output output_test_rr output_test_apnea
