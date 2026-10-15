//
//  MPURLSecurityPolicyTests.m
//  MacDown 3000
//
//  Tests for MPURLSecurityPolicy — covers CVE-2019-12138 (directory traversal)
//  and CVE-2019-12173 (RCE via app bundle links).
//

#import <XCTest/XCTest.h>
#import "MPURLSecurityPolicy.h"
#import "MPDocument.h"
#import <WebKit/WebKit.h>

@interface MPDocument (OfflinePolicyTests)
- (NSArray *)webView:(WebView *)view
    contextMenuItemsForElement:(NSDictionary *)element
    defaultMenuItems:(NSArray *)items;
- (void)openPreviewLinkFromMenu:(NSMenuItem *)item;
- (NSURLRequest *)webView:(WebView *)view resource:(id)resource
    willSendRequest:(NSURLRequest *)request
    redirectResponse:(NSURLResponse *)response
    fromDataSource:(WebDataSource *)source;
- (void)webView:(WebView *)view
    decidePolicyForNavigationAction:(NSDictionary *)information
    request:(NSURLRequest *)request frame:(WebFrame *)frame
    decisionListener:(id<WebPolicyDecisionListener>)listener;
- (void)webView:(WebView *)view
    decidePolicyForNewWindowAction:(NSDictionary *)information
    request:(NSURLRequest *)request newFrameName:(NSString *)name
    decisionListener:(id<WebPolicyDecisionListener>)listener;
- (void)openOrCreateFileForUrl:(NSURL *)url;
@end

@interface MPOfflineRecordingDocument : MPDocument
@property (strong) NSURL *openedURL;
@end
@implementation MPOfflineRecordingDocument
- (void)openOrCreateFileForUrl:(NSURL *)url { self.openedURL = url; }
@end

@interface MPOfflineDecisionListener : NSObject <WebPolicyDecisionListener>
@property BOOL ignored;
@end
@implementation MPOfflineDecisionListener
- (void)ignore { self.ignored = YES; }
- (void)use { self.ignored = NO; }
- (void)download { self.ignored = NO; }
@end

@interface MPURLSecurityPolicyTests : XCTestCase
@property (strong) NSString *tempDir;
@property (strong) NSURL *appBundleURL;
@end


@implementation MPURLSecurityPolicyTests

- (void)setUp
{
    [super setUp];
    self.tempDir = [NSTemporaryDirectory()
        stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.tempDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    // Build a minimal .app bundle that macOS will recognize as an application.
    // Structure: Test.app/Contents/Info.plist + Contents/MacOS/Test (stub)
    // The stub executable ensures Launch Services classifies the bundle
    // correctly even on CI runners without a warm LS cache.
    NSString *bundlePath = [self.tempDir
        stringByAppendingPathComponent:@"Test.app"];
    NSString *contentsPath = [bundlePath
        stringByAppendingPathComponent:@"Contents"];
    NSString *macosPath = [contentsPath
        stringByAppendingPathComponent:@"MacOS"];
    [[NSFileManager defaultManager] createDirectoryAtPath:macosPath
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    // Minimal Info.plist required for bundle type recognition.
    NSString *plist = (
        @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        @"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\""
        @" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
        @"<plist version=\"1.0\">\n"
        @"<dict>\n"
        @"    <key>CFBundleIdentifier</key>\n"
        @"    <string>com.test.testapp</string>\n"
        @"    <key>CFBundleName</key>\n"
        @"    <string>Test</string>\n"
        @"    <key>CFBundlePackageType</key>\n"
        @"    <string>APPL</string>\n"
        @"    <key>CFBundleExecutable</key>\n"
        @"    <string>Test</string>\n"
        @"</dict>\n"
        @"</plist>\n"
    );
    [plist writeToFile:[contentsPath stringByAppendingPathComponent:@"Info.plist"]
            atomically:YES
              encoding:NSUTF8StringEncoding
                 error:nil];

    // Stub executable — a zero-byte file with the executable bit set.
    NSString *execPath = [macosPath stringByAppendingPathComponent:@"Test"];
    [@"" writeToFile:execPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @(0755)}
                                     ofItemAtPath:execPath
                                            error:nil];

    self.appBundleURL = [NSURL fileURLWithPath:bundlePath];
}

- (void)tearDown
{
    [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:nil];
    [super tearDown];
}

#pragma mark - isExecutableOrAppBundleAtURL: Tests

- (void)testAppBundleDetectedAsExecutable
{
    // .app bundle with Contents/Info.plist should be detected as dangerous.
    XCTAssertTrue([MPURLSecurityPolicy isExecutableOrAppBundleAtURL:self.appBundleURL],
                  @"App bundle should be detected as executable/dangerous");
}

- (void)testPlainTextFileNotDetectedAsExecutable
{
    NSString *txtPath = [self.tempDir stringByAppendingPathComponent:@"readme.txt"];
    [@"hello world" writeToFile:txtPath
                     atomically:YES
                       encoding:NSUTF8StringEncoding
                          error:nil];
    NSURL *txtURL = [NSURL fileURLWithPath:txtPath];

    XCTAssertFalse([MPURLSecurityPolicy isExecutableOrAppBundleAtURL:txtURL],
                   @"Plain text file should not be detected as executable");
}

- (void)testPlainDirectoryNotDetectedAsExecutable
{
    NSString *dirPath = [self.tempDir stringByAppendingPathComponent:@"plain_dir"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dirPath
                              withIntermediateDirectories:NO
                                               attributes:nil
                                                    error:nil];
    NSURL *dirURL = [NSURL fileURLWithPath:dirPath];

    XCTAssertFalse([MPURLSecurityPolicy isExecutableOrAppBundleAtURL:dirURL],
                   @"Plain directory should not be detected as executable");
}

- (void)testSymlinkToAppBundleDetectedAsExecutable
{
    // Symlink pointing to an .app bundle should be resolved and flagged.
    NSString *symlinkPath = [self.tempDir stringByAppendingPathComponent:@"link.app"];
    [[NSFileManager defaultManager] createSymbolicLinkAtPath:symlinkPath
                                         withDestinationPath:self.appBundleURL.path
                                                       error:nil];
    NSURL *symlinkURL = [NSURL fileURLWithPath:symlinkPath];

    XCTAssertTrue([MPURLSecurityPolicy isExecutableOrAppBundleAtURL:symlinkURL],
                  @"Symlink to app bundle should be detected as executable after resolution");
}

- (void)testExecutableScriptDetectedAsExecutable
{
    // A file with the executable bit set should be flagged.
    NSString *scriptPath = [self.tempDir stringByAppendingPathComponent:@"script.sh"];
    [@"#!/bin/sh\necho hello\n" writeToFile:scriptPath
                                 atomically:YES
                                   encoding:NSUTF8StringEncoding
                                      error:nil];
    // Set executable bit (chmod +x).
    NSDictionary *attrs = @{NSFilePosixPermissions: @(0755)};
    [[NSFileManager defaultManager] setAttributes:attrs
                                     ofItemAtPath:scriptPath
                                            error:nil];
    NSURL *scriptURL = [NSURL fileURLWithPath:scriptPath];

    XCTAssertTrue([MPURLSecurityPolicy isExecutableOrAppBundleAtURL:scriptURL],
                  @"File with executable bit set should be detected as executable");
}

- (void)testNonExistentPathNotDetectedAsExecutable
{
    NSURL *missingURL = [NSURL fileURLWithPath:@"/tmp/nonexistent_file_that_does_not_exist_xyzzy"];

    // Should return NO gracefully rather than crash or throw.
    XCTAssertFalse([MPURLSecurityPolicy isExecutableOrAppBundleAtURL:missingURL],
                   @"Non-existent path should return NO gracefully");
}

- (void)testNilURLNotDetectedAsExecutable
{
    XCTAssertFalse([MPURLSecurityPolicy isExecutableOrAppBundleAtURL:nil],
                   @"Nil URL should return NO");
}

- (void)testBundlePluginDetectedAsDangerous
{
    // A .bundle package (CFBundlePackageType = BNDL) should be caught too,
    // not just .app bundles — plugins can contain executable code.
    NSString *bundlePath = [self.tempDir
        stringByAppendingPathComponent:@"Evil.bundle"];
    NSString *contentsPath = [bundlePath
        stringByAppendingPathComponent:@"Contents"];
    [[NSFileManager defaultManager] createDirectoryAtPath:contentsPath
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSString *plist = (
        @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        @"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\""
        @" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
        @"<plist version=\"1.0\">\n"
        @"<dict>\n"
        @"    <key>CFBundleIdentifier</key>\n"
        @"    <string>com.test.evilbundle</string>\n"
        @"    <key>CFBundleName</key>\n"
        @"    <string>Evil</string>\n"
        @"    <key>CFBundlePackageType</key>\n"
        @"    <string>BNDL</string>\n"
        @"</dict>\n"
        @"</plist>\n"
    );
    [plist writeToFile:[contentsPath stringByAppendingPathComponent:@"Info.plist"]
            atomically:YES
              encoding:NSUTF8StringEncoding
                 error:nil];
    NSURL *bundleURL = [NSURL fileURLWithPath:bundlePath];

    XCTAssertTrue([MPURLSecurityPolicy isExecutableOrAppBundleAtURL:bundleURL],
                  @".bundle plugin package should be detected as dangerous");
}

#pragma mark - url:isWithinScopeOfBaseURL: Tests

- (void)testFileInSameDirectoryIsInScope
{
    // Base: /tmp/docs/file.md — target: /tmp/docs/image.png
    // Both are in the same directory; target should be in scope.
    NSString *docsDir = [self.tempDir stringByAppendingPathComponent:@"docs"];
    [[NSFileManager defaultManager] createDirectoryAtPath:docsDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSURL *baseURL = [NSURL fileURLWithPath:
        [docsDir stringByAppendingPathComponent:@"file.md"]];
    NSURL *targetURL = [NSURL fileURLWithPath:
        [docsDir stringByAppendingPathComponent:@"image.png"]];

    XCTAssertTrue([MPURLSecurityPolicy url:targetURL isWithinScopeOfBaseURL:baseURL],
                  @"File in same directory should be in scope");
}

- (void)testFileInSubdirectoryIsInScope
{
    // Base: /tmp/docs/file.md — target: /tmp/docs/sub/image.png
    // Subdirectory of the base's parent should be in scope.
    NSString *docsDir = [self.tempDir stringByAppendingPathComponent:@"docs"];
    NSString *subDir = [docsDir stringByAppendingPathComponent:@"sub"];
    [[NSFileManager defaultManager] createDirectoryAtPath:subDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSURL *baseURL = [NSURL fileURLWithPath:
        [docsDir stringByAppendingPathComponent:@"file.md"]];
    NSURL *targetURL = [NSURL fileURLWithPath:
        [subDir stringByAppendingPathComponent:@"image.png"]];

    XCTAssertTrue([MPURLSecurityPolicy url:targetURL isWithinScopeOfBaseURL:baseURL],
                  @"File in subdirectory should be in scope");
}

- (void)testFileOutsideDirectoryIsNotInScope
{
    // Base: /tmp/docs/file.md — target: /tmp/other/evil.app
    // A different sibling of /tmp should not be in scope.
    NSString *docsDir = [self.tempDir stringByAppendingPathComponent:@"docs"];
    NSString *otherDir = [self.tempDir stringByAppendingPathComponent:@"other"];
    [[NSFileManager defaultManager] createDirectoryAtPath:docsDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:otherDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSURL *baseURL = [NSURL fileURLWithPath:
        [docsDir stringByAppendingPathComponent:@"file.md"]];
    NSURL *targetURL = [NSURL fileURLWithPath:
        [otherDir stringByAppendingPathComponent:@"evil.app"]];

    XCTAssertFalse([MPURLSecurityPolicy url:targetURL isWithinScopeOfBaseURL:baseURL],
                   @"File outside base directory should not be in scope");
}

- (void)testDotDotTraversalIsNotInScope
{
    // Base: /tmp/docs/file.md — target: /tmp/docs/../other/evil
    // After resolution, /tmp/other/evil is outside /tmp/docs/ and must be rejected.
    NSString *docsDir = [self.tempDir stringByAppendingPathComponent:@"docs"];
    NSString *otherDir = [self.tempDir stringByAppendingPathComponent:@"other"];
    [[NSFileManager defaultManager] createDirectoryAtPath:docsDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:otherDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSURL *baseURL = [NSURL fileURLWithPath:
        [docsDir stringByAppendingPathComponent:@"file.md"]];
    // Construct a path that uses ".." to escape the docs directory.
    NSString *traversalPath = [docsDir stringByAppendingPathComponent:
        @"../other/evil"];
    NSURL *targetURL = [NSURL fileURLWithPath:traversalPath];

    XCTAssertFalse([MPURLSecurityPolicy url:targetURL isWithinScopeOfBaseURL:baseURL],
                   @"Path traversal via .. should not be in scope after resolution");
}

- (void)testNilBaseURLReturnsFalse
{
    NSURL *targetURL = [NSURL fileURLWithPath:
        [self.tempDir stringByAppendingPathComponent:@"file.png"]];

    XCTAssertFalse([MPURLSecurityPolicy url:targetURL isWithinScopeOfBaseURL:nil],
                   @"Nil baseURL should return NO");
}

- (void)testNonFileTargetURLReturnsFalse
{
    // HTTPS URLs are not file URLs and must always be rejected for scope checks.
    NSURL *baseURL = [NSURL fileURLWithPath:
        [self.tempDir stringByAppendingPathComponent:@"file.md"]];
    NSURL *targetURL = [NSURL URLWithString:@"https://example.com/image.png"];

    XCTAssertFalse([MPURLSecurityPolicy url:targetURL isWithinScopeOfBaseURL:baseURL],
                   @"Non-file target URL should return NO");
}

- (void)testNilTargetURLReturnsFalse
{
    NSURL *baseURL = [NSURL fileURLWithPath:
        [self.tempDir stringByAppendingPathComponent:@"file.md"]];

    XCTAssertFalse([MPURLSecurityPolicy url:nil isWithinScopeOfBaseURL:baseURL],
                   @"Nil targetURL should return NO");
}

- (void)testSymlinkEscapeIsNotInScope
{
    // A symlink inside the document directory that points outside it must be
    // caught after symlink resolution. This is a distinct vector from ../
    // traversal: the unresolved path looks in-scope but resolves outside it.
    NSString *docsDir = [self.tempDir stringByAppendingPathComponent:@"docs"];
    NSString *outsideDir = [self.tempDir stringByAppendingPathComponent:@"outside"];
    [[NSFileManager defaultManager] createDirectoryAtPath:docsDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:outsideDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    // Create a symlink inside docs/ pointing to the outside directory.
    NSString *symlinkPath = [docsDir stringByAppendingPathComponent:@"escape"];
    [[NSFileManager defaultManager] createSymbolicLinkAtPath:symlinkPath
                                         withDestinationPath:outsideDir
                                                       error:nil];

    NSURL *baseURL = [NSURL fileURLWithPath:
        [docsDir stringByAppendingPathComponent:@"file.md"]];
    NSURL *targetURL = [NSURL fileURLWithPath:
        [symlinkPath stringByAppendingPathComponent:@"evil.app"]];

    XCTAssertFalse([MPURLSecurityPolicy url:targetURL isWithinScopeOfBaseURL:baseURL],
                   @"Symlink escaping directory scope must be rejected after resolution");
}


#pragma mark - Automatic resource requests and user activation

- (void)testAutomaticNetworkSchemesAreDenied
{
    MPDocument *document = [[MPDocument alloc] init];
    NSArray *urls = @[@"https://example.invalid/pixel", @"http://127.0.0.1/",
        @"ftp://example.invalid/file", @"wss://example.invalid/",
        @"file://example.invalid/share/image.png", @"javascript:alert(1)"];
    for (NSString *value in urls)
    {
        NSURL *url = [NSURL URLWithString:value];
        XCTAssertFalse([MPURLSecurityPolicy isAllowedPreviewResourceURL:url]);
        NSURLRequest *request = [NSURLRequest requestWithURL:url];
        XCTAssertNil([document webView:nil resource:nil willSendRequest:request
            redirectResponse:nil fromDataSource:nil], @"%@", value);
        NSURLResponse *redirect = [[NSURLResponse alloc]
            initWithURL:[NSURL fileURLWithPath:@"/tmp/local.png"]
            MIMEType:@"image/png" expectedContentLength:0 textEncodingName:nil];
        XCTAssertNil([document webView:nil resource:nil willSendRequest:request
            redirectResponse:redirect fromDataSource:nil], @"%@", value);
    }
    XCTAssertFalse([MPURLSecurityPolicy isAllowedPreviewResourceURL:nil]);
}

- (void)testAutomaticLocalAndEmbeddedResourcesRemainAvailable
{
    MPDocument *document = [[MPDocument alloc] init];
    for (NSString *value in @[@"file:///tmp/image.png",
        @"data:image/png;base64,AAAA", @"about:blank"])
    {
        NSURLRequest *request = [NSURLRequest requestWithURL:
            [NSURL URLWithString:value]];
        XCTAssertEqualObjects([document webView:nil resource:nil
            willSendRequest:request redirectResponse:nil fromDataSource:nil],
            request);
    }
}

- (void)testDOMClicksCannotOpenLinksButNativeMenuCan
{
    MPOfflineRecordingDocument *document =
        [[MPOfflineRecordingDocument alloc] init];
    NSURLRequest *request = [NSURLRequest requestWithURL:
        [NSURL URLWithString:@"https://example.invalid/"]];
    MPOfflineDecisionListener *listener = [[MPOfflineDecisionListener alloc] init];
    [document webView:nil decidePolicyForNavigationAction:@{
        WebActionNavigationTypeKey: @(WebNavigationTypeLinkClicked)}
        request:request frame:nil decisionListener:listener];
    XCTAssertTrue(listener.ignored);
    XCTAssertNil(document.openedURL);

    NSMenuItem *unsafe = [[NSMenuItem alloc] initWithTitle:@"Old open"
        action:NULL keyEquivalent:@""];
    unsafe.tag = WebMenuItemTagOpenLinkInNewWindow;
    NSMenuItem *download = [[NSMenuItem alloc] initWithTitle:@"Old download"
        action:NULL keyEquivalent:@""];
    download.tag = WebMenuItemTagDownloadLinkToDisk;
    NSArray *menu = [document webView:nil contextMenuItemsForElement:@{
        WebElementLinkURLKey: request.URL}
        defaultMenuItems:@[unsafe, download]];
    XCTAssertEqual(menu.count, (NSUInteger)1);
    NSMenuItem *open = menu.firstObject;
    XCTAssertEqualObjects(open.title, @"Open Link in Browser");
    XCTAssertEqual(open.action, @selector(openPreviewLinkFromMenu:));
    XCTAssertEqual(open.target, document);
    [document openPreviewLinkFromMenu:open];
    XCTAssertEqualObjects(document.openedURL, request.URL);

    NSArray *custom = [document webView:nil contextMenuItemsForElement:@{
        WebElementLinkURLKey: [NSURL URLWithString:@"some-app:payload"]}
        defaultMenuItems:@[unsafe, download]];
    XCTAssertEqual(custom.count, (NSUInteger)0);
}

- (void)testUnknownPreviewMenuActionsAreRejected
{
    MPDocument *document = [[MPDocument alloc] init];
    for (NSNumber *tag in @[@0, @(WebMenuItemTagOther), @10000])
    {
        NSMenuItem *unknown = [[NSMenuItem alloc] initWithTitle:@"Open Link"
            action:NSSelectorFromString(@"forwardContextMenuAction:")
            keyEquivalent:@""];
        unknown.tag = tag.integerValue;
        NSArray *menu = [document webView:nil contextMenuItemsForElement:@{
            WebElementLinkURLKey: [NSURL URLWithString:@"some-app:payload"]}
            defaultMenuItems:@[unknown]];
        XCTAssertEqual(menu.count, (NSUInteger)0,
            @"Private/unknown WebKit actions must not bypass the opener");
    }
}

- (void)testPreviewMenuPreservesCopyAndUsesNativeReload
{
    MPDocument *document = [[MPDocument alloc] init];
    NSMutableArray *defaults = [NSMutableArray array];
    for (NSNumber *tag in @[@(WebMenuItemTagCopy),
        @(WebMenuItemTagCopyLinkToClipboard),
        @(WebMenuItemTagCopyImageToClipboard), @(WebMenuItemTagReload)])
    {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Default"
            action:NSSelectorFromString(@"forwardContextMenuAction:")
            keyEquivalent:@""];
        item.tag = tag.integerValue;
        [defaults addObject:item];
    }
    NSArray *menu = [document webView:nil contextMenuItemsForElement:@{}
        defaultMenuItems:defaults];
    XCTAssertEqual(menu.count, (NSUInteger)4);
    for (NSUInteger i = 0; i < 3; i++)
        XCTAssertEqual(menu[i], defaults[i]);
    NSMenuItem *reload = menu.lastObject;
    XCTAssertEqual(reload.target, document);
    XCTAssertEqual(reload.action, NSSelectorFromString(@"reloadPreview:"));
    XCTAssertNotEqual(reload, defaults.lastObject);
}

- (void)testSiblingHTMLCannotReplaceProtectedPreview
{
    MPDocument *document = [[MPDocument alloc] init];
    NSURL *base = [NSURL fileURLWithPath:
        [self.tempDir stringByAppendingPathComponent:@".macdown-preview-base"]];
    [document setValue:base forKey:@"currentBaseUrl"];
    MPOfflineDecisionListener *listener = [[MPOfflineDecisionListener alloc] init];
    NSURL *sibling = [NSURL fileURLWithPath:
        [self.tempDir stringByAppendingPathComponent:@"payload.html"]];
    [document webView:nil decidePolicyForNavigationAction:@{
        WebActionNavigationTypeKey: @(WebNavigationTypeOther)}
        request:[NSURLRequest requestWithURL:sibling] frame:nil
        decisionListener:listener];
    XCTAssertTrue(listener.ignored);
    NSURL *anchor = [NSURL URLWithString:
        [base.absoluteString stringByAppendingString:@"#heading"]];
    [document webView:nil decidePolicyForNavigationAction:@{
        WebActionNavigationTypeKey: @(WebNavigationTypeLinkClicked)}
        request:[NSURLRequest requestWithURL:anchor] frame:nil
        decisionListener:listener];
    XCTAssertFalse(listener.ignored, @"Same-page anchors must still work");
}

- (void)testScriptedHTTPNavigationIsIgnored
{
    MPDocument *document = [[MPDocument alloc] init];
    MPOfflineDecisionListener *listener = [[MPOfflineDecisionListener alloc] init];
    [document webView:nil decidePolicyForNavigationAction:@{
        WebActionNavigationTypeKey: @(WebNavigationTypeOther)}
        request:[NSURLRequest requestWithURL:
            [NSURL URLWithString:@"https://example.invalid/"]]
        frame:nil decisionListener:listener];
    XCTAssertTrue(listener.ignored);
}


- (void)testPreviewCannotOpenNewWebWindows
{
    MPDocument *document = [[MPDocument alloc] init];
    MPOfflineDecisionListener *listener = [[MPOfflineDecisionListener alloc] init];
    [document webView:nil decidePolicyForNewWindowAction:@{}
        request:[NSURLRequest requestWithURL:
            [NSURL URLWithString:@"https://example.invalid/"]]
        newFrameName:@"_blank" decisionListener:listener];
    XCTAssertTrue(listener.ignored);
}


- (void)testGeneratedLoadPermissionIsSingleUse
{
    MPDocument *document = [[MPDocument alloc] init];
    NSURL *base = [NSURL fileURLWithPath:
        [self.tempDir stringByAppendingPathComponent:@".macdown-preview-base"]];
    [document setValue:base forKey:@"currentBaseUrl"];
    [document setValue:@YES forKey:@"awaitingGeneratedPreview"];
    MPOfflineDecisionListener *listener = [[MPOfflineDecisionListener alloc] init];
    NSDictionary *other = @{WebActionNavigationTypeKey: @(WebNavigationTypeOther)};
    [document webView:nil decidePolicyForNavigationAction:other
        request:[NSURLRequest requestWithURL:base] frame:nil
        decisionListener:listener];
    XCTAssertFalse(listener.ignored, @"App-owned generated load is permitted");
    for (NSURL *url in @[base, [NSURL URLWithString:@"about:blank"],
        [NSURL URLWithString:[base.absoluteString stringByAppendingString:@"?x=1"]],
        [NSURL URLWithString:[base.absoluteString stringByAppendingString:@"?x=1#h"]]])
    {
        [document webView:nil decidePolicyForNavigationAction:other
            request:[NSURLRequest requestWithURL:url] frame:nil
            decisionListener:listener];
        XCTAssertTrue(listener.ignored, @"A later bare/query navigation is denied");
    }
    [document webView:nil decidePolicyForNavigationAction:@{
        WebActionNavigationTypeKey: @(WebNavigationTypeReload)}
        request:[NSURLRequest requestWithURL:base] frame:nil
        decisionListener:listener];
    XCTAssertTrue(listener.ignored, @"Reload cannot fetch a planted base file");
}

@end
