# Makefile for exodia
# Author: gengyishuang
# Date: 2020-07-04

default: build

clean:
	rm -rf objs bin

build:
	mkdir -p objs bin
	cp src/Makefile objs/ 
	$(MAKE) -f objs/Makefile
