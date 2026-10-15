//
//  MPGlobals.h
//  MacDown 3000
//
//  Created by Tzu-ping Chung on 02/12.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import "version.h"

// These should match the main bundle's values.
static NSString * const kMPApplicationName = @"MacDown Local";

#ifdef DEBUG
static NSString * const kMPApplicationBundleIdentifier = @"io.github.rnt-kmlff.macdownlocal-debug";
#else
static NSString * const kMPApplicationBundleIdentifier = @"io.github.rnt-kmlff.macdownlocal";
#endif

static NSString * const kMPApplicationSuiteName = @"io.github.rnt-kmlff.macdownlocal";

static NSString * const MPCommandInstallationPath = @"/usr/local/bin/macdown-local";
static NSString * const kMPCommandName = @"macdown-local";

static NSString * const kMPHelpKey = @"help";
static NSString * const kMPVersionKey = @"version";

static NSString * const kMPFilesToOpenKey = @"filesToOpenOnNextLaunch";
static NSString * const kMPPipedContentFileToOpen = @"pipedContentFileToOpenOnNextLaunch";
static NSString * const kMPFoldersToOpenKey = @"foldersToOpenOnNextLaunch";
