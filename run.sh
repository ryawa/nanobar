#!/bin/bash

xcodebuild -workspace nanobar.xcodeproj/project.xcworkspace -scheme nanobar build
open ~/Library/Developer/Xcode/DerivedData/*/Build/Products/Debug/nanobar.app
