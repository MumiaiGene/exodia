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
	$(MAKE) -f objs/Makefile
	@rm -rf objs/*.cpp objs/*.h objs/*.proto
	@echo ">> make successfully <<"
