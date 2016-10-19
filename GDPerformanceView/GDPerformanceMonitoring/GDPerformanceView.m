//
// Copyright © 2016 Gavrilov Daniil
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
//

#import "GDPerformanceView.h"

#import <mach/mach.h>
#import <QuartzCore/QuartzCore.h>

@interface GDPerformanceView ()

@property (nonatomic, strong) CADisplayLink *displayLink;

@property (nonatomic, strong) UILabel *monitoringTextLabel;

@property (nonatomic) CGFloat lastFPSUsageValue;
@property (nonatomic) CFTimeInterval displayLinkLastTimestamp;
@property (nonatomic) CFTimeInterval lastUpdateTimestamp;

@end

@implementation GDPerformanceView

#pragma mark -
#pragma mark - Init Methods & Superclass Overriders

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupWindowAndDefaultVariables];
        [self setupDisplayLink];
        [self setupTextLayers];
        [self subscribeToNotifications];
    }
    return self;
}

- (void)becomeKeyWindow {
    [self setHidden:YES];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (1.0f * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self setHidden:NO];
    });
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return YES;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark -
#pragma mark - Notifications & Observers

- (void)applicationWillChangeStatusBarFrameNotification:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        CGRect statusBarFrame = [[UIApplication sharedApplication] statusBarFrame];
        [self setFrame:CGRectMake(0.0f, 0.0f, CGRectGetWidth(statusBarFrame), CGRectGetHeight(statusBarFrame))];
        [self layoutTextLabel];
    });
}

- (void)layoutTextLabel {
    CGFloat labelWidth = CGRectGetWidth(self.monitoringTextLabel.bounds);
    CGFloat labelHeight = CGRectGetHeight(self.monitoringTextLabel.bounds);
    CGFloat windowWidth = CGRectGetWidth(self.bounds);
    CGFloat windowHeight = CGRectGetHeight(self.bounds);
    
    [self.monitoringTextLabel setFrame:CGRectMake((windowWidth - labelWidth) / 2.0f, (windowHeight - labelHeight) / 2.0f, labelWidth, labelHeight)];
}

#pragma mark -
#pragma mark - Public Methods

- (UILabel *)textLabel {
    __weak UILabel *weakTextLabel = self.monitoringTextLabel;
    return weakTextLabel;
}

- (void)pauseMonitoring {
    [self.displayLink setPaused:YES];
}

- (void)resumeMonitoring {
    [self.displayLink setPaused:NO];
}

- (void)stopMonitoring {
    [self.displayLink invalidate];
    self.displayLink = nil;
}

#pragma mark -
#pragma mark - Private Methods

#pragma mark - Default Setups

- (void)setupWindowAndDefaultVariables {
    self.lastFPSUsageValue = 0.0f;
    self.displayLinkLastTimestamp = 0.0f;
    self.lastUpdateTimestamp = 0.0f;
    
    UIViewController *rootViewController = [[UIViewController alloc] init];
    [rootViewController.view setBackgroundColor:[UIColor clearColor]];
    
    [self setRootViewController:rootViewController];
    [self setWindowLevel:(UIWindowLevelStatusBar + 1.0f)];
    [self setBackgroundColor:[UIColor clearColor]];
    [self setHidden:NO];
}

- (void)setupDisplayLink {
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(displayLinkAction:)];
    [self.displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)setupTextLayers {
    self.monitoringTextLabel = [[UILabel alloc] init];
    [self.monitoringTextLabel setBackgroundColor:[UIColor whiteColor]];
    [self.monitoringTextLabel setTextColor:[UIColor blackColor]];
    [self.monitoringTextLabel setClipsToBounds:YES];
    [self.monitoringTextLabel setFont:[UIFont systemFontOfSize:8.0f]];
    [self.monitoringTextLabel.layer setBorderWidth:1.0f];
    [self.monitoringTextLabel.layer setBorderColor:[[UIColor blackColor] CGColor]];
    [self.monitoringTextLabel.layer setCornerRadius:5.0f];
    [self addSubview:self.monitoringTextLabel];
}

- (void)subscribeToNotifications {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillChangeStatusBarFrameNotification:) name:UIApplicationWillChangeStatusBarFrameNotification object:nil];
}

#pragma mark - Monitoring

- (void)displayLinkAction:(CADisplayLink *)displayLink {
    CGFloat fps;
    if (self.lastFPSUsageValue == 0) {
        fps = roundf(1.0f / (displayLink.timestamp - self.displayLinkLastTimestamp));
    } else {
        fps = (self.lastFPSUsageValue + roundf(1.0f / (displayLink.timestamp - self.displayLinkLastTimestamp))) / 2.0f;
    }
    
    self.lastFPSUsageValue = fps;
    self.displayLinkLastTimestamp = displayLink.timestamp;
    
    CFTimeInterval timestampSinceLastUpdate = self.displayLinkLastTimestamp - self.lastUpdateTimestamp;
    if (timestampSinceLastUpdate >= 1.0f) {
        self.lastFPSUsageValue = 0.0f;
        self.lastUpdateTimestamp = self.displayLinkLastTimestamp;
        
        CGFloat cpu = [self cpuUsage];
        CGFloat ram = [self ramUsage];
        
        [self updateMonitoringLabelWithFPS:fps CPU:cpu RAM:ram];
    }
}

- (CGFloat)cpuUsage {
    kern_return_t kern;
    task_info_data_t taskInfo;
    mach_msg_type_number_t taskInfoCount;
    
    taskInfoCount = TASK_BASIC_INFO_COUNT;
    kern = task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)taskInfo, &taskInfoCount);
    if (kern != KERN_SUCCESS) {
        return -1;
    }
    
    task_basic_info_t taskBasicInfo;
    thread_array_t threadList;
    mach_msg_type_number_t threadCount;
    
    thread_info_data_t threadInfo;
    mach_msg_type_number_t threadInfoCount;
    
    thread_basic_info_t threadBasicInfo;
    uint32_t threadStatistic = 0;
    
    taskBasicInfo = (task_basic_info_t)taskInfo;
    
    kern = task_threads(mach_task_self(), &threadList, &threadCount);
    if (kern != KERN_SUCCESS) {
        return -1;
    }
    if (threadCount > 0) {
        threadStatistic += threadCount;
    }
    
    float totalUsageOfCPU = 0;
    
    for (int i = 0; i < threadCount; i++) {
        threadInfoCount = THREAD_INFO_MAX;
        kern = thread_info(threadList[i], THREAD_BASIC_INFO, (thread_info_t)threadInfo, &threadInfoCount);
        if (kern != KERN_SUCCESS) {
            return -1;
        }
        
        threadBasicInfo = (thread_basic_info_t)threadInfo;
        
        if (!(threadBasicInfo -> flags & TH_FLAGS_IDLE)) {
            totalUsageOfCPU = totalUsageOfCPU + threadBasicInfo -> cpu_usage / (float)TH_USAGE_SCALE * 100.0f;
        }
    }
    
    kern = vm_deallocate(mach_task_self(), (vm_offset_t)threadList, threadCount * sizeof(thread_t));
    
    return totalUsageOfCPU;
}

- (CGFloat)ramUsage {
    kern_return_t kern;
    task_info_data_t taskInfo;
    mach_msg_type_number_t taskInfoCount;
    
    taskInfoCount = TASK_BASIC_INFO_COUNT;
    kern = task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&taskInfo, &taskInfoCount);
    if (kern != KERN_SUCCESS) {
        return -1;
    }
    
    task_basic_info_t taskBasicInfo = (task_basic_info_t)taskInfo;
    
    CGFloat megabytesUsed = (float)(taskBasicInfo -> resident_size) / 1000000.0f;
    
    return megabytesUsed;
} 

#pragma mark - Other Methods

- (void)updateMonitoringLabelWithFPS:(CGFloat)fpsUsage CPU:(CGFloat)cpuUsage RAM:(CGFloat)ramUsage {
    [self.monitoringTextLabel setText:[NSString stringWithFormat:@"  FPS : %.1f, CPU : %.1f%%, RAM : %.1f MiB  ", fpsUsage, cpuUsage, ramUsage]];
    [self.monitoringTextLabel sizeToFit];
    [self layoutTextLabel];
}

@end