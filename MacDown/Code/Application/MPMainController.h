//
//  MPMainController.h
//  MacDown 3000
//
//  Created by Tzu-ping Chung  on 7/06/2014.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import <Foundation/Foundation.h>
@class MPPreferences;

@interface MPMainController : NSObject <NSApplicationDelegate, NSMenuItemValidation>

@property (nonatomic, readonly) MPPreferences *preferences;

/** Inert, disabled target of the localized "Check for Updates…" menu item. */
- (IBAction)checkForUpdates:(id)sender;

/** Prompts for a directory and opens it as a folder workspace; target of the
    "Open Folder…" main-menu item. */
- (IBAction)openFolder:(id)sender;

@end
