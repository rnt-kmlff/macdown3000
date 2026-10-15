#import <Cocoa/Cocoa.h>
#import <XCTest/XCTest.h>
#import "MPMainController.h"
#import "MPGlobals.h"

@interface MPUpdaterTests : XCTestCase
@end

@implementation MPUpdaterTests

- (void)testForkHasNoUpdateFeedOrTrustedUpstreamKey
{
    NSDictionary *info = [NSBundle mainBundle].infoDictionary;
    XCTAssertNil(info[@"SUFeedURL"]);
    XCTAssertNil(info[@"SUBetaFeedURL"]);
    XCTAssertNil(info[@"SUPublicEDKey"]);
    XCTAssertFalse([info[@"SUEnableAutomaticChecks"] boolValue]);
    XCTAssertFalse([info[@"SUAllowsAutomaticUpdates"] boolValue]);
}

- (void)assertUpdaterIsAbsent
{
    NSString *framework = [[NSBundle mainBundle].privateFrameworksPath
        stringByAppendingPathComponent:@"Sparkle.framework"];
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:framework]);
    XCTAssertNil(NSClassFromString(@"SPUUpdater"));
    XCTAssertNil(NSClassFromString(@"SPUStandardUpdaterController"));
}

- (void)testForkNeverBundlesOrLoadsAnUpdater
{
    MPMainController *controller = [[MPMainController alloc] init];
    [self assertUpdaterIsAbsent];
    MPMainController *realDelegate = (MPMainController *)NSApp.delegate;
    XCTAssertNotNil(realDelegate);
    XCTAssertFalse([realDelegate respondsToSelector:
        NSSelectorFromString(@"updaterController")]);
    [controller applicationDidFinishLaunching:nil];
    [self assertUpdaterIsAbsent];
    [controller checkForUpdates:nil];
    [self assertUpdaterIsAbsent];
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Check for Updates"
        action:@selector(checkForUpdates:) keyEquivalent:@""];
    XCTAssertFalse([controller validateMenuItem:item]);
}

- (void)testForkIdentityAndPreferencesAreIsolated
{
    XCTAssertTrue([[NSBundle mainBundle].bundleIdentifier
        hasPrefix:@"io.github.rnt-kmlff.macdownlocal"]);
    XCTAssertEqualObjects(kMPApplicationSuiteName,
        @"io.github.rnt-kmlff.macdownlocal");
    XCTAssertEqualObjects([NSBundle mainBundle].infoDictionary[@"CFBundleName"],
        @"MacDown Local");
    NSArray *types = [NSBundle mainBundle].infoDictionary[@"CFBundleURLTypes"];
    XCTAssertEqualObjects(types[0][@"CFBundleURLSchemes"],
        (@[@"x-macdown-local"]));
    XCTAssertFalse([NSClassFromString(@"MPPreferences") instancesRespondToSelector:
        NSSelectorFromString(@"migratePreferencesFromLegacyBundleIdentifierIfNeeded")]);
}

@end
