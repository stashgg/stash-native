//
//  StashNativeCardLogging.h
//  StashNative
//
//  Internal debug logging. STASH_DEBUG_LOG forwards to NSLog in DEBUG builds and compiles to
//  nothing in release, so the shipped SDK emits no logs. Shared by all SDK translation units; the
//  #ifndef guard keeps it safe if a unit also defines it.
//

#import <Foundation/Foundation.h>

#ifndef STASH_DEBUG_LOG
#ifdef DEBUG
#define STASH_DEBUG_LOG(...) NSLog(__VA_ARGS__)
#else
#define STASH_DEBUG_LOG(...)
#endif
#endif
