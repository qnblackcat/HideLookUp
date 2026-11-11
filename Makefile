TARGET = iphone:clang:16.5:17.0
export ARCHS = arm64 arm64e

INSTALL_TARGET_PROCESSES = SpringBoard

FINALPACKAGE = 1

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = HideLookUp
HideLookUp_FILES = Tweak.x
HideLookUp_CFLAGS = -fobjc-arc
HideLookUp_FRAMEWORKS = UIKit

include $(THEOS_MAKE_PATH)/tweak.mk
