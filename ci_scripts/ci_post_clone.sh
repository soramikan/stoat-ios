#!/bin/sh



# allow using macros
defaults write com.apple.dt.Xcode IDESkipMacroFingerprintValidation -bool YES

# resolve packages
cd ..
xcodebuild -resolvePackageDependencies -project Stoat.xcodeproj -skipMacroValidation
cd ci_scripts
