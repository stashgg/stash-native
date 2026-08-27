//
//  StashNativeDesktopTests.mm
//  StashNativeDesktopTests
//
//  Facade and ABI checks that need the macOS host (the shared contract has its own C++ tests).
//

#import <XCTest/XCTest.h>
#import "StashNativeCard.h"

#include <string>

#include "StashDesktopConfig.h"
#include "StashNativeDesktop.h"
#include "StashSdkScript.h"

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

- (void)testShutdownClearsState {
    StashNativeCard *card = [StashNativeCard sharedInstance];
    [card prewarm];
    [card shutdown];
    StashNativeDesktop_Prewarm();
    StashNativeDesktop_Shutdown();
    XCTAssertFalse(card.isCurrentlyPresented);
}

@end
