export TARGET = iphone:clang:latest:14.0
export ARCHS = arm64
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = VCAM

VCAM_FILES = Tweak.x
VCAM_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
VCAM_FRAMEWORKS = UIKit Foundation AVFoundation CoreMedia CoreVideo QuartzCore CoreImage CoreGraphics
VCAM_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "sbreload || killall -9 SpringBoard"