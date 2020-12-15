
CC =	gcc
CFLAGS = -g -std=c++11 -pipe -W -Wall -fPIC
CPP =	g++
LINK =	$(CPP)

BRPC_PATH = /home/incubator-brpc-0.9.7

ALL_INCS = -I /usr/include \
		-I $(BRPC_PATH)/output/include

LIB = -lsqlite3 -lpthread -lbrpc -lssl -lcrypto -ldl -lz -lrt -lgflags -lprotobuf -lleveldb

HEADERS = src/carddata.h \
		src/database.h \

SRC_INCS = $(ALL_INCS) \
		-I src

BINARY_FILE = bin/exodia

build: objs/main.o
		$(LINK) -o $(BINARY_FILE) \
		objs/main.o \
		$(LIB)

objs/main.o:	$(HEADERS) \
	src/main.cpp
	$(LINK) -c $(CFLAGS) $(SRC_INCS) \
		src/main.cpp \
		-o objs/main.o
