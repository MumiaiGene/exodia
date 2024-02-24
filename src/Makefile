
CC =	gcc
CFLAGS = -g -std=c++11 -pipe -W -Wall -fPIC
CPP =	g++
PROTOC =	protoc
LINK =	$(CPP)

BRPC_PATH = /home/incubator-brpc-0.9.7

SYS_INCS = -I /usr/include \
		-I $(BRPC_PATH)/output/include

ALL_INCS = $(SYS_INCS) \
		-I src

LIB = -lsqlite3 -lpthread -lssl -lcrypto -ldl -lz -lrt

OBJS_PATH = objs
PROTOS = $(wildcard $(OBJS_PATH)/*.proto)
PROTO_OBJS = $(PROTOS:.proto=.pb.o)
SRC_OBJS = $(patsubst %.cpp, %.o, $(wildcard $(OBJS_PATH)/*.cpp))

BINARY_FILE = output/exodia

build: exodia

exodia: $(PROTO_OBJS) $(SRC_OBJS)
		@echo ">> Linking $@ <<"
		@$(LINK) $(LIB) $^ -o $(BINARY_FILE)

%.pb.cc %.pb.h:%.proto
		@echo ">> Generating $@ <<"
		@$(PROTOC) --cpp_out=./$(OBJS_PATH) --proto_path=./$(OBJS_PATH) $<

%.o:%.cpp
		@echo ">> Compiling $@ <<"
		@$(LINK) -c $(CFLAGS) $(ALL_INCS) $< -o $@

%.o:%.cc
		@echo ">> Compiling $@ <<"
		@$(LINK) -c $(CFLAGS) $(SYS_INCS) $< -o $@
