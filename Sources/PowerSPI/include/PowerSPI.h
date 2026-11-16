#ifndef POWER_SPI_H
#define POWER_SPI_H

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOReturn.h>

// Private calls from IOPMLibPrivate.h (IOKitUser). Unsupported by Apple.
// "SleepDisabled" is the setting `pmset disablesleep` changes.

CF_ASSUME_NONNULL_BEGIN

// Readable by any user.
CFDictionaryRef _Nullable IOPMCopySystemPowerSettings(void) CF_RETURNS_RETAINED;

// Requires root.
IOReturn IOPMSetSystemPowerSetting(CFStringRef key, CFTypeRef value);

CF_ASSUME_NONNULL_END

#endif
