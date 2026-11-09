ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = CopyModPrefs
CopyModPrefs_FILES = CMRootListController.m
CopyModPrefs_INSTALL_PATH = /Library/PreferenceBundles
CopyModPrefs_PRIVATE_FRAMEWORKS = Preferences
CopyModPrefs_CFLAGS = -fobjc-arc
CopyModPrefs_LIBRARIES = roothide

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp Resources/CopyModPrefs.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/CopyModPrefs.plist$(ECHO_END)
