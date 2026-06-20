MAKEFLAGS += -r
GEN_DIR = code/generation
SHADERS = code/shaders/screen.vert code/shaders/screen.frag
INCLUDED = code/vec3.asm code/rand.asm code/config_defaults.asm

# Root targets
bin/empedocles: build/main.o build/gl3w.o
	mkdir -p bin
	ld -o bin/empedocles --dynamic-linker /lib64/ld-linux-x86-64.so.2 \
		build/main.o build/gl3w.o \
		-lc -lm -lglfw -lGL -lX11 -lpthread -lXrandr -lXi -ldl

run: bin/empedocles
	bin/empedocles

debug: bin/empedocles
	gdb -tui bin/empedocles -ex "layout asm" -ex "layout regs" -ex "set disassembly-flavor intel" -ex "break _start" -ex "r"

clean:
	rm -f build/*.o
	rm -f bin/empedocles
	rm -f $(GEN_DIR)/generate
	rm -f $(GEN_DIR)/generated_data.asm

profile: bin/empedocles
	(cd bin && \
	    valgrind --tool=callgrind --branch-sim=yes --cache-sim=yes --dump-instr=yes --callgrind-out-file=cachegrind_out ./empedocles \
	    kcachegrind ./cachegrind_out)

# Leafier targets
build/main.o: code/main.asm $(INCLUDED) $(GEN_DIR)/generated_data.asm
	nasm code/main.asm -o build/main.o -f elf64 -i code/ -p config_defaults.asm $(EMPEDOCLES_PARAMS) -g -F dwarf

$(GEN_DIR)/generated_data.asm: $(SHADERS) $(GEN_DIR)/generate
	$(GEN_DIR)/generate
	touch $(SHADERS)

$(GEN_DIR)/generate: 
	gcc $(GEN_DIR)/gen.c -o $(GEN_DIR)/generate

build/gl3w.o: extern/GL/gl3w.c
	gcc -c extern/GL/gl3w.c -o build/gl3w.o
