// MPAFNetworkActivityIndicatorManager.m
// Copyright (c) 2011–2015 Alamofire Software Foundation (http://alamofire.org/)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "MPAFNetworkActivityIndicatorManager.h"

#if defined(__IPHONE_OS_VERSION_MAX_ALLOWED)

#import "MPAFHTTPRequestOperation.h"

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 70000
#import "MPAFURLSessionManager.h"
#endif

static NSTimeInterval const MPkAFNetworkActivityIndicatorInvisibilityDelay = 0.17;

static NSURLRequest * mp_AFNetworkRequestFromNotification(NSNotification *notification) {
    if ([[notification object] isKindOfClass:[MPAFURLConnectionOperation class]]) {
        return [(MPAFURLConnectionOperation *)[notification object] request];
    }

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 70000
    if ([[notification object] respondsToSelector:@selector(originalRequest)]) {
        return [(NSURLSessionTask *)[notification object] originalRequest];
    }
#endif

    return nil;
}

@interface MPAFNetworkActivityIndicatorManager ()
@property (readwrite, nonatomic, assign) NSInteger activityCount;
@property (readwrite, nonatomic, strong) NSTimer *activityIndicatorVisibilityTimer;
@property (readonly, nonatomic, getter = isNetworkActivityIndicatorVisible) BOOL networkActivityIndicatorVisible;

- (void)updateNetworkActivityIndicatorVisibility;
- (void)updateNetworkActivityIndicatorVisibilityDelayed;
@end

@implementation MPAFNetworkActivityIndicatorManager
@dynamic networkActivityIndicatorVisible;

+ (instancetype)sharedManager {
    static MPAFNetworkActivityIndicatorManager *_sharedManager = nil;
    static dispatch_once_t oncePredicate;
    dispatch_once(&oncePredicate, ^{
        _sharedManager = [[self alloc] init];
    });

    return _sharedManager;
}

+ (NSSet *)keyPathsForValuesAffectingIsNetworkActivityIndicatorVisible {
    return [NSSet setWithObject:@"activityCount"];
}

- (id)init {
    self = [super init];
    if (!self) {
        return nil;
    }

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(networkRequestDidStart:) name:MPAFNetworkingOperationDidStartNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(networkRequestDidFinish:) name:MPAFNetworkingOperationDidFinishNotification object:nil];

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 70000
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(networkRequestDidStart:) name:MPAFNetworkingTaskDidResumeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(networkRequestDidFinish:) name:MPAFNetworkingTaskDidSuspendNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(networkRequestDidFinish:) name:MPAFNetworkingTaskDidCompleteNotification object:nil];
#endif

    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    [_activityIndicatorVisibilityTimer invalidate];
}

- (void)updateNetworkActivityIndicatorVisibilityDelayed {
    if (self.enabled) {
        // Delay hiding of activity indicator for a short interval, to avoid flickering
        if (![self isNetworkActivityIndicatorVisible]) {
            [self.activityIndicatorVisibilityTimer invalidate];
            self.activityIndicatorVisibilityTimer = [NSTimer timerWithTimeInterval:MPkAFNetworkActivityIndicatorInvisibilityDelay target:self selector:@selector(updateNetworkActivityIndicatorVisibility) userInfo:nil repeats:NO];
            [[NSRunLoop mainRunLoop] addTimer:self.activityIndicatorVisibilityTimer forMode:NSRunLoopCommonModes];
        } else {
            [self performSelectorOnMainThread:@selector(updateNetworkActivityIndicatorVisibility) withObject:nil waitUntilDone:NO modes:@[NSRunLoopCommonModes]];
        }
    }
}

- (BOOL)isNetworkActivityIndicatorVisible {
    return self.activityCount > 0;
}

- (void)updateNetworkActivityIndicatorVisibility {
#if !defined(AF_APP_EXTENSIONS)
    [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:[self isNetworkActivityIndicatorVisible]];
#endif
}

- (void)setActivityCount:(NSInteger)activityCount {
	@synchronized(self) {
		_activityCount = activityCount;
	}

    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateNetworkActivityIndicatorVisibilityDelayed];
    });
}

- (void)incrementActivityCount {
    [self willChangeValueForKey:@"activityCount"];
	@synchronized(self) {
		_activityCount++;
	}
    [self didChangeValueForKey:@"activityCount"];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateNetworkActivityIndicatorVisibilityDelayed];
    });
}

- (void)decrementActivityCount {
    [self willChangeValueForKey:@"activityCount"];
	@synchronized(self) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wgnu"
		_activityCount = MAX(_activityCount - 1, 0);
#pragma clang diagnostic pop
	}
    [self didChangeValueForKey:@"activityCount"];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateNetworkActivityIndicatorVisibilityDelayed];
    });
}

- (void)networkRequestDidStart:(NSNotification *)notification {
    if ([mp_AFNetworkRequestFromNotification(notification) URL]) {
        [self incrementActivityCount];
    }
}

- (void)networkRequestDidFinish:(NSNotification *)notification {
    if ([mp_AFNetworkRequestFromNotification(notification) URL]) {
        [self decrementActivityCount];
    }
}

@end

#endif
