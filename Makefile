export TARGET = iphone:clang:latest:14.0
export ARCHS = arm64
INSTALL_TARGET_PROCESSES = SpringBoard

THEOS_DEVICE_IP=192.168.1.5

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = VCAM

VCAM_FILES = Tweak.x
VCAM_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
VCAM_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"
