//
//  StashNativeDesktopTests.mm
//  StashNativeDesktopTests
//
//  Facade and ABI checks that need the macOS host (the shared contract has its own C++ tests).
//

#import <XCTest/XCTest.h>
#import "StashNativeCard.h"
#import "StashNativeCardPrivate.h"

#include <algorithm>
#include <atomic>
#include <string>
#include <unistd.h>

#include "StashDesktopConfig.h"
#include "StashNativeDesktop.h"
#include "StashSdkScript.h"

#include <vector>

static std::string gLastEventType;
static std::string gLastEventPayload;
static std::vector<std::string> gEventTypes;

static void STASH_NATIVE_DESKTOP_CALL RecordEvent(const char *type, const char *payload, void *userData) {
    (void)userData;
    gLastEventType = type ?: "";
    gLastEventPayload = payload ?: "";
    gEventTypes.push_back(gLastEventType);
}

@interface StashNativeDesktopTests : XCTestCase
@end

@implementation StashNativeDesktopTests

- (void)testSdkVersionMatchesAbiVersion {
    XCTAssertEqualObjects([StashNativeCard sdkVersion], @STASH_NATIVE_DESKTOP_VERSION);
    XCTAssertEqual(strcmp(StashNativeDesktop_GetVersion(), STASH_NATIVE_DESKTOP_VERSION), 0);
    XCTAssertTrue([[StashNativeCard sdkVersion] containsString:@"."]);
}

- (void)testSharedInstanceReturnsSameObject {
    XCTAssertTrue([StashNativeCard sharedInstance] == [StashNativeCard sharedInstance]);
}

- (void)testCardConfigDefaults {
    StashNativeCardConfig *cfg = [[StashNativeCardConfig alloc] init];
    XCTAssertFalse(cfg.forcePortrait);
    XCTAssertEqualWithAccuracy(cfg.cardHeightRatioPortrait, 0.68, 0.001);
    XCTAssertEqualWithAccuracy(cfg.cardWidthRatioLandscape, 0.7, 0.01);
    XCTAssertEqualWithAccuracy(cfg.cardHeightRatioLandscape, 0.9, 0.01);
    XCTAssertEqualWithAccuracy(cfg.tabletWidthRatioPortrait, 0.4, 0.01);
    XCTAssertEqualWithAccuracy(cfg.tabletHeightRatioPortrait, 0.5, 0.01);
    XCTAssertEqualWithAccuracy(cfg.tabletWidthRatioLandscape, 0.3, 0.01);
    XCTAssertEqualWithAccuracy(cfg.tabletHeightRatioLandscape, 0.6, 0.01);
    XCTAssertTrue(cfg.autoClose);
    XCTAssertNil(cfg.backgroundColor);
}

- (void)testModalConfigDefaults {
    StashNativeModalConfig *cfg = [[StashNativeModalConfig alloc] init];
    XCTAssertTrue(cfg.allowDismiss);
    XCTAssertTrue(cfg.autoClose);
    XCTAssertEqualWithAccuracy(cfg.phoneWidthRatioPortrait, 0.80, 0.001);
    XCTAssertEqualWithAccuracy(cfg.phoneHeightRatioPortrait, 0.50, 0.001);
    XCTAssertEqualWithAccuracy(cfg.phoneWidthRatioLandscape, 0.50, 0.001);
    XCTAssertEqualWithAccuracy(cfg.phoneHeightRatioLandscape, 0.80, 0.001);
    XCTAssertEqualWithAccuracy(cfg.tabletWidthRatioPortrait, 0.40, 0.001);
    XCTAssertEqualWithAccuracy(cfg.tabletHeightRatioPortrait, 0.30, 0.001);
    XCTAssertEqualWithAccuracy(cfg.tabletWidthRatioLandscape, 0.30, 0.001);
    XCTAssertEqualWithAccuracy(cfg.tabletHeightRatioLandscape, 0.40, 0.001);
    XCTAssertNil(cfg.backgroundColor);
}

- (void)testModalConfigCustomInit {
    StashNativeModalConfig *cfg = [[StashNativeModalConfig alloc] initWithPhoneWidthPortrait:0.5
                                                                          phoneHeightPortrait:0.6
                                                                          phoneWidthLandscape:0.7
                                                                         phoneHeightLandscape:0.8
                                                                          tabletWidthPortrait:0.3
                                                                         tabletHeightPortrait:0.4
                                                                         tabletWidthLandscape:0.2
                                                                        tabletHeightLandscape:0.9
                                                                                 allowDismiss:NO];
    XCTAssertFalse(cfg.allowDismiss);
    XCTAssertTrue(cfg.autoClose);
    XCTAssertEqualWithAccuracy(cfg.phoneWidthRatioPortrait, 0.5, 0.001);
    XCTAssertEqualWithAccuracy(cfg.tabletHeightRatioLandscape, 0.9, 0.001);
}

- (void)testInitialStateNotPresentedNotProcessing {
    StashNativeCard *card = [StashNativeCard sharedInstance];
    XCTAssertFalse(card.isCurrentlyPresented);
    XCTAssertFalse(card.isPurchaseProcessing);
    XCTAssertEqual(StashNativeDesktop_IsCurrentlyPresented(), 0);
    XCTAssertEqual(StashNativeDesktop_IsPurchaseProcessing(), 0);
}

- (void)testEmptyUrlsDoNotCrashOrPresent {
    StashNativeCard *card = [StashNativeCard sharedInstance];
    [card openCardWithURL:@"" config:nil];
    [card openModalWithURL:@"" config:nil];
    [card openBrowserWithURL:@""];
    StashNativeDesktop_OpenCard("", "{}");
    StashNativeDesktop_OpenModal(nullptr, nullptr);
    StashNativeDesktop_OpenBrowser(nullptr);
    XCTAssertFalse(card.isCurrentlyPresented);
}

- (void)testResetAndDismissWithoutPresentationAreSafe {
    StashNativeCard *card = [StashNativeCard sharedInstance];
    [card dismiss];
    [card resetPresentationState];
    StashNativeDesktop_Dismiss();
    StashNativeDesktop_ResetPresentationState();
    XCTAssertFalse(card.isCurrentlyPresented);
}

- (void)testInspectableFlagRoundTrip {
    [StashNativeCard setInspectableWebViewsEnabled:YES];
    XCTAssertTrue([StashNativeCard isInspectableWebViewsEnabled]);
    StashNativeDesktop_SetInspectableWebViewsEnabled(0);
    XCTAssertFalse([StashNativeCard isInspectableWebViewsEnabled]);
}

- (void)testWebKitScriptUsesMessageHandlers {
    std::string script = STASH_SDK_SCRIPT_WEBKIT;
    XCTAssertTrue(script.find("window.webkit.messageHandlers[n].postMessage(d)") != std::string::npos);
    XCTAssertTrue(script.find("window.stash_sdk.openLink") != std::string::npos);
}

// An attached presentation ends with its host window; a later open must not be refused.
- (void)testHostWindowCloseEndsAttachedPresentation {
    [NSApplication sharedApplication];
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 900, 700)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.releasedWhenClosed = NO;
    StashNativeCard *card = [StashNativeCard sharedInstance];
    card.hostWindow = window;
    [card openCardWithURL:@"data:text/html,<p>stash</p>" config:nil];
    XCTAssertTrue(card.isCurrentlyPresented);

    [window close];
    XCTAssertFalse(card.isCurrentlyPresented);

    NSWindow *second = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 900, 700)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    second.releasedWhenClosed = NO;
    card.hostWindow = second;
    [card openCardWithURL:@"data:text/html,<p>again</p>" config:nil];
    XCTAssertTrue(card.isCurrentlyPresented);
    [card resetPresentationState];
    XCTAssertFalse(card.isCurrentlyPresented);
    card.hostWindow = nil;
    [second close];
}

// A WebKit string message with U+0000 inside goes through the core as bytes and reaches the
// ABI callback as U+FFFD followed by the rest, not truncated at the NUL.
- (void)testEmbeddedNulInStringMessageReachesCallbackAsReplacementCharacter {
    [NSApplication sharedApplication];
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 900, 700)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.releasedWhenClosed = NO;
    StashNativeCard *card = [StashNativeCard sharedInstance];
    card.hostWindow = window;
    gLastEventType.clear();
    gLastEventPayload.clear();
    StashNativeDesktop_SetEventCallback(RecordEvent, nullptr);
    [card openCardWithURL:@"data:text/html,<p>stash</p>" config:nil];
    XCTAssertTrue(card.isCurrentlyPresented);

    StashDesktopCore *core = [StashDesktopCore sharedInstance];
    NSString *body = [NSString stringWithFormat:@"order%C1", (unichar)0];
    XCTAssertEqual(body.length, (NSUInteger)7);
    [core handleMessageNamed:@STASH_SDK_MSG_PAYMENT_SUCCESS body:body fromWebView:core.liveWebView];
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];

    XCTAssertEqual(gLastEventType, std::string(STASH_NATIVE_DESKTOP_EVENT_PAYMENT_SUCCESS));
    XCTAssertEqual(gLastEventPayload, std::string("order\xEF\xBF\xBD" "1"));
    XCTAssertFalse(card.isCurrentlyPresented);

    StashNativeDesktop_SetEventCallback(nullptr, nullptr);
    [card resetPresentationState];
    card.hostWindow = nil;
    [window close];
}

// Off the main thread, SetEventCallback and Shutdown each return only after the main queue
// applied them. For each call a marker block is queued on the main queue first, while the main
// thread is deliberately not running its loop; the call must not return before that marker ran,
// which an asynchronous dispatch would.
- (void)testOffMainCallbackAndShutdownAreSynchronousBarriers {
    auto marker1 = std::make_shared<std::atomic<bool>>(false);
    auto marker2 = std::make_shared<std::atomic<bool>>(false);
    auto sawMarkerOnSet = std::make_shared<std::atomic<bool>>(false);
    auto sawMarkerOnShutdown = std::make_shared<std::atomic<bool>>(false);
    auto phase2 = std::make_shared<std::atomic<bool>>(false);
    auto mainPaused = std::make_shared<std::atomic<bool>>(false);
    auto done = std::make_shared<std::atomic<bool>>(false);
    dispatch_async(dispatch_get_main_queue(), ^{
        marker1->store(true);
    });
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        StashNativeDesktop_SetEventCallback(RecordEvent, nullptr);
        sawMarkerOnSet->store(marker1->load());
        phase2->store(true);
        while (!mainPaused->load()) {
            usleep(1000);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            marker2->store(true);
        });
        StashNativeDesktop_Shutdown();
        sawMarkerOnShutdown->store(marker2->load());
        done->store(true);
    });
    usleep(200000);
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!phase2->load() && [deadline timeIntervalSinceNow] > 0) {
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    mainPaused->store(true);
    usleep(200000);
    while (!done->load() && [deadline timeIntervalSinceNow] > 0) {
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    XCTAssertTrue(done->load());
    XCTAssertTrue(sawMarkerOnSet->load());
    XCTAssertTrue(sawMarkerOnShutdown->load());
    StashNativeDesktop_SetEventCallback(nullptr, nullptr);
}

// Opening right after prewarm: the placeholder's queued completion must not consume the
// one-shot pageLoaded. Exactly one pageLoaded, after the checkout's navigation event.
- (void)testPrewarmThenImmediateOpenReportsOnePageLoaded {
    [NSApplication sharedApplication];
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 900, 700)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.releasedWhenClosed = NO;
    StashNativeCard *card = [StashNativeCard sharedInstance];
    card.hostWindow = window;
    gEventTypes.clear();
    StashNativeDesktop_SetEventCallback(RecordEvent, nullptr);
    [card prewarm];
    [card openCardWithURL:@"data:text/html,<p>stash</p>" config:nil];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while ([deadline timeIntervalSinceNow] > 0) {
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        if (std::count(gEventTypes.begin(), gEventTypes.end(), std::string(STASH_NATIVE_DESKTOP_EVENT_PAGE_LOADED)) > 0 &&
            [deadline timeIntervalSinceNow] < 2.2) {
            break;
        }
    }
    size_t loaded = std::count(gEventTypes.begin(), gEventTypes.end(), std::string(STASH_NATIVE_DESKTOP_EVENT_PAGE_LOADED));
    XCTAssertEqual(loaded, (size_t)1);
    XCTAssertFalse(gEventTypes.empty());
    XCTAssertEqual(gEventTypes.front(), std::string(STASH_NATIVE_DESKTOP_EVENT_NAVIGATION));
    XCTAssertTrue(card.isCurrentlyPresented);
    StashNativeDesktop_SetEventCallback(nullptr, nullptr);
    [card resetPresentationState];
    card.hostWindow = nil;
    [window close];
}

- (void)testShutdownClearsState {
    StashNativeCard *card = [StashNativeCard sharedInstance];
    [card prewarm];
    [card shutdown];
    StashNativeDesktop_Prewarm();
    StashNativeDesktop_Shutdown();
    XCTAssertFalse(card.isCurrentlyPresented);
}

@end
