TARGET := iphone:clang:latest:11.0
INSTALL_TARGET_PROCESSES = SpringBoard Camera

THEOS_DEVICE_IP=192.168.1.5


include $(THEOS)/makefiles/common.mk

TWEAK_NAME = VCAM

VCAM_FILES = Tweak.x
VCAM_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "sbreload || killall -9 SpringBoard"
