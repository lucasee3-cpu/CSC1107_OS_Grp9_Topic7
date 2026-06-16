obj-m += sdhealth.o

sdhealth-objs := sdhealth_main.o detection.o

all:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) modules

clean:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) clean