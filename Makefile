export PACKAGE_VERSION := 1.0.2

export TARGET := iphone:clang:latest:15.0
export ARCHS := arm64 arm64e

# roothide (RootHide / Relaxin) is the default package scheme.
export THEOS_PACKAGE_SCHEME ?= roothide

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CopyMod
CopyMod_FILES = Tweak.xm \
	CMPreferences.m \
	CMLocalization.m \
	CMStore.m \
	CMMonitor.m \
	CMKeyboardBar.m \
	CMPanelView.m
CopyMod_CFLAGS = -fobjc-arc -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-declarations
CopyMod_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore
CopyMod_LIBRARIES = substrate
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
CopyMod_LIBRARIES += roothide
endif

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += Prefs
include $(THEOS_MAKE_PATH)/aggregate.mk

after-install::
	install.exec "killall -9 SpringBoard" || true
