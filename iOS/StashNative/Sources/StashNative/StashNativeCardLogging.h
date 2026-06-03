//
//  StashNativeCardLogging.h
//  StashNative
//
//  Internal debug logging. STASH_DEBUG_LOG forwards to NSLog in DEBUG builds and expands to
//  nothing in release builds.
//

#import <Foundation/Foundation.h>

#ifndef STASH_DEBUG_LOG
#ifdef DEBUG
#define STASH_DEBUG_LOG(...) NSLog(__VA_ARGS__)
#else
#define STASH_DEBUG_LOG(...)
#endif
#endif
