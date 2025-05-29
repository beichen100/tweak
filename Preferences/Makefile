TARGET := iphone:clang:latest:11.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = VCAMPrefs

VCAMPrefs_FILES = VCAMRootListController.m
VCAMPrefs_FRAMEWORKS = UIKit
VCAMPrefs_PRIVATE_FRAMEWORKS = Preferences
VCAMPrefs_INSTALL_PATH = /Library/PreferenceLoader/Preferences

include $(THEOS_MAKE_PATH)/bundle.mk 