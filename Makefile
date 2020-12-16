# Makefile for exodia
# Author: gengyishuang
# Date: 2020-07-04

default: build

clean:
	@echo "Cleaning"
	@rm -rf objs output

build:
	@mkdir -p objs output
	@cp src/* objs/
	@cp proto/* objs/
	$(MAKE) -f objs/Makefile
