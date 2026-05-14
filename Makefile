bin/cube_games: build/main.o build/gl3w.o
	mkdir -p bin
	ld -o bin/cube_games --dynamic-linker /lib64/ld-linux-x86-64.so.2 \
		build/main.o build/gl3w.o \
		-lc -lglfw -lGL -lX11 -lpthread -lXrandr -lXi -ldl

build/main.o: code/main.asm code/generation/generated_data.asm
	fasm code/main.asm build/main.o

code/generation/generated_data.asm:
	(cd code/generation && make)

build/gl3w.o: extern/GL/gl3w.c
	gcc -c extern/GL/gl3w.c -o build/gl3w.o

run: bin/cube_games
	bin/cube_games

debug: bin/cube_games
	gdb -tui bin/cube_games -ex "layout asm" -ex "layout regs" -ex "set disassembly-flavor intel" -ex "break _start" -ex "r"

clean:
	rm build/*.o
	rm bin/cube_games
