//
//  MPImageRenderingTests.m
//  MacDownTests
//
//  Regression coverage for GitHub issue #341: "Loss of all image rendering
//  in preview." Images that container-render (correct size/border) but never
//  load their bits are the symptom of something in the render pipeline
//  dropping or blocking the image source.
//
//  The offline fork preserves local/data images and blocks web resources.
//

#import <XCTest/XCTest.h>
#import "MPRenderer.h"
#import "MPRendererTestHelpers.h"
#import "hoedown/document.h"
#import "hoedown_html_patch.h"
#import <WebKit/WebKit.h>
#import "MPDocument.h"


@interface MPImageRenderingTests : XCTestCase
@property (nonatomic, strong) MPRenderer *renderer;
@property (nonatomic, strong) MPMockRendererDataSource *dataSource;
@property (nonatomic, strong) MPMockRendererDelegate *delegate;
@end


@implementation MPImageRenderingTests

- (void)setUp
{
    [super setUp];

    self.dataSource = [[MPMockRendererDataSource alloc] init];
    self.delegate = [[MPMockRendererDelegate alloc] init];

    self.renderer = [[MPRenderer alloc] init];
    self.renderer.dataSource = self.dataSource;
    self.renderer.delegate = self.delegate;
}

- (void)tearDown
{
    self.renderer = nil;
    self.dataSource = nil;
    self.delegate = nil;
    [super tearDown];
}

// Renders the given markdown through the live preview path and returns the
// full preview HTML (including head/CSP) captured by the mock delegate.
- (NSString *)previewHTMLForMarkdown:(NSString *)markdown
{
    self.dataSource.markdown = markdown;
    [self.renderer parseMarkdown:markdown];
    [self.renderer render];
    return self.delegate.lastHTML;
}


#pragma mark - Image src is preserved end-to-end across all sources

- (void)testPreviewPreservesHTTPSImageSource
{
    NSString *html =
        [self previewHTMLForMarkdown:@"![alt](https://example.com/photo.png)"];

    XCTAssertNotNil(html, @"Preview render should produce HTML");
    XCTAssertTrue([html containsString:@"<img"],
                  @"Preview HTML should contain an image element");
    XCTAssertTrue([html containsString:@"https://example.com/photo.png"],
                  @"Preview HTML must preserve the https image source");
}

- (void)testPreviewPreservesHTTPImageSource
{
    NSString *html =
        [self previewHTMLForMarkdown:@"![alt](http://example.com/photo.png)"];

    XCTAssertTrue([html containsString:@"http://example.com/photo.png"],
                  @"Preview HTML must preserve the http image source");
}

- (void)testPreviewPreservesLocalFileImageSource
{
    // Relative local path, as written for a sidecar image next to the document.
    NSString *html =
        [self previewHTMLForMarkdown:@"![alt](images/photo.png)"];

    XCTAssertTrue([html containsString:@"images/photo.png"],
                  @"Preview HTML must preserve the local file image source");
}

- (void)testPreviewPreservesAbsoluteFileURLImageSource
{
    NSString *html =
        [self previewHTMLForMarkdown:@"![alt](file:///tmp/photo.png)"];

    XCTAssertTrue([html containsString:@"file:///tmp/photo.png"],
                  @"Preview HTML must preserve the file:// image source");
}

- (void)testPreviewPreservesDataURIImageSource
{
    // A 1x1 transparent PNG as a data URI.
    NSString *dataURI = @"data:image/png;base64,"
        @"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==";
    NSString *markdown =
        [NSString stringWithFormat:@"![alt](%@)", dataURI];

    NSString *html = [self previewHTMLForMarkdown:markdown];

    XCTAssertTrue([html containsString:@"data:image/png;base64,"],
                  @"Preview HTML must preserve the data URI image source");
}


#pragma mark - Preview network isolation

- (void)testPreviewCSPAllowsOnlyLocalAndEmbeddedImages
{
    NSString *html = [self previewHTMLForMarkdown:@"# Heading"];

    XCTAssertTrue([html containsString:@"Content-Security-Policy"],
                  @"Preview HTML should include a CSP meta tag");
    XCTAssertTrue([html containsString:@"img-src data: file:;"],
                  @"Local/data images must remain available");
    XCTAssertFalse([html containsString:@"img-src data: file: http:"],
                   @"Web images must not load automatically");
    XCTAssertTrue([html containsString:@"connect-src &#39;none&#39;"],
                  @"XHR/fetch and other connections must be blocked");
}

- (void)testPreviewCSPAllowsOnlyLocalAndEmbeddedMedia
{
    NSString *html = [self previewHTMLForMarkdown:@"# Heading"];

    XCTAssertTrue([html containsString:@"media-src data: file:;"],
                  @"Media sources must be local or embedded");
}

@end

// Observe real legacy-WebView requests, including a positive control proving
// the interceptor is active. No test request leaves this process.
static NSUInteger MPOfflineObservedRequests;
@interface MPOfflineTestProtocol : NSURLProtocol
@end
@implementation MPOfflineTestProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request
{
    return [request.URL.host isEqualToString:@"offline.invalid"];
}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request
{
    return request;
}
- (void)startLoading
{
    MPOfflineObservedRequests++;
    NSData *png = [[NSData alloc] initWithBase64EncodedString:
        @"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGP4DwQACfsD/fteaysAAAAASUVORK5CYII="
        options:0];
    NSURLResponse *response = [[NSURLResponse alloc] initWithURL:self.request.URL
        MIMEType:@"image/png" expectedContentLength:png.length
        textEncodingName:nil];
    [self.client URLProtocol:self didReceiveResponse:response
        cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:png];
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end

@interface MPOfflineFrameObserver : NSObject <WebFrameLoadDelegate>
@property (strong) XCTestExpectation *loaded;
@property BOOL completed;
@end
@implementation MPOfflineFrameObserver
- (void)webView:(WebView *)view didFinishLoadForFrame:(WebFrame *)frame
{
    if (frame == view.mainFrame && !self.completed)
    {
        self.completed = YES;
        [self.loaded fulfill];
    }
}
@end

@interface MPOfflineWebViewTests : XCTestCase
@end
@implementation MPOfflineWebViewTests

- (void)testRealPreviewBlocksWebRequestsAndLoadsEmbeddedImage
{
    NSString *imagePath = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [[[NSUUID UUID] UUIDString] stringByAppendingPathExtension:@"png"]];
    NSData *localPNG = [[NSData alloc] initWithBase64EncodedString:
        @"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGP4DwQACfsD/fteaysAAAAASUVORK5CYII=" options:0];
    XCTAssertTrue([localPNG writeToFile:imagePath atomically:YES]);
    [NSURLProtocol registerClass:[MPOfflineTestProtocol class]];
    @try
    {
        MPOfflineObservedRequests = 0;
        WebView *control = [[WebView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
        MPOfflineFrameObserver *controlObserver = [[MPOfflineFrameObserver alloc] init];
        controlObserver.loaded = [self expectationWithDescription:@"network control"];
        control.frameLoadDelegate = controlObserver;
        [control.mainFrame loadHTMLString:
            @"<img src='https://offline.invalid/control.png'>" baseURL:nil];
        [self waitForExpectations:@[controlObserver.loaded] timeout:10];
        XCTAssertGreaterThan(MPOfflineObservedRequests, (NSUInteger)0,
            @"Positive control must prove WebView request observation works");
        [control close];

        MPMockRendererDataSource *source = [[MPMockRendererDataSource alloc] init];
        source.markdown = @"<img src='https://offline.invalid/pixel.png'>"
            "<link rel='stylesheet' href='https://offline.invalid/style.css'>"
            "<script src='https://offline.invalid/code.js'></script>"
            "<style>p {background:url(https://offline.invalid/css.png)}</style>"
            "<video src='https://offline.invalid/movie.mp4'></video>"
            "<img id='local' src='data:image/png;base64,"
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGP4DwQACfsD/fteaysAAAAASUVORK5CYII='>";
        source.markdown = [source.markdown stringByAppendingFormat:
            @"<img id='sidecar' src='%@'>",
            [NSURL fileURLWithPath:imagePath].absoluteString];
        MPMockRendererDelegate *delegate = [[MPMockRendererDelegate alloc] init];
        MPRenderer *renderer = [[MPRenderer alloc] init];
        renderer.dataSource = source;
        renderer.delegate = delegate;
        [renderer parseMarkdown:source.markdown];
        [renderer render];
        MPDocument *document = [[MPDocument alloc] init];
        MPOfflineObservedRequests = 0;
        WebView *preview = [[WebView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
        MPOfflineFrameObserver *observer = [[MPOfflineFrameObserver alloc] init];
        observer.loaded = [self expectationWithDescription:@"offline preview"];
        preview.frameLoadDelegate = observer;
        preview.resourceLoadDelegate = document;
        [preview.mainFrame loadHTMLString:delegate.lastHTML baseURL:nil];
        [self waitForExpectations:@[observer.loaded] timeout:10];
        XCTAssertEqual(MPOfflineObservedRequests, (NSUInteger)0);
        XCTAssertEqualObjects([preview stringByEvaluatingJavaScriptFromString:
            @"document.getElementById('local').naturalWidth.toString()"], @"1");
        XCTAssertEqualObjects([preview stringByEvaluatingJavaScriptFromString:
            @"document.getElementById('sidecar').naturalWidth.toString()"], @"1");
        [preview close];
    }
    @finally
    {
        [NSURLProtocol unregisterClass:[MPOfflineTestProtocol class]];
        [[NSFileManager defaultManager] removeItemAtPath:imagePath error:NULL];
    }
}

- (void)testMathAssetsExistAndUseOnlyALocalLoader
{
    MPMockRendererDataSource *source = [[MPMockRendererDataSource alloc] init];
    source.markdown = @"$$x^2 + y^2$$";
    MPMockRendererDelegate *delegate = [[MPMockRendererDelegate alloc] init];
    delegate.mathJax = YES;
    delegate.extensions = HOEDOWN_EXT_MATH;
    MPRenderer *renderer = [[MPRenderer alloc] init];
    renderer.dataSource = source;
    renderer.delegate = delegate;
    [renderer parseMarkdown:source.markdown];
    [renderer render];
    XCTAssertTrue([delegate.lastHTML containsString:@"MathJax/Offline/MathJax.js"]);
    XCTAssertFalse([delegate.lastHTML containsString:@"cdnjs.cloudflare.com"]);
    NSBundle *bundle = [NSBundle mainBundle];
    for (NSString *asset in @[@"MathJax.js", @"config/TeX-AMS-MML_HTMLorMML.js",
        @"jax/input/TeX/jax.js", @"jax/output/HTML-CSS/jax.js",
        @"fonts/HTML-CSS/TeX/woff/MathJax_Main-Regular.woff"])
    {
        NSString *path = [bundle.resourcePath stringByAppendingPathComponent:
            [@"MathJax/Offline" stringByAppendingPathComponent:asset]];
        XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:path],
            @"Missing offline math asset: %@", asset);
    }
    MPDocument *document = [[MPDocument alloc] init];
    WebView *preview = [[WebView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    preview.resourceLoadDelegate = document;
    [preview.mainFrame loadHTMLString:delegate.lastHTML baseURL:nil];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:15];
    NSString *completed = @"false";
    while ([deadline timeIntervalSinceNow] > 0)
    {
        completed = [preview stringByEvaluatingJavaScriptFromString:
            @"!!(window.MathJax && MathJax.Hub && !MathJax.Hub.queue.pending"
             " && document.querySelector('.MathJax_Display'))"];
        if ([completed isEqualToString:@"true"])
            break;
        [[NSRunLoop mainRunLoop] runUntilDate:
            [NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
    XCTAssertEqualObjects(completed, @"true",
        @"A complete math expression must typeset without a CDN");
    [preview close];

}

@end
